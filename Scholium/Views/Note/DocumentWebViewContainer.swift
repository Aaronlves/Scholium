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

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // A focused WebKit document gets key equivalents before the menu bar.
        // Give registered app commands to their native menu owner first, so
        // WebKit's editing/browser bindings cannot consume the same shortcut.
        // Hidden retained documents and other windows must never participate.
        if !isHiddenOrHasHiddenAncestor,
            window?.isKeyWindow == true,
            let responder = window?.firstResponder as? NSView,
            responder === webView || responder.isDescendant(of: webView),
            (webView as? WindowAttachedWebView)?.editorSession?.isComposing != true,
            ScholiumHotkeyPreferences.isMenuShortcut(event)
        {
            // A disabled app command must not fall through to a different
            // browser action with the same key (for example rich-text Italic).
            if NSApp.mainMenu?.performKeyEquivalent(with: event) != true {
                NSSound.beep()
            }
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
