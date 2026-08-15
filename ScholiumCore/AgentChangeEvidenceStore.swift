import Foundation
import ScholiumContracts

public struct AgentChangeEvidence: Hashable, Sendable {
    public let triptychID: UUID
    public let runID: UUID
    public let noteID: UUID
    public let startingRevision: DocumentFingerprint
    public let endingRevision: DocumentFingerprint?
}

public enum AgentChangeEvidenceError: LocalizedError, Hashable, Sendable {
    case missing(runID: UUID, noteID: UUID)
    case invalid(runID: UUID, noteID: UUID)
    case mismatchedBinding(runID: UUID, noteID: UUID)
    case sourceTooLarge
    case endingUnavailable(runID: UUID, noteID: UUID)
    case alreadyCommitted(runID: UUID, noteID: UUID)
    case unsafeStore(String)

    public var errorDescription: String? {
        switch self {
        case .missing: "The exact Agent change evidence is unavailable."
        case .invalid: "The exact Agent change evidence is damaged or has an unsupported schema."
        case .mismatchedBinding: "The exact Agent change evidence belongs to another Run or Note."
        case .sourceTooLarge: "The Agent change exceeds the supported exact-source evidence size."
        case .endingUnavailable: "The Agent ending revision has not been recorded yet."
        case .alreadyCommitted: "Committed Agent change evidence cannot be replaced."
        case .unsafeStore(let reason): "Agent change evidence is unavailable: \(reason)"
        }
    }
}

/// Machine-local exact bytes for one Agent-modified `(Run, Note)` pair.
/// The natural key prevents provisional duplicates during conflict refresh.
public actor AgentChangeEvidenceStore {
    private struct Payload: Codable, Hashable {
        static let currentSchemaVersion = 2

        let schemaVersion: Int
        let triptychID: UUID
        let runID: UUID
        let noteID: UUID
        let startingRevision: DocumentFingerprint
        let startingData: Data
        let endingRevision: DocumentFingerprint?
        let endingData: Data?

        init(
            triptychID: UUID,
            runID: UUID,
            noteID: UUID,
            startingRevision: DocumentFingerprint,
            startingData: Data,
            endingRevision: DocumentFingerprint? = nil,
            endingData: Data? = nil
        ) {
            schemaVersion = Self.currentSchemaVersion
            self.triptychID = triptychID
            self.runID = runID
            self.noteID = noteID
            self.startingRevision = startingRevision
            self.startingData = startingData
            self.endingRevision = endingRevision
            self.endingData = endingData
        }

        var evidence: AgentChangeEvidence {
            AgentChangeEvidence(
                triptychID: triptychID,
                runID: runID,
                noteID: noteID,
                startingRevision: startingRevision,
                endingRevision: endingRevision
            )
        }
    }

    private static let maximumSourceByteCount =
        ResearchBoundedWriteSet.maximumDocumentUTF8ByteCount
    private static let maximumPayloadByteCount =
        3 * maximumSourceByteCount + 64 * 1_024

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
                "agent-change-evidence-v2",
            ],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: Self.maximumPayloadByteCount
        )
        do {
            lock = try AdvisoryFileLock(
                directory: storage,
                fileName: "agent-change-evidence-v2.lock"
            )
            try lock.withExclusiveLock {
                try storage.removeAbandonedStagingFiles(in: [nil])
            }
        } catch {
            throw AgentChangeEvidenceError.unsafeStore(error.localizedDescription)
        }
    }

    @discardableResult
    public func captureStartingRevision(
        runID: UUID,
        noteID: UUID,
        data: Data,
        expectedRevision: DocumentFingerprint
    ) throws -> AgentChangeEvidence {
        guard data.count <= Self.maximumSourceByteCount else {
            throw AgentChangeEvidenceError.sourceTooLarge
        }
        guard DocumentFingerprint(data: data) == expectedRevision else {
            throw AgentChangeEvidenceError.invalid(runID: runID, noteID: noteID)
        }
        let payload = Payload(
            triptychID: triptychID,
            runID: runID,
            noteID: noteID,
            startingRevision: expectedRevision,
            startingData: data
        )
        return try locked {
            let encoded = try encode(payload)
            let name = fileName(runID: runID, noteID: noteID)
            do {
                let readback = try storage.createExclusive(
                    encoded,
                    directory: nil,
                    fileName: name
                )
                return try decodeAndValidate(
                    readback,
                    runID: runID,
                    noteID: noteID
                ).evidence
            } catch let error as SecureRecordDirectoryError {
                guard case .alreadyExists = error else { throw error }
                let existing = try readPayload(runID: runID, noteID: noteID)
                guard existing == payload else {
                    throw AgentChangeEvidenceError.mismatchedBinding(
                        runID: runID,
                        noteID: noteID
                    )
                }
                return existing.evidence
            }
        }
    }

    /// Replaces a provisional starting revision during conflict refresh. Once
    /// an Agent ending revision exists, the baseline is immutable.
    @discardableResult
    public func replaceStartingRevision(
        runID: UUID,
        noteID: UUID,
        data: Data,
        expectedRevision: DocumentFingerprint
    ) throws -> AgentChangeEvidence {
        guard data.count <= Self.maximumSourceByteCount,
              DocumentFingerprint(data: data) == expectedRevision else {
            throw AgentChangeEvidenceError.invalid(runID: runID, noteID: noteID)
        }
        return try locked {
            let current = try readPayload(runID: runID, noteID: noteID)
            guard current.endingRevision == nil else {
                throw AgentChangeEvidenceError.alreadyCommitted(
                    runID: runID,
                    noteID: noteID
                )
            }
            let replacement = Payload(
                triptychID: triptychID,
                runID: runID,
                noteID: noteID,
                startingRevision: expectedRevision,
                startingData: data
            )
            let readback = try storage.replace(
                encode(replacement),
                directory: nil,
                fileName: fileName(runID: runID, noteID: noteID)
            )
            return try decodeAndValidate(
                readback,
                runID: runID,
                noteID: noteID
            ).evidence
        }
    }

    @discardableResult
    public func recordEndingRevision(
        runID: UUID,
        noteID: UUID,
        data: Data,
        expectedRevision: DocumentFingerprint
    ) throws -> AgentChangeEvidence {
        guard data.count <= Self.maximumSourceByteCount,
              DocumentFingerprint(data: data) == expectedRevision else {
            throw AgentChangeEvidenceError.invalid(runID: runID, noteID: noteID)
        }
        return try locked {
            let current = try readPayload(runID: runID, noteID: noteID)
            if current.endingRevision == expectedRevision,
               current.endingData == data {
                return current.evidence
            }
            let updated = Payload(
                triptychID: triptychID,
                runID: runID,
                noteID: noteID,
                startingRevision: current.startingRevision,
                startingData: current.startingData,
                endingRevision: expectedRevision,
                endingData: data
            )
            let readback = try storage.replace(
                encode(updated),
                directory: nil,
                fileName: fileName(runID: runID, noteID: noteID)
            )
            return try decodeAndValidate(
                readback,
                runID: runID,
                noteID: noteID
            ).evidence
        }
    }

    public func evidence(runID: UUID, noteID: UUID) throws -> AgentChangeEvidence {
        try locked { try readPayload(runID: runID, noteID: noteID).evidence }
    }

    public func startingData(
        runID: UUID,
        noteID: UUID,
        expectedRevision: DocumentFingerprint
    ) throws -> Data {
        try locked {
            let payload = try readPayload(runID: runID, noteID: noteID)
            guard payload.startingRevision == expectedRevision else {
                throw AgentChangeEvidenceError.mismatchedBinding(
                    runID: runID,
                    noteID: noteID
                )
            }
            return payload.startingData
        }
    }

    public func endingData(
        runID: UUID,
        noteID: UUID,
        expectedRevision: DocumentFingerprint
    ) throws -> Data {
        try locked {
            let payload = try readPayload(runID: runID, noteID: noteID)
            guard payload.endingRevision == expectedRevision,
                  let endingData = payload.endingData else {
                throw AgentChangeEvidenceError.endingUnavailable(
                    runID: runID,
                    noteID: noteID
                )
            }
            return endingData
        }
    }

    public func discard(runID: UUID, noteID: UUID) throws {
        try locked {
            let name = fileName(runID: runID, noteID: noteID)
            guard let data = try storage.readIfPresent(directory: nil, fileName: name)
            else { return }
            _ = try decodeAndValidate(data, runID: runID, noteID: noteID)
            try storage.remove(directory: nil, fileName: name, expected: data)
        }
    }

    @discardableResult
    public func removeEvidence(runID: UUID) throws -> Int {
        try removeEvidence { $0.runID == runID }
    }

    @discardableResult
    public func removeEvidence(noteID: UUID) throws -> Int {
        try removeEvidence { $0.noteID == noteID }
    }

    private func removeEvidence(where shouldRemove: (Payload) -> Bool) throws -> Int {
        try locked {
            var removed = 0
            for name in try storage.fileNames(in: nil) where name.hasSuffix(".json") {
                let data = try storage.read(directory: nil, fileName: name)
                let payload = try decodeAndValidate(data, runID: nil, noteID: nil)
                guard shouldRemove(payload) else { continue }
                try storage.remove(directory: nil, fileName: name, expected: data)
                removed += 1
            }
            return removed
        }
    }

    private func readPayload(runID: UUID, noteID: UUID) throws -> Payload {
        do {
            return try decodeAndValidate(
                storage.read(
                    directory: nil,
                    fileName: fileName(runID: runID, noteID: noteID)
                ),
                runID: runID,
                noteID: noteID
            )
        } catch let error as SecureRecordDirectoryError {
            if case .notFound = error {
                throw AgentChangeEvidenceError.missing(
                    runID: runID,
                    noteID: noteID
                )
            }
            throw error
        }
    }

    private func encode(_ payload: Payload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    private func decodeAndValidate(
        _ data: Data,
        runID expectedRunID: UUID?,
        noteID expectedNoteID: UUID?
    ) throws -> Payload {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw AgentChangeEvidenceError.invalid(
                runID: expectedRunID ?? UUID(),
                noteID: expectedNoteID ?? UUID()
            )
        }
        guard payload.schemaVersion == Payload.currentSchemaVersion,
              payload.triptychID == triptychID,
              expectedRunID.map({ $0 == payload.runID }) ?? true,
              expectedNoteID.map({ $0 == payload.noteID }) ?? true,
              payload.startingData.count <= Self.maximumSourceByteCount,
              DocumentFingerprint(data: payload.startingData) == payload.startingRevision,
              (payload.endingData == nil) == (payload.endingRevision == nil),
              payload.endingData.map({ $0.count <= Self.maximumSourceByteCount }) ?? true,
              payload.endingData.map(DocumentFingerprint.init(data:))
                == payload.endingRevision else {
            throw AgentChangeEvidenceError.invalid(
                runID: expectedRunID ?? payload.runID,
                noteID: expectedNoteID ?? payload.noteID
            )
        }
        return payload
    }

    private func fileName(runID: UUID, noteID: UUID) -> String {
        "\(runID.uuidString.lowercased())-\(noteID.uuidString.lowercased()).json"
    }

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        do {
            return try lock.withExclusiveLock(operation)
        } catch let error as AgentChangeEvidenceError {
            throw error
        } catch {
            throw AgentChangeEvidenceError.unsafeStore(error.localizedDescription)
        }
    }
}
