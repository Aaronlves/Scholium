import AppKit
import SwiftUI

/// One auxiliary search window belongs to one workspace coordinator. It owns
/// native geometry and lifetime; all query and result state stays in Search.
@MainActor
final class AdvancedSearchWindowController: NSWindowController, NSWindowDelegate {
    private let didClose: () -> Void
    private weak var sourceWindow: NSWindow?

    init<Content: View>(sourceWindow: NSWindow?, content: Content, didClose: @escaping () -> Void) {
        self.sourceWindow = sourceWindow
        self.didClose = didClose
        let initialContentSize = NSSize(width: 760, height: 620)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = ScholiumL10n.string("Advanced Search")
        window.identifier = NSUserInterfaceItemIdentifier("scholium.advancedSearchWindow")
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        let host = NSHostingController(rootView: content)
        // AppKit owns window sizing; changing Search projections must not refit it.
        host.sizingOptions = []
        window.contentViewController = host
        // The native minimum accommodates the existing Term Groups sheet.
        NSLayoutConstraint.activate([
            host.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 600),
            host.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 380),
        ])
        // Attaching a content controller can resize its window. Install the
        // initial size afterwards, leaving subsequent resizing to the researcher.
        window.setContentSize(initialContentSize)
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("AdvancedSearchWindowController is code-only") }

    func present(appearance: WindowColorSchemeChoice) {
        guard let window else { return }
        ScholiumWindowAppearance.apply(appearance, to: window)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        didClose()
        if sourceWindow?.isVisible == true { sourceWindow?.makeKeyAndOrderFront(nil) }
    }
}
