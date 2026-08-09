import AppKit
import ScholiumContracts
import SwiftUI

struct WorkspaceSetupSelection {
    let paperAnalysisURL: URL
    let topicKnowledgeURL: URL
    let outputURL: URL
    let portableContainerURL: URL
    let triptychID: UUID?
    let triptychName: String
}

/// Immutable Bootstrap projection plus Application-owned filesystem and
/// registration actions. Bootstrap owns presentation and step-local form state
/// only; it never constructs a workspace.
struct WorkspaceSetupContext {
    let isCreatingNewTriptych: Bool
    let offersAgentPreparation: Bool
    let targetTriptychID: UUID?
    let workspaceAssignment: TriptychAssignment?
    let registeredTriptychs: [TriptychAssignment]
    let recoveryMessage: String?
    let refreshAssignment: () async -> Void
    let portableContainerURL: (URL) async -> URL?
    let prepareTriptychStructure: (URL, String) async throws -> WorkspaceSetupSelection
    let commandLineToolStatus: () async -> CommandLineToolStatus
    let installCommandLineTool: () async throws -> CommandLineToolStatus
    let configure: (WorkspaceSetupSelection) async throws -> Void
    let completeBootstrap: () -> Void
    let dismiss: () -> Void
}

struct WorkspaceSetupView: View {
    let context: WorkspaceSetupContext

    var body: some View {
        BootstrapFlowView(context: context)
            .frame(minWidth: 660, minHeight: 680)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .top)
            .interactiveDismissDisabled()
    }
}

private enum BootstrapSetupPath {
    case createNew
    case existingFolders
}

private enum BootstrapStep: Hashable {
    case welcome
    case choosePath
    case createStructure
    case existingAnalyses
    case existingTopics
    case existingWorks
    case authorizeParent
    case reviewTriptych
    case agent
    case ready
}

private enum BootstrapAgentOutcome: Equatable {
    case notOffered
    case deferred
    case confirmedByResearcher
}

private struct BootstrapFlowView: View {
    @Environment(\.scholiumReduceMotion) private var reduceMotion

    let context: WorkspaceSetupContext

    @State private var step: BootstrapStep = .welcome
    @State private var setupPath: BootstrapSetupPath = .createNew
    @State private var isMovingForward = true
    @State private var baseLocationURL: URL?
    @State private var paperAnalysisURL: URL?
    @State private var topicKnowledgeURL: URL?
    @State private var outputURL: URL?
    @State private var portableContainerURL: URL?
    @State private var triptychName = ""
    @State private var agentOutcome: BootstrapAgentOutcome = .notOffered
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isRegisteringTriptych = false
    @State private var pendingAgentOutcome: BootstrapAgentOutcome?
    @State private var loadedCurrentValues = false

    private let artRailWidth: CGFloat = 276

    var body: some View {
        HStack(spacing: 0) {
            BootstrapStageArtwork(stage: artworkStage)
                .frame(width: artRailWidth)

            if step == .agent, let rootURL = triptychRootURL {
                BootstrapAgentPreparationView(
                    triptychRootURL: rootURL,
                    commandLineToolStatus: context.commandLineToolStatus,
                    installCommandLineTool: context.installCommandLineTool,
                    allowsBack: !isRegisteringTriptych,
                    isCompletingBootstrap: pendingAgentOutcome != nil,
                    goBack: moveBack,
                    setUpLater: {
                        finishAgentPreparation(.deferred)
                    },
                    confirmSetup: {
                        finishAgentPreparation(.confirmedByResearcher)
                    }
                )
                .transition(stepTransition)
            } else {
                ZStack(alignment: .bottom) {
                    stepContent
                        .id(step)
                        .transition(stepTransition)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(ScholiumColorRole.documentBackground.color)
                        .clipped()

                    if let message = errorMessage ?? context.recoveryMessage {
                        BootstrapSetupStatus(
                            message: message,
                            isError: errorMessage != nil
                        )
                        .padding(.horizontal, 24)
                        .padding(.bottom, 62)
                    }

                    BootstrapFooter(
                        showsBack: canGoBack,
                        primaryTitle: primaryTitle,
                        primaryDisabled: primaryDisabled || isSaving,
                        onBack: moveBack,
                        onPrimary: performPrimary
                    )
                }
            }
        }
        .foregroundStyle(ScholiumColorRole.primaryText.color)
        .background(ScholiumColorRole.documentBackground.color)
        .tint(ScholiumColorRole.accent.color)
        .task {
            await context.refreshAssignment()
            loadCurrentValuesIfNeeded()
            await loadPortableContainerIfAvailable()
        }
        .onChange(of: context.workspaceAssignment) { _, _ in
            loadCurrentValuesIfNeeded(force: true)
            Task { await loadPortableContainerIfAvailable() }
        }
        .onChange(of: outputURL) { oldValue, newValue in
            let oldParent = oldValue?.deletingLastPathComponent().standardizedFileURL.path
            let newParent = newValue?.deletingLastPathComponent().standardizedFileURL.path
            if oldParent != newParent {
                portableContainerURL = nil
            }
            Task { await loadPortableContainerIfAvailable() }
        }
        .onExitCommand(perform: moveBack)
        .accessibilityIdentifier("scholium.bootstrap")
    }

    private var artworkStage: BootstrapArtworkStage {
        switch step {
        case .welcome:
            .welcome
        case .choosePath, .createStructure, .existingAnalyses,
             .existingTopics, .existingWorks, .authorizeParent,
             .reviewTriptych:
            .triptych
        case .agent:
            .agent
        case .ready:
            .ready
        }
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let offset = isMovingForward ? 14.0 : -14.0
        return .asymmetric(
            insertion: .offset(x: offset).combined(with: .opacity),
            removal: .opacity
        )
    }

    private var canGoBack: Bool {
        step != .welcome && step != .ready
    }

    private var primaryTitle: LocalizedStringResource {
        switch step {
        case .welcome: "Get Started"
        case .choosePath: "Continue"
        case .createStructure: "Review Structure"
        case .existingAnalyses, .existingTopics, .existingWorks: "Continue"
        case .authorizeParent: "Authorize This Folder"
        case .reviewTriptych:
            setupPath == .createNew ? "Create Triptych" : "Use This Triptych"
        case .agent: "I’ve Set Up My Agent"
        case .ready: "Open Workspace"
        }
    }

    private var primaryDisabled: Bool {
        switch step {
        case .welcome, .choosePath, .authorizeParent, .ready:
            false
        case .createStructure:
            sanitizedTriptychName == nil || baseLocationURL == nil
        case .existingAnalyses:
            paperAnalysisURL == nil
        case .existingTopics:
            topicKnowledgeURL == nil
        case .existingWorks:
            outputURL == nil
        case .reviewTriptych:
            setupPath == .createNew
                ? baseLocationURL == nil || sanitizedTriptychName == nil
                : !existingSelectionIsReady
        case .agent:
            true
        }
    }

    private var sanitizedTriptychName: String? {
        let trimmed = triptychName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.replacingOccurrences(of: "/", with: "-")
    }

    private var proposedTriptychRootURL: URL? {
        guard let baseLocationURL, let sanitizedTriptychName else { return nil }
        return baseLocationURL.appendingPathComponent(
            sanitizedTriptychName,
            isDirectory: true
        )
    }

    private var detectedParentURL: URL? {
        outputURL?
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }

    private var triptychRootURL: URL? {
        switch setupPath {
        case .createNew: proposedTriptychRootURL
        case .existingFolders: portableContainerURL ?? detectedParentURL
        }
    }

    private var effectiveAnalysesURL: URL? {
        setupPath == .createNew
            ? proposedTriptychRootURL?.appendingPathComponent("Analyses", isDirectory: true)
            : paperAnalysisURL
    }

    private var effectiveTopicsURL: URL? {
        setupPath == .createNew
            ? proposedTriptychRootURL?.appendingPathComponent("Topics", isDirectory: true)
            : topicKnowledgeURL
    }

    private var effectiveWorksURL: URL? {
        setupPath == .createNew
            ? proposedTriptychRootURL?.appendingPathComponent("Works", isDirectory: true)
            : outputURL
    }

    private var existingSelectionIsReady: Bool {
        guard paperAnalysisURL != nil,
              topicKnowledgeURL != nil,
              outputURL != nil,
              let portableContainerURL,
              let detectedParentURL else { return false }
        return portableContainerURL.resolvingSymlinksInPath().standardizedFileURL.path
            == detectedParentURL.path
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            BootstrapWelcomeStep()
        case .choosePath:
            BootstrapChoosePathStep(
                selection: setupPath,
                chooseCreateNew: { setupPath = .createNew },
                chooseExisting: { setupPath = .existingFolders }
            )
        case .createStructure:
            BootstrapCreateStructureStep(
                triptychName: $triptychName,
                parentURL: baseLocationURL,
                proposedRootURL: proposedTriptychRootURL,
                chooseParent: chooseParentLocation
            )
        case .existingAnalyses:
            BootstrapExistingFolderStep(
                title: "Choose Analyses",
                explanation: "Reusable analyses of papers and other sources.",
                path: paperAnalysisURL,
                chooseAction: {
                    paperAnalysisURL = chooseDirectory(title: "Choose Analyses Folder")
                }
            )
        case .existingTopics:
            BootstrapExistingFolderStep(
                title: "Choose Topics",
                explanation: "Concepts, distinctions, debates, objections, and syntheses.",
                path: topicKnowledgeURL,
                chooseAction: {
                    topicKnowledgeURL = chooseDirectory(title: "Choose Topics Folder")
                }
            )
        case .existingWorks:
            BootstrapExistingFolderStep(
                title: "Choose Works",
                explanation: "Researcher-governed plans, arguments, drafts, papers, and chapters.",
                path: outputURL,
                chooseAction: {
                    outputURL = chooseDirectory(title: "Choose Works Folder")
                }
            )
        case .authorizeParent:
            BootstrapAuthorizeParentStep(rootURL: detectedParentURL)
        case .reviewTriptych:
            BootstrapReviewTriptychStep(
                setupPath: setupPath,
                rootURL: triptychRootURL,
                analysesURL: effectiveAnalysesURL,
                topicsURL: effectiveTopicsURL,
                worksURL: effectiveWorksURL
            )
        case .agent:
            EmptyView()
        case .ready:
            BootstrapReadyStep(
                triptychName: triptychName,
                rootURL: triptychRootURL,
                agentOutcome: agentOutcome
            )
        }
    }

    private func performPrimary() {
        guard !primaryDisabled else { return }
        switch step {
        case .welcome:
            move(to: .choosePath)
        case .choosePath:
            move(to: setupPath == .createNew ? .createStructure : .existingAnalyses)
        case .createStructure:
            move(to: .reviewTriptych)
        case .existingAnalyses:
            move(to: .existingTopics)
        case .existingTopics:
            move(to: .existingWorks)
        case .existingWorks:
            move(to: .authorizeParent)
        case .authorizeParent:
            authorizeDetectedParent()
        case .reviewTriptych:
            save()
        case .agent:
            break
        case .ready:
            context.completeBootstrap()
            context.dismiss()
        }
    }

    private func moveBack() {
        guard !(step == .agent && isRegisteringTriptych) else { return }
        let destination: BootstrapStep?
        switch step {
        case .welcome: destination = nil
        case .choosePath: destination = .welcome
        case .createStructure, .existingAnalyses: destination = .choosePath
        case .existingTopics: destination = .existingAnalyses
        case .existingWorks: destination = .existingTopics
        case .authorizeParent: destination = .existingWorks
        case .reviewTriptych:
            destination = setupPath == .createNew ? .createStructure : .authorizeParent
        case .agent: destination = .reviewTriptych
        case .ready: destination = nil
        }
        guard let destination else { return }
        move(to: destination, movingForward: false)
    }

    private func move(to destination: BootstrapStep, movingForward: Bool = true) {
        isMovingForward = movingForward
        withAnimation(ScholiumMotion.bootstrapStep(reduceMotion: reduceMotion)) {
            step = destination
        }
    }

    private func finishAgentPreparation(_ outcome: BootstrapAgentOutcome) {
        agentOutcome = outcome
        guard isRegisteringTriptych else {
            move(to: .ready)
            return
        }
        pendingAgentOutcome = outcome
    }

    private func chooseParentLocation() {
        baseLocationURL = chooseDirectory(
            title: "Choose a Parent Location",
            prompt: "Choose Location"
        )
    }

    private func chooseDirectory(
        title: LocalizedStringResource,
        prompt: LocalizedStringResource = "Choose Folder"
    ) -> URL? {
        let panel = NSOpenPanel()
        panel.title = String(localized: title)
        panel.prompt = String(localized: prompt)
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func authorizeDetectedParent() {
        guard let expected = detectedParentURL else { return }
        let panel = NSOpenPanel()
        panel.title = String(localized: "Authorize the Detected Folder")
        panel.message = String(
            localized: "Confirm this folder so Scholium can use the portable .scholium control folder beside Works."
        )
        panel.prompt = String(localized: "Authorize")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = expected

        guard panel.runModal() == .OK, let selected = panel.url else { return }
        let canonical = selected.resolvingSymlinksInPath().standardizedFileURL
        guard canonical.path == expected.path else {
            errorMessage = String(
                localized: "Authorize the detected folder itself; no other folder can contain this Triptych's portable control data."
            )
            return
        }
        errorMessage = nil
        portableContainerURL = canonical
        move(to: .reviewTriptych)
    }

    private func save() {
        guard !isSaving, !isRegisteringTriptych else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let selection: WorkspaceSetupSelection
                switch setupPath {
                case .createNew:
                    guard let baseLocationURL else {
                        isSaving = false
                        return
                    }
                    selection = try await context.prepareTriptychStructure(
                        baseLocationURL,
                        triptychName
                    )
                    paperAnalysisURL = selection.paperAnalysisURL
                    topicKnowledgeURL = selection.topicKnowledgeURL
                    outputURL = selection.outputURL
                    portableContainerURL = selection.portableContainerURL
                case .existingFolders:
                    guard let paperAnalysisURL,
                          let topicKnowledgeURL,
                          let outputURL,
                          let portableContainerURL else {
                        isSaving = false
                        return
                    }
                    selection = WorkspaceSetupSelection(
                        paperAnalysisURL: paperAnalysisURL,
                        topicKnowledgeURL: topicKnowledgeURL,
                        outputURL: outputURL,
                        portableContainerURL: portableContainerURL,
                        triptychID: context.targetTriptychID,
                        triptychName: triptychName
                    )
                }

                let preparesAgent = context.offersAgentPreparation
                if preparesAgent {
                    isSaving = false
                    isRegisteringTriptych = true
                    move(to: .agent)
                }

                try await context.configure(selection)
                isSaving = false
                isRegisteringTriptych = false
                if preparesAgent {
                    if let pendingAgentOutcome {
                        agentOutcome = pendingAgentOutcome
                        self.pendingAgentOutcome = nil
                        move(to: .ready)
                    }
                } else {
                    agentOutcome = .notOffered
                    move(to: .ready)
                }
            } catch {
                isSaving = false
                isRegisteringTriptych = false
                pendingAgentOutcome = nil
                agentOutcome = .notOffered
                errorMessage = error.localizedDescription
                if step == .agent {
                    move(to: .reviewTriptych, movingForward: false)
                }
            }
        }
    }

    private func loadCurrentValuesIfNeeded(force: Bool = false) {
        guard force || !loadedCurrentValues else { return }
        loadedCurrentValues = true
        guard let assignment = targetAssignment else { return }
        setupPath = .existingFolders
        paperAnalysisURL = assignedURL(for: .paperAnalysis)
        topicKnowledgeURL = assignedURL(for: .topicKnowledge)
        outputURL = assignedURL(for: .output)
        triptychName = assignment.triptych.name
    }

    private func loadPortableContainerIfAvailable() async {
        guard let outputURL else {
            portableContainerURL = nil
            return
        }
        if let registered = await context.portableContainerURL(outputURL) {
            portableContainerURL = registered
        }
    }

    private var targetAssignment: TriptychAssignment? {
        if let targetTriptychID = context.targetTriptychID {
            return context.registeredTriptychs.first(where: { $0.id == targetTriptychID })
        }
        return context.workspaceAssignment
    }

    private func assignedURL(for slot: WorkspaceVaultSlot) -> URL? {
        targetAssignment?.vault(for: slot).map {
            URL(fileURLWithPath: $0.canonicalPath, isDirectory: true)
        }
    }
}

private struct BootstrapFooter: View {
    let showsBack: Bool
    let primaryTitle: LocalizedStringResource
    let primaryDisabled: Bool
    let onBack: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(ScholiumColorRole.separator.color)
                .frame(height: 1)
            HStack(spacing: 12) {
                if showsBack {
                    Button("Back", action: onBack)
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                Button(action: onPrimary) {
                    Text(primaryTitle)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(primaryDisabled)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .background(ScholiumColorRole.documentBackground.color)
    }
}

private struct BootstrapStepCanvas<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: 420, maxHeight: .infinity, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 32)
            .padding(.top, 68)
            .padding(.bottom, 88)
    }
}

private struct BootstrapStepHeading: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(title)
                .font(ScholiumTypography.Bootstrap.title)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(
            maxWidth: .infinity,
            alignment: alignment == .center ? .center : .leading
        )
    }
}

private struct BootstrapWelcomeStep: View {
    var body: some View {
        BootstrapStepCanvas {
            VStack(alignment: .leading, spacing: 0) {
                Text("Scholium")
                    .font(ScholiumTypography.Bootstrap.wordmark)
                    .accessibilityAddTraits(.isHeader)

                Text("A local-first, document-authoritative research environment for philosophy and the humanities.")
                    .font(ScholiumTypography.Bootstrap.statement)
                    .tracking(-0.1)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)

                Text("The research document—not a dashboard, task board, or Agent conversation—remains the primary interface.")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)

                Rectangle()
                    .fill(ScholiumColorRole.separator.color)
                    .frame(height: 1)
                    .padding(.vertical, 24)

                Text("A field of inquiry takes shape as a Triptych.")
                    .font(ScholiumTypography.interface(.sectionTitle))

                HStack(alignment: .top, spacing: 16) {
                    BootstrapWelcomeTriptychRole(
                        title: "Analyses",
                        detail: "Sources and interpretations"
                    )
                    BootstrapWelcomeTriptychRole(
                        title: "Topics",
                        detail: "Concepts and debates"
                    )
                    BootstrapWelcomeTriptychRole(
                        title: "Works",
                        detail: "Arguments of your own"
                    )
                }
                .padding(.top, 16)

                Text("Markdown stays ordinary and inspectable. Reading, writing, Search, Connections, review, and recovery work without an Agent.")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 22)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .accessibilityIdentifier("scholium.bootstrap.welcome")
    }
}

private struct BootstrapWelcomeTriptychRole: View {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(ScholiumTypography.interface(.sectionTitle))
            Text(detail)
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct BootstrapChoosePathStep: View {
    let selection: BootstrapSetupPath
    let chooseCreateNew: () -> Void
    let chooseExisting: () -> Void

    var body: some View {
        BootstrapStepCanvas {
            VStack(alignment: .leading, spacing: 20) {
                BootstrapStepHeading(
                    title: "Choose a Starting Point",
                    subtitle: "Create the Triptych together, or connect the folders you already use."
                )
                BootstrapSetupPathChoice(
                    title: "Create a New Triptych",
                    detail: "Choose one parent location. Scholium prepares Analyses, Topics, Works, and .scholium together.",
                    symbol: "folder.badge.plus",
                    isSelected: selection == .createNew,
                    action: chooseCreateNew
                )
                BootstrapSetupPathChoice(
                    title: "Connect Existing Folders",
                    detail: "Keep the three folders you already use and authorize their detected parent once.",
                    symbol: "folder.badge.gearshape",
                    isSelected: selection == .existingFolders,
                    action: chooseExisting
                )
                Text("You can manage Triptych locations later in Research Guidance Settings.")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.mutedText)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .accessibilityIdentifier("scholium.bootstrap.startingPoint")
    }
}

private struct BootstrapSetupPathChoice: View {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .scholiumSymbolStyle(.prominent)
                    .foregroundStyle(
                        isSelected
                            ? ScholiumColorRole.accent.color
                            : ScholiumColorRole.secondaryText.color
                    )
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(ScholiumTypography.interface(.sectionTitle))
                        .scholiumForeground(.primaryText)
                    Text(detail)
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(
                        isSelected
                            ? ScholiumColorRole.accent.color
                            : ScholiumColorRole.mutedText.color
                    )
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? ScholiumColorRole.accent.color.opacity(0.08)
                    : ScholiumColorRole.surfaceBackground.color
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected
                            ? ScholiumColorRole.accent.color
                            : ScholiumColorRole.separator.color,
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct BootstrapCreateStructureStep: View {
    @Binding var triptychName: String
    let parentURL: URL?
    let proposedRootURL: URL?
    let chooseParent: () -> Void

    var body: some View {
        BootstrapStepCanvas {
            VStack(alignment: .leading, spacing: 20) {
                BootstrapStepHeading(
                    title: "Create a Research Structure",
                    subtitle: "Name the Triptych and choose its parent location once."
                )
                VStack(alignment: .leading, spacing: 8) {
                    Text("Triptych Name")
                        .font(ScholiumTypography.interface(.rowTitle))
                    TextField("Triptych Name", text: $triptychName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("scholium.triptychName")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Parent Location")
                        .font(ScholiumTypography.interface(.rowTitle))
                    BootstrapPathSelectionRow(
                        path: parentURL,
                        emptyText: "No location selected",
                        buttonTitle: "Choose Location…",
                        action: chooseParent
                    )
                }
                BootstrapStructurePreview(rootURL: proposedRootURL)
                Text("Nothing is created until you review and confirm the structure.")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.mutedText)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .accessibilityIdentifier("scholium.bootstrap.createStructure")
    }
}

private struct BootstrapExistingFolderStep: View {
    let title: LocalizedStringResource
    let explanation: LocalizedStringResource
    let path: URL?
    let chooseAction: () -> Void

    var body: some View {
        BootstrapStepCanvas {
            VStack(alignment: .leading, spacing: 24) {
                BootstrapStepHeading(title: title, subtitle: explanation)
                BootstrapPathSelectionRow(
                    path: path,
                    emptyText: "No folder selected",
                    buttonTitle: "Choose Folder…",
                    action: chooseAction
                )
                Text("Only this folder is selected at this step.")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.mutedText)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct BootstrapPathSelectionRow: View {
    let path: URL?
    let emptyText: LocalizedStringResource
    let buttonTitle: LocalizedStringResource
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: path == nil ? "folder" : "folder.fill")
                    .foregroundStyle(
                        path == nil
                            ? ScholiumColorRole.secondaryText.color
                            : ScholiumColorRole.accent.color
                    )
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Group {
                    if let path {
                        Text(path.path(percentEncoded: false))
                    } else {
                        Text(emptyText)
                    }
                }
                .font(ScholiumTypography.exact(.body))
                .foregroundStyle(
                    path == nil
                        ? ScholiumColorRole.secondaryText.color
                        : ScholiumColorRole.primaryText.color
                )
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)
                Spacer(minLength: 8)
            }
            Rectangle()
                .fill(ScholiumColorRole.separator.color)
                .frame(height: 1)
            HStack {
                Spacer()
                Button(action: action) {
                    Text(buttonTitle)
                }
            }
        }
        .padding(16)
        .background(ScholiumColorRole.surfaceBackground.color)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct BootstrapAuthorizeParentStep: View {
    let rootURL: URL?

    var body: some View {
        BootstrapStepCanvas {
            VStack(alignment: .leading, spacing: 22) {
                BootstrapStepHeading(
                    title: "Authorize the Detected Folder",
                    subtitle: "Scholium needs access beside Works for the portable .scholium control folder."
                )
                BootstrapExplanationBlock(
                    symbol: "location.fill",
                    title: "Folder Detected from Works",
                    detail: rootURL?.path(percentEncoded: false) ?? "Works has not been selected"
                )
                Label {
                    Text("macOS still requires one system confirmation. The detected folder opens directly, so you do not browse the file tree again.")
                        .font(ScholiumTypography.interface(.body))
                        .scholiumForeground(.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lock.shield")
                        .scholiumForeground(.accent)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .accessibilityIdentifier("scholium.bootstrap.authorizeParent")
    }
}

private struct BootstrapExplanationBlock: View {
    let symbol: String
    let title: LocalizedStringResource
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .scholiumSymbolStyle(.prominent)
                .scholiumForeground(.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(ScholiumTypography.interface(.rowTitle))
                Text(detail)
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(ScholiumColorRole.apparatusSurfaceBackground.color)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(ScholiumColorRole.separator.color, lineWidth: 1)
        }
    }
}

private struct BootstrapReviewTriptychStep: View {
    let setupPath: BootstrapSetupPath
    let rootURL: URL?
    let analysesURL: URL?
    let topicsURL: URL?
    let worksURL: URL?

    var body: some View {
        BootstrapStepCanvas {
            VStack(alignment: .leading, spacing: 20) {
                BootstrapStepHeading(
                    title: setupPath == .createNew
                        ? "Review the New Triptych"
                        : "Review the Connected Triptych",
                    subtitle: "Research files remain ordinary folders and exact Markdown remains authoritative."
                )
                if setupPath == .createNew {
                    BootstrapStructurePreview(rootURL: rootURL)
                } else {
                    VStack(spacing: 10) {
                        BootstrapFolderSummaryRow(title: "Analyses", path: analysesURL)
                        BootstrapFolderSummaryRow(title: "Topics", path: topicsURL)
                        BootstrapFolderSummaryRow(title: "Works", path: worksURL)
                        BootstrapFolderSummaryRow(title: "Authorized Parent", path: rootURL)
                    }
                }
                Label {
                    Text("Agent setup comes next and remains optional. The copied prompt asks your Agent to inspect and create only the applicable instruction file.")
                        .font(ScholiumTypography.interface(.body))
                        .scholiumForeground(.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "person.badge.key")
                        .scholiumForeground(.accent)
                }
                Text("Agent write-set extensions ask you every time by default. You can change the Triptych collaboration policy later in Research Guidance Settings.")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("scholium.bootstrap.permissionDefault")
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .accessibilityIdentifier("scholium.bootstrap.review")
    }
}

private struct BootstrapStructurePreview: View {
    let rootURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Proposed Structure")
                .font(ScholiumTypography.interface(.sectionTitle))
            Text(rootURL?.path(percentEncoded: false) ?? "Chosen location/Triptych name")
                .font(ScholiumTypography.exact(.small))
                .scholiumForeground(.secondaryText)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
            Rectangle()
                .fill(ScholiumColorRole.separator.color)
                .frame(height: 1)
            HStack(alignment: .top, spacing: 16) {
                BootstrapRoleSummary(title: "Analyses", detail: "Evidence")
                BootstrapRoleSummary(title: "Topics", detail: "Synthesis")
                BootstrapRoleSummary(title: "Works", detail: "Writing")
            }
            Text(".scholium/ · portable control folder")
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BootstrapRoleSummary: View {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(ScholiumTypography.interface(.sectionTitle))
            Text(detail)
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BootstrapFolderSummaryRow: View {
    let title: LocalizedStringResource
    let path: URL?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(ScholiumTypography.interface(.rowTitle))
                .frame(width: 112, alignment: .leading)
            Text(path?.path(percentEncoded: false) ?? "Not selected")
                .font(ScholiumTypography.exact(.small))
                .scholiumForeground(.secondaryText)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

private struct BootstrapReadyStep: View {
    let triptychName: String
    let rootURL: URL?
    let agentOutcome: BootstrapAgentOutcome

    var body: some View {
        BootstrapStepCanvas {
            VStack(spacing: 18) {
                BootstrapStepHeading(
                    title: "Your Triptych Is Ready",
                    subtitle: completionSubtitle,
                    alignment: .center
                )
                VStack(spacing: 0) {
                    BootstrapCompletionStatusRow(
                        symbol: "rectangle.3.group",
                        title: triptychName.isEmpty ? "Triptych Ready" : triptychName,
                        detail: rootURL?.path(percentEncoded: false) ?? "Configured"
                    )
                    if agentOutcome != .notOffered {
                        Rectangle()
                            .fill(ScholiumColorRole.separator.color)
                            .frame(height: 1)
                        BootstrapCompletionStatusRow(
                            symbol: agentOutcome == .confirmedByResearcher
                                ? "person.crop.circle.badge.checkmark"
                                : "clock",
                            title: agentOutcome == .confirmedByResearcher
                                ? "Agent Ready — Confirmed by You"
                                : "Agent Setup Deferred",
                            detail: agentOutcome == .confirmedByResearcher
                                ? "External Agent project and instructions reported ready"
                                : "Workspace opens without an Agent and does not nag"
                        )
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .accessibilityIdentifier("scholium.bootstrap.ready")
    }

    private var completionSubtitle: LocalizedStringResource {
        switch agentOutcome {
        case .confirmedByResearcher:
            "Your research structure is configured and Agent setup is researcher-confirmed."
        case .deferred:
            "Your research structure is configured. You can prepare an Agent later when needed."
        case .notOffered:
            "Your research structure is configured."
        }
    }
}

private struct BootstrapCompletionStatusRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .scholiumSymbolStyle(.prominent)
                .scholiumForeground(.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ScholiumTypography.interface(.rowTitle))
                Text(detail)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
    }
}

private struct BootstrapSetupStatus: View {
    let message: String
    let isError: Bool

    var body: some View {
        Label(
            message,
            systemImage: isError
                ? "exclamationmark.triangle.fill"
                : "folder.badge.questionmark"
        )
        .font(ScholiumTypography.interface(.small))
        .scholiumForeground(isError ? .destructive : .attention)
        .lineLimit(2)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ScholiumColorRole.documentBackground.color)
        .accessibilityLabel("Workspace setup: \(message)")
    }
}
