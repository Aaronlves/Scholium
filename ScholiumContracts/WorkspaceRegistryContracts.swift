import Foundation

public enum VaultRole: String, Codable, CaseIterable, Sendable {
    case sourceCorpus = "source_corpus"
    case topicKnowledge = "topic_knowledge"
    case draftProject = "draft_project"
    case other

    /// Concise command aliases for the three researcher-facing vault roles.
    public static let sources = Self.sourceCorpus
    public static let knowledge = Self.topicKnowledge
    public static let project = Self.draftProject

    public var displayName: String {
        switch self {
        case .sourceCorpus: "Analyses"
        case .topicKnowledge: "Topics"
        case .draftProject: "Works"
        case .other: "Other"
        }
    }

    public var allowsCritique: Bool {
        self == .draftProject
    }

    public init?(commandLineValue: String) {
        switch commandLineValue.lowercased() {
        case "source_corpus", "sources", "analyses": self = .sourceCorpus
        case "topic_knowledge", "knowledge", "topics": self = .topicKnowledge
        case "draft_project", "project", "works": self = .draftProject
        case "other": self = .other
        default: return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let role = Self(rawValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown Scholium vault role: \(value)"
            )
        }
        self = role
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct RegisteredVault: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var role: VaultRole
    public let canonicalPath: String
    public let registeredAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        role: VaultRole,
        canonicalPath: String,
        registeredAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.canonicalPath = canonicalPath
        self.registeredAt = registeredAt
    }
}

/// One of the three peer roots in every Scholium Triptych.
public enum WorkspaceVaultSlot: String, Codable, CaseIterable, Identifiable, Sendable {
    case paperAnalysis = "paper_analysis"
    case topicKnowledge = "topic_knowledge"
    case output

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .paperAnalysis: "Analyses"
        case .topicKnowledge: "Topics"
        case .output: "Works"
        }
    }

    public var vaultRole: VaultRole {
        switch self {
        case .paperAnalysis: .sourceCorpus
        case .topicKnowledge: .topicKnowledge
        case .output: .draftProject
        }
    }
}

/// Stable machine-local registration for one complete Scholium Triptych.
///
/// The three vault UUIDs refer to `VaultIdentityRegistry`; paths and bookmarks
/// are deliberately not duplicated here.
public struct ScholiumTriptych: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var paperAnalysisVaultID: UUID
    public var topicKnowledgeVaultID: UUID
    public var outputVaultID: UUID
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String = "Triptych",
        paperAnalysisVaultID: UUID,
        topicKnowledgeVaultID: UUID,
        outputVaultID: UUID,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = Self.normalizedName(name)
        self.paperAnalysisVaultID = paperAnalysisVaultID
        self.topicKnowledgeVaultID = topicKnowledgeVaultID
        self.outputVaultID = outputVaultID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func vaultID(for slot: WorkspaceVaultSlot) -> UUID {
        switch slot {
        case .paperAnalysis: paperAnalysisVaultID
        case .topicKnowledge: topicKnowledgeVaultID
        case .output: outputVaultID
        }
    }

    private static func normalizedName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Triptych" : trimmed
    }
}

public struct TriptychAssignment: Hashable, Identifiable, Sendable {
    public let triptych: ScholiumTriptych
    public let vaults: [WorkspaceVaultSlot: RegisteredVault]
    public let hasCommonParent: Bool

    public var id: UUID { triptych.id }
    public var workspace: ScholiumTriptych { triptych }

    public init(
        triptych: ScholiumTriptych,
        vaults: [WorkspaceVaultSlot: RegisteredVault],
        hasCommonParent: Bool
    ) {
        self.triptych = triptych
        self.vaults = vaults
        self.hasCommonParent = hasCommonParent
    }

    public func vault(for slot: WorkspaceVaultSlot) -> RegisteredVault? {
        vaults[slot]
    }
}

/// The health of the machine-local Triptych registry. A non-healthy registry
/// never authorizes an empty workspace or a replacement registry by itself.
public enum WorkspaceRegistryHealth: Equatable, Sendable {
    case healthy
    case malformedCurrentSchema(String)
    case unsupportedNewerSchema(Int)
    case ioFailure(String)

    public var isHealthy: Bool {
        self == .healthy
    }

    /// Only a registry that cannot be decoded as the current or an older
    /// schema may be preserved and replaced through explicit relinking.
    public var canRelinkAfterPreserving: Bool {
        if case .malformedCurrentSchema = self { return true }
        return false
    }

    public var summary: String {
        switch self {
        case .healthy:
            "The Triptych registry is available."
        case .malformedCurrentSchema:
            "The Triptych registry is damaged and needs to be preserved before relinking."
        case .unsupportedNewerSchema:
            "The Triptych registry was created by a newer version of Scholium."
        case .ioFailure:
            "Scholium could not read the Triptych registry."
        }
    }

    public var details: String {
        switch self {
        case .healthy:
            "The registry file is readable and uses the supported schema."
        case .malformedCurrentSchema(let reason):
            "The registry could not be decoded as the supported schema. \(reason)"
        case .unsupportedNewerSchema(let version):
            "The registry uses schema \(version), but this Scholium version supports an earlier schema."
        case .ioFailure(let reason):
            "The registry could not be read. \(reason)"
        }
    }
}

public enum WorkspaceRegistryError: LocalizedError, Sendable {
    case notDirectory(String)
    case duplicateName(String)
    case vaultNotFound(String)
    case ambiguousSelector(String)
    case triptychNotFound(UUID)
    case triptychSelectorNotFound(String)
    case ambiguousTriptychSelector(String)
    case triptychIdentityConflict(UUID)
    case registryRecoveryRequired(WorkspaceRegistryHealth)
    case triptychControlDirectoryInUse(String)
    case overlappingVaults(String, String)
    case vaultIdentityMismatch(UUID, String, String)
    case incompleteWorkspace
    case vaultAccessUnavailable(String)
    case portableControlAccessUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .notDirectory(let path): return "Vault path is not a directory: \(path)"
        case .duplicateName(let name): return "A different registered vault already uses the name '\(name)'."
        case .vaultNotFound(let selector): return "No registered vault matches '\(selector)'."
        case .ambiguousSelector(let selector): return "More than one registered vault matches '\(selector)'. Use its UUID."
        case .triptychNotFound(let id): return "No registered Triptych matches '\(id.uuidString)'."
        case .triptychSelectorNotFound(let selector):
            return "No registered Triptych matches '\(selector)'."
        case .ambiguousTriptychSelector(let selector):
            return "More than one registered Triptych is named '\(selector)'. Use its UUID."
        case .triptychIdentityConflict(let id):
            return "Another registered Triptych already uses identity '\(id.uuidString)'."
        case .registryRecoveryRequired(let health):
            return health.summary
        case .triptychControlDirectoryInUse(let path):
            return "Another registered Triptych already uses the portable control folder at '\(path)'. Choose a Works folder under a different parent."
        case .overlappingVaults(let first, let second):
            return "Vault folders in one Triptych must be independent. '\(first)' overlaps '\(second)'."
        case .vaultIdentityMismatch(let id, let existing, let selected):
            return "Vault identity \(id.uuidString) already belongs to '\(existing)', not '\(selected)'."
        case .incompleteWorkspace:
            return "The Triptych is incomplete. Choose Analyses, Topics, and Works again."
        case .vaultAccessUnavailable(let path):
            return "Scholium no longer has access to '\(path)'. Open Manage Triptychs and choose that folder again."
        case .portableControlAccessUnavailable(let path):
            return "Scholium needs access to '\(path)' because the portable .scholium folder sits beside Works. Open Manage Triptychs and authorize that folder again."
        }
    }
}
