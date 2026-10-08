import Foundation
import ScholiumContracts
import ScholiumCore

extension WorkspaceHandle {
    func startCitationControlObservation(
        watcher: WorkspaceFileEventWatcher, events: AsyncStream<VaultWatchEvent>
    ) {
        guard !isShutDown, citationControlWatcherTask == nil else { return }
        citationControlWatcher = watcher
        citationControlWatcherTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled, let self else { return }
                await self.receiveCitationControlEvent(event)
            }
            guard !Task.isCancelled, let self else { return }
            await self.receiveCitationControlEvent(
                .reconciliationRequired(sequence: 0, rootChanged: true))
        }
    }

    /// A companion event is an invalidation hint, not new document content.
    /// Coalescing behind the source gate also keeps our own incomplete pair
    /// from appearing as an external conflict in another retained session.
    func receiveCitationControlEvent(_ event: VaultWatchEvent) {
        guard !isShutDown else { return }
        citationControlInvalidationPending = true
        guard citationControlInvalidationTask == nil else { return }
        citationControlInvalidationTask = Task { [weak self] in
            await self?.publishCitationControlInvalidation()
        }
    }

    private func publishCitationControlInvalidation() async {
        defer { citationControlInvalidationTask = nil }
        while citationControlInvalidationPending && !isShutDown && !Task.isCancelled {
            let lease: WorkspaceSourceOperationLease
            do {
                lease = try await acquireWorkspaceSourceOperation(.refreshCycle)
            } catch { return }
            guard !isShutDown, !Task.isCancelled else {
                releaseWorkspaceSourceOperation(lease)
                return
            }
            citationControlInvalidationPending = false
            await events.publishCitationAuthorityInvalidated(snapshot: currentSnapshot)
            releaseWorkspaceSourceOperation(lease)
        }
    }

    /// Attaches portable citation authority only to a freshly checked Note
    /// identity. A stale or unreadable companion never makes source unreadable.
    func documentWithCitationSnapshot(
        _ document: NoteDocument,
        id: VaultQualifiedNoteID,
        expectedNoteID: UUID? = nil
    ) async throws -> NoteDocument {
        guard
            let identity = try await services.controlStore.identityRecord(
                vaultID: id.vaultID, relativePath: id.relativePath)
        else {
            if expectedNoteID != nil { throw WorkspaceHydrationError.staleSnapshot }
            return document
        }
        if let expectedNoteID, identity.id != expectedNoteID {
            throw WorkspaceHydrationError.staleSnapshot
        }
        let snapshot: ZoteroCitationSnapshot
        do {
            snapshot = try await services.controlStore.citationSnapshot(
                noteID: identity.id, vaultID: id.vaultID,
                sourceFingerprint: document.fingerprint)
        } catch {
            return document.withCitationSnapshot(
                .init(
                    noteID: identity.id, vaultID: id.vaultID, status: .unresolved))
        }
        guard
            try await services.controlStore.identityRecord(
                vaultID: id.vaultID, relativePath: id.relativePath)?.id == identity.id
        else { throw WorkspaceHydrationError.staleSnapshot }
        return document.withCitationSnapshot(snapshot)
    }

    func citationSaveCoordinator() -> ZoteroCitationSaveCoordinator {
        ZoteroCitationSaveCoordinator(
            triptychID: services.manifest.id, repositories: services.repositories,
            controlStore: services.controlStore,
            recoveryStore: services.transactionRecoveryStore)
    }

    /// The caller holds the workspace source lease. Reconciliation may finish
    /// an already authorized companion write only against the exact retained
    /// pair; source or identity conflicts leave the recovery duty intact.
    func reconcileCitationSaveRecovery(
        _ recovery: ZoteroCitationPairRecovery, explicitlyCompleting: Bool = false
    ) async throws {
        let coordinator = citationSaveCoordinator()
        let target: NoteMutationTarget
        if recovery.sourceBefore == nil {
            let reservedTarget = NoteMutationTarget(
                documentID: .init(vaultID: recovery.vaultID, relativePath: recovery.relativePath),
                stableNoteID: recovery.noteID, revision: recovery.sourceAfter)
            do {
                if try await coordinator.reconcile(recovery, target: reservedTarget) == .unchanged {
                    try await coordinator.complete(
                        recovery, target: reservedTarget, explicitlyCompletingRetainedEvidence: explicitlyCompleting)
                    return
                }
            } catch ZoteroCitationSaveError.identityChanged {
                // A committed no-replace source may precede its reserved
                // identity. The creation-specific owner proves that case.
            }
            target = try await coordinator.recoverCreationIdentity(recovery)
        } else {
            let id = VaultQualifiedNoteID(vaultID: recovery.vaultID, relativePath: recovery.relativePath)
            let document = try await repository(vaultID: recovery.vaultID).load(
                relativePath: recovery.relativePath)
            guard
                try await services.controlStore.identityRecord(
                    vaultID: recovery.vaultID, relativePath: recovery.relativePath)?.id == recovery.noteID
            else { throw ZoteroCitationSaveError.recoveryRequired(recovery) }
            target = NoteMutationTarget(
                documentID: id, stableNoteID: recovery.noteID, revision: document.fingerprint)
        }
        switch try await coordinator.reconcile(recovery, target: target) {
        case .unchanged, .committed:
            try await coordinator.complete(
                recovery, target: target, explicitlyCompletingRetainedEvidence: explicitlyCompleting)
        case .sourceCommitted:
            _ = try await coordinator.resume(recovery, target: target)
        case .conflicted:
            if explicitlyCompleting {
                // Completion proves a coherent canonical pair independently.
                // It may account for displaced bytes, never restore over them.
                try await coordinator.complete(recovery, target: target, explicitlyCompletingRetainedEvidence: true)
                return
            }
            throw ZoteroCitationSaveError.recoveryRequired(recovery)
        }
    }

    /// Agent receipts retain source alone. They cannot authorize restoring an
    /// earlier source over independently changed essential citation metadata.
    func requireSourceOnlyAgentUndo(noteID: UUID, vaultID: UUID, changeID: UUID) async throws {
        let snapshot = try await services.controlStore.citationSnapshot(
            noteID: noteID, vaultID: vaultID)
        guard snapshot.status == .absent else {
            throw AgentChangeError.undoUnavailable(changeID)
        }
    }
}
