import AppKit
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Public conversation search")
struct AgentChatSearchTests {
  @Test("Literal Unicode queries search public plans, activities and exact material without changing history")
  func publicContent() {
    var conversation = AgentChatConversation(triptychID: UUID())
    conversation.title = "Reasons and 情绪"
    conversation.draft = "unsent private draft"
    let material = AgentChatAttachment(noteID: UUID(), vaultID: UUID(), relativePath: "原文.md",
      text: "原文观点 👨‍👩‍👧‍👦 café", fingerprint: .init(content: "原文观点 👨‍👩‍👧‍👦 café"))
    var planMessage = AgentChatMessage(role: .assistant, text: "")
    planMessage.plan = .init(turnID: "turn", explanation: "比较解释",
      steps: [.init(step: "核对引文", status: .pending)])
    conversation.messages = [
      .init(role: .user, text: "Literal a+b?", attachments: [material]),
      planMessage,
      .init(role: .operation, text: "", activity: .init(kind: .search, status: .completed,
        source: .runtime, subject: "反例", detail: "检索结果")),
    ]
    let before = conversation
    for query in ["reasons", "情绪", "a+b?", "CAFE\u{301}", "原文观点", "核对引文", "检索结果"] {
      #expect(AgentChatSearch.contains(conversation, query: query))
    }
    #expect(!AgentChatSearch.contains(conversation, query: "unsent private draft"))
    #expect(!AgentChatSearch.contains(conversation, query: ".*"))
    #expect(AgentChatSearch.contains(conversation, query: ""))
    #expect(AgentChatSearch.query(" \n情绪\t") == "情绪")
    #expect(conversation == before)
  }

  @Test("A passage retains the actual match and Unicode boundaries away from the start")
  func snippets() {
    let text = String(repeating: "😀文", count: 80) + "\nNeedle e\u{301}\n" + String(repeating: "后", count: 90)
    let passage = AgentChatSearch.snippet(text, query: "needle")
    #expect(passage.hasPrefix("…") && passage.hasSuffix("…"))
    #expect(passage.contains("Needle e\u{301}"))
    #expect(!passage.contains("\n") && !passage.contains("�"))
  }

  @Test("Find preserves the current message during streaming and wraps without stale destinations")
  func navigation() {
    var messages = [AgentChatMessage(id: "a", role: .user, text: "理由 理由"),
      .init(id: "b", role: .assistant, text: "另一种理由")]
    var find = AgentChatFindState()
    find.query = "理由"
    find.refresh(messages: messages)
    #expect(find.messageIDs == ["a", "b"] && find.position == 1)
    find.move(backwards: true)
    #expect(find.selectedID == "b" && find.position == 2)
    messages.append(.init(id: "c", role: .assistant, text: "理由的新解释"))
    find.refresh(messages: messages)
    #expect(find.selectedID == "b")
    find.move(backwards: false)
    #expect(find.selectedID == "c")
    find.move(backwards: false)
    #expect(find.selectedID == "a")
    find.query = "不存在"
    find.refresh(messages: messages, reset: true)
    find.move(backwards: false)
    #expect(find.selectedID == nil && find.position == nil && find.messageIDs.isEmpty)
    find.query = "理由"
    find.refresh(messages: messages)
    find.refresh(messages: Array(messages.dropFirst()))
    #expect(find.selectedID == "b")
  }

  @MainActor
  @Test("Optional search commands preserve marked text and ordinary search-field behavior")
  func nativeCommands() {
    var navigation: [Bool] = [], dismissals = 0
    let coordinator = ContextSearchField.Coordinator(parent: .init(text: .constant(""),
      prompt: "Find in Conversation", identifier: "fixture",
      navigate: { navigation.append($0) }, dismiss: { dismissals += 1 }))
    let field = ContextSearchField.Field(), editor = NSTextView()
    let enter = #selector(NSResponder.insertNewline(_:))
    let escape = #selector(NSResponder.cancelOperation(_:))
    #expect(coordinator.control(field, textView: editor, doCommandBy: enter))
    #expect(navigation == [false])
    editor.setMarkedText("候选", selectedRange: NSRange(location: 2, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(!coordinator.control(field, textView: editor, doCommandBy: enter))
    #expect(!coordinator.control(field, textView: editor, doCommandBy: escape))
    #expect(navigation.count == 1 && dismissals == 0)
    editor.unmarkText()
    #expect(coordinator.control(field, textView: editor, doCommandBy: escape))
    #expect(dismissals == 1)
    coordinator.parent.navigate = nil
    coordinator.parent.dismiss = nil
    #expect(!coordinator.control(field, textView: editor, doCommandBy: enter))
    #expect(!coordinator.control(field, textView: editor, doCommandBy: escape))
  }
}
