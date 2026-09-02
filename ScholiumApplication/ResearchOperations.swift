import Foundation
import ScholiumContracts
import ScholiumCore

extension WorkspaceHandle {
    @discardableResult
    func settle(
        _ noteID: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint,
        rationale: String?
    ) async throws -> SettlementRecord {
        let context = try await researcherJudgmentContext(
            for: noteID,
            expectedRevision: expectedRevision,
            permits: { $0 != .other },
            unavailable: { ResearchOperationError.settlementUnavailable($0) }
        )
        let settlement = try await services.settlementStore.settle(
            noteID: context.identity.id,
            fingerprint: expectedRevision,
            rationale: rationale
        )
        _ = try await refresh(publication: .explicit)
        return settlement
    }

    func critique(
        critiqueRelativePath: String
    ) async throws -> CritiqueAssociation? {
        try requireActive()
        if let issue = await services.critiqueRegistry.healthError() {
            throw ScholiumApplicationError.critiqueStoreUnavailable(issue)
        }
        return await services.critiqueRegistry.association(
            critiqueRelativePath: critiqueRelativePath
        )
    }

    func setCritiqueFindingDisposition(
        workNote: VaultQualifiedNoteID,
        roundID: UUID,
        findingID: String,
        decision: CritiqueFindingDispositionDecision,
        rationale: String?,
        noTextChangeRationale: String?,
        expectedRevision: DocumentFingerprint
    ) async throws -> CritiqueAssociation {
        let context = try await researcherJudgmentContext(
            for: workNote,
            expectedRevision: expectedRevision,
            permits: { $0.allowsCritique },
            unavailable: { ResearchOperationError.critiqueUnavailable($0) }
        )
        guard !CritiquePlacement.isManagedCritiquePath(workNote.relativePath) else {
            throw ResearchOperationError.critiqueTargetMustBeOrdinaryWork(
                workNote.relativePath
            )
        }
        if let issue = await services.critiqueRegistry.healthError() {
            throw ScholiumApplicationError.critiqueStoreUnavailable(issue)
        }
        guard let current = await services.critiqueRegistry.association(
            workNoteID: context.identity.id
        ), current.rounds.contains(where: { $0.id == roundID }) else {
            throw CritiqueRegistryError.roundNotFound(roundID)
        }
        let association = try await services.critiqueRegistry
            .setFindingDisposition(
                roundID: roundID,
                findingID: findingID,
                decision: decision,
                currentWorkRevision: context.document.fingerprint,
                rationale: rationale,
                noTextChangeRationale: noTextChangeRationale
            )
        _ = try await refresh(publication: .explicit)
        return association
    }

    func completeCritiqueRound(
        workNote: VaultQualifiedNoteID,
        roundID: UUID,
        expectedRevision: DocumentFingerprint
    ) async throws -> CritiqueAssociation {
        let context = try await researcherJudgmentContext(
            for: workNote,
            expectedRevision: expectedRevision,
            permits: { $0.allowsCritique },
            unavailable: { ResearchOperationError.critiqueUnavailable($0) }
        )
        guard !CritiquePlacement.isManagedCritiquePath(workNote.relativePath) else {
            throw ResearchOperationError.critiqueTargetMustBeOrdinaryWork(
                workNote.relativePath
            )
        }
        guard let current = await services.critiqueRegistry.association(
            workNoteID: context.identity.id
        ), current.rounds.contains(where: { $0.id == roundID }) else {
            throw CritiqueRegistryError.roundNotFound(roundID)
        }
        let association = try await services.critiqueRegistry.completeRound(
            roundID: roundID
        )
        guard association.rounds.contains(where: {
            $0.id == roundID && $0.completedAt != nil
        }) else {
            throw CritiqueRegistryError.incompleteDispositions(roundID)
        }
        _ = try await refresh(publication: .explicit)
        return association
    }

    func recoveryRecords() async throws -> [TriptychMutationRecoveryRecord] {
        try requireActive()
        return try await services.transactionRecoveryStore.pending()
    }

    func resolveRecoveryRecord(_ id: UUID) async throws {
        try requireActive()
        let records = try await services.transactionRecoveryStore.pending()
        guard let record = records.first(where: { $0.id == id }),
              record.triptychID == self.id else {
            throw TriptychTransactionError.invalidPlan(
                "The selected recovery record is unavailable for this Triptych."
            )
        }
        if let plan = record.systemTrashDeletionPlan,
           plan.sourceReceipts.contains(where: { $0.progress == .outcomeUnknown }) {
            guard let vaultID = plan.preview.sources.first?.vaultID,
                  plan.preview.sources.allSatisfy({ $0.vaultID == vaultID }) else {
                throw TriptychTransactionError.invalidPlan(
                    "The unknown system-Trash outcome cannot be resolved automatically."
                )
            }
            try await resolveUnknownSystemTrashOutcome(
                recoveryRecordID: record.id,
                vaultID: vaultID
            )
            _ = try await refresh(publication: .explicit)
            return
        }
        if let managedCreation = record.managedCreation {
            let lease = try await beginResearchControlledSourceObservation()
            var ownsLease = true
            defer {
                if ownsLease { endResearchControlledSourceObservation(lease) }
            }
            try await reconcileManagedCreationRecovery(
                record,
                reference: managedCreation
            )
            endResearchControlledSourceObservation(lease)
            ownsLease = false
            _ = try await refresh(publication: .explicit)
            return
        }
        try await services.transactionRecoveryStore.resolve(record)
        _ = try await refresh(publication: .explicit)
    }

    private func reconcileManagedCreationRecovery(
        _ record: TriptychMutationRecoveryRecord,
        reference: ManagedCreationRecoveryReference
    ) async throws {
        guard record.operation == .noteCreation,
              record.triptychID == id,
              record.files.count == 1,
              let file = record.files.first,
              file.role == .createdNote,
              file.beforeRevision == nil,
              file.vaultID == reference.target.vaultID,
              file.path == reference.target.relativePath,
              let intendedRevision = file.intendedRevision else {
            throw TriptychTransactionError.invalidPlan(
                "The managed creation recovery does not describe one exact new Note."
            )
        }
        let repository = try repository(vaultID: reference.target.vaultID)
        let source: NoteDocument?
        do {
            source = try await repository.load(
                relativePath: reference.target.relativePath
            )
        } catch VaultRepositoryError.fileDoesNotExist {
            source = nil
        } catch {
            throw TriptychTransactionError.recoveryRequired(record)
        }

        guard source == nil || source?.fingerprint == intendedRevision else {
            throw TriptychTransactionError.recoveryRequired(record)
        }
        let identityReconciliation: ManagedCreationIdentityReconciliation
        do {
            identityReconciliation = try await services.controlStore
                .reconcileManagedCreationIdentity(
                    vaultID: reference.target.vaultID,
                    relativePath: reference.target.relativePath,
                    intendedRevision: intendedRevision,
                    reservedIdentityID: reference.reservedIdentityID,
                    sourceIsPresent: source != nil
                )
        } catch {
            throw TriptychTransactionError.recoveryRequired(record)
        }

        var createdMetadata: NoteMetadataSnapshot?
        if let fields = reference.metadataFields, source != nil {
            do {
                if let current = try await services.controlStore.noteMetadata(
                    noteID: reference.reservedIdentityID
                ) {
                    guard current.record.fields == fields else {
                        throw NoteMetadataError.revisionConflict(
                            reference.reservedIdentityID
                        )
                    }
                } else {
                    createdMetadata = try await services.controlStore.saveNoteMetadata(
                        noteID: reference.reservedIdentityID,
                        fields: fields,
                        expectedRevision: nil
                    )
                }
            } catch {
                try? await services.controlStore.rollbackManagedCreationIdentity(
                    identityReconciliation,
                    vaultID: reference.target.vaultID,
                    relativePath: reference.target.relativePath
                )
                throw TriptychTransactionError.recoveryRequired(record)
            }
        }

        let finalSource: NoteDocument?
        do {
            finalSource = try await repository.load(
                relativePath: reference.target.relativePath
            )
        } catch VaultRepositoryError.fileDoesNotExist {
            finalSource = nil
        } catch {
            throw TriptychTransactionError.recoveryRequired(record)
        }
        let finalPathIdentity: NoteIdentityRecord?
        let finalReservedIdentity: NoteIdentityRecord?
        do {
            finalPathIdentity = try await services.controlStore.identityRecord(
                vaultID: reference.target.vaultID,
                relativePath: reference.target.relativePath
            )
            finalReservedIdentity = try await services.controlStore.identityRecord(
                id: reference.reservedIdentityID
            )
        } catch {
            throw TriptychTransactionError.recoveryRequired(record)
        }
        if let finalSource {
            let finalMetadata = try? await services.controlStore.noteMetadata(
                noteID: reference.reservedIdentityID
            )
            guard finalSource.fingerprint == intendedRevision,
                  finalPathIdentity?.id == reference.reservedIdentityID,
                  finalPathIdentity?.fingerprint == intendedRevision,
                  finalReservedIdentity == finalPathIdentity,
                  finalMetadata?.record.fields == reference.metadataFields else {
                if let createdMetadata {
                    try? await services.controlStore.removeNoteMetadata(createdMetadata)
                }
                try? await services.controlStore.rollbackManagedCreationIdentity(
                    identityReconciliation,
                    vaultID: reference.target.vaultID,
                    relativePath: reference.target.relativePath
                )
                throw TriptychTransactionError.recoveryRequired(record)
            }
        } else {
            guard finalPathIdentity == nil, finalReservedIdentity == nil else {
                try? await services.controlStore.rollbackManagedCreationIdentity(
                    identityReconciliation,
                    vaultID: reference.target.vaultID,
                    relativePath: reference.target.relativePath
                )
                throw TriptychTransactionError.recoveryRequired(record)
            }
            let currentMetadata: NoteMetadataSnapshot?
            do {
                currentMetadata = try await services.controlStore.noteMetadata(
                    noteID: reference.reservedIdentityID
                )
            } catch {
                throw TriptychTransactionError.recoveryRequired(record)
            }
            if let currentMetadata {
                guard currentMetadata.record.fields == reference.metadataFields else {
                    throw TriptychTransactionError.recoveryRequired(record)
                }
                do {
                    try await services.controlStore.removeNoteMetadata(currentMetadata)
                } catch {
                    throw TriptychTransactionError.recoveryRequired(record)
                }
            }
        }
        try await services.transactionRecoveryStore.resolve(record)
    }

    private struct ResearcherJudgmentContext {
        let document: NoteDocument
        let identity: NoteIdentityRecord
    }

    private func researcherJudgmentContext(
        for noteID: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint,
        permits: (VaultRole) -> Bool,
        unavailable: (VaultRole) -> Error
    ) async throws -> ResearcherJudgmentContext {
        try requireActive()
        let registeredVault = try vault(id: noteID.vaultID)
        guard permits(registeredVault.role) else {
            throw unavailable(registeredVault.role)
        }
        guard currentSnapshot.document(id: noteID) != nil else {
            throw ResearchOperationError.noteUnavailable(noteID)
        }
        let identity = try await resolvedIdentity(
            for: noteID,
            expectedRevision: expectedRevision
        )
        let document = try await repository(vaultID: noteID.vaultID).load(
            relativePath: noteID.relativePath
        )
        guard document.fingerprint == expectedRevision else {
            throw VaultRepositoryError.conflict(
                expected: expectedRevision,
                current: document.fingerprint
            )
        }
        return ResearcherJudgmentContext(
            document: document,
            identity: identity
        )
    }
}
