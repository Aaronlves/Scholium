import Foundation
import ScholiumContracts

/// Read-only child history. Parentage is runtime metadata, never a prompt or path heuristic.
public enum CodexChatChildReader {
  public typealias Request = @Sendable (String, [String: MCPJSONValue]) async throws -> MCPJSONValue

  public static func prepending(
    _ page: AgentChatChildHistory.Page,
    to snapshot: AgentChatChildHistory.Snapshot
  ) throws -> AgentChatChildHistory.Snapshot {
    guard Set(page.turns.map(\.id)).isDisjoint(with: snapshot.page.turns.map(\.id)) else {
      throw CodexConnectionError.invalidMessage
    }
    return .init(
      metadata: snapshot.metadata, page: .init(turns: page.turns + snapshot.page.turns, nextCursor: page.nextCursor))
  }

  public static func load(childID: String, parentID: String, request: Request) async throws
    -> AgentChatChildHistory.Snapshot
  {
    let child = try await verify(childID: childID, parentID: parentID, request: request)
    if child.isPaginated {
      return try await .init(metadata: child, page: older(childID: childID, cursor: nil, request: request))
    }
    let value = try await request("thread/read", ["threadId": .string(childID), "includeTurns": .bool(true)])
    let current = try metadata(value, expectedID: childID)
    guard current.parentID == child.parentID, !current.isPaginated,
      let turns = value.objectValue?["thread"]?.objectValue?["turns"]?.arrayValue
    else { throw CodexConnectionError.invalidMessage }
    return try .init(metadata: current, page: .init(turns: CodexChatTranscript.turns(turns, threadID: childID), nextCursor: nil))
  }

  public static func verify(childID: String, parentID: String, request: Request) async throws
    -> AgentChatChildHistory.Metadata
  {
    guard !childID.isEmpty, !parentID.isEmpty, childID != parentID else { throw CodexConnectionError.invalidMessage }
    var visited: Set<String> = [childID]
    let child = try await metadata(request("thread/read", ["threadId": .string(childID)]), expectedID: childID)
    var current = child.parentID
    while current != parentID {
      try Task.checkCancellation()
      guard visited.count < 64, visited.insert(current).inserted else { throw CodexConnectionError.invalidMessage }
      current = try await metadata(request("thread/read", ["threadId": .string(current)]), expectedID: current).parentID
    }
    return child
  }

  public static func older(childID: String, cursor: String?, request: Request) async throws
    -> AgentChatChildHistory.Page
  {
    var params: [String: MCPJSONValue] = [
      "threadId": .string(childID), "limit": .integer(25),
      "sortDirection": .string("desc"), "itemsView": .string("full"),
    ]
    if let cursor { params["cursor"] = .string(cursor) }
    let value = try await request("thread/turns/list", params)
    guard let object = value.objectValue, let data = object["data"]?.arrayValue,
      let next = object["nextCursor"], next == .null || next.stringValue?.isEmpty == false
    else { throw CodexConnectionError.invalidMessage }
    return try .init(turns: CodexChatTranscript.turns(data, threadID: childID).reversed(), nextCursor: next.stringValue)
  }

  private static func metadata(_ value: MCPJSONValue, expectedID: String) throws -> AgentChatChildHistory.Metadata {
    guard let object = value.objectValue?["thread"]?.objectValue,
      object["id"]?.stringValue == expectedID, let parent = object["parentThreadId"]?.stringValue, !parent.isEmpty,
      let state = object["status"]?.objectValue,
      let status = state["type"]?.stringValue.flatMap(AgentChatChildHistory.Metadata.Status.init(rawValue:))
    else { throw CodexConnectionError.invalidMessage }
    let history = object["historyMode"]?.stringValue ?? "legacy"
    guard ["legacy", "paginated"].contains(history) else { throw CodexConnectionError.invalidMessage }
    var flags: [String] = []
    if status == .active {
      guard let values = state["activeFlags"]?.arrayValue else { throw CodexConnectionError.invalidMessage }
      flags = try values.map { value in
        guard let flag = value.stringValue, ["waitingOnApproval", "waitingOnUserInput"].contains(flag) else {
          throw CodexConnectionError.invalidMessage
        }
        return flag
      }
    }
    return .init(
      id: expectedID, parentID: parent,
      name: object["agentNickname"]?.stringValue ?? object["name"]?.stringValue,
      role: object["agentRole"]?.stringValue, status: status, activeFlags: flags, isPaginated: history == "paginated")
  }

}
