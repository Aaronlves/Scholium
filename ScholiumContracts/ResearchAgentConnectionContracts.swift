import Foundation

/// The Agent-start wire shape is deliberately independent of Swift property
/// spelling. Other internal and portable contracts retain their own versions;
/// this adapter owns only the documented `agent start` JSON boundary.
private struct ResearchAgentStartWireNoteID: Codable {
    let value: VaultQualifiedNoteID

    init(_ value: VaultQualifiedNoteID) {
        self.value = value
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case vaultID = "vault_id"
        case relativePath = "relative_path"
    }

    init(from decoder: Decoder) throws {
        try ResearchAgentStartCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.self
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = VaultQualifiedNoteID(
            vaultID: try container.decode(UUID.self, forKey: .vaultID),
            relativePath: try container.decode(String.self, forKey: .relativePath)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value.vaultID, forKey: .vaultID)
        try container.encode(value.relativePath, forKey: .relativePath)
    }
}

public struct ResearchRunLocator: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard (20...96).contains(rawValue.utf8.count),
              rawValue.unicodeScalars.allSatisfy({
                  (48...57).contains($0.value)
                      || (65...90).contains($0.value)
                      || (97...122).contains($0.value)
                      || $0 == "-" || $0 == "_"
              }) else { return nil }
        self.rawValue = rawValue
    }
}

/// The portable Zotero relationship supplied when an Agent starts a new
/// Analysis. It is not bibliographic content and not a request to read
/// Zotero's database; Scholium attaches it only to a stable Analysis identity.
public struct ResearchAgentNewAnalysisSource: Codable, Hashable, Sendable {
    public let library: ZoteroLibraryIdentity
    public let itemKey: String

    public init(
        library: ZoteroLibraryIdentity,
        itemKey: String
    ) throws {
        let normalized = try AnalysisZoteroBinding(
            noteID: UUID(),
            library: library,
            itemKey: itemKey
        ).itemKey
        self.library = library
        self.itemKey = normalized
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case library
        case itemKey = "item_key"
    }

    public init(from decoder: Decoder) throws {
        try ResearchAgentStartCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.self
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            library: container.decode(ZoteroLibraryIdentity.self, forKey: .library),
            itemKey: container.decode(String.self, forKey: .itemKey)
        )
    }
}

/// Declares that the researcher will provide the source directly to the
/// external Agent. Scholium receives neither a path nor source bytes for this
/// route and therefore cannot resolve, cache, or attest to that local file.
public enum ResearchAgentSourceRoute: String, Codable, Hashable, Sendable {
    case researcherProvided = "researcher_provided"
}

/// A classification-bounded Agent destination request. Direct Agent creation
/// accepts one filename and always resolves it at the Analyses-vault root.
/// Researcher-selected subfolders remain available through a researcher-created
/// existing Analysis target, never through an Agent assertion.
public struct ResearchAgentAnalysisDestination: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let managedDefaultFilename: String

    public init(managedDefaultFilename: String) throws {
        guard Self.validFilename(managedDefaultFilename) else {
            throw ResearchAgentStartContractError.invalidRequest
        }
        schemaVersion = Self.currentSchemaVersion
        self.managedDefaultFilename = managedDefaultFilename
    }

    public var resolvedRelativePath: String {
        managedDefaultFilename
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case managedDefaultFilename = "managed_default_filename"
    }

    public init(from decoder: Decoder) throws {
        try ResearchAgentStartCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.self
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion)
                == Self.currentSchemaVersion else {
            throw ResearchAgentStartContractError.unsupportedSchemaVersion
        }
        guard let managed = try container.decodeIfPresent(
            String.self,
            forKey: .managedDefaultFilename
        ) else { throw ResearchAgentStartContractError.invalidRequest }
        try self.init(managedDefaultFilename: managed)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(
            managedDefaultFilename,
            forKey: .managedDefaultFilename
        )
    }

    private static func validFilename(_ value: String) -> Bool {
        validRelativePath(value)
            && !value.contains("/")
            && !value.hasPrefix(".")
    }

    private static func validRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.utf8.count <= 4_096,
              value.lowercased().hasSuffix(".md"),
              !value.hasPrefix("/"),
              !value.hasSuffix("/"),
              !value.contains("\\"),
              !value.unicodeScalars.contains(where: { $0.value == 0 }) else {
            return false
        }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }
}

/// Read-only input used before a consequential Agent start. It contains one
/// stable logical request identity but no vault ID or Settings revision.
public struct ResearchAgentAnalysisCreationPreflightRequest: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let requestID: UUID
    public let destination: ResearchAgentAnalysisDestination
    public let metadata: AnalysisCreationMetadata
    public let authoredYAML: AuthoredNoteYAML?
    public let source: ResearchAgentNewAnalysisSource?
    public let sourceRoute: ResearchAgentSourceRoute?

    public init(
        requestID: UUID = UUID(),
        destination: ResearchAgentAnalysisDestination,
        metadata: AnalysisCreationMetadata,
        authoredYAML: AuthoredNoteYAML? = nil,
        source: ResearchAgentNewAnalysisSource? = nil,
        sourceRoute: ResearchAgentSourceRoute? = nil
    ) throws {
        guard (source == nil) != (sourceRoute == nil),
              sourceRoute == nil || sourceRoute == .researcherProvided else {
            throw ResearchAgentStartContractError.invalidRequest
        }
        schemaVersion = Self.currentSchemaVersion
        self.requestID = requestID
        self.destination = destination
        self.metadata = metadata
        self.authoredYAML = authoredYAML
        self.source = source
        self.sourceRoute = sourceRoute
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case destination, metadata, source
        case authoredYAML = "authored_yaml"
        case sourceRoute = "source_route"
    }

    public init(from decoder: Decoder) throws {
        try ResearchAgentStartCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.self
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion)
                == Self.currentSchemaVersion else {
            throw ResearchAgentStartContractError.unsupportedSchemaVersion
        }
        try self.init(
            requestID: container.decode(UUID.self, forKey: .requestID),
            destination: container.decode(
                ResearchAgentAnalysisDestination.self,
                forKey: .destination
            ),
            metadata: container.decode(AnalysisCreationMetadata.self, forKey: .metadata),
            authoredYAML: container.decodeIfPresent(
                AuthoredNoteYAML.self,
                forKey: .authoredYAML
            ),
            source: container.decodeIfPresent(
                ResearchAgentNewAnalysisSource.self,
                forKey: .source
            ),
            sourceRoute: container.decodeIfPresent(
                ResearchAgentSourceRoute.self,
                forKey: .sourceRoute
            )
        )
    }
}

/// Consequential creation input returned by the current preflight. Application
/// resolves the Analyses vault and exact path from the nested intent again
/// before any mutation; optional Settings guidance grants no authority.
public struct ResearchAgentNewAnalysisRequest: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 4

    public let schemaVersion: Int
    public let preflight: ResearchAgentAnalysisCreationPreflightRequest

    public var requestID: UUID { preflight.requestID }
    public var destination: ResearchAgentAnalysisDestination { preflight.destination }
    public var metadata: AnalysisCreationMetadata { preflight.metadata }
    public var authoredYAML: AuthoredNoteYAML? { preflight.authoredYAML }
    public var source: ResearchAgentNewAnalysisSource? { preflight.source }
    public var sourceRoute: ResearchAgentSourceRoute? { preflight.sourceRoute }

    public init(preflight: ResearchAgentAnalysisCreationPreflightRequest) {
        schemaVersion = Self.currentSchemaVersion
        self.preflight = preflight
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case preflight
    }

    public init(from decoder: Decoder) throws {
        try ResearchAgentStartCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.self
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion)
                == Self.currentSchemaVersion else {
            throw ResearchAgentStartContractError.unsupportedSchemaVersion
        }
        self.init(
            preflight: try container.decode(
                ResearchAgentAnalysisCreationPreflightRequest.self,
                forKey: .preflight
            )
        )
    }
}

public enum ResearchAgentAnalysisCreationPreflightStatus: String, Codable,
    Hashable, Sendable
{
    case ready
    case invalidMetadata = "invalid_metadata"
    case pathOccupied = "path_occupied"
    case identityOccupied = "identity_occupied"
    case identitySourceMissingOrTrashed = "identity_source_missing_or_trashed"
    case sourceUnreadable = "source_unreadable"
    case sourceCommittedProjectionPending = "source_committed_projection_pending"
    case runPrepared = "run_prepared"
    case runStale = "run_stale"
    case replayConflict = "replay_conflict"
}

public enum ResearchAgentAnalysisSourceState: String, Codable, Hashable, Sendable {
    case absent
    case present
    case missing
    case inSystemTrash = "in_system_trash"
    case missingOrInSystemTrash = "missing_or_in_system_trash"
    case unreadable
}

public struct ResearchAgentAnalysisTargetState: Codable, Hashable, Sendable {
    public let target: VaultQualifiedNoteID
    public let stableIdentity: UUID?
    public let fingerprint: DocumentFingerprint?
    public let sourceState: ResearchAgentAnalysisSourceState

    public init(
        target: VaultQualifiedNoteID,
        stableIdentity: UUID?,
        fingerprint: DocumentFingerprint?,
        sourceState: ResearchAgentAnalysisSourceState
    ) {
        self.target = target
        self.stableIdentity = stableIdentity
        self.fingerprint = fingerprint
        self.sourceState = sourceState
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case stableIdentity = "stable_identity"
        case fingerprint
        case sourceState = "source_state"
    }
}

public struct ResearchAgentAnalysisCreationPreflight: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let requestID: UUID
    public let analysisVaultID: UUID
    public let sourceType: AnalysisSourceType
    public let applicableFields: [PropertyContract]
    public let preferredFields: [String]
    public let fixedYAMLFields: [String]
    public let targetState: ResearchAgentAnalysisTargetState
    public let status: ResearchAgentAnalysisCreationPreflightStatus
    public let startNewAnalysis: ResearchAgentNewAnalysisRequest?
    public let recovery: AgentOperationRecovery
    public let message: String

    public init(
        request: ResearchAgentAnalysisCreationPreflightRequest,
        analysisVaultID: UUID,
        applicableFields: [PropertyContract],
        preferredFields: [String],
        fixedYAMLFields: [String],
        targetState: ResearchAgentAnalysisTargetState,
        status: ResearchAgentAnalysisCreationPreflightStatus,
        startNewAnalysis: ResearchAgentNewAnalysisRequest? = nil,
        recovery: AgentOperationRecovery,
        message: String
    ) {
        schemaVersion = Self.currentSchemaVersion
        requestID = request.requestID
        self.analysisVaultID = analysisVaultID
        sourceType = request.metadata.sourceType
        self.applicableFields = applicableFields.sorted { $0.canonicalKey < $1.canonicalKey }
        self.preferredFields = preferredFields.sorted()
        self.fixedYAMLFields = fixedYAMLFields.sorted()
        self.targetState = targetState
        self.status = status
        self.startNewAnalysis = startNewAnalysis
        self.recovery = recovery
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case analysisVaultID = "analysis_vault_id"
        case sourceType = "source_type"
        case applicableFields = "applicable_fields"
        case preferredFields = "preferred_fields"
        case fixedYAMLFields = "fixed_yaml_fields"
        case targetState = "target_state"
        case status
        case startNewAnalysis = "start_new_analysis"
        case recovery, message
    }
}

/// Delivery-neutral request for an Agent-originated Run. Scholium resolves the
/// current Note identity, Action Profile, Method, and revision after receiving
/// this request; the request never carries a write grant or source bytes.
public struct ResearchAgentStartRequest: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 6

    public let schemaVersion: Int
    public let actionID: ResearchActionID
    /// Exactly one of `target` and `newAnalysis` is present. The former starts
    /// from an existing stable Note; the latter asks the Application to use the
    /// managed creator before preparing Analyze.
    public let target: VaultQualifiedNoteID?
    public let newAnalysis: ResearchAgentNewAnalysisRequest?
    /// Existing-Analysis-only declaration that the researcher will provide a
    /// local source directly to the external Agent. New creation carries the
    /// same declaration inside its preflight-owned request.
    public let sourceRoute: ResearchAgentSourceRoute?
    public let academicPurpose: String?

    public init(
        actionID: ResearchActionID,
        target: VaultQualifiedNoteID,
        academicPurpose: String? = nil,
        sourceRoute: ResearchAgentSourceRoute? = nil
    ) throws {
        try self.init(
            actionID: actionID,
            target: target,
            newAnalysis: nil,
            sourceRoute: sourceRoute,
            academicPurpose: academicPurpose
        )
    }

    public init(
        actionID: ResearchActionID,
        newAnalysis: ResearchAgentNewAnalysisRequest,
        academicPurpose: String? = nil,
        sourceRoute: ResearchAgentSourceRoute? = nil
    ) throws {
        try self.init(
            actionID: actionID,
            target: nil,
            newAnalysis: newAnalysis,
            sourceRoute: sourceRoute,
            academicPurpose: academicPurpose
        )
    }

    private init(
        actionID: ResearchActionID,
        target: VaultQualifiedNoteID?,
        newAnalysis: ResearchAgentNewAnalysisRequest?,
        sourceRoute: ResearchAgentSourceRoute?,
        academicPurpose: String?
    ) throws {
        let normalizedPurpose = academicPurpose?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard normalizedPurpose == nil || normalizedPurpose?.isEmpty == false,
              normalizedPurpose?.utf8.count ?? 0 <= 16 * 1_024,
              (target == nil) != (newAnalysis == nil),
              newAnalysis == nil || actionID == .analyze,
              sourceRoute == nil || actionID == .analyze,
              sourceRoute == nil || (newAnalysis == nil && target != nil) else {
            throw ResearchAgentStartContractError.invalidRequest
        }
        schemaVersion = Self.currentSchemaVersion
        self.actionID = actionID
        self.target = target
        self.newAnalysis = newAnalysis
        self.sourceRoute = sourceRoute
        self.academicPurpose = normalizedPurpose
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case actionID = "action_id"
        case target
        case newAnalysis = "new_analysis"
        case sourceRoute = "source_route"
        case academicPurpose = "academic_purpose"
    }

    public init(from decoder: Decoder) throws {
        try ResearchAgentStartCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.self
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion)
                == Self.currentSchemaVersion else {
            throw ResearchAgentStartContractError.unsupportedSchemaVersion
        }
        try self.init(
            actionID: container.decode(ResearchActionID.self, forKey: .actionID),
            target: container.decodeIfPresent(
                ResearchAgentStartWireNoteID.self,
                forKey: .target
            )?.value,
            newAnalysis: container.decodeIfPresent(
                ResearchAgentNewAnalysisRequest.self,
                forKey: .newAnalysis
            ),
            sourceRoute: container.decodeIfPresent(
                ResearchAgentSourceRoute.self,
                forKey: .sourceRoute
            ),
            academicPurpose: container.decodeIfPresent(
                String.self,
                forKey: .academicPurpose
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(actionID, forKey: .actionID)
        try container.encodeIfPresent(
            target.map(ResearchAgentStartWireNoteID.init),
            forKey: .target
        )
        try container.encodeIfPresent(newAnalysis, forKey: .newAnalysis)
        try container.encodeIfPresent(sourceRoute, forKey: .sourceRoute)
        try container.encodeIfPresent(academicPurpose, forKey: .academicPurpose)
    }
}

public struct ResearchAgentStartReceipt: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let run: ResearchRunLocator
    public let actionID: ResearchActionID
    public let target: ResearchActionNoteSnapshot
    public let state: ResearchActionRunState
    public let message: String

    public init(
        run: ResearchRunLocator,
        actionID: ResearchActionID,
        target: ResearchActionNoteSnapshot,
        state: ResearchActionRunState,
        message: String
    ) throws {
        let normalizedMessage = message.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedMessage.isEmpty, normalizedMessage.utf8.count <= 1_024 else {
            throw ResearchAgentStartContractError.invalidRequest
        }
        schemaVersion = Self.currentSchemaVersion
        self.run = run
        self.actionID = actionID
        self.target = target
        self.state = state
        self.message = normalizedMessage
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case run, actionID = "action_id", target, state, message
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: CodingKeys.self)
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        guard raw.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw ResearchAgentStartContractError.invalidRequest
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion)
                == Self.currentSchemaVersion else {
            throw ResearchAgentStartContractError.unsupportedSchemaVersion
        }
        try self.init(
            run: container.decode(ResearchRunLocator.self, forKey: .run),
            actionID: container.decode(ResearchActionID.self, forKey: .actionID),
            target: container.decode(ResearchActionNoteSnapshot.self, forKey: .target),
            state: container.decode(ResearchActionRunState.self, forKey: .state),
            message: container.decode(String.self, forKey: .message)
        )
    }
}

public struct ResearchAgentStartedSession: Hashable, Sendable {
    public let receipt: ResearchAgentStartReceipt
    public let credential: ResearchConnectionCredential

    public init(
        receipt: ResearchAgentStartReceipt,
        credential: ResearchConnectionCredential
    ) {
        self.receipt = receipt
        self.credential = credential
    }
}

public enum ResearchAgentStartContractError: LocalizedError, Hashable, Sendable {
    case invalidRequest
    case unsupportedSchemaVersion

    public var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "The Agent-originated Run request is invalid."
        case .unsupportedSchemaVersion:
            "The Agent-originated Run request schema is not current."
        }
    }
}

/// One-use local secret. Wire and protected-storage adapters must explicitly
/// unwrap it at their narrow boundary; the secret is intentionally not
/// generally Codable or printable.
public struct ResearchPairingCode: RawRepresentable, Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible
{
    public let rawValue: String

    public init?(rawValue: String) {
        let compact = rawValue.replacingOccurrences(of: "-", with: "")
        guard compact.utf8.count == 24,
              compact.unicodeScalars.allSatisfy({
                  (50...57).contains($0.value) || (65...90).contains($0.value)
              }) else { return nil }
        self.rawValue = stride(from: 0, to: compact.count, by: 4).map { offset in
            let start = compact.index(compact.startIndex, offsetBy: offset)
            let end = compact.index(start, offsetBy: min(4, compact.count - offset))
            return String(compact[start..<end])
        }.joined(separator: "-")
    }

    public var description: String { "<redacted pairing code>" }
    public var debugDescription: String { description }
}

/// Ephemeral presentation value deliberately copied by the researcher to the
/// selected Agent. The reusable Session credential remains hidden behind the
/// protected local bridge.
public struct ResearchAgentHandoff: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let run: ResearchRunLocator
    public let pairingCode: ResearchPairingCode
    public let expiresAt: Date

    public init(
        run: ResearchRunLocator,
        pairingCode: ResearchPairingCode,
        expiresAt: Date
    ) {
        self.run = run
        self.pairingCode = pairingCode
        self.expiresAt = expiresAt
    }

    public var agentInstructions: String {
        """
        Scholium Run: \(run.rawValue)
        Pairing Code: \(pairingCode.rawValue)

        Agent: use the installed `scholium` CLI yourself. Run `scholium agent pair --run \(run.rawValue)`, enter the Pairing Code above when the command asks through standard input, then run `scholium agent context --run \(run.rawValue)`. Do not ask the researcher to run these commands.
        """
    }

    public var description: String {
        "<redacted Research Agent handoff for run \(run.rawValue)>"
    }

    public var debugDescription: String { description }
}

/// Public, non-secret acknowledgement that an unfinished Run now refuses new
/// Agent operations. Confirmed results, conflicts, and recovery duties remain
/// with the durable Run rather than being hidden by Session cleanup.
public struct ResearchRunEndReceipt: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let run: ResearchRunLocator
    public let ended: Bool
    public let recoveryRetained: Bool
    public let message: String

    public init(
        run: ResearchRunLocator,
        recoveryRetained: Bool,
        message: String
    ) throws {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.utf8.count <= 1_024 else {
            throw ResearchAgentConnectionContractError.invalidRunEndReceipt
        }
        schemaVersion = Self.currentSchemaVersion
        self.run = run
        ended = true
        self.recoveryRetained = recoveryRetained
        self.message = normalized
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case run, ended
        case recoveryRetained = "recovery_retained"
        case message
    }

    public init(from decoder: Decoder) throws {
        try ResearchAgentConnectionCoding.rejectUnknownFields(
            decoder,
            allowed: CodingKeys.self,
            error: .invalidRunEndReceipt
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion)
                == Self.currentSchemaVersion,
              try container.decode(Bool.self, forKey: .ended) else {
            throw ResearchAgentConnectionContractError.invalidRunEndReceipt
        }
        try self.init(
            run: container.decode(ResearchRunLocator.self, forKey: .run),
            recoveryRetained: container.decode(
                Bool.self,
                forKey: .recoveryRetained
            ),
            message: container.decode(String.self, forKey: .message)
        )
    }
}

/// Machine-local credential returned only across the protected socket. The CLI
/// persists it with current-user-only permissions; it must never be printed,
/// placed in an argument, URL, prompt, Research Record, or ordinary log.
public struct ResearchConnectionCredential: Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible
{
    public let sessionID: UUID
    public let secret: String

    public init(sessionID: UUID, secret: String) throws {
        guard (40...256).contains(secret.utf8.count),
              !secret.unicodeScalars.contains(where: { $0.value <= 32 }) else {
            throw ResearchAgentConnectionContractError.invalidCredential
        }
        self.sessionID = sessionID
        self.secret = secret
    }

    public var description: String { "<redacted connection credential>" }
    public var debugDescription: String { description }
}

public struct ResearchRunCapabilityAvailability: Codable, Hashable, Sendable {
    public let search: Bool
    public let read: Bool
    public let relations: Bool
    public let metadata: Bool
    public let records: Bool
    public let researchState: Bool
    public let zotero: Bool
    public let writeInitialObject: Bool
    public let extendWriteSet: Bool
    public let continueResearch: Bool
    public let discussionReply: Bool
    public let discussionFinish: Bool

    public init(
        search: Bool,
        read: Bool,
        relations: Bool,
        metadata: Bool,
        records: Bool,
        researchState: Bool,
        zotero: Bool,
        writeInitialObject: Bool,
        extendWriteSet: Bool,
        continueResearch: Bool = false,
        discussionReply: Bool = false,
        discussionFinish: Bool = false
    ) {
        self.search = search
        self.read = read
        self.relations = relations
        self.metadata = metadata
        self.records = records
        self.researchState = researchState
        self.zotero = zotero
        self.writeInitialObject = writeInitialObject
        self.extendWriteSet = extendWriteSet
        self.continueResearch = continueResearch
        self.discussionReply = discussionReply
        self.discussionFinish = discussionFinish
    }
}

public struct ResearchRunBrief: Codable, Hashable, Sendable {
    public let run: ResearchRunLocator
    public let actionID: ResearchActionID
    public let state: ResearchActionRunState
    public let initialObjectTitle: String
    public let initialObjectRole: ResearchActionTargetRole
    public let academicPurpose: String?
    public let capabilities: ResearchRunCapabilityAvailability

    public init(
        run: ResearchRunLocator,
        actionID: ResearchActionID,
        state: ResearchActionRunState,
        initialObjectTitle: String,
        initialObjectRole: ResearchActionTargetRole,
        academicPurpose: String?,
        capabilities: ResearchRunCapabilityAvailability
    ) {
        self.run = run
        self.actionID = actionID
        self.state = state
        self.initialObjectTitle = initialObjectTitle
        self.initialObjectRole = initialObjectRole
        self.academicPurpose = academicPurpose
        self.capabilities = capabilities
    }
}

public struct ResearchMethodContext: Codable, Hashable, Sendable {
    public let displayName: String
    public let primaryMarkdown: String
    public let practices: [ResearchPracticeSnapshot]
    /// Delivered only after authentication. Scholium records the selected
    /// folder path but does not enumerate, snapshot, or own its contents.
    public let skillFolderPath: String?

    public init(snapshot: ResearchMethodSnapshot) {
        displayName = snapshot.registration.displayName
        primaryMarkdown = snapshot.primaryMarkdownSource
        practices = snapshot.practices
        skillFolderPath = snapshot.skillFolderPath
    }
}

/// Protected, release-managed instructions for the optional Zotero adapter.
/// Delivery explains how to use an already-authorized integration; it grants
/// no capability, transport, library access, or write authority.
public struct ResearchZoteroIntegrationAdapter: Codable, Hashable, Sendable {
    public let skillMarkdown: String
    public let capabilityContractMarkdown: String

    public init(
        skillMarkdown: String,
        capabilityContractMarkdown: String
    ) throws {
        guard Self.isValid(skillMarkdown),
              Self.isValid(capabilityContractMarkdown) else {
            throw ResearchAgentConnectionContractError.invalidHandoff
        }
        self.skillMarkdown = skillMarkdown
        self.capabilityContractMarkdown = capabilityContractMarkdown
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case skillMarkdown = "skill_markdown"
        case capabilityContractMarkdown = "capability_contract_markdown"
    }

    public init(from decoder: Decoder) throws {
        try ResearchAgentConnectionCoding.rejectUnknownFields(
            decoder,
            allowed: CodingKeys.self
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            skillMarkdown: container.decode(String.self, forKey: .skillMarkdown),
            capabilityContractMarkdown: container.decode(
                String.self,
                forKey: .capabilityContractMarkdown
            )
        )
    }

    private static func isValid(_ markdown: String) -> Bool {
        !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && markdown.utf8.count <= 1_048_576
    }
}

/// Exact read-only Fidelity obligations delivered only inside an authenticated
/// Run context. `requiredUnavailableChecks` is Application-established: the
/// Agent must not convert authored Note metadata into missing source evidence.
public struct ResearchFidelityRunContract: Codable, Hashable, Sendable {
    public let checks: Set<FidelityCheck>
    /// Exact immutable audit objects. These values are read-only context, not
    /// authorization tokens, and the Agent never echoes them in its Result.
    public let targets: [ResearchFunctionTarget]
    public let materials: [ResearchFunctionMaterial]
    public let scope: ResearchFunctionScope?
    /// Present only when Scholium can reopen one formal revision-bound source
    /// owner for this audit. Authored Note metadata is never promoted here.
    public let sourceReference: ResearchSourceReference?
    public let requiredUnavailableChecks: Set<FidelityCheck>
    public let evidenceLimitation: String?
    /// Ready-to-send exact-read requests derived by Scholium. They let a fresh
    /// Agent inspect the complete frozen boundary without reconstructing query
    /// JSON or remembering a parent conversation.
    public let inspectionRequests: [ResearchContextRequest]

    public init(
        checks: Set<FidelityCheck>,
        targets: [ResearchFunctionTarget],
        materials: [ResearchFunctionMaterial],
        scope: ResearchFunctionScope?,
        sourceReference: ResearchSourceReference?,
        requiredUnavailableChecks: Set<FidelityCheck> = [],
        evidenceLimitation: String? = nil,
        inspectionRequests: [ResearchContextRequest]
    ) throws {
        let limitation = evidenceLimitation?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let targetIDs = targets.map(\.noteID)
        let targetNotes = targets.map(\.note)
        let materialIDs = materials.map(\.noteID)
        let materialNotes = materials.map(\.note)
        let inspectionClauses = inspectionRequests.flatMap(\.clauses)
        let expectedReadKeys = Set((targets.map {
            "\($0.note.vaultID.uuidString.lowercased()):\($0.note.relativePath):\($0.fingerprint.sha256)"
        } + materials.map {
            "\($0.note.vaultID.uuidString.lowercased()):\($0.note.relativePath):\($0.fingerprint.sha256)"
        }))
        let deliveredReadKeys: Set<String> = Set(
            inspectionClauses.compactMap { clause -> String? in
            guard clause.kind == .readNote,
                  let note = clause.note,
                  let fingerprint = clause.expectedFingerprint else {
                return nil
            }
            return "\(note.vaultID.uuidString.lowercased()):\(note.relativePath):\(fingerprint.sha256)"
            }
        )
        guard !checks.isEmpty,
              !targets.isEmpty,
              targets.count <= 64,
              Set(targetIDs).count == targetIDs.count,
              Set(targetNotes).count == targetNotes.count,
              targets.allSatisfy({ !$0.title.isEmpty }),
              materials.count <= 64,
              Set(materialIDs).count == materialIDs.count,
              Set(materialNotes).count == materialNotes.count,
              Set(targetIDs).isDisjoint(with: materialIDs),
              materials.allSatisfy({ !$0.title.isEmpty }),
              requiredUnavailableChecks.isSubset(of: checks),
              requiredUnavailableChecks.isEmpty == (limitation == nil),
              limitation?.isEmpty != true,
              limitation?.utf8.count ?? 0 <= 2_048,
              !inspectionRequests.isEmpty,
              inspectionRequests.count <= 32,
              !inspectionClauses.isEmpty,
              inspectionClauses.allSatisfy({
                  $0.kind == .readNote || $0.kind == .inspectMaterials
              }),
              deliveredReadKeys == expectedReadKeys else {
            throw ResearchAgentConnectionContractError.invalidHandoff
        }
        if let scope, scope.kind == .passage {
            guard targets.count == 1,
                  scope.selection?.fingerprint == targets[0].fingerprint else {
                throw ResearchAgentConnectionContractError.invalidHandoff
            }
        }
        self.checks = checks
        self.targets = targets.sorted {
            if $0.note.vaultID != $1.note.vaultID {
                return $0.note.vaultID.uuidString < $1.note.vaultID.uuidString
            }
            return $0.note.relativePath < $1.note.relativePath
        }
        self.materials = materials.sorted {
            if $0.note.vaultID != $1.note.vaultID {
                return $0.note.vaultID.uuidString < $1.note.vaultID.uuidString
            }
            return $0.note.relativePath < $1.note.relativePath
        }
        self.scope = scope
        self.sourceReference = sourceReference
        self.requiredUnavailableChecks = requiredUnavailableChecks
        self.evidenceLimitation = limitation
        self.inspectionRequests = inspectionRequests
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case checks, targets, materials, scope
        case sourceReference = "source_reference"
        case requiredUnavailableChecks = "required_unavailable_checks"
        case evidenceLimitation = "evidence_limitation"
        case inspectionRequests = "inspection_requests"
    }

    public init(from decoder: Decoder) throws {
        try ResearchAgentConnectionCoding.rejectUnknownFields(
            decoder,
            allowed: CodingKeys.self
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            checks: container.decode(Set<FidelityCheck>.self, forKey: .checks),
            targets: container.decode(
                [ResearchFunctionTarget].self,
                forKey: .targets
            ),
            materials: container.decode(
                [ResearchFunctionMaterial].self,
                forKey: .materials
            ),
            scope: container.decodeIfPresent(
                ResearchFunctionScope.self,
                forKey: .scope
            ),
            sourceReference: container.decodeIfPresent(
                ResearchSourceReference.self,
                forKey: .sourceReference
            ),
            requiredUnavailableChecks: container.decode(
                Set<FidelityCheck>.self,
                forKey: .requiredUnavailableChecks
            ),
            evidenceLimitation: container.decodeIfPresent(
                String.self,
                forKey: .evidenceLimitation
            ),
            inspectionRequests: container.decode(
                [ResearchContextRequest].self,
                forKey: .inspectionRequests
            )
        )
    }
}

public struct ResearchAuthenticatedRunContext: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 11

    public let schemaVersion: Int
    /// Present exactly once for a Connection Session, never on ordinary reload.
    public let coreProtocol: String?
    public let brief: ResearchRunBrief
    public let method: ResearchMethodContext
    /// Present only for an eligible Analysis Run whose immutable Action
    /// snapshot contains Zotero bibliographic context.
    public let zoteroIntegrationAdapter: ResearchZoteroIntegrationAdapter?
    public let resultContract: ResearchResultContract
    /// Present only for Check Fidelity. It names the exact checks and any
    /// check that must remain unavailable because Scholium lacks formal source
    /// evidence for this Run.
    public let fidelityContract: ResearchFidelityRunContract?
    /// Present only for a Discuss Run. It describes the academic response
    /// shape; the authenticated Session, not this value, authorizes the
    /// idempotent Agent turn.
    public let discussionResponseContract: DialogueResponseContract?
    /// Current, capability-free view of the Run-local bounded write set. The
    /// Application retains Note identity, expected revisions, change evidence,
    /// and one-use capabilities; the Agent receives only the exact selectors
    /// and states needed to address the protected write route.
    public let boundedWriteSet: [ResearchBoundedWriteSetViewEntry]
    public let continuationHandoff: ResearchContinuationHandoffContext?
    /// Shell-safe, typed next operations. Fidelity includes a complete
    /// illustrative Result JSON shape so the Agent supplies judgments rather
    /// than reverse-engineering the wire contract.
    public let nextActions: [AgentCommandAction]

    public init(
        coreProtocol: String?,
        brief: ResearchRunBrief,
        method: ResearchMethodContext,
        zoteroIntegrationAdapter: ResearchZoteroIntegrationAdapter? = nil,
        resultContract: ResearchResultContract,
        fidelityContract: ResearchFidelityRunContract? = nil,
        boundedWriteSet: [ResearchBoundedWriteSetViewEntry],
        continuationHandoff: ResearchContinuationHandoffContext? = nil,
        discussionResponseContract: DialogueResponseContract? = nil,
        nextActions: [AgentCommandAction] = []
    ) throws {
        guard zoteroIntegrationAdapter == nil
                || (brief.initialObjectRole == .analysis
                    && brief.capabilities.zotero) else {
            throw ResearchAgentConnectionContractError.invalidHandoff
        }
        schemaVersion = Self.currentSchemaVersion
        self.coreProtocol = coreProtocol
        self.brief = brief
        self.method = method
        self.zoteroIntegrationAdapter = zoteroIntegrationAdapter
        self.resultContract = resultContract
        guard (fidelityContract != nil) == (brief.actionID == .checkFidelity) else {
            throw ResearchAgentConnectionContractError.invalidHandoff
        }
        self.fidelityContract = fidelityContract
        guard discussionResponseContract == nil
                || brief.capabilities.discussionReply else {
            throw ResearchAgentConnectionContractError.invalidHandoff
        }
        guard discussionResponseContract == nil
                || brief.capabilities.discussionFinish else {
            throw ResearchAgentConnectionContractError.invalidHandoff
        }
        self.discussionResponseContract = discussionResponseContract
        self.boundedWriteSet = boundedWriteSet.sorted {
            if $0.role != $1.role { return $0.role.rawValue < $1.role.rawValue }
            return $0.relativePath < $1.relativePath
        }
        self.continuationHandoff = continuationHandoff
        self.nextActions = nextActions
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case coreProtocol = "core_protocol"
        case brief, method
        case zoteroIntegrationAdapter = "zotero_integration_adapter"
        case resultContract = "result_contract"
        case fidelityContract = "fidelity_contract"
        case discussionResponseContract = "discussion_response_contract"
        case boundedWriteSet = "bounded_write_set"
        case continuationHandoff = "continuation_handoff"
        case nextActions = "next_actions"
    }

    public init(from decoder: Decoder) throws {
        try ResearchAgentConnectionCoding.rejectUnknownFields(
            decoder,
            allowed: CodingKeys.self
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion)
                == Self.currentSchemaVersion else {
            throw ResearchAgentConnectionContractError.unsupportedSchemaVersion
        }
        let boundedWriteSet = try container.decode(
            [ResearchBoundedWriteSetViewEntry].self,
            forKey: .boundedWriteSet
        )
        guard boundedWriteSet.count <= ResearchBoundedWriteSet.maximumEntriesPerRun,
              Set(boundedWriteSet.map(\.id)).count == boundedWriteSet.count else {
            throw ResearchAgentConnectionContractError.invalidHandoff
        }
        try self.init(
            coreProtocol: try container.decodeIfPresent(
                String.self,
                forKey: .coreProtocol
            ),
            brief: try container.decode(ResearchRunBrief.self, forKey: .brief),
            method: try container.decode(ResearchMethodContext.self, forKey: .method),
            zoteroIntegrationAdapter: try container.decodeIfPresent(
                ResearchZoteroIntegrationAdapter.self,
                forKey: .zoteroIntegrationAdapter
            ),
            resultContract: try container.decode(
                ResearchResultContract.self,
                forKey: .resultContract
            ),
            fidelityContract: try container.decodeIfPresent(
                ResearchFidelityRunContract.self,
                forKey: .fidelityContract
            ),
            boundedWriteSet: boundedWriteSet,
            continuationHandoff: try container.decodeIfPresent(
                ResearchContinuationHandoffContext.self,
                forKey: .continuationHandoff
            ),
            discussionResponseContract: try container.decodeIfPresent(
                DialogueResponseContract.self,
                forKey: .discussionResponseContract
            ),
            nextActions: try container.decode(
                [AgentCommandAction].self,
                forKey: .nextActions
            )
        )
    }
}

public enum ResearchAgentConnectionContractError: LocalizedError, Hashable, Sendable {
    case invalidCredential
    case invalidHandoff
    case invalidRunEndReceipt
    case unsupportedSchemaVersion

    public var errorDescription: String? {
        switch self {
        case .invalidCredential: "The local Connection Session credential is invalid."
        case .invalidHandoff: "The local Agent handoff is invalid."
        case .invalidRunEndReceipt: "The Research Run end receipt is invalid."
        case .unsupportedSchemaVersion:
            "The authenticated Research Run context schema is not current."
        }
    }
}

private enum ResearchAgentConnectionCoding {
    static func rejectUnknownFields<Key: CodingKey & CaseIterable>(
        _ decoder: Decoder,
        allowed: Key.Type,
        error: ResearchAgentConnectionContractError = .invalidHandoff
    ) throws {
        let raw = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowedNames = Set(Key.allCases.map(\.stringValue))
        guard raw.allKeys.allSatisfy({ allowedNames.contains($0.stringValue) }) else {
            throw error
        }
    }

    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

private enum ResearchAgentStartCoding {
    static func rejectUnknownFields<Key: CodingKey & CaseIterable>(
        in decoder: Decoder,
        allowed: Key.Type
    ) throws {
        let raw = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowedNames = Set(Key.allCases.map(\.stringValue))
        guard raw.allKeys.allSatisfy({ allowedNames.contains($0.stringValue) }) else {
            throw ResearchAgentStartContractError.invalidRequest
        }
    }

    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}
