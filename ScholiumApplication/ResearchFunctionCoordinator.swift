import Foundation
import ScholiumContracts
import ScholiumCore

struct ValidatedFunctionObject: Sendable {
    let noteID: UUID
    let note: WorkspaceNoteSnapshot
}

/// Stable authorities used by one Workspace's protected execution lifecycle.
/// This is intentionally narrower than the Workspace-wide service aggregate:
/// the coordinator cannot reach search, permission, recovery-policy, or window
/// state through this bundle.
struct ResearchFunctionCoordinatorDependencies: Sendable {
    let repositories: [UUID: VaultRepository]
    let vaults: [UUID: RegisteredVault]
    let controlStore: TriptychControlStore
    let researchConfigurationStore: ResearchConfigurationStore
    let sourceAccessStore: ResearchSourceAccessStore
    let portableResearchRecordStore: PortableResearchRecordStore
    let localExecutionStore: LocalResearchExecutionStore
    let agentChangeEvidenceStore: AgentChangeEvidenceStore
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
    func researchFunctionControlledFingerprint(
        for target: ResearchFunctionTarget
    ) async throws -> DocumentFingerprint
    func resolveDefaultResearchActionContext(
        for request: ResearchFunctionRequest
    ) async throws -> ResolvedResearchActionContext
    func revokeResearchAgentRunAccess(runID: UUID) async
    func finalizeResearchAgentRunAccess(runID: UUID) async
    func finishDiscussion(discussionID: UUID) async throws -> PortableResearchRecord
    func publishCommittedResearchFunctionChange(
        _ operation: String
    ) async throws -> String?
    func hasPendingResearchWriteRecovery(
        runID: UUID,
        writes: [ResearchDocumentWriteRecord]
    ) async throws -> Bool
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

    func record(runID: UUID) async throws -> LocalResearchExecutionRecord {
        guard let local = try await localExecutionStore.recordIfPresent(id: runID) else {
            throw ResearchFunctionContractError.preparationNotFound(runID)
        }
        return local
    }

    func persistCompletion(
        _ completion: ResearchFunctionCompletion,
        in stored: LocalResearchExecutionRecord,
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
        in stored: LocalResearchExecutionRecord
    ) async throws {
        guard payload.runID == stored.snapshot.runID else {
            throw ResearchAgentResultContractError.invalidSubmission
        }
        _ = try await localExecutionStore.stageResultPayload(payload)
    }

    func captureAgentChangeStartingRevision(
        runID: UUID,
        target: ResearchFunctionTarget
    ) async throws -> AgentChangeEvidence {
        guard let repository = dependencies.repositories[target.note.vaultID] else {
            throw ResearchFunctionContractError.targetUnavailable
        }
        let document = try await repository.load(
            relativePath: target.note.relativePath
        )
        guard document.fingerprint == target.fingerprint else {
            throw VaultRepositoryError.conflict(
                expected: target.fingerprint,
                current: document.fingerprint
            )
        }
        return try await dependencies.agentChangeEvidenceStore
            .captureStartingRevision(
                runID: runID,
                noteID: target.noteID,
                data: document.sourceBytes,
                expectedRevision: target.fingerprint
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
        stored: LocalResearchExecutionRecord,
        host: isolated Host
    ) async throws {
        if let existing = stored.completion {
            if existing.state == .cancelled {
                await host.revokeResearchAgentRunAccess(runID: runID)
                if stored.snapshot.request.function == .discuss {
                    _ = try await host.finishDiscussion(discussionID: runID)
                }
                return
            }
            // Any existing completion is already durable evidence for this
            // Run. Cancellation must not overwrite that terminal transition.
            throw ResearchFunctionContractError.cancellationAfterCompletion(runID)
        }
        let hasPendingWriteRecovery = try await host.hasPendingResearchWriteRecovery(
            runID: runID,
            writes: stored.documentWriteRecords
        )
        guard !stored.documentWriteRecords.contains(where: {
            [.writing, .recoveryRequired].contains($0.state)
        }), !stored.zoteroBindingWriteRecords.contains(where: {
            [.writing, .recoveryRequired].contains($0.state)
        }), !hasPendingWriteRecovery else {
            throw ResearchFunctionContractError.unresolvedWriteRecovery(runID)
        }
        guard !stored.documentWriteRecords.contains(where: {
            $0.state == .committed
        }), !stored.zoteroBindingWriteRecords.contains(where: {
            $0.state == .committed
        }) else {
            // A lightweight cancelled completion cannot carry the canonical
            // Result payload required by a portable Research Record. Refuse
            // the lossy terminal transition instead of orphaning confirmed
            // source or portable binding changes from their provenance.
            throw ResearchFunctionContractError.committedWritesRequireCompletion(
                runID
            )
        }
        let snapshot = stored.snapshot
        let completion = ResearchFunctionCompletion(
            runID: runID,
            function: snapshot.request.function,
            state: .cancelled,
            recordTitle: try ResearchRecordTitle("Cancelled"),
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
        if snapshot.request.function == .discuss {
            _ = try await host.finishDiscussion(discussionID: runID)
        }
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

    func researchFunctionControlledFingerprint(
        for target: ResearchFunctionTarget
    ) async throws -> DocumentFingerprint {
        let lease = try await beginResearchControlledSourceObservation()
        defer { endResearchControlledSourceObservation(lease) }
        guard ResearchFunctionTargetRole(
                vaultRole: try vault(id: target.note.vaultID).role
              ) == target.role,
              let identityBefore = try await services.controlStore.identityRecord(
                vaultID: target.note.vaultID,
                relativePath: target.note.relativePath
              ), identityBefore.id == target.noteID else {
            throw ResearchFunctionContractError.targetIdentityChanged
        }
        if let barrier = researchFunctionControlledObservationBarrierForTesting {
            await barrier()
        }
        let document = try await repository(vaultID: target.note.vaultID).load(
            relativePath: target.note.relativePath
        )
        guard let identityAfter = try await services.controlStore.identityRecord(
            vaultID: target.note.vaultID,
            relativePath: target.note.relativePath
        ), identityAfter.id == target.noteID else {
            throw ResearchFunctionContractError.targetIdentityChanged
        }
        return document.fingerprint
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

    func hasPendingResearchWriteRecovery(
        runID: UUID,
        writes: [ResearchDocumentWriteRecord]
    ) async throws -> Bool {
        let writeIDs = Set(writes.map(\.id))
        return try await services.transactionRecoveryStore.pending().contains {
            guard let link = $0.researchWrite, link.runID == runID else {
                return false
            }
            return writeIDs.contains(link.operationID)
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
