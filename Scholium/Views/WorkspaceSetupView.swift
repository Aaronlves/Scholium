import ScholiumContracts
import AppKit
import SwiftUI

struct WorkspaceSetupSelection {
    let paperAnalysisURL: URL
    let topicKnowledgeURL: URL
    let outputURL: URL
    let portableContainerURL: URL
    let triptychID: UUID?
    let triptychName: String
}

/// Immutable window projection plus setup actions supplied by `ContentView`.
/// The setup surface owns only its step-local form state.
struct WorkspaceSetupContext {
    let isCreatingNewTriptych: Bool
    let targetTriptychID: UUID?
    let workspaceAssignment: TriptychAssignment?
    let registeredTriptychs: [TriptychAssignment]
    let recoveryMessage: String?
    let isInitialConfiguration: Bool
    let refreshAssignment: () async -> Void
    let portableContainerURL: (URL) async -> URL?
    let configure: (WorkspaceSetupSelection) async throws -> Void
    let dismiss: () -> Void
}

struct WorkspaceSetupView: View {
    let context: WorkspaceSetupContext

    var body: some View {
        GuidedWorkspaceSetupView(
            context: context,
            completionTitle: context.isCreatingNewTriptych
                ? "Create Triptych"
                : "Use This Triptych"
        )
        .frame(
            minWidth: ScholiumMetrics.Onboarding.minimumWidth,
            maxWidth: .infinity,
            minHeight: ScholiumMetrics.Onboarding.minimumHeight,
            maxHeight: .infinity
        )
        .interactiveDismissDisabled()
    }
}

private enum GuidedSetupStep: Int, CaseIterable {
    case welcome
    case analyses
    case topics
    case works
    case finish
}

private struct GuidedWorkspaceSetupView: View {
    @Environment(\.scholiumReduceMotion) private var reduceMotion

    let context: WorkspaceSetupContext
    let completionTitle: LocalizedStringResource

    @State private var step: GuidedSetupStep = .welcome
    @State private var isMovingForward = true
    @State private var paperAnalysisURL: URL?
    @State private var topicKnowledgeURL: URL?
    @State private var outputURL: URL?
    @State private var portableContainerURL: URL?
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var loadedCurrentValues = false
    @State private var triptychName = ""

    var body: some View {
        VStack(spacing: 0) {
            GuidedSetupProgressHeader(
                currentStep: step.rawValue + 1,
                totalSteps: GuidedSetupStep.allCases.count
            )

            GuidedSetupStepContent(
                step: step,
                paperAnalysisURL: $paperAnalysisURL,
                topicKnowledgeURL: $topicKnowledgeURL,
                outputURL: $outputURL,
                portableContainerURL: $portableContainerURL,
                triptychName: $triptychName
            )
            .id(step)
            .transition(stepTransition)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            GuidedSetupStatus(
                errorMessage: errorMessage,
                recoveryMessage: context.recoveryMessage
            )

            Divider()

            GuidedSetupFooter(
                showsBack: step != .welcome,
                primaryTitle: primaryTitle,
                primaryDisabled: primaryDisabled || isSaving,
                onBack: moveBack,
                onContinue: continueSetup
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
    }

    private var primaryTitle: LocalizedStringResource {
        switch step {
        case .welcome: "Get Started"
        case .analyses, .topics, .works: "Continue"
        case .finish: completionTitle
        }
    }

    private var primaryDisabled: Bool {
        switch step {
        case .welcome: false
        case .analyses: paperAnalysisURL == nil
        case .topics: topicKnowledgeURL == nil
        case .works: outputURL == nil
        case .finish: !canSave
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

    private var canSave: Bool {
        guard let outputURL, let portableContainerURL else { return false }
        return paperAnalysisURL != nil
            && topicKnowledgeURL != nil
            && outputURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
                == portableContainerURL.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func continueSetup() {
        guard !primaryDisabled else { return }
        if step == .finish {
            save()
            return
        }
        guard let next = GuidedSetupStep(rawValue: step.rawValue + 1) else { return }
        isMovingForward = true
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            step = next
        }
    }

    private func moveBack() {
        guard let previous = GuidedSetupStep(rawValue: step.rawValue - 1) else { return }
        isMovingForward = false
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            step = previous
        }
    }

    private func loadCurrentValuesIfNeeded(force: Bool = false) {
        guard force || !loadedCurrentValues else { return }
        loadedCurrentValues = true
        paperAnalysisURL = assignedURL(for: .paperAnalysis)
        topicKnowledgeURL = assignedURL(for: .topicKnowledge)
        outputURL = assignedURL(for: .output)
        triptychName = targetAssignment?.triptych.name ?? ""
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

    private func save() {
        guard let paperAnalysisURL, let topicKnowledgeURL, let outputURL else { return }
        guard let portableContainerURL else { return }
        isSaving = true
        errorMessage = nil
        if context.isInitialConfiguration {
            // `vaultConfig` becomes valid before the async setup callback
            // returns. Clear the sheet route first so that root-level setup
            // cannot briefly re-present itself over the new stable workspace.
            context.dismiss()
        }
        Task {
            do {
                try await context.configure(WorkspaceSetupSelection(
                    paperAnalysisURL: paperAnalysisURL,
                    topicKnowledgeURL: topicKnowledgeURL,
                    outputURL: outputURL,
                    portableContainerURL: portableContainerURL,
                    triptychID: context.targetTriptychID,
                    triptychName: triptychName
                ))
                isSaving = false
                context.dismiss()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct GuidedSetupProgressHeader: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Scholium")
                    .font(.headline)
                    .accessibilityIdentifier("scholium.triptychSetup")
                Spacer()
                Text("Step \(currentStep) of \(totalSteps)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(currentStep), total: Double(totalSteps))
                .progressViewStyle(.linear)
                .accessibilityLabel("Setup progress")
                .accessibilityValue("Step \(currentStep) of \(totalSteps)")
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }
}

private struct GuidedSetupStepContent: View {
    let step: GuidedSetupStep
    @Binding var paperAnalysisURL: URL?
    @Binding var topicKnowledgeURL: URL?
    @Binding var outputURL: URL?
    @Binding var portableContainerURL: URL?
    @Binding var triptychName: String

    @ViewBuilder
    var body: some View {
        switch step {
        case .welcome:
            GuidedSetupWelcomeStep()
        case .analyses:
            GuidedSetupFolderStep(
                title: "Choose Analyses",
                subtitle: "Source reports and evidence.",
                symbol: "doc.text.magnifyingglass",
                folderTitle: "Analyses",
                folderSubtitle: "Source reports and evidence",
                url: $paperAnalysisURL
            )
        case .topics:
            GuidedSetupFolderStep(
                title: "Choose Topics",
                subtitle: "Concepts, debates, and synthesis.",
                symbol: "lightbulb",
                folderTitle: "Topics",
                folderSubtitle: "Concepts, debates, and synthesis",
                url: $topicKnowledgeURL
            )
        case .works:
            GuidedSetupFolderStep(
                title: "Choose Works",
                subtitle: "Papers, chapters, and prose.",
                symbol: "square.and.pencil",
                folderTitle: "Works",
                folderSubtitle: "Papers, chapters, and prose",
                url: $outputURL
            )
        case .finish:
            GuidedSetupFinishStep(
                paperAnalysisURL: paperAnalysisURL,
                topicKnowledgeURL: topicKnowledgeURL,
                outputURL: outputURL,
                portableContainerURL: $portableContainerURL,
                triptychName: $triptychName
            )
        }
    }
}

private struct GuidedSetupWelcomeStep: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "rectangle.3.group")
                .font(.largeTitle.weight(.light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Set Up Scholium")
                .font(.title2.weight(.semibold))
            Text("Choose three folders you control.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 24)
        .accessibilityIdentifier("scholium.guidedSetup.welcome")
    }
}

private struct GuidedSetupFolderStep: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let symbol: String
    let folderTitle: String
    let folderSubtitle: String
    @Binding var url: URL?

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 20)
            Image(systemName: symbol)
                .font(.largeTitle.weight(.light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(spacing: 5) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            WorkspaceFolderRow(
                title: folderTitle,
                subtitle: folderSubtitle,
                symbol: symbol,
                url: $url
            )
            .padding(.top, 8)
            Spacer(minLength: 20)
        }
        .padding(.horizontal, 24)
        .accessibilityIdentifier("scholium.guidedSetup.\(folderTitle.lowercased())")
    }
}

private struct GuidedSetupFinishStep: View {
    let paperAnalysisURL: URL?
    let topicKnowledgeURL: URL?
    let outputURL: URL?
    @Binding var portableContainerURL: URL?
    @Binding var triptychName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Finish")
                    .font(.title2.weight(.semibold))
                Text("Name and authorize this Triptych.")
                    .foregroundStyle(.secondary)
            }

            TextField("Triptych Name", text: $triptychName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("scholium.triptychName")

            VStack(spacing: 7) {
                GuidedSetupSummaryRow(
                    title: "Analyses",
                    symbol: "doc.text.magnifyingglass",
                    url: paperAnalysisURL
                )
                GuidedSetupSummaryRow(
                    title: "Topics",
                    symbol: "lightbulb",
                    url: topicKnowledgeURL
                )
                GuidedSetupSummaryRow(
                    title: "Works",
                    symbol: "square.and.pencil",
                    url: outputURL
                )
            }

            Divider()

            PortableControlFolderRow(
                worksURL: outputURL,
                containerURL: $portableContainerURL
            )
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .accessibilityIdentifier("scholium.guidedSetup.finish")
    }
}

private struct GuidedSetupSummaryRow: View {
    let title: LocalizedStringResource
    let symbol: String
    let url: URL?

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(title)
                .font(.callout.weight(.medium))
            Spacer(minLength: 8)
            Text(url?.lastPathComponent ?? "Not Selected")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(url?.path(percentEncoded: false) ?? "No folder selected")
        }
    }
}

private struct GuidedSetupStatus: View {
    let errorMessage: String?
    let recoveryMessage: String?

    var body: some View {
        if let message = errorMessage ?? recoveryMessage {
            Label(
                message,
                systemImage: errorMessage == nil
                    ? "folder.badge.questionmark"
                    : "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(errorMessage == nil ? .orange : .red)
            .lineLimit(2)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .accessibilityLabel("Workspace setup: \(message)")
        }
    }
}

private struct GuidedSetupFooter: View {
    let showsBack: Bool
    let primaryTitle: LocalizedStringResource
    let primaryDisabled: Bool
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        HStack {
            if showsBack {
                Button("Back", action: onBack)
            }
            Spacer()
            Button(action: onContinue) {
                Text(primaryTitle)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(primaryDisabled)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}
