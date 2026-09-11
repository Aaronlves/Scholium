import Foundation
import ScholiumContracts

/// Validate runtime history boundaries before projecting a branch into local public history.
public enum CodexChatBranch {
    public static func turnIDs(in result: MCPJSONValue, threadID: String, through turnID: String) throws -> [String] {
        let turns = try CodexChatTranscript.history(result, threadID: threadID)
        var ids: [String] = []
        for turn in turns {
            guard turn.status != .inProgress else { throw CodexConnectionError.invalidMessage }
            ids.append(turn.id)
            if turn.id == turnID { return ids }
        }
        throw CodexConnectionError.invalidMessage
    }

    public static func project(
        source: AgentChatConversation, threadID: String,
        retaining turnIDs: [String], boundary: String,
        position: AgentChatBranchOrigin.Position
    ) throws -> AgentChatConversation {
        let messages = try retainedMessages(source: source, through: turnIDs)
        guard source.threadID != threadID, !threadID.isEmpty,
            source.messages.contains(where: { $0.turnID == boundary }),
            position == .through ? turnIDs.last == boundary : !turnIDs.contains(boundary)
        else { throw CodexConnectionError.invalidMessage }
        var branch = AgentChatConversation(triptychID: source.triptychID)
        branch.threadID = threadID
        branch.permission = source.permission
        branch.preferences = source.preferences
        branch.branchOrigin = .init(conversationID: source.id, turnID: boundary, position: position)
        branch.messages = messages
        return branch
    }

    public static func retainedMessages(source: AgentChatConversation, through turnIDs: [String]) throws -> [AgentChatMessage] {
        guard !turnIDs.contains(where: \.isEmpty), Set(turnIDs).count == turnIDs.count,
            turnIDs.allSatisfy({ id in source.messages.contains(where: { $0.turnID == id }) }),
            source.messages.allSatisfy({ $0.turnID?.isEmpty == false })
        else { throw CodexConnectionError.invalidMessage }
        // Unattributed public content cannot be silently omitted from a purported history copy.
        let scope = Set(turnIDs)
        return source.messages.filter { $0.turnID.map(scope.contains) == true }
    }

    /// Fork confirmation must cover exactly the requested prefix, including an empty one.
    public static func confirm(
        _ result: MCPJSONValue, threadID: String,
        expected turnIDs: [String]
    ) throws {
        let turns = try CodexChatTranscript.history(result, threadID: threadID)
        guard turns.map(\.id) == turnIDs, turns.allSatisfy({ $0.status != .inProgress }) else {
            throw CodexConnectionError.invalidMessage
        }
    }
}
