import Foundation

public enum ResearchContinuationEpistemicStatus: String, Codable, CaseIterable,
    Hashable, Sendable
{
    case sourceConclusion = "source_conclusion"
    case agentReconstruction = "agent_reconstruction"
    case hypothesisToVerify = "hypothesis_to_verify"
    case unresolvedQuestion = "unresolved_question"
}

public struct ResearchContinuationHandoffItem: Codable, Hashable, Sendable {
    public let content: String
    public let epistemicStatus: ResearchContinuationEpistemicStatus
    public let nextUse: String
    public let sourceReferences: [SourceReferenceEnvelope]

    public init(
        content: String,
        epistemicStatus: ResearchContinuationEpistemicStatus,
        nextUse: String,
        sourceReferences: [SourceReferenceEnvelope] = []
    ) throws {
        let content = try ResearchContinuationValidation.text(
            content,
            maximumUTF8Count: 8_192
        )
        let nextUse = try ResearchContinuationValidation.text(
            nextUse,
            maximumUTF8Count: 4_096
        )
        guard sourceReferences.count <= 8,
              Set(sourceReferences.map(\.id)).count == sourceReferences.count else {
            throw ResearchContinuationContractError.invalidRequest
        }
        self.content = content
        self.epistemicStatus = epistemicStatus
        self.nextUse = nextUse
        self.sourceReferences = sourceReferences
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case content
        case epistemicStatus = "epistemic_status"
        case nextUse = "next_use"
        case sourceReferences = "source_references"
    }

    public init(from decoder: Decoder) throws {
        try ResearchContinuationValidation.rejectUnknownFields(
            decoder,
            allowed: CodingKeys.self
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            content: container.decode(String.self, forKey: .content),
            epistemicStatus: container.decode(
                ResearchContinuationEpistemicStatus.self,
                forKey: .epistemicStatus
            ),
            nextUse: container.decode(String.self, forKey: .nextUse),
            sourceReferences: container.decode(
                [SourceReferenceEnvelope].self,
                forKey: .sourceReferences
            )
        )
    }
}

/// Agent-facing Continue Research request. The target is role-and-path based;
/// Scholium resolves current identity, Profile, Method, permissions, and
/// revisions after authenticating the completed parent Run.
public struct ResearchContinuationRequest: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let nextActionID: ResearchActionID
    public let targetRole: ResearchActionTargetRole
    public let targetRelativePath: String
    public let academicPurpose: String
    public let handoff: [ResearchContinuationHandoffItem]
    public let fidelityChecks: [FidelityCheck]

    public init(
        nextActionID: ResearchActionID,
        targetRole: ResearchActionTargetRole,
        targetRelativePath: String,
        academicPurpose: String,
        handoff: [ResearchContinuationHandoffItem],
        fidelityChecks: [FidelityCheck] = []
    ) throws {
        guard ResearchContinuationValidation.isSafeRelativePath(targetRelativePath),
              !handoff.isEmpty,
              handoff.count <= 16,
              handoff.flatMap(\.sourceReferences).count <= 32,
              Set(fidelityChecks).count == fidelityChecks.count,
              (nextActionID == .checkFidelity || fidelityChecks.isEmpty) else {
            throw ResearchContinuationContractError.invalidRequest
        }
        schemaVersion = Self.currentSchemaVersion
        self.nextActionID = nextActionID
        self.targetRole = targetRole
        self.targetRelativePath = targetRelativePath
        self.academicPurpose = try ResearchContinuationValidation.text(
            academicPurpose,
            maximumUTF8Count: 16_384
        )
        self.handoff = handoff
        self.fidelityChecks = FidelityCheck.allCases.filter(Set(fidelityChecks).contains)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case nextActionID = "next_action_id"
        case targetRole = "target_role"
        case targetRelativePath = "target_relative_path"
        case academicPurpose = "academic_purpose"
        case handoff
        case fidelityChecks = "fidelity_checks"
    }

    public init(from decoder: Decoder) throws {
        try ResearchContinuationValidation.rejectUnknownFields(
            decoder,
            allowed: CodingKeys.self
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion)
                == Self.currentSchemaVersion else {
            throw ResearchContinuationContractError.unsupportedSchemaVersion
        }
        try self.init(
            nextActionID: container.decode(ResearchActionID.self, forKey: .nextActionID),
            targetRole: container.decode(
                ResearchActionTargetRole.self,
                forKey: .targetRole
            ),
            targetRelativePath: container.decode(
                String.self,
                forKey: .targetRelativePath
            ),
            academicPurpose: container.decode(String.self, forKey: .academicPurpose),
            handoff: container.decode(
                [ResearchContinuationHandoffItem].self,
                forKey: .handoff
            ),
            fidelityChecks: container.decode(
                [FidelityCheck].self,
                forKey: .fidelityChecks
            )
        )
    }

    public func contentFingerprint() throws -> DocumentFingerprint {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return DocumentFingerprint(data: try encoder.encode(self))
    }
}

public enum ResearchContinuationReferenceStatus: String, Codable, Hashable, Sendable {
    case current
    case changed
    case missing
    case unavailable
}

public struct ResearchContinuationReferenceCheck: Codable, Hashable, Sendable {
    public let sourceReference: SourceReferenceEnvelope
    public let status: ResearchContinuationReferenceStatus
    public let explanation: String

    public init(
        sourceReference: SourceReferenceEnvelope,
        status: ResearchContinuationReferenceStatus,
        explanation: String
    ) throws {
        self.sourceReference = sourceReference
        self.status = status
        self.explanation = try ResearchContinuationValidation.text(
            explanation,
            maximumUTF8Count: 1_024
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sourceReference = "source_reference"
        case status, explanation
    }

    public init(from decoder: Decoder) throws {
        try ResearchContinuationValidation.rejectUnknownFields(
            decoder,
            allowed: CodingKeys.self,
            error: .invalidHandoff
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sourceReference: container.decode(
                SourceReferenceEnvelope.self,
                forKey: .sourceReference
            ),
            status: container.decode(
                ResearchContinuationReferenceStatus.self,
                forKey: .status
            ),
            explanation: container.decode(String.self, forKey: .explanation)
        )
    }
}

/// Frozen, explicit continuation input delivered with the new independent
/// Run. It contains no prior query response, ranking, cache, write handle, or
/// permission state.
public struct ResearchContinuationHandoffContext: Codable, Hashable, Sendable {
    public let parentRecordID: UUID
    public let initiator: ResearchContextActorClass
    public let academicPurpose: String
    public let handoff: [ResearchContinuationHandoffItem]
    public let referenceChecks: [ResearchContinuationReferenceCheck]
    /// True when parent-Run Researcher State references were deliberately
    /// omitted. The child must issue a fresh inspect_researcher_state query;
    /// no old state envelope or response crosses the Run boundary.
    public let requiresResearcherStateRequery: Bool
    public let createdAt: Date

    public init(
        parentRecordID: UUID,
        initiator: ResearchContextActorClass,
        academicPurpose: String,
        handoff: [ResearchContinuationHandoffItem],
        referenceChecks: [ResearchContinuationReferenceCheck],
        requiresResearcherStateRequery: Bool = false,
        createdAt: Date = Date()
    ) throws {
        let inheritedReferences = handoff.flatMap(\.sourceReferences)
        guard initiator == .agent || initiator == .researcher,
              !handoff.isEmpty,
              handoff.count <= 16,
              referenceChecks.count <= 32,
              inheritedReferences.allSatisfy({
                  $0.sourceKind != .researcherState
              }),
              referenceChecks.allSatisfy({
                  $0.sourceReference.sourceKind != .researcherState
              }),
              Set(referenceChecks.map(\.sourceReference.id)).count
                == referenceChecks.count,
              createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ResearchContinuationContractError.invalidHandoff
        }
        self.parentRecordID = parentRecordID
        self.initiator = initiator
        self.academicPurpose = try ResearchContinuationValidation.text(
            academicPurpose,
            maximumUTF8Count: 16_384
        )
        self.handoff = handoff
        self.referenceChecks = referenceChecks
        self.requiresResearcherStateRequery = requiresResearcherStateRequery
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case parentRecordID = "parent_record_id"
        case initiator
        case academicPurpose = "academic_purpose"
        case handoff
        case referenceChecks = "reference_checks"
        case requiresResearcherStateRequery = "requires_researcher_state_requery"
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        try ResearchContinuationValidation.rejectUnknownFields(
            decoder,
            allowed: CodingKeys.self,
            error: .invalidHandoff
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            parentRecordID: container.decode(UUID.self, forKey: .parentRecordID),
            initiator: container.decode(
                ResearchContextActorClass.self,
                forKey: .initiator
            ),
            academicPurpose: container.decode(
                String.self,
                forKey: .academicPurpose
            ),
            handoff: container.decode(
                [ResearchContinuationHandoffItem].self,
                forKey: .handoff
            ),
            referenceChecks: container.decode(
                [ResearchContinuationReferenceCheck].self,
                forKey: .referenceChecks
            ),
            requiresResearcherStateRequery: container.decode(
                Bool.self,
                forKey: .requiresResearcherStateRequery
            ),
            createdAt: container.decode(Date.self, forKey: .createdAt)
        )
    }
}

public enum ResearchContinuationRequestState: String, Codable, Hashable, Sendable {
    case pending
    case allowed
    case created
    case declined
    case stale
    case expired
}

public enum ResearchContinuationAuthorizationBasis: String, Codable, Hashable,
    Sendable
{
    case collaborationPolicy = "collaboration_policy"
    case explicitResearcherDecision = "explicit_researcher_decision"
}

public struct ResearchContinuationRequestRecord: Codable, Hashable, Identifiable,
    Sendable
{
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let id: UUID
    public let parentRunID: UUID
    public let triptychID: UUID
    public let request: ResearchContinuationRequest
    public let requestFingerprint: DocumentFingerprint
    public let policy: ResearchCollaborationPolicy
    public let policyRevision: DocumentFingerprint
    public var state: ResearchContinuationRequestState
    public var authorizationBasis: ResearchContinuationAuthorizationBasis?
    public let receivedAt: Date
    public let expiresAt: Date
    public var decidedAt: Date?
    public var childRunID: UUID?

    public init(
        id: UUID,
        parentRunID: UUID,
        triptychID: UUID,
        request: ResearchContinuationRequest,
        requestFingerprint: DocumentFingerprint,
        policy: ResearchCollaborationPolicy,
        policyRevision: DocumentFingerprint,
        state: ResearchContinuationRequestState,
        authorizationBasis: ResearchContinuationAuthorizationBasis? = nil,
        receivedAt: Date,
        expiresAt: Date,
        decidedAt: Date? = nil,
        childRunID: UUID? = nil
    ) throws {
        let terminalWithoutChild = [
            ResearchContinuationRequestState.declined,
            .stale,
            .expired,
        ]
        let shapeIsValid = switch state {
        case .pending:
            decidedAt == nil && childRunID == nil && authorizationBasis == nil
        case .allowed:
            decidedAt != nil && childRunID == nil && authorizationBasis != nil
        case .created:
            decidedAt != nil && childRunID != nil && authorizationBasis != nil
        case .declined, .stale, .expired:
            decidedAt != nil && childRunID == nil && authorizationBasis == nil
        }
        guard requestFingerprint == (try request.contentFingerprint()),
              policyRevision.sha256.count == 64,
              receivedAt.timeIntervalSinceReferenceDate.isFinite,
              expiresAt > receivedAt,
              decidedAt.map({ $0.timeIntervalSinceReferenceDate.isFinite }) ?? true,
              shapeIsValid,
              !terminalWithoutChild.contains(state) || childRunID == nil else {
            throw ResearchContinuationContractError.invalidRecord
        }
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.parentRunID = parentRunID
        self.triptychID = triptychID
        self.request = request
        self.requestFingerprint = requestFingerprint
        self.policy = policy
        self.policyRevision = policyRevision
        self.state = state
        self.authorizationBasis = authorizationBasis
        self.receivedAt = receivedAt
        self.expiresAt = expiresAt
        self.decidedAt = decidedAt
        self.childRunID = childRunID
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case id
        case parentRunID = "parent_run_id"
        case triptychID = "triptych_id"
        case request
        case requestFingerprint = "request_fingerprint"
        case policy
        case policyRevision = "policy_revision"
        case state
        case authorizationBasis = "authorization_basis"
        case receivedAt = "received_at"
        case expiresAt = "expires_at"
        case decidedAt = "decided_at"
        case childRunID = "child_run_id"
    }

    public init(from decoder: Decoder) throws {
        try ResearchContinuationValidation.rejectUnknownFields(
            decoder,
            allowed: CodingKeys.self,
            error: .invalidRecord
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion)
                == Self.currentSchemaVersion else {
            throw ResearchContinuationContractError.unsupportedSchemaVersion
        }
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            parentRunID: container.decode(UUID.self, forKey: .parentRunID),
            triptychID: container.decode(UUID.self, forKey: .triptychID),
            request: container.decode(
                ResearchContinuationRequest.self,
                forKey: .request
            ),
            requestFingerprint: container.decode(
                DocumentFingerprint.self,
                forKey: .requestFingerprint
            ),
            policy: container.decode(
                ResearchCollaborationPolicy.self,
                forKey: .policy
            ),
            policyRevision: container.decode(
                DocumentFingerprint.self,
                forKey: .policyRevision
            ),
            state: container.decode(
                ResearchContinuationRequestState.self,
                forKey: .state
            ),
            authorizationBasis: container.decodeIfPresent(
                ResearchContinuationAuthorizationBasis.self,
                forKey: .authorizationBasis
            ),
            receivedAt: container.decode(Date.self, forKey: .receivedAt),
            expiresAt: container.decode(Date.self, forKey: .expiresAt),
            decidedAt: container.decodeIfPresent(Date.self, forKey: .decidedAt),
            childRunID: container.decodeIfPresent(UUID.self, forKey: .childRunID)
        )
    }
}

public enum ResearchContinuationResultState: String, Codable, Hashable, Sendable {
    case pendingResearcherDecision = "pending_researcher_decision"
    case created
    case declined
    case stale
    case expired
}

public struct ResearchContinuationResult: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 4

    public let schemaVersion: Int
    public let state: ResearchContinuationResultState
    public let nextRun: ResearchRunLocator?
    public let handoffContext: ResearchContinuationHandoffContext?
    public let context: ResearchAuthenticatedRunContext?
    public let message: String

    public init(
        state: ResearchContinuationResultState,
        nextRun: ResearchRunLocator? = nil,
        handoffContext: ResearchContinuationHandoffContext? = nil,
        context: ResearchAuthenticatedRunContext? = nil,
        message: String
    ) throws {
        guard (state == .created)
                == (nextRun != nil && handoffContext != nil && context != nil),
              state == .created
                || (nextRun == nil && handoffContext == nil && context == nil),
              context?.brief.run == nextRun else {
            throw ResearchContinuationContractError.invalidResult
        }
        schemaVersion = Self.currentSchemaVersion
        self.state = state
        self.nextRun = nextRun
        self.handoffContext = handoffContext
        self.context = context
        self.message = try ResearchContinuationValidation.text(
            message,
            maximumUTF8Count: 1_024
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case state
        case nextRun = "next_run"
        case handoffContext = "handoff_context"
        case context
        case message
    }

    public init(from decoder: Decoder) throws {
        try ResearchContinuationValidation.rejectUnknownFields(
            decoder,
            allowed: CodingKeys.self,
            error: .invalidResult
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion)
                == Self.currentSchemaVersion else {
            throw ResearchContinuationContractError.unsupportedSchemaVersion
        }
        try self.init(
            state: container.decode(
                ResearchContinuationResultState.self,
                forKey: .state
            ),
            nextRun: container.decodeIfPresent(
                ResearchRunLocator.self,
                forKey: .nextRun
            ),
            handoffContext: container.decodeIfPresent(
                ResearchContinuationHandoffContext.self,
                forKey: .handoffContext
            ),
            context: container.decodeIfPresent(
                ResearchAuthenticatedRunContext.self,
                forKey: .context
            ),
            message: container.decode(String.self, forKey: .message)
        )
    }
}

public enum ResearchContinuationContractError: LocalizedError, Hashable, Sendable {
    case unsupportedSchemaVersion
    case invalidRequest
    case invalidHandoff
    case invalidRecord
    case invalidResult
    case parentNotFinalized
    case decisionRequired

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion: "The Continue Research schema is unsupported."
        case .invalidRequest: "The Continue Research request is invalid or unbounded."
        case .invalidHandoff: "The Continue Research handoff is invalid."
        case .invalidRecord: "The stored Continue Research decision is invalid."
        case .invalidResult: "The Continue Research result is invalid."
        case .parentNotFinalized:
            "Continue Research requires one safely finalized parent Research Record."
        case .decisionRequired:
            "This Continue Research request is waiting for one researcher decision."
        }
    }
}

private enum ResearchContinuationValidation {
    static func text(_ value: String, maximumUTF8Count: Int) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.utf8.count <= maximumUTF8Count,
              !value.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
                      && $0 != "\n" && $0 != "\t"
              }) else {
            throw ResearchContinuationContractError.invalidRequest
        }
        return value
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              path.utf8.count <= 1_024,
              !path.hasPrefix("/"),
              !path.hasPrefix("\\"),
              !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }

    static func rejectUnknownFields<Key: CodingKey & CaseIterable>(
        _ decoder: Decoder,
        allowed: Key.Type,
        error: ResearchContinuationContractError = .invalidRequest
    ) throws {
        let raw = try decoder.container(keyedBy: AnyKey.self)
        let known = Set(Key.allCases.map(\.stringValue))
        guard raw.allKeys.allSatisfy({ known.contains($0.stringValue) }) else {
            throw error
        }
    }

    private struct AnyKey: CodingKey {
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
