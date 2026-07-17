import ScholiumContracts
import SwiftUI

/// One app-owned comment surface shared by Analyses, Topics, and ordinary
/// Works. Comments never require or imply a Human Review verdict.
struct ResearcherCommentsContext {
    let initialComments: [ResearcherComment]
    let pendingSelection: MarkdownReviewSelection?
    let focusedCommentID: UUID?
    let clearPendingSelection: () -> Void
    let add: (String, ResearcherCommentAnchor) async throws -> [ResearcherComment]
    let update: (UUID, String) async throws -> [ResearcherComment]
    let setResolved: (UUID, Bool) async throws -> [ResearcherComment]
    let delete: (UUID) async throws -> [ResearcherComment]
    let reattach: (UUID, ResearcherCommentAnchor) async throws -> [ResearcherComment]
    let tryAutomaticReattachment: () async throws -> [ResearcherComment]
}

/// Keeps the passage-only creation rule testable. A missing pending anchor can
/// never produce a new Comment composer or stored Comment.
enum ResearcherCommentCreationPolicy {
    static let selectionRequiredMessage =
        "Comments are passage-specific. Select text in Read, Live Preview, or Source, then choose Add Comment. Review or Critique provides the whole-note judgment."

    static func anchor(
        for selection: MarkdownReviewSelection?,
        in note: WindowDocumentLocation
    ) -> ResearcherCommentAnchor? {
        guard let selection else { return nil }
        let document = NoteDocument(relativePath: note.relativePath, rawContent: note.rawContent)
        if let exactRange = selection.exactUTF16Range {
            return ResearcherCommentAnchorBuilder.anchor(
                in: note.rawContent,
                fingerprint: document.fingerprint,
                utf16Range: exactRange,
                selectedText: selection.excerpt
            )
        }
        return ResearcherCommentAnchorBuilder.anchor(
            forRenderedQuotation: selection.excerpt,
            contextBefore: selection.contextBefore,
            contextAfter: selection.contextAfter,
            in: document
        )
    }
}

struct ResearcherCommentsView: View {
    let note: WindowDocumentLocation
    let context: ResearcherCommentsContext
    let focusComposerOnAppear: Bool
    let evidenceSelection: Set<UUID>
    let setEvidenceSelected: ((UUID, Bool) -> Void)?

    @State private var comments: [ResearcherComment] = []
    @State private var pendingSelection: MarkdownReviewSelection?
    @State private var newComment = ""
    @State private var editingCommentID: UUID?
    @State private var editingText = ""
    @State private var pendingDeletion: ResearcherComment?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var composerIsFocused: Bool

    init(
        note: WindowDocumentLocation,
        context: ResearcherCommentsContext,
        focusComposerOnAppear: Bool = false,
        evidenceSelection: Set<UUID> = [],
        setEvidenceSelected: ((UUID, Bool) -> Void)? = nil
    ) {
        self.note = note
        self.context = context
        self.focusComposerOnAppear = focusComposerOnAppear
        self.evidenceSelection = evidenceSelection
        self.setEvidenceSelected = setEvidenceSelected
    }

    private var pendingAnchor: ResearcherCommentAnchor? {
        ResearcherCommentCreationPolicy.anchor(for: pendingSelection, in: note)
    }

    private var canAdd: Bool {
        pendingAnchor != nil
            && !newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isWorking
    }

    var body: some View {
        embeddedBody
        .frame(minWidth: 0, idealWidth: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("scholium.researcherCommentsPanel")
        .onAppear(perform: load)
        .confirmationDialog(
            "Delete Comment?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { comment in
            Button("Delete Comment", role: .destructive) { delete(comment) }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { _ in
            Text("This removes the app-owned comment. It does not change the Markdown note.")
        }
        .alert("Comment Unavailable", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Keep Panel Open", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var embeddedBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            addSection
            existingComments
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() {
        comments = context.initialComments
        pendingSelection = context.pendingSelection
        if focusComposerOnAppear, pendingAnchor != nil {
            DispatchQueue.main.async { composerIsFocused = true }
        }
    }

    private var addSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if let selection = pendingSelection {
                    Label(selection.lineDescription, systemImage: "text.quote")
                        .font(.caption.weight(.semibold))
                    Text(selection.excerpt)
                        .font(ScholiumTypography.swiftUIMonospaceFont(size: 12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(6)
                    if pendingAnchor == nil {
                        Label(
                            "Scholium could not attach this selection to one exact source range. Select the passage again in Read, Live Preview, or Source.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }

                if pendingAnchor != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        TextEditor(text: $newComment)
                            .font(.body)
                            .frame(minHeight: 84, maxHeight: 130)
                            .padding(5)
                            .background(
                                Color(nsColor: .textBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                            }
                            .focused($composerIsFocused)
                            .accessibilityLabel("Comment on selected passage")
                            .accessibilityIdentifier("scholium.newResearcherComment")

                        HStack {
                            Spacer()
                            Button("Add Comment") { addComment() }
                                .buttonStyle(.borderedProminent)
                                .disabled(!canAdd)
                                .accessibilityIdentifier("scholium.addResearcherComment")
                        }
                    }
                    .id("scholium.commentComposer")
                } else {
                    Label(
                        ResearcherCommentCreationPolicy.selectionRequiredMessage,
                        systemImage: "selection.pin.in.out"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("scholium.commentSelectionRequired")
                }
            }
        } label: {
            Label("Add a Passage Comment", systemImage: "plus.bubble")
                .font(.headline)
        }
    }

    private var existingComments: some View {
        GroupBox {
            if comments.isEmpty {
                ContentUnavailableView(
                    "No Comments",
                    systemImage: "text.bubble",
                    description: Text("Select a passage in Read, Live Preview, or Source to add a Comment.")
                )
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(comments) { comment in
                        commentRow(comment)
                            .id(comment.id)
                        if comment.id != comments.last?.id { Divider() }
                    }
                }
            }
        } label: {
            Label("Saved Comments", systemImage: "text.bubble.fill")
                .font(.headline)
        }
    }

    private func commentRow(_ comment: ResearcherComment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                if let setEvidenceSelected {
                    Toggle(
                        "Use as Context",
                        isOn: Binding(
                            get: { evidenceSelection.contains(comment.id) },
                            set: { setEvidenceSelected(comment.id, $0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .help("Include this app-owned Comment as read-only context for Critique")
                    .accessibilityIdentifier(
                        "scholium.researchFunctionComment.\(comment.id.uuidString)"
                    )
                }
                Label(locationText(comment), systemImage: locationSymbol(comment))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(locationColor(comment))
                if comment.resolvedAt != nil {
                    Text("Resolved")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(comment.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if editingCommentID == comment.id {
                TextEditor(text: $editingText)
                    .frame(minHeight: 70, maxHeight: 120)
                    .padding(5)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel("Edit researcher comment")
                HStack {
                    Button("Cancel") {
                        editingCommentID = nil
                        editingText = ""
                    }
                    Spacer()
                    Button("Save Comment") { saveEdit(comment) }
                        .buttonStyle(.borderedProminent)
                        .disabled(editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
                }
            } else {
                Text(comment.text)
                    .textSelection(.enabled)
                let anchor = comment.anchor
                Text(anchor.selectedText ?? anchor.quotation)
                    .font(ScholiumTypography.swiftUIMonospaceFont(size: 11, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(4)
                HStack(spacing: 12) {
                    Button("Edit") {
                        editingCommentID = comment.id
                        editingText = comment.text
                    }
                    Button(comment.resolvedAt == nil ? "Resolve" : "Reopen") {
                        setResolved(comment, resolved: comment.resolvedAt == nil)
                    }
                    if comment.anchor.state == .needsReattachment {
                        if let pendingAnchor {
                            Button("Reattach Here") { reattach(comment, to: pendingAnchor) }
                        } else {
                            Button("Find in Current Note") { tryAutomaticReattachment() }
                        }
                    }
                    Spacer()
                    Button("Delete", role: .destructive) { pendingDeletion = comment }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Researcher comment, \(locationText(comment))")
    }

    private func run(
        _ operation: @escaping @MainActor () async throws -> [ResearcherComment]
    ) {
        Task { @MainActor in
            isWorking = true
            defer { isWorking = false }
            do {
                comments = try await operation()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addComment() {
        let text = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let anchor = pendingAnchor else { return }
        run {
            let updated = try await context.add(text, anchor)
            newComment = ""
            pendingSelection = nil
            context.clearPendingSelection()
            return updated
        }
    }

    private func saveEdit(_ comment: ResearcherComment) {
        let text = editingText
        run {
            let updated = try await context.update(comment.id, text)
            editingCommentID = nil
            editingText = ""
            return updated
        }
    }

    private func setResolved(_ comment: ResearcherComment, resolved: Bool) {
        run {
            try await context.setResolved(comment.id, resolved)
        }
    }

    private func delete(_ comment: ResearcherComment) {
        pendingDeletion = nil
        run {
            try await context.delete(comment.id)
        }
    }

    private func reattach(_ comment: ResearcherComment, to anchor: ResearcherCommentAnchor) {
        run {
            try await context.reattach(comment.id, anchor)
        }
    }

    private func tryAutomaticReattachment() {
        run { try await context.tryAutomaticReattachment() }
    }

    private func locationText(_ comment: ResearcherComment) -> String {
        let anchor = comment.anchor
        if anchor.state == .needsReattachment {
            return "Needs Reattachment — originally line \(anchor.line)"
        }
        return anchor.line == anchor.endLine
            ? "Line \(anchor.line)"
            : "Lines \(anchor.line)–\(anchor.endLine)"
    }

    private func locationSymbol(_ comment: ResearcherComment) -> String {
        comment.anchor.state == .attached ? "text.quote" : "exclamationmark.triangle"
    }

    private func locationColor(_ comment: ResearcherComment) -> Color {
        comment.anchor.state == .needsReattachment ? .orange : .secondary
    }
}
