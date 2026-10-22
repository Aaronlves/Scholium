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
            #expect(route.dispatch(value, targets: wheelTargets(horizontal, scroll)))
        }
        #expect(scroll.events.count == 5)
        #expect(scroll.events[2].phase.contains(.ended))
        #expect(scroll.events.last?.momentumPhase.contains(.ended) == true)
        // A new horizontal gesture belongs wholly to WebKit, including its zero-delta end.
        #expect(route.dispatch(try event(0, 0, phase: 1), targets: wheelTargets(horizontal, scroll)))
        #expect(route.dispatch(try event(0, 10, phase: 2), targets: wheelTargets(horizontal, scroll)))
        #expect(route.dispatch(try event(7, 2, phase: 2), targets: wheelTargets(horizontal, scroll)))
        #expect(route.dispatch(end, targets: wheelTargets(horizontal, scroll)))
        #expect(horizontal.events.count == 4 && scroll.events.count == 5)
        route.reset()
        #expect(!route.dispatch(begin, targets: wheelTargets(nil, scroll)))
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
            let handled = route.dispatch(begin, targets: wheelTargets(target(), conversation))
            #expect(handled)
            events += 1
            for _ in 0..<96 {
                let change = try event(horizontal ? 1 : 6, horizontal ? 6 : 1, phase: 2)
                let handled = route.dispatch(change, targets: wheelTargets(target(), conversation))
                #expect(handled)
                events += 1
            }
            for boundary in [
                try event(0, 0, phase: 4),
                try event(horizontal ? 1 : 6, horizontal ? 6 : 1, phase: 0, momentum: 1),
                try event(0, 0, phase: 0, momentum: 3),
            ] {
                let handled = route.dispatch(boundary, targets: wheelTargets(target(), conversation))
                #expect(handled)
                events += 1
            }
        }
        print("CHAT_WHEEL_TARGET events=\(events) target_lookups=\(lookups) gestures=3 evidence=dispatch_work_not_paint")
        #expect(lookups == 3)
        #expect(conversation.events.count == 200 && inline.events.count == 100)
        let beforeUnphased = lookups
        for _ in 0..<3 {
            let handled = route.dispatch(try event(4, 0, phase: 0), targets: wheelTargets(target(), conversation))
            #expect(handled)
        }
        #expect(lookups - beforeUnphased == 3, "Each ordinary wheel event remains independently targeted")
    }

    @Test("An ineligible gesture remains platform-owned through its terminal events", arguments: [false, true])
    func ineligibleWheelGestureNeverChangesOwner(includesMayBegin: Bool) throws {
        let route = AgentChatWheelRoute()
        let conversation = ScrollProbe()
        let inline = ScrollProbe()
        var eligible = false
        var lookups = 0
        func target() -> NSView? {
            lookups += 1
            return eligible ? inline : nil
        }
        if includesMayBegin {
            let mayBegin = try wheelEvent(0, 0, phase: 128)
            // Dispatch before #expect so its macro cannot eagerly evaluate the targets autoclosure.
            let handled = route.dispatch(mayBegin, targets: wheelTargets(target(), conversation))
            #expect(!handled)
            eligible = true
        }
        let begin = try wheelEvent(0, 0, phase: 1)
        let beginHandled = route.dispatch(begin, targets: wheelTargets(target(), conversation))
        #expect(!beginHandled)
        eligible = true
        for event in [
            try wheelEvent(8, 0, phase: 2, shift: true),
            try wheelEvent(0, 0, phase: 4),
            try wheelEvent(0, 9, phase: 0, momentum: 1),
            try wheelEvent(0, 9, phase: 0, momentum: 2),
            try wheelEvent(0, 0, phase: 0, momentum: 3),
        ] {
            let handled = route.dispatch(event, targets: wheelTargets(target(), conversation))
            #expect(!handled)
        }
        #expect(lookups == 1, "A nil initial lookup is a latched platform owner, not an unresolved recipient")
        #expect(inline.events.isEmpty && conversation.events.isEmpty)
        let next = try wheelEvent(0, 9, phase: 1)
        let nextHandled = route.dispatch(next, targets: wheelTargets(target(), conversation))
        #expect(nextHandled)
        #expect(lookups == 2 && inline.events.count == 1 && inline.events[0] === next)
    }

    @Test("mayBegin and began share one recipient and preserve both zero-delta boundaries")
    func wheelMayBeginDoesNotRestartOwnership() throws {
        let route = AgentChatWheelRoute()
        let inline = ScrollProbe()
        let replacement = ScrollProbe()
        let conversation = ScrollProbe()
        var lookups = 0
        func target() -> NSView? {
            lookups += 1
            return lookups == 1 ? inline : replacement
        }
        let events = [
            try wheelEvent(0, 0, phase: 128),
            try wheelEvent(0, 0, phase: 1),
            try wheelEvent(8, 0, phase: 2, shift: true),
            try wheelEvent(0, 0, phase: 8),
        ]
        for event in events {
            let handled = route.dispatch(event, targets: wheelTargets(target(), conversation))
            #expect(handled)
        }
        #expect(lookups == 1, "began must continue the already-owned mayBegin preface")
        #expect(inline.events.elementsEqual(events, by: { $0 === $1 }))
        #expect(replacement.events.isEmpty && conversation.events.isEmpty)
        let orphanedChange = try wheelEvent(0, 9, phase: 2)
        let orphanHandled = route.dispatch(orphanedChange, targets: wheelTargets(target(), conversation))
        #expect(!orphanHandled)
        #expect(lookups == 1, "A changed event after cancellation cannot create another gesture")
        let next = try wheelEvent(0, 9, phase: 1)
        let nextHandled = route.dispatch(next, targets: wheelTargets(target(), conversation))
        #expect(nextHandled)
        #expect(lookups == 2 && replacement.events.count == 1 && replacement.events[0] === next)
    }

    @Test("A mayBegin preface can terminate without began", arguments: [Int64(4), Int64(8)])
    func wheelMayBeginCanTerminateWithoutBegan(terminalPhase: Int64) throws {
        let route = AgentChatWheelRoute()
        let inline = ScrollProbe()
        let conversation = ScrollProbe()
        var lookups = 0
        func target() -> NSView? {
            lookups += 1
            return inline
        }
        let events = [try wheelEvent(0, 0, phase: 128), try wheelEvent(0, 0, phase: terminalPhase)]
        for event in events {
            let handled = route.dispatch(event, targets: wheelTargets(target(), conversation))
            #expect(handled)
        }
        #expect(lookups == 1 && inline.events.isEmpty)
        #expect(conversation.events.elementsEqual(events, by: { $0 === $1 }))
    }

    @Test("A departed weak recipient cannot hand a gesture to another view")
    func wheelWeakRecipientLossKeepsOwnership() throws {
        let route = AgentChatWheelRoute()
        let conversation = ScrollProbe()
        var inline: ScrollProbe?
        weak var departed: ScrollProbe?
        var lookups = 0
        func target() -> NSView? {
            lookups += 1
            return inline
        }
        try autoreleasepool {
            inline = ScrollProbe()
            departed = inline
            let begin = try wheelEvent(8, 0, phase: 1, shift: true)
            let handled = route.dispatch(begin, targets: wheelTargets(target(), conversation))
            #expect(handled)
            #expect(inline?.events.count == 1 && conversation.events.isEmpty)
            inline = nil
        }
        #expect(departed == nil, "Gesture ownership must not retain a removed native reader")
        inline = ScrollProbe()
        for event in [
            try wheelEvent(8, 0, phase: 2),
            try wheelEvent(0, 0, phase: 4),
            try wheelEvent(0, 9, phase: 0, momentum: 1),
            try wheelEvent(0, 9, phase: 0, momentum: 2),
            try wheelEvent(0, 0, phase: 0, momentum: 3),
        ] {
            let handled = route.dispatch(event, targets: wheelTargets(target(), conversation))
            #expect(handled)
        }
        #expect(lookups == 1 && inline?.events.isEmpty == true && conversation.events.isEmpty)
        let next = try wheelEvent(8, 0, phase: 1)
        let nextHandled = route.dispatch(next, targets: wheelTargets(target(), conversation))
        #expect(nextHandled)
        #expect(lookups == 2 && conversation.events.count == 1)
    }

    @Test("An orphaned changed tail remains platform-owned even when momentum begins", arguments: [false, true])
    func wheelOrphanedContinuationRemainsPlatformOwned(startsDuringMomentum: Bool) throws {
        let route = AgentChatWheelRoute()
        let inline = ScrollProbe()
        let conversation = ScrollProbe()
        var lookups = 0
        func target() -> NSView? {
            lookups += 1
            return inline
        }
        var events = [NSEvent]()
        if !startsDuringMomentum {
            events += [
                try wheelEvent(8, 0, phase: 2), try wheelEvent(0, 0, phase: 4),
                try wheelEvent(8, 0, phase: 0, momentum: 1),
            ]
        }
        events += [
            try wheelEvent(8, 0, phase: 0, momentum: 2),
            try wheelEvent(0, 0, phase: 0, momentum: 3),
        ]
        for _ in 0..<2 {
            for event in events {
                let handled = route.dispatch(event, targets: wheelTargets(target(), conversation))
                #expect(!handled)
            }
            route.reset()
        }
        #expect(lookups == 0 && inline.events.isEmpty && conversation.events.isEmpty)
        let next = try wheelEvent(8, 0, phase: 1)
        let nextHandled = route.dispatch(next, targets: wheelTargets(target(), conversation))
        #expect(nextHandled)
        #expect(lookups == 1 && conversation.events.count == 1)
    }

    @Test("Abandoning a page consumes its gesture tail without retargeting", arguments: [false, true])
    func wheelAbandonedRecipientKeepsOwnership(abandonsBeforeFirstDelta: Bool) throws {
        let route = AgentChatWheelRoute()
        let oldInline = ScrollProbe()
        let oldConversation = ScrollProbe()
        let newInline = ScrollProbe()
        let newConversation = ScrollProbe()
        var inline = oldInline
        var conversation = oldConversation
        var lookups = 0
        func targets() -> AgentChatWheelTargets? {
            lookups += 1
            return wheelTargets(inline, conversation)
        }
        let begin = try wheelEvent(abandonsBeforeFirstDelta ? 0 : 8, 0, phase: 1)
        let beginHandled = route.dispatch(begin, targets: targets())
        #expect(beginHandled)
        inline = newInline
        conversation = newConversation
        route.abandonRecipient()
        for event in [
            try wheelEvent(0, 9, phase: 2),
            try wheelEvent(0, 0, phase: 4),
            try wheelEvent(0, 9, phase: 0, momentum: 1),
            try wheelEvent(0, 9, phase: 0, momentum: 2),
            try wheelEvent(0, 0, phase: 0, momentum: 3),
        ] {
            let handled = route.dispatch(event, targets: targets())
            #expect(handled)
        }
        let expectedOld = abandonsBeforeFirstDelta ? [] : [begin]
        #expect(oldConversation.events.elementsEqual(expectedOld, by: { $0 === $1 }))
        #expect(oldInline.events.isEmpty && newInline.events.isEmpty && newConversation.events.isEmpty)
        #expect(lookups == 1, "Neither a surviving old page nor its replacement can receive the abandoned tail")
        let next = try wheelEvent(8, 0, phase: 1)
        let nextHandled = route.dispatch(next, targets: targets())
        #expect(nextHandled)
        #expect(lookups == 2 && newConversation.events.count == 1 && newConversation.events[0] === next)
    }

    @Test("A zero-delta begin weakly locks its original conversation before direction is known")
    func wheelZeroDeltaBeginKeepsOriginalConversation() throws {
        let route = AgentChatWheelRoute()
        let inline = ScrollProbe()
        let replacement = ScrollProbe()
        var original: ScrollProbe?
        weak var departed: ScrollProbe?
        var conversation = replacement
        var lookups = 0
        func targets() -> AgentChatWheelTargets? {
            lookups += 1
            return wheelTargets(inline, conversation)
        }
        try autoreleasepool {
            original = ScrollProbe()
            departed = original
            conversation = try #require(original)
            let begin = try wheelEvent(0, 0, phase: 1)
            let beginHandled = route.dispatch(begin, targets: targets())
            #expect(beginHandled)
            conversation = replacement
            let change = try wheelEvent(8, 0, phase: 2)
            let changeHandled = route.dispatch(change, targets: targets())
            #expect(changeHandled)
            #expect(original?.events.elementsEqual([begin, change], by: { $0 === $1 }) == true)
            #expect(replacement.events.isEmpty && inline.events.isEmpty && lookups == 1)
            original = nil
        }
        #expect(departed == nil, "The captured conversation must remain weak after recipient selection")
        for event in [
            try wheelEvent(8, 0, phase: 2), try wheelEvent(0, 0, phase: 4),
            try wheelEvent(8, 0, phase: 0, momentum: 1), try wheelEvent(0, 0, phase: 0, momentum: 3),
        ] {
            let handled = route.dispatch(event, targets: targets())
            #expect(handled)
        }
        #expect(lookups == 1 && replacement.events.isEmpty && inline.events.isEmpty)
    }

    @Test("An independent native momentum begin owns the complete gesture", arguments: [false, true])
    func wheelMomentumBeginCanStartOwnership(horizontal: Bool) throws {
        let route = AgentChatWheelRoute()
        let inline = ScrollProbe()
        let conversation = ScrollProbe()
        var lookups = 0
        func targets() -> AgentChatWheelTargets? {
            lookups += 1
            return wheelTargets(inline, conversation)
        }
        let events = [
            try wheelEvent(0, 0, phase: 0, momentum: 1),
            try wheelEvent(horizontal ? 1 : 9, horizontal ? 9 : 1, phase: 0, momentum: 2),
            try wheelEvent(horizontal ? 9 : 1, horizontal ? 1 : 9, phase: 0, momentum: 2),
            try wheelEvent(0, 0, phase: 0, momentum: 3),
        ]
        for event in events {
            let handled = route.dispatch(event, targets: targets())
            #expect(handled)
        }
        let recipient = horizontal ? inline : conversation
        let other = horizontal ? conversation : inline
        #expect(recipient.events.elementsEqual(events, by: { $0 === $1 }))
        #expect(other.events.isEmpty && lookups == 1)
        let next = try wheelEvent(horizontal ? 9 : 1, horizontal ? 1 : 9, phase: 0, momentum: 1)
        let nextHandled = route.dispatch(next, targets: targets())
        #expect(nextHandled)
        #expect(lookups == 2 && other.events.count == 1 && other.events[0] === next)
    }

    @Test("Momentum began preserves an existing touch recipient despite a different direction and page")
    func wheelMomentumBeginDoesNotReplaceTouchOwner() throws {
        let route = AgentChatWheelRoute()
        let inline = ScrollProbe()
        let conversation = ScrollProbe()
        let replacement = ScrollProbe()
        var lookups = 0
        func targets() -> AgentChatWheelTargets? {
            lookups += 1
            return wheelTargets(lookups == 1 ? inline : replacement, conversation)
        }
        let events = [
            try wheelEvent(0, 9, phase: 1), try wheelEvent(0, 0, phase: 4),
            try wheelEvent(9, 0, phase: 0, momentum: 1),
            try wheelEvent(9, 0, phase: 0, momentum: 2),
            try wheelEvent(0, 0, phase: 0, momentum: 3),
        ]
        for event in events {
            let handled = route.dispatch(event, targets: targets())
            #expect(handled)
        }
        #expect(inline.events.elementsEqual(events, by: { $0 === $1 }))
        #expect(conversation.events.isEmpty && replacement.events.isEmpty && lookups == 1)
    }

    @Test("Independent ordinary wheel events preserve an existing phased recipient")
    func ordinaryWheelDoesNotErasePhasedOwnership() throws {
        let route = AgentChatWheelRoute()
        let inline = ScrollProbe()
        let replacement = ScrollProbe()
        let conversation = ScrollProbe()
        var lookups = 0
        func target() -> NSView? {
            lookups += 1
            return lookups == 1 ? inline : replacement
        }
        let begin = try wheelEvent(0, 9, phase: 1)
        let beginHandled = route.dispatch(begin, targets: wheelTargets(target(), conversation))
        #expect(beginHandled)
        let ordinaryVertical = try wheelEvent(8, 0, phase: 0)
        let verticalHandled = route.dispatch(ordinaryVertical, targets: wheelTargets(target(), conversation))
        #expect(verticalHandled)
        let ordinaryShift = try wheelEvent(8, 0, phase: 0, shift: true)
        let shiftHandled = route.dispatch(ordinaryShift, targets: wheelTargets(target(), conversation))
        #expect(shiftHandled)
        let ineligibleOrdinary = try wheelEvent(8, 0, phase: 0)
        let ineligibleHandled = route.dispatch(ineligibleOrdinary, targets: wheelTargets(nil, conversation))
        #expect(!ineligibleHandled)
        let tail = [
            try wheelEvent(8, 0, phase: 2),
            try wheelEvent(0, 0, phase: 4),
            try wheelEvent(8, 0, phase: 0, momentum: 1),
            try wheelEvent(0, 0, phase: 0, momentum: 3),
        ]
        for event in tail {
            let handled = route.dispatch(event, targets: wheelTargets(target(), conversation))
            #expect(handled)
        }
        #expect(lookups == 3)
        #expect(inline.events.elementsEqual([begin] + tail, by: { $0 === $1 }))
        #expect(conversation.events.count == 1 && conversation.events[0] === ordinaryVertical)
        #expect(replacement.events.count == 1 && replacement.events[0] === ordinaryShift)
    }

    private func wheelTargets(_ inline: NSView?, _ conversation: NSScrollView) -> AgentChatWheelTargets? {
        inline.map { AgentChatWheelTargets(horizontal: $0, vertical: conversation) }
    }

    private func wheelEvent(_ y: Int32, _ x: Int32, phase: Int64, momentum: Int64 = 0, shift: Bool = false) throws -> NSEvent {
        let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0))
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        if shift { cg.flags.insert(.maskShift) }
        let event = try #require(NSEvent(cgEvent: cg))
        let expectedPhase: NSEvent.Phase =
            switch phase {
            case 0: []
            case 1: .began
            case 2: .changed
            case 4: .ended
            case 8: .cancelled
            case 128: .mayBegin
            default: throw CocoaError(.coderInvalidValue)
            }
        let expectedMomentum: NSEvent.Phase =
            switch momentum {
            case 0: []
            case 1: .began
            case 2: .changed
            case 3: .ended
            default: throw CocoaError(.coderInvalidValue)
            }
        try #require(event.phase == expectedPhase && event.momentumPhase == expectedMomentum)
        return event
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
        let snapshot = AgentChatReplyProjection.Snapshot(.init(source))
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
