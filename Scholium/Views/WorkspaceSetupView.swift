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
    let targetTriptychID: UUID?
    let workspaceAssignment: TriptychAssignment?
    let registeredTriptychs: [TriptychAssignment]
    let recoveryMessage: String?
    let refreshAssignment: () async -> Void
    let portableContainerURL: (URL) async -> URL?
    let prepareTriptychStructure: (URL, String) async throws -> WorkspaceSetupSelection
    let preserveUnsupportedPortableControl: (URL, URL, UUID?) async throws -> URL
    let configure: (WorkspaceSetupSelection) async throws -> Void
    let completeBootstrap: () -> Void
    let dismiss: () -> Void
}

struct WorkspaceSetupView: View {
    let context: WorkspaceSetupContext

    var body: some View {
        BootstrapFlowView(context: context)
            .frame(
                minWidth: ScholiumMetrics.Onboarding.minimumWidth,
                minHeight: ScholiumMetrics.Onboarding.minimumHeight
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .interactiveDismissDisabled()
    }
}

private enum BootstrapSetupPath {
    case createNew
    case existingFolders
}

private enum BootstrapStep: Hashable {
    case welcome
    case createStructure
    case existingFolders
}

private struct BootstrapFlowView: View {
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    @AccessibilityFocusState private var focusedHeading: BootstrapStep?

    let context: WorkspaceSetupContext

    @State private var step: BootstrapStep = .welcome
    @State private var setupPath: BootstrapSetupPath = .createNew
    @State private var baseLocationURL: URL?
    @State private var paperAnalysisURL: URL?
    @State private var topicKnowledgeURL: URL?
    @State private var outputURL: URL?
    @State private var portableContainerURL: URL?
    @State private var triptychName = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var didConfigure = false
    @State private var preparedSelection: WorkspaceSetupSelection?
    @State private var pendingPortableControlRecovery: WorkspaceSetupSelection?
    @State private var loadedCurrentValues = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.regionContentInset) {
                    stepContent
                        .disabled(isSaving || didConfigure)
                    if let message = errorMessage ?? context.recoveryMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("scholium.bootstrap.error")
                    }
                }
                .frame(maxWidth: ScholiumMetrics.Onboarding.contentMaximumWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(ScholiumMetrics.Onboarding.contentInset)
            }
            if step != .welcome {
                Divider()
                footer
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .buttonStyle(.automatic)
        .task {
            await context.refreshAssignment()
            loadCurrentValuesIfNeeded()
            await loadPortableContainerIfAvailable()
        }
        .onChange(of: context.workspaceAssignment) { _, _ in
            guard !isSaving, !didConfigure else { return }
            loadCurrentValuesIfNeeded()
        }
        .onChange(of: outputURL) { oldValue, newValue in
            let oldParent = oldValue?.deletingLastPathComponent().standardizedFileURL.path
            let newParent = newValue?.deletingLastPathComponent().standardizedFileURL.path
            if oldParent != newParent,
                portableContainerURL?.resolvingSymlinksInPath().standardizedFileURL
                    != detectedParentURL
            {
                portableContainerURL = nil
            }
            Task { await loadPortableContainerIfAvailable() }
        }
        .onExitCommand(perform: moveBack)
        .confirmationDialog(
            "Archive and Rebuild Portable Control?",
            isPresented: Binding(
                get: { pendingPortableControlRecovery != nil },
                set: { if !$0 { pendingPortableControlRecovery = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Archive and Rebuild", role: .destructive) {
                recoverPortableControl()
            }
            Button("Cancel", role: .cancel) {
                pendingPortableControlRecovery = nil
            }
        } message: {
            Text(
                "Scholium will move the entire existing .scholium folder to a uniquely named sibling recovery folder, preserving its exact files without interpreting the old schema. Analyses, Topics, and Works will not be changed. Scholium will then create current portable control state."
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.bootstrap")
    }

    private var footer: some View {
        HStack(spacing: ScholiumGrid.Spacing.nestedContentInset) {
            Button("Back", action: moveBack)
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving || didConfigure)
            Spacer()
            if isSaving || (didConfigure && context.recoveryMessage == nil) {
                ProgressView()
                    .controlSize(.small)
                Text(isSaving ? "Setting Up Triptych…" : "Opening Workspace…")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    if didConfigure {
                        openWorkspace()
                    } else {
                        save()
                    }
                } label: {
                    Text(primaryTitle)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!didConfigure && !selectionIsReady)
            }
        }
        .padding(.horizontal, ScholiumMetrics.Onboarding.contentInset)
        .padding(.vertical, ScholiumGrid.Spacing.sectionSeparation)
    }

    private var primaryTitle: LocalizedStringResource {
        if didConfigure { return "Open Workspace" }
        if setupPath == .createNew, preparedCurrentSelection != nil { return "Finish Setup and Open" }
        return setupPath == .createNew ? "Create and Open" : "Connect and Open"
    }

    private var sanitizedTriptychName: String? {
        let name = triptychName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        guard !name.isEmpty, name != ".", name != ".." else { return nil }
        return name
    }

    private var proposedTriptychRootURL: URL? {
        guard let baseLocationURL, let sanitizedTriptychName else { return nil }
        return baseLocationURL.resolvingSymlinksInPath()
            .appendingPathComponent(sanitizedTriptychName, isDirectory: true)
    }

    private var preparedCurrentSelection: WorkspaceSetupSelection? {
        guard let preparedSelection,
            preparedSelection.portableContainerURL.standardizedFileURL
                == proposedTriptychRootURL?.standardizedFileURL
        else { return nil }
        return preparedSelection
    }

    private var detectedParentURL: URL? {
        outputURL?.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
    }

    private var existingSelectionIsReady: Bool {
        guard paperAnalysisURL != nil, topicKnowledgeURL != nil, outputURL != nil,
            let portableContainerURL, let detectedParentURL
        else { return false }
        return portableContainerURL.resolvingSymlinksInPath().standardizedFileURL == detectedParentURL
    }

    private var selectionIsReady: Bool {
        setupPath == .createNew ? proposedTriptychRootURL != nil : existingSelectionIsReady
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            welcome
        case .createStructure:
            createStructure
        case .existingFolders:
            existingFolders
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.regionContentInset) {
            if let url = Bundle.module.url(forResource: "manicule-canonical", withExtension: "png"),
                let image = NSImage(contentsOf: url)
            {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: ScholiumMetrics.Onboarding.welcomeArtworkHeight)
                    .accessibilityHidden(true)
            }
            heading("Welcome to Scholium", subtitle: "A research space built around your Markdown files.")
            GroupBox {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                    BootstrapRoleDescription(title: "Analyses", detail: "Sources and interpretations")
                    BootstrapRoleDescription(title: "Topics", detail: "Concepts and debates")
                    BootstrapRoleDescription(title: "Works", detail: "Arguments of your own")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(ScholiumGrid.Spacing.inlineControlGap)
            }
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Button("Create a New Triptych") { choose(.createNew) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("scholium.bootstrap.createNew")
                Button("Connect Existing Folders") { choose(.existingFolders) }
                    .accessibilityIdentifier("scholium.bootstrap.connectExisting")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.bootstrap.welcome")
    }

    private var createStructure: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.regionContentInset) {
            heading("Create a New Triptych")
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Text("Triptych Name").font(.headline)
                TextField("Triptych Name", text: $triptychName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("scholium.triptychName")
            }
            BootstrapFolderRow(
                title: "Location", path: baseLocationURL,
                buttonTitle: "Choose Location…", identifier: "scholium.bootstrap.chooseLocation",
                action: chooseParentLocation
            )
            GroupBox {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                    Text("Proposed Structure").font(.headline)
                    if let root = proposedTriptychRootURL {
                        BootstrapPath(path: root)
                    } else {
                        Text("Choose a name and location to preview the new folder.")
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                        Label("Analyses", systemImage: "folder")
                        Label("Topics", systemImage: "folder")
                        Label("Works", systemImage: "folder")
                    }
                    Text("Scholium also creates a .scholium folder for portable control data.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(ScholiumGrid.Spacing.inlineControlGap)
            }
            Group {
                if preparedCurrentSelection != nil {
                    Text("The folders have been created. Retry to finish setting up this Triptych.")
                } else {
                    Text("A new folder will be created at this location. Existing folders will not be replaced.")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.bootstrap.createStructure")
    }

    private var existingFolders: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.regionContentInset) {
            heading("Connect Existing Folders", subtitle: "Choose a folder for each part of your Triptych. Your research files stay in place.")
            BootstrapFolderRow(
                title: "Analyses", path: paperAnalysisURL,
                buttonTitle: "Choose Analyses…", identifier: "scholium.bootstrap.chooseAnalyses"
            ) {
                chooseDirectory(title: "Choose Analyses Folder") { paperAnalysisURL = $0 }
            }
            BootstrapFolderRow(
                title: "Topics", path: topicKnowledgeURL,
                buttonTitle: "Choose Topics…", identifier: "scholium.bootstrap.chooseTopics"
            ) {
                chooseDirectory(title: "Choose Topics Folder") { topicKnowledgeURL = $0 }
            }
            BootstrapFolderRow(
                title: "Works", path: outputURL,
                buttonTitle: "Choose Works…", identifier: "scholium.bootstrap.chooseWorks"
            ) {
                chooseDirectory(title: "Choose Works Folder") { outputURL = $0 }
            }
            if let parent = detectedParentURL {
                Divider()
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    Text("Folder Containing Works").font(.headline)
                    BootstrapPath(path: parent)
                    Text("Scholium needs access to this folder to store portable control data in .scholium beside Works.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if portableContainerURL?.resolvingSymlinksInPath().standardizedFileURL == parent {
                        Label("Folder Access Granted", systemImage: "checkmark.circle")
                    } else {
                        Button("Authorize This Folder", action: authorizeDetectedParent)
                            .accessibilityIdentifier("scholium.bootstrap.authorizeParent")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.bootstrap.existingFolders")
    }

    private func heading(_ title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil) -> some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text(title)
                .font(.title)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusedHeading, equals: step)
            if let subtitle {
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func choose(_ path: BootstrapSetupPath) {
        setupPath = path
        step = path == .createNew ? .createStructure : .existingFolders
        errorMessage = nil
        focusedHeading = step
    }

    private func moveBack() {
        guard !isSaving, !didConfigure else { return }
        step = .welcome
        errorMessage = nil
        focusedHeading = .welcome
    }

    private func openWorkspace() {
        context.completeBootstrap()
        context.dismiss()
    }

    private func chooseParentLocation() {
        chooseDirectory(
            title: "Choose a Parent Location",
            prompt: "Choose Location"
        ) { baseLocationURL = $0 }
    }

    private func chooseDirectory(
        title: LocalizedStringResource,
        prompt: LocalizedStringResource = "Choose Folder",
        receive: @escaping @MainActor (URL) -> Void
    ) {
        let request = ScholiumFileSelectionRequest(
            title: String(localized: title),
            prompt: String(localized: prompt),
            kind: .directory(canCreateDirectories: true)
        )
        Task { @MainActor in
            do {
                guard
                    let url =
                        try await fileSelectionPresenter
                        .requiredForFileSelection()
                        .selectURL(request)
                else { return }
                errorMessage = nil
                receive(url)
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func authorizeDetectedParent() {
        guard let expected = detectedParentURL else { return }
        let request = ScholiumFileSelectionRequest(
            title: String(localized: "Authorize the Folder Containing Works"),
            message: String(
                localized: "Confirm this folder so Scholium can use the portable .scholium control folder beside Works."
            ),
            prompt: String(localized: "Authorize"),
            initialDirectoryURL: expected,
            kind: .directory(canCreateDirectories: false),
            constraint: .exactCanonicalDirectory(
                expected,
                rejectionMessage: String(
                    localized: "Authorize the detected folder itself; no other folder can contain this Triptych's portable control data."
                )
            )
        )
        Task { @MainActor in
            do {
                guard
                    let selected =
                        try await fileSelectionPresenter
                        .requiredForFileSelection()
                        .selectURL(request)
                else { return }
                errorMessage = nil
                portableContainerURL = selected
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        guard !isSaving, !didConfigure, selectionIsReady else { return }
        isSaving = true
        errorMessage = nil
        Task {
            var attemptedSelection: WorkspaceSetupSelection?
            do {
                let selection: WorkspaceSetupSelection
                switch setupPath {
                case .createNew:
                    guard let baseLocationURL else {
                        isSaving = false
                        return
                    }
                    if let preparedSelection = preparedCurrentSelection {
                        selection = WorkspaceSetupSelection(
                            paperAnalysisURL: preparedSelection.paperAnalysisURL,
                            topicKnowledgeURL: preparedSelection.topicKnowledgeURL,
                            outputURL: preparedSelection.outputURL,
                            portableContainerURL: preparedSelection.portableContainerURL,
                            triptychID: preparedSelection.triptychID,
                            triptychName: triptychName.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    } else {
                        selection = try await context.prepareTriptychStructure(
                            baseLocationURL,
                            triptychName
                        )
                        preparedSelection = selection
                    }
                    paperAnalysisURL = selection.paperAnalysisURL
                    topicKnowledgeURL = selection.topicKnowledgeURL
                    outputURL = selection.outputURL
                    portableContainerURL = selection.portableContainerURL
                case .existingFolders:
                    guard let paperAnalysisURL,
                        let topicKnowledgeURL,
                        let outputURL,
                        let portableContainerURL
                    else {
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
                attemptedSelection = selection

                try await context.configure(selection)
                isSaving = false
                didConfigure = true
                openWorkspace()
            } catch {
                isSaving = false
                if setupPath == .existingFolders,
                    let attemptedSelection,
                    let applicationError = error as? ScholiumApplicationError,
                    case .portableControlRecoveryRequired = applicationError
                {
                    pendingPortableControlRecovery = attemptedSelection
                    errorMessage = nil
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func recoverPortableControl() {
        guard let selection = pendingPortableControlRecovery else { return }
        pendingPortableControlRecovery = nil
        isSaving = true
        errorMessage = nil
        Task {
            do {
                _ = try await context.preserveUnsupportedPortableControl(
                    selection.portableContainerURL,
                    selection.outputURL,
                    selection.triptychID
                )
                try await context.configure(selection)
                isSaving = false
                didConfigure = true
                openWorkspace()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadCurrentValuesIfNeeded() {
        guard !loadedCurrentValues else { return }
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
        if let registered = await context.portableContainerURL(outputURL),
            self.outputURL == outputURL
        {
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

private struct BootstrapRoleDescription: View {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            Text(title).font(.headline)
            Text(detail).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BootstrapFolderRow: View {
    let title: LocalizedStringResource
    let path: URL?
    let buttonTitle: LocalizedStringResource
    let identifier: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button(action: action) { Text(buttonTitle) }
                    .accessibilityIdentifier(identifier)
            }
            if let path {
                BootstrapPath(path: path)
            } else {
                Text("No folder selected").foregroundStyle(.secondary)
            }
        }
    }
}

private struct BootstrapPath: View {
    let path: URL

    var body: some View {
        Text(path.path(percentEncoded: false))
            .font(.callout)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}
