import WebKit

/// Owns the cancellable lazy mathematics and Mermaid runtime installation for one retained
/// Read surface. The generated Reader bundle owns rendering after installation.
@MainActor
final class SafeMarkdownReadRuntimeCoordinator {
    var bridgeContentWorld = SafeMarkdownReadWebView.bridgeContentWorld
    private var mathTask: Task<Void, Never>?
    private var mathLoadID: UUID?
    private var mermaidTask: Task<Void, Never>?
    private var mermaidLoadID: UUID?

    func requestMermaid(
        in webView: WKWebView,
        isCurrent: @escaping @MainActor () -> Bool
    ) {
        guard mermaidTask == nil else { return }
        let loadID = UUID()
        mermaidLoadID = loadID
        mermaidTask = Task { @MainActor [weak self, weak webView] in
            guard let self else { return }
            defer {
                if self.mermaidLoadID == loadID {
                    self.mermaidTask = nil
                    self.mermaidLoadID = nil
                }
            }
            guard let webView, !Task.isCancelled, isCurrent() else { return }
            await ScholiumMermaidRuntimeLoader.installAndNotify(
                in: webView,
                contentWorld: self.bridgeContentWorld
            )
        }
    }

    func requestMath(in webView: WKWebView, isCurrent: @escaping @MainActor () -> Bool) {
        guard mathTask == nil else { return }
        let loadID = UUID()
        let contentWorld = bridgeContentWorld
        mathLoadID = loadID
        mathTask = Task { @MainActor [weak self, weak webView] in
            guard let self else { return }
            defer {
                if self.mathLoadID == loadID {
                    self.mathTask = nil
                    self.mathLoadID = nil
                }
            }
            guard let webView, !Task.isCancelled, isCurrent() else { return }
            _ = await ScholiumMathRuntimeLoader.installAndRefresh(in: webView, contentWorld: contentWorld)
        }
    }

    func cancel() {
        mathTask?.cancel()
        mathTask = nil
        mathLoadID = nil
        mermaidTask?.cancel()
        mermaidTask = nil
        mermaidLoadID = nil
    }
}
