import AppKit
import ScholiumContracts
import Testing
import SwiftUI
@testable import ScholiumApp

@Suite("Chat content and viewed changes")
@MainActor
struct AgentChatContentTests {
  @Test func expandedObjectHasNativeWindowGeometryAndCancel() throws {
    _ = NSApplication.shared
    AgentChatRichWindowController.present(content: Text("Nonprivate layout fixture"), naturalSize: CGSize(width: 700, height: 400))
    let window = try #require(NSApp.windows.first { $0.identifier?.rawValue == "scholium.chat.richContentWindow" })
    defer { window.close() }
    #expect(window.frame.width > 600)
    #expect(window.frame.height > 400)
    window.cancelOperation(nil)
    #expect(!window.isVisible)
  }

  @Test func expandedWindowFitsContentAndBoundsLargeObjects() {
    let available = CGSize(width: 1400, height: 900)
    let small = AgentChatRichWindowController.fittedSize(CGSize(width: 380, height: 70), available: available)
    #expect(small == CGSize(width: 444, height: 182))
    let large = AgentChatRichWindowController.fittedSize(CGSize(width: 5000, height: 4000), available: available)
    #expect(large == CGSize(width: 1260, height: 810))
  }

  @Test func inlineCodeUsesNativeBackground() {
    let rendered = AgentChatSelectableText.renderReply("普通 `concept` 文字")
    let range = (rendered.string as NSString).range(of: "concept")
    #expect(rendered.attribute(.backgroundColor, at: range.location, effectiveRange: nil) as? NSColor == .quaternaryLabelColor)
    #expect(rendered.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
  }

  @Test func richSegmentsPreserveQuotationOffsets() throws {
    let source = "前文 😀\n\n| 概念 | 理由 |\n|---|---|\n|情绪|评价|\n\n后文中的评价。\n\n```mermaid\ngraph LR\nA --> B\n```"
    let layout = AgentChatSelectableText.layoutReply(source)
    let segments = AgentChatRichSegment.collect(layout)
    #expect(segments.count == 4)
    #expect(segments[1].columns == 2)
    #expect(segments.last?.language == "mermaid")
    #expect(segments.map { layout.text.attributedSubstring(from: $0.range).string }.joined() == layout.text.string)
    let range = (layout.text.string as NSString).range(of: "后文中的评价")
    let selection = AgentChatReplySelection(range: range, renderedText: layout.text.string)
    #expect(AgentChatReplyQuotation.passage(selection, in: source) != nil)
  }

  @Test func viewedIsPerReceiptAndNotAnOutcome() {
    let triptych = UUID(), note = UUID()
    func change(_ state: AgentChangeRecoveryState) -> AgentChange {
      .init(id: UUID(), triptychID: triptych, operation: .update, noteID: note, role: .sourceCorpus,
        originalRelativePath: "A.md", finalRelativePath: "A.md", beforeFingerprint: nil,
        afterFingerprint: nil, state: state, createdAt: Date(), confirmedAt: nil, undoneAt: nil)
    }
    let first = change(.confirmed), next = change(.confirmed), undone = change(.undone), uncertain = change(.outcomeUncertain)
    let all = [first, next, undone, uncertain]
    var ledger = AgentChangeViewedLedger()
    ledger.setViewed(true, id: first.id)
    let restored = AgentChangeViewedLedger(data: ledger.data)
    #expect(restored.pending(all, receiptIDs: Set(all.map(\.id))).map(\.id) == [next.id])
    ledger.setViewed(false, id: first.id)
    #expect(ledger.pending(all, receiptIDs: [first.id]).map(\.id) == [first.id])
    #expect(first.state == .confirmed && uncertain.state == .outcomeUncertain)
  }
}
