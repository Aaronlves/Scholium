import Foundation
import ScholiumContracts

/// A projection of public runtime events and App receipts, never a source writer.
enum AgentChatActivityProjection {
  static func title(_ activity: AgentChatActivity, locale: Locale = .current) -> String {
    switch activity.kind {
    case .command, .tool: ScholiumL10n.string("Working", locale: locale)
    case .compaction: ScholiumL10n.string("Organizing Conversation", locale: locale)
    default: activity.kind.label(locale: locale)
    }
  }

  static func subject(_ activity: AgentChatActivity) -> String? {
    guard activity.source == .scholium, [.read, .readAttachment, .create, .update, .trash].contains(activity.kind),
      let file = activity.files.first else { return nil }
    return (file.path as NSString).lastPathComponent
  }
  static func withLocalizedFailure(_ value: AgentChatActivity?) -> AgentChatActivity? {
    guard var activity = value else { return nil }
    if activity.kind == .delegation && activity.delegation == nil {
      activity.detail = ScholiumL10n.string("The delegated-work report could not be read.")
    }
    return activity
  }

  static func afterConnectionLoss(_ activity: AgentChatActivity) -> AgentChatActivity {
    guard activity.status.isActive else { return activity }
    var result = activity
    result.status = activity.status == .running && (activity.source == .runtime || activity.kind.isMutation)
      ? .uncertain : .interrupted
    return result
  }
}

extension AgentChatActivity.Kind {
  var isMutation: Bool { [.create, .update, .trash, .files].contains(self) }
  var label: String { label(locale: .current) }
  func label(locale: Locale) -> String {
    let key: String.LocalizationValue
    switch self {
    case .read: key = "Read Note"
    case .readAttachment: key = "Read Attachment"
    case .search: key = "Search Research Materials"
    case .create: key = "Create Note"
    case .update: key = "Edit Note"
    case .trash: key = "Move Note to Trash"
    case .command: key = "Run Command"
    case .webSearch: key = "Search the Web"
    case .tool: key = "Use Tool"
    case .files: key = "Change Files"
    case .compaction: key = "Compact Context"
    case .delegation: key = "Agent Collaboration"
    }
    return ScholiumL10n.string(key, locale: locale)
  }
  var symbol: String {
    switch self {
    case .read, .readAttachment: "doc.text.magnifyingglass"
    case .search, .webSearch: "magnifyingglass"
    case .create: "doc.badge.plus"
    case .update, .files: "pencil.line"
    case .trash: "trash"
    case .command: "terminal"
    case .tool: "gearshape.2"
    case .compaction: "arrow.down.right.and.arrow.up.left"
    case .delegation: "person.2"
    }
  }
}

extension AgentChatActivity.Status {
  var label: String { label(locale: .current) }
  func label(locale: Locale) -> String {
    let key: String.LocalizationValue
    switch self {
    case .running: key = "In Progress"
    case .waitingForApproval: key = "Waiting for Approval"
    case .waitingForInput: key = "Input Requested"
    case .completed: key = "Completed"
    case .failed: key = "Failed"
    case .declined: key = "Declined"
    case .interrupted: key = "Interrupted"
    case .uncertain: key = "Outcome Uncertain"
    }
    return ScholiumL10n.string(key, locale: locale)
  }
  var symbol: String {
    switch self {
    case .running: "ellipsis"
    case .waitingForApproval: "hand.raised"
    case .waitingForInput: "questionmark.bubble"
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
    case .moved: String(localized: "Moved")
    }
  }
  var isMutation: Bool { self == .created || self == .edited || self == .trashed || self == .moved }
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
