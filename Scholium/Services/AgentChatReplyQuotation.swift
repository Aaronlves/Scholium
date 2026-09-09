import Foundation
import ScholiumContracts

/// A temporary selection in rendered Agent prose, not a research-source range.
struct AgentChatReplySelection: Equatable {
  let range: NSRange
  let renderedText: String
  var readerSource: String? = nil
  static func reader(source: String, excerpt: String) -> Self {
    .init(range: NSRange(location: 0, length: excerpt.utf16.count), renderedText: excerpt, readerSource: source)
  }
}

enum AgentChatReplyQuotation {
  @MainActor static func passage(_ selection: AgentChatReplySelection, in reply: String) -> String?
  {
    if let source = selection.readerSource {
      guard source == reply, selection.range == NSRange(location: 0, length: selection.renderedText.utf16.count),
            !selection.renderedText.isEmpty, selection.renderedText.utf8.count <= 65_536 else { return nil }
      return selection.renderedText
    }
    let text = AgentChatSelectableText.renderReply(reply).string
    guard text == selection.renderedText, selection.range.length > 0,
      let range = Range(selection.range, in: text)
    else { return nil }
    return String(text[range])
  }

  static func url(conversationID: UUID, messageID: String) -> URL {
    var components = URLComponents()
    components.scheme = "scholium-chat"
    components.host = "reply"
    components.queryItems = [
      .init(name: "conversation", value: conversationID.uuidString),
      .init(name: "message", value: messageID),
    ]
    return components.url!
  }

  static func target(_ url: URL) -> (conversationID: UUID, messageID: String)? {
    guard let value = URLComponents(url: url, resolvingAgainstBaseURL: false),
      value.scheme == "scholium-chat", value.host == "reply", value.path.isEmpty,
      value.user == nil, value.password == nil, value.port == nil, value.fragment == nil,
      let items = value.queryItems, items.count == 2,
      items.filter({ $0.name == "conversation" }).count == 1,
      items.filter({ $0.name == "message" }).count == 1,
      let id = items.first(where: { $0.name == "conversation" })?.value.flatMap(
        UUID.init(uuidString:)),
      let message = items.first(where: { $0.name == "message" })?.value, !message.isEmpty
    else { return nil }
    return (id, message)
  }

}
