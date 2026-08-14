import ScholiumContracts
import CryptoKit
import Foundation

public actor TriptychMutationRecoveryStore {
    private static let recordsDirectory = "records"
    private static let lockName = "transaction-recovery.lock"
    private static let maximumByteCount = 8 * 1024 * 1024

    public nonisolated let storageURL: URL
    private let triptychID: UUID
    private let storage: SecureRecordDirectory
    private let lock: AdvisoryFileLock

    public init(storageURL: URL, fileManager: FileManager = .default) throws {
        self.storageURL = storageURL.standardizedFileURL
        triptychID = UUID(uuidString: self.storageURL
            .deletingLastPathComponent().lastPathComponent)
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        try fileManager.createDirectory(at: self.storageURL, withIntermediateDirectories: true)
        let storage = SecureRecordDirectory(
            trustedRootURL: self.storageURL.deletingLastPathComponent(),
            components: [self.storageURL.lastPathComponent],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: Self.maximumByteCount
        )
        try storage.ensureDirectories([Self.recordsDirectory])
        let lock = try AdvisoryFileLock(
            directory: storage,
            fileName: Self.lockName
        )
        try lock.withExclusiveLock {
            try storage.recoverAbandonedDeletionFiles(in: Self.recordsDirectory)
            try storage.removeAbandonedStagingFiles(in: [Self.recordsDirectory])
        }
        self.storage = storage
        self.lock = lock
    }

    init(
        storageURL: URL,
        fileManager: FileManager = .default,
        postCommitFault: @escaping @Sendable (String) throws -> Void
    ) throws {
        self.storageURL = storageURL.standardizedFileURL
        triptychID = UUID(uuidString: self.storageURL
            .deletingLastPathComponent().lastPathComponent)
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        try fileManager.createDirectory(at: self.storageURL, withIntermediateDirectories: true)
        let storage = SecureRecordDirectory(
            trustedRootURL: self.storageURL.deletingLastPathComponent(),
            components: [self.storageURL.lastPathComponent],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: Self.maximumByteCount,
            postCommitFault: postCommitFault
        )
        try storage.ensureDirectories([Self.recordsDirectory])
        let lock = try AdvisoryFileLock(
            directory: storage,
            fileName: Self.lockName
        )
        try lock.withExclusiveLock {
            try storage.recoverAbandonedDeletionFiles(in: Self.recordsDirectory)
            try storage.removeAbandonedStagingFiles(in: [Self.recordsDirectory])
        }
        self.storage = storage
        self.lock = lock
    }

    init(
        storageURL: URL,
        fileManager: FileManager = .default,
        preCommitFault: @escaping @Sendable (String) throws -> Void
    ) throws {
        self.storageURL = storageURL.standardizedFileURL
        triptychID = UUID(uuidString: self.storageURL
            .deletingLastPathComponent().lastPathComponent)
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        try fileManager.createDirectory(at: self.storageURL, withIntermediateDirectories: true)
        let storage = SecureRecordDirectory(
            trustedRootURL: self.storageURL.deletingLastPathComponent(),
            components: [self.storageURL.lastPathComponent],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: Self.maximumByteCount,
            preCommitFault: preCommitFault
        )
        try storage.ensureDirectories([Self.recordsDirectory])
        let lock = try AdvisoryFileLock(
            directory: storage,
            fileName: Self.lockName
        )
        try lock.withExclusiveLock {
            try storage.recoverAbandonedDeletionFiles(in: Self.recordsDirectory)
            try storage.removeAbandonedStagingFiles(in: [Self.recordsDirectory])
        }
        self.storage = storage
        self.lock = lock
    }

    public func pending() throws -> [TriptychMutationRecoveryRecord] {
        try lock.withSharedLock {
            try loadRecords().sorted { $0.createdAt > $1.createdAt }
        }
    }

    public func record(_ record: TriptychMutationRecoveryRecord) throws {
        try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL) {
                try persist(record)
            }
        }
    }

    public func resolve(_ record: TriptychMutationRecoveryRecord) throws {
        try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL) {
                guard let current = try loadRecords().first(where: { $0.id == record.id }) else {
                    return
                }
                guard current == record else {
                    throw SecureRecordDirectoryError.replacementNotCommitted(
                        "The transaction recovery evidence changed before deletion."
                    )
                }
                let fileName = Self.fileName(record.id)
                guard try storage.readIfPresent(
                    directory: Self.recordsDirectory,
                    fileName: fileName
                ) != nil else {
                    throw SecureRecordDirectoryError.unsafe(
                        "An unreadable transaction recovery entry is not a resolvable record."
                    )
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try storage.remove(
                    directory: Self.recordsDirectory,
                    fileName: fileName,
                    expected: encoder.encode(record)
                )
            }
        }
    }

    private func loadRecords() throws -> [TriptychMutationRecoveryRecord] {
        try storage.fileNames(in: Self.recordsDirectory).map { fileName in
            guard fileName.hasSuffix(".json"),
                  let id = UUID(uuidString: String(fileName.dropLast(5))),
                  fileName == Self.fileName(id) else {
                return unreadableRecord(
                    id: Self.unreadableRecordID(
                        triptychID: triptychID,
                        fileName: fileName
                    ),
                    fileName: fileName,
                    error: SecureRecordDirectoryError.unsafe(
                        "The transaction recovery directory contains an invalid record name."
                    )
                )
            }
            do {
                let data = try storage.read(
                    directory: Self.recordsDirectory,
                    fileName: fileName
                )
                let record = try JSONDecoder().decode(
                    TriptychMutationRecoveryRecord.self,
                    from: data
                )
                guard record.id == id else {
                    throw SecureRecordDirectoryError.unsafe(
                        "A transaction recovery record has the wrong identity."
                    )
                }
                return record
            } catch {
                return unreadableRecord(
                    id: id,
                    fileName: fileName,
                    error: error
                )
            }
        }
    }

    private func unreadableRecord(
        id: UUID,
        fileName: String,
        error: any Error
    ) -> TriptychMutationRecoveryRecord {
        TriptychMutationRecoveryRecord(
            id: id,
            triptychID: triptychID,
            operation: .noteSave,
            createdAt: Date(timeIntervalSince1970: 0),
            failure: "Recovery record \(fileName) is unreadable and remains unchanged: \(error.localizedDescription)",
            files: [TriptychMutationRecoveryFile(
                vaultID: nil,
                path: "records/\(fileName)",
                role: .savedNote,
                beforeRevision: nil,
                intendedRevision: nil,
                observedRevision: nil,
                state: .unreadable,
                detail: "Reveal the operation records in Finder and preserve this file for manual recovery."
            )]
        )
    }

    private func persist(_ record: TriptychMutationRecoveryRecord) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(record)
        let fileName = Self.fileName(record.id)
        let readback: Data
        if try storage.readIfPresent(
            directory: Self.recordsDirectory,
            fileName: fileName
        ) == nil {
            readback = try storage.createExclusive(
                data,
                directory: Self.recordsDirectory,
                fileName: fileName
            )
        } else {
            readback = try storage.replace(
                data,
                directory: Self.recordsDirectory,
                fileName: fileName
            )
        }
        guard try JSONDecoder().decode(
            TriptychMutationRecoveryRecord.self,
            from: readback
        ) == record else {
            throw SecureRecordDirectoryError.replacementCommitUncertain(
                "The transaction recovery readback did not match the requested record."
            )
        }
    }

    private static func fileName(_ id: UUID) -> String {
        id.uuidString.lowercased() + ".json"
    }

    private static func unreadableRecordID(
        triptychID: UUID,
        fileName: String
    ) -> UUID {
        let seed = "transaction-recovery-unreadable\u{1F}\(triptychID.uuidString.lowercased())\u{1F}\(fileName)"
        var hexadecimal = Array(SHA256.hash(data: Data(seed.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(32))
        hexadecimal[12] = "5"
        hexadecimal[16] = "8"
        let value = String(hexadecimal[0..<8]) + "-" + String(hexadecimal[8..<12]) + "-"
            + String(hexadecimal[12..<16]) + "-" + String(hexadecimal[16..<20]) + "-"
            + String(hexadecimal[20..<32])
        return UUID(uuidString: value)!
    }

    private static func coordinateWrite<T>(
        at url: URL,
        _ operation: () throws -> T
    ) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(
            writingItemAt: url,
            options: .forMerging,
            error: &coordinationError
        ) { coordinatedURL in
            guard coordinatedURL.standardizedFileURL == url.standardizedFileURL else {
                result = .failure(SecureRecordDirectoryError.unsafe(
                    "The transaction recovery directory moved during coordination."
                ))
                return
            }
            result = Result { try operation() }
        }
        if let coordinationError { throw coordinationError }
        guard let result else {
            throw SecureRecordDirectoryError.unsafe(
                "The transaction recovery coordinator did not execute the write."
            )
        }
        return try result.get()
    }
}


enum TriptychTransactionFaultPoint: Hashable, Sendable {
    case beforeMove
    case afterRewrite(Int)
    case beforeRewriteRollback(Int)
    case beforeMoveRollback
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
                applied.append(AppliedRewrite(
                    prepared: rewrite,
                    committed: saved.document
                ))
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
