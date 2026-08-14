import WebKit

/// Installs the app-owned mathematics runtime only for an Editor page that
/// presents mathematics. The coordinator validates the request and owns task
/// cancellation; this loader exposes no source or filesystem capability.
enum ScholiumMathRuntimeLoader {
    @MainActor
    static func installAndRefresh(in webView: WKWebView) async -> Bool {
        if let installed = try? await webView.callAsyncJavaScript(
            "return window.scholiumMath?.version === 1",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ), installed as? Bool == true {
            await refresh(in: webView)
            return true
        }
        guard !ScholiumMathAssets.runtimeJavaScript.isEmpty else { return false }
        do {
            _ = try await webView.evaluateJavaScript(
                ScholiumMathAssets.runtimeJavaScript,
                in: nil,
                contentWorld: .page
            )
            await refresh(in: webView)
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
