import ScholiumContracts
import SwiftUI

/// Fingerprint-bound Human Review for Analyses and Topics.
struct QualityReviewContext {
    let revision: DocumentFingerprint?
    let record: HumanReviewRecord?
    let qualification: Binding<NoteQualification?>
    let reviewNote: Binding<String>
    let researchStatusDeclared: Bool
    let declareResearchStatus: () -> Void
    let saveDraft: (DocumentFingerprint, NoteQualification?, String) async throws -> Void
    let completeReview: (DocumentFingerprint, NoteQualification?, String) async throws -> Void

    init(
        revision: DocumentFingerprint?,
        record: HumanReviewRecord?,
        qualification: Binding<NoteQualification?>,
        reviewNote: Binding<String>,
        researchStatusDeclared: Bool = true,
        declareResearchStatus: @escaping () -> Void = {},
        saveDraft: @escaping (DocumentFingerprint, NoteQualification?, String) async throws -> Void,
        completeReview: @escaping (DocumentFingerprint, NoteQualification?, String) async throws -> Void
    ) {
        self.revision = revision
        self.record = record
        self.qualification = qualification
        self.reviewNote = reviewNote
        self.researchStatusDeclared = researchStatusDeclared
        self.declareResearchStatus = declareResearchStatus
        self.saveDraft = saveDraft
        self.completeReview = completeReview
    }
}

struct QualityReviewView: View {
    @Environment(\.dismiss) private var dismiss

    let note: WindowDocumentLocation
    let context: QualityReviewContext
    let showsHeader: Bool

    @State private var errorMessage: String?
    @State private var isSaving = false

    init(
        note: WindowDocumentLocation,
        context: QualityReviewContext,
        showsHeader: Bool = true
    ) {
        self.note = note
        self.context = context
        self.showsHeader = showsHeader
    }

    private var existingReviewIsStale: Bool {
        guard let record = context.record,
              let current = context.revision else { return false }
        return record.latestReview != nil && record.review(for: current) == nil
    }

    private var canComplete: Bool {
        context.researchStatusDeclared &&
        context.qualification.wrappedValue != nil &&
        !context.reviewNote.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        context.reviewNote.wrappedValue.count <= 500 &&
        !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header
                Divider()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !context.researchStatusDeclared {
                        researchStatusGate
                    }
                    reviewNoteSection
                    qualificationSection
                    storageExplanation
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .frame(
            minWidth: 0,
            idealWidth: 660,
            minHeight: showsHeader ? 540 : 340,
            idealHeight: showsHeader ? 680 : 500
        )
        .scholiumSurface(.denseEvidence)
        .accessibilityIdentifier("scholium.humanReviewSheet")
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
                    .scholiumForeground(.attention)
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
                TextEditor(text: context.reviewNote)
                    .font(.body)
                    .frame(minHeight: 100, maxHeight: 140)
                    .padding(5)
                    .background(
                        ScholiumColorRole.documentBackground.color,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                context.reviewNote.wrappedValue.count > 500
                                    ? ScholiumColorRole.destructive.color
                                    : ScholiumColorRole.separator.color,
                                lineWidth: 0.5
                            )
                    }
                    .accessibilityLabel("Review Note")
                    .accessibilityIdentifier("scholium.reviewNoteField")

                Text("\(context.reviewNote.wrappedValue.count)/500")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(
                        context.reviewNote.wrappedValue.count > 500
                            ? ScholiumColorRole.destructive.color
                            : ScholiumColorRole.secondaryText.color
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } label: {
            Label("Review Note", systemImage: "note.text")
                .font(.headline)
        }
    }

    private var qualificationSection: some View {
        GroupBox {
            Picker("Qualification", selection: context.qualification) {
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
            "Human Review and Comments remain separate app-owned records even though this panel presents them together. Neither alters the Markdown file.",
            systemImage: "externaldrive.badge.checkmark"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var researchStatusGate: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("You can keep editing this Review and save it as a draft. Complete Review becomes available after this Analysis has a declared Research Status.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Declare Research Status…", action: context.declareResearchStatus)
                    .accessibilityHint("Opens Properties for this Analysis")
                    .accessibilityIdentifier("scholium.reviewDeclareResearchStatus")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Research Status: Not Yet", systemImage: "circle.dashed")
                .font(.headline)
        }
        .accessibilityIdentifier("scholium.reviewResearchStatusGate")
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("scholium.reviewCancel")
            Spacer()
            Button("Save as Draft") { save(asDraft: true) }
                .disabled(isSaving || context.reviewNote.wrappedValue.count > 500)
                .accessibilityIdentifier("scholium.reviewSaveDraft")
            Button("Complete Review") { save(asDraft: false) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canComplete)
                .accessibilityIdentifier("scholium.reviewComplete")
        }
        .padding(16)
    }

    private func save(asDraft: Bool) {
        guard let revision = context.revision else {
            errorMessage = "The reviewed revision is unavailable. Close Review and reopen the note."
            return
        }
        Task { @MainActor in
            isSaving = true
            defer { isSaving = false }
            do {
                if asDraft {
                    try await context.saveDraft(
                        revision,
                        context.qualification.wrappedValue,
                        context.reviewNote.wrappedValue
                    )
                } else {
                    try await context.completeReview(
                        revision,
                        context.qualification.wrappedValue,
                        context.reviewNote.wrappedValue
                    )
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

}
