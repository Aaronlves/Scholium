import AppKit
import WebKit

/// Native geometry and accessibility boundary shared by the editor and reader.
/// WebKit owns the document; contextual native surfaces are sibling views.
final class DocumentWebViewContainer: NSView {
    let webView: WKWebView
    override var isFlipped: Bool { true }

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: webView.frame)
        setAccessibilityElement(true)
        setAccessibilityEnabled(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(ScholiumL10n.string("Document"))
        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)
    }

    required init?(coder: NSCoder) { nil }

    override func accessibilityChildren() -> [Any]? {
        // WKWebView's own AX tree does not include arbitrary native subviews.
        // The native parent exposes both owners without mirroring their content.
        subviews
    }
}
