import AppKit

/// Converts AppKit's physical key events into the canonical shortcut value.
/// It owns no persistence or command action; those remain with the shortcut
/// preference owner and native menu respectively.
@MainActor
enum ScholiumHotkeyEventAdapter {
    static func binding(from event: NSEvent) -> ScholiumHotkeyBinding? {
        guard event.type == .keyDown,
            let characters = event.characters(byApplyingModifiers: .command)
                ?? event.charactersIgnoringModifiers,
            let character = characters.first
        else { return nil }
        return ScholiumHotkeyBinding(
            key: String(character),
            modifiers: modifiers(from: event.modifierFlags)
        )
    }

    static func command(
        for event: NSEvent,
        defaults: UserDefaults = .standard
    ) -> ScholiumHotkeyCommand? {
        guard let binding = binding(from: event) else { return nil }
        return ScholiumHotkeyPreferences.command(for: binding, defaults: defaults)
    }

    private static func modifiers(from flags: NSEvent.ModifierFlags) -> ScholiumHotkeyModifiers {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var result: ScholiumHotkeyModifiers = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        return result
    }
}
