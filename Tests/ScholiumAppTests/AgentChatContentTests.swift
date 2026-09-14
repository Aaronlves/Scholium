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

    @Test func expandedObjectsShareOneParentedPreviewAndEscapeCloses() throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let input = NSTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        window.contentView = input
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(input)
        let first = ScholiumContentPreview(animates: false)
        let second = ScholiumContentPreview(animates: false)
        defer {
            first.close()
            second.close()
            window.close()
        }
        first.present(title: "Code", copyText: "exact fixture", from: input) { Text("Fixture") }
        let initial = try #require(first.panel)
        #expect(initial.parent === window && initial.isVisible)
        let expected = ScholiumContentPreview.previewFrame(
            parent: window.convertToScreen(window.contentLayoutRect), available: window.screen?.visibleFrame ?? window.frame)
        #expect(abs(initial.frame.width - expected.width) < 1 && abs(initial.frame.height - expected.height) < 1)
        #expect(abs(initial.frame.midX - expected.midX) < 1 && abs(initial.frame.midY - expected.midY) < 1)
        #expect(initial.standardWindowButton(.closeButton)?.isHidden != false)
        #expect(initial.standardWindowButton(.miniaturizeButton)?.isHidden != false)
        #expect(initial.standardWindowButton(.zoomButton)?.isHidden != false)
        second.present(title: "Output", copyText: "output", from: input) { Text("Output") }
        #expect(first.panel == nil && !initial.isVisible)
        let replacement = try #require(second.panel)
        #expect(window.childWindows?.filter { $0 is ScholiumContentPreview.Panel }.count == 1)
        second.update(title: "Output", copyText: "updated") { Text("Updated output") }
        #expect(second.panel === replacement)
        replacement.cancelOperation(nil)
        #expect(second.panel == nil && !replacement.isVisible)
        #expect(window.childWindows?.contains(replacement) != true)
    }

    @Test func animatedDismissalFinishesAboveParentAndRemovesThePanel() async throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        let source = try #require(window.contentView)
        let controller = ScholiumContentPreview()
        defer {
            controller.close()
            window.close()
        }
        controller.present(title: "Code", copyText: "exact", from: source) { Text("Fixture") }
        let panel = try #require(controller.panel)
        controller.dismiss()
        #expect(panel.parent === window && panel.isVisible)
        controller.dismiss()  // Repeated dismissal must not restart the closing lifecycle.
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while controller.panel != nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(controller.panel == nil && !panel.isVisible)
        #expect(panel.parent == nil)
    }

    @Test func previewDoesNotSurviveItsOrigin() throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        let controller = ScholiumContentPreview(animates: false)
        let input = try #require(window.contentView)
        controller.present(title: "Diagram", copyText: "graph LR", from: input) { Text("Fixture") }
        let panel = try #require(controller.panel)
        window.close()
        #expect(controller.panel == nil && !panel.isVisible)
    }

    @Test func immersivePreviewCentersOnOriginAndStaysInsideVisibleScreen() {
        let screen = NSRect(x: -1440, y: 40, width: 1440, height: 860)
        for parent in [
            NSRect(x: -1300, y: 100, width: 1100, height: 700),
            NSRect(x: -1800, y: -500, width: 2000, height: 1600),
        ] {
            let frame = ScholiumContentPreview.previewFrame(parent: parent, available: screen)
            #expect(screen.contains(frame))
            #expect(frame.width > 600 && frame.height > 400)
        }
        let centered = ScholiumContentPreview.previewFrame(parent: screen, available: screen)
        #expect(centered.midX == screen.midX && centered.midY == screen.midY)
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
        ledger.markViewed(id: first.id)
        let restored = AgentChangeViewedLedger(data: ledger.data)
        #expect(restored.pending(all, receiptIDs: Set(all.map(\.id))).map(\.id) == [next.id])
        ledger.markViewed(id: first.id)
        #expect(ledger.pending(all, receiptIDs: [first.id]).isEmpty)
        #expect(first.state == .confirmed && uncertain.state == .outcomeUncertain)
    }
}
