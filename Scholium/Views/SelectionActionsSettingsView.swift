import AppKit
import Combine
import SwiftUI

/// Session-owned draft; opening another settings category never commits or replaces it.
@MainActor
final class SelectionActionsSettingsDraft: ObservableObject {
    @Published var actions: [SelectionActionDefinition]
    @Published var selectedActionID: UUID?
    @Published var editingActionID: UUID?
    @Published var error: String?
    @Published private(set) var hasExternalChange = false
    let preferences: SelectionActionPreferences
    private var baseline: [SelectionActionDefinition]
    private var editingOriginal: SelectionActionDefinition?

    init(preferences: SelectionActionPreferences = .shared) {
        self.preferences = preferences
        let saved = preferences.actions
        actions = saved
        baseline = saved
    }

    func synchronize(with saved: [SelectionActionDefinition]) {
        guard saved != baseline else { return }
        if actions == baseline && editingActionID == nil {
            reload(saved)
        } else {
            hasExternalChange = true
        }
    }

    func reload(_ saved: [SelectionActionDefinition]) {
        actions = saved
        baseline = saved
        editingActionID = nil
        selectedActionID = nil
        editingOriginal = nil
        error = nil
        hasExternalChange = false
    }

    func beginEditing(_ action: SelectionActionDefinition, isNew: Bool = false) {
        guard editingActionID == nil, !hasExternalChange else { return }
        editingActionID = action.id
        selectedActionID = action.id
        editingOriginal = isNew ? nil : action
        error = nil
    }

    func cancelEditing() {
        guard let id = editingActionID else { return }
        if let editingOriginal, let index = actions.firstIndex(where: { $0.id == id }) {
            actions[index] = editingOriginal
        } else {
            actions.removeAll { $0.id == id }
        }
        editingActionID = nil
        self.editingOriginal = nil
        error = nil
    }

    func finishEditing() {
        editingActionID = nil
        editingOriginal = nil
        error = nil
    }

    func save() {
        guard editingActionID == nil else { return }
        guard preferences.actions == baseline else {
            hasExternalChange = true
            return
        }
        do {
            try preferences.save(actions)
            baseline = preferences.actions
            editingActionID = nil
            editingOriginal = nil
            error = nil
            hasExternalChange = false
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct SelectionActionsSettingsContent: View {
    @Environment(\.scholiumSettingsPaneIsActive) private var isPaneActive
    @ObservedObject var state: SelectionActionsSettingsDraft
    @ObservedObject private var preferences: SelectionActionPreferences
    private enum FocusTarget: Hashable {
        case name
        case edit(UUID)
        case add, reload
    }
    @FocusState private var focusedTarget: FocusTarget?

    init(state: SelectionActionsSettingsDraft) {
        self.state = state
        self.preferences = state.preferences
    }

    var body: some View {
        Section {
            Text("Choose which actions are available for selected text. Edit an action to change its label or instruction.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if state.actions.isEmpty {
                Text("No selection actions configured.").foregroundStyle(.secondary)
            } else {
                ForEach(state.actions) { action in
                    HStack(alignment: .top, spacing: 12) {
                        Toggle("", isOn: actionBinding(action.id, keyPath: \.isEnabled, fallback: false))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .accessibilityLabel(Text(verbatim: String(format: ScholiumL10n.string("Enable %@"), displayName(action))))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: displayName(action))
                            if action.prompt.isEmpty {
                                Text("No instruction")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(verbatim: action.prompt)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                                    .help(Text(verbatim: action.prompt))
                                    .accessibilityLabel(Text(verbatim: action.prompt))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Edit") {
                            state.beginEditing(action)
                            focusedTarget = .name
                        }
                        .buttonStyle(.borderless)
                        .focused($focusedTarget, equals: .edit(action.id))
                        .disabled(state.editingActionID != nil)
                        .accessibilityLabel(Text(verbatim: String(format: ScholiumL10n.string("Edit %@"), displayName(action))))
                        .accessibilityIdentifier("scholium.selectionActions.edit")

                        Menu {
                            Button("Move Up") { move(action.id, by: -1) }
                                .disabled(state.actions.first?.id == action.id)
                            Button("Move Down") { move(action.id, by: 1) }
                                .disabled(state.actions.last?.id == action.id)
                            Button("Remove", role: .destructive) { remove(action.id) }
                        } label: {
                            Label("More", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
                        }
                        .menuStyle(.borderlessButton)
                        .disabled(state.editingActionID != nil)
                        .accessibilityLabel(Text(verbatim: "\(ScholiumL10n.string("More")) \(displayName(action))"))
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("scholium.selectionActions.row.\(action.id.uuidString)")
                    .disabled(state.hasExternalChange)

                    if state.editingActionID == action.id {
                        actionEditor(for: action)
                            .id("selection.action.editor.\(action.id.uuidString)")
                    }
                }
            }

            HStack {
                Button("Add Action", systemImage: "plus") {
                    let action = SelectionActionDefinition(name: "", prompt: "")
                    state.actions.append(action)
                    state.beginEditing(action, isNew: true)
                    focusedTarget = .name
                }
                .focused($focusedTarget, equals: .add)
                .disabled(state.actions.count >= SelectionActionPreferences.maximumCount || state.editingActionID != nil || state.hasExternalChange)
                Spacer()
                Button("Restore Defaults") {
                    state.actions = SelectionActionPreferences.defaultActions
                    state.editingActionID = nil
                    state.selectedActionID = nil
                    state.error = nil
                }
                .disabled(state.editingActionID != nil || state.hasExternalChange)
            }

            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Text("Preview")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                SelectionActionBarPreview(actions: state.actions)
                    .id(previewIdentity)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                Text("Shown when text is selected. Custom actions appear in More Actions.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if state.hasExternalChange {
                Text("Selection actions changed elsewhere. Your draft has been retained. Reload saved actions before editing again.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("scholium.selectionActions.conflict")
                Button("Reload Saved Actions") {
                    state.reload(preferences.actions)
                    focusedTarget = state.actions.first.map { .edit($0.id) } ?? .add
                }
                .focused($focusedTarget, equals: .reload)
            }
            if let message = state.error ?? preferences.loadError
                ?? (state.editingActionID == nil ? SelectionActionPreferences.validationError(state.actions) : nil)
            {
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("scholium.selectionActions.validation")
            }
            HStack {
                Spacer()
                Button("Save Selection Actions") {
                    state.save()
                    if state.error == nil && !state.hasExternalChange {
                        focusedTarget = state.selectedActionID.map(FocusTarget.edit)
                    }
                }
                .scholiumSettingsDefaultAction()
                .disabled(
                    state.editingActionID != nil || state.hasExternalChange || SelectionActionPreferences.validationError(state.actions) != nil
                        || state.actions == preferences.actions
                )
                .accessibilityIdentifier("scholium.selectionActions.save")
            }
        } header: {
            Text("Selection Actions")
        } footer: {
            Text("This Mac", bundle: .module)
        }
        .id(SettingsSection.writingSelection)
        .onAppear { state.synchronize(with: preferences.actions) }
        .onChange(of: preferences.actions) { _, actions in state.synchronize(with: actions) }
    }

    private var previewIdentity: String {
        state.actions.filter(\.isEnabled).map { "\($0.id.uuidString):\($0.name)" }.joined(separator: "|")
    }

    private func actionEditor(for action: SelectionActionDefinition) -> some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text("Edit Selection Action")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Group {
                LabeledContent("Name") {
                    TextField("", text: actionBinding(action.id, keyPath: \.name, fallback: ""))
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedTarget, equals: .name)
                        .accessibilityLabel(Text("Name"))
                        .accessibilityIdentifier("scholium.selectionActions.name")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Instruction")
                    TextEditor(text: actionBinding(action.id, keyPath: \.prompt, fallback: ""))
                        .font(.body)
                        .frame(minHeight: 140)
                        .accessibilityLabel(Text("Instruction"))
                        .accessibilityIdentifier("scholium.selectionActions.prompt")
                    Text("The name appears in More Actions. The instruction is sent with the selected passage and does not edit Notes.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let validation = SelectionActionPreferences.validationError([action]) {
                    Text(validation)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("scholium.selectionActions.validation")
                }
            }
            .disabled(state.hasExternalChange)

            Text("Save Selection Actions on the page to keep these changes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") {
                    state.cancelEditing()
                    if state.hasExternalChange {
                        focusedTarget = .reload
                    } else {
                        focusedTarget = state.actions.contains { $0.id == action.id } ? .edit(action.id) : .add
                    }
                }
                .keyboardShortcut(isPaneActive ? .cancelAction : nil)
                Button("Done") {
                    state.finishEditing()
                    focusedTarget = .edit(action.id)
                }
                .disabled(state.hasExternalChange || SelectionActionPreferences.validationError([action]) != nil)
                .accessibilityIdentifier("scholium.selectionActions.done")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.selectionActions.editor")
    }

    private func displayName(_ action: SelectionActionDefinition) -> String {
        let name = action.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? ScholiumL10n.string("Unnamed Action") : name
    }

    private func actionBinding<Value>(_ id: UUID, keyPath: WritableKeyPath<SelectionActionDefinition, Value>, fallback: Value) -> Binding<Value> {
        Binding(
            get: { state.actions.first(where: { $0.id == id })?[keyPath: keyPath] ?? fallback },
            set: { value in
                guard let index = state.actions.firstIndex(where: { $0.id == id }) else { return }
                state.actions[index][keyPath: keyPath] = value
            }
        )
    }

    private func remove(_ id: UUID) {
        state.actions.removeAll { $0.id == id }
        if state.selectedActionID == id { state.selectedActionID = nil }
        if state.editingActionID == id { state.editingActionID = nil }
    }

    private func move(_ id: UUID, by delta: Int) {
        guard let index = state.actions.firstIndex(where: { $0.id == id }), state.actions.indices.contains(index + delta) else { return }
        state.actions.swapAt(index, index + delta)
    }
}

@MainActor
private struct SelectionActionBarPreview: NSViewRepresentable {
    let actions: [SelectionActionDefinition]

    func makeNSView(context: Context) -> SelectionActionBar {
        let bar = SelectionActionBar(actions: actions)
        bar.setAccessibilityIdentifier("scholium.selectionActions.preview")
        return bar
    }

    func updateNSView(_ nsView: SelectionActionBar, context: Context) {}
}
