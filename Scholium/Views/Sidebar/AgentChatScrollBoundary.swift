import AppKit
import SwiftUI
import WebKit

/// One event boundary for the transcript. SwiftUI platform hosts can consume
/// wheel events before either native text or WebKit responder fallback is reached.
/// Route transcript gestures before dispatch; native details and popovers
/// retain their own normal scrolling. This view owns no offset or geometry.
struct AgentChatScrollBoundary: NSViewRepresentable {
    @Environment(\.scholiumDocumentSurfaceVisibility) private var surfaceVisibility
    @Environment(\.isEnabled) private var isEnabled
    func makeNSView(context: Context) -> BoundaryView { BoundaryView() }
    func updateNSView(_ view: BoundaryView, context: Context) { view.setActive(surfaceVisibility.isActive && isEnabled) }
    static func dismantleNSView(_ view: BoundaryView, coordinator: ()) { view.invalidate() }

    final class BoundaryView: NSView {
        private var monitor: Any?
        private var route = AgentChatWheelRoute()
        private(set) var isActive = true
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateMonitor()
        }
        func setActive(_ active: Bool) {
            guard isActive != active else { return }
            isActive = active
            updateMonitor()
        }
        private func updateMonitor() {
            invalidate()
            guard isActive, window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDown]) { [weak self] event in
                guard let self else { return event }
                return self.routeEvent(event)
            }
        }
        func invalidate() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            route.reset()
        }
        private func routeEvent(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window, !isHiddenOrHasHiddenAncestor,
                let scroll = enclosingScrollView, let content = window.contentView
            else {
                route.reset()
                return event
            }
            if event.type == .leftMouseDown {
                // The platform content group can also mask the overlay scroller.
                // Delegate its real hit region to AppKit's own tracking loop.
                if let bar = scroll.verticalScroller, bar.isEnabled, !bar.isHidden,
                    bar.bounds.contains(bar.convert(event.locationInWindow, from: nil))
                {
                    bar.mouseDown(with: event)
                    return nil
                }
                return event
            }
            return route.dispatch(
                event, inlineTarget: inlineTarget(for: event, conversation: scroll, content: content), conversation: scroll
            ) ? nil : event
        }

        private func inlineTarget(for event: NSEvent, conversation scroll: NSScrollView, content: NSView) -> NSView? {
            let hit = content.hitTest(content.convert(event.locationInWindow, from: nil))
            // SwiftUI's platform group can terminate hitTest before the embedded
            // WKContentView. Locate the typed reader by native visible geometry,
            // clipped to the transcript above its composer inset.
            var viewport = scroll.contentView.bounds
            let insets = scroll.contentInsets
            viewport.origin.y += scroll.contentView.isFlipped ? insets.top : insets.bottom
            viewport.size.height = max(0, viewport.height - insets.top - insets.bottom)
            let point = scroll.contentView.convert(event.locationInWindow, from: nil)
            let nested = (hit as? NSScrollView) ?? hit?.enclosingScrollView
            let ownsLocalVerticalScroll =
                nested.map {
                    $0 !== scroll && ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 1
                } ?? false
            let eligible = viewport.contains(point) && !(hit is NSScroller) && !ownsLocalVerticalScroll
            let reply = eligible ? Self.inlineReply(in: scroll.documentView, at: event.locationInWindow) : nil
            let target =
                reply.flatMap { view in
                    view.hitTest(view.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow)
                } ?? reply ?? hit ?? scroll
            return eligible ? target : nil
        }
        static func inlineReply(in root: NSView?, at windowPoint: NSPoint) -> AgentChatReadWebView? {
            guard let root, !root.isHiddenOrHasHiddenAncestor else { return nil }
            if let reply = root as? AgentChatReadWebView {
                // Disabled disclosures retain their readers and selection, but
                // cannot own input. WebKit's internal descendants never identify
                // another Chat reply, including when this reply is offscreen.
                return reply.isChatInteractive && reply.bounds.contains(reply.convert(windowPoint, from: nil)) ? reply : nil
            }
            for child in root.subviews.reversed() {
                if let found = inlineReply(in: child, at: windowPoint) { return found }
            }
            return nil
        }
    }
}

/// Latches one native recipient for a whole gesture, including zero-delta
/// boundaries and momentum. No synthetic deltas, timers or offset writes.
@MainActor
final class AgentChatWheelRoute {
    private enum Owner { case platform, transcript }
    private var owner: Owner?
    private var awaitingBegan = false
    private var recipientSelected = false
    private weak var target: NSView?
    private weak var initialTarget: NSView?
    private var pending: [NSEvent] = []
    func reset() {
        owner = nil
        awaitingBegan = false
        recipientSelected = false
        target = nil
        initialTarget = nil
        pending = []
    }

    @discardableResult
    func dispatch(_ event: NSEvent, inlineTarget: @autoclosure () -> NSView?, conversation: NSScrollView) -> Bool {
        let phased = !event.phase.isEmpty || !event.momentumPhase.isEmpty
        if !phased {
            // Legacy wheel events have no gesture lifetime and may be interleaved
            // with a trackpad sequence. They cannot replace its latched owner.
            guard let inline = inlineTarget() else { return false }
            let recipient =
                !event.modifierFlags.contains(.shift) && abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
                ? conversation : inline
            recipient.scrollWheel(with: event)
            return true
        }
        if event.phase.contains(.mayBegin) {
            if !awaitingBegan { begin(inlineTarget()) }
            awaitingBegan = true
        } else if event.phase.contains(.began) {
            if !awaitingBegan { begin(inlineTarget()) }
            awaitingBegan = false
        }
        if event.phase.contains(.ended) { awaitingBegan = false }
        defer {
            if event.phase.contains(.cancelled) || event.momentumPhase.contains(.ended) { reset() }
        }
        // A nil lookup is a platform-owned gesture, not an unresolved target.
        // Installation/reset during a gesture also leaves its tail with AppKit.
        if owner == nil { owner = .platform }
        guard owner == .transcript else { return false }
        let hasDelta = event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0
        if !recipientSelected, !hasDelta, !event.phase.contains(.ended), !event.phase.contains(.cancelled) {
            // Keep the actual mayBegin/began prefix until direction is known.
            // Stationary changes add no unbounded queue of zero-delta events.
            if event.phase.contains(.began) || (event.phase.contains(.mayBegin) && pending.isEmpty) {
                pending.append(event)
            }
            return true
        }
        if !recipientSelected {
            recipientSelected = true
            target =
                !event.modifierFlags.contains(.shift) && abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
                ? conversation : initialTarget
        }
        guard let target else {
            // A removed weak recipient must not hand an already-consumed begin
            // to another view, or send only the remainder back through AppKit.
            pending = []
            return true
        }
        for start in pending { target.scrollWheel(with: start) }
        pending = []
        target.scrollWheel(with: event)
        return true
    }

    private func begin(_ inline: NSView?) {
        reset()
        initialTarget = inline
        owner = inline == nil ? .platform : .transcript
    }
}
