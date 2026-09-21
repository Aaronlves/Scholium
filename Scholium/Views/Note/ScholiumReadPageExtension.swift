import WebKit

/// Optional feature ownership for the neutral, source-located Read runtime.
/// Document Review uses no extension. Other read-only consumers may provide a
/// bounded page capability without entering the Review coordinator's policy.
@MainActor
protocol ScholiumReadPageExtension: AnyObject {
    var requiresDedicatedWebView: Bool { get }
    var requiresMathRuntime: Bool { get }
    var replyProjectionEnabled: Bool { get }

    func makeWebView(configuration: WKWebViewConfiguration) -> WKWebView
    func preservesPage(
        currentDocumentID: String,
        nextDocumentID: String,
        hasLoadedPage: Bool
    ) -> Bool
    func canUpdateInPlace(
        currentDocumentID: String,
        nextDocumentID: String,
        hasLoadedPage: Bool
    ) -> Bool
    func acceptsMessageWithoutCurrentFingerprint(type: String) -> Bool
    func willBeginLoad(fingerprint: String)
    func updateIfNeeded(
        body: String,
        source: String,
        fingerprint: String,
        signature: String,
        documentID: String,
        loadGeneration: UInt64,
        presentationCSS: String,
        userCSS: String,
        in webView: WKWebView,
        isCurrent: @escaping @MainActor () -> Bool,
        didApply: @escaping @MainActor (_ source: String, _ fingerprint: String) -> Void,
        didFail: @escaping @MainActor (_ error: any Error) -> Void
    ) -> Bool
    func didFinishNavigation(
        _ navigation: WKNavigation?,
        isCurrent: @escaping @MainActor () -> Bool
    )
    func didFinalizePage(fingerprint: String)
    func handleMessage(
        type: String,
        payload: [String: Any],
        webView: WKWebView?
    ) -> Bool
    func cancel()
}
