import Foundation

/// Stable identity for one code-owned Platform Action. Researcher-editable
/// presentation and academic fields live in the Profile; they cannot create a
/// second executable Action identity.
public struct ResearchActionID: RawRepresentable, Codable, Hashable, Sendable,
    CustomStringConvertible
{
    public let rawValue: String

    public init?(rawValue: String) {
        guard Self.supportedRawValues.contains(rawValue) else { return nil }
        self.rawValue = rawValue
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

    public var description: String { rawValue }
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

    private static let supportedRawValues: Set<String> = [
        "discuss", "analyze", "synthesize", "write", "critique",
        "check-fidelity",
    ]
}

/// Public execution semantics available to the closed Platform Actions.
/// These values never expose the protected Function used to execute them.
public enum ResearchActionExecutionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case discussion
    case analysis
    case synthesis
    case writing
    case critique
    case checkFidelity = "check_fidelity"

    public var allowedTargetRoles: Set<ResearchActionTargetRole> {
        switch self {
        case .discussion, .checkFidelity:
            Set(ResearchActionTargetRole.allCases)
        case .analysis:
            [.analysis]
        case .synthesis:
            [.topic]
        case .writing, .critique:
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

    /// Stable default order before role filtering.
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
/// Schema v4 is created only after the resolver has frozen the exact Target,
/// Skill, academic Profile, protected Platform inputs, academic inputs,
/// Result Contract, and concrete authority envelope. It
/// intentionally contains no internal Function ID.
public struct ResearchActionSnapshot: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 4

    public let schemaVersion: Int
    public let definition: ResearchActionDefinition
    public let target: ResearchActionNoteSnapshot
    public let method: ResearchMethodSnapshot
    public let resolvedProfile: ResearchActionResolvedProfileSnapshot
    public let platformInputs: ResearchActionPlatformInputs
    public let academicInputs: ResearchAcademicFieldValues
    public let resultContract: ResearchResultContract
    public let authority: ResearchAuthorityEnvelope

    public var actionID: ResearchActionID { definition.id }
    public var executionKind: ResearchActionExecutionKind { definition.executionKind }
    public var targetRole: ResearchActionTargetRole { target.role }

    public init(
        definition: ResearchActionDefinition,
        target: ResearchActionNoteSnapshot,
        method: ResearchMethodSnapshot,
        resolvedProfile: ResearchActionResolvedProfileSnapshot,
        platformInputs: ResearchActionPlatformInputs,
        academicInputs: ResearchAcademicFieldValues,
        resultContract: ResearchResultContract,
        authority: ResearchAuthorityEnvelope
    ) throws {
        try definition.validate(targetRole: target.role)
        guard let platform = PlatformActionCatalog.definition(for: definition.id) else {
            throw ResearchActionExecutionContractError.staleResolution
        }
        try platform.validate(profile: resolvedProfile.profile)
        let validatedPlatformInputs = try platformInputs.validated(
            for: platform,
            target: target
        )
        let validatedAcademicInputs = try ResearchAcademicFieldValues(
            rawValues: academicInputs.values,
            definitions: resolvedProfile.profile.academicInputFields
        )
        let validatedAuthority = try ResearchAuthorityEnvelope(
            readableNotes: authority.readableNotes,
            writableNotes: authority.writableNotes,
            writeOperations: authority.writeOperations,
            editableMetadataKeys: authority.editableMetadataKeys
        )
        let canWriteInitial = platform.operations.contains(.modifyInitialNote)
        guard resolvedProfile.profile.actionID == definition.id,
              resolvedProfile.profile.applicableRoles.contains(target.role),
              method.registration.actionID == definition.id,
              method.registration.isEnabled,
              method.primaryMarkdownRevision
                == DocumentFingerprint(content: method.primaryMarkdownSource),
              validatedAuthority.readableNotes.contains(target),
              validatedPlatformInputs.focalNotes.allSatisfy(
                validatedAuthority.readableNotes.contains
              ),
              validatedAuthority.writableNotes.allSatisfy({ $0 == target }),
              (validatedAuthority.writableNotes.isEmpty || canWriteInitial),
              resultContract.actionID == definition.id,
              resultContract.registrationKey == method.registration.key,
              resultContract.profileRevision == resolvedProfile.profileRevision else {
            throw ResearchActionExecutionContractError.staleResolution
        }
        schemaVersion = Self.currentSchemaVersion
        self.definition = definition
        self.target = target
        self.method = method
        self.resolvedProfile = resolvedProfile
        self.platformInputs = validatedPlatformInputs
        self.academicInputs = validatedAcademicInputs
        self.resultContract = resultContract
        self.authority = validatedAuthority
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case actionID = "action_id"
        case executionKind = "execution_kind"
        case target
        case method
        case resolvedProfile = "resolved_profile"
        case platformInputs = "platform_inputs"
        case academicInputs = "academic_inputs"
        case resultContract = "result_contract"
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
            method: container.decode(ResearchMethodSnapshot.self, forKey: .method),
            resolvedProfile: container.decode(
                ResearchActionResolvedProfileSnapshot.self,
                forKey: .resolvedProfile
            ),
            platformInputs: container.decode(
                ResearchActionPlatformInputs.self,
                forKey: .platformInputs
            ),
            academicInputs: container.decode(
                ResearchAcademicFieldValues.self,
                forKey: .academicInputs
            ),
            resultContract: container.decode(
                ResearchResultContract.self,
                forKey: .resultContract
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
        try container.encode(platformInputs, forKey: .platformInputs)
        try container.encode(academicInputs, forKey: .academicInputs)
        try container.encode(resultContract, forKey: .resultContract)
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
        default: nil
        }
    }
}
