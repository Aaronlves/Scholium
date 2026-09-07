import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

/// Chat is a native macOS reading and control surface; only Paper and Accent are branded.
enum NativeChatSourceScope {
  static let paths: Set<String> = [
    "Scholium/Views/Sidebar/AgentChatView.swift",
    "Scholium/Views/Sidebar/AgentChatMarkdown.swift",
    "Scholium/Views/Sidebar/AgentChatMaterialChip.swift",
    "Scholium/Views/Sidebar/AgentChatComposerInput.swift",
  ]
}

/// Shared native sidebar presentation is allowed to use system typography and color.
enum NativeSidebarSourceScope {
  static let paths: Set<String> = [
    "Scholium/Views/Sidebar/RelatedMaterialsView.swift",
    "Scholium/UI/Components/ScholiumSidebarHeaderControl.swift",
    "Scholium/Views/Sidebar/SidebarView.swift",
  ]
}

@Suite("Native research conversation presentation")
struct AgentChatPresentationTests {
  @Test("Long replies preserve paragraphs, quotation, argument numbering and exact code")
  func markdownBlocks() {
    let source =
      "## A distinction\n\nA **strong** claim.\n\nA second paragraph with 中文 😀.\n\n> Source quotation.\n\n3. Premise\n4. Conclusion\n\n```text\na < b\n  exact spacing\n```"
    let blocks = AgentChatMarkdownBlock.parse(source)
    #expect(
      blocks.map(\.kind) == [.heading, .prose, .prose, .quote, .list("3."), .list("4."), .code])
    #expect(String(blocks[2].text.characters) == "A second paragraph with 中文 😀.")
    #expect(String(blocks[6].text.characters) == "a < b\n  exact spacing\n")
    #expect(
      blocks[1].text.runs.contains {
        $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
      })
    #expect(Set(blocks.map(\.id)).count == blocks.count)
    #expect(AgentChatMarkdownBlock.parse("> 1. Quoted premise").first?.isQuoted == true)
  }

  @Test("Note citations remain links and comparison tables retain cells")
  func referencesAndTables() throws {
    let url = AgentChatReference.url(noteID: UUID(), line: 5)
    let blocks = AgentChatMarkdownBlock.parse(
      "Read [this note](\(url)).\n\n| View | Objection |\n|---|---|\n| One | Two |")
    #expect(blocks.first?.text.runs.contains { $0.link == url } == true)
    #expect(blocks[1].kind == .tableRow(true))
    #expect(blocks[1].cells.map { String($0.characters) } == ["View", "Objection"])
    #expect(blocks[2].cells.map { String($0.characters) } == ["One", "Two"])
  }

  @Test("Activity can collapse without hiding replies or losing exact change links")
  func timeline() {
    let change = UUID()
    let messages: [AgentChatMessage] = [
      .init(role: .user, text: "Explain."),
      .init(role: .operation, text: "Read"),
      .init(role: .operation, text: "Updated", changeID: change),
      .init(role: .assistant, text: "First paragraph."),
      .init(role: .assistant, text: "Second paragraph."),
      .init(role: .user, text: "An objection."),
    ]
    let items = AgentChatTimelineItem.group(messages)
    #expect(items.count == 5)
    #expect(items[1].isActivity && items[1].messages.count == 2)
    #expect(items[1].messages[1].changeID == change)
    #expect(items[2].showsSpeaker && !items[3].showsSpeaker && items[4].showsSpeaker)
    #expect(items.flatMap(\.messages) == messages)
  }

  @Test("Runtime status and reported edits never manufacture Scholium mutation evidence")
  func runtimeEvidence() throws {
    let own: [String: MCPJSONValue] = ["type": .string("mcpToolCall"),
      "server": .string("scholium"), "tool": .string("scholium_update_note")]
    #expect(AgentChatActivityProjection.runtime(own, completed: false) == nil)
    let item: [String: MCPJSONValue] = ["type": .string("fileChange"), "status": .string("completed"),
      "changes": .array([.object(["path": .string("fixture.md"), "diff": .string("-old\n+new"),
        "kind": .object(["type": .string("update")])])])]
    let activity = try #require(AgentChatActivityProjection.runtime(item, completed: true))
    let message = AgentChatMessage(role: .operation, text: "", activity: activity)
    let file = try #require(AgentChatFileSummary.collect([message]).first)
    #expect(file.source == .runtime && file.changeIDs.isEmpty && file.file.effect == .edited)
    var pending = activity
    pending.status = .running
    #expect(AgentChatActivityProjection.interrupted(pending).status == .uncertain)
    pending.status = .waitingForApproval
    #expect(AgentChatActivityProjection.interrupted(pending).status == .interrupted)
    var failed = item
    failed["status"] = .string("failed")
    let failure = try #require(AgentChatActivityProjection.runtime(failed, completed: true))
    #expect(failure.status == .failed && failure.files.first?.effect == nil)
  }

  @Test("A later read cannot erase a confirmed edit and duplicate receipts stay unique")
  func fileEvidenceGrouping() throws {
    let note = UUID(), change = UUID()
    let edited = AgentChatMessage(role: .operation, text: "", changeID: change,
      activity: .init(kind: .update, status: .completed, source: .scholium,
        files: [.init(path: "note.md", noteID: note, effect: .edited)]))
    let read = AgentChatMessage(role: .operation, text: "",
      activity: .init(kind: .read, status: .completed, source: .scholium,
        files: [.init(path: "note.md", noteID: note, effect: .read)]))
    let summaries = AgentChatFileSummary.collect([edited, read, edited])
    #expect(summaries.count == 1 && summaries[0].file.effect == .edited)
    #expect(summaries[0].changeIDs == [change])
    let data = try JSONEncoder().encode(edited)
    #expect(try JSONDecoder().decode(AgentChatMessage.self, from: data) == edited)
  }

  @Test("Conversation change history retains earlier receipts without importing unrelated changes")
  func conversationChangeScope() {
    let triptych = UUID(), note = UUID()
    func change(_ time: Double) -> AgentChange {
      AgentChange(id: UUID(), triptychID: triptych, operation: .update, noteID: note,
        role: .topicKnowledge, originalRelativePath: "note.md", finalRelativePath: "note.md",
        beforeFingerprint: nil, afterFingerprint: nil, state: .confirmed,
        createdAt: Date(timeIntervalSince1970: time), confirmedAt: Date(timeIntervalSince1970: time), undoneAt: nil)
    }
    let earlier = change(1), latest = change(2), unrelated = change(3)
    let all = [earlier, latest, unrelated]
    #expect(AgentChangePresentation.inScope(all, scope: .conversation([earlier.id, latest.id, latest.id])).map(\.id)
      == [earlier.id, latest.id])
    #expect(AgentChangePresentation.inScope(all, scope: .exact(earlier.id)).map(\.id) == [earlier.id])
    #expect(AgentChangePresentation.inScope(all, scope: .current).map(\.id) == [unrelated.id])
    #expect(AgentChangePresentation.inScope(all, scope: .conversation([])).isEmpty)
  }

  @Test("Chat typography and controls are native, with no response-length restriction")
  func nativeBoundary() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    for path in NativeChatSourceScope.paths {
      let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
      #expect(!source.contains("ScholiumTypography"))
      #expect(!source.contains(".scholiumSurface(.document)"))
      #expect(!source.contains(".scholiumForeground("))
      #expect(!source.contains(".font(.system(size:"))
    }
    let source = try String(
      contentsOf: root.appendingPathComponent("Scholium/Services/AgentChatController.swift"),
      encoding: .utf8)
    #expect(source.contains("Do not impose short-answer limits"))
    #expect(!source.contains("max_output_tokens"))
  }
}
