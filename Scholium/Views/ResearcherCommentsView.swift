import ScholiumCore
import SwiftUI

/// One app-owned comment surface shared by Analyses, Topics, and ordinary
/// Works. Comments never require or imply a Human Review verdict.
struct ResearcherCommentsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let note: Note

    @State private var comments: [ResearcherComment] = []
    @State private var newComment = ""
    @State private var editingCommentID: UUID?
    @State private var editingText = ""
    @State private var pendingDeletion: ResearcherComment?
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var pendingSelection: MarkdownReviewSelection? {
        appState.pendingCommentSelection
    }

    private var pendingAnchor: ResearcherCommentAnchor? {
        guard let selection = pendingSelection else { return nil }
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

    private var canAdd: Bool {
        !newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWorking
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        addSection
                        existingComments
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear {
                    loadComments()
                    if let id = appState.focusedResearcherCommentID {
                        DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }

            Divider()
            HStack {
                Label(
                    "Stored in Scholium, not in the Markdown file",
                    systemImage: "externaldrive.badge.checkmark"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .frame(minWidth: 620, idealWidth: 700, minHeight: 520, idealHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("scholium.researcherCommentsSheet")
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
        .alert("Comments Unavailable", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Keep Comments Open", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Researcher Comments")
                    .font(.title2.weight(.semibold))
                Text(note.title ?? note.displayName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(18)
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
                            "Scholium could not identify one exact source range for this rendered selection. Select it again in Live Preview or Source, or add a whole-note comment.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                } else {
                    Text("This comment applies to the whole note.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                TextEditor(text: $newComment)
                    .font(.body)
                    .frame(minHeight: 84, maxHeight: 130)
                    .padding(5)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    }
                    .accessibilityLabel(pendingAnchor == nil ? "Whole-note comment" : "Comment on selected passage")
                    .accessibilityIdentifier("scholium.newResearcherComment")

                HStack {
                    if pendingSelection != nil, pendingAnchor == nil {
                        Button("Use as Whole-Note Comment") {
                            appState.pendingCommentSelection = nil
                        }
                    }
                    Spacer()
                    Button("Add Comment") { addComment() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canAdd || (pendingSelection != nil && pendingAnchor == nil))
                        .accessibilityIdentifier("scholium.addResearcherComment")
                }
            }
        } label: {
            Label(pendingSelection == nil ? "New Whole-Note Comment" : "New Selection Comment", systemImage: "plus.bubble")
                .font(.headline)
        }
    }

    private var existingComments: some View {
        GroupBox {
            if comments.isEmpty {
                ContentUnavailableView(
                    "No Comments",
                    systemImage: "text.bubble",
                    description: Text("Add a whole-note comment or select a passage in Read, Live Preview, or Source.")
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
                if let anchor = comment.anchor {
                    Text(anchor.selectedText ?? anchor.quotation)
                        .font(ScholiumTypography.swiftUIMonospaceFont(size: 11, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(4)
                }
                HStack(spacing: 12) {
                    Button("Edit") {
                        editingCommentID = comment.id
                        editingText = comment.text
                    }
                    Button(comment.resolvedAt == nil ? "Resolve" : "Reopen") {
                        setResolved(comment, resolved: comment.resolvedAt == nil)
                    }
                    if comment.anchor?.state == .needsReattachment {
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

    private func loadComments() {
        comments = appState.humanReviewRecord(for: note.relativePath)?.comments ?? []
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            isWorking = true
            defer { isWorking = false }
            do {
                try await operation()
                loadComments()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addComment() {
        let text = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let anchor = pendingSelection == nil ? nil : pendingAnchor
        run {
            _ = try await appState.addResearcherComment(
                to: note.relativePath,
                text: text,
                anchor: anchor
            )
            newComment = ""
            appState.pendingCommentSelection = nil
        }
    }

    private func saveEdit(_ comment: ResearcherComment) {
        let text = editingText
        run {
            try await appState.updateResearcherComment(
                at: note.relativePath,
                commentID: comment.id,
                text: text
            )
            editingCommentID = nil
            editingText = ""
        }
    }

    private func setResolved(_ comment: ResearcherComment, resolved: Bool) {
        run {
            try await appState.setResearcherCommentResolved(
                at: note.relativePath,
                commentID: comment.id,
                resolved: resolved
            )
        }
    }

    private func delete(_ comment: ResearcherComment) {
        pendingDeletion = nil
        run {
            try await appState.deleteResearcherComment(
                at: note.relativePath,
                commentID: comment.id
            )
        }
    }

    private func reattach(_ comment: ResearcherComment, to anchor: ResearcherCommentAnchor) {
        run {
            try await appState.reattachResearcherComment(
                at: note.relativePath,
                commentID: comment.id,
                anchor: anchor
            )
        }
    }

    private func tryAutomaticReattachment() {
        run { _ = try await appState.tryReattachingResearcherComments(at: note.relativePath) }
    }

    private func locationText(_ comment: ResearcherComment) -> String {
        guard let anchor = comment.anchor else { return "Whole note" }
        if anchor.state == .needsReattachment {
            return "Needs Reattachment · originally line \(anchor.line)"
        }
        return anchor.line == anchor.endLine
            ? "Line \(anchor.line)"
            : "Lines \(anchor.line)–\(anchor.endLine)"
    }

    private func locationSymbol(_ comment: ResearcherComment) -> String {
        guard let anchor = comment.anchor else { return "doc.text" }
        return anchor.state == .attached ? "text.quote" : "exclamationmark.triangle"
    }

    private func locationColor(_ comment: ResearcherComment) -> Color {
        comment.anchor?.state == .needsReattachment ? .orange : .secondary
    }
}
