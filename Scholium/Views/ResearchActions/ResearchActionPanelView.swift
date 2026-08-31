import AppKit
import Foundation
import ScholiumContracts
import SwiftUI

enum ResearchActionDismissalFocusDisposition: Equatable, Sendable {
    case preserveInputModality
    case restoreOriginatingAction

    @MainActor
    static var currentInput: Self {
        switch NSApp.currentEvent?.type {
        case .keyDown, .keyUp:
            .restoreOriginatingAction
        default:
            .preserveInputModality
        }
    }
}

struct ResearchActionPanelContext {
    let chooseLocalSource: @MainActor () async throws -> URL?
    let copyInstructions: (String) throws -> Void
    let didCopyHandoff: (UUID) -> Void
    let retryRefresh: () -> Void
    let openRecovery: () -> Void
    let dismiss: (ResearchActionDismissalFocusDisposition) -> Void
}

enum ResearchActionHandoffDelivery {
    static func copyAndComplete(
        instructions: String,
        runID: UUID,
        copy: (String) throws -> Void,
        didCopy: (UUID) -> Void,
        dismiss: () -> Void
    ) throws {
        try copy(instructions)
        didCopy(runID)
        dismiss()
    }
}

/// One native sheet for every Action. It keeps the Action, target, possible
/// document effect, academic inputs, Agent status, and recovery routes
/// visible without turning implementation identities into researcher tasks.
struct ResearchActionPanelView: View {
    @ObservedObject private var controller: ResearchActionController
    let context: ResearchActionPanelContext

    @State private var focalNoteQuery = ""
    @State private var pendingHandoff: PendingHandoff?
    @State private var handoffErrorMessage: String?
    @State private var sourceSelectionErrorMessage: String?
    @State private var confirmsEndAction = false
    @State private var showsAdditionalContext = false
    @State private var showsOptionalAcademicInputs = false
    @State private var showsFollowUpFeedback = false
    @State private var pendingDismissalFocusDisposition:
        ResearchActionDismissalFocusDisposition = .preserveInputModality

    init(
        controller: ResearchActionController,
        context: ResearchActionPanelContext
    ) {
        self.controller = controller
        self.context = context
    }

    var body: some View {
        Group {
            if controller.isStatusPresentation {
                statusPanel
            } else {
                preparationPanel
            }
        }
        .frame(
            minWidth: ScholiumMetrics.ResearchSheet.Action.minimumWidth,
            idealWidth: ScholiumMetrics.ResearchSheet.Action.idealWidth,
            minHeight: controller.isStatusPresentation
                ? 300
                : preparationMinimumHeight,
            idealHeight: controller.isStatusPresentation
                ? 360
                : preparationIdealHeight
        )
        .scholiumSurface(.denseEvidence)
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            controller.isStatusPresentation
                ? "scholium.researchAction.statusSheet"
                : "scholium.researchAction.sheet"
        )
        .interactiveDismissDisabled(
            controller.phase == .preparing
                || controller.phase == .cancelling
        )
        .onAppear {
            synchronizeDisclosureState()
        }
        .onChange(of: controller.phase) { _, phase in
            switch phase {
            case .prepared:
                completePendingHandoff()
            case .failed:
                pendingHandoff = nil
            case .cancelled:
                pendingHandoff = nil
                context.dismiss(pendingDismissalFocusDisposition)
            case .idle, .loading, .editing, .preparing, .cancelling:
                break
            }
        }
        .onChange(of: controller.selectedFocalNoteIDs) { _, selectedIDs in
            if !selectedIDs.isEmpty {
                showsAdditionalContext = true
            }
        }
        .onExitCommand {
            guard controller.phase != .preparing,
                  controller.phase != .cancelling,
                  !confirmsEndAction else {
                return
            }
            context.dismiss(.restoreOriginatingAction)
        }
        .confirmationDialog(
            "End this Action?",
            isPresented: $confirmsEndAction,
            titleVisibility: .visible
        ) {
            Button("Keep Action", role: .cancel) {}
            Button("End Action", role: .destructive) {
                pendingDismissalFocusDisposition = .currentInput
                controller.cancelPreparedRun()
            }
        } message: {
            Text("Scholium will revoke Agent access and end this unfinished Run. Confirmed changes, conflicts, and recovery records remain available.")
        }
    }

    private var preparationPanel: some View {
        VStack(spacing: 0) {
            header
            ScholiumStructuralRule()
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumMetrics.ResearchSheet.bodySectionSpacing
                ) {
                    followUpBridge
                    primaryResearchRequest
                    platformInputs
                    academicInputs
                    status
                    if !controller.continuationRecords.isEmpty {
                        ScholiumStructuralRule()
                        ResearchActionContinuationRecordsView(
                            records: controller.continuationRecords
                        )
                    }
                }
                .padding(ScholiumMetrics.ResearchSheet.contentInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("scholium.researchAction.scroll")
            ScholiumStructuralRule()
            if let handoffErrorMessage {
                Label(handoffErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, ScholiumMetrics.ResearchSheet.contentInset)
                    .padding(
                        .vertical,
                        ScholiumMetrics.ResearchSheet.statusVerticalInset
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("scholium.researchAction.handoffError")
                ScholiumStructuralRule()
            }
            footer
        }
    }

    private var statusPanel: some View {
        VStack(spacing: 0) {
            statusHeader
            ScholiumStructuralRule()
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumMetrics.ResearchSheet.bodySectionSpacing
                ) {
                    statusSheetContent
                }
                .padding(ScholiumMetrics.ResearchSheet.contentInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("scholium.researchAction.statusScroll")
            ScholiumStructuralRule()
            if let handoffErrorMessage {
                Label(handoffErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(ScholiumMetrics.ResearchSheet.contentInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ScholiumStructuralRule()
            }
            statusFooter
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.nestedContentInset) {
            Image(
                systemName: controller.activeAvailability?.definition.interfaceSymbol
                    ?? "sparkles"
            )
            .scholiumSymbolStyle(.emphasizedProminent)
            .scholiumForeground(.secondaryText)
            .accessibilityHidden(true)
            VStack(
                alignment: .leading,
                spacing: ScholiumMetrics.ResearchSheet.headerDetailSpacing
            ) {
                Text(verbatim: controller.followUpContext == nil
                    ? actionTitle
                    : "Follow Up · \(actionTitle)")
                    .font(ScholiumTypography.interface(.primaryTitle))
                    .accessibilityAddTraits(.isHeader)
                HStack(alignment: .firstTextBaseline, spacing: ScholiumMetrics.ResearchSheet.fieldSpacing) {
                    Text("Target")
                        .font(ScholiumTypography.interface(.sectionTitle))
                    Text(verbatim: targetTitle)
                }
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(.secondaryText)
                .accessibilityElement(children: .combine)
                Text(actionEffectLabel)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(ScholiumMetrics.ResearchSheet.contentInset)
    }

    private var statusHeader: some View {
        HStack(
            alignment: .firstTextBaseline,
            spacing: ScholiumGrid.Spacing.nestedContentInset
        ) {
            Image(
                systemName: controller.activeAvailability?.definition.interfaceSymbol
                    ?? "sparkles"
            )
            .scholiumSymbolStyle(.emphasizedProminent)
            .scholiumForeground(.secondaryText)
            .accessibilityHidden(true)
            VStack(
                alignment: .leading,
                spacing: ScholiumMetrics.ResearchSheet.headerDetailSpacing
            ) {
                Text(verbatim: actionTitle)
                    .font(ScholiumTypography.interface(.primaryTitle))
                    .accessibilityAddTraits(.isHeader)
                HStack(
                    alignment: .firstTextBaseline,
                    spacing: ScholiumMetrics.ResearchSheet.fieldSpacing
                ) {
                    Text("Target")
                        .font(ScholiumTypography.interface(.sectionTitle))
                    Text(verbatim: targetTitle)
                }
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(.secondaryText)
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
        }
        .padding(ScholiumMetrics.ResearchSheet.contentInset)
    }

    @ViewBuilder
    private var statusSheetContent: some View {
        if controller.phase == .loading {
            ProgressView("Loading Action Status…")
                .controlSize(.small)
        } else if let activity = controller.statusActivity {
            VStack(
                alignment: .leading,
                spacing: ScholiumGrid.Spacing.nestedContentInset
            ) {
                Label(statusTitle(for: activity), systemImage: statusSymbol(for: activity))
                    .font(ScholiumTypography.interface(.sectionTitle))
                    .accessibilityIdentifier("scholium.researchAction.status")
                if let reason = activity.repairReason {
                    Text(reason.interfaceRepairDescription)
                        .font(ScholiumTypography.interface(.body))
                        .scholiumForeground(.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(statusDetail(for: activity))
                        .font(ScholiumTypography.interface(.body))
                        .scholiumForeground(.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let warning = controller.preparation?.derivedRefreshWarning {
                    Label(warning, systemImage: "arrow.triangle.2.circlepath")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.attention)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        if let errorMessage = controller.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.octagon")
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(.destructive)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusFooter: some View {
        HStack(spacing: ScholiumMetrics.ResearchSheet.footerControlSpacing) {
            Button("Close", action: dismissFromCurrentInput)
                .keyboardShortcut(.cancelAction)
                .disabled(controller.isBusy)
            if canEndStatusAction {
                Button("End Action…", role: .destructive) {
                    confirmsEndAction = true
                }
                .disabled(controller.isBusy)
            }
            Spacer()
            statusRecoveryAction
            if controller.canResumePreparedRun {
                Button {
                    copyNewHandoff()
                } label: {
                    handoffButtonLabel(
                        title: controller.statusActivity?.repairReason == .resultRequired
                            ? "Copy Resume Handoff"
                            : "Copy New Handoff",
                        isPending: pendingHandoff == .copyNew
                    )
                }
                .disabled(pendingHandoff != nil || controller.isBusy)
                .accessibilityIdentifier(
                    "scholium.researchAction.statusCopyNewHandoff"
                )
            }
        }
        .padding(ScholiumMetrics.ResearchSheet.contentInset)
    }

    @ViewBuilder
    private var statusRecoveryAction: some View {
        switch controller.statusActivity?.repairReason {
        case .recoveryRequired:
            Button("Open Recovery…") { context.openRecovery() }
                .disabled(controller.isBusy)
        case .recordUnavailable:
            Button("Retry Refresh") { context.retryRefresh() }
                .disabled(controller.isBusy)
        case .sourceConflict:
            Button("Return to Document", action: dismissFromCurrentInput)
                .disabled(controller.isBusy)
        case .sourceChanged, .resultRequired, .none:
            EmptyView()
        }
    }

    private func statusTitle(for activity: WorkspaceResearchActivity) -> String {
        ResearchActionActivityPresentation.make(activities: [activity])?.stateTitle
            ?? String(
                localized: "Action Status",
                table: "Localizable",
                bundle: .module
            )
    }

    private func statusDetail(for activity: WorkspaceResearchActivity) -> String {
        switch activity.state {
        case .waitingForAgent:
            String(
                localized: "The handoff is ready. Scholium is waiting for the Agent to connect.",
                table: "Localizable",
                bundle: .module
            )
        case .running:
            if activity.repairReason == .resultRequired {
                String(
                    localized: "Agent changes are saved. Resume this Action so the Agent can submit its Research Result.",
                    table: "Localizable",
                    bundle: .module
                )
            } else {
                String(
                    localized: "The Agent has started this Action.",
                    table: "Localizable",
                    bundle: .module
                )
            }
        case .needsAttention:
            String(
                localized: "This Action needs recovery before it can continue.",
                table: "Localizable",
                bundle: .module
            )
        }
    }

    private func statusSymbol(for activity: WorkspaceResearchActivity) -> String {
        if activity.repairReason == .resultRequired { return "doc.text" }
        return switch activity.state {
        case .waitingForAgent: "clock"
        case .running: "arrow.triangle.2.circlepath"
        case .needsAttention: "exclamationmark.triangle"
        }
    }

    private var canEndStatusAction: Bool {
        controller.canEndPreparedRun
    }

    @ViewBuilder
    private var platformInputs: some View {
        let layout = actionSheetLayout
        if !layout.primaryModules.isEmpty || !layout.additionalContextModules.isEmpty {
            VStack(
                alignment: .leading,
                spacing: ScholiumMetrics.ResearchSheet.bodySectionSpacing
            ) {
                ForEach(layout.primaryModules, id: \.self) { module in
                    platformModule(module)
                }
                if !layout.additionalContextModules.isEmpty {
                    ScholiumDisclosureHeaderButton(
                        isExpanded: showsAdditionalContext,
                        accessibilityLabel: Text("Additional Context"),
                        accessibilityIdentifier:
                            "scholium.researchAction.additionalContext",
                        action: { showsAdditionalContext.toggle() }
                    ) {
                        Text("Additional Context")
                            .font(ScholiumTypography.interface(.sectionTitle))
                    }
                    if showsAdditionalContext {
                        VStack(
                            alignment: .leading,
                            spacing: ScholiumMetrics.ResearchSheet.fieldGroupSpacing
                        ) {
                            ForEach(layout.additionalContextModules, id: \.self) { module in
                                platformModule(module)
                            }
                        }
                        .padding(.top, ScholiumMetrics.ResearchSheet.fieldSpacing)
                        .padding(.leading, ScholiumGrid.Spacing.nestedContentInset)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func platformModule(_ module: ResearchActionSheetModule) -> some View {
        switch module {
        case .source:
            sourceSelector
        case .fidelityChecks:
            fidelityChecksSelector
        case .passage:
            passageSelector
        case .focalNotes:
            focalNotesSelector
        }
    }

    @ViewBuilder
    private var followUpBridge: some View {
        if controller.followUpContext != nil {
            VStack(
                alignment: .leading,
                spacing: ScholiumMetrics.ResearchSheet.fieldGroupSpacing
            ) {
                Text("CONTINUED FROM PREVIOUS RESULT")
                    .scholiumApparatusHeadingStyle()
                    .accessibilityAddTraits(.isHeader)

                Picker("Bridge Type", selection: $controller.followUpKind) {
                    Text("Finding").tag(ResearchFollowUpKind.finding)
                    Text("Question").tag(ResearchFollowUpKind.question)
                    Text("Hypothesis").tag(ResearchFollowUpKind.hypothesis)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("scholium.researchFollowUp.kind")

                TextEditor(text: $controller.followUpStatement)
                    .font(ScholiumTypography.scholarly(.body))
                    .frame(minHeight: 76, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(ScholiumMetrics.ResearchSheet.textEditorInset)
                    .background(ScholiumColorRole.documentBackground.color)
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: ScholiumShape.editorialControlCornerRadius
                        )
                        .stroke(ScholiumColorRole.separator.color, lineWidth: 0.5)
                    }
                    .accessibilityLabel("Finding, question, or hypothesis")
                    .accessibilityIdentifier(
                        "scholium.researchFollowUp.statement"
                    )

                ScholiumDisclosureHeaderButton(
                    isExpanded: showsFollowUpFeedback,
                    accessibilityLabel: Text("Feedback on Previous Result"),
                    accessibilityIdentifier:
                        "scholium.researchFollowUp.feedbackDisclosure",
                    action: { showsFollowUpFeedback.toggle() }
                ) {
                    Text("Feedback on Previous Result")
                        .font(ScholiumTypography.interface(.sectionTitle))
                }
                if showsFollowUpFeedback {
                    VStack(
                        alignment: .leading,
                        spacing: ScholiumGrid.Spacing.inlineControlGap
                    ) {
                        Text("Optional Method Feedback is stored on the previous Record. It is not part of the new Agent result.")
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        TextEditor(text: $controller.followUpMethodFeedback)
                            .font(ScholiumTypography.scholarly(.body))
                            .frame(minHeight: 72, maxHeight: 120)
                            .scrollContentBackground(.hidden)
                            .padding(ScholiumMetrics.ResearchSheet.textEditorInset)
                            .background(ScholiumColorRole.documentBackground.color)
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius:
                                        ScholiumShape.editorialControlCornerRadius
                                )
                                .stroke(
                                    ScholiumColorRole.separator.color,
                                    lineWidth: 0.5
                                )
                            }
                            .accessibilityIdentifier(
                                "scholium.researchFollowUp.methodFeedback"
                            )
                    }
                    .padding(.leading, ScholiumGrid.Spacing.nestedContentInset)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var primaryResearchRequest: some View {
        if let researchRequestField {
            academicField(researchRequestField)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var academicInputs: some View {
        if !requiredAcademicFields.isEmpty || !optionalAcademicFields.isEmpty {
            VStack(
                alignment: .leading,
                spacing: ScholiumMetrics.ResearchSheet.bodySectionSpacing
            ) {
                if !requiredAcademicFields.isEmpty {
                    VStack(
                        alignment: .leading,
                        spacing: ScholiumMetrics.ResearchSheet.fieldGroupSpacing
                    ) {
                        Text("ACADEMIC INPUTS")
                            .scholiumApparatusHeadingStyle()
                            .accessibilityAddTraits(.isHeader)
                        ForEach(requiredAcademicFields, id: \.id) { field in
                            academicField(field)
                        }
                    }
                }
                if !optionalAcademicFields.isEmpty {
                    ScholiumDisclosureHeaderButton(
                        isExpanded: showsOptionalAcademicInputs,
                        accessibilityLabel: Text("Additional Instructions"),
                        accessibilityIdentifier:
                            "scholium.researchAction.additionalInstructions",
                        action: { showsOptionalAcademicInputs.toggle() }
                    ) {
                        Text("Additional Instructions")
                            .font(ScholiumTypography.interface(.sectionTitle))
                    }
                    if showsOptionalAcademicInputs {
                        VStack(
                            alignment: .leading,
                            spacing: ScholiumMetrics.ResearchSheet.fieldGroupSpacing
                        ) {
                            ForEach(optionalAcademicFields, id: \.id) { field in
                                academicField(field)
                            }
                        }
                        .padding(.top, ScholiumMetrics.ResearchSheet.fieldSpacing)
                        .padding(.leading, ScholiumGrid.Spacing.nestedContentInset)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var requiredAcademicFields: [ResearchAcademicFieldDefinition] {
        controller.profile?.academicInputFields.filter {
            $0.requirement == .required && !isResearchRequest($0)
        } ?? []
    }

    private var optionalAcademicFields: [ResearchAcademicFieldDefinition] {
        controller.profile?.academicInputFields.filter {
            $0.requirement == .optional && !isResearchRequest($0)
        } ?? []
    }

    private var researchRequestField: ResearchAcademicFieldDefinition? {
        controller.profile?.academicInputFields.first {
            $0.requirement != .excluded && isResearchRequest($0)
        }
    }

    private func isResearchRequest(
        _ field: ResearchAcademicFieldDefinition
    ) -> Bool {
        field.fieldID.rawValue == "research-request"
    }

    private var actionSheetLayout: ResearchActionSheetLayout {
        ResearchActionSheetLayout.resolve(
            selectors: controller.platformSelectors,
            passageIsAvailable: controller.passageIsAvailable,
            selectedFocalNoteCount: controller.selectedFocalNoteIDs.count
        )
    }

    private var preparationMinimumHeight: CGFloat {
        actionSheetLayout.primaryModules.isEmpty
            ? ScholiumMetrics.ResearchSheet.Action.compactMinimumHeight
            : ScholiumMetrics.ResearchSheet.Action.regularMinimumHeight
    }

    private var preparationIdealHeight: CGFloat {
        actionSheetLayout.primaryModules.isEmpty
            ? ScholiumMetrics.ResearchSheet.Action.compactIdealHeight
            : ScholiumMetrics.ResearchSheet.Action.regularIdealHeight
    }

    private func synchronizeDisclosureState() {
        showsAdditionalContext = actionSheetLayout.expandsAdditionalContext
        showsOptionalAcademicInputs = false
        showsFollowUpFeedback = false
    }

    @ViewBuilder
    private func academicField(_ field: ResearchAcademicFieldDefinition) -> some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            HStack(alignment: .firstTextBaseline, spacing: ScholiumMetrics.ResearchSheet.fieldSpacing) {
                Text(verbatim: field.label).font(ScholiumTypography.interface(.sectionTitle))
                if field.requirement != .required {
                    Text("Optional")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.mutedText)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(
                "scholium.researchAction.academicFieldHeader.\(field.fieldID.rawValue)"
            )
            if let helpText = field.helpText {
                Text(verbatim: helpText)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
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
        .font(ScholiumTypography.scholarly(.body))
        .frame(minHeight: 92, maxHeight: 150)
        .scrollContentBackground(.hidden)
        .padding(ScholiumMetrics.ResearchSheet.textEditorInset)
        .background(ScholiumColorRole.documentBackground.color)
        .overlay {
            RoundedRectangle(cornerRadius: ScholiumShape.editorialControlCornerRadius)
                .stroke(ScholiumColorRole.separator.color, lineWidth: 0.5)
        }
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
        VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.fieldSpacing) {
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
            .font(ScholiumTypography.interface(.body))
            .accessibilityIdentifier("scholium.researchAction.source.available")
        } else {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Label("Source access needs attention.", systemImage: "exclamationmark.triangle")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.attention)
                Button(controller.isBindingSource ? "Binding Source…" : "Choose Source…") {
                    chooseLocalSource()
                }
                .disabled(controller.isBindingSource)
                .accessibilityIdentifier("scholium.researchAction.source.choose")
                if let sourceSelectionErrorMessage {
                    Text(sourceSelectionErrorMessage)
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                Text("The source stays local. Its path and contents aren’t stored in the Research Record.")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func chooseLocalSource() {
        Task { @MainActor in
            do {
                guard let url = try await context.chooseLocalSource() else { return }
                sourceSelectionErrorMessage = nil
                controller.bindLocalSource(url)
            } catch is CancellationError {
                return
            } catch {
                sourceSelectionErrorMessage = error.localizedDescription
            }
        }
    }

    private var focalNotesSelector: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
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
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
            } else if visibleFocalNoteCandidates.isEmpty {
                Text("Enter a title or path to find an eligible note.")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
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
                    .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
                }
            }
        }
    }

    private var passageSelector: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            selectorHeader("Passage", required: selectorIsRequired(.passage))
            if controller.passageIsAvailable {
                Toggle("Use selected passage", isOn: $controller.usesPassage)
                    .toggleStyle(.checkbox)
                    .accessibilityValue("Passage available")
            } else {
                VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.fieldSpacing) {
                    Label("No passage selected", systemImage: "selection.pin.in.out")
                        .font(ScholiumTypography.interface(.body))
                    Text("Select a passage in the document, then reopen this Action.")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                }
            }
        }
    }

    private var fidelityChecksSelector: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
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
            if controller.selectedFidelityChecks.contains(.citations) {
                Text("Citation checks use the active style from Research Guidance.")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func selectorHeader(_ title: String, required: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ScholiumMetrics.ResearchSheet.fieldSpacing) {
            Text(LocalizedStringKey(title)).font(ScholiumTypography.interface(.sectionTitle))
            if !required {
                Text("Optional")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.mutedText)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if let errorMessage = controller.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.octagon")
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("scholium.researchAction.error")
        }
        if let preparation = controller.preparation,
           controller.resultRecord == nil {
            VStack(
                alignment: .leading,
                spacing: ScholiumGrid.Spacing.nestedContentInset
            ) {
                Label("Handoff ready", systemImage: "doc.on.clipboard")
                    .font(ScholiumTypography.interface(.body))
                    .accessibilityIdentifier("scholium.researchAction.connection")
                Text("Closing this sheet leaves the Action active.")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let warning = preparation.derivedRefreshWarning {
                    Label(warning, systemImage: "arrow.triangle.2.circlepath")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.attention)
                }
                if let handoff = controller.agentHandoff,
                   controller.canResumePreparedRun {
                    Divider()
                    HStack(
                        alignment: .firstTextBaseline,
                        spacing: ScholiumMetrics.ResearchSheet.footerControlSpacing
                    ) {
                        Text("Expires \(handoff.expiresAt, style: .relative).")
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.mutedText)
                        Spacer()
                        Button {
                            copyNewHandoff()
                        } label: {
                            handoffButtonLabel(
                                title: "Copy New Handoff",
                                isPending: pendingHandoff == .copyNew
                            )
                        }
                        .disabled(pendingHandoff != nil || controller.isBusy)
                        .accessibilityIdentifier(
                            "scholium.researchAction.copyNewHandoff"
                        )
                        .accessibilityHint(
                            "Invalidates the previous pairing and copies a replacement handoff for this Action."
                        )
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: ScholiumMetrics.ResearchSheet.footerControlSpacing) {
            Button(controller.preparation == nil ? "Cancel" : "Close") {
                dismissFromCurrentInput()
            }
            .disabled(
                controller.phase == .preparing
                    || controller.phase == .cancelling
            )
            .accessibilityIdentifier("scholium.researchAction.dismiss")
            if controller.canEndPreparedRun {
                Button("End Action…", role: .destructive) {
                    confirmsEndAction = true
                }
                .disabled(controller.isBusy)
                .accessibilityIdentifier("scholium.researchAction.endAction")
            }
            Spacer()
            if controller.preparation == nil || controller.canResumePreparedRun {
                Button {
                    beginHandoff(.copy)
                } label: {
                    handoffButtonLabel(
                        title: "Copy Handoff",
                        isPending: pendingHandoff == .copy
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canCopyInstructions)
                .accessibilityIdentifier("scholium.researchAction.copyHandoff")
            }
        }
        .padding(ScholiumMetrics.ResearchSheet.contentInset)
    }

    @ViewBuilder
    private func handoffButtonLabel(title: String, isPending: Bool) -> some View {
        HStack(spacing: ScholiumMetrics.ResearchSheet.fieldSpacing) {
            if isPending {
                ProgressView().controlSize(.small)
            }
            Text(LocalizedStringKey(isPending ? "Preparing…" : title)).lineLimit(1)
        }
    }

    private func beginHandoff(_ handoff: PendingHandoff) {
        pendingDismissalFocusDisposition = .currentInput
        handoffErrorMessage = nil
        if let agentHandoff = controller.agentHandoff,
           controller.canResumePreparedRun,
           !controller.isBusy {
            performHandoff(instructions: agentHandoff.agentInstructions)
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
        guard pendingHandoff != nil,
              let agentHandoff = controller.agentHandoff else {
            pendingHandoff = nil
            return
        }
        pendingHandoff = nil
        performHandoff(instructions: agentHandoff.agentInstructions)
    }

    private func copyNewHandoff() {
        pendingDismissalFocusDisposition = .currentInput
        guard controller.canResumePreparedRun,
              pendingHandoff == nil,
              !controller.isBusy else { return }
        pendingHandoff = .copyNew
        if controller.phase == .failed {
            controller.retryHandoff()
        } else {
            controller.regenerateHandoff()
        }
    }

    private func performHandoff(instructions: String) {
        do {
            guard let runID = controller.preparation?.runID else {
                throw ResearchActionExecutionContractError.staleResolution
            }
            try ResearchActionHandoffDelivery.copyAndComplete(
                instructions: instructions,
                runID: runID,
                copy: context.copyInstructions,
                didCopy: context.didCopyHandoff,
                dismiss: {
                    context.dismiss(pendingDismissalFocusDisposition)
                }
            )
        } catch {
            handoffErrorMessage = String(
                localized: "Scholium could not copy the handoff. \(error.localizedDescription)",
                table: "Localizable",
                bundle: .module
            )
        }
    }

    private func dismissFromCurrentInput() {
        context.dismiss(.currentInput)
    }

    private var actionTitle: String {
        controller.activeAvailability?.buttonName
            ?? String(localized: "Research Action", table: "Localizable", bundle: .module)
    }

    private var targetTitle: String {
        controller.target?.title
            ?? String(localized: "Unavailable", table: "Localizable", bundle: .module)
    }

    private var actionEffectLabel: String {
        guard let platform = controller.platformDefinition else {
            return String(localized: "Checking…", table: "Localizable", bundle: .module)
        }
        let role = controller.target?.role.interfaceTitle
            ?? String(localized: "note", table: "Localizable", bundle: .module)
        return platform.operations.contains(.modifyInitialNote)
            ? String(
                localized: "Can update this \(role). The Agent may add other relevant Notes to this Run before changing them.",
                table: "Localizable",
                bundle: .module
            )
            : String(
                localized: "Does not change research documents.",
                table: "Localizable",
                bundle: .module
            )
    }

    private var canCopyInstructions: Bool {
        guard pendingHandoff == nil, !controller.isBusy else { return false }
        return controller.canResumePreparedRun || controller.canPrepare
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
        case copy
        case copyNew
    }
}

private struct ResearchActionContinuationRecordsView: View {
    let records: [PortableResearchRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
            HStack(alignment: .firstTextBaseline) {
                Text("CONTINUE RESEARCH")
                    .scholiumApparatusHeadingStyle()
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(records.count)")
                    .font(ScholiumTypography.interface(.small, emphasis: .medium, tabularDigits: true))
                    .scholiumForeground(.secondaryText)
            }
            Text("The Agent continued this Action; the continuation remains attached here.")
                .font(ScholiumTypography.interface(.small, emphasis: .medium))
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    HStack(alignment: .firstTextBaseline) {
                        Label(
                            actionTitle(record.action?.actionID ?? .analyze),
                            systemImage: "arrow.turn.down.right"
                        )
                        .font(ScholiumTypography.interface(.rowTitle))
                        Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
                        Text(record.finishedAt, format: .dateTime.year().month().day().hour().minute())
                            .font(ScholiumTypography.interface(.small, emphasis: .medium, tabularDigits: true))
                            .scholiumForeground(.secondaryText)
                    }
                    Text(record.title.value)
                        .font(ScholiumTypography.scholarly(.body))
                        .textSelection(.enabled)
                    if let summary = summary(for: record) {
                        Text(summary)
                            .font(ScholiumTypography.interface(.small, emphasis: .medium))
                            .scholiumForeground(.secondaryText)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(
                    "scholium.researchAction.continuation.\(record.id.uuidString)"
                )
                if index + 1 < records.count { ScholiumStructuralRule() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("scholium.researchAction.continuations")
    }

    private func summary(for record: PortableResearchRecord) -> String? {
        if let result = record.academicResults.first(where: { $0.value != nil }),
           let value = result.value {
            return switch value {
            case .freeText(let text): text
            case .singleChoice(let choice):
                result.definition.choices.first { $0.value == choice }?.label ?? choice
            case .multipleChoice(let choices):
                choices.map { choice in
                    result.definition.choices.first { $0.value == choice }?.label ?? choice
                }.joined(separator: ", ")
            }
        }
        return record.statements.last?.text
    }
}

extension ResearchActionDefinition {
    var interfaceSymbol: String {
        switch id {
        case .discuss: "text.bubble"
        case .analyze: "doc.text.magnifyingglass"
        case .synthesize: "arrow.triangle.merge"
        case .write: "pencil"
        case .critique: "text.magnifyingglass"
        case .checkFidelity: "checkmark.shield"
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
