import WebKit

/// Installs the large, app-owned Mermaid runtime only after a validated page
/// bridge request. Assets remain immutable resources; each WebView coordinator
/// owns request identity, cancellation, and page lifetime.
enum ScholiumMermaidRuntimeLoader {
    @MainActor
    static func installAndNotify(in webView: WKWebView) async {
        let loaded = await install(in: webView)
        _ = try? await webView.callAsyncJavaScript(
            "window.scholiumMermaidRuntimeDidLoad?.(loaded)",
            arguments: ["loaded": loaded],
            in: nil,
            contentWorld: .page
        )
    }

    @MainActor
    private static func install(in webView: WKWebView) async -> Bool {
        if let installed = try? await webView.callAsyncJavaScript(
            "return window.scholiumMermaid?.version === 2",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ), installed as? Bool == true {
            return true
        }
        guard !ScholiumMermaidAssets.runtimeJavaScript.isEmpty else { return false }
        do {
            // WebKit explicitly supports evaluateJavaScript for installing
            // page-world libraries whose globals later calls rely on.
            _ = try await webView.evaluateJavaScript(
                ScholiumMermaidAssets.runtimeJavaScript
            )
            let installed = try await webView.callAsyncJavaScript(
                "return window.scholiumMermaid?.version === 2",
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            return installed as? Bool == true
        } catch {
            return false
        }
    }
}
