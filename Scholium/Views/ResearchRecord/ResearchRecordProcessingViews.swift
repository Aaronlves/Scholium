import AppKit
import ScholiumApplication
import ScholiumContracts
import ScholiumResearchRecordsFeature
import SwiftUI

struct ResearchRecordResearcherResponseSection: View {
    let record: PortableResearchRecord
    let model: ResearchRecordBrowserModel
    let context: ResearchRecordBrowserContext

    @State private var isPresentingEditor = false
    @State private var isStartingImprovement = false
    @State private var improvementHandoff: ResearchAgentHandoff?
    @State private var improvementError: String?
    @FocusState private var isEditorButtonFocused: Bool
    @FocusState private var isImprovementButtonFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            ResearchRecordEvidenceSectionHeader(
                title: "RESEARCHER RESPONSE",
                identifier: "scholium.researchRecord.responseHeader"
            )

            ResearchRecordEvidenceEntry(
                symbol: record.researcherEvaluation == nil
                    ? "person.crop.circle" : "checkmark.circle",
                title: record.researcherEvaluation == nil
                    ? "Evaluation not recorded" : "Evaluation saved",
                body: evaluationSummary,
                identifier: "scholium.researchRecord.response.evaluation"
            )
            ResearchRecordEvidenceEntry(
                symbol: record.methodFeedbackComment == nil
                    ? "text.bubble" : "checkmark.circle",
                title: record.methodFeedbackComment == nil
                    ? "No Method feedback" : "Method Feedback saved",
                body: methodFeedbackSummary,
                identifier: "scholium.researchRecord.response.methodFeedback"
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    responseControls
                }
                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.inlineControlGap
                ) {
                    responseControls
                }
            }

            if let improvementError {
                Text(improvementError)
                    .font(ScholiumTypography.interface(.compact))
                    .scholiumForeground(.destructive)
                    .textSelection(.enabled)
                    .accessibilityIdentifier(
                        "scholium.researchRecord.response.improvementError"
                    )
            }
        }
        .sheet(isPresented: $isPresentingEditor, onDismiss: restoreEditorFocus) {
            ResearcherResponseEditorSheet(
                record: record,
                save: { draft, evaluationRevision, feedbackRevision, fingerprint in
                    try await context.saveResponse(
                        record.id,
                        draft,
                        evaluationRevision,
                        feedbackRevision,
                        fingerprint
                    )
                },
                reload: { try await context.reloadRecord(record.id) },
                didUpdateRecord: model.acceptUpdatedRecord
            )
        }
        .sheet(
            isPresented: Binding(
                get: { improvementHandoff != nil },
                set: { if !$0 { improvementHandoff = nil } }
            ),
            onDismiss: restoreImprovementFocus
        ) {
            if let improvementHandoff {
                ResearchMethodImprovementHandoffSheet(handoff: improvementHandoff)
            }
        }
    }

    private var evaluationSummary: String {
        guard let evaluation = record.researcherEvaluation else {
            return String(localized: "Add your judgment of the result without changing the Agent's finalized work.")
        }
        var parts: [String] = []
        if evaluation.noIssuesObserved {
            parts.append(String(localized: "No issue marked in this evaluation scope"))
        }
        if !evaluation.observedIssues.isEmpty {
            parts.append(String(localized: "\(evaluation.observedIssues.count) observed issues"))
        }
        if evaluation.valuableDiscovery { parts.append(String(localized: "Valuable discovery")) }
        if evaluation.note != nil { parts.append(String(localized: "Researcher note")) }
        return parts.joined(separator: " · ")
    }

    private var methodFeedbackSummary: String {
        record.methodFeedbackComment?.text
            ?? String(localized: "Add a bounded comment only when the Method itself needs attention.")
    }

    @ViewBuilder
    private var responseControls: some View {
        Button("Edit Response…") { isPresentingEditor = true }
            .buttonStyle(.borderedProminent)
            .scholiumActivationFocus(
                $isEditorButtonFocused,
                presentation: .native
            )
            .accessibilityHint(
                "Edits Researcher Evaluation and Method Feedback together"
            )
            .accessibilityIdentifier("scholium.researchRecord.response.edit")

        if record.methodFeedbackComment != nil {
            Button("Improve Current Method…") { startMethodImprovement() }
                .disabled(isStartingImprovement)
                .scholiumActivationFocus(
                    $isImprovementButtonFocused,
                    presentation: .native
                )
                .accessibilityHint(
                    "Starts a separate paired Method improvement Run from the saved feedback"
                )
                .accessibilityIdentifier(
                    "scholium.researchRecord.response.improveMethod"
                )
        }
        if isStartingImprovement {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Preparing Method improvement")
        }
    }

    private func startMethodImprovement() {
        guard record.methodFeedbackComment != nil, !isStartingImprovement else { return }
        improvementError = nil
        isStartingImprovement = true
        Task { @MainActor in
            defer { isStartingImprovement = false }
            do {
                improvementHandoff = try await context.startMethodImprovement(record.id)
            } catch {
                improvementError = error.localizedDescription
            }
        }
    }

    private func restoreEditorFocus() {
        Task { @MainActor in
            await Task.yield()
            isEditorButtonFocused = true
        }
    }

    private func restoreImprovementFocus() {
        Task { @MainActor in
            await Task.yield()
            isImprovementButtonFocused = true
        }
    }
}

private struct ResearcherResponseContent: Equatable {
    var issues: Set<PortableResearchObservedIssue>
    var noIssuesObserved: Bool
    var valuableDiscovery: Bool
    var evaluationNote: String
    var methodFeedback: String

    init(record: PortableResearchRecord) {
        issues = Set(record.researcherEvaluation?.observedIssues ?? [])
        noIssuesObserved = record.researcherEvaluation?.noIssuesObserved ?? false
        valuableDiscovery = record.researcherEvaluation?.valuableDiscovery ?? false
        evaluationNote = record.researcherEvaluation?.note ?? ""
        methodFeedback = record.methodFeedbackComment?.text ?? ""
    }

    static let empty = ResearcherResponseContent(
        issues: [],
        noIssuesObserved: false,
        valuableDiscovery: false,
        evaluationNote: "",
        methodFeedback: ""
    )

    private init(
        issues: Set<PortableResearchObservedIssue>,
        noIssuesObserved: Bool,
        valuableDiscovery: Bool,
        evaluationNote: String,
        methodFeedback: String
    ) {
        self.issues = issues
        self.noIssuesObserved = noIssuesObserved
        self.valuableDiscovery = valuableDiscovery
        self.evaluationNote = evaluationNote
        self.methodFeedback = methodFeedback
    }
}

enum ResearcherResponseEditorStatus: Equatable {
    case clean
    case unsaved
    case saving
    case saved
    case outOfDate
    case saveFailed

    var title: LocalizedStringResource {
        switch self {
        case .clean: "No Changes"
        case .unsaved: "Unsaved Draft"
        case .saving: "Saving"
        case .saved: "Saved"
        case .outOfDate: "Out of Date"
        case .saveFailed: "Save Failed"
        }
    }

    var symbol: String {
        switch self {
        case .clean: "circle"
        case .unsaved: "pencil.circle"
        case .saving: "arrow.triangle.2.circlepath"
        case .saved: "checkmark.circle"
        case .outOfDate: "exclamationmark.arrow.triangle.2.circlepath"
        case .saveFailed: "exclamationmark.circle"
        }
    }

    var colorRole: ScholiumColorRole {
        switch self {
        case .outOfDate, .saveFailed: .destructive
        case .unsaved: .attention
        case .clean, .saving, .saved: .secondaryText
        }
    }

    static func afterMutationFailure(_ error: Error) -> Self {
        if error is PortableResearcherResponseMutationError {
            return .outOfDate
        }
        if let applicationError = error as? ScholiumApplicationError,
           applicationError.mutationRequiresReconciliation {
            return .outOfDate
        }
        return .saveFailed
    }

    func afterDraftChange(isDirty: Bool) -> Self {
        switch self {
        case .saving, .outOfDate:
            self
        case .clean, .unsaved, .saved, .saveFailed:
            isDirty ? .unsaved : .clean
        }
    }

    var permitsMutation: Bool { self != .saving && self != .outOfDate }
}

private struct ResearcherResponseEditorSheet: View {
    typealias Save = @MainActor (
        ResearcherResponseDraft,
        UUID?,
        UUID?,
        DocumentFingerprint
    ) async throws -> PortableResearchRecord
    typealias Reload = @MainActor () async throws -> PortableResearchRecord

    @Environment(\.dismiss) private var dismiss

    let record: PortableResearchRecord
    let save: Save
    let reload: Reload
    let didUpdateRecord: (PortableResearchRecord) -> Void

    @State private var content: ResearcherResponseContent
    @State private var baseline: ResearcherResponseContent
    @State private var evaluationRevision: UUID?
    @State private var feedbackRevision: UUID?
    @State private var resultFingerprint: DocumentFingerprint?
    @State private var status: ResearcherResponseEditorStatus
    @State private var statusMessage: String?
    @State private var operationInFlight = false
    @State private var confirmsDiscard = false
    @State private var confirmsReload = false
    @State private var confirmsClearEvaluation = false
    @State private var confirmsClearFeedback = false
    @State private var confirmsClearingOnSave = false
    @State private var authorizedEvaluationClear = false
    @State private var authorizedFeedbackClear = false

    init(
        record: PortableResearchRecord,
        save: @escaping Save,
        reload: @escaping Reload,
        didUpdateRecord: @escaping (PortableResearchRecord) -> Void
    ) {
        self.record = record
        self.save = save
        self.reload = reload
        self.didUpdateRecord = didUpdateRecord
        let initial = ResearcherResponseContent(record: record)
        _content = State(initialValue: initial)
        _baseline = State(initialValue: initial)
        _evaluationRevision = State(initialValue: record.researcherEvaluation?.revision)
        _feedbackRevision = State(initialValue: record.methodFeedbackComment?.revision)
        _resultFingerprint = State(initialValue: try? record.finalizedResultFingerprint())
        _status = State(initialValue: .clean)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScholiumStructuralRule()
            ScrollView {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                    evaluationEditor
                    ScholiumStructuralRule()
                    methodFeedbackEditor
                    if let statusMessage {
                        Text(statusMessage)
                            .font(ScholiumTypography.interface(.compact))
                            .scholiumForeground(
                                status == .outOfDate || status == .saveFailed
                                    ? .destructive : .secondaryText
                            )
                            .textSelection(.enabled)
                            .accessibilityIdentifier(
                                "scholium.researchResponse.message"
                            )
                    }
                }
                .padding(ScholiumMetrics.ResearchSheet.contentInset)
            }
            ScholiumStructuralRule()
            footer
        }
        .frame(
            minWidth: ScholiumMetrics.ResearchSheet.ResearcherResponse.minimumWidth,
            idealWidth: ScholiumMetrics.ResearchSheet.ResearcherResponse.idealWidth,
            minHeight: ScholiumMetrics.ResearchSheet.ResearcherResponse.minimumHeight,
            idealHeight: ScholiumMetrics.ResearchSheet.ResearcherResponse.idealHeight
        )
        .scholiumSurface(.document)
        .interactiveDismissDisabled(isDirty || operationInFlight)
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.researchResponse.sheet")
        .onChange(of: content) { _, _ in
            let nextStatus = status.afterDraftChange(isDirty: isDirty)
            if nextStatus != status {
                status = nextStatus
                statusMessage = nil
            }
        }
        .onChange(of: externalRevisionToken) { _, token in
            guard token != baselineRevisionToken else { return }
            status = .outOfDate
            statusMessage = String(localized: "The saved Researcher Response changed elsewhere. Your local draft remains here until you reload or close it.")
        }
        .alert("Discard the Unsaved Response?", isPresented: $confirmsDiscard) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard Draft and Close", role: .destructive) { dismiss() }
        } message: {
            Text("The saved Researcher Response and finalized Agent result remain unchanged.")
        }
        .confirmationDialog(
            "Discard This Draft and Reload?",
            isPresented: $confirmsReload,
            titleVisibility: .visible
        ) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard Draft and Reload", role: .destructive) { reloadResponse() }
        } message: {
            Text("The current saved Researcher Response will replace this local draft.")
        }
        .confirmationDialog(
            "Clear the Saved Evaluation from This Draft?",
            isPresented: $confirmsClearEvaluation,
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Evaluation", role: .destructive) {
                authorizedEvaluationClear = true
                content.issues = []
                content.noIssuesObserved = false
                content.valuableDiscovery = false
                content.evaluationNote = ""
            }
        } message: {
            Text("The Evaluation is removed only when you choose Save Response.")
        }
        .confirmationDialog(
            "Clear the Saved Method Feedback from This Draft?",
            isPresented: $confirmsClearFeedback,
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Method Feedback", role: .destructive) {
                authorizedFeedbackClear = true
                content.methodFeedback = ""
            }
        } message: {
            Text("The Method Feedback is removed only when you choose Save Response.")
        }
        .confirmationDialog(
            "Clear Saved Response Content?",
            isPresented: $confirmsClearingOnSave,
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Clear and Save", role: .destructive) {
                if removesSavedEvaluation { authorizedEvaluationClear = true }
                if removesSavedFeedback { authorizedFeedbackClear = true }
                saveResponse()
            }
        } message: {
            Text("Saving this draft will remove one or more saved Researcher Response sections. The Agent result remains unchanged.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.headerDetailSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text("Researcher Response")
                    .font(ScholiumTypography.interface(.primaryTitle))
                    .accessibilityHeading(.h1)
                Spacer(minLength: 0)
                Label(status.title, systemImage: status.symbol)
                    .font(ScholiumTypography.interface(.small, emphasis: .strong))
                    .scholiumForeground(status.colorRole)
                    .accessibilityIdentifier("scholium.researchResponse.status")
            }
            Text("Record your judgment first, then any bounded feedback about the Method. Both are saved together without changing the Agent's finalized result.")
                .font(ScholiumTypography.interface(.compact))
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ScholiumMetrics.ResearchSheet.contentInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var evaluationEditor: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
            HStack(alignment: .firstTextBaseline) {
                Text("RESEARCHER EVALUATION")
                    .scholiumApparatusHeadingStyle()
                    .accessibilityHeading(.h2)
                Spacer()
                if evaluationRevision != nil {
                    Button("Clear Evaluation…") { confirmsClearEvaluation = true }
                        .disabled(operationInFlight)
                }
            }
            Text("Observed Issues")
                .font(ScholiumTypography.interface(.sectionTitle))
            issueControls

            Text("Evaluation Note")
                .font(ScholiumTypography.interface(.sectionTitle))
            TextEditor(text: $content.evaluationNote)
                .font(ScholiumTypography.scholarly(.body))
                .frame(
                    minHeight: ScholiumMetrics.ResearchSheet.ResearcherResponse.editorMinimumHeight,
                    idealHeight: ScholiumMetrics.ResearchSheet.ResearcherResponse.editorIdealHeight
                )
                .scrollContentBackground(.hidden)
                .padding(ScholiumMetrics.ResearchSheet.textEditorInset)
                .background(ScholiumColorRole.documentBackground.color)
                .overlay { editorBorder }
                .accessibilityLabel("Evaluation Note")
                .accessibilityIdentifier("scholium.researchResponse.evaluationNote")
        }
        .disabled(operationInFlight)
    }

    private var methodFeedbackEditor: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
            HStack(alignment: .firstTextBaseline) {
                Text("METHOD FEEDBACK")
                    .scholiumApparatusHeadingStyle()
                    .accessibilityHeading(.h2)
                Spacer()
                if feedbackRevision != nil {
                    Button("Clear Method Feedback…") { confirmsClearFeedback = true }
                        .disabled(operationInFlight)
                }
            }
            Text("Optional. Describe a problem with the Method itself; execution or source-result judgments belong in the Evaluation above.")
                .font(ScholiumTypography.interface(.compact))
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $content.methodFeedback)
                .font(ScholiumTypography.scholarly(.body))
                .frame(
                    minHeight: ScholiumMetrics.ResearchSheet.ResearcherResponse.editorMinimumHeight,
                    idealHeight: ScholiumMetrics.ResearchSheet.ResearcherResponse.editorIdealHeight
                )
                .scrollContentBackground(.hidden)
                .padding(ScholiumMetrics.ResearchSheet.textEditorInset)
                .background(ScholiumColorRole.documentBackground.color)
                .overlay { editorBorder }
                .accessibilityLabel("Method Feedback")
                .accessibilityIdentifier("scholium.researchResponse.methodFeedback")
        }
        .disabled(operationInFlight)
    }

    private var editorBorder: some View {
        RoundedRectangle(
            cornerRadius: ScholiumShape.editorialControlCornerRadius,
            style: .continuous
        )
        .stroke(ScholiumColorRole.separator.color, lineWidth: 0.5)
    }

    private var issueControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(
                alignment: .top,
                spacing: ScholiumGrid.Spacing.sectionSeparation
            ) {
                issueColumn(Array(PortableResearchObservedIssue.allCases.prefix(4)))
                issueColumn(Array(PortableResearchObservedIssue.allCases.dropFirst(4)))
            }
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                ForEach(PortableResearchObservedIssue.allCases, id: \.self) { issue in
                    issueToggle(issue)
                }
                responseSummaryToggles
            }
        }
    }

    private func issueColumn(
        _ issues: [PortableResearchObservedIssue]
    ) -> some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            ForEach(issues, id: \.self) { issue in
                issueToggle(issue)
            }
            if issues.last == PortableResearchObservedIssue.allCases.last {
                responseSummaryToggles
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func issueToggle(_ issue: PortableResearchObservedIssue) -> some View {
        Toggle(issueTitle(issue), isOn: issueBinding(issue))
            .toggleStyle(.checkbox)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var responseSummaryToggles: some View {
        Group {
            Toggle(
                "No issue marked in this evaluation scope",
                isOn: Binding(
                    get: { content.noIssuesObserved },
                    set: { selected in
                        content.noIssuesObserved = selected
                        if selected { content.issues.removeAll() }
                    }
                )
            )
            .toggleStyle(.checkbox)
            Toggle("Valuable Discovery", isOn: $content.valuableDiscovery)
                .toggleStyle(.checkbox)
        }
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                responseFooterControls
            }
            VStack(
                alignment: .trailing,
                spacing: ScholiumGrid.Spacing.inlineControlGap
            ) {
                if status == .outOfDate {
                    Button("Reload Saved Response…") {
                        if isDirty { confirmsReload = true } else { reloadResponse() }
                    }
                    .disabled(operationInFlight)
                }
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    Spacer(minLength: 0)
                    if operationInFlight {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(
                                status == .saving
                                    ? "Saving Response" : "Reloading Response"
                            )
                    }
                    Button("Cancel", action: attemptDismiss)
                        .keyboardShortcut(.cancelAction)
                        .disabled(operationInFlight)
                    Button("Save Response", action: saveResponse)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!isDirty || operationInFlight || status == .outOfDate)
                        .accessibilityIdentifier("scholium.researchResponse.save")
                }
            }
        }
        .padding(ScholiumMetrics.ResearchSheet.contentInset)
    }

    @ViewBuilder
    private var responseFooterControls: some View {
        if status == .outOfDate {
            Button("Reload Saved Response…") {
                if isDirty { confirmsReload = true } else { reloadResponse() }
            }
            .disabled(operationInFlight)
        }
        Spacer(minLength: 0)
        if operationInFlight {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(status == .saving ? "Saving Response" : "Reloading Response")
        }
        Button("Cancel", action: attemptDismiss)
            .keyboardShortcut(.cancelAction)
            .disabled(operationInFlight)
        Button("Save Response", action: saveResponse)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!isDirty || operationInFlight || status == .outOfDate)
            .accessibilityIdentifier("scholium.researchResponse.save")
    }

    private var isDirty: Bool { content != baseline }

    private var baselineRevisionToken: String {
        "\(evaluationRevision?.uuidString ?? "nil"):" +
            "\(feedbackRevision?.uuidString ?? "nil")"
    }

    private var externalRevisionToken: String {
        "\(record.researcherEvaluation?.revision.uuidString ?? "nil"):" +
            "\(record.methodFeedbackComment?.revision.uuidString ?? "nil")"
    }

    private var hasEvaluationContent: Bool {
        !content.issues.isEmpty
            || content.noIssuesObserved
            || content.valuableDiscovery
            || !content.evaluationNote.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
    }

    private func issueBinding(
        _ issue: PortableResearchObservedIssue
    ) -> Binding<Bool> {
        Binding(
            get: { content.issues.contains(issue) },
            set: { selected in
                if selected {
                    content.issues.insert(issue)
                    content.noIssuesObserved = false
                } else {
                    content.issues.remove(issue)
                }
            }
        )
    }

    private func saveResponse() {
        guard isDirty, !operationInFlight, status != .outOfDate,
              let resultFingerprint else { return }
        if (removesSavedEvaluation && !authorizedEvaluationClear)
            || (removesSavedFeedback && !authorizedFeedbackClear) {
            confirmsClearingOnSave = true
            return
        }
        let draft: ResearcherResponseDraft
        do {
            let evaluation = hasEvaluationContent
                ? try ResearcherEvaluationDraft(
                    observedIssues: PortableResearchObservedIssue.allCases.filter(
                        content.issues.contains
                    ),
                    noIssuesObserved: content.noIssuesObserved,
                    valuableDiscovery: content.valuableDiscovery,
                    note: content.evaluationNote
                )
                : nil
            draft = try ResearcherResponseDraft(
                evaluation: evaluation,
                methodFeedbackText: content.methodFeedback
            )
        } catch {
            status = .saveFailed
            statusMessage = error.localizedDescription
            return
        }
        status = .saving
        statusMessage = nil
        operationInFlight = true
        let expectedEvaluation = evaluationRevision
        let expectedFeedback = feedbackRevision
        Task { @MainActor in
            defer { operationInFlight = false }
            do {
                let updated = try await save(
                    draft,
                    expectedEvaluation,
                    expectedFeedback,
                    resultFingerprint
                )
                install(updated)
                status = .saved
                didUpdateRecord(updated)
                dismiss()
            } catch {
                status = .afterMutationFailure(error)
                statusMessage = error.localizedDescription
            }
        }
    }

    private func reloadResponse() {
        guard !operationInFlight else { return }
        operationInFlight = true
        statusMessage = nil
        Task { @MainActor in
            defer { operationInFlight = false }
            do {
                let updated = try await reload()
                install(updated)
                didUpdateRecord(updated)
            } catch {
                status = .outOfDate
                statusMessage = error.localizedDescription
            }
        }
    }

    private func install(_ updated: PortableResearchRecord) {
        let installed = ResearcherResponseContent(record: updated)
        content = installed
        baseline = installed
        evaluationRevision = updated.researcherEvaluation?.revision
        feedbackRevision = updated.methodFeedbackComment?.revision
        authorizedEvaluationClear = false
        authorizedFeedbackClear = false
        resultFingerprint = try? updated.finalizedResultFingerprint()
        status = .clean
        statusMessage = nil
    }

    private var removesSavedEvaluation: Bool {
        evaluationRevision != nil && !hasEvaluationContent
    }

    private var removesSavedFeedback: Bool {
        feedbackRevision != nil
            && content.methodFeedback.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
    }

    private func attemptDismiss() {
        if isDirty { confirmsDiscard = true } else { dismiss() }
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

enum ResearchRecordChangeDecisionFailureRecovery: Equatable {
    case retry
    case reloadRequired

    static func after(_ error: Error) -> Self {
        if error is PortableResearcherReviewMutationError {
            return .reloadRequired
        }
        if let applicationError = error as? ScholiumApplicationError,
           applicationError.mutationRequiresReconciliation {
            return .reloadRequired
        }
        return .retry
    }
}

struct ResearchRecordChangeDecisionSection: View {
    let record: PortableResearchRecord
    let model: ResearchRecordBrowserModel
    let context: ResearchRecordBrowserContext
    let canDirectlyUndo: Bool

    @State private var reviewState: ResearchRecordChangeReviewState?
    @State private var isLoading = false
    @State private var isMutating = false
    @State private var isReloading = false
    @State private var isReloadRequired = false
    @State private var errorMessage: String?
    @State private var confirmsFinishCurrentState = false
    @State private var isPresentingComparison = false
    @FocusState private var isComparisonButtonFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            ResearchRecordEvidenceSectionHeader(
                title: "CHANGE DECISION",
                identifier: "scholium.researchRecord.changeDecisionHeader"
            )

            ResearchRecordEvidenceEntry(
                symbol: decisionSymbol,
                title: decisionTitle,
                body: decisionDetail,
                identifier: "scholium.researchRecord.changeDecision.status"
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    changeDecisionControls
                }
                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.inlineControlGap
                ) {
                    if !record.confirmedChanges.isEmpty {
                        compareChangesButton
                    }
                    if !record.researcherReviewIsComplete {
                        decisionButton
                    }
                    if isLoading || isMutating || isReloading {
                        ProgressView().controlSize(.small)
                    }
                }
            }

            if let errorMessage {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.inlineControlGap
                ) {
                    Text(errorMessage)
                        .font(ScholiumTypography.interface(.compact))
                        .scholiumForeground(.destructive)
                        .textSelection(.enabled)
                        .accessibilityIdentifier(
                            "scholium.researchRecord.changeDecision.error"
                        )
                    if isReloadRequired {
                        Button("Reload Result", action: reloadResult)
                            .disabled(isReloading || isMutating)
                            .accessibilityIdentifier(
                                "scholium.researchRecord.changeDecision.reload"
                            )
                    }
                }
            }
        }
        .task(id: reviewTaskID) { await loadReviewState() }
        .sheet(
            isPresented: $isPresentingComparison,
            onDismiss: restoreComparisonFocus
        ) {
            if let reviewState {
                ResearchRecordComparisonSheet(
                    record: record,
                    initialReviewState: reviewState,
                    canDirectlyUndo: canDirectlyUndo,
                    loadComparison: context.comparison,
                    loadReviewState: context.changeReviewState,
                    undo: context.undoChanges,
                    didUpdateRecord: model.acceptUpdatedRecord
                )
            }
        }
        .confirmationDialog(
            "Finish Review with the Current Source State?",
            isPresented: $confirmsFinishCurrentState,
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Finish Review") { finishReview() }
        } message: {
            Text("Later edits, restored revisions, and unavailable documents will be recorded as source facts. No source file will be changed.")
        }
    }

    @ViewBuilder
    private var decisionButton: some View {
        if record.confirmedChanges.isEmpty {
            Button("Finish Review") { finishReview() }
                .buttonStyle(.bordered)
                .disabled(isLoading || isMutating || isReloading || isReloadRequired)
                .accessibilityIdentifier(
                    "scholium.researchRecord.changeDecision.finish"
                )
        } else if everyDocumentIsAgentEndingRevision {
            Button("Keep Agent Changes") { keepChanges() }
                .buttonStyle(.bordered)
                .disabled(isLoading || isMutating || isReloading || isReloadRequired)
                .accessibilityIdentifier(
                    "scholium.researchRecord.changeDecision.keep"
                )
        } else {
            Button("Finish Review with Current State…") {
                confirmsFinishCurrentState = true
            }
            .buttonStyle(.bordered)
            .disabled(
                isLoading || isMutating || isReloading || isReloadRequired
                    || reviewState == nil
            )
            .accessibilityIdentifier(
                "scholium.researchRecord.changeDecision.finishCurrent"
            )
        }
    }

    @ViewBuilder
    private var changeDecisionControls: some View {
        if !record.confirmedChanges.isEmpty { compareChangesButton }
        Spacer(minLength: 0)
        if isLoading || isMutating || isReloading {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(
                    isLoading
                        ? "Checking source changes"
                        : isReloading ? "Reloading Result" : "Saving change decision"
                )
        }
        if !record.researcherReviewIsComplete { decisionButton }
    }

    private var compareChangesButton: some View {
        Button("Compare Changes…") { isPresentingComparison = true }
            .disabled(
                reviewState == nil || isMutating || isReloading
                    || isReloadRequired
            )
            .scholiumActivationFocus(
                $isComparisonButtonFocused,
                presentation: .native
            )
            .accessibilityIdentifier(
                "scholium.researchRecord.changeDecision.compare"
            )
    }

    private func restoreComparisonFocus() {
        Task { @MainActor in
            await Task.yield()
            isComparisonButtonFocused = true
        }
    }

    private var reviewTaskID: String {
        "\(record.id.uuidString):" +
            "\(record.researcherReviewDisposition?.revision.uuidString ?? "nil")"
    }

    private var everyDocumentIsAgentEndingRevision: Bool {
        guard let reviewState, !reviewState.documents.isEmpty else { return false }
        return reviewState.documents.allSatisfy {
            $0.status == .agentEndingRevision
        }
    }

    private var decisionSymbol: String {
        if record.researcherReviewIsComplete { return "checkmark.circle" }
        if isLoading { return "arrow.triangle.2.circlepath" }
        if record.confirmedChanges.isEmpty { return "checkmark.seal" }
        return "arrow.uturn.backward.circle"
    }

    private var decisionTitle: String {
        if record.researcherReviewIsComplete {
            return String(localized: "Review complete")
        }
        if record.confirmedChanges.isEmpty {
            return String(localized: "No source changes to decide")
        }
        return String(localized: "\(record.confirmedChanges.count) changes need a decision")
    }

    private var decisionDetail: String {
        if record.researcherReviewIsComplete {
            return String(localized: "Every confirmed source change has a recorded factual outcome.")
        }
        if record.confirmedChanges.isEmpty {
            return String(localized: "Finish Review to mark this no-change result as handled.")
        }
        if canDirectlyUndo {
            return String(localized: "Keep the Agent revisions, compare them, or restore complete selected documents while this Records window remains open.")
        }
        return String(localized: "Compare the confirmed revisions, then record how the current sources should be treated.")
    }

    private func loadReviewState() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            reviewState = try await context.changeReviewState(record.id)
        } catch is CancellationError {
            return
        } catch {
            reviewState = nil
            errorMessage = error.localizedDescription
        }
    }

    private func keepChanges() {
        mutate { fingerprint in
            try await context.keepChanges(
                record.id,
                record.researcherReviewDisposition?.revision,
                fingerprint
            )
        }
    }

    private func finishReview() {
        mutate { fingerprint in
            try await context.finishReview(
                record.id,
                record.researcherReviewDisposition?.revision,
                fingerprint
            )
        }
    }

    private func mutate(
        _ operation: @escaping @MainActor (
            DocumentFingerprint
        ) async throws -> PortableResearchRecord
    ) {
        guard !isMutating, !isReloading, !isReloadRequired else { return }
        let fingerprint: DocumentFingerprint
        do { fingerprint = try record.finalizedResultFingerprint() }
        catch {
            errorMessage = error.localizedDescription
            return
        }
        isMutating = true
        errorMessage = nil
        Task { @MainActor in
            defer { isMutating = false }
            do {
                let updated = try await operation(fingerprint)
                model.acceptUpdatedRecord(updated)
                reviewState = try await context.changeReviewState(updated.id)
            } catch {
                errorMessage = error.localizedDescription
                isReloadRequired =
                    ResearchRecordChangeDecisionFailureRecovery.after(error)
                        == .reloadRequired
            }
        }
    }

    private func reloadResult() {
        guard isReloadRequired, !isReloading, !isMutating else { return }
        isReloading = true
        Task { @MainActor in
            defer { isReloading = false }
            do {
                let updated = try await context.reloadRecord(record.id)
                guard updated.id == record.id else {
                    throw PortableResearcherReviewMutationError.recordUnavailable
                }
                let state = try await context.changeReviewState(updated.id)
                model.acceptUpdatedRecord(updated)
                reviewState = state
                isReloadRequired = false
                errorMessage = nil
            } catch {
                isReloadRequired = true
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct ResearchRecordComparisonDocument: Identifiable {
    enum LoadState {
        case loading
        case loaded(ExactSourceComparison)
        case unavailable(String)
    }

    let id: UUID
    let change: PortableResearchConfirmedChange
    let participant: PortableResearchNoteRevision
    var current: ResearchRecordChangeCurrentState
    var loadState: LoadState = .loading
    var undoStatus: ResearchRecordChangeUndoStatus?
}

struct ResearchRecordDirectUndoGrantState: Equatable {
    let finalizedResultFingerprint: DocumentFingerprint
    private(set) var isValid: Bool

    init(
        finalizedResultFingerprint: DocumentFingerprint,
        isValid: Bool
    ) {
        self.finalizedResultFingerprint = finalizedResultFingerprint
        self.isValid = isValid
    }

    @discardableResult
    mutating func reconcile(
        observedFinalizedResultFingerprint: DocumentFingerprint
    ) -> Bool {
        guard isValid else { return false }
        if observedFinalizedResultFingerprint != finalizedResultFingerprint {
            isValid = false
        }
        return isValid
    }
}

private struct ResearchRecordComparisonSheet: View {
    typealias LoadComparison = @MainActor (UUID, UUID) async throws
        -> ExactSourceComparison
    typealias LoadReviewState = @MainActor (UUID) async throws
        -> ResearchRecordChangeReviewState
    typealias Undo = @MainActor (
        UUID,
        Set<UUID>,
        UUID?,
        DocumentFingerprint
    ) async throws -> ResearchRecordChangesUndoResult

    @Environment(\.dismiss) private var dismiss

    let record: PortableResearchRecord
    let initialReviewState: ResearchRecordChangeReviewState
    let loadComparison: LoadComparison
    let loadReviewState: LoadReviewState
    let undo: Undo
    let didUpdateRecord: (PortableResearchRecord) -> Void

    @State private var documents: [ResearchRecordComparisonDocument]
    @State private var expandedDocumentIDs: Set<UUID>
    @State private var selectedDocumentIDs: Set<UUID> = []
    @State private var workingReviewRevision: UUID?
    @State private var directUndoGrant: ResearchRecordDirectUndoGrantState
    @State private var isUndoing = false
    @State private var confirmsUndo = false
    @State private var operationMessage: String?

    init(
        record: PortableResearchRecord,
        initialReviewState: ResearchRecordChangeReviewState,
        canDirectlyUndo: Bool,
        loadComparison: @escaping LoadComparison,
        loadReviewState: @escaping LoadReviewState,
        undo: @escaping Undo,
        didUpdateRecord: @escaping (PortableResearchRecord) -> Void
    ) {
        self.record = record
        self.initialReviewState = initialReviewState
        self.loadComparison = loadComparison
        self.loadReviewState = loadReviewState
        self.undo = undo
        self.didUpdateRecord = didUpdateRecord
        let statesByID = Dictionary(uniqueKeysWithValues:
            initialReviewState.documents.map { ($0.noteID, $0) }
        )
        let mapped: [ResearchRecordComparisonDocument] = record.confirmedChanges
            .compactMap { change -> ResearchRecordComparisonDocument? in
            guard let participant = record.participatingNotes.first(where: {
                $0.noteID == change.noteID
            }), let current = statesByID[change.noteID] else { return nil }
            return ResearchRecordComparisonDocument(
                id: change.noteID,
                change: change,
                participant: participant,
                current: current
            )
        }
        _documents = State(initialValue: mapped)
        _expandedDocumentIDs = State(
            initialValue: mapped.first.map { [$0.id] } ?? []
        )
        _workingReviewRevision = State(initialValue: initialReviewState.reviewRevision)
        _directUndoGrant = State(
            initialValue: ResearchRecordDirectUndoGrantState(
                finalizedResultFingerprint:
                    initialReviewState.finalizedResultFingerprint,
                isValid: canDirectlyUndo
            )
        )
    }

    var body: some View {
        ExactSourceComparisonSheetLayout(
            title: "Compare Changes",
            detail: "Agent changes appear in one unified diff. Select complete documents only when direct undo is available in this window.",
            identifier: "scholium.researchRecord.comparison"
        ) {
            Button("Expand All") {
                expandedDocumentIDs = Set(documents.map(\.id))
            }
            Button("Collapse All") { expandedDocumentIDs.removeAll() }
        } content: {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
                    ForEach($documents) { $document in
                        comparisonDocument($document)
                    }
                    if let operationMessage {
                        Text(operationMessage)
                            .font(ScholiumTypography.interface(.compact))
                            .scholiumForeground(.destructive)
                            .textSelection(.enabled)
                            .accessibilityIdentifier(
                                "scholium.researchRecord.comparison.message"
                            )
                    }
                }
                .padding(ScholiumGrid.Spacing.sectionSeparation)
            }
        } footer: {
            comparisonFooter
        }
        .interactiveDismissDisabled(isUndoing)
        .task { await loadAllComparisons() }
        .confirmationDialog(
            undoConfirmationTitle,
            isPresented: $confirmsUndo,
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Undo Selected Documents", role: .destructive) {
                undoSelectedDocuments()
            }
        } message: {
            Text("Each selected document will be restored to its exact Before Agent Work revision. Later or missing source revisions will not be overwritten.")
        }
    }

    private func comparisonDocument(
        _ document: Binding<ResearchRecordComparisonDocument>
    ) -> some View {
        let value = document.wrappedValue
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                if allowsDirectUndo {
                    Toggle(
                        "Select \(value.participant.title)",
                        isOn: selectionBinding(for: value)
                    )
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .disabled(value.current.status != .agentEndingRevision || isUndoing)
                    .accessibilityIdentifier(
                        "scholium.researchRecord.comparison.select.\(value.id.uuidString)"
                    )
                }
                Button {
                    toggleExpanded(value.id)
                } label: {
                    HStack(alignment: .top, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                        Image(
                            systemName: expandedDocumentIDs.contains(value.id)
                                ? "chevron.down" : "chevron.right"
                        )
                        .font(ScholiumTypography.interface(.small, emphasis: .strong))
                        .scholiumForeground(.secondaryText)
                        .frame(width: ScholiumMetrics.ResearchSheet.Comparison.disclosureIndicatorWidth)
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                            Text(value.participant.title)
                                .font(ScholiumTypography.interface(.rowTitle))
                                .scholiumForeground(.primaryText)
                            Text(value.current.currentRelativePath
                                ?? value.participant.note.relativePath)
                                .font(ScholiumTypography.exact(.small))
                                .scholiumForeground(.secondaryText)
                            Text(documentStatus(value))
                                .font(ScholiumTypography.interface(.small, emphasis: .strong))
                                .scholiumForeground(statusColor(value))
                        }
                        Spacer(minLength: 0)
                        if let revision = value.current.observedRevision {
                            Text(short(revision))
                                .font(ScholiumTypography.exact(.small))
                                .scholiumForeground(.mutedText)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(value.participant.title), "
                        + (value.current.currentRelativePath
                            ?? value.participant.note.relativePath)
                )
                .accessibilityValue(
                    "\(expandedDocumentIDs.contains(value.id) ? String(localized: "Expanded") : String(localized: "Collapsed")), \(documentStatus(value))"
                )
                .accessibilityHint(
                    expandedDocumentIDs.contains(value.id)
                        ? "Collapses this document" : "Expands this document"
                )
            }
            .padding(ScholiumGrid.Spacing.nestedContentInset)

            if expandedDocumentIDs.contains(value.id) {
                ScholiumStructuralRule()
                switch value.loadState {
                case .loading:
                    ScholiumContentStateView(
                        "Preparing Exact Comparison…",
                        indicator: .progress
                    )
                    .frame(
                        minHeight: ScholiumMetrics.ResearchSheet.Comparison.documentStateMinimumHeight
                    )
                case .loaded(let comparison):
                    ExactSourceComparisonView(
                        comparison: comparison,
                        startingLabel: "Before Agent Work",
                        endingLabel: "Agent Revision",
                        startingOnlyLabel: "Before Agent Work only",
                        endingOnlyLabel: "Agent revision only",
                        identifierPrefix:
                            "scholium.researchRecord.comparison.\(value.id.uuidString)"
                    )
                    .padding(ScholiumGrid.Spacing.nestedContentInset)
                case .unavailable(let message):
                    ScholiumContentStateView(
                        "Comparison Unavailable",
                        detail: Text(message),
                        indicator: .symbol("exclamationmark.triangle", role: .attention)
                    )
                    .frame(
                        minHeight: ScholiumMetrics.ResearchSheet.Comparison.documentStateMinimumHeight
                    )
                }
            }
        }
        .background(ScholiumColorRole.documentBackground.color)
        .clipShape(RoundedRectangle(
            cornerRadius: ScholiumShape.editorialControlCornerRadius,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(
                cornerRadius: ScholiumShape.editorialControlCornerRadius,
                style: .continuous
            )
            .stroke(ScholiumColorRole.separator.color, lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            "scholium.researchRecord.comparison.document.\(value.id.uuidString)"
        )
    }

    private var comparisonFooter: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Button("Return to Result", action: dismiss.callAsFunction)
                .keyboardShortcut(.cancelAction)
                .disabled(isUndoing)
            Spacer(minLength: 0)
            if isUndoing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Undoing selected documents")
            }
            if allowsDirectUndo {
                Button("Undo Selected Documents…") { confirmsUndo = true }
                    .disabled(selectedDocumentIDs.isEmpty || isUndoing)
                    .accessibilityIdentifier(
                        "scholium.researchRecord.comparison.undo"
                    )
            }
        }
        .padding(ScholiumGrid.Spacing.sectionSeparation)
    }

    private var undoConfirmationTitle: String {
        selectedDocumentIDs.count == 1
            ? String(localized: "Undo the Selected Document?")
            : String(localized: "Undo \(selectedDocumentIDs.count) Selected Documents?")
    }

    private func selectionBinding(
        for document: ResearchRecordComparisonDocument
    ) -> Binding<Bool> {
        Binding(
            get: { selectedDocumentIDs.contains(document.id) },
            set: { selected in
                if selected { selectedDocumentIDs.insert(document.id) }
                else { selectedDocumentIDs.remove(document.id) }
            }
        )
    }

    private func toggleExpanded(_ id: UUID) {
        if expandedDocumentIDs.contains(id) { expandedDocumentIDs.remove(id) }
        else { expandedDocumentIDs.insert(id) }
    }

    private func loadAllComparisons() async {
        for index in documents.indices {
            guard !Task.isCancelled else { return }
            do {
                let comparison = try await loadComparison(record.id, documents[index].id)
                try Task.checkCancellation()
                documents[index].loadState = .loaded(comparison)
            } catch is CancellationError {
                return
            } catch {
                documents[index].loadState = .unavailable(error.localizedDescription)
            }
        }
    }

    private func undoSelectedDocuments() {
        let selected = selectedDocumentIDs
        guard allowsDirectUndo, !selected.isEmpty, !isUndoing else { return }
        isUndoing = true
        operationMessage = nil
        Task { @MainActor in
            defer { isUndoing = false }
            do {
                let result = try await undo(
                    record.id,
                    selected,
                    workingReviewRevision,
                    directUndoGrant.finalizedResultFingerprint
                )
                didUpdateRecord(result.record)
                workingReviewRevision = result.record
                    .researcherReviewDisposition?.revision
                guard directUndoGrant.reconcile(
                    observedFinalizedResultFingerprint:
                        try result.record.finalizedResultFingerprint()
                ) else {
                    selectedDocumentIDs.removeAll()
                    operationMessage = String(localized: "The finalized Agent result changed. Return to the Result before continuing.")
                    return
                }
                for outcome in result.documents {
                    guard let index = documents.firstIndex(where: {
                        $0.id == outcome.noteID
                    }) else { continue }
                    documents[index].undoStatus = outcome.status
                }
                let allSucceeded = result.documents.count == selected.count
                    && result.documents.allSatisfy {
                        $0.status == .restored
                            || $0.status == .alreadyAtStartingRevision
                    }
                if allSucceeded {
                    dismiss()
                    return
                }
                selectedDocumentIDs.removeAll()
                operationMessage = String(localized: "Some selected documents were not restored. Review each document's current state before trying another action.")
                let state = try await loadReviewState(record.id)
                if !directUndoGrant.reconcile(
                    observedFinalizedResultFingerprint:
                        state.finalizedResultFingerprint
                ) {
                    selectedDocumentIDs.removeAll()
                }
                workingReviewRevision = state.reviewRevision
                for current in state.documents {
                    guard let index = documents.firstIndex(where: {
                        $0.id == current.noteID
                    }) else { continue }
                    documents[index].current = current
                }
            } catch {
                operationMessage = error.localizedDescription
                selectedDocumentIDs.removeAll()
                do {
                    let state = try await loadReviewState(record.id)
                    if !directUndoGrant.reconcile(
                        observedFinalizedResultFingerprint:
                            state.finalizedResultFingerprint
                    ) {
                        selectedDocumentIDs.removeAll()
                    }
                    workingReviewRevision = state.reviewRevision
                    for current in state.documents {
                        guard let index = documents.firstIndex(where: {
                            $0.id == current.noteID
                        }) else { continue }
                        documents[index].current = current
                        documents[index].undoStatus = nil
                    }
                } catch {
                    operationMessage = [
                        operationMessage,
                        error.localizedDescription
                    ].compactMap { $0 }.joined(separator: "\n\n")
                }
            }
        }
    }

    private var allowsDirectUndo: Bool { directUndoGrant.isValid }

    private func documentStatus(
        _ document: ResearchRecordComparisonDocument
    ) -> String {
        if let undoStatus = document.undoStatus {
            switch undoStatus {
            case .restored: return String(localized: "Restored to Before Agent Work")
            case .alreadyAtStartingRevision:
                return String(localized: "Already at Before Agent Work")
            case .conflict: return String(localized: "Changed since Agent revision")
            case .unavailable: return String(localized: "Source unavailable")
            case .commitUncertain: return String(localized: "Restore outcome uncertain")
            }
        }
        return switch document.current.status {
        case .agentEndingRevision: String(localized: "Agent revision is current")
        case .startingRevision: String(localized: "Before Agent Work is current")
        case .superseded: String(localized: "Changed after Agent work")
        case .unavailable: String(localized: "Source unavailable")
        }
    }

    private func statusColor(
        _ document: ResearchRecordComparisonDocument
    ) -> ScholiumColorRole {
        if document.undoStatus == .commitUncertain
            || document.undoStatus == .conflict
            || document.undoStatus == .unavailable {
            return .destructive
        }
        return switch document.current.status {
        case .agentEndingRevision, .startingRevision:
            ScholiumColorRole.secondaryText
        case .superseded, .unavailable:
            ScholiumColorRole.attention
        }
    }

    private func short(_ fingerprint: DocumentFingerprint) -> String {
        "\(fingerprint.sha256.prefix(10))…"
    }
}

private struct ResearchMethodImprovementHandoffSheet: View {
    @Environment(\.dismiss) private var dismiss
    let handoff: ResearchAgentHandoff
    @State private var copyMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.headerDetailSpacing) {
                Text("Method Improvement Handoff")
                    .font(ScholiumTypography.interface(.primaryTitle))
                    .accessibilityHeading(.h1)
                Text("This is a separate, short-lived paired Run bound to the saved Method Feedback.")
                    .font(ScholiumTypography.interface(.compact))
                    .scholiumForeground(.secondaryText)
            }
            .padding(ScholiumMetrics.ResearchSheet.contentInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            ScholiumStructuralRule()
            ScrollView {
                Text(instructions)
                    .font(ScholiumTypography.exact(.small))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(ScholiumMetrics.ResearchSheet.contentInset)
            }
            if let copyMessage {
                Text(copyMessage)
                    .font(ScholiumTypography.interface(.compact))
                    .scholiumForeground(.secondaryText)
                    .padding(.horizontal, ScholiumMetrics.ResearchSheet.contentInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ScholiumStructuralRule()
            HStack {
                Button("Copy Handoff") { copyHandoff() }
                Spacer()
                Button("Done", action: dismiss.callAsFunction)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(ScholiumMetrics.ResearchSheet.contentInset)
        }
        .frame(
            minWidth: ScholiumMetrics.ResearchSheet.MethodImprovementHandoff.minimumWidth,
            idealWidth: ScholiumMetrics.ResearchSheet.MethodImprovementHandoff.idealWidth,
            minHeight: ScholiumMetrics.ResearchSheet.MethodImprovementHandoff.minimumHeight,
            idealHeight: ScholiumMetrics.ResearchSheet.MethodImprovementHandoff.idealHeight
        )
        .scholiumSurface(.document)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("scholium.methodImprovement.handoff")
    }

    private var instructions: String {
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

    private func copyHandoff() {
        NSPasteboard.general.clearContents()
        let copied = NSPasteboard.general.setString(instructions, forType: .string)
        copyMessage = copied
            ? String(localized: "Copied the complete Method improvement handoff.")
            : String(localized: "The Method improvement handoff could not be copied.")
    }
}
