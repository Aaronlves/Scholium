import WebKit

/// Installs the app-owned mathematics runtime only for an Editor page that
/// presents mathematics. The coordinator validates the request and owns task
/// cancellation; this loader exposes no source or filesystem capability.
enum ScholiumMathRuntimeLoader {
    @MainActor
    static func installAndRefresh(in webView: WKWebView) async -> Bool {
        let installed = await install(in: webView)
        if installed { await refresh(in: webView) }
        // Successful refresh replaces pending source projections before the
        // geometry barrier proceeds. Failure settles their exact-source fallback.
        _ = try? await webView.callAsyncJavaScript(
            "window.dispatchEvent(new Event('scholium-math-runtime-settled'))",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        return installed
    }

    @MainActor
    private static func install(in webView: WKWebView) async -> Bool {
        if let installed = try? await webView.callAsyncJavaScript(
            "return window.scholiumMath?.version === 1",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ), installed as? Bool == true {
            return true
        }
        guard !ScholiumMathAssets.runtimeJavaScript.isEmpty else { return false }
        do {
            _ = try await webView.evaluateJavaScript(
                ScholiumMathAssets.runtimeJavaScript,
                in: nil,
                contentWorld: .page
            )
            return true
        } catch {
            // Exact mathematics source remains visible through the existing
            // fail-closed projection when the optional renderer cannot load.
            return false
        }
    }

    @MainActor
    private static func refresh(in webView: WKWebView) async {
        _ = try? await webView.callAsyncJavaScript(
            "return window.scholiumEditor?.refreshMathRuntime?.() === true",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
    }
}
