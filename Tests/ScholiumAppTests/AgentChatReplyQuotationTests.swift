import AppKit
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Reply selection handoff", .serialized)
@MainActor
struct AgentChatReplyQuotationTests {
  @Test("Unicode reader selections reject stale, empty and oversized excerpts")
  func exactSelection() throws {
    let source = "First **理由 😀**.\n\nRepeated 理由 😀."
    let selected = AgentChatReplySelection.reader(source: source, excerpt: "理由 😀")
    #expect(AgentChatReplyQuotation.passage(selected, in: source) == "理由 😀")
    #expect(AgentChatReplyQuotation.passage(selected, in: "changed") == nil)
    #expect(AgentChatReplyQuotation.passage(.reader(source: source, excerpt: ""), in: source) == nil)
    #expect(AgentChatReplyQuotation.passage(.reader(source: source,
      excerpt: String(repeating: "😀", count: 20_000)), in: source) == nil)
    let id = UUID()
    let message = "reply/a?b=中文"
    let url = AgentChatReplyQuotation.url(conversationID: id, messageID: message)
    #expect(AgentChatReplyQuotation.target(url)?.conversationID == id)
    #expect(AgentChatReplyQuotation.target(url)?.messageID == message)
    #expect(
      AgentChatReplyQuotation.target(URL(string: url.absoluteString + "&message=wrong")!) == nil)
  }

  @Test("Object preview measurement preserves native selection and geometry")
  func measurement() {
    let view = AgentChatObjectTextView()
    view.frame = NSRect(x: 0, y: 0, width: 300, height: 120)
    view.textStorage?.setAttributedString(
      AgentChatObjectProjection.render(
        AttributedString(String(repeating: "原文与解释需要区分。 ", count: 20)), font: .systemFont(ofSize: 13)
      ))
    view.setSelectedRange(NSRange(location: 2, length: 4))
    let frame = view.frame
    let container = view.textContainer?.containerSize
    let narrow = view.measuredHeight(width: 160)
    let wide = view.measuredHeight(width: 320)
    #expect(narrow > wide && wide > 0)
    #expect(view.frame == frame && view.textContainer?.containerSize == container)
    #expect(view.selectedRange() == NSRange(location: 2, length: 4))
  }

  @Test("Quoting preserves the owning draft and rejects actions from another conversation")
  func ownedDraft() async throws {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let root = repository.appendingPathComponent(".build/agent-chat-evolution/quote-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let triptych = UUID()
    var conversation = AgentChatConversation(triptychID: triptych)
    conversation.draft = "我的问题"
    let reply = AgentChatMessage(
      id: "original", role: .assistant, text: "这是 **原回复**。", phase: .finalAnswer)
    conversation.messages = [reply]
    let storage = AgentChatStorage(root: root.appendingPathComponent(triptych.uuidString))
    try await storage.save([conversation])
    let defaults = try #require(UserDefaults(suiteName: "quote-\(triptych)"))
    defer { defaults.removePersistentDomain(forName: "quote-\(triptych)") }
    let controller = AgentChatController(triptychID: triptych, root: root, methodDefaults: defaults)
    { request in
      Issue.record("Quoting must not invoke a tool")
      return try! .init(requestID: request.requestID, result: .null)
    }
    for _ in 0..<100 where !controller.isLoaded { try await Task.sleep(for: .milliseconds(10)) }
    #expect(controller.isLoaded)
    controller.select(conversation.id)
    let selected = AgentChatReplySelection.reader(source: reply.text, excerpt: "原回复")
    #expect(controller.quoteReply(reply.id, selection: selected, in: conversation.id))
    #expect(controller.selected?.draft == "我的问题")
    #expect(controller.selected?.draftReplyQuotes?.first?.text == "原回复")
    #expect(controller.selected?.draftReplyQuotes?.first?.messageID == reply.id)
    try await controller.flushPersistence()
    #expect(
      try await storage.load().first?.draftReplyQuotes == controller.selected?.draftReplyQuotes)
    #expect(controller.selected?.messages == [reply])
    controller.newConversation()
    controller.editDraft("另一讨论")
    #expect(!controller.quoteReply(reply.id, selection: selected, in: conversation.id))
    #expect(controller.selected?.draft == "另一讨论")
    await controller.disconnect()
  }
}
