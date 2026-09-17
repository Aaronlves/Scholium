import AppKit
import WebKit

typealias ScholiumDocumentKeyEquivalentRoute = @MainActor (NSEvent) -> Bool

@MainActor
protocol ScholiumDocumentInputStateProviding: AnyObject {
    var scholiumIsComposing: Bool { get }
}

/// Native geometry and accessibility boundary shared by the editor and reader.
/// WebKit owns the document; contextual native surfaces are sibling views.
final class DocumentWebViewContainer: NSView {
    let webView: WKWebView
    private let keyEquivalentRoute: ScholiumDocumentKeyEquivalentRoute
    private var loadingObservation: NSKeyValueObservation?
    override var isFlipped: Bool { true }

    init(
        webView: WKWebView,
        keyEquivalentRoute: @escaping ScholiumDocumentKeyEquivalentRoute = { _ in false }
    ) {
        self.webView = webView
        self.keyEquivalentRoute = keyEquivalentRoute
        super.init(frame: webView.frame)
        setAccessibilityElement(true)
        setAccessibilityEnabled(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(ScholiumL10n.string("Document"))
        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)
        // WebKit deliberately exposes a default blue CSS system Accent. Resolve
        // the researcher's choice in AppKit and project it into every retained
        // document, including Review and both editing modes.
        loadingObservation = webView.observe(\.isLoading, options: [.initial, .new]) {
            [weak self] _, change in
            guard change.newValue == false else { return }
            MainActor.assumeIsolated { self?.updateSystemAccent() }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemColorsDidChange),
            name: NSColor.systemColorsDidChangeNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSystemAccent()
    }

    @objc private func systemColorsDidChange(_ notification: Notification) {
        updateSystemAccent()
    }

    private func updateSystemAccent() {
        let value = ScholiumColorRole.systemAccentRGBValue(for: webView.effectiveAppearance)
        webView.callAsyncJavaScript(
            """
            const root = document.documentElement;
            if (root && root.style.getPropertyValue(name) !== value) {
                root.style.setProperty(name, value);
            }
            """,
            arguments: [
                "name": ScholiumColorRole.accent.cssVariableName,
                "value": String(format: "#%06x", value),
            ],
            in: nil,
            in: .defaultClient,
            completionHandler: nil
        )
    }

    private var documentOwnsKeyEquivalentFocus: Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder === webView || responder.isDescendant(of: webView)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // A focused WebKit document gets key equivalents before the menu bar.
        // Give registered app commands to their native menu owner first. The
        // composition root injects any app-level routing. This shared
        // container only supplies the native boundary and composition guard.
        // Hidden retained documents and other windows must never participate.
        if !isHiddenOrHasHiddenAncestor,
            window?.isKeyWindow == true,
            documentOwnsKeyEquivalentFocus,
            (webView as? any ScholiumDocumentInputStateProviding)?.scholiumIsComposing != true,
            keyEquivalentRoute(event)
        {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func accessibilityChildren() -> [Any]? {
        // WKWebView's own AX tree does not include arbitrary native subviews.
        // The native parent exposes both owners without mirroring their content.
        subviews
    }
}
