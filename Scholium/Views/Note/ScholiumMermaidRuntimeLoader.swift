import WebKit

/// Installs the large, app-owned Mermaid runtime only after a validated page
/// bridge request. Assets remain immutable resources; each WebView coordinator
/// owns request identity, cancellation, and page lifetime.
enum ScholiumMermaidRuntimeLoader {
    @MainActor
    static func installAndNotify(
        in webView: WKWebView,
        contentWorld: WKContentWorld = .page
    ) async {
        let loaded = await install(in: webView, contentWorld: contentWorld)
        _ = try? await webView.callAsyncJavaScript(
            "window.scholiumMermaidRuntimeDidLoad?.(loaded)",
            arguments: ["loaded": loaded],
            in: nil,
            contentWorld: contentWorld
        )
    }

    @MainActor
    private static func install(
        in webView: WKWebView,
        contentWorld: WKContentWorld
    ) async -> Bool {
        if let installed = try? await webView.callAsyncJavaScript(
            "return window.scholiumMermaid?.version === 2",
            arguments: [:],
            in: nil,
            contentWorld: contentWorld
        ), installed as? Bool == true {
            return true
        }
        guard !ScholiumMermaidAssets.runtimeJavaScript.isEmpty else { return false }
        do {
            // WebKit explicitly supports evaluateJavaScript for installing
            // content-world libraries whose globals later calls rely on.
            _ = try await webView.evaluateJavaScript(
                ScholiumMermaidAssets.runtimeJavaScript,
                in: nil,
                contentWorld: contentWorld
            )
            let installed = try await webView.callAsyncJavaScript(
                "return window.scholiumMermaid?.version === 2",
                arguments: [:],
                in: nil,
                contentWorld: contentWorld
            )
            return installed as? Bool == true
        } catch {
            return false
        }
    }
}
