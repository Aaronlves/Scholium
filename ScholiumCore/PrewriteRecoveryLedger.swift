import CryptoKit
import Foundation
import SQLite3
import ScholiumContracts

/// Core-only durable pre-write evidence. Research files never contain this
/// state and the ledger is not a delivery-facing Note History feature.
final class PrewriteRecoveryLedger {
    private struct ObjectManifest: Codable {
        let id: UUID
        let relativePath: String
        let sequence: Int
        let createdAt: Date
        let fingerprint: DocumentFingerprint
    }

    private struct TransactionManifest: Codable {
        enum State: String, Codable { case prepared, committed }
        let id: UUID
        let entryID: UUID
        let relativePath: String
        let expected: DocumentFingerprint
        var state: State
    }

    struct MutationTransaction: Codable, Hashable, Sendable {
        let id: UUID
        let relativePath: String
        let expected: DocumentFingerprint
        let candidate: DocumentFingerprint
        let createdAt: Date
        var retainedReason: String?
    }

    private let rootURL: URL
    private let objectsURL: URL
    private let transactionsURL: URL
    private let mutationTransactionsURL: URL
    private let remapsURL: URL
    private let tombstonesURL: URL
    private let quarantineURL: URL
    private let databaseURL: URL
    private let legacyVersionsURL: URL
    private let migrationMarkerURL: URL
    private let fileManager: FileManager
    private var database: OpaquePointer?
    private(set) var healthDiagnostic: String?
    private var writeBlocker: String?

    init(
        storageURL: URL,
        vaultURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        self.fileManager = fileManager
        rootURL = storageURL.appendingPathComponent("recovery-v2", isDirectory: true)
        objectsURL = rootURL.appendingPathComponent("objects", isDirectory: true)
        transactionsURL = rootURL.appendingPathComponent("transactions", isDirectory: true)
        mutationTransactionsURL = transactionsURL.appendingPathComponent("mutations", isDirectory: true)
        remapsURL = rootURL.appendingPathComponent("remaps", isDirectory: true)
        tombstonesURL = rootURL.appendingPathComponent("tombstones", isDirectory: true)
        quarantineURL = rootURL.appendingPathComponent("quarantine", isDirectory: true)
        databaseURL = rootURL.appendingPathComponent("history.sqlite")
        legacyVersionsURL = storageURL.appendingPathComponent("versions", isDirectory: true)
        migrationMarkerURL = rootURL.appendingPathComponent("v1-migration-complete.json")
        for directory in [
            rootURL, objectsURL, transactionsURL, mutationTransactionsURL,
            remapsURL, tombstonesURL, quarantineURL,
        ] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        do {
            try openDatabase()
            try configureAndCreateSchema()
            try validateDatabase()
        } catch {
            healthDiagnostic = "The recovery database was isolated and rebuilt: \(error.localizedDescription)"
            closeDatabase()
            try quarantineDatabaseFiles()
            try openDatabase()
            try configureAndCreateSchema()
            try rebuildDatabaseFromObjects()
        }
        try applyTombstonesBeforeRebuild()
        try migrateLegacyV1IfNeeded()
        if let vaultURL {
            try replayMutationTransactions(vaultURL: vaultURL)
        }
    }

    deinit { closeDatabase() }

    func prepare(relativePath: String, data: Data) throws -> PrewriteRecoveryReference {
        if let writeBlocker {
            throw VaultRepositoryError.recoveryLedgerUnavailable(writeBlocker)
        }
        let path = try MarkdownRelativePath(relativePath)
        try clearTombstone(relativePath: path.rawValue)
        let nextSequence = try maximumSequence(path: path.rawValue) + 1
        let entry = PrewriteRecoveryReference(
            id: UUID(),
            relativePath: path.rawValue,
            sequence: nextSequence,
            createdAt: Date(),
            fingerprint: DocumentFingerprint(data: data)
        )
        let objectDirectory = objectURL(entry.id)
        try fileManager.createDirectory(at: objectDirectory, withIntermediateDirectories: false)
        do {
            let sourceURL = objectDirectory.appendingPathComponent("source.md")
            try data.write(to: sourceURL, options: [.atomic])
            let readback = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
            guard DocumentFingerprint(data: readback) == entry.fingerprint else {
                throw VaultRepositoryError.readbackMismatch(
                    expected: entry.fingerprint,
                    current: DocumentFingerprint(data: readback)
                )
            }
            try writeJSON(
                ObjectManifest(
                    id: entry.id,
                    relativePath: entry.relativePath,
                    sequence: entry.sequence,
                    createdAt: entry.createdAt,
                    fingerprint: entry.fingerprint
                ),
                to: objectDirectory.appendingPathComponent("manifest.json")
            )
            try execute(
                "INSERT INTO entries(id, relative_path, sequence, created_at, sha256, byte_count) VALUES(?, ?, ?, ?, ?, ?)",
                bindings: [
                    .text(entry.id.uuidString), .text(entry.relativePath), .int(entry.sequence),
                    .double(entry.createdAt.timeIntervalSince1970), .text(entry.fingerprint.sha256),
                    .int(entry.fingerprint.byteCount),
                ]
            )
            try writeJSON(
                TransactionManifest(
                    id: entry.id,
                    entryID: entry.id,
                    relativePath: entry.relativePath,
                    expected: entry.fingerprint,
                    state: .prepared
                ),
                to: transactionURL(entry.id)
            )
            return entry
        } catch {
            try? fileManager.removeItem(at: objectDirectory)
            try? execute("DELETE FROM entries WHERE id = ?", bindings: [.text(entry.id.uuidString)])
            throw error
        }
    }

    func commit(_ entry: PrewriteRecoveryReference) throws {
        let transaction = transactionURL(entry.id)
        if fileManager.fileExists(atPath: transaction.path) {
            try writeJSON(
                TransactionManifest(
                    id: entry.id,
                    entryID: entry.id,
                    relativePath: entry.relativePath,
                    expected: entry.fingerprint,
                    state: .committed
                ),
                to: transaction
            )
        }
        try enforceRetention(relativePath: entry.relativePath, keeping: 10)
        if fileManager.fileExists(atPath: transaction.path) {
            try fileManager.removeItem(at: transaction)
        }
    }

    func discard(_ entry: PrewriteRecoveryReference) throws {
        try execute("DELETE FROM entries WHERE id = ?", bindings: [.text(entry.id.uuidString)])
        let object = objectURL(entry.id)
        if fileManager.fileExists(atPath: object.path) { try fileManager.removeItem(at: object) }
        let transaction = transactionURL(entry.id)
        if fileManager.fileExists(atPath: transaction.path) { try fileManager.removeItem(at: transaction) }
    }

    func entries(relativePath: String) throws -> [PrewriteRecoveryReference] {
        try query(
            "SELECT id, relative_path, sequence, created_at, sha256, byte_count FROM entries WHERE relative_path = ? ORDER BY sequence DESC",
            bindings: [.text(relativePath)]
        ).compactMap(Self.entry)
    }

    func content(entryID: UUID) throws -> Data {
        let rows = try query(
            "SELECT id, relative_path, sequence, created_at, sha256, byte_count FROM entries WHERE id = ?",
            bindings: [.text(entryID.uuidString)]
        )
        guard let entry = rows.first.flatMap(Self.entry) else {
            throw VaultRepositoryError.recoveryEntryNotFound(entryID)
        }
        let data = try Data(contentsOf: objectURL(entryID).appendingPathComponent("source.md"))
        let observed = DocumentFingerprint(data: data)
        guard observed == entry.fingerprint else {
            throw VaultRepositoryError.readbackMismatch(expected: entry.fingerprint, current: observed)
        }
        return data
    }

    func beginMutation(
        relativePath: String,
        expected: Data,
        candidate: Data
    ) throws -> MutationTransaction {
        let path = try MarkdownRelativePath(relativePath)
        let transaction = MutationTransaction(
            id: UUID(),
            relativePath: path.rawValue,
            expected: DocumentFingerprint(data: expected),
            candidate: DocumentFingerprint(data: candidate),
            createdAt: Date(),
            retainedReason: nil
        )
        let directory = mutationTransactionURL(transaction.id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            let expectedURL = directory.appendingPathComponent("expected.md")
            let candidateURL = directory.appendingPathComponent("candidate.md")
            try expected.write(to: expectedURL, options: .atomic)
            try candidate.write(to: candidateURL, options: .atomic)
            guard DocumentFingerprint(data: try Data(contentsOf: expectedURL)) == transaction.expected,
                  DocumentFingerprint(data: try Data(contentsOf: candidateURL)) == transaction.candidate else {
                throw VaultRepositoryError.recoveryLedgerUnavailable(
                    "A mutation transaction failed exact-byte readback."
                )
            }
            try writeJSON(transaction, to: directory.appendingPathComponent("manifest.json"))
            return transaction
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    func completeMutation(_ transaction: MutationTransaction) throws {
        let directory = mutationTransactionURL(transaction.id)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    func retainMutation(_ transaction: MutationTransaction, reason: String) throws {
        let directory = mutationTransactionURL(transaction.id)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        var retained = transaction
        retained.retainedReason = reason
        try writeJSON(retained, to: directory.appendingPathComponent("manifest.json"))
        healthDiagnostic = "A save transaction requires researcher-visible recovery: \(reason)"
    }

    func pendingMutations() throws -> [MutationTransaction] {
        try fileManager.contentsOfDirectory(
            at: mutationTransactionsURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ).compactMap { directory in
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(
                MutationTransaction.self,
                from: Data(contentsOf: directory.appendingPathComponent("manifest.json"))
            )
        }.sorted { $0.createdAt < $1.createdAt }
    }

    func remap(from source: String, to destination: String) throws {
        _ = try MarkdownRelativePath(source)
        _ = try MarkdownRelativePath(destination)
        let journal = remapsURL.appendingPathComponent("\(UUID().uuidString).json")
        try writeJSON(["source": source, "destination": destination], to: journal)
        try execute(
            "UPDATE entries SET relative_path = ? WHERE relative_path = ?",
            bindings: [.text(destination), .text(source)]
        )
        for entry in try entries(relativePath: destination) {
            let directory = objectURL(entry.id)
            try writeJSON(
                ObjectManifest(
                    id: entry.id,
                    relativePath: destination,
                    sequence: entry.sequence,
                    createdAt: entry.createdAt,
                    fingerprint: entry.fingerprint
                ),
                to: directory.appendingPathComponent("manifest.json")
            )
        }
        try fileManager.removeItem(at: journal)
    }

    func tombstoneAndPurge(relativePath: String) throws {
        _ = try MarkdownRelativePath(relativePath)
        let digest = Self.pathDigest(relativePath)
        let tombstone = tombstonesURL.appendingPathComponent("\(digest).json")
        try writeJSON(
            ["relative_path": relativePath, "created_at": ISO8601DateFormatter().string(from: Date())],
            to: tombstone
        )
        let doomed = try entries(relativePath: relativePath)
        try execute("DELETE FROM entries WHERE relative_path = ?", bindings: [.text(relativePath)])
        for entry in doomed {
            let object = objectURL(entry.id)
            if fileManager.fileExists(atPath: object.path) { try fileManager.removeItem(at: object) }
        }
    }

    private func clearTombstone(relativePath: String) throws {
        let tombstone = tombstonesURL.appendingPathComponent(
            "\(Self.pathDigest(relativePath)).json"
        )
        if fileManager.fileExists(atPath: tombstone.path) {
            try fileManager.removeItem(at: tombstone)
        }
    }

    private func replayMutationTransactions(vaultURL: URL) throws {
        let canonicalRoot = vaultURL.resolvingSymlinksInPath().standardizedFileURL
        for transaction in try pendingMutations() {
            let directory = mutationTransactionURL(transaction.id)
            do {
                let expected = try Data(contentsOf: directory.appendingPathComponent("expected.md"))
                let candidate = try Data(contentsOf: directory.appendingPathComponent("candidate.md"))
                guard DocumentFingerprint(data: expected) == transaction.expected,
                      DocumentFingerprint(data: candidate) == transaction.candidate else {
                    throw VaultRepositoryError.recoveryLedgerUnavailable(
                        "A pending mutation's preserved bytes failed fingerprint verification."
                    )
                }
                let path = try MarkdownRelativePath(transaction.relativePath)
                let target = canonicalRoot.appendingPathComponent(path.rawValue).standardizedFileURL
                let rootPrefix = canonicalRoot.path.hasSuffix("/")
                    ? canonicalRoot.path
                    : canonicalRoot.path + "/"
                guard target.path.hasPrefix(rootPrefix),
                      fileManager.fileExists(atPath: target.path) else {
                    healthDiagnostic = "A pending save transaction has no unambiguous canonical file and was retained."
                    continue
                }
                let values = try target.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true else {
                    healthDiagnostic = "A pending save transaction resolved to an unsafe file identity and was retained."
                    continue
                }
                let observed = DocumentFingerprint(data: try Data(contentsOf: target))
                if observed == transaction.expected || observed == transaction.candidate {
                    try completeMutation(transaction)
                } else {
                    healthDiagnostic = "A pending save transaction observed bytes other than its expected or candidate revision and was retained."
                }
            } catch {
                healthDiagnostic = "A pending save transaction could not be verified and was retained: \(error.localizedDescription)"
            }
        }
    }

    private func mutationTransactionURL(_ id: UUID) -> URL {
        mutationTransactionsURL.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    private func migrateLegacyV1IfNeeded() throws {
        guard !fileManager.fileExists(atPath: migrationMarkerURL.path),
              fileManager.fileExists(atPath: legacyVersionsURL.path) else { return }
        let indexURL = legacyVersionsURL.appendingPathComponent("index.json")
        guard fileManager.fileExists(atPath: indexURL.path) else { return }
        struct LegacyIndex: Codable { let entries: [String: [PrewriteRecoveryReference]] }
        do {
            let indexData = try Data(contentsOf: indexURL)
            let legacy = try JSONDecoder().decode(LegacyIndex.self, from: indexData)
            var verified: [(PrewriteRecoveryReference, Data)] = []
            for (path, entries) in legacy.entries {
                _ = try MarkdownRelativePath(path)
                for entry in entries {
                    guard entry.relativePath == path else {
                        throw VaultRepositoryError.recoveryPathConflict(path)
                    }
                    let blob = legacyVersionsURL
                        .appendingPathComponent(Self.pathDigest(path), isDirectory: true)
                        .appendingPathComponent(entry.id.uuidString + ".md")
                    let data = try Data(contentsOf: blob)
                    guard DocumentFingerprint(data: data) == entry.fingerprint else {
                        throw VaultRepositoryError.readbackMismatch(
                            expected: entry.fingerprint,
                            current: DocumentFingerprint(data: data)
                        )
                    }
                    verified.append((entry, data))
                }
            }
            for (entry, data) in verified where try !contains(id: entry.id) {
                try importVerified(entry: entry, data: data)
            }
            try writeJSON(
                ["completed_at": ISO8601DateFormatter().string(from: Date()), "entry_count": "\(verified.count)"],
                to: migrationMarkerURL
            )
        } catch {
            let message = "Legacy recovery bytes remain read-only because migration could not be verified: \(error.localizedDescription)"
            healthDiagnostic = message
            writeBlocker = message
            let diagnostic = quarantineURL.appendingPathComponent("legacy-migration-\(UUID().uuidString).json")
            try? writeJSON(["error": error.localizedDescription], to: diagnostic)
        }
    }

    private func importVerified(entry: PrewriteRecoveryReference, data: Data) throws {
        let directory = objectURL(entry.id)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        }
        let sourceURL = directory.appendingPathComponent("source.md")
        if fileManager.fileExists(atPath: sourceURL.path) {
            let existing = try Data(contentsOf: sourceURL)
            guard existing == data else {
                throw VaultRepositoryError.readbackMismatch(
                    expected: DocumentFingerprint(data: data),
                    current: DocumentFingerprint(data: existing)
                )
            }
        } else {
            try data.write(to: sourceURL, options: .atomic)
        }
        try writeJSON(
            ObjectManifest(
                id: entry.id,
                relativePath: entry.relativePath,
                sequence: entry.sequence,
                createdAt: entry.createdAt,
                fingerprint: entry.fingerprint
            ),
            to: directory.appendingPathComponent("manifest.json")
        )
        try execute(
            "INSERT OR IGNORE INTO entries(id, relative_path, sequence, created_at, sha256, byte_count) VALUES(?, ?, ?, ?, ?, ?)",
            bindings: [
                .text(entry.id.uuidString), .text(entry.relativePath), .int(entry.sequence),
                .double(entry.createdAt.timeIntervalSince1970), .text(entry.fingerprint.sha256),
                .int(entry.fingerprint.byteCount),
            ]
        )
    }

    private func rebuildDatabaseFromObjects() throws {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: objectsURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }
        for directory in directories {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let manifest = try decoder.decode(
                    ObjectManifest.self,
                    from: Data(contentsOf: directory.appendingPathComponent("manifest.json"))
                )
                let source = try Data(contentsOf: directory.appendingPathComponent("source.md"))
                guard DocumentFingerprint(data: source) == manifest.fingerprint else {
                    throw VaultRepositoryError.readbackMismatch(
                        expected: manifest.fingerprint,
                        current: DocumentFingerprint(data: source)
                    )
                }
                try importVerified(
                    entry: PrewriteRecoveryReference(
                        id: manifest.id,
                        relativePath: manifest.relativePath,
                        sequence: manifest.sequence,
                        createdAt: manifest.createdAt,
                        fingerprint: manifest.fingerprint
                    ),
                    data: source
                )
            } catch {
                let destination = quarantineURL.appendingPathComponent(directory.lastPathComponent)
                if !fileManager.fileExists(atPath: destination.path) {
                    try? fileManager.moveItem(at: directory, to: destination)
                }
                healthDiagnostic = "At least one recovery object was quarantined: \(error.localizedDescription)"
            }
        }
    }

    private func applyTombstonesBeforeRebuild() throws {
        guard let files = try? fileManager.contentsOfDirectory(at: tombstonesURL, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files where file.pathExtension == "json" {
            guard let object = try? JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: String],
                  let path = object["relative_path"] else { continue }
            let doomed = try entries(relativePath: path)
            try execute("DELETE FROM entries WHERE relative_path = ?", bindings: [.text(path)])
            for entry in doomed {
                let objectURL = objectURL(entry.id)
                if fileManager.fileExists(atPath: objectURL.path) { try fileManager.removeItem(at: objectURL) }
            }
        }
    }

    private func enforceRetention(relativePath: String, keeping limit: Int) throws {
        let entries = try entries(relativePath: relativePath)
        for entry in entries.dropFirst(limit) {
            try execute("DELETE FROM entries WHERE id = ?", bindings: [.text(entry.id.uuidString)])
            let object = objectURL(entry.id)
            if fileManager.fileExists(atPath: object.path) { try fileManager.removeItem(at: object) }
        }
    }

    private func maximumSequence(path: String) throws -> Int {
        try query(
            "SELECT COALESCE(MAX(sequence), 0) FROM entries WHERE relative_path = ?",
            bindings: [.text(path)]
        ).first?.ints.first ?? 0
    }

    private func contains(id: UUID) throws -> Bool {
        !(try query("SELECT 1 FROM entries WHERE id = ? LIMIT 1", bindings: [.text(id.uuidString)])).isEmpty
    }

    private func objectURL(_ id: UUID) -> URL {
        objectsURL.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    private func transactionURL(_ id: UUID) -> URL {
        transactionsURL.appendingPathComponent(id.uuidString.lowercased() + ".json")
    }

    private func openDatabase() throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw VaultRepositoryError.recoveryLedgerUnavailable("Could not open recovery database.")
        }
        database = handle
        sqlite3_busy_timeout(handle, 5_000)
    }

    private func configureAndCreateSchema() throws {
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=FULL")
        try execute("PRAGMA foreign_keys=ON")
        try execute("CREATE TABLE IF NOT EXISTS entries(id TEXT PRIMARY KEY, relative_path TEXT NOT NULL, sequence INTEGER NOT NULL, created_at REAL NOT NULL, sha256 TEXT NOT NULL, byte_count INTEGER NOT NULL, UNIQUE(relative_path, sequence))")
        try execute("CREATE INDEX IF NOT EXISTS entries_path_sequence ON entries(relative_path, sequence DESC)")
    }

    private func validateDatabase() throws {
        guard try query("PRAGMA integrity_check").first?.texts.first == "ok" else {
            throw VaultRepositoryError.recoveryLedgerUnavailable("SQLite integrity check failed.")
        }
    }

    private func quarantineDatabaseFiles() throws {
        try fileManager.createDirectory(at: quarantineURL, withIntermediateDirectories: true)
        let group = quarantineURL.appendingPathComponent("database-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: group, withIntermediateDirectories: false)
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: databaseURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.moveItem(at: source, to: group.appendingPathComponent(source.lastPathComponent))
        }
    }

    private func closeDatabase() {
        if let database { sqlite3_close(database) }
        database = nil
    }

    private enum Binding {
        case text(String)
        case int(Int)
        case double(Double)
    }

    private struct Row {
        var texts: [String] = []
        var ints: [Int] = []
        var doubles: [Double] = []
        var columns: [SQLiteValue] = []
    }

    private enum SQLiteValue {
        case text(String)
        case int(Int)
        case double(Double)
    }

    private func execute(_ sql: String, bindings: [Binding] = []) throws {
        guard let database else { throw VaultRepositoryError.recoveryLedgerUnavailable("Database closed.") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw sqliteError()
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE || sqlite3_column_count(statement) > 0 else {
            throw sqliteError()
        }
    }

    private func query(_ sql: String, bindings: [Binding] = []) throws -> [Row] {
        guard let database else { throw VaultRepositoryError.recoveryLedgerUnavailable("Database closed.") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw sqliteError()
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        var rows: [Row] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else { throw sqliteError() }
            var row = Row()
            for column in 0..<sqlite3_column_count(statement) {
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER:
                    let value = Int(sqlite3_column_int64(statement, column))
                    row.ints.append(value)
                    row.columns.append(.int(value))
                case SQLITE_FLOAT:
                    let value = sqlite3_column_double(statement, column)
                    row.doubles.append(value)
                    row.columns.append(.double(value))
                default:
                    let value = sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
                    row.texts.append(value)
                    row.columns.append(.text(value))
                }
            }
            rows.append(row)
        }
    }

    private func bind(_ bindings: [Binding], to statement: OpaquePointer) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch binding {
            case .text(let value):
                result = value.withCString { sqlite3_bind_text(statement, index, $0, -1, SQLITE_TRANSIENT_RECOVERY) }
            case .int(let value):
                result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
            case .double(let value):
                result = sqlite3_bind_double(statement, index, value)
            }
            guard result == SQLITE_OK else { throw sqliteError() }
        }
    }

    private func sqliteError() -> Error {
        let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
        return VaultRepositoryError.recoveryLedgerUnavailable(message)
    }

    private static func entry(_ row: Row) -> PrewriteRecoveryReference? {
        guard row.columns.count >= 6,
              case .text(let idRaw) = row.columns[0], let id = UUID(uuidString: idRaw),
              case .text(let path) = row.columns[1],
              case .int(let sequence) = row.columns[2],
              case .double(let created) = row.columns[3],
              case .text(let sha256) = row.columns[4],
              case .int(let byteCount) = row.columns[5] else { return nil }
        return PrewriteRecoveryReference(
            id: id,
            relativePath: path,
            sequence: sequence,
            createdAt: Date(timeIntervalSince1970: created),
            fingerprint: DocumentFingerprint(sha256: sha256, byteCount: byteCount)
        )
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: [.atomic])
    }

    private static func pathDigest(_ path: String) -> String {
        SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private let SQLITE_TRANSIENT_RECOVERY = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
