import Foundation

/// The two source routes that can satisfy Analyze's source requirement.
///
/// This value is safe to retain in an Action snapshot or portable Research
/// Record. Machine-local bookmarks, paths, and source bytes are deliberately
/// absent from every type in this file.
public enum ResearchSourceRouteKind: String, Codable, CaseIterable, Hashable, Sendable {
    case localFile = "local_file"
    case zoteroAttachment = "zotero_attachment"
}

public enum ResearchSourceAccessRepairAction: String, Codable, Hashable, Sendable {
    case chooseSourceAgain = "choose_source_again"
}

public enum ResearchSourceAccessFailureCode: String, Codable, Hashable, Sendable {
    case missingBinding = "missing_binding"
    case corruptBinding = "corrupt_binding"
    case bookmarkUnavailable = "bookmark_unavailable"
    case bookmarkStale = "bookmark_stale"
    case sourceMissing = "source_missing"
    case sourceUnreadable = "source_unreadable"
    case sourceNotRegular = "source_not_regular"
    case sourceIsSymbolicLink = "source_is_symbolic_link"
    case sourceChanged = "source_changed"
    case zoteroUnavailable = "zotero_unavailable"
    case zoteroAttachmentMissing = "zotero_attachment_missing"
    case zoteroIdentityMismatch = "zotero_identity_mismatch"
}

/// One localization-free, semantically narrow repair result. Every failure
/// returns the same researcher-controlled recovery action rather than silently
/// substituting the Analysis note for its source.
public struct ResearchSourceAccessFailure: Codable, Hashable, Sendable {
    public let code: ResearchSourceAccessFailureCode
    public let repairAction: ResearchSourceAccessRepairAction

    public init(
        code: ResearchSourceAccessFailureCode,
        repairAction: ResearchSourceAccessRepairAction = .chooseSourceAgain
    ) {
        self.code = code
        self.repairAction = repairAction
    }
}

/// Stable source identity without a machine path. Zotero identity is exact at
/// both the parent-item and attachment-item layers; a parent item alone can
/// never satisfy Analyze.
public struct ResearchSourceIdentity: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumZoteroKeyUTF8ByteCount = 64

    public let schemaVersion: Int
    public let id: UUID
    public let route: ResearchSourceRouteKind
    public let zoteroItemKey: String?
    public let zoteroAttachmentKey: String?

    public static func localFile(id: UUID = UUID()) -> Self {
        Self(
            validatedSchemaVersion: Self.currentSchemaVersion,
            id: id,
            route: .localFile,
            zoteroItemKey: nil,
            zoteroAttachmentKey: nil
        )
    }

    public static func zoteroAttachment(
        id: UUID = UUID(),
        itemKey: String,
        attachmentKey: String
    ) throws -> Self {
        try Self(
            id: id,
            route: .zoteroAttachment,
            zoteroItemKey: itemKey,
            zoteroAttachmentKey: attachmentKey
        )
    }

    private init(
        schemaVersion: Int = currentSchemaVersion,
        id: UUID,
        route: ResearchSourceRouteKind,
        zoteroItemKey: String? = nil,
        zoteroAttachmentKey: String? = nil
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ResearchSourceAccessContractError.unsupportedSchemaVersion(schemaVersion)
        }
        let itemKey = try Self.normalizedZoteroKey(zoteroItemKey)
        let attachmentKey = try Self.normalizedZoteroKey(zoteroAttachmentKey)
        switch route {
        case .localFile:
            guard itemKey == nil, attachmentKey == nil else {
                throw ResearchSourceAccessContractError.invalidIdentity
            }
        case .zoteroAttachment:
            guard itemKey != nil, attachmentKey != nil,
                  itemKey != attachmentKey else {
                throw ResearchSourceAccessContractError.invalidIdentity
            }
        }
        self.init(
            validatedSchemaVersion: schemaVersion,
            id: id,
            route: route,
            zoteroItemKey: itemKey,
            zoteroAttachmentKey: attachmentKey
        )
    }

    private init(
        validatedSchemaVersion schemaVersion: Int,
        id: UUID,
        route: ResearchSourceRouteKind,
        zoteroItemKey: String?,
        zoteroAttachmentKey: String?
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.route = route
        self.zoteroItemKey = zoteroItemKey
        self.zoteroAttachmentKey = zoteroAttachmentKey
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case id
        case route
        case zoteroItemKey
        case zoteroAttachmentKey
    }

    public init(from decoder: Decoder) throws {
        let strictContainer = try decoder.container(keyedBy: StrictCodingKey.self)
        try rejectUnknownKeys(strictContainer, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            id: try container.decode(UUID.self, forKey: .id),
            route: try container.decode(ResearchSourceRouteKind.self, forKey: .route),
            zoteroItemKey: try container.decodeIfPresent(
                String.self,
                forKey: .zoteroItemKey
            ),
            zoteroAttachmentKey: try container.decodeIfPresent(
                String.self,
                forKey: .zoteroAttachmentKey
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(route, forKey: .route)
        try container.encodeIfPresent(zoteroItemKey, forKey: .zoteroItemKey)
        try container.encodeIfPresent(zoteroAttachmentKey, forKey: .zoteroAttachmentKey)
    }

    private static func normalizedZoteroKey(_ value: String?) throws -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty,
              normalized.utf8.count <= maximumZoteroKeyUTF8ByteCount,
              normalized.unicodeScalars.allSatisfy({ scalar in
                  CharacterSet.alphanumerics.contains(scalar)
                      || scalar == "-"
                      || scalar == "_"
              }) else {
            throw ResearchSourceAccessContractError.invalidZoteroKey
        }
        return normalized
    }
}

/// The complete source projection allowed in a durable run or portable
/// Research Record. It is intentionally impossible to encode the bookmark,
/// absolute path, or source bytes through this contract.
public struct ResearchSourceReference: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumDisplayNameUTF8ByteCount = 512

    public let schemaVersion: Int
    public let identity: ResearchSourceIdentity
    public let displayName: String
    public let fingerprint: DocumentFingerprint

    public init(
        identity: ResearchSourceIdentity,
        displayName: String,
        fingerprint: DocumentFingerprint
    ) throws {
        try self.init(
            schemaVersion: Self.currentSchemaVersion,
            identity: identity,
            displayName: displayName,
            fingerprint: fingerprint
        )
    }

    private init(
        schemaVersion: Int,
        identity: ResearchSourceIdentity,
        displayName: String,
        fingerprint: DocumentFingerprint
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ResearchSourceAccessContractError.unsupportedSchemaVersion(schemaVersion)
        }
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty,
              normalizedName.utf8.count <= Self.maximumDisplayNameUTF8ByteCount,
              !normalizedName.contains("/"),
              !normalizedName.contains("\\"),
              !normalizedName.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else {
            throw ResearchSourceAccessContractError.invalidDisplayName
        }
        guard fingerprint.byteCount >= 0,
              fingerprint.sha256.count == 64,
              fingerprint.sha256.unicodeScalars.allSatisfy({ scalar in
                  ("0"..."9").contains(Character(scalar))
                      || ("a"..."f").contains(Character(scalar))
              }) else {
            throw ResearchSourceAccessContractError.invalidFingerprint
        }
        self.schemaVersion = schemaVersion
        self.identity = identity
        self.displayName = normalizedName
        self.fingerprint = fingerprint
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case identity
        case displayName
        case fingerprint
    }

    public init(from decoder: Decoder) throws {
        let strictContainer = try decoder.container(keyedBy: StrictCodingKey.self)
        try rejectUnknownKeys(strictContainer, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            identity: try container.decode(
                ResearchSourceIdentity.self,
                forKey: .identity
            ),
            displayName: try container.decode(String.self, forKey: .displayName),
            fingerprint: try container.decode(
                DocumentFingerprint.self,
                forKey: .fingerprint
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(identity, forKey: .identity)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(fingerprint, forKey: .fingerprint)
    }
}

public enum ResearchSourceAccessState: String, Codable, Hashable, Sendable {
    case available
    case repairRequired = "repair_required"
}

/// Safe status projection for preparation and later native source controls.
/// A missing binding is represented as repair-required rather than by a nil
/// status so callers cannot confuse absence with optional source access.
public struct ResearchSourceAccessStatus: Codable, Hashable, Sendable {
    public let state: ResearchSourceAccessState
    public let reference: ResearchSourceReference?
    public let failure: ResearchSourceAccessFailure?

    public static func available(_ reference: ResearchSourceReference) -> Self {
        Self(state: .available, reference: reference, failure: nil)
    }

    public static func repairRequired(
        _ code: ResearchSourceAccessFailureCode,
        reference: ResearchSourceReference? = nil
    ) -> Self {
        Self(
            state: .repairRequired,
            reference: reference,
            failure: ResearchSourceAccessFailure(code: code)
        )
    }

    private init(
        state: ResearchSourceAccessState,
        reference: ResearchSourceReference?,
        failure: ResearchSourceAccessFailure?
    ) {
        self.state = state
        self.reference = reference
        self.failure = failure
    }
}

/// A transient selection request. It is deliberately not Codable because its
/// file URL belongs only to the current machine-local handoff.
public enum ResearchSourceSelection: Hashable, Sendable {
    case localFile(URL)
    case zoteroAttachment(
        itemKey: String,
        attachmentKey: String,
        selectedFileURL: URL
    )
}

public struct ResearchSourceBindingRequest: Hashable, Sendable {
    public let target: ResearchFunctionTarget
    public let selection: ResearchSourceSelection

    public init(target: ResearchFunctionTarget, selection: ResearchSourceSelection) {
        self.target = target
        self.selection = selection
    }
}

public enum ResearchSourceAccessContractError: LocalizedError, Sendable {
    case unsupportedSchemaVersion(Int)
    case unknownField(String)
    case invalidIdentity
    case invalidZoteroKey
    case invalidDisplayName
    case invalidFingerprint

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Unsupported Research Source Access schema version: \(version)."
        case .unknownField(let field):
            "Unknown Research Source Access field: \(field)."
        case .invalidIdentity:
            "The Research Source identity does not match its route."
        case .invalidZoteroKey:
            "A Zotero source requires bounded item and attachment keys."
        case .invalidDisplayName:
            "A Research Source display name must be bounded and contain no control characters."
        case .invalidFingerprint:
            "A Research Source fingerprint must contain a lowercase SHA-256 digest and a nonnegative byte count."
        }
    }
}

private struct StrictCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }

    init<Key: RawRepresentable>(_ key: Key) where Key.RawValue == String {
        stringValue = key.rawValue
    }
}

private func rejectUnknownKeys<Key: CodingKey & CaseIterable>(
    _ container: KeyedDecodingContainer<StrictCodingKey>,
    allowed: Key.Type
) throws where Key.AllCases: Sequence {
    let allowedNames = Set(allowed.allCases.map(\.stringValue))
    if let unknown = container.allKeys.first(where: {
        !allowedNames.contains($0.stringValue)
    }) {
        throw ResearchSourceAccessContractError.unknownField(unknown.stringValue)
    }
}
