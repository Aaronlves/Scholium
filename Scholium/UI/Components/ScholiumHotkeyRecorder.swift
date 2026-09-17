import AppKit
import SwiftUI

/// Native input adapter for the SwiftUI shortcut settings page. It owns only
/// recording focus and control events; shortcut policy belongs to the catalog
/// and preference owner.
struct ScholiumHotkeyRecorder: NSViewRepresentable {
    @Binding var binding: ScholiumHotkeyBinding?
    @Binding var isRecording: Bool
    let isActive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton(title: "", target: context.coordinator, action: #selector(Coordinator.beginRecording))
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.setAccessibilityLabel("Shortcut recorder")
        context.coordinator.button = button
        update(button, coordinator: context.coordinator)
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        context.coordinator.parent = self
        update(nsView, coordinator: context.coordinator)
    }

    private func update(_ button: RecorderButton, coordinator: Coordinator) {
        button.title =
            isRecording
            ? String(localized: "Press a Shortcut…")
            : binding?.displayName ?? String(localized: "Record Shortcut")
        button.isRecording = isRecording && isActive
        button.isEnabled = isActive
        if !isActive, button.window?.firstResponder === button {
            button.window?.makeFirstResponder(nil)
        }
        button.setAccessibilityValue(binding?.displayName ?? String(localized: "No shortcut"))
        button.setAccessibilityHelp(
            "Activate, then press a shortcut that includes the Command key."
        )
        button.capture = { captured in
            coordinator.parent.binding = captured
            coordinator.parent.isRecording = false
        }
        button.clear = {
            coordinator.parent.binding = nil
            coordinator.parent.isRecording = false
        }
        button.cancel = {
            coordinator.parent.isRecording = false
        }
    }

    @MainActor
    final class Coordinator {
        var parent: ScholiumHotkeyRecorder
        weak var button: RecorderButton?

        init(parent: ScholiumHotkeyRecorder) {
            self.parent = parent
        }

        @objc func beginRecording() {
            guard parent.isActive else { return }
            parent.isRecording = true
            button?.isRecording = true
            button?.title = String(localized: "Press a Shortcut…")
            button?.window?.makeFirstResponder(button)
        }
    }

    final class RecorderButton: ScholiumPointingHandButton {
        var isRecording = false
        var capture: ((ScholiumHotkeyBinding) -> Void)?
        var clear: (() -> Void)?
        var cancel: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                super.keyDown(with: event)
                return
            }
            handle(event)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard isRecording else {
                return super.performKeyEquivalent(with: event)
            }
            handle(event)
            return true
        }

        private func handle(_ event: NSEvent) {
            if event.keyCode == 53 {
                cancel?()
                return
            }
            if event.keyCode == 51 || event.keyCode == 117 {
                clear?()
                return
            }
            guard let binding = ScholiumHotkeyEventAdapter.binding(from: event) else {
                NSSound.beep()
                return
            }
            capture?(binding)
        }
    }
}
