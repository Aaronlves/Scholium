import AppKit
import SwiftUI
import WebKit

/// One event boundary for the transcript. SwiftUI platform hosts can consume
/// wheel events before either native text or WebKit responder fallback is reached.
/// Route transcript gestures before dispatch; native details and popovers
/// retain their own normal scrolling. This view owns no offset or geometry.
struct AgentChatScrollBoundary: NSViewRepresentable {
    func makeNSView(context: Context) -> BoundaryView { BoundaryView() }
    func updateNSView(_ view: BoundaryView, context: Context) {}
    static func dismantleNSView(_ view: BoundaryView, coordinator: ()) { view.invalidate() }

    final class BoundaryView: NSView {
        private var monitor: Any?
        private var route = AgentChatWheelRoute()
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            invalidate()
            guard window != nil else { return }
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
                  let scroll = enclosingScrollView, let content = window.contentView else { route.reset(); return event }
            if event.type == .leftMouseDown {
                // The platform content group can also mask the overlay scroller.
                // Delegate its real hit region to AppKit's own tracking loop.
                if let bar = scroll.verticalScroller, bar.isEnabled, !bar.isHidden,
                   bar.bounds.contains(bar.convert(event.locationInWindow, from: nil)) {
                    bar.mouseDown(with: event)
                    return nil
                }
                return event
            }
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
            let ownsLocalVerticalScroll = nested.map {
                $0 !== scroll && ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 1
            } ?? false
            let eligible = viewport.contains(point) && !(hit is NSScroller) && !ownsLocalVerticalScroll
            let reply = eligible ? Self.inlineReply(in: scroll.documentView, at: event.locationInWindow) : nil
            let target = reply.flatMap { view in
                view.hitTest(view.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow)
            } ?? reply ?? hit ?? scroll
            return route.dispatch(event, inlineTarget: eligible ? target : nil, conversation: scroll) ? nil : event
        }
        static func inlineReply(in root: NSView?, at windowPoint: NSPoint) -> AgentChatReadWebView? {
            guard let root, !root.isHiddenOrHasHiddenAncestor else { return nil }
            if let reply = root as? AgentChatReadWebView,
               reply.bounds.contains(reply.convert(windowPoint, from: nil)) { return reply }
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
    private weak var target: NSView?
    private weak var initialTarget: NSView?
    private var pending: [NSEvent] = []
    func reset() { target = nil; initialTarget = nil; pending = [] }

    @discardableResult
    func dispatch(_ event: NSEvent, inlineTarget: NSView?, conversation: NSScrollView) -> Bool {
        let phased = !event.phase.isEmpty || !event.momentumPhase.isEmpty
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) { reset() }
        if !phased { reset() }
        if target == nil, initialTarget == nil { initialTarget = inlineTarget }
        guard target != nil || initialTarget != nil else { return false }
        let hasDelta = event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0
        if target == nil, !hasDelta, !event.phase.contains(.ended), !event.phase.contains(.cancelled) {
            if pending.isEmpty || event.phase.contains(.began) { pending = [event] }
            return true
        }
        if target == nil {
            target = !event.modifierFlags.contains(.shift) && abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
                ? conversation : initialTarget
        }
        guard let target else { reset(); return false }
        for start in pending { target.scrollWheel(with: start) }
        pending = []
        target.scrollWheel(with: event)
        if !phased || event.phase.contains(.cancelled) || event.momentumPhase.contains(.ended) { reset() }
        return true
    }
}
