import AppKit
import WebKit

enum DocumentPreviewFailure {
    case loading
    case size
    case measurement
}

/// Native presentation only. The originating document owns preview identity,
/// source, hover intent and invalidation; AppKit owns the visible frame.
@MainActor
final class DocumentPreviewPopover: NSObject, WKNavigationDelegate, NSPopoverDelegate {
    var onEvent: ((DocumentFloatingAction) -> Void)?
    var onShown: (() -> Void)?
    var onFailure: ((DocumentPreviewFailure) -> Void)?
    // One renderer per document host. Hidden content is never an active preview.
    private var renderer: PreviewWebView?
    var webView: WKWebView? { surface == nil ? nil : renderer }
    private var activeNavigation: WKNavigation?
    private var generation: UInt64 = 0
    var isShown: Bool { popover?.isShown == true }
    private weak var owner: WKWebView?
    private var surface: DocumentPreviewSurface?
    private var popover: NSPopover?
    private var measurement: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var appearanceObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var eventMonitor: Any?
    private var appearanceObservation: NSKeyValueObservation?
    private var imageResources: [String: String] = [:]

    func present(_ value: DocumentPreviewSurface, in owner: WKWebView, imageResources: [String: String] = [:]) {
        // Repeated pointer/focus reports retain both the loaded content and its
        // reading position. A different target gets a fresh measured presentation.
        if self.owner === owner, let surface,
            surface.html == value.html, surface.css == value.css, self.imageResources == imageResources,
            surface.left == value.left, surface.top == value.top, surface.bottom == value.bottom
        {
            self.surface = value
            return
        }
        dismiss()
        self.owner = owner
        surface = value
        self.imageResources = imageResources
        let content: PreviewWebView
        if let renderer {
            content = renderer
            content.frame = NSRect(x: 0, y: 0, width: min(368, owner.bounds.width - 24), height: 1)
        } else {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = ScholiumWebKitRuntime.nonPersistentDataStore
            configuration.defaultWebpagePreferences.allowsContentJavaScript = false
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            configuration.suppressesIncrementalRendering = true
            ScholiumWebFontResources.install(in: configuration)
            content = PreviewWebView(
                frame: NSRect(x: 0, y: 0, width: min(368, owner.bounds.width - 24), height: 1),
                configuration: configuration)
            content.setValue(false, forKey: "drawsBackground")
            content.underPageBackgroundColor = .clear
            renderer = content
        }
        content.allowsFocus = false
        content.appearance = owner.effectiveAppearance
        content.setAccessibilityElement(true)
        content.setAccessibilityIdentifier("scholium.documentPreview.content")
        content.navigationDelegate = self
        observeContext(owner)
        activeNavigation = content.loadHTMLString(Self.previewHTML(value), baseURL: nil)
    }

    func dismiss() {
        generation &+= 1
        activeNavigation = nil
        measurement?.cancel()
        measurement = nil
        appearanceObservation = nil
        for (center, token) in appearanceObservers { center.removeObserver(token) }
        appearanceObservers.removeAll()
        imageResources = [:]
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        let closing = popover
        popover = nil
        closing?.delegate = nil
        closing?.close()
        closing?.contentViewController = nil
        renderer?.stopLoading()
        renderer?.removeFromSuperview()
        renderer?.allowsFocus = false
        surface = nil
        owner = nil
    }

    /// Document departure releases both derived content and the WebKit page.
    func reset() {
        dismiss()
        renderer?.navigationDelegate = nil
        renderer = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView, let navigation, navigation === activeNavigation else { return }
        let generation = generation
        let imageResources = imageResources
        measurement?.cancel()
        measurement = Task { @MainActor [weak self, weak webView] in
            guard !Task.isCancelled, let webView, self?.generation == generation,
                webView === self?.webView, navigation === self?.activeNavigation
            else { return }
            // Finish font layout at the final width before exposing any window.
            let result = try? await webView.callAsyncJavaScript(
                """
                for (const image of document.querySelectorAll('img.scholium-embedded-image[data-scholium-image-resource]')) {
                    if (image.closest('.scholium-embedded-note')) continue;
                    const key = image.getAttribute('data-scholium-image-resource');
                    const resource = Object.hasOwn(resources, key) ? resources[key] : null;
                    if (resource) image.setAttribute('src', resource);
                    else {
                        const missing = document.createElement('span');
                        missing.className = 'scholium-media-placeholder';
                        missing.textContent = image.alt ? `${unavailable} (${image.alt})` : unavailable;
                        image.replaceWith(missing);
                    }
                }
                await document.fonts.ready;
                await Promise.all(Array.from(document.images, async image => {
                    let timer;
                    try {
                        await Promise.race([
                            image.decode(),
                            new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('image decode timeout')), 8000); })
                        ]);
                    } catch (_) {
                        const missing = document.createElement('span');
                        missing.className = 'scholium-media-placeholder';
                        missing.textContent = image.alt ? `${unavailable} (${image.alt})` : unavailable;
                        image.replaceWith(missing);
                    } finally { clearTimeout(timer); }
                }));
                return Math.ceil(document.body.getBoundingClientRect().height);
                """,
                arguments: [
                    "resources": imageResources,
                    "unavailable": ScholiumL10n.string("The image could not be previewed. It may be unavailable or unsupported."),
                ], in: nil, contentWorld: .page)
            guard !Task.isCancelled, let self, self.generation == generation,
                webView === self.webView, navigation === self.activeNavigation
            else { return }
            guard let owner = self.owner, let surface = self.surface,
                owner.window?.isVisible == true
            else {
                self.onEvent?(.dismiss)
                return
            }
            guard let height = result as? Double, height.isFinite, height > 0 else {
                self.onFailure?(.measurement)
                self.onEvent?(.dismiss)
                return
            }
            let size = NSSize(width: webView.frame.width, height: min(352, owner.bounds.height - 24, ceil(height)))
            let container = PreviewTrackingView(frame: NSRect(origin: .zero, size: size))
            container.onPointerPresence = { [weak self] entered in
                guard let self, self.generation == generation else { return }
                self.onEvent?(entered ? .enter : .leave)
            }
            container.setAccessibilityIdentifier("scholium.documentPreview")
            container.setAccessibilityElement(true)
            container.setAccessibilityEnabled(true)
            container.setAccessibilityRole(.group)
            container.setAccessibilityLabel(WebKitInterfaceLocalization.current().string("Preview content"))
            webView.frame = container.bounds
            webView.autoresizingMask = [.width, .height]
            container.addSubview(webView)
            let controller = NSViewController()
            controller.view = container
            let popover = NSPopover()
            // Hover previews must survive entering their content. Explicit outside
            // activation and the document's existing lifecycle dismiss this surface.
            popover.behavior = .applicationDefined
            popover.appearance = owner.effectiveAppearance
            popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            popover.contentViewController = controller
            popover.contentSize = size
            popover.delegate = self
            self.popover = popover
            let visibleTop = (owner.superview as? DocumentWebViewContainer)?.floatingContentTopInset ?? 0
            let top = min(max(visibleTop, surface.top), owner.bounds.height - 1)
            let bottom = min(max(top, surface.bottom), owner.bounds.height - 1)
            let anchor = NSRect(
                x: min(max(0, surface.left), owner.bounds.width - 1),
                y: owner.isFlipped ? top : owner.bounds.height - bottom,
                width: 1, height: max(1, bottom - top))
            popover.show(relativeTo: anchor, of: owner, preferredEdge: owner.isFlipped ? .maxY : .minY)
            (webView as? PreviewWebView)?.allowsFocus = true
            if popover.isShown { self.onShown?() }
        }
    }

    private func observeContext(_ owner: WKWebView) {
        appearanceObservation = owner.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshAppearance() }
        }
        for name in [NSColor.systemColorsDidChangeNotification, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification] {
            let center =
                name == NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
                ? NSWorkspace.shared.notificationCenter : NotificationCenter.default
            // Each token retains its own center for symmetric cancellation.
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshAppearance() }
            }
            appearanceObservers.append((center, token))
        }
        guard let window = owner.window else { return }
        for name in [NSWindow.willCloseNotification, NSWindow.didResizeNotification] {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onEvent?(.dismiss) }
                })
        }
        observers.append(
            NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onEvent?(.dismiss) }
            })
        observers.append(
            NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] notification in
                let activated = notification.object as? NSWindow
                MainActor.assumeIsolated {
                    guard let self, let activated,
                        activated !== self.owner?.window, activated !== self.webView?.window
                    else { return }
                    self.onEvent?(.dismiss)
                }
            })
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                if event.type == .keyDown {
                    // Leave document/IME key handling with its original owner.
                    if event.window === self.webView?.window, event.keyCode == 53 {
                        let owner = self.owner
                        self.onEvent?(.dismiss)
                        owner?.window?.makeKey()
                        owner?.window?.makeFirstResponder(owner)
                        return true
                    }
                } else if event.window !== self.webView?.window {
                    // The document must process its own marker activation first:
                    // a repeated click toggles a pinned annotation closed.
                    let target = event.window?.contentView?.hitTest(event.locationInWindow)
                    let isDocument =
                        self.owner.map { owner in
                            target.map { $0 === owner || $0.isDescendant(of: owner) } ?? false
                        } ?? false
                    if !isDocument { self.onEvent?(.dismiss) }
                }
                return false
            }
            return consumed ? nil : event
        }
    }

    private func refreshAppearance() {
        guard let owner, let renderer, surface != nil else { return }
        renderer.appearance = owner.effectiveAppearance
        popover?.appearance = owner.effectiveAppearance
        // Replace only the native style owner; preserve DOM, focus and scrolling.
        renderer.callAsyncJavaScript(
            "document.getElementById('scholium-native-preview-css')?.replaceChildren(document.createTextNode(css));",
            arguments: ["css": ScholiumPreviewStyles.nativeCSS], in: nil, in: .page
        ) { _ in }
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closed = notification.object as? NSPopover, closed === popover else { return }
        onEvent?(.dismiss)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        if webView === self.webView, let navigation, navigation === activeNavigation {
            onFailure?(.loading)
            onEvent?(.dismiss)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        if webView === self.webView, let navigation, navigation === activeNavigation {
            onFailure?(.loading)
            onEvent?(.dismiss)
        }
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(action.navigationType == .other && action.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
    }

    private static func previewHTML(_ value: DocumentPreviewSurface) -> String {
        let css = value.css.replacingOccurrences(of: "</style", with: "<\\/style", options: .caseInsensitive)
        return """
            <!doctype html><html><head><meta charset="utf-8">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src scholium-font: data:; connect-src 'none'; base-uri 'none'; form-action 'none'">
            <style>\(css)</style><style id="scholium-native-preview-css">
            \(ScholiumPreviewStyles.nativeCSS)
            </style></head><body>\(value.html)</body></html>
            """
    }
}

private final class PreviewWebView: WKWebView {
    // AppKit's initial key-view search must not take focus on hover. Once shown,
    // normal pointer and accessibility interaction may enter the preview.
    var allowsFocus = false
    override var acceptsFirstResponder: Bool { allowsFocus && super.acceptsFirstResponder }
}

private final class PreviewTrackingView: NSView {
    var onPointerPresence: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?
    override func accessibilityChildren() -> [Any]? { subviews }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        tracking = area
        addTrackingArea(area)
    }
    override func mouseEntered(with event: NSEvent) { onPointerPresence?(true) }
    override func mouseExited(with event: NSEvent) { onPointerPresence?(false) }
}
