import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Quiet activity and context presentation")
struct AgentChatActivityRefinementTests {
  @Test("Compact tool groups preserve every item and public commentary boundary")
  func toolGrouping() {
    let first = AgentChatMessage(id: "a", role: .operation, text: "", activity: .init(kind: .search, source: .runtime))
    let second = AgentChatMessage(id: "b", role: .operation, text: "", activity: .init(kind: .read, source: .runtime))
    let commentary = AgentChatMessage(id: "c", role: .assistant, text: "已找到原文，继续核对。", phase: .commentary)
    let third = AgentChatMessage(id: "d", role: .operation, text: "", activity: .init(kind: .read, source: .runtime))
    let groups = AgentChatProcessSlice.collect([first, second, commentary, third])
    #expect(groups.map { $0.messages.map(\.id) } == [["a", "b"], ["c"], ["d"]])
    #expect(groups.map(\.isTools) == [true, false, true])
    #expect(AgentChatProcessSlice.collect([first, second]).first?.id == "a")
  }
  @Test("A completed operation keeps its object without a repeated Completed label")
  func summary() {
    let locale = Locale(identifier: "zh-Hans")
    var activity = AgentChatActivity(kind: .read, source: .scholium,
      files: [.init(path: "Topics/行动理由.md")])
    #expect(AgentChatActivityProjection.summary(activity, locale: locale) == "正在研读笔记 · 行动理由.md")
    activity.status = .completed
    #expect(AgentChatActivityProjection.summary(activity, locale: locale) == "已读取笔记 · 行动理由.md")
    let search = AgentChatActivity(kind: .search, source: .scholium, subject: "实践理性")
    #expect(AgentChatActivityProjection.subject(search) == "实践理性")
    var command = AgentChatActivity(kind: .command, source: .runtime, subject: "cat /private/raw")
    #expect(AgentChatActivityProjection.subject(command) == nil)
    command.commandAction = .init(kind: .read, target: "/guidance/SKILL.md")
    #expect(AgentChatActivityProjection.subject(command) == "SKILL.md")

    var zotero = AgentChatActivity(kind: .tool, source: .runtime)
    zotero.sourceObservation = .zoteroReadReport(.init(server: "fixture", tool: "zotero_read_original",
      reference: try! ZoteroReference(library: .user, itemKey: "ITEM01"), representation: .text,
      fingerprint: String(repeating: "a", count: 64)))
    #expect(AgentChatActivityProjection.title(zotero, locale: Locale(identifier: "en")) == "Reading a Zotero source")
    zotero.status = .completed
    #expect(AgentChatActivityProjection.title(zotero, locale: Locale(identifier: "en")) == "Read a Zotero source")
  }

  @Test("Reply actions keep supplied materials separate from explicit sources")
  func replyActionAvailability() {
    let source = AgentChatReplySource(url: URL(string: "https://example.org/paper")!, title: "Paper")
    let both = AgentChatReplyActionAvailability(sources: [source], hasMaterials: true)
    #expect(both.hasSources && both.hasMaterials)
    let materialsOnly = AgentChatReplyActionAvailability(sources: [], hasMaterials: true)
    #expect(!materialsOnly.hasSources && materialsOnly.hasMaterials)
    let sourcesOnly = AgentChatReplyActionAvailability(sources: [source], hasMaterials: false)
    #expect(sourcesOnly.hasSources && !sourcesOnly.hasMaterials)
  }

  @Test("Context occupancy uses the latest observation, never cumulative usage or guessed capacity")
  func context() {
    #expect(AgentChatContextPresentation.fraction(nil) == nil)
    #expect(AgentChatContextPresentation.fraction(.init(lastTurnTokens: 12, totalTokens: 9999, capacity: nil)) == nil)
    #expect(AgentChatContextPresentation.fraction(.init(lastTurnTokens: 12, totalTokens: 9999, capacity: 0)) == nil)
    #expect(AgentChatContextPresentation.fraction(.init(lastTurnTokens: 25, totalTokens: 9999, capacity: 100)) == 0.25)
    #expect(AgentChatContextPresentation.fraction(.init(lastTurnTokens: 101, totalTokens: 9999, capacity: 100)) == 1)
    #expect(AgentChatContextPresentation.fraction(.init(lastTurnTokens: 0, totalTokens: 0, capacity: 100)) == 0)
  }

  @Test("Context ledger derives staged materials and controls without duplicating runtime usage")
  func contextLedger() {
    var conversation = AgentChatConversation(triptychID: UUID())
    conversation.attachments = [
      AgentChatAttachment(noteID: UUID(), vaultID: UUID(), relativePath: "Topics/行动理由.md",
        text: "A passage", fingerprint: .init(content: "A passage"))
    ]
    conversation.selectedMethods = [
      .init(name: "argument-check", title: "Check the argument", path: "/methods/argument-check.md")
    ]
    conversation.draftReplyQuotes = [
      .init(conversationID: conversation.id, messageID: "reply-1", text: "A quoted premise\nwith its qualification.")
    ]
    conversation.preferences = .init(model: "research", effort: "high", webSearch: .live)
    let ledger = AgentChatContextLedger(conversation: conversation, modelName: "Research Model", effort: "high")
    #expect(ledger.materials.map(\.title) == ["行动理由"])
    #expect(ledger.materials.first?.detail == ScholiumL10n.string("Attached Passage"))
    #expect(ledger.quotes.count == 1 && ledger.quotes.first?.messageID == "reply-1")
    #expect(ledger.quotes.first?.preview == "A quoted premise with its qualification.")
    #expect(ledger.methods.map(\.title) == ["Check the argument"])
    #expect(ledger.modelName == "Research Model" && ledger.effort == "high" && ledger.webSearch == .live)
    #expect(!ledger.isEmpty)
    #expect(AgentChatContextLedger(conversation: nil).isEmpty)
  }
}
