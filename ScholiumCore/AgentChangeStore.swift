import Foundation
import ScholiumContracts

/// Machine-local, descriptor-contained exact evidence for MCP mutations. One
/// file is one independent source transaction; no Run, Session, Result, or
/// research lifecycle participates.
public actor AgentChangeStore {
    private struct Payload: Codable, Hashable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        let id: UUID
        let triptychID: UUID
        let operation: AgentChangeOperation
        let noteID: UUID
        let role: VaultRole
        let originalRelativePath: String?
        let finalRelativePath: String?
        let beforeFingerprint: DocumentFingerprint?
        let beforeData: Data?
        let afterFingerprint: DocumentFingerprint?
        let afterData: Data?
        let state: AgentChangeRecoveryState
        let createdAt: Date
        let confirmedAt: Date?
        let undoneAt: Date?

        init(
            id: UUID,
            triptychID: UUID,
            operation: AgentChangeOperation,
            noteID: UUID,
            role: VaultRole,
            originalRelativePath: String?,
            finalRelativePath: String?,
            beforeData: Data?,
            afterData: Data?,
            state: AgentChangeRecoveryState = .prepared,
            createdAt: Date = Date(),
            confirmedAt: Date? = nil,
            undoneAt: Date? = nil
        ) {
            schemaVersion = Self.currentSchemaVersion
            self.id = id
            self.triptychID = triptychID
            self.operation = operation
            self.noteID = noteID
            self.role = role
            self.originalRelativePath = originalRelativePath
            self.finalRelativePath = finalRelativePath
            beforeFingerprint = beforeData.map(DocumentFingerprint.init(data:))
            self.beforeData = beforeData
            afterFingerprint = afterData.map(DocumentFingerprint.init(data:))
            self.afterData = afterData
            self.state = state
            self.createdAt = createdAt
            self.confirmedAt = confirmedAt
            self.undoneAt = undoneAt
        }

        var change: AgentChange {
            AgentChange(
                id: id,
                triptychID: triptychID,
                operation: operation,
                noteID: noteID,
                role: role,
                originalRelativePath: originalRelativePath,
                finalRelativePath: finalRelativePath,
                beforeFingerprint: beforeFingerprint,
                afterFingerprint: afterFingerprint,
                state: state,
                createdAt: createdAt,
                confirmedAt: confirmedAt,
                undoneAt: undoneAt
            )
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case schemaVersion, id, triptychID, operation, noteID, role
            case originalRelativePath, finalRelativePath
            case beforeFingerprint, beforeData, afterFingerprint, afterData
            case state, createdAt, confirmedAt, undoneAt
        }

        init(from decoder: Decoder) throws {
            try ResearchStoreCodingValidation.rejectUnknownFields(
                in: decoder,
                allowed: CodingKeys.allCases.map(\.stringValue),
                onUnknownField: { _ in AgentChangeError.invalid(UUID()) }
            )
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            id = try container.decode(UUID.self, forKey: .id)
            triptychID = try container.decode(UUID.self, forKey: .triptychID)
            operation = try container.decode(AgentChangeOperation.self, forKey: .operation)
            noteID = try container.decode(UUID.self, forKey: .noteID)
            role = try container.decode(VaultRole.self, forKey: .role)
            originalRelativePath = try container.decodeIfPresent(
                String.self,
                forKey: .originalRelativePath
            )
            finalRelativePath = try container.decodeIfPresent(
                String.self,
                forKey: .finalRelativePath
            )
            beforeFingerprint = try container.decodeIfPresent(
                DocumentFingerprint.self,
                forKey: .beforeFingerprint
            )
            beforeData = try container.decodeIfPresent(Data.self, forKey: .beforeData)
            afterFingerprint = try container.decodeIfPresent(
                DocumentFingerprint.self,
                forKey: .afterFingerprint
            )
            afterData = try container.decodeIfPresent(Data.self, forKey: .afterData)
            state = try container.decode(AgentChangeRecoveryState.self, forKey: .state)
            createdAt = try container.decode(Date.self, forKey: .createdAt)
            confirmedAt = try container.decodeIfPresent(Date.self, forKey: .confirmedAt)
            undoneAt = try container.decodeIfPresent(Date.self, forKey: .undoneAt)
        }
    }

    private static let maximumPayloadByteCount =
        3 * ScholiumMCPContract.maximumDocumentUTF8ByteCount + 64 * 1_024

    private let triptychID: UUID
    private let storage: SecureRecordDirectory
    private let lock: AdvisoryFileLock

    public init(applicationSupportURL: URL, triptychID: UUID) throws {
        self.triptychID = triptychID
        storage = SecureRecordDirectory(
            trustedRootURL: applicationSupportURL,
            components: [
                "Triptychs",
                triptychID.uuidString,
                "agent-changes-v1",
            ],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: Self.maximumPayloadByteCount
        )
        do {
            lock = try AdvisoryFileLock(
                directory: storage,
                fileName: "agent-changes-v1.lock"
            )
            try lock.withExclusiveLock {
                try storage.removeAbandonedStagingFiles(in: [nil])
            }
        } catch {
            throw AgentChangeError.unsafeStore(error.localizedDescription)
        }
    }

    @discardableResult
    public func prepare(
        id: UUID = UUID(),
        operation: AgentChangeOperation,
        noteID: UUID,
        role: VaultRole,
        originalRelativePath: String?,
        finalRelativePath: String?,
        beforeData: Data?,
        afterData: Data?
    ) throws -> AgentChange {
        guard [beforeData, afterData].compactMap({ $0 }).allSatisfy({
            $0.count <= ScholiumMCPContract.maximumDocumentUTF8ByteCount
        }) else {
            throw AgentChangeError.sourceTooLarge
        }
        let payload = Payload(
            id: id,
            triptychID: triptychID,
            operation: operation,
            noteID: noteID,
            role: role,
            originalRelativePath: originalRelativePath,
            finalRelativePath: finalRelativePath,
            beforeData: beforeData,
            afterData: afterData
        )
        try validate(payload)
        return try locked {
            let readback = try storage.createExclusive(
                encode(payload),
                directory: nil,
                fileName: fileName(id)
            )
            return try decodeAndValidate(readback, expectedID: id).change
        }
    }

    @discardableResult
    public func confirm(
        id: UUID,
        observedAfterFingerprint: DocumentFingerprint?
    ) throws -> AgentChange {
        try locked {
            let current = try readPayload(id)
            if current.state == .confirmed {
                guard current.afterFingerprint == observedAfterFingerprint else {
                    throw AgentChangeError.mismatchedBinding(id)
                }
                return current.change
            }
            guard current.state == .prepared,
                  current.afterFingerprint == observedAfterFingerprint else {
                throw AgentChangeError.mismatchedBinding(id)
            }
            let replacement = Payload(
                id: current.id,
                triptychID: current.triptychID,
                operation: current.operation,
                noteID: current.noteID,
                role: current.role,
                originalRelativePath: current.originalRelativePath,
                finalRelativePath: current.finalRelativePath,
                beforeData: current.beforeData,
                afterData: current.afterData,
                state: .confirmed,
                createdAt: current.createdAt,
                confirmedAt: Date()
            )
            return try replace(replacement).change
        }
    }

    @discardableResult
    public func markOutcomeUncertain(id: UUID) throws -> AgentChange {
        try locked {
            let current = try readPayload(id)
            guard current.state == .prepared else { return current.change }
            let replacement = Payload(
                id: current.id,
                triptychID: current.triptychID,
                operation: current.operation,
                noteID: current.noteID,
                role: current.role,
                originalRelativePath: current.originalRelativePath,
                finalRelativePath: current.finalRelativePath,
                beforeData: current.beforeData,
                afterData: current.afterData,
                state: .outcomeUncertain,
                createdAt: current.createdAt
            )
            return try replace(replacement).change
        }
    }

    public func discardPrepared(id: UUID) throws {
        try locked {
            let data = try storage.read(directory: nil, fileName: fileName(id))
            let payload = try decodeAndValidate(data, expectedID: id)
            guard payload.state == .prepared else {
                throw AgentChangeError.alreadyFinal(id)
            }
            try storage.remove(directory: nil, fileName: fileName(id), expected: data)
        }
    }

    public func change(id: UUID) throws -> AgentChange {
        try locked { try readPayload(id).change }
    }

    public func changes() throws -> [AgentChange] {
        try locked {
            try storage.fileNames(in: nil)
                .filter { $0.hasSuffix(".json") }
                .map { name in
                    let data = try storage.read(directory: nil, fileName: name)
                    return try decodeAndValidate(data, expectedID: nil).change
                }
                .sorted {
                    if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                    return $0.id.uuidString < $1.id.uuidString
                }
        }
    }

    public func beforeDataForUndo(
        id: UUID,
        expectedAfterFingerprint: DocumentFingerprint
    ) throws -> Data {
        try locked {
            let payload = try readPayload(id)
            guard payload.operation == .update,
                  payload.state == .confirmed,
                  payload.afterFingerprint == expectedAfterFingerprint,
                  let data = payload.beforeData else {
                throw AgentChangeError.undoUnavailable(id)
            }
            return data
        }
    }

    @discardableResult
    public func markUndone(
        id: UUID,
        restoredFingerprint: DocumentFingerprint
    ) throws -> AgentChange {
        try locked {
            let current = try readPayload(id)
            guard current.operation == .update,
                  current.state == .confirmed,
                  current.beforeFingerprint == restoredFingerprint else {
                throw AgentChangeError.undoUnavailable(id)
            }
            let replacement = Payload(
                id: current.id,
                triptychID: current.triptychID,
                operation: current.operation,
                noteID: current.noteID,
                role: current.role,
                originalRelativePath: current.originalRelativePath,
                finalRelativePath: current.finalRelativePath,
                beforeData: current.beforeData,
                afterData: current.afterData,
                state: .undone,
                createdAt: current.createdAt,
                confirmedAt: current.confirmedAt,
                undoneAt: Date()
            )
            return try replace(replacement).change
        }
    }

    private func replace(_ payload: Payload) throws -> Payload {
        try validate(payload)
        let readback = try storage.replace(
            encode(payload),
            directory: nil,
            fileName: fileName(payload.id)
        )
        return try decodeAndValidate(readback, expectedID: payload.id)
    }

    private func readPayload(_ id: UUID) throws -> Payload {
        do {
            return try decodeAndValidate(
                storage.read(directory: nil, fileName: fileName(id)),
                expectedID: id
            )
        } catch let error as SecureRecordDirectoryError {
            if case .notFound = error { throw AgentChangeError.missing(id) }
            throw error
        }
    }

    private func encode(_ payload: Payload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    private func decodeAndValidate(
        _ data: Data,
        expectedID: UUID?
    ) throws -> Payload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload: Payload
        do {
            payload = try decoder.decode(Payload.self, from: data)
        } catch {
            throw AgentChangeError.invalid(expectedID ?? UUID())
        }
        guard expectedID.map({ $0 == payload.id }) ?? true else {
            throw AgentChangeError.mismatchedBinding(expectedID ?? payload.id)
        }
        try validate(payload)
        return payload
    }

    private func validate(_ payload: Payload) throws {
        let shapeIsValid: Bool = switch payload.operation {
        case .create:
            payload.beforeData == nil && payload.beforeFingerprint == nil
                && payload.afterData != nil && payload.afterFingerprint != nil
                && payload.originalRelativePath == nil
                && payload.finalRelativePath != nil
        case .update:
            payload.beforeData != nil && payload.beforeFingerprint != nil
                && payload.afterData != nil && payload.afterFingerprint != nil
                && payload.originalRelativePath != nil
                && payload.originalRelativePath == payload.finalRelativePath
        case .trash:
            payload.beforeData != nil && payload.beforeFingerprint != nil
                && payload.afterData == nil && payload.afterFingerprint == nil
                && payload.originalRelativePath != nil
                && payload.finalRelativePath == nil
        }
        let stateIsValid: Bool = switch payload.state {
        case .prepared, .outcomeUncertain:
            payload.confirmedAt == nil && payload.undoneAt == nil
        case .confirmed:
            payload.confirmedAt != nil && payload.undoneAt == nil
        case .undone:
            payload.operation == .update && payload.confirmedAt != nil
                && payload.undoneAt != nil
        }
        guard payload.schemaVersion == Payload.currentSchemaVersion,
              payload.triptychID == triptychID,
              shapeIsValid,
              stateIsValid,
              [payload.beforeData, payload.afterData].compactMap({ $0 }).allSatisfy({
                  $0.count <= ScholiumMCPContract.maximumDocumentUTF8ByteCount
              }),
              payload.beforeData.map(DocumentFingerprint.init(data:))
                == payload.beforeFingerprint,
              payload.afterData.map(DocumentFingerprint.init(data:))
                == payload.afterFingerprint,
              payload.beforeFingerprint.map(
                  ResearchStoreCodingValidation.isValidFingerprint
              ) ?? true,
              payload.afterFingerprint.map(
                  ResearchStoreCodingValidation.isValidFingerprint
              ) ?? true else {
            throw AgentChangeError.invalid(payload.id)
        }
    }

    private func fileName(_ id: UUID) -> String {
        "\(id.uuidString.lowercased()).json"
    }

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        do {
            return try lock.withExclusiveLock(operation)
        } catch let error as AgentChangeError {
            throw error
        } catch {
            throw AgentChangeError.unsafeStore(error.localizedDescription)
        }
    }
}
