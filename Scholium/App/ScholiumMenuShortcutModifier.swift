import SwiftUI

/// SwiftUI delivery adapter for the canonical command catalog. Menu actions
/// and availability remain owned by the native command definitions.
extension ScholiumHotkeyModifiers {
    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if contains(.control) { result.insert(.control) }
        if contains(.option) { result.insert(.option) }
        if contains(.shift) { result.insert(.shift) }
        if contains(.command) { result.insert(.command) }
        return result
    }
}

extension ScholiumHotkeyBinding {
    var keyEquivalent: KeyEquivalent {
        KeyEquivalent(key.first!)
    }
}

extension View {
    func scholiumKeyboardShortcut(_ command: ScholiumHotkeyCommand) -> some View {
        modifier(ScholiumMenuShortcutModifier(command: command))
    }
}

private struct ScholiumMenuShortcutModifier: ViewModifier {
    let command: ScholiumHotkeyCommand
    @AppStorage(ScholiumHotkeyPreferences.defaultsKey)
    private var data = ScholiumHotkeyPreferences.defaultData

    func body(content: Content) -> some View {
        if let binding = ScholiumHotkeyPreferences.binding(for: command, data: data) {
            content.keyboardShortcut(binding.keyEquivalent, modifiers: binding.modifiers.eventModifiers)
        } else {
            content
        }
    }
}
