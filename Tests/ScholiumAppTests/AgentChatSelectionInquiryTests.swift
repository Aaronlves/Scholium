import Foundation
import ScholiumContracts
import ScholiumApplication
import Testing
@testable import ScholiumApp

@Suite("Passage research handoff", .serialized)
@MainActor struct AgentChatSelectionInquiryTests {
  @Test("Inquiry questions preserve exact material, existing drafts and conversation ownership")
  func stage() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".build/agent-chat-evolution/inquiry-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let triptych = UUID()
    let defaults = try #require(UserDefaults(suiteName: "inquiry-\(triptych)"))
    defer { defaults.removePersistentDomain(forName: "inquiry-\(triptych)") }
    let chat = AgentChatController(triptychID: triptych, root: root, methodDefaults: defaults) { request in
      Issue.record("Preparing a question must not invoke a tool")
      return try! .init(requestID: request.requestID, result: .null)
    }
    for _ in 0..<100 where !chat.isLoaded { try await Task.sleep(for: .milliseconds(10)) }
    #expect(chat.isLoaded)
    let passage = "理由与解释 😀\r\n仍需核对。"
    let material = AgentChatAttachment(noteID: UUID(), vaultID: UUID(), relativePath: "Source.md",
      text: passage, fingerprint: .init(content: passage), sourceLine: 4, source: .editorSnapshot)
    for inquiry in AgentChatSelectionInquiry.allCases {
      chat.newConversation()
      let id = try #require(chat.selectedID)
      chat.editDraft("保留我的问题。")
      #expect(chat.prepareSelectionInquiry([material], inquiry: inquiry, to: id))
      let expected = "保留我的问题。" + (inquiry.question.map { "\n\n" + $0 } ?? "")
      #expect(chat.selected?.draft == expected)
      #expect(chat.selected?.attachments == [material])
      #expect(chat.selected?.messages.isEmpty == true && !chat.isBusy)
      #expect(!chat.prepareSelectionInquiry([], inquiry: inquiry, to: id))
      try await chat.flushPersistence()
      let storage = AgentChatStorage(root: root.appendingPathComponent(triptych.uuidString))
      let saved = try await storage.load().first { $0.id == id }
      #expect(saved?.draft == expected && saved?.attachments == [material])
      chat.newConversation()
      #expect(!chat.prepareSelectionInquiry([material], inquiry: inquiry, to: id))
      #expect(chat.selected?.draft.isEmpty == true && chat.selected?.attachments.isEmpty == true)
    }
    let visible = chat.selectedID
    chat.editDraft("Keep this draft")
    let resultID = try #require(chat.beginSelectionInquiry(.polish, attachment: material))
    #expect(chat.selectedID == visible && chat.selected?.draft == "Keep this draft")
    let result = try #require(chat.conversations.first { $0.id == resultID })
    #expect(result.attachments == [material] && result.permission == .ask)
    #expect(result.messages.isEmpty && !result.draft.isEmpty)
    #expect(chat.selectionResultError(in: resultID) != nil)
    await chat.disconnect()
  }
}
