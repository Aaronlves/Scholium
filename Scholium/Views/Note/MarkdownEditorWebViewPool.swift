import WebKit

/// An uncleared page is inaccessible until the incoming initialization is
/// checked. This lease owns only runtime lifetime, never document source.
@MainActor
final class MarkdownEditorHandoffLease {
    private weak var pool: MarkdownEditorWebViewPool?
    private weak var webView: WindowAttachedWebView?
    private let generation: Int
    private var deadline: Task<Void, Never>?
    private var isClaimed = false
    private(set) var isRetired = false

    var permitsInitialization: Bool {
        isClaimed && !isRetired && webView?.editorHandoffLease === self
    }

    init(pool: MarkdownEditorWebViewPool, webView: WindowAttachedWebView, generation: Int, timeout: Duration) {
        self.pool = pool
        self.webView = webView
        self.generation = generation
        deadline = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.retire()
        }
    }

    func claim() -> Bool {
        guard !isRetired, !isClaimed, let webView, webView.editorHandoffLease === self else { return false }
        isClaimed = true
        // Acquisition bounds only delivery. Once attached, the session's
        // existing readiness/bridge deadlines own initialization, including
        // its injected policy for legitimately large documents.
        deadline?.cancel()
        deadline = nil
        return true
    }

    func commit() -> Bool {
        guard isClaimed, !isRetired, let webView, webView.editorHandoffLease === self,
            pool?.commitHandoff(self, webView: webView, generation: generation) == true
        else { return false }
        deadline?.cancel()
        deadline = nil
        webView.editorHandoffLease = nil
        return true
    }

    func retire() {
        guard !isRetired, let webView, webView.editorHandoffLease === self else { return }
        isRetired = true
        deadline?.cancel()
        deadline = nil
        pool?.retireHandoff(self, webView: webView)
        // Keep the quarantine on the retired page. A late WebKit call may
        // still run, so it must never become visible or enter the idle pool.
        webView.editorSession?.retireQuarantinedHandoff(in: webView)
    }
}

/// A window's one idle, already bootstrapped editor page. Document sessions
/// still own exact source, history recovery, and transport identity. Reuse
/// avoids reloading bundled JavaScript; initialization installs a fresh state.
@MainActor
final class MarkdownEditorWebViewPool {
    #if DEBUG
        struct QADiagnosticCounts: Sendable {
            let idle: Int
            let attached: Int
            let preparing: Int
            let abandonedLive: Int
            let waiting: Int
        }
    #endif

    private let idleLifetime: Duration
    private let acquisitionDeadline: Duration
    private let maximumSafeReuses: Int
    private let preparationGate: (@MainActor () async -> Void)?
    private var idleWebView: WindowAttachedWebView?
    private weak var attachedWebView: WindowAttachedWebView?
    private let attachedWebViews = NSHashTable<WindowAttachedWebView>.weakObjects()
    private var tabLeasedSessionIDs: Set<ObjectIdentifier> = []
    private weak var preparingWebView: WindowAttachedWebView?
    private weak var handoffLease: MarkdownEditorHandoffLease?
    private let abandonedWebViews = NSHashTable<WindowAttachedWebView>.weakObjects()
    private var preparation: Task<Void, Never>?
    private var expiry: Task<Void, Never>?
    private struct WaitingAcquisition {
        let id: UUID
        weak var outgoingWebView: WindowAttachedWebView?
        let continuation: CheckedContinuation<WindowAttachedWebView?, Never>
        let deadline: Task<Void, Never>
    }
    private var waiting: [WaitingAcquisition] = []
    private(set) var acquisitionSerial = 0
    private(set) var preparationSettledSerial = 0
    private var generation = 0
    private var isInvalidated = false

    init(
        idleLifetime: Duration = .seconds(30),
        acquisitionDeadline: Duration = .seconds(2),
        maximumSafeReuses: Int = 16,
        preparationGate: (@MainActor () async -> Void)? = nil
    ) {
        precondition(maximumSafeReuses >= 0)
        self.idleLifetime = idleLifetime
        self.acquisitionDeadline = acquisitionDeadline
        self.maximumSafeReuses = maximumSafeReuses
        self.preparationGate = preparationGate
    }

    var hasPreparedView: Bool { idleWebView != nil }
    var hasOutgoingView: Bool {
        outgoingAttachedWebView != nil || preparation != nil
    }
    var waitingAcquisitionCount: Int { waiting.count }

    private var outgoingAttachedWebView: WindowAttachedWebView? {
        if let webView = attachedWebView, canYieldAttachedPage(webView) { return webView }
        // A previously created tab can depart while the most recently
        // attached page is still retained by another tab.
        return attachedWebViews.allObjects.first { canYieldAttachedPage($0) }
    }

    private func canYieldAttachedPage(_ webView: WindowAttachedWebView) -> Bool {
        guard !abandonedWebViews.contains(webView),
            let session = webView.editorSession,
            session.webView === webView,
            session.webViewPool === self,
            !tabLeasedSessionIDs.contains(ObjectIdentifier(session))
        else { return false }
        return true
    }

    /// Tab membership owns whether an attached page will actually depart.
    /// A new tab retains its predecessor, so waiting for that page to recycle
    /// would only expire. A detached page already preparing for reuse remains
    /// a valid acquisition regardless of its former session's membership.
    func reconcileTabLeases(_ sessions: [MarkdownEditorSession]) {
        tabLeasedSessionIDs = Set(sessions.map(ObjectIdentifier.init))
        for entry in waiting {
            guard let webView = entry.outgoingWebView,
                webView === preparingWebView || canYieldAttachedPage(webView)
            else {
                cancelWaiter(entry.id)
                continue
            }
        }
    }

    /// Transfer releases this pool's attachment projection without detaching,
    /// clearing or quarantining the page now owned by another window.
    func forgetTransferredSession(_ session: MarkdownEditorSession) {
        tabLeasedSessionIDs.remove(ObjectIdentifier(session))
        for webView in attachedWebViews.allObjects where webView.editorSession === session {
            attachedWebViews.remove(webView)
            cancelWaiters(for: webView)
        }
        if attachedWebView?.editorSession === session { attachedWebView = nil }
    }

    #if DEBUG
        var qaDiagnosticCounts: QADiagnosticCounts {
            QADiagnosticCounts(
                idle: idleWebView == nil ? 0 : 1,
                attached: attachedWebViews.allObjects.filter { webView in
                    guard let session = webView.editorSession else { return false }
                    return session.webView === webView && session.webViewPool === self
                }.count,
                preparing: preparingWebView == nil ? 0 : 1,
                abandonedLive: abandonedWebViews.allObjects.count,
                waiting: waiting.count
            )
        }
    #endif

    func take() -> WindowAttachedWebView? {
        guard let webView = idleWebView else { return nil }
        idleWebView = nil
        expiry?.cancel()
        expiry = nil
        webView.editorReuseCount += 1
        return webView
    }

    func registerAttached(_ webView: WindowAttachedWebView) {
        attachedWebViews.add(webView)
        attachedWebView = webView
    }

    /// A replacement may be made before SwiftUI dismantles its predecessor.
    /// Keep the new mount empty until the outgoing page is either cleared or
    /// quarantined for a checked document initialization.
    func takeWhenPrepared() async -> WindowAttachedWebView? {
        if let webView = take() { return webView }
        guard !isInvalidated,
            let outgoing = preparingWebView ?? outgoingAttachedWebView
        else { return nil }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: nil)
                } else {
                    acquisitionSerial &+= 1
                    let deadline = Task { @MainActor [weak self, acquisitionDeadline] in
                        try? await Task.sleep(for: acquisitionDeadline)
                        guard !Task.isCancelled else { return }
                        self?.expireAcquisition(id)
                    }
                    waiting.append(
                        WaitingAcquisition(
                            id: id, outgoingWebView: outgoing,
                            continuation: continuation, deadline: deadline))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        let entry = waiting.remove(at: index)
        entry.deadline.cancel()
        entry.continuation.resume(returning: nil)
    }

    private func cancelWaiters(for webView: WindowAttachedWebView) {
        for entry in waiting where entry.outgoingWebView === webView {
            cancelWaiter(entry.id)
        }
    }

    private func expireAcquisition(_ id: UUID) {
        guard let entry = waiting.first(where: { $0.id == id }) else { return }
        guard let outgoing = entry.outgoingWebView,
            outgoing === preparingWebView || canYieldAttachedPage(outgoing)
        else {
            cancelWaiter(id)
            return
        }
        // A hung outgoing page may still execute JavaScript after cancellation.
        // Retire only the page this acquisition actually awaited. Another
        // retained tab or a different preparation is not its timeout target.
        abandonedWebViews.add(outgoing)
        if outgoing === preparingWebView {
            discardIdleAndPreparation()
        } else {
            outgoing.editorHandoffLease?.retire()
        }
        cancelWaiters(for: outgoing)
    }

    private func finishWaiters(with webView: WindowAttachedWebView?) -> Bool {
        guard !waiting.isEmpty else { return false }
        if let webView, waiting.last?.outgoingWebView !== webView { return false }
        let newest = waiting.removeLast()
        newest.deadline.cancel()
        webView?.editorReuseCount += 1
        newest.continuation.resume(returning: webView)
        for entry in waiting {
            entry.deadline.cancel()
            entry.continuation.resume(returning: nil)
        }
        waiting.removeAll()
        return true
    }

    func recycle(_ webView: WKWebView, hasFrozenSnapshot: Bool = false) {
        let openingMeasurement = PerformanceProbe.shared.armedNoteOpeningAttemptID
        PerformanceProbe.shared.markNoteOpeningMilestone(.poolRecycleEntered, attemptID: openingMeasurement)
        if let webView = webView as? WindowAttachedWebView { attachedWebViews.remove(webView) }
        if let lease = (webView as? DocumentNativeWebView)?.editorHandoffLease {
            lease.retire()
            return
        }
        if let webView = webView as? WindowAttachedWebView,
            abandonedWebViews.contains(webView)
        {
            if attachedWebView === webView { attachedWebView = nil }
            return
        }
        guard !isInvalidated, let webView = webView as? WindowAttachedWebView else {
            abandonOutgoing(webView)
            return
        }
        if attachedWebView === webView { attachedWebView = nil }
        // Never retain the outgoing SwiftUI hierarchy, its coordinator, or
        // its closures. Only a detached, document-inaccessible page is idle.
        webView.removeFromSuperview()
        PerformanceProbe.shared.markNoteOpeningMilestone(.poolOutgoingDetached, attemptID: openingMeasurement)
        if webView.editorReuseCount >= maximumSafeReuses {
            abandonedWebViews.add(webView)
            discardIdleAndPreparation()
            _ = finishWaiters(with: nil)
            return
        }
        discardIdleAndPreparation()
        preparingWebView = webView
        let expectedGeneration = generation
        if preparationGate == nil,
            offerFrozenHandoff(
                webView, hasFrozenSnapshot: hasFrozenSnapshot, generation: expectedGeneration,
                openingMeasurement: openingMeasurement)
        {
            preparationSettledSerial &+= 1
            return
        }
        preparation = Task { @MainActor [weak self] in
            defer { self?.preparationSettledSerial &+= 1 }
            if let gate = self?.preparationGate { await gate() }
            guard !Task.isCancelled else { return }
            if self?.offerFrozenHandoff(
                webView, hasFrozenSnapshot: hasFrozenSnapshot, generation: expectedGeneration,
                openingMeasurement: openingMeasurement) == true
            {
                return
            }
            PerformanceProbe.shared.markNoteOpeningMilestone(.poolReuseRequested, attemptID: openingMeasurement)
            let cleared =
                try? await webView.evaluateJavaScript(
                    "window.scholiumEditor?.prepareForReuse() === true",
                    in: nil, contentWorld: .page
                ) as? Bool
            PerformanceProbe.shared.markNoteOpeningMilestone(.poolReuseReturned, attemptID: openingMeasurement)
            guard !Task.isCancelled, let self,
                self.generation == expectedGeneration, !self.isInvalidated
            else { return }
            self.preparation = nil
            self.preparingWebView = nil
            guard webView.navigationDelegate == nil, cleared == true else {
                _ = self.finishWaiters(with: nil)
                return
            }
            if self.finishWaiters(with: webView) { return }
            self.idleWebView = webView
            self.expiry = Task { @MainActor [weak self, idleLifetime = self.idleLifetime] in
                try? await Task.sleep(for: idleLifetime)
                guard !Task.isCancelled, let self,
                    self.generation == expectedGeneration,
                    self.idleWebView != nil
                else { return }
                self.removeAll()
            }
        }
    }

    private func offerFrozenHandoff(
        _ webView: WindowAttachedWebView, hasFrozenSnapshot: Bool, generation expectedGeneration: Int,
        openingMeasurement: UUID?
    ) -> Bool {
        guard hasFrozenSnapshot, waiting.last?.outgoingWebView === webView, generation == expectedGeneration,
            !isInvalidated, webView.navigationDelegate == nil
        else { return false }
        let lease = MarkdownEditorHandoffLease(
            pool: self, webView: webView, generation: expectedGeneration, timeout: acquisitionDeadline)
        webView.editorHandoffLease = lease
        handoffLease = lease
        preparation = nil
        preparingWebView = nil
        _ = finishWaiters(with: webView)
        PerformanceProbe.shared.markNoteOpeningMilestone(
            .poolHandoffOffered, attemptID: openingMeasurement)
        return true
    }

    func abandonOutgoing(_ webView: WKWebView) {
        if let webView = webView as? WindowAttachedWebView {
            attachedWebViews.remove(webView)
            cancelWaiters(for: webView)
        }
        (webView as? DocumentNativeWebView)?.editorHandoffLease?.retire()
        if attachedWebView === webView { attachedWebView = nil }
    }

    fileprivate func commitHandoff(
        _ lease: MarkdownEditorHandoffLease, webView: WindowAttachedWebView, generation: Int
    ) -> Bool {
        guard handoffLease === lease, self.generation == generation, !isInvalidated,
            attachedWebView === webView, !abandonedWebViews.contains(webView)
        else { return false }
        handoffLease = nil
        return true
    }

    fileprivate func retireHandoff(_ lease: MarkdownEditorHandoffLease, webView: WindowAttachedWebView) {
        abandonedWebViews.add(webView)
        attachedWebViews.remove(webView)
        guard handoffLease === lease else { return }
        handoffLease = nil
        if attachedWebView === webView { attachedWebView = nil }
        cancelWaiters(for: webView)
    }

    private func discardIdleAndPreparation() {
        generation &+= 1
        handoffLease?.retire()
        handoffLease = nil
        preparation?.cancel()
        preparation = nil
        preparingWebView = nil
        expiry?.cancel()
        expiry = nil
        idleWebView = nil
    }

    func removeAll() {
        discardIdleAndPreparation()
        _ = finishWaiters(with: nil)
    }

    func invalidate() {
        isInvalidated = true
        removeAll()
    }
}
