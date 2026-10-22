import WebKit

/// Installs the app-owned Pele renderer for Mermaid syntax only after a validated page
/// bridge request. Assets remain immutable resources; each WebView coordinator
/// owns request identity, cancellation, and page lifetime.
enum ScholiumMermaidRuntimeLoader {
    @MainActor
    static func installAndNotify(
        in webView: WKWebView,
        contentWorld: WKContentWorld = .page
    ) async {
        guard !Task.isCancelled else { return }
        let loaded = await install(in: webView, contentWorld: contentWorld)
        guard !Task.isCancelled else { return }
        _ = try? await webView.callCancellableJavaScript(
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
        guard !Task.isCancelled else { return false }
        let installed = try? await webView.callCancellableJavaScript(
            "return window.scholiumMermaid?.version === 3",
            arguments: [:],
            in: nil,
            contentWorld: contentWorld
        )
        guard !Task.isCancelled else { return false }
        if installed as? Bool == true {
            return true
        }
        guard !ScholiumMermaidAssets.runtimeJavaScript.isEmpty else { return false }
        do {
            guard !Task.isCancelled else { return false }
            // WebKit explicitly supports evaluateJavaScript for installing
            // content-world libraries whose globals later calls rely on.
            _ = try await webView.evaluateCancellableJavaScript(
                ScholiumMermaidAssets.runtimeJavaScript,
                in: nil,
                contentWorld: contentWorld
            )
            guard !Task.isCancelled else { return false }
            let installed = try await webView.callCancellableJavaScript(
                "return window.scholiumMermaid?.version === 3",
                arguments: [:],
                in: nil,
                contentWorld: contentWorld
            )
            guard !Task.isCancelled else { return false }
            return installed as? Bool == true
        } catch {
            return false
        }
    }
}
