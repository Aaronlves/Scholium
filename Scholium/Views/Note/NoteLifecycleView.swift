import ScholiumContracts
import SwiftUI

struct NoteLifecycleActions {
    let putBackDestination: @MainActor (String) -> String?
    let duplicate: @MainActor (NoteLifecycleTarget, String) async throws -> Void
    let move: @MainActor (NoteLifecycleTarget, String) async throws -> Void
    let putBack: @MainActor (String) async throws -> Void
    let classify: @MainActor (String, WorkspaceVaultSlot, String) async throws -> Void
}

struct NoteLifecycleView: View {
    @Environment(\.dismiss) private var dismiss

    let request: NoteLifecycleRequest
    let actions: NoteLifecycleActions

    @State private var destination = ""
    @State private var classificationSlot: WorkspaceVaultSlot = .paperAnalysis
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Label(sheetTitle, systemImage: symbol)
                        .font(.title2.weight(.semibold))
                    Spacer()
                }

                if case .classify = request {
                    adaptiveField(
                        "Destination",
                        wide: {
                            destinationPicker
                                .frame(minWidth: 300)
                        },
                        compact: {
                            destinationPicker
                                .frame(maxWidth: .infinity)
                        }
                    )
                }

                if case .putBack = request {
                    adaptiveField(
                        "Original Location",
                        wide: {
                            Text(destination)
                                .textSelection(.enabled)
                                .font(.body.monospaced())
                                .frame(minWidth: 300, alignment: .leading)
                        },
                        compact: {
                            Text(destination)
                                .textSelection(.enabled)
                                .font(.body.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    )
                } else {
                    adaptiveField(
                        "Location",
                        wide: {
                            TextField("Folder/Note.md", text: $destination)
                                .font(.body.monospaced())
                                .frame(minWidth: 300)
                        },
                        compact: {
                            TextField("Folder/Note.md", text: $destination)
                                .font(.body.monospaced())
                        }
                    )
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
                        .disabled(
                            destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || isWorking
                        )
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 0, idealWidth: 540, minHeight: 0, idealHeight: 460)
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

    @ViewBuilder
    private func adaptiveField<WideContent: View, CompactContent: View>(
        _ title: String,
        @ViewBuilder wide: () -> WideContent,
        @ViewBuilder compact: () -> CompactContent
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            LabeledContent(title) {
                wide()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.callout.weight(.medium))
                compact()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var destinationPicker: some View {
        Picker("Destination", selection: $classificationSlot) {
            ForEach(WorkspaceVaultSlot.allCases) { slot in
                Text(ScholiumL10n.dynamicString(slot.displayName)).tag(slot)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }

    private var sheetTitle: String {
        switch request {
        case .duplicate: "Duplicate Note"
        case .move: "Move or Rename Note"
        case .putBack: "Put Back Note"
        case .classify: "Classify Imported Note"
        }
    }

    private var actionTitle: String {
        switch request {
        case .duplicate: "Duplicate"
        case .move: "Move"
        case .putBack: "Put Back"
        case .classify: "Classify"
        }
    }

    private var symbol: String {
        switch request {
        case .duplicate: "plus.square.on.square"
        case .move: "folder"
        case .putBack: "arrow.uturn.backward"
        case .classify: "tray.and.arrow.down"
        }
    }

    private var helpText: String {
        switch request {
        case .duplicate:
            "The duplicate preserves the exact source bytes and receives a new stable note identity."
        case .move:
            "Moving or renaming preserves the note identity, page annotations, earlier Review and Dialogue archives, and Research Record."
        case .putBack:
            "Put Back returns this note to its exact original vault-relative location. Scholium never renames it or chooses another folder."
        case .classify:
            "Classification moves the imported copy from Unclassified into the selected Triptych vault. The original external file remains unchanged."
        }
    }

    private func configureDefaults() {
        switch request {
        case .duplicate(let target):
            let base = (target.relativePath as NSString).deletingPathExtension
            destination = base + " Copy.md"
        case .move(let target):
            destination = target.relativePath
        case .putBack(let path):
            destination = actions.putBackDestination(path) ?? ""
        case .classify(let path):
            destination = path
        }
    }

    private func perform() {
        isWorking = true
        Task {
            do {
                switch request {
                case .duplicate(let source):
                    try await actions.duplicate(source, destination)
                case .move(let source):
                    try await actions.move(source, destination)
                case .putBack(let source):
                    try await actions.putBack(source)
                case .classify(let source):
                    try await actions.classify(source, classificationSlot, destination)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }

}
