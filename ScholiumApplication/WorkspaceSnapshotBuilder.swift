import ScholiumContracts
import Foundation
import ScholiumCore

struct WorkspaceRefreshMeasurement: Sendable {
    let workspaceGeneration: UInt64
    let enumeratedFiles: Int
    let readFiles: Int
    let parsedDocuments: Int
    let projectedDocuments: Int
    let enumerationDuration: Duration
    let readDuration: Duration
    let parseDuration: Duration
    let projectionDuration: Duration
    let identityProjectionDuration: Duration
    let graphDuration: Duration
    let researchStateDuration: Duration
    let searchDocumentProjectionDuration: Duration
    let searchDuration: Duration
    let snapshotAssemblyDuration: Duration
    let totalDuration: Duration
    let snapshotSourceBytes: Int
}

struct WorkspaceSnapshotBuildResult: Sendable {
    let snapshot: WorkspaceSnapshot
    let measurement: WorkspaceRefreshMeasurement
}

enum WorkspaceSnapshotBuilder {
    private struct LoadedVault: Sendable {
        let slot: WorkspaceVaultSlot
        let vault: RegisteredVault
        let folders: [VaultRelativeFolderPath]
        let fileMetadata: [String: WorkspaceFileMetadata]
        let allDocuments: [NoteDocument]
        let activeDocuments: [NoteDocument]
        let semantics: [String: MarkdownSemanticDocument]
        let searchProjections: [String: SearchDocumentProjection]
        let identityStates: [String: WorkspaceNoteIdentityState]
        let identityRecovery: NoteIdentityRecoveryState
        let identityHealthIssues: [String]
    }

    private struct SourceInput: Sendable {
        let order: Int
        let slot: WorkspaceVaultSlot
        let vault: RegisteredVault
        let repository: VaultRepository
        let catalog: VaultSourceCatalog
    }

    private struct LoadedSource: Sendable {
        let input: SourceInput
        let snapshot: VaultSourceCatalogSnapshot
    }

    static func build(
        assignment: TriptychAssignment,
        mode: WorkspaceConfigurationMode,
        services: WorkspaceServices,
        graphGeneration: Int,
        workspaceGeneration: UInt64
    ) async throws -> WorkspaceSnapshotBuildResult {
        let clock = ContinuousClock()
        let totalStart = clock.now
        try Task.checkCancellation()

        var loadedVaults: [LoadedVault] = []
        var semanticDocuments: [VaultQualifiedNoteID: MarkdownSemanticDocument] = [:]
        var linkCatalog: [LinkCatalogNote] = []
        var sourceMeasurements: [VaultSourceCatalogMeasurement] = []
        var identityProjectionDuration = Duration.zero

        var sourceInputs: [SourceInput] = []
        for (order, slot) in WorkspaceVaultSlot.allCases.enumerated() {
            try Task.checkCancellation()
            guard let vault = assignment.vault(for: slot),
                  let repository = services.repositories[vault.id],
                  let sourceCatalog = services.sourceCatalogs[vault.id] else {
                throw ScholiumApplicationError.incompleteTriptych(assignment.id)
            }
            let rootURL = await repository.vaultURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: rootURL.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue else {
                throw WorkspaceFileEventWatcherError.rootUnavailable(rootURL.path)
            }
            sourceInputs.append(SourceInput(
                order: order,
                slot: slot,
                vault: vault,
                repository: repository,
                catalog: sourceCatalog
            ))
        }

        let loadedSources = try await withThrowingTaskGroup(
            of: LoadedSource.self
        ) { group in
            for input in sourceInputs {
                group.addTask {
                    try Task.checkCancellation()
                    // Each catalog is an independent rebuildable projection.
                    // The refresh coordinator still owns one atomic cycle;
                    // only preparation of the three immutable generations
                    // overlaps.
                    return LoadedSource(
                        input: input,
                        snapshot: try await input.catalog.snapshot(
                            refreshFolders: false,
                            consumePendingMeasurement: true
                        )
                    )
                }
            }
            var loaded: [LoadedSource] = []
            for try await source in group {
                loaded.append(source)
            }
            return loaded.sorted { $0.input.order < $1.input.order }
        }

        for loadedSource in loadedSources {
            try Task.checkCancellation()
            let slot = loadedSource.input.slot
            let vault = loadedSource.input.vault
            let repository = loadedSource.input.repository
            // The refresh coordinator has already reconciled or applied the
            // exact event delta. Do not repeat directory enumeration while
            // assembling this immutable generation.
            let sourceSnapshot = loadedSource.snapshot
            sourceMeasurements.append(sourceSnapshot.measurement)
            let allDocuments = sourceSnapshot.documents
            let activeDocuments = allDocuments.filter {
                WorkspaceDocumentLifecycle(relativePath: $0.relativePath) == .active
            }
            let semantics = sourceSnapshot.semantics
            for document in activeDocuments {
                try Task.checkCancellation()
                guard let semantic = semantics[document.relativePath] else {
                    throw ScholiumApplicationError.incompleteTriptych(assignment.id)
                }
                let id = VaultQualifiedNoteID(
                    vaultID: vault.id,
                    relativePath: document.relativePath
                )
                semanticDocuments[id] = semantic
                linkCatalog.append(
                    LinkCatalogNote(
                        vaultID: vault.id,
                        document: document,
                        profile: WorkflowProfileResolver.resolve(
                            vaultRole: vault.role,
                            frontmatter: document.parsedFrontmatter,
                            relativePath: document.relativePath
                        ),
                        semantic: semantic
                    )
                )
            }
            let identityProjectionStart = clock.now
            var identityStates = Dictionary(
                uniqueKeysWithValues: allDocuments.map {
                    ($0.relativePath, WorkspaceNoteIdentityState.unresolved)
                }
            )
            var identityHealthIssues: [String] = []
            var identityRecovery = NoteIdentityRecoveryState(
                identities: [:],
                ambiguities: [],
                pendingRebindings: [],
                failures: []
            )
            do {
                let recovery = try await services.identityRecoveryCoordinator.reconcile(
                    vaultID: vault.id,
                    documents: allDocuments.map { ($0.relativePath, $0.fingerprint) },
                    repository: repository,
                    migrateCritiquePaths: slot == .output
                )
                identityRecovery = recovery
                for (path, record) in recovery.identities {
                    identityStates[path] = .resolved(record.id)
                }
                for ambiguity in recovery.ambiguities {
                    identityStates[ambiguity.relativePath] = .ambiguous(
                        candidateIDs: ambiguity.candidates.map(\.id).sorted {
                            $0.uuidString < $1.uuidString
                        }
                    )
                }
                for pending in recovery.pendingRebindings {
                    identityStates[pending.relativePath] = .pending(pending.noteID)
                }
                identityHealthIssues.append(contentsOf: recovery.failures.map(\.message))
            } catch {
                identityHealthIssues.append(
                    "Portable note identity for \(vault.name): \(error.localizedDescription)"
                )
            }
            loadedVaults.append(
                LoadedVault(
                    slot: slot,
                    vault: vault,
                    folders: sourceSnapshot.folders,
                    fileMetadata: sourceSnapshot.fileMetadata,
                    allDocuments: allDocuments,
                    activeDocuments: activeDocuments,
                    semantics: semantics,
                    searchProjections: sourceSnapshot.searchProjections,
                    identityStates: identityStates,
                    identityRecovery: identityRecovery,
                    identityHealthIssues: identityHealthIssues
                )
            )
            identityProjectionDuration += identityProjectionStart.duration(
                to: clock.now
            )
        }

        let sourceManifestHash = SearchSourceManifest.hash(
            loadedVaults.flatMap { loaded in
                loaded.activeDocuments.map {
                    SearchSourceManifestEntry(
                        vaultID: loaded.vault.id,
                        relativePath: $0.relativePath,
                        fingerprint: $0.fingerprint
                    )
                }
            }
        )
        let graph: GraphSnapshot?
        let graphBuildIssue: String?
        let graphStart = clock.now
        do {
            graph = try LinkGraphBuilder.buildCancellable(
                generation: graphGeneration,
                catalog: linkCatalog,
                documents: semanticDocuments,
                resolutionScope: .workspace,
                sourceManifestHash: sourceManifestHash
            )
            graphBuildIssue = nil
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Search is an independent projection of the same source
            // snapshot. A graph failure must not prevent a complete lexical
            // generation from replacing its predecessor.
            graph = nil
            graphBuildIssue = "Relationship graph: \(error.localizedDescription)"
        }
        let graphDuration = graphStart.duration(to: clock.now)
        let brokenNoteIDs = Set((graph?.diagnostics ?? []).compactMap { diagnostic in
            diagnostic.code == .broken ? diagnostic.source : nil
        })

        let researchStateStart = clock.now
        let portableSettlementListing = try await services
            .portableResearchRecordStore.settlementListing()
        let settlements = portableSettlementListing.settlements
        let localExecutionListing = try await services.localResearchExecutionStore
            .listing()
        let finishedResearchRecordListing = try await services
            .portableResearchRecordStore.listing(location: .records)
        var activeDiscussionListing = try await services
            .portableResearchRecordStore.activeDiscussions()
        var activeDiscussionReconciliationIssues: [String] = []
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
                        triptychID: assignment.id
                    )
                    if let active = activeDiscussionListing.discussions.first(where: {
                        $0.id == local.id
                    }) {
                        guard ResearchDiscussionFactory.activeMatches(
                            active,
                            expected: expected
                        ) else {
                            throw ResearchFunctionContractError.invalidCompletion(
                                "The active Discussion does not match its Local-v2 run."
                            )
                        }
                    } else if let finished = finishedByID[local.id] {
                        guard ResearchDiscussionFactory.finishedMatches(
                            finished,
                            expected: expected
                        ) else {
                            throw ResearchFunctionContractError.invalidCompletion(
                                "The finished Discussion does not match its Local-v2 run."
                            )
                        }
                    } else if local.completion == nil,
                              !activeDiscussionListing.discussions.contains(where: {
                                  $0.primaryNoteID == expected.primaryNoteID
                              }) {
                        _ = try await services.portableResearchRecordStore
                            .createActiveDiscussion(expected)
                    } else {
                        throw ResearchFunctionContractError.invalidCompletion(
                            "The Local-v2 Discuss run has no exact portable Discussion pair."
                        )
                    }
                } catch {
                    activeDiscussionReconciliationIssues.append(
                        "Discussion \(local.id.uuidString): \(error.localizedDescription)"
                    )
                }
            }
        }
        activeDiscussionListing = try await services.portableResearchRecordStore
            .activeDiscussions()
        for discussion in activeDiscussionListing.issues.isEmpty
            ? activeDiscussionListing.discussions
            : [] {
            guard let loaded = loadedVaults.first(where: { vault in
                vault.identityStates.values.contains(.resolved(discussion.primaryNoteID))
            }), let relativePath = loaded.identityStates.first(where: {
                $0.value == .resolved(discussion.primaryNoteID)
            })?.key, let document = loaded.activeDocuments.first(where: {
                $0.relativePath == relativePath
            }) else { continue }
            do {
                _ = try await services.portableResearchRecordStore
                    .reconcileDiscussionPassages(
                        id: discussion.id,
                        primaryDocument: document
                    )
            } catch {
                activeDiscussionReconciliationIssues.append(
                    "Discussion \(discussion.id.uuidString): \(error.localizedDescription)"
                )
            }
        }
        activeDiscussionListing = try await services.portableResearchRecordStore
            .activeDiscussions()
        let activityGrants = await services.researchActivityStore.grants()
        let latestSettlementByNoteID = Dictionary(
            settlements.map { ($0.noteID, $0) },
            uniquingKeysWith: { lhs, rhs in
                lhs.settledAt >= rhs.settledAt ? lhs : rhs
            }
        )
        let researchStateDuration = researchStateStart.duration(to: clock.now)
        let searchDocumentProjectionStart = clock.now
        var searchDocuments: [SearchIndexDocument] = []

        for loaded in loadedVaults {
            try Task.checkCancellation()
            searchDocuments.append(contentsOf: try loaded.activeDocuments.map { document in
                let id = VaultQualifiedNoteID(
                    vaultID: loaded.vault.id,
                    relativePath: document.relativePath
                )
                guard let semantic = loaded.semantics[document.relativePath],
                      let cachedSourceProjection = loaded.searchProjections[
                          document.relativePath
                      ] else {
                    throw ScholiumApplicationError.incompleteTriptych(
                        assignment.id
                    )
                }
                return SearchIndexDocument(
                    vaultID: loaded.vault.id,
                    vaultName: loaded.vault.name,
                    vaultRole: loaded.vault.role,
                    document: document,
                    semantic: semantic,
                    cachedSourceProjection: cachedSourceProjection,
                    hasBrokenLink: brokenNoteIDs.contains(id)
                )
            })
        }
        let searchDocumentProjectionDuration = searchDocumentProjectionStart.duration(
            to: clock.now
        )
        let searchStart = clock.now
        let searchPublication = try await services.searchIndex.synchronize(
            searchDocuments,
            workspaceGeneration: workspaceGeneration
        )
        let searchDuration = searchStart.duration(to: clock.now)
        guard searchPublication.generation.sourceManifestHash == sourceManifestHash else {
            throw SearchIndexError.invalidDocuments(
                "Search and Graph were derived from different source manifests"
            )
        }

        let assemblyStart = clock.now
        let documentsByVault = Dictionary(
            uniqueKeysWithValues: loadedVaults.map {
                ($0.vault.id, $0.activeDocuments)
            }
        )
        var settlementStates: [String: WorkspaceSettlementState] = [:]
        var changedSinceSettledStates: [PendingResearchState] = []
        for loaded in loadedVaults {
            for document in loaded.activeDocuments {
                guard case .resolved(let noteID) = loaded.identityStates[document.relativePath],
                      let settlement = latestSettlementByNoteID[noteID] else { continue }
                let referenceID = "\(loaded.vault.id.uuidString):\(document.relativePath)"
                let changedSinceSettled = settlement.fingerprint != document.fingerprint
                settlementStates[referenceID] = WorkspaceSettlementState(
                    settledFingerprint: settlement.fingerprint,
                    changedSinceSettled: changedSinceSettled
                )
                if changedSinceSettled {
                    changedSinceSettledStates.append(PendingResearchState(
                        id: settlement.id,
                        noteID: noteID,
                        kind: .changedSinceSettled,
                        createdAt: settlement.settledAt,
                        fingerprint: document.fingerprint
                    ))
                }
            }
        }
        let loadedVaultsByID = Dictionary(
            uniqueKeysWithValues: loadedVaults.map { ($0.vault.id, $0) }
        )
        let attributionAttention = activityGrants.flatMap { grant -> [AttentionQueueItem] in
            guard let report = grant.completionReport else { return [] }
            return report.unreportedChangedNotes.compactMap { changed in
                guard let loaded = loadedVaultsByID[changed.note.vaultID],
                      loaded.activeDocuments.contains(where: {
                          $0.relativePath == changed.note.relativePath
                      }),
                      case .resolved(let currentID) = loaded.identityStates[
                          changed.note.relativePath
                      ],
                      currentID == changed.noteID else { return nil }
                return AttentionQueueItem(
                    kind: .changeAttributionNeeded,
                    severity: .warning,
                    note: VaultNoteReference(
                        vaultID: loaded.vault.id,
                        vaultName: loaded.vault.name,
                        vaultRole: loaded.vault.role,
                        relativePath: changed.note.relativePath
                    ),
                    message: "This note changed inside a frozen Write scope but was not included in the agent's completion report. Review its attribution before treating it as part of the activity from \(grant.origin.title)."
                )
            }
        }
        let catalog = WorkspaceCatalogBuilder.build(
            vaults: loadedVaults.map(\.vault),
            documents: documentsByVault,
            semanticDocuments: semanticDocuments,
            settlementStates: settlementStates,
            additionalAttention: attributionAttention,
            graph: graph
        )

        var healthIssues: [String] = []
        healthIssues.append(contentsOf: loadedVaults.flatMap(\.identityHealthIssues))
        if let graphBuildIssue { healthIssues.append(graphBuildIssue) }
        if let issue = await services.researchActivityStore.healthError() {
            healthIssues.append(issue)
        }
        healthIssues.append(contentsOf: portableSettlementListing.issues.map {
            "Portable Settlement \($0.fileName): \($0.reason)"
        })
        healthIssues.append(contentsOf: activeDiscussionListing.issues.map {
            "Active Discussion \($0.fileName): \($0.reason)"
        })
        healthIssues.append(contentsOf: activeDiscussionReconciliationIssues)
        healthIssues.append(contentsOf: finishedResearchRecordListing.issues.map {
            "Portable Research Record \($0.fileName): \($0.reason)"
        })
        if let issue = await services.critiqueRegistry.healthError() {
            healthIssues.append(issue)
        }
        let recoveryRecords: [TriptychMutationRecoveryRecord]
        do {
            recoveryRecords = try await services.transactionRecoveryStore.pending()
        } catch {
            recoveryRecords = []
            healthIssues.append(
                "Durable transaction recovery: \(error.localizedDescription)"
            )
        }
        for loaded in loadedVaults {
            if let repository = services.repositories[loaded.vault.id],
               let issue = await repository.recoveryLedgerHealthDiagnostic() {
                healthIssues.append("\(loaded.vault.name): \(issue)")
            }
        }

        var critiquesByID: [UUID: CritiqueAssociation] = [:]
        if let output = loadedVaults.first(where: { $0.slot == .output }) {
            for document in output.activeDocuments {
                if let association = await services.critiqueRegistry.association(
                    critiqueRelativePath: document.relativePath
                ) {
                    critiquesByID[association.id] = association
                }
                if case .resolved(let noteID) = output.identityStates[
                    document.relativePath
                ], let association = await services.critiqueRegistry.association(
                    workNoteID: noteID
                ) {
                    critiquesByID[association.id] = association
                }
            }
        }

        let vaultSnapshots = try loadedVaults.map { loaded in
            WorkspaceVaultSnapshot(
                slot: loaded.slot,
                vault: loaded.vault,
                documents: try loaded.allDocuments.map { document in
                    let id = VaultQualifiedNoteID(
                        vaultID: loaded.vault.id,
                        relativePath: document.relativePath
                    )
                    guard let fileMetadata = loaded.fileMetadata[
                        document.relativePath
                    ] else {
                        throw ScholiumApplicationError.incompleteTriptych(
                            assignment.id
                        )
                    }
                    let diagnostics = (graph?.diagnostics ?? []).filter { $0.source == id }
                    return WorkspaceNoteSnapshot(
                        id: id,
                        vaultRole: loaded.vault.role,
                        stableIdentity: loaded.identityStates[document.relativePath] ?? .unresolved,
                        document: document,
                        fileMetadata: fileMetadata,
                        lifecycle: WorkspaceDocumentLifecycle(
                            relativePath: document.relativePath
                        ),
                        graphCounts: WorkspaceGraphCounts(
                            incoming: graph?.incoming[id]?.count ?? 0,
                            outgoing: graph?.outgoing[id]?.count ?? 0,
                            broken: diagnostics.count { $0.code == .broken },
                            ambiguous: diagnostics.count {
                                $0.code == .ambiguous || $0.code == .ambiguousHeading
                            }
                        ),
                        cachedTitleProjection: loaded.semantics[
                            document.relativePath
                        ].map {
                            WorkspaceNoteTitleProjection(
                                document: document,
                                vaultRole: loaded.vault.role,
                                semantic: $0
                            )
                        }
                    )
                },
                folders: loaded.folders,
                identityRecovery: loaded.identityRecovery
            )
        }
        healthIssues.append(contentsOf: localExecutionListing.issues.map {
            "Local Research Execution \($0.fileName): \($0.reason)"
        })
        var critiqueAssociations = critiquesByID.values.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        let retainedCritiqueFunctionRuns = critiqueAssociations.flatMap { association in
                association.rounds.compactMap { round in
                    round.functionSnapshot.map {
                        ResearchFunctionRecordProjection(
                            snapshot: $0,
                            completion: round.functionCompletion,
                            preparedInstructions: round.functionInstructions
                        )
                    }
                }
            }
        var localFunctionRuns = localExecutionListing.records.map { record in
            ResearchFunctionRecordProjection(
                snapshot: record.snapshot,
                completion: record.completion,
                preparedInstructions: record.preparedInstructions
            )
        }
        var localRunIDs = Set(localFunctionRuns.map(\.id))
        let unhealthyLocalFileNames = Set(localExecutionListing.issues.map(\.fileName))
        let stagedCritiqueRounds = critiqueAssociations.flatMap { association in
            association.rounds.compactMap { round in
                round.functionSnapshot.map { (association, round, $0) }
            }
        }
        for (association, round, snapshot) in stagedCritiqueRounds {
            guard !localRunIDs.contains(round.id) else { continue }
            let localFileName = round.id.uuidString.lowercased() + ".json"
            guard !unhealthyLocalFileNames.contains(localFileName) else {
                healthIssues.append(
                    "Critique handoff \(round.id.uuidString) has unreadable Local Execution v2 evidence; its portable staging evidence was preserved."
                )
                continue
            }
            guard snapshot.actionSnapshot?.actionID == .critique,
                  snapshot.request.function == .critique,
                  snapshot.runID == round.id,
                  snapshot.recordKind == .critique,
                  snapshot.recordID == round.id,
                  snapshot.checkpointID == round.checkpointID,
                  snapshot.request.target.noteID == association.workNoteID,
                  snapshot.request.target.fingerprint == round.targetFingerprint,
                  snapshot.actionSnapshot?.target.noteID == association.workNoteID,
                  snapshot.actionSnapshot?.target.note == snapshot.request.target.note,
                  snapshot.actionSnapshot?.target.fingerprint
                    == round.targetFingerprint,
                  snapshot.preparedOutput?.note.vaultID
                    == snapshot.request.target.note.vaultID,
                  snapshot.preparedOutput?.note.relativePath
                    == association.critiqueRelativePath,
                  snapshot.preparedOutput?.fingerprint != nil,
                  round.functionCompletion == nil,
                  round.actionableFindings.isEmpty,
                  !round.localExecutionFindingsCaptured,
                  round.findingDispositions.isEmpty,
                  round.completedAt == nil,
                  let preparedInstructions = round.functionInstructions else {
                healthIssues.append(
                    "Critique handoff \(round.id.uuidString) has inconsistent portable staging evidence; it was preserved without creating Local Execution v2."
                )
                continue
            }
            do {
                guard try await services.localResearchExecutionStore
                    .hasMatchingCritiqueHandoff(
                        snapshot: snapshot,
                        preparedInstructions: preparedInstructions
                    ) else {
                    healthIssues.append(
                        "Critique handoff \(round.id.uuidString) has no matching machine-local intent; its portable staging evidence was preserved."
                    )
                    continue
                }
                if let checkpointID = snapshot.checkpointID {
                    let checkpoint = try await services.checkpointStore.checkpoint(
                        id: checkpointID
                    )
                    guard checkpoint.kind == .automatic else {
                        throw ResearchFunctionContractError.invalidCompletion(
                            "The legacy Critique staging checkpoint is not automatic."
                        )
                    }
                }
                let recovered = try LocalResearchExecutionRecord(
                    triptychID: services.manifest.id,
                    snapshot: snapshot,
                    preparedInstructions: preparedInstructions
                )
                let stored = try await services.localResearchExecutionStore
                    .create(recovered)
                localFunctionRuns.append(ResearchFunctionRecordProjection(
                    snapshot: stored.snapshot,
                    completion: stored.completion,
                    preparedInstructions: stored.preparedInstructions
                ))
                localRunIDs.insert(stored.id)
                do {
                    try await services.localResearchExecutionStore
                        .discardCritiqueHandoff(
                            snapshot: snapshot,
                            preparedInstructions: preparedInstructions
                        )
                } catch {
                    healthIssues.append(
                        "Critique handoff \(round.id.uuidString) was installed, but its machine-local intent could not be discarded: \(error.localizedDescription)"
                    )
                }
            } catch {
                healthIssues.append(
                    "Critique handoff \(round.id.uuidString) could not be installed in Local Execution v2; its portable staging evidence was preserved: \(error.localizedDescription)"
                )
            }
        }
        for local in localFunctionRuns {
            let duplicates = retainedCritiqueFunctionRuns.filter { $0.id == local.id }
            guard !duplicates.isEmpty else { continue }
            let isExactCritiqueHandoff = duplicates.count == 1
                && duplicates[0].snapshot == local.snapshot
                && duplicates[0].completion == local.completion
                && duplicates[0].preparedInstructions == local.preparedInstructions
                && critiqueAssociations.contains { association in
                    association.rounds.contains {
                        $0.functionSnapshot?.runID == local.id
                    }
                }
            if isExactCritiqueHandoff {
                do {
                    let updated = try await services.critiqueRegistry.detachFunctionEvidence(
                        runID: local.id,
                        matching: local.snapshot
                    )
                    if let index = critiqueAssociations.firstIndex(where: {
                        $0.id == updated.id
                    }) {
                        critiqueAssociations[index] = updated
                    }
                } catch {
                    healthIssues.append(
                        "Critique handoff \(local.id.uuidString): \(error.localizedDescription)"
                    )
                }
            } else {
                healthIssues.append(
                    "Research execution \(local.id.uuidString) has conflicting retained evidence; Local Execution v2 was projected read-only."
                )
            }
        }
        critiqueAssociations.sort {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        // Retained Critique Function evidence remains reveal-only. Current
        // planning and projection publish only Local Execution v2 records.
        let storedFunctionRuns = localFunctionRuns.sorted {
            if $0.snapshot.preparedAt != $1.snapshot.preparedAt {
                return $0.snapshot.preparedAt > $1.snapshot.preparedAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        let currentByStableID: [UUID: DocumentFingerprint] = Dictionary(
            vaultSnapshots.flatMap(\.documents).compactMap { note in
                guard case .resolved(let stableID) = note.stableIdentity else { return nil }
                return (stableID, note.fingerprint)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let currentByLocation: [VaultQualifiedNoteID: DocumentFingerprint] = Dictionary(
            uniqueKeysWithValues: vaultSnapshots.flatMap(\.documents).map {
                ($0.id, $0.fingerprint)
            }
        )
        let functionRuns = storedFunctionRuns.map { run in
            guard let completion = run.completion,
                  completion.state != .cancelled,
                  completion.state != .stale else { return run }
            let targetIsCurrent = currentByStableID[run.snapshot.request.target.noteID]
                == completion.targetFingerprint
            let materialsAreCurrent = run.snapshot.request.materials.allSatisfy { material in
                currentByStableID[material.noteID]
                    == completion.materialFingerprints[material.noteID]
            }
            let outputIsCurrent: Bool
            if let preparedOutput = run.snapshot.preparedOutput {
                outputIsCurrent = currentByLocation[preparedOutput.note]
                    == completion.outputFingerprint
            } else {
                outputIsCurrent = completion.outputFingerprint == nil
            }
            let currentEvidence: [DocumentFingerprint]? = run.snapshot.request.commentIDs.isEmpty
                ? []
                : nil
            let preparedEvidence = run.snapshot.evidenceRevisions.sorted { lhs, rhs in
                if lhs.sha256 != rhs.sha256 { return lhs.sha256 < rhs.sha256 }
                return lhs.byteCount < rhs.byteCount
            }
            guard targetIsCurrent,
                  materialsAreCurrent,
                  outputIsCurrent,
                  currentEvidence == preparedEvidence else {
                return ResearchFunctionRecordProjection(
                    snapshot: run.snapshot,
                    completion: ResearchFunctionCompletion(
                        runID: completion.runID,
                        function: completion.function,
                        state: .stale,
                        targetFingerprint: completion.targetFingerprint,
                        materialFingerprints: completion.materialFingerprints,
                        summary: completion.summary,
                        didModifyTarget: completion.didModifyTarget,
                        outputFingerprint: completion.outputFingerprint,
                        fidelityOutcomes: completion.fidelityOutcomes,
                        fidelityTargetResults: completion.fidelityTargetResults ?? [],
                        fidelityEvidenceKey: completion.fidelityEvidenceKey,
                        reusedFidelityRunID: completion.reusedFidelityRunID,
                        childRunIDs: completion.childRunIDs ?? [],
                        completedAt: completion.completedAt,
                        derivedRefreshWarning: completion.derivedRefreshWarning
                    ),
                    preparedInstructions: run.preparedInstructions
                )
            }
            return run
        }
        let research = WorkspaceResearchSnapshot(
            activityEvents: await services.researchActivityStore.allEvents(),
            settlements: settlements,
            activeDiscussions: activeDiscussionListing.issues.isEmpty
                ? activeDiscussionListing.discussions
                : [],
            finishedResearchRecords: finishedResearchRecordListing.records,
            pendingResearchStates: changedSinceSettledStates.sorted {
                    if $0.createdAt != $1.createdAt {
                        return $0.createdAt > $1.createdAt
                    }
                    return $0.id.uuidString < $1.id.uuidString
                },
            activityGrants: activityGrants,
            critiques: critiqueAssociations,
            functionRuns: functionRuns,
            checkpointListing: await services.checkpointStore.listing(),
            recoveryRecords: recoveryRecords,
            healthIssues: Array(Set(healthIssues)).sorted()
        )
        let snapshot = WorkspaceSnapshot(
            triptych: assignment.triptych,
            mode: mode,
            generatedAt: Date(),
            vaults: vaultSnapshots,
            discovery: WorkspaceDiscoverySnapshot(
                catalog: catalog,
                searchGeneration: searchPublication.generation
            ),
            research: research
        )
        let assemblyDuration = assemblyStart.duration(to: clock.now)
        return WorkspaceSnapshotBuildResult(
            snapshot: snapshot,
            measurement: WorkspaceRefreshMeasurement(
                workspaceGeneration: workspaceGeneration,
                enumeratedFiles: sourceMeasurements.reduce(0) {
                    $0 + $1.enumeratedFiles
                },
                readFiles: sourceMeasurements.reduce(0) { $0 + $1.readFiles },
                parsedDocuments: sourceMeasurements.reduce(0) {
                    $0 + $1.parsedDocuments
                },
                projectedDocuments: sourceMeasurements.reduce(0) {
                    $0 + $1.projectedDocuments
                },
                enumerationDuration: sourceMeasurements.reduce(.zero) {
                    $0 + $1.enumerationDuration
                },
                readDuration: sourceMeasurements.reduce(.zero) {
                    $0 + $1.readDuration
                },
                parseDuration: sourceMeasurements.reduce(.zero) {
                    $0 + $1.parseDuration
                },
                projectionDuration: sourceMeasurements.reduce(.zero) {
                    $0 + $1.projectionDuration
                },
                identityProjectionDuration: identityProjectionDuration,
                graphDuration: graphDuration,
                researchStateDuration: researchStateDuration,
                searchDocumentProjectionDuration:
                    searchDocumentProjectionDuration,
                searchDuration: searchDuration,
                snapshotAssemblyDuration: assemblyDuration,
                totalDuration: totalStart.duration(to: clock.now),
                snapshotSourceBytes: snapshot.vaults
                    .flatMap(\.documents)
                    .reduce(0) { $0 + $1.document.sourceBytes.count }
            )
        )
    }

}
