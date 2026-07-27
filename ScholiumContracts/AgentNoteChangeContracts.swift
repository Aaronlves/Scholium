import Foundation

/// Short-lived authority to ask Scholium to coordinate a separately bounded
/// continuation from one frozen local Action run. Only the digest is durable;
/// the plaintext key exists solely in the live delivery packet and bridge
/// request.
public struct AgentCoordinationGrant: Codable, Hashable, Sendable {
    public static let maximumLifetime: TimeInterval = 24 * 60 * 60

    public let triptychID: UUID
    public let parentRunID: UUID
    public let actionRevision: AgentNoteChangeActionRevision
    public let keyDigest: String
    public let issuedAt: Date
    public let expiresAt: Date

    public init(
        triptychID: UUID,
        parentRunID: UUID,
        actionRevision: AgentNoteChangeActionRevision,
        keyDigest: String,
        issuedAt: Date,
        expiresAt: Date
    ) throws {
        guard keyDigest.range(
            of: #"^[0-9a-f]{64}$"#,
            options: .regularExpression
        ) != nil,
        issuedAt.timeIntervalSinceReferenceDate.isFinite,
        expiresAt.timeIntervalSinceReferenceDate.isFinite,
        expiresAt > issuedAt,
        expiresAt.timeIntervalSince(issuedAt) <= Self.maximumLifetime else {
            throw AgentNoteChangeContractError.invalidCoordinationGrant
        }
        self.triptychID = triptychID
        self.parentRunID = parentRunID
        self.actionRevision = actionRevision
        self.keyDigest = keyDigest
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case triptychID = "triptych_id"
        case parentRunID = "parent_run_id"
        case actionRevision = "action_revision"
        case keyDigest = "key_digest"
        case issuedAt = "issued_at"
        case expiresAt = "expires_at"
    }

    public init(from decoder: Decoder) throws {
        try AgentNoteChangeValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            triptychID: container.decode(UUID.self, forKey: .triptychID),
            parentRunID: container.decode(UUID.self, forKey: .parentRunID),
            actionRevision: container.decode(
                AgentNoteChangeActionRevision.self,
                forKey: .actionRevision
            ),
            keyDigest: container.decode(String.self, forKey: .keyDigest),
            issuedAt: container.decode(Date.self, forKey: .issuedAt),
            expiresAt: container.decode(Date.self, forKey: .expiresAt)
        )
    }

    public static func boundKeyDigest(
        coordinationKey: String,
        triptychID: UUID,
        parentRunID: UUID,
        actionRevision: AgentNoteChangeActionRevision
    ) throws -> String {
        guard coordinationKey.utf8.count == 73 else {
            throw AgentNoteChangeContractError.invalidCoordinationGrant
        }
        let input = AgentCoordinationDigestInput(
            coordinationKey: coordinationKey,
            triptychID: triptychID,
            parentRunID: parentRunID,
            actionRevision: actionRevision
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return DocumentFingerprint(data: try encoder.encode(input)).sha256
    }

    public func boundKeyDigest(coordinationKey: String) throws -> String {
        try Self.boundKeyDigest(
            coordinationKey: coordinationKey,
            triptychID: triptychID,
            parentRunID: parentRunID,
            actionRevision: actionRevision
        )
    }
}

private struct AgentCoordinationDigestInput: Encodable {
    let coordinationKey: String
    let triptychID: UUID
    let parentRunID: UUID
    let actionRevision: AgentNoteChangeActionRevision

    private enum CodingKeys: String, CodingKey {
        case coordinationKey = "coordination_key"
        case triptychID = "triptych_id"
        case parentRunID = "parent_run_id"
        case actionRevision = "action_revision"
    }
}

/// The only value that carries the plaintext coordination key. It is
/// intentionally not Codable.
public struct AgentCoordinationAuthorization: Sendable {
    public let grant: AgentCoordinationGrant
    public let coordinationKey: String

    public init(grant: AgentCoordinationGrant, coordinationKey: String) {
        self.grant = grant
        self.coordinationKey = coordinationKey
    }
}

/// Exact Action, Method Skill, and Profile revision participating in an
/// agent-requested continuation.
///
/// This is revision evidence, not authority. The Application must still
/// resolve and validate the current Action before any decision or child phase.
public struct AgentNoteChangeActionRevision: Codable, Hashable, Sendable {
    public let definition: ResearchActionDefinition
    public let packageID: String
    public let skillRevision: DocumentFingerprint
    public let profileOrigin: ResearchActionProfileOrigin
    public let profileRevision: DocumentFingerprint
    public let profileDocumentRevision: DocumentFingerprint?

    public init(
        definition: ResearchActionDefinition,
        packageID: String,
        skillRevision: DocumentFingerprint,
        profileOrigin: ResearchActionProfileOrigin,
        profileRevision: DocumentFingerprint,
        profileDocumentRevision: DocumentFingerprint?
    ) throws {
        guard AgentNoteChangeValidation.isValidPackageID(packageID),
              AgentNoteChangeValidation.isValidFingerprint(skillRevision),
              AgentNoteChangeValidation.isValidFingerprint(profileRevision),
              profileDocumentRevision.map(
                AgentNoteChangeValidation.isValidFingerprint
              ) ?? true,
              (profileOrigin == .researcher) == (profileDocumentRevision != nil) else {
            throw AgentNoteChangeContractError.invalidActionRevision
        }
        self.definition = definition
        self.packageID = packageID
        self.skillRevision = skillRevision
        self.profileOrigin = profileOrigin
        self.profileRevision = profileRevision
        self.profileDocumentRevision = profileDocumentRevision
    }

    public init(actionSnapshot: ResearchActionSnapshot) throws {
        try self.init(
            definition: actionSnapshot.definition,
            packageID: actionSnapshot.method.packageID,
            skillRevision: actionSnapshot.method.packageRevision,
            profileOrigin: actionSnapshot.resolvedProfile.origin,
            profileRevision: actionSnapshot.resolvedProfile.profileRevision,
            profileDocumentRevision:
                actionSnapshot.resolvedProfile.profileDocumentRevision
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case definition
        case packageID = "package_id"
        case skillRevision = "skill_revision"
        case profileOrigin = "profile_origin"
        case profileRevision = "profile_revision"
        case profileDocumentRevision = "profile_document_revision"
    }

    public init(from decoder: Decoder) throws {
        try AgentNoteChangeValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            definition: container.decode(
                AgentNoteChangeStrictActionDefinition.self,
                forKey: .definition
            ).value,
            packageID: container.decode(String.self, forKey: .packageID),
            skillRevision: container.decode(
                AgentNoteChangeStrictFingerprint.self,
                forKey: .skillRevision
            ).value,
            profileOrigin: container.decode(
                ResearchActionProfileOrigin.self,
                forKey: .profileOrigin
            ),
            profileRevision: container.decode(
                AgentNoteChangeStrictFingerprint.self,
                forKey: .profileRevision
            ).value,
            profileDocumentRevision: container.decodeIfPresent(
                AgentNoteChangeStrictFingerprint.self,
                forKey: .profileDocumentRevision
            )?.value
        )
    }
}

private struct AgentNoteChangeStrictActionDefinition: Decodable {
    let value: ResearchActionDefinition

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id = "action_id"
        case executionKind = "execution_kind"
    }

    init(from decoder: Decoder) throws {
        try AgentNoteChangeValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(ResearchActionID.self, forKey: .id)
        let kind = try container.decode(
            ResearchActionExecutionKind.self,
            forKey: .executionKind
        )
        let definition: ResearchActionDefinition
        switch id {
        case .discuss: definition = .discuss
        case .analyze: definition = .analyze
        case .synthesize: definition = .synthesize
        case .write: definition = .write
        case .critique: definition = .critique
        case .checkFidelity: definition = .checkFidelity
        case .manuscript: definition = .manuscript
        default:
            definition = try ResearchActionDefinition(
                researcherOwnedID: id,
                executionKind: kind
            )
        }
        guard definition.executionKind == kind else {
            throw AgentNoteChangeContractError.invalidActionRevision
        }
        value = definition
    }
}

private struct AgentNoteChangeStrictFingerprint: Decodable {
    let value: DocumentFingerprint

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sha256, byteCount
    }

    init(from decoder: Decoder) throws {
        try AgentNoteChangeValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = DocumentFingerprint(
            sha256: try container.decode(String.self, forKey: .sha256),
            byteCount: try container.decode(Int.self, forKey: .byteCount)
        )
        self.value = value
    }
}

private struct AgentNoteChangeStrictNoteID: Decodable {
    let value: VaultQualifiedNoteID

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case vaultID, relativePath
    }

    init(from decoder: Decoder) throws {
        try AgentNoteChangeValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = VaultQualifiedNoteID(
            vaultID: try container.decode(UUID.self, forKey: .vaultID),
            relativePath: try container.decode(String.self, forKey: .relativePath)
        )
    }
}

/// Stable identity and expected bytes for one Note an agent asks Scholium to
/// place inside a separately authorized write phase. Display title and
/// lifecycle are deliberately absent: Scholium derives both from current
/// Application-owned state before presenting or resolving the request.
public struct AgentNoteChangeTarget: Codable, Hashable, Sendable {
    public let noteID: UUID
    public let note: VaultQualifiedNoteID
    public let role: ResearchActionTargetRole
    public let expectedFingerprint: DocumentFingerprint

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case noteID = "note_id"
        case note, role
        case expectedFingerprint = "expected_fingerprint"
    }

    public init(
        noteID: UUID,
        note: VaultQualifiedNoteID,
        role: ResearchActionTargetRole,
        expectedFingerprint: DocumentFingerprint
    ) throws {
        guard AgentNoteChangeValidation.isValidNotePath(note.relativePath),
              AgentNoteChangeValidation.isValidFingerprint(
                  expectedFingerprint
              ) else {
            throw AgentNoteChangeContractError.invalidRequest
        }
        self.noteID = noteID
        self.note = note
        self.role = role
        self.expectedFingerprint = expectedFingerprint
    }

    public init(snapshot: ResearchActionNoteSnapshot) throws {
        try self.init(
            noteID: snapshot.noteID,
            note: snapshot.note,
            role: snapshot.role,
            expectedFingerprint: snapshot.fingerprint
        )
    }

    public init(from decoder: Decoder) throws {
        try AgentNoteChangeValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            noteID: try container.decode(UUID.self, forKey: .noteID),
            note: try container.decode(
                AgentNoteChangeStrictNoteID.self,
                forKey: .note
            ).value,
            role: try container.decode(
                ResearchActionTargetRole.self,
                forKey: .role
            ),
            expectedFingerprint: try container.decode(
                AgentNoteChangeStrictFingerprint.self,
                forKey: .expectedFingerprint
            ).value
        )
    }
}

/// One idempotent request by an attributed external agent to change additional
/// Notes or begin a separately bounded write-capable Action.
///
/// The request never expands the frozen parent snapshot or its grant. It only
/// supplies input to standing policy or a later researcher decision.
public struct AgentNoteChangeRequest: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumTargetCount = 64
    public static let maximumReasonUTF8ByteCount = 16_384

    public let schemaVersion: Int
    public let requestID: UUID
    public let triptychID: UUID
    public let parentRunID: UUID
    public let parentAction: AgentNoteChangeActionRevision
    public let requestedAction: AgentNoteChangeActionRevision
    public let targets: [AgentNoteChangeTarget]
    public let operations: [ResearchActionCandidateWriteOperation]
    public let agentReason: String

    public var id: UUID { requestID }

    public init(
        requestID: UUID = UUID(),
        triptychID: UUID,
        parentRunID: UUID,
        parentAction: AgentNoteChangeActionRevision,
        requestedAction: AgentNoteChangeActionRevision,
        targets: [AgentNoteChangeTarget],
        operations: [ResearchActionCandidateWriteOperation],
        agentReason: String
    ) throws {
        let canonicalTargets = targets.sorted {
            $0.noteID.uuidString < $1.noteID.uuidString
        }
        let canonicalOperations = Array(Set(operations)).sorted {
            $0.rawValue < $1.rawValue
        }
        let targetRoles = Set(canonicalTargets.map(\.role))
        guard !canonicalTargets.isEmpty,
              canonicalTargets.count <= Self.maximumTargetCount,
              Set(canonicalTargets.map(\.noteID)).count == canonicalTargets.count,
              Set(canonicalTargets.map(\.note)).count == canonicalTargets.count,
              canonicalTargets.allSatisfy({ target in
                  AgentNoteChangeValidation.isValidFingerprint(
                      target.expectedFingerprint
                  ) && AgentNoteChangeValidation.isValidNotePath(
                      target.note.relativePath
                  )
              }),
              targetRoles.count == 1,
              canonicalTargets.allSatisfy({
                  requestedAction.definition.allowedTargetRoles.contains($0.role)
              }),
              !canonicalOperations.isEmpty,
              canonicalOperations.count == operations.count,
              !agentReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              agentReason.utf8.count <= Self.maximumReasonUTF8ByteCount,
              !agentReason.unicodeScalars.contains(where: {
                  $0.value == 0 || ($0.value < 32 && $0 != "\n" && $0 != "\t")
              }) else {
            throw AgentNoteChangeContractError.invalidRequest
        }
        schemaVersion = Self.currentSchemaVersion
        self.requestID = requestID
        self.triptychID = triptychID
        self.parentRunID = parentRunID
        self.parentAction = parentAction
        self.requestedAction = requestedAction
        self.targets = canonicalTargets
        self.operations = canonicalOperations
        self.agentReason = agentReason
    }

    /// Deterministic payload identity used to make retries idempotent while
    /// rejecting reuse of one request ID for different intent.
    public func payloadDigest() throws -> DocumentFingerprint {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return DocumentFingerprint(data: try encoder.encode(self))
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case triptychID = "triptych_id"
        case parentRunID = "parent_run_id"
        case parentAction = "parent_action"
        case requestedAction = "requested_action"
        case targets, operations
        case agentReason = "agent_reason"
    }

    public init(from decoder: Decoder) throws {
        try AgentNoteChangeValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw AgentNoteChangeContractError.unsupportedSchemaVersion(version)
        }
        try self.init(
            requestID: container.decode(UUID.self, forKey: .requestID),
            triptychID: container.decode(UUID.self, forKey: .triptychID),
            parentRunID: container.decode(UUID.self, forKey: .parentRunID),
            parentAction: container.decode(
                AgentNoteChangeActionRevision.self,
                forKey: .parentAction
            ),
            requestedAction: container.decode(
                AgentNoteChangeActionRevision.self,
                forKey: .requestedAction
            ),
            targets: container.decode(
                [AgentNoteChangeTarget].self,
                forKey: .targets
            ),
            operations: container.decode(
                [ResearchActionCandidateWriteOperation].self,
                forKey: .operations
            ),
            agentReason: container.decode(String.self, forKey: .agentReason)
        )
    }
}

public enum AgentNoteChangeDecisionState: String, Codable, CaseIterable,
    Hashable, Sendable
{
    case pending
    case allowedSubset = "allowed_subset"
    case continueWithoutChanges = "continue_without_changes"
    case cancelled
    case stale
    case expired
}

/// Current machine-local disposition of one exact request payload.
public struct AgentNoteChangeDecision: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let requestID: UUID
    public let requestDigest: DocumentFingerprint
    public let state: AgentNoteChangeDecisionState
    public let allowedNoteIDs: [UUID]
    public let decidedAt: Date?

    public init(
        requestID: UUID,
        requestDigest: DocumentFingerprint,
        state: AgentNoteChangeDecisionState,
        allowedNoteIDs: [UUID] = [],
        decidedAt: Date? = nil
    ) throws {
        let canonicalIDs = Array(Set(allowedNoteIDs)).sorted {
            $0.uuidString < $1.uuidString
        }
        guard AgentNoteChangeValidation.isValidFingerprint(requestDigest),
              canonicalIDs.count == allowedNoteIDs.count,
              canonicalIDs.count <= AgentNoteChangeRequest.maximumTargetCount,
              (state == .allowedSubset) == !canonicalIDs.isEmpty,
              (state == .pending) == (decidedAt == nil) else {
            throw AgentNoteChangeContractError.invalidDecision
        }
        schemaVersion = Self.currentSchemaVersion
        self.requestID = requestID
        self.requestDigest = requestDigest
        self.state = state
        self.allowedNoteIDs = canonicalIDs
        self.decidedAt = decidedAt
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case requestDigest = "request_digest"
        case state
        case allowedNoteIDs = "allowed_note_ids"
        case decidedAt = "decided_at"
    }

    public init(from decoder: Decoder) throws {
        try AgentNoteChangeValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw AgentNoteChangeContractError.unsupportedSchemaVersion(version)
        }
        try self.init(
            requestID: container.decode(UUID.self, forKey: .requestID),
            requestDigest: container.decode(
                AgentNoteChangeStrictFingerprint.self,
                forKey: .requestDigest
            ).value,
            state: container.decode(
                AgentNoteChangeDecisionState.self,
                forKey: .state
            ),
            allowedNoteIDs: container.decode(
                [UUID].self,
                forKey: .allowedNoteIDs
            ),
            decidedAt: container.decodeIfPresent(Date.self, forKey: .decidedAt)
        )
    }
}

/// Durable machine-local coordination state. It is neither a write grant nor
/// portable scholarly history.
public struct AgentNoteChangeRequestRecord: Codable, Hashable, Identifiable,
    Sendable
{
    public static let currentSchemaVersion = 1
    public static let maximumLifetime: TimeInterval = 30 * 60

    public let schemaVersion: Int
    public let request: AgentNoteChangeRequest
    public let requestDigest: DocumentFingerprint
    public let receivedAt: Date
    public let expiresAt: Date
    public let decision: AgentNoteChangeDecision

    public var id: UUID { request.id }
    public var isUnresolved: Bool { decision.state == .pending }

    public init(
        request: AgentNoteChangeRequest,
        receivedAt: Date,
        validFor requestedLifetime: TimeInterval = 10 * 60,
        initialState: AgentNoteChangeDecisionState = .pending
    ) throws {
        guard requestedLifetime.isFinite,
              receivedAt.timeIntervalSinceReferenceDate.isFinite,
              initialState == .pending || initialState == .stale else {
            throw AgentNoteChangeContractError.invalidDecision
        }
        let lifetime = min(max(1, requestedLifetime), Self.maximumLifetime)
        let digest = try request.payloadDigest()
        schemaVersion = Self.currentSchemaVersion
        self.request = request
        requestDigest = digest
        self.receivedAt = receivedAt
        expiresAt = receivedAt.addingTimeInterval(lifetime)
        decision = try AgentNoteChangeDecision(
            requestID: request.id,
            requestDigest: digest,
            state: initialState,
            decidedAt: initialState == .pending ? nil : receivedAt
        )
    }

    private init(
        request: AgentNoteChangeRequest,
        requestDigest: DocumentFingerprint,
        receivedAt: Date,
        expiresAt: Date,
        decision: AgentNoteChangeDecision
    ) throws {
        let receivedAtValue = receivedAt.timeIntervalSinceReferenceDate
        let expiresAtValue = expiresAt.timeIntervalSinceReferenceDate
        let decisionTimelineIsValid: Bool
        if decision.state == .pending {
            decisionTimelineIsValid = decision.decidedAt == nil
        } else if let decidedAt = decision.decidedAt {
            let decidedAtValue = decidedAt.timeIntervalSinceReferenceDate
            decisionTimelineIsValid = decidedAtValue.isFinite
                && decidedAt >= receivedAt
                && (decision.state == .expired
                    ? decidedAt >= expiresAt
                    : decidedAt < expiresAt)
        } else {
            decisionTimelineIsValid = false
        }
        guard requestDigest == (try request.payloadDigest()),
              request.id == decision.requestID,
              requestDigest == decision.requestDigest,
              receivedAtValue.isFinite,
              expiresAtValue.isFinite,
              expiresAt > receivedAt,
              expiresAt.timeIntervalSince(receivedAt) <= Self.maximumLifetime,
              decisionTimelineIsValid,
              Set(decision.allowedNoteIDs).isSubset(
                  of: Set(request.targets.map(\.noteID))
              ) else {
            throw AgentNoteChangeContractError.invalidRecord
        }
        schemaVersion = Self.currentSchemaVersion
        self.request = request
        self.requestDigest = requestDigest
        self.receivedAt = receivedAt
        self.expiresAt = expiresAt
        self.decision = decision
    }

    public func expiringIfNeeded(at date: Date) throws -> Self {
        guard decision.state == .pending, date >= expiresAt else { return self }
        return try resolving(state: .expired, at: date)
    }

    public func resolving(
        state: AgentNoteChangeDecisionState,
        allowedNoteIDs: [UUID] = [],
        at date: Date
    ) throws -> Self {
        guard decision.state == .pending,
              state != .pending,
              (state == .expired ? date >= expiresAt : date < expiresAt),
              Set(allowedNoteIDs).isSubset(
                  of: Set(request.targets.map(\.noteID))
              ) else {
            throw AgentNoteChangeContractError.invalidDecision
        }
        let resolved = try AgentNoteChangeDecision(
            requestID: request.id,
            requestDigest: requestDigest,
            state: state,
            allowedNoteIDs: allowedNoteIDs,
            decidedAt: date
        )
        return try Self(
            request: request,
            requestDigest: requestDigest,
            receivedAt: receivedAt,
            expiresAt: expiresAt,
            decision: resolved
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case request
        case requestDigest = "request_digest"
        case receivedAt = "received_at"
        case expiresAt = "expires_at"
        case decision
    }

    public init(from decoder: Decoder) throws {
        try AgentNoteChangeValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw AgentNoteChangeContractError.unsupportedSchemaVersion(version)
        }
        try self.init(
            request: container.decode(
                AgentNoteChangeRequest.self,
                forKey: .request
            ),
            requestDigest: container.decode(
                AgentNoteChangeStrictFingerprint.self,
                forKey: .requestDigest
            ).value,
            receivedAt: container.decode(Date.self, forKey: .receivedAt),
            expiresAt: container.decode(Date.self, forKey: .expiresAt),
            decision: container.decode(
                AgentNoteChangeDecision.self,
                forKey: .decision
            )
        )
    }
}

public enum AgentNoteChangeContractError: LocalizedError, Hashable, Sendable {
    case unsupportedSchemaVersion(Int)
    case unsupportedField(String)
    case invalidActionRevision
    case invalidRequest
    case invalidDecision
    case invalidRecord
    case invalidCoordinationGrant

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Unsupported Agent Note Change schema version \(version)."
        case .unsupportedField(let field):
            "Unsupported Agent Note Change field: \(field)."
        case .invalidActionRevision:
            "The Agent Note Change Action revision is invalid."
        case .invalidRequest:
            "The Agent Note Change request is invalid."
        case .invalidDecision:
            "The Agent Note Change decision is invalid."
        case .invalidRecord:
            "The Agent Note Change record is invalid."
        case .invalidCoordinationGrant:
            "The Agent coordination grant is invalid."
        }
    }
}

private enum AgentNoteChangeValidation {
    static func isValidPackageID(_ value: String) -> Bool {
        value.range(
            of: #"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$"#,
            options: .regularExpression
        ) != nil
    }

    static func isValidFingerprint(_ fingerprint: DocumentFingerprint) -> Bool {
        fingerprint.byteCount >= 0
            && fingerprint.sha256.range(
                of: #"^[0-9a-f]{64}$"#,
                options: .regularExpression
            ) != nil
    }

    static func isValidNotePath(_ value: String) -> Bool {
        let components = value.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        return !value.isEmpty
            && value.utf8.count <= 4_096
            && !value.hasPrefix("/")
            && value.lowercased().hasSuffix(".md")
            && !components.contains(where: {
                $0.isEmpty || $0 == "." || $0 == ".."
            })
            && !value.unicodeScalars.contains(where: { $0.value == 0 })
    }

    static func rejectUnknownFields(
        in decoder: Decoder,
        allowed: some Sequence<String>
    ) throws {
        let raw = try decoder.container(keyedBy: AnyCodingKey.self)
        let permitted = Set(allowed)
        if let unknown = raw.allKeys.map(\.stringValue).sorted()
            .first(where: { !permitted.contains($0) }) {
            throw AgentNoteChangeContractError.unsupportedField(unknown)
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
