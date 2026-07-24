import Foundation

/// One Triptych-local relationship between an installed Researcher Skill and
/// the declarative Action Profile that presents it. The package identifier is
/// not authority: Core reopens and validates the package before every save,
/// and the later Action resolver still intersects the Profile with protected
/// Application policy.
public struct ResearchActionProfileBinding: Codable, Hashable, Sendable {
    public let packageID: String
    public let profile: ResearchActionProfile

    public init(packageID: String, profile: ResearchActionProfile) throws {
        guard Self.isValidPackageIdentifier(packageID) else {
            throw ResearchActionProfileStorageError.invalidPackageID(packageID)
        }
        self.packageID = packageID
        self.profile = profile
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case packageID = "package_id"
        case profile
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(
            keyedBy: ResearchActionProfileStorageAnyCodingKey.self
        )
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        if let unknown = raw.allKeys.map(\.stringValue)
            .first(where: { !allowed.contains($0) }) {
            throw ResearchActionProfileStorageError.unsupportedField(unknown)
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            packageID: container.decode(String.self, forKey: .packageID),
            profile: container.decode(ResearchActionProfile.self, forKey: .profile)
        )
    }

    private static func isValidPackageIdentifier(_ value: String) -> Bool {
        value.range(
            of: #"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$"#,
            options: .regularExpression
        ) != nil
    }
}

/// Portable Profile bindings for one Triptych. One file keeps Action order,
/// Skill ownership, and Profile replacement revision-checked as a unit while
/// allowing independent copies in other Triptychs.
public struct ResearchActionProfileDocument: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumBindingCount = 256

    public let schemaVersion: Int
    public let actionBindings: [String: ResearchActionProfileBinding]

    public init(
        actionBindings: [ResearchActionID: ResearchActionProfileBinding] = [:]
    ) throws {
        schemaVersion = Self.currentSchemaVersion
        self.actionBindings = Dictionary(uniqueKeysWithValues: actionBindings.map {
            ($0.key.rawValue, $0.value)
        })
        try Self.validate(self.actionBindings)
    }

    public func binding(
        for actionID: ResearchActionID
    ) -> ResearchActionProfileBinding? {
        actionBindings[actionID.rawValue]
    }

    public func replacing(
        _ binding: ResearchActionProfileBinding,
        for actionID: ResearchActionID
    ) throws -> Self {
        var replacement = actionBindings
        replacement[actionID.rawValue] = binding
        return try Self(validatingRawBindings: replacement)
    }

    public func removing(_ actionID: ResearchActionID) throws -> Self {
        var replacement = actionBindings
        replacement.removeValue(forKey: actionID.rawValue)
        return try Self(validatingRawBindings: replacement)
    }

    public var orderedBindings: [ResearchActionProfileBinding] {
        actionBindings.values.sorted {
            if $0.profile.order != $1.profile.order {
                return $0.profile.order < $1.profile.order
            }
            return $0.profile.actionID.rawValue < $1.profile.actionID.rawValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case actionBindings = "action_bindings"
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(
            keyedBy: ResearchActionProfileStorageAnyCodingKey.self
        )
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        if let unknown = raw.allKeys.map(\.stringValue)
            .first(where: { !allowed.contains($0) }) {
            throw ResearchActionProfileStorageError.unsupportedField(unknown)
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ResearchActionProfileStorageError.unsupportedSchemaVersion(
                schemaVersion
            )
        }
        try self.init(validatingRawBindings: container.decode(
            [String: ResearchActionProfileBinding].self,
            forKey: .actionBindings
        ))
    }

    private init(
        validatingRawBindings actionBindings: [String: ResearchActionProfileBinding]
    ) throws {
        try Self.validate(actionBindings)
        schemaVersion = Self.currentSchemaVersion
        self.actionBindings = actionBindings
    }

    private static func validate(
        _ bindings: [String: ResearchActionProfileBinding]
    ) throws {
        guard bindings.count <= maximumBindingCount else {
            throw ResearchActionProfileStorageError.tooManyBindings(bindings.count)
        }
        for (rawActionID, binding) in bindings {
            guard let actionID = ResearchActionID(rawValue: rawActionID) else {
                throw ResearchActionProfileStorageError.invalidActionID(rawActionID)
            }
            guard binding.profile.actionID == actionID else {
                throw ResearchActionProfileStorageError.actionIdentityMismatch(
                    key: actionID,
                    profile: binding.profile.actionID
                )
            }
            guard actionID == .manuscript || !actionID.isReservedForBundledAction else {
                throw ResearchActionProfileStorageError.bundledActionCannotBeCustomized(
                    actionID
                )
            }
        }
    }
}

public struct ResearchActionProfileSnapshot: Hashable, Sendable {
    public let document: ResearchActionProfileDocument
    public let revision: DocumentFingerprint

    public init(
        document: ResearchActionProfileDocument,
        revision: DocumentFingerprint
    ) {
        self.document = document
        self.revision = revision
    }
}

public enum ResearchActionProfileStorageError: LocalizedError, Hashable, Sendable {
    case unsupportedSchemaVersion(Int)
    case unsupportedField(String)
    case invalidActionID(String)
    case invalidPackageID(String)
    case actionIdentityMismatch(key: ResearchActionID, profile: ResearchActionID)
    case bundledActionCannotBeCustomized(ResearchActionID)
    case tooManyBindings(Int)
    case staleDocument
    case unsafeDocument
    case invalidPackage(String, [String])
    case packageDoesNotSupportAction(packageID: String, actionID: ResearchActionID)
    case packageInUse(String)
    case invalidDocument(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Unsupported Research Action Profile document schema version \(version)."
        case .unsupportedField(let field):
            "Unsupported Research Action Profile storage field: \(field)."
        case .invalidActionID(let value):
            "Invalid Research Action Profile Action identifier: \(value)."
        case .invalidPackageID(let value):
            "Invalid Research Action Profile package identifier: \(value)."
        case .actionIdentityMismatch(let key, let profile):
            "Action Profile key \(key.rawValue) does not match Profile \(profile.rawValue)."
        case .bundledActionCannotBeCustomized(let actionID):
            "The bundled Action \(actionID.rawValue) cannot be replaced by a custom Profile."
        case .tooManyBindings(let count):
            "The Research Action Profile document contains \(count) bindings; at most \(ResearchActionProfileDocument.maximumBindingCount) are allowed."
        case .staleDocument:
            "The Research Action Profile configuration changed on disk. Reload it before saving."
        case .unsafeDocument:
            "The Research Action Profile configuration could not be read or replaced safely."
        case .invalidPackage(let packageID, let issues):
            "Skill \(packageID) cannot own an Action Profile. \(issues.joined(separator: " "))"
        case .packageDoesNotSupportAction(let packageID, let actionID):
            "Skill \(packageID) does not declare Action \(actionID.rawValue)."
        case .packageInUse(let packageID):
            "Skill \(packageID) is still used by an Action Profile or Working Method. Remove that binding before deleting the Skill."
        case .invalidDocument(let reason):
            "The Research Action Profile configuration is invalid. \(reason)"
        }
    }
}

private struct ResearchActionProfileStorageAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}
