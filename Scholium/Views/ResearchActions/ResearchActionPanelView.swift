import Foundation
import ScholiumContracts
import SwiftUI

struct ResearchActionPanelContext {
    let chooseLocalSource: () -> URL?
    let agentApplicationHandoff: AgentApplicationHandoffController
    let copyInstructions: (String) throws -> Void
    let dismiss: () -> Void
}

/// One native sheet for every Action. Protected Platform selectors and
/// researcher-owned academic fields are rendered as separate evidential
/// layers; neither can hide the app-owned Target, revision, authority,
/// conflict, recovery, or frozen Result Contract boundary.
struct ResearchActionPanelView: View {
    @ObservedObject private var controller: ResearchActionController
    @ObservedObject private var agentApplicationHandoff: AgentApplicationHandoffController
    let context: ResearchActionPanelContext

    @FocusState private var focusedAcademicFieldID: String?
    @State private var focalNoteQuery = ""
    @State private var pendingHandoff: PendingHandoff?
    @State private var evaluationHasUnsavedChanges = false
    @State private var confirmsDiscardEvaluation = false

    init(
        controller: ResearchActionController,
        context: ResearchActionPanelContext
    ) {
        self.controller = controller
        self.context = context
        _agentApplicationHandoff = ObservedObject(
            wrappedValue: context.agentApplicationHandoff
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScholiumStructuralRule()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    appOwnedContext
                    platformInputs
                    academicInputs
                    status
                    if let result = controller.resultRecord {
                        ScholiumStructuralRule()
                        ResearchFinalizedResultView(record: result)
                        ScholiumStructuralRule()
                        ResearcherEvaluationView(
                            record: result,
                            save: {
                                draft, expectedRevision, resultFingerprint in
                                try await controller.saveResearcherEvaluation(
                                    draft: draft,
                                    expectedEvaluationRevision: expectedRevision,
                                    expectedResultFingerprint: resultFingerprint
                                )
                            },
                            clear: { expectedRevision, resultFingerprint in
                                try await controller.clearResearcherEvaluation(
                                    expectedEvaluationRevision: expectedRevision,
                                    expectedResultFingerprint: resultFingerprint
                                )
                            },
                            draftStateDidChange: {
                                evaluationHasUnsavedChanges = $0
                            }
                        )
                        ScholiumStructuralRule()
                        ResearchMethodFeedbackView(
                            record: result,
                            save: {
                                draft, expectedRevision, resultFingerprint in
                                try await controller.saveMethodFeedbackComment(
                                    draft: draft,
                                    expectedCommentRevision: expectedRevision,
                                    expectedResultFingerprint: resultFingerprint
                                )
                            },
                            clear: { expectedRevision, resultFingerprint in
                                try await controller.clearMethodFeedbackComment(
                                    expectedCommentRevision: expectedRevision,
                                    expectedResultFingerprint: resultFingerprint
                                )
                            },
                            startImprovement: {
                                try await controller.startMethodImprovement()
                            }
                        )
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("scholium.researchAction.scroll")
            ScholiumStructuralRule()
            if let errorMessage = agentApplicationHandoff.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .scholiumForeground(.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("scholium.researchAction.handoffError")
                ScholiumStructuralRule()
            }
            footer
        }
        .frame(minWidth: 520, idealWidth: 660, minHeight: 500, idealHeight: 680)
        .scholiumSurface(.denseEvidence)
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.researchAction.sheet")
        .interactiveDismissDisabled(
            controller.phase == .preparing
                || controller.phase == .cancelling
                || evaluationHasUnsavedChanges
        )
        .onAppear { focusFirstAcademicTextField() }
        .onChange(of: controller.phase) { _, phase in
            switch phase {
            case .editing:
                focusFirstAcademicTextField()
            case .prepared:
                completePendingHandoff()
            case .failed, .cancelled:
                pendingHandoff = nil
            case .idle, .loading, .preparing, .cancelling:
                break
            }
        }
        .alert(
            "Discard the Unsaved Evaluation Draft?",
            isPresented: $confirmsDiscardEvaluation
        ) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard Draft and Close", role: .destructive) {
                evaluationHasUnsavedChanges = false
                context.dismiss()
            }
        } message: {
            Text("The saved evaluation and finalized Research Result will remain unchanged.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(
                systemName: controller.activeAvailability?.definition.interfaceSymbol
                    ?? "sparkles"
            )
            .font(.title3.weight(.semibold))
            .foregroundStyle(ScholiumColorRole.secondaryText.color)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: actionTitle)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Method + Academic Profile")
                    .font(.callout)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var appOwnedContext: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RUN BOUNDARY")
                .scholiumApparatusHeadingStyle()
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                Grid(
                    alignment: .leading,
                    horizontalSpacing: 18,
                    verticalSpacing: 8
                ) {
                    boundaryRows
                }
                VStack(alignment: .leading, spacing: 10) {
                    boundaryBlock("Target", value: controller.target?.title ?? "Unavailable")
                    boundaryBlock("Revision", value: revisionLabel)
                    boundaryBlock("Authority", value: authorityLabel)
                }
            }
            Text("Scholium revalidates the exact note and Method/Profile revisions before preparation. Write-capable Actions preserve the bytes they replace and remain subject to conflict and recovery checks.")
                .font(.caption)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("scholium.researchAction.boundary")
    }

    @ViewBuilder
    private var boundaryRows: some View {
        GridRow(alignment: .firstTextBaseline) {
            boundaryLabel("Target")
            Text(controller.target?.title ?? "Unavailable")
        }
        GridRow(alignment: .firstTextBaseline) {
            boundaryLabel("Revision")
            Text(revisionLabel).monospacedDigit()
        }
        GridRow(alignment: .firstTextBaseline) {
            boundaryLabel("Authority")
            Text(authorityLabel)
        }
    }

    private func boundaryLabel(_ value: String) -> some View {
        Text(LocalizedStringKey(value))
            .font(.callout.weight(.semibold))
            .foregroundStyle(ScholiumColorRole.secondaryText.color)
            .frame(width: 76, alignment: .leading)
    }

    private func boundaryBlock(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(label))
                .font(.callout.weight(.semibold))
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
            Text(value).padding(.leading, 10)
        }
    }

    @ViewBuilder
    private var platformInputs: some View {
        let selectors = controller.platformSelectors
        if !selectors.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("RESEARCH CONTEXT")
                    .scholiumApparatusHeadingStyle()
                    .accessibilityAddTraits(.isHeader)
                if selectors.contains(.source) { sourceSelector }
                if selectors.contains(.focalNotes) { focalNotesSelector }
                if selectors.contains(.passage) { passageSelector }
                if selectors.contains(.fidelityChecks) { fidelityChecksSelector }
                if selectors.contains(.citationStyle) {
                    machineResolvedSelector(
                        title: "Citation Style",
                        detail: "Scholium resolves the current citation configuration at preparation."
                    )
                }
                if selectors.contains(.feedback) {
                    machineResolvedSelector(
                        title: "Feedback",
                        detail: "Only explicit current feedback supplied through Scholium is included."
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("scholium.researchAction.platformInputs")
        }
    }

    @ViewBuilder
    private var academicInputs: some View {
        if let fields = controller.profile?.academicInputFields.filter({
            $0.requirement != .excluded
        }), !fields.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("ACADEMIC INPUTS")
                    .scholiumApparatusHeadingStyle()
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                    academicField(field)
                    if index < fields.count - 1 { ScholiumStructuralRule() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("scholium.researchAction.academicInputs")
        }
    }

    @ViewBuilder
    private func academicField(_ field: ResearchAcademicFieldDefinition) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: field.label).font(.headline)
                if field.requirement != .required {
                    Text("Optional")
                        .font(.caption)
                        .foregroundStyle(ScholiumColorRole.mutedText.color)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(
                "scholium.researchAction.academicFieldHeader.\(field.fieldID.rawValue)"
            )
            if let helpText = field.helpText {
                Text(verbatim: helpText)
                    .font(.caption)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            switch field.kind {
            case .freeText:
                academicText(field)
            case .singleChoice:
                academicSingleChoice(field)
            case .multipleChoice:
                academicMultipleChoice(field)
            }
        }
    }

    private func academicText(_ field: ResearchAcademicFieldDefinition) -> some View {
        TextEditor(text: Binding(
            get: { controller.textValues[field.fieldID.rawValue] ?? "" },
            set: { controller.setText($0, field: field) }
        ))
        .frame(minHeight: 92, maxHeight: 150)
        .scrollContentBackground(.hidden)
        .padding(6)
        .background(ScholiumColorRole.documentBackground.color)
        .overlay {
            RoundedRectangle(cornerRadius: ScholiumShape.editorialControlCornerRadius)
                .stroke(ScholiumColorRole.separator.color, lineWidth: 0.5)
        }
        .focused($focusedAcademicFieldID, equals: field.fieldID.rawValue)
        .accessibilityLabel(Text(verbatim: field.label))
        .accessibilityIdentifier(
            "scholium.researchAction.academicText.\(field.fieldID.rawValue)"
        )
    }

    private func academicSingleChoice(
        _ field: ResearchAcademicFieldDefinition
    ) -> some View {
        Picker(
            selection: Binding<String?>(
                get: { controller.choiceValues[field.fieldID.rawValue]?.first },
                set: { value in
                    let current = controller.choiceValues[field.fieldID.rawValue]?.first
                    if let value {
                        controller.setChoice(value, isSelected: true, field: field)
                    } else if let current {
                        controller.setChoice(current, isSelected: false, field: field)
                    }
                }
            )
        ) {
            if field.requirement != .required {
                Text("None").tag(Optional<String>.none)
            }
            ForEach(field.choices, id: \.value) { choice in
                Text(verbatim: choice.label).tag(Optional(choice.value))
            }
        } label: {
            Text(verbatim: field.label)
        }
        .labelsHidden()
        .pickerStyle(.radioGroup)
        .accessibilityLabel(Text(verbatim: field.label))
    }

    private func academicMultipleChoice(
        _ field: ResearchAcademicFieldDefinition
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(field.choices, id: \.value) { choice in
                Toggle(
                    isOn: Binding(
                        get: {
                            controller.choiceValues[field.fieldID.rawValue]?
                                .contains(choice.value) == true
                        },
                        set: {
                            controller.setChoice(
                                choice.value,
                                isSelected: $0,
                                field: field
                            )
                        }
                    )
                ) {
                    Text(verbatim: choice.label)
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    @ViewBuilder
    private var sourceSelector: some View {
        selectorHeader("Source", required: selectorIsRequired(.source))
        if controller.isLoadingSourceStatus {
            ProgressView("Checking source access…")
                .controlSize(.small)
                .accessibilityIdentifier("scholium.researchAction.source.loading")
        } else if controller.sourceStatus?.state == .available,
                  let reference = controller.sourceStatus?.reference {
            Label {
                Text(verbatim: reference.displayName)
            } icon: {
                Image(systemName: "doc.text.magnifyingglass")
            }
            .font(.callout)
            .accessibilityIdentifier("scholium.researchAction.source.available")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Source access needs attention.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .scholiumForeground(.attention)
                Button(controller.isBindingSource ? "Binding Source…" : "Choose Source…") {
                    guard let url = context.chooseLocalSource() else { return }
                    controller.bindLocalSource(url)
                }
                .disabled(controller.isBindingSource)
                .accessibilityIdentifier("scholium.researchAction.source.choose")
                Text("Scholium retains permission and the fingerprint locally; the Research Record stores neither the path nor source bytes.")
                    .font(.caption)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var focalNotesSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            selectorHeader("Focal Notes", required: selectorIsRequired(.focalNotes))
            TextField("Search eligible notes", text: $focalNoteQuery)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("scholium.researchAction.focalNoteSearch")
            if controller.isLoadingMaterialCandidates {
                ProgressView("Loading eligible notes…")
                    .controlSize(.small)
                    .accessibilityIdentifier("scholium.researchAction.notes.loading")
            } else if controller.materialCandidates.isEmpty {
                Text("No eligible notes are available.")
                    .font(.callout)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            } else if visibleFocalNoteCandidates.isEmpty {
                Text("Enter a title or path to find an eligible note.")
                    .font(.callout)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            } else {
                ForEach(visibleFocalNoteCandidates, id: \.noteID) { candidate in
                    Toggle(
                        isOn: Binding(
                            get: {
                                controller.selectedFocalNoteIDs.contains(candidate.noteID)
                            },
                            set: {
                                controller.setFocalNote(candidate.noteID, isSelected: $0)
                            }
                        )
                    ) {
                        Text(verbatim: candidate.title)
                    }
                    .toggleStyle(.checkbox)
                    .help(candidate.note.relativePath)
                    .accessibilityIdentifier(
                        "scholium.researchAction.focalNote.\(candidate.noteID.uuidString.lowercased())"
                    )
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var passageSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            selectorHeader("Passage", required: selectorIsRequired(.passage))
            if controller.passageIsAvailable {
                Toggle("Use selected passage", isOn: $controller.usesPassage)
                    .toggleStyle(.checkbox)
                    .accessibilityValue("Passage available")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("No passage selected", systemImage: "selection.pin.in.out")
                        .font(.callout)
                    Text("Select a passage in the document, then reopen this Action.")
                        .font(.caption)
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                }
            }
        }
    }

    private var fidelityChecksSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            selectorHeader(
                "Fidelity Checks",
                required: selectorIsRequired(.fidelityChecks)
            )
            ForEach(FidelityCheck.allCases, id: \.self) { check in
                Toggle(
                    isOn: Binding(
                        get: { controller.selectedFidelityChecks.contains(check) },
                        set: { controller.setFidelityCheck(check, isSelected: $0) }
                    )
                ) {
                    Text(check.interfaceTitle)
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private func machineResolvedSelector(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            selectorHeader(title, required: false)
            Text(detail)
                .font(.caption)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
        }
    }

    private func selectorHeader(_ title: String, required: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(LocalizedStringKey(title)).font(.headline)
            if !required {
                Text("Optional")
                    .font(.caption)
                    .foregroundStyle(ScholiumColorRole.mutedText.color)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if let errorMessage = controller.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.octagon")
                .font(.callout)
                .scholiumForeground(.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("scholium.researchAction.error")
        }
        if let preparation = controller.preparation {
            VStack(alignment: .leading, spacing: 10) {
                Text("PREPARED")
                    .scholiumApparatusHeadingStyle()
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("scholium.researchAction.prepared")
                Text("The exact Action, Method and Profile revisions, Platform and academic inputs, Result Contract, Target revision, and authority boundary are frozen for this Run.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if let warning = preparation.derivedRefreshWarning {
                    Label(warning, systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .scholiumForeground(.attention)
                }
                if let message = controller.agentBridgeDisabledMessage {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(
                            message,
                            systemImage: "person.crop.circle.badge.exclamationmark"
                        )
                        .font(.callout)
                        .scholiumForeground(.attention)
                        Text("The Run is frozen and durable. This build cannot connect a local Agent; use a bridge-enabled signed build for Agent collaboration.")
                            .font(.caption)
                            .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("scholium.researchAction.bridgeDisabled")
                }
                if let handoff = controller.agentHandoff,
                   controller.canCancelPreparedRun {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PAIRING CODE")
                            .scholiumApparatusHeadingStyle()
                            .accessibilityAddTraits(.isHeader)
                        Text(handoff.pairingCode.rawValue)
                            .font(.system(.title3, design: .monospaced).weight(.semibold))
                            .privacySensitive()
                            .accessibilityLabel("Pairing Code")
                            .accessibilityValue(handoff.pairingCode.rawValue)
                            .accessibilityIdentifier(
                                "scholium.researchAction.pairingCode"
                            )
                        Text("Enter this one-time code only when `scholium agent pair` asks on standard input. Do not paste it into the Agent conversation or command.")
                            .font(.caption)
                            .foregroundStyle(ScholiumColorRole.secondaryText.color)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Expires \(handoff.expiresAt, style: .relative).")
                            .font(.caption)
                            .foregroundStyle(ScholiumColorRole.mutedText.color)
                    }
                    Button("Generate New Pairing Code") {
                        controller.regenerateHandoff()
                    }
                    .disabled(controller.isBusy)
                    .accessibilityIdentifier(
                        "scholium.researchAction.regeneratePairing"
                    )
                    .accessibilityHint(
                        "Invalidates the previous pairing for this Run without replacing the Run or its recovery state."
                    )
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(controller.preparation == nil ? "Cancel" : "Done") {
                if evaluationHasUnsavedChanges {
                    confirmsDiscardEvaluation = true
                } else {
                    context.dismiss()
                }
            }
            .keyboardShortcut(.cancelAction)
            .disabled(controller.phase == .preparing || controller.phase == .cancelling)
            .accessibilityIdentifier("scholium.researchAction.dismiss")
            if controller.canCancelPreparedRun {
                Button("Cancel Run", role: .destructive) {
                    controller.cancelPreparedRun()
                }
                .disabled(controller.isBusy)
                .accessibilityIdentifier("scholium.researchAction.cancelRun")
            }
            Spacer()
            if controller.preparation == nil || controller.canCancelPreparedRun {
                Button {
                    beginHandoff(.copyOnly)
                } label: {
                    handoffButtonLabel(
                        title: "Copy Only",
                        isPending: pendingHandoff == .copyOnly
                    )
                }
                .disabled(!canCopyInstructions)
                .accessibilityIdentifier("scholium.researchAction.copyOnly")
                .accessibilityHint("Validates and freezes this Action, then copies non-secret connection instructions without the Pairing Code, research content, or local paths.")
                Button {
                    beginHandoff(.copyAndOpen)
                } label: {
                    handoffButtonLabel(
                        title: agentApplicationHandoff.primaryActionTitle,
                        isPending: pendingHandoff == .copyAndOpen
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canCopyInstructions || agentApplicationHandoff.isOpening)
                .accessibilityIdentifier("scholium.researchAction.copyAndOpen")
                .accessibilityHint(agentApplicationHandoff.primaryActionAccessibilityHint)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func handoffButtonLabel(title: String, isPending: Bool) -> some View {
        HStack(spacing: 6) {
            if isPending {
                ProgressView().controlSize(.small)
            }
            Text(LocalizedStringKey(isPending ? "Preparing…" : title)).lineLimit(1)
        }
    }

    private func beginHandoff(_ handoff: PendingHandoff) {
        if let agentHandoff = controller.agentHandoff,
           controller.canCancelPreparedRun,
           !controller.isBusy {
            performHandoff(handoff, instructions: agentHandoff.agentInstructions)
            return
        }
        if controller.preparation != nil,
           controller.phase == .failed,
           !controller.isBusy {
            pendingHandoff = handoff
            controller.retryHandoff()
            return
        }
        guard controller.canPrepare, pendingHandoff == nil else { return }
        pendingHandoff = handoff
        controller.prepare()
    }

    private func completePendingHandoff() {
        guard let handoff = pendingHandoff,
              let agentHandoff = controller.agentHandoff else {
            pendingHandoff = nil
            return
        }
        pendingHandoff = nil
        performHandoff(handoff, instructions: agentHandoff.agentInstructions)
    }

    private func performHandoff(_ handoff: PendingHandoff, instructions: String) {
        switch handoff {
        case .copyOnly:
            agentApplicationHandoff.copyOnly(
                instructions: instructions,
                copy: context.copyInstructions
            )
        case .copyAndOpen:
            agentApplicationHandoff.copyAndOpen(
                instructions: instructions,
                copy: context.copyInstructions
            )
        }
    }

    private var actionTitle: String {
        controller.activeAvailability?.buttonName
            ?? String(localized: "Research Action", table: "Localizable", bundle: .module)
    }

    private var revisionLabel: String {
        controller.target.map { String($0.fingerprint.sha256.prefix(8)) }
            ?? String(localized: "Unavailable", table: "Localizable", bundle: .module)
    }

    private var authorityLabel: String {
        guard let platform = controller.platformDefinition else {
            return String(localized: "Checking…", table: "Localizable", bundle: .module)
        }
        let role = controller.target?.role.interfaceTitle
            ?? String(localized: "note", table: "Localizable", bundle: .module)
        return platform.operations.contains(.modifyInitialNote)
            ? String(
                localized: "Candidate write to current \(role)",
                table: "Localizable",
                bundle: .module
            )
            : String(localized: "Read-only", table: "Localizable", bundle: .module)
    }

    private var canCopyInstructions: Bool {
        guard pendingHandoff == nil, !controller.isBusy else { return false }
        guard controller.agentBridgeDisabledMessage == nil else { return false }
        return controller.canCancelPreparedRun || controller.canPrepare
    }

    private func focusFirstAcademicTextField() {
        focusedAcademicFieldID = controller.profile?.academicInputFields.first(where: {
            $0.kind == .freeText && $0.requirement != .excluded
        })?.fieldID.rawValue
    }

    private func selectorIsRequired(_ selector: PlatformActionSelector) -> Bool {
        controller.platformDefinition?.requiredSelectors.contains(selector) == true
    }

    private var visibleFocalNoteCandidates: [ResearchActionNoteSnapshot] {
        let candidates = controller.materialCandidates
        let query = focalNoteQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            guard candidates.count > 20 else { return candidates }
            return candidates.filter {
                controller.selectedFocalNoteIDs.contains($0.noteID)
            }
        }
        let comparable = query.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        return candidates.filter { candidate in
            [candidate.title, candidate.note.relativePath].contains { value in
                value.folding(
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    locale: .current
                ).contains(comparable)
            }
        }.prefix(50).map { $0 }
    }

    private enum PendingHandoff {
        case copyOnly
        case copyAndOpen
    }
}

extension ResearchActionDefinition {
    var interfaceSymbol: String {
        switch executionKind {
        case .discussion: "text.bubble"
        case .analysis: "doc.text.magnifyingglass"
        case .synthesis: "arrow.triangle.merge"
        case .writing: "pencil"
        case .critique: "text.magnifyingglass"
        case .checkFidelity: "checkmark.shield"
        case .manuscript: "doc.richtext"
        }
    }

    var interfaceSummary: String {
        switch executionKind {
        case .discussion:
            String(localized: "Discuss this note or a selected passage without changing Markdown.", table: "Localizable", bundle: .module)
        case .analysis:
            String(localized: "Analyze the bound source and update this Analysis when warranted.", table: "Localizable", bundle: .module)
        case .synthesis:
            String(localized: "Integrate Analyses, Sources, and reliable information into this Topic.", table: "Localizable", bundle: .module)
        case .writing:
            String(localized: "Write to this Work within its explicit boundary.", table: "Localizable", bundle: .module)
        case .critique:
            String(localized: "Produce bounded critical feedback before any separately authorized writing.", table: "Localizable", bundle: .module)
        case .checkFidelity:
            String(localized: "Check content fidelity without modifying the note.", table: "Localizable", bundle: .module)
        case .manuscript:
            String(localized: "Run the configured manuscript method within its declared boundary.", table: "Localizable", bundle: .module)
        }
    }

    var interfaceKeyboardShortcut: KeyboardShortcut? {
        switch id {
        case .discuss:
            KeyboardShortcut("r", modifiers: [.command])
        case .analyze, .synthesize, .write:
            KeyboardShortcut("r", modifiers: [.command, .shift])
        default:
            nil
        }
    }
}

private extension FidelityCheck {
    var interfaceTitle: String {
        switch self {
        case .content: "Content"
        case .citations: "Citations"
        }
    }
}

private extension ResearchActionTargetRole {
    var interfaceTitle: String {
        switch self {
        case .analysis:
            String(localized: "Analysis", table: "Localizable", bundle: .module)
        case .topic:
            String(localized: "Topic", table: "Localizable", bundle: .module)
        case .work:
            String(localized: "Work", table: "Localizable", bundle: .module)
        }
    }
}
