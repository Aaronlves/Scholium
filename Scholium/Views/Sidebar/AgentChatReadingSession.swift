import AppKit
import Observation
import SwiftUI

/// Window-local reading state. It never changes conversation history or execution.
@MainActor @Observable
final class AgentChatReadingSession {
    var isAwayFromLatest = false
    var expandedActivities: Set<String> = []
    var processExpansions: [String: Bool] = [:]
    var toolGroupExpansions: [String: Bool] = [:]
    var processWindows: [String: AgentChatProcessWindow] = [:]
    var planExpansions: [String: Bool] = [:]
    var history = AgentChatHistoryWindow()
    struct HistoryPage {
        let previous: AgentChatHistoryWindow
        let itemIDs: Set<String>
        var readerIDs: Set<String>
        let earlier: Bool
    }
    private(set) var pendingHistoryPage: HistoryPage?
    // The native viewport retains full-precision offsets. Declarative content
    // observes only the reading mode and semantic row, never every scroll tick.
    @ObservationIgnored var position: ReadingPosition = .followingLatest {
        didSet {
            let retaining: Bool
            let itemID: String?
            switch position {
            case .followingLatest:
                retaining = false
                itemID = nil
            case .retaining(let anchor):
                retaining = true
                itemID = anchor?.id
            }
            if isRetainingPosition != retaining { isRetainingPosition = retaining }
            if currentReadingItemID != itemID { currentReadingItemID = itemID }
        }
    }
    private(set) var isRetainingPosition = false
    private(set) var currentReadingItemID: String?
    private(set) var initialTranscriptPhase: InitialTranscriptPhase = .unmounted
    private var activePresentationID: UUID?
    @ObservationIgnored private var presentationIsActive = false
    var isScrolling = false {
        didSet { readerPreparation.setScrolling(isScrolling) }
    }
    @ObservationIgnored let readerPreparation = AgentChatReaderPreparation()
    @ObservationIgnored private(set) weak var viewport: AgentChatTranscriptViewport.View?
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
    private struct MountedReader {
        let instance: UUID
        let itemID: String
        var hydrated: Bool
        var layoutApplied = false
    }
    private var mountedReaders: [UUID: [String: MountedReader]] = [:]

    var isInitialTranscriptReady: Bool {
        initialTranscriptPhase == .visible
    }

    func beginPresentation(_ id: UUID, isActive: Bool = true) {
        guard activePresentationID != id else { return }
        if viewport?.presentationID != id { viewport?.retire() }
        cancelPendingHistory()
        activePresentationID = id
        presentationIsActive = isActive
        readerPreparation.begin(id)
        // Child appearance can precede the root's appearance. Admit that
        // root's staged receipts while retiring every departed page's proof.
        mountedReaders = mountedReaders.filter { $0.key == id }
        expectedReaderIDs = []
        isScrolling = false
        initialTranscriptPhase = .hydrating
        // A new native owner must not inherit an old owner's acknowledgement,
        // even when both are restoring the same passage or latest reply.
        viewportRequest = nil
        enqueue(anchor.map(ViewportTarget.anchor) ?? .latest)
        reconcileReaderHydration()
    }

    func endPresentation(_ id: UUID) {
        mountedReaders[id] = nil
        guard activePresentationID == id else { return }
        cancelPendingHistory()
        presentationIsActive = false
        readerPreparation.end()
        viewport?.detach()
        activePresentationID = nil
        expectedReaderIDs = []
        viewportRequest = nil
        initialTranscriptPhase = .unmounted
        isScrolling = false
    }

    func isPresentationReady(_ id: UUID) -> Bool {
        ownsPresentation(id) && isInitialTranscriptReady
    }

    func ownsPresentation(_ id: UUID) -> Bool {
        activePresentationID == id
    }

    func setPresentationActive(_ active: Bool, for id: UUID) {
        guard ownsPresentation(id) else { return }
        presentationIsActive = active
        if active { viewport?.scheduleLayout() }
    }

    func ownsViewport(_ viewport: AgentChatTranscriptViewport.View) -> Bool {
        self.viewport === viewport && activePresentationID == viewport.presentationID
    }

    @discardableResult
    func attachViewport(_ viewport: AgentChatTranscriptViewport.View) -> Bool {
        guard !viewport.isRetired else { return false }
        guard activePresentationID == nil || activePresentationID == viewport.presentationID else { return false }
        guard self.viewport !== viewport else { return true }
        self.viewport?.retire()
        self.viewport = viewport
        isScrolling = false
        viewportRequest = nil
        enqueue(anchor.map(ViewportTarget.anchor) ?? .latest)
        return true
    }

    func detachViewport(_ viewport: AgentChatTranscriptViewport.View) {
        guard self.viewport === viewport else { return }
        self.viewport = nil
        isScrolling = false
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
        presentPreparedHistoryIfReady()
        viewport?.scheduleLayout()
    }
    func navigate(to id: String, in ids: [String]) {
        cancelPendingHistory()
        history.reveal(id, in: ids)
        let anchor = Anchor(id: id, offset: 0)
        position = .retaining(anchor)
        enqueue(.anchor(anchor))
    }
    func latest(in ids: [String]) {
        cancelPendingHistory()
        // Only this explicit navigation action releases loaded activity pages;
        // a native viewport arriving at the bottom preserves their extent.
        processWindows = [:]
        history.latest(in: ids)
        position = .followingLatest
        enqueue(.latest)
    }
    func mount(in ids: [String], readerIDs: Set<String> = []) {
        guard activePresentationID != nil else { return }
        switch position {
        case .followingLatest:
            history.latest(in: ids)
            enqueue(.latest)
        case .retaining(let anchor):
            if let anchor, ids.contains(anchor.id) {
                history.reveal(anchor.id, in: ids)
                enqueue(.anchor(anchor))
            } else {
                position = .retaining(nil)
                enqueue(.latest)
            }
        }
        reconcileInitialReaders(in: ids, readerIDs: readerIDs)
    }
    func contentDidChange(in ids: [String], readerIDs: Set<String> = []) {
        guard activePresentationID != nil else { return }
        if var page = pendingHistoryPage {
            if page.itemIDs.isSubset(of: Set(ids)) {
                page.readerIDs = readerIDs.intersection(page.itemIDs)
                pendingHistoryPage = page
                viewport?.scheduleLayout()
            } else {
                cancelPendingHistory()
            }
        }
        switch position {
        case .followingLatest:
            history.latest(in: ids)
            enqueue(.latest)
        case .retaining(let anchor):
            if let anchor, ids.contains(anchor.id), viewportRequest == nil {
                history.reveal(anchor.id, in: ids)
                enqueue(.anchor(anchor))
            }
        }
        reconcileInitialReaders(in: ids, readerIDs: readerIDs)
    }
    func areReadersHydrated(_ ids: Set<String>) -> Bool {
        guard let activePresentationID else { return ids.isEmpty }
        return ids.allSatisfy { mountedReaders[activePresentationID]?[$0]?.hydrated == true }
    }

    func ownsReplyReader(_ id: String, presentationID: UUID, instance: UUID) -> Bool {
        ownsPresentation(presentationID) && mountedReaders[presentationID]?[id]?.instance == instance
    }

    func mountReplyReader(_ id: String, presentationID: UUID, instance: UUID, hydrated: Bool, itemID: String? = nil) {
        if let previous = mountedReaders[presentationID]?[id], previous.instance != instance {
            readerPreparation.remove(.init(presentationID: presentationID, id: id, instance: previous.instance))
        }
        mountedReaders[presentationID, default: [:]][id] = MountedReader(instance: instance, itemID: itemID ?? id, hydrated: hydrated)
        reconcileReaderHydration()
        if pendingHistoryPage != nil { viewport?.scheduleLayout() }
    }

    func updateReplyHydration(_ id: String, presentationID: UUID, instance: UUID, hydrated: Bool, layoutApplied: Bool) {
        // A replaced or departed reader cannot overwrite its current successor.
        guard mountedReaders[presentationID]?[id]?.instance == instance else { return }
        mountedReaders[presentationID]?[id]?.hydrated = hydrated
        mountedReaders[presentationID]?[id]?.layoutApplied = layoutApplied
        if hydrated {
            readerPreparation.complete(.init(presentationID: presentationID, id: id, instance: instance))
        }
        reconcileReaderHydration()
        if pendingHistoryPage != nil { viewport?.scheduleLayout() }
    }

    func unmountReplyReader(_ id: String, presentationID: UUID, instance: UUID) {
        readerPreparation.remove(.init(presentationID: presentationID, id: id, instance: instance))
        guard mountedReaders[presentationID]?[id]?.instance == instance else { return }
        mountedReaders[presentationID]?.removeValue(forKey: id)
        if mountedReaders[presentationID]?.isEmpty == true { mountedReaders[presentationID] = nil }
        reconcileReaderHydration()
        if pendingHistoryPage != nil { viewport?.scheduleLayout() }
    }
    func page(earlier: Bool, in ids: [String], readerIDs: Set<String>) {
        guard pendingHistoryPage == nil, activePresentationID != nil, presentationIsActive else { return }
        pause()
        let previous = history
        let previousIDs = Set(ids[previous.range(in: ids)])
        if earlier { history.earlier(in: ids) } else { history.later(in: ids) }
        let added = Set(ids[history.range(in: ids)]).subtracting(previousIDs)
        if !added.isEmpty {
            pendingHistoryPage = HistoryPage(previous: previous, itemIDs: added, readerIDs: readerIDs.intersection(added), earlier: earlier)
        }
        viewport?.scheduleLayout()
    }

    func pagingRange(in ids: [String]) -> Range<Int> {
        (pendingHistoryPage?.previous ?? history).range(in: ids)
    }

    func presentPreparedHistoryIfReady() {
        guard let page = pendingHistoryPage, presentationIsActive, !isScrolling, isInitialTranscriptReady,
            let activePresentationID, let viewport, ownsViewport(viewport),
            let window = viewport.window, let document = viewport.enclosingScrollView?.documentView,
            page.itemIDs.allSatisfy({ id in
                guard let marker = markers[id]?.view else { return false }
                return marker.window === window && marker.isDescendant(of: document)
            }),
            areReadersHydrated(page.readerIDs),
            mountedReaders[activePresentationID]?.values.filter({ page.itemIDs.contains($0.itemID) })
                .allSatisfy({ $0.hydrated && $0.layoutApplied }) ?? true
        else { return }
        // The new rows stay mounted at zero extent while their real readers
        // prepare. One publication presents the complete page's final geometry.
        pendingHistoryPage = nil
        viewport.scheduleLayout()
    }

    private func cancelPendingHistory() {
        guard let page = pendingHistoryPage else { return }
        history = page.previous
        pendingHistoryPage = nil
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
        guard initialReadersAreHydrated else { return }
        initialTranscriptPhase = .positioning
        viewport?.scheduleLayout()
    }

    private func reconcileReaderHydration() {
        guard initialTranscriptPhase == .hydrating || initialTranscriptPhase == .positioning else { return }
        if !initialReadersAreHydrated {
            initialTranscriptPhase = .hydrating
        }
        advanceInitialHydrationIfReady()
    }

    private var initialReadersAreHydrated: Bool {
        // Expanded public commentary also has native readers. Never wait for
        // collapsed content that has not mounted, but include every actual
        // mounted reader in this page's initial geometry proof.
        guard let activePresentationID else { return false }
        return areReadersHydrated(expectedReaderIDs)
            && (mountedReaders[activePresentationID]?.values.allSatisfy(\.hydrated) ?? true)
    }

    private func reconcileInitialReaders(in ids: [String], readerIDs: Set<String>) {
        guard initialTranscriptPhase == .hydrating || initialTranscriptPhase == .positioning else { return }
        // The history window can move while readers are loading. Wait only for
        // readers in its resulting range, never an already unmounted prefix.
        expectedReaderIDs = readerIDs.intersection(ids[history.range(in: ids)])
        reconcileReaderHydration()
    }
}

struct AgentChatReadingPresentation: Equatable {
    let id: UUID
    let session: AgentChatReadingSession
    var itemID: String? = nil

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.session === rhs.session && lhs.itemID == rhs.itemID
    }
}

private struct AgentChatReadingPresentationKey: EnvironmentKey {
    static let defaultValue: AgentChatReadingPresentation? = nil
}

extension EnvironmentValues {
    var chatReadingPresentation: AgentChatReadingPresentation? {
        get { self[AgentChatReadingPresentationKey.self] }
        set { self[AgentChatReadingPresentationKey.self] = newValue }
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
    let presentationID: UUID
    func makeNSView(context: Context) -> View { View(session: session, presentationID: presentationID) }
    func updateNSView(_ view: View, context: Context) { view.connectIfNeeded() }
    static func dismantleNSView(_ view: View, coordinator: ()) { view.retire() }

    final class View: NSView {
        let session: AgentChatReadingSession
        let presentationID: UUID
        private(set) var isRetired = false
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
            let retainedRowOrigin: CGFloat?
            @MainActor init(_ scroll: NSScrollView, document: NSView, retainedRowOrigin: CGFloat?) {
                documentSize = document.frame.size
                viewportSize = scroll.contentView.bounds.size
                let insets = scroll.contentInsets
                top = insets.top
                bottom = insets.bottom
                left = insets.left
                right = insets.right
                self.retainedRowOrigin = retainedRowOrigin
            }
        }
        private var lastGeometry: Geometry?
        private var hasAppliedPosition = false
        private var lifecycleID: UInt64 = 0
        init(session: AgentChatReadingSession, presentationID: UUID) {
            self.session = session
            self.presentationID = presentationID
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            connectIfNeeded()
        }
        func connectIfNeeded() {
            guard !isRetired else { return }
            if window != nil, let scroll = enclosingScrollView, self.scroll === scroll, session.viewport === self {
                scheduleLayout()
                return
            }
            detach()
            guard window != nil, let scroll = enclosingScrollView else { return }
            self.scroll = scroll
            guard session.attachViewport(self) else {
                self.scroll = nil
                return
            }
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
        func retire() {
            isRetired = true
            detach()
        }
        func detach() {
            lifecycleID &+= 1
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            insetObservation?.invalidate()
            insetObservation = nil
            session.detachViewport(self)
            scroll = nil
            queued = false
            writing = false
            pendingScrollObservation = false
            lastGeometry = nil
            hasAppliedPosition = false
        }
        override func layout() {
            super.layout()
            connectIfNeeded()
        }
        func scheduleLayout() {
            guard session.ownsViewport(self), !queued else { return }
            queued = true
            let lifecycleID = self.lifecycleID
            // Coalesce native layout notifications after the current layout pass.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.lifecycleID == lifecycleID, self.session.ownsViewport(self) else { return }
                self.queued = false
                self.reconcile()
            }
        }
        private func rows(in document: NSView) -> [(String, NSRect)] {
            return session.markers.compactMap { id, entry in
                guard session.pendingHistoryPage?.itemIDs.contains(id) != true,
                    let view = entry.view, view.window === window, view.isDescendant(of: document)
                else { return nil }
                return (id, view.convert(view.bounds, to: document))
            }.sorted { $0.1.minY < $1.1.minY }
        }
        private func rowFrame(_ id: String, in document: NSView) -> NSRect? {
            guard session.pendingHistoryPage?.itemIDs.contains(id) != true,
                let view = session.markers[id]?.view,
                view.window === window, view.isDescendant(of: document)
            else { return nil }
            return view.convert(view.bounds, to: document)
        }
        private func geometry(_ scroll: NSScrollView, document: NSView) -> Geometry {
            // A preceding row may grow while another shrinks. Total document
            // size alone cannot detect that the retained passage has moved.
            let origin = session.anchor.flatMap { rowFrame($0.id, in: document)?.minY }
            return Geometry(scroll, document: document, retainedRowOrigin: origin)
        }
        func capture() {
            guard session.ownsViewport(self), let scroll, let document = scroll.documentView else { return }
            let top = scroll.contentView.bounds.minY + scroll.contentInsets.top
            let rows = rows(in: document)
            if let row = rows.first(where: { $0.1.maxY > top + 1 }) ?? rows.last {
                guard session.viewportRequest == nil else { return }
                session.anchor = .init(id: row.0, offset: row.1.minY - top)
            }
        }
        func settleUserPosition() {
            guard session.ownsViewport(self) else { return }
            guard !writing, let scroll, let document = scroll.documentView, session.viewportRequest == nil else {
                scheduleLayout()
                return
            }
            if bottomDistance(scroll) <= 1, session.history.last == nil {
                session.reachedLatestFromViewport()
            } else {
                capture()
            }
            session.isAwayFromLatest = bottomDistance(scroll) > 80
            // Capturing native input may select another row. Store its geometry
            // after that selection so the next input is not mistaken for reflow.
            lastGeometry = geometry(scroll, document: document)
        }
        private func boundsChanged() {
            guard session.ownsViewport(self), !writing, let scroll, let document = scroll.documentView else { return }
            if session.viewportRequest != nil {
                scheduleLayout()
                return
            }
            if session.isScrolling {
                // During a gesture the native clip owns the reading position.
                // A changing dock or reply height must not leave lastGeometry
                // stale and suppress every later bounds observation.
                settleUserPosition()
                return
            }
            // Resizing the viewport or its floating input inset is layout,
            // not a researcher choosing another reading position.
            if geometry(scroll, document: document) != lastGeometry {
                scheduleLayout()
                return
            }
            if !queued {
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
            guard session.ownsViewport(self), window != nil,
                let scroll, let document = scroll.documentView,
                scroll.contentView.bounds.width > 0, scroll.contentView.bounds.height > 0
            else { return }
            session.presentPreparedHistoryIfReady()
            let geometry = geometry(scroll, document: document)
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
                guard let row = rowFrame(anchor.id, in: document) else { return false }
                origin.y = row.minY - anchor.offset - scroll.contentInsets.top
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
