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
        if actions == baseline {
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

    func save() {
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
    @ObservedObject var state: SelectionActionsSettingsDraft
    @ObservedObject private var preferences: SelectionActionPreferences
    @FocusState private var nameFocused: Bool
    @FocusState private var editButtonID: UUID?

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
                Table(state.actions, selection: $state.selectedActionID) {
                    TableColumn("Enabled") { action in
                        Toggle("", isOn: actionBinding(action.id, keyPath: \.isEnabled, fallback: false))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .accessibilityLabel(Text(verbatim: String(format: ScholiumL10n.string("Enable %@"), displayName(action))))
                    }.width(58)
                    TableColumn("Action") { action in
                        Text(verbatim: displayName(action)).lineLimit(1)
                    }
                    TableColumn("Instruction") { action in
                        Group {
                            if action.prompt.isEmpty { Text("No instruction") } else { Text(verbatim: action.prompt) }
                        }
                        .foregroundStyle(.secondary).lineLimit(1)
                        .help(Text(verbatim: action.prompt))
                    }
                    TableColumn("Actions") { action in
                        HStack {
                            Button("Edit") {
                                state.beginEditing(action)
                                nameFocused = true
                            }
                            .buttonStyle(.borderless)
                            .focused($editButtonID, equals: action.id)
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
                            .accessibilityLabel(Text("More"))
                        }
                    }.width(min: 118, ideal: 126)
                }
                .tableStyle(.inset)
                .frame(height: CGFloat(max(state.actions.count, 1)) * 32 + 30)
                .accessibilityIdentifier("scholium.selectionActions.table")
            }

            HStack {
                Button("Add Action", systemImage: "plus") {
                    let action = SelectionActionDefinition(name: "", prompt: "")
                    state.actions.append(action)
                    state.beginEditing(action, isNew: true)
                    nameFocused = true
                }
                .disabled(state.actions.count >= SelectionActionPreferences.maximumCount || state.editingActionID != nil)
                Spacer()
                Button("Restore Defaults") {
                    state.actions = SelectionActionPreferences.defaultActions
                    state.editingActionID = nil
                    state.selectedActionID = nil
                    state.error = nil
                }
            }

            if let id = state.editingActionID, state.actions.contains(where: { $0.id == id }) {
                LabeledContent("Name") {
                    TextField("", text: actionBinding(id, keyPath: \.name, fallback: ""))
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                        .accessibilityIdentifier("scholium.selectionActions.name")
                }
                VStack(alignment: .leading) {
                    Text("Instruction")
                    TextEditor(text: actionBinding(id, keyPath: \.prompt, fallback: ""))
                        .font(.body)
                        .frame(minHeight: 140)
                        .accessibilityLabel(Text("Instruction"))
                        .accessibilityIdentifier("scholium.selectionActions.prompt")
                    Text("The name appears in More Actions. The instruction is sent with the selected passage and does not edit Notes.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Cancel Action Changes") {
                        state.cancelEditing()
                        nameFocused = false
                        editButtonID = state.actions.contains(where: { $0.id == id }) ? id : nil
                    }
                }
            }

            if state.hasExternalChange {
                Text("Selection actions changed elsewhere. Your draft has been retained. Reload saved actions before editing again.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("scholium.selectionActions.conflict")
                Button("Reload Saved Actions") { state.reload(preferences.actions) }
            }
            if let message = state.error ?? preferences.loadError ?? SelectionActionPreferences.validationError(state.actions) {
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("scholium.selectionActions.validation")
            }
            HStack {
                Spacer()
                Button("Save Selection Actions") {
                    let id = state.editingActionID
                    state.save()
                    if state.error == nil && !state.hasExternalChange {
                        nameFocused = false
                        editButtonID = id
                    }
                }
                .scholiumSettingsDefaultAction()
                .disabled(state.hasExternalChange || SelectionActionPreferences.validationError(state.actions) != nil || state.actions == preferences.actions)
                .accessibilityIdentifier("scholium.selectionActions.save")
            }
        } header: {
            Text("Selection Actions")
        } footer: {
            Text("This Mac", bundle: .module)
        }
        .id("writing.selection")
        .onAppear { state.synchronize(with: preferences.actions) }
        .onChange(of: preferences.actions) { _, actions in state.synchronize(with: actions) }

        Section("Preview") {
            SelectionActionBarPreview(actions: state.actions)
                .id(previewIdentity)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            Text("Shown when text is selected. Custom actions appear in More Actions.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var previewIdentity: String {
        state.actions.filter(\.isEnabled).map { "\($0.id.uuidString):\($0.name)" }.joined(separator: "|")
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
        bar.onInquiry = { _ in }
        bar.setAccessibilityIdentifier("scholium.selectionActions.preview")
        return bar
    }

    func updateNSView(_ nsView: SelectionActionBar, context: Context) {}
}
