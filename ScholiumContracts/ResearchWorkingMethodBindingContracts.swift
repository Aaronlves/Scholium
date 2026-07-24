import Foundation

/// The explicit ownership state of one Action's active Method.
///
/// Absence is never equivalent to a bundled default. A missing binding is an
/// unavailable Action that must be repaired explicitly.
public enum ResearchWorkingMethodBindingState: String, Codable, Hashable, Sendable {
    case installedDefault = "installed_default"
    case researcherSkill = "researcher_skill"
    case disabled
}

/// One Action-keyed Method selection in the portable binding-v2 document.
public struct ResearchWorkingMethodBinding: Codable, Hashable, Sendable {
    public let state: ResearchWorkingMethodBindingState
    public let packageID: String?

    public init(
        state: ResearchWorkingMethodBindingState,
        packageID: String? = nil
    ) throws {
        switch state {
        case .installedDefault, .researcherSkill:
            guard let packageID,
                  Self.isValidPackageIdentifier(packageID) else {
                throw ResearchWorkingMethodBindingContractError.activePackageRequired(state)
            }
            self.packageID = packageID
        case .disabled:
            guard packageID == nil else {
                throw ResearchWorkingMethodBindingContractError.disabledPackageForbidden
            }
            self.packageID = nil
        }
        self.state = state
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case packageID = "package_id"
    }

    public init(from decoder: Decoder) throws {
        let rawContainer = try decoder.container(
            keyedBy: ResearchWorkingMethodAnyCodingKey.self
        )
        let allowed = Set(["state", "package_id"])
        if let unknown = rawContainer.allKeys.map(\.stringValue)
            .first(where: { !allowed.contains($0) }) {
            throw ResearchWorkingMethodBindingContractError.unsupportedField(unknown)
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            state: container.decode(ResearchWorkingMethodBindingState.self, forKey: .state),
            packageID: container.decodeIfPresent(String.self, forKey: .packageID)
        )
    }

    private static func isValidPackageIdentifier(_ value: String) -> Bool {
        value.range(
            of: #"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$"#,
            options: .regularExpression
        ) != nil
    }
}

/// Portable Action-keyed Method bindings. Schema version 2 intentionally
/// lives beside, rather than migrates, the retained Function-era v1 file.
public struct ResearchWorkingMethodBindingDocument: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let actionBindings: [String: ResearchWorkingMethodBinding]

    public init(
        actionBindings: [ResearchActionID: ResearchWorkingMethodBinding]
    ) throws {
        schemaVersion = Self.currentSchemaVersion
        self.actionBindings = Dictionary(uniqueKeysWithValues: actionBindings.map {
            ($0.key.rawValue, $0.value)
        })
        try Self.validateActionIDs(self.actionBindings.keys)
    }

    public func binding(
        for actionID: ResearchActionID
    ) -> ResearchWorkingMethodBinding? {
        actionBindings[actionID.rawValue]
    }

    public func replacing(
        _ binding: ResearchWorkingMethodBinding,
        for actionID: ResearchActionID
    ) throws -> Self {
        var replacement = actionBindings
        replacement[actionID.rawValue] = binding
        return try Self(validatingRawBindings: replacement)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case actionBindings = "action_bindings"
    }

    public init(from decoder: Decoder) throws {
        let rawContainer = try decoder.container(
            keyedBy: ResearchWorkingMethodAnyCodingKey.self
        )
        let allowed = Set(["schema_version", "action_bindings"])
        if let unknown = rawContainer.allKeys.map(\.stringValue)
            .first(where: { !allowed.contains($0) }) {
            throw ResearchWorkingMethodBindingContractError.unsupportedField(unknown)
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ResearchWorkingMethodBindingContractError.unsupportedSchemaVersion(
                schemaVersion
            )
        }
        let bindings = try container.decode(
            [String: ResearchWorkingMethodBinding].self,
            forKey: .actionBindings
        )
        try self.init(validatingRawBindings: bindings)
    }

    private init(
        validatingRawBindings actionBindings: [String: ResearchWorkingMethodBinding]
    ) throws {
        try Self.validateActionIDs(actionBindings.keys)
        schemaVersion = Self.currentSchemaVersion
        self.actionBindings = actionBindings
    }

    private static func validateActionIDs<S: Sequence>(_ values: S) throws
    where S.Element == String {
        for rawValue in values where ResearchActionID(rawValue: rawValue) == nil {
            throw ResearchWorkingMethodBindingContractError.invalidActionID(rawValue)
        }
    }
}

public enum ResearchWorkingMethodBindingContractError: LocalizedError, Hashable, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidActionID(String)
    case activePackageRequired(ResearchWorkingMethodBindingState)
    case disabledPackageForbidden
    case unsupportedField(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Unsupported Working Method binding schema version \(version)."
        case .invalidActionID(let value):
            "Invalid Working Method Action identifier: \(value)."
        case .activePackageRequired(let state):
            "Working Method state \(state.rawValue) requires one valid package identifier."
        case .disabledPackageForbidden:
            "A disabled Working Method cannot retain an active package identifier."
        case .unsupportedField(let field):
            "Unsupported Working Method binding field: \(field)."
        }
    }
}

private struct ResearchWorkingMethodAnyCodingKey: CodingKey {
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

public struct ResearchWorkingMethodBindingSnapshot: Hashable, Sendable {
    public let document: ResearchWorkingMethodBindingDocument
    public let revision: DocumentFingerprint

    public init(
        document: ResearchWorkingMethodBindingDocument,
        revision: DocumentFingerprint
    ) {
        self.document = document
        self.revision = revision
    }
}

public enum ResearchWorkingMethodExpectedPackageState: Hashable, Sendable {
    case missing
    case present(DocumentFingerprint)
}

public struct ResearchWorkingMethodRestoreOutcome: Hashable, Sendable {
    public let actionID: ResearchActionID
    public let package: ResearchSkillPackage
    public let binding: ResearchWorkingMethodBindingSnapshot

    public init(
        actionID: ResearchActionID,
        package: ResearchSkillPackage,
        binding: ResearchWorkingMethodBindingSnapshot
    ) {
        self.actionID = actionID
        self.package = package
        self.binding = binding
    }
}
