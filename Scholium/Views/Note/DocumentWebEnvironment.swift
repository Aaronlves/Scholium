import AppKit
import WebKit

/// Projects native appearance and viewport insets into the current Web page.
/// Owns only disposable CSS values: never document text, selection, mode,
/// scrolling, hit testing or editor-session identity.
@MainActor
final class DocumentWebEnvironment: NSObject {
    private struct Values: Equatable {
        let colors: [String: String]
        let toolbarInset: CGFloat
    }

    private weak var webView: WKWebView?
    private weak var hostView: NSView?
    private var loadingObservation: NSKeyValueObservation?
    private var toolbarInset: CGFloat = 0
    private var projectedValues: Values?
    private var projectionRevision: UInt64 = 0

    init(webView: WKWebView, hostView: NSView) {
        self.webView = webView
        self.hostView = hostView
        super.init()
        loadingObservation = webView.observe(\.isLoading, options: [.initial, .new]) {
            [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.invalidateProjection()
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemColorsDidChange),
            name: NSColor.systemColorsDidChangeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemColorsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    func updateToolbarInset(_ inset: CGFloat) {
        toolbarInset = inset
        project()
    }

    func refreshAppearance() {
        invalidateProjection()
    }

    @objc private func systemColorsDidChange(_ notification: Notification) {
        refreshAppearance()
    }

    private func invalidateProjection() {
        projectionRevision &+= 1
        projectedValues = nil
        project()
    }

    private func project() {
        // An old retained container may outlive WebKit's return to the pool.
        // Its observations must never restyle the WebView's next attachment.
        guard let webView, let hostView, webView.superview === hostView,
            !webView.isLoading
        else { return }
        let increasedContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let values = Values(
            colors: Dictionary(
                uniqueKeysWithValues: ScholiumColorRole.allCases.map { role in
                    (
                        role.cssVariableName,
                        String(
                            format: "#%06x",
                            role.resolvedRGBValue(
                                for: webView.effectiveAppearance,
                                increasedContrast: increasedContrast
                            )
                        )
                    )
                }),
            toolbarInset: toolbarInset
        )
        guard projectedValues != values else { return }
        projectedValues = values
        projectionRevision &+= 1
        let revision = projectionRevision
        var cssValues = values.colors
        cssValues["--scholium-document-toolbar-inset"] = "\(values.toolbarInset)px"
        webView.callAsyncJavaScript(
            """
            const root = document.documentElement;
            if (!root) return false;
            for (const [name, value] of Object.entries(values)) {
                if (root.style.getPropertyValue(name) !== value) {
                    root.style.setProperty(name, value);
                }
            }
            return true;
            """,
            arguments: ["values": cssValues],
            in: nil,
            in: .defaultClient
        ) { [weak self] result in
            guard let self, self.projectionRevision == revision else { return }
            // A failed/empty-page delivery is not an applied projection. A
            // later layout or load may retry the current environment values.
            if case .success(let applied) = result, applied as? Bool == true { return }
            self.projectedValues = nil
        }
    }
}
