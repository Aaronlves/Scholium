import Foundation
import ScholiumContracts

/// A projection of public runtime events and App receipts, never a source writer.
enum AgentChatActivityProjection {
  static func title(_ activity: AgentChatActivity, locale: Locale = .current) -> String {
    let running = activity.status == .running
    let completed = activity.status == .completed
    let key: String.LocalizationValue
    if activity.kind == .tool, case .zoteroReadReport = activity.sourceObservation {
      key = running ? "Reading a Zotero source" : completed ? "Read a Zotero source" : "Zotero source reading"
    } else if activity.kind == .tool, case .webAccess = activity.sourceObservation {
      key = running ? "Checking a web source" : completed ? "Checked a web source" : "Web source check"
    } else if let action = activity.commandAction {
      switch action.kind {
      case .read: key = running ? "Reading file" : completed ? "Read file" : "File reading"
      case .search: key = running ? "Searching files" : completed ? "Searched files" : "File search"
      case .listFiles: key = running ? "Browsing files" : completed ? "Browsed files" : "File browsing"
      }
    } else {
      switch activity.kind {
      case .read: key = running ? "Reading note" : completed ? "Read note" : "Note reading"
      case .readAttachment: key = running ? "Reading attachment" : completed ? "Read attachment" : "Attachment reading"
      case .search: key = running ? "Searching the library" : completed ? "Searched the library" : "Library search"
      case .create: key = running ? "Creating note" : completed ? "Created note" : "Note creation"
      case .update: key = running ? "Revising note" : completed ? "Revised note" : "Note revision"
      case .trash: key = running ? "Moving note to Trash" : completed ? "Moved note to Trash" : "Note removal"
      case .webSearch: key = running ? "Searching the web" : completed ? "Searched the web" : "Web search"
      case .files: key = running ? "Updating files" : completed ? "Updated files" : "File update"
      case .compaction: key = running ? "Organizing conversation" : completed ? "Organized conversation" : "Conversation organization"
      case .delegation: key = "Agent Collaboration"
      case .command: key = running ? "Running command" : completed ? "Ran command" : "Run Command"
      case .tool: key = running ? "Using tool" : completed ? "Used tool" : "Use Tool"
      }
    }
    return ScholiumL10n.string(key, locale: locale)
  }

  static func subject(_ activity: AgentChatActivity) -> String? {
    let value: String
    if let action = activity.commandAction {
      value = action.kind == .search ? action.target : (action.target as NSString).lastPathComponent
    } else if let file = activity.files.first, !file.path.isEmpty {
      value = (file.path as NSString).lastPathComponent
    } else if activity.kind == .tool {
      value = activity.subject
    } else if activity.kind == .search || activity.kind == .webSearch {
      if let url = URL(string: activity.subject), let host = url.host { value = host }
      else { value = activity.subject }
    } else { return nil }
    let text = value.split(whereSeparator: { $0.isNewline }).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    return text.isEmpty ? nil : String(text.prefix(160))
  }

  static func summary(_ activity: AgentChatActivity, locale: Locale = .current) -> String {
    let title = title(activity, locale: locale)
    return subject(activity).map { title + " · " + $0 } ?? title
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
