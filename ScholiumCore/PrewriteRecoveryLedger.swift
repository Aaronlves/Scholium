import CryptoKit
import Darwin
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

    struct SettledPin: Hashable, Sendable {
        let id: UUID
        let noteID: UUID
        let entry: PrewriteRecoveryReference
        let createdAt: Date
        let settledOrder: Int
    }

    struct SettledPinOutcome: Sendable {
        let pin: SettledPin
        let wasCreated: Bool
    }

    private struct SettledPinManifest: Codable, Hashable {
        let id: UUID
        let noteID: UUID
        let entryID: UUID
        let createdAt: Date
        let fingerprint: DocumentFingerprint
        /// Added after the initial manifest schema. A missing value denotes a
        /// legacy manifest and is deterministically assigned during rebuild.
        let settledOrder: Int?
    }

    private struct VerifiedSettledPinManifest {
        let manifest: SettledPinManifest
        let entry: PrewriteRecoveryReference
        let settledOrder: Int
    }

    struct MutationTransaction: Codable, Hashable, Sendable {
        let id: UUID
        let relativePath: String
        let expected: DocumentFingerprint
        let candidate: DocumentFingerprint
        let createdAt: Date
        var retainedReason: String?
        var cleanupPending: VaultMutationCleanupTask?
    }

    private struct VerifiedMutation {
        let transaction: MutationTransaction
        let candidate: Data
    }

    private let rootURL: URL
    private let objectsURL: URL
    private let transactionsURL: URL
    private let mutationTransactionsURL: URL
    private let remapsURL: URL
    private let tombstonesURL: URL
    private let quarantineURL: URL
    private let settledPinsURL: URL
    private let settledPinStorage: SecureRecordDirectory
    private let mutationStorage: SecureRecordDirectory
    private let mutationByteAccess: VaultDescriptorAccess
    private let settledPinLock: AdvisoryFileLock
    private let databaseURL: URL
    private let legacyVersionsURL: URL
    private let migrationMarkerURL: URL
    private let fileManager: FileManager
    private let cleanupHooks: VaultMutationHooks
    private var database: OpaquePointer?
    private(set) var healthDiagnostic: String?
    private var writeBlocker: String?

    init(
        storageURL: URL,
        vaultURL: URL? = nil,
        cleanupHooks: VaultMutationHooks = .none,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(
            at: storageURL,
            withIntermediateDirectories: true
        )
        self.fileManager = fileManager
        self.cleanupHooks = cleanupHooks
        rootURL = storageURL.appendingPathComponent("recovery-v2", isDirectory: true)
        objectsURL = rootURL.appendingPathComponent("objects", isDirectory: true)
        transactionsURL = rootURL.appendingPathComponent("transactions", isDirectory: true)
        mutationTransactionsURL = transactionsURL.appendingPathComponent("mutations", isDirectory: true)
        remapsURL = rootURL.appendingPathComponent("remaps", isDirectory: true)
        tombstonesURL = rootURL.appendingPathComponent("tombstones", isDirectory: true)
        quarantineURL = rootURL.appendingPathComponent("quarantine", isDirectory: true)
        settledPinsURL = rootURL.appendingPathComponent("settled", isDirectory: true)
        settledPinStorage = SecureRecordDirectory(
            trustedRootURL: storageURL,
            components: ["recovery-v2", "settled"],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: 64 * 1024
        )
        mutationStorage = SecureRecordDirectory(
            trustedRootURL: storageURL,
            components: ["recovery-v2", "transactions", "mutations"],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: .max
        )
        mutationByteAccess = VaultDescriptorAccess(rootURL: mutationTransactionsURL)
        do {
            settledPinLock = try AdvisoryFileLock(
                directory: settledPinStorage,
                fileName: ".settled-pins.lock"
            )
        } catch {
            throw VaultRepositoryError.recoveryLedgerUnavailable(
                "The settled snapshot coordination lock is unavailable: \(error.localizedDescription)"
            )
        }
        databaseURL = rootURL.appendingPathComponent("history.sqlite")
        legacyVersionsURL = storageURL.appendingPathComponent("versions", isDirectory: true)
        migrationMarkerURL = rootURL.appendingPathComponent("v1-migration-complete.json")
        for directory in [
            rootURL, objectsURL, transactionsURL, mutationTransactionsURL,
            remapsURL, tombstonesURL, quarantineURL, settledPinsURL,
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
        try settledPinLock.withExclusiveLock {
            try applyTombstonesBeforeRebuild()
            try reconcileSettledPinManifests()
        }
        try migrateLegacyV1IfNeeded()
        if let vaultURL {
            try replayMutationTransactions(vaultURL: vaultURL)
        }
    }

    deinit { closeDatabase() }

    func prepare(relativePath: String, data: Data) throws -> PrewriteRecoveryReference {
        try settledPinLock.withExclusiveLock {
            try reconcileSettledPinManifests()
            return try prepareLocked(relativePath: relativePath, data: data)
        }
    }

    private func prepareLocked(
        relativePath: String,
        data: Data
    ) throws -> PrewriteRecoveryReference {
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
        try settledPinLock.withExclusiveLock {
            try reconcileSettledPinManifests()
            try commitLocked(entry)
        }
    }

    private func commitLocked(_ entry: PrewriteRecoveryReference) throws {
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

    func pinSettled(
        relativePath: String,
        noteID: UUID,
        data: Data,
        createdAt: Date = Date()
    ) throws -> SettledPinOutcome {
        try settledPinLock.withExclusiveLock {
            // Recover any prior process that committed a manifest before its
            // derived row, then allocate a unique monotonic order while every
            // cooperating ledger is excluded by the same machine-local lock.
            try reconcileSettledPinManifests()
            return try pinSettledLocked(
                relativePath: relativePath,
                noteID: noteID,
                data: data,
                createdAt: createdAt
            )
        }
    }

    private func pinSettledLocked(
        relativePath: String,
        noteID: UUID,
        data: Data,
        createdAt: Date
    ) throws -> SettledPinOutcome {
        if let writeBlocker {
            throw VaultRepositoryError.recoveryLedgerUnavailable(writeBlocker)
        }
        let path = try MarkdownRelativePath(relativePath).rawValue
        let fingerprint = DocumentFingerprint(data: data)
        if let existing = try settledPins(noteID: noteID).first(where: {
            $0.entry.fingerprint == fingerprint
        }) {
            return SettledPinOutcome(pin: existing, wasCreated: false)
        }

        let matchingEntry = try entries(relativePath: path).first(where: {
            $0.fingerprint == fingerprint
        })
        let entry: PrewriteRecoveryReference
        let createdEntry: Bool
        if let matchingEntry {
            entry = matchingEntry
            createdEntry = false
        } else {
            entry = try prepareLocked(relativePath: path, data: data)
            createdEntry = true
        }
        let durableCreatedAt = Date(
            timeIntervalSince1970: floor(createdAt.timeIntervalSince1970)
        )
        let previousSettledOrder = try maximumSettledOrder(noteID: noteID)
        guard previousSettledOrder < Int.max else {
            throw VaultRepositoryError.recoveryLedgerUnavailable(
                "The settled snapshot order is exhausted for this Note."
            )
        }
        let pin = SettledPin(
            id: UUID(),
            noteID: noteID,
            entry: entry,
            createdAt: durableCreatedAt,
            settledOrder: previousSettledOrder + 1
        )
        var manifestWasCommitted = false
        do {
            if createdEntry { try commitLocked(entry) }
            try writeSettledPinManifest(
                SettledPinManifest(
                    id: pin.id,
                    noteID: pin.noteID,
                    entryID: pin.entry.id,
                    createdAt: pin.createdAt,
                    fingerprint: pin.entry.fingerprint,
                    settledOrder: pin.settledOrder
                )
            )
            manifestWasCommitted = true
            do {
                try execute(
                    "INSERT INTO settled_snapshots(id, note_id, entry_id, settled_at, settled_order) VALUES(?, ?, ?, ?, ?)",
                    bindings: [
                        .text(pin.id.uuidString),
                        .text(pin.noteID.uuidString),
                        .text(pin.entry.id.uuidString),
                        .double(pin.createdAt.timeIntervalSince1970),
                        .int(pin.settledOrder),
                    ]
                )
            } catch {
                // The manifest is authoritative. Repair the derived row
                // immediately when possible rather than requiring restart.
                try reconcileSettledPinManifests()
                guard try settledPins(noteID: noteID).contains(where: {
                    $0.id == pin.id
                        && $0.entry.id == pin.entry.id
                        && $0.settledOrder == pin.settledOrder
                }) else {
                    throw error
                }
            }
            return SettledPinOutcome(pin: pin, wasCreated: true)
        } catch {
            // Once the durable manifest is committed it remains the authority
            // from which SQLite can be rebuilt. Do not erase exact bytes merely
            // because the derived row could not be updated.
            if !manifestWasCommitted {
                try? execute(
                    "DELETE FROM settled_snapshots WHERE id = ?",
                    bindings: [.text(pin.id.uuidString)]
                )
                if createdEntry { try? discardLocked(entry) }
            }
            throw error
        }
    }

    func settledPins(noteID: UUID? = nil) throws -> [SettledPin] {
        let sql: String
        let bindings: [Binding]
        if let noteID {
            sql = "SELECT s.id, s.note_id, e.id, e.relative_path, e.sequence, e.created_at, s.settled_at, s.settled_order, e.sha256, e.byte_count FROM settled_snapshots s JOIN entries e ON e.id = s.entry_id WHERE s.note_id = ? ORDER BY s.settled_order DESC, s.id ASC"
            bindings = [.text(noteID.uuidString)]
        } else {
            sql = "SELECT s.id, s.note_id, e.id, e.relative_path, e.sequence, e.created_at, s.settled_at, s.settled_order, e.sha256, e.byte_count FROM settled_snapshots s JOIN entries e ON e.id = s.entry_id ORDER BY s.note_id ASC, s.settled_order DESC, s.id ASC"
            bindings = []
        }
        return try query(sql, bindings: bindings).compactMap(Self.settledPin)
    }

    func settledSnapshotIDsToRemove(maximumCount: Int?) throws -> Set<UUID> {
        try settledPinLock.withExclusiveLock {
            try reconcileSettledPinManifests()
            return try settledSnapshotIDsToRemoveLocked(maximumCount: maximumCount)
        }
    }

    private func settledSnapshotIDsToRemoveLocked(
        maximumCount: Int?
    ) throws -> Set<UUID> {
        if let writeBlocker {
            throw VaultRepositoryError.recoveryLedgerUnavailable(writeBlocker)
        }
        guard let maximumCount else { return [] }
        let grouped = Dictionary(grouping: try settledPins(), by: \.noteID)
        return Set(grouped.values.flatMap { pins in
            pins.dropFirst(maximumCount).map(\.id)
        })
    }

    @discardableResult
    func removeSettledPins(_ ids: Set<UUID>) throws -> Int {
        try settledPinLock.withExclusiveLock {
            try reconcileSettledPinManifests()
            return try removeSettledPinsLocked(ids)
        }
    }

    @discardableResult
    private func removeSettledPinsLocked(_ ids: Set<UUID>) throws -> Int {
        if let writeBlocker {
            throw VaultRepositoryError.recoveryLedgerUnavailable(writeBlocker)
        }
        guard !ids.isEmpty else { return 0 }
        let existing = try settledPins().filter { ids.contains($0.id) }
        for pin in existing {
            let manifest = settledPinURL(pin.id)
            if fileManager.fileExists(atPath: manifest.path) {
                try settledPinStorage.removeIfPresent(
                    directory: nil,
                    fileName: manifest.lastPathComponent
                )
            }
            try execute(
                "DELETE FROM settled_snapshots WHERE id = ?",
                bindings: [.text(pin.id.uuidString)]
            )
        }
        for path in Set(existing.map(\.entry.relativePath)) {
            try enforceRetention(relativePath: path, keeping: 10)
        }
        return existing.count
    }

    func discard(_ entry: PrewriteRecoveryReference) throws {
        try settledPinLock.withExclusiveLock {
            try discardLocked(entry)
        }
    }

    private func discardLocked(_ entry: PrewriteRecoveryReference) throws {
        try removeSettledPinManifestsLocked(entryIDs: [entry.id])
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
            retainedReason: nil,
            cleanupPending: nil
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
            try writeMutationManifest(transaction)
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

    func persistCleanupPending(_ transaction: MutationTransaction) throws {
        guard let cleanup = transaction.cleanupPending else {
            throw VaultRepositoryError.recoveryLedgerUnavailable(
                "The source transaction has no cleanup task."
            )
        }
        try cleanupHooks.cleanupPersistenceOverride?()
        try validateCleanupTask(cleanup, for: transaction)
        try writeMutationManifest(transaction)
    }

    func attemptCommittedCleanup(
        _ transaction: MutationTransaction,
        vaultURL: URL
    ) -> SaveCleanupWarning? {
        guard let cleanup = transaction.cleanupPending else { return nil }
        do {
            try cleanupHooks.didReach?(.cleanup)
            try cleanupHooks.cleanupOverride?()
            try validateCleanupTask(cleanup, for: transaction)
            try removeCleanup(
                cleanup,
                transactionID: transaction.id,
                vaultURL: vaultURL,
                expectedIdentity: cleanup.displacedSource
            )
            return nil
        } catch {
            healthDiagnostic = "The note was saved, but its displaced source cleanup is pending: \(error.localizedDescription)"
            return SaveCleanupWarning(
                kind: .displacedSourceCopy,
                message: "The note was saved, but its displaced source copy could not be removed. Scholium will retry cleanup when this vault reopens."
            )
        }
    }

    func cleanupStagedCandidate(
        _ transaction: MutationTransaction,
        task: VaultMutationCleanupTask,
        vaultURL: URL
    ) throws {
        guard transaction.cleanupPending == task else {
            throw VaultRepositoryError.recoveryLedgerUnavailable(
                "The staged-candidate cleanup task changed before removal."
            )
        }
        try cleanupHooks.didReach?(.cleanup)
        try cleanupHooks.cleanupOverride?()
        try validateCleanupTask(task, for: transaction)
        try removeCleanup(
            task,
            transactionID: transaction.id,
            vaultURL: vaultURL,
            expectedIdentity: task.stagedCandidate
        )
    }

    /// Completes a verified source transaction only after its displaced copy
    /// was removed. Pending cleanup remains durable and never changes the
    /// already-proven source commit into a save failure.
    func finishCommittedMutation(
        _ transaction: MutationTransaction,
        cleanupCompleted: Bool,
        cleanupWarning: SaveCleanupWarning?
    ) -> SaveCleanupWarning? {
        if transaction.cleanupPending != nil, !cleanupCompleted {
            if cleanupWarning == nil {
                healthDiagnostic = "The note was saved, but its displaced source cleanup is pending until the vault reopens."
            }
            return cleanupWarning
                ?? SaveCleanupWarning(
                    kind: .displacedSourceCopy,
                    message: "The note was saved, but its displaced source copy could not be removed. Scholium will retry cleanup when this vault reopens."
                )
        }
        do {
            try cleanupHooks.cleanupRecordRemovalOverride?()
            try completeMutation(transaction)
            return cleanupWarning
        } catch {
            healthDiagnostic = "The committed save was verified, but its transaction record could not be removed: \(error.localizedDescription)"
            return SaveCleanupWarning(
                kind: .transactionRecord,
                message: "The note was saved, but its machine-local transaction record could not be removed. Scholium will retry cleanup when this vault reopens."
            )
        }
    }

    func retainMutation(_ transaction: MutationTransaction, reason: String) throws {
        let directory = mutationTransactionURL(transaction.id)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        var retained = transaction
        retained.retainedReason = reason
        try writeMutationManifest(retained)
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

    /// Returns only transactions that startup or a failed commit explicitly
    /// retained for researcher recovery. Exact bytes and manifest identity are
    /// revalidated through no-follow descriptor reads before any entry becomes
    /// delivery-visible.
    func retainedMutations() throws -> [MutationTransaction] {
        try pendingMutations().compactMap { transaction in
            guard transaction.retainedReason != nil else { return nil }
            return try verifiedMutation(matching: transaction).transaction
        }
    }

    func retainedMutation(id: UUID) throws -> MutationTransaction {
        guard let transaction = try pendingMutations().first(where: { $0.id == id }),
              transaction.retainedReason != nil else {
            throw VaultRepositoryError.recoveryEntryNotFound(id)
        }
        return try verifiedMutation(matching: transaction).transaction
    }

    func candidateData(for transaction: MutationTransaction) throws -> Data {
        try verifiedMutation(matching: transaction).candidate
    }

    func retainedMutationDirectory(for transaction: MutationTransaction) throws -> URL {
        _ = try verifiedMutation(matching: transaction)
        return mutationTransactionURL(transaction.id)
    }

    private func verifiedMutation(
        matching reference: MutationTransaction,
        requiresRetention: Bool = true
    ) throws -> VerifiedMutation {
        let directoryName = reference.id.uuidString.lowercased()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest: MutationTransaction
        do {
            manifest = try decoder.decode(
                MutationTransaction.self,
                from: mutationStorage.read(
                    directory: directoryName,
                    fileName: "manifest.json"
                )
            )
        } catch {
            throw VaultRepositoryError.recoveryLedgerUnavailable(
                "The interrupted save manifest could not be verified: \(error.localizedDescription)"
            )
        }
        guard manifest.id == reference.id,
              manifest.relativePath == reference.relativePath,
              manifest.expected == reference.expected,
              manifest.candidate == reference.candidate,
              manifest.createdAt == reference.createdAt,
              (!requiresRetention || manifest.retainedReason != nil) else {
            throw VaultRepositoryError.recoveryLedgerUnavailable(
                "The interrupted save manifest changed after it was listed."
            )
        }
        _ = try MarkdownRelativePath(manifest.relativePath)
        let expected: Data
        let candidate: Data
        do {
            expected = try mutationByteAccess.read(
                MarkdownRelativePath("\(directoryName)/expected.md")
            )
            candidate = try mutationByteAccess.read(
                MarkdownRelativePath("\(directoryName)/candidate.md")
            )
        } catch {
            throw VaultRepositoryError.recoveryLedgerUnavailable(
                "The interrupted save bytes could not be read safely: \(error.localizedDescription)"
            )
        }
        let observedExpected = DocumentFingerprint(data: expected)
        let observedCandidate = DocumentFingerprint(data: candidate)
        guard observedExpected == manifest.expected,
              observedCandidate == manifest.candidate else {
            throw VaultRepositoryError.recoveryLedgerUnavailable(
                "The interrupted save bytes no longer match their recorded fingerprints."
            )
        }
        return VerifiedMutation(
            transaction: manifest,
            candidate: candidate
        )
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
        try settledPinLock.withExclusiveLock {
            try tombstoneAndPurgeLocked(relativePath: relativePath)
        }
    }

    private func tombstoneAndPurgeLocked(relativePath: String) throws {
        _ = try MarkdownRelativePath(relativePath)
        let digest = Self.pathDigest(relativePath)
        let tombstone = tombstonesURL.appendingPathComponent("\(digest).json")
        try writeJSON(
            ["relative_path": relativePath, "created_at": ISO8601DateFormatter().string(from: Date())],
            to: tombstone
        )
        let doomed = try entries(relativePath: relativePath)
        try removeSettledPinManifestsLocked(entryIDs: Set(doomed.map(\.id)))
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
        let descriptorAccess = VaultDescriptorAccess(rootURL: canonicalRoot)
        for transaction in try pendingMutations() {
            do {
                _ = try verifiedMutation(
                    matching: transaction,
                    requiresRetention: false
                )
                let path = try MarkdownRelativePath(transaction.relativePath)
                let observedData: Data
                do {
                    observedData = try descriptorAccess.read(path)
                } catch VaultRepositoryError.fileDoesNotExist {
                    healthDiagnostic = "A pending save transaction has no unambiguous canonical file and was retained."
                    continue
                } catch VaultRepositoryError.notRegularFile {
                    healthDiagnostic = "A pending save transaction resolved to an unsafe file identity and was retained."
                    continue
                }
                let observed = DocumentFingerprint(data: observedData)
                if observed == transaction.candidate,
                   let cleanup = transaction.cleanupPending {
                    do {
                        try validateCleanupTask(cleanup, for: transaction)
                        try removeCleanup(
                            cleanup,
                            transactionID: transaction.id,
                            vaultURL: vaultURL,
                            expectedIdentity: cleanup.displacedSource
                        )
                        try completeMutation(transaction)
                    } catch {
                        healthDiagnostic = "A committed save's displaced source cleanup remains pending: \(error.localizedDescription)"
                    }
                } else if observed == transaction.candidate {
                    try completeMutation(transaction)
                } else if observed == transaction.expected {
                    if let cleanup = transaction.cleanupPending {
                        do {
                            try validateCleanupTask(cleanup, for: transaction)
                            try removeCleanup(
                                cleanup,
                                transactionID: transaction.id,
                                vaultURL: vaultURL,
                                expectedIdentity: cleanup.stagedCandidate
                            )
                        } catch {
                            healthDiagnostic = "An interrupted save's staged candidate cleanup remains pending: \(error.localizedDescription)"
                            continue
                        }
                    }
                    if transaction.expected == transaction.candidate {
                        try completeMutation(transaction)
                    } else {
                        try retainMutation(
                            transaction,
                            reason: "The previous process ended before the candidate revision became canonical. The canonical source remains at its expected revision and the candidate bytes remain in machine-local recovery."
                        )
                    }
                } else {
                    healthDiagnostic = "A pending save transaction observed bytes other than its expected or candidate revision and was retained."
                }
            } catch {
                healthDiagnostic = "A pending save transaction could not be verified and was retained: \(error.localizedDescription)"
            }
        }
    }

    private func removeCleanup(
        _ task: VaultMutationCleanupTask,
        transactionID: UUID,
        vaultURL: URL,
        expectedIdentity: VaultMutationCleanupIdentity
    ) throws {
        let path = try MarkdownRelativePath(task.relativePath)
        guard Self.isValidSwapStagingName(task.stagingName) else {
            throw VaultRepositoryError.recoveryLedgerUnavailable(
                "The cleanup task contains an unsafe staging name."
            )
        }
        let descriptorAccess = VaultDescriptorAccess(rootURL: vaultURL)
        try descriptorAccess.withParentDescriptor(path) { parentDescriptor, _ in
            let cleanupDirectoryName = Self.cleanupDirectoryName(
                for: task.stagingName
            )
            let isolatedName = "source-\(transactionID.uuidString.lowercased()).md"
            let stagingPresence = VaultDescriptorAccess.presence(
                name: task.stagingName,
                parentDescriptor: parentDescriptor
            )
            let directoryPresence = VaultDescriptorAccess.presence(
                name: cleanupDirectoryName,
                parentDescriptor: parentDescriptor
            )
            if directoryPresence == .absent, stagingPresence == .absent {
                return
            }
            if case .inaccessible(let code) = directoryPresence {
                throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
            }
            var validatedStagingIdentity: VaultDescriptorAccess.FileIdentity?
            if directoryPresence == .absent {
                switch stagingPresence {
                case .present:
                    validatedStagingIdentity = try validateCleanupSource(
                        task,
                        expectedIdentity: expectedIdentity,
                        parentDescriptor: parentDescriptor
                    )
                case .inaccessible(let code):
                    throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
                case .absent:
                    return
                }
                guard mkdirat(parentDescriptor, cleanupDirectoryName, 0o700) == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            }
            let cleanupDescriptor = openat(
                parentDescriptor,
                cleanupDirectoryName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            guard cleanupDescriptor >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            do {
                var directoryStatus = stat()
                guard fstat(cleanupDescriptor, &directoryStatus) == 0,
                      (directoryStatus.st_mode & S_IFMT) == S_IFDIR,
                      directoryStatus.st_uid == geteuid(),
                      (directoryStatus.st_mode & 0o077) == 0 else {
                    throw VaultRepositoryError.recoveryPathConflict(
                        cleanupDirectoryName
                    )
                }
                switch VaultDescriptorAccess.presence(
                    name: isolatedName,
                    parentDescriptor: cleanupDescriptor
                ) {
                case .present:
                    switch stagingPresence {
                    case .absent:
                        break
                    case .inaccessible(let code):
                        throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
                    case .present:
                        throw VaultRepositoryError.recoveryPathConflict(
                            task.stagingName
                        )
                    }
                    try removeIsolatedCleanup(
                        name: isolatedName,
                        expectedIdentity: expectedIdentity,
                        parentDescriptor: cleanupDescriptor
                    )
                case .inaccessible(let code):
                    throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
                case .absent:
                    switch stagingPresence {
                    case .absent:
                        break
                    case .inaccessible(let code):
                        throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
                    case .present:
                        let openedIdentity: VaultDescriptorAccess.FileIdentity
                        if let validatedStagingIdentity {
                            openedIdentity = validatedStagingIdentity
                        } else {
                            openedIdentity = try validateCleanupSource(
                                task,
                                expectedIdentity: expectedIdentity,
                                parentDescriptor: parentDescriptor
                            )
                        }
                        guard renameatx_np(
                            parentDescriptor,
                            task.stagingName,
                            cleanupDescriptor,
                            isolatedName,
                            UInt32(RENAME_EXCL)
                        ) == 0 else {
                            throw POSIXError(
                                POSIXErrorCode(rawValue: errno) ?? .EIO
                            )
                        }
                        guard try VaultDescriptorAccess.identity(
                            name: isolatedName,
                            parentDescriptor: cleanupDescriptor
                        ) == openedIdentity else {
                            _ = renameatx_np(
                                cleanupDescriptor,
                                isolatedName,
                                parentDescriptor,
                                task.stagingName,
                                UInt32(RENAME_EXCL)
                            )
                            throw VaultRepositoryError.recoveryPathConflict(
                                task.stagingName
                            )
                        }
                        try synchronizeCleanupParent(parentDescriptor)
                        try synchronizeCleanupParent(cleanupDescriptor)
                        try removeIsolatedCleanup(
                            name: isolatedName,
                            expectedIdentity: expectedIdentity,
                            parentDescriptor: cleanupDescriptor
                        )
                    }
                }
                try synchronizeCleanupParent(cleanupDescriptor)
            } catch {
                close(cleanupDescriptor)
                throw error
            }
            close(cleanupDescriptor)
            guard unlinkat(
                parentDescriptor,
                cleanupDirectoryName,
                AT_REMOVEDIR
            ) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            try synchronizeCleanupParent(parentDescriptor)
            switch VaultDescriptorAccess.presence(
                name: task.stagingName,
                parentDescriptor: parentDescriptor
            ) {
            case .absent:
                break
            case .present:
                throw VaultRepositoryError.recoveryPathConflict(
                    task.stagingName
                )
            case .inaccessible(let code):
                throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
            }
        }
    }

    private func validateCleanupSource(
        _ task: VaultMutationCleanupTask,
        expectedIdentity: VaultMutationCleanupIdentity,
        parentDescriptor: Int32
    ) throws -> VaultDescriptorAccess.FileIdentity {
        let fd = openat(
            parentDescriptor,
            task.stagingName,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(fd) }
        var openedStatus = stat()
        guard fstat(fd, &openedStatus) == 0,
              (openedStatus.st_mode & S_IFMT) == S_IFREG else {
            throw VaultRepositoryError.notRegularFile(task.stagingName)
        }
        guard openedStatus.st_nlink == 1 else {
            throw VaultRepositoryError.recoveryPathConflict(task.stagingName)
        }
        let openedIdentity = VaultDescriptorAccess.FileIdentity(openedStatus)
        guard UInt64(openedIdentity.device) == expectedIdentity.device,
              UInt64(openedIdentity.inode) == expectedIdentity.inode else {
            throw VaultRepositoryError.recoveryPathConflict(task.stagingName)
        }
        let data = try VaultDescriptorAccess.readAll(from: fd)
        var finalStatus = stat()
        guard fstat(fd, &finalStatus) == 0,
              VaultDescriptorAccess.FileIdentity(finalStatus) == openedIdentity,
              finalStatus.st_nlink == 1,
              Int(finalStatus.st_size) == data.count,
              DocumentFingerprint(data: data) == expectedIdentity.fingerprint,
              try VaultDescriptorAccess.identity(
                  name: task.stagingName,
                  parentDescriptor: parentDescriptor
              ) == openedIdentity else {
            throw VaultRepositoryError.recoveryPathConflict(task.stagingName)
        }
        return openedIdentity
    }

    private func removeIsolatedCleanup(
        name: String,
        expectedIdentity: VaultMutationCleanupIdentity,
        parentDescriptor: Int32
    ) throws {
        let fd = openat(
            parentDescriptor,
            name,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(fd) }
        var openedStatus = stat()
        guard fstat(fd, &openedStatus) == 0,
              (openedStatus.st_mode & S_IFMT) == S_IFREG else {
            throw VaultRepositoryError.notRegularFile(name)
        }
        guard openedStatus.st_nlink == 1 else {
            throw VaultRepositoryError.recoveryPathConflict(name)
        }
        let openedIdentity = VaultDescriptorAccess.FileIdentity(openedStatus)
        guard UInt64(openedIdentity.device) == expectedIdentity.device,
              UInt64(openedIdentity.inode) == expectedIdentity.inode else {
            throw VaultRepositoryError.recoveryPathConflict(name)
        }
        let data = try VaultDescriptorAccess.readAll(from: fd)
        try cleanupHooks.cleanupIsolationOverride?()
        guard lseek(fd, 0, SEEK_SET) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let finalData = try VaultDescriptorAccess.readAll(from: fd)
        var finalStatus = stat()
        guard fstat(fd, &finalStatus) == 0,
              VaultDescriptorAccess.FileIdentity(finalStatus) == openedIdentity,
              finalStatus.st_nlink == 1,
              Int(finalStatus.st_size) == finalData.count,
              DocumentFingerprint(data: data) == expectedIdentity.fingerprint,
              DocumentFingerprint(data: finalData) == expectedIdentity.fingerprint else {
            throw VaultRepositoryError.recoveryPathConflict(name)
        }
        guard try VaultDescriptorAccess.identity(
            name: name,
            parentDescriptor: parentDescriptor
        ) == openedIdentity else {
            throw VaultRepositoryError.recoveryPathConflict(name)
        }
        guard unlinkat(parentDescriptor, name, 0) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard VaultDescriptorAccess.presence(
            name: name,
            parentDescriptor: parentDescriptor
        ) == .absent else {
            throw VaultRepositoryError.commitUncertain(
                "The isolated cleanup path was not absent after removal."
            )
        }
    }

    private func synchronizeCleanupParent(_ parentDescriptor: Int32) throws {
        guard fsync(parentDescriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func validateCleanupTask(
        _ task: VaultMutationCleanupTask,
        for transaction: MutationTransaction
    ) throws {
        guard task.relativePath == transaction.relativePath,
              task.displacedSource.fingerprint == transaction.expected,
              task.stagedCandidate.fingerprint == transaction.candidate,
              Self.isValidSwapStagingName(task.stagingName) else {
            throw VaultRepositoryError.recoveryLedgerUnavailable(
                "The cleanup task does not match its source transaction."
            )
        }
    }

    private static func isValidSwapStagingName(_ name: String) -> Bool {
        let prefix = ".scholium-swap-"
        let suffix = ".md"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return false }
        let uuidStart = name.index(name.startIndex, offsetBy: prefix.count)
        let uuidEnd = name.index(name.endIndex, offsetBy: -suffix.count)
        let spelling = String(name[uuidStart..<uuidEnd])
        guard let uuid = UUID(uuidString: spelling) else { return false }
        return spelling == uuid.uuidString.lowercased()
    }

    private static func cleanupDirectoryName(for stagingName: String) -> String {
        let replaced = stagingName.replacingOccurrences(
            of: ".scholium-swap-",
            with: ".scholium-cleanup-",
            options: [.anchored]
        )
        return String(replaced.dropLast(3))
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

    private func reconcileSettledPinManifests() throws {
        let files = try fileManager.contentsOfDirectory(
            at: settledPinsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ).filter { $0.pathExtension == "json" }
        var decoded: [(SettledPinManifest, PrewriteRecoveryReference)] = []
        var manifestIDs: Set<UUID> = []
        for file in files {
            do {
                let values = try file.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                )
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    throw VaultRepositoryError.recoveryLedgerUnavailable(
                        "A settled snapshot reference is linked or is not a regular file."
                    )
                }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let manifest = try decoder.decode(
                    SettledPinManifest.self,
                    from: Data(contentsOf: file)
                )
                guard file.deletingPathExtension().lastPathComponent
                        == manifest.id.uuidString.lowercased(),
                      let entry = try entry(id: manifest.entryID),
                      entry.fingerprint == manifest.fingerprint,
                      manifest.createdAt.timeIntervalSince1970.isFinite,
                      manifest.settledOrder.map({ $0 > 0 }) ?? true else {
                    throw VaultRepositoryError.recoveryLedgerUnavailable(
                        "A settled snapshot reference does not match its exact recovery bytes."
                    )
                }
                decoded.append((manifest, entry))
                manifestIDs.insert(manifest.id)
            } catch {
                healthDiagnostic = "At least one settled snapshot reference is unavailable: \(error.localizedDescription)"
            }
        }

        var verified: [VerifiedSettledPinManifest] = []
        for group in Dictionary(grouping: decoded, by: { $0.0.noteID }).values {
            let legacy = group.filter { $0.0.settledOrder == nil }.sorted { lhs, rhs in
                if lhs.0.createdAt != rhs.0.createdAt {
                    return lhs.0.createdAt < rhs.0.createdAt
                }
                if lhs.1.sequence != rhs.1.sequence {
                    return lhs.1.sequence < rhs.1.sequence
                }
                return lhs.0.id.uuidString < rhs.0.id.uuidString
            }
            verified.append(contentsOf: legacy.enumerated().map { offset, value in
                VerifiedSettledPinManifest(
                    manifest: value.0,
                    entry: value.1,
                    settledOrder: offset + 1
                )
            })
            let explicitOrderCounts = Dictionary(
                grouping: group.compactMap { $0.0.settledOrder },
                by: { $0 }
            ).mapValues(\.count)
            verified.append(contentsOf: group.compactMap { value in
                let manifest = value.0
                let entry = value.1
                guard let order = manifest.settledOrder else { return nil }
                guard order > legacy.count,
                      explicitOrderCounts[order] == 1 else {
                    let reason = "At least one settled snapshot reference has an ambiguous durable order."
                    healthDiagnostic = reason
                    writeBlocker = reason
                    return nil
                }
                return VerifiedSettledPinManifest(
                    manifest: manifest,
                    entry: entry,
                    settledOrder: order
                )
            })
        }

        for verifiedManifest in verified {
            do {
                let manifest = verifiedManifest.manifest
                let entry = verifiedManifest.entry
                let exactRowExists = !(try query(
                    "SELECT 1 FROM settled_snapshots WHERE id = ? AND note_id = ? AND entry_id = ? AND settled_at = ? AND settled_order = ? LIMIT 1",
                    bindings: [
                        .text(manifest.id.uuidString),
                        .text(manifest.noteID.uuidString),
                        .text(entry.id.uuidString),
                        .double(manifest.createdAt.timeIntervalSince1970),
                        .int(verifiedManifest.settledOrder),
                    ]
                )).isEmpty
                if !exactRowExists {
                    try execute("BEGIN IMMEDIATE")
                    do {
                        try execute(
                            "INSERT INTO settled_snapshots(id, note_id, entry_id, settled_at, settled_order) VALUES(?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET note_id = excluded.note_id, entry_id = excluded.entry_id, settled_at = excluded.settled_at, settled_order = excluded.settled_order",
                            bindings: [
                                .text(manifest.id.uuidString),
                                .text(manifest.noteID.uuidString),
                                .text(entry.id.uuidString),
                                .double(manifest.createdAt.timeIntervalSince1970),
                                .int(verifiedManifest.settledOrder),
                            ]
                        )
                        try execute("COMMIT")
                    } catch {
                        try? execute("ROLLBACK")
                        throw error
                    }
                }
            } catch {
                let reason = "At least one settled snapshot reference cannot be projected safely: \(error.localizedDescription)"
                healthDiagnostic = reason
                writeBlocker = reason
            }
        }
        let databasePins = try settledPins()
        for pin in databasePins where !manifestIDs.contains(pin.id) {
            try execute(
                "DELETE FROM settled_snapshots WHERE id = ?",
                bindings: [.text(pin.id.uuidString)]
            )
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
            try removeSettledPinManifestsLocked(entryIDs: Set(doomed.map(\.id)))
            try execute("DELETE FROM entries WHERE relative_path = ?", bindings: [.text(path)])
            for entry in doomed {
                let objectURL = objectURL(entry.id)
                if fileManager.fileExists(atPath: objectURL.path) { try fileManager.removeItem(at: objectURL) }
            }
        }
    }

    private func enforceRetention(relativePath: String, keeping limit: Int) throws {
        // A validated manifest that cannot be projected safely is a recovery
        // authority fault, not permission to collect bytes. Preserve all
        // entries until the ambiguity is repaired.
        guard writeBlocker == nil else { return }
        let entries = try entries(relativePath: relativePath)
        var pinnedEntryIDs = Set(try query(
            "SELECT s.entry_id FROM settled_snapshots s JOIN entries e ON e.id = s.entry_id WHERE e.relative_path = ?",
            bindings: [.text(relativePath)]
        ).compactMap { row -> UUID? in
            guard case .text(let raw)? = row.columns.first else { return nil }
            return UUID(uuidString: raw)
        })
        // A fully validated manifest continues to protect its exact bytes even
        // when its derived row cannot be projected because order metadata is
        // ambiguous or SQLite is temporarily unavailable.
        pinnedEntryIDs.formUnion(
            try validatedSettledManifestEntryIDs(relativePath: relativePath)
        )
        let unpinned = entries.filter { !pinnedEntryIDs.contains($0.id) }
        for entry in unpinned.dropFirst(limit) {
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

    private func maximumSettledOrder(noteID: UUID) throws -> Int {
        try query(
            "SELECT COALESCE(MAX(settled_order), 0) FROM settled_snapshots WHERE note_id = ?",
            bindings: [.text(noteID.uuidString)]
        ).first?.ints.first ?? 0
    }

    private func contains(id: UUID) throws -> Bool {
        !(try query("SELECT 1 FROM entries WHERE id = ? LIMIT 1", bindings: [.text(id.uuidString)])).isEmpty
    }

    private func entry(id: UUID) throws -> PrewriteRecoveryReference? {
        try query(
            "SELECT id, relative_path, sequence, created_at, sha256, byte_count FROM entries WHERE id = ? LIMIT 1",
            bindings: [.text(id.uuidString)]
        ).first.flatMap(Self.entry)
    }

    private func removeSettledPinManifestsLocked(entryIDs: Set<UUID>) throws {
        guard !entryIDs.isEmpty else { return }
        let files = try fileManager.contentsOfDirectory(
            at: settledPinsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ).filter { $0.pathExtension == "json" }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for file in files {
            let values = try file.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                continue
            }
            guard let manifest = try? decoder.decode(
                SettledPinManifest.self,
                from: Data(contentsOf: file)
            ), entryIDs.contains(manifest.entryID) else {
                continue
            }
            try settledPinStorage.removeIfPresent(
                directory: nil,
                fileName: file.lastPathComponent
            )
        }
    }

    private func validatedSettledManifestEntryIDs(
        relativePath: String
    ) throws -> Set<UUID> {
        let files = try fileManager.contentsOfDirectory(
            at: settledPinsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ).filter { $0.pathExtension == "json" }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var entryIDs: Set<UUID> = []
        for file in files {
            do {
                let values = try file.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                )
                guard values.isRegularFile == true,
                      values.isSymbolicLink != true,
                      let manifest = try? decoder.decode(
                        SettledPinManifest.self,
                        from: Data(contentsOf: file)
                      ),
                      file.deletingPathExtension().lastPathComponent
                        == manifest.id.uuidString.lowercased(),
                      let entry = try entry(id: manifest.entryID),
                      entry.relativePath == relativePath,
                      entry.fingerprint == manifest.fingerprint else {
                    continue
                }
                entryIDs.insert(entry.id)
            } catch {
                healthDiagnostic = "At least one settled snapshot reference could not be checked for retention: \(error.localizedDescription)"
            }
        }
        return entryIDs
    }

    private func objectURL(_ id: UUID) -> URL {
        objectsURL.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    private func transactionURL(_ id: UUID) -> URL {
        transactionsURL.appendingPathComponent(id.uuidString.lowercased() + ".json")
    }

    private func settledPinURL(_ id: UUID) -> URL {
        settledPinsURL.appendingPathComponent(
            id.uuidString.lowercased() + ".json"
        )
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
        try execute("CREATE TABLE IF NOT EXISTS settled_snapshots(id TEXT PRIMARY KEY, note_id TEXT NOT NULL, entry_id TEXT NOT NULL REFERENCES entries(id) ON DELETE CASCADE, settled_at REAL NOT NULL, settled_order INTEGER NOT NULL DEFAULT 0)")
        let settledColumns = Set(try query("PRAGMA table_info(settled_snapshots)").flatMap(\.texts))
        if !settledColumns.contains("settled_order") {
            try execute("ALTER TABLE settled_snapshots ADD COLUMN settled_order INTEGER NOT NULL DEFAULT 0")
        }
        try execute("CREATE INDEX IF NOT EXISTS settled_snapshots_note_order ON settled_snapshots(note_id, settled_order DESC)")
        try execute("CREATE UNIQUE INDEX IF NOT EXISTS settled_snapshots_unique_note_order ON settled_snapshots(note_id, settled_order) WHERE settled_order > 0")
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

    private static func settledPin(_ row: Row) -> SettledPin? {
        guard row.columns.count >= 10,
              case .text(let idRaw) = row.columns[0],
              let id = UUID(uuidString: idRaw),
              case .text(let noteIDRaw) = row.columns[1],
              let noteID = UUID(uuidString: noteIDRaw),
              case .text(let entryIDRaw) = row.columns[2],
              let entryID = UUID(uuidString: entryIDRaw),
              case .text(let path) = row.columns[3],
              case .int(let sequence) = row.columns[4],
              case .double(let entryCreatedAt) = row.columns[5],
              case .double(let settledAt) = row.columns[6],
              case .int(let settledOrder) = row.columns[7],
              case .text(let sha256) = row.columns[8],
              case .int(let byteCount) = row.columns[9] else { return nil }
        let entry = PrewriteRecoveryReference(
            id: entryID,
            relativePath: path,
            sequence: sequence,
            createdAt: Date(timeIntervalSince1970: entryCreatedAt),
            fingerprint: DocumentFingerprint(sha256: sha256, byteCount: byteCount)
        )
        return SettledPin(
            id: id,
            noteID: noteID,
            entry: entry,
            createdAt: Date(timeIntervalSince1970: settledAt),
            settledOrder: settledOrder
        )
    }

    private func writeSettledPinManifest(_ manifest: SettledPinManifest) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        let readback = try settledPinStorage.createExclusive(
            data,
            directory: nil,
            fileName: manifest.id.uuidString.lowercased() + ".json"
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard try decoder.decode(SettledPinManifest.self, from: readback)
                == manifest else {
            throw VaultRepositoryError.recoveryLedgerUnavailable(
                "A settled snapshot reference failed durable readback."
            )
        }
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: [.atomic])
    }

    private func writeMutationManifest(_ transaction: MutationTransaction) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(transaction)
        let readback = try mutationStorage.replace(
            data,
            directory: transaction.id.uuidString.lowercased(),
            fileName: "manifest.json"
        )
        guard readback == data else {
            throw VaultRepositoryError.recoveryLedgerUnavailable(
                "A mutation transaction manifest failed durable readback."
            )
        }
    }

    private static func pathDigest(_ path: String) -> String {
        SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private let SQLITE_TRANSIENT_RECOVERY = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
