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

    var boundedWriteSet: ResearchBoundedWriteSet {
        localRecord.boundedWriteSet
    }

    var documentWriteRecords: [ResearchDocumentWriteRecord] {
        localRecord.documentWriteRecords
    }

    var writeConflictResolutionRecords: [ResearchWriteConflictResolutionRecord] {
        localRecord.writeConflictResolutionRecords
    }

    var writeReport: ResearchRunWriteReport? {
        localRecord.writeReport
    }

    var resultPayload: ResearchRunResultPayload? {
        localRecord.resultPayload
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
    let researchConfigurationStore: ResearchConfigurationStore
    let sourceAccessStore: ResearchSourceAccessStore
    let portableResearchRecordStore: PortableResearchRecordStore
    let localExecutionStore: LocalResearchExecutionStore
    let checkpointStore: TriptychCheckpointStore
    let zotero: ZoteroOperations
}

/// The narrow Workspace boundary required by protected-run execution.
///
/// The coordinator borrows this actor's existing isolation. The host retains
/// the sole ownership of Discussion storage and
/// disposable snapshot publication; none of those authorities are copied into
/// the coordinator.
protocol ResearchFunctionCoordinatorHost: Actor {
    var id: UUID { get }

    func requireActive() throws
    func researchFunctionCurrentSnapshot() -> WorkspaceSnapshot
    func resolveDefaultResearchActionContext(
        for request: ResearchFunctionRequest
    ) async throws -> ResolvedResearchActionContext
    func revokeResearchAgentRunAccess(runID: UUID) async
    func finalizeResearchAgentRunAccess(runID: UUID) async
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
/// current Local Execution lookup/reconciliation, completion persistence, cancellation, and
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
        return .local(local)
    }

    func persistCompletion(
        _ completion: ResearchFunctionCompletion,
        in stored: StoredFunctionRecord,
        resultPayload: ResearchRunResultPayload? = nil,
        writeReport: ResearchRunWriteReport? = nil,
        submissionDigest: String? = nil
    ) async throws {
        _ = stored
        _ = try await localExecutionStore.setCompletion(
            completion,
            resultPayload: resultPayload,
            writeReport: writeReport,
            submissionDigest: submissionDigest,
            runID: completion.runID
        )
    }

    func stageResultPayload(
        _ payload: ResearchRunResultPayload,
        in stored: StoredFunctionRecord
    ) async throws {
        guard payload.runID == stored.snapshot.runID else {
            throw ResearchAgentResultContractError.invalidSubmission
        }
        _ = try await localExecutionStore.stageResultPayload(payload)
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
        let record = try await host.finishDiscussion(discussionID: runID)
        await host.finalizeResearchAgentRunAccess(runID: runID)
        return record
    }

    private func cancel<Host: ResearchFunctionCoordinatorHost>(
        runID: UUID,
        stored: StoredFunctionRecord,
        host: isolated Host
    ) async throws {
        if let existing = stored.completion {
            if existing.state == .cancelled {
                await host.revokeResearchAgentRunAccess(runID: runID)
                return
            }
            // Awaiting-Fidelity and Unverified are already durable completion
            // evidence for substantive work. Cancellation must not overwrite
            // that evidence any more than it may overwrite a complete run.
            throw ResearchFunctionContractError.cancellationAfterCompletion(runID)
        }
        let snapshot = stored.snapshot
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
        await host.revokeResearchAgentRunAccess(runID: runID)
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

    func resolveDefaultResearchActionContext(
        for request: ResearchFunctionRequest
    ) async throws -> ResolvedResearchActionContext {
        try await resolvedDefaultActionContext(for: request)
    }

    func revokeResearchAgentRunAccess(runID: UUID) async {
        await services.researchAgentSessions?.revokeRun(runID)
    }

    func finalizeResearchAgentRunAccess(runID: UUID) async {
        await services.researchAgentSessions?.finalizeRun(runID)
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
