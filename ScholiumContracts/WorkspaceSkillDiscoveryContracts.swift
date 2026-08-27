import Foundation

public enum WorkspaceSkillSourceOwnership: String, Codable, Hashable, Sendable {
    case scholiumManaged = "scholium_managed"
    case researcherOwned = "researcher_owned"
}

/// One exact Skill directory that an authorized setup Agent may expose through
/// its current host's project-level discovery directory. This value grants no
/// read, write, Run, or research authority by itself.
public struct WorkspaceSkillSource: Codable, Hashable, Sendable {
    public let name: String
    public let sourceDirectory: String
    public let ownership: WorkspaceSkillSourceOwnership
    public let actionID: ResearchActionID?

    public init(
        name: String,
        sourceDirectory: String,
        ownership: WorkspaceSkillSourceOwnership,
        actionID: ResearchActionID? = nil
    ) throws {
        guard Self.isSafeSkillName(name) else {
            throw WorkspaceSkillDiscoveryContractError.invalidSkillName(name)
        }
        guard (sourceDirectory as NSString).isAbsolutePath,
              !sourceDirectory.contains("\n"),
              !sourceDirectory.contains("\r"),
              sourceDirectory.utf8.count <= 16_384 else {
            throw WorkspaceSkillDiscoveryContractError.invalidSourceDirectory(
                sourceDirectory
            )
        }
        switch ownership {
        case .scholiumManaged:
            guard actionID == nil else {
                throw WorkspaceSkillDiscoveryContractError.invalidOwnership
            }
        case .researcherOwned:
            guard actionID != nil else {
                throw WorkspaceSkillDiscoveryContractError.invalidOwnership
            }
        }
        self.name = name
        self.sourceDirectory = sourceDirectory
        self.ownership = ownership
        self.actionID = actionID
    }

    private enum CodingKeys: String, CodingKey {
        case name, ownership
        case sourceDirectory = "source_directory"
        case actionID = "action_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            name: container.decode(String.self, forKey: .name),
            sourceDirectory: container.decode(String.self, forKey: .sourceDirectory),
            ownership: container.decode(
                WorkspaceSkillSourceOwnership.self,
                forKey: .ownership
            ),
            actionID: container.decodeIfPresent(
                ResearchActionID.self,
                forKey: .actionID
            )
        )
    }

    private static func isSafeSkillName(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= 128,
              name.first != "-", name.last != "-" else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 0x61 && scalar.value <= 0x7A)
                || (scalar.value >= 0x30 && scalar.value <= 0x39)
                || scalar.value == 0x2D
        }
    }
}

public struct WorkspaceSkillSourceManifest: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2
    public static let maximumSkillCount = 64

    public let schemaVersion: Int
    public let triptychID: UUID
    public let triptychName: String
    public let workspaceRoot: String
    public let skills: [WorkspaceSkillSource]

    public init(
        triptychID: UUID,
        triptychName: String,
        workspaceRoot: String,
        skills: [WorkspaceSkillSource]
    ) throws {
        let normalizedName = triptychName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedName.isEmpty, normalizedName.utf8.count <= 512 else {
            throw WorkspaceSkillDiscoveryContractError.invalidTriptychName
        }
        guard (workspaceRoot as NSString).isAbsolutePath,
              !workspaceRoot.contains("\n"),
              !workspaceRoot.contains("\r"),
              workspaceRoot.utf8.count <= 16_384 else {
            throw WorkspaceSkillDiscoveryContractError.invalidWorkspaceRoot(
                workspaceRoot
            )
        }
        guard !skills.isEmpty, skills.count <= Self.maximumSkillCount,
              Set(skills.map(\.name)).count == skills.count,
              Set(skills.map(\.sourceDirectory)).count == skills.count,
              Set(skills.compactMap(\.actionID)).count
                == skills.compactMap(\.actionID).count,
              Set(skills.filter({ $0.ownership == .scholiumManaged }).map(\.name))
                == Set(ResearchSystemSkillID.allCases.map(\.rawValue))
        else {
            throw WorkspaceSkillDiscoveryContractError.invalidManifest
        }
        schemaVersion = Self.currentSchemaVersion
        self.triptychID = triptychID
        self.triptychName = normalizedName
        self.workspaceRoot = workspaceRoot
        self.skills = skills.sorted {
            if $0.ownership != $1.ownership {
                return $0.ownership == .scholiumManaged
            }
            return $0.name < $1.name
        }
    }

    private enum CodingKeys: String, CodingKey {
        case skills
        case schemaVersion = "schema_version"
        case triptychID = "triptych_id"
        case triptychName = "triptych_name"
        case workspaceRoot = "workspace_root"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported workspace Skill source schema."
            )
        }
        try self.init(
            triptychID: container.decode(UUID.self, forKey: .triptychID),
            triptychName: container.decode(String.self, forKey: .triptychName),
            workspaceRoot: container.decode(String.self, forKey: .workspaceRoot),
            skills: container.decode([WorkspaceSkillSource].self, forKey: .skills)
        )
    }
}

public enum WorkspaceSkillDiscoveryContractError: LocalizedError, Hashable,
    Sendable
{
    case invalidSkillName(String)
    case invalidSourceDirectory(String)
    case invalidOwnership
    case invalidTriptychName
    case invalidWorkspaceRoot(String)
    case invalidManifest

    public var errorDescription: String? {
        switch self {
        case .invalidSkillName(let name):
            "The project Skill discovery name is invalid: \(name)"
        case .invalidSourceDirectory(let path):
            "The project Skill source directory is invalid: \(path)"
        case .invalidOwnership:
            "The project Skill source ownership is invalid."
        case .invalidTriptychName:
            "The project Skill source Triptych name is invalid."
        case .invalidWorkspaceRoot(let path):
            "The project Skill workspace root is invalid: \(path)"
        case .invalidManifest:
            "The project Skill source manifest is invalid."
        }
    }
}
