import ScholiumCore
import SwiftUI

/// Fingerprint-bound Human Review for Analyses and Topics.
struct QualityReviewView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let note: Note

    @State private var qualification: NoteQualification?
    @State private var reviewNote = ""
    @State private var reviewRevision: DocumentFingerprint?
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var existingReviewIsStale: Bool {
        guard let record = appState.humanReviewRecord(for: note.relativePath),
              let current = appState.documentRevisions[note.relativePath] else { return false }
        return record.latestReview != nil && record.review(for: current) == nil
    }

    private var canComplete: Bool {
        qualification != nil &&
        !reviewNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        reviewNote.count <= 500 &&
        !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    reviewNoteSection
                    qualificationSection
                    storageExplanation
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .frame(minWidth: 620, idealWidth: 660, minHeight: 540, idealHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("scholium.humanReviewSheet")
        .onAppear(perform: loadReview)
        .alert("Could Not Save Human Review", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Keep Editing", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Human Review")
                    .font(.title2.weight(.semibold))
                Text(note.title ?? note.displayName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if existingReviewIsStale {
                    Label(
                        "This note changed since its latest completed Review.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
            Spacer()
        }
        .padding(18)
    }

    private var reviewNoteSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Summarize the main strength, problem, or next step in a few sentences.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $reviewNote)
                    .font(.body)
                    .frame(minHeight: 100, maxHeight: 140)
                    .padding(5)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(reviewNote.count > 500 ? Color.red : Color(nsColor: .separatorColor), lineWidth: 0.5)
                    }
                    .accessibilityLabel("Review Note")
                    .accessibilityIdentifier("scholium.reviewNoteField")

                Text("\(reviewNote.count)/500")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(reviewNote.count > 500 ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } label: {
            Label("Review Note", systemImage: "note.text")
                .font(.headline)
        }
    }

    private var qualificationSection: some View {
        GroupBox {
            Picker("Qualification", selection: $qualification) {
                Text("Choose…").tag(NoteQualification?.none)
                Label("Qualified", systemImage: "checkmark.seal").tag(NoteQualification?.some(.qualified))
                Label("Unqualified", systemImage: "xmark.seal").tag(NoteQualification?.some(.unqualified))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Qualification")
            .accessibilityHint("A verdict is required only when completing Review")
            .accessibilityIdentifier("scholium.reviewQualification")
        } label: {
            Text("Qualification")
                .font(.headline)
        }
    }

    private var storageExplanation: some View {
        Label(
            "Human Review stays in Scholium’s Application Support folder and does not alter this Markdown file. Researcher comments are managed separately from Review.",
            systemImage: "externaldrive.badge.checkmark"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("scholium.reviewCancel")
            Spacer()
            Button("Save as Draft") { save(asDraft: true) }
                .disabled(isSaving || reviewNote.count > 500)
                .accessibilityIdentifier("scholium.reviewSaveDraft")
            Button("Complete Review") { save(asDraft: false) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canComplete)
                .accessibilityIdentifier("scholium.reviewComplete")
        }
        .padding(16)
    }

    private func loadReview() {
        reviewRevision = appState.documentRevisions[note.relativePath]
        guard let record = appState.humanReviewRecord(for: note.relativePath) else { return }
        if let draft = record.draft, draft.fingerprint == reviewRevision {
            qualification = draft.qualification
            reviewNote = draft.reviewNote
        } else if let revision = reviewRevision, let completed = record.review(for: revision) {
            qualification = completed.qualification
            reviewNote = completed.reviewNote
        }
    }

    private func save(asDraft: Bool) {
        guard let revision = reviewRevision else {
            errorMessage = "The reviewed revision is unavailable. Close Review and reopen the note."
            return
        }
        Task { @MainActor in
            isSaving = true
            defer { isSaving = false }
            do {
                if asDraft {
                    try await appState.saveHumanReviewDraft(
                        for: note.relativePath,
                        fingerprint: revision,
                        qualification: qualification,
                        reviewNote: reviewNote
                    )
                } else {
                    try await appState.completeHumanReview(
                        for: note.relativePath,
                        fingerprint: revision,
                        qualification: qualification,
                        reviewNote: reviewNote
                    )
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

}
