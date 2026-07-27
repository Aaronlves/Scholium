import Foundation
import ScholiumContracts

public enum AgentNoteChangeRequestStoreError: LocalizedError, Hashable, Sendable {
    case requestNotFound(UUID)
    case duplicateRequestPayload(UUID)
    case unresolvedRequestExists(UUID)
    case requestAlreadyResolved(UUID)
    case triptychMismatch(UUID)
    case capacityExceeded
    case corruptStore
    case unsafeStore

    public var errorDescription: String? {
        switch self {
        case .requestNotFound(let id):
            "Agent Note Change request \(id.uuidString.lowercased()) was not found."
        case .duplicateRequestPayload(let id):
            "Agent Note Change request \(id.uuidString.lowercased()) was reused with different content."
        case .unresolvedRequestExists(let parentRunID):
            "Parent run \(parentRunID.uuidString.lowercased()) already has an unresolved Agent Note Change request."
        case .requestAlreadyResolved(let id):
            "Agent Note Change request \(id.uuidString.lowercased()) is already resolved."
        case .triptychMismatch(let id):
            "Agent Note Change request \(id.uuidString.lowercased()) belongs to another Triptych."
        case .capacityExceeded:
            "The Agent Note Change request store reached its bounded capacity."
        case .corruptStore:
            "The machine-local Agent Note Change request store is malformed."
        case .unsafeStore:
            "The machine-local Agent Note Change request store is unsafe or changed during an operation."
        }
    }
}

/// Private per-Triptych coordination state for agent-requested changes.
///
/// A stored decision is not a write grant. The later continuation coordinator
/// must independently resolve current identity, revision, permission, recovery,
/// and completion authority before creating a child phase.
public actor AgentNoteChangeRequestStore {
    private static let maximumRecordCount = 4_096
    private static let maximumRecordByteCount = 1024 * 1024
    private static let processLock = NSLock()

    public nonisolated let storageURL: URL
    private let triptychID: UUID
    private let storage: SecureRecordDirectory
    private let lock: AdvisoryFileLock

    public init(applicationSupportURL: URL, triptychID: UUID) throws {
        self.triptychID = triptychID
        storageURL = applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(triptychID.uuidString, isDirectory: true)
            .appendingPathComponent("agent-change-requests-v1", isDirectory: true)
        storage = SecureRecordDirectory(
            trustedRootURL: applicationSupportURL,
            components: [
                "Triptychs",
                triptychID.uuidString,
                "agent-change-requests-v1",
            ],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: Self.maximumRecordByteCount
        )
        try storage.ensureDirectories([])
        lock = try AdvisoryFileLock(
            directory: storage,
            fileName: "agent-change-requests-v1.lock"
        )
        Self.processLock.lock()
        defer { Self.processLock.unlock() }
        try lock.withExclusiveLock {
            try storage.removeAbandonedStagingFiles(in: [nil])
        }
    }

    /// Atomically records one request after the Application has authenticated
    /// its parent run and evaluated the live requested Action envelope.
    /// Exact replay returns the first record; changed content under the same ID
    /// fails closed.
    public func submitValidated(
        _ request: AgentNoteChangeRequest,
        isCurrent: Bool,
        receivedAt: Date = Date(),
        validFor: TimeInterval = 10 * 60
    ) throws -> AgentNoteChangeRequestRecord {
        try Task.checkCancellation()
        guard request.triptychID == triptychID else {
            throw AgentNoteChangeRequestStoreError.triptychMismatch(request.id)
        }
        return try withExclusiveLock {
            try Task.checkCancellation()
            var records = try readAllRecords()
            try expirePendingRecords(&records, at: receivedAt)

            if let existing = records.first(where: { $0.id == request.id }) {
                guard existing.request == request else {
                    throw AgentNoteChangeRequestStoreError
                        .duplicateRequestPayload(request.id)
                }
                return existing
            }
            guard records.count < Self.maximumRecordCount else {
                throw AgentNoteChangeRequestStoreError.capacityExceeded
            }
            if records.contains(where: {
                $0.request.parentRunID == request.parentRunID && $0.isUnresolved
            }) {
                throw AgentNoteChangeRequestStoreError
                    .unresolvedRequestExists(request.parentRunID)
            }

            let record = try AgentNoteChangeRequestRecord(
                request: request,
                receivedAt: receivedAt,
                validFor: validFor,
                initialState: isCurrent ? .pending : .stale
            )
            return try create(record)
        }
    }

    public func record(
        id: UUID,
        now: Date = Date()
    ) throws -> AgentNoteChangeRequestRecord {
        try Task.checkCancellation()
        return try withExclusiveLock {
            try Task.checkCancellation()
            var record = try readRecord(id: id)
            let current = try record.expiringIfNeeded(at: now)
            if current != record {
                record = try replace(current)
            }
            return record
        }
    }

    public func recordIfPresent(
        id: UUID,
        now: Date = Date()
    ) throws -> AgentNoteChangeRequestRecord? {
        do {
            return try record(id: id, now: now)
        } catch AgentNoteChangeRequestStoreError.requestNotFound {
            return nil
        }
    }

    /// Reads the exact stored request solely to locate its authenticated
    /// parent. It performs no expiry or decision transition; an untrusted
    /// bridge caller must authenticate before any machine-local mutation.
    public func recordForAuthentication(
        id: UUID
    ) throws -> AgentNoteChangeRequestRecord {
        try Task.checkCancellation()
        return try withExclusiveLock {
            try Task.checkCancellation()
            return try readRecord(id: id)
        }
    }

    public func pending(now: Date = Date()) throws -> [AgentNoteChangeRequestRecord] {
        try withExclusiveLock {
            var records = try readAllRecords()
            try expirePendingRecords(&records, at: now)
            return records.filter(\.isUnresolved).sorted {
                if $0.receivedAt != $1.receivedAt {
                    return $0.receivedAt < $1.receivedAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
        }
    }

    /// Fails before a destructive Note transaction if any private request is
    /// malformed or belongs to another Triptych, so privacy cleanup cannot
    /// silently strand uninterpreted coordination data.
    public func validateStoreHealth() throws {
        try withExclusiveLock {
            _ = try readAllRecords()
        }
    }

    /// Removes private coordination records whose requested Notes or
    /// authenticated parent execution contain a permanently deleted Note.
    /// The caller's durable deletion journal makes this idempotent cleanup
    /// retryable after the source deletion has committed.
    @discardableResult
    public func purgeRequests(
        containing noteIDs: Set<UUID>,
        parentRunIDs: Set<UUID>
    ) throws -> [UUID] {
        guard !noteIDs.isEmpty || !parentRunIDs.isEmpty else { return [] }
        return try withExclusiveLock {
            let records = try readAllRecords()
            let removed = records.filter { record in
                parentRunIDs.contains(record.request.parentRunID)
                    || !Set(record.request.targets.map(\.noteID))
                        .isDisjoint(with: noteIDs)
            }.map(\.id).sorted { $0.uuidString < $1.uuidString }
            for id in removed {
                try storage.removeIfPresent(
                    directory: nil,
                    fileName: Self.fileName(id)
                )
            }
            return removed
        }
    }

    public func resolve(
        id: UUID,
        state: AgentNoteChangeDecisionState,
        allowedNoteIDs: [UUID] = [],
        continuationPlan: AgentNoteChangeContinuationPlan? = nil,
        decidedAt: Date = Date()
    ) throws -> AgentNoteChangeRequestRecord {
        try Task.checkCancellation()
        guard state != .pending else {
            throw AgentNoteChangeContractError.invalidDecision
        }
        return try withExclusiveLock {
            try Task.checkCancellation()
            var current = try readRecord(id: id)
            let expired = try current.expiringIfNeeded(at: decidedAt)
            if expired != current {
                current = try replace(expired)
            }
            if current.decision.state != .pending {
                if current.decision.state == state,
                   current.decision.allowedNoteIDs
                    == allowedNoteIDs.sorted(by: {
                        $0.uuidString < $1.uuidString
                    }) {
                    return current
                }
                throw AgentNoteChangeRequestStoreError.requestAlreadyResolved(id)
            }
            let resolved = try current.resolving(
                state: state,
                allowedNoteIDs: allowedNoteIDs,
                continuationPlan: continuationPlan,
                at: decidedAt
            )
            return try replace(resolved)
        }
    }

    private func expirePendingRecords(
        _ records: inout [AgentNoteChangeRequestRecord],
        at date: Date
    ) throws {
        for index in records.indices where records[index].isUnresolved {
            let current = try records[index].expiringIfNeeded(at: date)
            if current != records[index] {
                records[index] = try replace(current)
            }
        }
    }

    private func create(
        _ record: AgentNoteChangeRequestRecord
    ) throws -> AgentNoteChangeRequestRecord {
        let (canonical, data) = try Self.canonicalized(record)
        do {
            let readback = try storage.createExclusive(
                data,
                directory: nil,
                fileName: Self.fileName(record.id)
            )
            let stored = try Self.decode(readback)
            guard stored == canonical else {
                throw AgentNoteChangeRequestStoreError.unsafeStore
            }
            return stored
        } catch let error as AgentNoteChangeRequestStoreError {
            throw error
        } catch let error as SecureRecordDirectoryError {
            if case .alreadyExists = error {
                throw AgentNoteChangeRequestStoreError
                    .duplicateRequestPayload(record.id)
            }
            throw AgentNoteChangeRequestStoreError.unsafeStore
        } catch {
            throw AgentNoteChangeRequestStoreError.corruptStore
        }
    }

    private func replace(
        _ record: AgentNoteChangeRequestRecord
    ) throws -> AgentNoteChangeRequestRecord {
        let (canonical, data) = try Self.canonicalized(record)
        do {
            let readback = try storage.replace(
                data,
                directory: nil,
                fileName: Self.fileName(record.id)
            )
            let stored = try Self.decode(readback)
            guard stored == canonical else {
                throw AgentNoteChangeRequestStoreError.unsafeStore
            }
            return stored
        } catch let error as AgentNoteChangeRequestStoreError {
            throw error
        } catch let error as SecureRecordDirectoryError {
            if case .replacementCommitUncertain = error {
                throw AgentNoteChangeRequestStoreError.unsafeStore
            }
            throw AgentNoteChangeRequestStoreError.corruptStore
        } catch {
            throw AgentNoteChangeRequestStoreError.corruptStore
        }
    }

    private func readRecord(id: UUID) throws -> AgentNoteChangeRequestRecord {
        do {
            let record = try Self.decode(storage.read(
                directory: nil,
                fileName: Self.fileName(id)
            ))
            guard record.id == id,
                  record.request.triptychID == triptychID else {
                throw AgentNoteChangeRequestStoreError.corruptStore
            }
            return record
        } catch let error as SecureRecordDirectoryError {
            if case .notFound = error {
                throw AgentNoteChangeRequestStoreError.requestNotFound(id)
            }
            throw AgentNoteChangeRequestStoreError.corruptStore
        } catch let error as AgentNoteChangeRequestStoreError {
            throw error
        } catch {
            throw AgentNoteChangeRequestStoreError.corruptStore
        }
    }

    private func readAllRecords() throws -> [AgentNoteChangeRequestRecord] {
        do {
            let names = try storage.fileNames(in: nil).filter { $0.hasSuffix(".json") }
            guard names.count <= Self.maximumRecordCount else {
                throw AgentNoteChangeRequestStoreError.capacityExceeded
            }
            return try names.map { name in
                guard let id = Self.id(from: name) else {
                    throw AgentNoteChangeRequestStoreError.corruptStore
                }
                let record = try Self.decode(storage.read(
                    directory: nil,
                    fileName: name
                ))
                guard record.id == id,
                      record.request.triptychID == triptychID else {
                    throw AgentNoteChangeRequestStoreError.corruptStore
                }
                return record
            }
        } catch let error as AgentNoteChangeRequestStoreError {
            throw error
        } catch {
            throw AgentNoteChangeRequestStoreError.corruptStore
        }
    }

    private func withExclusiveLock<T>(_ operation: () throws -> T) throws -> T {
        Self.processLock.lock()
        defer { Self.processLock.unlock() }
        return try lock.withExclusiveLock(operation)
    }

    private static func canonicalized(
        _ record: AgentNoteChangeRequestRecord
    ) throws -> (AgentNoteChangeRequestRecord, Data) {
        let first = try makeEncoder().encode(record)
        let canonical = try makeDecoder().decode(
            AgentNoteChangeRequestRecord.self,
            from: first
        )
        return (canonical, try makeEncoder().encode(canonical))
    }

    private static func decode(_ data: Data) throws -> AgentNoteChangeRequestRecord {
        try makeDecoder().decode(AgentNoteChangeRequestRecord.self, from: data)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }

    private static func fileName(_ id: UUID) -> String {
        id.uuidString.lowercased() + ".json"
    }

    private static func id(from fileName: String) -> UUID? {
        guard fileName.hasSuffix(".json") else { return nil }
        return UUID(uuidString: String(fileName.dropLast(5)))
    }
}
