import ScholiumContracts
import SwiftUI

/// A selection and unsent capture task; document reads stay with the window owner.
struct AgentChatNotePicker: View {
    struct Target: Identifiable { let id: UUID }
    let notes: [WorkspaceCatalogNote]
    let add: (WorkspaceCatalogNote) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedID: String?
    @State private var operation: Task<Void, Never>?
    @State private var error: String?

    private var visibleNotes: [WorkspaceCatalogNote] {
        let needle = AgentChatSearch.query(query)
        return notes.filter { note in
            note.reference.stableNoteID.flatMap(UUID.init(uuidString:)) != nil
                && (needle.isEmpty || AgentChatSearch.matches(note.title, query: needle)
                    || AgentChatSearch.matches(note.reference.relativePath, query: needle))
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Note").font(.headline).accessibilityAddTraits(.isHeader)
            ContextSearchField(text: $query, prompt: "Search Notes", identifier: "scholium.chat.notePicker.search")
                .disabled(operation != nil)
            List(selection: $selectedID) {
                ForEach(visibleNotes) { note in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(note.title).lineLimit(2)
                        Text(LocalizedStringKey(note.reference.vaultRole.displayName)).font(.caption).foregroundStyle(.secondary)
                        Text(note.reference.relativePath).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }.tag(note.id).help(note.reference.relativePath)
                }
            }
            .overlay {
                if visibleNotes.isEmpty {
                    Text(notes.isEmpty ? "No Notes Available" : "No Matching Notes").foregroundStyle(.secondary)
                }
            }
            .disabled(operation != nil)
            .accessibilityLabel("Notes")
            if let error { Text(error).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                if operation != nil { ProgressView().controlSize(.small).accessibilityLabel("Reading Note") }
                Spacer()
                Button("Cancel") {
                    operation?.cancel()
                    dismiss()
                }.keyboardShortcut(.cancelAction)
                Button("Add") {
                    guard let note = visibleNotes.first(where: { $0.id == selectedID }), operation == nil else { return }
                    error = nil
                    operation = Task { @MainActor in
                        defer { operation = nil }
                        do {
                            try await add(note)
                            try Task.checkCancellation()
                            dismiss()
                        } catch is CancellationError {} catch { self.error = error.localizedDescription }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(operation != nil || !visibleNotes.contains(where: { $0.id == selectedID }))
            }
        }
        .padding(20).frame(width: 440, height: 430)
        .onDisappear { operation?.cancel() }
        .tint(nil as Color?)
    }
}
