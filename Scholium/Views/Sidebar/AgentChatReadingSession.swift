import AppKit
import Observation
import SwiftUI

/// Window-local reading state. It never changes conversation history or execution.
@MainActor @Observable
final class AgentChatReadingSession {
    var isAwayFromLatest = false
    var expandedActivities: Set<String> = []
    var processExpansions: [String: Bool] = [:]
    var processWindows: [String: AgentChatProcessWindow] = [:]
    var planExpansions: [String: Bool] = [:]
    var history = AgentChatHistoryWindow()
    var position: ReadingPosition = .followingLatest
    var initialTranscriptPhase: InitialTranscriptPhase = .unmounted
    @ObservationIgnored var isScrolling = false
    @ObservationIgnored weak var viewport: AgentChatTranscriptViewport.View?
    @ObservationIgnored var markers: [String: WeakMarker] = [:]

    struct Anchor: Equatable {
        let id: String
        let offset: CGFloat
    }
    enum ReadingPosition: Equatable {
        case followingLatest
        case retaining(Anchor?)
    }
    enum InitialTranscriptPhase: Equatable {
        case unmounted
        case hydrating
        case positioning
        case visible
    }
    enum ViewportTarget: Equatable {
        case latest
        case anchor(Anchor)
    }
    struct ViewportRequest: Equatable {
        let id: UInt64
        let target: ViewportTarget
    }
    @ObservationIgnored private var nextViewportRequestID: UInt64 = 0
    @ObservationIgnored private(set) var viewportRequest: ViewportRequest?
    @ObservationIgnored private var expectedReaderIDs: Set<String> = []
    @ObservationIgnored private var readerHydration: [String: Bool] = [:]

    var isInitialTranscriptReady: Bool {
        initialTranscriptPhase == .unmounted || initialTranscriptPhase == .visible
    }

    var isRetainingPosition: Bool {
        if case .retaining = position { return true }
        return false
    }
    var anchor: Anchor? {
        get {
            guard case .retaining(let anchor) = position else { return nil }
            return anchor
        }
        set { position = newValue.map { .retaining($0) } ?? .followingLatest }
    }

    final class WeakMarker {
        weak var view: AgentChatReadingMarker.View?
        init(_ view: AgentChatReadingMarker.View) { self.view = view }
    }

    func pause() {
        viewportRequest = nil
        viewport?.capture()
        if case .followingLatest = position {
            position = .retaining(anchor)
        }
    }
    func beginUserScroll() {
        isScrolling = true
        pause()
    }
    func endUserScroll() {
        isScrolling = false
        viewport?.settleUserPosition()
        viewport?.scheduleLayout()
    }
    func navigate(to id: String, in ids: [String]) {
        history.reveal(id, in: ids)
        let anchor = Anchor(id: id, offset: 0)
        position = .retaining(anchor)
        enqueue(.anchor(anchor))
    }
    func latest(in ids: [String]) {
        history.latest(in: ids)
        position = .followingLatest
        enqueue(.latest)
    }
    func mount(in ids: [String], readerIDs: Set<String> = []) {
        if initialTranscriptPhase == .unmounted {
            expectedReaderIDs = readerIDs
            initialTranscriptPhase = readerIDs.isEmpty ? .positioning : .hydrating
            advanceInitialHydrationIfReady()
        }
        switch position {
        case .followingLatest:
            history.latest(in: ids)
            enqueue(.latest)
        case .retaining(let anchor):
            guard let anchor, ids.contains(anchor.id) else {
                viewport?.scheduleLayout()
                return
            }
            history.reveal(anchor.id, in: ids)
            enqueue(.anchor(anchor))
        }
    }
    func contentDidChange(in ids: [String], readerIDs: Set<String> = []) {
        if initialTranscriptPhase == .hydrating || initialTranscriptPhase == .positioning {
            expectedReaderIDs = readerIDs
            advanceInitialHydrationIfReady()
        }
        switch position {
        case .followingLatest:
            history.latest(in: ids)
            enqueue(.latest)
        case .retaining(let anchor):
            guard let anchor, ids.contains(anchor.id), viewportRequest == nil else { return }
            history.reveal(anchor.id, in: ids)
            enqueue(.anchor(anchor))
        }
    }
    func observeReplyHydration(_ states: [String: Bool]) {
        readerHydration = states
        advanceInitialHydrationIfReady()
    }
    func page(earlier: Bool, in ids: [String]) {
        pause()
        if earlier { history.earlier(in: ids) } else { history.later(in: ids) }
        viewport?.scheduleLayout()
    }
    func acknowledge(_ request: ViewportRequest) {
        guard viewportRequest?.id == request.id else { return }
        viewportRequest = nil
        if initialTranscriptPhase == .positioning {
            initialTranscriptPhase = .visible
        }
    }
    func reachedLatestFromViewport() {
        position = .followingLatest
        isAwayFromLatest = false
    }
    private func enqueue(_ target: ViewportTarget) {
        if viewportRequest?.target == target { return }
        nextViewportRequestID &+= 1
        viewportRequest = .init(id: nextViewportRequestID, target: target)
        viewport?.scheduleLayout()
    }

    private func advanceInitialHydrationIfReady() {
        guard initialTranscriptPhase == .hydrating else { return }
        guard expectedReaderIDs.allSatisfy({ readerHydration[$0] == true }) else { return }
        initialTranscriptPhase = .positioning
        viewport?.scheduleLayout()
    }
}

@MainActor @Observable
final class AgentChatReadingStore {
    private var sessions: [UUID: AgentChatReadingSession] = [:]
    private let empty = AgentChatReadingSession()
    func session(for id: UUID?) -> AgentChatReadingSession {
        guard let id else { return empty }
        if let value = sessions[id] { return value }
        let value = AgentChatReadingSession()
        sessions[id] = value
        return value
    }
    func retain(_ ids: Set<UUID>) { sessions = sessions.filter { ids.contains($0.key) } }
}

/// A presentation window over already retained history. Explicit paging keeps
/// mounted rows alive; explicit jumps replace the window. No source is discarded.
struct AgentChatHistoryWindow: Equatable {
    static let pageSize = 24
    // Bound cold WebKit startup to the latest exchanges. Earlier Messages
    // retains the larger explicit page size without discarding any history.
    static let initialPageSize = 4
    var first: String?
    var last: String?
    func range(in ids: [String]) -> Range<Int> {
        let end = last.flatMap { ids.firstIndex(of: $0).map { $0 + 1 } } ?? ids.count
        let start = first.flatMap { ids.firstIndex(of: $0) } ?? max(0, end - Self.initialPageSize)
        return min(start, end)..<end
    }
    mutating func latest(in ids: [String]) {
        first = ids.dropFirst(max(0, ids.count - Self.initialPageSize)).first
        last = nil
    }
    mutating func earlier(in ids: [String]) {
        let current = range(in: ids)
        guard !ids.isEmpty else { return }
        first = ids[max(0, current.lowerBound - Self.pageSize)]
    }
    mutating func later(in ids: [String]) {
        let current = range(in: ids)
        guard !ids.isEmpty else { return }
        let end = min(ids.count, current.upperBound + Self.pageSize)
        last = end == ids.count ? nil : ids[end - 1]
    }
    mutating func reveal(_ id: String, in ids: [String]) {
        guard let index = ids.firstIndex(of: id), !range(in: ids).contains(index) else { return }
        let start = max(0, index - Self.pageSize / 2)
        let end = min(ids.count, start + Self.pageSize)
        first = ids[start]
        last = end == ids.count ? nil : ids[end - 1]
    }
}

/// SwiftUI owns row content; this native boundary alone writes the viewport.
/// A semantic row and its offset survive asynchronous WebKit measurements.
struct AgentChatTranscriptViewport: NSViewRepresentable {
    let session: AgentChatReadingSession
    func makeNSView(context: Context) -> View { View(session: session) }
    func updateNSView(_ view: View, context: Context) { view.scheduleLayout() }
    static func dismantleNSView(_ view: View, coordinator: ()) { view.detach() }

    final class View: NSView {
        let session: AgentChatReadingSession
        private var observers: [NSObjectProtocol] = []
        private var insetObservation: NSKeyValueObservation?
        private weak var scroll: NSScrollView?
        private var queued = false
        private var writing = false
        private var pendingScrollObservation = false
        private struct Geometry: Equatable {
            let documentSize: NSSize
            let viewportSize: NSSize
            let top: CGFloat
            let bottom: CGFloat
            let left: CGFloat
            let right: CGFloat
            @MainActor init(_ scroll: NSScrollView, document: NSView) {
                documentSize = document.frame.size
                viewportSize = scroll.contentView.bounds.size
                let insets = scroll.contentInsets
                top = insets.top
                bottom = insets.bottom
                left = insets.left
                right = insets.right
            }
        }
        private var lastGeometry: Geometry?
        private var hasAppliedPosition = false
        private var lifecycleID: UInt64 = 0
        init(session: AgentChatReadingSession) {
            self.session = session
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard window != nil, let scroll = enclosingScrollView else { return }
            self.scroll = scroll
            session.viewport = self
            insetObservation = scroll.observe(\.contentInsets, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.scheduleLayout() }
            }
            let clip = scroll.contentView
            clip.postsBoundsChangedNotifications = true
            scroll.documentView?.postsFrameChangedNotifications = true
            observers.append(
                NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.boundsChanged() }
                })
            if let document = scroll.documentView {
                observers.append(
                    NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: document, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.scheduleLayout() }
                    })
            }
            scheduleLayout()
        }
        func detach() {
            lifecycleID &+= 1
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            insetObservation?.invalidate()
            insetObservation = nil
            if session.viewport === self { session.viewport = nil }
            session.isScrolling = false
            scroll = nil
            queued = false
            writing = false
            pendingScrollObservation = false
            lastGeometry = nil
            hasAppliedPosition = false
        }
        override func layout() {
            super.layout()
            scheduleLayout()
        }
        func scheduleLayout() {
            guard !queued else { return }
            queued = true
            let lifecycleID = self.lifecycleID
            // Coalesce native layout notifications after the current layout pass.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.lifecycleID == lifecycleID else { return }
                self.queued = false
                self.reconcile()
            }
        }
        private func rows(in document: NSView) -> [(String, NSRect)] {
            session.markers.compactMap { id, entry in
                guard let view = entry.view, view.window === window, view.isDescendant(of: document) else { return nil }
                return (id, view.convert(view.bounds, to: document))
            }.sorted { $0.1.minY < $1.1.minY }
        }
        func capture() {
            guard let scroll, let document = scroll.documentView else { return }
            let top = scroll.contentView.bounds.minY + scroll.contentInsets.top
            let rows = rows(in: document)
            if let row = rows.first(where: { $0.1.maxY > top + 1 }) ?? rows.last {
                guard session.viewportRequest == nil else { return }
                session.anchor = .init(id: row.0, offset: row.1.minY - top)
            }
        }
        func settleUserPosition() {
            guard !writing, let scroll, scroll.documentView != nil, session.viewportRequest == nil else {
                scheduleLayout()
                return
            }
            if bottomDistance(scroll) <= 1, session.history.last == nil {
                session.reachedLatestFromViewport()
            } else {
                capture()
            }
            session.isAwayFromLatest = bottomDistance(scroll) > 80
        }
        private func boundsChanged() {
            guard !writing, let scroll, let document = scroll.documentView else { return }
            if session.viewportRequest != nil {
                scheduleLayout()
                return
            }
            // Resizing the viewport or its floating input inset is layout,
            // not a researcher choosing another reading position.
            if Geometry(scroll, document: document) != lastGeometry {
                scheduleLayout()
                return
            }
            if session.isScrolling {
                settleUserPosition()
            } else if !queued {
                // Native input layout can move the clip before publishing its
                // new inset. Classify a phase-less movement after that layout
                // settles; unchanged geometry still admits accessibility scrolls.
                pendingScrollObservation = true
                scheduleLayout()
            }
        }
        private func bottomDistance(_ scroll: NSScrollView) -> CGFloat {
            max(0, (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.maxY + scroll.contentInsets.bottom)
        }
        func reconcile() {
            guard let scroll, let document = scroll.documentView else { return }
            let geometry = Geometry(scroll, document: document)
            if session.initialTranscriptPhase == .hydrating {
                lastGeometry = geometry
                return
            }
            guard !session.isScrolling else {
                return
            }
            let geometryChanged = geometry != lastGeometry
            lastGeometry = geometry
            let observedScroll = pendingScrollObservation
            pendingScrollObservation = false

            if let request = session.viewportRequest {
                guard apply(request.target, in: scroll, document: document) else { return }
                hasAppliedPosition = true
                session.acknowledge(request)
                session.isAwayFromLatest = bottomDistance(scroll) > 80
                return
            }

            if observedScroll && !geometryChanged { settleUserPosition() }
            guard !hasAppliedPosition || geometryChanged else {
                session.isAwayFromLatest = bottomDistance(scroll) > 80
                return
            }
            switch session.position {
            case .followingLatest:
                _ = apply(.latest, in: scroll, document: document)
                hasAppliedPosition = true
            case .retaining(let anchor):
                guard let anchor, apply(.anchor(anchor), in: scroll, document: document) else {
                    session.isAwayFromLatest = bottomDistance(scroll) > 80
                    return
                }
                hasAppliedPosition = true
            }
            session.isAwayFromLatest = bottomDistance(scroll) > 80
        }
        private func apply(
            _ requestedTarget: AgentChatReadingSession.ViewportTarget, in scroll: NSScrollView, document: NSView
        ) -> Bool {
            var origin = scroll.contentView.bounds.origin
            switch requestedTarget {
            case .latest:
                origin.y = max(-scroll.contentInsets.top, document.frame.height - scroll.contentView.bounds.height + scroll.contentInsets.bottom)
            case .anchor(let anchor):
                guard let row = rows(in: document).first(where: { $0.0 == anchor.id }) else { return false }
                origin.y = row.1.minY - anchor.offset - scroll.contentInsets.top
            }
            writing = true
            scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(NSRect(origin: origin, size: scroll.contentView.bounds.size)).origin)
            scroll.reflectScrolledClipView(scroll.contentView)
            writing = false
            return true
        }
    }
}

struct AgentChatReadingMarker: NSViewRepresentable {
    let id: String
    let session: AgentChatReadingSession
    func makeNSView(context: Context) -> View { View(id: id, session: session) }
    func updateNSView(_ view: View, context: Context) { session.viewport?.scheduleLayout() }
    static func dismantleNSView(_ view: View, coordinator: ()) {
        if view.session.markers[view.id]?.view === view { view.session.markers[view.id] = nil }
    }
    final class View: NSView {
        let id: String
        let session: AgentChatReadingSession
        init(id: String, session: AgentChatReadingSession) {
            self.id = id
            self.session = session
            super.init(frame: .zero)
            session.markers[id] = .init(self)
        }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func layout() {
            super.layout()
            session.viewport?.scheduleLayout()
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            session.viewport?.scheduleLayout()
        }
    }
}
