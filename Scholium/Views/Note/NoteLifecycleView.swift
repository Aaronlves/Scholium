import SwiftUI
import ScholiumCore

struct NoteLifecycleView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let request: AppState.NoteLifecycleRequest

    @State private var title = ""
    @State private var destination = ""
    @State private var classificationSlot: WorkspaceVaultSlot = .paperAnalysis
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Label(sheetTitle, systemImage: symbol)
                    .font(.title2.weight(.semibold))
                Spacer()
            }

            if request == .create {
                LabeledContent("Title") {
                    TextField("Untitled note", text: $title)
                        .frame(minWidth: 300)
                }
            }

            if case .classify = request {
                LabeledContent("Destination") {
                    Picker("Destination", selection: $classificationSlot) {
                        ForEach(WorkspaceVaultSlot.allCases) { slot in
                            Text(slot.displayName).tag(slot)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }

            LabeledContent("Location") {
                TextField("Folder/Note.md", text: $destination)
                    .font(.body.monospaced())
                    .frame(minWidth: 300)
            }

            Text(helpText)
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(actionTitle) { perform() }
                    .buttonStyle(.borderedProminent)
                    .disabled(destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(minWidth: 540)
        .onAppear { configureDefaults() }
        .alert("Could Not \(actionTitle)", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Dismiss", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var sheetTitle: String {
        switch request {
        case .create: "New Note"
        case .duplicate: "Duplicate Note"
        case .move: "Move or Rename Note"
        case .restore: "Restore Note"
        case .classify: "Classify Imported Note"
        }
    }

    private var actionTitle: String {
        switch request {
        case .create: "Create"
        case .duplicate: "Duplicate"
        case .move: "Move"
        case .restore: "Restore"
        case .classify: "Classify"
        }
    }

    private var symbol: String {
        switch request {
        case .create: "doc.badge.plus"
        case .duplicate: "plus.square.on.square"
        case .move: "folder"
        case .restore: "arrow.uturn.backward"
        case .classify: "tray.and.arrow.down"
        }
    }

    private var helpText: String {
        switch request {
        case .create:
            "Scholium creates a Markdown file at this vault-relative location. Existing files are never replaced."
        case .duplicate:
            "The duplicate preserves the exact source bytes and receives a new stable note identity."
        case .move:
            "Moving or renaming preserves the note identity, Human Review, comments, and Note History."
        case .restore:
            "Restore moves this note back into the active Workspace. Choose its vault-relative destination."
        case .classify:
            "Classification moves the imported copy from Unclassified into the selected Triptych vault. The original external file remains unchanged."
        }
    }

    private func configureDefaults() {
        switch request {
        case .create:
            destination = "Untitled.md"
        case .duplicate(let path):
            let base = (path as NSString).deletingPathExtension
            destination = base + " Copy.md"
        case .move(let path):
            destination = path
        case .restore(let path):
            destination = path
                .replacingOccurrences(of: "Set Aside/", with: "", options: [.anchored])
                .replacingOccurrences(of: "Trash/", with: "", options: [.anchored])
        case .classify(let path):
            destination = path
        }
    }

    private func perform() {
        isWorking = true
        Task {
            do {
                switch request {
                case .create:
                    _ = try await appState.createNote(relativePath: destination, title: title)
                case .duplicate(let source):
                    _ = try await appState.duplicateNote(source, to: destination)
                case .move(let source), .restore(let source):
                    try await appState.moveNote(source, to: destination)
                case .classify(let source):
                    try await appState.classifyUnclassified(
                        source,
                        into: classificationSlot,
                        destination: destination
                    )
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }
}
