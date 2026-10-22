import AppKit
import SwiftUI
import WebKit

/// The persistent Sidebar pane is the native wheel target. AppKit may retain a
/// momentum target past its terminal event; that target must not be a reply WK
/// or a transient transcript subtree. Only current, weak recipients receive input.
@MainActor
class AgentChatScrollHost: ScholiumSurfaceContainerView {
    private weak var boundary: AgentChatScrollBoundary.BoundaryView?
    private let route = AgentChatWheelRoute()
    private var forwardingWheel = false
    var showsChat = false {
        didSet {
            if oldValue != showsChat { route.abandonRecipient() }
        }
    }

    func register(_ boundary: AgentChatScrollBoundary.BoundaryView) {
        guard self.boundary !== boundary else { return }
        route.abandonRecipient()
        self.boundary = boundary
    }

    func unregister(_ boundary: AgentChatScrollBoundary.BoundaryView) {
        guard self.boundary === boundary else { return }
        route.abandonRecipient()
        self.boundary = nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        hitTest(point, event: NSApp.currentEvent)
    }

    func hitTest(_ point: NSPoint, event: NSEvent?) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        guard let event else { return hit }
        // Every Sidebar page uses the same native wheel target. A gesture
        // starting in a composer, list or Library cannot later latch a WK when
        // the pointer or presentation changes. Pointer events stay native.
        if event.type == .scrollWheel { return self }
        if showsChat, event.type == .leftMouseDown,
            let scroller = boundary?.scroller(at: event.locationInWindow)
        {
            return scroller
        }
        return hit
    }

    override func scrollWheel(with event: NSEvent) {
        // A recipient's normal responder fallback can return here. This pane
        // has already dispatched this event; it cannot initiate another route.
        guard !forwardingWheel else { return }
        forwardingWheel = true
        defer { forwardingWheel = false }
        let point = superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
        _ = route.dispatch(event, targets: wheelTargets(for: event, at: point))
    }

    private func wheelTargets(for event: NSEvent, at point: NSPoint) -> AgentChatWheelTargets? {
        guard let hit = super.hitTest(point) else { return nil }
        if showsChat, let targets = boundary?.targets(for: event, hit: hit) { return targets }
        let native = (hit as? NSScrollView) ?? hit.enclosingScrollView ?? hit
        return AgentChatWheelTargets(horizontal: native, vertical: native)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { route.reset() }
    }

    override func viewDidHide() {
        super.viewDidHide()
        route.abandonRecipient()
    }
}

/// A transcript registers its visible native geometry with the pane. It owns
/// neither the event monitor nor the lifetime of a wheel gesture.
struct AgentChatScrollBoundary: NSViewRepresentable {
    @Environment(\.scholiumDocumentSurfaceVisibility) private var surfaceVisibility
    @Environment(\.isEnabled) private var isEnabled
    func makeNSView(context: Context) -> BoundaryView { BoundaryView() }
    func updateNSView(_ view: BoundaryView, context: Context) { view.setActive(surfaceVisibility.isActive && isEnabled) }
    static func dismantleNSView(_ view: BoundaryView, coordinator: ()) { view.retire() }

    final class BoundaryView: NSView {
        private weak var host: AgentChatScrollHost?
        private(set) var isActive = true
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reconcileHost()
        }
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            reconcileHost()
        }
        func setActive(_ active: Bool) {
            isActive = active
            reconcileHost()
        }
        func retire() {
            isActive = false
            reconcileHost()
        }
        private func reconcileHost() {
            var ancestor = superview
            while let view = ancestor, !(view is AgentChatScrollHost) { ancestor = view.superview }
            let next = isActive && window != nil ? ancestor as? AgentChatScrollHost : nil
            if host !== next {
                host?.unregister(self)
                host = next
            }
            host?.register(self)
        }
        func scroller(at windowPoint: NSPoint) -> NSScroller? {
            guard isActive, !isHiddenOrHasHiddenAncestor,
                let bar = enclosingScrollView?.verticalScroller, bar.isEnabled, !bar.isHidden,
                bar.bounds.contains(bar.convert(windowPoint, from: nil))
            else { return nil }
            return bar
        }
        func conversation(for event: NSEvent, hit: NSView?) -> NSScrollView? {
            guard isActive, !isHiddenOrHasHiddenAncestor, window != nil,
                let scroll = enclosingScrollView
            else { return nil }
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
            guard viewport.contains(point), !(hit is NSScroller) else { return nil }
            if ownsLocalVerticalScroll {
                return nested
            }
            return scroll
        }
        func targets(for event: NSEvent, hit: NSView?) -> AgentChatWheelTargets? {
            guard let scroll = conversation(for: event, hit: hit) else { return nil }
            let reply = Self.inlineReply(in: scroll.documentView, at: event.locationInWindow)
            let nested = (hit as? NSScrollView) ?? hit?.enclosingScrollView
            let localScroll = nested !== scroll ? nested : nil
            let inline =
                reply.flatMap { view in
                    view.hitTest(view.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow)
                } ?? reply ?? localScroll ?? scroll
            return AgentChatWheelTargets(horizontal: inline, vertical: scroll)
        }
        static func inlineReply(in root: NSView?, at windowPoint: NSPoint) -> AgentChatReadWebView? {
            guard let root, !root.isHiddenOrHasHiddenAncestor else { return nil }
            if let reply = root as? AgentChatReadWebView {
                return reply.isChatInteractive && reply.bounds.contains(reply.convert(windowPoint, from: nil)) ? reply : nil
            }
            for child in root.subviews.reversed() {
                if let found = inlineReply(in: child, at: windowPoint) { return found }
            }
            return nil
        }
    }
}

struct AgentChatWheelTargets {
    let horizontal: NSView
    let vertical: NSView
}

/// Latches one native recipient for a whole gesture, including zero-delta
/// boundaries and momentum. No synthetic deltas, timers or offset writes.
@MainActor
final class AgentChatWheelRoute {
    private enum Owner { case unclaimed, routed }
    private var owner: Owner?
    private var awaitingBegan = false
    private var recipientSelected = false
    private weak var target: NSView?
    private weak var initialTarget: NSView?
    private weak var verticalTarget: NSView?
    private var pending: [NSEvent] = []
    func reset() {
        owner = nil
        awaitingBegan = false
        recipientSelected = false
        target = nil
        initialTarget = nil
        verticalTarget = nil
        pending = []
    }

    @discardableResult
    func dispatch(_ event: NSEvent, targets: @autoclosure () -> AgentChatWheelTargets?) -> Bool {
        let phased = !event.phase.isEmpty || !event.momentumPhase.isEmpty
        if !phased {
            // Legacy wheel events have no gesture lifetime and may be interleaved
            // with a trackpad sequence. They cannot replace its latched owner.
            guard let targets = targets() else { return false }
            let recipient =
                !event.modifierFlags.contains(.shift) && abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
                ? targets.vertical : targets.horizontal
            recipient.scrollWheel(with: event)
            return true
        }
        if event.phase.contains(.mayBegin) {
            if !awaitingBegan { begin(targets()) }
            awaitingBegan = true
        } else if event.phase.contains(.began) {
            if !awaitingBegan { begin(targets()) }
            awaitingBegan = false
        }
        if event.momentumPhase.contains(.began), owner == nil { begin(targets()) }
        if event.phase.contains(.ended) { awaitingBegan = false }
        defer {
            if event.phase.contains(.cancelled) || event.momentumPhase.contains(.ended) { reset() }
        }
        // An ineligible start or orphaned continuation cannot acquire a new
        // recipient halfway through the native gesture.
        if owner == nil { owner = .unclaimed }
        guard owner == .routed else { return false }
        let hasDelta = event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0
        if !recipientSelected, !hasDelta, !event.phase.contains(.ended), !event.phase.contains(.cancelled),
            !event.momentumPhase.contains(.ended)
        {
            // Keep the actual mayBegin/began prefix until direction is known.
            // Stationary changes add no unbounded queue of zero-delta events.
            if event.phase.contains(.began) || event.momentumPhase.contains(.began)
                || (event.phase.contains(.mayBegin) && pending.isEmpty)
            {
                pending.append(event)
            }
            return true
        }
        if !recipientSelected {
            recipientSelected = true
            target =
                !event.modifierFlags.contains(.shift) && abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
                ? verticalTarget : initialTarget
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

    /// Retiring a presentation revokes its input without handing the tail of
    /// an already-owned gesture to a replacement page.
    func abandonRecipient() {
        target = nil
        initialTarget = nil
        verticalTarget = nil
        pending = []
        recipientSelected = true
    }

    private func begin(_ targets: AgentChatWheelTargets?) {
        reset()
        initialTarget = targets?.horizontal
        verticalTarget = targets?.vertical
        owner = targets == nil ? .unclaimed : .routed
    }
}
