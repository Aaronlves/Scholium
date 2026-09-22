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
    private var chromeObservation: NSKeyValueObservation?
    private let toolbarTransition = DocumentToolbarTransition()
    private var projectedToolbarInset: CGFloat?
    var toolbarUnderlapEnabled = false {
        didSet { if oldValue != toolbarUnderlapEnabled { needsLayout = true } }
    }
    private(set) var surfaceVisibility: DocumentSurfaceVisibility = .active
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
        toolbarTransition.isHidden = true
        addSubview(toolbarTransition)
        // WebKit deliberately exposes a default blue CSS system Accent. Resolve
        // the researcher's choice in AppKit and project it into every retained
        // document, including Review and both editing modes.
        loadingObservation = webView.observe(\.isLoading, options: [.initial, .new]) {
            [weak self] _, change in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.projectedToolbarInset = nil
                guard change.newValue == false else { return }
                self.updateSystemAccent()
                self.needsLayout = true
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemColorsDidChange),
            name: NSColor.systemColorsDidChangeNotification,
            object: nil
        )
    }

    /// Native WebKit views remain allocated for editor identity and recovery,
    /// but only the active document surface may participate in compositing or
    /// accessibility. SwiftUI hit-testing and z-order are not sufficient for
    /// NSView-backed WebKit content.
    func setSurfaceVisibility(_ visibility: DocumentSurfaceVisibility) {
        guard surfaceVisibility != visibility else { return }
        surfaceVisibility = visibility
        let isRetained = !visibility.isActive
        isHidden = isRetained
        webView.isHidden = isRetained
        needsLayout = true
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The document paints behind native chrome, but must not own its
        // pointer, selection or clicks. Exclude the whole WebKit subtree so
        // AppKit can route this area to the window's toolbar/titlebar.
        if toolbarUnderlapEnabled, toolbarOverlap.contains(convert(point, from: superview)) {
            return nil
        }
        return super.hitTest(point)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        chromeObservation = window?.observe(\.contentLayoutRect, options: [.initial, .new]) {
            [weak self] _, _ in
            MainActor.assumeIsolated { self?.needsLayout = true }
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let overlap = toolbarUnderlapEnabled ? toolbarOverlap : .zero
        toolbarTransition.frame = overlap
        toolbarTransition.isHidden = overlap.isEmpty
        // Retained surfaces need the same geometry before scroll restoration
        // and reveal; visibility must not change document padding.
        guard webView.superview === self, !webView.isLoading,
            projectedToolbarInset != overlap.height else { return }
        projectedToolbarInset = overlap.height
        webView.callAsyncJavaScript(
            "document.documentElement.style.setProperty(name, value)",
            arguments: ["name": "--scholium-document-toolbar-inset", "value": "\(overlap.height)px"],
            in: nil, in: .defaultClient,
            completionHandler: nil
        )
    }

    /// Window coordinates are unflipped; convert the actual chrome rectangle
    /// before intersecting. Tabs or notices may leave no overlap at all.
    var toolbarOverlap: NSRect {
        guard let window, let contentView = window.contentView else { return .zero }
        let content = contentView.convert(contentView.bounds, to: nil)
        let lowerEdge = window.contentLayoutRect.maxY
        let height = max(0, content.maxY - lowerEdge)
        guard height > 0 else { return .zero }
        let chrome = NSRect(x: content.minX, y: lowerEdge, width: content.width, height: height)
        let overlap = bounds.intersection(convert(chrome, from: nil))
        return overlap.isEmpty ? .zero : overlap
    }

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
        isHidden ? [] : subviews.filter { $0 !== toolbarTransition }
    }
}
