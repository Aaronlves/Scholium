import AppKit
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Chat content and scoped changes", .serialized)
@MainActor
struct AgentChatContentTests {
    @Test func objectGeometryRejectsInvalidOrAmbiguousIdentity() throws {
        let entry: [String: Any] = [
            "identity": "object-7", "left": 0.0, "top": 35.0,
            "width": 300.0, "height": 120.0, "naturalWidth": 800.0, "naturalHeight": 90.0,
        ]
        let object = try #require(ReadReplyObject.decode([entry])?.first)
        #expect(object.id == "object-7" && object.naturalSize.width == 800)
        for (key, value) in [("width", Double.nan), ("top", Double.infinity), ("height", -1.0)] {
            var bad = entry
            bad[key] = value
            #expect(ReadReplyObject.decode([bad]) == nil)
        }
        #expect(ReadReplyObject.decode([entry, entry]) == nil)
        #expect(ReadReplyObject.decode([entry.merging(["identity": ""]) { _, new in new }]) == nil)
    }

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

    @Test("A complete wheel gesture resolves its native target once, including momentum")
    func wheelGestureResolvesTargetOnce() throws {
        let route = AgentChatWheelRoute()
        let inline = ScrollProbe()
        let conversation = ScrollProbe()
        var lookups = 0
        var events = 0
        func target() -> NSView? {
            lookups += 1
            return inline
        }
        func event(_ y: Int32, _ x: Int32, phase: Int64, momentum: Int64 = 0) throws -> NSEvent {
            let cg = try #require(
                CGEvent(
                    scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                    wheel1: y, wheel2: x, wheel3: 0))
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
            return try #require(NSEvent(cgEvent: cg))
        }
        for horizontal in [false, true, false] {
            let begin = try event(0, 0, phase: 1)
            let handled = route.dispatch(begin, inlineTarget: target(), conversation: conversation)
            #expect(handled)
            events += 1
            for _ in 0..<96 {
                let change = try event(horizontal ? 1 : 6, horizontal ? 6 : 1, phase: 2)
                let handled = route.dispatch(change, inlineTarget: target(), conversation: conversation)
                #expect(handled)
                events += 1
            }
            for boundary in [
                try event(0, 0, phase: 4),
                try event(horizontal ? 1 : 6, horizontal ? 6 : 1, phase: 0, momentum: 1),
                try event(0, 0, phase: 0, momentum: 3),
            ] {
                let handled = route.dispatch(boundary, inlineTarget: target(), conversation: conversation)
                #expect(handled)
                events += 1
            }
        }
        print("CHAT_WHEEL_TARGET events=\(events) target_lookups=\(lookups) gestures=3 evidence=dispatch_work_not_paint")
        #expect(lookups == 3)
        #expect(conversation.events.count == 200 && inline.events.count == 100)
        let beforeUnphased = lookups
        for _ in 0..<3 {
            let handled = route.dispatch(try event(4, 0, phase: 0), inlineTarget: target(), conversation: conversation)
            #expect(handled)
        }
        #expect(lookups - beforeUnphased == 3, "Each ordinary wheel event remains independently targeted")
    }

    @Test("Lazy wheel lookup preserves ineligible, Shift, cancellation and weak target boundaries")
    func wheelTargetBoundaries() throws {
        let route = AgentChatWheelRoute()
        let conversation = ScrollProbe()
        var inline: ScrollProbe?
        weak var departed: ScrollProbe?
        var lookups = 0
        func target() -> NSView? {
            lookups += 1
            return inline
        }
        func event(_ y: Int32, _ x: Int32, phase: Int64, shift: Bool = false) throws -> NSEvent {
            let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0))
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            if shift { cg.flags.insert(.maskShift) }
            return try #require(NSEvent(cgEvent: cg))
        }
        try autoreleasepool {
            inline = ScrollProbe()
            departed = inline
            // A local detail scroller may initially own input. A nil lookup does
            // not consume that event or prevent a later eligible target.
            let handled1 = !route.dispatch(try event(0, 0, phase: 1), inlineTarget: nil, conversation: conversation)
            #expect(handled1)
            let handled2 = route.dispatch(try event(8, 0, phase: 2, shift: true), inlineTarget: target(), conversation: conversation)
            #expect(handled2)
            #expect(inline?.events.count == 1 && conversation.events.isEmpty)
            let handled3 = route.dispatch(try event(0, 0, phase: 8), inlineTarget: target(), conversation: conversation)
            #expect(handled3)
            #expect(lookups == 1, "Cancellation reaches the locked recipient before clearing it")
            let handled4 = route.dispatch(try event(0, 9, phase: 2), inlineTarget: target(), conversation: conversation)
            #expect(handled4)
            #expect(lookups == 2)
            inline = nil
        }
        #expect(departed == nil, "Gesture ownership must not retain a removed native reader")
        inline = ScrollProbe()
        let handled5 = route.dispatch(try event(0, 9, phase: 2), inlineTarget: target(), conversation: conversation)
        #expect(handled5)
        #expect(lookups == 3 && inline?.events.count == 1)
        route.reset()
        let handled6 = route.dispatch(try event(0, 0, phase: 128), inlineTarget: target(), conversation: conversation)
        #expect(handled6)
        let handled7 = route.dispatch(try event(0, 0, phase: 1), inlineTarget: target(), conversation: conversation)
        #expect(handled7)
        #expect(lookups == 5, "mayBegin and began retain their existing separate reset semantics")
    }

    @Test("Reader lookup skips retained disabled replies and treats each reader as a terminal node")
    func readerLookupUsesOnlyInteractiveReplyGeometry() throws {
        _ = NSApplication.shared
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let window = NSWindow(contentRect: root.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = root
        defer { window.close() }
        let visible = AgentChatReadWebView(frame: NSRect(x: 0, y: 0, width: 100, height: 100), configuration: .init())
        let retained = AgentChatReadWebView(frame: visible.frame, configuration: .init())
        root.addSubview(visible)
        root.addSubview(retained)
        retained.setChatInteractive(false)
        let inside = root.convert(NSPoint(x: 25, y: 25), to: nil)
        #expect(AgentChatScrollBoundary.BoundaryView.inlineReply(in: root, at: inside) === visible)
        let descendants = DescendantProbe(frame: visible.bounds)
        visible.addSubview(descendants)
        descendants.subtreeReads = 0
        let outside = AgentChatScrollBoundary.BoundaryView.inlineReply(in: root, at: root.convert(NSPoint(x: 150, y: 150), to: nil))
        let subtreeReads = descendants.subtreeReads
        print("CHAT_READER_TARGET replies=2 webkit_subtree_reads=\(subtreeReads) evidence=lookup_work_not_paint")
        #expect(outside == nil)
        #expect(subtreeReads == 0, "The transcript does not search WebKit's internal view tree")
        visible.setChatInteractive(false)
        #expect(AgentChatScrollBoundary.BoundaryView.inlineReply(in: root, at: inside) == nil)
    }

    private final class DescendantProbe: NSView {
        var subtreeReads = 0
        override var subviews: [NSView] {
            get {
                subtreeReads += 1
                return super.subviews
            }
            set { super.subviews = newValue }
        }
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

    @Test func richObjectsUseTheirOwnRendererPayload() throws {
        let source = "前文 😀\n\n| 概念 | 理由 |\n|---|---|\n|情绪|评价|\n\n后文中的评价。\n\n```mermaid\ngraph LR\nA --> B\n```"
        let snapshot = AgentChatReplyProjection.Snapshot(source)
        #expect(snapshot.objects.count == 2)
        let table = try #require(snapshot.objects.values.first { $0.kind == .table })
        let diagram = try #require(snapshot.objects.values.first { $0.kind == .diagram })
        #expect(table.copyText == "| 概念 | 理由 |\n|---|---|\n|情绪|评价|")
        #expect(diagram.copyText == "graph LR\nA --> B\n")
        #expect(snapshot.html.contains("data-scholium-object=\"" + table.id + "\""))
        #expect(snapshot.html.contains("data-scholium-object=\"" + diagram.id + "\""))
    }

    @Test func conversationReceiptsScopeCurrentChangesByAffectedNote() {
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
        #expect(
            DocumentChangesScope.noteIDs(
                forReceiptIDs: [first.id, next.id], in: all
            ) == [note])
        #expect(
            DocumentChangesScope.noteIDs(
                forReceiptIDs: [UUID()], in: all
            ).isEmpty)
        #expect(first.state == .confirmed && uncertain.state == .outcomeUncertain)
    }
}
