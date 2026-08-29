import ScholiumContracts
import ScholiumResearchRecordsFeature
import SwiftUI
import UniformTypeIdentifiers

struct ResearchRecordFollowUpSection: View {
    let record: PortableResearchRecord
    let model: ResearchRecordBrowserModel
    let context: ResearchRecordBrowserContext

    @State private var isPresentingFollowUp = false
    @State private var isStartingImprovement = false
    @State private var improvementHandoff: ResearchAgentHandoff?
    @State private var improvementError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
            Text("CONTINUE RESEARCH")
                .scholiumApparatusHeadingStyle()
                .accessibilityHeading(.h2)

            Text("Start a new Action from this completed Result. Scholium will resolve the current Method, Profile, materials, permissions, and write boundary again.")
                .font(ScholiumTypography.interface(.compact))
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    controls
                }
                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.inlineControlGap
                ) {
                    controls
                }
            }

            if let improvementError {
                Text(improvementError)
                    .font(ScholiumTypography.interface(.compact))
                    .scholiumForeground(.destructive)
                    .textSelection(.enabled)
            }
        }
        .sheet(isPresented: $isPresentingFollowUp) {
            ResearchRecordFollowUpSheet(
                record: record,
                client: context.followUpClient,
                loadContext: context.followUpContext
            )
        }
        .sheet(
            isPresented: Binding(
                get: { improvementHandoff != nil },
                set: { if !$0 { improvementHandoff = nil } }
            )
        ) {
            if let improvementHandoff {
                ResearchMethodImprovementHandoffSheet(handoff: improvementHandoff)
            }
        }
        .onAppear {
            if model.consumeFollowUpRequest(recordID: record.id) {
                isPresentingFollowUp = true
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        Button("Follow Up…") { isPresentingFollowUp = true }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("scholium.researchRecord.followUp")

        if record.methodFeedbackComment != nil {
            Button("Improve Current Method…") { startMethodImprovement() }
                .disabled(isStartingImprovement)
                .accessibilityHint(
                    "Starts a separate Method improvement Run from Feedback on the previous Result"
                )
            if isStartingImprovement {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Preparing Method improvement")
            }
        }
    }

    private func startMethodImprovement() {
        guard record.methodFeedbackComment != nil, !isStartingImprovement else {
            return
        }
        improvementError = nil
        isStartingImprovement = true
        Task { @MainActor in
            defer { isStartingImprovement = false }
            do {
                improvementHandoff = try await context.startMethodImprovement(
                    record.id
                )
            } catch {
                improvementError = error.localizedDescription
            }
        }
    }
}

private struct ResearchRecordFollowUpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scholiumFileSelectionPresenter)
    private var fileSelectionPresenter

    let record: PortableResearchRecord
    let client: ResearchActionClient
    let loadContext: @MainActor (UUID, DocumentFingerprint) async throws
        -> ResearchFollowUpContext

    @StateObject private var controller = ResearchActionController()
    @State private var followUpContext: ResearchFollowUpContext?
    @State private var actions: [ResearchActionAvailability] = []
    @State private var selectedActionID: ResearchActionID?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if controller.isPresented {
                ResearchActionPanelView(
                    controller: controller,
                    context: ResearchActionPanelContext(
                        chooseLocalSource: chooseLocalSource,
                        copyInstructions: { instructions in
                            guard ScholiumPasteboardWriter.general.writeText(
                                instructions
                            ) else {
                                throw ResearchActionExecutionContractError
                                    .staleResolution
                            }
                        },
                        didCopyHandoff: { _ in },
                        retryRefresh: load,
                        openRecovery: {},
                        dismiss: { _ in dismiss() }
                    )
                )
            } else {
                actionPicker
            }
        }
        .task { load() }
    }

    private var actionPicker: some View {
        VStack(spacing: 0) {
            VStack(
                alignment: .leading,
                spacing: ScholiumMetrics.ResearchSheet.headerDetailSpacing
            ) {
                Text("Follow Up")
                    .font(ScholiumTypography.interface(.primaryTitle))
                    .accessibilityHeading(.h1)
                Text(verbatim: record.title.value)
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
            }
            .padding(ScholiumMetrics.ResearchSheet.contentInset)
            .frame(maxWidth: .infinity, alignment: .leading)

            ScholiumStructuralRule()

            VStack(
                alignment: .leading,
                spacing: ScholiumMetrics.ResearchSheet.bodySectionSpacing
            ) {
                Text("NEXT ACTION")
                    .scholiumApparatusHeadingStyle()
                    .accessibilityAddTraits(.isHeader)
                if isLoading {
                    ProgressView("Resolving current Actions…")
                        .controlSize(.small)
                } else if actions.isEmpty {
                    Text(errorMessage ?? "No current Action is available for this Note.")
                        .font(ScholiumTypography.interface(.body))
                        .scholiumForeground(errorMessage == nil ? .secondaryText : .destructive)
                } else {
                    Picker("Next Action", selection: $selectedActionID) {
                        ForEach(actions, id: \.id) { action in
                            Text(verbatim: action.buttonName)
                                .tag(Optional(action.id))
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .accessibilityIdentifier(
                        "scholium.researchFollowUp.actionPicker"
                    )
                    if let selected = selectedAction {
                        Text("A new \(selected.buttonName) Run will be resolved from current workspace state.")
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.secondaryText)
                    }
                }
            }
            .padding(ScholiumMetrics.ResearchSheet.contentInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            ScholiumStructuralRule()

            HStack {
                Button("Cancel", action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Continue") { beginSelectedAction() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedAction == nil || followUpContext == nil)
            }
            .padding(ScholiumMetrics.ResearchSheet.contentInset)
        }
        .frame(
            minWidth: ScholiumMetrics.ResearchSheet.Action.minimumWidth,
            idealWidth: ScholiumMetrics.ResearchSheet.Action.idealWidth,
            minHeight: 360,
            idealHeight: 440
        )
        .scholiumSurface(.denseEvidence)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("scholium.researchFollowUp.sheet")
    }

    private var selectedAction: ResearchActionAvailability? {
        selectedActionID.flatMap { id in actions.first { $0.id == id } }
    }

    private func load() {
        guard !isLoading || followUpContext == nil else { return }
        isLoading = true
        errorMessage = nil
        controller.bind(client)
        Task { @MainActor in
            do {
                let fingerprint = try record.finalizedResultFingerprint()
                let context = try await loadContext(record.id, fingerprint)
                let available = try await client.availableActions(context.target)
                followUpContext = context
                actions = available.filter {
                    $0.id != .discuss && $0.canPresentInInterface
                }
                selectedActionID = actions.first(where: \.isEnabled)?.id
                    ?? actions.first?.id
                isLoading = false
            } catch {
                followUpContext = nil
                actions = []
                selectedActionID = nil
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func beginSelectedAction() {
        guard let followUpContext, let selectedAction else { return }
        _ = controller.beginFollowUp(
            context: followUpContext,
            availability: selectedAction,
            presentationID: UUID()
        )
    }

    @MainActor
    private func chooseLocalSource() async throws -> URL? {
        try await fileSelectionPresenter
            .requiredForFileSelection()
            .selectURL(ScholiumFileSelectionRequest(
                title: String(localized: "Choose Source"),
                prompt: String(localized: "Choose"),
                kind: .files(
                    allowedContentTypes: [.item],
                    resolvesAliases: false
                )
            ))
    }
}
