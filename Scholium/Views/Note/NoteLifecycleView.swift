import ScholiumContracts
import SwiftUI

struct NoteLifecycleActions {
    let putBackDestination: @MainActor (String) -> String?
    let create: @MainActor (String, String, String?, [String]) async throws -> Void
    let duplicate: @MainActor (String, String) async throws -> Void
    let move: @MainActor (String, String) async throws -> Void
    let putBack: @MainActor (String) async throws -> Void
    let classify: @MainActor (String, WorkspaceVaultSlot, String) async throws -> Void
}

struct NoteLifecycleView: View {
    @Environment(\.dismiss) private var dismiss

    let request: NoteLifecycleRequest
    let vaultRole: VaultRole
    let actions: NoteLifecycleActions

    @State private var title = ""
    @State private var destination = ""
    @State private var researchUnitScope = ""
    @State private var researchUnitLimitationsText = ""
    @State private var classificationSlot: WorkspaceVaultSlot = .paperAnalysis
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var isAnalysisCreation: Bool {
        if case .create = request {
            return vaultRole == .sourceCorpus
        }
        return false
    }

    private var researchUnitLimitations: [String] {
        researchUnitLimitationsText
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Label(sheetTitle, systemImage: symbol)
                        .font(.title2.weight(.semibold))
                    Spacer()
                }

                if request == .create {
                    adaptiveField(
                        "Title",
                        wide: {
                            TextField("Untitled note", text: $title)
                                .frame(minWidth: 300)
                        },
                        compact: {
                            TextField("Untitled note", text: $title)
                        }
                    )

                    if isAnalysisCreation {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Research Status", systemImage: "scope")
                                .font(.headline)
                            Text("Declare the source material this Analysis will represent. Limitations are optional and should describe material boundaries.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            adaptiveField(
                                "Scope",
                                wide: {
                                    TextField("For example, Introduction and Chapters 1–4", text: $researchUnitScope)
                                        .frame(minWidth: 300)
                                        .accessibilityLabel("Research Status Scope")
                                        .accessibilityIdentifier("scholium.newNote.researchUnitScope")
                                },
                                compact: {
                                    TextField("For example, Introduction and Chapters 1–4", text: $researchUnitScope)
                                        .accessibilityLabel("Research Status Scope")
                                        .accessibilityIdentifier("scholium.newNote.researchUnitScope")
                                }
                            )

                            adaptiveField(
                                "Limitations",
                                wide: { limitationsEditor(minWidth: 300) },
                                compact: { limitationsEditor(minWidth: 0) }
                            )
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("scholium.newNote.researchStatus")
                    }
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
                                || (isAnalysisCreation && researchUnitScope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                Text(slot.displayName).tag(slot)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }

    private func limitationsEditor(minWidth: CGFloat) -> some View {
        TextEditor(text: $researchUnitLimitationsText)
            .font(.body)
            .frame(minWidth: minWidth, maxWidth: .infinity, minHeight: 72)
            .scrollContentBackground(.hidden)
            .padding(4)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            }
            .accessibilityLabel("Research Status Limitations")
            .accessibilityHint("Enter one material boundary per line")
            .accessibilityIdentifier("scholium.newNote.researchUnitLimitations")
    }

    private var sheetTitle: String {
        switch request {
        case .create: "New Note"
        case .duplicate: "Duplicate Note"
        case .move: "Move or Rename Note"
        case .putBack: "Put Back Note"
        case .classify: "Classify Imported Note"
        }
    }

    private var actionTitle: String {
        switch request {
        case .create: "Create"
        case .duplicate: "Duplicate"
        case .move: "Move"
        case .putBack: "Put Back"
        case .classify: "Classify"
        }
    }

    private var symbol: String {
        switch request {
        case .create: "doc.badge.plus"
        case .duplicate: "plus.square.on.square"
        case .move: "folder"
        case .putBack: "arrow.uturn.backward"
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
        case .putBack:
            "Put Back returns this note to its exact original vault-relative location. Scholium never renames it or chooses another folder."
        case .classify:
            "Classification moves the imported copy from Unclassified into the selected Triptych vault. The original external file remains unchanged."
        }
    }

    private func configureDefaults() {
        researchUnitScope = ""
        researchUnitLimitationsText = ""
        switch request {
        case .create:
            destination = "Untitled.md"
        case .duplicate(let path):
            let base = (path as NSString).deletingPathExtension
            destination = base + " Copy.md"
        case .move(let path):
            destination = path
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
                case .create:
                    try await actions.create(
                        destination,
                        title,
                        isAnalysisCreation ? researchUnitScope : nil,
                        isAnalysisCreation ? researchUnitLimitations : []
                    )
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
