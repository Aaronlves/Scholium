import SwiftUI

struct HotkeySettingsView: View {
    @AppStorage(ScholiumHotkeyPreferences.defaultsKey)
    private var preferencesData = ScholiumHotkeyPreferences.defaultData
    @State private var editingCommand: ScholiumHotkeyCommand?
    @State private var pendingResetAll = false
    @FocusState private var shortcutCommand: ScholiumHotkeyCommand?

    let searchQuery: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                ForEach(visibleCategories) { category in
                    Section {
                        ForEach(visibleCommands(in: category)) { command in
                            LabeledContent {
                                hotkeyMenu(command)
                            } label: {
                                Text(command.title).help(Text(command.menuPath))
                            }
                            .contextMenu { hotkeyActions(command) }
                            .id(command.rawValue)
                            if editingCommand == command {
                                HotkeyRecordingEditor(
                                    command: command,
                                    preferencesData: $preferencesData,
                                    finish: {
                                        editingCommand = nil
                                        shortcutCommand = command
                                    }
                                )
                                .id(command.rawValue + ".recorder")
                            }
                        }
                    } header: {
                        Text(category.title)
                    }
                }
                if visibleCategories.isEmpty {
                    ScholiumContentStateView(
                        "No Matching Shortcuts",
                        detail: Text("Try a command name or menu location."),
                        indicator: .symbol("keyboard")
                    )
                }
            }
            .scholiumSettingsFormStyle()
            .scholiumSettingsSearchDestination()

            Divider()
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Text("Keyboard shortcuts are stored on this Mac and update menu commands immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if ScholiumHotkeyPreferences.needsRecovery(preferencesData) {
                    Label(
                        "Some shortcuts could not be loaded. Available shortcuts remain usable; restore defaults to repair the saved settings.",
                        systemImage: "exclamationmark.triangle")
                }
                HStack {
                    Spacer()
                    Button("Restore Default Shortcuts…") {
                        pendingResetAll = true
                    }
                    .disabled(!hasCustomizations && !ScholiumHotkeyPreferences.needsRecovery(preferencesData))
                }
            }
            .padding(.horizontal, ScholiumMetrics.Settings.pathHorizontalInset)
            .padding(.vertical, ScholiumGrid.Spacing.sectionSeparation)
        }
        .scholiumSettingsPaneSurface()
        .accessibilityIdentifier("scholium.hotkeys")
        .confirmationDialog(
            "Restore Default Shortcuts?",
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
        ScholiumHotkeyCommand.customizableCommands.contains {
            ScholiumHotkeyPreferences.isCustomized($0, data: preferencesData)
        }
    }

    private var visibleCategories: [ScholiumHotkeyCategory] {
        ScholiumHotkeyCategory.allCases.filter { !visibleCommands(in: $0).isEmpty }
    }

    private func visibleCommands(
        in category: ScholiumHotkeyCategory
    ) -> [ScholiumHotkeyCommand] {
        ScholiumHotkeyCommand.customizableCommands.filter {
            $0.category == category && (matchesSearch($0) || editingCommand == $0)
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
        .menuStyle(.button)
        .focused($shortcutCommand, equals: command)
        .controlSize(.small)
        .accessibilityLabel(Text("Shortcut for \(String(localized: command.title))"))
        .accessibilityValue(Text(binding(for: command)?.displayName ?? "None"))
        .accessibilityIdentifier("scholium.hotkeys.command.\(command.rawValue)")
    }
    @ViewBuilder
    private func hotkeyActions(_ command: ScholiumHotkeyCommand) -> some View {
        Button("Record New Shortcut…") { editingCommand = command }
        Button("Clear Shortcut") {
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
        .disabled(
            !ScholiumHotkeyPreferences.isCustomized(
                command,
                data: preferencesData
            )
                || command.defaultBinding.map {
                    ScholiumHotkeyPreferences.validationIssue(
                        for: $0, command: command, data: preferencesData
                    ) != nil
                } == true)
    }

    private func binding(
        for command: ScholiumHotkeyCommand
    ) -> ScholiumHotkeyBinding? {
        ScholiumHotkeyPreferences.binding(for: command, data: preferencesData)
    }
}

private struct HotkeyRecordingEditor: View {
    @Environment(\.scholiumSettingsPaneIsActive) private var paneIsActive
    @State private var draft: ScholiumHotkeyBinding?
    @State private var isRecording = false
    @Binding private var preferencesData: Data

    let command: ScholiumHotkeyCommand
    let finish: () -> Void

    init(
        command: ScholiumHotkeyCommand,
        preferencesData: Binding<Data>,
        finish: @escaping () -> Void
    ) {
        self.command = command
        _preferencesData = preferencesData
        self.finish = finish
        _draft = State(initialValue: ScholiumHotkeyPreferences.binding(for: command, data: preferencesData.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            ScholiumHotkeyRecorder(binding: $draft, isRecording: $isRecording, isActive: paneIsActive)
                .frame(maxWidth: .infinity, minHeight: 52)
                .accessibilityIdentifier("scholium.hotkeys.recorder")
            Text("Include ⌘. Press Delete to clear the shortcut or Escape to stop recording.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let issue = validationIssue {
                Label(issue.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("scholium.hotkeys.validation")
            }
            HStack {
                Button("Clear") {
                    draft = nil
                    isRecording = false
                }
                .disabled(draft == nil)
                Spacer()
                Button("Cancel", role: .cancel) {
                    isRecording = false
                    finish()
                }
                Button("Save Shortcut") {
                    guard validationIssue == nil else { return }
                    isRecording = false
                    preferencesData = ScholiumHotkeyPreferences.data(setting: draft, for: command, in: preferencesData)
                    finish()
                }
                .buttonStyle(.bordered)
                .disabled(validationIssue != nil)
                .accessibilityIdentifier("scholium.hotkeys.save")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Shortcut for \(String(localized: command.title))"))
        .onChange(of: paneIsActive) { _, active in
            if !active { isRecording = false }
        }
        .onDisappear { isRecording = false }
    }

    private var validationIssue: ScholiumHotkeyValidationIssue? {
        guard let draft else { return nil }
        return ScholiumHotkeyPreferences.validationIssue(for: draft, command: command, data: preferencesData)
    }
}
