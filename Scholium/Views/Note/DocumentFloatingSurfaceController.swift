import AppKit
import WebKit

/// A bounded read-only projection, never an editor/source operation.
struct DocumentFloatingSurface: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case preview, suggestions, selection, hidden }
    struct Item: Codable, Equatable, Sendable {
        let label: String
        let detail: String
    }
    let id: Int
    let kind: Kind
    let left: Double
    let top: Double
    let bottom: Double
    let html: String
    let css: String
    let items: [Item]
    let selected: Int

    static func decode(_ value: Any?) -> Self? {
        guard let value = value as? [String: Any],
              Set(value.keys) == ["id", "kind", "left", "top", "bottom", "html", "css", "items", "selected"],
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              data.count <= 1_500_000,
              let result = try? JSONDecoder().decode(Self.self, from: data),
              result.id > 0,
              [result.left, result.top, result.bottom].allSatisfy({ $0.isFinite && abs($0) <= 100_000 }),
              result.bottom >= result.top,
              result.html.utf8.count <= 500_000, result.css.utf8.count <= 900_000,
              result.items.count <= 100,
              result.items.allSatisfy({ $0.label.utf16.count <= 512 && $0.detail.utf16.count <= 1_024 }),
              result.selected >= -1, result.selected < max(1, result.items.count) else { return nil }
        switch result.kind {
        case .preview:
            guard !result.html.isEmpty, result.items.isEmpty, result.selected == -1 else { return nil }
        case .suggestions:
            guard result.html.isEmpty, result.css.isEmpty, !result.items.isEmpty else { return nil }
        case .selection:
            guard result.html.isEmpty, result.css.isEmpty, result.items.isEmpty, result.selected == -1 else { return nil }
        case .hidden:
            guard result.html.isEmpty, result.css.isEmpty, result.items.isEmpty else { return nil }
        }
        return result
    }
}

/// Owns only native floating presentation in the originating WebKit viewport.
/// No window, source mirror, editing history, or independent completion state.
@MainActor
final class DocumentFloatingSurfaceController: NSObject, WKNavigationDelegate {
    private weak var owner: WKWebView?
    private var surface: DocumentFloatingSurface?
    private var glass: TrackingGlassView?
    private var preview: FloatingPreviewWebView?
    private var suggestions: NativeFloatingChoiceList?
    private var preferredWidth: CGFloat = 368
    var previewWebView: WKWebView? { preview }
    private var event: ((Int, String, Int) -> Void)?
    private var observers: [NSObjectProtocol] = []

    func present(
        _ value: DocumentFloatingSurface,
        in webView: WKWebView,
        event: @escaping (Int, String, Int) -> Void
    ) {
        if value.kind == .hidden {
            if surface?.id == value.id { dismiss() }
            return
        }
        guard webView.window != nil, webView.bounds.width > 24, webView.bounds.height > 24,
              let viewport = webView.superview as? DocumentWebViewContainer else { return }
        if let surface, value.id <= surface.id { return }
        if value.kind == .selection,
           value.bottom + 52 > webView.bounds.height - 12, value.top < 64 {
            dismiss()
            return
        }
        let isSamePreview = surface?.kind == .preview && value.kind == .preview
            && surface?.html == value.html && surface?.css == value.css
        self.event = event
        self.owner = webView
        self.surface = value
        if glass == nil {
            let container = TrackingGlassView()
            container.style = .regular
            container.setAccessibilityEnabled(true)
            container.cornerRadius = ScholiumCornerRole.boundedPanel.radius
            container.onPointerPresence = { [weak self] entered in self?.send(entered ? "enter" : "leave") }
            glass = container
            viewport.addSubview(container, positioned: .above, relativeTo: webView)
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didUpdateNotification, object: webView.window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let owner = self.owner,
                          let responder = owner.window?.firstResponder as? NSView,
                          responder !== owner, !responder.isDescendant(of: owner),
                          self.glass.map({ !responder.isDescendant(of: $0) }) == true else { return }
                    self.send("dismiss")
                    self.dismiss()
                }
            })
            for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification, NSWindow.didResizeNotification] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: webView.window, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.send("dismiss"); self?.dismiss() }
                })
            }
        }
        guard let glass else { return }
        switch value.kind {
        case .suggestions:
            preview?.stopLoading()
            preview = nil
            let content = suggestions ?? NativeFloatingChoiceList(acceptsKeyboard: false)
            if suggestions == nil {
                suggestions = content
                glass.contentView = content
            }
            content.choose = { [weak self] index in self?.send("choose", index: index) }
            content.select = { [weak self] index in self?.send("select", index: index) }
            content.update(items: value.items.map { .init(label: $0.label, detail: $0.detail) }, selected: value.selected)
            preferredWidth = content.preferredSize.width
            // CodeMirror retains the single AX listbox, active descendant and keyboard path.
            glass.setAccessibilityElement(true)
            glass.setAccessibilityRole(.group)
            glass.setAccessibilityLabel(ScholiumL10n.string("Suggestions"))
            glass.setAccessibilityIdentifier("scholium.documentSuggestions")
            glass.setAccessibilityChildren([])
            layout(height: content.preferredSize.height)
        case .preview:
            suggestions = nil
            preferredWidth = 368
            glass.setAccessibilityElement(true)
            glass.setAccessibilityRole(.group)
            glass.setAccessibilityLabel(WebKitInterfaceLocalization.current().string("Preview content"))
            glass.setAccessibilityIdentifier("scholium.documentPreview")
            if !isSamePreview || preview == nil {
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = ScholiumWebKitRuntime.nonPersistentDataStore
                configuration.defaultWebpagePreferences.allowsContentJavaScript = false
                configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
                ScholiumWebFontResources.install(in: configuration)
                let content = FloatingPreviewWebView(frame: .zero, configuration: configuration)
                content.setValue(false, forKey: "drawsBackground")
                content.underPageBackgroundColor = .clear
                content.setAccessibilityElement(true)
                content.setAccessibilityIdentifier("scholium.documentPreview.content")
                content.navigationDelegate = self
                content.onDismiss = { [weak self] in
                    guard let self else { return }
                    self.send("dismiss")
                    self.owner?.window?.makeFirstResponder(self.owner)
                    self.dismiss()
                }
                preview = content
                glass.contentView = content
                layout(height: 240)
                content.loadHTMLString(Self.previewHTML(value), baseURL: nil)
            } else {
                layout(height: glass.frame.height)
            }
            glass.setAccessibilityChildren(glass.contentView.map { [$0] })
        case .selection:
            preview?.stopLoading()
            preview = nil
            suggestions = nil
            let button = NSButton(title: ScholiumL10n.string("Ask Agent"), target: self, action: #selector(askAgent))
            button.bezelStyle = .inline
            button.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.setAccessibilityLabel(ScholiumL10n.string("Ask Agent"))
            button.setAccessibilityIdentifier("scholium.document.askAgent")
            button.sizeToFit()
            preferredWidth = button.fittingSize.width + 24
            glass.contentView = button
            glass.setAccessibilityElement(false)
            glass.setAccessibilityChildren([button])
            layout(height: max(32, button.fittingSize.height + 12))
        case .hidden: break
        }
    }

    func dismiss() {
        preview?.stopLoading()
        preview?.navigationDelegate = nil
        if let preview, let owner,
           let responder = owner.window?.firstResponder as? NSView,
           responder.isDescendant(of: preview) {
            owner.window?.makeFirstResponder(owner)
        }
        preview = nil
        suggestions = nil
        glass?.removeFromSuperview()
        glass = nil
        surface = nil
        event = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }

    @objc private func askAgent() { send("choose", index: 0) }

    private func send(_ action: String, index: Int = -1) {
        guard let surface else { return }
        event?(surface.id, action, index)
    }

    private func layout(height: CGFloat) {
        guard let owner, let surface, let glass else { return }
        let bounds = owner.bounds
        let width = min(preferredWidth, 368, bounds.width - 24)
        let height = min(height, 352, bounds.height - 24)
        let x = min(max(12, surface.left), bounds.width - width - 12)
        let below = surface.bottom + 8
        let top = below + height <= bounds.height - 12
            ? below : max(12, surface.top - height - 8)
        let rect = NSRect(x: x, y: owner.isFlipped ? top : bounds.height - top - height,
                          width: width, height: height)
        glass.frame = owner.convert(rect, to: glass.superview)
        glass.contentView?.frame = glass.bounds
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === preview else { return }
        let id = surface?.id
        webView.evaluateJavaScript("document.body.scrollHeight") { [weak self, weak webView] result, _ in
            guard let self, webView === self.preview, self.surface?.id == id,
                  let height = result as? Double, height.isFinite else { return }
            self.layout(height: height)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        decisionHandler(action.navigationType == .other && action.request.url?.absoluteString == "about:blank"
                        ? .allow : .cancel)
    }

    private static func previewHTML(_ value: DocumentFloatingSurface) -> String {
        let css = value.css.replacingOccurrences(of: "</style", with: "<\\/style", options: .caseInsensitive)
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src scholium-font: data:; connect-src 'none'; base-uri 'none'; form-action 'none'">
        <style>\(css)</style><style>
        html, body { margin: 0 !important; min-height: 0 !important; height: auto !important; background: transparent !important; }
        body { padding: 14px 16px !important; box-sizing: border-box; color: var(--scholium-color-primary-text); overflow-wrap: anywhere; }
        .scholium-preview-body.scholium-document { padding: 0 !important; margin: 0 !important; min-height: 0 !important; max-width: none !important; }
        </style></head><body>\(value.html)</body></html>
        """
    }
}

private final class TrackingGlassView: NSGlassEffectView {
    var onPointerPresence: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        tracking = area
        addTrackingArea(area)
    }
    override func mouseEntered(with event: NSEvent) { onPointerPresence?(true) }
    override func mouseExited(with event: NSEvent) { onPointerPresence?(false) }
}

private final class FloatingPreviewWebView: WKWebView {
    var onDismiss: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onDismiss?() } else { super.keyDown(with: event) }
    }
}
