import Foundation

/// Stable identity for a researcher-visible Action.
///
/// Bundled and researcher-created Actions share one bounded identifier form.
/// Interface labels remain separate, researcher-editable presentation data.
/// Parsing a raw value does not establish ownership; creation flows for a
/// researcher-owned Action must use `init(researcherOwnedRawValue:)` so a
/// bundled identity cannot be replaced accidentally.
public struct ResearchActionID: RawRepresentable, Codable, Hashable, Sendable,
    CustomStringConvertible
{
    public let rawValue: String

    public init?(rawValue: String) {
        let bytes = Array(rawValue.utf8)
        guard (1...64).contains(bytes.count),
              bytes.first != 45,
              bytes.last != 45,
              !rawValue.contains("--"),
              !Self.protectedFunctionOnlyIDs.contains(rawValue),
              bytes.allSatisfy(Self.isIdentifierByte) else {
            return nil
        }
        self.rawValue = rawValue
    }

    public init?(researcherOwnedRawValue rawValue: String) {
        guard let identifier = Self(rawValue: rawValue),
              !identifier.isReservedForBundledAction else {
            return nil
        }
        self = identifier
    }

    private init(uncheckedRawValue: String) {
        rawValue = uncheckedRawValue
    }

    public static let discuss = Self(uncheckedRawValue: "discuss")
    public static let analyze = Self(uncheckedRawValue: "analyze")
    public static let synthesize = Self(uncheckedRawValue: "synthesize")
    public static let write = Self(uncheckedRawValue: "write")
    public static let critique = Self(uncheckedRawValue: "critique")
    public static let checkFidelity = Self(uncheckedRawValue: "check-fidelity")
    public static let manuscript = Self(uncheckedRawValue: "manuscript")

    public var description: String { rawValue }
    public var isReservedForBundledAction: Bool { reservedExecutionKind != nil }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let identifier = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid Research Action identifier: \(rawValue)"
            )
        }
        self = identifier
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static let protectedFunctionOnlyIDs: Set<String> = [
        "develop",
        "fidelity",
        "revise",
    ]

    private static func isIdentifierByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 45, 48...57, 97...122:
            true
        default:
            false
        }
    }
}

/// Public execution semantics available to bundled and custom Actions.
/// These values never expose the protected Function used to execute them.
public enum ResearchActionExecutionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case discussion
    case analysis
    case synthesis
    case writing
    case critique
    case checkFidelity = "check_fidelity"
    case manuscript

    public var allowedTargetRoles: Set<ResearchActionTargetRole> {
        switch self {
        case .discussion, .checkFidelity:
            Set(ResearchActionTargetRole.allCases)
        case .analysis:
            [.analysis]
        case .synthesis:
            [.topic]
        case .writing, .critique, .manuscript:
            [.work]
        }
    }
}

/// Researcher-visible role vocabulary for the Action boundary.
public enum ResearchActionTargetRole: String, Codable, CaseIterable, Hashable, Sendable {
    case analysis
    case topic
    case work
}

/// Identity plus the public execution semantics of one Action.
/// Role applicability is derived from the execution kind and may be narrowed
/// later by an Action Profile, but never widened beyond this definition.
public struct ResearchActionDefinition: Codable, Hashable, Identifiable, Sendable {
    public let id: ResearchActionID
    public let executionKind: ResearchActionExecutionKind

    public var allowedTargetRoles: Set<ResearchActionTargetRole> {
        executionKind.allowedTargetRoles
    }

    /// Creates a researcher-owned definition without permitting it to
    /// impersonate one of Scholium's bundled Actions.
    public init(
        researcherOwnedID id: ResearchActionID,
        executionKind: ResearchActionExecutionKind
    ) throws {
        guard !id.isReservedForBundledAction else {
            throw ResearchActionContractError.bundledActionIDReserved(id)
        }
        try self.init(validatingID: id, executionKind: executionKind)
    }

    init(
        validatingID id: ResearchActionID,
        executionKind: ResearchActionExecutionKind
    ) throws {
        if let expected = id.reservedExecutionKind, expected != executionKind {
            throw ResearchActionContractError.reservedExecutionKindMismatch(
                actionID: id,
                expected: expected,
                actual: executionKind
            )
        }
        self.id = id
        self.executionKind = executionKind
    }

    private init(
        defaultID: ResearchActionID,
        executionKind: ResearchActionExecutionKind
    ) {
        id = defaultID
        self.executionKind = executionKind
    }

    public func validate(targetRole: ResearchActionTargetRole) throws {
        guard allowedTargetRoles.contains(targetRole) else {
            throw ResearchActionContractError.invalidTargetRole(
                actionID: id,
                executionKind: executionKind,
                role: targetRole
            )
        }
    }

    public static let discuss = Self(defaultID: .discuss, executionKind: .discussion)
    public static let analyze = Self(defaultID: .analyze, executionKind: .analysis)
    public static let synthesize = Self(defaultID: .synthesize, executionKind: .synthesis)
    public static let write = Self(defaultID: .write, executionKind: .writing)
    public static let critique = Self(defaultID: .critique, executionKind: .critique)
    public static let checkFidelity = Self(
        defaultID: .checkFidelity,
        executionKind: .checkFidelity
    )
    public static let manuscript = Self(defaultID: .manuscript, executionKind: .manuscript)

    /// Stable default order before role filtering. Manuscript remains a
    /// bundled optional definition and is not part of the default surface.
    public static let defaultDefinitions: [Self] = [
        .discuss,
        .analyze,
        .synthesize,
        .write,
        .critique,
        .checkFidelity,
    ]

    public static func defaultDefinitions(
        for role: ResearchActionTargetRole
    ) -> [Self] {
        defaultDefinitions.filter { $0.allowedTargetRoles.contains(role) }
    }

    private enum CodingKeys: String, CodingKey {
        case id = "action_id"
        case executionKind = "execution_kind"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            validatingID: container.decode(ResearchActionID.self, forKey: .id),
            executionKind: container.decode(
                ResearchActionExecutionKind.self,
                forKey: .executionKind
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(executionKind, forKey: .executionKind)
    }
}

/// Versioned public identity and authority recorded for one Action run.
///
/// Schema v2 is created only after the resolver has frozen the exact Target,
/// Method, Profile, parameter values, and concrete authority envelope. It
/// intentionally contains no internal Function ID.
public struct ResearchActionSnapshot: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let definition: ResearchActionDefinition
    public let target: ResearchActionNoteSnapshot
    public let method: ResearchActionMethodSnapshot
    public let resolvedProfile: ResearchActionResolvedProfileSnapshot
    public let parameters: ResearchActionParameterModel
    public let authority: ResearchAuthorityEnvelope

    public var actionID: ResearchActionID { definition.id }
    public var executionKind: ResearchActionExecutionKind { definition.executionKind }
    public var targetRole: ResearchActionTargetRole { target.role }

    public init(
        definition: ResearchActionDefinition,
        target: ResearchActionNoteSnapshot,
        method: ResearchActionMethodSnapshot,
        resolvedProfile: ResearchActionResolvedProfileSnapshot,
        parameters: ResearchActionParameterModel,
        authority: ResearchAuthorityEnvelope
    ) throws {
        try definition.validate(targetRole: target.role)
        let validatedParameters = try ResearchActionParameterModel(
            profile: resolvedProfile.profile,
            rawValues: parameters.values
        )
        let validatedAuthority = try ResearchAuthorityEnvelope(
            readableNotes: authority.readableNotes,
            writableNotes: authority.writableNotes,
            writeOperations: authority.writeOperations,
            editablePropertyKeys: authority.editablePropertyKeys
        )
        let capabilities = resolvedProfile.profile.capabilities
        let readableRoles = Set(capabilities.readableRoles)
        let writableRoles = Set(capabilities.candidateWritableRoles)
        let candidateOperations = Set(capabilities.candidateWriteOperations)
        let candidatePropertyKeys = Set(capabilities.editablePropertyKeys)
        let selectedNotes = validatedParameters.values.values.flatMap { value in
            if case .notes(let notes) = value { return notes }
            return []
        }
        let anchorsMatchTarget = validatedParameters.values.values.allSatisfy { value in
            if case .passage(let anchor) = value {
                return anchor.fingerprint == target.fingerprint
            }
            return true
        }
        let resourcePaths = method.loadedResources.map(\.relativePath)
        guard resolvedProfile.profile.definition == definition,
              resolvedProfile.profile.applicableRoles.contains(target.role),
              method.packageID.isEmpty == false,
              method.loadedResources.isEmpty == false,
              Set(resourcePaths).count == resourcePaths.count,
              resourcePaths.allSatisfy({ path in
                  !path.isEmpty
                      && !path.hasPrefix("/")
                      && !path.split(separator: "/", omittingEmptySubsequences: false)
                          .contains(where: { $0 == "." || $0 == ".." || $0.isEmpty })
              }),
              validatedAuthority.readableNotes.contains(target),
              validatedAuthority.readableNotes.allSatisfy({
                  readableRoles.contains($0.role)
              }),
              validatedAuthority.writableNotes.allSatisfy({
                  writableRoles.contains($0.role)
              }),
              Set(validatedAuthority.writeOperations).isSubset(of: candidateOperations),
              Set(validatedAuthority.editablePropertyKeys).isSubset(
                  of: candidatePropertyKeys
              ),
              selectedNotes.allSatisfy(validatedAuthority.readableNotes.contains),
              anchorsMatchTarget else {
            throw ResearchActionExecutionContractError.staleResolution
        }
        schemaVersion = Self.currentSchemaVersion
        self.definition = definition
        self.target = target
        self.method = method
        self.resolvedProfile = resolvedProfile
        self.parameters = validatedParameters
        self.authority = validatedAuthority
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case actionID = "action_id"
        case executionKind = "execution_kind"
        case target
        case method
        case resolvedProfile = "resolved_profile"
        case parameters
        case authority
    }

    public init(from decoder: Decoder) throws {
        try ResearchActionExecutionValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ResearchActionContractError.unsupportedSchemaVersion(schemaVersion)
        }
        let definition = try ResearchActionDefinition(
            validatingID: container.decode(ResearchActionID.self, forKey: .actionID),
            executionKind: container.decode(
                ResearchActionExecutionKind.self,
                forKey: .executionKind
            )
        )
        try self.init(
            definition: definition,
            target: container.decode(ResearchActionNoteSnapshot.self, forKey: .target),
            method: container.decode(ResearchActionMethodSnapshot.self, forKey: .method),
            resolvedProfile: container.decode(
                ResearchActionResolvedProfileSnapshot.self,
                forKey: .resolvedProfile
            ),
            parameters: container.decode(
                ResearchActionParameterModel.self,
                forKey: .parameters
            ),
            authority: container.decode(ResearchAuthorityEnvelope.self, forKey: .authority)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(actionID, forKey: .actionID)
        try container.encode(executionKind, forKey: .executionKind)
        try container.encode(target, forKey: .target)
        try container.encode(method, forKey: .method)
        try container.encode(resolvedProfile, forKey: .resolvedProfile)
        try container.encode(parameters, forKey: .parameters)
        try container.encode(authority, forKey: .authority)
    }
}

/// The complete Action projection permitted in a portable Research Record.
///
/// A record identifies what the researcher invoked without persisting the
/// protected Function selected by the Application or duplicating execution
/// policy. The portable store adopts this value during its later cutover;
/// legacy Function-era records remain outside this contract.
public struct ResearchActionRecordIdentity: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let actionID: ResearchActionID

    public init(actionID: ResearchActionID) {
        schemaVersion = Self.currentSchemaVersion
        self.actionID = actionID
    }

    public init(snapshot: ResearchActionSnapshot) {
        self.init(actionID: snapshot.actionID)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case actionID = "action_id"
    }

    public init(from decoder: Decoder) throws {
        try ResearchActionExecutionValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ResearchActionContractError.unsupportedRecordIdentitySchemaVersion(
                schemaVersion
            )
        }
        self.schemaVersion = schemaVersion
        actionID = try container.decode(ResearchActionID.self, forKey: .actionID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(actionID, forKey: .actionID)
    }
}

public enum ResearchActionContractError: LocalizedError, Hashable, Sendable {
    case bundledActionIDReserved(ResearchActionID)
    case reservedExecutionKindMismatch(
        actionID: ResearchActionID,
        expected: ResearchActionExecutionKind,
        actual: ResearchActionExecutionKind
    )
    case invalidTargetRole(
        actionID: ResearchActionID,
        executionKind: ResearchActionExecutionKind,
        role: ResearchActionTargetRole
    )
    case unsupportedSchemaVersion(Int)
    case unsupportedRecordIdentitySchemaVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .bundledActionIDReserved(let actionID):
            "The Action identifier \(actionID.rawValue) is reserved for a bundled Action."
        case .reservedExecutionKindMismatch(let actionID, let expected, let actual):
            "The reserved Action \(actionID.rawValue) requires \(expected.rawValue), not \(actual.rawValue)."
        case .invalidTargetRole(let actionID, _, let role):
            "The Action \(actionID.rawValue) is not available for a \(role.rawValue) Target."
        case .unsupportedSchemaVersion(let version):
            "Unsupported Research Action snapshot schema version \(version)."
        case .unsupportedRecordIdentitySchemaVersion(let version):
            "Unsupported Research Action record identity schema version \(version)."
        }
    }
}

private extension ResearchActionID {
    var reservedExecutionKind: ResearchActionExecutionKind? {
        switch rawValue {
        case Self.discuss.rawValue: .discussion
        case Self.analyze.rawValue: .analysis
        case Self.synthesize.rawValue: .synthesis
        case Self.write.rawValue: .writing
        case Self.critique.rawValue: .critique
        case Self.checkFidelity.rawValue: .checkFidelity
        case Self.manuscript.rawValue: .manuscript
        default: nil
        }
    }
}
