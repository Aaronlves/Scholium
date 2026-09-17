import AppKit

/// The application-level transport for commands whose action is owned by the
/// native menu. Document WebViews may receive a key equivalent before AppKit
/// asks the menu; this adapter preserves the menu as the sole action owner
/// without making a document container interpret command policy.
@MainActor
enum ScholiumCommandKeyEquivalentRouter {
    @discardableResult
    static func route(
        _ event: NSEvent,
        menu: NSMenu? = NSApp.mainMenu,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard ScholiumHotkeyEventAdapter.command(for: event, defaults: defaults) != nil else {
            return false
        }
        if menu?.performKeyEquivalent(with: event) != true {
            // Registered-but-disabled commands remain consumed so WebKit does
            // not reinterpret the same physical event as an editor action.
            NSSound.beep()
        }
        return true
    }
}
