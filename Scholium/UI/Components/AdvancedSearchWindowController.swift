import AppKit
import SwiftUI

/// One auxiliary search window belongs to one workspace coordinator. It owns
/// native window lifetime only; all query and result state stays in Search.
@MainActor
final class AdvancedSearchWindowController: NSWindowController, NSWindowDelegate {
    private let didClose: () -> Void
    private weak var sourceWindow: NSWindow?

    init<Content: View>(sourceWindow: NSWindow?, content: Content, didClose: @escaping () -> Void) {
        self.sourceWindow = sourceWindow
        self.didClose = didClose
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = ScholiumL10n.string("Advanced Search")
        window.identifier = NSUserInterfaceItemIdentifier("scholium.advancedSearchWindow")
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentMinSize = NSSize(width: 480, height: 340)
        window.contentViewController = NSHostingController(rootView: content)
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
