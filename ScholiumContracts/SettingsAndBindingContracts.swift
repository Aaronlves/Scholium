import Foundation

/// Exact-byte revision of portable `.scholium/settings.json`.
public struct SettingsRevision: Codable, Hashable, Sendable {
    public let fingerprint: DocumentFingerprint

    public init(fingerprint: DocumentFingerprint) {
        self.fingerprint = fingerprint
    }
}

public struct TriptychSettingsSnapshot: Codable, Hashable, Sendable {
    public let settings: TriptychSettings
    public let revision: SettingsRevision

    public init(settings: TriptychSettings, revision: SettingsRevision) {
        self.settings = settings
        self.revision = revision
    }
}

/// Read result for portable settings before the app decides whether editing or
/// managed creation is authorized. A current-schema semantic failure retains
/// the decoded candidate and exact-byte revision so Settings can repair it;
/// unsupported or damaged envelopes remain byte-preserved but undecoded.
public enum TriptychSettingsLoadState: Equatable, Sendable {
    case current(TriptychSettingsSnapshot)
    case needsReview(
        settings: TriptychSettings,
        revision: SettingsRevision,
        reason: String
    )
    case missing
    case oldSchema(Int?)
    case futureSchema(Int)
    case corrupted

    public var authorizesAboutProjection: Bool {
        if case .current = self { true } else { false }
    }
}

/// Exact Zotero library identity. User and group libraries remain distinct
/// even when they contain the same item key.
public enum ZoteroLibraryIdentity: Codable, Hashable, Sendable {
    case user
    case group(Int)

    private enum CodingKeys: String, CodingKey {
        case kind
        case groupID = "group_id"
    }

    private enum Kind: String, Codable {
        case user
        case group
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .user:
            self = .user
        case .group:
            let id = try container.decode(Int.self, forKey: .groupID)
            guard id > 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .groupID,
                    in: container,
                    debugDescription: "Zotero group IDs must be positive."
                )
            }
            self = .group(id)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .user:
            try container.encode(Kind.user, forKey: .kind)
        case .group(let id):
            guard id > 0 else {
                throw EncodingError.invalidValue(
                    id,
                    EncodingError.Context(
                        codingPath: encoder.codingPath,
                        debugDescription: "Zotero group IDs must be positive."
                    )
                )
            }
            try container.encode(Kind.group, forKey: .kind)
            try container.encode(id, forKey: .groupID)
        }
    }
}

/// Portable integration relationship keyed only by stable Analysis Note ID.
/// It is not a Property or a bibliographic metadata snapshot.
public struct AnalysisZoteroBinding: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID { noteID }
    public let noteID: UUID
    public let library: ZoteroLibraryIdentity
    public let itemKey: String

    public init(noteID: UUID, library: ZoteroLibraryIdentity, itemKey: String) throws {
        if case .group(let groupID) = library, groupID <= 0 {
            throw AnalysisZoteroBindingError.invalidLibrary
        }
        let itemKey = itemKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !itemKey.isEmpty,
              itemKey.utf8.count <= 128,
              itemKey.unicodeScalars.allSatisfy({ scalar in
                  CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
              }) else {
            throw AnalysisZoteroBindingError.invalidItemKey
        }
        self.noteID = noteID
        self.library = library
        self.itemKey = itemKey
    }

    private enum CodingKeys: String, CodingKey {
        case noteID = "note_id"
        case library
        case itemKey = "item_key"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                noteID: container.decode(UUID.self, forKey: .noteID),
                library: container.decode(ZoteroLibraryIdentity.self, forKey: .library),
                itemKey: container.decode(String.self, forKey: .itemKey)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .itemKey,
                in: container,
                debugDescription: error.localizedDescription
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        let validated = try AnalysisZoteroBinding(
            noteID: noteID,
            library: library,
            itemKey: itemKey
        )
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(validated.noteID, forKey: .noteID)
        try container.encode(validated.library, forKey: .library)
        try container.encode(validated.itemKey, forKey: .itemKey)
    }
}

public enum AnalysisZoteroBindingError: LocalizedError, Sendable {
    case invalidLibrary
    case invalidItemKey

    public var errorDescription: String? {
        switch self {
        case .invalidLibrary: "The Zotero library identity is invalid."
        case .invalidItemKey: "The Zotero item key is invalid."
        }
    }
}

public struct AnalysisZoteroBindingsSnapshot: Codable, Hashable, Sendable {
    public let bindings: [AnalysisZoteroBinding]
    public let revision: DocumentFingerprint

    public init(bindings: [AnalysisZoteroBinding], revision: DocumentFingerprint) {
        self.bindings = bindings.sorted { $0.noteID.uuidString < $1.noteID.uuidString }
        self.revision = revision
    }

    public func binding(for noteID: UUID) -> AnalysisZoteroBinding? {
        bindings.first { $0.noteID == noteID }
    }
}

public struct AnalysisZoteroBindingMutationResult: Codable, Hashable, Sendable {
    public let snapshot: AnalysisZoteroBindingsSnapshot
    public let derivedRefreshWarning: String?

    public init(
        snapshot: AnalysisZoteroBindingsSnapshot,
        derivedRefreshWarning: String? = nil
    ) {
        self.snapshot = snapshot
        self.derivedRefreshWarning = derivedRefreshWarning
    }
}
