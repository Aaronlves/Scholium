import Foundation
import ScholiumContracts
import ScholiumCore

struct WorkspaceResearchStateRepair: Sendable {
    let activeDiscussionListing: PortableResearchDiscussionListing
    let issues: [String]
}

struct WorkspaceResearchStateReconcilerDependencies: Sendable {
    let portableResearchRecordStore: PortableResearchRecordStore
    let localResearchExecutionStore: LocalResearchExecutionStore
}

extension WorkspaceServices {
    var researchStateReconcilerDependencies:
        WorkspaceResearchStateReconcilerDependencies {
        WorkspaceResearchStateReconcilerDependencies(
            portableResearchRecordStore: portableResearchRecordStore,
            localResearchExecutionStore: localResearchExecutionStore
        )
    }
}

/// Repairs the durable Research Record pair only at the explicit refresh
/// boundary. Snapshot projection may read this state, but it must not create
/// or rewrite portable Discussion files as an incidental consequence of
/// building a derived generation.
enum WorkspaceResearchStateReconciler {
    static func repairBeforePublication(
        build: WorkspaceSnapshotBuildResult,
        triptychID: UUID,
        dependencies: WorkspaceResearchStateReconcilerDependencies
    ) async throws -> WorkspaceSnapshotBuildResult {
        guard build.snapshot.phase.isComplete else { return build }

        let clock = ContinuousClock()
        let start = clock.now
        let localExecutionListing = try await dependencies.localResearchExecutionStore
            .listing()
        let finishedResearchRecordListing = try await dependencies
            .portableResearchRecordStore.listing()
        var activeDiscussionListing = try await dependencies
            .portableResearchRecordStore.activeDiscussions()
        var issues: [String] = []
        let finishedByID = Dictionary(
            uniqueKeysWithValues: finishedResearchRecordListing.records.map { ($0.id, $0) }
        )

        if activeDiscussionListing.issues.isEmpty,
           finishedResearchRecordListing.issues.isEmpty {
            for local in localExecutionListing.records
                where local.snapshot.request.function == .discuss {
                do {
                    let expected = try ResearchDiscussionFactory.make(
                        snapshot: local.snapshot,
                        triptychID: triptychID
                    )
                    if let active = activeDiscussionListing.discussions.first(where: {
                        $0.id == local.id
                    }) {
                        guard ResearchDiscussionFactory.activeMatches(
                            active,
                            expected: expected
                        ) else {
                            throw ResearchFunctionContractError.invalidCompletion(
                                "The active Discussion does not match its current Run."
                            )
                        }
                    } else if let finished = finishedByID[local.id] {
                        guard ResearchDiscussionFactory.finishedMatches(
                            finished,
                            expected: expected
                        ) else {
                            throw ResearchFunctionContractError.invalidCompletion(
                                "The finished Discussion does not match its current Run."
                            )
                        }
                    } else if local.completion == nil,
                              !activeDiscussionListing.discussions.contains(where: {
                                  $0.primaryNoteID == expected.primaryNoteID
                              }) {
                        _ = try await dependencies.portableResearchRecordStore
                            .createActiveDiscussion(expected)
                    } else {
                        throw ResearchFunctionContractError.invalidCompletion(
                            "The current Discuss Run has no exact portable Discussion pair."
                        )
                    }
                } catch {
                    issues.append(
                        "Discussion \(local.id.uuidString): \(error.localizedDescription)"
                    )
                }
            }
        }

        activeDiscussionListing = try await dependencies.portableResearchRecordStore
            .activeDiscussions()
        for discussion in activeDiscussionListing.issues.isEmpty
            ? activeDiscussionListing.discussions
            : [] {
            guard let primaryDocument = build.snapshot.vaults
                .flatMap(\.documents)
                .first(where: {
                    $0.lifecycle == .active
                        && $0.stableIdentity.resolvedID == discussion.primaryNoteID
                }) else {
                continue
            }
            do {
                _ = try await dependencies.portableResearchRecordStore
                    .reconcileDiscussionPassages(
                        id: discussion.id,
                        primaryDocument: primaryDocument.document
                    )
            } catch {
                issues.append(
                    "Discussion \(discussion.id.uuidString): \(error.localizedDescription)"
                )
            }
        }
        activeDiscussionListing = try await dependencies.portableResearchRecordStore
            .activeDiscussions()

        let duration = start.duration(to: clock.now)
        let repairedSnapshot = applying(
            WorkspaceResearchStateRepair(
                activeDiscussionListing: activeDiscussionListing,
                issues: issues
            ),
            to: build.snapshot
        )
        return WorkspaceSnapshotBuildResult(
            snapshot: repairedSnapshot,
            measurement: build.measurement.addingResearchRepairDuration(duration)
        )
    }

    private static func applying(
        _ repair: WorkspaceResearchStateRepair,
        to snapshot: WorkspaceSnapshot
    ) -> WorkspaceSnapshot {
        var healthIssues = snapshot.research.healthIssues.filter {
            !$0.hasPrefix("Active Discussion ") && !$0.hasPrefix("Discussion ")
        }
        healthIssues.append(contentsOf: repair.activeDiscussionListing.issues.map {
            "Active Discussion \($0.fileName): \($0.reason)"
        })
        healthIssues.append(contentsOf: repair.issues)

        let research = snapshot.research
        let repairedResearch = WorkspaceResearchSnapshot(
            settlements: research.settlements,
            activeDiscussions: repair.activeDiscussionListing.issues.isEmpty
                ? repair.activeDiscussionListing.discussions
                : [],
            finishedResearchRecords: research.finishedResearchRecords,
            finishedResearchRecordFingerprints:
                research.finishedResearchRecordFingerprints,
            finishedResearchRecordSourceManifestHash:
                research.finishedResearchRecordSourceManifestHash,
            finishedResearchRecordProjectionIsComplete:
                research.finishedResearchRecordProjectionIsComplete,
            critiques: research.critiques,
            recoveryRecords: research.recoveryRecords,
            activities: research.activities,
            noteReviews: research.noteReviews,
            noteReviewStates: research.noteReviewStates,
            resultArrivals: research.resultArrivals,
            healthIssues: Array(Set(healthIssues)).sorted()
        )
        return WorkspaceSnapshot(
            triptych: snapshot.triptych,
            mode: snapshot.mode,
            phase: snapshot.phase,
            generatedAt: snapshot.generatedAt,
            vaults: snapshot.vaults,
            discovery: snapshot.discovery,
            research: repairedResearch
        )
    }
}

private extension WorkspaceRefreshMeasurement {
    func addingResearchRepairDuration(_ duration: Duration) -> Self {
        WorkspaceRefreshMeasurement(
            workspaceGeneration: workspaceGeneration,
            enumeratedFiles: enumeratedFiles,
            readFiles: readFiles,
            parsedDocuments: parsedDocuments,
            projectedDocuments: projectedDocuments,
            enumerationDuration: enumerationDuration,
            readDuration: readDuration,
            parseDuration: parseDuration,
            projectionDuration: projectionDuration,
            identityProjectionDuration: identityProjectionDuration,
            graphDuration: graphDuration,
            researchStateDuration: researchStateDuration + duration,
            searchDocumentProjectionDuration: searchDocumentProjectionDuration,
            searchDuration: searchDuration,
            snapshotAssemblyDuration: snapshotAssemblyDuration,
            totalDuration: totalDuration + duration,
            snapshotSourceBytes: snapshotSourceBytes
        )
    }
}
