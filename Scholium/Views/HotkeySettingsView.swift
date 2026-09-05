import AppKit
import SwiftUI

struct HotkeySettingsView: View {
    @AppStorage(ScholiumHotkeyPreferences.defaultsKey)
    private var preferencesData = ScholiumHotkeyPreferences.defaultData
    @State private var editingCommand: ScholiumHotkeyCommand?
    @State private var pendingResetAll = false
    @State private var selectedCommandID: String?

    let searchQuery: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.sectionSeparation
                ) {
                    ForEach(visibleCategories) { category in
                        settingsEditorSection(category.title) {
                            Table(visibleCommands(in: category), selection: $selectedCommandID) {
                                TableColumn("Command") { command in
                                    Text(command.title)
                                        .help(Text(command.menuPath))
                                }
                                TableColumn("Hotkey") { command in
                                    hotkeyMenu(command)
                                }
                                .width(100)
                            }
                            .contextMenu(forSelectionType: String.self) { ids in
                                if let id = ids.first, let command = ScholiumHotkeyCommand(rawValue: id) {
                                    hotkeyActions(command)
                                }
                            } primaryAction: { ids in
                                if let id = ids.first { editingCommand = ScholiumHotkeyCommand(rawValue: id) }
                            }
                            .tableStyle(.inset)
                            .frame(height: CGFloat(visibleCommands(in: category).count) * 30 + 32)

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
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Restore Default Hotkeys…") {
                            pendingResetAll = true
                        }
                        .disabled(!hasCustomizations)
                    }
                }
                .padding(24)
                .frame(maxWidth: 760, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
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
            .buttonStyle(.automatic)
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

    private func hotkeyMenu(_ command: ScholiumHotkeyCommand) -> some View {
            Menu {
                hotkeyActions(command)
            } label: {
                Text(binding(for: command)?.displayName ?? "None")
                    .monospacedDigit()
                    .frame(minWidth: 64)
            }
            .scholiumMenuStyle(.button)
            .controlSize(.small)
            .accessibilityLabel(Text("Hotkey for \(String(localized: command.title))"))
            .accessibilityValue(Text(binding(for: command)?.displayName ?? "None"))
            .accessibilityIdentifier("scholium.hotkeys.command.\(command.rawValue)")
    }
    @ViewBuilder
    private func hotkeyActions(_ command: ScholiumHotkeyCommand) -> some View {
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
                    .foregroundStyle(.secondary)
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
                .buttonStyle(.bordered)
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
