import ScholiumContracts
import Foundation

enum PermanentDeletionFaultPoint: Hashable, Sendable {
    case afterCritiqueDeletion
    case afterSourceDeletion
    case afterDialoguePurge
    case afterSettlementPurge
    case afterCritiqueAssociationPurge
    case afterCheckpointPurge
    case afterIdentityPurge
    case afterCommitDecision
}

struct PermanentDeletionFaultPlan: Sendable {
    let failures: Set<PermanentDeletionFaultPoint>
    let interruptions: Set<PermanentDeletionFaultPoint>

    static let none = Self(failures: [], interruptions: [])

    func trigger(_ point: PermanentDeletionFaultPoint) throws {
        if interruptions.contains(point) {
            throw PermanentDeletionInjectedFailure(point: point, isInterruption: true)
        }
        if failures.contains(point) {
            throw PermanentDeletionInjectedFailure(point: point, isInterruption: false)
        }
    }
}

private struct PermanentDeletionInjectedFailure: LocalizedError, Sendable {
    let point: PermanentDeletionFaultPoint
    let isInterruption: Bool

    var errorDescription: String? {
        "Injected permanent-deletion \(isInterruption ? "interruption" : "failure") at \(String(describing: point))."
    }
}

/// Coordinates permanent deletion across authoritative Markdown, app-owned
/// records, portable identity, and self-contained checkpoints. Every source
/// file has a committed recovery version and every non-file record is copied
/// into a durable transaction journal before the first removal.
public actor NotePermanentDeletionCoordinator {
    private let triptychID: UUID
    private let repository: VaultRepository
    private let dialogueStore: DialogueStore
    private let critiqueRegistry: CritiqueRegistry
    private let checkpointStore: TriptychCheckpointStore
    private let controlStore: TriptychControlStore
    private let recoveryStore: TriptychMutationRecoveryStore
    private let sourceAccessStore: ResearchSourceAccessStore?
    private let portableRecordStore: PortableResearchRecordStore?
    private let localExecutionStore: LocalResearchExecutionStore?
    private let faultPlan: PermanentDeletionFaultPlan

    public init(
        triptychID: UUID,
        repository: VaultRepository,
        dialogueStore: DialogueStore,
        critiqueRegistry: CritiqueRegistry,
        checkpointStore: TriptychCheckpointStore,
        controlStore: TriptychControlStore,
        recoveryStore: TriptychMutationRecoveryStore,
        sourceAccessStore: ResearchSourceAccessStore? = nil,
        portableRecordStore: PortableResearchRecordStore? = nil,
        localExecutionStore: LocalResearchExecutionStore? = nil
    ) {
        self.triptychID = triptychID
        self.repository = repository
        self.dialogueStore = dialogueStore
        self.critiqueRegistry = critiqueRegistry
        self.checkpointStore = checkpointStore
        self.controlStore = controlStore
        self.recoveryStore = recoveryStore
        self.sourceAccessStore = sourceAccessStore
        self.portableRecordStore = portableRecordStore
        self.localExecutionStore = localExecutionStore
        self.faultPlan = .none
    }

    init(
        triptychID: UUID,
        repository: VaultRepository,
        dialogueStore: DialogueStore,
        critiqueRegistry: CritiqueRegistry,
        checkpointStore: TriptychCheckpointStore,
        controlStore: TriptychControlStore,
        recoveryStore: TriptychMutationRecoveryStore,
        sourceAccessStore: ResearchSourceAccessStore? = nil,
        portableRecordStore: PortableResearchRecordStore? = nil,
        localExecutionStore: LocalResearchExecutionStore? = nil,
        faultPlan: PermanentDeletionFaultPlan
    ) {
        self.triptychID = triptychID
        self.repository = repository
        self.dialogueStore = dialogueStore
        self.critiqueRegistry = critiqueRegistry
        self.checkpointStore = checkpointStore
        self.controlStore = controlStore
        self.recoveryStore = recoveryStore
        self.sourceAccessStore = sourceAccessStore
        self.portableRecordStore = portableRecordStore
        self.localExecutionStore = localExecutionStore
        self.faultPlan = faultPlan
    }

    public func delete(
        noteID: UUID,
        vaultID: UUID,
        relativePath: String,
        expectedRevision: DocumentFingerprint,
        checkpointArea: TriptychCheckpointArea
    ) async throws -> PermanentDeletionCommit {
        try await requireHealthyStores()
        // Fail before the first authoritative mutation if machine-local
        // source bindings cannot be decoded safely. Otherwise a deletion
        // could reach its commit decision and then strand privacy cleanup.
        try await sourceAccessStore?.validateStoreHealth()
        try await localExecutionStore?.validateStoreHealth()
        guard repository.identity.id == vaultID else {
            throw TriptychTransactionError.invalidPlan(
                "The permanent-deletion repository does not match the selected vault identity."
            )
        }
        _ = try await repository.preflightExisting(
            relativePath: relativePath,
            expectedRevision: expectedRevision
        )

        let associations = await critiqueRegistry.associationsRelated(
            noteID: noteID,
            relativePath: relativePath
        )
        let workAssociation = associations.first {
            $0.workNoteID == noteID && $0.workRelativePath == relativePath
        }
        let critiqueBefore: NoteDocument?
        if let workAssociation {
            guard workAssociation.critiqueRelativePath != relativePath else {
                throw TriptychTransactionError.invalidPlan(
                    "A Work and its associated Critique cannot use the same path."
                )
            }
            critiqueBefore = try await repository.load(
                relativePath: workAssociation.critiqueRelativePath
            )
        } else {
            critiqueBefore = nil
        }

        let critiqueIdentityRecord: NoteIdentityRecord?
        if let workAssociation {
            critiqueIdentityRecord = try await controlStore.identityRecord(
                vaultID: vaultID,
                relativePath: workAssociation.critiqueRelativePath
            )
        } else {
            critiqueIdentityRecord = nil
        }
        let critiqueNoteID = critiqueIdentityRecord?.id
        let critiqueDialogues: [DialogueEntry]
        let critiqueIdentityBackup: PermanentDeletionIdentityBackup?
        if let critiqueIdentityRecord {
            critiqueDialogues = []
            critiqueIdentityBackup = try await controlStore.prepareIdentityPurge(
                id: critiqueIdentityRecord.id,
                vaultID: critiqueIdentityRecord.vaultID,
                relativePath: critiqueIdentityRecord.relativePath
            )
        } else {
            critiqueDialogues = []
            critiqueIdentityBackup = nil
        }

        let settlementIDs = [noteID, critiqueNoteID].compactMap { $0 }
        var settlements: [SettlementRecord] = []
        for settlementID in settlementIDs {
            if let settlement = try await portableRecordStore?.latestSettlement(
                noteID: settlementID
            ) {
                settlements.append(settlement)
            }
        }
        var backup = PermanentDeletionRecoveryBackup(
            phase: .rollbackRequired,
            noteID: noteID,
            vaultID: vaultID,
            relativePath: relativePath,
            expectedRevision: expectedRevision,
            checkpointArea: checkpointArea,
            dialogues: [],
            critiqueNoteID: critiqueNoteID,
            critiqueDialogues: critiqueDialogues,
            critiqueAssociations: associations,
            identity: try await controlStore.prepareIdentityPurge(
                id: noteID,
                vaultID: vaultID,
                relativePath: relativePath
            ),
            critiqueIdentity: critiqueIdentityBackup,
            sourceDeletion: nil,
            critiqueDeletion: nil,
            checkpointPurge: nil,
            settlements: settlements
        )
        var record = makeRecord(
            id: UUID(),
            createdAt: Date(),
            failure: "Permanent deletion was prepared but has not completed.",
            backup: backup,
            files: initialFileEvidence(
                relativePath: relativePath,
                expectedRevision: expectedRevision,
                critiqueBefore: critiqueBefore
            )
        )
        try await recoveryStore.record(record)

        do {
            try await portableRecordStore?.markNoteDeletionStarted(
                noteIDs: Set(settlementIDs)
            )
            let sourceDeletion = try await repository.preparePermanentDeletion(
                relativePath: relativePath,
                expectedRevision: expectedRevision
            )
            backup = backup.updating(sourceDeletion: .some(sourceDeletion))
            record = try await persist(record: record, backup: backup)

            if let workAssociation, let critiqueBefore {
                let critiqueDeletion = try await repository.preparePermanentDeletion(
                    relativePath: workAssociation.critiqueRelativePath,
                    expectedRevision: critiqueBefore.fingerprint
                )
                backup = backup.updating(critiqueDeletion: .some(critiqueDeletion))
                record = try await persist(record: record, backup: backup)
            }

            let additionalKeys = backup.critiqueDeletion.map {
                [TriptychCheckpointFileKey(area: checkpointArea, relativePath: $0.relativePath)]
            } ?? []
            let checkpointPurge = try await checkpointStore.preparePurgeNoteCopies(
                noteID: noteID,
                area: checkpointArea,
                currentRelativePath: relativePath,
                additionalKeys: additionalKeys
            )
            backup = backup.updating(checkpointPurge: .some(checkpointPurge))
            record = try await persist(record: record, backup: backup)

            if let critiqueDeletion = backup.critiqueDeletion {
                try await repository.applyPreparedPermanentDeletion(critiqueDeletion)
                try faultPlan.trigger(.afterCritiqueDeletion)
            }
            try await repository.applyPreparedPermanentDeletion(sourceDeletion)
            try faultPlan.trigger(.afterSourceDeletion)

            try faultPlan.trigger(.afterDialoguePurge)
            let settlementsByNoteID = Dictionary(
                uniqueKeysWithValues: backup.settlements.map { ($0.noteID, $0) }
            )
            for settlementID in settlementIDs {
                try await portableRecordStore?.purgeSettlement(
                    noteID: settlementID,
                    matching: settlementsByNoteID[settlementID]
                )
            }
            try faultPlan.trigger(.afterSettlementPurge)
            _ = try await critiqueRegistry.purgeAssociations(
                noteID: noteID,
                relativePath: relativePath
            )
            try faultPlan.trigger(.afterCritiqueAssociationPurge)

            try await checkpointStore.applyPreparedCheckpointPurge(checkpointPurge)
            try faultPlan.trigger(.afterCheckpointPurge)
            _ = try await controlStore.purgeIdentity(
                id: noteID,
                vaultID: vaultID,
                relativePath: relativePath
            )
            if let critiqueIdentity = backup.critiqueIdentity {
                _ = try await controlStore.purgeIdentity(
                    id: critiqueIdentity.record.id,
                    vaultID: critiqueIdentity.record.vaultID,
                    relativePath: critiqueIdentity.record.relativePath
                )
            }
            try faultPlan.trigger(.afterIdentityPurge)

            backup = backup.updating(phase: .committing)
            record = try await persist(
                record: record,
                backup: backup,
                failure: "Permanent deletion committed; final privacy cleanup is pending."
            )
            try faultPlan.trigger(.afterCommitDecision)
            try await finalize(record)

            return PermanentDeletionCommit(
                noteID: noteID,
                vaultID: vaultID,
                relativePath: relativePath,
                fingerprint: expectedRevision,
                removedCritiqueDocumentPath: backup.critiqueDeletion?.relativePath,
                removedDialogueIDs: [],
                removedCritiqueAssociationIDs: backup.critiqueAssociations.map(\.id).sorted {
                    $0.uuidString < $1.uuidString
                },
                invalidatedCheckpointIDs: checkpointPurge.checkpointIDs
            )
        } catch let interruption as PermanentDeletionInjectedFailure where interruption.isInterruption {
            let files = await observedFileEvidence(backup)
            record = try await persist(
                record: record,
                backup: backup,
                failure: interruption.localizedDescription,
                files: files
            )
            throw TriptychTransactionError.recoveryRequired(record)
        } catch {
            let latestRecord = makeRecord(
                id: record.id,
                createdAt: record.createdAt,
                failure: record.failure,
                backup: backup,
                files: record.files
            )
            try await rollback(latestRecord, cause: error)
        }
    }

    /// Reconciles durable deletion journals after process interruption. A
    /// rollback-phase journal restores all recoverable state; a commit-phase
    /// journal completes privacy cleanup and removes its recovery copies.
    public func recoverInterruptedTransactions() async throws {
        for record in try await recoveryStore.pending() where record.operation == .permanentDeletion {
            guard let backup = record.permanentDeletionBackup,
                  backup.vaultID == repository.identity.id else { continue }
            switch backup.phase {
            case .rollbackRequired:
                do {
                    try await rollback(record, cause: CocoaError(.userCancelled))
                } catch let error as TriptychTransactionError {
                    if case .transactionRolledBack = error { continue }
                    throw error
                }
            case .committing:
                try await finalize(record)
            }
        }
    }

    private func finalize(_ record: TriptychMutationRecoveryRecord) async throws {
        guard let backup = record.permanentDeletionBackup else {
            throw TriptychTransactionError.invalidPlan("Permanent-deletion recovery data is missing.")
        }
        if let source = backup.sourceDeletion {
            try await repository.finalizePreparedPermanentDeletion(source)
        }
        if let critique = backup.critiqueDeletion {
            try await repository.finalizePreparedPermanentDeletion(critique)
        }
        if let checkpoints = backup.checkpointPurge {
            try await checkpointStore.finalizePreparedCheckpointPurge(checkpoints)
        }
        // Source locators are machine-local privacy state. Remove them only
        // after the deletion commit decision; if cleanup fails, the durable
        // committing journal remains so recovery retries instead of silently
        // claiming the permanent deletion is fully finalized.
        if let sourceAccessStore {
            try await sourceAccessStore.remove(analysisNoteID: backup.noteID)
            if let critiqueNoteID = backup.critiqueNoteID {
                try await sourceAccessStore.remove(analysisNoteID: critiqueNoteID)
            }
        }
        var deletedNoteIDs: Set<UUID> = [backup.noteID]
        if let critiqueNoteID = backup.critiqueNoteID {
            deletedNoteIDs.insert(critiqueNoteID)
        }
        for noteID in deletedNoteIDs {
            try await portableRecordStore?.purgeSettlement(
                noteID: noteID
            )
        }
        try await localExecutionStore?.purgeExecutions(
            containing: deletedNoteIDs
        )
        try await portableRecordStore?.handlePermanentDeletion(
            noteIDs: deletedNoteIDs
        )
        try await recoveryStore.resolve(record.id)
    }

    private func rollback(
        _ record: TriptychMutationRecoveryRecord,
        cause: Error
    ) async throws -> Never {
        guard let backup = record.permanentDeletionBackup else {
            throw TriptychTransactionError.invalidPlan("Permanent-deletion recovery data is missing.")
        }
        var rollbackErrors: [String] = []

        if let source = backup.sourceDeletion {
            do { try await repository.rollbackPreparedPermanentDeletion(source) }
            catch { rollbackErrors.append("\(source.relativePath): \(error.localizedDescription)") }
        }
        if let critique = backup.critiqueDeletion {
            do { try await repository.rollbackPreparedPermanentDeletion(critique) }
            catch { rollbackErrors.append("\(critique.relativePath): \(error.localizedDescription)") }
        }
        if let checkpoints = backup.checkpointPurge {
            do { try await checkpointStore.rollbackPreparedCheckpointPurge(checkpoints) }
            catch { rollbackErrors.append("Checkpoints: \(error.localizedDescription)") }
        }
        for settlement in backup.settlements {
            do { try await portableRecordStore?.restoreSettlement(settlement) }
            catch ResearchRecordStoreV1Error.settlementChanged(_) {
                // A newer researcher-authored Settle state wins. Rollback
                // restores only missing preimages and never overwrites it.
            }
            catch { rollbackErrors.append("Settlement: \(error.localizedDescription)") }
        }
        do { try await critiqueRegistry.restorePurgedAssociations(backup.critiqueAssociations) }
        catch { rollbackErrors.append("Critique: \(error.localizedDescription)") }
        do { try await controlStore.restorePurgedIdentity(backup.identity) }
        catch { rollbackErrors.append("Identity: \(error.localizedDescription)") }
        do { try await controlStore.restorePurgedIdentity(backup.critiqueIdentity) }
        catch { rollbackErrors.append("Critique identity: \(error.localizedDescription)") }

        let files = await observedFileEvidence(backup)
        let filesRestored = files.allSatisfy { $0.state == .restored }
        if filesRestored, rollbackErrors.isEmpty {
            var restoredNoteIDs: Set<UUID> = [backup.noteID]
            if let critiqueNoteID = backup.critiqueNoteID {
                restoredNoteIDs.insert(critiqueNoteID)
            }
            do {
                try await portableRecordStore?.clearNoteDeletionMarkers(
                    noteIDs: restoredNoteIDs
                )
            } catch {
                rollbackErrors.append(
                    "Discussion deletion gate: \(error.localizedDescription)"
                )
            }
        }
        let restored = filesRestored && rollbackErrors.isEmpty
        if restored, rollbackErrors.isEmpty {
            do {
                try await recoveryStore.resolve(record.id)
                throw TriptychTransactionError.transactionRolledBack(cause.localizedDescription)
            } catch let transaction as TriptychTransactionError {
                throw transaction
            } catch {
                let updated = makeRecord(
                    id: record.id,
                    createdAt: record.createdAt,
                    failure: "Rollback restored the files, but its recovery journal could not be removed. \(error.localizedDescription)",
                    backup: backup,
                    files: files
                )
                throw TriptychTransactionError.recoveryPersistenceFailed(updated, error.localizedDescription)
            }
        }

        let detail = ([cause.localizedDescription] + rollbackErrors).joined(separator: "\n")
        let updated = makeRecord(
            id: record.id,
            createdAt: record.createdAt,
            failure: detail,
            backup: backup,
            files: files
        )
        do {
            try await recoveryStore.record(updated)
        } catch {
            throw TriptychTransactionError.recoveryPersistenceFailed(updated, error.localizedDescription)
        }
        throw TriptychTransactionError.recoveryRequired(updated)
    }

    private func persist(
        record: TriptychMutationRecoveryRecord,
        backup: PermanentDeletionRecoveryBackup,
        failure: String? = nil,
        files: [TriptychMutationRecoveryFile]? = nil
    ) async throws -> TriptychMutationRecoveryRecord {
        let updated = makeRecord(
            id: record.id,
            createdAt: record.createdAt,
            failure: failure ?? record.failure,
            backup: backup,
            files: files ?? record.files
        )
        do {
            try await recoveryStore.record(updated)
            return updated
        } catch {
            throw TriptychTransactionError.recoveryPersistenceFailed(updated, error.localizedDescription)
        }
    }

    private func makeRecord(
        id: UUID,
        createdAt: Date,
        failure: String,
        backup: PermanentDeletionRecoveryBackup,
        files: [TriptychMutationRecoveryFile]
    ) -> TriptychMutationRecoveryRecord {
        TriptychMutationRecoveryRecord(
            id: id,
            triptychID: triptychID,
            createdAt: createdAt,
            failure: failure,
            files: files,
            permanentDeletionBackup: backup
        )
    }

    private func initialFileEvidence(
        relativePath: String,
        expectedRevision: DocumentFingerprint,
        critiqueBefore: NoteDocument?
    ) -> [TriptychMutationRecoveryFile] {
        var files = [TriptychMutationRecoveryFile(
            vaultID: repository.identity.id,
            path: relativePath,
            role: .deletedNote,
            beforeRevision: expectedRevision,
            intendedRevision: nil,
            observedRevision: expectedRevision,
            state: .unreadable,
            detail: "A durable recovery version is prepared before this source is removed. Inspect the path after interruption."
        )]
        if let critiqueBefore {
            files.append(TriptychMutationRecoveryFile(
                vaultID: repository.identity.id,
                path: critiqueBefore.relativePath,
                role: .associatedCritique,
                beforeRevision: critiqueBefore.fingerprint,
                intendedRevision: nil,
                observedRevision: critiqueBefore.fingerprint,
                state: .unreadable,
                detail: "Associated Critique Markdown is part of the same deletion transaction."
            ))
        }
        return files
    }

    private func observedFileEvidence(
        _ backup: PermanentDeletionRecoveryBackup
    ) async -> [TriptychMutationRecoveryFile] {
        var result: [TriptychMutationRecoveryFile] = []
        if let source = backup.sourceDeletion {
            result.append(await observe(source, role: .deletedNote))
        } else {
            result.append(TriptychMutationRecoveryFile(
                vaultID: backup.vaultID,
                path: backup.relativePath,
                role: .deletedNote,
                beforeRevision: backup.expectedRevision,
                intendedRevision: nil,
                observedRevision: (try? await repository.load(relativePath: backup.relativePath))?.fingerprint,
                state: .restored,
                detail: "The source was not prepared for removal."
            ))
        }
        if let critique = backup.critiqueDeletion {
            result.append(await observe(critique, role: .associatedCritique))
        }
        return result
    }

    private func observe(
        _ prepared: PreparedPermanentDeletion,
        role: TriptychMutationFileRole
    ) async -> TriptychMutationRecoveryFile {
        let observed = try? await repository.load(relativePath: prepared.relativePath)
        let state: TriptychMutationRecoveryState
        if observed?.fingerprint == prepared.fingerprint {
            state = .restored
        } else if observed == nil {
            state = .missing
        } else {
            state = .externallyChanged
        }
        return TriptychMutationRecoveryFile(
            vaultID: repository.identity.id,
            path: prepared.relativePath,
            role: role,
            beforeRevision: prepared.fingerprint,
            intendedRevision: nil,
            observedRevision: observed?.fingerprint,
            state: state,
            detail: state == .restored
                ? "Exact pre-deletion bytes are present."
                : "The committed recovery version remains in Note History until recovery is resolved."
        )
    }

    private func requireHealthyStores() async throws {
        if let error = await critiqueRegistry.healthError() {
            throw ResearchRecordStoreError.unreadableStore(kind: "Critique", reason: error)
        }
        guard let portableRecordStore else { return }
        var issues = try await portableRecordStore.activeDiscussions().issues
        for location in PortableResearchRecordLocation.allCases {
            issues += try await portableRecordStore.listing(location: location).issues
        }
        issues += try await portableRecordStore.settlementListing().issues
        guard issues.isEmpty else {
            let reason = issues.map { "\($0.id): \($0.reason)" }.joined(separator: "; ")
            throw ResearchRecordStoreError.unreadableStore(
                kind: "Portable Research Record",
                reason: reason
            )
        }
    }
}
