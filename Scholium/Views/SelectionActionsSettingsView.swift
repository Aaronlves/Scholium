import AppKit
import SwiftUI

struct SelectionActionsSettingsView: View {
    @ObservedObject private var preferences = SelectionActionPreferences.shared
    @State private var draft: [SelectionActionDefinition] = []
    @State private var editingAction: SelectionActionDefinition?
    @State private var isAddingAction = false
    @State private var selectedActionID: UUID?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                Text("Selection Actions")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Text("Choose which actions are available for selected text. Edit an action to change its label or instruction.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if draft.isEmpty {
                    Text("No selection actions configured.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
                } else {
                    Table(draft, selection: $selectedActionID) {
                        TableColumn("Enabled") { action in
                            Toggle(
                                "",
                                isOn: isEnabledBinding(for: action)
                            )
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .accessibilityLabel(
                                Text(
                                    verbatim: String(
                                        format: ScholiumL10n.string("Enable %@"),
                                        displayName(for: action)
                                    ))
                            )
                        }
                        .width(58)

                        TableColumn("Action") { action in
                            Text(verbatim: displayName(for: action))
                                .lineLimit(1)
                        }

                        TableColumn("Instruction") { action in
                            Group {
                                if action.prompt.isEmpty {
                                    Text("No instruction")
                                } else {
                                    Text(verbatim: action.prompt)
                                }
                            }
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .help(Text(verbatim: action.prompt))
                        }

                        TableColumn("Actions") { action in
                            HStack(spacing: 8) {
                                Button("Edit…") { beginEditing(action) }
                                    .buttonStyle(.borderless)
                                    .accessibilityIdentifier("scholium.selectionActions.edit")

                                Menu {
                                    Button("Move Up") { move(action.id, by: -1) }
                                        .disabled(draft.first?.id == action.id)
                                    Button("Move Down") { move(action.id, by: 1) }
                                        .disabled(draft.last?.id == action.id)
                                    Button("Remove", role: .destructive) {
                                        remove(action.id)
                                    }
                                } label: {
                                    Label("More", systemImage: "ellipsis.circle")
                                        .labelStyle(.iconOnly)
                                }
                                .menuStyle(.borderlessButton)
                                .accessibilityLabel(Text("More"))
                            }
                        }
                        .width(min: 118, ideal: 126)
                    }
                    .tableStyle(.inset)
                    .frame(height: tableHeight)
                    .accessibilityIdentifier("scholium.selectionActions.table")
                }

                HStack {
                    Button("Add Action", systemImage: "plus") {
                        beginAdding()
                    }
                    .disabled(draft.count >= SelectionActionPreferences.maximumCount)

                    Spacer()

                    Button("Restore Defaults") {
                        draft = SelectionActionPreferences.defaultActions
                        selectedActionID = nil
                        error = nil
                    }
                    .disabled(draft == SelectionActionPreferences.defaultActions)
                }

                if let message = error ?? preferences.loadError
                    ?? SelectionActionPreferences.validationError(draft)
                {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("scholium.selectionActions.validation")
                }

                settingsEditorSection("Preview") {
                    VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                        SelectionActionBarPreview(actions: draft)
                            .id(previewIdentity)
                            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                        Text("Shown when text is selected. Custom actions appear in More Actions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack {
                    Spacer()
                    Button("Save") {
                        saveDraft()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        SelectionActionPreferences.validationError(draft) != nil
                            || draft == preferences.actions
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: 760, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scholiumSettingsPaneSurface()
        .onAppear { draft = preferences.actions }
        .onChange(of: preferences.actions) { _, actions in
            if editingAction == nil {
                draft = actions
            }
        }
        .sheet(item: $editingAction) { action in
            SelectionActionEditorSheet(
                initialAction: action,
                isNew: isAddingAction,
                onSave: { updated in
                    updateDraft(with: updated)
                    editingAction = nil
                    isAddingAction = false
                },
                onDelete: isAddingAction
                    ? nil
                    : {
                        remove(action.id)
                        editingAction = nil
                        isAddingAction = false
                    }
            )
        }
        .accessibilityIdentifier("scholium.selectionActions.settings")
    }

    private var tableHeight: CGFloat {
        CGFloat(max(draft.count, 1)) * 32 + 30
    }

    private var previewIdentity: String {
        draft
            .filter(\.isEnabled)
            .map { "\($0.id.uuidString):\($0.name)" }
            .joined(separator: "|")
    }

    private func displayName(for action: SelectionActionDefinition) -> String {
        let name = action.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Unnamed Action" : name
    }

    private func isEnabledBinding(for action: SelectionActionDefinition) -> Binding<Bool> {
        Binding(
            get: { draft.first(where: { $0.id == action.id })?.isEnabled ?? false },
            set: { value in
                guard let index = draft.firstIndex(where: { $0.id == action.id }) else { return }
                draft[index].isEnabled = value
            }
        )
    }

    private func beginAdding() {
        guard draft.count < SelectionActionPreferences.maximumCount else { return }
        isAddingAction = true
        selectedActionID = nil
        error = nil
        editingAction = SelectionActionDefinition(name: "", prompt: "")
    }

    private func beginEditing(_ action: SelectionActionDefinition) {
        isAddingAction = false
        error = nil
        editingAction = action
    }

    private func updateDraft(with action: SelectionActionDefinition) {
        if let index = draft.firstIndex(where: { $0.id == action.id }) {
            draft[index] = action
        } else {
            draft.append(action)
        }
    }

    private func remove(_ id: UUID) {
        draft.removeAll { $0.id == id }
        if selectedActionID == id {
            selectedActionID = nil
        }
    }

    private func move(_ id: UUID, by delta: Int) {
        guard let index = draft.firstIndex(where: { $0.id == id }),
            draft.indices.contains(index + delta)
        else { return }
        draft.swapAt(index, index + delta)
    }

    private func saveDraft() {
        do {
            try preferences.save(draft)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

@MainActor
private struct SelectionActionBarPreview: NSViewRepresentable {
    let actions: [SelectionActionDefinition]

    func makeNSView(context: Context) -> SelectionActionBar {
        let bar = SelectionActionBar(actions: actions)
        bar.onInquiry = { _ in }
        bar.setAccessibilityIdentifier("scholium.selectionActions.preview")
        return bar
    }

    func updateNSView(_ nsView: SelectionActionBar, context: Context) {}
}

private struct SelectionActionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SelectionActionDefinition

    let isNew: Bool
    let onSave: (SelectionActionDefinition) -> Void
    let onDelete: (() -> Void)?

    init(
        initialAction: SelectionActionDefinition,
        isNew: Bool,
        onSave: @escaping (SelectionActionDefinition) -> Void,
        onDelete: (() -> Void)?
    ) {
        _draft = State(initialValue: initialAction)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
            VStack(alignment: .leading, spacing: ScholiumMetrics.SettingsPresentation.titleDetailSpacing) {
                Text(isNew ? "Add Selection Action" : "Edit Selection Action")
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)
                Text("Define the label and instruction used for a selected passage.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Form {
                Section {
                    LabeledContent("Name") {
                        TextField("", text: $draft.name)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("scholium.selectionActions.name")
                    }

                    LabeledContent("Instruction") {
                        TextEditor(text: $draft.prompt)
                            .font(.body)
                            .frame(minHeight: 140)
                            .accessibilityIdentifier("scholium.selectionActions.prompt")
                    }
                }

                Section {
                    Text("The name appears in More Actions. The instruction is sent with the selected passage and does not edit Notes.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.columns)

            if let issue = SelectionActionPreferences.validationError([draft]) {
                Label(issue, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("scholium.selectionActions.editor.validation")
            }

            HStack {
                if let onDelete {
                    Button("Remove", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(SelectionActionPreferences.validationError([draft]) != nil)
            }
        }
        .padding(24)
        .frame(width: 640, height: 440)
    }
}
