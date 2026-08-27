import Foundation

/// Stable identity for one code-owned Platform Action. Researcher-editable
/// presentation and academic fields live in the Profile; they cannot create a
/// second executable Action identity.
public enum ResearchActionID: String, Codable, CaseIterable, Hashable, Sendable,
    CustomStringConvertible
{
    case discuss
    case analyze
    case synthesize
    case write
    case critique
    case checkFidelity = "check-fidelity"

    public var definition: ResearchActionDefinition {
        switch self {
        case .discuss: .discuss
        case .analyze: .analyze
        case .synthesize: .synthesize
        case .write: .write
        case .critique: .critique
        case .checkFidelity: .checkFidelity
        }
    }

    public var allowedTargetRoles: Set<ResearchActionTargetRole> {
        switch self {
        case .discuss, .checkFidelity:
            Set(ResearchActionTargetRole.allCases)
        case .analyze:
            [.analysis]
        case .synthesize:
            [.topic]
        case .write, .critique:
            [.work]
        }
    }

    public var requiresAgentChangeEvidence: Bool {
        switch self {
        case .analyze, .synthesize, .write: true
        case .discuss, .critique, .checkFidelity: false
        }
    }

    public var writesTarget: Bool { requiresAgentChangeEvidence }

    /// Stable project-discovery name for the one registered Method Skill that
    /// supplies this Action's intellectual procedure. It identifies a Skill
    /// source; it grants no Run or mutation authority.
    public var projectSkillName: String {
        switch self {
        case .discuss: "scholium-discuss"
        case .analyze: "scholium-analyze"
        case .synthesize: "scholium-synthesize"
        case .write: "scholium-write"
        case .critique: "scholium-critique"
        case .checkFidelity: "scholium-content-fidelity"
        }
    }

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

}

/// Researcher-visible role vocabulary for the Action boundary.
public enum ResearchActionTargetRole: String, Codable, CaseIterable, Hashable, Sendable {
    case analysis
    case topic
    case work

    public init?(vaultRole: VaultRole) {
        switch vaultRole {
        case .sourceCorpus: self = .analysis
        case .topicKnowledge: self = .topic
        case .draftProject: self = .work
        case .other: return nil
        }
    }

    public var vaultRoles: Set<VaultRole> {
        switch self {
        case .analysis: [.sourceCorpus]
        case .topic: [.topicKnowledge]
        case .work: [.draftProject]
        }
    }
}

/// The closed public definition of one Action. It wraps the direct Action ID
/// for presentation and profile APIs without adding another semantic identity.
public struct ResearchActionDefinition: Codable, Hashable, Identifiable, Sendable {
    public let id: ResearchActionID

    public var allowedTargetRoles: Set<ResearchActionTargetRole> {
        id.allowedTargetRoles
    }

    private init(id: ResearchActionID) {
        self.id = id
    }

    public func validate(targetRole: ResearchActionTargetRole) throws {
        guard allowedTargetRoles.contains(targetRole) else {
            throw ResearchActionContractError.invalidTargetRole(
                actionID: id,
                role: targetRole
            )
        }
    }

    public static let discuss = Self(id: .discuss)
    public static let analyze = Self(id: .analyze)
    public static let synthesize = Self(id: .synthesize)
    public static let write = Self(id: .write)
    public static let critique = Self(id: .critique)
    public static let checkFidelity = Self(id: .checkFidelity)

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
    }

    public init(from decoder: Decoder) throws {
        try ResearchActionExecutionValidation.rejectUnknownFields(
            in: decoder,
            allowed: [CodingKeys.id.stringValue]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decode(ResearchActionID.self, forKey: .id))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
    }
}

/// Versioned public identity and authority recorded for one Action run.
///
/// Schema v5 is created only after the resolver has frozen the exact Target,
/// Skill, academic Profile, protected Platform inputs, academic inputs,
/// Result Contract, and concrete authority envelope. It
/// contains no second internal operation identity.
public struct ResearchActionSnapshot: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 5

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
        let definition = try container.decode(
            ResearchActionID.self,
            forKey: .actionID
        ).definition
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
/// resolved Action Run selected by the Application or duplicating execution
/// policy. The portable store adopts this value during its later cutover;
/// legacy pre-Action records remain outside this contract.
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
    case invalidTargetRole(
        actionID: ResearchActionID,
        role: ResearchActionTargetRole
    )
    case unsupportedSchemaVersion(Int)
    case unsupportedRecordIdentitySchemaVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidTargetRole(let actionID, let role):
            "The Action \(actionID.rawValue) is not available for a \(role.rawValue) Target."
        case .unsupportedSchemaVersion(let version):
            "Unsupported Research Action snapshot schema version \(version)."
        case .unsupportedRecordIdentitySchemaVersion(let version):
            "Unsupported Research Action record identity schema version \(version)."
        }
    }
}
