import Foundation

/// Exact serialized managed values, never a replacement for authored Markdown.
/// A null record represents absence so additions and removals have reviewable endings.
public enum AgentRecordChange {
    public static func metadata(_ value: NoteMetadataRecord?) throws -> Data {
        try value?.encodedPortableData() ?? Data("null".utf8)
    }

    public static func attachment(_ value: DocumentAttachmentRecord?) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    public static func validate(operation: AgentChangeOperation, noteID: UUID, before: Data, after: Data) throws {
        let decoder = JSONDecoder()
        switch operation {
        case .metadata:
            for data in [before, after] {
                if let record = try decoder.decode(NoteMetadataRecord?.self, from: data), record.noteID != noteID {
                    throw AgentChangeError.invalid(noteID)
                }
            }
        case .attachment:
            let old = try decoder.decode(DocumentAttachmentRecord?.self, from: before)
            let new = try decoder.decode(DocumentAttachmentRecord?.self, from: after)
            guard old != nil || new != nil,
                  [old, new].compactMap({ $0 }).allSatisfy({ $0.noteID == noteID }),
                  old == nil || new == nil || (old?.id == new?.id && old?.vaultID == new?.vaultID) else {
                throw AgentChangeError.invalid(noteID)
            }
        default: throw AgentChangeError.invalid(noteID)
        }
    }
}

public struct AgentMetadataUpdate: Sendable {
    public let expectedRevision: DocumentFingerprint?
    public let set: [String: YAMLValue]
    public let remove: [String]
    public init(expectedRevision: DocumentFingerprint?, set: [String: YAMLValue], remove: [String]) {
        self.expectedRevision = expectedRevision; self.set = set; self.remove = remove
    }
}

public struct AgentAttachmentUpdate: Sendable {
    public enum Action: String, Sendable { case add, replace, remove }
    public struct Source: Sendable {
        public let noteID: UUID
        public let attachmentID: UUID
        public let listingFingerprint: DocumentFingerprint
        public let fileFingerprint: DocumentFingerprint
        public init(noteID: UUID, attachmentID: UUID, listingFingerprint: DocumentFingerprint, fileFingerprint: DocumentFingerprint) {
            self.noteID = noteID; self.attachmentID = attachmentID; self.listingFingerprint = listingFingerprint; self.fileFingerprint = fileFingerprint
        }
    }
    public let action: Action
    public let attachmentID: UUID
    public let listingFingerprint: DocumentFingerprint
    public let source: Source?
    public init(action: Action, attachmentID: UUID, listingFingerprint: DocumentFingerprint, source: Source?) {
        self.action = action; self.attachmentID = attachmentID; self.listingFingerprint = listingFingerprint; self.source = source
    }
}

extension AgentAttachmentListing {
    public func fingerprint(triptychID: UUID, noteID: UUID) throws -> DocumentFingerprint {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let value: MCPJSONValue = .object([
            "triptych_id": .string(triptychID.uuidString), "note_id": .string(noteID.uuidString),
            "note_fingerprint": .object(["sha256": .string(noteFingerprint.sha256), "byte_count": .integer(noteFingerprint.byteCount)]),
            "attachments": try JSONDecoder().decode(MCPJSONValue.self, from: encoder.encode(attachments)),
        ])
        return DocumentFingerprint(data: try encoder.encode(value))
    }
}
