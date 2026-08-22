import AppKit
import SwiftUI

struct HotkeySettingsView: View {
    @AppStorage(ScholiumHotkeyPreferences.defaultsKey)
    private var preferencesData = ScholiumHotkeyPreferences.defaultData
    @State private var editingCommand: ScholiumHotkeyCommand?
    @State private var pendingResetAll = false

    let searchQuery: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsTitle(
                "Hotkeys",
                detail: "Customize frequently used Scholium commands. Standard macOS shortcuts remain unchanged."
            )
            .padding(ScholiumMetrics.Settings.editorContentInset)

            Divider()

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.sectionSeparation
                ) {
                    ForEach(visibleCategories) { category in
                        settingsEditorSection(category.title) {
                            VStack(spacing: 0) {
                                let commands = visibleCommands(in: category)
                                ForEach(commands) { command in
                                    hotkeyRow(command)
                                    if command != commands.last { Divider() }
                                }
                            }
                        }
                    }

                    if visibleCategories.isEmpty {
                        ScholiumContentStateView(
                            "No Matching Hotkeys",
                            detail: Text("Try a command name or menu location."),
                            indicator: .symbol("keyboard")
                        )
                    }

                    Divider()

                    HStack {
                        Text("Hotkeys are stored on this Mac and update menu commands immediately.")
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Restore Default Hotkeys…") {
                            pendingResetAll = true
                        }
                        .disabled(!hasCustomizations)
                    }
                }
                .padding(ScholiumGrid.Spacing.regionContentInset)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollContentBackground(.hidden)
        }
        .scholiumSettingsPaneSurface()
        .accessibilityIdentifier("scholium.hotkeys")
        .sheet(item: $editingCommand) { command in
            HotkeyRecordingSheet(
                command: command,
                preferencesData: preferencesData
            ) { binding in
                preferencesData = ScholiumHotkeyPreferences.data(
                    setting: binding,
                    for: command,
                    in: preferencesData
                )
            }
        }
        .confirmationDialog(
            "Restore Default Hotkeys?",
            isPresented: $pendingResetAll,
            titleVisibility: .visible
        ) {
            Button("Restore Defaults", role: .destructive) {
                preferencesData = ScholiumHotkeyPreferences.defaultData
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores every customizable Scholium command on this Mac. Standard macOS shortcuts are not affected.")
        }
    }

    private var hasCustomizations: Bool {
        ScholiumHotkeyCommand.allCases.contains {
            ScholiumHotkeyPreferences.isCustomized($0, data: preferencesData)
        }
    }

    private var visibleCategories: [ScholiumHotkeyCategory] {
        ScholiumHotkeyCategory.allCases.filter { !visibleCommands(in: $0).isEmpty }
    }

    private func visibleCommands(
        in category: ScholiumHotkeyCategory
    ) -> [ScholiumHotkeyCommand] {
        ScholiumHotkeyCommand.allCases.filter {
            $0.category == category && matchesSearch($0)
        }
    }

    private func matchesSearch(_ command: ScholiumHotkeyCommand) -> Bool {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [
            String(localized: command.title),
            String(localized: command.menuPath),
            String(localized: command.category.title),
        ].contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func hotkeyRow(_ command: ScholiumHotkeyCommand) -> some View {
        HStack(
            alignment: .center,
            spacing: ScholiumGrid.Spacing.inlineControlGap
        ) {
            VStack(
                alignment: .leading,
                spacing: ScholiumGrid.Spacing.labelAccessoryGap
            ) {
                Text(command.title)
                    .font(ScholiumTypography.interface(.rowTitle))
                Text(command.menuPath)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
            }
            Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)

            Menu {
                Button("Record New Hotkey…") { editingCommand = command }
                Button("Clear Hotkey") {
                    preferencesData = ScholiumHotkeyPreferences.data(
                        setting: nil,
                        for: command,
                        in: preferencesData
                    )
                }
                .disabled(binding(for: command) == nil)
                Divider()
                Button("Restore Default") {
                    preferencesData = ScholiumHotkeyPreferences.data(
                        setting: command.defaultBinding,
                        for: command,
                        in: preferencesData
                    )
                }
                .disabled(!ScholiumHotkeyPreferences.isCustomized(
                    command,
                    data: preferencesData
                ))
            } label: {
                Text(binding(for: command)?.displayName ?? "None")
                    .monospacedDigit()
                    .frame(minWidth: 64)
            }
            .menuStyle(.button)
            .controlSize(.small)
            .accessibilityLabel(Text("Hotkey for \(String(localized: command.title))"))
            .accessibilityValue(Text(binding(for: command)?.displayName ?? "None"))
            .accessibilityIdentifier("scholium.hotkeys.command.\(command.rawValue)")
        }
        .padding(.vertical, ScholiumMetrics.Settings.rowVerticalInset)
        .accessibilityElement(children: .contain)
    }

    private func binding(
        for command: ScholiumHotkeyCommand
    ) -> ScholiumHotkeyBinding? {
        ScholiumHotkeyPreferences.binding(for: command, data: preferencesData)
    }
}

private struct HotkeyRecordingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ScholiumHotkeyBinding?
    @State private var isRecording = false

    let command: ScholiumHotkeyCommand
    let preferencesData: Data
    let save: (ScholiumHotkeyBinding?) -> Void

    init(
        command: ScholiumHotkeyCommand,
        preferencesData: Data,
        save: @escaping (ScholiumHotkeyBinding?) -> Void
    ) {
        self.command = command
        self.preferencesData = preferencesData
        self.save = save
        _draft = State(initialValue: ScholiumHotkeyPreferences.binding(
            for: command,
            data: preferencesData
        ))
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: ScholiumGrid.Spacing.sectionSeparation
        ) {
            settingsTitle(
                "Record Hotkey",
                detail: "Choose a shortcut for \(String(localized: command.title))."
            )

            VStack(
                alignment: .leading,
                spacing: ScholiumGrid.Spacing.inlineControlGap
            ) {
                HotkeyRecorderControl(
                    binding: $draft,
                    isRecording: $isRecording
                )
                .frame(maxWidth: .infinity, minHeight: 52)

                Text("Include ⌘. Press Delete to clear the shortcut or Escape to stop recording.")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let issue = validationIssue {
                    Label(issue.message, systemImage: "exclamationmark.triangle")
                        .font(ScholiumTypography.interface(.body))
                        .scholiumForeground(.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("scholium.hotkeys.validation")
                }
            }

            Divider()

            HStack {
                Button("Clear") { draft = nil }
                    .disabled(draft == nil)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    save(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(validationIssue != nil)
            }
        }
        .padding(ScholiumGrid.Spacing.regionContentInset)
        .frame(width: 440)
        .onDisappear { isRecording = false }
    }

    private var validationIssue: ScholiumHotkeyValidationIssue? {
        guard let draft else { return nil }
        return ScholiumHotkeyPreferences.validationIssue(
            for: draft,
            command: command,
            data: preferencesData
        )
    }
}

private struct HotkeyRecorderControl: NSViewRepresentable {
    @Binding var binding: ScholiumHotkeyBinding?
    @Binding var isRecording: Bool

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
        button.title = isRecording
            ? String(localized: "Press a Shortcut…")
            : binding?.displayName ?? String(localized: "Record Shortcut")
        button.isRecording = isRecording
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
        var parent: HotkeyRecorderControl
        weak var button: RecorderButton?

        init(parent: HotkeyRecorderControl) {
            self.parent = parent
        }

        @objc func beginRecording() {
            parent.isRecording = true
            button?.isRecording = true
            button?.title = String(localized: "Press a Shortcut…")
            button?.window?.makeFirstResponder(button)
        }
    }

    final class RecorderButton: NSButton {
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
            guard let characters = event.charactersIgnoringModifiers,
                  let character = characters.first,
                  let binding = ScholiumHotkeyBinding(
                    key: String(character),
                    modifiers: ScholiumHotkeyModifiers.from(event.modifierFlags)
                  ) else {
                NSSound.beep()
                return
            }
            capture?(binding)
        }
    }
}
