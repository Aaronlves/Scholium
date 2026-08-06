import AppKit
import ScholiumContracts
import SwiftUI

struct ResearchFinalizedResultView: View {
    let record: PortableResearchRecord

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
            HStack(alignment: .firstTextBaseline) {
                Text("RESEARCH RESULT")
                    .scholiumApparatusHeadingStyle()
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Label(dispositionTitle, systemImage: dispositionSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            }
            if record.academicResults.isEmpty {
                Text("This Action's frozen Result Contract has no academic fields.")
                    .font(.callout)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            } else {
                ForEach(Array(record.academicResults.enumerated()), id: \.element.id) {
                    index, result in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: result.definition.label)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(verbatim: resultValue(result))
                            .font(ScholiumInterfaceTypography.apparatusResearchContent)
                            .foregroundStyle(
                                result.value == nil
                                    ? ScholiumColorRole.secondaryText.color
                                    : ScholiumColorRole.primaryText.color
                            )
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if index + 1 < record.academicResults.count {
                        ScholiumStructuralRule()
                    }
                }
            }
            if let contextUse = record.contextUseReport {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Verified Context Use")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(
                        contextUse.entries.isEmpty
                            ? "The Agent did not claim any Research Context item as used."
                            : contextUse.entries.count == 1
                                ? "Scholium verified one claimed Context item against its current owner and recorded the reference."
                                : "Scholium verified \(contextUse.entries.count) claimed Context items against their current owners and recorded references."
                    )
                    .font(.callout)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("The result partition above is finalized. Researcher evaluation below is a separate, editable researcher-authored judgment.")
                .font(.caption)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("scholium.researchResult.finalized")
    }

    private var dispositionTitle: String {
        switch record.resultDisposition {
        case .completed: String(localized: "Completed")
        case .blocked: String(localized: "Blocked")
        }
    }

    private var dispositionSymbol: String {
        switch record.resultDisposition {
        case .completed: "checkmark.circle"
        case .blocked: "exclamationmark.circle"
        }
    }

    private func resultValue(_ result: PortableResearchAcademicFieldResult) -> String {
        guard let value = result.value else { return String(localized: "Not supplied") }
        return switch value {
        case .freeText(let text):
            text
        case .singleChoice(let choice):
            result.definition.choices.first { $0.value == choice }?.label ?? choice
        case .multipleChoice(let choices):
            choices.map { choice in
                result.definition.choices.first { $0.value == choice }?.label ?? choice
            }.joined(separator: ", ")
        }
    }
}

struct ResearcherEvaluationView: View {
    typealias Save = @MainActor (
        ResearcherEvaluationDraft,
        UUID?,
        DocumentFingerprint
    ) async throws -> PortableResearchRecord
    typealias Clear = @MainActor (
        UUID,
        DocumentFingerprint
    ) async throws -> PortableResearchRecord

    let record: PortableResearchRecord
    let save: Save
    let clear: Clear
    let didUpdateRecord: (PortableResearchRecord) -> Void
    let draftStateDidChange: (Bool) -> Void

    @State private var issues: Set<PortableResearchObservedIssue>
    @State private var noIssuesObserved: Bool
    @State private var valuableDiscovery: Bool
    @State private var note: String
    @State private var baseline: EvaluationSnapshot
    @State private var status: SaveStatus
    @State private var statusMessage: String?
    @State private var confirmsClear = false

    init(
        record: PortableResearchRecord,
        save: @escaping Save,
        clear: @escaping Clear,
        didUpdateRecord: @escaping (PortableResearchRecord) -> Void = { _ in },
        draftStateDidChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.record = record
        self.save = save
        self.clear = clear
        self.didUpdateRecord = didUpdateRecord
        self.draftStateDidChange = draftStateDidChange
        let snapshot = EvaluationSnapshot(record.researcherEvaluation)
        _issues = State(initialValue: snapshot.issues)
        _noIssuesObserved = State(initialValue: snapshot.noIssuesObserved)
        _valuableDiscovery = State(initialValue: snapshot.valuableDiscovery)
        _note = State(initialValue: snapshot.note)
        _baseline = State(initialValue: snapshot)
        _status = State(initialValue: record.researcherEvaluation == nil ? .clean : .saved)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
            HStack(alignment: .firstTextBaseline) {
                Text("RESEARCHER EVALUATION")
                    .scholiumApparatusHeadingStyle()
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Label(status.title, systemImage: status.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.foreground)
                    .accessibilityIdentifier("scholium.researchEvaluation.saveState")
            }
            Text("Record your explicit research judgment. This does not change the Agent's finalized result and does not by itself establish a philosophical truth.")
                .font(.caption)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Text("Observed Issues")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(PortableResearchObservedIssue.allCases, id: \.self) { issue in
                    Toggle(issueTitle(issue), isOn: issueBinding(issue))
                        .toggleStyle(.checkbox)
                        .frame(minHeight: 20)
                }
                Toggle("No Issues Observed", isOn: Binding(
                    get: { noIssuesObserved },
                    set: { selected in
                        noIssuesObserved = selected
                        if selected { issues.removeAll() }
                    }
                ))
                .toggleStyle(.checkbox)
                .frame(minHeight: 20)
                Toggle("Valuable Discovery", isOn: $valuableDiscovery)
                    .toggleStyle(.checkbox)
                    .frame(minHeight: 20)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Evaluation Note")
                    .font(.headline)
                TextEditor(text: $note)
                    .frame(minHeight: 104, idealHeight: 128)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(ScholiumColorRole.documentBackground.color)
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: ScholiumShape.editorialControlCornerRadius
                        )
                        .stroke(ScholiumColorRole.separator.color, lineWidth: 0.5)
                    }
                    .accessibilityLabel("Evaluation Note")
                    .accessibilityIdentifier("scholium.researchEvaluation.note")
                Text("Optional. Keep the note about this result; use Improve Current Method only for an explicit method-change comment.")
                    .font(.caption)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(
                        status == .outOfDate || status == .saveFailed
                            ? ScholiumColorRole.destructive.color
                            : ScholiumColorRole.secondaryText.color
                    )
                    .textSelection(.enabled)
                    .accessibilityIdentifier("scholium.researchEvaluation.message")
            }

            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                if baseline.revision != nil {
                    Button("Clear Saved Evaluation…") { confirmsClear = true }
                        .disabled(status == .saving)
                }
                Spacer()
                if status == .saving {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Saving Researcher Evaluation")
                }
                Button("Save Evaluation") { saveDraft() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave || status == .saving)
                    .accessibilityIdentifier("scholium.researchEvaluation.save")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: draftSnapshot) { _, newValue in
            let dirty = newValue != baseline
            if dirty && status != .saving { status = .unsavedDraft }
            if !dirty && status == .unsavedDraft { status = .saved }
            draftStateDidChange(dirty)
        }
        .onChange(of: record.researcherEvaluation?.revision) { _, revision in
            guard revision != baseline.revision else { return }
            if isDirty {
                status = .outOfDate
                statusMessage = "The saved evaluation changed elsewhere. Your local draft is preserved; reload or reconcile it before saving."
            } else {
                install(record.researcherEvaluation, status: .saved)
            }
        }
        .onDisappear { draftStateDidChange(isDirty) }
        .alert("Clear the Saved Evaluation?", isPresented: $confirmsClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Evaluation", role: .destructive) { clearSavedEvaluation() }
        } message: {
            Text("This removes the one current researcher evaluation. The finalized Agent result remains unchanged.")
        }
    }

    private var draftSnapshot: EvaluationSnapshot {
        EvaluationSnapshot(
            revision: baseline.revision,
            issues: issues,
            noIssuesObserved: noIssuesObserved,
            valuableDiscovery: valuableDiscovery,
            note: note
        )
    }

    private var isDirty: Bool { draftSnapshot != baseline }

    private var canSave: Bool {
        isDirty && (!issues.isEmpty
            || noIssuesObserved
            || valuableDiscovery
            || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func issueBinding(
        _ issue: PortableResearchObservedIssue
    ) -> Binding<Bool> {
        Binding(
            get: { issues.contains(issue) },
            set: { selected in
                if selected {
                    issues.insert(issue)
                    noIssuesObserved = false
                } else {
                    issues.remove(issue)
                }
            }
        )
    }

    private func saveDraft() {
        let draft: ResearcherEvaluationDraft
        let resultFingerprint: DocumentFingerprint
        do {
            draft = try ResearcherEvaluationDraft(
                observedIssues: PortableResearchObservedIssue.allCases.filter(
                    issues.contains
                ),
                noIssuesObserved: noIssuesObserved,
                valuableDiscovery: valuableDiscovery,
                note: note
            )
            resultFingerprint = try record.finalizedResultFingerprint()
        } catch {
            status = .saveFailed
            statusMessage = error.localizedDescription
            return
        }
        status = .saving
        statusMessage = nil
        let expectedRevision = baseline.revision
        Task { @MainActor in
            do {
                let updated = try await save(
                    draft,
                    expectedRevision,
                    resultFingerprint
                )
                install(updated.researcherEvaluation, status: .saved)
                didUpdateRecord(updated)
            } catch let error as PortableResearchEvaluationMutationError {
                status = error == .staleEvaluationRevision
                    || error == .finalizedResultChanged ? .outOfDate : .saveFailed
                statusMessage = error.localizedDescription
                draftStateDidChange(true)
            } catch {
                status = .saveFailed
                statusMessage = error.localizedDescription
                draftStateDidChange(true)
            }
        }
    }

    private func clearSavedEvaluation() {
        guard let revision = baseline.revision else { return }
        let resultFingerprint: DocumentFingerprint
        do { resultFingerprint = try record.finalizedResultFingerprint() }
        catch {
            status = .saveFailed
            statusMessage = error.localizedDescription
            return
        }
        status = .saving
        statusMessage = nil
        Task { @MainActor in
            do {
                let updated = try await clear(revision, resultFingerprint)
                install(nil, status: .saved)
                didUpdateRecord(updated)
            } catch let error as PortableResearchEvaluationMutationError {
                status = error == .staleEvaluationRevision
                    || error == .finalizedResultChanged ? .outOfDate : .saveFailed
                statusMessage = error.localizedDescription
            } catch {
                status = .saveFailed
                statusMessage = error.localizedDescription
            }
        }
    }

    private func install(
        _ evaluation: PortableResearcherEvaluation?,
        status: SaveStatus
    ) {
        let snapshot = EvaluationSnapshot(evaluation)
        baseline = snapshot
        issues = snapshot.issues
        noIssuesObserved = snapshot.noIssuesObserved
        valuableDiscovery = snapshot.valuableDiscovery
        note = snapshot.note
        self.status = status
        statusMessage = nil
        draftStateDidChange(false)
    }

    private func issueTitle(_ issue: PortableResearchObservedIssue) -> String {
        switch issue {
        case .sourceOrAttribution: String(localized: "Source or Attribution")
        case .conceptOrInterpretation: String(localized: "Concept or Interpretation")
        case .argumentOrObjectionReply:
            String(localized: "Argument or Objection/Reply")
        case .epistemicIdentityOrResearcherState:
            String(localized: "Epistemic Identity or Researcher State")
        case .evidentialScopeOrRestraint:
            String(localized: "Evidential Scope or Restraint")
        case .researchHelpOrNextStep:
            String(localized: "Research Help or Next Step")
        case .other: String(localized: "Other")
        }
    }
}

private struct EvaluationSnapshot: Equatable {
    let revision: UUID?
    let issues: Set<PortableResearchObservedIssue>
    let noIssuesObserved: Bool
    let valuableDiscovery: Bool
    let note: String

    init(_ evaluation: PortableResearcherEvaluation?) {
        revision = evaluation?.revision
        issues = Set(evaluation?.observedIssues ?? [])
        noIssuesObserved = evaluation?.noIssuesObserved ?? false
        valuableDiscovery = evaluation?.valuableDiscovery ?? false
        note = evaluation?.note ?? ""
    }

    init(
        revision: UUID?,
        issues: Set<PortableResearchObservedIssue>,
        noIssuesObserved: Bool,
        valuableDiscovery: Bool,
        note: String
    ) {
        self.revision = revision
        self.issues = issues
        self.noIssuesObserved = noIssuesObserved
        self.valuableDiscovery = valuableDiscovery
        self.note = note
    }
}

private enum SaveStatus: Equatable {
    case clean
    case unsavedDraft
    case saving
    case saved
    case outOfDate
    case saveFailed

    var title: String {
        switch self {
        case .clean: String(localized: "Not Evaluated")
        case .unsavedDraft: String(localized: "Unsaved Draft")
        case .saving: String(localized: "Saving")
        case .saved: String(localized: "Saved")
        case .outOfDate: String(localized: "Out of Date")
        case .saveFailed: String(localized: "Save Failed")
        }
    }

    var symbol: String {
        switch self {
        case .clean: "circle"
        case .unsavedDraft: "pencil.circle"
        case .saving: "arrow.triangle.2.circlepath"
        case .saved: "checkmark.circle"
        case .outOfDate: "exclamationmark.arrow.triangle.2.circlepath"
        case .saveFailed: "exclamationmark.circle"
        }
    }

    var foreground: Color {
        switch self {
        case .outOfDate, .saveFailed: ScholiumColorRole.destructive.color
        case .unsavedDraft: ScholiumColorRole.attention.color
        case .clean, .saving, .saved: ScholiumColorRole.secondaryText.color
        }
    }
}

struct ResearchMethodFeedbackView: View {
    typealias Save = @MainActor (
        ResearchMethodFeedbackDraft,
        UUID?,
        DocumentFingerprint
    ) async throws -> PortableResearchRecord
    typealias Clear = @MainActor (
        UUID,
        DocumentFingerprint
    ) async throws -> PortableResearchRecord
    typealias StartImprovement = @MainActor () async throws
        -> ResearchAgentHandoff

    let record: PortableResearchRecord
    let save: Save
    let clear: Clear
    let startImprovement: StartImprovement
    let didUpdateRecord: (PortableResearchRecord) -> Void

    @State private var isEditing = false
    @State private var draftText: String
    @State private var baselineRevision: UUID?
    @State private var status: SaveStatus
    @State private var message: String?
    @State private var confirmsHandled = false
    @State private var isStartingImprovement = false
    @State private var improvementHandoff: ResearchAgentHandoff?
    @State private var improvementMessage: String?

    init(
        record: PortableResearchRecord,
        save: @escaping Save,
        clear: @escaping Clear,
        startImprovement: @escaping StartImprovement,
        didUpdateRecord: @escaping (PortableResearchRecord) -> Void = { _ in }
    ) {
        self.record = record
        self.save = save
        self.clear = clear
        self.startImprovement = startImprovement
        self.didUpdateRecord = didUpdateRecord
        _draftText = State(initialValue: record.methodFeedbackComment?.text ?? "")
        _baselineRevision = State(
            initialValue: record.methodFeedbackComment?.revision
        )
        _status = State(
            initialValue: record.methodFeedbackComment == nil ? .clean : .saved
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("METHOD FEEDBACK")
                        .scholiumApparatusHeadingStyle()
                        .accessibilityAddTraits(.isHeader)
                    Text(
                        record.methodFeedbackComment == nil
                            ? "No unhandled Method feedback comment."
                            : "One researcher-authored Method feedback comment is still unhandled."
                    )
                    .font(.caption)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                }
                Spacer()
                Button(isEditing ? "Close Editor" : "Add Method Feedback…") {
                    isEditing.toggle()
                }
                .accessibilityHint(
                    "Opens the one researcher-authored Method feedback comment; it does not copy or reinterpret the evaluation automatically."
                )
                .accessibilityIdentifier("scholium.methodFeedback.edit")
            }

            if let comment = record.methodFeedbackComment, !isEditing {
                Text(comment.text)
                    .font(ScholiumInterfaceTypography.apparatusResearchContent)
                    .textSelection(.enabled)
                HStack {
                    Button("Improve Current Method…") {
                        beginMethodImprovement()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isStartingImprovement)
                    .accessibilityHint(
                        "Starts one local, short-lived Agent Run bounded to the exact Method and Practices used by this Research Record."
                    )
                    .accessibilityIdentifier("scholium.methodFeedback.improve")
                    if isStartingImprovement {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    Button("Mark Method Feedback Handled…") {
                        confirmsHandled = true
                    }
                }
            }

            if let handoff = improvementHandoff {
                VStack(alignment: .leading, spacing: 8) {
                    Text("METHOD IMPROVEMENT HANDOFF")
                        .scholiumApparatusHeadingStyle()
                    Text(improvementInstructions(handoff))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    HStack {
                        Button("Copy Improvement Handoff") {
                            NSPasteboard.general.clearContents()
                            let copied = NSPasteboard.general.setString(
                                improvementInstructions(handoff),
                                forType: .string
                            )
                            improvementMessage = copied
                                ? String(localized:
                                    "Copied the complete Method improvement handoff."
                                )
                                : String(localized:
                                    "The improvement handoff could not be copied."
                                )
                        }
                        Spacer()
                        Text("Expires \(handoff.expiresAt, style: .relative).")
                            .font(.caption)
                            .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    }
                }
                .padding(12)
                .background(ScholiumColorRole.raisedSurfaceBackground.color)
                .clipShape(RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialControlCornerRadius
                ))
            }

            if isEditing {
                Text("Write a bounded comment about the Method used for this Record. Scholium will not alter the Method until you explicitly enter the separate Method maintenance flow.")
                    .font(.caption)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
                TextEditor(text: $draftText)
                    .frame(minHeight: 88, idealHeight: 112)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(ScholiumColorRole.documentBackground.color)
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: ScholiumShape.editorialControlCornerRadius
                        )
                        .stroke(ScholiumColorRole.separator.color, lineWidth: 0.5)
                    }
                    .accessibilityLabel("Method Feedback Comment")
                HStack {
                    Label(status.title, systemImage: status.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status.foreground)
                    Spacer()
                    if status == .saving {
                        ProgressView().controlSize(.small)
                    }
                    Button("Save Method Feedback") { saveComment() }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            status == .saving
                                || draftText.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty
                        )
                }
            }

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(
                        status == .outOfDate || status == .saveFailed
                            ? ScholiumColorRole.destructive.color
                            : ScholiumColorRole.secondaryText.color
                    )
                    .textSelection(.enabled)
            }
            if let improvementMessage {
                Text(improvementMessage)
                    .font(.caption)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: draftText) { _, text in
            guard isEditing, status != .saving else { return }
            status = text == record.methodFeedbackComment?.text ? .saved : .unsavedDraft
        }
        .onChange(of: record.methodFeedbackComment?.revision) { _, revision in
            guard revision != baselineRevision else { return }
            improvementHandoff = nil
            improvementMessage = nil
            if draftText != (record.methodFeedbackComment?.text ?? "") {
                status = .outOfDate
                message = String(localized:
                    "The Method feedback comment changed elsewhere. Your local text remains in the editor."
                )
            } else {
                install(record)
            }
        }
        .alert("Mark This Method Feedback Handled?", isPresented: $confirmsHandled) {
            Button("Cancel", role: .cancel) {}
            Button("Mark Handled") { clearComment() }
        } message: {
            Text("This clears the one current pending Method feedback comment. It does not change the Method or the Researcher Evaluation.")
        }
    }

    private func saveComment() {
        let draft: ResearchMethodFeedbackDraft
        let resultFingerprint: DocumentFingerprint
        do {
            draft = try ResearchMethodFeedbackDraft(
                text: draftText,
                sourceEvaluationRevision:
                    record.methodFeedbackComment?.sourceEvaluationRevision
                        ?? record.researcherEvaluation?.revision
            )
            resultFingerprint = try record.finalizedResultFingerprint()
        } catch {
            status = .saveFailed
            message = error.localizedDescription
            return
        }
        status = .saving
        message = nil
        Task { @MainActor in
            do {
                let updated = try await save(
                    draft,
                    baselineRevision,
                    resultFingerprint
                )
                install(updated)
                didUpdateRecord(updated)
            } catch let error as PortableResearchMethodFeedbackMutationError {
                status = error == .staleCommentRevision
                    || error == .finalizedResultChanged
                    || error == .sourceEvaluationChanged ? .outOfDate : .saveFailed
                message = error.localizedDescription
            } catch {
                status = .saveFailed
                message = error.localizedDescription
            }
        }
    }

    private func clearComment() {
        guard let revision = baselineRevision else { return }
        let resultFingerprint: DocumentFingerprint
        do { resultFingerprint = try record.finalizedResultFingerprint() }
        catch {
            status = .saveFailed
            message = error.localizedDescription
            return
        }
        status = .saving
        Task { @MainActor in
            do {
                let updated = try await clear(revision, resultFingerprint)
                install(updated)
                isEditing = false
                didUpdateRecord(updated)
            } catch let error as PortableResearchMethodFeedbackMutationError {
                status = error == .staleCommentRevision
                    || error == .finalizedResultChanged ? .outOfDate : .saveFailed
                message = error.localizedDescription
            } catch {
                status = .saveFailed
                message = error.localizedDescription
            }
        }
    }

    private func beginMethodImprovement() {
        guard record.methodFeedbackComment != nil else { return }
        isStartingImprovement = true
        improvementMessage = nil
        Task { @MainActor in
            do {
                improvementHandoff = try await startImprovement()
                improvementMessage = String(localized:
                    "The local Method improvement Run is ready. Copy the complete handoff to the Agent."
                )
            } catch {
                improvementMessage = error.localizedDescription
            }
            isStartingImprovement = false
        }
    }

    private func improvementInstructions(
        _ handoff: ResearchAgentHandoff
    ) -> String {
        """
        Continue one Scholium Method improvement Run on this Mac.
        Scholium Run: \(handoff.run.rawValue)
        Pairing Code: \(handoff.pairingCode.rawValue)

        Agent: use the installed `scholium` CLI yourself.
        1. Run `scholium agent pair --run \(handoff.run.rawValue)` and enter the Pairing Code above through standard input.
        2. Run `scholium agent method-context --run \(handoff.run.rawValue)` to receive the exact researcher comment, frozen primary Method, linked Practices, and revisions.
        3. Decide whether the issue concerns the Method or Practice rather than execution, material, provider, request, or preference. Submit at most one exact file replacement, or an explicit no-change/unavailable diagnosis, with `scholium agent improve-method --run \(handoff.run.rawValue) --from <json|->`.
        4. End local access with `scholium agent end --run \(handoff.run.rawValue)`. Do not edit the Method files directly or reuse authority from another Run.
        """
    }

    private func install(_ updated: PortableResearchRecord) {
        baselineRevision = updated.methodFeedbackComment?.revision
        draftText = updated.methodFeedbackComment?.text ?? ""
        status = updated.methodFeedbackComment == nil ? .clean : .saved
        message = nil
        if updated.methodFeedbackComment == nil {
            improvementHandoff = nil
        }
    }
}
