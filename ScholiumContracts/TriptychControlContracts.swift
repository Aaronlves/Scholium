import Foundation

/// Portable identity and configuration for one Scholium Triptych.
///
/// The manifest deliberately stores no absolute paths or security-scoped
/// bookmarks. Those machine-local values remain in Application Support.
public struct TriptychManifest: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let id: UUID
    public var vaultIDs: [WorkspaceVaultSlot: UUID]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        vaultIDs: [WorkspaceVaultSlot: UUID],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.vaultIDs = vaultIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct VaultAboutConfiguration: Codable, Hashable, Sendable {
    /// Optional Scholium-managed fields always shown by About, in display
    /// order. Other stored managed values remain visible automatically.
    /// Authored `summary` and `keywords` have a fixed presentation contract
    /// and are deliberately not configurable here.
    public var visibleFields: [String] {
        didSet { visibleFields = Self.unique(visibleFields) }
    }

    public init(visibleFields: [String] = []) {
        self.visibleFields = Self.unique(visibleFields)
    }

    private enum CodingKeys: String, CodingKey {
        case visibleFields
    }

    /// Decoding deliberately retains current-schema bytes semantically as
    /// authored. The shared settings validator, rather than synthesized
    /// Codable or property observers, decides whether they need review.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        visibleFields = try container.decode([String].self, forKey: .visibleFields)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(visibleFields, forKey: .visibleFields)
    }

    /// Adds or removes an always-shown field without losing the explicit order
    /// of the remaining core fields.
    public mutating func setVisible(_ isVisible: Bool, field: String) {
        guard let field = Self.normalized(field) else { return }
        if isVisible {
            if !visibleFields.contains(field) { visibleFields.append(field) }
        } else {
            visibleFields.removeAll { $0 == field }
        }
    }

    /// Moves one always-shown field to a bounded destination while preserving
    /// all other relative ordering.
    public mutating func moveVisibleField(_ field: String, to destinationIndex: Int) {
        guard let sourceIndex = visibleFields.firstIndex(of: field) else { return }
        let value = visibleFields.remove(at: sourceIndex)
        let boundedIndex = min(max(0, destinationIndex), visibleFields.count)
        visibleFields.insert(value, at: boundedIndex)
    }

    private static func unique(_ fields: [String]) -> [String] {
        var seen: Set<String> = []
        return fields.compactMap { field in
            guard let normalized = normalized(field),
                  seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }

    private static func normalized(_ field: String) -> String? {
        let normalized = field.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

}

public struct TriptychSettings: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 8

    public let schemaVersion: Int
    /// Stable global managed-field definitions, independently scoped to
    /// Analysis, Topic, and Work. Adding or archiving a definition changes no
    /// Note value.
    public var metadataFields: [WorkspaceVaultSlot: [MetadataFieldDefinition]] {
        didSet { metadataFields = Self.completeMetadataFields(metadataFields) }
    }
    public var about: [WorkspaceVaultSlot: VaultAboutConfiguration] {
        didSet { about = Self.completeAbout(about) }
    }
    public var attentionDismissalDays: Int

    public init(
        metadataFields: [WorkspaceVaultSlot: [MetadataFieldDefinition]] = Self.defaultMetadataFields,
        about: [WorkspaceVaultSlot: VaultAboutConfiguration] = Self.defaultAbout,
        attentionDismissalDays: Int = 7
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.metadataFields = Self.completeMetadataFields(metadataFields)
        self.about = Self.completeAbout(about)
        self.attentionDismissalDays = max(1, attentionDismissalDays)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case metadataFields
        case about
        case attentionDismissalDays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported Triptych settings schema \(schemaVersion)."
            )
        }
        let metadataFields = try container.decode(
            [WorkspaceVaultSlot: [MetadataFieldDefinition]].self,
            forKey: .metadataFields
        )
        let about = try container.decode(
            [WorkspaceVaultSlot: VaultAboutConfiguration].self,
            forKey: .about
        )
        guard Set(metadataFields.keys) == Set(WorkspaceVaultSlot.allCases),
              Set(about.keys) == Set(WorkspaceVaultSlot.allCases) else {
            throw DecodingError.dataCorruptedError(
                forKey: .metadataFields,
                in: container,
                debugDescription: "Metadata settings must contain exactly all Triptych roles."
            )
        }
        self.schemaVersion = schemaVersion
        self.metadataFields = metadataFields
        self.about = about
        attentionDismissalDays = try container.decode(
            Int.self,
            forKey: .attentionDismissalDays
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(metadataFields, forKey: .metadataFields)
        try container.encode(about, forKey: .about)
        try container.encode(attentionDismissalDays, forKey: .attentionDismissalDays)
    }

    public static let defaultMetadataFields: [WorkspaceVaultSlot: [MetadataFieldDefinition]] = [
        .paperAnalysis: [],
        .topicKnowledge: [],
        .output: [],
    ]

    public static let defaultAbout: [WorkspaceVaultSlot: VaultAboutConfiguration] = [
        .paperAnalysis: VaultAboutConfiguration(
            visibleFields: [
                "type", "authors", "publication_date",
            ]
        ),
        .topicKnowledge: VaultAboutConfiguration(
            visibleFields: ["aliases"]
        ),
        .output: VaultAboutConfiguration(
            visibleFields: ["work_type", "coauthors"]
        ),
    ]

    private static func completeMetadataFields(
        _ fields: [WorkspaceVaultSlot: [MetadataFieldDefinition]]
    ) -> [WorkspaceVaultSlot: [MetadataFieldDefinition]] {
        var result = defaultMetadataFields
        for (slot, definitions) in fields {
            result[slot] = definitions
        }
        return result
    }

    private static func completeAbout(
        _ about: [WorkspaceVaultSlot: VaultAboutConfiguration]
    ) -> [WorkspaceVaultSlot: VaultAboutConfiguration] {
        var result = defaultAbout
        for (slot, configuration) in about {
            result[slot] = configuration
        }
        return result
    }

}

public struct NoteIdentityRecord: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let vaultID: UUID
    public var relativePath: String
    public var fingerprint: DocumentFingerprint
    public let createdAt: Date
    public var updatedAt: Date
    public var duplicatedFrom: UUID?

    public init(
        id: UUID = UUID(),
        vaultID: UUID,
        relativePath: String,
        fingerprint: DocumentFingerprint,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        duplicatedFrom: UUID? = nil
    ) {
        self.id = id
        self.vaultID = vaultID
        self.relativePath = relativePath
        self.fingerprint = fingerprint
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.duplicatedFrom = duplicatedFrom
    }
}

public struct NoteIdentityRebinding: Codable, Hashable, Sendable {
    public let id: UUID
    public let previousRelativePath: String
    public let relativePath: String

    public init(id: UUID, previousRelativePath: String, relativePath: String) {
        self.id = id
        self.previousRelativePath = previousRelativePath
        self.relativePath = relativePath
    }
}

public struct NoteIdentityAmbiguity: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(vaultID.uuidString):\(relativePath)" }
    public let vaultID: UUID
    public let relativePath: String
    public let fingerprint: DocumentFingerprint
    public let candidates: [NoteIdentityRecord]

    public init(
        vaultID: UUID,
        relativePath: String,
        fingerprint: DocumentFingerprint,
        candidates: [NoteIdentityRecord]
    ) {
        self.vaultID = vaultID
        self.relativePath = relativePath
        self.fingerprint = fingerprint
        self.candidates = candidates.sorted { $0.relativePath < $1.relativePath }
    }
}

/// A confirmed or uniquely detected path change whose app-owned references
/// have not all been migrated yet. This record is written atomically with the
/// identity path change, so an interruption cannot make the note appear fully
/// reconciled while History, comments, Dialogue, or other state still points
/// at the previous path.
public struct NoteIdentityPendingRebinding: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(vaultID.uuidString):\(noteID.uuidString):\(relativePath)" }
    public let noteID: UUID
    public let vaultID: UUID
    public let previousRelativePath: String
    public let relativePath: String
    public let fingerprint: DocumentFingerprint
    public let detectedAt: Date

    public init(
        noteID: UUID,
        vaultID: UUID,
        previousRelativePath: String,
        relativePath: String,
        fingerprint: DocumentFingerprint,
        detectedAt: Date = Date()
    ) {
        self.noteID = noteID
        self.vaultID = vaultID
        self.previousRelativePath = previousRelativePath
        self.relativePath = relativePath
        self.fingerprint = fingerprint
        self.detectedAt = detectedAt
    }
}

public struct NoteIdentityReconciliation: Codable, Hashable, Sendable {
    public let identities: [String: NoteIdentityRecord]
    public let rebound: [NoteIdentityRebinding]
    public let ambiguities: [NoteIdentityAmbiguity]
    public let pendingRebindings: [NoteIdentityPendingRebinding]

    public init(
        identities: [String: NoteIdentityRecord],
        rebound: [NoteIdentityRebinding] = [],
        ambiguities: [NoteIdentityAmbiguity] = [],
        pendingRebindings: [NoteIdentityPendingRebinding] = []
    ) {
        self.identities = identities
        self.rebound = rebound
        self.ambiguities = ambiguities
        self.pendingRebindings = pendingRebindings
    }
}

public enum TriptychControlError: LocalizedError, Sendable {
    case invalidManifest
    case settingsMissing
    case settingsOldSchema(Int?)
    case settingsFutureSchema(Int)
    case settingsCorrupted
    case settingsNeedsReview(String)
    case settingsRevisionConflict
    case controlFileCommitUncertain(String)
    case invalidZoteroBindings
    case zoteroBindingsRevisionConflict
    case invalidIdentities
    case identitiesRevisionConflict
    case invalidIdentityCandidate(UUID)
    case identityPathAlreadyAssigned(String)
    case identityRebindingNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .invalidManifest:
            return "The Triptych manifest is missing or does not match the selected vaults."
        case .settingsMissing:
            return "The portable Triptych settings are missing. Managed creation is unavailable until they are restored."
        case .settingsOldSchema(let version):
            let value = version.map(String.init) ?? "without a version"
            return "The portable Triptych settings use an unsupported old schema (\(value)). Their exact bytes were preserved."
        case .settingsFutureSchema(let version):
            return "The portable Triptych settings use future schema \(version). Their exact bytes were preserved."
        case .settingsCorrupted:
            return "The current-schema portable Triptych settings are damaged. Their exact bytes were preserved for recovery."
        case .settingsNeedsReview(let reason):
            return "The current-schema portable Triptych settings need review before managed creation can continue: \(reason)"
        case .settingsRevisionConflict:
            return "The Triptych settings changed after they were loaded. Reload the saved settings before trying again."
        case .controlFileCommitUncertain(let reason):
            return "Scholium could not prove the final state of a portable control-file replacement. Reread the authoritative file before retrying: \(reason)"
        case .invalidZoteroBindings:
            return "The portable Zotero bindings are missing, damaged, or use an unsupported schema."
        case .zoteroBindingsRevisionConflict:
            return "The Zotero bindings changed after they were loaded. Reload them before trying again."
        case .invalidIdentities:
            return "The portable Note identities are missing or damaged. Their exact bytes were preserved for recovery."
        case .identitiesRevisionConflict:
            return "The portable Note identities changed while Scholium was updating them. Reload the workspace before trying again."
        case .invalidIdentityCandidate(let id):
            return "The selected note identity is no longer a valid candidate: \(id.uuidString)"
        case .identityPathAlreadyAssigned(let path):
            return "Another note identity is already assigned to \(path)."
        case .identityRebindingNotFound(let id):
            return "The pending note-identity migration no longer exists: \(id.uuidString)."
        }
    }
}
