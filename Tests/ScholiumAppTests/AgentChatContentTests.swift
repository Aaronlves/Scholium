import AppKit
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Chat content and viewed changes")
@MainActor
struct AgentChatContentTests {
    @Test func richReplyForwardsCompleteVerticalGesture() throws {
        _ = NSApplication.shared
        let route = AgentChatWheelRoute()
        let horizontal = ScrollProbe()
        let scroll = ScrollProbe()
        func event(_ y: Int32, _ x: Int32, phase: Int64, momentum: Int64 = 0) throws -> NSEvent {
            let cg = try #require(
                CGEvent(
                    scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                    wheel1: y, wheel2: x, wheel3: 0))
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
            return try #require(NSEvent(cgEvent: cg))
        }
        let begin = try event(12, 0, phase: 1)
        let end = try event(0, 0, phase: 4)
        #expect(begin.phase.contains(.began) && end.phase.contains(.ended))
        for value in [
            begin, try event(3, 5, phase: 2), end,
            try event(6, 0, phase: 0, momentum: 1), try event(0, 0, phase: 0, momentum: 3),
        ] {
            #expect(route.dispatch(value, inlineTarget: horizontal, conversation: scroll))
        }
        #expect(scroll.events.count == 5)
        #expect(scroll.events[2].phase.contains(.ended))
        #expect(scroll.events.last?.momentumPhase.contains(.ended) == true)
        // A new horizontal gesture belongs wholly to WebKit, including its zero-delta end.
        #expect(route.dispatch(try event(0, 0, phase: 1), inlineTarget: horizontal, conversation: scroll))
        #expect(route.dispatch(try event(0, 10, phase: 2), inlineTarget: horizontal, conversation: scroll))
        #expect(route.dispatch(try event(7, 2, phase: 2), inlineTarget: horizontal, conversation: scroll))
        #expect(route.dispatch(end, inlineTarget: horizontal, conversation: scroll))
        #expect(horizontal.events.count == 4 && scroll.events.count == 5)
        route.reset()
        #expect(!route.dispatch(begin, inlineTarget: nil, conversation: scroll))
    }

    private final class ScrollProbe: NSScrollView {
        var events: [NSEvent] = []
        override func scrollWheel(with event: NSEvent) { events.append(event) }
    }

    @Test func expandedObjectIsTransientCard() async throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let source = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        window.contentView = source
        window.makeKeyAndOrderFront(nil)
        let controller = AgentChatRichPreviewController()
        defer {
            controller.close()
            window.close()
        }
        controller.present(
            content: Text("Fixture"), naturalSize: CGSize(width: 400, height: 80),
            anchor: NSRect(x: 100, y: 100, width: 24, height: 24), of: source)
        let popover = try #require(controller.popover)
        #expect(popover.behavior == .transient && popover.isShown)
        controller.close()
        for _ in 0..<100 where popover.isShown { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!popover.isShown)
    }

    @Test func expandedCardFitsContentAndBoundsLargeObjects() {
        let available = CGSize(width: 1400, height: 900)
        let small = AgentChatRichPreviewController.fittedSize(CGSize(width: 380, height: 70), available: available)
        #expect(small == CGSize(width: 412, height: 150))
        let large = AgentChatRichPreviewController.fittedSize(CGSize(width: 5000, height: 4000), available: available)
        #expect(large == CGSize(width: 1190, height: 765))
    }

    @Test func inlineCodeUsesNativeBackground() {
        let rendered = AgentChatObjectProjection.layoutReply("普通 `concept` 文字").text
        let range = (rendered.string as NSString).range(of: "concept")
        #expect(rendered.attribute(.backgroundColor, at: range.location, effectiveRange: nil) as? NSColor == .quaternaryLabelColor)
        #expect(rendered.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
    }

    @Test func richSegmentsPreserveObjectContent() throws {
        let source = "前文 😀\n\n| 概念 | 理由 |\n|---|---|\n|情绪|评价|\n\n后文中的评价。\n\n```mermaid\ngraph LR\nA --> B\n```"
        let layout = AgentChatObjectProjection.layoutReply(source)
        let segments = AgentChatRichSegment.collect(layout)
        #expect(segments.count == 4)
        #expect(segments[1].columns == 2)
        #expect(segments.last?.language == "mermaid")
        #expect(segments.map { layout.text.attributedSubstring(from: $0.range).string }.joined() == layout.text.string)
    }

    @Test func viewedIsPerReceiptAndNotAnOutcome() {
        let triptych = UUID()
        let note = UUID()
        func change(_ state: AgentChangeRecoveryState) -> AgentChange {
            .init(
                id: UUID(), triptychID: triptych, operation: .update, noteID: note, role: .sourceCorpus,
                originalRelativePath: "A.md", finalRelativePath: "A.md", beforeFingerprint: nil,
                afterFingerprint: nil, state: state, createdAt: Date(), confirmedAt: nil, undoneAt: nil)
        }
        let first = change(.confirmed)
        let next = change(.confirmed)
        let undone = change(.undone)
        let uncertain = change(.outcomeUncertain)
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
