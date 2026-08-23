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

public enum NoteMetadataRecoveryReason: String, Codable, Hashable, Sendable {
    case invalidEnvelope
    case fileIdentityMismatch
    case orphanedNoteIdentity
    case invalidRoleOrFields
}

/// Fingerprint-bound recovery authority for exactly one portable metadata
/// record. It contains no record values and cannot authorize any other file.
public struct NoteMetadataRecoveryIssue: Codable, Hashable, Sendable {
    public let fileName: String
    public let fingerprint: DocumentFingerprint
    public let noteID: UUID?
    public let reason: NoteMetadataRecoveryReason

    public init(
        fileName: String,
        fingerprint: DocumentFingerprint,
        noteID: UUID?,
        reason: NoteMetadataRecoveryReason
    ) {
        self.fileName = fileName
        self.fingerprint = fingerprint
        self.noteID = noteID
        self.reason = reason
    }

    public var explanation: String {
        switch reason {
        case .invalidEnvelope:
            "The JSON record is damaged or uses an unsupported schema."
        case .fileIdentityMismatch:
            "The record's filename and embedded Note identity do not agree."
        case .orphanedNoteIdentity:
            "The record does not belong to a current stable Note identity."
        case .invalidRoleOrFields:
            "The record contains fields that do not match its Note role or the current Metadata catalog."
        }
    }
}

public enum NoteMetadataError: LocalizedError, Equatable, Sendable {
    case invalidCatalog
    case invalidRecord(UUID)
    case recoveryRequired(NoteMetadataRecoveryIssue)
    case recoveryIssueChanged
    case recoveryArchiveFailed(String)
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
        case .recoveryRequired(let issue):
            "Portable Note metadata record \(issue.fileName) requires recovery. \(issue.explanation) Its exact bytes were preserved."
        case .recoveryIssueChanged:
            "The portable Note metadata recovery record changed. Reload its current state before archiving it."
        case .recoveryArchiveFailed(let reason):
            "The portable Note metadata record could not be archived safely: \(reason)"
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
