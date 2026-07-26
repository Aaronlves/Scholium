import Foundation

/// Machine-local policy deciding whether a validated, short-lived grant may
/// be issued without another researcher decision.
public enum ResearchPermissionPolicy: String, Codable, CaseIterable, Hashable, Sendable {
    case askEveryTime = "ask_every_time"
    case askOnlyForWorks = "ask_only_for_works"
    case triptychWide = "triptych_wide"
}

/// One Action/Profile role inside the complete current envelope of a Skill.
public struct ResearchPermissionProfileRevision: Codable, Hashable, Sendable {
    public let actionID: ResearchActionID
    public let targetRole: ResearchActionTargetRole
    public let profileRevision: DocumentFingerprint

    public init(
        actionID: ResearchActionID,
        targetRole: ResearchActionTargetRole,
        profileRevision: DocumentFingerprint
    ) throws {
        guard Self.isValid(profileRevision) else {
            throw ResearchPermissionContractError.invalidFingerprint
        }
        self.actionID = actionID
        self.targetRole = targetRole
        self.profileRevision = profileRevision
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case actionID = "action_id"
        case targetRole = "target_role"
        case profileRevision = "profile_revision"
    }

    public init(from decoder: Decoder) throws {
        try ResearchPermissionValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            actionID: container.decode(ResearchActionID.self, forKey: .actionID),
            targetRole: container.decode(
                ResearchActionTargetRole.self,
                forKey: .targetRole
            ),
            profileRevision: container.decode(
                DocumentFingerprint.self,
                forKey: .profileRevision
            )
        )
    }

    fileprivate static func isValid(_ fingerprint: DocumentFingerprint) -> Bool {
        fingerprint.byteCount >= 0
            && fingerprint.sha256.range(
                of: #"^[0-9a-f]{64}$"#,
                options: .regularExpression
            ) != nil
    }
}

/// Complete currently active Method/Profile envelope for one ordinary Skill.
///
/// The digest covers the package revision and every Action/Profile role. A
/// change anywhere in that envelope invalidates one per-Skill override rather
/// than allowing a stale approval to fall through to a broader default.
public struct ResearchPermissionSubject: Hashable, Sendable, Identifiable {
    public static let maximumProfileCount = 256
    public static let maximumDisplayNameUTF8ByteCount = 256

    public let packageID: String
    public let displayName: String
    public let packageRevision: DocumentFingerprint
    public let profiles: [ResearchPermissionProfileRevision]
    public let envelopeDigest: DocumentFingerprint

    public var id: String { packageID }

    public init(
        packageID: String,
        displayName: String,
        packageRevision: DocumentFingerprint,
        profiles: [ResearchPermissionProfileRevision]
    ) throws {
        let canonicalProfiles = profiles.sorted { lhs, rhs in
            if lhs.actionID.rawValue != rhs.actionID.rawValue {
                return lhs.actionID.rawValue < rhs.actionID.rawValue
            }
            return lhs.targetRole.rawValue < rhs.targetRole.rawValue
        }
        let profileKeys = canonicalProfiles.map {
            "\($0.actionID.rawValue):\($0.targetRole.rawValue)"
        }
        guard ResearchPermissionValidation.isValidPackageID(packageID),
              !displayName.isEmpty,
              displayName.utf8.count <= Self.maximumDisplayNameUTF8ByteCount,
              !displayName.contains("\n"),
              !displayName.contains("\r"),
              ResearchPermissionProfileRevision.isValid(packageRevision),
              !canonicalProfiles.isEmpty,
              canonicalProfiles.count <= Self.maximumProfileCount,
              Set(profileKeys).count == profileKeys.count else {
            throw ResearchPermissionContractError.invalidSubject
        }
        let digestPayload = DigestPayload(
            packageID: packageID,
            packageRevision: packageRevision,
            profiles: canonicalProfiles
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.packageID = packageID
        self.displayName = displayName
        self.packageRevision = packageRevision
        self.profiles = canonicalProfiles
        envelopeDigest = DocumentFingerprint(data: try encoder.encode(digestPayload))
    }

    private struct DigestPayload: Codable {
        let packageID: String
        let packageRevision: DocumentFingerprint
        let profiles: [ResearchPermissionProfileRevision]

        private enum CodingKeys: String, CodingKey {
            case packageID = "package_id"
            case packageRevision = "package_revision"
            case profiles
        }
    }
}

/// One deliberate per-Skill override bound to its approved complete envelope.
public struct ResearchSkillPermissionOverride: Codable, Hashable, Sendable {
    public let packageID: String
    public let policy: ResearchPermissionPolicy
    public let approvedEnvelopeDigest: DocumentFingerprint

    public init(
        packageID: String,
        policy: ResearchPermissionPolicy,
        approvedEnvelopeDigest: DocumentFingerprint
    ) throws {
        guard ResearchPermissionValidation.isValidPackageID(packageID),
              ResearchPermissionProfileRevision.isValid(approvedEnvelopeDigest) else {
            throw ResearchPermissionContractError.invalidOverride
        }
        self.packageID = packageID
        self.policy = policy
        self.approvedEnvelopeDigest = approvedEnvelopeDigest
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case packageID = "package_id"
        case policy
        case approvedEnvelopeDigest = "approved_envelope_digest"
    }

    public init(from decoder: Decoder) throws {
        try ResearchPermissionValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            packageID: container.decode(String.self, forKey: .packageID),
            policy: container.decode(ResearchPermissionPolicy.self, forKey: .policy),
            approvedEnvelopeDigest: container.decode(
                DocumentFingerprint.self,
                forKey: .approvedEnvelopeDigest
            )
        )
    }
}

/// Versioned machine-local policy document for one Triptych.
public struct ResearchPermissionPolicyDocument: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumOverrideCount = 256

    public let schemaVersion: Int
    public let triptychDefault: ResearchPermissionPolicy
    public let skillOverrides: [ResearchSkillPermissionOverride]

    public init(
        triptychDefault: ResearchPermissionPolicy = .askEveryTime,
        skillOverrides: [ResearchSkillPermissionOverride] = []
    ) throws {
        let canonicalOverrides = skillOverrides.sorted {
            $0.packageID < $1.packageID
        }
        guard canonicalOverrides.count <= Self.maximumOverrideCount,
              Set(canonicalOverrides.map(\.packageID)).count
                == canonicalOverrides.count else {
            throw ResearchPermissionContractError.invalidDocument
        }
        schemaVersion = Self.currentSchemaVersion
        self.triptychDefault = triptychDefault
        self.skillOverrides = canonicalOverrides
    }

    public func override(for packageID: String) -> ResearchSkillPermissionOverride? {
        skillOverrides.first { $0.packageID == packageID }
    }

    public func replacingTriptychDefault(
        _ policy: ResearchPermissionPolicy
    ) throws -> Self {
        try Self(triptychDefault: policy, skillOverrides: skillOverrides)
    }

    public func replacingOverride(
        _ override: ResearchSkillPermissionOverride
    ) throws -> Self {
        try Self(
            triptychDefault: triptychDefault,
            skillOverrides: skillOverrides.filter {
                $0.packageID != override.packageID
            } + [override]
        )
    }

    public func removingOverride(for packageID: String) throws -> Self {
        try Self(
            triptychDefault: triptychDefault,
            skillOverrides: skillOverrides.filter { $0.packageID != packageID }
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case triptychDefault = "triptych_default"
        case skillOverrides = "skill_overrides"
    }

    public init(from decoder: Decoder) throws {
        try ResearchPermissionValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ResearchPermissionContractError.unsupportedSchemaVersion(
                schemaVersion
            )
        }
        try self.init(
            triptychDefault: container.decode(
                ResearchPermissionPolicy.self,
                forKey: .triptychDefault
            ),
            skillOverrides: container.decode(
                [ResearchSkillPermissionOverride].self,
                forKey: .skillOverrides
            )
        )
    }
}

public struct ResearchPermissionPolicySnapshot: Hashable, Sendable {
    public let document: ResearchPermissionPolicyDocument
    public let revision: DocumentFingerprint?

    public init(
        document: ResearchPermissionPolicyDocument,
        revision: DocumentFingerprint?
    ) {
        self.document = document
        self.revision = revision
    }
}

public enum ResearchPermissionOverrideStatus: String, Codable, Hashable, Sendable {
    case inherited
    case approved
    case invalidated
    case missingSkill = "missing_skill"
}

/// Settings projection for one active or retained per-Skill policy row.
public struct ResearchPermissionSkillStatus: Hashable, Sendable, Identifiable {
    public let packageID: String
    public let displayName: String
    public let subject: ResearchPermissionSubject?
    public let overridePolicy: ResearchPermissionPolicy?
    public let effectivePolicy: ResearchPermissionPolicy
    public let status: ResearchPermissionOverrideStatus

    public var id: String { packageID }

    public init(
        packageID: String,
        displayName: String,
        subject: ResearchPermissionSubject?,
        overridePolicy: ResearchPermissionPolicy?,
        effectivePolicy: ResearchPermissionPolicy,
        status: ResearchPermissionOverrideStatus
    ) {
        self.packageID = packageID
        self.displayName = displayName
        self.subject = subject
        self.overridePolicy = overridePolicy
        self.effectivePolicy = effectivePolicy
        self.status = status
    }
}

public struct ResearchPermissionSettingsSnapshot: Hashable, Sendable {
    public let policy: ResearchPermissionPolicySnapshot
    public let skills: [ResearchPermissionSkillStatus]

    public init(
        policy: ResearchPermissionPolicySnapshot,
        skills: [ResearchPermissionSkillStatus]
    ) {
        self.policy = policy
        self.skills = skills
    }
}

public enum ResearchPermissionRequestKind: String, Codable, Hashable, Sendable {
    case initialAction = "initial_action"
    case additionalNoteChanges = "additional_note_changes"
    case writeCapableChildPhase = "write_capable_child_phase"
}

/// Policy-only input. Application hard limits, identities, revisions, source,
/// Skill declaration, Profile envelope, and the concrete request remain
/// independent mandatory intersections before any grant can be issued.
public struct ResearchStandingPermissionRequest: Hashable, Sendable {
    public let kind: ResearchPermissionRequestKind
    public let packageID: String
    public let currentEnvelopeDigest: DocumentFingerprint
    public let requestedWritableRoles: Set<ResearchActionTargetRole>

    public init(
        kind: ResearchPermissionRequestKind,
        packageID: String,
        currentEnvelopeDigest: DocumentFingerprint,
        requestedWritableRoles: Set<ResearchActionTargetRole>
    ) throws {
        guard ResearchPermissionValidation.isValidPackageID(packageID),
              ResearchPermissionProfileRevision.isValid(currentEnvelopeDigest),
              kind == .initialAction || !requestedWritableRoles.isEmpty else {
            throw ResearchPermissionContractError.invalidRequest
        }
        self.kind = kind
        self.packageID = packageID
        self.currentEnvelopeDigest = currentEnvelopeDigest
        self.requestedWritableRoles = requestedWritableRoles
    }
}

public enum ResearchPermissionPolicySource: String, Codable, Hashable, Sendable {
    case explicitAction = "explicit_action"
    case triptychDefault = "triptych_default"
    case skillOverride = "skill_override"
    case invalidatedOverride = "invalidated_override"
}

public enum ResearchPermissionDisposition: String, Codable, Hashable, Sendable {
    case initialTargetAuthorized = "initial_target_authorized"
    case mayIssueBoundedGrant = "may_issue_bounded_grant"
    case requiresResearcherDecision = "requires_researcher_decision"
}

public struct ResearchPermissionEvaluation: Hashable, Sendable {
    public let effectivePolicy: ResearchPermissionPolicy
    public let source: ResearchPermissionPolicySource
    public let disposition: ResearchPermissionDisposition

    public init(
        effectivePolicy: ResearchPermissionPolicy,
        source: ResearchPermissionPolicySource,
        disposition: ResearchPermissionDisposition
    ) {
        self.effectivePolicy = effectivePolicy
        self.source = source
        self.disposition = disposition
    }
}

public enum ResearchPermissionPolicyResolver {
    public static func evaluate(
        document: ResearchPermissionPolicyDocument,
        request: ResearchStandingPermissionRequest
    ) -> ResearchPermissionEvaluation {
        if request.kind == .initialAction {
            return ResearchPermissionEvaluation(
                effectivePolicy: .askEveryTime,
                source: .explicitAction,
                disposition: .initialTargetAuthorized
            )
        }

        let policy: ResearchPermissionPolicy
        let source: ResearchPermissionPolicySource
        if let override = document.override(for: request.packageID) {
            if override.approvedEnvelopeDigest == request.currentEnvelopeDigest {
                policy = override.policy
                source = .skillOverride
            } else {
                policy = .askEveryTime
                source = .invalidatedOverride
            }
        } else {
            policy = document.triptychDefault
            source = .triptychDefault
        }

        let disposition: ResearchPermissionDisposition = switch policy {
        case .askEveryTime:
            .requiresResearcherDecision
        case .askOnlyForWorks:
            request.requestedWritableRoles.contains(.work)
                ? .requiresResearcherDecision
                : .mayIssueBoundedGrant
        case .triptychWide:
            .mayIssueBoundedGrant
        }
        return ResearchPermissionEvaluation(
            effectivePolicy: policy,
            source: source,
            disposition: disposition
        )
    }
}

public enum ResearchPermissionContractError: LocalizedError, Hashable, Sendable {
    case unsupportedSchemaVersion(Int)
    case unsupportedField(String)
    case invalidFingerprint
    case invalidSubject
    case invalidOverride
    case invalidDocument
    case invalidRequest

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Unsupported Research Permission schema version \(version)."
        case .unsupportedField(let field):
            "Unsupported Research Permission field: \(field)."
        case .invalidFingerprint:
            "A Research Permission revision fingerprint is invalid."
        case .invalidSubject:
            "The Research Permission Skill envelope is invalid."
        case .invalidOverride:
            "The per-Skill Research Permission override is invalid."
        case .invalidDocument:
            "The Research Permission document is invalid."
        case .invalidRequest:
            "The standing Research Permission request is invalid."
        }
    }
}

private enum ResearchPermissionValidation {
    static func isValidPackageID(_ value: String) -> Bool {
        value.range(
            of: #"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$"#,
            options: .regularExpression
        ) != nil
    }

    static func rejectUnknownFields(
        in decoder: Decoder,
        allowed: some Sequence<String>
    ) throws {
        let raw = try decoder.container(keyedBy: AnyCodingKey.self)
        let permitted = Set(allowed)
        if let unknown = raw.allKeys.map(\.stringValue).sorted()
            .first(where: { !permitted.contains($0) }) {
            throw ResearchPermissionContractError.unsupportedField(unknown)
        }
    }

    private struct AnyCodingKey: CodingKey {
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
}
