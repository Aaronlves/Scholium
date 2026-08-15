import Foundation
import ScholiumContracts

enum PermanentDeletionFaultPoint: Hashable, Sendable {
    case afterCritiqueDeletion
    case afterSourceDeletion
    case afterSettlementPurge
    case afterCritiqueAssociationPurge
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

/// Coordinates permanent deletion as one durable, monotonic cleanup plan.
/// Once a source has been deleted it is never recreated. Interrupted work is
/// resumed idempotently from the plan until source and private state are gone.
public actor NotePermanentDeletionCoordinator {
    private let triptychID: UUID
    private let repository: VaultRepository
    private let critiqueRegistry: CritiqueRegistry
    private let controlStore: TriptychControlStore
    private let recoveryStore: TriptychMutationRecoveryStore
    private let sourceAccessStore: ResearchSourceAccessStore?
    private let portableRecordStore: PortableResearchRecordStore?
    private let localExecutionStore: LocalResearchExecutionStore?
    private let agentChangeEvidenceStore: AgentChangeEvidenceStore?
    private let faultPlan: PermanentDeletionFaultPlan

    public init(
        triptychID: UUID,
        repository: VaultRepository,
        critiqueRegistry: CritiqueRegistry,
        controlStore: TriptychControlStore,
        recoveryStore: TriptychMutationRecoveryStore,
        sourceAccessStore: ResearchSourceAccessStore? = nil,
        portableRecordStore: PortableResearchRecordStore? = nil,
        localExecutionStore: LocalResearchExecutionStore? = nil,
        agentChangeEvidenceStore: AgentChangeEvidenceStore? = nil
    ) {
        self.triptychID = triptychID
        self.repository = repository
        self.critiqueRegistry = critiqueRegistry
        self.controlStore = controlStore
        self.recoveryStore = recoveryStore
        self.sourceAccessStore = sourceAccessStore
        self.portableRecordStore = portableRecordStore
        self.localExecutionStore = localExecutionStore
        self.agentChangeEvidenceStore = agentChangeEvidenceStore
        faultPlan = .none
    }

    init(
        triptychID: UUID,
        repository: VaultRepository,
        critiqueRegistry: CritiqueRegistry,
        controlStore: TriptychControlStore,
        recoveryStore: TriptychMutationRecoveryStore,
        sourceAccessStore: ResearchSourceAccessStore? = nil,
        portableRecordStore: PortableResearchRecordStore? = nil,
        localExecutionStore: LocalResearchExecutionStore? = nil,
        agentChangeEvidenceStore: AgentChangeEvidenceStore? = nil,
        faultPlan: PermanentDeletionFaultPlan
    ) {
        self.triptychID = triptychID
        self.repository = repository
        self.critiqueRegistry = critiqueRegistry
        self.controlStore = controlStore
        self.recoveryStore = recoveryStore
        self.sourceAccessStore = sourceAccessStore
        self.portableRecordStore = portableRecordStore
        self.localExecutionStore = localExecutionStore
        self.agentChangeEvidenceStore = agentChangeEvidenceStore
        self.faultPlan = faultPlan
    }

    public func delete(
        noteID: UUID,
        vaultID: UUID,
        relativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> PermanentDeletionCommit {
        try await requireHealthyStores()
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
        guard try await controlStore.identityRecord(
            vaultID: vaultID,
            relativePath: relativePath
        )?.id == noteID else {
            throw TriptychTransactionError.invalidPlan(
                "The permanent-deletion source no longer matches its stable Note identity."
            )
        }

        let associations = await critiqueRegistry.associationsRelated(
            noteID: noteID,
            relativePath: relativePath
        )
        let workAssociation = associations.first {
            $0.workNoteID == noteID && $0.workRelativePath == relativePath
        }
        let critique: PermanentDeletionTarget?
        if let workAssociation {
            guard workAssociation.critiqueRelativePath != relativePath else {
                throw TriptychTransactionError.invalidPlan(
                    "A Work and its associated Critique cannot use the same path."
                )
            }
            let document = try await repository.load(
                relativePath: workAssociation.critiqueRelativePath
            )
            guard let identity = try await controlStore.identityRecord(
                vaultID: vaultID,
                relativePath: workAssociation.critiqueRelativePath
            ) else {
                throw TriptychTransactionError.invalidPlan(
                    "The associated Critique has no stable identity."
                )
            }
            critique = PermanentDeletionTarget(
                noteID: identity.id,
                relativePath: document.relativePath,
                expectedRevision: document.fingerprint
            )
        } else {
            critique = nil
        }
        let plan = PermanentDeletionPlan(
            noteID: noteID,
            vaultID: vaultID,
            relativePath: relativePath,
            expectedRevision: expectedRevision,
            critique: critique,
            critiqueAssociations: associations
        )
        let record = makeRecord(
            id: UUID(),
            createdAt: Date(),
            failure: "Permanent deletion is pending.",
            plan: plan,
            files: await observedFiles(plan)
        )
        do {
            try await recoveryStore.record(record)
        } catch {
            throw TriptychTransactionError.recoveryPersistenceFailed(
                record,
                error.localizedDescription
            )
        }
        return try await perform(record)
    }

    public func recoverInterruptedTransactions() async throws {
        for record in try await recoveryStore.pending()
        where record.operation == .permanentDeletion {
            guard record.permanentDeletionPlan?.vaultID == repository.identity.id else {
                continue
            }
            _ = try await perform(record)
        }
    }

    private func perform(
        _ record: TriptychMutationRecoveryRecord
    ) async throws -> PermanentDeletionCommit {
        guard let plan = record.permanentDeletionPlan,
              plan.vaultID == repository.identity.id else {
            throw TriptychTransactionError.invalidPlan(
                "Permanent-deletion recovery data is missing or belongs to another vault."
            )
        }
        do {
            try await portableRecordStore?.markNoteDeletionStarted(
                noteIDs: plan.deletedNoteIDs
            )
            if let critique = plan.critique {
                try await deleteIfPresent(critique)
                try faultPlan.trigger(.afterCritiqueDeletion)
            }
            try await deleteIfPresent(PermanentDeletionTarget(
                noteID: plan.noteID,
                relativePath: plan.relativePath,
                expectedRevision: plan.expectedRevision
            ))
            try faultPlan.trigger(.afterSourceDeletion)

            for noteID in plan.deletedNoteIDs {
                try await portableRecordStore?.purgeSettlement(noteID: noteID)
            }
            try faultPlan.trigger(.afterSettlementPurge)
            _ = try await critiqueRegistry.purgeAssociations(
                noteID: plan.noteID,
                relativePath: plan.relativePath
            )
            try faultPlan.trigger(.afterCritiqueAssociationPurge)

            _ = try await controlStore.purgeIdentityPermanently(
                id: plan.noteID,
                vaultID: plan.vaultID,
                relativePath: plan.relativePath
            )
            if let critique = plan.critique {
                _ = try await controlStore.purgeIdentityPermanently(
                    id: critique.noteID,
                    vaultID: plan.vaultID,
                    relativePath: critique.relativePath
                )
            }
            try faultPlan.trigger(.afterIdentityPurge)
            try faultPlan.trigger(.afterCommitDecision)

            for noteID in plan.deletedNoteIDs {
                try await sourceAccessStore?.remove(analysisNoteID: noteID)
            }
            try await localExecutionStore?.purgeExecutions(
                containing: plan.deletedNoteIDs
            )
            for noteID in plan.deletedNoteIDs {
                try await agentChangeEvidenceStore?.removeEvidence(noteID: noteID)
            }
            try await portableRecordStore?.handlePermanentDeletion(
                noteIDs: plan.deletedNoteIDs
            )
            try await recoveryStore.resolve(record)
            return PermanentDeletionCommit(
                noteID: plan.noteID,
                vaultID: plan.vaultID,
                relativePath: plan.relativePath,
                fingerprint: plan.expectedRevision,
                removedCritiqueDocumentPath: plan.critique?.relativePath,
                removedDialogueIDs: [],
                removedCritiqueAssociationIDs: plan.critiqueAssociations
                    .map(\.id)
                    .sorted { $0.uuidString < $1.uuidString }
            )
        } catch {
            let updated = makeRecord(
                id: record.id,
                createdAt: record.createdAt,
                failure: error.localizedDescription,
                plan: plan,
                files: await observedFiles(plan)
            )
            do {
                try await recoveryStore.record(updated)
            } catch {
                throw TriptychTransactionError.recoveryPersistenceFailed(
                    updated,
                    error.localizedDescription
                )
            }
            throw TriptychTransactionError.recoveryRequired(updated)
        }
    }

    private func deleteIfPresent(_ target: PermanentDeletionTarget) async throws {
        let document: NoteDocument
        do {
            document = try await repository.load(relativePath: target.relativePath)
        } catch VaultRepositoryError.fileDoesNotExist {
            return
        }
        guard document.fingerprint == target.expectedRevision else {
            throw VaultRepositoryError.conflict(
                expected: target.expectedRevision,
                current: document.fingerprint
            )
        }
        do {
            _ = try await repository.deletePermanently(
                relativePath: target.relativePath,
                expectedRevision: target.expectedRevision
            )
        } catch {
            do {
                _ = try await repository.load(relativePath: target.relativePath)
                throw error
            } catch VaultRepositoryError.fileDoesNotExist {
                return
            }
        }
    }

    private func observedFiles(
        _ plan: PermanentDeletionPlan
    ) async -> [TriptychMutationRecoveryFile] {
        var files = [await observedFile(
            path: plan.relativePath,
            revision: plan.expectedRevision,
            role: .deletedNote
        )]
        if let critique = plan.critique {
            files.append(await observedFile(
                path: critique.relativePath,
                revision: critique.expectedRevision,
                role: .associatedCritique
            ))
        }
        return files
    }

    private func observedFile(
        path: String,
        revision: DocumentFingerprint,
        role: TriptychMutationFileRole
    ) async -> TriptychMutationRecoveryFile {
        do {
            let document = try await repository.load(relativePath: path)
            let state: TriptychMutationRecoveryState = document.fingerprint == revision
                ? .restored
                : .externallyChanged
            return TriptychMutationRecoveryFile(
                vaultID: repository.identity.id,
                path: path,
                role: role,
                beforeRevision: revision,
                intendedRevision: nil,
                observedRevision: document.fingerprint,
                state: state,
                detail: state == .restored
                    ? "The exact planned source is still present and will be deleted on retry."
                    : "The source changed after deletion was planned; cleanup will not delete it."
            )
        } catch VaultRepositoryError.fileDoesNotExist {
            return TriptychMutationRecoveryFile(
                vaultID: repository.identity.id,
                path: path,
                role: role,
                beforeRevision: revision,
                intendedRevision: nil,
                observedRevision: nil,
                state: .missing,
                detail: "The source is deleted; remaining privacy cleanup will continue without restoring it."
            )
        } catch {
            return TriptychMutationRecoveryFile(
                vaultID: repository.identity.id,
                path: path,
                role: role,
                beforeRevision: revision,
                intendedRevision: nil,
                observedRevision: nil,
                state: .unreadable,
                detail: "The source could not be verified: \(error.localizedDescription)"
            )
        }
    }

    private func makeRecord(
        id: UUID,
        createdAt: Date,
        failure: String,
        plan: PermanentDeletionPlan,
        files: [TriptychMutationRecoveryFile]
    ) -> TriptychMutationRecoveryRecord {
        TriptychMutationRecoveryRecord(
            id: id,
            triptychID: triptychID,
            createdAt: createdAt,
            failure: failure,
            files: files,
            permanentDeletionPlan: plan
        )
    }

    private func requireHealthyStores() async throws {
        if let error = await critiqueRegistry.healthError() {
            throw ResearchRecordStoreError.unreadableStore(
                kind: "Critique",
                reason: error
            )
        }
        guard let portableRecordStore else { return }
        var issues = try await portableRecordStore.activeDiscussions().issues
        issues += try await portableRecordStore.listing().issues
        issues += try await portableRecordStore.settlementListing().issues
        guard issues.isEmpty else {
            let reason = issues.map { "\($0.id): \($0.reason)" }
                .joined(separator: "; ")
            throw ResearchRecordStoreError.unreadableStore(
                kind: "Portable Research Record",
                reason: reason
            )
        }
    }
}
