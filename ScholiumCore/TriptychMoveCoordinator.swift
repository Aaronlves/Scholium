import Foundation

public enum TriptychMutationOperation: String, Codable, Hashable, Sendable {
    case noteMove
    case unclassifiedClassification
    case permanentDeletion
}

public enum TriptychMutationFileRole: String, Codable, Hashable, Sendable {
    case movedNote
    case incomingLinkRewrite
    case classifiedSource
    case classifiedDestination
    case deletedNote
    case associatedCritique
}

enum PermanentDeletionRecoveryPhase: String, Codable, Hashable, Sendable {
    case rollbackRequired
    case committing
}

struct PermanentDeletionRecoveryBackup: Codable, Hashable, Sendable {
    let phase: PermanentDeletionRecoveryPhase
    let noteID: UUID
    let vaultID: UUID
    let relativePath: String
    let expectedRevision: DocumentFingerprint
    let checkpointArea: TriptychCheckpointArea
    let humanReview: HumanReviewRecord?
    let dialogues: [DialogueEntry]
    let critiqueNoteID: UUID?
    let critiqueHumanReview: HumanReviewRecord?
    let critiqueDialogues: [DialogueEntry]
    let critiqueAssociations: [CritiqueAssociation]
    let identity: PermanentDeletionIdentityBackup?
    let critiqueIdentity: PermanentDeletionIdentityBackup?
    let sourceDeletion: PreparedPermanentDeletion?
    let critiqueDeletion: PreparedPermanentDeletion?
    let checkpointPurge: PreparedCheckpointPurge?

    func updating(
        phase: PermanentDeletionRecoveryPhase? = nil,
        sourceDeletion: PreparedPermanentDeletion?? = nil,
        critiqueDeletion: PreparedPermanentDeletion?? = nil,
        checkpointPurge: PreparedCheckpointPurge?? = nil
    ) -> Self {
        Self(
            phase: phase ?? self.phase,
            noteID: noteID,
            vaultID: vaultID,
            relativePath: relativePath,
            expectedRevision: expectedRevision,
            checkpointArea: checkpointArea,
            humanReview: humanReview,
            dialogues: dialogues,
            critiqueNoteID: critiqueNoteID,
            critiqueHumanReview: critiqueHumanReview,
            critiqueDialogues: critiqueDialogues,
            critiqueAssociations: critiqueAssociations,
            identity: identity,
            critiqueIdentity: critiqueIdentity,
            sourceDeletion: sourceDeletion ?? self.sourceDeletion,
            critiqueDeletion: critiqueDeletion ?? self.critiqueDeletion,
            checkpointPurge: checkpointPurge ?? self.checkpointPurge
        )
    }
}

public enum TriptychMutationRecoveryState: String, Codable, Hashable, Sendable {
    case restored
    case intendedBytesRemain
    case externallyChanged
    case missing
    case unreadable
}

public struct TriptychMutationRecoveryFile: Codable, Hashable, Sendable, Identifiable {
    public var id: String {
        "\(vaultID?.uuidString ?? "unclassified"):\(path):\(role.rawValue)"
    }

    public let vaultID: UUID?
    public let path: String
    public let alternatePath: String?
    public let role: TriptychMutationFileRole
    public let beforeRevision: DocumentFingerprint?
    public let intendedRevision: DocumentFingerprint?
    public let observedRevision: DocumentFingerprint?
    public let state: TriptychMutationRecoveryState
    public let detail: String

    public init(
        vaultID: UUID?,
        path: String,
        alternatePath: String? = nil,
        role: TriptychMutationFileRole,
        beforeRevision: DocumentFingerprint?,
        intendedRevision: DocumentFingerprint?,
        observedRevision: DocumentFingerprint?,
        state: TriptychMutationRecoveryState,
        detail: String
    ) {
        self.vaultID = vaultID
        self.path = path
        self.alternatePath = alternatePath
        self.role = role
        self.beforeRevision = beforeRevision
        self.intendedRevision = intendedRevision
        self.observedRevision = observedRevision
        self.state = state
        self.detail = detail
    }
}

/// Durable machine-local evidence that a multi-file operation could not be
/// completely rolled back. It never claims cross-filesystem atomicity.
public struct TriptychMutationRecoveryRecord: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let triptychID: UUID
    public let operation: TriptychMutationOperation
    public let createdAt: Date
    public let failure: String
    public let files: [TriptychMutationRecoveryFile]
    let permanentDeletionBackup: PermanentDeletionRecoveryBackup?

    public init(
        id: UUID = UUID(),
        triptychID: UUID,
        operation: TriptychMutationOperation,
        createdAt: Date = Date(),
        failure: String,
        files: [TriptychMutationRecoveryFile]
    ) {
        self.id = id
        self.triptychID = triptychID
        self.operation = operation
        self.createdAt = createdAt
        self.failure = failure
        self.files = files
        self.permanentDeletionBackup = nil
    }

    init(
        id: UUID,
        triptychID: UUID,
        createdAt: Date,
        failure: String,
        files: [TriptychMutationRecoveryFile],
        permanentDeletionBackup: PermanentDeletionRecoveryBackup
    ) {
        self.id = id
        self.triptychID = triptychID
        self.operation = .permanentDeletion
        self.createdAt = createdAt
        self.failure = failure
        self.files = files
        self.permanentDeletionBackup = permanentDeletionBackup
    }
}

public actor TriptychMutationRecoveryStore {
    private struct Payload: Codable {
        var records: [TriptychMutationRecoveryRecord]
    }

    public nonisolated let storageURL: URL
    private let fileURL: URL
    private let fileManager: FileManager

    public init(storageURL: URL, fileManager: FileManager = .default) throws {
        self.storageURL = storageURL.standardizedFileURL
        self.fileURL = self.storageURL.appendingPathComponent("transaction-recovery.json")
        self.fileManager = fileManager
        try fileManager.createDirectory(at: self.storageURL, withIntermediateDirectories: true)
    }

    public func pending() throws -> [TriptychMutationRecoveryRecord] {
        try load().records.sorted { $0.createdAt > $1.createdAt }
    }

    public func record(_ record: TriptychMutationRecoveryRecord) throws {
        var payload = try load()
        payload.records.removeAll { $0.id == record.id }
        payload.records.append(record)
        try persist(payload)
    }

    public func resolve(_ id: UUID) throws {
        var payload = try load()
        payload.records.removeAll { $0.id == id }
        try persist(payload)
    }

    private func load() throws -> Payload {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return Payload(records: [])
        }
        return try JSONDecoder().decode(Payload.self, from: Data(contentsOf: fileURL))
    }

    private func persist(_ payload: Payload) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(payload).write(to: fileURL, options: .atomic)
    }
}

public struct CoordinatedIncomingLinkRewriteResult: Hashable, Sendable {
    public let note: VaultQualifiedNoteID
    public let previousRevision: DocumentFingerprint
    public let committedRevision: DocumentFingerprint
    public let rewrittenOccurrences: Int
}

public struct TriptychMoveCommit: Hashable, Sendable {
    public let movedNote: VaultQualifiedNoteID
    public let destination: VaultQualifiedNoteID
    public let previousRevision: DocumentFingerprint
    public let committedRevision: DocumentFingerprint
    public let graphGeneration: Int
    public let rewrites: [CoordinatedIncomingLinkRewriteResult]
}

public struct UnclassifiedClassificationCommit: Hashable, Sendable {
    public let sourceRelativePath: String
    public let destination: VaultQualifiedNoteID
    public let committedRevision: DocumentFingerprint
}

public enum TriptychTransactionError: LocalizedError, Sendable {
    case invalidPlan(String)
    case preflightFailed(note: VaultQualifiedNoteID?, detail: String)
    case transactionRolledBack(String)
    case recoveryRequired(TriptychMutationRecoveryRecord)
    case recoveryPersistenceFailed(TriptychMutationRecoveryRecord, String)

    public var errorDescription: String? {
        switch self {
        case .invalidPlan(let detail):
            return "The note move plan is invalid: \(detail)"
        case .preflightFailed(let note, let detail):
            if let note {
                return "Scholium did not change any files because \(note.relativePath) failed preflight: \(detail)"
            }
            return "Scholium did not change any files because preflight failed: \(detail)"
        case .transactionRolledBack(let detail):
            return "The operation failed and Scholium restored the affected files: \(detail)"
        case .recoveryRequired(let record):
            return "The operation did not complete and could not be fully restored. Recovery record \(record.id.uuidString) identifies every affected file."
        case .recoveryPersistenceFailed(let record, let detail):
            return "The operation requires recovery, and Scholium could not persist recovery record \(record.id.uuidString): \(detail)"
        }
    }
}

enum TriptychTransactionFaultPoint: Hashable, Sendable {
    case beforeMove
    case afterRewrite(Int)
    case beforeRewriteRollback(Int)
    case beforeMoveRollback
    case beforeDestinationCreate
    case beforeUnclassifiedRemoval
    case beforeClassificationRollback
}

struct TriptychTransactionFaultPlan: Sendable {
    let points: Set<TriptychTransactionFaultPoint>

    static let none = Self(points: [])

    func trigger(_ point: TriptychTransactionFaultPoint) throws {
        guard points.contains(point) else { return }
        throw TriptychInjectedTransactionFailure(point: point)
    }
}

private struct TriptychInjectedTransactionFailure: LocalizedError, Sendable {
    let point: TriptychTransactionFaultPoint
    var errorDescription: String? { "Injected transaction failure at \(String(describing: point))." }
}

public actor TriptychMoveCoordinator {
    private struct PreparedRewrite {
        let plan: IncomingLinkRewrite
        let repository: VaultRepository
        let mutationPath: String
        let before: NoteDocument
    }

    private struct AppliedRewrite {
        let prepared: PreparedRewrite
        let committed: NoteDocument
    }

    private let triptychID: UUID
    private let repositories: [UUID: VaultRepository]
    private let recoveryStore: TriptychMutationRecoveryStore
    private let faultPlan: TriptychTransactionFaultPlan

    public init(
        triptychID: UUID,
        repositories: [UUID: VaultRepository],
        recoveryStore: TriptychMutationRecoveryStore
    ) {
        self.triptychID = triptychID
        self.repositories = repositories
        self.recoveryStore = recoveryStore
        self.faultPlan = .none
    }

    init(
        triptychID: UUID,
        repositories: [UUID: VaultRepository],
        recoveryStore: TriptychMutationRecoveryStore,
        faultPlan: TriptychTransactionFaultPlan
    ) {
        self.triptychID = triptychID
        self.repositories = repositories
        self.recoveryStore = recoveryStore
        self.faultPlan = faultPlan
    }

    public func move(
        _ plan: IncomingLinkRewritePlan,
        expectedRevision: DocumentFingerprint
    ) async throws -> TriptychMoveCommit {
        guard plan.movedNote.vaultID == plan.destination.vaultID else {
            throw TriptychTransactionError.invalidPlan("A note cannot change vault identity during an ordinary move.")
        }
        guard plan.movedNote.relativePath != plan.destination.relativePath else {
            throw TriptychTransactionError.invalidPlan("The source and destination paths are identical.")
        }
        guard plan.blockedIncomingLinks.isEmpty else {
            let first = plan.blockedIncomingLinks[0]
            throw TriptychTransactionError.invalidPlan(
                "An incoming link in \(first.source.relativePath) at line \(first.span.start.line) cannot identify the moved note at its new path without ambiguity."
            )
        }

        let sourceRepository = try await repository(for: plan.movedNote)
        let sourceBefore: NoteDocument
        do {
            sourceBefore = try await sourceRepository.preflightExisting(
                relativePath: plan.movedNote.relativePath,
                expectedRevision: expectedRevision
            )
            try await sourceRepository.preflightNewFile(relativePath: plan.destination.relativePath)
        } catch {
            throw TriptychTransactionError.preflightFailed(
                note: plan.movedNote,
                detail: error.localizedDescription
            )
        }

        var prepared: [PreparedRewrite] = []
        do {
            for rewrite in plan.rewrites {
                let repository = try await repository(for: rewrite.source)
                let mutationPath = rewrite.source == plan.movedNote
                    ? plan.destination.relativePath
                    : rewrite.source.relativePath
                let before: NoteDocument
                if rewrite.source == plan.movedNote {
                    guard rewrite.expectedRevision == expectedRevision else {
                        throw TriptychTransactionError.invalidPlan(
                            "The moved note and its self-link rewrite have different starting revisions."
                        )
                    }
                    before = sourceBefore
                } else {
                    before = try await repository.preflightExisting(
                        relativePath: rewrite.source.relativePath,
                        expectedRevision: rewrite.expectedRevision
                    )
                }
                let proposed = NoteDocument(relativePath: mutationPath, rawContent: rewrite.updatedSource)
                if proposed.rawFrontmatter != nil, !proposed.validationWarnings.isEmpty {
                    throw VaultRepositoryError.invalidFrontmatter(
                        proposed.validationWarnings.joined(separator: "\n")
                    )
                }
                prepared.append(PreparedRewrite(
                    plan: rewrite,
                    repository: repository,
                    mutationPath: mutationPath,
                    before: before
                ))
            }
        } catch let error as TriptychTransactionError {
            throw error
        } catch {
            throw TriptychTransactionError.preflightFailed(note: nil, detail: error.localizedDescription)
        }

        var moveResult: NoteMoveResult?
        var applied: [AppliedRewrite] = []
        do {
            try faultPlan.trigger(.beforeMove)
            moveResult = try await sourceRepository.move(
                relativePath: plan.movedNote.relativePath,
                to: plan.destination.relativePath,
                expectedRevision: expectedRevision
            )
            for (index, rewrite) in prepared.enumerated() {
                let saved = try await rewrite.repository.save(
                    relativePath: rewrite.mutationPath,
                    changeSet: .exactContent(rewrite.plan.updatedSource),
                    expectedRevision: rewrite.plan.expectedRevision
                )
                applied.append(AppliedRewrite(prepared: rewrite, committed: saved.document))
                try faultPlan.trigger(.afterRewrite(index))
            }
        } catch {
            try await reconcileMoveFailure(
                cause: error,
                plan: plan,
                sourceBefore: sourceBefore,
                sourceRepository: sourceRepository,
                didMove: moveResult != nil,
                applied: applied
            )
        }

        guard let moveResult else {
            throw TriptychTransactionError.transactionRolledBack("The move did not commit.")
        }
        let rewriteResults = applied.map {
            CoordinatedIncomingLinkRewriteResult(
                note: $0.prepared.plan.source == plan.movedNote ? plan.destination : $0.prepared.plan.source,
                previousRevision: $0.prepared.before.fingerprint,
                committedRevision: $0.committed.fingerprint,
                rewrittenOccurrences: $0.prepared.plan.rewrittenOccurrences
            )
        }
        let finalMovedRevision = applied.first {
            $0.prepared.plan.source == plan.movedNote
        }?.committed.fingerprint ?? moveResult.document.fingerprint
        return TriptychMoveCommit(
            movedNote: plan.movedNote,
            destination: plan.destination,
            previousRevision: sourceBefore.fingerprint,
            committedRevision: finalMovedRevision,
            graphGeneration: plan.graphGeneration,
            rewrites: rewriteResults
        )
    }

    private func repository(for note: VaultQualifiedNoteID) async throws -> VaultRepository {
        guard let repository = repositories[note.vaultID] else {
            throw TriptychTransactionError.invalidPlan(
                "No repository is registered for vault \(note.vaultID.uuidString)."
            )
        }
        guard repository.identity.id == note.vaultID else {
            throw TriptychTransactionError.invalidPlan(
                "The repository identity does not match \(note.vaultID.uuidString)."
            )
        }
        return repository
    }

    private func reconcileMoveFailure(
        cause: Error,
        plan: IncomingLinkRewritePlan,
        sourceBefore: NoteDocument,
        sourceRepository: VaultRepository,
        didMove: Bool,
        applied: [AppliedRewrite]
    ) async throws -> Never {
        var rollbackErrors: [String] = []

        for (reverseIndex, rewrite) in applied.reversed().enumerated() {
            do {
                try faultPlan.trigger(.beforeRewriteRollback(reverseIndex))
                _ = try await rewrite.prepared.repository.save(
                    relativePath: rewrite.prepared.mutationPath,
                    changeSet: .exactContent(rewrite.prepared.before.rawContent),
                    expectedRevision: rewrite.committed.fingerprint
                )
            } catch {
                rollbackErrors.append("\(rewrite.prepared.plan.source.relativePath): \(error.localizedDescription)")
            }
        }

        if didMove {
            do {
                try faultPlan.trigger(.beforeMoveRollback)
                let currentDestination = try await sourceRepository.load(
                    relativePath: plan.destination.relativePath
                )
                guard currentDestination.fingerprint == sourceBefore.fingerprint else {
                    throw VaultRepositoryError.conflict(
                        expected: sourceBefore.fingerprint,
                        current: currentDestination.fingerprint
                    )
                }
                _ = try await sourceRepository.move(
                    relativePath: plan.destination.relativePath,
                    to: plan.movedNote.relativePath,
                    expectedRevision: currentDestination.fingerprint
                )
            } catch {
                rollbackErrors.append("\(plan.movedNote.relativePath): \(error.localizedDescription)")
            }
        }

        let observations = await observeMoveFiles(
            plan: plan,
            sourceBefore: sourceBefore,
            didMove: didMove,
            applied: applied
        )
        let restored = observations.allSatisfy { $0.state == .restored }
        if restored {
            throw TriptychTransactionError.transactionRolledBack(cause.localizedDescription)
        }

        let detail = ([cause.localizedDescription] + rollbackErrors).joined(separator: "\n")
        let record = TriptychMutationRecoveryRecord(
            triptychID: triptychID,
            operation: .noteMove,
            failure: detail,
            files: observations
        )
        do {
            try await recoveryStore.record(record)
        } catch {
            throw TriptychTransactionError.recoveryPersistenceFailed(record, error.localizedDescription)
        }
        throw TriptychTransactionError.recoveryRequired(record)
    }

    private func observeMoveFiles(
        plan: IncomingLinkRewritePlan,
        sourceBefore: NoteDocument,
        didMove: Bool,
        applied: [AppliedRewrite]
    ) async -> [TriptychMutationRecoveryFile] {
        let sourceObserved = try? await repositories[plan.movedNote.vaultID]?.load(
            relativePath: plan.movedNote.relativePath
        )
        let destinationObserved = try? await repositories[plan.destination.vaultID]?.load(
            relativePath: plan.destination.relativePath
        )
        let moveState: TriptychMutationRecoveryState
        if !didMove, sourceObserved != nil, destinationObserved == nil {
            // The repository never returned a committed move and no destination
            // exists. Preserve any concurrent source edit; Scholium has no
            // mutation left to roll back.
            moveState = .restored
        } else if sourceObserved?.fingerprint == sourceBefore.fingerprint, destinationObserved == nil {
            moveState = .restored
        } else if destinationObserved?.fingerprint == sourceBefore.fingerprint {
            moveState = .intendedBytesRemain
        } else if sourceObserved == nil, destinationObserved == nil {
            moveState = .missing
        } else {
            moveState = .externallyChanged
        }
        var files = [TriptychMutationRecoveryFile(
            vaultID: plan.movedNote.vaultID,
            path: plan.movedNote.relativePath,
            alternatePath: plan.destination.relativePath,
            role: .movedNote,
            beforeRevision: sourceBefore.fingerprint,
            intendedRevision: sourceBefore.fingerprint,
            observedRevision: sourceObserved?.fingerprint ?? destinationObserved?.fingerprint,
            state: moveState,
            detail: "Observe both the original and destination paths before choosing recovery."
        )]

        for appliedRewrite in applied {
            let rewrite = appliedRewrite.prepared
            let observedPath: String
            if rewrite.plan.source == plan.movedNote {
                observedPath = sourceObserved == nil
                    ? plan.destination.relativePath
                    : plan.movedNote.relativePath
            } else {
                observedPath = rewrite.plan.source.relativePath
            }
            let observed = try? await rewrite.repository.load(relativePath: observedPath)
            let intended = DocumentFingerprint(content: rewrite.plan.updatedSource)
            let state: TriptychMutationRecoveryState
            if observed?.fingerprint == rewrite.before.fingerprint {
                state = .restored
            } else if observed?.fingerprint == intended {
                state = .intendedBytesRemain
            } else if observed == nil {
                state = .missing
            } else {
                state = .externallyChanged
            }
            files.append(TriptychMutationRecoveryFile(
                vaultID: rewrite.plan.source.vaultID,
                path: observedPath,
                role: .incomingLinkRewrite,
                beforeRevision: rewrite.before.fingerprint,
                intendedRevision: intended,
                observedRevision: observed?.fingerprint,
                state: state,
                detail: "Incoming link rewrite for \(rewrite.plan.rewrittenOccurrences) resolved occurrence(s)."
            ))
        }
        return files
    }
}

public actor UnclassifiedClassificationCoordinator {
    private let triptychID: UUID
    private let control: TriptychControlStore
    private let destinationVaultID: UUID
    private let destinationRepository: VaultRepository
    private let recoveryStore: TriptychMutationRecoveryStore
    private let faultPlan: TriptychTransactionFaultPlan

    public init(
        triptychID: UUID,
        control: TriptychControlStore,
        destinationVaultID: UUID,
        destinationRepository: VaultRepository,
        recoveryStore: TriptychMutationRecoveryStore
    ) {
        self.triptychID = triptychID
        self.control = control
        self.destinationVaultID = destinationVaultID
        self.destinationRepository = destinationRepository
        self.recoveryStore = recoveryStore
        self.faultPlan = .none
    }

    init(
        triptychID: UUID,
        control: TriptychControlStore,
        destinationVaultID: UUID,
        destinationRepository: VaultRepository,
        recoveryStore: TriptychMutationRecoveryStore,
        faultPlan: TriptychTransactionFaultPlan
    ) {
        self.triptychID = triptychID
        self.control = control
        self.destinationVaultID = destinationVaultID
        self.destinationRepository = destinationRepository
        self.recoveryStore = recoveryStore
        self.faultPlan = faultPlan
    }

    public func classify(
        sourceRelativePath: String,
        expectedRevision: DocumentFingerprint,
        destinationRelativePath: String
    ) async throws -> UnclassifiedClassificationCommit {
        let source: NoteDocument
        do {
            guard destinationRepository.identity.id == destinationVaultID else {
                throw TriptychTransactionError.invalidPlan("The destination repository identity does not match its Triptych vault.")
            }
            source = try await control.loadUnclassified(relativePath: sourceRelativePath)
            guard source.fingerprint == expectedRevision else {
                throw VaultRepositoryError.conflict(
                    expected: expectedRevision,
                    current: source.fingerprint
                )
            }
            try await destinationRepository.preflightNewFile(relativePath: destinationRelativePath)
        } catch let error as TriptychTransactionError {
            throw error
        } catch {
            throw TriptychTransactionError.preflightFailed(note: nil, detail: error.localizedDescription)
        }

        var created: NoteDocument?
        do {
            try faultPlan.trigger(.beforeDestinationCreate)
            created = try await destinationRepository.create(
                relativePath: destinationRelativePath,
                content: source.rawContent
            )
            try faultPlan.trigger(.beforeUnclassifiedRemoval)
            try await control.removeUnclassified(
                relativePath: sourceRelativePath,
                expectedRevision: expectedRevision
            )
        } catch {
            guard let created else {
                let sourceObserved = try? await control.loadUnclassified(relativePath: sourceRelativePath)
                let destinationObserved = try? await destinationRepository.load(relativePath: destinationRelativePath)
                guard let destinationObserved else {
                    throw TriptychTransactionError.transactionRolledBack(error.localizedDescription)
                }
                let files = [
                    TriptychMutationRecoveryFile(
                        vaultID: nil,
                        path: sourceRelativePath,
                        role: .classifiedSource,
                        beforeRevision: expectedRevision,
                        intendedRevision: nil,
                        observedRevision: sourceObserved?.fingerprint,
                        state: classificationSourceState(sourceObserved, expected: expectedRevision),
                        detail: "Portable Unclassified copy. The original imported file outside Scholium was never modified."
                    ),
                    TriptychMutationRecoveryFile(
                        vaultID: destinationVaultID,
                        path: destinationRelativePath,
                        role: .classifiedDestination,
                        beforeRevision: nil,
                        intendedRevision: source.fingerprint,
                        observedRevision: destinationObserved.fingerprint,
                        state: destinationObserved.fingerprint == source.fingerprint
                            ? .intendedBytesRemain
                            : .externallyChanged,
                        detail: "Destination appeared while creation failed. Scholium did not delete it because ownership could not be verified."
                    ),
                ]
                let record = TriptychMutationRecoveryRecord(
                    triptychID: triptychID,
                    operation: .unclassifiedClassification,
                    failure: error.localizedDescription,
                    files: files
                )
                do {
                    try await recoveryStore.record(record)
                } catch {
                    throw TriptychTransactionError.recoveryPersistenceFailed(record, error.localizedDescription)
                }
                throw TriptychTransactionError.recoveryRequired(record)
            }
            var rollbackError: Error?
            do {
                try faultPlan.trigger(.beforeClassificationRollback)
                try await destinationRepository.removeCreatedFileForRollback(
                    relativePath: destinationRelativePath,
                    createdRevision: created.fingerprint
                )
            } catch {
                rollbackError = error
            }

            let sourceObserved = try? await control.loadUnclassified(relativePath: sourceRelativePath)
            let destinationObserved = try? await destinationRepository.load(relativePath: destinationRelativePath)
            if sourceObserved != nil, destinationObserved == nil {
                throw TriptychTransactionError.transactionRolledBack(error.localizedDescription)
            }

            let files = [
                TriptychMutationRecoveryFile(
                    vaultID: nil,
                    path: sourceRelativePath,
                    role: .classifiedSource,
                    beforeRevision: expectedRevision,
                    intendedRevision: nil,
                    observedRevision: sourceObserved?.fingerprint,
                    state: classificationSourceState(sourceObserved, expected: expectedRevision),
                    detail: "Portable Unclassified copy. The original imported file outside Scholium was never modified."
                ),
                TriptychMutationRecoveryFile(
                    vaultID: destinationVaultID,
                    path: destinationRelativePath,
                    role: .classifiedDestination,
                    beforeRevision: nil,
                    intendedRevision: created.fingerprint,
                    observedRevision: destinationObserved?.fingerprint,
                    state: classificationDestinationState(destinationObserved, intended: created.fingerprint),
                    detail: "Destination created from the exact Unclassified bytes."
                ),
            ]
            let detail = [error.localizedDescription, rollbackError?.localizedDescription]
                .compactMap { $0 }
                .joined(separator: "\n")
            let record = TriptychMutationRecoveryRecord(
                triptychID: triptychID,
                operation: .unclassifiedClassification,
                failure: detail,
                files: files
            )
            do {
                try await recoveryStore.record(record)
            } catch {
                throw TriptychTransactionError.recoveryPersistenceFailed(record, error.localizedDescription)
            }
            throw TriptychTransactionError.recoveryRequired(record)
        }

        guard let created else {
            throw TriptychTransactionError.transactionRolledBack("The destination was not created.")
        }
        return UnclassifiedClassificationCommit(
            sourceRelativePath: sourceRelativePath,
            destination: VaultQualifiedNoteID(
                vaultID: destinationVaultID,
                relativePath: destinationRelativePath
            ),
            committedRevision: created.fingerprint
        )
    }

    private func classificationSourceState(
        _ observed: NoteDocument?,
        expected: DocumentFingerprint
    ) -> TriptychMutationRecoveryState {
        guard let observed else { return .missing }
        return observed.fingerprint == expected ? .restored : .externallyChanged
    }

    private func classificationDestinationState(
        _ observed: NoteDocument?,
        intended: DocumentFingerprint
    ) -> TriptychMutationRecoveryState {
        guard let observed else { return .restored }
        return observed.fingerprint == intended ? .intendedBytesRemain : .externallyChanged
    }
}
