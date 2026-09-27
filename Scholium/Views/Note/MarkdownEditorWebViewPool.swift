import WebKit

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
    private weak var preparingWebView: WindowAttachedWebView?
    private let abandonedWebViews = NSHashTable<WindowAttachedWebView>.weakObjects()
    private var preparation: Task<Void, Never>?
    private var expiry: Task<Void, Never>?
    private struct WaitingAcquisition {
        let id: UUID
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
        (attachedWebView.map { !abandonedWebViews.contains($0) } ?? false) || preparation != nil
    }
    var waitingAcquisitionCount: Int { waiting.count }

    #if DEBUG
        var qaDiagnosticCounts: QADiagnosticCounts {
            QADiagnosticCounts(
                idle: idleWebView == nil ? 0 : 1,
                attached: attachedWebView == nil ? 0 : 1,
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
        attachedWebView = webView
    }

    /// A replacement may be made before SwiftUI dismantles its predecessor.
    /// Keep the new mount empty until the outgoing page has completed its
    /// JavaScript reset. A failed reset grants no reuse.
    func takeWhenPrepared() async -> WindowAttachedWebView? {
        if let webView = take() { return webView }
        guard !isInvalidated, hasOutgoingView else { return nil }
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
                            id: id, continuation: continuation, deadline: deadline))
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

    private func expireAcquisition(_ id: UUID) {
        guard waiting.contains(where: { $0.id == id }) else { return }
        // A hung outgoing page may still execute JavaScript after cancellation.
        // Retire that exact page and advance the generation before resolving
        // mounts to the ordinary fresh-page path.
        if let oldPage = preparingWebView ?? attachedWebView {
            abandonedWebViews.add(oldPage)
        }
        discardIdleAndPreparation()
        _ = finishWaiters(with: nil)
    }

    private func finishWaiters(with webView: WindowAttachedWebView?) -> Bool {
        guard !waiting.isEmpty else { return false }
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

    func recycle(_ webView: WKWebView) {
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
        if webView.editorReuseCount >= maximumSafeReuses {
            abandonedWebViews.add(webView)
            discardIdleAndPreparation()
            _ = finishWaiters(with: nil)
            return
        }
        discardIdleAndPreparation()
        preparingWebView = webView
        let expectedGeneration = generation
        preparation = Task { @MainActor [weak self] in
            defer { self?.preparationSettledSerial &+= 1 }
            if let gate = self?.preparationGate { await gate() }
            guard !Task.isCancelled else { return }
            let cleared =
                try? await webView.callAsyncJavaScript(
                    "return window.scholiumEditor?.prepareForReuse() === true",
                    arguments: [:], in: nil, contentWorld: .page
                ) as? Bool
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

    func abandonOutgoing(_ webView: WKWebView) {
        if attachedWebView === webView { attachedWebView = nil }
        if preparation == nil { _ = finishWaiters(with: nil) }
    }

    private func discardIdleAndPreparation() {
        generation &+= 1
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
