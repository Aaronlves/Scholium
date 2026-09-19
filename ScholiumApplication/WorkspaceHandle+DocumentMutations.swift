import Foundation
import OSLog
import ScholiumContracts
import ScholiumCore

enum DocumentSaveCompletion: Equatable {
    /// Return only after the matching derived workspace generation publishes.
    case sourceAndDerived
    /// Return after the authoritative repository commit and refresh in the
    /// Workspace-owned background queue.
    case sourceOnly
}

enum DocumentSaveOperationOutcome: Sendable {
    case committed(WorkspaceMutationOutcome<SaveResult>)
    case notWritten(VaultSaveNotWrittenReason)
    case recoveryRequired(TriptychMutationRecoveryRecord)
}
extension WorkspaceHandle {
    func saveDocument(
        _ id: VaultQualifiedNoteID,
        changeSet: NoteChangeSet,
        expectedRevision: DocumentFingerprint
    ) async throws -> WorkspaceMutationOutcome<SaveResult> {
        switch try await performDocumentSave(
            id,
            changeSet: changeSet,
            expectedRevision: expectedRevision,
            completion: .sourceAndDerived
        ) {
        case .committed(let outcome):
            return outcome
        case .notWritten(let reason):
            throw documentSaveError(reason, expectedRevision: expectedRevision)
        case .recoveryRequired(let record):
            throw TriptychTransactionError.recoveryRequired(record)
        }
    }

    /// Shared Metadata writer; callers hold the workspace source-mutation lease.

    func commitDocument(
        _ id: VaultQualifiedNoteID,
        changeSet: NoteChangeSet,
        expectedRevision: DocumentFingerprint
    ) async throws -> SaveResult {
        switch try await performDocumentSave(
            id,
            changeSet: changeSet,
            expectedRevision: expectedRevision,
            completion: .sourceOnly
        ) {
        case .committed(let outcome):
            return outcome.committedValue
        case .notWritten(let reason):
            throw documentSaveError(reason, expectedRevision: expectedRevision)
        case .recoveryRequired(let record):
            throw TriptychTransactionError.recoveryRequired(record)
        }
    }

    private func performDocumentSave(
        _ id: VaultQualifiedNoteID,
        changeSet: NoteChangeSet,
        expectedRevision: DocumentFingerprint,
        completion: DocumentSaveCompletion
    ) async throws -> DocumentSaveOperationOutcome {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer {
            if ownsMutation { endSourceMutation(mutationLease) }
        }
        let repository = try repository(vaultID: id.vaultID)
        let save = try await repository.saveOutcome(
            relativePath: id.relativePath,
            changeSet: changeSet,
            expectedRevision: expectedRevision
        )
        switch save {
        case .notWritten(let reason):
            return .notWritten(reason)
        case .recoveryRequired(let sourceRecovery):
            let record = try await recordUncertainNoteSave(
                id: id,
                expectedRevision: expectedRevision,
                // A displaced external revision is a restoration candidate,
                // not the source this save originally attempted to write.
                intendedRevision: sourceRecovery.expectedRevision == expectedRevision
                    ? sourceRecovery.candidateRevision : nil,
                repository: repository,
                failure: sourceRecovery.retainedReason,
                detail: "The coordinated save could not prove the canonical result. The exact source transaction remains machine-local for reconciliation."
            )
            return .recoveryRequired(record)
        case .committed(let result):
            if completion == .sourceOnly {
                // Queue before releasing the mutation lease so the matching
                // watcher event cannot start a competing refresh first.
                scheduleSourceCommitRefresh(id: id, kind: .save)
            }
            endSourceMutation(mutationLease)
            ownsMutation = false
            var derivedRefreshWarning: String?
            if completion == .sourceAndDerived {
                do {
                    _ = try await refresh(
                        publication: .sourceCommitted(id, .save),
                        failureDisposition: .staleAfterCommittedMutation(
                            affectedVaultIDs: [id.vaultID]
                        )
                    )
                    derivedRefreshWarning = nil
                } catch {
                    derivedRefreshWarning = error.localizedDescription
                }
            }
            return .committed(
                WorkspaceMutationOutcome(
                    committedValue: result,
                    derivedRefreshWarning: derivedRefreshWarning
                ))
        }
    }

    private func recordUncertainNoteSave(
        id: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint,
        intendedRevision: DocumentFingerprint?,
        repository: VaultRepository,
        failure: String,
        detail: String
    ) async throws -> TriptychMutationRecoveryRecord {
        let observed = try? await repository.load(relativePath: id.relativePath).fingerprint
        let state: TriptychMutationRecoveryState
        if let observed {
            if observed == expectedRevision {
                state = .restored
            } else if observed == intendedRevision {
                state = .intendedBytesRemain
            } else {
                state = .externallyChanged
            }
        } else {
            state = .unreadable
        }
        let record = TriptychMutationRecoveryRecord(
            triptychID: self.id,
            operation: .noteSave,
            failure: failure,
            files: [
                TriptychMutationRecoveryFile(
                    vaultID: id.vaultID,
                    path: id.relativePath,
                    role: .savedNote,
                    beforeRevision: expectedRevision,
                    intendedRevision: intendedRevision,
                    observedRevision: observed,
                    state: state,
                    detail: detail
                )
            ]
        )
        do {
            try await services.transactionRecoveryStore.record(record)
        } catch {
            throw TriptychTransactionError.recoveryPersistenceFailed(
                record,
                error.localizedDescription
            )
        }
        return record
    }

    private func documentSaveError(
        _ reason: VaultSaveNotWrittenReason,
        expectedRevision: DocumentFingerprint
    ) -> VaultRepositoryError {
        switch reason {
        case .conflict(let current):
            .conflict(expected: expectedRevision, current: current)
        case .targetIdentityChanged:
            .notRegularFile("The Note path no longer belongs to the authorized portable identity.")
        case .invalidFrontmatter(let message):
            .invalidFrontmatter(message)
        case .atomicCommitUnsupported(let message):
            .atomicCommitUnsupported(message)
        }
    }

    func moveDocument(
        _ id: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit> {
        try await coordinatedMoveDocument(
            id,
            to: destinationRelativePath,
            expectedRevision: expectedRevision
        )
    }

    func moveDocument(
        _ target: NoteMutationTarget,
        to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit> {
        try await coordinatedMoveDocument(
            target.documentID,
            to: destinationRelativePath,
            expectedRevision: target.revision,
            expectedStableNoteID: target.stableNoteID
        )
    }

    func prepareSystemTrash(
        _ target: NoteMutationTarget
    ) async throws -> SystemTrashDeletionPreview {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        defer { endSourceMutation(mutationLease) }
        let identity = try await resolvedIdentity(
            for: target.documentID,
            expectedRevision: target.revision
        )
        try requireExpectedIdentity(
            target.stableNoteID,
            resolved: identity.id,
            relativePath: target.relativePath
        )
        return try await systemTrashCoordinator(vaultID: target.documentID.vaultID)
            .prepareNote(
                noteID: identity.id,
                vaultID: target.documentID.vaultID,
                relativePath: target.relativePath,
                expectedRevision: target.revision
            )
    }

    func prepareFolderSystemTrash(
        inVault vaultID: UUID,
        relativePath: String
    ) async throws -> SystemTrashDeletionPreview {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        defer { endSourceMutation(mutationLease) }
        return try await systemTrashCoordinator(vaultID: vaultID).prepareFolder(
            vaultID: vaultID,
            relativePath: relativePath
        )
    }

    func moveToSystemTrash(
        _ preview: SystemTrashDeletionPreview
    ) async throws -> WorkspaceMutationOutcome<SystemTrashDeletionCommit> {
        try requireActive()
        guard let vaultID = preview.sources.first?.vaultID,
            preview.sources.allSatisfy({ $0.vaultID == vaultID })
        else {
            throw TriptychTransactionError.invalidPlan(
                "A system-Trash plan must belong to exactly one vault."
            )
        }
        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer { if ownsMutation { endSourceMutation(mutationLease) } }
        let commit: SystemTrashDeletionCommit
        do {
            commit = try await systemTrashCoordinator(vaultID: vaultID)
                .moveToSystemTrash(preview)
        } catch {
            endSourceMutation(mutationLease)
            ownsMutation = false
            _ = try? await refresh(
                publication: .explicit,
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: [vaultID]
                )
            )
            throw error
        }
        endSourceMutation(mutationLease)
        ownsMutation = false
        let deletedIDs = preview.sources.flatMap(\.notes).map {
            VaultQualifiedNoteID(vaultID: vaultID, relativePath: $0.relativePath)
        }
        let derivedRefreshWarning: String?
        do {
            _ = try await refresh(
                publication: .explicit,
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: [vaultID]
                ),
                sourceCatalogPreparation: Self.catalogPreparation(
                    deletions: deletedIDs,
                    refreshFolderVaultIDs: [vaultID]
                )
            )
            derivedRefreshWarning = nil
        } catch {
            derivedRefreshWarning = error.localizedDescription
        }
        return WorkspaceMutationOutcome(
            committedValue: commit,
            derivedRefreshWarning: derivedRefreshWarning
        )
    }

    func systemTrashCoordinator(
        vaultID: UUID
    ) throws -> NoteSystemTrashDeletionCoordinator {
        let repository = try repository(vaultID: vaultID)
        return NoteSystemTrashDeletionCoordinator(
            triptychID: services.manifest.id,
            repository: repository,
            controlStore: services.controlStore,
            recoveryStore: services.transactionRecoveryStore
        )
    }

    func interruptedSaveRecoveries() async throws -> [InterruptedSaveRecovery] {
        try requireActive()
        var recoveries: [InterruptedSaveRecovery] = []
        for vault in orderedVaults() {
            let repository = try repository(vaultID: vault.id)
            recoveries.append(contentsOf: try await repository.interruptedSaveRecoveries())
        }
        return recoveries.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            if $0.id.vaultID != $1.id.vaultID {
                return $0.id.vaultID.uuidString < $1.id.vaultID.uuidString
            }
            return $0.id.transactionID.uuidString < $1.id.transactionID.uuidString
        }
    }

    func interruptedSaveRecoveryContent(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> InterruptedSaveRecoveryContent {
        try requireActive()
        return try await repository(vaultID: recovery.id.vaultID)
            .interruptedSaveRecoveryContent(recovery)
    }

    func prepareInterruptedSaveRecoveryLocation(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> URL {
        try requireActive()
        return try await repository(vaultID: recovery.id.vaultID)
            .prepareInterruptedSaveRecoveryLocation(recovery)
    }

    func restoreInterruptedSaveRecovery(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> WorkspaceMutationOutcome<InterruptedSaveRecoveryRestoreCommit> {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer {
            if ownsMutation { endSourceMutation(mutationLease) }
        }
        let repository = try repository(vaultID: recovery.id.vaultID)
        let commit: InterruptedSaveRecoveryRestoreCommit
        do {
            commit = try await repository.restoreInterruptedSaveRecovery(recovery)
        } catch let error as VaultRepositoryError {
            let sourceRecovery: InterruptedSaveRecovery
            let failure: String
            switch error {
            case .commitUncertain:
                sourceRecovery = recovery
                failure = error.localizedDescription
            case .recoveryRequired(let retained):
                sourceRecovery = retained
                failure = retained.retainedReason
            default:
                throw error
            }
            let record = try await recordUncertainNoteSave(
                id: VaultQualifiedNoteID(
                    vaultID: recovery.id.vaultID,
                    relativePath: recovery.relativePath
                ),
                expectedRevision: sourceRecovery.expectedRevision,
                intendedRevision: sourceRecovery.candidateRevision,
                repository: repository,
                failure: failure,
                detail:
                    "Interrupted-save recovery could not prove both canonical and displaced bytes. The candidate and every available source revision remain machine-local for inspection."
            )
            throw TriptychTransactionError.recoveryRequired(record)
        }
        endSourceMutation(mutationLease)
        ownsMutation = false

        var derivedRefreshWarning: String?
        if commit.didReplaceSource {
            do {
                _ = try await refresh(
                    publication: .sourceCommitted(
                        VaultQualifiedNoteID(
                            vaultID: recovery.id.vaultID,
                            relativePath: recovery.relativePath
                        ),
                        .save
                    ),
                    failureDisposition: .staleAfterCommittedMutation(
                        affectedVaultIDs: [recovery.id.vaultID]
                    )
                )
            } catch {
                derivedRefreshWarning = error.localizedDescription
            }
        }
        return WorkspaceMutationOutcome(
            committedValue: commit,
            derivedRefreshWarning: derivedRefreshWarning
        )
    }

    func recoverInterruptedDocumentTransactions() async -> [String] {
        guard !isShutDown else {
            return [ScholiumApplicationError.workspaceShutDown(id).localizedDescription]
        }
        let mutationLease: WorkspaceSourceOperationLease
        do {
            mutationLease = try await beginSourceMutation()
        } catch {
            return [error.localizedDescription]
        }
        defer { endSourceMutation(mutationLease) }
        var issues: [String] = []
        for (vaultID, repository) in services.repositories.sorted(by: {
            $0.key.uuidString < $1.key.uuidString
        }) {
            let coordinator = NoteSystemTrashDeletionCoordinator(
                triptychID: services.manifest.id,
                repository: repository,
                controlStore: services.controlStore,
                recoveryStore: services.transactionRecoveryStore
            )
            do {
                try await coordinator.recoverInterruptedTransactions()
            } catch {
                issues.append("Vault \(vaultID.uuidString): \(error.localizedDescription)")
            }
        }
        return issues
    }

    func resolveUnknownSystemTrashOutcome(
        recoveryRecordID: UUID,
        vaultID: UUID
    ) async throws {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        defer { endSourceMutation(mutationLease) }
        try await systemTrashCoordinator(vaultID: vaultID)
            .resolveUnknownOutcome(
                recoveryRecordID: recoveryRecordID
            )
    }

}
