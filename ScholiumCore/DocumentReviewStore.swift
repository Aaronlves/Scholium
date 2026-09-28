import Foundation
import ScholiumContracts

/// Machine-local acknowledgement metadata. Markdown in the vault remains the
/// only editable source; this store retains exact copies solely for comparison.
public actor DocumentReviewStore {
    /// Exact operational lifecycle version visible at one source snapshot.
    /// A later confirmation or Undo is a different version and needs review.
    public struct ReceiptVersion: Codable, Hashable, Sendable {
        public let id: UUID
        public let state: AgentChangeRecoveryState
        public let confirmedAt: Date?
        public let undoneAt: Date?

        public init(_ change: AgentChange) {
            id = change.id
            state = change.state
            confirmedAt = change.confirmedAt
            undoneAt = change.undoneAt
        }
    }

    public struct Baseline: Sendable {
        public let id: UUID
        public let state: DocumentChangeBaselineState
        public let fingerprint: DocumentFingerprint?
    }

    public struct Captured: Sendable {
        public let token: DocumentChangeCapture
        public let baselineState: DocumentChangeBaselineState
        public let startingData: Data?
        public let endingData: Data
    }

    public struct HistoryDetail: Sendable {
        public let batch: ReviewedDocumentChange
        public let startingData: Data?
        public let endingData: Data
    }

    private struct CaptureRecord: Codable {
        let id: UUID
        let baselineID: UUID
        let capturedAt: Date
        let endingData: Data
        let endingFingerprint: DocumentFingerprint
        let vaultID: UUID
        let role: VaultRole
        let relativePath: String
        var receiptVersions: [ReceiptVersion]
    }

    private struct CoverageWindow: Codable {
        let batchID: UUID
        let reviewedAt: Date
        var historyDeleted: Bool
        var receiptVersions: [ReceiptVersion]
    }

    private struct BatchRecord: Codable {
        let id: UUID
        let startingBaselineID: UUID
        let vaultID: UUID
        let role: VaultRole
        let relativePath: String
        let startingData: Data?
        let startingFingerprint: DocumentFingerprint?
        let endingData: Data
        let endingFingerprint: DocumentFingerprint
        let reviewedAt: Date
        let wasNewDocument: Bool

        func summary(noteID: UUID) -> ReviewedDocumentChange {
            ReviewedDocumentChange(
                id: id, noteID: noteID, vaultID: vaultID, role: role,
                relativePath: relativePath,
                startingRevision: startingFingerprint,
                endingRevision: endingFingerprint,
                reviewedAt: reviewedAt, wasNewDocument: wasNewDocument
            )
        }
    }

    private struct Record: Codable {
        static let schema = 1
        let schemaVersion: Int
        let triptychID: UUID
        let noteID: UUID
        let vaultID: UUID
        var baselineID: UUID
        var baselineState: DocumentChangeBaselineState
        var baselineData: Data?
        var baselineFingerprint: DocumentFingerprint?
        var initialReceiptVersions: [ReceiptVersion]
        var captures: [CaptureRecord]
        var batches: [BatchRecord]
        var coverage: [CoverageWindow]
        var lastAppliedCaptureID: UUID?

        init(
            triptychID: UUID, noteID: UUID, vaultID: UUID,
            baselineState: DocumentChangeBaselineState, baselineData: Data?,
            initialReceiptVersions: [ReceiptVersion] = []
        ) {
            schemaVersion = Self.schema
            self.triptychID = triptychID
            self.noteID = noteID
            self.vaultID = vaultID
            baselineID = UUID()
            self.baselineState = baselineState
            self.baselineData = baselineData
            baselineFingerprint = baselineData.map(DocumentFingerprint.init(data:))
            self.initialReceiptVersions = initialReceiptVersions
            captures = []
            batches = []
            coverage = []
            lastAppliedCaptureID = nil
        }
    }

    private struct Preferences: Codable {
        let schemaVersion: Int
        let triptychID: UUID
        let retention: DocumentChangeRetention
    }

    private let triptychID: UUID
    private let storage: SecureRecordDirectory
    private let lock: AdvisoryFileLock
    private static let maximumRecordBytes = 256 * 1_024 * 1_024
    private static let maximumCapturesPerNote = 8

    public init(applicationSupportURL: URL, triptychID: UUID) throws {
        self.triptychID = triptychID
        storage = SecureRecordDirectory(
            trustedRootURL: applicationSupportURL,
            components: ["Triptychs", triptychID.uuidString, "document-reviews-v1"],
            directoryMode: 0o700, fileMode: 0o600,
            maximumByteCount: Self.maximumRecordBytes
        )
        do {
            lock = try AdvisoryFileLock(directory: storage, fileName: "document-reviews.lock")
            try lock.withExclusiveLock {
                try storage.removeAbandonedStagingFiles(in: [nil])
            }
        } catch {
            throw DocumentChangeError.unavailable(error.localizedDescription)
        }
    }

    /// Called only for exact sources present in the opening inventory. A
    /// changed/unreadable opening candidate gets an explicit unknown baseline.
    public func initializeExisting(
        noteID: UUID, vaultID: UUID, source: Data?,
        receiptVersions: [ReceiptVersion] = []
    ) throws {
        try locked {
            if let existing = try read(noteID) {
                guard existing.vaultID == vaultID else {
                    throw DocumentChangeError.invalidRecord(noteID)
                }
                return
            }
            let record = Record(
                triptychID: triptychID, noteID: noteID, vaultID: vaultID,
                baselineState: source == nil ? .unavailable : .known,
                baselineData: source,
                initialReceiptVersions: receiptVersions
            )
            try create(record)
        }
    }

    /// Documents first seen after opening have no known preimage. Their first
    /// review is explicitly of a new document, with no fabricated empty diff.
    public func initializeNew(noteID: UUID, vaultID: UUID) throws {
        try locked {
            if let existing = try read(noteID) {
                guard existing.vaultID == vaultID else {
                    throw DocumentChangeError.invalidRecord(noteID)
                }
                return
            }
            try create(
                Record(
                    triptychID: triptychID, noteID: noteID, vaultID: vaultID,
                    baselineState: .newDocument, baselineData: nil
                ))
        }
    }

    public func baseline(noteID: UUID, vaultID: UUID) throws -> Baseline? {
        try locked {
            guard let record = try read(noteID) else { return nil }
            guard record.vaultID == vaultID else {
                throw DocumentChangeError.invalidRecord(noteID)
            }
            return Baseline(
                id: record.baselineID, state: record.baselineState,
                fingerprint: record.baselineFingerprint
            )
        }
    }

    public func capture(
        noteID: UUID, vaultID: UUID, role: VaultRole,
        relativePath: String, endingData: Data,
        receiptVersions: [ReceiptVersion] = []
    ) throws -> Captured {
        try locked {
            guard var record = try read(noteID), record.vaultID == vaultID else {
                throw DocumentChangeError.noteUnavailable(noteID)
            }
            guard record.baselineState != .known || record.baselineFingerprint != DocumentFingerprint(data: endingData)
            else { throw DocumentChangeError.noPendingChanges(noteID) }
            let excluded = Set(record.initialReceiptVersions)
                .union(record.coverage.flatMap(\.receiptVersions))
            let included = Array(Set(receiptVersions).subtracting(excluded))
                .sorted { $0.id.uuidString < $1.id.uuidString }
            let capture = CaptureRecord(
                id: UUID(), baselineID: record.baselineID,
                capturedAt: Date(),
                endingData: endingData,
                endingFingerprint: DocumentFingerprint(data: endingData),
                vaultID: vaultID, role: role, relativePath: relativePath,
                receiptVersions: included
            )
            record.captures.append(capture)
            if record.captures.count > Self.maximumCapturesPerNote {
                record.captures.removeFirst(record.captures.count - Self.maximumCapturesPerNote)
            }
            try replace(record)
            return Captured(
                token: DocumentChangeCapture(
                    id: capture.id, noteID: noteID,
                    baselineID: capture.baselineID,
                    endingRevision: capture.endingFingerprint
                ),
                baselineState: record.baselineState,
                startingData: record.baselineData,
                endingData: endingData
            )
        }
    }

    /// The token binds the displayed baseline generation and saved ending
    /// bytes. A later source revision does not change the acknowledged ending.
    public func markReviewed(
        _ token: DocumentChangeCapture,
        at date: Date = Date()
    ) throws -> ReviewedDocumentChange {
        try locked {
            guard var record = try read(token.noteID) else {
                throw DocumentChangeError.noteUnavailable(token.noteID)
            }
            if record.lastAppliedCaptureID == token.id,
                let batch = record.batches.first(where: { $0.id == token.id }),
                token.baselineID == batch.startingBaselineID,
                token.endingRevision == batch.endingFingerprint
            {
                return batch.summary(noteID: token.noteID)
            }
            guard record.baselineID == token.baselineID else {
                throw DocumentChangeError.staleCapture(token.id)
            }
            guard let captured = record.captures.first(where: { $0.id == token.id }),
                captured.baselineID == token.baselineID,
                captured.endingFingerprint == token.endingRevision,
                DocumentFingerprint(data: captured.endingData) == token.endingRevision
            else { throw DocumentChangeError.missingCapture(token.id) }
            let batch = BatchRecord(
                id: captured.id, startingBaselineID: captured.baselineID,
                vaultID: captured.vaultID, role: captured.role,
                relativePath: captured.relativePath,
                startingData: record.baselineData,
                startingFingerprint: record.baselineFingerprint,
                endingData: captured.endingData,
                endingFingerprint: captured.endingFingerprint,
                reviewedAt: date,
                wasNewDocument: record.baselineState == .newDocument
            )
            record.batches.append(batch)
            record.coverage.append(
                CoverageWindow(
                    batchID: batch.id,
                    reviewedAt: date,
                    historyDeleted: false,
                    receiptVersions: captured.receiptVersions
                ))
            record.baselineID = UUID()
            record.baselineState = .known
            record.baselineData = captured.endingData
            record.baselineFingerprint = captured.endingFingerprint
            record.captures = []
            record.lastAppliedCaptureID = token.id
            try replace(record)
            return batch.summary(noteID: token.noteID)
        }
    }

    public func history() throws -> [ReviewedDocumentChange] {
        try locked {
            try allRecords().flatMap { record in
                record.batches.map { $0.summary(noteID: record.noteID) }
            }.sorted {
                if $0.reviewedAt != $1.reviewedAt { return $0.reviewedAt > $1.reviewedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
        }
    }

    public func historyDetail(id: UUID) throws -> HistoryDetail {
        try locked {
            for record in try allRecords() {
                if let batch = record.batches.first(where: { $0.id == id }) {
                    return HistoryDetail(
                        batch: batch.summary(noteID: record.noteID),
                        startingData: batch.startingData,
                        endingData: batch.endingData
                    )
                }
            }
            throw DocumentChangeError.missingHistory(id)
        }
    }

    public func deleteHistory(ids: Set<UUID>) throws {
        try locked {
            guard !ids.isEmpty else { return }
            var found: Set<UUID> = []
            var changes: [Record] = []
            for var record in try allRecords() {
                let before = record.batches.count
                let removed = record.batches.filter { ids.contains($0.id) }
                found.formUnion(removed.map(\.id))
                record.batches.removeAll { ids.contains($0.id) }
                if record.batches.count != before {
                    for index in record.coverage.indices where ids.contains(record.coverage[index].batchID) {
                        record.coverage[index].historyDeleted = true
                    }
                    changes.append(record)
                }
            }
            guard found == ids else {
                throw DocumentChangeError.missingHistory(ids.subtracting(found).first!)
            }
            for record in changes { try replace(record) }
        }
    }

    public func clearHistory() throws {
        try locked {
            for var record in try allRecords() where !record.batches.isEmpty {
                record.batches = []
                for index in record.coverage.indices {
                    record.coverage[index].historyDeleted = true
                }
                try replace(record)
            }
        }
    }

    public func retention() throws -> DocumentChangeRetention {
        try locked { try readPreferences().retention }
    }

    public func setRetention(_ retention: DocumentChangeRetention) throws {
        try locked {
            let data = try encode(
                Preferences(
                    schemaVersion: 1, triptychID: triptychID, retention: retention
                ))
            _ = try storage.replace(data, directory: nil, fileName: "preferences.json")
        }
    }

    @discardableResult
    public func expireHistory(now: Date = Date()) throws -> Bool {
        try locked {
            guard let days = try readPreferences().retention.days else { return false }
            let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
            var didExpire = false
            for var record in try allRecords() {
                let prior = record.batches.count
                let expiredIDs = Set(record.batches.filter { $0.reviewedAt < cutoff }.map(\.id))
                record.batches.removeAll { expiredIDs.contains($0.id) }
                if record.batches.count != prior {
                    for index in record.coverage.indices where expiredIDs.contains(record.coverage[index].batchID) {
                        record.coverage[index].historyDeleted = true
                    }
                    try replace(record)
                    didExpire = true
                }
            }
            return didExpire
        }
    }

    public func historyUsage() throws -> DocumentChangeHistoryUsage {
        try locked {
            let records = try allRecords()
            let batches = records.flatMap(\.batches)
            let batchBytes = try batches.reduce(0) {
                $0 + (try encode($1)).count
            }
            let totalRecordBytes = try records.reduce(0) {
                $0
                    + (try storage.read(
                        directory: nil, fileName: fileName($1.noteID)
                    )).count
            }
            return DocumentChangeHistoryUsage(
                count: batches.count,
                byteCount: batchBytes,
                protectedByteCount: max(0, totalRecordBytes - batchBytes)
            )
        }
    }

    /// Compact review coverage survives batch deletion. Only the exact
    /// receipt lifecycle version captured with a displayed source can expire
    /// after its covering review reaches the selected retention age.
    public func hasReclaimableCoverage(
        noteID: UUID, vaultID: UUID, receipt: ReceiptVersion,
        now: Date = Date()
    ) throws -> Bool {
        try locked {
            guard let record = try read(noteID), record.vaultID == vaultID else { return false }
            let retention = try readPreferences().retention
            guard let days = retention.days else { return false }
            let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
            return record.coverage.contains { window in
                window.receiptVersions.contains(receipt) && window.reviewedAt < cutoff
            }
        }
    }

    /// Discards compact receipt IDs after their operational records are gone
    /// or change lifecycle version. Active source baselines, captures and
    /// visible reviewed batches remain intact.
    public func compactReceiptMetadata(retained: Set<ReceiptVersion>) throws {
        try locked {
            for var record in try allRecords() {
                let previous = try encode(record)
                record.initialReceiptVersions.removeAll { !retained.contains($0) }
                for index in record.captures.indices {
                    record.captures[index].receiptVersions.removeAll {
                        !retained.contains($0)
                    }
                }
                for index in record.coverage.indices {
                    record.coverage[index].receiptVersions.removeAll {
                        !retained.contains($0)
                    }
                }
                record.coverage.removeAll {
                    $0.historyDeleted && $0.receiptVersions.isEmpty
                }
                if try encode(record) != previous { try replace(record) }
            }
        }
    }

    private func readPreferences() throws -> Preferences {
        guard
            let data = try storage.readIfPresent(
                directory: nil, fileName: "preferences.json"
            )
        else {
            return Preferences(schemaVersion: 1, triptychID: triptychID, retention: .days90)
        }
        try rejectUnknownFields(
            data, allowed: ["schemaVersion", "triptychID", "retention"]
        )
        let value = try JSONDecoder().decode(Preferences.self, from: data)
        guard value.schemaVersion == 1, value.triptychID == triptychID else {
            throw DocumentChangeError.unavailable("Retention settings are invalid.")
        }
        return value
    }

    private func allRecords() throws -> [Record] {
        try storage.fileNames(in: nil)
            .filter { $0.hasSuffix(".json") && $0 != "preferences.json" }
            .map { name in
                guard let id = UUID(uuidString: String(name.dropLast(5))) else {
                    throw DocumentChangeError.unavailable("An unknown review record is present.")
                }
                guard let record = try read(id) else {
                    throw DocumentChangeError.invalidRecord(id)
                }
                return record
            }
    }

    private func read(_ noteID: UUID) throws -> Record? {
        guard
            let data = try storage.readIfPresent(
                directory: nil, fileName: fileName(noteID)
            )
        else { return nil }
        let record: Record
        do {
            try rejectUnknownFields(
                data,
                allowed: [
                    "schemaVersion", "triptychID", "noteID", "vaultID",
                    "baselineID", "baselineState", "baselineData",
                    "baselineFingerprint", "captures", "batches",
                    "lastAppliedCaptureID", "initialReceiptVersions", "coverage",
                ])
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dictionary = object as? [String: Any],
                let captures = dictionary["captures"] as? [[String: Any]],
                let batches = dictionary["batches"] as? [[String: Any]],
                let coverage = dictionary["coverage"] as? [[String: Any]]
            else { throw DocumentChangeError.invalidRecord(noteID) }
            for value in captures {
                try rejectUnknownFields(
                    value,
                    allowed: [
                        "id", "baselineID", "capturedAt", "endingData", "endingFingerprint",
                        "vaultID", "role", "relativePath", "receiptVersions",
                    ])
                try validateReceiptVersions(value["receiptVersions"])
            }
            for value in coverage {
                try rejectUnknownFields(
                    value,
                    allowed: [
                        "batchID", "reviewedAt", "historyDeleted", "receiptVersions",
                    ])
                try validateReceiptVersions(value["receiptVersions"])
            }
            try validateReceiptVersions(dictionary["initialReceiptVersions"])
            for value in batches {
                try rejectUnknownFields(
                    value,
                    allowed: [
                        "id", "startingBaselineID", "vaultID", "role", "relativePath",
                        "startingData", "startingFingerprint", "endingData",
                        "endingFingerprint", "reviewedAt", "wasNewDocument",
                    ])
            }
            record = try JSONDecoder().decode(Record.self, from: data)
        } catch { throw DocumentChangeError.invalidRecord(noteID) }
        guard record.schemaVersion == Record.schema,
            record.triptychID == triptychID,
            record.noteID == noteID,
            (record.baselineState == .known) == (record.baselineData != nil),
            record.baselineFingerprint == record.baselineData.map(DocumentFingerprint.init(data:)),
            record.captures.allSatisfy({
                $0.baselineID == record.baselineID && $0.vaultID == record.vaultID && Set($0.receiptVersions).count == $0.receiptVersions.count
                    && DocumentFingerprint(data: $0.endingData) == $0.endingFingerprint
            }),
            Set(record.batches.map(\.id)).count == record.batches.count,
            record.batches.allSatisfy({
                $0.vaultID == record.vaultID && $0.startingFingerprint == $0.startingData.map(DocumentFingerprint.init(data:))
                    && $0.endingFingerprint == DocumentFingerprint(data: $0.endingData)
            }),
            Set(record.coverage.map(\.batchID)).count == record.coverage.count,
            Set(record.initialReceiptVersions).count == record.initialReceiptVersions.count,
            record.coverage.allSatisfy({
                Set($0.receiptVersions).count == $0.receiptVersions.count
            }),
            record.batches.allSatisfy({ batch in
                record.coverage.contains { $0.batchID == batch.id && !$0.historyDeleted }
            })
        else { throw DocumentChangeError.invalidRecord(noteID) }
        return record
    }

    private func create(_ record: Record) throws {
        _ = try storage.createExclusive(
            encode(record), directory: nil, fileName: fileName(record.noteID)
        )
    }

    private func replace(_ record: Record) throws {
        _ = try storage.replace(
            encode(record), directory: nil, fileName: fileName(record.noteID)
        )
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    private func fileName(_ noteID: UUID) -> String { "\(noteID.uuidString).json" }

    private func rejectUnknownFields(_ data: Data, allowed: Set<String>) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw DocumentChangeError.unavailable("A review record is invalid.") }
        try rejectUnknownFields(object, allowed: allowed)
    }

    private func rejectUnknownFields(_ object: [String: Any], allowed: Set<String>) throws {
        guard Set(object.keys).isSubset(of: allowed) else {
            throw DocumentChangeError.unavailable("A review record has an unsupported field.")
        }
    }

    private func validateReceiptVersions(_ raw: Any?) throws {
        guard let values = raw as? [[String: Any]] else {
            throw DocumentChangeError.unavailable("Receipt coverage is invalid.")
        }
        for value in values {
            try rejectUnknownFields(
                value,
                allowed: [
                    "id", "state", "confirmedAt", "undoneAt",
                ])
        }
    }

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        do { return try lock.withExclusiveLock(operation) } catch let error as DocumentChangeError { throw error } catch {
            throw DocumentChangeError.unavailable(error.localizedDescription)
        }
    }
}
