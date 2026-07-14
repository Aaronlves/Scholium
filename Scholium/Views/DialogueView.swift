import ScholiumCore
import SwiftUI

struct DialogueView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings

    @State private var instruction = ""
    @State private var requestedDestination = ""
    @State private var candidates: [DialogueNoteReference] = []
    @State private var selectedNoteIDs: Set<UUID> = []
    @State private var commentsByNote: [UUID: [ResearcherComment]] = [:]
    @State private var includedCommentIDs: Set<UUID> = []
    @State private var isLoading = true
    @State private var isCopying = false
    @State private var errorMessage: String?

    private var selectedNotes: [DialogueNoteReference] {
        candidates.filter { selectedNoteIDs.contains($0.noteID) }
    }

    private var includedCommentCandidates: [DialogueIncludedComment] {
        selectedNotes.flatMap { note in
            (commentsByNote[note.noteID] ?? []).map {
                DialogueIncludedComment(note: note, comment: $0)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isLoading {
                Spacer()
                ProgressView("Loading Triptych notes…")
                Spacer()
            } else {
                HSplitView {
                    selectionColumn
                        .frame(minWidth: 300, idealWidth: 340)
                    instructionColumn
                        .frame(minWidth: 430, maxWidth: .infinity)
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 820, idealWidth: 940, minHeight: 600, idealHeight: 700)
        .task { await loadCandidates() }
        .alert("Could Not Create Dialogue", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Keep Editing", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Create Dialogue")
                    .font(.title2.weight(.semibold))
                Text("Choose focal notes and package your comments into instructions for an external agent.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
    }

    private var selectionColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Selected Notes")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Divider()
            List {
                ForEach(WorkspaceVaultSlot.allCases) { slot in
                    let notes = candidates.filter { $0.vaultName == slot.displayName }
                    if !notes.isEmpty {
                        Section(slot.displayName) {
                            ForEach(notes) { note in
                                Toggle(isOn: noteSelection(note)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(note.title).lineLimit(1)
                                        Text(note.relativePath)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var instructionColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Researcher Instruction") {
                    TextEditor(text: $instruction)
                        .frame(minHeight: 100)
                        .padding(5)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel("Researcher instruction")
                        .accessibilityIdentifier("scholium.dialogue.instruction")
                }

                GroupBox("Requested Destination (Optional)") {
                    TextField(
                        "For example: update relevant Topic notes when warranted",
                        text: $requestedDestination
                    )
                    .textFieldStyle(.roundedBorder)
                    .accessibilityHint("Describe where the agent should place or apply the requested work.")
                }

                if !selectedNotes.isEmpty {
                    GroupBox("Included Comments") {
                        VStack(alignment: .leading, spacing: 8) {
                            if includedCommentCandidates.isEmpty {
                                Text("No comments are attached to the selected notes.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(selectedNotes) { note in
                                    let comments = commentsByNote[note.noteID] ?? []
                                    if !comments.isEmpty {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(note.title)
                                                .font(.subheadline.weight(.semibold))
                                            Text("\(note.vaultName) · \(note.relativePath)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Text("Note ID: \(note.noteID.uuidString)")
                                                .font(ScholiumTypography.swiftUIMonospaceFont(
                                                    size: 10,
                                                    relativeTo: .caption
                                                ))
                                                .foregroundStyle(.tertiary)
                                                .textSelection(.enabled)
                                        }
                                        .accessibilityElement(children: .combine)

                                        ForEach(comments) { comment in
                                            let location = comment.anchor.map {
                                                "Lines \($0.line)–\($0.endLine)"
                                            } ?? "Whole note"
                                            Toggle(isOn: commentSelection(comment)) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(comment.text).lineLimit(2)
                                                    Text(location)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                }
                                            }
                                            .toggleStyle(.checkbox)
                                            .accessibilityLabel(
                                                "\(note.title), \(note.relativePath), \(location): \(comment.text)"
                                            )
                                        }
                                        Divider()
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                LabeledContent("Template") {
                    HStack {
                        Text("Triptych Dialogue template")
                            .foregroundStyle(.secondary)
                        Button("Edit Dialogue Template…") {
                            UserDefaults.standard.set("research-guidance", forKey: "scholium.settings.selectedPane")
                            UserDefaults.standard.set("prompt-templates", forKey: "scholium.settings.researchGuidanceCollection")
                            UserDefaults.standard.set(ResearchPromptKind.dialogue.rawValue, forKey: "scholium.settings.researchGuidanceKind")
                            if let triptychID = appState.workspaceAssignment?.id {
                                UserDefaults.standard.set(triptychID.uuidString, forKey: "scholium.settings.triptychID")
                            }
                            openSettings()
                        }
                    }
                }

                Label(
                    "Copying completes pending autosaves and creates the automatic Before Agent Work checkpoint.",
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(18)
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.glass)
            Spacer()
            Button {
                copyInstructions()
            } label: {
                Label("Copy Instructions for Agent", systemImage: "doc.on.doc")
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("scholium.dialogue.copyInstructions")
            .disabled(
                instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                selectedNotes.isEmpty || isCopying
            )
        }
        .padding(16)
    }

    private func noteSelection(_ note: DialogueNoteReference) -> Binding<Bool> {
        Binding(
            get: { selectedNoteIDs.contains(note.noteID) },
            set: { selected in
                if selected { selectedNoteIDs.insert(note.noteID) }
                else { selectedNoteIDs.remove(note.noteID) }
                Task { await loadComments(for: note) }
            }
        )
    }

    private func commentSelection(_ comment: ResearcherComment) -> Binding<Bool> {
        Binding(
            get: { includedCommentIDs.contains(comment.id) },
            set: { included in
                if included { includedCommentIDs.insert(comment.id) }
                else { includedCommentIDs.remove(comment.id) }
            }
        )
    }

    private func loadCandidates() async {
        do {
            candidates = try await appState.dialogueCandidates()
            let fallbackInitial: Set<VaultQualifiedNoteID>
            if let vaultID = appState.currentRegisteredVault?.id,
               let path = appState.currentNote?.relativePath {
                fallbackInitial = [VaultQualifiedNoteID(vaultID: vaultID, relativePath: path)]
            } else {
                fallbackInitial = []
            }
            let initial = appState.dialogueInitialNotes.isEmpty
                ? fallbackInitial
                : appState.dialogueInitialNotes
            selectedNoteIDs = Set(candidates.filter {
                initial.contains(VaultQualifiedNoteID(
                    vaultID: $0.vaultID,
                    relativePath: $0.relativePath
                ))
            }.map(\.noteID))
            for note in selectedNotes { await loadComments(for: note) }
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    private func loadComments(for note: DialogueNoteReference) async {
        guard commentsByNote[note.noteID] == nil else { return }
        let comments = await appState.comments(for: note.noteID)
        commentsByNote[note.noteID] = comments
        includedCommentIDs.formUnion(comments.filter { $0.resolvedAt == nil }.map(\.id))
    }

    private func copyInstructions() {
        Task { @MainActor in
            isCopying = true
            defer { isCopying = false }
            do {
                let entry = try await appState.createDialogue(
                    instruction: instruction,
                    selectedNotes: selectedNotes,
                    includedCommentIDs: includedCommentIDs,
                    requestedDestination: requestedDestination
                )
                appState.showToast("Instructions copied. Before Agent Work checkpoint created.")
                appState.dialogueInitialNotes = []
                dismiss()
                _ = entry
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
