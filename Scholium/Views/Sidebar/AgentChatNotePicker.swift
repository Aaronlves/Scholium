import ScholiumContracts
import SwiftUI

/// A selection and unsent capture task; document reads stay with the window owner.
struct AgentChatNotePicker: View {
    struct Target: Identifiable { let id: UUID }
    let notes: [WorkspaceCatalogNote]
    var noteCatalogCache = AgentChatNoteCatalogCache()
    let prepare: @MainActor (WorkspaceCatalogNote) throws -> (@MainActor () async throws -> Void)
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedID: String?
    @State private var operation: Task<Void, Never>?
    @State private var error: String?

    private var visibleNotes: [WorkspaceCatalogNote] {
        noteCatalogCache.catalog(notes: notes).matchingNotes(query: query)
    }

    var body: some View {
        let visible = visibleNotes
        return VStack(alignment: .leading, spacing: 12) {
            Text("Choose Note").font(.headline).accessibilityAddTraits(.isHeader)
            ContextSearchField(text: $query, prompt: "Search Notes", identifier: "scholium.chat.notePicker.search")
                .disabled(operation != nil)
            List(selection: $selectedID) {
                ForEach(visible) { note in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(note.title).lineLimit(2)
                        Text(LocalizedStringKey(note.reference.vaultRole.displayName)).font(.caption).foregroundStyle(.secondary)
                        Text(note.reference.relativePath).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }.tag(note.id).help(note.reference.relativePath)
                }
            }
            .overlay {
                if visible.isEmpty {
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
                    guard let note = visible.first(where: { $0.id == selectedID }), operation == nil else { return }
                    error = nil
                    let work: @MainActor () async throws -> Void
                    do { work = try prepare(note) } catch {
                        self.error = error.localizedDescription
                        return
                    }
                    operation = Task { @MainActor in
                        defer { operation = nil }
                        do {
                            try await work()
                            try Task.checkCancellation()
                            dismiss()
                        } catch is CancellationError {} catch { self.error = error.localizedDescription }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(operation != nil || !visible.contains(where: { $0.id == selectedID }))
            }
        }
        .padding(20).frame(width: 440, height: 430)
        // Admitted work outlives presentation hiding. Explicit Cancel above
        // retains cancellation authority through the controller's preparation.
        .tint(nil as Color?)
    }
}
