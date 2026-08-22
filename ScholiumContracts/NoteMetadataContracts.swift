import Foundation

/// One portable, researcher-owned metadata record. Scholium owns the schema,
/// validation, and transaction boundary; the researcher owns every value.
/// The record is never a writable projection of Markdown or YAML.
public struct NoteMetadataRecord: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let noteID: UUID
    public let fields: [String: YAMLValue]

    public init(noteID: UUID, fields: [String: YAMLValue]) {
        schemaVersion = Self.currentSchemaVersion
        self.noteID = noteID
        self.fields = fields
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, noteID, fields
    }

    /// Canonical portable bytes shared by the control store, write planning,
    /// and recovery classification. No caller may invent another encoding.
    public func encodedPortableData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported Note metadata schema \(version)."
            )
        }
        let noteID = try container.decode(UUID.self, forKey: .noteID)
        let fields = try container.decode([String: YAMLValue].self, forKey: .fields)
        guard fields.count <= 128,
              fields.keys.allSatisfy({ key in
                  !key.isEmpty && key.utf8.count <= 128
                      && !key.unicodeScalars.contains(where: {
                          CharacterSet.controlCharacters.contains($0)
                      })
              }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .fields,
                in: container,
                debugDescription: "Note metadata contains invalid field keys."
            )
        }
        self.schemaVersion = version
        self.noteID = noteID
        self.fields = fields
    }
}

/// Exact portable-file revision used for compare-and-swap metadata edits.
public struct NoteMetadataSnapshot: Codable, Hashable, Sendable {
    public let record: NoteMetadataRecord
    public let revision: DocumentFingerprint

    public init(record: NoteMetadataRecord, revision: DocumentFingerprint) {
        self.record = record
        self.revision = revision
    }
}

public enum NoteMetadataError: LocalizedError, Equatable, Sendable {
    case invalidCatalog
    case invalidRecord(UUID)
    case revisionConflict(UUID)
    case identityUnavailable(UUID)
    case identityUnavailableAtPath(String)
    case commitUncertain(UUID, String)

    public var errorDescription: String? {
        switch self {
        case .invalidCatalog:
            "Portable Note metadata is damaged or uses an unsupported schema. Its exact files were preserved."
        case .invalidRecord(let id):
            "Portable metadata for Note \(id.uuidString) is invalid. Its exact bytes were preserved."
        case .revisionConflict:
            "This Note's metadata changed after it was loaded. Reload the current values before saving."
        case .identityUnavailable(let id):
            "Portable metadata cannot be changed because Note identity \(id.uuidString) is unavailable."
        case .identityUnavailableAtPath(let relativePath):
            "Portable metadata cannot be changed because the Note at \(relativePath) does not have a current stable identity."
        case .commitUncertain(let id, let reason):
            "Scholium could not prove the final metadata state for Note \(id.uuidString). Reread it before retrying: \(reason)"
        }
    }
}
