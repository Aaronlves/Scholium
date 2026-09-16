import WebKit

/// A window's one idle, already bootstrapped editor page. Document sessions
/// still own exact source, history recovery, and transport identity. Reuse
/// avoids reloading bundled JavaScript; initialization installs a fresh state.
@MainActor
final class MarkdownEditorWebViewPool {
    private var idleWebView: WindowAttachedWebView?
    private var preparation: Task<Void, Never>?
    private var generation = 0
    private var isInvalidated = false

    var hasPreparedView: Bool { idleWebView != nil }

    func take() -> WindowAttachedWebView? {
        defer { idleWebView = nil }
        return idleWebView
    }

    func recycle(_ webView: WKWebView) {
        guard !isInvalidated, let webView = webView as? WindowAttachedWebView else { return }
        // Never retain the outgoing SwiftUI hierarchy, its coordinator, or
        // its closures. Only a detached, document-inaccessible page is idle.
        webView.removeFromSuperview()
        removeAll()
        let expectedGeneration = generation
        preparation = Task { @MainActor [weak self] in
            let cleared = try? await webView.callAsyncJavaScript(
                "return window.scholiumEditor?.prepareForReuse() === true",
                arguments: [:], in: nil, contentWorld: .page
            ) as? Bool
            guard !Task.isCancelled, let self,
                self.generation == expectedGeneration,
                !self.isInvalidated, webView.navigationDelegate == nil,
                cleared == true else { return }
            self.idleWebView = webView
            self.preparation = nil
        }
    }

    func removeAll() {
        generation &+= 1
        preparation?.cancel()
        preparation = nil
        idleWebView = nil
    }

    func invalidate() {
        isInvalidated = true
        removeAll()
    }
}
