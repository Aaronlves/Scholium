import ScholiumContracts
import SwiftUI

struct SearchTermGroupManager: View {
    @ObservedObject var controller: WindowSearchController
    @Environment(\.dismiss) private var dismiss
    @State private var selection: SearchTermGroup?
    @State private var name = ""
    @State private var terms = ""
    @State private var failure: String?
    @State private var isSaving = false
    @State private var isDirty = false

    private var draft: SearchTermGroup {
        SearchTermGroup(id: selection?.id ?? UUID(), name: name, terms: terms.components(separatedBy: .newlines))
    }
    var body: some View {
        VStack(alignment: .leading) {
            Text("Term Groups").font(.headline)
            Text("Insert alternatives as visible query text. Groups do not declare terms synonymous.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .top) {
                List(
                    selection: Binding(
                        get: { selection?.id },
                        set: { id in
                            guard let group = controller.termGroups.first(where: { $0.id == id }) else { return }
                            selection = group
                            name = group.name
                            terms = group.terms.joined(separator: "\n")
                            isDirty = false
                            failure = nil
                        })
                ) {
                    ForEach(controller.termGroups) { group in Text(group.name).tag(group.id) }
                }
                .frame(minWidth: 150)
                .disabled(isSaving || isDirty)
                Form {
                    TextField("Group Name", text: $name).disabled(isSaving)
                    VStack(alignment: .leading) {
                        Text("Terms, one per line")
                        TextEditor(text: $terms).frame(minHeight: 160).disabled(isSaving)
                            .accessibilityLabel("Terms, one per line")
                    }
                    Text("1–24 terms; each is inserted as literal text.").font(.caption).foregroundStyle(.secondary)
                }
                .formStyle(.grouped)
            }
            if let issue = failure ?? controller.termGroupError {
                Text(ScholiumL10n.dynamicString(issue)).scholiumForeground(.destructive).textSelection(.enabled)
                Button("Discard Draft and Reload") {
                    Task {
                        await controller.loadTermGroups()
                        selection = nil
                        name = ""
                        terms = ""
                        isDirty = false
                        failure = nil
                    }
                }.disabled(isSaving)
            }
            HStack {
                Button("New Group") {
                    selection = nil
                    name = ""
                    terms = ""
                    isDirty = false
                    failure = nil
                }
                .disabled(isSaving || isDirty)
                Button("Delete Group", role: .destructive) {
                    guard let selection else { return }
                    perform {
                        try await controller.deleteTermGroup(selection)
                        self.selection = nil
                        name = ""
                        terms = ""
                        isDirty = false
                    }
                }.disabled(selection == nil || isSaving || isDirty)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(isSaving)
                Button("Save") {
                    let group = draft
                    perform {
                        try group.validate()
                        try await controller.saveTermGroup(group, replacing: selection)
                        selection = group
                        isDirty = false
                        dismiss()
                    }
                }.keyboardShortcut(.defaultAction).disabled(isSaving || (try? draft.validate()) == nil)
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 380)
        .onChange(of: name) { _, _ in updateDirty() }
        .onChange(of: terms) { _, _ in updateDirty() }
        .task { await controller.loadTermGroups() }
        .interactiveDismissDisabled(isSaving)
    }
    private func updateDirty() {
        isDirty = selection.map { $0.name != name || $0.terms.joined(separator: "\n") != terms } ?? (!name.isEmpty || !terms.isEmpty)
    }
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        isSaving = true
        failure = nil
        Task { @MainActor in
            defer { isSaving = false }
            do { try await operation() } catch { failure = error.localizedDescription }
        }
    }
}
