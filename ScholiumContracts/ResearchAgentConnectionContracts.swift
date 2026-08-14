import Foundation

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
    public let properties: Bool
    public let records: Bool
    public let researchState: Bool
    public let zotero: Bool
    public let writeInitialObject: Bool
    public let extendWriteSet: Bool
    public let continueResearch: Bool

    public init(
        search: Bool,
        read: Bool,
        relations: Bool,
        properties: Bool,
        records: Bool,
        researchState: Bool,
        zotero: Bool,
        writeInitialObject: Bool,
        extendWriteSet: Bool,
        continueResearch: Bool = false
    ) {
        self.search = search
        self.read = read
        self.relations = relations
        self.properties = properties
        self.records = records
        self.researchState = researchState
        self.zotero = zotero
        self.writeInitialObject = writeInitialObject
        self.extendWriteSet = extendWriteSet
        self.continueResearch = continueResearch
    }
}

public struct ResearchRunBrief: Codable, Hashable, Sendable {
    public let run: ResearchRunLocator
    public let actionID: ResearchActionID
    public let initialObjectTitle: String
    public let initialObjectRole: ResearchActionTargetRole
    public let academicPurpose: String?
    public let capabilities: ResearchRunCapabilityAvailability

    public init(
        run: ResearchRunLocator,
        actionID: ResearchActionID,
        initialObjectTitle: String,
        initialObjectRole: ResearchActionTargetRole,
        academicPurpose: String?,
        capabilities: ResearchRunCapabilityAvailability
    ) {
        self.run = run
        self.actionID = actionID
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

public struct ResearchAuthenticatedRunContext: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 6

    public let schemaVersion: Int
    /// Present exactly once for a Connection Session, never on ordinary reload.
    public let coreProtocol: String?
    public let brief: ResearchRunBrief
    public let method: ResearchMethodContext
    /// Present only for an eligible Analysis Run whose immutable Action
    /// snapshot contains Zotero bibliographic context.
    public let zoteroIntegrationAdapter: ResearchZoteroIntegrationAdapter?
    public let resultContract: ResearchResultContract
    /// Current, capability-free view of the Run-local bounded write set. The
    /// Application retains Note identity, expected revisions, checkpoints,
    /// and one-use capabilities; the Agent receives only the exact selectors
    /// and states needed to address the protected write route.
    public let boundedWriteSet: [ResearchBoundedWriteSetViewEntry]
    public let continuationHandoff: ResearchContinuationHandoffContext?

    public init(
        coreProtocol: String?,
        brief: ResearchRunBrief,
        method: ResearchMethodContext,
        zoteroIntegrationAdapter: ResearchZoteroIntegrationAdapter? = nil,
        resultContract: ResearchResultContract,
        boundedWriteSet: [ResearchBoundedWriteSetViewEntry],
        continuationHandoff: ResearchContinuationHandoffContext? = nil
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
        self.boundedWriteSet = boundedWriteSet.sorted {
            if $0.role != $1.role { return $0.role.rawValue < $1.role.rawValue }
            return $0.relativePath < $1.relativePath
        }
        self.continuationHandoff = continuationHandoff
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case coreProtocol = "core_protocol"
        case brief, method
        case zoteroIntegrationAdapter = "zotero_integration_adapter"
        case resultContract = "result_contract"
        case boundedWriteSet = "bounded_write_set"
        case continuationHandoff = "continuation_handoff"
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
            boundedWriteSet: boundedWriteSet,
            continuationHandoff: try container.decodeIfPresent(
                ResearchContinuationHandoffContext.self,
                forKey: .continuationHandoff
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
