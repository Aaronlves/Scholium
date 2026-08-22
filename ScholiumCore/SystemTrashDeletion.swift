import Foundation
import ScholiumContracts

enum SystemTrashDeletionFaultPoint: Hashable, Sendable {
    case afterPlanPersistence
    case afterSystemTrashMoveBeforeReceipt
    case afterSourceReceipts
    case afterDiscussionRemoval
    case afterRecordDeletion
    case afterExecutionCleanup
}

struct SystemTrashDeletionFaultPlan: Sendable {
    let failures: Set<SystemTrashDeletionFaultPoint>
    let interruptions: Set<SystemTrashDeletionFaultPoint>

    static let none = Self(failures: [], interruptions: [])

    func trigger(_ point: SystemTrashDeletionFaultPoint) throws {
        if interruptions.contains(point) {
            throw InjectedSystemTrashDeletionFailure(point: point, isInterruption: true)
        }
        if failures.contains(point) {
            throw InjectedSystemTrashDeletionFailure(point: point, isInterruption: false)
        }
    }
}

private struct InjectedSystemTrashDeletionFailure: LocalizedError, Sendable {
    let point: SystemTrashDeletionFaultPoint
    let isInterruption: Bool

    var errorDescription: String? {
        "Injected system-Trash deletion \(isInterruption ? "interruption" : "failure") at \(String(describing: point))."
    }
}

/// Coordinates one researcher-confirmed cutover without claiming atomicity
/// across Finder's system Trash and portable Research Record storage. Files
/// move first. Record deletion is then idempotently resumed forward.
public actor NoteSystemTrashDeletionCoordinator {
    private let triptychID: UUID
    private let repository: VaultRepository
    private let critiqueRegistry: CritiqueRegistry
    private let controlStore: TriptychControlStore
    private let recoveryStore: TriptychMutationRecoveryStore
    private let portableRecordStore: PortableResearchRecordStore
    private let localExecutionStore: LocalResearchExecutionStore?
    private let agentChangeEvidenceStore: AgentChangeEvidenceStore?
    private let faultPlan: SystemTrashDeletionFaultPlan

    public init(
        triptychID: UUID,
        repository: VaultRepository,
        critiqueRegistry: CritiqueRegistry,
        controlStore: TriptychControlStore,
        recoveryStore: TriptychMutationRecoveryStore,
        portableRecordStore: PortableResearchRecordStore,
        localExecutionStore: LocalResearchExecutionStore? = nil,
        agentChangeEvidenceStore: AgentChangeEvidenceStore? = nil
    ) {
        self.triptychID = triptychID
        self.repository = repository
        self.critiqueRegistry = critiqueRegistry
        self.controlStore = controlStore
        self.recoveryStore = recoveryStore
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
        portableRecordStore: PortableResearchRecordStore,
        localExecutionStore: LocalResearchExecutionStore? = nil,
        agentChangeEvidenceStore: AgentChangeEvidenceStore? = nil,
        faultPlan: SystemTrashDeletionFaultPlan
    ) {
        self.triptychID = triptychID
        self.repository = repository
        self.critiqueRegistry = critiqueRegistry
        self.controlStore = controlStore
        self.recoveryStore = recoveryStore
        self.portableRecordStore = portableRecordStore
        self.localExecutionStore = localExecutionStore
        self.agentChangeEvidenceStore = agentChangeEvidenceStore
        self.faultPlan = faultPlan
    }

    public func prepareNote(
        noteID: UUID,
        vaultID: UUID,
        relativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> SystemTrashDeletionPreview {
        try await requireHealthyStores()
        guard repository.identity.id == vaultID else {
            throw TriptychTransactionError.invalidPlan(
                "The system-Trash repository does not match the selected vault identity."
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
                "The selected source no longer matches its stable Note identity."
            )
        }

        let noteTarget = SystemTrashDeletionNoteTarget(
            noteID: noteID,
            relativePath: relativePath,
            expectedRevision: expectedRevision
        )
        var sources = [SystemTrashDeletionSourceTarget(
            vaultID: vaultID,
            relativePath: relativePath,
            kind: .note,
            notes: [noteTarget]
        )]
        let associations = await critiqueRegistry.associationsRelated(
            noteID: noteID,
            relativePath: relativePath
        )
        if let association = associations.first(where: {
            $0.workNoteID == noteID && $0.workRelativePath == relativePath
        }), association.critiqueRelativePath != relativePath {
            let critique = try await repository.load(
                relativePath: association.critiqueRelativePath
            )
            guard let identity = try await controlStore.identityRecord(
                vaultID: vaultID,
                relativePath: critique.relativePath
            ) else {
                throw TriptychTransactionError.invalidPlan(
                    "The associated Critique has no stable identity."
                )
            }
            sources.append(SystemTrashDeletionSourceTarget(
                vaultID: vaultID,
                relativePath: critique.relativePath,
                kind: .note,
                notes: [SystemTrashDeletionNoteTarget(
                    noteID: identity.id,
                    relativePath: critique.relativePath,
                    expectedRevision: critique.fingerprint
                )]
            ))
        }
        return try await makePreview(sources: sources)
    }

    public func prepareFolder(
        vaultID: UUID,
        relativePath: String
    ) async throws -> SystemTrashDeletionPreview {
        try await requireHealthyStores()
        guard repository.identity.id == vaultID,
              let folder = try? VaultRelativeFolderPath(relativePath),
              try await repository.folderRelativePaths().contains(folder) else {
            throw TriptychTransactionError.invalidPlan(
                "The selected folder is no longer an ordinary contained vault folder."
            )
        }
        let prefix = folder.rawValue + "/"
        let paths = try await repository.markdownRelativePaths()
            .filter { $0.hasPrefix(prefix) }
        var noteTargets: [SystemTrashDeletionNoteTarget] = []
        for path in paths {
            let document = try await repository.load(relativePath: path)
            guard let identity = try await controlStore.identityRecord(
                vaultID: vaultID,
                relativePath: path
            ) else {
                throw TriptychTransactionError.invalidPlan(
                    "The folder descendant \(path) has no stable identity."
                )
            }
            noteTargets.append(SystemTrashDeletionNoteTarget(
                noteID: identity.id,
                relativePath: path,
                expectedRevision: document.fingerprint
            ))
        }
        var sources = [SystemTrashDeletionSourceTarget(
            vaultID: vaultID,
            relativePath: relativePath,
            kind: .folder,
            notes: noteTargets,
            expectedDirectoryManifest: try await repository
                .systemTrashDirectoryManifest(relativePath: relativePath)
        )]

        // A Work's managed Critique may sit outside the selected folder. Keep
        // that explicit second system operation rather than silently orphaning
        // the association or pretending the two moves are atomic.
        var extraCritiquePaths: Set<String> = []
        for note in noteTargets {
            let associations = await critiqueRegistry.associationsRelated(
                noteID: note.noteID,
                relativePath: note.relativePath
            )
            for association in associations where association.workNoteID == note.noteID {
                let path = association.critiqueRelativePath
                guard !path.hasPrefix(prefix), extraCritiquePaths.insert(path).inserted else {
                    continue
                }
                let document = try await repository.load(relativePath: path)
                guard let identity = try await controlStore.identityRecord(
                    vaultID: vaultID,
                    relativePath: path
                ) else {
                    throw TriptychTransactionError.invalidPlan(
                        "The associated Critique \(path) has no stable identity."
                    )
                }
                sources.append(SystemTrashDeletionSourceTarget(
                    vaultID: vaultID,
                    relativePath: path,
                    kind: .note,
                    notes: [SystemTrashDeletionNoteTarget(
                        noteID: identity.id,
                        relativePath: path,
                        expectedRevision: document.fingerprint
                    )]
                ))
            }
        }
        return try await makePreview(sources: sources)
    }

    public func moveToSystemTrash(
        _ preview: SystemTrashDeletionPreview
    ) async throws -> SystemTrashDeletionCommit {
        try await requireHealthyStores()
        guard preview.triptychID == triptychID,
              preview.sources.allSatisfy({ $0.vaultID == repository.identity.id }) else {
            throw TriptychTransactionError.invalidPlan(
                "The prepared system-Trash operation belongs to another Triptych or vault."
            )
        }
        try await validate(preview)
        let plan = SystemTrashDeletionPlan(preview: preview)
        let record = await makeRecord(
            plan: plan,
            failure: "The system-Trash operation is pending."
        )
        do {
            try await recoveryStore.record(record)
        } catch {
            throw TriptychTransactionError.recoveryPersistenceFailed(
                record,
                error.localizedDescription
            )
        }
        try faultPlan.trigger(.afterPlanPersistence)
        return try await perform(record)
    }

    @discardableResult
    public func recoverInterruptedTransactions() async throws -> [SystemTrashDeletionCommit] {
        var commits: [SystemTrashDeletionCommit] = []
        for record in try await recoveryStore.pending()
        where record.operation == .systemTrashDeletion {
            guard record.systemTrashDeletionPlan?.preview.sources.allSatisfy({
                $0.vaultID == repository.identity.id
            }) == true else { continue }
            commits.append(try await perform(record))
        }
        return commits
    }

    /// Resolves only the irreducible native-Trash uncertainty case. This is
    /// deliberately not an automatic recovery path: Finder owns the source
    /// item, while Scholium explicitly retains every associated Record and
    /// releases only the short-lived deletion gate after researcher review.
    public func retainRecordsForUnknownOutcome(
        recoveryRecordID: UUID
    ) async throws {
        guard let record = try await recoveryStore.pending().first(where: {
            $0.id == recoveryRecordID && $0.operation == .systemTrashDeletion
        }), let plan = record.systemTrashDeletionPlan else {
            throw TriptychTransactionError.invalidPlan(
                "The selected system-Trash recovery record is unavailable."
            )
        }
        try validatePlanShape(plan, recoveryRecord: record)
        guard plan.sourceReceipts.contains(where: { $0.progress == .outcomeUnknown }),
              plan.deletedRecordIDs.isEmpty,
              plan.removedDiscussionIDs.isEmpty else {
            throw TriptychTransactionError.invalidPlan(
                "Records can be retained only before any Discussion or Record cleanup committed and when a native Trash result is unknown."
            )
        }
        try await portableRecordStore.clearNoteDeletionGate(
            noteIDs: plan.affectedNoteIDs
        )
        try await recoveryStore.resolve(record)
    }

    private func makePreview(
        sources: [SystemTrashDeletionSourceTarget]
    ) async throws -> SystemTrashDeletionPreview {
        let noteIDs = Set(sources.flatMap(\.notes).map(\.noteID))
        try await requireNoActiveExecutions(noteIDs: noteIDs)
        let recordListing = try await portableRecordStore.listing()
        let discussions = try await portableRecordStore.activeDiscussions()
        guard recordListing.issues.isEmpty, discussions.issues.isEmpty else {
            throw ResearchRecordStoreError.unreadableStore(
                kind: "Portable Research Record",
                reason: (recordListing.issues + discussions.issues)
                    .map { "\($0.id): \($0.reason)" }
                    .joined(separator: "; ")
            )
        }
        let records = recordListing.revisions.compactMap { revision
            -> SystemTrashDeletionRecordTarget? in
            let participants = Set(revision.record.participatingNotes.map(\.noteID))
            guard !participants.isDisjoint(with: noteIDs) else { return nil }
            let unaffected = revision.record.participatingNotes.compactMap { participant
                -> SystemTrashDeletionRecordParticipant? in
                guard !noteIDs.contains(participant.noteID) else { return nil }
                return SystemTrashDeletionRecordParticipant(
                    noteID: participant.noteID,
                    title: participant.title,
                    relativePath: participant.note.relativePath
                )
            }
            return SystemTrashDeletionRecordTarget(
                id: revision.id,
                title: revision.record.title.value,
                fingerprint: revision.fingerprint,
                participantNoteIDs: Array(participants),
                unaffectedParticipants: unaffected
            )
        }
        let activeDiscussionIDs = discussions.discussions.filter {
            !Set($0.participatingNotes.map(\.noteID)).isDisjoint(with: noteIDs)
        }.map(\.id)
        return SystemTrashDeletionPreview(
            triptychID: triptychID,
            sources: sources,
            records: records,
            activeDiscussionIDs: activeDiscussionIDs
        )
    }

    private func validate(_ preview: SystemTrashDeletionPreview) async throws {
        try validatePreviewShape(preview)
        try await requireNoActiveExecutions(noteIDs: preview.affectedNoteIDs)
        for source in preview.sources {
            switch source.kind {
            case .note:
                guard source.notes.count == 1, let note = source.notes.first,
                      note.relativePath == source.relativePath else {
                    throw TriptychTransactionError.invalidPlan(
                        "A Note system-Trash source has an invalid inventory."
                    )
                }
                try await repository.preflightSystemTrashNote(
                    relativePath: note.relativePath,
                    expectedRevision: note.expectedRevision,
                    bindingID: source.id
                )
            case .folder:
                let expected = Dictionary(uniqueKeysWithValues: source.notes.map {
                    ($0.relativePath, $0.expectedRevision)
                })
                _ = try await repository.moveFolderToSystemTrashPreflight(
                    relativePath: source.relativePath,
                    expectedDocuments: expected,
                    expectedDirectoryManifest: try requiredDirectoryManifest(source),
                    bindingID: source.id
                )
            }
            for note in source.notes {
                guard try await controlStore.identityRecord(
                    vaultID: source.vaultID,
                    relativePath: note.relativePath
                )?.id == note.noteID else {
                    throw TriptychTransactionError.invalidPlan(
                        "Stable identity changed for \(note.relativePath)."
                    )
                }
            }
        }
        let listing = try await portableRecordStore.listing()
        guard listing.issues.isEmpty else {
            throw ResearchRecordStoreError.unreadableStore(
                kind: "Portable Research Record",
                reason: listing.issues.map(\.reason).joined(separator: "; ")
            )
        }
        let expectedByID = Dictionary(uniqueKeysWithValues: preview.records.map {
            ($0.id, $0.fingerprint)
        })
        let current = listing.revisions.filter { revision in
            !Set(revision.record.participatingNotes.map(\.noteID))
                .isDisjoint(with: preview.affectedNoteIDs)
        }
        guard current.count == expectedByID.count,
              current.allSatisfy({ expectedByID[$0.id] == $0.fingerprint }) else {
            throw TriptychTransactionError.preflightFailed(
                note: nil,
                detail: "Associated finished Research Records changed after confirmation."
            )
        }
        let discussions = try await portableRecordStore.activeDiscussions()
        guard discussions.issues.isEmpty else {
            throw ResearchRecordStoreError.unreadableStore(
                kind: "Portable Research Discussion",
                reason: discussions.issues.map(\.reason).joined(separator: "; ")
            )
        }
        let currentDiscussionIDs = Set(discussions.discussions.filter {
            !Set($0.participatingNotes.map(\.noteID))
                .isDisjoint(with: preview.affectedNoteIDs)
        }.map(\.id))
        guard currentDiscussionIDs == Set(preview.activeDiscussionIDs) else {
            throw TriptychTransactionError.preflightFailed(
                note: nil,
                detail: "Active Discussion participation changed after confirmation."
            )
        }
    }

    private func perform(
        _ record: TriptychMutationRecoveryRecord
    ) async throws -> SystemTrashDeletionCommit {
        guard var plan = record.systemTrashDeletionPlan else {
            throw TriptychTransactionError.invalidPlan(
                "System-Trash recovery data is missing."
            )
        }
        try validatePlanShape(plan, recoveryRecord: record)
        do {
            try await portableRecordStore.markNoteDeletionStarted(
                noteIDs: plan.affectedNoteIDs
            )
            if plan.sourceReceipts.allSatisfy({ $0.progress == .pending }),
               plan.deletedRecordIDs.isEmpty,
               plan.removedDiscussionIDs.isEmpty {
                // The durable plan precedes the gate so a crash cannot strand
                // an unowned gate. Revalidate after installing the gate to
                // close the Record/Discussion race before the first native
                // filesystem move.
                try await validate(plan.preview)
            }
            for source in plan.preview.sources {
                guard let receipt = plan.sourceReceipts.first(where: {
                    $0.targetID == source.id
                }) else {
                    throw TriptychTransactionError.invalidPlan(
                        "A system-Trash source receipt is missing."
                    )
                }
                switch receipt.progress {
                case .movedToSystemTrash:
                    continue
                case .outcomeUnknown:
                    throw TriptychTransactionError.invalidPlan(
                        "The system Trash result for \(source.relativePath) is unknown. Restore the exact item to its original path before retrying, or retain the associated Records."
                    )
                case .pending:
                    break
                }

                var resultingURL: URL?
                do {
                    switch source.kind {
                    case .note:
                        guard let note = source.notes.first else {
                            throw TriptychTransactionError.invalidPlan(
                                "A Note system-Trash source has no exact Note target."
                            )
                        }
                        resultingURL = try await repository.moveToSystemTrash(
                            relativePath: note.relativePath,
                            expectedRevision: note.expectedRevision,
                            bindingID: source.id
                        )
                    case .folder:
                        resultingURL = try await repository.moveFolderToSystemTrash(
                            relativePath: source.relativePath,
                            expectedDirectoryManifest: try requiredDirectoryManifest(source),
                            bindingID: source.id
                        )
                    }
                    try faultPlan.trigger(.afterSystemTrashMoveBeforeReceipt)
                } catch {
                    let nativeOutcomeUnknown = error is SystemTrashMoveError
                    let bindingExists = (try? await repository.systemTrashBindingExists(
                        relativePath: source.relativePath,
                        kind: source.kind,
                        bindingID: source.id
                    )) ?? true
                    let sourceIsAbsent: Bool
                    switch source.kind {
                    case .note:
                        sourceIsAbsent = (try? await repository.load(
                            relativePath: source.relativePath
                        )) == nil
                    case .folder:
                        sourceIsAbsent = !(await repository.folderExistsForDeletion(
                            relativePath: source.relativePath
                        ))
                    }
                    let unknown = nativeOutcomeUnknown || (sourceIsAbsent && !bindingExists)
                    if unknown {
                        plan = replacingReceipt(
                            in: plan,
                            targetID: source.id,
                            progress: .outcomeUnknown,
                            resultingTrashPath: (error as? SystemTrashMoveError)
                                .flatMap { moveError in
                                    if case .outcomeUnknown(let url, _) = moveError {
                                        return url?.path
                                    }
                                    return nil
                                } ?? resultingURL?.path
                        )
                        try await persist(plan, replacing: record, failure: error.localizedDescription)
                    }
                    throw error
                }
                plan = replacingReceipt(
                    in: plan,
                    targetID: source.id,
                    progress: .movedToSystemTrash,
                    resultingTrashPath: resultingURL?.path
                )
                try await persist(
                    plan,
                    replacing: record,
                    failure: "System Trash completed; associated Research Record cleanup is pending."
                )
            }
            try faultPlan.trigger(.afterSourceReceipts)

            let removedDiscussions = try await portableRecordStore
                .discardActiveDiscussions(noteIDs: plan.affectedNoteIDs)
            plan = SystemTrashDeletionPlan(
                preview: plan.preview,
                sourceReceipts: plan.sourceReceipts,
                deletedRecordIDs: plan.deletedRecordIDs,
                removedDiscussionIDs: Array(Set(plan.removedDiscussionIDs + removedDiscussions))
            )
            try await persist(plan, replacing: record, failure: "Research Record cleanup is pending.")
            try faultPlan.trigger(.afterDiscussionRemoval)

            for target in plan.preview.records where !plan.deletedRecordIDs.contains(target.id) {
                do {
                    _ = try await portableRecordStore.deletePermanently(
                        id: target.id,
                        expectedFingerprint: target.fingerprint
                    )
                } catch ResearchRecordStoreV1Error.recordNotFound {
                    guard await portableRecordStore.isRecordPermanentlyDeleted(id: target.id) else {
                        throw ResearchRecordStoreV1Error.recordNotFound(target.id)
                    }
                }
                try await portableRecordStore.removeNoteReviewActivities(
                    recordIDs: [target.id]
                )
                plan = SystemTrashDeletionPlan(
                    preview: plan.preview,
                    sourceReceipts: plan.sourceReceipts,
                    deletedRecordIDs: Array(Set(plan.deletedRecordIDs + [target.id])),
                    removedDiscussionIDs: plan.removedDiscussionIDs
                )
                try await persist(plan, replacing: record, failure: "Research Record cleanup is pending.")
            }
            try faultPlan.trigger(.afterRecordDeletion)

            try await localExecutionStore?.purgeExecutions(containing: plan.affectedNoteIDs)
            for noteID in plan.affectedNoteIDs {
                try await agentChangeEvidenceStore?.removeEvidence(noteID: noteID)
            }
            try faultPlan.trigger(.afterExecutionCleanup)
            try await portableRecordStore.clearNoteDeletionGate(noteIDs: plan.affectedNoteIDs)

            let completedRecord = await makeRecord(
                plan: plan,
                failure: "System Trash and associated Research Record cleanup completed."
            )
            try await recoveryStore.record(completedRecord)
            try await recoveryStore.resolve(completedRecord)
            return SystemTrashDeletionCommit(
                planID: plan.id,
                noteIDs: Array(plan.affectedNoteIDs),
                deletedRecordIDs: plan.deletedRecordIDs,
                removedDiscussionIDs: plan.removedDiscussionIDs,
                originalRelativePaths: plan.preview.sources.map(\.relativePath),
                resultingTrashPaths: plan.sourceReceipts.compactMap(\.resultingTrashPath)
            )
        } catch {
            let updated = await makeRecord(
                plan: plan,
                failure: error.localizedDescription
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

    private func replacingReceipt(
        in plan: SystemTrashDeletionPlan,
        targetID: UUID,
        progress: SystemTrashDeletionSourceProgress,
        resultingTrashPath: String?
    ) -> SystemTrashDeletionPlan {
        SystemTrashDeletionPlan(
            preview: plan.preview,
            sourceReceipts: plan.sourceReceipts.map { receipt in
                guard receipt.targetID == targetID else { return receipt }
                return SystemTrashDeletionSourceReceipt(
                    targetID: targetID,
                    progress: progress,
                    resultingTrashPath: resultingTrashPath
                )
            },
            deletedRecordIDs: plan.deletedRecordIDs,
            removedDiscussionIDs: plan.removedDiscussionIDs
        )
    }

    private func requiredDirectoryManifest(
        _ source: SystemTrashDeletionSourceTarget
    ) throws -> DocumentFingerprint {
        guard let manifest = source.expectedDirectoryManifest else {
            throw TriptychTransactionError.invalidPlan(
                "A folder system-Trash source has no complete inventory fingerprint."
            )
        }
        return manifest
    }

    private func validatePreviewShape(
        _ preview: SystemTrashDeletionPreview
    ) throws {
        let sourceIDs = preview.sources.map(\.id)
        let sourcePaths = preview.sources.map(\.relativePath)
        let noteTargets = preview.sources.flatMap(\.notes)
        let noteIDs = noteTargets.map(\.noteID)
        let notePaths = noteTargets.map(\.relativePath)
        let recordIDs = preview.records.map(\.id)
        let discussionIDs = preview.activeDiscussionIDs
        guard !preview.sources.isEmpty,
              Set(sourceIDs).count == sourceIDs.count,
              Set(sourcePaths).count == sourcePaths.count,
              Set(noteIDs).count == noteIDs.count,
              Set(notePaths).count == notePaths.count,
              Set(recordIDs).count == recordIDs.count,
              Set(discussionIDs).count == discussionIDs.count else {
            throw TriptychTransactionError.invalidPlan(
                "System-Trash source, Note, Record, and Discussion identities must be unique."
            )
        }
        for source in preview.sources {
            let participantIDs = source.notes.map(\.noteID)
            let participantPaths = source.notes.map(\.relativePath)
            let sourceShapeIsValid = switch source.kind {
            case .note:
                source.notes.count == 1
                    && source.notes.first?.relativePath == source.relativePath
                    && source.expectedDirectoryManifest == nil
            case .folder:
                !source.notes.isEmpty
                    && source.expectedDirectoryManifest != nil
                    && source.notes.allSatisfy {
                        $0.relativePath.hasPrefix(source.relativePath + "/")
                    }
            }
            guard sourceShapeIsValid,
                  Set(participantIDs).count == participantIDs.count,
                  Set(participantPaths).count == participantPaths.count else {
                throw TriptychTransactionError.invalidPlan(
                    "A system-Trash source has an invalid or duplicate Note inventory."
                )
            }
        }
        let affectedNoteIDs = preview.affectedNoteIDs
        for record in preview.records {
            let participantIDs = record.participantNoteIDs
            let unaffectedIDs = record.unaffectedParticipants.map(\.noteID)
            guard !participantIDs.isEmpty,
                  Set(participantIDs).count == participantIDs.count,
                  Set(unaffectedIDs).count == unaffectedIDs.count,
                  !Set(participantIDs).isDisjoint(with: affectedNoteIDs),
                  Set(unaffectedIDs).isDisjoint(with: affectedNoteIDs),
                  Set(unaffectedIDs).isSubset(of: Set(participantIDs)) else {
                throw TriptychTransactionError.invalidPlan(
                    "A system-Trash Record has an invalid participant inventory."
                )
            }
        }
    }

    private func validatePlanShape(
        _ plan: SystemTrashDeletionPlan,
        recoveryRecord: TriptychMutationRecoveryRecord
    ) throws {
        try validatePreviewShape(plan.preview)
        let sourceIDs = plan.preview.sources.map(\.id)
        let receiptIDs = plan.sourceReceipts.map(\.targetID)
        let recordIDs = plan.preview.records.map(\.id)
        let deletedRecordIDs = plan.deletedRecordIDs
        let discussionIDs = plan.preview.activeDiscussionIDs
        let removedDiscussionIDs = plan.removedDiscussionIDs
        guard recoveryRecord.id == plan.id,
              recoveryRecord.triptychID == triptychID,
              recoveryRecord.operation == .systemTrashDeletion,
              plan.preview.triptychID == triptychID,
              receiptIDs.count == sourceIDs.count,
              Set(receiptIDs).count == receiptIDs.count,
              Set(receiptIDs) == Set(sourceIDs),
              Set(deletedRecordIDs).count == deletedRecordIDs.count,
              Set(deletedRecordIDs).isSubset(of: Set(recordIDs)),
              Set(removedDiscussionIDs).count == removedDiscussionIDs.count,
              Set(removedDiscussionIDs).isSubset(of: Set(discussionIDs)) else {
            throw TriptychTransactionError.invalidPlan(
                "System-Trash recovery identities or progress receipts are inconsistent."
            )
        }
    }

    private func persist(
        _ plan: SystemTrashDeletionPlan,
        replacing record: TriptychMutationRecoveryRecord,
        failure: String
    ) async throws {
        try await recoveryStore.record(await makeRecord(
            id: record.id,
            createdAt: record.createdAt,
            plan: plan,
            failure: failure
        ))
    }

    private func makeRecord(
        id: UUID? = nil,
        createdAt: Date? = nil,
        plan: SystemTrashDeletionPlan,
        failure: String
    ) async -> TriptychMutationRecoveryRecord {
        let files = plan.preview.sources.map { source in
            let receipt = plan.sourceReceipts.first { $0.targetID == source.id }
            let state: TriptychMutationRecoveryState
            let detail: String
            switch receipt?.progress ?? .pending {
            case .pending:
                state = .restored
                detail = "The exact source remains pending for a native system-Trash move."
            case .movedToSystemTrash:
                state = .missing
                detail = "Foundation moved the item to the system Trash. Finder owns restoration."
            case .outcomeUnknown:
                state = .unreadable
                detail = "Scholium cannot prove the system Trash outcome and will not infer Record deletion from source absence."
            }
            return TriptychMutationRecoveryFile(
                vaultID: source.vaultID,
                path: source.relativePath,
                alternatePath: receipt?.resultingTrashPath,
                role: source.kind == .folder ? .trashedFolder : .trashedNote,
                beforeRevision: source.notes.count == 1
                    ? source.notes.first?.expectedRevision
                    : nil,
                intendedRevision: nil,
                observedRevision: nil,
                state: state,
                detail: detail
            )
        }
        return TriptychMutationRecoveryRecord(
            id: id ?? plan.id,
            triptychID: triptychID,
            createdAt: createdAt ?? plan.preview.preparedAt,
            failure: failure,
            files: files,
            systemTrashDeletionPlan: plan
        )
    }

    private func requireHealthyStores() async throws {
        if let error = await critiqueRegistry.healthError() {
            throw ResearchRecordStoreError.unreadableStore(kind: "Critique", reason: error)
        }
        try await localExecutionStore?.validateDeletionAuthority()
        let records = try await portableRecordStore.listing()
        let discussions = try await portableRecordStore.activeDiscussions()
        let issues = records.issues + discussions.issues
        guard issues.isEmpty else {
            throw ResearchRecordStoreError.unreadableStore(
                kind: "Portable Research Record",
                reason: issues.map { "\($0.id): \($0.reason)" }.joined(separator: "; ")
            )
        }
    }

    private func requireNoActiveExecutions(noteIDs: Set<UUID>) async throws {
        guard let localExecutionStore else { return }
        let runIDs = try await localExecutionStore.activeExecutionIDs(containing: noteIDs)
        guard runIDs.isEmpty else {
            throw TriptychTransactionError.preflightFailed(
                note: nil,
                detail: "Finish, cancel, or recover the active Research Action before moving its participating Note to the system Trash. Active Run IDs: \(runIDs.map(\.uuidString).joined(separator: ", "))."
            )
        }
    }
}
