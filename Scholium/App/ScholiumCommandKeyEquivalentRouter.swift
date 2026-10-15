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
        let handled = menu?.performKeyEquivalent(with: event) == true
        #if DEBUG
            if ScholiumHotkeyEventAdapter.command(for: event, defaults: defaults) == .save {
                var flags: [PerformanceProbe.QASaveFlag: Bool] = [.menuHandled: handled]
                let enabled = menuItemEnabled(for: event, in: menu)
                flags[.menuItemFound] = enabled != nil
                flags[.menuEnabled] = enabled
                PerformanceProbe.shared.recordQASaveStage(.nativeKeyMenuResult, flags: flags)
            }
        #endif
        if !handled {
            // Registered-but-disabled commands remain consumed so WebKit does
            // not reinterpret the same physical event as an editor action.
            NSSound.beep()
        }
        return true
    }

    #if DEBUG
        private static func menuItemEnabled(for event: NSEvent, in menu: NSMenu?) -> Bool? {
            guard let menu,
                let key = event.characters(byApplyingModifiers: .command)?.lowercased()
                    ?? event.charactersIgnoringModifiers?.lowercased()
            else { return nil }
            let relevantFlags: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            for item in menu.items {
                if !item.keyEquivalent.isEmpty,
                    item.keyEquivalent.lowercased() == key,
                    item.keyEquivalentModifierMask.intersection(relevantFlags)
                        == event.modifierFlags.intersection(relevantFlags)
                {
                    return item.isEnabled
                }
                if let enabled = menuItemEnabled(for: event, in: item.submenu) { return enabled }
            }
            return nil
        }
    #endif
}
