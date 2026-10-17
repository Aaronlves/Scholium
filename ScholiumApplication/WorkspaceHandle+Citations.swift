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
        expectedNoteID: UUID? = nil,
        identityInventory suppliedInventory: TriptychIdentityInventorySnapshot? = nil
    ) async throws -> NoteDocument {
        // Standalone hydration reaches this point only after its exact-source
        // read. Preview batches may instead supply one operation-local revision.
        let inventory: TriptychIdentityInventorySnapshot
        if let suppliedInventory {
            inventory = suppliedInventory
        } else {
            inventory = try await services.controlStore.identityInventorySnapshot()
        }
        try Task.checkCancellation()
        try requireActive()
        try await services.controlStore.validateIdentityInventory(inventory)
        let identity: NoteIdentityRecord?
        if let expectedNoteID {
            identity = inventory.recordsByID[expectedNoteID]
        } else {
            identity = inventory.recordsByID.values.first {
                $0.vaultID == id.vaultID && $0.relativePath.utf8.elementsEqual(id.relativePath.utf8)
            }
        }
        guard let identity else {
            if expectedNoteID != nil { throw WorkspaceHydrationError.staleSnapshot }
            return document
        }
        guard identity.vaultID == id.vaultID,
            identity.relativePath.utf8.elementsEqual(id.relativePath.utf8)
        else { throw WorkspaceHydrationError.staleSnapshot }
        let snapshot: ZoteroCitationSnapshot
        do {
            snapshot = try await services.controlStore.citationSnapshot(
                noteID: identity.id, vaultID: id.vaultID,
                sourceFingerprint: document.fingerprint, identity: identity, inventory: inventory)
        } catch TriptychControlError.identitiesRevisionConflict {
            throw WorkspaceHydrationError.staleSnapshot
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            snapshot = .init(noteID: identity.id, vaultID: id.vaultID, status: .unresolved)
        }
        // This await is outside companion fallback handling. No fallback may
        // admit changed identity authority or publish after shutdown/cancel.
        try await services.controlStore.validateIdentityInventory(inventory)
        try Task.checkCancellation()
        try requireActive()
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
