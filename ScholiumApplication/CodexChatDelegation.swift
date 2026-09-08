import ScholiumContracts

/// Strict projection of public collaboration items from the installed runtime schema.
public enum CodexChatDelegation {
  public static func parse(_ item: [String: MCPJSONValue], senderThreadID: String) throws -> AgentChatDelegation {
    guard !senderThreadID.isEmpty, let type = item["type"]?.stringValue else { throw CodexConnectionError.invalidMessage }
    if type == "subAgentActivity" {
      guard let operation = item["kind"]?.stringValue.flatMap(AgentChatDelegation.Operation.init(rawValue:)),
        [.started, .interacted, .interrupted, .completed].contains(operation),
        let id = item["agentThreadId"]?.stringValue, !id.isEmpty, id != senderThreadID,
        let path = item["agentPath"]?.stringValue, !path.isEmpty else { throw CodexConnectionError.invalidMessage }
      // Started/interacted does not establish the target's current run status.
      let state: AgentChatDelegation.State? = operation == .completed ? .completed : operation == .interrupted ? .interrupted : nil
      return .init(operation: operation, senderThreadID: senderThreadID, prompt: nil,
        targets: [.init(id: id, path: path, state: state)])
    }
    guard type == "collabAgentToolCall", let reportedSender = item["senderThreadId"]?.stringValue, !reportedSender.isEmpty,
      let operation = item["tool"]?.stringValue.flatMap(AgentChatDelegation.Operation.init(rawValue:)),
      ![.started, .interacted, .interrupted, .completed].contains(operation),
      let values = item["receiverThreadIds"]?.arrayValue,
      let states = item["agentsStates"]?.objectValue,
      let status = item["status"]?.stringValue,
      ["inProgress", "completed", "failed", "interrupted"].contains(status)
    else { throw CodexConnectionError.invalidMessage }
    let ids = try values.map { value -> String in
      guard let id = value.stringValue, !id.isEmpty else { throw CodexConnectionError.invalidMessage }
      return id
    }
    guard Set(ids).count == ids.count else { throw CodexConnectionError.invalidMessage }
    if let value = item["prompt"], value != .null, value.stringValue == nil { throw CodexConnectionError.invalidMessage }
    // List/wait may report agents outside the receiver list. Preserve them as
    // observations, without inferring a parent relation or granting control.
    let allIDs = ids + states.keys.filter { !ids.contains($0) }.sorted()
    let targets = try allIDs.map { id -> AgentChatDelegation.Target in
      guard !id.isEmpty else { throw CodexConnectionError.invalidMessage }
      guard let value = states[id] else { return .init(id: id, state: nil) }
      guard let object = value.objectValue,
        let state = object["status"]?.stringValue.flatMap(AgentChatDelegation.State.init(rawValue:))
      else { throw CodexConnectionError.invalidMessage }
      if let message = object["message"], message != .null, message.stringValue == nil { throw CodexConnectionError.invalidMessage }
      return .init(id: id, state: state, message: object["message"]?.stringValue)
    }
    return .init(operation: operation, senderThreadID: reportedSender,
      prompt: item["prompt"]?.stringValue, targets: targets)
  }
}
