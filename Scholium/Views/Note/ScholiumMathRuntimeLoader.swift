import WebKit

/// Installs the app-owned mathematics runtime only for a document page that
/// presents mathematics. The coordinator validates the request and owns task
/// cancellation; this loader exposes no source or filesystem capability.
enum ScholiumMathRuntimeLoader {
    @MainActor
    static func installAndRefresh(in webView: WKWebView, contentWorld: WKContentWorld) async -> Bool {
        guard !Task.isCancelled else { return false }
        let installed = await install(in: webView, contentWorld: contentWorld)
        guard !Task.isCancelled else { return false }
        if installed {
            await refresh(in: webView, contentWorld: contentWorld)
            guard !Task.isCancelled else { return false }
        }
        // Successful refresh replaces pending source projections before the
        // geometry barrier proceeds. Failure settles their exact-source fallback.
        _ = try? await webView.callCancellableJavaScript(
            "window.dispatchEvent(new Event('scholium-math-runtime-settled'))",
            arguments: [:],
            in: nil,
            contentWorld: contentWorld
        )
        return installed
    }

    @MainActor
    private static func install(in webView: WKWebView, contentWorld: WKContentWorld) async -> Bool {
        guard !Task.isCancelled else { return false }
        let stylesReady = try? await webView.callCancellableJavaScript(
            "return getComputedStyle(document.documentElement).getPropertyValue('--scholium-math-css-ready').trim() === '1'",
            arguments: [:], in: nil, contentWorld: contentWorld
        )
        guard !Task.isCancelled else { return false }
        if stylesReady as? Bool != true {
            guard !ScholiumMathAssets.css.isEmpty else { return false }
            do {
                _ = try await webView.callCancellableJavaScript(
                    """
                    let style = document.getElementById('scholium-lazy-math-css');
                    if (!style) {
                        style = document.createElement('style');
                        style.id = 'scholium-lazy-math-css';
                        document.head.append(style);
                    }
                    style.textContent = css;
                    """,
                    arguments: ["css": ScholiumMathAssets.css], in: nil, contentWorld: contentWorld
                )
            } catch { return false }
            guard !Task.isCancelled else { return false }
        }
        let installed = try? await webView.callCancellableJavaScript(
            "return window.scholiumMath?.version === 1",
            arguments: [:],
            in: nil,
            contentWorld: contentWorld
        )
        guard !Task.isCancelled else { return false }
        if installed as? Bool == true {
            return true
        }
        guard !ScholiumMathAssets.runtimeJavaScript.isEmpty else { return false }
        do {
            guard !Task.isCancelled else { return false }
            _ = try await webView.evaluateCancellableJavaScript(
                ScholiumMathAssets.runtimeJavaScript,
                in: nil,
                contentWorld: contentWorld
            )
            guard !Task.isCancelled else { return false }
            return true
        } catch {
            // Exact mathematics source remains visible through the existing
            // fail-closed projection when the optional renderer cannot load.
            return false
        }
    }

    @MainActor
    private static func refresh(in webView: WKWebView, contentWorld: WKContentWorld) async {
        guard !Task.isCancelled else { return }
        _ = try? await webView.callCancellableJavaScript(
            "return window.scholiumEditor?.refreshMathRuntime?.() === true",
            arguments: [:],
            in: nil,
            contentWorld: contentWorld
        )
    }
}
