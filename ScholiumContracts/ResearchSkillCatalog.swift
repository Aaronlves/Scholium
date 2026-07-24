import Foundation

/// A bounded mode in which an external agent may use Scholium guidance.
///
/// The value is a routing selector, not a philosophical method and not a
/// permission to edit a note. Mixed mode is represented by an explicit list
/// of isolated phases rather than by a union of every available skill.
public enum ResearchSkillMode: String, Codable, CaseIterable, Hashable, Sendable {
    case all
    case mixed
    case read
    case integrate
    case write
    case discuss
    case retrieve
    case analyze
    case zotero
    case explore
    case develop
    case review
    case synthesize
    case feedback
    case audit
    case manuscript

    public var displayName: String {
        switch self {
        case .all: "All-purpose"
        case .mixed: "Mixed"
        case .read: "Read"
        case .integrate: "Integrate"
        case .write: "Write"
        case .discuss: "Discuss"
        case .retrieve: "Retrieve"
        case .analyze: "Analyze"
        case .zotero: "Zotero"
        case .explore: "Explore"
        case .develop: "Develop"
        case .review: "Review"
        case .synthesize: "Synthesize"
        case .feedback: "Feedback"
        case .audit: "Audit"
        case .manuscript: "Manuscript"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if value == "dialogue" {
            self = .discuss
        } else if let mode = Self(rawValue: value) {
            self = mode
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown Research Skill mode: \(value)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum ResearchSkillClass: String, Codable, CaseIterable, Hashable, Sendable {
    case system
    case method
    case researcher
}

/// One release-managed or researcher-owned entry in the protected catalog.
public struct ResearchSkillCatalogEntry: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let skillClass: ResearchSkillClass
    public let role: String
    public let version: String
    /// Researcher-visible Actions for which this package is a complete method.
    ///
    /// Protected Function identifiers remain a compatibility detail; Action
    /// identity is the semantic routing boundary for bundled methods.
    public let supportedActions: [ResearchActionID]
    public let supportedFunctions: [ResearchFunctionID]
    public let capabilities: [ResearchSkillCapability]
    public let citationStyles: [String]
    public let citationStyleResources: [String: String]
    public let supportedModes: [ResearchSkillMode]
    /// Modes that select this System package without an explicit package ID.
    ///
    /// Compatibility and automatic activation are deliberately separate: an
    /// adapter may support every mode while remaining opt-in except for one
    /// app-owned route such as Discuss.
    public let automaticModes: [ResearchSkillMode]
    /// Researcher-owned Practice identifiers that may refine this Method Skill.
    ///
    /// These are routing hints, not dependencies, permissions, or endorsements.
    public let compatiblePracticeIDs: [String]
    public let requiredSkillIDs: [String]
    /// Stable Practice identifier to one bounded package-relative reference.
    ///
    /// This is routing metadata only. A listed Practice never activates
    /// automatically and cannot grant evidence, scope, or permission.
    public let practiceResources: [String: String]
    public let updatePolicy: String
    public let resourcePath: String

    public init(
        id: String,
        name: String,
        description: String,
        skillClass: ResearchSkillClass,
        role: String,
        version: String,
        supportedActions: [ResearchActionID] = [],
        supportedFunctions: [ResearchFunctionID] = [],
        capabilities: [ResearchSkillCapability] = [],
        citationStyles: [String] = [],
        citationStyleResources: [String: String] = [:],
        supportedModes: [ResearchSkillMode],
        automaticModes: [ResearchSkillMode] = [],
        compatiblePracticeIDs: [String] = [],
        requiredSkillIDs: [String] = [],
        practiceResources: [String: String] = [:],
        updatePolicy: String,
        resourcePath: String
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.skillClass = skillClass
        self.role = role
        self.version = version
        self.supportedActions = Self.unique(supportedActions)
        self.supportedFunctions = Self.unique(supportedFunctions)
        self.capabilities = Self.unique(capabilities)
        self.citationStyles = Self.unique(citationStyles.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.filter { !$0.isEmpty })
        var normalizedStyleResources: [String: String] = [:]
        for (key, value) in citationStyleResources {
            normalizedStyleResources[
                key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            ] = value
        }
        self.citationStyleResources = normalizedStyleResources
        self.supportedModes = Self.unique(supportedModes)
        self.automaticModes = Self.unique(automaticModes)
        self.compatiblePracticeIDs = Self.unique(compatiblePracticeIDs)
        self.requiredSkillIDs = Self.unique(requiredSkillIDs)
        self.practiceResources = practiceResources
        self.updatePolicy = updatePolicy
        self.resourcePath = resourcePath
    }

    public func supports(_ mode: ResearchSkillMode) -> Bool {
        supportedModes.contains(.all) || supportedModes.contains(mode)
    }

    public func supports(_ function: ResearchFunctionID) -> Bool {
        supportedFunctions.contains(function)
    }

    public func supports(_ actionID: ResearchActionID) -> Bool {
        supportedActions.contains(actionID)
    }

    public func provides(_ capability: ResearchSkillCapability) -> Bool {
        capabilities.contains(capability)
    }

    public func activatesAutomatically(in mode: ResearchSkillMode) -> Bool {
        automaticModes.contains(.all) || automaticModes.contains(mode)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case skillClass = "class"
        case role
        case version
        case supportedActions = "supported_actions"
        case supportedFunctions = "supported_functions"
        case capabilities
        case citationStyles = "citation_styles"
        case citationStyleResources = "citation_style_resources"
        case supportedModes = "supported_modes"
        case automaticModes = "automatic_modes"
        case compatiblePracticeIDs = "compatible_practices"
        case requiredSkillIDs = "required_skills"
        case practiceResources = "practice_resources"
        case updatePolicy = "update_policy"
        case resourcePath = "path"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            description: try container.decode(String.self, forKey: .description),
            skillClass: try container.decode(ResearchSkillClass.self, forKey: .skillClass),
            role: try container.decode(String.self, forKey: .role),
            version: try container.decode(String.self, forKey: .version),
            supportedActions: try container.decodeIfPresent(
                [ResearchActionID].self,
                forKey: .supportedActions
            ) ?? [],
            supportedFunctions: try container.decodeIfPresent(
                [ResearchFunctionID].self,
                forKey: .supportedFunctions
            ) ?? [],
            capabilities: try container.decodeIfPresent(
                [ResearchSkillCapability].self,
                forKey: .capabilities
            ) ?? [],
            citationStyles: try container.decodeIfPresent(
                [String].self,
                forKey: .citationStyles
            ) ?? [],
            citationStyleResources: try container.decodeIfPresent(
                [String: String].self,
                forKey: .citationStyleResources
            ) ?? [:],
            supportedModes: try container.decode([ResearchSkillMode].self, forKey: .supportedModes),
            automaticModes: try container.decodeIfPresent(
                [ResearchSkillMode].self,
                forKey: .automaticModes
            ) ?? [],
            compatiblePracticeIDs: try container.decodeIfPresent(
                [String].self,
                forKey: .compatiblePracticeIDs
            ) ?? [],
            requiredSkillIDs: try container.decodeIfPresent(
                [String].self,
                forKey: .requiredSkillIDs
            ) ?? [],
            practiceResources: try container.decodeIfPresent(
                [String: String].self,
                forKey: .practiceResources
            ) ?? [:],
            updatePolicy: try container.decode(String.self, forKey: .updatePolicy),
            resourcePath: try container.decode(String.self, forKey: .resourcePath)
        )
    }

    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        return values.filter { seen.insert($0).inserted }
    }
}

public struct ResearchSkillAssemblyPhase: Hashable, Sendable {
    public let mode: ResearchSkillMode
    public let skillIDs: [String]

    public init(mode: ResearchSkillMode, skillIDs: [String] = []) {
        self.mode = mode
        self.skillIDs = skillIDs
    }
}

public enum ResearchSkillCatalogError: LocalizedError, Sendable {
    case resourceMissing(String)
    case malformedCatalog(String)
    case unknownSkill(String)
    case unsupportedMode(skillID: String, mode: ResearchSkillMode)
    case missingDependency(skillID: String, dependencyID: String)
    case mixedModeRequiresPhases
    case invalidResourcePath(String)

    public var errorDescription: String? {
        switch self {
        case .resourceMissing(let path):
            "The protected Scholium Skill resource is missing: \(path)"
        case .malformedCatalog(let reason):
            "The protected Scholium Skill catalog is invalid. \(reason)"
        case .unknownSkill(let id):
            "The requested Scholium Skill is not in the protected catalog: \(id)"
        case .unsupportedMode(let id, let mode):
            "Skill \(id) does not support the \(mode.rawValue) mode."
        case .missingDependency(let id, let dependency):
            "Skill \(id) requires a catalog entry that is missing: \(dependency)"
        case .mixedModeRequiresPhases:
            "Mixed mode requires an explicit, nonempty list of isolated phases."
        case .invalidResourcePath(let path):
            "The requested Skill resource path is not allowed: \(path)"
        }
    }
}

/// The release-managed catalog. It deliberately has no API for scanning an
/// arbitrary directory or importing global agent configuration.
public struct ResearchSkillCatalog: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 4

    public let schemaVersion: Int
    public let status: String
    public let entries: [ResearchSkillCatalogEntry]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        status: String = "active",
        entries: [ResearchSkillCatalogEntry]
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ResearchSkillCatalogError.malformedCatalog(
                "Unsupported schema version \(schemaVersion)."
            )
        }
        guard !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ResearchSkillCatalogError.malformedCatalog(
                "The catalog status cannot be empty."
            )
        }
        var seen: Set<String> = []
        for entry in entries {
            guard seen.insert(entry.id).inserted else {
                throw ResearchSkillCatalogError.malformedCatalog(
                    "Duplicate Skill identifier (entry.id)."
                )
            }
            guard Self.isValidIdentifier(entry.id) else {
                throw ResearchSkillCatalogError.malformedCatalog(
                    "Skill identifiers must use 1–64 lowercase letters, numbers, or hyphens: \(entry.id)."
                )
            }
            guard !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !entry.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !entry.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !entry.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !entry.updatePolicy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ResearchSkillCatalogError.malformedCatalog(
                    "Skill \(entry.id) is missing required routing metadata."
                )
            }
            guard !entry.supportedModes.isEmpty else {
                throw ResearchSkillCatalogError.malformedCatalog(
                    "Skill \(entry.id) must declare at least one supported mode."
                )
            }
            guard entry.skillClass != .method || entry.supportedFunctions.count == 1 else {
                throw ResearchSkillCatalogError.malformedCatalog(
                    "Method Skill \(entry.id) must declare one protected execution function."
                )
            }
            guard entry.skillClass != .method || entry.supportedActions.count == 1 else {
                throw ResearchSkillCatalogError.malformedCatalog(
                    "Method Skill \(entry.id) must declare exactly one researcher-visible Action."
                )
            }
            guard entry.citationStyles.allSatisfy({ style in
                style.range(
                    of: #"^[a-z0-9](?:[a-z0-9.-]{0,62}[a-z0-9])?$"#,
                    options: .regularExpression
                ) != nil
            }) else {
                throw ResearchSkillCatalogError.malformedCatalog(
                    "Skill \(entry.id) contains an invalid citation style identifier."
                )
            }
            guard Set(entry.citationStyleResources.keys).isSubset(
                of: Set(entry.citationStyles)
            ) else {
                throw ResearchSkillCatalogError.malformedCatalog(
                    "Skill \(entry.id) maps a resource for an undeclared citation style."
                )
            }
            for (style, path) in entry.citationStyleResources {
                guard ResearchSkillResourcePath.isAllowed(path),
                      path.hasPrefix("references/") else {
                    throw ResearchSkillCatalogError.malformedCatalog(
                        "\(entry.id).citation_style_resources contains an invalid reference path for \(style): \(path)."
                    )
                }
            }
            guard entry.automaticModes.allSatisfy({ entry.supports($0) }) else {
                throw ResearchSkillCatalogError.malformedCatalog(
                    "Skill \(entry.id) automatically activates in an unsupported mode."
                )
            }
            guard entry.skillClass == .system || entry.automaticModes.isEmpty else {
                throw ResearchSkillCatalogError.malformedCatalog(
                    "Only System Skills may declare automatic modes: \(entry.id)."
                )
            }
            guard entry.practiceResources.isEmpty || entry.role == "practice" else {
                throw ResearchSkillCatalogError.malformedCatalog(
                    "Only Practice packages may declare practice_resources: \(entry.id)."
                )
            }
            for (practiceID, path) in entry.practiceResources {
                guard Self.isValidIdentifier(practiceID) else {
                    throw ResearchSkillCatalogError.malformedCatalog(
                        "Practice identifiers must use lowercase letters, numbers, or hyphens: \(practiceID)."
                    )
                }
                guard ResearchSkillResourcePath.isAllowed(path),
                      path.hasPrefix("references/") else {
                    throw ResearchSkillCatalogError.malformedCatalog(
                        "\(entry.id).practice_resources contains an invalid reference path: \(path)."
                    )
                }
            }
            guard Self.isValidResourcePath(
                entry.resourcePath,
                skillID: entry.id,
                skillClass: entry.skillClass
            ) else {
                throw ResearchSkillCatalogError.malformedCatalog(
                    "Skill \(entry.id) has an invalid ownership resource path: \(entry.resourcePath)."
                )
            }
        }
        let ids = Set(entries.map(\.id))
        for entry in entries {
            for dependency in entry.requiredSkillIDs where !ids.contains(dependency) {
                throw ResearchSkillCatalogError.missingDependency(
                    skillID: entry.id,
                    dependencyID: dependency
                )
            }
        }
        self.schemaVersion = schemaVersion
        self.status = status
        self.entries = entries
    }

    public func entry(id: String) throws -> ResearchSkillCatalogEntry {
        guard let entry = entries.first(where: { $0.id == id }) else {
            throw ResearchSkillCatalogError.unknownSkill(id)
        }
        return entry
    }

    public func entries(supporting mode: ResearchSkillMode) -> [ResearchSkillCatalogEntry] {
        entries.filter { $0.supports(mode) }
    }

    public func entries(supporting function: ResearchFunctionID) -> [ResearchSkillCatalogEntry] {
        entries.filter { $0.supports(function) }
    }

    /// Returns a stable, dependency-closed list for one ordinary mode.
    ///
    /// Automatic System packages are always selected. Method, Researcher,
    /// and optional adapter packages remain opt-in by ID. This keeps ordinary
    /// assembly bounded while allowing a requested adapter to participate in
    /// any mode it explicitly supports.
    public func dependencyClosedIDs(
        for mode: ResearchSkillMode,
        requestedSkillIDs: [String] = []
    ) throws -> [String] {
        guard mode != .mixed else { throw ResearchSkillCatalogError.mixedModeRequiresPhases }
        let automaticSystemIDs = entries.filter {
            $0.skillClass == .system && $0.activatesAutomatically(in: mode)
        }.map(\.id)
        let seeds = Self.unique(automaticSystemIDs + requestedSkillIDs)
        var included: Set<String> = []
        var visiting: Set<String> = []

        func visit(_ id: String) throws {
            guard let entry = entries.first(where: { $0.id == id }) else {
                throw ResearchSkillCatalogError.unknownSkill(id)
            }
            guard entry.supports(mode) else {
                throw ResearchSkillCatalogError.unsupportedMode(skillID: id, mode: mode)
            }
            guard !included.contains(id) else { return }
            guard visiting.insert(id).inserted else {
                throw ResearchSkillCatalogError.malformedCatalog(
                    "Dependency cycle includes \(id)."
                )
            }
            for dependency in entry.requiredSkillIDs {
                try visit(dependency)
            }
            visiting.remove(id)
            included.insert(id)
        }

        for seed in seeds { try visit(seed) }
        return entries.filter { included.contains($0.id) }.map(\.id)
    }

    /// Resolves each Mixed-mode phase independently. The returned arrays are
    /// intentionally not flattened: a later phase cannot inherit a previous
    /// phase's workflow, researcher package, or permission state.
    public func mixedDependencyClosedIDs(
        _ phases: [ResearchSkillAssemblyPhase]
    ) throws -> [[String]] {
        guard !phases.isEmpty else { throw ResearchSkillCatalogError.mixedModeRequiresPhases }
        return try phases.map { phase in
            try dependencyClosedIDs(for: phase.mode, requestedSkillIDs: phase.skillIDs)
        }
    }

    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        return values.filter { seen.insert($0).inserted }
    }

    private static func isValidIdentifier(_ id: String) -> Bool {
        id.range(
            of: #"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isValidResourcePath(
        _ path: String,
        skillID: String,
        skillClass: ResearchSkillClass
    ) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard components.count == 2,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              components[1] == skillID else {
            return false
        }
        let expectedRoot: String = switch skillClass {
        case .system: "Scholium System Skills"
        case .method: "Scholium Method Skills"
        case .researcher: "Researcher Skills"
        }
        return components[0] == expectedRoot
    }

}

public enum ResearchSkillResourcePath {
    public static func isAllowed(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              components.count <= 2 else {
            return false
        }
        if components.count == 1 { return components[0] == "SKILL.md" }
        return ["references", "templates", "evals"].contains(components[0])
    }
}
