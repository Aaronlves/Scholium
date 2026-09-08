import Foundation
import ScholiumContracts

/// Public runtime item projection. Localized presentation belongs to the client.
public enum CodexChatActivity {
  public static func parse(
    _ item: [String: MCPJSONValue], completed: Bool, threadID: String? = nil,
    includesManagedTools: Bool = false
  ) -> AgentChatActivity? {
    let type = item["type"]?.stringValue ?? ""
    if ["collabAgentToolCall", "subAgentActivity"].contains(type) {
      var activity = AgentChatActivity(kind: .delegation, status: .uncertain, source: .runtime)
      guard let threadID, let report = try? CodexChatDelegation.parse(item, senderThreadID: threadID) else {
        return activity
      }
      activity.delegation = report
      switch item["status"]?.stringValue {
      case "failed": activity.status = .failed
      case "interrupted": activity.status = .interrupted
      case "inProgress": activity.status = completed ? .uncertain : .running
      default: activity.status = completed ? .completed : .running
      }
      return activity
    }
    let managedTool =
      type == "mcpToolCall" && item["server"]?.stringValue == "scholium"
      ? ScholiumMCPToolName(rawValue: item["tool"]?.stringValue ?? "") : nil
    // The parent App bridge records these exact calls, including approval and receipt.
    // Child inspection keeps the runtime invocation without manufacturing that receipt.
    if !includesManagedTools, managedTool != nil { return nil }
    let kind: AgentChatActivity.Kind
    switch type {
    case "mcpToolCall": kind = managedTool.map(AgentChatActivity.Kind.forTool) ?? .tool
    case "commandExecution": kind = .command
    case "fileChange": kind = .files
    case "webSearch": kind = .webSearch
    case "contextCompaction": kind = .compaction
    default: return nil
    }
    var status: AgentChatActivity.Status = completed ? .completed : .running
    switch item["status"]?.stringValue {
    case "failed": status = .failed
    case "declined": status = .declined
    case "inProgress": status = completed ? .uncertain : .running
    default: break
    }
    if item["error"]?.objectValue != nil { status = .failed }
    if completed, let exitCode = item["exitCode"]?.intValue, exitCode != 0 { status = .failed }
    var subject =
      item["tool"]?.stringValue ?? item["command"]?.stringValue
      ?? item["query"]?.stringValue ?? ""
    var detail =
      item["error"]?.objectValue?["message"]?.stringValue
      ?? item["aggregatedOutput"]?.stringValue ?? ""
    if let managedTool {
      subject = item["arguments"]?.objectValue?["relative_path"]?.stringValue ?? ""
      detail = [managedTool.rawValue, detail].filter { !$0.isEmpty }.joined(separator: "\n")
    }
    let files: [AgentChatActivity.File] = (item["changes"]?.arrayValue ?? []).compactMap { value in
      guard let file = value.objectValue, let path = file["path"]?.stringValue else { return nil }
      let effect: AgentChatActivity.File.Effect
      switch file["kind"]?.objectValue?["type"]?.stringValue {
      case "add": effect = .created
      case "delete": effect = .trashed
      default: effect = .edited
      }
      if let diff = file["diff"]?.stringValue { detail += "\n" + path + "\n" + diff }
      return .init(path: path, effect: status == .completed ? effect : nil)
    }
    var activity = AgentChatActivity(
      kind: kind, status: status, source: .runtime, subject: subject,
      detail: String(detail.suffix(16_000)), files: files)
    if kind == .webSearch, completed, status == .completed,
      let action = item["action"]?.objectValue,
      let raw = action["type"]?.stringValue,
      let operation = AgentChatSourceObservation.WebAccess.Action(rawValue: raw),
      let destination = action["url"]?.stringValue, destination.utf8.count <= 8_192,
      let url = URL(string: destination), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
      url.host != nil, url.user == nil, url.password == nil {
      activity.sourceObservation = .webAccess(.init(action: operation, url: url))
      activity.subject = destination
    }
    return activity
  }

}
