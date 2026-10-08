import Foundation

/// Durable Zotero-owned field data. Markdown owns the current readable text.
public struct ZoteroCitationFieldData: Codable, Hashable, Sendable {
    public let id: String
    public let kind: ZoteroMarkdownField.Kind
    public let code: String
    public let text: String

    public init(id: String, kind: ZoteroMarkdownField.Kind, code: String, text: String) {
        self.id = id
        self.kind = kind
        self.code = code
        self.text = text
    }
}

public enum ZoteroCitationError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedVersion, invalidData, unavailable, ownershipMismatch, sourceMismatch, invalidSource

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "This citation companion uses an unsupported format."
        case .invalidData: "The citation companion is invalid or exceeds the supported limits."
        case .unavailable: "The citation companion is missing or unavailable."
        case .ownershipMismatch: "The citation companion belongs to another Note or vault."
        case .sourceMismatch: "The citation companion does not match this exact Markdown revision."
        case .invalidSource: "Citation markers cannot be associated safely with their companion."
        }
    }
}

public struct ZoteroCitationData: Codable, Hashable, Sendable {
    public static let maximumEncodedByteCount = 8 * 1_024 * 1_024
    public static let maximumFieldUTF16Count = 256 * 1_024
    public static let maximumDocumentDataUTF16Count = 256 * 1_024

    public let schemaVersion: Int
    public let fields: [ZoteroCitationFieldData]
    public let documentData: String?
    public let bibliographyStyle: ZoteroMarkdownBibliographyStyle?
    public let acceptedFields: [ZoteroMarkdownAcceptedField]?

    public init(
        schemaVersion: Int = 1, fields: [ZoteroCitationFieldData] = [], documentData: String? = nil,
        bibliographyStyle: ZoteroMarkdownBibliographyStyle? = nil, acceptedFields: [ZoteroMarkdownAcceptedField]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.fields = fields
        self.documentData = documentData
        self.bibliographyStyle = bibliographyStyle
        self.acceptedFields = acceptedFields
    }

    public static func isValidOccurrenceID(_ id: String) -> Bool {
        id.range(of: #"\A[A-Za-z][A-Za-z0-9_-]{0,127}\z"#, options: .regularExpression) != nil
    }

    public static func newOccurrenceID() -> String {
        "c" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    public func validate() throws {
        guard schemaVersion == 1 else { throw ZoteroCitationError.unsupportedVersion }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard fields.count <= ZoteroMarkdownFields.maximumFieldCount,
            Set(fields.map(\.id)).count == fields.count,
            fields.allSatisfy({
                Self.isValidOccurrenceID($0.id) && $0.code.utf16.count <= Self.maximumFieldUTF16Count
                    && $0.text.utf16.count <= ZoteroMarkdownFields.maximumFallbackUTF16Count
            }),
            (documentData?.utf16.count ?? 0) <= Self.maximumDocumentDataUTF16Count,
            bibliographyStyle?.isValid != false,
            (acceptedFields?.count ?? 0) <= ZoteroMarkdownFields.maximumFieldCount,
            acceptedFields?.allSatisfy({ Self.isValidOccurrenceID($0.id) && $0.code.utf16.count <= Self.maximumFieldUTF16Count }) != false,
            Set(acceptedFields?.map(\.id) ?? []).count == (acceptedFields?.count ?? 0),
            try encoder.encode(self).count <= Self.maximumEncodedByteCount
        else { throw ZoteroCitationError.invalidData }
    }
}

/// Portable authority keyed by Note and vault identity, never by filename or label.
public struct ZoteroCitationCompanion: Codable, Hashable, Sendable {
    public static let maximumEncodedByteCount = ZoteroCitationData.maximumEncodedByteCount + 1_024
    public let schemaVersion: Int
    public let noteID: UUID
    public let vaultID: UUID
    public let sourceFingerprint: DocumentFingerprint
    public let data: ZoteroCitationData

    public init(
        schemaVersion: Int = 1, noteID: UUID, vaultID: UUID, sourceFingerprint: DocumentFingerprint,
        data: ZoteroCitationData
    ) {
        self.schemaVersion = schemaVersion
        self.noteID = noteID
        self.vaultID = vaultID
        self.sourceFingerprint = sourceFingerprint
        self.data = data
    }

    public func validate(noteID: UUID, vaultID: UUID, sourceFingerprint: DocumentFingerprint? = nil) throws {
        guard schemaVersion == 1 else { throw ZoteroCitationError.unsupportedVersion }
        guard self.noteID == noteID, self.vaultID == vaultID else { throw ZoteroCitationError.ownershipMismatch }
        guard self.sourceFingerprint.byteCount >= 0,
            self.sourceFingerprint.byteCount <= VaultSourceReadLimits.maximumNoteByteCount,
            self.sourceFingerprint.sha256.range(of: #"\A[a-f0-9]{64}\z"#, options: .regularExpression) != nil
        else { throw ZoteroCitationError.invalidData }
        if let sourceFingerprint, self.sourceFingerprint != sourceFingerprint { throw ZoteroCitationError.sourceMismatch }
        try data.validate()
    }

    /// Unknown record members are retained on disk as unsupported authority,
    /// never silently discarded by a subsequent Codable round trip.
    public static func decode(_ bytes: Data) throws -> Self {
        guard bytes.count <= maximumEncodedByteCount,
            let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        else { throw ZoteroCitationError.invalidData }
        func keys(_ object: [String: Any], _ allowed: Set<String>) throws {
            guard Set(object.keys).isSubset(of: allowed) else { throw ZoteroCitationError.unsupportedVersion }
        }
        try keys(object, ["schemaVersion", "noteID", "vaultID", "sourceFingerprint", "data"])
        if let version = object["schemaVersion"] as? Int, version != 1 { throw ZoteroCitationError.unsupportedVersion }
        guard let data = object["data"] as? [String: Any], let fields = data["fields"] as? [[String: Any]],
            let fingerprint = object["sourceFingerprint"] as? [String: Any]
        else { throw ZoteroCitationError.invalidData }
        try keys(fingerprint, ["sha256", "byteCount"])
        try keys(data, ["schemaVersion", "fields", "documentData", "bibliographyStyle", "acceptedFields"])
        if let version = data["schemaVersion"] as? Int, version != 1 { throw ZoteroCitationError.unsupportedVersion }
        for field in fields { try keys(field, ["id", "kind", "code", "text"]) }
        if let style = data["bibliographyStyle"] as? [String: Any] {
            try keys(style, ["firstLineIndent", "indent", "lineSpacing", "entrySpacing", "tabStops"])
        }
        if let accepted = data["acceptedFields"] as? [[String: Any]] {
            for field in accepted { try keys(field, ["id", "code"]) }
        }
        let companion = try JSONDecoder().decode(Self.self, from: bytes)
        try companion.validate(noteID: companion.noteID, vaultID: companion.vaultID)
        return companion
    }
}

/// `revision` fingerprints exact companion bytes. Only `.absent` with nil revision
/// proves checked absence; unavailable statuses never authorize an absence write.
public struct ZoteroCitationSnapshot: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Hashable, Sendable { case absent, available, unresolved, unsupported }
    public let noteID: UUID
    public let vaultID: UUID
    public let revision: DocumentFingerprint?
    public let sourceFingerprint: DocumentFingerprint?
    public let data: ZoteroCitationData?
    public let status: Status

    public init(
        noteID: UUID, vaultID: UUID, revision: DocumentFingerprint? = nil, sourceFingerprint: DocumentFingerprint? = nil,
        data: ZoteroCitationData? = nil, status: Status
    ) {
        self.noteID = noteID
        self.vaultID = vaultID
        self.revision = revision
        self.sourceFingerprint = sourceFingerprint
        self.data = data
        self.status = status
    }
}

public struct ZoteroCitationEdit: Codable, Hashable, Sendable {
    public let expectedRevision: DocumentFingerprint?
    /// Nil is an explicit paired restoration of companion absence, including
    /// Undo of embedded-field conversion. It is never an ordinary source save.
    public let data: ZoteroCitationData?

    public init(expectedRevision: DocumentFingerprint?, data: ZoteroCitationData?) {
        self.expectedRevision = expectedRevision
        self.data = data
    }
}

public struct ZoteroCitationConversion: Hashable, Sendable {
    public let source: String
    public let data: ZoteroCitationData
}

public enum ZoteroCitationSaveError: Error, LocalizedError, Sendable {
    case companionConflict
    case invalidCompanion(String)
    case identityChanged
    case sourceNotWritten(VaultSaveNotWrittenReason)
    case recoveryRequired(ZoteroCitationPairRecovery)

    public var errorDescription: String? {
        switch self {
        case .companionConflict: "The citation companion changed. Reload the current Note before saving citations."
        case .invalidCompanion(let reason): reason
        case .identityChanged: "The Note identity or location changed. Citation data was not reassigned."
        case .sourceNotWritten: "The Note could not be saved at its expected revision."
        case .recoveryRequired(let record):
            "The Note and its citation companion require recovery (\(record.id.uuidString)). Their exact before and after bytes remain retained."
        }
    }
}

/// A durable logical pair, separate from the repository's physical source-write
/// ledger. Fingerprints describe exact payload bytes; nil records checked absence.
public struct ZoteroCitationPairRecovery: Codable, Hashable, Identifiable, Sendable {
    public let schemaVersion: Int
    public let id: UUID
    public let triptychID: UUID
    public let noteID: UUID
    public let vaultID: UUID
    public let relativePath: String
    public let sourceBefore: DocumentFingerprint?
    public let sourceAfter: DocumentFingerprint
    public let companionBefore: DocumentFingerprint?
    public let companionAfter: DocumentFingerprint?
    public let companionRequiredBefore: Bool
    public let companionRequiredAfter: Bool

    public init(
        id: UUID = UUID(), triptychID: UUID, noteID: UUID, vaultID: UUID, relativePath: String,
        sourceBefore: Data?, sourceAfter: Data, companionBefore: Data?, companionAfter: Data?,
        companionRequiredBefore: Bool
    ) {
        schemaVersion = 1
        self.id = id
        self.triptychID = triptychID
        self.noteID = noteID
        self.vaultID = vaultID
        self.relativePath = relativePath
        self.sourceBefore = sourceBefore.map { DocumentFingerprint(data: $0) }
        self.sourceAfter = DocumentFingerprint(data: sourceAfter)
        self.companionBefore = companionBefore.map { DocumentFingerprint(data: $0) }
        self.companionAfter = companionAfter.map { DocumentFingerprint(data: $0) }
        self.companionRequiredBefore = companionRequiredBefore
        self.companionRequiredAfter = companionAfter != nil
    }
}

public enum ZoteroCitationPairState: Equatable, Sendable {
    case unchanged
    case committed
    case sourceCommitted
    case conflicted
}
