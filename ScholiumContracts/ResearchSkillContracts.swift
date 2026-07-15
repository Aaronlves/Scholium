import Foundation

public enum ResearchSkillOrigin: String, Codable, Hashable, Sendable {
    case bundled
    case triptych

    public var displayName: String {
        switch self {
        case .bundled: "Bundled"
        case .triptych: "Triptych"
        }
    }
}

public struct ResearchSkillPackage: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let source: String
    public let origin: ResearchSkillOrigin
    public let skillClass: ResearchSkillClass
    public let role: String
    public let version: String
    public let updatePolicy: String
    public let supportedModes: [ResearchSkillMode]
    public let automaticModes: [ResearchSkillMode]
    public let compatiblePracticeIDs: [String]
    public let requiredSkillIDs: [String]
    public let practiceResources: [String: String]
    public let validationIssues: [String]
    public let revision: DocumentFingerprint?

    public var isValid: Bool { validationIssues.isEmpty }
    public var isTriptychLocal: Bool { origin != .bundled }
    public var selectionID: String { "\(origin.rawValue):\(id)" }
    public var canDuplicate: Bool {
        origin == .bundled
            && (updatePolicy == "release-managed-duplicable"
                || updatePolicy == "copy-on-adoption-researcher-owned")
    }

    public init(
        id: String,
        name: String,
        description: String,
        source: String,
        origin: ResearchSkillOrigin,
        skillClass: ResearchSkillClass = .researcher,
        role: String = "specialist",
        version: String = "local",
        updatePolicy: String = "researcher-owned",
        supportedModes: [ResearchSkillMode] = [.all],
        automaticModes: [ResearchSkillMode] = [],
        compatiblePracticeIDs: [String] = [],
        requiredSkillIDs: [String] = [],
        practiceResources: [String: String] = [:],
        validationIssues: [String] = [],
        revision: DocumentFingerprint? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.source = source
        self.origin = origin
        self.skillClass = skillClass
        self.role = role
        self.version = version
        self.updatePolicy = updatePolicy
        self.supportedModes = Self.unique(supportedModes)
        self.automaticModes = Self.unique(automaticModes)
        self.compatiblePracticeIDs = Self.unique(compatiblePracticeIDs)
        self.requiredSkillIDs = Self.unique(requiredSkillIDs)
        self.practiceResources = practiceResources
        self.validationIssues = validationIssues
        self.revision = revision
    }

    public func supports(_ mode: ResearchSkillMode) -> Bool {
        supportedModes.contains(.all) || supportedModes.contains(mode)
    }

    public func addingValidationIssues(_ issues: [String]) -> Self {
        guard !issues.isEmpty else { return self }
        return Self(
            id: id,
            name: name,
            description: description,
            source: source,
            origin: origin,
            skillClass: skillClass,
            role: role,
            version: version,
            updatePolicy: updatePolicy,
            supportedModes: supportedModes,
            automaticModes: automaticModes,
            compatiblePracticeIDs: compatiblePracticeIDs,
            requiredSkillIDs: requiredSkillIDs,
            practiceResources: practiceResources,
            validationIssues: validationIssues + issues,
            revision: revision
        )
    }

    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        return values.filter { seen.insert($0).inserted }
    }
}

public enum ResearchSkillError: LocalizedError, Sendable {
    case invalidIdentifier(String)
    case unsafeSkillsRoot
    case unsafePackage(String)
    case protectedPackageShadow(String)
    case packageNotFound(String)
    case packageAlreadyExists(String)
    case bundledPackageIsNotDuplicable(String)
    case stalePackage(String)
    case invalidPackage(String, [String])

    public var errorDescription: String? {
        switch self {
        case .invalidIdentifier(let id):
            "Skill identifiers must use 1–64 lowercase letters, numbers, or hyphens: \(id)"
        case .unsafeSkillsRoot:
            "The Triptych Skills folder is a symbolic link or is outside the portable control directory."
        case .unsafePackage(let id):
            "The skill package is not a safe regular package: \(id)"
        case .protectedPackageShadow(let id):
            "A Triptych-local package cannot shadow the protected Scholium Skill \(id)."
        case .packageNotFound(let id):
            "The Triptych skill no longer exists: \(id)"
        case .packageAlreadyExists(let id):
            "A Triptych skill already uses the identifier \(id)."
        case .bundledPackageIsNotDuplicable(let id):
            "Protected Scholium System Skill \(id) cannot be duplicated into the Triptych."
        case .stalePackage(let id):
            "The skill changed on disk. Reload it before saving, renaming, or deleting: \(id)"
        case .invalidPackage(let id, let issues):
            "Skill \(id) cannot be assembled. \(issues.joined(separator: " "))"
        }
    }
}
