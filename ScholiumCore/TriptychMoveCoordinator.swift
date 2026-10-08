import CryptoKit
import Foundation
import ScholiumContracts

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
        triptychID =
            UUID(
                uuidString: self.storageURL
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
        triptychID =
            UUID(
                uuidString: self.storageURL
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
        triptychID =
            UUID(
                uuidString: self.storageURL
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
            try (loadRecords() + loadCitationSaves().map(citationRecoveryProjection))
                .sorted { $0.createdAt > $1.createdAt }
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
                guard
                    try citationPairStorage.readIfPresent(
                        directory: nil, fileName: citationManifestName(record.id)
                    ) == nil
                else {
                    throw ZoteroCitationSaveError.invalidCompanion(
                        "A citation pair must be reconciled before its recovery evidence can be removed."
                    )
                }
                guard let current = try loadRecords().first(where: { $0.id == record.id }) else {
                    return
                }
                guard current == record else {
                    throw SecureRecordDirectoryError.replacementNotCommitted(
                        "The transaction recovery evidence changed before deletion."
                    )
                }
                let fileName = Self.fileName(record.id)
                guard
                    try storage.readIfPresent(
                        directory: Self.recordsDirectory,
                        fileName: fileName
                    ) != nil
                else {
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
                fileName == Self.fileName(id)
            else {
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
            files: [
                TriptychMutationRecoveryFile(
                    vaultID: nil,
                    path: "records/\(fileName)",
                    role: .savedNote,
                    beforeRevision: nil,
                    intendedRevision: nil,
                    observedRevision: nil,
                    state: .unreadable,
                    detail: "Reveal the operation records in Finder and preserve this file for manual recovery."
                )
            ]
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
        guard
            try JSONDecoder().decode(
                TriptychMutationRecoveryRecord.self,
                from: readback
            ) == record
        else {
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
        var hexadecimal = Array(
            SHA256.hash(data: Data(seed.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
                .prefix(32))
        hexadecimal[12] = "5"
        hexadecimal[16] = "8"
        let value =
            String(hexadecimal[0..<8]) + "-" + String(hexadecimal[8..<12]) + "-"
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
                result = .failure(
                    SecureRecordDirectoryError.unsafe(
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

extension TriptychMutationRecoveryStore {
    private struct CitationPayload: Codable { let bytes: Data }
    private struct CitationCompletionReceipt: Codable {
        let schemaVersion: Int
        let recordRevision: DocumentFingerprint
        let displacedRevision: DocumentFingerprint
        let canonicalPair: String
    }

    private var citationPairStorage: SecureRecordDirectory {
        let largestPayload = max(VaultSourceReadLimits.maximumNoteByteCount, ZoteroCitationCompanion.maximumEncodedByteCount)
        return SecureRecordDirectory(
            trustedRootURL: storageURL.deletingLastPathComponent(),
            components: [storageURL.lastPathComponent, "citation-pairs-v1"],
            directoryMode: 0o700, fileMode: 0o600,
            maximumByteCount: ((largestPayload + 2) / 3) * 4 + 1_024
        )
    }

    public func pendingCitationSaves() throws -> [ZoteroCitationPairRecovery] {
        try lock.withSharedLock { try loadCitationSaves() }
    }

    /// Explicitly completed pairs whose displaced external bytes remain intact.
    /// These records are inspectable through citationSaveEvidence, but never
    /// enter pending recovery or authorize automatic replay.
    public func retainedCitationSaves() throws -> [ZoteroCitationPairRecovery] {
        try lock.withSharedLock { try loadCitationSaves(retained: true) }
    }

    func prepareCitationSave(
        noteID: UUID, vaultID: UUID, relativePath: String,
        sourceBefore: Data?, sourceAfter: Data, companionBefore: Data?, companionAfter: Data?,
        companionRequiredBefore: Bool
    ) throws -> ZoteroCitationPairRecovery {
        _ = try MarkdownRelativePath(relativePath)
        guard sourceAfter.count <= VaultSourceReadLimits.maximumNoteByteCount,
            (sourceBefore?.count ?? 0) <= VaultSourceReadLimits.maximumNoteByteCount,
            (companionAfter?.count ?? 0) <= ZoteroCitationCompanion.maximumEncodedByteCount,
            (companionBefore?.count ?? 0) <= ZoteroCitationCompanion.maximumEncodedByteCount
        else { throw ZoteroCitationSaveError.invalidCompanion("Citation recovery payload exceeds its byte limit.") }
        let record = ZoteroCitationPairRecovery(
            triptychID: triptychID, noteID: noteID, vaultID: vaultID, relativePath: relativePath,
            sourceBefore: sourceBefore, sourceAfter: sourceAfter,
            companionBefore: companionBefore, companionAfter: companionAfter,
            companionRequiredBefore: companionRequiredBefore
        )
        return try lock.withExclusiveLock {
            guard try loadCitationSaves().allSatisfy({ $0.noteID != noteID }) else {
                throw ZoteroCitationSaveError.invalidCompanion("This Note already has an unresolved citation save.")
            }
            let store = citationPairStorage
            try store.ensureDirectories([])
            let payloads: [(String, Data?)] = [
                ("source-before", sourceBefore), ("source-after", sourceAfter),
                ("companion-before", companionBefore), ("companion-after", companionAfter),
            ]
            for (name, bytes) in payloads {
                guard let bytes else { continue }
                let encoded = try citationEncoder().encode(CitationPayload(bytes: bytes))
                guard try store.createExclusive(encoded, directory: nil, fileName: citationPayloadName(record.id, name)) == encoded else {
                    throw ZoteroCitationSaveError.invalidCompanion("Citation recovery payload readback failed.")
                }
            }
            // Publish the manifest last. No canonical write can start until all
            // separate payloads and this manifest have exact durable readback.
            let manifest = try citationEncoder().encode(record)
            guard try store.createExclusive(manifest, directory: nil, fileName: citationManifestName(record.id)) == manifest else {
                throw ZoteroCitationSaveError.invalidCompanion("Citation recovery manifest readback failed.")
            }
            _ = try citationEvidence(record)
            return record
        }
    }

    public func citationSaveEvidence(_ record: ZoteroCitationPairRecovery) throws -> ZoteroCitationPairEvidence {
        try lock.withSharedLock { try citationEvidence(record) }
    }

    /// Verifies the immutable completion disposition before any retry of its
    /// exact, noncanonical filesystem cleanup.
    public func retainedCitationSaveEvidence(_ record: ZoteroCitationPairRecovery) throws -> ZoteroCitationPairEvidence {
        try lock.withSharedLock {
            let evidence = try citationEvidence(record)
            guard try citationCompletion(record, evidence: evidence) != nil else {
                throw ZoteroCitationSaveError.recoveryRequired(record)
            }
            return evidence
        }
    }

    func retainDisplacedCitationCompanion(_ record: ZoteroCitationPairRecovery, bytes: Data) throws {
        try lock.withExclusiveLock {
            let evidence = try citationEvidence(record)
            if let retained = evidence.companionDisplaced {
                guard retained == bytes else {
                    throw ZoteroCitationSaveError.invalidCompanion("Another displaced citation revision remains at its transaction-bound location.")
                }
                return
            }
            let encoded = try citationEncoder().encode(CitationPayload(bytes: bytes))
            guard
                try citationPairStorage.createExclusive(
                    encoded, directory: nil, fileName: citationPayloadName(record.id, "companion-displaced")
                ) == encoded
            else { throw ZoteroCitationSaveError.invalidCompanion("The displaced citation revision could not be retained.") }
        }
    }

    /// Only the paired-save coordinator calls this after exact canonical proof.
    func completeCitationSave(
        _ record: ZoteroCitationPairRecovery, retainingDisplacedEvidenceAt state: ZoteroCitationPairState? = nil
    ) throws {
        try lock.withExclusiveLock {
            let evidence = try citationEvidence(record)
            let store = citationPairStorage
            if let displaced = evidence.companionDisplaced {
                guard state == .committed || state == .unchanged else {
                    throw ZoteroCitationSaveError.recoveryRequired(record)
                }
                let receipt = CitationCompletionReceipt(
                    schemaVersion: 1, recordRevision: DocumentFingerprint(data: try citationEncoder().encode(record)),
                    displacedRevision: DocumentFingerprint(data: displaced),
                    canonicalPair: state == .committed ? "after" : "before"
                )
                let encoded = try citationEncoder().encode(receipt)
                let name = citationCompletionName(record.id)
                if let existing = try store.readIfPresent(directory: nil, fileName: name) {
                    guard existing == encoded else {
                        throw ZoteroCitationSaveError.invalidCompanion("The retained citation completion receipt changed.")
                    }
                } else {
                    guard try store.createExclusive(encoded, directory: nil, fileName: name) == encoded else {
                        throw ZoteroCitationSaveError.invalidCompanion("Citation completion could not retain its exact evidence receipt.")
                    }
                }
                _ = try citationCompletion(record, evidence: citationEvidence(record))
                // Keep the original manifest and every payload. The immutable
                // receipt changes pending disposition, never research bytes or
                // the recoverability of the displaced external revision.
                return
            }
            guard try store.readIfPresent(directory: nil, fileName: citationCompletionName(record.id)) == nil else {
                throw ZoteroCitationSaveError.invalidCompanion("A citation completion receipt has lost its retained evidence.")
            }
            try store.remove(directory: nil, fileName: citationManifestName(record.id), expected: citationEncoder().encode(record))
            // Removing the published manifest first makes interrupted cleanup
            // inert. These exact transaction-owned payloads no longer authorize work.
            for name in ["source-before", "source-after", "companion-before", "companion-after"] {
                let fileName = citationPayloadName(record.id, name)
                if let bytes = try store.readIfPresent(directory: nil, fileName: fileName) {
                    try store.remove(directory: nil, fileName: fileName, expected: bytes)
                }
            }
        }
    }

    private func loadCitationSaves(retained: Bool = false) throws -> [ZoteroCitationPairRecovery] {
        let store = citationPairStorage
        let names: [String]
        do { names = try store.fileNames(in: nil) } catch let error as SecureRecordDirectoryError {
            if case .notFound = error { return [] }
            throw error
        }
        return try names.filter { $0.hasSuffix("-pair.json") }.sorted().compactMap { name in
            let record = try decodeCitationRecord(store.read(directory: nil, fileName: name))
            guard record.schemaVersion == 1, record.triptychID == triptychID,
                citationManifestName(record.id) == name
            else {
                throw ZoteroCitationSaveError.invalidCompanion("Citation recovery identity or schema is invalid; its bytes remain unchanged.")
            }
            let evidence = try citationEvidence(record)
            let completed = try citationCompletion(record, evidence: evidence) != nil
            return completed == retained ? record : nil
        }
    }

    private func citationCompletion(
        _ record: ZoteroCitationPairRecovery, evidence: ZoteroCitationPairEvidence
    ) throws -> CitationCompletionReceipt? {
        guard let encoded = try citationPairStorage.readIfPresent(directory: nil, fileName: citationCompletionName(record.id)) else { return nil }
        let receipt = try JSONDecoder().decode(CitationCompletionReceipt.self, from: encoded)
        guard let displaced = evidence.companionDisplaced,
            receipt.canonicalPair == "before" || receipt.canonicalPair == "after"
        else { throw ZoteroCitationSaveError.invalidCompanion("Retained citation completion evidence is invalid.") }
        let expected = CitationCompletionReceipt(
            schemaVersion: 1, recordRevision: DocumentFingerprint(data: try citationEncoder().encode(record)),
            displacedRevision: DocumentFingerprint(data: displaced), canonicalPair: receipt.canonicalPair
        )
        guard encoded == (try citationEncoder().encode(expected)) else {
            throw ZoteroCitationSaveError.invalidCompanion("Unsupported or changed citation completion evidence remains intact.")
        }
        return receipt
    }

    private func citationEvidence(_ record: ZoteroCitationPairRecovery) throws -> ZoteroCitationPairEvidence {
        let store = citationPairStorage
        let saved = try decodeCitationRecord(store.read(directory: nil, fileName: citationManifestName(record.id)))
        guard saved == record, record.schemaVersion == 1, record.triptychID == triptychID else {
            throw ZoteroCitationSaveError.invalidCompanion("Citation recovery evidence changed.")
        }
        _ = try MarkdownRelativePath(record.relativePath)
        func payload(_ name: String, revision: DocumentFingerprint?) throws -> Data? {
            let encoded = try store.readIfPresent(directory: nil, fileName: citationPayloadName(record.id, name))
            guard let revision else {
                guard encoded == nil else { throw ZoteroCitationSaveError.invalidCompanion("Checked-absent recovery bytes changed.") }
                return nil
            }
            guard let encoded else { throw ZoteroCitationSaveError.invalidCompanion("Citation recovery payload is missing.") }
            let bytes = try decodeCitationPayload(encoded)
            guard DocumentFingerprint(data: bytes) == revision else {
                throw ZoteroCitationSaveError.invalidCompanion("Citation recovery payload no longer matches its exact revision.")
            }
            return bytes
        }
        guard let sourceAfter = try payload("source-after", revision: record.sourceAfter)
        else { throw ZoteroCitationSaveError.invalidCompanion("Citation recovery candidate is missing.") }
        let companionAfter = try payload("companion-after", revision: record.companionAfter)
        guard record.companionRequiredAfter == (companionAfter != nil) else {
            throw ZoteroCitationSaveError.invalidCompanion("Citation recovery declaration does not match its companion.")
        }
        if let companionAfter {
            let companion = try ZoteroCitationCompanion.decode(companionAfter)
            try companion.validate(noteID: record.noteID, vaultID: record.vaultID, sourceFingerprint: record.sourceAfter)
            guard let source = NoteDocument.decodeUTF8PreservingBOM(sourceAfter) else { throw ZoteroCitationError.invalidSource }
            try ZoteroMarkdownFields.validateCompanion(source: source, data: companion.data)
        } else {
            guard sourceAfter.count <= VaultSourceReadLimits.maximumNoteByteCount,
                let source = NoteDocument.decodeUTF8PreservingBOM(sourceAfter)
            else { throw ZoteroCitationError.invalidSource }
            let document = NoteDocument(
                relativePath: record.relativePath, rawContent: source,
                citationSnapshot: .init(noteID: record.noteID, vaultID: record.vaultID, status: .absent))
            let fields = ZoteroMarkdownFields(parsing: document)
            guard document.frontmatterState != .malformed, fields.canMutate,
                fields.fields.allSatisfy(\.isCompleted)
            else { throw ZoteroCitationError.invalidSource }
        }
        let beforeCompanion = try payload("companion-before", revision: record.companionBefore)
        guard !record.companionRequiredBefore || beforeCompanion != nil else {
            throw ZoteroCitationSaveError.invalidCompanion("Citation recovery lost its required original companion.")
        }
        let displaced = try store.readIfPresent(directory: nil, fileName: citationPayloadName(record.id, "companion-displaced"))
            .map { try decodeCitationPayload($0) }
        return ZoteroCitationPairEvidence(
            record: record, sourceBefore: try payload("source-before", revision: record.sourceBefore),
            sourceAfter: sourceAfter, companionBefore: beforeCompanion,
            companionAfter: companionAfter, companionDisplaced: displaced
        )
    }

    private func citationRecoveryProjection(_ record: ZoteroCitationPairRecovery) -> TriptychMutationRecoveryRecord {
        TriptychMutationRecoveryRecord(
            id: record.id, triptychID: record.triptychID, operation: .noteSave,
            createdAt: Date(timeIntervalSince1970: 0),
            failure: "The Note and its citation companion require exact-pair reconciliation.",
            files: [
                TriptychMutationRecoveryFile(
                    vaultID: record.vaultID, path: record.relativePath,
                    role: record.sourceBefore == nil ? .createdNote : .savedNote,
                    beforeRevision: record.sourceBefore, intendedRevision: record.sourceAfter,
                    observedRevision: nil, state: .unreadable,
                    detail:
                        "Both source and citation companion revisions remain in machine-local recovery. Resolve through citation recovery; generic dismissal is unavailable."
                )
            ]
        )
    }

    private func citationManifestName(_ id: UUID) -> String { "\(id.uuidString.lowercased())-pair.json" }
    private func citationCompletionName(_ id: UUID) -> String { "\(id.uuidString.lowercased())-completed.json" }
    private func citationPayloadName(_ id: UUID, _ name: String) -> String { "\(id.uuidString.lowercased())-\(name).json" }
    private func citationEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private func decodeCitationRecord(_ bytes: Data) throws -> ZoteroCitationPairRecovery {
        let allowed: Set<String> = [
            "schemaVersion", "id", "triptychID", "noteID", "vaultID", "relativePath", "sourceBefore", "sourceAfter", "companionBefore", "companionAfter",
            "companionRequiredBefore", "companionRequiredAfter",
        ]
        guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
            Set(object.keys).isSubset(of: allowed)
        else {
            throw ZoteroCitationSaveError.invalidCompanion("Unsupported citation recovery authority remains unchanged.")
        }
        for key in ["sourceBefore", "sourceAfter", "companionBefore", "companionAfter"] {
            if let fingerprint = object[key] as? [String: Any],
                !Set(fingerprint.keys).isSubset(of: ["sha256", "byteCount"])
            {
                throw ZoteroCitationSaveError.invalidCompanion("Unsupported citation recovery fingerprint remains unchanged.")
            }
        }
        return try JSONDecoder().decode(ZoteroCitationPairRecovery.self, from: bytes)
    }

    private func decodeCitationPayload(_ bytes: Data) throws -> Data {
        guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
            Set(object.keys) == ["bytes"]
        else {
            throw ZoteroCitationSaveError.invalidCompanion("Unsupported citation recovery payload remains unchanged.")
        }
        return try JSONDecoder().decode(CitationPayload.self, from: bytes).bytes
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

    /// Runs the same path/source/link preflight as execution without moving or recording source.
    public func validate(_ plan: IncomingLinkRewritePlan, expectedRevision: DocumentFingerprint) async throws {
        _ = try await prepareMove(plan, expectedRevision: expectedRevision)
    }

    private func prepareMove(_ plan: IncomingLinkRewritePlan, expectedRevision: DocumentFingerprint)
        async throws -> (VaultRepository, NoteDocument, [PreparedRewrite])
    {
        try Task.checkCancellation()
        guard plan.movedNote.vaultID == plan.destination.vaultID else {
            throw TriptychTransactionError.invalidPlan("A note cannot change vault identity during an ordinary move.")
        }
        guard plan.movedNote.relativePath != plan.destination.relativePath else {
            throw TriptychTransactionError.invalidPlan("The source and destination paths are identical.")
        }
        guard plan.blockedIncomingLinks.isEmpty else {
            let first = plan.blockedIncomingLinks[0]
            throw TriptychTransactionError.invalidPlan(
                "A link in \(first.source.relativePath) at line \(first.span.start.line) cannot retain its target after this move without ambiguity."
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
                let mutationPath =
                    rewrite.source == plan.movedNote
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
                prepared.append(
                    PreparedRewrite(
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

        return (sourceRepository, sourceBefore, prepared)
    }

    public func move(_ plan: IncomingLinkRewritePlan, expectedRevision: DocumentFingerprint) async throws -> TriptychMoveCommit {
        let (sourceRepository, sourceBefore, prepared) = try await prepareMove(plan, expectedRevision: expectedRevision)
        try Task.checkCancellation()
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
                applied.append(
                    AppliedRewrite(
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
        let finalMovedRevision =
            applied.first {
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
        var files = [
            TriptychMutationRecoveryFile(
                vaultID: plan.movedNote.vaultID,
                path: plan.movedNote.relativePath,
                alternatePath: plan.destination.relativePath,
                role: .movedNote,
                beforeRevision: sourceBefore.fingerprint,
                intendedRevision: sourceBefore.fingerprint,
                observedRevision: sourceObserved?.fingerprint ?? destinationObserved?.fingerprint,
                state: moveState,
                detail: "Observe both the original and destination paths before choosing recovery."
            )
        ]

        for appliedRewrite in applied {
            let rewrite = appliedRewrite.prepared
            let observedPath: String
            if rewrite.plan.source == plan.movedNote {
                observedPath =
                    sourceObserved == nil
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
            files.append(
                TriptychMutationRecoveryFile(
                    vaultID: rewrite.plan.source.vaultID,
                    path: observedPath,
                    role: .incomingLinkRewrite,
                    beforeRevision: rewrite.before.fingerprint,
                    intendedRevision: intended,
                    observedRevision: observed?.fingerprint,
                    state: state,
                    detail: "Link rewrite for \(rewrite.plan.rewrittenOccurrences) resolved occurrence(s)."
                ))
        }
        return files
    }
}
