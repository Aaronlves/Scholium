import WebKit

/// Process-local WebKit configuration shared by Scholium's trusted Editor and
/// Read surfaces. The store is nonpersistent; CSP and scheme handlers retain
/// their narrower content boundaries on each concrete configuration.
@MainActor
enum ScholiumWebKitRuntime {
    static let nonPersistentDataStore = WKWebsiteDataStore.nonPersistent()
}

/// Starts WebKit in parallel with an initial workspace restore only when that
/// restore is known to present a Document. The first Review surface takes the
/// already-created view instead of constructing a second page context. Until
/// then, the font-only page carries no research source, path, script, storage,
/// or network capability and expires after a bounded interval.
@MainActor
final class ScholiumWebKitProcessPrewarmer {
    static let shared = ScholiumWebKitProcessPrewarmer()

    private var webView: WKWebView?
    private var expiryTask: Task<Void, Never>?

    var isActive: Bool { webView != nil }
    #if DEBUG
    var testingPreparedWebViewIdentity: ObjectIdentifier? {
        webView.map(ObjectIdentifier.init)
    }
    #endif

    func start() {
        guard webView == nil else { return }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = ScholiumWebKitRuntime.nonPersistentDataStore
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        ScholiumWebFontResources.install(in: configuration)
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 1, height: 1),
            configuration: configuration
        )
        self.webView = webView
        webView.loadHTMLString(
            """
            <!doctype html>
            <meta charset="utf-8">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; font-src scholium-font:">
            <style>\(ScholiumWebFonts.css) body { font-family: Alegreya, serif; }</style>
            <span aria-hidden="true">Scholium</span>
            """,
            baseURL: nil
        )
        expiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    /// Transfers the single prepared view to the first Review surface. Once
    /// taken, expiry and later completion signals no longer own that view.
    func takeReadWebView() -> WKWebView? {
        guard let webView else { return nil }
        expiryTask?.cancel()
        expiryTask = nil
        self.webView = nil
        return webView
    }

    func finish() {
        expiryTask?.cancel()
        expiryTask = nil
        webView?.stopLoading()
        webView = nil
    }
}
