import Foundation
import ScholiumContracts

/// Opaque, transient operation context. Only Application codecs interpret its wire fields.
public struct CodexChatOperationContext: Sendable {
  let value: MCPJSONValue
  public init(_ value: MCPJSONValue) { self.value = value }


  public func toolQuestion() throws -> (identity: String, arguments: MCPJSONValue?)? {
    guard let item = value.objectValue, item["type"]?.stringValue == "mcpToolCall" else { return nil }
    guard let server = item["server"]?.stringValue, !server.isEmpty,
      let tool = item["tool"]?.stringValue, !tool.isEmpty else { throw CodexConnectionError.invalidMessage }
    return (server + " · " + tool, item["arguments"])
  }
}

/// One decoder for public live events and complete or paginated history.
public enum CodexChatTranscript {
  public struct Event: Sendable {
    public enum Content: Sendable {
      case turnStarted(AgentChatTranscript.Turn)
      case turnCompleted(AgentChatTranscript.Turn)
      case item(AgentChatTranscript.Item, completed: Bool, context: CodexChatOperationContext?)
      case assistantDelta(itemID: String, text: String)
      case activityDelta(itemID: String, text: String)
      case plan(AgentChatPlan)
      case contextUsage(AgentChatContextUsage)
    }
    public let threadID: String
    public let turnID: String?
    public let content: Content
  }

  public static func event(_ value: [String: MCPJSONValue]) throws -> Event? {
    guard let method = value["method"]?.stringValue,
      ["turn/started", "turn/completed", "item/started", "item/completed",
       "item/agentMessage/delta", "item/commandExecution/outputDelta", "item/mcpToolCall/progress",
       "turn/plan/updated", "thread/tokenUsage/updated"].contains(method) else { return nil }
    guard let params = value["params"]?.objectValue else { throw CodexConnectionError.invalidMessage }
    let threadID = try identifier(params["threadId"])
    let turnID = try optionalIdentifier(params["turnId"])
    let content: Event.Content
    switch method {
    case "turn/started", "turn/completed":
      let turn = try turn(params["turn"], threadID: threadID)
      guard method == "turn/started" ? turn.status == .inProgress : turn.status != .inProgress else {
        throw CodexConnectionError.invalidMessage
      }
      content = method == "turn/started" ? .turnStarted(turn) : .turnCompleted(turn)
    case "item/started", "item/completed":
      guard let object = params["item"]?.objectValue else { throw CodexConnectionError.invalidMessage }
      guard let item = try item(object, completed: method == "item/completed", threadID: threadID) else { return nil }
      let context: CodexChatOperationContext?
      if case .activity = item.content { context = .init(.object(object)) } else { context = nil }
      content = .item(item, completed: method == "item/completed", context: context)
    case "item/agentMessage/delta":
      guard let text = params["delta"]?.stringValue else { throw CodexConnectionError.invalidMessage }
      content = .assistantDelta(itemID: try identifier(params["itemId"]), text: text)
    case "item/commandExecution/outputDelta", "item/mcpToolCall/progress":
      guard let text = params["delta"]?.stringValue ?? params["message"]?.stringValue else {
        throw CodexConnectionError.invalidMessage
      }
      content = .activityDelta(itemID: try identifier(params["itemId"]), text: text)
    case "turn/plan/updated":
      guard let plan = CodexChatCapabilities.plan(params) else { throw CodexConnectionError.invalidMessage }
      content = .plan(plan)
    default:
      guard let usage = CodexChatCapabilities.contextUsage(params) else { throw CodexConnectionError.invalidMessage }
      content = .contextUsage(usage)
    }
    return .init(threadID: threadID, turnID: turnID, content: content)
  }

  public static func history(_ value: MCPJSONValue, threadID: String,
    delegationOrigins: [String: String] = [:]) throws -> [AgentChatTranscript.Turn] {
    guard let thread = value.objectValue?["thread"]?.objectValue,
      thread["id"]?.stringValue == threadID,
      let values = thread["turns"]?.arrayValue else { throw CodexConnectionError.invalidMessage }
    // Storage mode does not describe response coverage: includeTurns may return
    // full items for a paginated thread. Validate the payload, not that mode label.
    return try turns(values, threadID: threadID, delegationOrigins: delegationOrigins)
  }

  public static func turns(_ values: [MCPJSONValue], threadID: String,
    delegationOrigins: [String: String] = [:]) throws -> [AgentChatTranscript.Turn] {
    var seen: Set<String> = []
    return try values.map {
      let turn = try turn($0, threadID: threadID, delegationOrigins: delegationOrigins, requiresFullItems: true)
      guard seen.insert(turn.id).inserted else { throw CodexConnectionError.invalidMessage }
      return turn
    }
  }

  public static func turn(_ value: MCPJSONValue?, threadID: String,
    delegationOrigins: [String: String] = [:], requiresFullItems: Bool = false) throws -> AgentChatTranscript.Turn {
    guard let object = value?.objectValue,
      let status = object["status"]?.stringValue.flatMap(AgentChatTranscript.Turn.Status.init(rawValue:)),
      let values = object["items"]?.arrayValue else { throw CodexConnectionError.invalidMessage }
    let id = try identifier(object["id"])
    let coverage = object["itemsView"]?.stringValue ?? "full"
    guard ["full", "summary", "notLoaded"].contains(coverage),
      !requiresFullItems || coverage == "full" else { throw CodexConnectionError.invalidMessage }
    let error = object["error"]?.objectValue?["message"]?.stringValue
    // Optional display metadata must not prevent delivery of otherwise valid prose.
    func timestamp(_ key: String) -> Date? {
      guard let seconds = object[key]?.intValue, seconds >= 0, seconds <= 253_402_300_799 else { return nil }
      return Date(timeIntervalSince1970: Double(seconds))
    }
    let started = timestamp("startedAt"), completed = timestamp("completedAt")
    let duration = object["durationMs"]?.intValue
    let ordered = started == nil || completed == nil || completed! >= started!
    let timing = AgentChatTurnTiming(startedAt: ordered ? started : nil,
      completedAt: ordered ? completed : nil,
      durationMilliseconds: duration.flatMap { $0 >= 0 ? $0 : nil })
    if coverage == "notLoaded" {
      guard values.isEmpty else { throw CodexConnectionError.invalidMessage }
      return .init(id: id, status: status, items: .notLoaded, error: error, timing: timing)
    }
    if coverage == "summary" {
      var identities: Set<String> = [], seen: Set<String> = []
      for value in values {
        guard let item = value.objectValue else { throw CodexConnectionError.invalidMessage }
        let itemID = try identifier(item["id"])
        guard seen.insert(itemID).inserted else { throw CodexConnectionError.invalidMessage }
        identities.formUnion([itemID, "runtime:\(itemID)"])
        if let client = try optionalIdentifier(item["clientId"]) { identities.insert(client) }
      }
      return .init(id: id, status: status, items: .references(identities), error: error, timing: timing)
    }
    var seen: Set<String> = []
    let items = try values.compactMap { value -> AgentChatTranscript.Item? in
      guard let object = value.objectValue else { throw CodexConnectionError.invalidMessage }
      let itemID = try identifier(object["id"])
      guard seen.insert(itemID).inserted else { throw CodexConnectionError.invalidMessage }
      let origin = delegationOrigins["runtime:\(itemID)"] ?? threadID
      return try item(object, completed: object["status"]?.stringValue != "inProgress",
        threadID: origin, turnStatus: status)
    }
    return .init(id: id, status: status, items: .full(items), error: error, timing: timing)
  }

  private static func item(_ object: [String: MCPJSONValue], completed: Bool, threadID: String,
    turnStatus: AgentChatTranscript.Turn.Status? = nil) throws -> AgentChatTranscript.Item? {
    let id = try identifier(object["id"])
    guard let type = object["type"]?.stringValue else { throw CodexConnectionError.invalidMessage }
    if type == "agentMessage" {
      guard let text = object["text"]?.stringValue else { throw CodexConnectionError.invalidMessage }
      return .init(id: id, content: .assistant(text: text,
        phase: object["phase"]?.stringValue.flatMap(AgentChatMessage.Phase.init(rawValue:))),
        asyncQuestions: completed && object["delivery"]?.stringValue == "async"
          ? try CodexChatAsyncQuestions.parse(object, id: id, text: text) : nil)
    }
    if type == "userMessage" {
      guard let values = object["content"]?.arrayValue else { throw CodexConnectionError.invalidMessage }
      var text: [String] = [], additional = false
      for value in values {
        guard let input = value.objectValue, let type = input["type"]?.stringValue else { throw CodexConnectionError.invalidMessage }
        if type == "text" {
          guard let value = input["text"]?.stringValue else { throw CodexConnectionError.invalidMessage }
          text.append(value)
        } else { additional = true }
      }
      return .init(id: id, content: .user(text: text.joined(separator: "\n\n"), hasAdditionalMaterial: additional),
        clientMessageID: try optionalIdentifier(object["clientId"]))
    }
    guard var activity = CodexChatActivity.parse(object, completed: completed, threadID: threadID,
      includesManagedTools: true) else { return nil }
    if let status = object["status"] {
      let supported = activity.kind == .delegation ? ["inProgress", "completed", "failed", "interrupted"]
        : type == "mcpToolCall" ? ["inProgress", "completed", "failed"]
        : ["inProgress", "completed", "failed", "declined"]
      guard let value = status.stringValue,
        supported.contains(value) else {
        throw CodexConnectionError.invalidMessage
      }
    }
    if activity.kind == .compaction, let turnStatus {
      activity.status = turnStatus == .completed ? .completed : turnStatus == .inProgress ? .running : .interrupted
    }
    let managed = type == "mcpToolCall" && object["server"]?.stringValue == "scholium"
      && object["tool"]?.stringValue.flatMap(ScholiumMCPToolName.init(rawValue:)) != nil
    return .init(id: id, content: .activity(activity), isManagedTool: managed)
  }

  private static func identifier(_ value: MCPJSONValue?) throws -> String {
    guard let id = value?.stringValue, !id.isEmpty else { throw CodexConnectionError.invalidMessage }
    return id
  }
  private static func optionalIdentifier(_ value: MCPJSONValue?) throws -> String? {
    guard let value, value != .null else { return nil }
    return try identifier(value)
  }
}
