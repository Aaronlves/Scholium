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
