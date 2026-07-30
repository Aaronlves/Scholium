import Foundation
import ScholiumContracts
import ScholiumCore

struct ValidatedFunctionObject: Sendable {
    let noteID: UUID
    let note: WorkspaceNoteSnapshot
}

enum StoredFunctionRecord: Sendable {
    case local(LocalResearchExecutionRecord)

    private var localRecord: LocalResearchExecutionRecord {
        switch self {
        case .local(let record): record
        }
    }

    var snapshot: ResearchFunctionSnapshot {
        localRecord.snapshot
    }

    var completion: ResearchFunctionCompletion? {
        localRecord.completion
    }

    var preparedInstructions: String? {
        localRecord.preparedInstructions
    }

    var discussionExecution: ResearchDiscussionExecutionContract? {
        localRecord.discussion
    }
}

/// Stable authorities used by one Workspace's protected execution lifecycle.
/// This is intentionally narrower than the Workspace-wide service aggregate:
/// the coordinator cannot reach search, permission, recovery-policy, or window
/// state through this bundle.
struct ResearchFunctionCoordinatorDependencies: Sendable {
    let repositories: [UUID: VaultRepository]
    let vaults: [UUID: RegisteredVault]
    let roots: TriptychRoots
    let controlStore: TriptychControlStore
    let researchSkillStore: ResearchSkillTransactionCoordinator
    let sourceAccessStore: ResearchSourceAccessStore
    let agentNoteChangeRequestStore: AgentNoteChangeRequestStore
    let portableResearchRecordStore: PortableResearchRecordStore
    let localExecutionStore: LocalResearchExecutionStore
    let critiqueRegistry: CritiqueRegistry
    let checkpointStore: TriptychCheckpointStore
    let zotero: ZoteroOperations
}

/// The narrow Workspace boundary required by protected-run execution.
///
/// The coordinator borrows this actor's existing isolation. The host retains
/// the sole ownership of process-local activity keys, Discussion storage, and
/// disposable snapshot publication; none of those authorities are copied into
/// the coordinator.
protocol ResearchFunctionCoordinatorHost: Actor {
    var id: UUID { get }

    func requireActive() throws
    func researchFunctionCurrentSnapshot() -> WorkspaceSnapshot
    func researchActivityKey(runID: UUID) -> String?
    func setResearchActivityKey(_ key: String?, runID: UUID)
    func agentCoordinationKey(runID: UUID) -> String?
    func setAgentCoordinationKey(_ key: String?, runID: UUID)
    func resolveDefaultResearchActionContext(
        for request: ResearchFunctionRequest
    ) async throws -> ResolvedResearchActionContext
    func clearResearchActivityKey(runID: UUID)
    func clearAgentCoordinationKey(runID: UUID)
    func prepareResearchFunctionCritique(
        for workID: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint,
        scope: CritiqueRequestScope,
        selectedRanges: String,
        additionalInstructions: String,
        roundID: UUID,
        functionSnapshotBuilder: @escaping (ResearchFunctionOutputSnapshot) -> ResearchFunctionSnapshot,
        skillInstructionsOverride: @escaping (ResearchFunctionOutputSnapshot) throws -> String
    ) async throws -> CritiquePreparation
    func finishDiscussion(discussionID: UUID) async throws -> PortableResearchRecord
    func publishCommittedResearchFunctionChange(
        _ operation: String
    ) async throws -> String?
    func scheduleResearchFunctionRefreshRecovery()
}

/// One per-workspace owner for protected Research Function preparation,
/// delivery, run records, and terminal lifecycle transitions.
///
/// This component owns availability, immutable preparation and delivery,
/// Local-v2 lookup/reconciliation, completion persistence, cancellation, and
/// protected Discussion Finish. It does not own Markdown, Workspace snapshots,
/// source-operation exclusion, Discussion storage, or refresh publication. Its
/// methods execute on the existing Workspace actor through an `isolated` host,
/// so this extraction adds no actor or actor hop.
final class ResearchFunctionCoordinator: Sendable {
    let workspaceID: UUID

    let dependencies: ResearchFunctionCoordinatorDependencies

    private var localExecutionStore: LocalResearchExecutionStore {
        dependencies.localExecutionStore
    }

    private var critiqueRegistry: CritiqueRegistry {
        dependencies.critiqueRegistry
    }

    init(
        workspaceID: UUID,
        dependencies: ResearchFunctionCoordinatorDependencies
    ) {
        self.workspaceID = workspaceID
        self.dependencies = dependencies
    }

    func record(runID: UUID) async throws -> StoredFunctionRecord {
        guard let local = try await localExecutionStore.recordIfPresent(id: runID) else {
            throw ResearchFunctionContractError.preparationNotFound(runID)
        }
        if let critique = try await critiqueRegistry.functionRecord(runID: runID),
           local.snapshot == critique.snapshot,
           local.completion == critique.completion,
           local.preparedInstructions == critique.preparedInstructions {
            _ = try await critiqueRegistry.detachFunctionEvidence(
                runID: runID,
                matching: local.snapshot
            )
        }
        return .local(local)
    }

    func persistCompletion(
        _ completion: ResearchFunctionCompletion,
        in stored: StoredFunctionRecord,
        submissionDigest: String? = nil
    ) async throws {
        _ = stored
        _ = try await localExecutionStore.setCompletion(
            completion,
            submissionDigest: submissionDigest,
            runID: completion.runID
        )
    }

    func researchContinuationCheckpointKey(
        for target: ResearchFunctionTarget
    ) -> TriptychCheckpointFileKey {
        let area: TriptychCheckpointArea = switch target.role {
        case .analysis: .analyses
        case .topic: .topics
        case .work: .works
        }
        return TriptychCheckpointFileKey(
            area: area,
            relativePath: target.note.relativePath
        )
    }

    func cancelProtectedFunction<Host: ResearchFunctionCoordinatorHost>(
        runID: UUID,
        host: isolated Host
    ) async throws {
        try requireMatchingActiveHost(host)
        let stored = try await record(runID: runID)
        try await cancel(runID: runID, stored: stored, host: host)
    }

    func cancelAction<Host: ResearchFunctionCoordinatorHost>(
        runID: UUID,
        host: isolated Host
    ) async throws {
        try requireMatchingActiveHost(host)
        let stored = try await record(runID: runID)
        guard stored.snapshot.actionSnapshot != nil else {
            throw ResearchActionExecutionContractError.staleResolution
        }
        try await cancel(runID: runID, stored: stored, host: host)
    }

    /// Finish is a record transition, not acceptance of the agent's response
    /// and not a claim that the Discussion reached a true result.
    func finishProtectedDiscussion<Host: ResearchFunctionCoordinatorHost>(
        runID: UUID,
        host: isolated Host
    ) async throws -> PortableResearchRecord {
        try requireMatchingActiveHost(host)
        let stored = try await record(runID: runID)
        guard stored.snapshot.request.function == .discuss else {
            throw ResearchFunctionContractError.invalidCompletion(
                "Only a current portable Discussion can be finished."
            )
        }
        return try await host.finishDiscussion(discussionID: runID)
    }

    private func cancel<Host: ResearchFunctionCoordinatorHost>(
        runID: UUID,
        stored: StoredFunctionRecord,
        host: isolated Host
    ) async throws {
        if let existing = stored.completion {
            if existing.state == .cancelled {
                host.clearAgentCoordinationKey(runID: runID)
                return
            }
            // Awaiting-Fidelity and Unverified are already durable completion
            // evidence for substantive work. Cancellation must not overwrite
            // that evidence any more than it may overwrite a complete run.
            throw ResearchFunctionContractError.cancellationAfterCompletion(runID)
        }
        let snapshot = stored.snapshot
        if let activityID = snapshot.activityID {
            _ = try? await localExecutionStore.transitionGrant(
                activityID: activityID,
                to: .cancelled
            )
            host.clearResearchActivityKey(runID: runID)
        }
        let completion = ResearchFunctionCompletion(
            runID: runID,
            function: snapshot.request.function,
            state: .cancelled,
            targetFingerprint: snapshot.request.target.fingerprint,
            materialFingerprints: Dictionary(
                uniqueKeysWithValues: snapshot.request.materials.map {
                    ($0.noteID, $0.fingerprint)
                }
            ),
            summary: "Cancelled",
            didModifyTarget: false,
            fidelityOutcomes: []
        )
        try await persistCompletion(completion, in: stored)
        host.clearAgentCoordinationKey(runID: runID)
        _ = try await host.publishCommittedResearchFunctionChange(
            "The Research Action cancellation"
        )
    }

    func requireMatchingActiveHost<Host: ResearchFunctionCoordinatorHost>(
        _ host: isolated Host
    ) throws {
        precondition(host.id == workspaceID)
        try host.requireActive()
    }
}

extension WorkspaceHandle: ResearchFunctionCoordinatorHost {
    func researchFunctionCurrentSnapshot() -> WorkspaceSnapshot {
        currentSnapshot
    }

    func researchActivityKey(runID: UUID) -> String? {
        activeResearchActivityKeys[runID]
    }

    func setResearchActivityKey(_ key: String?, runID: UUID) {
        activeResearchActivityKeys[runID] = key
    }

    func agentCoordinationKey(runID: UUID) -> String? {
        activeAgentCoordinationKeys[runID]
    }

    func setAgentCoordinationKey(_ key: String?, runID: UUID) {
        activeAgentCoordinationKeys[runID] = key
    }

    func resolveDefaultResearchActionContext(
        for request: ResearchFunctionRequest
    ) async throws -> ResolvedResearchActionContext {
        try await resolvedDefaultActionContext(for: request)
    }

    func clearResearchActivityKey(runID: UUID) {
        activeResearchActivityKeys[runID] = nil
    }

    func clearAgentCoordinationKey(runID: UUID) {
        activeAgentCoordinationKeys[runID] = nil
    }

    func prepareResearchFunctionCritique(
        for workID: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint,
        scope: CritiqueRequestScope,
        selectedRanges: String,
        additionalInstructions: String,
        roundID: UUID,
        functionSnapshotBuilder: @escaping (ResearchFunctionOutputSnapshot) -> ResearchFunctionSnapshot,
        skillInstructionsOverride: @escaping (ResearchFunctionOutputSnapshot) throws -> String
    ) async throws -> CritiquePreparation {
        try await requestCritique(
            for: workID,
            expectedRevision: expectedRevision,
            scope: scope,
            lens: "",
            selectedRanges: selectedRanges,
            additionalInstructions: additionalInstructions,
            roundID: roundID,
            functionSnapshotBuilder: functionSnapshotBuilder,
            skillInstructionsOverride: skillInstructionsOverride
        )
    }

    func publishCommittedResearchFunctionChange(
        _ operation: String
    ) async throws -> String? {
        do {
            try await refreshAfterCommittedOperation(
                operation,
                publication: .researchRecords
            )
            return nil
        } catch let error as ScholiumApplicationError
            where error.durableMutationWasCommitted {
            scheduleResearchFunctionRefreshRecovery()
            return error.localizedDescription
        }
    }

    func scheduleResearchFunctionRefreshRecovery() {
        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.refresh(
                publication: .researchRecords,
                failureDisposition: .failed(affectedVaultIDs: [])
            )
        }
    }
}
