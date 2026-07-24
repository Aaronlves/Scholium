import Foundation

/// One regular UTF-8 file that Scholium read into a staged Researcher Skill.
/// The source bytes remain Core-private; presentation receives only bounded
/// inventory and revision evidence.
public struct ResearchSkillInstallationFile: Codable, Hashable, Identifiable, Sendable {
    public let relativePath: String
    public let utf8ByteCount: Int
    public let revision: DocumentFingerprint

    public var id: String { relativePath }

    public init(
        relativePath: String,
        utf8ByteCount: Int,
        revision: DocumentFingerprint
    ) {
        self.relativePath = relativePath
        self.utf8ByteCount = utf8ByteCount
        self.revision = revision
    }
}

/// The only first-version placement for an imported Researcher Skill.
/// Installation does not create or activate an Action Profile.
public enum ResearchSkillInstallationActionPlacement: String, Codable, Hashable,
    Sendable
{
    case researcherSkills = "researcher_skills"
}

/// A Skill may describe a method and requested semantic capabilities, but it
/// cannot grant itself note authority. The staged boundary therefore makes the
/// absence of an approved Action Profile explicit rather than inventing
/// permissions from package prose.
public enum ResearchSkillInstallationPermissionState: String, Codable, Hashable,
    Sendable
{
    case actionProfileRequired = "action_profile_required"
}

/// An inspectable, nonexecuting view of one exact local-directory package.
/// Core retains the corresponding source bytes only until installation,
/// explicit discard, or expiry and rejects a forged or changed preparation.
public struct ResearchSkillInstallationPreparation: Codable, Hashable, Identifiable,
    Sendable
{
    public static let maximumFileCount = 128
    public static let maximumFileUTF8ByteCount = 1_048_576
    public static let maximumPackageUTF8ByteCount = 8_388_608

    public let id: UUID
    public let packageID: String
    public let packageRevision: DocumentFingerprint
    public let originDisplayName: String
    public let files: [ResearchSkillInstallationFile]
    public let purpose: String
    public let packageRole: String
    public let applicableRoles: [ResearchActionTargetRole]
    public let declaredCapabilities: [ResearchSkillCapability]
    public let proposedActionIDs: [ResearchActionID]
    public let actionPlacement: ResearchSkillInstallationActionPlacement
    public let permissionState: ResearchSkillInstallationPermissionState
    public let installsDisabled: Bool
    public let preparedAt: Date
    public let expiresAt: Date

    public init(
        id: UUID,
        packageID: String,
        packageRevision: DocumentFingerprint,
        originDisplayName: String,
        files: [ResearchSkillInstallationFile],
        purpose: String,
        packageRole: String,
        applicableRoles: [ResearchActionTargetRole],
        declaredCapabilities: [ResearchSkillCapability],
        proposedActionIDs: [ResearchActionID],
        preparedAt: Date,
        expiresAt: Date
    ) {
        self.id = id
        self.packageID = packageID
        self.packageRevision = packageRevision
        self.originDisplayName = originDisplayName
        self.files = files.sorted { $0.relativePath < $1.relativePath }
        self.purpose = purpose
        self.packageRole = packageRole
        self.applicableRoles = Self.canonicalRoles(applicableRoles)
        self.declaredCapabilities = Self.unique(declaredCapabilities)
        self.proposedActionIDs = Self.unique(proposedActionIDs)
        actionPlacement = .researcherSkills
        permissionState = .actionProfileRequired
        installsDisabled = true
        self.preparedAt = preparedAt
        self.expiresAt = expiresAt
    }

    private static func canonicalRoles(
        _ roles: [ResearchActionTargetRole]
    ) -> [ResearchActionTargetRole] {
        let selected = Set(roles)
        return ResearchActionTargetRole.allCases.filter(selected.contains)
    }

    private static func unique<Value: Hashable>(_ values: [Value]) -> [Value] {
        var seen: Set<Value> = []
        return values.filter { seen.insert($0).inserted }
    }
}

/// One independent Triptych-local package created by a successful request.
public struct ResearchSkillInstallationResult: Codable, Hashable, Identifiable,
    Sendable
{
    public let triptychID: UUID
    public let packageID: String
    public let packageRevision: DocumentFingerprint
    public let isEnabled: Bool

    public var id: UUID { triptychID }

    public init(
        triptychID: UUID,
        packageID: String,
        packageRevision: DocumentFingerprint,
        isEnabled: Bool = false
    ) {
        self.triptychID = triptychID
        self.packageID = packageID
        self.packageRevision = packageRevision
        self.isEnabled = isEnabled
    }
}

public struct ResearchSkillInstallationOutcome: Codable, Hashable, Sendable {
    public let preparationID: UUID
    public let packageID: String
    public let packageRevision: DocumentFingerprint
    public let installations: [ResearchSkillInstallationResult]
    public let installedAt: Date

    public init(
        preparationID: UUID,
        packageID: String,
        packageRevision: DocumentFingerprint,
        installations: [ResearchSkillInstallationResult],
        installedAt: Date = Date()
    ) {
        self.preparationID = preparationID
        self.packageID = packageID
        self.packageRevision = packageRevision
        self.installations = installations
        self.installedAt = installedAt
    }
}

public enum ResearchSkillInstallationError: LocalizedError, Hashable, Sendable {
    case sourceMustBeLocalDirectory
    case invalidPackageID(String)
    case protectedPackageCollision(String)
    case unsafeSource(String)
    case unsupportedResource(String)
    case executableResource(String)
    case scriptResource(String)
    case invalidUTF8(String)
    case tooManyFiles(Int)
    case fileTooLarge(String)
    case packageTooLarge
    case malformedMetadata([String])
    case preparationNotFound(UUID)
    case preparationMismatch(UUID)
    case preparationExpired(UUID)
    case noTriptychsSelected
    case duplicateTriptych(UUID)
    case destinationBindingConflict(String)
    case destinationBindingStateUnverified
    case destinationRecoveryRequired([UUID])

    public var errorDescription: String? {
        return switch self {
        case .sourceMustBeLocalDirectory:
            "Choose one local Researcher Skill directory. Archives and network locations are not supported."
        case .invalidPackageID(let id):
            "The Researcher Skill directory name is not a valid package identifier: \(id)"
        case .protectedPackageCollision(let id):
            "A Researcher Skill cannot use the protected Scholium package identifier: \(id)"
        case .unsafeSource(let path):
            "The Researcher Skill source could not be read through the safe directory boundary: \(path)"
        case .unsupportedResource(let path):
            "The Researcher Skill contains an unsupported resource: \(path)"
        case .executableResource(let path):
            "Researcher Skill files cannot be executable: \(path)"
        case .scriptResource(let path):
            "Researcher Skill packages cannot install scripts: \(path)"
        case .invalidUTF8(let path):
            "Researcher Skill files must contain valid UTF-8 text: \(path)"
        case .tooManyFiles(let count):
            "The Researcher Skill contains \(count) files; at most \(ResearchSkillInstallationPreparation.maximumFileCount) are allowed."
        case .fileTooLarge(let path):
            "The Researcher Skill file exceeds the 1 MiB limit: \(path)"
        case .packageTooLarge:
            "The Researcher Skill exceeds the 8 MiB package limit."
        case .malformedMetadata(let issues):
            "The Researcher Skill metadata is not structurally valid. \(issues.joined(separator: " "))"
        case .preparationNotFound(let id):
            "Researcher Skill installation preparation not found: \(id.uuidString)"
        case .preparationMismatch(let id):
            "Researcher Skill installation preparation does not match the staged package: \(id.uuidString)"
        case .preparationExpired(let id):
            "Researcher Skill installation preparation expired: \(id.uuidString)"
        case .noTriptychsSelected:
            "Select at least one Triptych for Researcher Skill installation."
        case .duplicateTriptych(let id):
            "A Researcher Skill installation request repeats Triptych \(id.uuidString)."
        case .destinationBindingConflict(let id):
            "Researcher Skill \(id) is still named by an active Triptych binding. Repair or disable that binding before installing the package."
        case .destinationBindingStateUnverified:
            "Scholium could not prove that the Triptych has no active binding for this Researcher Skill. Repair Research Guidance before installing it."
        case .destinationRecoveryRequired(let ids):
            "Researcher Skill installation could not prove rollback for Triptych: \(ids.map(\.uuidString).joined(separator: ", "))"
        }
    }
}
