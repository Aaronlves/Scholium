import Darwin
import Foundation
import ScholiumContracts

public enum PortableResearchRecordLocation: String, CaseIterable, Sendable {
    case active
    case records
    case trash
}

public struct PortableResearchRecordStoreIssue: Hashable, Identifiable, Sendable {
    public let location: String
    public let fileName: String
    public let reason: String

    public var id: String { "\(location)/\(fileName)" }

    public init(location: String, fileName: String, reason: String) {
        self.location = location
        self.fileName = fileName
        self.reason = reason
    }
}

public struct PortableResearchRecordListing: Sendable {
    public let records: [PortableResearchRecord]
    public let issues: [PortableResearchRecordStoreIssue]

    public init(
        records: [PortableResearchRecord],
        issues: [PortableResearchRecordStoreIssue]
    ) {
        self.records = records
        self.issues = issues
    }
}

public struct PortableSettlementListing: Sendable {
    public let settlements: [SettlementRecord]
    public let issues: [PortableResearchRecordStoreIssue]

    public init(
        settlements: [SettlementRecord],
        issues: [PortableResearchRecordStoreIssue]
    ) {
        self.settlements = settlements
        self.issues = issues
    }
}

public enum ResearchRecordStoreV1Error: LocalizedError, Sendable {
    case unsafeStore(String)
    case recordAlreadyExists(UUID)
    case recordNotFound(UUID)
    case recordIdentityMismatch(UUID)
    case recordTooLarge(Int)
    case coordinationFailed(String)
    case executionAlreadyExists(UUID)
    case executionNotFound(UUID)
    case executionAlreadyCompleted(UUID)
    case settlementChanged(UUID)

    public var errorDescription: String? {
        switch self {
        case .unsafeStore(let reason):
            "The Research Record store is unsafe or unavailable: \(reason)"
        case .recordAlreadyExists(let id):
            "Research Record \(id.uuidString) already exists."
        case .recordNotFound(let id):
            "Research Record \(id.uuidString) was not found."
        case .recordIdentityMismatch(let id):
            "Research Record \(id.uuidString) does not match its file identity."
        case .recordTooLarge(let count):
            "The Research Record exceeds the \(count)-byte storage boundary."
        case .coordinationFailed(let reason):
            "Portable Research Record coordination failed: \(reason)"
        case .executionAlreadyExists(let id):
            "Research execution \(id.uuidString) already exists."
        case .executionNotFound(let id):
            "Research execution \(id.uuidString) was not found."
        case .executionAlreadyCompleted(let id):
            "Research execution \(id.uuidString) already has different completion evidence."
        case .settlementChanged(let noteID):
            "The current Settle state for \(noteID.uuidString) changed during the transaction."
        }
    }
}

/// Portable, one-file-per-record storage beside Works.
///
/// The actor serializes callers in one process. A machine-local advisory lock
/// serializes cooperating Scholium processes, while NSFileCoordinator gives
/// registered sync/file-provider participants a chance to coordinate access.
/// Every actual file open remains descriptor-relative and no-follow.
public actor PortableResearchRecordStore {
    private static let maximumRecordByteCount = 8 * 1024 * 1024

    public nonisolated let storageURL: URL
    private let triptychID: UUID
    private let storage: SecureRecordDirectory
    private let lock: AdvisoryFileLock

    public init(
        controlURL: URL,
        applicationSupportURL: URL,
        triptychID: UUID
    ) throws {
        self.triptychID = triptychID
        storageURL = controlURL
            .appendingPathComponent("research-records", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        storage = SecureRecordDirectory(
            trustedRootURL: controlURL,
            components: ["research-records", "v1"],
            directoryMode: 0o755,
            fileMode: 0o600,
            maximumByteCount: Self.maximumRecordByteCount
        )
        let coordinationDirectory = SecureRecordDirectory(
            trustedRootURL: applicationSupportURL,
            components: ["Triptychs", triptychID.uuidString],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: 1
        )
        try coordinationDirectory.ensureDirectories([])
        lock = try AdvisoryFileLock(
            directory: coordinationDirectory,
            fileName: "portable-records-v1.lock"
        )
        try lock.withExclusiveLock {
            try Self.coordinateWrite(at: controlURL) {
                let directories = PortableResearchRecordLocation.allCases.map(\.rawValue)
                    + ["settlements"]
                try storage.ensureDirectories(directories)
                try storage.removeAbandonedStagingFiles(in: directories.map(Optional.some))
            }
        }
    }

    @discardableResult
    public func createFinishedRecord(
        _ record: PortableResearchRecord
    ) throws -> PortableResearchRecord {
        guard record.triptychID == triptychID else {
            throw ResearchRecordStoreV1Error.recordIdentityMismatch(record.id)
        }
        let (canonicalRecord, data) = try Self.canonicalized(record)
        guard data.count <= Self.maximumRecordByteCount else {
            throw ResearchRecordStoreV1Error.recordTooLarge(
                Self.maximumRecordByteCount
            )
        }
        return try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL) {
                do {
                    let readback = try storage.createExclusive(
                        data,
                        directory: PortableResearchRecordLocation.records.rawValue,
                        fileName: Self.fileName(record.id)
                    )
                    let stored = try Self.decode(
                        PortableResearchRecord.self,
                        from: readback
                    )
                    guard stored == canonicalRecord else {
                        throw ResearchRecordStoreV1Error.recordIdentityMismatch(record.id)
                    }
                    return stored
                } catch let error as SecureRecordDirectoryError {
                    if case .alreadyExists = error {
                        let existing = try readRecord(
                            id: record.id,
                            location: .records
                        )
                        if existing == canonicalRecord { return existing }
                        throw ResearchRecordStoreV1Error.recordAlreadyExists(record.id)
                    }
                    throw Self.map(error)
                }
            }
        }
    }

    public func record(
        id: UUID,
        location: PortableResearchRecordLocation = .records
    ) throws -> PortableResearchRecord {
        try lock.withSharedLock {
            try Self.coordinateRead(at: storageURL) {
                try readRecord(id: id, location: location)
            }
        }
    }

    public func listing(
        location: PortableResearchRecordLocation? = nil
    ) throws -> PortableResearchRecordListing {
        try lock.withSharedLock {
            try Self.coordinateRead(at: storageURL) {
                let locations = location.map { [$0] }
                    ?? PortableResearchRecordLocation.allCases
                var records: [PortableResearchRecord] = []
                var issues: [PortableResearchRecordStoreIssue] = []
                for location in locations {
                    let files = try storage.fileNames(in: location.rawValue)
                    for fileName in files where fileName.hasSuffix(".json") {
                        do {
                            let data = try storage.read(
                                directory: location.rawValue,
                                fileName: fileName
                            )
                            let record = try Self.decode(
                                PortableResearchRecord.self,
                                from: data
                            )
                            guard fileName == Self.fileName(record.id),
                                  record.triptychID == triptychID else {
                                throw ResearchRecordStoreV1Error.recordIdentityMismatch(
                                    record.id
                                )
                            }
                            records.append(record)
                        } catch {
                            issues.append(PortableResearchRecordStoreIssue(
                                location: location.rawValue,
                                fileName: fileName,
                                reason: error.localizedDescription
                            ))
                        }
                    }
                }
                return PortableResearchRecordListing(
                    records: records.sorted {
                        if $0.finishedAt != $1.finishedAt {
                            return $0.finishedAt > $1.finishedAt
                        }
                        return $0.id.uuidString < $1.id.uuidString
                    },
                    issues: issues.sorted { $0.id < $1.id }
                )
            }
        }
    }

    @discardableResult
    public func settle(
        noteID: UUID,
        fingerprint: DocumentFingerprint,
        researcher: String = "Researcher",
        rationale: String?,
        settledAt: Date = Date()
    ) throws -> SettlementRecord {
        try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL) {
                let fileName = Self.fileName(noteID)
                let current: PortableSettlementState?
                do {
                    let data = try storage.read(
                        directory: "settlements",
                        fileName: fileName
                    )
                    current = try Self.decode(
                        PortableSettlementState.self,
                        from: data
                    )
                } catch let error as SecureRecordDirectoryError {
                    if case .notFound = error {
                        current = nil
                    } else {
                        throw Self.map(error)
                    }
                }
                if let current {
                    guard current.triptychID == triptychID,
                          current.settlement.noteID == noteID else {
                        throw ResearchRecordStoreV1Error.recordIdentityMismatch(noteID)
                    }
                    if current.settlement.fingerprint == fingerprint {
                        return current.settlement
                    }
                }
                let settlement = SettlementRecord(
                    noteID: noteID,
                    fingerprint: fingerprint,
                    settledAt: settledAt,
                    researcher: researcher,
                    rationale: rationale
                )
                let state = try PortableSettlementState(
                    triptychID: triptychID,
                    settlement: settlement
                )
                let (canonicalState, data) = try Self.canonicalized(state)
                let readback = try storage.replace(
                    data,
                    directory: "settlements",
                    fileName: fileName
                )
                let stored = try Self.decode(
                    PortableSettlementState.self,
                    from: readback
                )
                guard stored == canonicalState else {
                    throw ResearchRecordStoreV1Error.recordIdentityMismatch(noteID)
                }
                return stored.settlement
            }
        }
    }

    public func settlementListing() throws -> PortableSettlementListing {
        try lock.withSharedLock {
            try Self.coordinateRead(at: storageURL) {
                var settlements: [SettlementRecord] = []
                var issues: [PortableResearchRecordStoreIssue] = []
                for fileName in try storage.fileNames(in: "settlements")
                    where fileName.hasSuffix(".json") {
                    do {
                        let data = try storage.read(
                            directory: "settlements",
                            fileName: fileName
                        )
                        let state = try Self.decode(
                            PortableSettlementState.self,
                            from: data
                        )
                        guard state.triptychID == triptychID,
                              fileName == Self.fileName(state.settlement.noteID) else {
                            throw ResearchRecordStoreV1Error.recordIdentityMismatch(
                                state.settlement.noteID
                            )
                        }
                        settlements.append(state.settlement)
                    } catch {
                        issues.append(PortableResearchRecordStoreIssue(
                            location: "settlements",
                            fileName: fileName,
                            reason: error.localizedDescription
                        ))
                    }
                }
                return PortableSettlementListing(
                    settlements: settlements.sorted {
                        if $0.settledAt != $1.settledAt {
                            return $0.settledAt > $1.settledAt
                        }
                        return $0.noteID.uuidString < $1.noteID.uuidString
                    },
                    issues: issues.sorted { $0.id < $1.id }
                )
            }
        }
    }

    public func latestSettlement(noteID: UUID) throws -> SettlementRecord? {
        try lock.withSharedLock {
            try Self.coordinateRead(at: storageURL) {
                do {
                    let data = try storage.read(
                        directory: "settlements",
                        fileName: Self.fileName(noteID)
                    )
                    let state = try Self.decode(
                        PortableSettlementState.self,
                        from: data
                    )
                    guard state.triptychID == triptychID,
                          state.settlement.noteID == noteID else {
                        throw ResearchRecordStoreV1Error.recordIdentityMismatch(noteID)
                    }
                    return state.settlement
                } catch let error as SecureRecordDirectoryError {
                    if case .notFound = error { return nil }
                    throw Self.map(error)
                }
            }
        }
    }

    public func purgeSettlement(noteID: UUID) throws {
        try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL) {
                try storage.removeIfPresent(
                    directory: "settlements",
                    fileName: Self.fileName(noteID)
                )
            }
        }
    }

    /// Removes only the exact Settle state captured by a rollback journal.
    /// Passing nil proves that no Settle existed at capture time; a newly
    /// appearing state then aborts the transaction instead of being deleted.
    public func purgeSettlement(
        noteID: UUID,
        matching expected: SettlementRecord?
    ) throws {
        try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL) {
                let current: PortableSettlementState
                do {
                    current = try Self.decode(
                        PortableSettlementState.self,
                        from: storage.read(
                            directory: "settlements",
                            fileName: Self.fileName(noteID)
                        )
                    )
                } catch let error as SecureRecordDirectoryError {
                    if case .notFound = error { return }
                    throw Self.map(error)
                }
                guard current.triptychID == triptychID,
                      current.settlement.noteID == noteID else {
                    throw ResearchRecordStoreV1Error.recordIdentityMismatch(noteID)
                }
                guard let expected, current.settlement == expected else {
                    throw ResearchRecordStoreV1Error.settlementChanged(noteID)
                }
                try storage.removeIfPresent(
                    directory: "settlements",
                    fileName: Self.fileName(noteID)
                )
            }
        }
    }

    public func restoreSettlement(_ settlement: SettlementRecord) throws {
        try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL) {
                do {
                    let data = try storage.read(
                        directory: "settlements",
                        fileName: Self.fileName(settlement.noteID)
                    )
                    let current = try Self.decode(
                        PortableSettlementState.self,
                        from: data
                    )
                    guard current.triptychID == triptychID,
                          current.settlement.noteID == settlement.noteID else {
                        throw ResearchRecordStoreV1Error.recordIdentityMismatch(
                            settlement.noteID
                        )
                    }
                    guard current.settlement == settlement else {
                        throw ResearchRecordStoreV1Error.settlementChanged(
                            settlement.noteID
                        )
                    }
                    return
                } catch let error as SecureRecordDirectoryError {
                    if case .notFound = error {
                        // Restore the journaled preimage below.
                    } else {
                        throw Self.map(error)
                    }
                }
                let state = try PortableSettlementState(
                    triptychID: triptychID,
                    settlement: settlement
                )
                let (canonicalState, data) = try Self.canonicalized(state)
                let readback = try storage.replace(
                    data,
                    directory: "settlements",
                    fileName: Self.fileName(settlement.noteID)
                )
                let stored = try Self.decode(
                    PortableSettlementState.self,
                    from: readback
                )
                guard stored == canonicalState else {
                    throw ResearchRecordStoreV1Error.recordIdentityMismatch(
                        settlement.noteID
                    )
                }
            }
        }
    }

    private func readRecord(
        id: UUID,
        location: PortableResearchRecordLocation
    ) throws -> PortableResearchRecord {
        do {
            let data = try storage.read(
                directory: location.rawValue,
                fileName: Self.fileName(id)
            )
            let record = try Self.decode(
                PortableResearchRecord.self,
                from: data
            )
            guard record.id == id, record.triptychID == triptychID else {
                throw ResearchRecordStoreV1Error.recordIdentityMismatch(id)
            }
            return record
        } catch let error as SecureRecordDirectoryError {
            if case .notFound = error {
                throw ResearchRecordStoreV1Error.recordNotFound(id)
            }
            throw Self.map(error)
        }
    }

    private static func fileName(_ id: UUID) -> String {
        id.uuidString.lowercased() + ".json"
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try makeDecoder().decode(type, from: data)
    }

    private static func canonicalized<T: Codable>(_ value: T) throws -> (T, Data) {
        let first = try makeEncoder().encode(value)
        let canonical = try makeDecoder().decode(T.self, from: first)
        return (canonical, try makeEncoder().encode(canonical))
    }

    private static func map(_ error: SecureRecordDirectoryError) -> Error {
        ResearchRecordStoreV1Error.unsafeStore(error.localizedDescription)
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
                result = .failure(ResearchRecordStoreV1Error.coordinationFailed(
                    "The coordinated Research Record root moved during the operation."
                ))
                return
            }
            result = Result { try operation() }
        }
        if let coordinationError {
            throw ResearchRecordStoreV1Error.coordinationFailed(
                coordinationError.localizedDescription
            )
        }
        guard let result else {
            throw ResearchRecordStoreV1Error.coordinationFailed(
                "The file coordinator did not execute the write."
            )
        }
        return try result.get()
    }

    private static func coordinateRead<T>(
        at url: URL,
        _ operation: () throws -> T
    ) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(
            readingItemAt: url,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            guard coordinatedURL.standardizedFileURL == url.standardizedFileURL else {
                result = .failure(ResearchRecordStoreV1Error.coordinationFailed(
                    "The coordinated Research Record root moved during the operation."
                ))
                return
            }
            result = Result { try operation() }
        }
        if let coordinationError {
            throw ResearchRecordStoreV1Error.coordinationFailed(
                coordinationError.localizedDescription
            )
        }
        guard let result else {
            throw ResearchRecordStoreV1Error.coordinationFailed(
                "The file coordinator did not execute the read."
            )
        }
        return try result.get()
    }
}

private struct PortableSettlementState: Codable, Hashable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let triptychID: UUID
    let settlement: SettlementRecord

    init(triptychID: UUID, settlement: SettlementRecord) throws {
        guard !settlement.researcher.isEmpty,
              settlement.researcher.utf8.count <= 256,
              ResearchRecordStoreCodingValidation.isValidFingerprint(
                settlement.fingerprint
              ),
              !ResearchRecordStoreCodingValidation.containsAbsolutePath(
                settlement.researcher
              ),
              (settlement.rationale?.utf8.count ?? 0) <= 256 * 1024,
              !ResearchRecordStoreCodingValidation.containsAbsolutePath(
                settlement.rationale ?? ""
              ) else {
            throw PortableResearchRecordError.invalidRecord
        }
        schemaVersion = Self.currentSchemaVersion
        self.triptychID = triptychID
        self.settlement = settlement
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case triptychID = "triptych_id"
        case settlement
    }

    private enum SettlementCodingKeys: String, CodingKey, CaseIterable {
        case id, noteID, fingerprint, settledAt, researcher, rationale
    }

    init(from decoder: Decoder) throws {
        try ResearchRecordStoreCodingValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw PortableResearchRecordError.unsupportedSchemaVersion(schemaVersion)
        }
        let settlementDecoder = try container.superDecoder(forKey: .settlement)
        try ResearchRecordStoreCodingValidation.rejectUnknownFields(
            in: settlementDecoder,
            allowed: SettlementCodingKeys.allCases.map(\.stringValue)
        )
        let settlementContainer = try settlementDecoder.container(
            keyedBy: SettlementCodingKeys.self
        )
        try self.init(
            triptychID: container.decode(UUID.self, forKey: .triptychID),
            settlement: SettlementRecord(
                id: settlementContainer.decode(UUID.self, forKey: .id),
                noteID: settlementContainer.decode(UUID.self, forKey: .noteID),
                fingerprint: settlementContainer.decode(
                    StrictResearchRecordFingerprint.self,
                    forKey: .fingerprint
                ).value,
                settledAt: settlementContainer.decode(Date.self, forKey: .settledAt),
                researcher: settlementContainer.decode(String.self, forKey: .researcher),
                rationale: settlementContainer.decodeIfPresent(
                    String.self,
                    forKey: .rationale
                )
            )
        )
    }
}

private struct StrictResearchRecordFingerprint: Decodable {
    let value: DocumentFingerprint

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sha256, byteCount
    }

    init(from decoder: Decoder) throws {
        try ResearchRecordStoreCodingValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = DocumentFingerprint(
            sha256: try container.decode(String.self, forKey: .sha256),
            byteCount: try container.decode(Int.self, forKey: .byteCount)
        )
        guard value.byteCount >= 0,
              value.sha256.count == 64,
              value.sha256.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
            throw PortableResearchRecordError.invalidRecord
        }
        self.value = value
    }
}

/// Machine-local execution evidence. Protected Function identity and assembled
/// instructions are allowed here and are never projected into the portable
/// record type.
public struct LocalResearchExecutionRecord: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let triptychID: UUID
    public let snapshot: ResearchFunctionSnapshot
    public let preparedInstructions: String
    public var dialogue: DialogueEntry?
    public var grant: ResearchActivityGrant?
    public var completion: ResearchFunctionCompletion?
    public var completionSubmissionDigest: String?

    public var id: UUID { snapshot.runID }

    public init(
        triptychID: UUID,
        snapshot: ResearchFunctionSnapshot,
        preparedInstructions: String,
        dialogue: DialogueEntry? = nil,
        grant: ResearchActivityGrant? = nil,
        completion: ResearchFunctionCompletion? = nil,
        completionSubmissionDigest: String? = nil
    ) throws {
        guard snapshot.actionSnapshot != nil,
              snapshot.runID == snapshot.recordID,
              preparedInstructions.utf8.count <= 2 * 1024 * 1024,
              dialogue?.id == snapshot.runID || dialogue == nil,
              dialogue?.functionSnapshot == snapshot || dialogue == nil,
              grant?.activityID == snapshot.activityID || grant == nil,
              completion?.runID == snapshot.runID || completion == nil,
              completion?.function == snapshot.request.function || completion == nil,
              grant?.state != .completed || completion != nil,
              grant?.state != .completed || grant?.completionReport != nil,
              grant?.state != .completed || grant?.completionPayloadDigest != nil else {
            throw ResearchRecordStoreV1Error.unsafeStore(
                "The local execution does not match its frozen Action run."
            )
        }
        schemaVersion = Self.currentSchemaVersion
        self.triptychID = triptychID
        self.snapshot = snapshot
        self.preparedInstructions = preparedInstructions
        self.dialogue = dialogue
        self.grant = grant
        self.completion = completion
        self.completionSubmissionDigest = completionSubmissionDigest
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case triptychID = "triptych_id"
        case snapshot
        case preparedInstructions = "prepared_instructions"
        case dialogue, grant, completion
        case completionSubmissionDigest = "completion_submission_digest"
    }

    public init(from decoder: Decoder) throws {
        try ResearchRecordStoreCodingValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw PortableResearchRecordError.unsupportedSchemaVersion(schemaVersion)
        }
        try self.init(
            triptychID: container.decode(UUID.self, forKey: .triptychID),
            snapshot: container.decode(ResearchFunctionSnapshot.self, forKey: .snapshot),
            preparedInstructions: container.decode(
                String.self,
                forKey: .preparedInstructions
            ),
            dialogue: container.decodeIfPresent(DialogueEntry.self, forKey: .dialogue),
            grant: container.decodeIfPresent(ResearchActivityGrant.self, forKey: .grant),
            completion: container.decodeIfPresent(
                ResearchFunctionCompletion.self,
                forKey: .completion
            ),
            completionSubmissionDigest: container.decodeIfPresent(
                String.self,
                forKey: .completionSubmissionDigest
            )
        )
    }
}

public struct LocalResearchExecutionListing: Sendable {
    public let records: [LocalResearchExecutionRecord]
    public let issues: [PortableResearchRecordStoreIssue]
}

/// Private per-run execution storage. Each run is isolated so one malformed or
/// partially synchronized file cannot make unrelated completion grants usable.
public actor LocalResearchExecutionStore {
    private static let maximumExecutionByteCount = 16 * 1024 * 1024

    public nonisolated let storageURL: URL
    private let triptychID: UUID
    private let storage: SecureRecordDirectory
    private let lock: AdvisoryFileLock

    public init(applicationSupportURL: URL, triptychID: UUID) throws {
        self.triptychID = triptychID
        storageURL = applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(triptychID.uuidString, isDirectory: true)
            .appendingPathComponent("research-execution-v2", isDirectory: true)
        storage = SecureRecordDirectory(
            trustedRootURL: applicationSupportURL,
            components: [
                "Triptychs",
                triptychID.uuidString,
                "research-execution-v2",
            ],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: Self.maximumExecutionByteCount
        )
        try storage.ensureDirectories([])
        lock = try AdvisoryFileLock(
            directory: storage,
            fileName: "execution-v2.lock"
        )
        try lock.withExclusiveLock {
            try storage.removeAbandonedStagingFiles(in: [nil])
        }
    }

    public nonisolated static func prepareGrant(
        activityID: UUID,
        origin: ResearchActivityNoteReference,
        writeScope: ResearchWriteScope,
        allowedTargets: [ResearchActivityNoteReference],
        startingFingerprints: [UUID: DocumentFingerprint],
        issuedAt: Date,
        validFor requestedDuration: TimeInterval = 60 * 60
    ) throws -> ResearchActivityGrantAuthorization {
        let distinctTargets = Dictionary(
            allowedTargets.map { ($0.noteID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard !distinctTargets.isEmpty else {
            throw ResearchActivityGrantError.emptyWriteSet
        }
        guard Set(distinctTargets.keys) == Set(startingFingerprints.keys) else {
            throw ResearchActivityGrantError.incompleteStartingFingerprints
        }
        let duration = min(max(1, requestedDuration), 24 * 60 * 60)
        let rawKey = [UUID().uuidString, UUID().uuidString]
            .joined(separator: "-")
            .lowercased()
        let grant = ResearchActivityGrant(
            activityID: activityID,
            keyDigest: DocumentFingerprint(content: rawKey).sha256,
            origin: origin,
            writeScope: writeScope,
            allowedTargets: Array(distinctTargets.values),
            startingFingerprints: startingFingerprints,
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(duration)
        )
        return ResearchActivityGrantAuthorization(
            grant: grant,
            activityKey: rawKey
        )
    }

    @discardableResult
    public func create(
        _ record: LocalResearchExecutionRecord
    ) throws -> LocalResearchExecutionRecord {
        guard record.triptychID == triptychID else {
            throw ResearchRecordStoreV1Error.recordIdentityMismatch(record.id)
        }
        return try lock.withExclusiveLock {
            let (canonicalRecord, data) = try Self.canonicalized(record)
            do {
                let readback = try storage.createExclusive(
                    data,
                    directory: nil,
                    fileName: Self.fileName(record.id)
                )
                let stored = try Self.decode(
                    LocalResearchExecutionRecord.self,
                    from: readback
                )
                guard stored == canonicalRecord else {
                    throw ResearchRecordStoreV1Error.recordIdentityMismatch(record.id)
                }
                return stored
            } catch let error as SecureRecordDirectoryError {
                if case .alreadyExists = error {
                    let existing = try readRecord(id: record.id)
                    if existing == canonicalRecord { return existing }
                    throw ResearchRecordStoreV1Error.executionAlreadyExists(record.id)
                }
                throw ResearchRecordStoreV1Error.unsafeStore(error.localizedDescription)
            }
        }
    }

    public func record(id: UUID) throws -> LocalResearchExecutionRecord {
        try lock.withSharedLock { try readRecord(id: id) }
    }

    public func recordIfPresent(id: UUID) throws -> LocalResearchExecutionRecord? {
        try lock.withSharedLock {
            do { return try readRecord(id: id) }
            catch ResearchRecordStoreV1Error.executionNotFound { return nil }
        }
    }

    public func listing() throws -> LocalResearchExecutionListing {
        try lock.withSharedLock {
            try readListing()
        }
    }

    /// Fails closed before a destructive note transaction begins. A malformed
    /// execution file may contain note-specific private state, so Scholium may
    /// not claim permanent deletion while leaving it uninterpreted.
    public func validateStoreHealth() throws {
        let listing = try listing()
        guard listing.issues.isEmpty else {
            throw ResearchRecordStoreV1Error.unsafeStore(
                listing.issues.map(\.id).joined(separator: ", ")
            )
        }
    }

    /// Removes machine-local runs that contain any permanently deleted note.
    /// Finished portable records are deliberately not touched; participant
    /// tombstones belong to the separate Research Record lifecycle.
    @discardableResult
    public func purgeExecutions(containing noteIDs: Set<UUID>) throws -> [UUID] {
        guard !noteIDs.isEmpty else { return [] }
        return try lock.withExclusiveLock {
            let listing = try readListing()
            guard listing.issues.isEmpty else {
                throw ResearchRecordStoreV1Error.unsafeStore(
                    listing.issues.map(\.id).joined(separator: ", ")
                )
            }
            let removed = listing.records
                .filter { !Self.noteIDs(in: $0).isDisjoint(with: noteIDs) }
                .map(\.id)
                .sorted { $0.uuidString < $1.uuidString }
            for runID in removed {
                try storage.removeIfPresent(
                    directory: nil,
                    fileName: Self.fileName(runID)
                )
            }
            return removed
        }
    }

    @discardableResult
    public func appendReply(
        _ reply: DialogueReply,
        to runID: UUID
    ) throws -> DialogueEntry {
        try update(runID) { record in
            guard var dialogue = record.dialogue else {
                throw DialogueError.entryNotFound(runID)
            }
            guard !reply.text.isEmpty, !reply.agentName.isEmpty else {
                throw DialogueError.emptyReply
            }
            guard !dialogue.replies.contains(where: { $0.id == reply.id }) else {
                throw DialogueError.duplicateReply(reply.id)
            }
            try Self.validateDialogueTarget(
                noteID: reply.noteID,
                commentID: reply.commentID,
                dialogue: dialogue
            )
            dialogue.replies.append(reply)
            record.dialogue = dialogue
        }.dialogue!
    }

    @discardableResult
    public func appendFollowUp(
        _ comment: DialogueFollowUpComment,
        to runID: UUID
    ) throws -> DialogueEntry {
        try update(runID) { record in
            guard var dialogue = record.dialogue else {
                throw DialogueError.entryNotFound(runID)
            }
            guard !comment.text.isEmpty else { throw DialogueError.emptyFollowUpComment }
            guard !dialogue.followUpComments.contains(where: { $0.id == comment.id }) else {
                throw DialogueError.duplicateFollowUpComment(comment.id)
            }
            try Self.validateDialogueTarget(
                noteID: comment.noteID,
                commentID: comment.commentID,
                dialogue: dialogue
            )
            dialogue.followUpComments.append(comment)
            record.dialogue = dialogue
        }.dialogue!
    }

    public func authorizeCompletion(
        activityID: UUID,
        activityKey: String,
        at date: Date
    ) throws -> ResearchActivityGrant {
        let record = try update(activityID) { record in
            guard var grant = record.grant else {
                throw ResearchActivityGrantError.notFound(activityID)
            }
            if grant.state == .active, date > grant.expiresAt {
                grant.state = .expired
                record.grant = grant
            }
        }
        guard let grant = record.grant else {
            throw ResearchActivityGrantError.notFound(activityID)
        }
        guard grant.keyDigest == DocumentFingerprint(content: activityKey).sha256 else {
            throw ResearchActivityGrantError.keyMismatch
        }
        switch grant.state {
        case .active, .completed:
            return grant
        case .cancelled, .revoked, .expired:
            throw ResearchActivityGrantError.inactive(grant.state)
        }
    }

    public func grant(activityID: UUID) throws -> ResearchActivityGrant? {
        try recordIfPresent(id: activityID)?.grant
    }

    /// Commits the write grant report and the Function completion in one
    /// replacement of the same Local Execution file. A process can therefore
    /// observe either the active grant with no completion or the complete pair,
    /// never a consumed grant whose completion evidence is missing.
    @discardableResult
    public func completeExecution(
        activityID: UUID,
        activityKey: String,
        completionPayloadDigest: String,
        report: MultiTargetCompletionReport,
        completion: ResearchFunctionCompletion,
        submissionDigest: String
    ) throws -> LocalResearchExecutionRecord {
        try update(activityID) { record in
            guard var grant = record.grant else {
                throw ResearchActivityGrantError.notFound(activityID)
            }
            guard grant.keyDigest == DocumentFingerprint(content: activityKey).sha256 else {
                throw ResearchActivityGrantError.keyMismatch
            }
            if grant.state == .active, report.completedAt > grant.expiresAt {
                throw ResearchActivityGrantError.inactive(.expired)
            }
            guard report.activityID == activityID else {
                throw ResearchActivityGrantError.activityMismatch
            }
            guard completion.runID == activityID,
                  completion.function == record.snapshot.request.function else {
                throw ResearchFunctionRecordStoreError.completionMismatch(activityID)
            }
            if grant.state == .completed || record.completion != nil {
                guard grant.state == .completed,
                      grant.completionPayloadDigest == completionPayloadDigest,
                      grant.completionReport == report,
                      record.completion == completion,
                      record.completionSubmissionDigest == submissionDigest else {
                    throw ResearchActivityGrantError.completionAlreadyRecorded(activityID)
                }
                return
            }
            guard grant.state == .active else {
                throw ResearchActivityGrantError.inactive(grant.state)
            }
            let allowed = Set(grant.allowedTargets.map(\.noteID))
            let confirmed = Set(report.confirmedModifiedNotes.map(\.noteID))
            let unmodified = Set(report.unmodifiedNotes.map(\.noteID))
            let unreported = Set(report.unreportedChangedNotes.map(\.noteID))
            guard confirmed.isDisjoint(with: unmodified),
                  confirmed.isDisjoint(with: unreported),
                  unmodified.isDisjoint(with: unreported),
                  confirmed.union(unmodified).union(unreported).isSubset(of: allowed),
                  Set(report.observedFingerprints.keys) == allowed else {
                throw ResearchActivityGrantError.invalidConfirmedSets
            }
            grant.state = .completed
            grant.completionPayloadDigest = completionPayloadDigest
            grant.completionReport = report
            record.grant = grant
            record.completion = completion
            record.completionSubmissionDigest = submissionDigest
        }
    }

    public func transitionGrant(
        activityID: UUID,
        to state: ResearchActivityGrantState
    ) throws {
        _ = try update(activityID) { record in
            guard var grant = record.grant else {
                throw ResearchActivityGrantError.notFound(activityID)
            }
            if grant.state == state { return }
            guard grant.state == .active else {
                throw ResearchActivityGrantError.inactive(grant.state)
            }
            grant.state = state
            record.grant = grant
        }
    }

    @discardableResult
    public func setCompletion(
        _ completion: ResearchFunctionCompletion,
        submissionDigest: String?,
        runID: UUID
    ) throws -> LocalResearchExecutionRecord {
        try update(runID) { record in
            guard completion.runID == runID,
                  completion.function == record.snapshot.request.function else {
                throw ResearchFunctionRecordStoreError.completionMismatch(runID)
            }
            if let existing = record.completion {
                if existing == completion {
                    if record.completionSubmissionDigest == submissionDigest {
                        return
                    }
                    guard [.awaitingFidelity, .unverified, .stale].contains(
                        existing.state
                    ) else {
                        throw ResearchRecordStoreV1Error.executionAlreadyCompleted(runID)
                    }
                    // The coordinator has revalidated this external
                    // submission against current bytes and it reconstructs
                    // the exact same nonterminal evidence. Accept its digest
                    // before internal orchestration attempts advancement.
                    record.completionSubmissionDigest = submissionDigest
                    return
                }
                guard Self.canAdvance(existing, to: completion, snapshot: record.snapshot) else {
                    throw ResearchRecordStoreV1Error.executionAlreadyCompleted(runID)
                }
            }
            record.completion = completion
            record.completionSubmissionDigest = submissionDigest
        }
    }

    public func discardUncompleted(runID: UUID) throws {
        try lock.withExclusiveLock {
            let current = try readRecord(id: runID)
            guard current.completion == nil else {
                throw ResearchRecordStoreV1Error.executionAlreadyCompleted(runID)
            }
            try storage.removeIfPresent(directory: nil, fileName: Self.fileName(runID))
        }
    }

    private func readRecord(id: UUID) throws -> LocalResearchExecutionRecord {
        do {
            let data = try storage.read(directory: nil, fileName: Self.fileName(id))
            let record = try Self.decode(
                LocalResearchExecutionRecord.self,
                from: data
            )
            guard record.id == id, record.triptychID == triptychID else {
                throw ResearchRecordStoreV1Error.recordIdentityMismatch(id)
            }
            return record
        } catch let error as SecureRecordDirectoryError {
            if case .notFound = error {
                throw ResearchRecordStoreV1Error.executionNotFound(id)
            }
            throw ResearchRecordStoreV1Error.unsafeStore(error.localizedDescription)
        }
    }

    private func readListing() throws -> LocalResearchExecutionListing {
        var records: [LocalResearchExecutionRecord] = []
        var issues: [PortableResearchRecordStoreIssue] = []
        for fileName in try storage.fileNames(in: nil)
            where fileName.hasSuffix(".json") {
            do {
                let data = try storage.read(directory: nil, fileName: fileName)
                let record = try Self.decode(
                    LocalResearchExecutionRecord.self,
                    from: data
                )
                guard record.triptychID == triptychID,
                      fileName == Self.fileName(record.id) else {
                    throw ResearchRecordStoreV1Error.recordIdentityMismatch(record.id)
                }
                records.append(record)
            } catch {
                issues.append(PortableResearchRecordStoreIssue(
                    location: "research-execution-v2",
                    fileName: fileName,
                    reason: error.localizedDescription
                ))
            }
        }
        return LocalResearchExecutionListing(
            records: records.sorted {
                if $0.snapshot.preparedAt != $1.snapshot.preparedAt {
                    return $0.snapshot.preparedAt > $1.snapshot.preparedAt
                }
                return $0.id.uuidString < $1.id.uuidString
            },
            issues: issues.sorted { $0.id < $1.id }
        )
    }

    @discardableResult
    private func update(
        _ id: UUID,
        _ body: (inout LocalResearchExecutionRecord) throws -> Void
    ) throws -> LocalResearchExecutionRecord {
        try lock.withExclusiveLock {
            var record = try readRecord(id: id)
            let original = record
            try body(&record)
            if record == original { return original }
            let (canonicalRecord, data) = try Self.canonicalized(record)
            let readback = try storage.replace(
                data,
                directory: nil,
                fileName: Self.fileName(id)
            )
            let stored = try Self.decode(
                LocalResearchExecutionRecord.self,
                from: readback
            )
            guard stored == canonicalRecord else {
                throw ResearchRecordStoreV1Error.recordIdentityMismatch(id)
            }
            return stored
        }
    }

    private nonisolated static func canAdvance(
        _ existing: ResearchFunctionCompletion,
        to replacement: ResearchFunctionCompletion,
        snapshot: ResearchFunctionSnapshot
    ) -> Bool {
        let stateAdvances: Bool
        switch (existing.state, replacement.state) {
        case (.awaitingFidelity, .complete),
             (.awaitingFidelity, .unverified),
             (.unverified, .complete),
             (.stale, .complete):
            stateAdvances = true
        default:
            stateAdvances = false
        }
        guard stateAdvances,
              existing.runID == replacement.runID,
              existing.function == replacement.function,
              existing.targetFingerprint == replacement.targetFingerprint,
              existing.materialFingerprints == replacement.materialFingerprints,
              existing.didModifyTarget == replacement.didModifyTarget,
              existing.summary == replacement.summary,
              existing.outputFingerprint == replacement.outputFingerprint,
              existing.completedAt == replacement.completedAt else {
            return false
        }
        let allowed = snapshot.fidelityHandoff?.checks ?? snapshot.request.checks
        return Set(replacement.fidelityOutcomes.map(\.check)).isSubset(of: allowed)
    }

    private nonisolated static func validateDialogueTarget(
        noteID: UUID?,
        commentID: UUID?,
        dialogue: DialogueEntry
    ) throws {
        if let noteID,
           !dialogue.selectedNotes.contains(where: { $0.noteID == noteID }) {
            throw DialogueError.invalidReplyTarget
        }
        if let commentID,
           !dialogue.includedComments.contains(where: { $0.exchange.id == commentID }) {
            throw DialogueError.invalidReplyTarget
        }
        if let noteID, let commentID,
           !dialogue.includedComments.contains(where: {
               $0.exchange.id == commentID && $0.note.noteID == noteID
           }) {
            throw DialogueError.invalidReplyTarget
        }
    }

    private nonisolated static func noteIDs(
        in record: LocalResearchExecutionRecord
    ) -> Set<UUID> {
        let request = record.snapshot.request
        var noteIDs: Set<UUID> = [request.target.noteID]
        noteIDs.formUnion(request.materials.map(\.noteID))
        noteIDs.formUnion(request.authorizedWriteTargets.map(\.noteID))
        noteIDs.formUnion(request.fidelityTargets?.map(\.noteID) ?? [])

        if let action = record.snapshot.actionSnapshot {
            noteIDs.insert(action.target.noteID)
            noteIDs.formUnion(action.authority.readableNotes.map(\.noteID))
            noteIDs.formUnion(action.authority.writableNotes.map(\.noteID))
            for value in action.parameters.values.values {
                if case .notes(let notes) = value {
                    noteIDs.formUnion(notes.map(\.noteID))
                }
            }
        }
        if let grant = record.grant {
            noteIDs.insert(grant.origin.noteID)
            noteIDs.formUnion(grant.allowedTargets.map(\.noteID))
            noteIDs.formUnion(grant.startingFingerprints.keys)
            if let report = grant.completionReport {
                noteIDs.formUnion(report.confirmedModifiedNotes.map(\.noteID))
                noteIDs.formUnion(report.unmodifiedNotes.map(\.noteID))
                noteIDs.formUnion(report.unreportedChangedNotes.map(\.noteID))
                noteIDs.formUnion(report.observedFingerprints.keys)
            }
        }
        if let dialogue = record.dialogue {
            noteIDs.formUnion(dialogue.selectedNotes.map(\.noteID))
            noteIDs.formUnion(dialogue.includedComments.map(\.note.noteID))
            noteIDs.formUnion(dialogue.replies.compactMap(\.noteID))
            noteIDs.formUnion(dialogue.followUpComments.compactMap(\.noteID))
        }
        return noteIDs
    }

    private static func fileName(_ id: UUID) -> String {
        id.uuidString.lowercased() + ".json"
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try makeDecoder().decode(type, from: data)
    }

    private static func canonicalized<T: Codable>(_ value: T) throws -> (T, Data) {
        let first = try makeEncoder().encode(value)
        let canonical = try makeDecoder().decode(T.self, from: first)
        return (canonical, try makeEncoder().encode(canonical))
    }
}

private final class AdvisoryFileLock: @unchecked Sendable {
    private let descriptor: Int32

    init(directory: SecureRecordDirectory, fileName: String) throws {
        descriptor = try directory.openLockFile(fileName)
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              status.st_nlink == 1 else {
            Darwin.close(descriptor)
            throw ResearchRecordStoreV1Error.unsafeStore(
                "The coordination lock is linked or is not a regular file."
            )
        }
        if status.st_mode & 0o777 != 0o600 {
            guard fchmod(descriptor, 0o600) == 0 else {
                Darwin.close(descriptor)
                throw ResearchRecordStoreV1Error.unsafeStore(
                    "Cannot restrict the coordination lock."
                )
            }
        }
    }

    deinit { Darwin.close(descriptor) }

    func withSharedLock<T>(_ operation: () throws -> T) throws -> T {
        try withLock(LOCK_SH, operation)
    }

    func withExclusiveLock<T>(_ operation: () throws -> T) throws -> T {
        try withLock(LOCK_EX, operation)
    }

    private func withLock<T>(
        _ kind: Int32,
        _ operation: () throws -> T
    ) throws -> T {
        while flock(descriptor, kind) != 0 {
            if errno == EINTR { continue }
            throw ResearchRecordStoreV1Error.unsafeStore(
                "Cannot acquire the coordination lock (\(Self.message()))."
            )
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try operation()
    }

    private static func message() -> String {
        String(cString: strerror(errno))
    }
}

private enum SecureRecordDirectoryError: LocalizedError {
    case unsafe(String)
    case notFound(String)
    case alreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .unsafe(let reason): reason
        case .notFound(let file): "\(file) was not found."
        case .alreadyExists(let file): "\(file) already exists."
        }
    }
}

private struct ResearchRecordStoreAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private enum ResearchRecordStoreCodingValidation {
    static func isValidFingerprint(_ fingerprint: DocumentFingerprint) -> Bool {
        fingerprint.byteCount >= 0
            && fingerprint.sha256.count == 64
            && fingerprint.sha256.unicodeScalars.allSatisfy { scalar in
                ("0"..."9").contains(Character(scalar))
                    || ("a"..."f").contains(Character(scalar))
            }
    }

    static func rejectUnknownFields(
        in decoder: Decoder,
        allowed: [String]
    ) throws {
        let container = try decoder.container(
            keyedBy: ResearchRecordStoreAnyCodingKey.self
        )
        let allowed = Set(allowed)
        if let unknown = container.allKeys.map(\.stringValue)
            .first(where: { !allowed.contains($0) }) {
            throw PortableResearchRecordError.unsupportedField(unknown)
        }
    }

    static func containsAbsolutePath(_ value: String) -> Bool {
        value.split(whereSeparator: { character in
            character.isWhitespace
                || "\"'`()[]{}<>,;".contains(character)
        }).contains { rawToken in
            let token = String(rawToken)
            if token.lowercased().hasPrefix("file://") { return true }
            if token.hasPrefix("/") && token.split(separator: "/").count > 1 {
                return true
            }
            let scalars = Array(token.unicodeScalars)
            return scalars.count >= 3
                && CharacterSet.letters.contains(scalars[0])
                && scalars[1] == ":"
                && (scalars[2] == "\\" || scalars[2] == "/")
        }
    }
}

/// Minimal descriptor-relative file primitive shared by the portable and
/// private stores. It does not interpret record semantics.
private struct SecureRecordDirectory: Sendable {
    let trustedRootURL: URL
    let components: [String]
    let directoryMode: mode_t
    let fileMode: mode_t
    let maximumByteCount: Int

    init(
        trustedRootURL: URL,
        components: [String],
        directoryMode: mode_t,
        fileMode: mode_t,
        maximumByteCount: Int
    ) {
        precondition(!components.isEmpty)
        precondition(components.allSatisfy(Self.isSafeComponent))
        self.trustedRootURL = trustedRootURL.standardizedFileURL
        self.components = components
        self.directoryMode = directoryMode
        self.fileMode = fileMode
        self.maximumByteCount = maximumByteCount
    }

    func ensureDirectories(_ children: [String]) throws {
        let root = try openStorageDirectory(createIfMissing: true)
        defer { Darwin.close(root) }
        for child in children {
            guard Self.isSafeComponent(child) else {
                throw SecureRecordDirectoryError.unsafe("Invalid record directory name.")
            }
            let descriptor = try openChildDirectory(
                parent: root,
                name: child,
                createIfMissing: true
            )
            Darwin.close(descriptor)
        }
    }

    func createExclusive(
        _ data: Data,
        directory: String?,
        fileName: String
    ) throws -> Data {
        try write(data, directory: directory, fileName: fileName, exclusive: true)
    }

    func replace(
        _ data: Data,
        directory: String?,
        fileName: String
    ) throws -> Data {
        try write(data, directory: directory, fileName: fileName, exclusive: false)
    }

    func read(directory: String?, fileName: String) throws -> Data {
        try validateFileName(fileName)
        let parent = try openTargetDirectory(directory, createIfMissing: false)
        defer { Darwin.close(parent) }
        return try read(parent: parent, fileName: fileName)
    }

    func fileNames(in directory: String?) throws -> [String] {
        try fileNames(in: directory, includingStaging: false)
    }

    func removeAbandonedStagingFiles(in directories: [String?]) throws {
        for directory in directories {
            let parent = try openTargetDirectory(directory, createIfMissing: false)
            defer { Darwin.close(parent) }
            var removedAny = false
            for name in try fileNames(
                parent: parent,
                includingStaging: true
            ) where name.hasPrefix(".scholium-pending-") {
                let result = name.withCString { unlinkat(parent, $0, 0) }
                if result != 0, errno == ENOENT { continue }
                guard result == 0 else { throw unsafe("remove abandoned staging file") }
                removedAny = true
            }
            if removedAny, fsync(parent) != 0 {
                throw unsafe("flush staging recovery")
            }
        }
    }

    private func fileNames(
        in directory: String?,
        includingStaging: Bool
    ) throws -> [String] {
        let parent = try openTargetDirectory(directory, createIfMissing: false)
        defer { Darwin.close(parent) }
        return try fileNames(parent: parent, includingStaging: includingStaging)
    }

    private func fileNames(
        parent: Int32,
        includingStaging: Bool
    ) throws -> [String] {
        let enumerationDescriptor = dup(parent)
        guard enumerationDescriptor >= 0 else {
            throw unsafe("duplicate record directory")
        }
        guard let stream = fdopendir(enumerationDescriptor) else {
            Darwin.close(enumerationDescriptor)
            throw unsafe("enumerate record directory")
        }
        defer { closedir(stream) }
        var names: [String] = []
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(
                    to: CChar.self,
                    capacity: Int(MAXNAMLEN) + 1
                ) { String(cString: $0) }
            }
            guard name != ".", name != ".." else { continue }
            if !includingStaging, name.hasPrefix(".scholium-pending-") {
                continue
            }
            names.append(name)
        }
        return names.sorted()
    }

    func removeIfPresent(directory: String?, fileName: String) throws {
        try validateFileName(fileName)
        let parent = try openTargetDirectory(directory, createIfMissing: false)
        defer { Darwin.close(parent) }
        let result = fileName.withCString { unlinkat(parent, $0, 0) }
        if result != 0, errno == ENOENT { return }
        guard result == 0, fsync(parent) == 0 else {
            throw unsafe("remove \(fileName)")
        }
    }

    func openLockFile(_ fileName: String) throws -> Int32 {
        guard Self.isSafeComponent(fileName) else {
            throw SecureRecordDirectoryError.unsafe("Invalid coordination lock name.")
        }
        let parent = try openStorageDirectory(createIfMissing: true)
        defer { Darwin.close(parent) }
        let descriptor = fileName.withCString {
            openat(
                parent,
                $0,
                O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
                fileMode
            )
        }
        guard descriptor >= 0 else { throw unsafe("open coordination lock") }
        return descriptor
    }

    private func write(
        _ data: Data,
        directory: String?,
        fileName: String,
        exclusive: Bool
    ) throws -> Data {
        guard data.count <= maximumByteCount else {
            throw SecureRecordDirectoryError.unsafe("Record exceeds its byte boundary.")
        }
        try validateFileName(fileName)
        let parent = try openTargetDirectory(directory, createIfMissing: true)
        defer { Darwin.close(parent) }

        var existing = stat()
        let existingResult = fileName.withCString {
            fstatat(parent, $0, &existing, AT_SYMLINK_NOFOLLOW)
        }
        if exclusive, existingResult == 0 {
            throw SecureRecordDirectoryError.alreadyExists(fileName)
        }
        if existingResult == 0 {
            guard (existing.st_mode & S_IFMT) == S_IFREG,
                  existing.st_nlink == 1 else {
                throw SecureRecordDirectoryError.unsafe(
                    "Destination \(fileName) is linked or is not a regular file."
                )
            }
        } else if errno != ENOENT {
            throw unsafe("inspect \(fileName)")
        }

        let temporaryName = ".scholium-pending-\(UUID().uuidString.lowercased())"
        let temporary = temporaryName.withCString {
            openat(
                parent,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                fileMode
            )
        }
        guard temporary >= 0 else { throw unsafe("create staging file") }
        var temporaryExists = true
        defer {
            Darwin.close(temporary)
            if temporaryExists {
                _ = temporaryName.withCString { unlinkat(parent, $0, 0) }
            }
        }
        try Self.writeAll(data, descriptor: temporary)
        guard fchmod(temporary, fileMode) == 0,
              fsync(temporary) == 0 else {
            throw unsafe("flush staging file")
        }

        let result: Int32
        if exclusive {
            result = temporaryName.withCString { source in
                fileName.withCString { destination in
                    renameatx_np(
                        parent,
                        source,
                        parent,
                        destination,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
        } else {
            result = temporaryName.withCString { source in
                fileName.withCString { destination in
                    renameat(parent, source, parent, destination)
                }
            }
        }
        if result != 0, exclusive, errno == EEXIST {
            throw SecureRecordDirectoryError.alreadyExists(fileName)
        }
        guard result == 0 else { throw unsafe("commit \(fileName)") }
        temporaryExists = false
        guard fsync(parent) == 0 else { throw unsafe("flush record directory") }
        let readback = try read(parent: parent, fileName: fileName)
        guard readback == data else {
            throw SecureRecordDirectoryError.unsafe(
                "Committed record \(fileName) did not match readback."
            )
        }
        return readback
    }

    private func openTargetDirectory(
        _ directory: String?,
        createIfMissing: Bool
    ) throws -> Int32 {
        let root = try openStorageDirectory(createIfMissing: createIfMissing)
        guard let directory else { return root }
        guard Self.isSafeComponent(directory) else {
            Darwin.close(root)
            throw SecureRecordDirectoryError.unsafe("Invalid record directory name.")
        }
        do {
            let child = try openChildDirectory(
                parent: root,
                name: directory,
                createIfMissing: createIfMissing
            )
            Darwin.close(root)
            return child
        } catch {
            Darwin.close(root)
            throw error
        }
    }

    private func openStorageDirectory(createIfMissing: Bool) throws -> Int32 {
        var current = trustedRootURL.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard current >= 0 else { throw unsafe("open trusted root") }
        do {
            for component in components {
                let next = try openChildDirectory(
                    parent: current,
                    name: component,
                    createIfMissing: createIfMissing
                )
                Darwin.close(current)
                current = next
            }
            var status = stat()
            guard fstat(current, &status) == 0,
                  (status.st_mode & S_IFMT) == S_IFDIR else {
                throw SecureRecordDirectoryError.unsafe(
                    "The record root is not a directory."
                )
            }
            if status.st_mode & 0o777 != directoryMode {
                guard fchmod(current, directoryMode) == 0,
                      fsync(current) == 0 else {
                    throw unsafe("restrict record root")
                }
            }
            return current
        } catch {
            Darwin.close(current)
            throw error
        }
    }

    private func openChildDirectory(
        parent: Int32,
        name: String,
        createIfMissing: Bool
    ) throws -> Int32 {
        var next = name.withCString {
            openat(parent, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        if next < 0, errno == ENOENT, createIfMissing {
            let created = name.withCString { mkdirat(parent, $0, directoryMode) }
            guard created == 0 || errno == EEXIST else {
                throw unsafe("create directory \(name)")
            }
            next = name.withCString {
                openat(parent, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            }
        }
        if next < 0, errno == ENOENT {
            throw SecureRecordDirectoryError.notFound(name)
        }
        guard next >= 0 else {
            throw SecureRecordDirectoryError.unsafe(
                "Directory \(name) is missing, linked, or unavailable."
            )
        }
        return next
    }

    private func read(parent: Int32, fileName: String) throws -> Data {
        let descriptor = fileName.withCString {
            openat(parent, $0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        }
        if descriptor < 0, errno == ENOENT {
            throw SecureRecordDirectoryError.notFound(fileName)
        }
        guard descriptor >= 0 else { throw unsafe("open \(fileName)") }
        defer { Darwin.close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1,
              before.st_size >= 0,
              before.st_size <= maximumByteCount else {
            throw SecureRecordDirectoryError.unsafe(
                "Record \(fileName) is linked, malformed, or too large."
            )
        }
        let expected = Int(before.st_size)
        var data = Data()
        data.reserveCapacity(expected)
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while data.count < expected {
            let requested = min(buffer.count, expected - data.count)
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, requested)
            }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw unsafe("read \(fileName)") }
            data.append(contentsOf: buffer.prefix(Int(count)))
        }
        var overflow: UInt8 = 0
        let overflowCount = Darwin.read(descriptor, &overflow, 1)
        var after = stat()
        guard overflowCount == 0,
              fstat(descriptor, &after) == 0,
              Self.sameFile(before, after) else {
            throw SecureRecordDirectoryError.unsafe(
                "Record \(fileName) changed while it was read."
            )
        }
        return data
    }

    private func validateFileName(_ fileName: String) throws {
        guard Self.isSafeComponent(fileName), fileName.hasSuffix(".json") else {
            throw SecureRecordDirectoryError.unsafe("Invalid record file name.")
        }
    }

    private static func writeAll(_ data: Data, descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(
                    descriptor,
                    bytes.baseAddress?.advanced(by: offset),
                    bytes.count - offset
                )
                if count < 0, errno == EINTR { continue }
                guard count > 0 else {
                    throw SecureRecordDirectoryError.unsafe(
                        "The staging file accepted no bytes."
                    )
                }
                offset += count
            }
        }
    }

    private static func sameFile(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev
            && lhs.st_ino == rhs.st_ino
            && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
            && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }

    private static func isSafeComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\0")
    }

    private func unsafe(_ operation: String) -> SecureRecordDirectoryError {
        .unsafe("\(operation) failed (\(String(cString: strerror(errno)))).")
    }
}
