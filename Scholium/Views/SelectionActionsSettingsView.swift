import SwiftUI

struct SelectionActionsSettingsView: View {
    @ObservedObject private var preferences = SelectionActionPreferences.shared
    @State private var draft: [SelectionActionDefinition] = []
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                ForEach($draft) { $action in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle("Enabled", isOn: $action.isEnabled).labelsHidden()
                                .accessibilityLabel(Text("Enable \(action.name)"))
                            TextField("Action name", text: $action.name)
                                .labelsHidden().multilineTextAlignment(.leading)
                                .accessibilityIdentifier("scholium.selectionActions.name")
                            Menu {
                                Button("Move Up") { move(action.id, by: -1) }
                                    .disabled(draft.first?.id == action.id)
                                Button("Move Down") { move(action.id, by: 1) }
                                    .disabled(draft.last?.id == action.id)
                                Button("Remove", role: .destructive) { draft.removeAll { $0.id == action.id } }
                            } label: { Image(systemName: "ellipsis") }
                            .menuStyle(.borderlessButton)
                            .accessibilityLabel(Text("Options for \(action.name)"))
                        }
                        TextField("Instruction", text: $action.prompt, axis: .vertical)
                            .lineLimit(3...6).multilineTextAlignment(.leading)
                            .labelsHidden()
                            .accessibilityIdentifier("scholium.selectionActions.prompt")
                    }
                }
                Button("Add Action", systemImage: "plus") {
                    draft.append(.init(name: "", prompt: ""))
                }.disabled(draft.count >= SelectionActionPreferences.maximumCount)
            } header: { Text("Selection Actions") }
            Section("Preview") {
                ViewThatFits(in: .horizontal) {
                    HStack { previewLabels }
                    VStack(alignment: .leading) { previewLabels }
                }
            }
            if let message = error ?? preferences.loadError ?? SelectionActionPreferences.validationError(draft) {
                Text(message).foregroundStyle(.secondary)
                    .accessibilityIdentifier("scholium.selectionActions.validation")
            }
            HStack {
                Button("Restore Defaults") {
                    preferences.restoreDefaults(); draft = preferences.actions; error = nil
                }
                Spacer()
                Button("Save") {
                    do { try preferences.save(draft); error = nil }
                    catch { self.error = error.localizedDescription }
                }
                .disabled(SelectionActionPreferences.validationError(draft) != nil || draft == preferences.actions)
            }
        }
        .formStyle(.grouped)
        .onAppear { draft = preferences.actions }
        .accessibilityIdentifier("scholium.selectionActions.settings")
    }

    @ViewBuilder private var previewLabels: some View {
        ForEach(draft.filter(\.isEnabled)) { action in
            Text(action.name)
        }
        if draft.allSatisfy({ !$0.isEnabled }) { Text("No enabled actions").foregroundStyle(.secondary) }
    }
    private func move(_ id: UUID, by delta: Int) {
        guard let index = draft.firstIndex(where: { $0.id == id }), draft.indices.contains(index + delta) else { return }
        draft.swapAt(index, index + delta)
    }
}
