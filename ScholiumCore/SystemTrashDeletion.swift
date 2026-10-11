import Foundation
import ScholiumContracts

enum SystemTrashDeletionFaultPoint: Hashable, Sendable {
    case afterPlanPersistence
    case afterNativeRequestPersistence
    case afterSystemTrashMoveBeforeReceipt
    case afterSourceReceipts
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

/// Coordinates one researcher-confirmed system-Trash operation and the
/// durable operation receipts. Portable identities remain for Finder restoration.
public actor NoteSystemTrashDeletionCoordinator {
    private let triptychID: UUID
    private let repository: VaultRepository
    private let controlStore: TriptychControlStore
    private let recoveryStore: TriptychMutationRecoveryStore
    private let faultPlan: SystemTrashDeletionFaultPlan
    private let nativeDispatchBarrierForTesting: (@Sendable () async -> Void)?

    public init(
        triptychID: UUID,
        repository: VaultRepository,
        controlStore: TriptychControlStore,
        recoveryStore: TriptychMutationRecoveryStore
    ) {
        self.triptychID = triptychID
        self.repository = repository
        self.controlStore = controlStore
        self.recoveryStore = recoveryStore
        faultPlan = .none
        nativeDispatchBarrierForTesting = nil
    }

    init(
        triptychID: UUID,
        repository: VaultRepository,
        controlStore: TriptychControlStore,
        recoveryStore: TriptychMutationRecoveryStore,
        faultPlan: SystemTrashDeletionFaultPlan,
        nativeDispatchBarrierForTesting: (@Sendable () async -> Void)? = nil
    ) {
        self.triptychID = triptychID
        self.repository = repository
        self.controlStore = controlStore
        self.recoveryStore = recoveryStore
        self.faultPlan = faultPlan
        self.nativeDispatchBarrierForTesting = nativeDispatchBarrierForTesting
    }

    public func prepareNote(
        noteID: UUID,
        vaultID: UUID,
        relativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> SystemTrashDeletionPreview {
        guard repository.identity.id == vaultID else {
            throw TriptychTransactionError.invalidPlan(
                "The system-Trash repository does not match the selected vault identity."
            )
        }
        _ = try await repository.preflightExisting(
            relativePath: relativePath,
            expectedRevision: expectedRevision
        )
        guard
            try await controlStore.identityRecord(
                vaultID: vaultID,
                relativePath: relativePath
            )?.id == noteID
        else {
            throw TriptychTransactionError.invalidPlan(
                "The selected source no longer matches its stable Note identity."
            )
        }

        let noteTarget = SystemTrashDeletionNoteTarget(
            noteID: noteID,
            relativePath: relativePath,
            expectedRevision: expectedRevision
        )
        let sources = [
            SystemTrashDeletionSourceTarget(
                vaultID: vaultID,
                relativePath: relativePath,
                kind: .note,
                notes: [noteTarget]
            )
        ]
        return try await makePreview(sources: sources)
    }

    public func prepareFolder(
        vaultID: UUID,
        relativePath: String
    ) async throws -> SystemTrashDeletionPreview {
        guard repository.identity.id == vaultID,
            let folder = try? VaultRelativeFolderPath(relativePath),
            try await repository.folderRelativePaths().contains(folder)
        else {
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
            guard
                let identity = try await controlStore.identityRecord(
                    vaultID: vaultID,
                    relativePath: path
                )
            else {
                throw TriptychTransactionError.invalidPlan(
                    "The folder descendant \(path) has no stable identity."
                )
            }
            noteTargets.append(
                SystemTrashDeletionNoteTarget(
                    noteID: identity.id,
                    relativePath: path,
                    expectedRevision: document.fingerprint
                ))
        }
        let sources = [
            SystemTrashDeletionSourceTarget(
                vaultID: vaultID,
                relativePath: relativePath,
                kind: .folder,
                notes: noteTargets,
                expectedDirectoryManifest:
                    try await repository
                    .systemTrashDirectoryManifest(relativePath: relativePath)
            )
        ]

        return try await makePreview(sources: sources)
    }

    public func moveToSystemTrash(
        _ preview: SystemTrashDeletionPreview
    ) async throws -> SystemTrashDeletionCommit {
        guard preview.triptychID == triptychID,
            preview.sources.allSatisfy({ $0.vaultID == repository.identity.id })
        else {
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
            guard
                record.systemTrashDeletionPlan?.preview.sources.allSatisfy({
                    $0.vaultID == repository.identity.id
                }) == true
            else { continue }
            commits.append(try await perform(record))
        }
        return commits
    }

    /// Resolves only the irreducible native-Trash uncertainty case. This is
    /// deliberately not an automatic recovery path: Finder owns the source
    /// item, while Scholium releases only the short-lived deletion gate after
    /// researcher review.
    public func resolveUnknownOutcome(
        recoveryRecordID: UUID
    ) async throws {
        guard
            let record = try await recoveryStore.pending().first(where: {
                $0.id == recoveryRecordID && $0.operation == .systemTrashDeletion
            }), let plan = record.systemTrashDeletionPlan
        else {
            throw TriptychTransactionError.invalidPlan(
                "The selected system-Trash recovery record is unavailable."
            )
        }
        try validatePlanShape(plan, recoveryRecord: record)
        guard plan.sourceReceipts.contains(where: { $0.progress == .outcomeUnknown }) else {
            throw TriptychTransactionError.invalidPlan(
                "The selected recovery record has no unknown native Trash outcome."
            )
        }
        try await recoveryStore.resolve(record)
    }

    private func makePreview(
        sources: [SystemTrashDeletionSourceTarget]
    ) async throws -> SystemTrashDeletionPreview {
        return SystemTrashDeletionPreview(
            triptychID: triptychID,
            sources: sources
        )
    }

    private func validate(_ preview: SystemTrashDeletionPreview) async throws {
        try validatePreviewShape(preview)
        for source in preview.sources {
            switch source.kind {
            case .note:
                guard source.notes.count == 1, let note = source.notes.first,
                    note.relativePath == source.relativePath
                else {
                    throw TriptychTransactionError.invalidPlan(
                        "A Note system-Trash source has an invalid inventory."
                    )
                }
                try await repository.preflightSystemTrashNote(
                    relativePath: note.relativePath,
                    expectedRevision: note.expectedRevision
                )
            case .folder:
                let expected = Dictionary(
                    uniqueKeysWithValues: source.notes.map {
                        ($0.relativePath, $0.expectedRevision)
                    })
                _ = try await repository.moveFolderToSystemTrashPreflight(
                    relativePath: source.relativePath,
                    expectedDocuments: expected,
                    expectedDirectoryManifest: try requiredDirectoryManifest(source)
                )
            }
            for note in source.notes {
                guard
                    try await controlStore.identityRecord(
                        vaultID: source.vaultID,
                        relativePath: note.relativePath
                    )?.id == note.noteID
                else {
                    throw TriptychTransactionError.invalidPlan(
                        "Stable identity changed for \(note.relativePath)."
                    )
                }
            }
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
            if plan.sourceReceipts.allSatisfy({ $0.progress == .pending }) {
                try await validate(plan.preview)
            }
            for source in plan.preview.sources {
                guard
                    let receipt = plan.sourceReceipts.first(where: {
                        $0.targetID == source.id
                    })
                else {
                    throw TriptychTransactionError.invalidPlan(
                        "A system-Trash source receipt is missing."
                    )
                }
                switch receipt.progress {
                case .movedToSystemTrash:
                    continue
                case .outcomeUnknown:
                    throw TriptychTransactionError.invalidPlan(
                        "The system Trash result for \(source.relativePath) is unknown. Inspect Finder before resolving this recovery record."
                    )
                case .pending:
                    break
                }

                // A process exit after Finder accepts the request cannot
                // leave a replayable pending receipt. Unknown is durable before
                // dispatch and becomes moved only after exact native readback.
                plan = replacingReceipt(
                    in: plan, targetID: source.id,
                    progress: .outcomeUnknown, resultingTrashPath: nil)
                try await persist(
                    plan, replacing: record,
                    failure: "The native Trash request is starting; no retry is authorized until its exact outcome is recorded.")
                try faultPlan.trigger(.afterNativeRequestPersistence)
                if let barrier = nativeDispatchBarrierForTesting { await barrier() }
                try Task.checkCancellation()

                let nativeOutcome: SystemTrashOperationOutcome
                switch source.kind {
                case .note:
                    guard let note = source.notes.first else {
                        throw TriptychTransactionError.invalidPlan("A Note system-Trash source has no exact Note target.")
                    }
                    nativeOutcome = await repository.systemTrashNoteOutcome(
                        relativePath: note.relativePath, expectedRevision: note.expectedRevision)
                case .folder:
                    nativeOutcome = await repository.systemTrashFolderOutcome(
                        relativePath: source.relativePath,
                        expectedDirectoryManifest: try requiredDirectoryManifest(source))
                }
                var resultingURL: URL?
                switch nativeOutcome {
                case .notDispatched(let error):
                    // Only Core's explicit predispatch result restores replay
                    // eligibility. An NSError after dispatch is insufficient.
                    plan = replacingReceipt(
                        in: plan, targetID: source.id,
                        progress: .pending, resultingTrashPath: nil)
                    try await persist(plan, replacing: record, failure: error.localizedDescription)
                    throw error
                case .outcomeUnknown(let url, let reason):
                    plan = replacingReceipt(
                        in: plan, targetID: source.id,
                        progress: .outcomeUnknown, resultingTrashPath: url?.path)
                    try await persist(plan, replacing: record, failure: reason)
                    throw SystemTrashMoveError.outcomeUnknown(resultingURL: url, reason: reason)
                case .moved(let url):
                    resultingURL = url
                }
                do { try faultPlan.trigger(.afterSystemTrashMoveBeforeReceipt) } catch {
                    plan = replacingReceipt(
                        in: plan, targetID: source.id,
                        progress: .outcomeUnknown, resultingTrashPath: resultingURL?.path)
                    try await persist(plan, replacing: record, failure: error.localizedDescription)
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
                    failure: "System Trash completed; temporary application cleanup is pending."
                )
            }
            try faultPlan.trigger(.afterSourceReceipts)

            let completedRecord = await makeRecord(
                plan: plan,
                failure: "System Trash completed."
            )
            try await recoveryStore.record(completedRecord)
            try await recoveryStore.resolve(completedRecord)
            return SystemTrashDeletionCommit(
                planID: plan.id,
                noteIDs: Array(plan.affectedNoteIDs),
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
                if plan.sourceReceipts.allSatisfy({ $0.progress == .pending }) {
                    // Every participant is proved undispatched. Release the
                    // failed confirmation so a changed source can prepare a
                    // fresh plan rather than remain behind a deletion gate.
                    try await recoveryStore.resolve(updated)
                }
            } catch {
                throw TriptychTransactionError.recoveryPersistenceFailed(
                    updated,
                    error.localizedDescription
                )
            }
            if plan.sourceReceipts.allSatisfy({ $0.progress == .pending }) { throw error }
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
            }
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
        guard !preview.sources.isEmpty,
            Set(sourceIDs).count == sourceIDs.count,
            Set(sourcePaths).count == sourcePaths.count,
            Set(noteIDs).count == noteIDs.count,
            Set(notePaths).count == notePaths.count
        else {
            throw TriptychTransactionError.invalidPlan(
                "System-Trash source and Note identities must be unique."
            )
        }
        for source in preview.sources {
            let participantIDs = source.notes.map(\.noteID)
            let participantPaths = source.notes.map(\.relativePath)
            let sourceShapeIsValid =
                switch source.kind {
                case .note:
                    source.notes.count == 1
                        && source.notes.first?.relativePath == source.relativePath
                        && source.expectedDirectoryManifest == nil
                case .folder:
                    source.expectedDirectoryManifest != nil
                        && source.notes.allSatisfy {
                            $0.relativePath.hasPrefix(source.relativePath + "/")
                        }
                }
            guard sourceShapeIsValid,
                Set(participantIDs).count == participantIDs.count,
                Set(participantPaths).count == participantPaths.count
            else {
                throw TriptychTransactionError.invalidPlan(
                    "A system-Trash source has an invalid or duplicate Note inventory."
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
        guard plan.schemaVersion == 2,
            recoveryRecord.id == plan.id,
            recoveryRecord.triptychID == triptychID,
            recoveryRecord.operation == .systemTrashDeletion,
            plan.preview.triptychID == triptychID,
            receiptIDs.count == sourceIDs.count,
            Set(receiptIDs).count == receiptIDs.count,
            Set(receiptIDs) == Set(sourceIDs)
        else {
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
        try await recoveryStore.record(
            await makeRecord(
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
                detail = "Scholium cannot prove the system Trash outcome and will not infer cleanup from source absence."
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

}
