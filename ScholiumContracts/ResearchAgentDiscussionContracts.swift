import Foundation

/// One idempotent Agent-authored turn in the active Discussion owned by the
/// authenticated Run. The statement ID is supplied by the Agent so an
/// outcome-unknown retry can converge on the same portable statement.
public struct ResearchAgentDiscussionReplyRequest: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let statementID: UUID
    public let attribution: String
    public let text: String

    public init(
        statementID: UUID,
        attribution: String,
        text: String
    ) throws {
        let attribution = attribution.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try PortableResearchStatement(
                id: statementID,
                author: .agent,
                kind: .discussionTurn,
                attribution: attribution,
                text: text
            )
        } catch {
            throw ResearchAgentDiscussionReplyContractError.invalidReply
        }
        schemaVersion = Self.currentSchemaVersion
        self.statementID = statementID
        self.attribution = attribution
        self.text = text
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case statementID = "statement_id"
        case attribution
        case text
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        guard raw.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw ResearchAgentDiscussionReplyContractError.invalidReply
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion)
                == Self.currentSchemaVersion else {
            throw ResearchAgentDiscussionReplyContractError.unsupportedSchemaVersion
        }
        try self.init(
            statementID: container.decode(UUID.self, forKey: .statementID),
            attribution: container.decode(String.self, forKey: .attribution),
            text: container.decode(String.self, forKey: .text)
        )
    }
}

public enum ResearchAgentDiscussionReplyState: String, Codable, Hashable,
    Sendable
{
    case recorded
    case alreadyRecorded = "already_recorded"
}

/// Minimal acknowledgement for a key-authorized Discussion turn. The
/// Discussion and its statements remain the portable scholarly owner; this
/// receipt carries only the idempotent operation outcome.
public struct ResearchAgentDiscussionReplyReceipt: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let run: ResearchRunLocator
    public let discussionID: UUID
    public let statementID: UUID
    public let state: ResearchAgentDiscussionReplyState
    public let message: String

    public init(
        run: ResearchRunLocator,
        discussionID: UUID,
        statementID: UUID,
        state: ResearchAgentDiscussionReplyState,
        message: String
    ) throws {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty,
              message.utf8.count <= 1_024,
              !message.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else {
            throw ResearchAgentDiscussionReplyContractError.invalidReply
        }
        schemaVersion = Self.currentSchemaVersion
        self.run = run
        self.discussionID = discussionID
        self.statementID = statementID
        self.state = state
        self.message = message
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case run
        case discussionID = "discussion_id"
        case statementID = "statement_id"
        case state
        case message
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        guard raw.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw ResearchAgentDiscussionReplyContractError.invalidReply
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion)
                == Self.currentSchemaVersion else {
            throw ResearchAgentDiscussionReplyContractError.unsupportedSchemaVersion
        }
        try self.init(
            run: container.decode(ResearchRunLocator.self, forKey: .run),
            discussionID: container.decode(UUID.self, forKey: .discussionID),
            statementID: container.decode(UUID.self, forKey: .statementID),
            state: container.decode(
                ResearchAgentDiscussionReplyState.self,
                forKey: .state
            ),
            message: container.decode(String.self, forKey: .message)
        )
    }
}

/// Minimal acknowledgement that the authenticated Agent finished the active
/// Discuss Run after at least one durable attributed Agent turn. The portable
/// Discussion and resulting Record remain the scholarly owners.
public struct ResearchAgentDiscussionFinishReceipt: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let run: ResearchRunLocator
    public let discussionID: UUID
    public let finished: Bool
    public let recordFormed: Bool
    public let message: String

    public init(
        run: ResearchRunLocator,
        discussionID: UUID,
        message: String
    ) throws {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty,
              message.utf8.count <= 1_024,
              !message.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else {
            throw ResearchAgentDiscussionFinishContractError.invalidReceipt
        }
        schemaVersion = Self.currentSchemaVersion
        self.run = run
        self.discussionID = discussionID
        finished = true
        recordFormed = true
        self.message = message
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case run
        case discussionID = "discussion_id"
        case finished
        case recordFormed = "record_formed"
        case message
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        guard raw.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw ResearchAgentDiscussionFinishContractError.invalidReceipt
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion)
                == Self.currentSchemaVersion,
              try container.decode(Bool.self, forKey: .finished),
              try container.decode(Bool.self, forKey: .recordFormed) else {
            throw ResearchAgentDiscussionFinishContractError.invalidReceipt
        }
        try self.init(
            run: container.decode(ResearchRunLocator.self, forKey: .run),
            discussionID: container.decode(UUID.self, forKey: .discussionID),
            message: container.decode(String.self, forKey: .message)
        )
    }
}

public enum ResearchAgentDiscussionFinishContractError: LocalizedError,
    Hashable, Sendable
{
    case invalidReceipt

    public var errorDescription: String? {
        "The Agent Discussion finish receipt is invalid."
    }
}

public enum ResearchAgentDiscussionReplyContractError: LocalizedError,
    Hashable, Sendable
{
    case unsupportedSchemaVersion
    case invalidReply

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion:
            "The Agent Discussion reply schema version is unsupported."
        case .invalidReply:
            "The Agent Discussion reply does not match its bounded contract."
        }
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}
