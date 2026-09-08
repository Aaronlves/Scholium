import Foundation
import ScholiumContracts

/// A read-only projection of public conversation content; no index or runtime requests.
enum AgentChatSearch {
  static func query(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func matches(_ text: String, query: String) -> Bool {
    !query.isEmpty && text.range(of: query, options: .caseInsensitive) != nil
  }

  static func passage(in message: AgentChatMessage, query: String) -> String? {
    var texts = [message.text]
    if let target = message.coordinationTarget {
      texts += [target.name ?? "", target.childThreadID, target.parentThreadID]
    }
    texts += (message.methods ?? []).map(\.title)
    if let plan = message.plan {
      texts += [plan.explanation ?? ""] + plan.steps.map(\.step)
    }
    if let activity = message.activity {
      texts += [activity.subject, activity.detail] + activity.files.map(\.path)
      if let report = activity.delegation {
        texts += [report.prompt ?? "", report.senderThreadID]
        texts += report.targets.flatMap { [$0.id, $0.path ?? "", $0.message ?? ""] }
      }
    }
    for material in message.attachments { texts += [material.relativePath, material.text] }
    for material in message.localMaterials {
      texts += [material.fileName, AgentChatLocalMaterialLabels.title(material), material.text] + material.pages.map(\.text)
    }
    return texts.first { matches($0, query: query) }.map { snippet($0, query: query) }
  }

  static func contains(_ conversation: AgentChatConversation, query: String) -> Bool {
    query.isEmpty || matches(conversation.title, query: query)
      || conversation.messages.contains { passage(in: $0, query: query) != nil }
  }

  static func snippet(_ text: String, query: String) -> String {
    guard let range = text.range(of: query, options: .caseInsensitive) else { return "" }
    let start = text.index(range.lowerBound, offsetBy: -32, limitedBy: text.startIndex) ?? text.startIndex
    let end = text.index(range.upperBound, offsetBy: 72, limitedBy: text.endIndex) ?? text.endIndex
    return (start == text.startIndex ? "" : "…")
      + text[start..<end].components(separatedBy: .newlines).joined(separator: " ")
      + (end == text.endIndex ? "" : "…")
  }
}

/// Only navigation state is mutable. Results always derive from the current public messages.
struct AgentChatFindState {
  var query = ""
  private(set) var messageIDs: [String] = []
  private(set) var selectedID: String?
  var position: Int? { selectedID.flatMap { messageIDs.firstIndex(of: $0) }.map { $0 + 1 } }

  mutating func refresh(messages: [AgentChatMessage], reset: Bool = false) {
    let needle = AgentChatSearch.query(query)
    messageIDs = messages.compactMap { AgentChatSearch.passage(in: $0, query: needle) == nil ? nil : $0.id }
    if reset || !messageIDs.contains(selectedID ?? "") { selectedID = messageIDs.first }
  }

  mutating func move(backwards: Bool) {
    guard !messageIDs.isEmpty else { selectedID = nil; return }
    let index = selectedID.flatMap { messageIDs.firstIndex(of: $0) } ?? (backwards ? 0 : -1)
    selectedID = messageIDs[(index + (backwards ? -1 : 1) + messageIDs.count) % messageIDs.count]
  }
}
