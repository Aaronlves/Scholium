import AppKit
import Testing

@testable import ScholiumApp

@Suite("Chat native wheel host", .serialized)
@MainActor
struct AgentChatScrollHostTests {
    private final class ScrollProbe: NSScrollView {
        var events: [NSEvent] = []
        override func scrollWheel(with event: NSEvent) { events.append(event) }
    }

    @MainActor
    private final class Fixture {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
        let host = AgentChatScrollHost(relinquishesToolbarInput: true)
        let conversation = ScrollProbe(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 1200))
        let boundary = AgentChatScrollBoundary.BoundaryView()
        init() {
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.showsChat = true
            host.addSubview(conversation)
            conversation.documentView = document
            document.addSubview(boundary)
            window.contentView?.layoutSubtreeIfNeeded()
        }
        func close() {
            boundary.retire()
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        func event(at point: NSPoint = NSPoint(x: 30, y: 30), x: Int32 = 0, y: Int32 = 8, phase: Int64 = 1, momentum: Int64 = 0) throws -> NSEvent {
            let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0))
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
            let screenPoint = window.convertPoint(toScreen: point)
            cg.location = CGPoint(x: screenPoint.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - screenPoint.y)
            let event = try #require(NSEvent(cgEvent: cg))
            #expect(abs(event.locationInWindow.x - point.x) < 0.1 && abs(event.locationInWindow.y - point.y) < 0.1)
            return event
        }
        // Avoid nested application event loops in Swift Testing. Exercise the
        // override's event projection directly; the isolated
        // Release journey owns NSWindow delivery and real WebKit lifetime.
        func hit(_ event: NSEvent) -> NSView? {
            host.hitTest(event.locationInWindow, event: event)
        }
    }

    @Test("The native wheel hit retains the stable pane, while pointer input still reaches transient content")
    func wheelHitIsStableAndPointerIsNative() throws {
        _ = NSApplication.shared
        let fixture = Fixture()
        defer { fixture.close() }
        weak var departed: NSView?
        var retainedNativeHit: NSView?
        try autoreleasepool {
            let reply = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 160))
            departed = reply
            fixture.document.addSubview(reply)
            let mouse = try #require(
                NSEvent.mouseEvent(
                    with: .leftMouseDown, location: NSPoint(x: 30, y: 30), modifierFlags: [], timestamp: 0, windowNumber: fixture.window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            let mouseHit = fixture.hit(mouse)
            let hit = try #require(mouseHit)
            #expect(hit === reply || hit.isDescendant(of: reply))
            retainedNativeHit = try fixture.hit(fixture.event())
            #expect(retainedNativeHit === fixture.host)
            fixture.boundary.retire()
            reply.removeFromSuperview()
        }
        #expect(retainedNativeHit === fixture.host && departed == nil)
    }

    @Test("A retiring presentation consumes its owned tail without scrolling its replacement")
    func retiringBoundaryRevokesRecipient() throws {
        _ = NSApplication.shared
        let fixture = Fixture()
        defer { fixture.close() }
        let begin = try fixture.event()
        #expect(fixture.hit(begin) === fixture.host)
        fixture.host.scrollWheel(with: begin)
        #expect(fixture.conversation.events.count == 1)
        fixture.boundary.retire()
        fixture.host.showsChat = false
        for event in [
            try fixture.event(phase: 2), try fixture.event(y: 0, phase: 4), try fixture.event(phase: 0, momentum: 1),
            try fixture.event(y: 0, phase: 0, momentum: 3),
        ] {
            #expect(fixture.hit(event) === fixture.host)
            fixture.host.scrollWheel(with: event)
        }
        #expect(fixture.conversation.events.count == 1)
        let newBegin = try fixture.event()
        #expect(fixture.hit(newBegin) === fixture.host)
        fixture.host.scrollWheel(with: newBegin)
        #expect(fixture.conversation.events.count == 2)
    }

    @Test("A composer or Library gesture retains its own native recipient when crossing into the transcript", arguments: [false, true])
    func nativeGestureKeepsItsRecipient(library: Bool) throws {
        _ = NSApplication.shared
        let fixture = Fixture()
        defer { fixture.close() }
        let composer = ScrollProbe(frame: NSRect(x: 0, y: 300, width: 400, height: 100))
        composer.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
        fixture.host.addSubview(composer)
        if library { fixture.host.showsChat = false }
        let events = [
            try fixture.event(at: NSPoint(x: 30, y: 350), y: 0, phase: 128),
            try fixture.event(), try fixture.event(phase: 2), try fixture.event(y: 0, phase: 4),
            try fixture.event(phase: 0, momentum: 1), try fixture.event(y: 0, phase: 0, momentum: 3),
        ]
        for event in events {
            #expect(fixture.hit(event) === fixture.host)
            fixture.host.scrollWheel(with: event)
        }
        #expect(composer.events.elementsEqual(events, by: { $0 === $1 }))
        #expect(fixture.conversation.events.isEmpty)
        // A new real start replaces the previous weak recipient.
        let begin = try fixture.event()
        #expect(fixture.hit(begin) === fixture.host)
        fixture.host.scrollWheel(with: begin)
        #expect(fixture.conversation.events.count == 1)
    }

    @Test("Switching either Sidebar page revokes the former native recipient", arguments: [false, true])
    func changingPagesRevokesNativeTail(startInChat: Bool) throws {
        _ = NSApplication.shared
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.boundary.retire()
        fixture.host.showsChat = startInChat
        let begin = try fixture.event()
        #expect(fixture.hit(begin) === fixture.host)
        fixture.host.scrollWheel(with: begin)
        #expect(fixture.conversation.events.count == 1)
        fixture.host.showsChat = !startInChat
        let tail = try fixture.event(phase: 2)
        #expect(fixture.hit(tail) === fixture.host)
        fixture.host.scrollWheel(with: tail)
        #expect(fixture.conversation.events.count == 1)
        let next = try fixture.event()
        fixture.host.scrollWheel(with: next)
        #expect(fixture.conversation.events.count == 2)
    }

    @Test("Native mayBegin and began keep the same transcript recipient")
    func mayBeginKeepsItsNativeRecipient() throws {
        _ = NSApplication.shared
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.host.addSubview(NSView(frame: NSRect(x: 0, y: 300, width: 400, height: 100)))
        let mayBegin = try fixture.event(y: 0, phase: 128)
        #expect(fixture.hit(mayBegin) === fixture.host)
        fixture.host.scrollWheel(with: mayBegin)
        let begin = try fixture.event(at: NSPoint(x: 30, y: 350))
        #expect(fixture.hit(begin) === fixture.host)
        fixture.host.scrollWheel(with: begin)
        #expect(fixture.conversation.events.elementsEqual([mayBegin, begin], by: { $0 === $1 }))
    }

    @Test("Native horizontal detail scrolling remains local and locks one recipient")
    func horizontalNativeDetailKeepsItsEvents() throws {
        _ = NSApplication.shared
        let fixture = Fixture()
        defer { fixture.close() }
        let detail = ScrollProbe(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        detail.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 100))
        fixture.document.addSubview(detail)
        let events = [
            try fixture.event(x: 9, y: 0), try fixture.event(x: 9, y: 0, phase: 2), try fixture.event(y: 0, phase: 4),
            try fixture.event(x: 9, y: 0, phase: 0, momentum: 1), try fixture.event(y: 0, phase: 0, momentum: 3),
        ]
        for event in events {
            #expect(fixture.hit(event) === fixture.host)
            fixture.host.scrollWheel(with: event)
        }
        #expect(detail.events.elementsEqual(events, by: { $0 === $1 }))
        #expect(fixture.conversation.events.isEmpty)
    }

    @Test("A local vertical scroll view receives its events and the native scroller remains a pointer target")
    func nativeLocalScrollAndScrollerHits() throws {
        _ = NSApplication.shared
        let fixture = Fixture()
        defer { fixture.close() }
        let detail = ScrollProbe(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        detail.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 600))
        fixture.document.addSubview(detail)
        let localHit = try fixture.hit(fixture.event())
        let hit = try #require(localHit)
        #expect(hit === fixture.host)
        let event = try fixture.event()
        fixture.host.scrollWheel(with: event)
        #expect(detail.events.count == 1 && fixture.conversation.events.isEmpty)
        detail.removeFromSuperview()
        fixture.conversation.hasVerticalScroller = true
        fixture.conversation.scrollerStyle = .legacy
        fixture.conversation.autohidesScrollers = false
        fixture.conversation.tile()
        let bar = try #require(fixture.conversation.verticalScroller)
        let point = bar.convert(NSPoint(x: bar.bounds.midX, y: bar.bounds.midY), to: nil)
        let click = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: fixture.window.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1))
        #expect(fixture.hit(click) === bar)
    }

    @Test("A zero-delta native momentum sequence preserves both real boundaries")
    func zeroDeltaMomentumKeepsBoundaries() throws {
        _ = NSApplication.shared
        let fixture = Fixture()
        defer { fixture.close() }
        let route = AgentChatWheelRoute()
        let events = [try fixture.event(y: 0, phase: 0, momentum: 1), try fixture.event(y: 0, phase: 0, momentum: 3)]
        for event in events {
            let handled = route.dispatch(event, targets: AgentChatWheelTargets(horizontal: fixture.document, vertical: fixture.conversation))
            #expect(handled)
        }
        #expect(fixture.conversation.events.elementsEqual(events, by: { $0 === $1 }))
    }
}
