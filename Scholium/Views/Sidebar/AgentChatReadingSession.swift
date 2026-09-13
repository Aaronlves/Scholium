import AppKit
import Observation
import SwiftUI

/// Window-local reading state. It never changes conversation history or execution.
@MainActor @Observable
final class AgentChatReadingSession {
    var isAwayFromLatest = false
    var isPaused = false
    var expandedActivities: Set<String> = []
    var processExpansions: [String: Bool] = [:]
    var planExpansions: [String: Bool] = [:]
    var history = AgentChatHistoryWindow()
    @ObservationIgnored var anchor: Anchor?
    @ObservationIgnored var isScrolling = false
    @ObservationIgnored weak var viewport: AgentChatTranscriptViewport.View?
    @ObservationIgnored var markers: [String: WeakMarker] = [:]

    struct Anchor: Equatable {
        let id: String
        let offset: CGFloat
    }
    final class WeakMarker {
        weak var view: AgentChatReadingMarker.View?
        init(_ view: AgentChatReadingMarker.View) { self.view = view }
    }

    func pause() {
        viewport?.capture()
        isPaused = true
    }
    func navigate(to id: String, in ids: [String]) {
        isPaused = true
        history.reveal(id, in: ids)
        anchor = Anchor(id: id, offset: 0)
        viewport?.scheduleLayout()
    }
    func latest(in ids: [String]) {
        history.latest(in: ids)
        anchor = nil
        isPaused = false
        isAwayFromLatest = false
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
    var first: String?
    var last: String?
    func range(in ids: [String]) -> Range<Int> {
        let end = last.flatMap { ids.firstIndex(of: $0).map { $0 + 1 } } ?? ids.count
        let start = first.flatMap { ids.firstIndex(of: $0) } ?? max(0, end - Self.pageSize)
        return min(start, end)..<end
    }
    mutating func latest(in ids: [String]) {
        first = ids.dropFirst(max(0, ids.count - Self.pageSize)).first
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
        private weak var scroll: NSScrollView?
        private var queued = false
        private var writing = false
        private var lastDocumentSize = NSSize.zero
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
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            if session.viewport === self { session.viewport = nil }
            scroll = nil
        }
        override func layout() {
            super.layout()
            scheduleLayout()
        }
        func scheduleLayout() {
            guard !queued else { return }
            queued = true
            // Coalesce native layout notifications after the current layout pass.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
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
                session.anchor = .init(id: row.0, offset: row.1.minY - top)
            }
        }
        private func boundsChanged() {
            guard !writing, let scroll, let document = scroll.documentView else { return }
            if document.frame.size != lastDocumentSize {
                scheduleLayout()
                return
            }
            // Includes accessibility scrollbar actions that have no gesture phase.
            if session.isScrolling || !queued {
                capture()
                let away = bottomDistance(scroll) > 80
                if !session.isScrolling || away { session.isPaused = away || session.isPaused }
                if session.isScrolling && bottomDistance(scroll) <= 1 { session.isPaused = false }
                session.isAwayFromLatest = away
            }
        }
        private func bottomDistance(_ scroll: NSScrollView) -> CGFloat {
            max(0, (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.maxY + scroll.contentInsets.bottom)
        }
        func reconcile() {
            guard let scroll, let document = scroll.documentView else { return }
            lastDocumentSize = document.frame.size
            guard !session.isScrolling else {
                capture()
                return
            }
            var target = scroll.contentView.bounds.origin
            if !session.isPaused {
                target.y = max(-scroll.contentInsets.top, document.frame.height - scroll.contentView.bounds.height + scroll.contentInsets.bottom)
            } else if let anchor = session.anchor, let row = rows(in: document).first(where: { $0.0 == anchor.id }) {
                target.y = row.1.minY - anchor.offset - scroll.contentInsets.top
            } else {
                session.isAwayFromLatest = bottomDistance(scroll) > 80
                return
            }
            writing = true
            scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(NSRect(origin: target, size: scroll.contentView.bounds.size)).origin)
            scroll.reflectScrolledClipView(scroll.contentView)
            writing = false
            session.isAwayFromLatest = bottomDistance(scroll) > 80
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
