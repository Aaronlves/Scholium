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
    private var navigationDelegate: PrewarmNavigationDelegate?
    private var isPageReady = false
    private var expiryTask: Task<Void, Never>?

    var isActive: Bool { webView != nil }
    #if DEBUG
    var testingPreparedWebViewIdentity: ObjectIdentifier? {
        webView.map(ObjectIdentifier.init)
    }
    var testingPreparedWebViewIsReady: Bool { isPageReady }
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
        let navigationDelegate = PrewarmNavigationDelegate { [weak self] in
            self?.isPageReady = true
        }
        self.navigationDelegate = navigationDelegate
        self.isPageReady = false
        self.webView = webView
        webView.navigationDelegate = navigationDelegate
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

    /// Transfers the prepared view only after its isolated page has finished.
    /// An in-flight WebKit page must never cross from the prewarmer into a
    /// SwiftUI/AppKit hierarchy: its pending remote-layer transaction belongs
    /// to the original lifecycle owner.
    func takeReadWebView() -> WKWebView? {
        guard isPageReady, let webView else { return nil }
        expiryTask?.cancel()
        expiryTask = nil
        webView.navigationDelegate = nil
        navigationDelegate = nil
        self.webView = nil
        isPageReady = false
        return webView
    }

    func finish() {
        expiryTask?.cancel()
        expiryTask = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        navigationDelegate = nil
        isPageReady = false
    }

    private final class PrewarmNavigationDelegate: NSObject, WKNavigationDelegate {
        private let didFinish: @MainActor () -> Void

        init(didFinish: @escaping @MainActor () -> Void) {
            self.didFinish = didFinish
        }

        @MainActor
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFinish()
        }
    }
}
