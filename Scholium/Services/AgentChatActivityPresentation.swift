import Foundation
import ScholiumContracts

/// A projection of public runtime events and App receipts, never a source writer.
enum AgentChatActivityProjection {
  static func kind(_ tool: ScholiumMCPToolName) -> AgentChatActivity.Kind {
    switch tool {
    case .readNote: .read
    case .search, .listLinks, .workspaceStatus: .search
    case .createNote: .create
    case .updateNote: .update
    case .trashNote: .trash
    }
  }

  static func runtime(_ item: [String: MCPJSONValue], completed: Bool) -> AgentChatActivity? {
    let type = item["type"]?.stringValue ?? ""
    // The App bridge records these exact calls, including approval and receipt.
    if type == "mcpToolCall", item["server"]?.stringValue == "scholium",
       ScholiumMCPToolName(rawValue: item["tool"]?.stringValue ?? "") != nil { return nil }
    let kind: AgentChatActivity.Kind
    switch type {
    case "mcpToolCall": kind = .tool
    case "commandExecution": kind = .command
    case "fileChange": kind = .files
    case "webSearch": kind = .webSearch
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
    let subject = item["tool"]?.stringValue ?? item["command"]?.stringValue
      ?? item["query"]?.stringValue ?? ""
    var detail = item["error"]?.objectValue?["message"]?.stringValue
      ?? item["aggregatedOutput"]?.stringValue ?? ""
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
    return .init(kind: kind, status: status, source: .runtime, subject: subject,
                 detail: String(detail.suffix(16_000)), files: files)
  }

  static func interrupted(_ activity: AgentChatActivity) -> AgentChatActivity {
    guard activity.status.isActive else { return activity }
    var result = activity
    result.status = activity.status == .running && activity.kind.isMutation ? .uncertain : .interrupted
    return result
  }
}

extension AgentChatActivity.Kind {
  var isMutation: Bool { [.create, .update, .trash, .files].contains(self) }
  var label: String {
    switch self {
    case .read: String(localized: "Read Note")
    case .search: String(localized: "Search Research Materials")
    case .create: String(localized: "Create Note")
    case .update: String(localized: "Edit Note")
    case .trash: String(localized: "Move Note to Trash")
    case .command: String(localized: "Run Command")
    case .webSearch: String(localized: "Search the Web")
    case .tool: String(localized: "Use Tool")
    case .files: String(localized: "Change Files")
    }
  }
  var symbol: String {
    switch self {
    case .read: "doc.text.magnifyingglass"
    case .search, .webSearch: "magnifyingglass"
    case .create: "doc.badge.plus"
    case .update, .files: "pencil.line"
    case .trash: "trash"
    case .command: "terminal"
    case .tool: "gearshape.2"
    }
  }
}

extension AgentChatActivity.Status {
  var label: String {
    switch self {
    case .running: String(localized: "In Progress")
    case .waitingForApproval: String(localized: "Waiting for Approval")
    case .completed: String(localized: "Completed")
    case .failed: String(localized: "Failed")
    case .declined: String(localized: "Declined")
    case .interrupted: String(localized: "Interrupted")
    case .uncertain: String(localized: "Outcome Uncertain")
    }
  }
  var symbol: String {
    switch self {
    case .running: "ellipsis"
    case .waitingForApproval: "hand.raised"
    case .completed: "checkmark"
    case .failed, .uncertain: "exclamationmark.triangle"
    case .declined: "xmark"
    case .interrupted: "stop"
    }
  }
}

extension AgentChatActivity.File.Effect {
  var label: String {
    switch self {
    case .read: String(localized: "Read Only")
    case .created: String(localized: "Created")
    case .edited: String(localized: "Edited")
    case .unchanged: String(localized: "Unchanged")
    case .trashed: String(localized: "Moved to Trash")
    }
  }
  var isMutation: Bool { self == .created || self == .edited || self == .trashed }
}

struct AgentChatFileSummary: Identifiable {
  let id: String
  var file: AgentChatActivity.File
  var source: AgentChatActivity.Source
  var changeIDs: [UUID]

  static func collect(_ messages: [AgentChatMessage]) -> [Self] {
    var result: [Self] = []
    for message in messages {
      guard let activity = message.activity, activity.status == .completed else { continue }
      for file in activity.files where file.effect != nil {
        let id = activity.source.rawValue + ":" + (file.noteID?.uuidString ?? file.path)
        if let index = result.firstIndex(where: { $0.id == id }) {
          // A later read or no-op cannot erase a recorded edit from this conversation.
          if file.effect?.isMutation == true || result[index].file.effect?.isMutation != true {
            result[index].file = file
          }
          if let change = message.changeID, !result[index].changeIDs.contains(change) {
            result[index].changeIDs.append(change)
          }
        } else {
          result.append(.init(id: id, file: file, source: activity.source,
                              changeIDs: message.changeID.map { [$0] } ?? []))
        }
      }
    }
    return result
  }
}
