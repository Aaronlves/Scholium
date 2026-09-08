import AppKit
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Reply selection handoff", .serialized)
@MainActor
struct AgentChatReplyQuotationTests {
  @Test("Unicode selection retains its rendered block and rejects stale or invalid ranges")
  func exactSelection() throws {
    let source = "First **理由 😀**.\n\nRepeated 理由 😀."
    let text = AgentChatSelectableText.renderReply(source).string
    let range = (text as NSString).range(of: "理由 😀")
    let selected = AgentChatReplySelection(range: range, renderedText: text)
    #expect(AgentChatReplyQuotation.passage(selected, in: source) == "理由 😀")
    #expect(AgentChatReplyQuotation.passage(selected, in: "changed") == nil)
    #expect(
      AgentChatReplyQuotation.passage(
        .init(range: .init(location: text.utf16.count - 1, length: 10), renderedText: text),
        in: source) == nil)
    let id = UUID()
    let message = "reply/a?b=中文"
    let url = AgentChatReplyQuotation.url(conversationID: id, messageID: message)
    #expect(AgentChatReplyQuotation.target(url)?.conversationID == id)
    #expect(AgentChatReplyQuotation.target(url)?.messageID == message)
    #expect(
      AgentChatReplyQuotation.target(URL(string: url.absoluteString + "&message=wrong")!) == nil)
  }

  @Test("One native selection crosses prose, lists and table cells in Copy order")
  func crossBlockSelection() throws {
    let source = "First **理由 😀**.\n\n- One\n- Two\n\n| A | B |\n|---|---|\n| C | D |\n\nLast."
    let rendered = AgentChatSelectableText.renderReply(source)
    #expect(rendered.string == "First 理由 😀.\n• One\n• Two\nA\nB\nC\nD\nLast.")
    let view = AgentChatReplyTextView()
    view.displayReply(source)
    let start = (view.string as NSString).range(of: "理由").location
    let end = NSMaxRange((view.string as NSString).range(of: "D\nLast."))
    let range = NSRange(location: start, length: end - start)
    var quoted: String?
    view.quote = { range, text in
      quoted = AgentChatReplyQuotation.passage(.init(range: range, renderedText: text), in: source)
    }
    view.setSelectedRange(range)
    view.displayReply(source)
    #expect(view.selectedRange() == range)
    view.quoteSelection(nil)
    let board = NSPasteboard(name: .init("reply-copy-\(UUID())"))
    defer { board.releaseGlobally() }
    #expect(view.writeSelection(to: board, types: view.writablePasteboardTypes))
    #expect(board.string(forType: .string) == quoted)
    #expect(quoted == "理由 😀.\n• One\n• Two\nA\nB\nC\nD\nLast.")
    let narrow = view.measuredHeight(width: 160)
    #expect(narrow.isFinite && narrow > 0)
    #expect(view.selectedRange() == range)
  }

  @Test("Native selection quotes with the keyboard without editing or copying to the clipboard")
  func nativeSelection() throws {
    let view = AgentChatReplyTextView()
    let text = "一段 **文字** 😀"
    let attributed = try AttributedString(markdown: text)
    view.textStorage?.setAttributedString(
      AgentChatSelectableText.render(attributed, font: .systemFont(ofSize: 13)))
    let original = view.string
    let range = (original as NSString).range(of: "文字")
    var captured: String?
    view.quote = { selection, string in captured = (string as NSString).substring(with: selection) }
    view.setSelectedRange(range)
    let event = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero,
        modifierFlags: [.command, .shift], timestamp: 0, windowNumber: 0, context: nil,
        characters: "R", charactersIgnoringModifiers: "r", isARepeat: false, keyCode: 15))
    let clipboard = NSPasteboard.general.changeCount
    view.keyDown(with: event)
    #expect(captured == "文字")
    #expect(view.string == original)
    #expect(view.selectedRange() == range)
    #expect(original == "一段 文字 😀")
    #expect(!view.isEditable && NSPasteboard.general.changeCount == clipboard)
    view.quote = nil
    captured = nil
    view.quoteSelection(nil)
    #expect(captured == nil)
  }

  @Test("Reply measurement wraps on a detached copy without moving native selection or geometry")
  func measurement() {
    let view = AgentChatReplyTextView()
    view.frame = NSRect(x: 0, y: 0, width: 300, height: 120)
    view.textStorage?.setAttributedString(
      AgentChatSelectableText.render(
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
    let text = AgentChatSelectableText.renderReply(reply.text).string
    let selected = AgentChatReplySelection(
      range: (text as NSString).range(of: "原回复"), renderedText: text)
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
