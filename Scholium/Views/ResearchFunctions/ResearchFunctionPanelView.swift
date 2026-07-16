import ScholiumContracts
import SwiftUI

struct ResearchFunctionPanelContext {
    let comments: [ResearcherComment]
    let manageComments: () -> Void
    let repairCitationMethod: () -> Void
    let copyInstructions: (String) -> Void
    let dismiss: () -> Void
}

/// Shared presentation root for the editor Strip. It observes only the
/// per-window function controller; Review is supplied through a narrow,
/// immutable adapter so the reusable Human Review view keeps its own record
/// boundary.
struct ResearchFunctionPanelView<ReviewContent: View>: View {
    @ObservedObject private var controller: ResearchFunctionController
    let context: ResearchFunctionPanelContext
    private let reviewContent: ReviewContent

    init(
        controller: ResearchFunctionController,
        context: ResearchFunctionPanelContext,
        @ViewBuilder reviewContent: () -> ReviewContent
    ) {
        self.controller = controller
        self.context = context
        self.reviewContent = reviewContent()
    }

    var body: some View {
        Group {
            if controller.activeFunction == .review {
                reviewPanel
            } else {
                agentPanel
            }
        }
        .frame(minWidth: 560, idealWidth: 680, minHeight: 520, idealHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(panelAccessibilityLabel)
        .accessibilityIdentifier("scholium.researchFunctionPanel")
    }

    private var panelAccessibilityLabel: String {
        guard let function = controller.activeFunction else {
            return "Research function"
        }
        return "\(function.interfaceTitle) function"
    }

    private var reviewPanel: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let target = controller.target {
                        ResearchFunctionTargetSection(target: target)
                    }
                    ResearchFunctionCommentsSection(
                        comments: context.comments,
                        selection: [],
                        permitsSelection: false,
                        manage: context.manageComments,
                        setSelected: { _, _ in }
                    )
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)

            Divider()
            reviewContent
        }
    }

    private var agentPanel: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let target = controller.target {
                        ResearchFunctionTargetSection(target: target)
                    }

                    if controller.phase == .loading {
                        ProgressView("Preparing function…")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        availabilityNotice
                        ResearchFunctionMaterialsSection(
                            candidates: controller.materialCandidates,
                            selection: controller.selectedMaterialIDs,
                            setSelected: controller.setMaterialSelected
                        )
                        ResearchFunctionScopeSection(
                            selection: controller.scopeKind,
                            passageIsAvailable: controller.passageIsAvailable,
                            select: controller.setScope
                        )

                        if controller.activeFunction == .critique {
                            ResearchFunctionCommentsSection(
                                comments: context.comments,
                                selection: controller.selectedCommentIDs,
                                permitsSelection: true,
                                manage: context.manageComments,
                                setSelected: controller.setCommentSelected
                            )
                        }

                        if controller.activeFunction == .fidelity {
                            ResearchFunctionFidelitySection(
                                checks: controller.fidelityChecks,
                                availability: Dictionary(
                                    uniqueKeysWithValues: FidelityCheck.allCases.compactMap {
                                        guard let availability = controller.fidelityCheckAvailability($0) else {
                                            return nil
                                        }
                                        return ($0, availability)
                                    }
                                ),
                                setSelected: controller.setFidelityCheck,
                                repairCitationMethod: context.repairCitationMethod
                            )
                        }

                        instructionSection
                        preparationStatus
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let function = controller.activeFunction {
                Image(systemName: function.interfaceSymbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(function.interfaceTitle)
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(controller.target?.title ?? "Research Function")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(18)
    }

    @ViewBuilder
    private var availabilityNotice: some View {
        if let function = controller.activeFunction,
           let availability = controller.availability[function],
           !availability.isEnabled {
            Label(
                availability.repairReasons.first?.interfaceDescription
                    ?? "This function is unavailable.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.callout)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("scholium.researchFunctionUnavailable")
        }
    }

    private var instructionSection: some View {
        ResearchFunctionSection(title: instructionTitle, symbol: "text.alignleft") {
            TextEditor(text: $controller.instruction)
                .font(.body)
                .frame(minHeight: 92, maxHeight: 150)
                .padding(5)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                }
                .accessibilityLabel(instructionTitle)
                .accessibilityIdentifier("scholium.researchFunctionInstruction")
        }
    }

    private var instructionTitle: String {
        controller.activeFunction == .dialogue ? "Question" : "Focus (Optional)"
    }

    @ViewBuilder
    private var preparationStatus: some View {
        if let error = controller.errorMessage {
            Label(error, systemImage: "exclamationmark.octagon")
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("scholium.researchFunctionError")
        }

        if let preparation = controller.preparation {
            let record = controller.presentedRun
                ?? ResearchFunctionRecordProjection(
                    snapshot: preparation.snapshot,
                    completion: preparation.reusedCompletion
                )
            ResearchFunctionSection(
                title: "Run Status",
                symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    ResearchFunctionRunStatusView(record: record, showsFunction: false)
                    if let warning = preparation.derivedRefreshWarning {
                        Label(warning, systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(
                                "scholium.researchFunctionDerivedRefreshWarning"
                            )
                    }
                    Button("Copy Instructions for Agent") {
                        context.copyInstructions(preparation.instructions)
                    }
                    .accessibilityIdentifier("scholium.copyResearchFunctionInstructions")
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(controller.preparation == nil ? "Cancel" : "Done") {
                context.dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Spacer()
            if controller.canCancelPreparedRun {
                Button("Cancel Run", role: .destructive) {
                    controller.cancelPreparedRun()
                }
                .disabled(controller.isBusy)
            } else if controller.preparation == nil {
                Button("Prepare") {
                    controller.prepare()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!controller.canPrepare)
                .accessibilityIdentifier("scholium.prepareResearchFunction")
            }
        }
        .padding(16)
    }

}

/// Read-only status projection for a Function-run envelope. It deliberately
/// does not render Dialogue turns, Critique prose, Human Review, or Comments.
struct ResearchFunctionRunStatusView: View {
    let record: ResearchFunctionRecordProjection
    let showsFunction: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                if showsFunction {
                    Text(record.snapshot.request.function.interfaceTitle)
                        .font(.callout.weight(.semibold))
                }
                Label(statusTitle, systemImage: statusSymbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(statusColor)
                Spacer()
                Text(record.snapshot.preparedAt.formatted(
                    date: .abbreviated,
                    time: .shortened
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(statusDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let completion = record.completion, !completion.summary.isEmpty {
                LabeledContent("Agent-reported completion") {
                    Text(completion.summary)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                .font(.caption)
            }

            if let completion = record.completion,
               !completion.fidelityOutcomes.isEmpty {
                DisclosureGroup("Fidelity Outcomes") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("These are attributed Function-run outcomes, not Human Review or Critique.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(completion.fidelityOutcomes, id: \.check) { outcome in
                            VStack(alignment: .leading, spacing: 3) {
                                Label(
                                    "\(checkTitle(outcome.check)): \(outcomeTitle(outcome.state))",
                                    systemImage: outcomeSymbol(outcome.state)
                                )
                                .font(.caption.weight(.semibold))
                                Text(outcome.summary)
                                    .font(.caption)
                                    .textSelection(.enabled)
                                ForEach(outcome.findings, id: \.self) { finding in
                                    Text("• \(finding)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    .padding(.top, 5)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("scholium.researchFunction.runStatus")
    }

    private var state: ResearchFunctionRunState { record.runState }

    private var statusTitle: String {
        switch state {
        case .prepared: "Prepared"
        case .awaitingFidelity: "Awaiting Fidelity"
        case .complete: "Complete"
        case .unverified: "Unverified"
        case .stale: "Stale"
        case .cancelled: "Cancelled"
        }
    }

    private var statusDescription: String {
        switch state {
        case .prepared:
            "Instructions are prepared for an external agent; no completion has been reported."
        case .awaitingFidelity:
            "Substantive work was reported, but the required final Fidelity phase is still pending."
        case .complete:
            "Required completion evidence is recorded for the reported final revision."
        case .unverified:
            "The reported work does not include all required Fidelity evidence."
        case .stale:
            "Later Target or evidence changes made this recorded outcome stale."
        case .cancelled:
            "This Function run was cancelled."
        }
    }

    private var statusSymbol: String {
        switch state {
        case .prepared: "doc.badge.clock"
        case .awaitingFidelity: "checkmark.shield.badge.questionmark"
        case .complete: "checkmark.circle.fill"
        case .unverified: "questionmark.diamond.fill"
        case .stale: "exclamationmark.arrow.trianglehead.counterclockwise.rotate.90"
        case .cancelled: "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch state {
        case .complete: .green
        case .awaitingFidelity, .unverified, .stale: .orange
        case .cancelled: .red
        case .prepared: .secondary
        }
    }

    private func checkTitle(_ check: FidelityCheck) -> String {
        switch check {
        case .content: "Content"
        case .citations: "Citations"
        }
    }

    private func outcomeTitle(_ state: FidelityCheckOutcomeState) -> String {
        switch state {
        case .passed: "Passed"
        case .issuesFound: "Issues Found"
        case .unavailable: "Unavailable"
        }
    }

    private func outcomeSymbol(_ state: FidelityCheckOutcomeState) -> String {
        switch state {
        case .passed: "checkmark.circle.fill"
        case .issuesFound: "exclamationmark.triangle.fill"
        case .unavailable: "questionmark.circle"
        }
    }
}

struct ResearchFunctionTargetSection: View {
    let target: ResearchFunctionTarget

    var body: some View {
        ResearchFunctionSection(title: "Target", symbol: "scope") {
            VStack(alignment: .leading, spacing: 3) {
                Text(target.title)
                    .font(.body.weight(.medium))
                Text(target.note.relativePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("scholium.researchFunctionTarget")
    }
}

struct ResearchFunctionMaterialsSection: View {
    let candidates: [ResearchFunctionMaterialCandidate]
    let selection: Set<UUID>
    let setSelected: (UUID, Bool) -> Void

    var body: some View {
        ResearchFunctionSection(title: "Materials", symbol: "doc.on.doc") {
            if candidates.isEmpty {
                Text("No additional notes are available. The Target remains the only writable note.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(candidates) { candidate in
                        Toggle(isOn: Binding(
                            get: { selection.contains(candidate.id) },
                            set: { setSelected(candidate.id, $0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.material.title)
                                Text(candidate.material.note.relativePath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(!candidate.isSelectable)
                        .help(candidate.repairReasons.first?.interfaceDescription ?? "Use as read-only Material")
                        .accessibilityLabel(candidate.material.title)
                        .accessibilityHint(materialAccessibilityHint(for: candidate))
                        .accessibilityIdentifier(
                            "scholium.researchFunctionMaterial.\(candidate.material.role.rawValue).\(candidate.material.note.relativePath)"
                        )
                    }
                }
            }
        }
        .accessibilityIdentifier("scholium.researchFunctionMaterials")
    }

    private func materialAccessibilityHint(
        for candidate: ResearchFunctionMaterialCandidate
    ) -> String {
        candidate.repairReasons.first?.interfaceDescription
            ?? "Read-only Material at \(candidate.material.note.relativePath)"
    }
}

struct ResearchFunctionScopeSection: View {
    let selection: ResearchFunctionScopeKind
    let passageIsAvailable: Bool
    let select: (ResearchFunctionScopeKind) -> Void

    var body: some View {
        ResearchFunctionSection(title: "Scope", symbol: "selection.pin.in.out") {
            Picker("Scope", selection: Binding(
                get: { selection },
                set: { newValue in select(newValue) }
            )) {
                Text("Whole").tag(ResearchFunctionScopeKind.whole)
                Text("Passage").tag(ResearchFunctionScopeKind.passage)
                    .disabled(!passageIsAvailable)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("scholium.researchFunctionScope")
        }
    }
}

struct ResearchFunctionCommentsSection: View {
    let comments: [ResearcherComment]
    let selection: Set<UUID>
    let permitsSelection: Bool
    let manage: () -> Void
    let setSelected: (UUID, Bool) -> Void

    var body: some View {
        ResearchFunctionSection(title: "Comments", symbol: "text.bubble") {
            VStack(alignment: .leading, spacing: 8) {
                if comments.isEmpty {
                    Text("No Comments are attached to this note.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(comments) { comment in
                        if permitsSelection {
                            Toggle(isOn: Binding(
                                get: { selection.contains(comment.id) },
                                set: { setSelected(comment.id, $0) }
                            )) {
                                commentLabel(comment)
                            }
                            .toggleStyle(.checkbox)
                        } else {
                            commentLabel(comment)
                        }
                    }
                }
                Button("Manage Comments…", action: manage)
                    .buttonStyle(.link)
            }
        }
        .accessibilityIdentifier("scholium.researchFunctionComments")
    }

    private func commentLabel(_ comment: ResearcherComment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(comment.text)
                .lineLimit(3)
            if comment.resolvedAt != nil {
                Text("Resolved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ResearchFunctionFidelitySection: View {
    let checks: Set<FidelityCheck>
    let availability: [FidelityCheck: ResearchFunctionCheckAvailability]
    let setSelected: (FidelityCheck, Bool) -> Void
    let repairCitationMethod: () -> Void

    var body: some View {
        ResearchFunctionSection(title: "Checks", symbol: "checkmark.shield") {
            VStack(alignment: .leading, spacing: 8) {
                fidelityToggle(.content, title: "Content")
                fidelityToggle(.citations, title: "Citations")
                if availability[.citations]?.isEnabled == false {
                    Button("Open Research Guidance…", action: repairCitationMethod)
                        .buttonStyle(.link)
                        .accessibilityIdentifier(
                            "scholium.researchFunction.repairCitationMethod"
                        )
                }
            }
        }
        .accessibilityIdentifier("scholium.researchFunctionFidelity")
    }

    private func fidelityToggle(_ check: FidelityCheck, title: String) -> some View {
        let checkAvailability = availability[check]
        return Toggle(isOn: Binding(
            get: { checks.contains(check) },
            set: { setSelected(check, $0) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let reason = checkAvailability?.repairReasons.first?.interfaceDescription,
                   checkAvailability?.isEnabled == false {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(checkAvailability?.isEnabled == false)
    }
}

struct ResearchFunctionSection<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content

    init(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        GroupBox {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(title, systemImage: symbol)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
        }
    }
}
