import Foundation
import ScholiumContracts

public struct SettlementStoreIssue: Hashable, Identifiable, Sendable {
    public let fileName: String
    public let reason: String

    public var id: String { fileName }

    public init(fileName: String, reason: String) {
        self.fileName = fileName
        self.reason = reason
    }
}

public struct SettlementListing: Sendable {
    public let settlements: [SettlementRecord]
    public let issues: [SettlementStoreIssue]

    public init(settlements: [SettlementRecord], issues: [SettlementStoreIssue]) {
        self.settlements = settlements
        self.issues = issues
    }
}

public enum SettlementStoreError: LocalizedError, Sendable {
    case invalid(UUID)
    case unsafeStore(String)
    case coordinationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let id):
            "Settlement \(id.uuidString) is invalid."
        case .unsafeStore(let reason):
            "Settlement storage is unavailable: \(reason)"
        case .coordinationFailed(let reason):
            "Settlement file coordination failed: \(reason)"
        }
    }
}

/// Portable researcher-owned Settle judgments. The path remains compatible
/// with earlier Scholium releases, but this store has no dependency on Agent
/// tasks, Agent Changes, or mutation evidence.
public actor SettlementStore {
    private struct State: Codable, Hashable {
        static let currentSchemaVersion = 2

        let schemaVersion: Int
        let triptychID: UUID
        let settlement: SettlementRecord

        init(triptychID: UUID, settlement: SettlementRecord) {
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
            case coveredActivities
        }

        init(from decoder: Decoder) throws {
            try ResearchStoreCodingValidation.rejectUnknownFields(
                in: decoder,
                allowed: CodingKeys.allCases.map(\.stringValue),
                onUnknownField: { _ in SettlementStoreError.invalid(UUID()) }
            )
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            guard schemaVersion == Self.currentSchemaVersion else {
                throw SettlementStoreError.invalid(UUID())
            }
            let settlementDecoder = try container.superDecoder(forKey: .settlement)
            try ResearchStoreCodingValidation.rejectUnknownFields(
                in: settlementDecoder,
                allowed: SettlementCodingKeys.allCases.map(\.stringValue),
                onUnknownField: { _ in SettlementStoreError.invalid(UUID()) }
            )
            let settlementContainer = try settlementDecoder.container(
                keyedBy: SettlementCodingKeys.self
            )
            let value = SettlementRecord(
                id: try settlementContainer.decode(UUID.self, forKey: .id),
                noteID: try settlementContainer.decode(UUID.self, forKey: .noteID),
                fingerprint: try settlementContainer.decode(
                    StrictSettlementFingerprint.self,
                    forKey: .fingerprint
                ).value,
                settledAt: try settlementContainer.decode(Date.self, forKey: .settledAt),
                researcher: try settlementContainer.decode(String.self, forKey: .researcher),
                rationale: try settlementContainer.decodeIfPresent(
                    String.self,
                    forKey: .rationale
                )
            )
            _ = try settlementContainer.decodeIfPresent(
                [LegacySettlementActivityReference].self,
                forKey: .coveredActivities
            )
            self.schemaVersion = schemaVersion
            triptychID = try container.decode(UUID.self, forKey: .triptychID)
            settlement = value
        }
    }

    private static let maximumByteCount = 512 * 1_024
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
            maximumByteCount: Self.maximumByteCount
        )
        let coordination = SecureRecordDirectory(
            trustedRootURL: applicationSupportURL,
            components: ["Triptychs", triptychID.uuidString],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: 1
        )
        do {
            try coordination.ensureDirectories([])
            lock = try AdvisoryFileLock(
                directory: coordination,
                fileName: "settlements-v2.lock"
            )
            try lock.withExclusiveLock {
                try Self.coordinateWrite(at: storageURL) {
                    try storage.ensureDirectories(["settlements"])
                    try storage.removeAbandonedStagingFiles(in: ["settlements"])
                }
            }
        } catch {
            throw SettlementStoreError.unsafeStore(error.localizedDescription)
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
        let settlement = SettlementRecord(
            noteID: noteID,
            fingerprint: fingerprint,
            settledAt: settledAt,
            researcher: researcher,
            rationale: rationale
        )
        let state = State(triptychID: triptychID, settlement: settlement)
        try validate(state)
        return try withExclusiveCoordination {
            let readback = try storage.replace(
                encode(state),
                directory: "settlements",
                fileName: fileName(noteID)
            )
            return try decodeAndValidate(readback, expectedNoteID: noteID).settlement
        }
    }

    public func listing() throws -> SettlementListing {
        try withSharedCoordination {
            var settlements: [SettlementRecord] = []
            var issues: [SettlementStoreIssue] = []
            for name in try storage.fileNames(in: "settlements")
                where name.hasSuffix(".json") {
                do {
                    let state = try decodeAndValidate(
                        storage.read(directory: "settlements", fileName: name),
                        expectedNoteID: noteID(from: name)
                    )
                    guard name == fileName(state.settlement.noteID) else {
                        throw SettlementStoreError.invalid(state.settlement.id)
                    }
                    settlements.append(state.settlement)
                } catch {
                    issues.append(SettlementStoreIssue(
                        fileName: name,
                        reason: error.localizedDescription
                    ))
                }
            }
            return SettlementListing(
                settlements: settlements.sorted {
                    if $0.settledAt != $1.settledAt { return $0.settledAt > $1.settledAt }
                    return $0.noteID.uuidString < $1.noteID.uuidString
                },
                issues: issues.sorted { $0.fileName < $1.fileName }
            )
        }
    }

    public func latest(noteID: UUID) throws -> SettlementRecord? {
        try withSharedCoordination {
            do {
                return try decodeAndValidate(
                    storage.read(directory: "settlements", fileName: fileName(noteID)),
                    expectedNoteID: noteID
                ).settlement
            } catch let error as SecureRecordDirectoryError {
                if case .notFound = error { return nil }
                throw error
            }
        }
    }

    private func validate(_ state: State) throws {
        let settlement = state.settlement
        guard state.schemaVersion == State.currentSchemaVersion,
              state.triptychID == triptychID,
              !settlement.researcher.isEmpty,
              settlement.researcher.utf8.count <= 256,
              ResearchStoreCodingValidation.isValidFingerprint(settlement.fingerprint),
              !ResearchStoreCodingValidation.containsAbsolutePath(settlement.researcher),
              (settlement.rationale?.utf8.count ?? 0) <= 256 * 1_024,
              !ResearchStoreCodingValidation.containsAbsolutePath(
                  settlement.rationale ?? ""
              ) else {
            throw SettlementStoreError.invalid(settlement.id)
        }
    }

    private func encode(_ state: State) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(state)
        guard data.count <= Self.maximumByteCount else {
            throw SettlementStoreError.invalid(state.settlement.id)
        }
        return data
    }

    private func decodeAndValidate(
        _ data: Data,
        expectedNoteID: UUID?
    ) throws -> State {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(State.self, from: data)
        try validate(state)
        guard expectedNoteID.map({ $0 == state.settlement.noteID }) ?? true else {
            throw SettlementStoreError.invalid(state.settlement.id)
        }
        return state
    }

    private func fileName(_ noteID: UUID) -> String {
        "\(noteID.uuidString.lowercased()).json"
    }

    private func noteID(from fileName: String) -> UUID? {
        UUID(uuidString: String(fileName.dropLast(".json".count)))
    }

    private func withExclusiveCoordination<T>(_ operation: () throws -> T) throws -> T {
        try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL, operation)
        }
    }

    private func withSharedCoordination<T>(_ operation: () throws -> T) throws -> T {
        try lock.withSharedLock {
            try Self.coordinateRead(at: storageURL, operation)
        }
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
                result = .failure(SettlementStoreError.coordinationFailed(
                    "The coordinated settlement root moved during the operation."
                ))
                return
            }
            result = Result { try operation() }
        }
        if let coordinationError {
            throw SettlementStoreError.coordinationFailed(
                coordinationError.localizedDescription
            )
        }
        guard let result else {
            throw SettlementStoreError.coordinationFailed(
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
                result = .failure(SettlementStoreError.coordinationFailed(
                    "The coordinated settlement root moved during the operation."
                ))
                return
            }
            result = Result { try operation() }
        }
        if let coordinationError {
            throw SettlementStoreError.coordinationFailed(
                coordinationError.localizedDescription
            )
        }
        guard let result else {
            throw SettlementStoreError.coordinationFailed(
                "The file coordinator did not execute the read."
            )
        }
        return try result.get()
    }
}

private struct LegacySettlementActivityReference: Decodable {
    let recordID: UUID
    let noteID: UUID
}

private struct StrictSettlementFingerprint: Decodable {
    let value: DocumentFingerprint

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sha256, byteCount
    }

    init(from decoder: Decoder) throws {
        try ResearchStoreCodingValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            onUnknownField: { _ in SettlementStoreError.invalid(UUID()) }
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = DocumentFingerprint(
            sha256: try container.decode(String.self, forKey: .sha256),
            byteCount: try container.decode(Int.self, forKey: .byteCount)
        )
    }
}
