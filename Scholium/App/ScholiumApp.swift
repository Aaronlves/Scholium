import ScholiumContracts
import AppKit
import Combine
import notify
import QuartzCore
import ScholiumApplication
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ScholiumApplicationDelegate: NSObject, NSApplicationDelegate {
    let windowLifecycleRegistry = ScholiumWindowLifecycleRegistry()
    private var terminationInFlight = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard windowLifecycleRegistry.hasRegisteredWindows else {
            return .terminateNow
        }
        guard !terminationInFlight else { return .terminateLater }
        terminationInFlight = true
        Task { @MainActor in
            do {
                try await windowLifecycleRegistry.flushAll()
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                terminationInFlight = false
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
}

// MARK: - App Entry Point

struct TriptychWindowRoute: Codable, Hashable {
    let windowID: UUID
    let triptychID: UUID?
    let initialDocument: VaultNoteReference?

    init(
        windowID: UUID = UUID(),
        triptychID: UUID? = nil,
        initialDocument: VaultNoteReference? = nil
    ) {
        self.windowID = windowID
        self.triptychID = triptychID
        self.initialDocument = initialDocument
    }
}

enum BootstrapPurpose: String, Codable, Hashable {
    case firstConfiguration
    case newTriptych
    case missingRegistration
}

struct BootstrapWindowRoute: Codable, Hashable {
    let windowID: UUID
    let purpose: BootstrapPurpose
    let targetTriptychID: UUID?

    init(
        windowID: UUID = UUID(),
        purpose: BootstrapPurpose,
        targetTriptychID: UUID? = nil
    ) {
        self.windowID = windowID
        self.purpose = purpose
        self.targetTriptychID = targetTriptychID
    }
}

@main
struct ScholiumApp: App {
    @NSApplicationDelegateAdaptor(ScholiumApplicationDelegate.self) private var applicationDelegate
    @FocusedObject private var focusedWindowModel: WindowModel?
    @StateObject private var applicationBootstrap = ApplicationBootstrapController()

    init() {
        // Document tabs live inside the central split item. Native window
        // tabbing would create a second, whole-window tab system with different
        // state ownership, so it remains disabled.
        NSWindow.allowsAutomaticWindowTabbing = false
        ScholiumFontRegistry.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup(
            id: "scholium-bootstrap",
            for: BootstrapWindowRoute.self,
            content: { route in
                ApplicationBootstrapGate(controller: applicationBootstrap) { workspaceStore in
                    ScholiumBootstrapRoot(
                        workspaceStore: workspaceStore,
                        route: route.wrappedValue,
                        lifecycleRegistry: applicationDelegate.windowLifecycleRegistry
                    )
                }
            },
            defaultValue: {
                BootstrapWindowRoute(purpose: .firstConfiguration)
            }
        )
        .defaultSize(
            width: ScholiumMetrics.Onboarding.preferredWidth,
            height: ScholiumMetrics.Onboarding.preferredHeight
        )
        .windowResizability(.automatic)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)

        WindowGroup(
            id: "scholium-main",
            for: TriptychWindowRoute.self,
            content: { route in
                ApplicationBootstrapGate(controller: applicationBootstrap) { workspaceStore in
                    ScholiumWindowRoot(
                        workspaceStore: workspaceStore,
                        route: route.wrappedValue,
                        lifecycleRegistry: applicationDelegate.windowLifecycleRegistry
                    )
                }
            },
            defaultValue: { TriptychWindowRoute() }
        )
        .defaultSize(
            width: ScholiumRuntimeIsolation.initialWorkspaceWidth()
                ?? ScholiumMetrics.Workspace.preferredWidth,
            height: ScholiumMetrics.Workspace.preferredHeight
        )
        .windowResizability(.automatic)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(
            ScholiumRuntimeIsolation.disablesSystemWindowRestoration()
                ? .disabled
                : .automatic
        )
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { ScholiumCommands(storageReady: applicationBootstrap.isReady) }

        UtilityWindow("Research Record", id: "scholium-research-record") {
            ScholiumResearchRecordUtilityRoot(appState: focusedWindowModel)
        }
        .defaultSize(width: 760, height: 680)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commandsRemoved()

        Settings {
            ApplicationBootstrapGate(controller: applicationBootstrap) { workspaceStore in
                ScholiumSettingsRoot(workspaceStore: workspaceStore)
            }
        }

        #if DEBUG
        Window(
            "Research Workflow Interface Proofs",
            id: "scholium-research-workflow-proofs"
        ) {
            ResearchWorkflowPreviewCatalog()
        }
        .defaultSize(width: 1_080, height: 760)
        .windowResizability(.automatic)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commandsRemoved()
        #endif
    }
}

/// A secondary scholarly-record window that follows the focused workspace.
/// It consumes the focused window model but owns no document or editor state.
private struct ScholiumResearchRecordUtilityRoot: View {
    let appState: WindowModel?

    var body: some View {
        Group {
            if let appState {
                ScholiumResearchRecordFocusedContent(appState: appState)
            } else {
                ContentUnavailableView(
                    "No Active Triptych",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Focus a Scholium workspace to view its Research Record.")
                )
            }
        }
        .scholiumSurface(.denseEvidence)
    }
}

private struct ScholiumResearchRecordFocusedContent: View {
    @ObservedObject var appState: WindowModel
    @State private var browserModel = ResearchRecordBrowserModel()

    var body: some View {
        if let assignment = appState.workspaceAssignment {
            ResearchRecordBrowserView(
                model: browserModel,
                triptychName: assignment.triptych.name,
                initialNoteID: currentNoteID,
                context: ResearchRecordBrowserContext(
                    setPinned: { id, isPinned in
                        try await appState.researchController.setResearchRecordPinned(
                            id: id,
                            isPinned: isPinned
                        )
                    },
                    deletePermanently: { id in
                        try await appState.researchController.deleteResearchRecordPermanently(id: id)
                    },
                    comparison: { recordID, noteID in
                        try await appState.researchController.researchRecordComparison(
                            recordID: recordID,
                            noteID: noteID
                        )
                    },
                    openNote: { noteID, note, sourceLine in
                        appState.requestOpenNote(
                            note,
                            stableNoteID: noteID,
                            sourceLine: sourceLine
                        )
                    }
                )
            )
            .onAppear {
                browserModel.prepareForOpen(
                    triptychID: assignment.id,
                    records: finishedRecords,
                    initialNoteID: currentNoteID
                )
            }
            .onReceive(appState.researchController.$records) { snapshot in
                browserModel.receive(
                    triptychID: assignment.id,
                    records: snapshot?.finishedResearchRecords ?? [],
                    currentNoteID: currentNoteID
                )
            }
        } else {
            ContentUnavailableView(
                "No Active Triptych",
                systemImage: "clock.arrow.circlepath",
                description: Text("Focus a Scholium workspace to view its Research Record.")
            )
        }
    }

    private var currentNoteID: UUID? {
        appState.currentDocumentDescriptor?.sessionKey.noteID
    }

    private var finishedRecords: [PortableResearchRecord] {
        appState.researchController.records?.finishedResearchRecords ?? []
    }
}

/// The launch and first-run boundary. Bootstrap deliberately does not create
/// the workspace split controller or install the workspace toolbar. Once a
/// Triptych is available it opens a configured workspace window and closes.
private struct ScholiumBootstrapRoot: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    private let route: BootstrapWindowRoute
    private let lifecycleRegistry: ScholiumWindowLifecycleRegistry
    @StateObject private var model: ScholiumBootstrapModel
    @State private var isResolvingWorkspace = true
    @State private var didRouteToWorkspace = false
    @State private var destinationWindowID: UUID?
    @State private var routingErrorMessage: String?

    init(
        workspaceStore: WorkspaceStore,
        route: BootstrapWindowRoute,
        lifecycleRegistry: ScholiumWindowLifecycleRegistry
    ) {
        self.route = route
        self.lifecycleRegistry = lifecycleRegistry
        _model = StateObject(wrappedValue: ScholiumBootstrapModel(
            workspaceStore: workspaceStore,
            route: route
        ))
    }

    var body: some View {
        Group {
            if isResolvingWorkspace {
                ScholiumLaunchPlaceholderView()
            } else {
                WorkspaceSetupView(context: workspaceSetupContext)
            }
        }
        .tint(ScholiumColorRole.accent.color)
        .background(
            BootstrapWindowAttachment(
                windowID: route.windowID,
                lifecycleRegistry: lifecycleRegistry
            )
        )
        .task {
            if openFixtureWorkspaceIfRequested() {
                return
            }
            await model.refresh()
            isResolvingWorkspace = false
            openConfiguredWorkspaceIfAvailable()
        }
        .onChange(of: model.workspaceAssignment?.id) { _, _ in
            openConfiguredWorkspaceIfAvailable()
        }
        .task(id: destinationWindowID) {
            guard let destinationWindowID else { return }
            do {
                try await lifecycleRegistry.waitUntilReady(id: destinationWindowID)
                dismissWindow()
            } catch is CancellationError {
                return
            } catch {
                didRouteToWorkspace = false
                self.destinationWindowID = nil
                routingErrorMessage = error.localizedDescription
            }
        }
    }

    private var workspaceSetupContext: WorkspaceSetupContext {
        WorkspaceSetupContext(
            isCreatingNewTriptych: model.isCreatingNewTriptych,
            targetTriptychID: model.targetTriptychID,
            workspaceAssignment: model.workspaceAssignment,
            registeredTriptychs: model.registeredTriptychs,
            recoveryMessage: routingErrorMessage ?? model.recoveryMessage,
            refreshAssignment: { await model.refresh() },
            portableContainerURL: { await model.portableContainerURL(for: $0) },
            configure: { selection in
                try await model.configure(selection)
            },
            dismiss: { openConfiguredWorkspaceIfAvailable() }
        )
    }

    private func openConfiguredWorkspaceIfAvailable() {
        guard !didRouteToWorkspace,
              let triptychID = model.workspaceAssignment?.id,
              model.isReadyToOpenWorkspace
        else { return }
        openWorkspace(TriptychWindowRoute(triptychID: triptychID))
    }

    /// UI automation supplies an explicit disposable fixture root. Bootstrap
    /// remains the default scene, so it must hand that isolated launch to the
    /// workspace scene before a WindowModel exists to consume the fixture.
    /// Real launches never take this path and continue through setup or the
    /// registered-Triptych restore flow above.
    private func openFixtureWorkspaceIfRequested() -> Bool {
        guard ScholiumRuntimeIsolation.fixtureRootURL() != nil,
              !didRouteToWorkspace
        else { return false }
        openWorkspace(
            TriptychWindowRoute(
                windowID: ScholiumRuntimeIsolation.initialWindowSessionID() ?? UUID()
            )
        )
        return true
    }

    private func openWorkspace(_ destination: TriptychWindowRoute) {
        didRouteToWorkspace = true
        routingErrorMessage = nil
        openWindow(id: "scholium-main", value: destination)
        destinationWindowID = destination.windowID
    }
}

/// Bootstrap owns only registration and folder selection. It deliberately has
/// no Document, Discovery, Research, presentation-router, or window-session
/// state; the configured workspace creates those owners after this window
/// completes.
@MainActor
private final class ScholiumBootstrapModel: ObservableObject {
    @Published private(set) var workspaceAssignment: TriptychAssignment?
    @Published private(set) var registeredTriptychs: [TriptychAssignment] = []
    @Published private(set) var recoveryMessage: String?
    @Published private(set) var isReadyToOpenWorkspace = false

    private let workspaceStore: WorkspaceStore
    private let route: BootstrapWindowRoute

    init(workspaceStore: WorkspaceStore, route: BootstrapWindowRoute) {
        self.workspaceStore = workspaceStore
        self.route = route
    }

    var isCreatingNewTriptych: Bool {
        route.purpose == .newTriptych
    }

    var targetTriptychID: UUID? {
        switch route.purpose {
        case .firstConfiguration, .newTriptych: nil
        case .missingRegistration: route.targetTriptychID
        }
    }

    func refresh() async {
        do {
            registeredTriptychs = try await workspaceStore.registeredTriptychs()
            switch route.purpose {
            case .firstConfiguration:
                workspaceAssignment = try? await workspaceStore.defaultTriptych()
                isReadyToOpenWorkspace = workspaceAssignment != nil
            case .newTriptych:
                workspaceAssignment = nil
                isReadyToOpenWorkspace = false
            case .missingRegistration:
                workspaceAssignment = route.targetTriptychID.flatMap { requestedID in
                    registeredTriptychs.first(where: { $0.id == requestedID })
                }
                isReadyToOpenWorkspace = workspaceAssignment != nil
                if workspaceAssignment == nil {
                    recoveryMessage = "This Triptych is no longer registered on this Mac. Choose its three folders again."
                }
            }
        } catch {
            workspaceAssignment = nil
            isReadyToOpenWorkspace = false
            recoveryMessage = error.localizedDescription
        }
    }

    func portableContainerURL(for worksURL: URL) async -> URL? {
        await workspaceStore.portableContainerURL(forWorksURL: worksURL)
    }

    func configure(_ selection: WorkspaceSetupSelection) async throws {
        let capabilities = try await workspaceStore.configureTriptychCapabilities(
            paperAnalysisURL: selection.paperAnalysisURL,
            topicKnowledgeURL: selection.topicKnowledgeURL,
            outputURL: selection.outputURL,
            portableContainerURL: selection.portableContainerURL,
            triptychID: selection.triptychID ?? targetTriptychID,
            triptychName: selection.triptychName
        )
        workspaceAssignment = capabilities.assignment
        registeredTriptychs = try await workspaceStore.registeredTriptychs()
        recoveryMessage = nil
        isReadyToOpenWorkspace = true
    }
}

private struct ScholiumWindowRoot: View {
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    private let route: TriptychWindowRoute
    private let lifecycleRegistry: ScholiumWindowLifecycleRegistry
    @StateObject private var appState: WindowModel
    @StateObject private var windowCoordinator: WorkspaceWindowCoordinator
    @State private var destinationBootstrapWindowID: UUID?

    init(
        workspaceStore: WorkspaceStore,
        route: TriptychWindowRoute,
        lifecycleRegistry: ScholiumWindowLifecycleRegistry
    ) {
        self.route = route
        self.lifecycleRegistry = lifecycleRegistry
        let model = WindowModel(
            workspaceStore: workspaceStore,
            nativeWindowID: route.windowID,
            requestedTriptychID: route.triptychID,
            requestedInitialDocument: route.initialDocument
        )
        _appState = StateObject(wrappedValue: model)
        _windowCoordinator = StateObject(wrappedValue: WorkspaceWindowCoordinator(
            windowID: route.windowID,
            appState: model,
            lifecycleRegistry: lifecycleRegistry
        ))
    }

    var body: some View {
        Group {
            if appState.hasCompletedInitialRestore, appState.vaultConfig != nil {
                ContentView(windowCoordinator: windowCoordinator)
            } else {
                ScholiumLaunchPlaceholderView()
            }
        }
            .environmentObject(appState)
            .toolbar(removing: .sidebarToggle)
            .tint(ScholiumColorRole.accent.color)
            .focusedSceneObject(appState)
            .focusedSceneValue(\.scholiumWorkspaceWindowActions, windowCoordinator.actions)
            .background(
                WorkspaceWindowAttachment(coordinator: windowCoordinator)
            )
            .fileImporter(
                isPresented: $appState.showMarkdownImporter,
                allowedContentTypes: [UTType(filenameExtension: "md") ?? .plainText],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task {
                        do {
                            let imported = try await appState.importMarkdownFiles(urls)
                            let destination = appState.currentWorkspaceSlot?.displayName
                                ?? "current vault"
                            appState.showToast(String(localized: "Imported \(imported.count) Markdown file\(imported.count == 1 ? "" : "s") into \(destination).", table: "Localizable", bundle: .module))
                        } catch {
                            appState.vaultError = error.localizedDescription
                        }
                    }
                case .failure(let error):
                    appState.vaultError = error.localizedDescription
                }
            }
            .sheet(item: $appState.workspaceAccessRecovery) { recovery in
                RestoreWorkspaceAccessView(
                    recovery: recovery,
                    restore: { try await appState.restoreWorkspaceAccess(using: $0) },
                    closeWindow: { dismissWindow() }
                )
            }
            .preferredColorScheme(colorScheme)
            .task(id: route.windowID) {
                windowCoordinator.update(reduceMotion: reduceMotion)
                await appState.restoreWindowSession(id: route.windowID)
                redirectUnconfiguredWindowToBootstrapIfNeeded()
                appState.openRequestedInitialDocumentIfNeeded()
            }
            .task(id: destinationBootstrapWindowID) {
                guard let destinationBootstrapWindowID else { return }
                do {
                    try await lifecycleRegistry.waitUntilReady(
                        id: destinationBootstrapWindowID
                    )
                    dismissWindow()
                } catch is CancellationError {
                    return
                } catch {
                    self.destinationBootstrapWindowID = nil
                    appState.vaultError = error.localizedDescription
                }
            }
            .onAppear {
                windowCoordinator.activate(
                    showResearchRecord: {
                        openWindow(id: "scholium-research-record")
                    },
                    showAttention: { anchor, workspaceSlot, noteScope in
                        appState.attentionPopoverSession.present(
                            from: anchor,
                            workspaceSlot: workspaceSlot,
                            noteScope: noteScope
                        )
                    }
                )
                windowCoordinator.update(reduceMotion: reduceMotion)
            }
            .onChange(of: reduceMotion) { _, reduceMotion in
                windowCoordinator.update(reduceMotion: reduceMotion)
            }
            .onDisappear {
                windowCoordinator.detach()
                appState.persistWindowSessionNow()
            }
    }

    private func redirectUnconfiguredWindowToBootstrapIfNeeded() {
        guard appState.hasCompletedInitialRestore,
              appState.vaultConfig == nil,
              appState.workspaceAccessRecovery == nil,
              destinationBootstrapWindowID == nil
        else { return }
        let destination = BootstrapWindowRoute(
            purpose: appState.requestedTriptychIDForRecovery == nil
                ? .firstConfiguration
                : .missingRegistration,
            targetTriptychID: appState.requestedTriptychIDForRecovery
        )
        windowCoordinator.failReadiness(
            ScholiumWindowLifecycleError.failed(
                "The workspace route has no configured Triptych."
            )
        )
        openWindow(id: "scholium-bootstrap", value: destination)
        destinationBootstrapWindowID = destination.windowID
    }

    private var colorScheme: ColorScheme? {
        switch appState.colorScheme {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}

private struct ScholiumSettingsRoot: View {
    @ObservedObject private var workspaceStore: WorkspaceStore
    @StateObject private var settingsModel: WorkspaceSettingsModel

    init(workspaceStore: WorkspaceStore) {
        self.workspaceStore = workspaceStore
        _settingsModel = StateObject(
            wrappedValue: WorkspaceSettingsModel(
                capabilities: workspaceStore.settingsCapabilities(),
                cssSnippetStore: workspaceStore.cssSnippetStore
            )
        )
    }

    var body: some View {
        ScholiumSettingsView()
            .environmentObject(settingsModel)
            .frame(width: 700, height: 560)
            .task(id: workspaceStore.latestWorkspaceActivation?.runtimeIdentity.activationID) {
                await settingsModel.restorePreferredWorkspaceIfNeeded(
                    activeTriptychID: workspaceStore.latestWorkspaceActivation?.workspaceID
                )
            }
    }
}

struct ScholiumSearchActions {
    let begin: (SearchInvocation) -> Void
}

struct ScholiumSearchActionsFocusedKey: FocusedValueKey {
    typealias Value = ScholiumSearchActions
}

struct ScholiumWorkspaceWindowActionsFocusedKey: FocusedValueKey {
    typealias Value = WorkspaceWindowActions
}

struct ScholiumFocusedResearchActionActions {
    let open: @MainActor (ResearchActionID) -> Void
}

struct ScholiumFocusedResearchActionActionsKey: FocusedValueKey {
    typealias Value = ScholiumFocusedResearchActionActions
}

struct ScholiumFocusedEditorActions {
    let documentID: String
    let isComposing: Bool
    let isAvailable: (MarkdownEditorCommand) -> Bool
    let canCommentOnSelectedPassage: () -> Bool
    let perform: (MarkdownEditorCommand) -> Void
    let performWithArgument: (MarkdownEditorCommand, String) -> Void
    let startComment: () -> Void
}

struct ScholiumFocusedEditorActionsKey: FocusedValueKey {
    typealias Value = ScholiumFocusedEditorActions
}

extension FocusedValues {
    var scholiumSearchActions: ScholiumSearchActions? {
        get { self[ScholiumSearchActionsFocusedKey.self] }
        set { self[ScholiumSearchActionsFocusedKey.self] = newValue }
    }

    var scholiumWorkspaceWindowActions: WorkspaceWindowActions? {
        get { self[ScholiumWorkspaceWindowActionsFocusedKey.self] }
        set { self[ScholiumWorkspaceWindowActionsFocusedKey.self] = newValue }
    }

    var scholiumResearchActionActions: ScholiumFocusedResearchActionActions? {
        get { self[ScholiumFocusedResearchActionActionsKey.self] }
        set { self[ScholiumFocusedResearchActionActionsKey.self] = newValue }
    }

    var scholiumEditorActions: ScholiumFocusedEditorActions? {
        get { self[ScholiumFocusedEditorActionsKey.self] }
        set { self[ScholiumFocusedEditorActionsKey.self] = newValue }
    }
}

private struct ScholiumCommands: Commands {
    let storageReady: Bool
    @FocusedObject private var appState: WindowModel?
    @FocusedValue(\.scholiumSearchActions) private var searchActions
    @FocusedValue(\.scholiumWorkspaceWindowActions) private var workspaceWindowActions
    @FocusedValue(\.scholiumResearchActionActions) private var researchActionActions
    @FocusedValue(\.scholiumEditorActions) private var editorActions
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                openWindow(
                    id: "scholium-main",
                    value: TriptychWindowRoute(triptychID: appState?.workspaceAssignment?.id)
                )
            }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(!storageReady)
        }
        CommandGroup(after: .newItem) {
            Button("New Triptych…") {
                openWindow(
                    id: "scholium-bootstrap",
                    value: BootstrapWindowRoute(purpose: .newTriptych)
                )
            }
            .disabled(!storageReady)
            Menu("Open Triptych") {
                ForEach(appState?.registeredTriptychs ?? []) { assignment in
                    Button(triptychCommandLabel(assignment)) {
                        openWindow(
                            id: "scholium-main",
                            value: TriptychWindowRoute(triptychID: assignment.id)
                        )
                    }
                }
            }
            .disabled(appState?.registeredTriptychs.isEmpty != false)
            Divider()
            Button("New Note") {
                appState?.requestUntitledNoteCreation(in: nil)
            }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(
                    appState?.workspaceAssignment == nil
                        || appState?.noteLocationScope != .workspace
                        || appState?.isCreatingNote == true
                )
            Button("Import Markdown…") { appState?.showMarkdownImporter = true }
                .disabled(appState?.workspaceAssignment == nil)
            Divider()
            Button("Duplicate Note…") {
                guard let note = appState?.currentNote,
                      let target = NoteLifecycleTarget(note) else { return }
                appState?.noteLifecycleRequest = .duplicate(target)
            }
            .disabled(appState?.currentDocumentCapabilities.allows(.duplicate) != true)
            Button("Move or Rename Note…") {
                guard let note = appState?.currentNote,
                      let target = NoteLifecycleTarget(note) else { return }
                appState?.noteLifecycleRequest = .move(target)
            }
            .disabled(appState?.currentDocumentCapabilities.allows(.move) != true)
            Divider()
            Button("Create Checkpoint…") { appState?.showCreateCheckpoint = true }
                .disabled(appState?.workspaceAssignment == nil)
            Button("Restore from Checkpoint…") { appState?.showCheckpointBrowser = true }
                .disabled(appState?.workspaceAssignment == nil)
            Button("Reveal Checkpoints in Finder") { appState?.revealCheckpointsInFinder() }
                .disabled(appState?.workspaceAssignment == nil)
            Button("Reveal Current Vault in Finder") { appState?.revealVaultInFinder() }
                .disabled(appState?.vaultConfig == nil)
        }
        CommandGroup(after: .pasteboard) {
            Button("Paste as Markdown") {
                guard let payload = markdownPasteboardPayload() else { return }
                editorActions?.performWithArgument(.pasteMarkdown, payload)
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .disabled(editorActions?.isAvailable(.pasteMarkdown) != true)
            Divider()
            Button("Find in This Note…") {
                guard let appState else { return }
                searchActions?.begin(
                    .findInNote(previousScope: appState.searchController.ordinaryScope)
                )
            }
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(searchActions == nil || appState?.currentNote == nil)
            Button("Edit Properties…") { appState?.showFrontmatterEditor = true }
                .disabled(appState?.canEditCurrentNote != true)
        }
        CommandGroup(after: .textFormatting) {
            Divider()
            Button("Bold") { editorActions?.perform(.bold) }
                .keyboardShortcut("b", modifiers: [.command])
                .disabled(editorActions?.isAvailable(.bold) != true)
            Button("Emphasis") { editorActions?.perform(.emphasis) }
                .keyboardShortcut("i", modifiers: [.command])
                .disabled(editorActions?.isAvailable(.emphasis) != true)
            Button("Strikethrough") { editorActions?.perform(.strikethrough) }
                .disabled(editorActions?.isAvailable(.strikethrough) != true)
            Button("Highlight") { editorActions?.perform(.highlight) }
                .disabled(editorActions?.isAvailable(.highlight) != true)
            Button("Inline Code") { editorActions?.perform(.inlineCode) }
                .disabled(editorActions?.isAvailable(.inlineCode) != true)
            Divider()
            Menu("Heading") {
                Button("Paragraph") { editorActions?.perform(.paragraph) }
                    .disabled(editorActions?.isAvailable(.paragraph) != true)
                ForEach(1...6, id: \.self) { level in
                    Button("Heading \(level)") {
                        let command: MarkdownEditorCommand = switch level {
                        case 1: .heading1
                        case 2: .heading2
                        case 3: .heading3
                        case 4: .heading4
                        case 5: .heading5
                        default: .heading6
                        }
                        editorActions?.perform(command)
                    }
                    .disabled(editorActions?.isAvailable(headingCommand(level)) != true)
                }
            }
            Menu("Lists") {
                Button("Bulleted List") { editorActions?.perform(.bulletList) }
                    .disabled(editorActions?.isAvailable(.bulletList) != true)
                Button("Numbered List") { editorActions?.perform(.numberedList) }
                    .disabled(editorActions?.isAvailable(.numberedList) != true)
                Button("Task List") { editorActions?.perform(.taskList) }
                    .disabled(editorActions?.isAvailable(.taskList) != true)
                Button("Toggle Task") { editorActions?.perform(.toggleTask) }
                    .disabled(editorActions?.isAvailable(.toggleTask) != true)
            }
            Menu("Table") {
                Button("Insert Row Before") { editorActions?.perform(.tableInsertRowBefore) }
                    .disabled(editorActions?.isAvailable(.tableInsertRowBefore) != true)
                Button("Insert Row After") { editorActions?.perform(.tableInsertRowAfter) }
                    .disabled(editorActions?.isAvailable(.tableInsertRowAfter) != true)
                Button("Delete Row") { editorActions?.perform(.tableDeleteRow) }
                    .disabled(editorActions?.isAvailable(.tableDeleteRow) != true)
                Divider()
                Button("Insert Column Before") { editorActions?.perform(.tableInsertColumnBefore) }
                    .disabled(editorActions?.isAvailable(.tableInsertColumnBefore) != true)
                Button("Insert Column After") { editorActions?.perform(.tableInsertColumnAfter) }
                    .disabled(editorActions?.isAvailable(.tableInsertColumnAfter) != true)
                Button("Delete Column") { editorActions?.perform(.tableDeleteColumn) }
                    .disabled(editorActions?.isAvailable(.tableDeleteColumn) != true)
                Divider()
                Button("Align Left") { editorActions?.perform(.tableAlignLeft) }
                    .disabled(editorActions?.isAvailable(.tableAlignLeft) != true)
                Button("Align Center") { editorActions?.perform(.tableAlignCenter) }
                    .disabled(editorActions?.isAvailable(.tableAlignCenter) != true)
                Button("Align Right") { editorActions?.perform(.tableAlignRight) }
                    .disabled(editorActions?.isAvailable(.tableAlignRight) != true)
            }
            Button("Block Quotation") { editorActions?.perform(.blockQuotation) }
                .disabled(editorActions?.isAvailable(.blockQuotation) != true)
            Button("Fenced Code") { editorActions?.perform(.fencedCode) }
                .disabled(editorActions?.isAvailable(.fencedCode) != true)
        }
        CommandMenu("Insert") {
            Button("Link") { editorActions?.perform(.standardLink) }
                .keyboardShortcut("k", modifiers: [.command])
                .disabled(editorActions?.isAvailable(.standardLink) != true)
            Button("Wikilink") { editorActions?.perform(.wikilink) }
                .disabled(editorActions?.isAvailable(.wikilink) != true)
            Menu("Vector Link") {
                Button("Supports") { editorActions?.perform(.vectorSupports) }
                    .disabled(editorActions?.isAvailable(.vectorSupports) != true)
                Button("Opposes") { editorActions?.perform(.vectorOpposes) }
                    .disabled(editorActions?.isAvailable(.vectorOpposes) != true)
                Button("Incompatible") { editorActions?.perform(.vectorIncompatible) }
                    .disabled(editorActions?.isAvailable(.vectorIncompatible) != true)
            }
            Divider()
            Button("Footnote") { editorActions?.perform(.insertFootnote) }
                .disabled(editorActions?.isAvailable(.insertFootnote) != true)
            Button("Table") { editorActions?.perform(.insertTable) }
                .disabled(editorActions?.isAvailable(.insertTable) != true)
            Button("Thematic Break") { editorActions?.perform(.thematicBreak) }
                .disabled(editorActions?.isAvailable(.thematicBreak) != true)
            Menu("Callout") {
                Button("Orientation") { editorActions?.perform(.calloutOrient) }
                    .disabled(editorActions?.isAvailable(.calloutOrient) != true)
                Button("Source") { editorActions?.perform(.calloutCite) }
                    .disabled(editorActions?.isAvailable(.calloutCite) != true)
                Button("Connections") { editorActions?.perform(.calloutConnect) }
                    .disabled(editorActions?.isAvailable(.calloutConnect) != true)
                Button("Statement") { editorActions?.perform(.calloutState) }
                    .disabled(editorActions?.isAvailable(.calloutState) != true)
                Button("Illustration") { editorActions?.perform(.calloutIllustrate) }
                    .disabled(editorActions?.isAvailable(.calloutIllustrate) != true)
                Button("Quotation") { editorActions?.perform(.calloutQuote) }
                    .disabled(editorActions?.isAvailable(.calloutQuote) != true)
                Button("Caution") { editorActions?.perform(.calloutFlag) }
                    .disabled(editorActions?.isAvailable(.calloutFlag) != true)
            }
            Divider()
            Button("Comment on Selection…") { editorActions?.startComment() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(
                    editorActions?.canCommentOnSelectedPassage() != true
                        || editorActions?.isComposing == true
                )
        }
        CommandGroup(replacing: .sidebar) {
            Button(
                ScholiumL10n.dynamicString(
                    appState?.sidebarVisible == true ? "Hide Sidebar" : "Show Sidebar"
                )
            ) {
                guard let appState else { return }
                workspaceWindowActions?.setLibraryVisible(!appState.sidebarVisible)
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(workspaceWindowActions == nil)
            Divider()
            Button("Search…") {
                searchActions?.begin(.general)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(searchActions == nil)
            Button(
                ScholiumL10n.dynamicString(
                    appState?.researchInspectorVisible == true
                        ? "Hide Research Inspector"
                        : "Show Research Inspector"
                )
            ) {
                guard let appState else { return }
                workspaceWindowActions?.setResearchInspectorVisible(
                    !appState.researchInspectorVisible
                )
            }
            .keyboardShortcut("b", modifiers: [.command, .option])
            .disabled(
                workspaceWindowActions == nil
                    || (appState?.researchInspectorVisible != true
                        && appState?.currentNote == nil)
            )
            Menu("Document Mode") {
                Button("Review") { appState?.requestDocumentMode(.read) }
                Button("Edit") { appState?.requestDocumentMode(.livePreview) }
                    .disabled(appState?.canEditCurrentNote != true)
                Button("Source") { appState?.requestDocumentMode(.source) }
                    .disabled(appState?.canEditCurrentNote != true)
            }
            .disabled(appState?.currentNote == nil || editorActions?.isComposing == true)
            Divider()
            Menu("Document Text Size") {
                Button("Increase Text Size") {
                    appState?.adjustDocumentTextScale(by: ScholiumMetrics.Document.textScaleStep)
                }
                    .keyboardShortcut("=", modifiers: [.command])
                    .disabled(
                        appState?.currentNote == nil
                            || appState?.documentTextScale == ScholiumMetrics.Document.maximumTextScale
                    )
                Button("Decrease Text Size") {
                    appState?.adjustDocumentTextScale(by: -ScholiumMetrics.Document.textScaleStep)
                }
                    .keyboardShortcut("-", modifiers: [.command])
                    .disabled(
                        appState?.currentNote == nil
                            || appState?.documentTextScale == ScholiumMetrics.Document.minimumTextScale
                    )
                Button("Actual Size (100%)") { appState?.resetDocumentTextScale() }
                    .keyboardShortcut("0", modifiers: [.command])
                    .disabled(
                        appState?.currentNote == nil
                            || appState?.documentTextScale == ScholiumMetrics.Document.defaultTextScale
                    )
                Divider()
                Button("150%") { appState?.setDocumentTextScale(1.5) }
                    .disabled(appState?.currentNote == nil || appState?.documentTextScale == 1.5)
                Button("200%") {
                    appState?.setDocumentTextScale(ScholiumMetrics.Document.maximumTextScale)
                }
                    .disabled(
                        appState?.currentNote == nil
                            || appState?.documentTextScale == ScholiumMetrics.Document.maximumTextScale
                    )
            }
            .disabled(appState?.currentNote == nil)
            Menu("Appearance") {
                Button("Use System Appearance") { appState?.colorScheme = .system }
                Button("Light") { appState?.colorScheme = .light }
                Button("Dark") { appState?.colorScheme = .dark }
            }
        }
        CommandGroup(after: .windowArrangement) {
            Button("Attention") {
                workspaceWindowActions?.showPreferredAttention()
            }
            .disabled(workspaceWindowActions?.canShowAttention() != true)
        }
        CommandMenu("Research") {
            if let appState, researchActionActions != nil {
                ForEach(appState.researchController.actions.availability) { action in
                    Button {
                        researchActionActions?.open(action.id)
                    } label: {
                        if action.profile.origin == .applicationDefault {
                            Text(LocalizedStringKey(action.buttonName))
                        } else {
                            Text(verbatim: action.buttonName)
                        }
                    }
                    .keyboardShortcut(action.definition.interfaceKeyboardShortcut)
                    .disabled(
                        !action.canPresentInInterface
                            || !appState.hasConfirmedCurrentResearchActionAvailability
                            || appState.researchController.actions.hasCancellationBarrier
                    )
                }
            }
            Divider()
            WindowVisibilityToggle(windowID: "scholium-research-record")
                .disabled(appState?.workspaceAssignment == nil)
        }
        #if DEBUG
        if qaEditorFaultsAreEnabled || qaResearchWorkflowProofsAreEnabled {
            CommandMenu("QA") {
                if qaEditorFaultsAreEnabled {
                    Button("Simulate Editor Process Termination") {
                        guard let documentID = editorActions?.documentID else { return }
                        DistributedNotificationCenter.default().postNotificationName(
                            Notification.Name("com.scholium.qa.simulate-editor-process-termination"),
                            object: nil,
                            userInfo: ["documentID": documentID],
                            deliverImmediately: true
                        )
                    }
                    .keyboardShortcut("w", modifiers: [.command, .option, .control])
                    .disabled(editorActions == nil)
                }
                if qaEditorFaultsAreEnabled && qaResearchWorkflowProofsAreEnabled {
                    Divider()
                }
                if qaResearchWorkflowProofsAreEnabled {
                    Button("Open Research Workflow Interface Proofs") {
                        openWindow(id: "scholium-research-workflow-proofs")
                    }
                }
            }
        }
        #endif
    }

    #if DEBUG
    private var qaEditorFaultsAreEnabled: Bool {
        Bundle.main.bundleIdentifier == "com.scholium.qa"
            && ProcessInfo.processInfo.arguments.contains("--scholium-editor-qa-faults")
    }

    private var qaResearchWorkflowProofsAreEnabled: Bool {
        Bundle.main.bundleIdentifier == "com.scholium.qa"
            && ProcessInfo.processInfo.arguments.contains(
                "--scholium-research-workflow-proofs"
            )
    }
    #endif

    private func markdownPasteboardPayload() -> String? {
        let pasteboard = NSPasteboard.general
        let plainText = pasteboard.string(forType: .string) ?? ""
        let html = pasteboard.string(forType: .html)
        guard !plainText.isEmpty || html?.isEmpty == false else { return nil }
        var payload = ["plainText": plainText]
        if let html, !html.isEmpty { payload["html"] = html }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func headingCommand(_ level: Int) -> MarkdownEditorCommand {
        switch level {
        case 1: .heading1
        case 2: .heading2
        case 3: .heading3
        case 4: .heading4
        case 5: .heading5
        default: .heading6
        }
    }

    private func triptychCommandLabel(_ assignment: TriptychAssignment) -> String {
        let registered = appState?.registeredTriptychs ?? []
        let duplicates = registered.filter {
            $0.triptych.name.caseInsensitiveCompare(assignment.triptych.name) == .orderedSame
        }
        guard duplicates.count > 1,
              let works = assignment.vault(for: .output) else {
            return assignment.triptych.name
        }
        let parent = URL(fileURLWithPath: works.canonicalPath, isDirectory: true)
            .deletingLastPathComponent().lastPathComponent
        return "\(assignment.triptych.name) — \(parent)"
    }

}

// MARK: - App State

@MainActor
final class WindowModel: ObservableObject {
    struct ClosePreparationOutcome: Sendable {
        let presentationWarning: String?
    }

    private enum WindowNavigationError: LocalizedError {
        case noteUnavailable(String)
        case vaultUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .noteUnavailable(let path):
                String(localized: "The visited note '\(path)' is no longer available. Scholium kept the current document open.", table: "Localizable", bundle: .module)
            case .vaultUnavailable(let name):
                String(localized: "The \(name) vault is not available in this Triptych. Scholium kept the current document open.", table: "Localizable", bundle: .module)
            }
        }
    }

    enum DocumentTabActivation {
        case place(DocumentTabPlacement)
        case preserveTabMembership
    }
    private(set) var windowSessionID = UUID()
    let nativeWindowID: UUID

    // MARK: Published State
    @Published var vaultConfig: VaultConfig?
    @Published var currentRegisteredVault: RegisteredVault?
    @Published var currentVaultRole: VaultRole = .other
    @Published private(set) var libraryFocusRequestGeneration: UInt64 = 0
    @Published private(set) var isCreatingNote = false
    @Published private(set) var isMutatingFolder = false
    @Published var triptychSettings = TriptychSettings()
    /// One-shot routing from Actions to one portable active Discussion. The
    /// document view consumes and clears it without changing record state.
    @Published var requestedDiscussionID: UUID? = nil
    @Published var registeredVaults: [RegisteredVault] = []
    let presentationRouter = WindowPresentationRouter()
    let shellState = WindowShellState()
    lazy var discoveryController = DiscoveryController(
        shellState: shellState
    ) { [weak self] intent in
        self?.handleWindowIntent(intent)
    }
    lazy var searchController = WindowSearchController(
        discoveryController: discoveryController,
        dependencies: .init(
            loadSavedSearches: { [workspaceStore] in
                try await workspaceStore.savedSearches()
            },
            saveSavedSearches: { [workspaceStore] searches in
                try await workspaceStore.saveSavedSearches(searches)
            },
            executionContext: { [weak self] state in
                guard let self else {
                    throw DiscoverySearchExecutionError.workspaceUnavailable
                }
                return DiscoverySearchExecutionContext(
                    workspaceIsAvailable: self.workspaceAssignment != nil,
                    currentNoteSnapshot: state.scope == .thisNote
                        ? try await self.currentSearchSourceSnapshot()
                        : nil,
                    currentVaultID: self.currentRegisteredVault?.id
                )
            },
            lexicalEvidence: { [weak self] hit, scope in
                guard let self else {
                    return WindowLexicalSearchEvidence(
                        freshness: nil,
                        fingerprint: nil
                    )
                }
                return await self.currentLexicalSearchEvidence(
                    for: hit,
                    scope: scope
                )
            },
            open: { [weak self] result, disposition in
                await self?.openSearchSelection(result, disposition: disposition)
            },
            hasCurrentNote: { [weak self] in self?.currentNote != nil },
            isPresented: { [weak self] in self?.showSearchSurface == true },
            setPresented: { [weak self] in self?.showSearchSurface = $0 },
            reportInformation: { [weak self] message in
                self?.showToast(message, kind: .information)
            },
            reportLoadFailure: { [weak self] message in
                self?.vaultError = message
            },
            reportSaveFailure: { [weak self] message in
                self?.showToast(message, kind: .error)
            },
            setAvailabilityStatus: { [weak self] status in
                guard let self else { return }
                if let status {
                    self.refreshStatusText = status
                } else if self.refreshStatusText == "Search unavailable" {
                    self.refreshStatusText = nil
                }
            },
            reportCatalogFailure: { [weak self] message in
                self?.workspaceProjectionController.reportCatalogError(message)
            }
        )
    )
    lazy var documentController = DocumentController { [weak self] intent in
        self?.handleWindowIntent(intent)
    }
    let documentTabController = DocumentTabController()
    lazy var researchController = ResearchController(
        shellState: shellState
    ) { [weak self] intent in
        self?.handleWindowIntent(intent)
    }
    lazy var workspaceProjectionController = WindowWorkspaceProjectionController(
        loadCatalog: { [weak self] in
            guard let self else {
                throw DiscoverySearchExecutionError.workspaceUnavailable
            }
            return try await self.discoveryController.discoverySnapshot().catalog
        }
    )
    let attentionPresentationState = AttentionPresentationState()
    lazy var attentionPopoverSession = AttentionPopoverSession(workspace: self)
    lazy var agentNoteChangeWindowController = AgentNoteChangeWindowController(
        windowID: nativeWindowID,
        presentationRouter: presentationRouter,
        claimCoordinator: workspaceStore.agentNoteChangeClaims,
        dependencies: .init(
            presentationIdentity: { [workspaceStore] record in
                try await workspaceStore.agentNoteChangePresentationIdentity(
                    for: record
                )
            },
            refresh: { [workspaceStore] requestID, triptychID in
                try await workspaceStore.refreshAgentNoteChangeRequest(
                    id: requestID,
                    in: triptychID
                )
            },
            resolve: { [workspaceStore] triptychID, requestID, state, noteIDs in
                try await workspaceStore.resolveAgentNoteChangeRequest(
                    triptychID: triptychID,
                    requestID: requestID,
                    state: state,
                    allowedNoteIDs: noteIDs
                )
            },
            snapshot: { [workspaceStore] in workspaceStore.snapshot(for: $0) }
        ),
        reportError: { [weak self] message in
            self?.showToast(message, kind: .error)
        }
    )

    var sidebarVisible: Bool {
        get { shellState.libraryVisible }
        set { shellState.recordLibraryVisibility(newValue) }
    }

    var hasCompletedInitialRestore: Bool {
        shellState.hasCompletedInitialRestore
    }

    var toastMessage: WindowToast? {
        shellState.toastMessage
    }

    var colorScheme: WindowColorSchemeChoice {
        get { shellState.colorScheme }
        set { shellState.colorScheme = newValue }
    }

    var documentTextScale: Double {
        get { shellState.documentTextScale }
        set { shellState.setDocumentTextScale(newValue) }
    }

    var refreshStatusText: String? {
        get { shellState.refreshStatusText }
        set { shellState.setRefreshStatus(newValue) }
    }

    var windowSessionPersistenceError: String? {
        shellState.windowSessionPersistenceError
    }

    var workspaceAssignment: TriptychAssignment? {
        get { windowWorkspaceController.state.assignment }
        set { windowWorkspaceController.setAssignment(newValue) }
    }

    var registeredTriptychs: [TriptychAssignment] {
        get { windowWorkspaceController.state.registeredTriptychs }
        set { windowWorkspaceController.setRegisteredTriptychs(newValue) }
    }

    var workspaceRecoveryMessage: String? {
        get { windowWorkspaceController.state.recoveryMessage }
        set { windowWorkspaceController.setRecoveryMessage(newValue) }
    }

    var workspaceAccessRecovery: WorkspaceAccessRecovery? {
        get { windowWorkspaceController.state.accessRecovery }
        set { windowWorkspaceController.setAccessRecovery(newValue) }
    }

    private(set) var activeTriptychServicesID: UUID? {
        get { windowWorkspaceController.state.activeServicesID }
        set { windowWorkspaceController.setActiveServicesID(newValue) }
    }

    var notes: [WindowDocumentLocation] { workspaceProjectionController.notes }
    var availablePropertyFilterOptions: WindowPropertyFilterOptions {
        workspaceProjectionController.propertyFilterOptions
    }
    var allTags: [String] { workspaceProjectionController.tags }
    var documentRevisions: [String: DocumentFingerprint] {
        workspaceProjectionController.documentRevisions
    }
    var workspaceCatalog: WorkspaceCatalogSnapshot? {
        workspaceProjectionController.catalog
    }
    var isRefreshingWorkspaceCatalog: Bool {
        workspaceProjectionController.isRefreshingCatalog
    }
    var derivedRefreshStatus: WorkspaceDerivedRefreshStatus? {
        workspaceProjectionController.derivedRefreshStatus
    }
    var workspaceCatalogError: String? {
        workspaceProjectionController.catalogError
    }
    // Window-level projections for Library leaves. DiscoveryController remains
    // the sole mutable owner.
    var noteLocationScope: NoteLocationScope {
        discoveryController.library.locationScope
    }

    var isNeedsAttentionFilter: Bool {
        get { discoveryController.library.filters.needsAttention }
        set { updateDiscoveryFilters { $0.needsAttention = newValue } }
    }

    var isExplicitConnectionsFilter: Bool {
        get { discoveryController.library.filters.hasExplicitConnections }
        set { updateDiscoveryFilters { $0.hasExplicitConnections = newValue } }
    }

    var isMalformedMetadataFilter: Bool {
        get { discoveryController.library.filters.hasMalformedMetadata }
        set { updateDiscoveryFilters { $0.hasMalformedMetadata = newValue } }
    }

    var selectedTag: String? {
        get { discoveryController.library.filters.tag }
        set { updateDiscoveryFilters { $0.tag = newValue } }
    }

    var selectedAuthor: String? {
        get { discoveryController.library.filters.author }
        set { updateDiscoveryFilters { $0.author = newValue } }
    }

    var selectedYear: Int? {
        get { discoveryController.library.filters.year }
        set { updateDiscoveryFilters { $0.year = newValue } }
    }

    var selectedPropertyKey: String? {
        get { discoveryController.library.filters.propertyKey }
        set { updateDiscoveryFilters { $0.propertyKey = newValue } }
    }

    var selectedPropertyValue: String? {
        get { discoveryController.library.filters.propertyValue }
        set { updateDiscoveryFilters { $0.propertyValue = newValue } }
    }

    var noteSortOrder: NoteSortOrder {
        get { discoveryController.library.sortOrder }
        set {
            discoveryController.selectSortOrder(newValue)
            UserDefaults.standard.set(newValue.rawValue, forKey: "noteSortOrder")
        }
    }

    private func updateDiscoveryFilters(
        _ update: (inout DiscoveryFilterState) -> Void
    ) {
        var filters = discoveryController.library.filters
        update(&filters)
        discoveryController.replaceFilters(filters)
    }

    // Triptych-wide immutable semantic graph forwarded from the exact-window
    // Workspace projection owner.
    var relationshipGraph: GraphSnapshot? {
        workspaceProjectionController.relationshipGraph
    }

    // MARK: Window Presentation

    var researchInspectorMode: ResearchInspectorMode {
        get { researchController.inspector.mode }
        set { researchController.selectInspectorMode(newValue) }
    }

    var researchInspectorVisible: Bool {
        get { researchController.inspector.isVisible }
        set { researchController.showResearchInspector(newValue) }
    }

    var noteLifecycleRequest: NoteLifecycleRequest? {
        get {
            guard case .lifecycle(let request) = presentationRouter.sheet else { return nil }
            return request
        }
        set {
            if let newValue {
                presentationRouter.present(.lifecycle(newValue))
            } else if case .lifecycle = presentationRouter.sheet {
                presentationRouter.dismissSheet()
            }
        }
    }

    var folderLifecycleRequest: FolderLifecycleRequest? {
        get {
            guard case .folderLifecycle(let request) = presentationRouter.sheet else {
                return nil
            }
            return request
        }
        set {
            if let newValue {
                presentationRouter.present(.folderLifecycle(newValue))
            } else if case .folderLifecycle = presentationRouter.sheet {
                presentationRouter.dismissSheet()
            }
        }
    }

    var isLoading: Bool {
        get { presentationRouter.presentsOverlay(.loading) }
        set { presentationRouter.setOverlay(.loading, isPresented: newValue) }
    }

    var showMarkdownImporter: Bool {
        get { presentationRouter.fileImport == .markdown }
        set { presentationRouter.fileImport = newValue ? .markdown : nil }
    }

    var showSearchSurface: Bool {
        get { presentationRouter.presentsOverlay(.search) }
        set { presentationRouter.setOverlay(.search, isPresented: newValue) }
    }

    var editingNotePath: String? {
        get {
            guard case .frontmatter(let route) = presentationRouter.sheet else { return nil }
            return route.path
        }
        set {
            if let newValue {
                presentationRouter.presentFrontmatter(path: newValue)
            } else if case .frontmatter = presentationRouter.sheet {
                presentationRouter.dismissSheet()
            }
        }
    }

    var showFrontmatterEditor: Bool {
        get { editingNotePath != nil }
        set {
            if newValue, let path = editingNotePath ?? currentNote?.relativePath {
                presentationRouter.presentFrontmatter(path: path)
            } else if !newValue, case .frontmatter = presentationRouter.sheet {
                presentationRouter.dismissSheet()
            }
        }
    }

    var vaultError: String? {
        get { presentationRouter.alert?.message }
        set { presentationRouter.alert = newValue.map(WindowAlertRoute.actionFailure) }
    }

    var selectedIdentityAmbiguity: NoteIdentityAmbiguity? {
        get {
            guard case .identityResolution(let ambiguity) = presentationRouter.sheet else { return nil }
            return ambiguity
        }
        set {
            if let newValue {
                presentationRouter.present(.identityResolution(newValue))
            } else if case .identityResolution = presentationRouter.sheet {
                presentationRouter.dismissSheet()
            }
        }
    }

    var showCheckpointBrowser: Bool {
        get {
            guard case .restoreCheckpoint = presentationRouter.sheet else { return false }
            return true
        }
        set {
            if newValue {
                presentationRouter.present(.restoreCheckpoint)
            } else {
                presentationRouter.dismissSheet(if: "restore-checkpoint")
            }
        }
    }

    var showCreateCheckpoint: Bool {
        get {
            guard case .createCheckpoint = presentationRouter.sheet else { return false }
            return true
        }
        set {
            if newValue {
                presentationRouter.present(.createCheckpoint)
            } else {
                presentationRouter.dismissSheet(if: "create-checkpoint")
            }
        }
    }

    var showTransactionRecovery: Bool {
        get {
            guard case .transactionRecovery = presentationRouter.sheet else { return false }
            return true
        }
        set {
            if newValue {
                presentationRouter.present(.transactionRecovery)
            } else {
                presentationRouter.dismissSheet(if: "transaction-recovery")
            }
        }
    }

    // MARK: Services
    private var activeWorkspaceCapabilities: WindowWorkspaceCapabilities? {
        get { windowWorkspaceController.activeCapabilities }
        set { windowWorkspaceController.setActiveCapabilities(newValue) }
    }
    let cssSnippetStore: CSSSnippetStore
    let zoteroBridge: ZoteroBridge
    let agentApplicationHandoff: AgentApplicationHandoffController
    private var requestedTriptychID: UUID? {
        windowWorkspaceController.requestedTriptychID
    }
    private let requestedInitialDocument: VaultNoteReference?
    private var didOpenRequestedInitialDocument = false
    private var projectionRefreshToken: UInt64 = 0
    private var attemptedVaultRestore = false
    private let workspaceStore: WorkspaceStore
    private let lifecyclePolicy: ScholiumLifecyclePolicy
    private let documentTransitionCoordinator = DocumentTransitionCoordinator()
    private let editorFlushCoordinator: WindowEditorFlushCoordinator
    private let windowSessionPersistenceCoordinator: WindowSessionPersistenceCoordinator
    let windowWorkspaceController: WindowWorkspaceController
    private var workspaceCancellables: Set<AnyCancellable> = []
    private var researchActionOpenTask: Task<Void, Never>?
    private var researchActionOpenRequestID: UUID?
    private var discussionPresentationRequestID: UUID?
    private var isRestoringWindowSession = false
    private var didRestoreWindowSession = false
    private var closeAttemptSequence: UInt64 = 0
    private var currentCloseAttemptID = LifecycleAttemptID(rawValue: 0)
    private var identityRefreshGeneration: UInt64 = 0
    private let documentPresentationDidChange = PassthroughSubject<Void, Never>()
    #if DEBUG
    private var qaPerformanceModeNotificationTokens: [Int32] = []
    #endif

    init(
        workspaceStore: WorkspaceStore,
        nativeWindowID: UUID? = nil,
        requestedTriptychID: UUID? = nil,
        requestedInitialDocument: VaultNoteReference? = nil,
        lifecyclePolicy: ScholiumLifecyclePolicy = ScholiumLifecyclePolicy(),
        finalWindowSessionSaver: WindowSessionPersistenceCoordinator.Saver? = nil
    ) {
        let resolvedWindowID = nativeWindowID ?? UUID()
        self.nativeWindowID = resolvedWindowID
        windowSessionID = resolvedWindowID
        self.workspaceStore = workspaceStore
        self.lifecyclePolicy = lifecyclePolicy
        self.editorFlushCoordinator = WindowEditorFlushCoordinator(
            windowID: resolvedWindowID,
            registry: workspaceStore
        )
        let resolvedSessionSaver = finalWindowSessionSaver ?? {
            [workspaceStore] snapshot, attempt in
            try await workspaceStore.saveWindowSession(snapshot, attempt: attempt)
        }
        self.windowSessionPersistenceCoordinator = WindowSessionPersistenceCoordinator(
            lifecyclePolicy: lifecyclePolicy,
            finalSaver: resolvedSessionSaver
        )
        self.windowWorkspaceController = WindowWorkspaceController(
            workspaceStore: workspaceStore,
            requestedTriptychID: requestedTriptychID
        )
        self.requestedInitialDocument = requestedInitialDocument
        cssSnippetStore = workspaceStore.cssSnippetStore
        zoteroBridge = workspaceStore.zoteroBridge
        agentApplicationHandoff = workspaceStore.agentApplicationHandoff
        presentationRouter.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &workspaceCancellables)
        discoveryController.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &workspaceCancellables)
        searchController.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &workspaceCancellables)
        researchController.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &workspaceCancellables)
        documentController.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &workspaceCancellables)
        documentTabController.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &workspaceCancellables)
        workspaceProjectionController.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &workspaceCancellables)
        agentNoteChangeWindowController.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &workspaceCancellables)
        cssSnippetStore.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &workspaceCancellables)
        windowWorkspaceController.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &workspaceCancellables)
        workspaceStore.$latestWorkspaceActivation
            .compactMap { $0 }
            .sink { [weak self] activation in
                self?.adoptWorkspaceActivation(activation)
            }
            .store(in: &workspaceCancellables)
        workspaceStore.$workspaceEvents
            .sink { [weak self] events in
                self?.receiveWorkspaceEvents(events)
            }
            .store(in: &workspaceCancellables)
        #if DEBUG
        if Bundle.main.bundleIdentifier == "com.scholium.qa",
           ProcessInfo.processInfo.arguments.contains(
               "--scholium-performance-editor-mode-notifications"
           ) {
            let requests: [(String, NotePresentationMode)] = [
                ("com.scholium.qa.performance-editor-mode.live-preview", .livePreview),
                ("com.scholium.qa.performance-editor-mode.source", .source),
            ]
            for (name, mode) in requests {
                var token: Int32 = 0
                let status = notify_register_dispatch(name, &token, .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.requestPerformanceEditorMode(mode)
                    }
                }
                if status == NOTIFY_STATUS_OK {
                    qaPerformanceModeNotificationTokens.append(token)
                }
            }
        }
        if Bundle.main.bundleIdentifier == "com.scholium.qa",
           ProcessInfo.processInfo.arguments.contains(
               "--scholium-agent-change-request-fixture"
           ) {
            var token: Int32 = 0
            let name = "com.scholium.qa.present-agent-change-request.\(resolvedWindowID.uuidString)"
            let status = notify_register_dispatch(name, &token, .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.agentNoteChangeWindowController.presentQASyntheticRequest(
                        activeTriptychID: self.activeTriptychServicesID
                    )
                }
            }
            if status == NOTIFY_STATUS_OK {
                qaPerformanceModeNotificationTokens.append(token)
            }
        }
        #endif
        if let saved = UserDefaults.standard.string(forKey: "noteSortOrder"),
           let order = NoteSortOrder(rawValue: saved) {
            // Metadata filters are intentionally request-local and are not
            // restored. A Debate Importance ordering without one explicit
            // debate scope would compare incommensurable ratings.
            noteSortOrder = order == .debateImportanceDescending ? .modifiedNewest : order
        }
        UserDefaults.standard.removeObject(forKey: "libraryViewMode")
        searchController.loadSavedSearches()
        observeWindowSessionChanges()
    }

    deinit {
        researchActionOpenTask?.cancel()
        #if DEBUG
        for token in qaPerformanceModeNotificationTokens {
            notify_cancel(token)
        }
        #endif
    }

    // MARK: Computed Properties
    private(set) var lifecycleMutationGeneration: UInt64 {
        get { documentController.lifecycleMutationGeneration }
        set { documentController.lifecycleMutationGeneration = newValue }
    }

    var pendingSourceLine: Int? {
        get { documentController.pendingSourceLine }
        set { documentController.pendingSourceLine = newValue }
    }

    var pendingSourceRange: SearchSourceRange? {
        get { documentController.pendingSourceRange }
        set { documentController.pendingSourceRange = newValue }
    }

    var lastSaveError: String? {
        get { documentController.lastSaveError }
        set { documentController.setSaveError(newValue) }
    }

    var requestPresentationMode: NotePresentationMode? {
        get { documentController.requestedPresentationMode }
        set { documentController.requestedPresentationMode = newValue }
    }

    var noteIdentityByPath: [String: UUID] {
        get { documentController.noteIdentityByPath }
        set { documentController.noteIdentityByPath = newValue }
    }

    var identityAmbiguities: [NoteIdentityAmbiguity] {
        get { documentController.identityAmbiguities }
        set { documentController.identityAmbiguities = newValue }
    }

    var pendingIdentityRebindings: [NoteIdentityPendingRebinding] {
        get { documentController.pendingIdentityRebindings }
        set { documentController.pendingIdentityRebindings = newValue }
    }

    var identityMigrationFailures: [NoteIdentityMigrationFailure] {
        get { documentController.identityMigrationFailures }
        set { documentController.identityMigrationFailures = newValue }
    }

    var isResolvingIdentity: Bool {
        get { documentController.isResolvingIdentity }
        set { documentController.isResolvingIdentity = newValue }
    }

    var identityResolutionError: String? {
        get { documentController.identityResolutionError }
        set { documentController.identityResolutionError = newValue }
    }

    var checkpointListingError: String? {
        get { researchController.checkpointListingError }
        set { researchController.checkpointListingError = newValue }
    }

    var transactionRecoveryRecords: [TriptychMutationRecoveryRecord] {
        get { researchController.transactionRecoveryRecords }
        set { researchController.transactionRecoveryRecords = newValue }
    }

    var transactionRecoveryError: String? {
        get { researchController.transactionRecoveryError }
        set { researchController.transactionRecoveryError = newValue }
    }

    var selectedDocumentPath: String? {
        documentController.selectedDocumentPath
    }

    var currentDocumentDescriptor: WindowDocumentDescriptor? {
        documentController.activeDocument
    }

    var currentDocumentVaultID: UUID? {
        if let vaultID = documentController.selectedDocument?.vaultID {
            return vaultID
        }
        guard noteLocationScope == .workspace,
              currentNote != nil else { return nil }
        // Identity-recovery notes deliberately have no stable document
        // descriptor yet, but they remain vault-qualified by the Library
        // projection that selected them. Preserve that vault ownership so the
        // Document surface can present the authoritative recovery state
        // without inventing a stable note identity or enabling writes.
        return currentRegisteredVault?.id
    }

    var currentDocumentVaultRole: VaultRole {
        if let role = currentDocumentDescriptor?.reference.vaultRole {
            return role
        }
        guard noteLocationScope == .workspace,
              currentNote != nil else { return .other }
        return currentRegisteredVault?.role ?? .other
    }

    var currentDocumentVault: RegisteredVault? {
        guard let vaultID = currentDocumentVaultID else { return nil }
        return workspaceAssignment?.vaults.values.first { $0.id == vaultID }
    }

    var currentDocumentVaultSnapshot: WorkspaceVaultSnapshot? {
        guard let vaultID = currentDocumentVaultID else { return nil }
        return workspaceProjectionController.vaultSnapshot(id: vaultID)
    }

    var currentDocumentNotes: [WindowDocumentLocation] {
        guard let snapshot = currentDocumentVaultSnapshot else {
            return currentNote.map { [$0] } ?? []
        }
        return snapshot.documents
            .filter { $0.lifecycle == .active }
            .map(WindowDocumentLocation.workspace)
            .sorted(by: notesAreOrdered)
    }

    var currentLibraryFolders: [String] {
        guard noteLocationScope == .workspace,
              let vaultID = currentRegisteredVault?.id,
              let snapshot = workspaceProjectionController.vaultSnapshot(
                  id: vaultID
              ) else { return [] }
        return snapshot.folders
            .map(\.rawValue)
            .filter {
                WorkspaceDocumentLifecycle(
                    relativePath: $0 + "/placeholder.md"
                ) == .active
            }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var currentDocumentIdentityByPath: [String: UUID] {
        guard let snapshot = currentDocumentVaultSnapshot else {
            guard let descriptor = currentDocumentDescriptor else { return [:] }
            return [descriptor.reference.relativePath: descriptor.sessionKey.noteID]
        }
        return Dictionary(uniqueKeysWithValues: snapshot.documents.compactMap { note in
            note.stableIdentity.resolvedID.map { (note.id.relativePath, $0) }
        })
    }

    var currentDocumentRevisions: [String: DocumentFingerprint] {
        Dictionary(uniqueKeysWithValues: currentDocumentNotes.map {
            ($0.relativePath, $0.document.fingerprint)
        })
    }

    var currentNote: WindowDocumentLocation? {
        if let active = documentController.activeSnapshot {
            return .workspace(active)
        }
        if let descriptor = currentDocumentDescriptor,
           let snapshot = workspaceProjectionController.cachedNote(
               vaultID: descriptor.reference.vaultID,
               stableNoteID: descriptor.sessionKey.noteID,
               relativePath: descriptor.reference.relativePath
           ) {
            return .workspace(snapshot)
        }
        guard let selectedDocumentPath else { return nil }
        return notes.first { $0.relativePath == selectedDocumentPath }
    }

    var selectedDocument: VaultQualifiedNoteID? {
        guard let descriptor = currentDocumentDescriptor else { return nil }
        return VaultQualifiedNoteID(
            vaultID: descriptor.reference.vaultID,
            relativePath: descriptor.reference.relativePath
        )
    }

    var currentResearchFunctionTarget: ResearchFunctionTarget? {
        guard let descriptor = currentDocumentDescriptor,
              let note = currentNote,
              currentDocumentCapabilities.canUseResearchFunctions,
              let role = ResearchFunctionTargetRole(vaultRole: descriptor.reference.vaultRole) else {
            return nil
        }
        return ResearchFunctionTarget(
            noteID: descriptor.sessionKey.noteID,
            note: VaultQualifiedNoteID(
                vaultID: descriptor.reference.vaultID,
                relativePath: note.relativePath
            ),
            role: role,
            lifecycle: note.workspaceSnapshot?.lifecycle ?? .active,
            fingerprint: note.document.fingerprint,
            title: note.title ?? note.displayName
        )
    }

    var currentResearchActionTarget: ResearchActionNoteSnapshot? {
        guard let target = currentResearchFunctionTarget else { return nil }
        return ResearchActionNoteSnapshot(
            noteID: target.noteID,
            note: target.note,
            role: target.role.actionRole,
            lifecycle: target.lifecycle,
            fingerprint: target.fingerprint,
            title: target.title
        )
    }

    var hasConfirmedCurrentResearchActionAvailability: Bool {
        guard let target = currentResearchActionTarget else { return false }
        let actions = researchController.actions
        return actions.availabilityTarget == target
            && !actions.isRefreshingAvailability
            && actions.availabilityError == nil
    }

    var currentResearchFunctionReference: VaultNoteReference? {
        currentDocumentDescriptor?.reference
    }

    var currentRecommendedBibliographyScope: RecommendedBibliographyScope? {
        guard let triptychID = activeTriptychServicesID else { return nil }
        let selectedNotes: [RecommendedBibliographySourceNote]
        if let target = currentResearchFunctionTarget,
           let descriptor = currentDocumentDescriptor {
            selectedNotes = [RecommendedBibliographySourceNote(
                noteID: target.noteID,
                note: target.note,
                role: descriptor.reference.vaultRole,
                fingerprint: target.fingerprint,
                title: target.title
            )]
        } else {
            selectedNotes = []
        }
        return RecommendedBibliographyScope(
            triptychID: triptychID,
            selectedNotes: selectedNotes
        )
    }

    func researchActionsPresentation() -> ResearchActionsPresentation {
        let target = currentResearchActionTarget
        let actions = researchController.actions
        let matchesTarget = actions.availabilityTarget == target
        return ResearchActionsPresentation.make(
            target: target,
            availability: matchesTarget ? actions.availability : [],
            isCheckingAvailability: actions.isRefreshingAvailability,
            availabilityError: matchesTarget ? actions.availabilityError : nil,
            cancellationRecoveries: researchController.actions.cancellationRecoveries,
            retryingCancellationRecoveryIDs:
                researchController.actions.retryingCancellationRecoveryIDs,
            pendingCancellationBarrierCount:
                researchController.actions.pendingCancellationBarrierCount,
            activeDiscussions: researchController.records?.activeDiscussions ?? [],
            settlements: researchController.records?.settlements ?? []
        )
    }

    func refreshResearchActionAvailability() async {
        let target = currentResearchActionTarget
        researchController.setActiveDocument(currentResearchFunctionReference)
        researchController.actions.invalidateIfTargetChanged(target)
        reconcileResearchActionPresentation()
        await researchController.actions.refreshAvailability(for: target)
        await researchController.bibliography.refresh(
            for: currentRecommendedBibliographyScope
        )
    }

    private func reconcileResearchActionPresentation() {
        guard case .researchAction(let route) = presentationRouter.sheet else { return }
        guard researchController.actions.presentationID == route.presentationID,
              researchController.actions.activeActionID == route.actionID,
              researchController.actions.target?.noteID == currentResearchActionTarget?.noteID else {
            presentationRouter.dismissSheet()
            return
        }
    }

    var canEditCurrentNote: Bool {
        currentDocumentCapabilities.canEditSource
    }

    var canCommentCurrentNote: Bool {
        currentDocumentCapabilities.canComment
    }

    var currentDocumentCapabilities: DocumentCapabilities {
        if let capabilities = currentNote?.workspaceSnapshot?.capabilities {
            return capabilities
        }
        guard let note = currentNote else {
            return DocumentCapabilities(
                role: currentDocumentVaultRole,
                lifecycle: .active,
                identity: .unresolved,
                isManagedCritique: false
            )
        }
        return DocumentCapabilities(
            role: currentDocumentVaultRole,
            lifecycle: WorkspaceDocumentLifecycle(relativePath: note.relativePath),
            identity: .unresolved,
            isManagedCritique: false
        )
    }

    func identityAmbiguity(for path: String) -> NoteIdentityAmbiguity? {
        identityAmbiguities.first { $0.relativePath == path }
    }

    func pendingIdentityRebinding(for path: String) -> NoteIdentityPendingRebinding? {
        pendingIdentityRebindings.first { $0.relativePath == path }
    }

    func identityMigrationFailure(for path: String) -> NoteIdentityMigrationFailure? {
        identityMigrationFailures.first { $0.rebinding.relativePath == path }
    }

    var currentDocumentIdentityAmbiguity: NoteIdentityAmbiguity? {
        guard let path = currentNote?.relativePath else { return nil }
        if let ambiguity = currentDocumentVaultSnapshot?.identityRecovery.ambiguities.first(
            where: { $0.relativePath == path }
        ) {
            return ambiguity
        }
        return identityAmbiguity(for: path)
    }

    var currentDocumentPendingIdentityRebinding: NoteIdentityPendingRebinding? {
        guard let path = currentNote?.relativePath else { return nil }
        if let rebinding = currentDocumentVaultSnapshot?.identityRecovery.pendingRebindings.first(
            where: { $0.relativePath == path }
        ) {
            return rebinding
        }
        return pendingIdentityRebinding(for: path)
    }

    var currentDocumentIdentityMigrationFailure: NoteIdentityMigrationFailure? {
        guard let path = currentNote?.relativePath else { return nil }
        if let failure = currentDocumentVaultSnapshot?.identityRecovery.failures.first(
            where: { $0.rebinding.relativePath == path }
        ) {
            return failure
        }
        return identityMigrationFailure(for: path)
    }

    func requestIdentityResolution(for path: String) {
        let ambiguity = currentNote?.relativePath == path
            ? currentDocumentIdentityAmbiguity
            : identityAmbiguity(for: path)
        guard let ambiguity else { return }
        identityResolutionError = nil
        selectedIdentityAmbiguity = ambiguity
    }

    func resolveSelectedIdentity(candidateID: UUID?) async {
        guard let ambiguity = selectedIdentityAmbiguity else { return }
        isResolvingIdentity = true
        identityResolutionError = nil
        defer { isResolvingIdentity = false }
        do {
            _ = try await documentController.resolveIdentity(
                ambiguity,
                candidateID: candidateID
            )
            selectedIdentityAmbiguity = nil
            await refreshIdentityState()
        } catch {
            identityResolutionError = error.localizedDescription
            try? await refreshNoteLocationScope()
            if let refreshed = identityAmbiguity(for: ambiguity.relativePath) {
                selectedIdentityAmbiguity = refreshed
            }
        }
    }

    func retryIdentityRecovery() async {
        do {
            try await refreshNoteLocationScope()
        } catch {
            identityResolutionError = error.localizedDescription
        }
    }

    @discardableResult
    private func requireResolvedIdentity(for path: String) throws -> UUID? {
        guard let noteID = noteIdentityByPath[path] else {
            throw NoteIdentityRecoveryError.identityUnresolved(path)
        }
        return noteID
    }

    /// Resolves document-scoped commands through the selected document's
    /// vault-qualified identity. Library browsing deliberately owns a
    /// different vault projection, so path-only lookup is unsafe when two
    /// Triptych roots contain the same relative path.
    private func activeDocumentContext(
        for path: String
    ) -> (
        noteID: UUID,
        vaultID: UUID,
        vaultRole: VaultRole,
        fingerprint: DocumentFingerprint,
        note: WindowDocumentLocation
    )? {
        guard let descriptor = currentDocumentDescriptor,
              descriptor.reference.relativePath == path,
              let note = currentNote,
              note.relativePath == path else { return nil }
        return (
            descriptor.sessionKey.noteID,
            descriptor.reference.vaultID,
            descriptor.reference.vaultRole,
            note.document.fingerprint,
            note
        )
    }

    /// Uses the route's exact revision unless it addresses the active editor
    /// session, whose explicit flush may have just committed a newer revision.
    /// In either case the vault and stable note identity remain those captured
    /// by the lifecycle route, never those of the Library's browsed hierarchy.
    private func lifecycleExpectedRevision(
        for target: NoteLifecycleTarget
    ) throws -> DocumentFingerprint {
        guard let descriptor = currentDocumentDescriptor,
              descriptor.reference.vaultID == target.documentID.vaultID,
              descriptor.reference.relativePath == target.relativePath,
              descriptor.sessionKey.noteID == target.stableNoteID else {
            return target.revision
        }
        guard let currentNote,
              currentNote.workspaceSnapshot?.stableIdentity.resolvedID == target.stableNoteID else {
            throw NoteIdentityRecoveryError.identityUnresolved(target.relativePath)
        }
        return currentNote.document.fingerprint
    }

    func registerEditorFlush(
        for relativePath: String,
        token: UUID,
        flush: @escaping @MainActor () async throws -> Void,
        captureForReconstruction: @escaping @MainActor () async throws -> Void
    ) {
        editorFlushCoordinator.registerCurrentEditor(
            relativePath: relativePath,
            token: token,
            triptychID: workspaceAssignment?.id,
            flush: flush,
            captureForReconstruction: captureForReconstruction
        )
    }

    func unregisterEditorFlush(token: UUID) {
        editorFlushCoordinator.unregisterCurrentEditor(
            token: token,
            selectedDocumentPath: selectedDocumentPath
        )
    }

    private func flushRegisteredEditorIfNeeded(
        capturingEditorState: Bool = false
    ) async throws {
        try await editorFlushCoordinator.flushCurrentEditor(
            selectedDocumentPath: selectedDocumentPath,
            capturingEditorState: capturingEditorState,
            fallback: { [weak self] capturingEditorState in
                guard let self else { return }
                try await self.documentController.flushLeasedOrPinnedSessions(
                    capturingEditorState: capturingEditorState
                )
            }
        )
    }

    /// Opening an Action needs the exact current Target, not every open Note
    /// in the Triptych. The sheet is modal for this window, and a later
    /// preparation revalidates the frozen Target rather than saving unrelated
    /// open Notes.
    func flushCurrentEditorBeforeOpeningResearchAction() async throws {
        try await editorFlushCoordinator.flushCurrentEditorForResearchAction(
            selectedDocumentPath: selectedDocumentPath,
            fallback: { [weak self] in
                guard let self,
                      let selectedDocument = self.documentController.selectedDocument else {
                    return
                }
                try await self.documentController.flushBeforeClosing(selectedDocument)
            }
        )
    }

    func prepareForWindowClose() async throws -> ClosePreparationOutcome {
        guard closeAttemptSequence < UInt64.max else {
            throw ScholiumWindowLifecycleError.failed(
                "Window lifecycle attempt IDs were exhausted."
            )
        }
        closeAttemptSequence += 1
        let attempt = LifecycleAttemptID(rawValue: closeAttemptSequence)
        currentCloseAttemptID = attempt
        try await withScholiumLifecycleDeadline(
            phase: .contentFlush,
            timeout: lifecyclePolicy.contentFlush
        ) { [weak self] in
            guard let self else {
                throw ScholiumWindowLifecycleError.unregisteredBeforeReady
            }
            try await self.flushRegisteredEditorIfNeeded()
        }
        guard attempt == currentCloseAttemptID else {
            throw ScholiumWindowLifecycleError.cancelled
        }

        let presentationWarning = await persistWindowSessionBeforeClose(
            attempt: attempt
        )
        guard attempt == currentCloseAttemptID else {
            throw ScholiumWindowLifecycleError.cancelled
        }
        editorFlushCoordinator.shutdown()
        return ClosePreparationOutcome(presentationWarning: presentationWarning)
    }

    /// Serializes every transition that can replace the active document view.
    /// The newest requested destination wins, but an already-running operation
    /// is allowed to finish before the next begins so vault state is never
    /// mutated concurrently by two window transitions. Replacement navigation
    /// still flushes CodeMirror's exact text, but skips serializing selection,
    /// scroll, and undo state that will be discarded with the replaced tab.
    private func enqueueDocumentTransition(
        preservingCurrentEditorState: Bool = true,
        _ operation: @escaping @MainActor () async throws -> Void,
        didFail customFailure: (@MainActor (Error) -> Void)? = nil,
        didSucceed: (@MainActor () -> Void)? = nil,
        didFinish: (@MainActor () -> Void)? = nil
    ) {
        documentTransitionCoordinator.enqueue(
            prepare: { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.flushRegisteredEditorIfNeeded(
                    capturingEditorState: preservingCurrentEditorState
                )
            },
            operation: operation,
            didFail: { [weak self] error in
                guard let self else { return }
                if let customFailure {
                    customFailure(error)
                    return
                }
                if let navigationError = error as? WindowNavigationError {
                    self.showToast(navigationError.localizedDescription, kind: .warning)
                } else {
                    self.lastSaveError = error.localizedDescription
                    self.showToast(
                        "The current note could not be saved, so Scholium kept it open. \(error.localizedDescription)",
                        kind: .error
                    )
                }
            },
            didSucceed: { didSucceed?() },
            didFinish: { didFinish?() }
        )
    }

    #if DEBUG
    func waitForPendingDocumentTransitionsForTesting() async {
        await documentTransitionCoordinator.waitForIdle()
    }
    #endif

    /// The only cross-feature routing boundary. Feature controllers emit a
    /// closed intent and never reach into a peer controller's mutable state.
    private func handleWindowIntent(_ intent: WindowIntent) {
        switch intent {
        case .openDocument(let route):
            if route.disposition == .newTab {
                requestOpenNote(route.reference, disposition: .newTab)
                return
            }
            Task { [weak self] in
                await self?.openWorkspaceReference(
                    route.reference,
                    line: route.sourceLocator?.line,
                    mode: route.sourceLocator == nil ? .read : .source
                )
            }
        case .openSearchResult(let result, let disposition):
            Task { [weak self] in
                await self?.searchController.open(result, disposition: disposition)
            }
        case .revealSourceLocator(let vaultID, let locator):
            Task { [weak self] in
                guard let self else { return }
                do {
                    let vault = try await self.workspaceStore.resolveVault(vaultID.uuidString)
                    let reference = VaultNoteReference(
                        vaultID: vault.id,
                        vaultName: vault.name,
                        vaultRole: vault.role,
                        relativePath: locator.file,
                        stableNoteID: nil
                    )
                    await self.openWorkspaceReference(
                        reference,
                        line: locator.line,
                        mode: .source
                    )
                } catch {
                    self.vaultError = error.localizedDescription
                }
            }
        case .switchVault(let vaultID):
            Task { [weak self] in
                guard let self else { return }
                do {
                    let vault = try await self.workspaceStore.resolveVault(vaultID.uuidString)
                    try await self.browseRegisteredVault(vault)
                } catch {
                    self.vaultError = error.localizedDescription
                }
            }
        case .presentResearchAction(let route):
            guard currentResearchFunctionReference == route.target,
                  researchController.actions.presentationID == route.presentationID,
                  researchController.actions.activeActionID == route.actionID else { return }
            presentationRouter.present(.researchAction(route))
        case .presentLifecycle(let request):
            noteLifecycleRequest = request
        }
    }

    private func openSearchSelection(
        _ result: SearchResultSelection,
        disposition: WindowOpenDisposition
    ) async {
        switch result {
        case .related:
            var route = result.documentRoute
            route = WindowDocumentRoute(
                reference: route.reference,
                sourceLocator: route.sourceLocator,
                disposition: disposition
            )
            if disposition == .newTab {
                requestOpenNote(route.reference, disposition: .newTab)
            } else {
                await openWorkspaceReference(
                    route.reference,
                    line: route.sourceLocator?.line,
                    mode: route.sourceLocator == nil ? .read : .source
                )
            }
        case .lexical(let hit):
            let reference = VaultNoteReference(
                vaultID: hit.vaultID,
                vaultName: hit.vaultName,
                vaultRole: hit.vaultRole,
                relativePath: hit.relativePath,
                stableNoteID: hit.stableNoteID
            )
            let isCurrentDocument = currentDocumentDescriptor?.reference.vaultID == hit.vaultID
                && currentDocumentDescriptor?.reference.relativePath == hit.relativePath
            if isCurrentDocument {
                pendingSourceRange = hit.sourceRange
                pendingSourceLine = hit.sourceRange?.line ?? hit.sourceLine
                requestPresentationMode = .source
            } else if disposition == .newTab {
                requestOpenNote(reference, disposition: .newTab)
            } else {
                openWorkspaceReference(
                    reference,
                    sourceRange: hit.sourceRange,
                    fallbackLine: hit.sourceLine
                )
            }
        }
    }

    func requestOpenNote(
        _ path: String,
        disposition: WindowOpenDisposition = .replaceCurrent
    ) {
        if disposition == .newTab {
            guard let reference = documentReference(for: path) else { return }
            requestOpenNote(reference, disposition: .newTab)
            return
        }
        enqueueDocumentTransition(preservingCurrentEditorState: false) { [weak self] in
            guard let self else { return }
            self.openNote(path)
        }
    }

    func requestOpenNote(
        _ location: WindowDocumentLocation,
        disposition: WindowOpenDisposition = .replaceCurrent
    ) {
        guard let snapshot = location.workspaceSnapshot else {
            requestOpenNote(location.relativePath, disposition: disposition)
            return
        }
        guard let vault = workspaceAssignment?.vaults.values.first(where: {
            $0.id == snapshot.id.vaultID
        }) else {
            showToast(String(localized: "The selected vault is no longer available.", table: "Localizable", bundle: .module), kind: .warning)
            return
        }
        let reference = VaultNoteReference(
            vaultID: vault.id,
            vaultName: vault.name,
            vaultRole: vault.role,
            relativePath: snapshot.id.relativePath,
            stableNoteID: snapshot.stableIdentity.resolvedID?.uuidString.lowercased()
        )
        requestOpenNote(reference, disposition: disposition)
    }

    func requestOpenNote(
        _ reference: VaultNoteReference,
        disposition: WindowOpenDisposition = .replaceCurrent
    ) {
        if disposition == .newTab {
            openInNewTab(reference)
            return
        }
        enqueueDocumentTransition(preservingCurrentEditorState: false) { [weak self] in
            guard let self else { return }
            try self.activateWorkspaceReference(
                reference,
                tabActivation: .place(.replaceSelected)
            )
        }
    }

    /// Opens the common Synthesize sheet for one exact, derived
    /// Topic/Analysis revision condition. Preparation remains fail-closed at
    /// the Application boundary if either source or record changed meanwhile.
    func requestResynthesis(_ item: AttentionQueueItem) {
        guard item.kind == .materialChangedSinceUse,
              let context = item.materialChangedSinceUse else { return }
        enqueueDocumentTransition(preservingCurrentEditorState: false, { [weak self] in
            guard let self else { return }
            try self.activateWorkspaceReference(
                item.note,
                tabActivation: .place(.replaceSelected)
            )
            guard let target = self.currentResearchActionTarget,
                  target.noteID == context.topicNoteID else {
                throw WindowNavigationError.noteUnavailable(
                    item.note.relativePath
                )
            }
            await self.researchController.actions.refreshAvailability(
                for: target
            )
            // ContentView also refreshes Actions when the active target
            // changes. If that task superseded this request, make one final
            // request so the transition itself owns a confirmed availability
            // snapshot before presenting the sheet.
            if !self.hasConfirmedCurrentResearchActionAvailability {
                await self.researchController.actions.refreshAvailability(
                    for: target
                )
            }
            let synthesis = self.researchController.actions.availability.first {
                $0.id == .synthesize
            }
            guard self.hasConfirmedCurrentResearchActionAvailability,
                  synthesis?.canPresentInInterface == true else {
                let reason = synthesis?.repairReasons.first?.interfaceDescription
                    ?? String(
                        localized: "Scholium could not confirm that this Action is available for the current note.",
                        table: "Localizable",
                        bundle: .module
                    )
                throw ScholiumApplicationError.researchStoreUnavailable(
                    reason
                )
            }
        }, didFail: { [weak self] error in
            self?.showToast(error.localizedDescription, kind: .warning)
        }, didSucceed: { [weak self] in
            self?.openResearchAction(
                .synthesize,
                initialMaterialNoteIDs: [context.materialNoteID],
                resynthesisContext: context
            )
        })
    }

    func requestOpenNote(
        _ note: VaultQualifiedNoteID,
        stableNoteID: UUID,
        sourceLine: Int? = nil
    ) {
        guard let vault = workspaceAssignment?.vaults.values.first(where: {
            $0.id == note.vaultID
        }) else {
            showToast(
                String(
                    localized: "The selected vault is no longer available.",
                    table: "Localizable",
                    bundle: .module
                ),
                kind: .warning
            )
            return
        }
        let reference = VaultNoteReference(
            vaultID: vault.id,
            vaultName: vault.name,
            vaultRole: vault.role,
            relativePath: note.relativePath,
            stableNoteID: stableNoteID.uuidString.lowercased()
        )
        enqueueDocumentTransition(preservingCurrentEditorState: false) { [weak self] in
            guard let self else { return }
            try self.activateWorkspaceReference(
                reference,
                tabActivation: .place(.replaceSelected)
            )
            if let sourceLine {
                self.pendingSourceRange = nil
                self.pendingSourceLine = max(1, sourceLine)
                self.requestPresentationMode = .source
            }
        }
    }

    func requestOpenNote(
        _ path: String,
        sourceLine: Int,
        mode: NotePresentationMode = .source
    ) {
        enqueueDocumentTransition(preservingCurrentEditorState: false) { [weak self] in
            guard let self else { return }
            self.pendingSourceLine = max(1, sourceLine)
            self.openNote(path)
            self.requestPresentationMode = mode
        }
    }

    func requestWorkspaceVault(_ slot: WorkspaceVaultSlot) {
        let currentLocation = discoveryController.library.locationScope
        guard discoveryController.library.workspaceSlot != slot
                || discoveryController.library.locationError != nil
                || discoveryController.locationRequestIsActive else { return }
        let request = discoveryController.beginLocationRequest(
            workspaceSlot: slot,
            location: currentLocation,
            presentation: .stagedReplacement
        )
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.browseWorkspaceVault(slot, request: request)
            } catch is CancellationError {
                return
            } catch {
                guard self.discoveryController.isCurrentLocationRequest(request) else { return }
                self.discoveryController.failLocationRequest(
                    error.localizedDescription,
                    for: request
                )
                self.showToast(
                    "Could not browse \(slot.displayName): \(error.localizedDescription)",
                    kind: .error
                )
            }
        }
    }

    func requestNoteLocationScope(_ scope: NoteLocationScope) {
        Task { [weak self] in await self?.selectNoteLocationScope(scope) }
    }

    func requestLifecycleNote(_ path: String, in scope: NoteLocationScope) {
        guard scope == .setAside || scope == .trash else { return }
        enqueueDocumentTransition(preservingCurrentEditorState: false) { [weak self] in
            guard let self else { return }
            await self.selectNoteLocationScope(scope)
            self.openNote(path)
        }
    }

    func putBackNote(_ path: String) async throws {
        try await flushRegisteredEditorIfNeeded()
        guard let noteID = try requireResolvedIdentity(for: path) else {
            throw NoteIdentityRecoveryError.identityUnresolved(path)
        }
        guard let vaultID = currentRegisteredVault?.id,
              let expected = documentRevisions[path] else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let commit: TriptychMoveCommit
        do {
            commit = try await documentController.putBack(
                VaultQualifiedNoteID(vaultID: vaultID, relativePath: path),
                expectedRevision: expected
            )
        } catch {
            await refreshTransactionRecoveryRecords()
            throw error
        }
        let destination = commit.destination.relativePath
        migrateAppOwnedState(
            sourcePath: path,
            destinationPath: destination,
            noteID: noteID,
            vaultID: vaultID
        )
        try await refreshNoteLocationScope()
        if noteLocationScope == .workspace { openNote(destination) }
        scheduleWorkspaceCatalogRefresh()
    }

    func requestDocumentMode(_ mode: NotePresentationMode) {
        guard mode == .read || canEditCurrentNote else {
            showToast(String(localized: "This note is read-only in Scholium.", table: "Localizable", bundle: .module), kind: .information)
            return
        }
        requestPresentationMode = mode
    }

    #if DEBUG
    /// Drives the retained-editor performance scenario through the current
    /// document session instead of a one-shot SwiftUI presentation request.
    /// The editor bridge still performs the real mode transition and reports
    /// readiness only after CodeMirror acknowledges it.
    private func requestPerformanceEditorMode(_ mode: NotePresentationMode) {
        guard Bundle.main.bundleIdentifier == "com.scholium.qa",
              ProcessInfo.processInfo.arguments.contains(
                  "--scholium-performance-editor-mode-notifications"
              ),
              mode != .read,
              canEditCurrentNote,
              let descriptor = currentDocumentDescriptor else { return }

        let session = documentController.session(for: descriptor)
        guard session.isEditing, session.editorSession.isLoaded else {
            requestDocumentMode(mode)
            return
        }
        guard session.editorSession.context?.composing != true else { return }

        guard let editorMode = mode.editorMode else { return }
        session.switchEditorMode(to: editorMode)
    }
    #endif

    func openResearchAction(
        _ actionID: ResearchActionID,
        selection: CommentAnchor? = nil,
        initialMaterialNoteIDs: Set<UUID> = [],
        resynthesisContext: MaterialChangedSinceUseAttentionContext? = nil
    ) {
        guard let initialTarget = currentResearchActionTarget else { return }
        if actionID == .discuss,
           let discussion = researchController.records?.activeDiscussions.first(where: {
               $0.primaryNoteID == initialTarget.noteID
                   && $0.action != nil
                   && $0.method != nil
           }) {
            requestDiscussionPresentation(discussion.id)
            return
        }
        guard !researchController.actions.hasCancellationBarrier else {
            showToast(
                String(
                    localized: "Resolve the pending Action cancellation before starting another Action.",
                    table: "Localizable",
                    bundle: .module
                ),
                kind: .warning
            )
            return
        }
        guard hasConfirmedCurrentResearchActionAvailability else { return }
        guard let initialAvailability = researchController.actions.availability.first(where: {
                  $0.id == actionID
              }), initialAvailability.canPresentInInterface else { return }
        let initialNoteID = initialTarget.noteID
        let requestID = UUID()
        researchActionOpenRequestID = requestID
        researchActionOpenTask?.cancel()

        researchActionOpenTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.flushCurrentEditorBeforeOpeningResearchAction()
                guard !Task.isCancelled,
                      self.researchActionOpenRequestID == requestID,
                      let target = self.currentResearchActionTarget,
                      target.noteID == initialNoteID,
                      let reference = self.currentResearchFunctionReference else { return }
                if actionID == .discuss,
                   let discussion = self.researchController.records?.activeDiscussions.first(where: {
                        $0.primaryNoteID == target.noteID
                            && $0.action != nil
                            && $0.method != nil
                   }) {
                    self.requestDiscussionPresentation(discussion.id)
                    return
                }
                let availability: ResearchActionAvailability
                if target == initialTarget {
                    guard self.hasConfirmedCurrentResearchActionAvailability,
                          self.researchController.actions.availability.first(where: {
                              $0.id == actionID
                          }) == initialAvailability else { return }
                    availability = initialAvailability
                } else {
                    await self.researchController.actions.refreshAvailability(for: target)
                    guard !Task.isCancelled,
                          self.researchActionOpenRequestID == requestID,
                          self.hasConfirmedCurrentResearchActionAvailability,
                          let refreshed = self.researchController.actions.availability.first(where: {
                              $0.id == actionID
                          }) else { return }
                    availability = refreshed
                }
                guard let refreshedTarget = self.currentResearchActionTarget,
                      refreshedTarget == target,
                      self.researchController.actions.availabilityTarget == target,
                      !self.researchController.actions.isRefreshingAvailability,
                      self.researchController.actions.availabilityError == nil,
                      availability.canPresentInInterface else {
                    let reason = self.researchController.actions.availability.first(where: {
                        $0.id == actionID
                    })?.repairReasons.first?.interfaceDescription
                        ?? String(
                            localized: "Scholium could not confirm that this Action is available for the current note.",
                            table: "Localizable",
                            bundle: .module
                        )
                    self.showToast(reason, kind: .information)
                    return
                }
                let capturedSelection: CommentAnchor?
                if let selection, selection.fingerprint == target.fingerprint {
                    capturedSelection = selection
                } else {
                    capturedSelection = nil
                    if selection != nil {
                        self.showToast(
                            String(
                                localized: "The selected passage changed while Scholium saved the note. The Action will open for the whole note.",
                                table: "Localizable",
                                bundle: .module
                            ),
                            kind: .information
                        )
                    }
                }
                let presentationID = UUID()
                guard !self.researchController.actions.hasCancellationBarrier,
                      self.researchController.actions.begin(
                    target: target,
                    availability: availability,
                    selection: capturedSelection,
                    initialInstruction: actionID == .discuss
                        ? "Discuss this note, including any existing Comments."
                        : nil,
                    initialMaterialNoteIDs: initialMaterialNoteIDs,
                    resynthesisContext: resynthesisContext,
                    presentationID: presentationID
                      ) else {
                    self.showToast(
                        String(
                            localized: "Resolve the pending Action cancellation before starting another Action.",
                            table: "Localizable",
                            bundle: .module
                        ),
                        kind: .warning
                    )
                    return
                }
                self.researchController.requestPresentAction(
                    actionID,
                    target: reference,
                    presentationID: presentationID
                )
            } catch {
                guard !Task.isCancelled,
                      self.researchActionOpenRequestID == requestID else { return }
                self.showToast(
                    String(
                        localized: "Scholium could not save the current editor before opening this Action. \(error.localizedDescription)",
                        table: "Localizable",
                        bundle: .module
                    ),
                    kind: .error
                )
            }
        }
    }

    func requestDiscussionPresentation(_ discussionID: UUID) {
        let requestID = UUID()
        discussionPresentationRequestID = requestID
        requestedDiscussionID = nil
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  self.discussionPresentationRequestID == requestID else { return }
            self.requestedDiscussionID = discussionID
        }
    }

    func clearRequestedDiscussionPresentation() {
        discussionPresentationRequestID = nil
        requestedDiscussionID = nil
    }

    var hasDerivedRefreshFailure: Bool {
        switch derivedRefreshStatus {
        case .stale, .failed:
            true
        case .current, .none:
            false
        }
    }

    func retryDerivedRefresh() async {
        guard let vaultID = currentRegisteredVault?.id else { return }
        refreshStatusText = "Retrying Triptych refresh…"
        do {
            let snapshot = try await discoveryController.refreshWorkspace()
            guard currentRegisteredVault?.id == vaultID,
                  let capabilities = activeWorkspaceCapabilities,
                  let commit = workspaceProjectionController.replaceSnapshot(
                      snapshot,
                      runtimeIdentity: capabilities.runtimeIdentity,
                      status: .current(WorkspaceDerivedRefreshEvidence(snapshot: snapshot)),
                      context: workspaceProjectionContext
                  ) else { return }
            applyWorkspaceProjectionCommit(commit)
            refreshStatusText = nil
            workspaceProjectionController.reportCatalogError(nil)
        } catch {
            refreshStatusText = "Triptych refresh failed"
            workspaceProjectionController.reportCatalogError(error.localizedDescription)
        }
    }

    var filteredNotes: [WindowDocumentLocation] {
        var result = notes
        guard noteLocationScope == .workspace else {
            return result.sorted(by: notesAreOrdered)
        }
        if isNeedsAttentionFilter, let paths = currentAttentionPaths {
            result = result.filter { paths.contains($0.relativePath) }
        }
        if isExplicitConnectionsFilter, let paths = currentExplicitConnectionPaths {
            result = result.filter { paths.contains($0.relativePath) }
        }
        if isMalformedMetadataFilter, let paths = currentMalformedMetadataPaths {
            result = result.filter { paths.contains($0.relativePath) }
        }
        if let tag = selectedTag { result = result.filter { $0.tags.contains(tag) } }
        if let author = selectedAuthor { result = result.filter { $0.authors.contains(author) } }
        if let year = selectedYear { result = result.filter { $0.year == year } }
        if let key = selectedPropertyKey, let value = selectedPropertyValue {
            result = result.filter { $0.property(at: key)?.appFilterValues.contains(value) == true }
        }
        return result.sorted(by: notesAreOrdered)
    }

    var activeResearchFilterCount: Int {
        [
            isNeedsAttentionFilter,
            isExplicitConnectionsFilter,
            isMalformedMetadataFilter,
        ].count(where: { $0 })
    }

    func clearResearchFilters() {
        isNeedsAttentionFilter = false
        isExplicitConnectionsFilter = false
        isMalformedMetadataFilter = false
    }

    private var currentAttentionPaths: Set<String>? {
        guard let vaultID = currentRegisteredVault?.id,
              let workspaceCatalog else { return nil }
        return Set(workspaceCatalog.attention.compactMap { item in
            item.note.vaultID == vaultID ? item.note.relativePath : nil
        })
    }

    private var currentMalformedMetadataPaths: Set<String>? {
        guard let vaultID = currentRegisteredVault?.id,
              let workspaceCatalog else { return nil }
        return Set(workspaceCatalog.notes.compactMap { catalogNote in
            guard catalogNote.reference.vaultID == vaultID,
                  !catalogNote.validationWarnings.isEmpty else { return nil }
            return catalogNote.reference.relativePath
        })
    }

    private var currentExplicitConnectionPaths: Set<String>? {
        guard let vaultID = currentRegisteredVault?.id,
              let graph = relationshipGraph else { return nil }
        return Set(notes.compactMap { note in
            let noteID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: note.relativePath)
            let edges = (graph.outgoing[noteID] ?? []) + (graph.incoming[noteID] ?? [])
            let hasExplicitConnection = edges.contains { edge in
                guard edge.destination != nil else { return false }
                return edge.occurrence.vectorKind == nil || edge.occurrence.vectorKind != .neutral
            }
            return hasExplicitConnection ? note.relativePath : nil
        })
    }

    func notesAreOrdered(_ lhs: WindowDocumentLocation, _ rhs: WindowDocumentLocation) -> Bool {
        let lhsTitle = lhs.title ?? lhs.displayName
        let rhsTitle = rhs.title ?? rhs.displayName
        switch noteSortOrder {
        case .modifiedNewest:
            if lhs.fileModifiedAt != rhs.fileModifiedAt { return lhs.fileModifiedAt > rhs.fileModifiedAt }
        case .modifiedOldest:
            if lhs.fileModifiedAt != rhs.fileModifiedAt { return lhs.fileModifiedAt < rhs.fileModifiedAt }
        case .titleAscending:
            return lhsTitle.localizedStandardCompare(rhsTitle) == .orderedAscending
        case .titleDescending:
            return lhsTitle.localizedStandardCompare(rhsTitle) == .orderedDescending
        case .debateImportanceDescending:
            guard hasScopedDebateImportanceFilter else {
                if lhs.fileModifiedAt != rhs.fileModifiedAt { return lhs.fileModifiedAt > rhs.fileModifiedAt }
                break
            }
            switch (lhs.debateImportance, rhs.debateImportance) {
            case let (left?, right?) where left != right:
                return left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }
        }
        return lhsTitle.localizedStandardCompare(rhsTitle) == .orderedAscending
    }

    var hasScopedDebateImportanceFilter: Bool {
        selectedPropertyKey == "debate_importance_scope"
            && selectedPropertyValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var availableAuthors: [String] {
        Set(notesInCurrentScope.flatMap(\.authors)).sorted()
    }

    var availableYears: [Int] {
        Set(notesInCurrentScope.compactMap(\.year)).sorted(by: >)
    }

    var activeMetadataFilterCount: Int {
        [
            selectedAuthor != nil,
            selectedYear != nil,
            selectedPropertyKey != nil && selectedPropertyValue != nil,
        ].count(where: { $0 })
    }

    func clearMetadataFilters() {
        selectedAuthor = nil
        selectedYear = nil
        selectedPropertyKey = nil
        selectedPropertyValue = nil
        if noteSortOrder == .debateImportanceDescending {
            noteSortOrder = .modifiedNewest
        }
    }

    private var notesInCurrentScope: [WindowDocumentLocation] {
        notes
    }

    // MARK: Actions

    /// Mirrors the native Sidebar state for focused labels and next-session
    /// restoration. Researcher intents enter through WorkspaceWindowActions.
    func recordLibraryVisibility(_ visible: Bool) {
        guard sidebarVisible != visible else { return }
        sidebarVisible = visible
    }

    func openRequestedInitialDocumentIfNeeded() {
        guard !didOpenRequestedInitialDocument,
              workspaceAssignment != nil,
              let requestedInitialDocument else { return }
        didOpenRequestedInitialDocument = true
        requestOpenNote(requestedInitialDocument, disposition: .replaceCurrent)
    }

    private func openInNewTab(_ reference: VaultNoteReference) {
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            try self.activateWorkspaceReference(
                reference,
                tabActivation: .place(.newTab)
            )
        }
    }

    func selectDocumentTab(withID id: UUID) {
        guard documentTabController.selectedTabID != id,
              let tab = documentTabController.tabs.first(where: { $0.id == id }) else {
            return
        }
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            try self.activateDocument(
                tab.document,
                tabActivation: .preserveTabMembership
            )
            self.documentTabController.selectTab(withID: id)
            self.reconcileDocumentSessionLeases()
        }
    }

    func closeDocumentTab(withID id: UUID) {
        guard let plan = documentTabController.closePlan(forTabWithID: id) else {
            return
        }
        guard let closingDocument = documentTabController.tabs.first(where: { $0.id == id })?.document else {
            return
        }
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            try await self.documentController.flushBeforeClosing(closingDocument)
            if let documentToActivate = plan.documentToActivate {
                try self.activateDocument(
                    documentToActivate,
                    tabActivation: .preserveTabMembership
                )
            } else {
                self.documentController.clearSelectionAfterClosingLastTab()
            }
            self.documentTabController.apply(plan)
            self.reconcileDocumentSessionLeases()
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.documentController.reapDetachedSessions()
            }
        }
    }

    /// Mirrors the native Inspector state without driving its geometry.
    func recordResearchInspectorVisibility(_ visible: Bool) {
        guard visible != researchInspectorVisible else { return }
        researchInspectorVisible = visible
    }

    func presentationMode(for path: String) -> NotePresentationMode {
        documentController.presentationMode(for: path, vaultID: currentDocumentVaultID)
    }

    func rememberPresentationMode(_ mode: NotePresentationMode, for path: String) {
        documentController.rememberPresentationMode(
            mode,
            for: path,
            vaultID: currentDocumentVaultID
        )
        documentPresentationDidChange.send()
    }

    func scrollPosition(for path: String) -> Double {
        documentController.scrollPosition(for: path, vaultID: currentDocumentVaultID)
    }

    func rememberScrollPosition(_ fraction: Double, for path: String) {
        documentController.rememberScrollPosition(
            fraction,
            for: path,
            vaultID: currentDocumentVaultID
        )
        documentPresentationDidChange.send()
    }

    /// Restores only committed presentation state. Editor buffers are absent
    /// from `WindowSessionSnapshot` and therefore cannot override disk bytes.
    func restoreWindowSession(id: UUID) async {
        guard !didRestoreWindowSession || windowSessionID != id else { return }
        windowSessionID = id
        editorFlushCoordinator.updateWindowID(id)
        isRestoringWindowSession = true
        defer {
            isRestoringWindowSession = false
            didRestoreWindowSession = true
            shellState.completeInitialRestore()
            persistWindowSessionNow()
        }

        let stored: WindowSessionSnapshot?
        do {
            stored = try await workspaceStore.windowSession(id: id)
        } catch {
            showToast(String(localized: "The saved window layout could not be restored. Scholium opened a clean window instead.", table: "Localizable", bundle: .module), kind: .warning)
            stored = nil
        }
        guard let stored else {
            // New configured windows keep the stable three-region shell.
            // Visibility changes only after a direct researcher action.
            shellState.restoreLibraryVisibility(true)
            researchController.restoreInspector(
                storedMode: nil,
                isVisible: nil
            )
            await restoreWorkspaceIfNeeded()
            return
        }

        await refreshRegisteredVaults()
        await refreshWorkspaceAssignment(
            preferredTriptychID: requestedTriptychID ?? stored.triptychID
        )
        guard let restoredAssignment = workspaceAssignment else {
            attemptedVaultRestore = true
            return
        }
        do {
            let browsedVaultID = stored.vaultID
                ?? requestedInitialDocument?.vaultID
                ?? stored.selectedDocument?.vaultID
            if let vaultID = browsedVaultID,
               let vault = restoredAssignment.vaults.values.first(where: { $0.id == vaultID }) {
                attemptedVaultRestore = true
                try await openRegisteredVault(vault)
            } else {
                await restoreWorkspaceIfNeeded()
            }
        } catch {
            vaultError = error.localizedDescription
            return
        }

        let restoredDocumentVaultID = requestedInitialDocument?.vaultID
            ?? stored.selectedDocument?.vaultID
        let restoredDocumentPaths = restoredDocumentVaultID
            .flatMap { workspaceProjectionController.vaultSnapshot(id: $0) }
            .map { Set($0.documents.map(\.id.relativePath)) }
            ?? Set(notes.map(\.relativePath))
        let restoredPresentation = stored.normalized(availablePaths: restoredDocumentPaths)
        let hasRestorableDocument = requestedInitialDocument != nil
            || restoredPresentation.selectedDocument.map {
                restoredDocumentPaths.contains($0.relativePath)
            } == true
        shellState.restoreLibraryVisibility(
            hasRestorableDocument
                ? (restoredPresentation.libraryVisible ?? true)
                : true
        )
        researchController.restoreInspector(
            storedMode: restoredPresentation.inspectorMode,
            isVisible: restoredPresentation.inspectorVisible
        )
        discoveryController.replaceSearchCriteria(SearchWorkspaceState(
            scope: restoredPresentation.searchState.scope
        ))
        shellState.setDocumentTextScale(
            restoredPresentation.documentTextScale
                ?? ScholiumMetrics.Document.defaultTextScale
        )
        documentController.restorePresentationState(
            modes: restoredPresentation.documentModes,
            scrollPositions: restoredPresentation.scrollPositions,
            vaultID: restoredDocumentVaultID
        )
        if requestedInitialDocument == nil,
           let restoredDocument = restoredPresentation.selectedDocument,
           restoredDocumentPaths.contains(restoredDocument.relativePath) {
            openRestoredDocument(restoredDocument)
        }
        _ = restoredPresentation.contentDestination
    }

    func persistWindowSessionNow() {
        guard didRestoreWindowSession,
              !isRestoringWindowSession,
              !windowSessionPersistenceCoordinator.isFinalizing else { return }
        let snapshot = currentWindowSessionSnapshot()
        windowSessionPersistenceCoordinator.schedule(
            snapshot: snapshot,
            save: { [workspaceStore] snapshot, attempt in
                try await workspaceStore.saveWindowSession(
                    snapshot,
                    attempt: attempt
                )
            },
            completion: { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    self.shellState.clearWindowSessionPersistenceFailure()
                case .failure(let error):
                    self.shellState.recordWindowSessionPersistenceFailure(
                        error.localizedDescription
                    )
                }
            }
        )
    }

    /// Window state is recoverable presentation data, not document content.
    /// A bounded failure is recorded for the next launch but cannot turn a
    /// content-safe close into an unbounded or permanently blocked close.
    private func persistWindowSessionBeforeClose(
        attempt: LifecycleAttemptID
    ) async -> String? {
        guard didRestoreWindowSession,
              !isRestoringWindowSession else { return nil }
        let snapshot = currentWindowSessionSnapshot()
        let result = await windowSessionPersistenceCoordinator.finalize(
            snapshot: snapshot,
            attemptIsCurrent: { [weak self] in
                self?.currentCloseAttemptID == attempt
            }
        )
        switch result {
        case .saved:
            shellState.clearWindowSessionPersistenceFailure()
            return nil
        case .failed(let message):
            shellState.recordWindowSessionPersistenceFailure(message)
            return message
        case .superseded:
            return nil
        }
    }

    private func currentWindowSessionSnapshot() -> WindowSessionSnapshot {
        let browsedVaultID = currentRegisteredVault?.id
        let documentPresentation = documentController.presentationSnapshot(
            vaultID: currentDocumentVaultID
        )
        return WindowSessionSnapshot(
            id: windowSessionID,
            triptychID: workspaceAssignment?.id,
            vaultID: browsedVaultID,
            selectedDocument: selectedDocument,
            documentModes: documentPresentation.modes,
            scrollPositions: documentPresentation.scrollPositions,
            libraryVisible: sidebarVisible,
            inspectorMode: researchInspectorMode.rawValue,
            inspectorVisible: researchInspectorVisible,
            contentDestination: .document,
            searchState: SearchWorkspaceState(scope: searchController.ordinaryScope),
            documentTextScale: documentTextScale
        )
    }

    private func observeWindowSessionChanges() {
        let stateChanges: [AnyPublisher<Void, Never>] = [
            windowWorkspaceController.$state
                .map { $0.assignment?.id }
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
            $currentRegisteredVault.map { _ in () }.eraseToAnyPublisher(),
            documentController.$selectedDocument.map { _ in () }.eraseToAnyPublisher(),
            shellState.$libraryVisible.map { _ in () }.eraseToAnyPublisher(),
            shellState.$documentTextScale.map { _ in () }.eraseToAnyPublisher(),
            shellState.$inspector.map { _ in () }.eraseToAnyPublisher(),
            discoveryController.$search.map { _ in () }.eraseToAnyPublisher(),
        ]
        let changes = stateChanges.map { $0.dropFirst().eraseToAnyPublisher() }
            + [documentPresentationDidChange.eraseToAnyPublisher()]
        Publishers.MergeMany(changes)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] in self?.persistWindowSessionNow() }
            .store(in: &workspaceCancellables)
    }

    func adjustDocumentTextScale(by delta: Double) {
        shellState.setDocumentTextScale(documentTextScale + delta)
    }

    func setDocumentTextScale(_ requestedScale: Double) {
        shellState.setDocumentTextScale(requestedScale)
    }

    func resetDocumentTextScale() {
        shellState.resetDocumentTextScale()
    }

    func refreshWorkspaceAssignment(preferredTriptychID: UUID? = nil) async {
        let resolution = await windowWorkspaceController.resolveAssignment(
            preferredTriptychID: preferredTriptychID,
            currentTriptychID: workspaceAssignment?.id
        )
        switch resolution {
        case .unavailable(let assignments, let message):
            registeredTriptychs = assignments
            workspaceAssignment = nil
            workspaceRecoveryMessage = message
        case .selected(let assignments, let assignment, let repairFailure):
            registeredTriptychs = assignments
            workspaceAssignment = assignment
            let activated = await activateTriptychServicesReportingFailure(
                assignment: assignment
            )
            if activated, let repairFailure {
                workspaceRecoveryMessage = "Scholium opened the registered Triptych, but could not repair its stored vault identities. \(repairFailure)"
            }
        }
    }

    @discardableResult
    private func activateTriptychServicesReportingFailure(
        assignment: TriptychAssignment
    ) async -> Bool {
        do {
            try await activateTriptychServices(assignment: assignment)
            return true
        } catch {
            if let recovery = workspaceAccessRecoveryRoute(for: error) {
                workspaceAccessRecovery = recovery
                workspaceRecoveryMessage = workspaceAccessRecoveryMessage(for: recovery)
                vaultError = nil
                return false
            }
            let message = "Scholium could not activate this Triptych's shared files, search, and research history. The registered locations remain unchanged. \(error.localizedDescription)"
            workspaceRecoveryMessage = message
            vaultError = message
            return false
        }
    }

    func configureTriptych(
        paperAnalysisURL: URL,
        topicKnowledgeURL: URL,
        outputURL: URL,
        portableContainerURL: URL,
        triptychID: UUID? = nil,
        triptychName: String? = nil
    ) async throws {
        let intendedTriptychID = triptychID ?? workspaceAssignment?.id ?? requestedTriptychID
        let normalizedTriptychName = triptychName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let capabilities = try await workspaceStore.configureTriptychCapabilities(
            paperAnalysisURL: paperAnalysisURL,
            topicKnowledgeURL: topicKnowledgeURL,
            outputURL: outputURL,
            portableContainerURL: portableContainerURL,
            triptychID: intendedTriptychID,
            triptychName: (normalizedTriptychName?.isEmpty == false ? normalizedTriptychName : nil)
                ?? registeredTriptychs.first(where: { $0.id == triptychID })?.triptych.name
                ?? workspaceAssignment?.triptych.name
        )
        let assignment = capabilities.assignment
        workspaceAssignment = assignment
        workspaceAccessRecovery = nil
        registeredVaults = await workspaceStore.registeredVaults()
        registeredTriptychs = (try? await workspaceStore.registeredTriptychs()) ?? []
        try await activateTriptychServices(assignment: assignment)
        if let current = currentRegisteredVault,
           let assignedCurrent = assignment.vaults.values.first(where: {
               $0.id == current.id || $0.canonicalPath == current.canonicalPath
           }) {
            currentRegisteredVault = assignedCurrent
            currentVaultRole = assignedCurrent.role
            return
        }
        try await openWorkspaceVault(.paperAnalysis)
    }

    func activateRegisteredTriptych(id: UUID) async {
        await refreshWorkspaceAssignment(preferredTriptychID: id)
    }

    func portableContainerURL(for worksURL: URL) async -> URL? {
        await workspaceStore.portableContainerURL(forWorksURL: worksURL)
    }

    var requestedTriptychIDForRecovery: UUID? { requestedTriptychID }

    private func activateTriptychServices(
        assignment: TriptychAssignment
    ) async throws {
        let capabilities = try await workspaceStore.workspaceCapabilities(id: assignment.id)
        bindApplicationCapabilities(to: capabilities)
        let researchSnapshot = try await researchController.researchSnapshot()
        triptychSettings = try await researchController.settings()
        if !researchSnapshot.healthIssues.isEmpty {
            vaultError = ([
                "Some Scholium research history could not be loaded. The affected files remain unchanged and edits to those records are blocked.",
            ] + researchSnapshot.healthIssues).joined(separator: "\n\n")
        }
        let recoveryIssues = try await documentController.recoverInterruptedTransactions()
        if !recoveryIssues.isEmpty {
            workspaceRecoveryMessage = ([
                "An interrupted permanent deletion still requires inspection.",
            ] + recoveryIssues).joined(separator: "\n")
        }
        do {
            transactionRecoveryRecords = try await researchController.recoveryRecords()
            transactionRecoveryError = nil
        } catch {
            transactionRecoveryRecords = []
            transactionRecoveryError = "Scholium could not read the durable recovery records. Their file remains unchanged. \(error.localizedDescription)"
        }
        activeTriptychServicesID = assignment.id
    }

    private func bindApplicationCapabilities(
        to capabilities: WindowWorkspaceCapabilities,
        snapshot: WorkspaceSnapshot? = nil
    ) {
        activeWorkspaceCapabilities = capabilities
        discoveryController.bind(to: capabilities.discovery)
        documentController.bind(
            to: capabilities.documents,
            snapshot: snapshot,
            documentDidCommit: { [weak self] document in
                guard let self else { return }
                _ = await self.replaceSavedDocument(document)
            }
        )
        researchController.bind(
            to: ResearchControllerCapabilities(
                records: capabilities.research.records,
                checkpoints: capabilities.research.checkpoints,
                skills: capabilities.research.skills,
                actions: capabilities.research.actions,
                skillsURL: capabilities.research.skillsURL,
                recoveryRecordsURL: capabilities.research.recoveryRecordsURL
            ),
            snapshot: snapshot
        )
        researchController.actions.bind(ResearchActionClient(
            availableActions: { target in
                try await capabilities.research.actions.availableActions(for: target)
            },
            materialCandidates: { target, definition in
                try await capabilities.research.actions.materialCandidates(
                    for: target,
                    actionID: definition.id
                )
            },
            sourceAccess: { target in
                try await capabilities.research.sourceAccess.sourceAccess(
                    for: target.functionTarget
                )
            },
            bindLocalSource: { target, url in
                try await capabilities.research.sourceAccess.bindSourceAccess(
                    ResearchSourceBindingRequest(
                        target: target.functionTarget,
                        selection: .localFile(url)
                    )
                )
            },
            prepare: { [weak self] request, resynthesisContext in
                guard self != nil else {
                    throw ScholiumApplicationError.researchStoreUnavailable(
                        "No workspace is active."
                    )
                }
                if let resynthesisContext {
                    return try await capabilities.research.actions.prepareResynthesis(
                        request,
                        context: resynthesisContext
                    )
                }
                return try await capabilities.research.actions.prepareAction(request)
            },
            cancel: { runID in
                try await capabilities.research.actions.cancelAction(runID: runID)
            },
            openActiveDiscussion: { [weak self] discussionID in
                guard let self else { return }
                self.presentationRouter.dismissSheet()
                Task { @MainActor [weak self] in
                    await Task.yield()
                    self?.requestDiscussionPresentation(discussionID)
                }
            }
        ))
        researchController.bibliography.bind(RecommendedBibliographyClient(
            overview: {
                try await capabilities.research.bibliography.recommendationOverview()
            },
            prepare: { [weak self] request in
                guard let self, let assignment = self.workspaceAssignment else {
                    throw ScholiumApplicationError.researchStoreUnavailable(
                        "No workspace is active."
                    )
                }
                try await self.editorFlushCoordinator.flushAllEditors(in: assignment.id)
                return try await capabilities.research.bibliography
                    .prepareRecommendation(request)
            },
            cancel: { id in
                try await capabilities.research.bibliography.cancelRecommendation(id: id)
            },
            dismiss: { requestID, candidateID in
                try await capabilities.research.bibliography.dismissRecommendation(
                    requestID: requestID,
                    candidateID: candidateID
                )
            }
        ))
        reconcileResearchActionPresentation()
    }

    private func adoptWorkspaceActivation(_ activation: WorkspaceActivation) {
        let previousIdentity = activeWorkspaceCapabilities?.runtimeIdentity
        let intendedID = workspaceAssignment?.id
            ?? activeTriptychServicesID
            ?? requestedTriptychID
        guard activation.workspaceID == intendedID
                || previousIdentity.map(activation.replaces) == true else {
            return
        }
        guard previousIdentity != activation.runtimeIdentity else { return }

        let previousAssignment = workspaceAssignment
        let previousVault = currentRegisteredVault
        workspaceAssignment = activation.capabilities.assignment
        registeredTriptychs.removeAll {
            $0.id == previousAssignment?.id || $0.id == activation.workspaceID
        }
        registeredTriptychs.append(activation.capabilities.assignment)
        registeredTriptychs.sort {
            let order = $0.triptych.name.localizedStandardCompare($1.triptych.name)
            return order == .orderedSame
                ? $0.id.uuidString < $1.id.uuidString
                : order == .orderedAscending
        }
        activeTriptychServicesID = activation.workspaceID
        bindApplicationCapabilities(
            to: activation.capabilities,
            snapshot: activation.snapshot
        )
        editorFlushCoordinator.activateTriptych(activation.workspaceID) { [weak self] in
            guard let self else { return }
            try await self.documentController.flushLeasedOrPinnedSessions()
        }
        Task { [weak self] in
            await self?.workspaceStore.refreshPendingAgentNoteChangeRequests(
                in: activation.workspaceID
            )
        }

        if let previousVault {
            let previousSlot = WorkspaceVaultSlot.allCases.first(where: { slot in
                guard let assigned = previousAssignment?.vault(for: slot) else { return false }
                return assigned.id == previousVault.id
                    || assigned.canonicalPath == previousVault.canonicalPath
            })
            let rebound = previousSlot.flatMap { slot in
                activation.capabilities.assignment.vault(for: slot)
            }
                ?? activation.capabilities.assignment.vaults.values.first(where: {
                    $0.id == previousVault.id
                        || $0.canonicalPath == previousVault.canonicalPath
                })
            if let rebound {
                currentRegisteredVault = rebound
                currentVaultRole = rebound.role
            }
        }

        let projectionCommit = workspaceProjectionController.activate(
            snapshot: activation.snapshot,
            runtimeIdentity: activation.runtimeIdentity,
            context: workspaceProjectionContext
        )
        applyWorkspaceProjectionCommit(projectionCommit)
        agentNoteChangeWindowController.refreshForWorkspaceSnapshot(
            triptychID: activation.snapshot.triptych.id
        )
    }

    func saveTriptychSettings(_ settings: TriptychSettings) async throws {
        try await researchController.saveSettings(settings)
        triptychSettings = settings
    }

    var currentWorkspaceSlot: WorkspaceVaultSlot? {
        let selected = discoveryController.library.workspaceSlot
        return workspaceAssignment?.vault(for: selected) == nil ? nil : selected
    }

    var currentDocumentPropertiesConfiguration: VaultPropertiesConfiguration? {
        guard let vault = currentDocumentVault,
              let slot = WorkspaceVaultSlot.allCases.first(where: {
                  workspaceAssignment?.vault(for: $0)?.id == vault.id
              }) else { return nil }
        return triptychSettings.properties[slot] ?? TriptychSettings.defaultProperties[slot]
    }

    func createCheckpoint(name: String, kind: TriptychCheckpointKind = .manual) async throws -> TriptychCheckpoint {
        guard let assignment = workspaceAssignment else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        try await editorFlushCoordinator.flushAllEditors(in: assignment.id)
        return try await researchController.createCheckpoint(name: name, kind: kind)
    }

    func checkpoints() async -> [TriptychCheckpoint] {
        let listing: TriptychCheckpointListing
        do {
            listing = try await researchController.checkpoints()
        } catch {
            checkpointListingError = error.localizedDescription
            return []
        }
        checkpointListingError = listing.unreadableEntries.isEmpty
            ? nil
            : "Some checkpoint folders could not be read and remain unchanged.\n\n"
                + listing.unreadableEntries.joined(separator: "\n")
        return listing.checkpoints
    }

    func noteCheckpoints(for path: String) async throws -> [TriptychCheckpoint] {
        guard let context = activeDocumentContext(for: path) else { return [] }
        return try await researchController.noteCheckpoints(for: VaultQualifiedNoteID(
            vaultID: context.vaultID,
            relativePath: path
        ))
    }

    func restoreNote(_ path: String, from checkpointID: UUID) async throws {
        guard let context = activeDocumentContext(for: path),
              let assignment = workspaceAssignment else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        try await editorFlushCoordinator.flushAllEditors(in: assignment.id)
        _ = try await researchController.restoreNote(
            VaultQualifiedNoteID(vaultID: context.vaultID, relativePath: path),
            from: checkpointID,
            expectedRevision: context.fingerprint
        )
        await refreshWindowProjection()
    }

    func critiqueAssociation(for path: String) async -> CritiqueAssociation? {
        guard let context = activeDocumentContext(for: path),
              context.vaultRole.allowsCritique else { return nil }
        return try? await researchController.critique(workNoteID: context.noteID)
    }

    func critiqueAssociation(forCritiquePath path: String) async -> CritiqueAssociation? {
        guard let context = activeDocumentContext(for: path),
              context.vaultRole.allowsCritique else { return nil }
        return try? await researchController.critique(critiqueRelativePath: path)
    }

    func critiqueAssociationRelated(to path: String) async -> CritiqueAssociation? {
        if CritiquePlacement.isManagedCritiquePath(path) {
            return await critiqueAssociation(forCritiquePath: path)
        }
        return await critiqueAssociation(for: path)
    }

    func openCritiqueFinding(
        _ finding: CritiqueFinding,
        fallbackTargetPath: String?
    ) {
        guard let path = finding.targetRelativePath ?? fallbackTargetPath,
              let target = currentDocumentNotes.first(where: { $0.relativePath == path }),
              let reference = target.workspaceSnapshot.map({ snapshot in
                  VaultNoteReference(
                      vaultID: snapshot.id.vaultID,
                      vaultName: currentDocumentVault?.name ?? "Current Vault",
                      vaultRole: snapshot.vaultRole,
                      relativePath: snapshot.id.relativePath,
                      stableNoteID: snapshot.stableIdentity.resolvedID?.uuidString.lowercased()
                  )
              }) else { return }
        let document = NoteDocument(relativePath: path, rawContent: target.rawContent)
        let line = finding.resolvedTargetLine(in: document)
        Task { await openWorkspaceReference(reference, line: line, mode: line == nil ? .read : .source) }
    }

    func checkpointComparison(_ checkpointID: UUID) async throws -> [TriptychCheckpointChange] {
        try await researchController.checkpointComparison(checkpointID)
    }

    func restoreCheckpoint(
        _ checkpointID: UUID,
        selection: TriptychCheckpointRestoreSelection
    ) async throws -> TriptychCheckpointRestoreResult {
        guard let assignment = workspaceAssignment else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        try await editorFlushCoordinator.flushAllEditors(in: assignment.id)
        let result = try await researchController.restoreCheckpoint(
            checkpointID,
            selection: selection
        )
        do {
            triptychSettings = try await researchController.settings()
            try await rescanVault()
        } catch {
            refreshStatusText = "Triptych refresh failed after restore"
            workspaceProjectionController.reportCatalogError(
                "The checkpoint restore committed successfully, but Scholium could not reload every restored setting or derived view. \(error.localizedDescription)"
            )
        }
        return result
    }

    func revealCheckpointsInFinder() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await researchController.prepareCheckpointsLocation()
                workspaceStore.revealInFinder(url)
            } catch {
                showToast(
                    "Could not reveal checkpoints: \(error.localizedDescription)",
                    kind: .error
                )
            }
        }
    }

    func importMarkdownFiles(_ urls: [URL]) async throws -> [NoteDocument] {
        guard let vaultID = currentRegisteredVault?.id else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        var imported: [NoteDocument] = []
        for url in urls {
            imported.append(try await documentController.importMarkdown(
                at: url,
                intoVault: vaultID
            ))
        }
        return imported
    }

    func copyTextToClipboard(_ text: String, recovery: String? = nil) throws {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else {
            throw ClipboardWorkflowError.copyFailed(recovery: recovery)
        }
    }

    func refreshRegisteredVaults() async {
        registeredVaults = await workspaceStore.registeredVaults()
        registeredTriptychs = (try? await workspaceStore.registeredTriptychs()) ?? []
    }

    func openWorkspaceVault(_ slot: WorkspaceVaultSlot) async throws {
        guard let vault = workspaceAssignment?.vault(for: slot) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        try await openRegisteredVault(vault)
    }

    private func browseWorkspaceVault(
        _ slot: WorkspaceVaultSlot,
        request: DiscoveryLocationRequest
    ) async throws {
        guard let vault = workspaceAssignment?.vault(for: slot) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        try await browseRegisteredVault(
            vault,
            slot: slot,
            locationRequest: request
        )
    }

    /// Reprojects Library onto another Triptych vault without touching the
    /// selected document. The target snapshot is staged completely before the
    /// browsed-vault identity changes, so a failed browse leaves both Library
    /// and the open editor intact.
    private func browseRegisteredVault(
        _ registered: RegisteredVault,
        slot: WorkspaceVaultSlot? = nil,
        locationRequest: DiscoveryLocationRequest? = nil
    ) async throws {
        let vaultSnapshot = try await currentWorkspaceVaultSnapshot(
            vaultID: registered.id
        )
        let targetConfig = await workspaceStore.vaultConfig(
            rootURL: URL(
                fileURLWithPath: registered.canonicalPath,
                isDirectory: true
            )
        )
        if let locationRequest,
           !discoveryController.isCurrentLocationRequest(locationRequest) {
            throw CancellationError()
        }

        let resolvedSlot = slot ?? workspaceSlot(for: registered)
        let targetLocation = locationRequest?.location
            ?? discoveryController.library.locationScope
        let lifecycle: WorkspaceDocumentLifecycle = switch targetLocation {
        case .workspace: .active
        case .setAside: .setAside
        case .trash: .trash
        }
        let targetNotes = vaultSnapshot.documents
            .filter { $0.lifecycle == lifecycle }
            .map(WindowDocumentLocation.workspace)
            .sorted(by: notesAreOrdered)

        if let locationRequest,
           !discoveryController.isCurrentLocationRequest(locationRequest) {
            throw CancellationError()
        }
        currentRegisteredVault = registered
        currentVaultRole = registered.role
        vaultConfig = targetConfig
        if let locationRequest {
            guard discoveryController.receiveLocationResult(for: locationRequest) else {
                throw CancellationError()
            }
        } else if let resolvedSlot {
            discoveryController.synchronizeLibrarySelection(
                workspaceSlot: resolvedSlot,
                location: targetLocation
            )
        }
        if let resolvedSlot {
            attentionPresentationState.selectWorkspaceSlot(resolvedSlot)
        }
        workspaceProjectionController.commitVaultSelection(
            snapshot: vaultSnapshot,
            notes: targetNotes
        )
        await refreshIdentityState()
        scheduleWorkspaceCatalogRefresh()
        persistWindowSessionNow()
    }

    private func workspaceSlot(for vault: RegisteredVault) -> WorkspaceVaultSlot? {
        WorkspaceVaultSlot.allCases.first { slot in
            guard let assigned = workspaceAssignment?.vault(for: slot) else { return false }
            return assigned.id == vault.id || assigned.canonicalPath == vault.canonicalPath
        }
    }

    func openRegisteredVault(_ vault: RegisteredVault) async throws {
        // WorkspaceStore resolves and retains any bookmark security scope while
        // activating the shared Triptych runtime. WindowModel only subscribes to
        // that runtime and never starts a second scope for the same vault.
        try await loadVault(vault)
    }

    func refreshWorkspaceCatalog() async {
        await workspaceProjectionController.refreshCatalog()
    }

    private func loadVault(_ registered: RegisteredVault) async throws {
        isLoading = true
        vaultError = nil
        do {
            guard let assignment = workspaceAssignment else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            let capabilities: WindowWorkspaceCapabilities
            if let activeWorkspaceCapabilities {
                capabilities = activeWorkspaceCapabilities
            } else {
                capabilities = try await workspaceStore.workspaceCapabilities(id: assignment.id)
                bindApplicationCapabilities(to: capabilities)
            }
            let workspaceVaultSnapshots = try await documentController.workspaceSnapshots()
            guard let vaultSnapshot = workspaceVaultSnapshots.first(where: {
                $0.vault.id == registered.id
            }) else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            let researchSnapshot = try await researchController.researchSnapshot()
            // Stage the complete target runtime and inventory before replacing
            // any visible window state. A failed vault open must leave the
            // current Triptych document and editor intact.
            let targetNotes = vaultSnapshot.documents
                .filter { $0.lifecycle == .active }
                .map(WindowDocumentLocation.workspace)
                .sorted {
                    $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
                }
            let targetConfig = await workspaceStore.vaultConfig(
                rootURL: URL(
                    fileURLWithPath: registered.canonicalPath,
                    isDirectory: true
                )
            )

            resetWindowSession()

            workspaceProjectionController.replaceVaultSnapshots(workspaceVaultSnapshots)
            if let slot = workspaceSlot(for: registered) {
                discoveryController.synchronizeLibrarySelection(
                    workspaceSlot: slot,
                    location: .workspace
                )
                attentionPresentationState.selectWorkspaceSlot(slot)
            }
            currentRegisteredVault = registered
            currentVaultRole = registered.role
            activeTriptychServicesID = assignment.id
            activeWorkspaceCapabilities = capabilities
            vaultConfig = targetConfig
            workspaceProjectionController.replaceVisibleNotes(targetNotes)
            await refreshIdentityState()
            if let snapshot = workspaceStore.snapshot(for: capabilities.id) {
                let commit = workspaceProjectionController.activate(
                    snapshot: snapshot,
                    runtimeIdentity: capabilities.runtimeIdentity,
                    context: workspaceProjectionContext
                )
                applyWorkspaceProjectionCommit(commit)
            }
            isLoading = false
            refreshStatusText = nil
            await refreshWindowProjection()
            if !researchSnapshot.healthIssues.isEmpty {
                vaultError = researchSnapshot.healthIssues.joined(separator: "\n\n")
            }
        } catch {
            isLoading = false
            refreshStatusText = nil
            vaultError = error.localizedDescription
            throw error
        }
    }

    func restoreWorkspaceIfNeeded() async {
        guard !attemptedVaultRestore, vaultConfig == nil else { return }
        attemptedVaultRestore = true
        if let root = ScholiumRuntimeIsolation.fixtureRootURL() {
            do {
                try await configureTriptych(
                    paperAnalysisURL: root.appendingPathComponent("01-analyses", isDirectory: true),
                    topicKnowledgeURL: root.appendingPathComponent("02-topics", isDirectory: true),
                    outputURL: root.appendingPathComponent("03-works", isDirectory: true),
                    portableContainerURL: root
                )
                let allowsRequestedSlot: Bool = {
#if DEBUG
                    true
#else
                    PerformanceProbe.shared.isEnabled
#endif
                }()
                if allowsRequestedSlot,
                   let requestedSlot = ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_OPEN_SLOT"],
                   let slot = WorkspaceVaultSlot.allCases.first(where: {
                       switch $0 {
                       case .paperAnalysis: requestedSlot == "paper_analysis"
                       case .topicKnowledge: requestedSlot == "topic_knowledge"
                       case .output: requestedSlot == "output"
                       }
                }) {
                    try await openWorkspaceVault(slot)
                }
                openRequestedTestNoteIfNeeded()
            } catch {
                vaultError = error.localizedDescription
            }
            return
        }
        await refreshRegisteredVaults()
        await refreshWorkspaceAssignment()
        guard workspaceAssignment != nil else {
            return
        }

        do {
            try await openWorkspaceVault(.paperAnalysis)
            openRequestedTestNoteIfNeeded()
        } catch {
            if let recovery = workspaceAccessRecoveryRoute(for: error) {
                workspaceAccessRecovery = recovery
                workspaceRecoveryMessage = workspaceAccessRecoveryMessage(for: recovery)
                vaultError = nil
            } else {
                vaultError = error.localizedDescription
            }
        }
    }

    private func workspaceAccessRecoveryRoute(for error: Error) -> WorkspaceAccessRecovery? {
        guard let workspaceError = error as? WorkspaceRegistryError else { return nil }
        switch workspaceError {
        case .vaultAccessUnavailable(let path):
            return WorkspaceAccessRecovery(kind: .vault, expectedPath: path)
        case .portableControlAccessUnavailable(let path):
            return WorkspaceAccessRecovery(kind: .portableControl, expectedPath: path)
        default:
            return nil
        }
    }

    private func workspaceAccessRecoveryMessage(
        for recovery: WorkspaceAccessRecovery
    ) -> String {
        switch recovery.kind {
        case .vault:
            "Scholium needs renewed access to '\(recovery.expectedPath)'. Choose that folder again."
        case .portableControl:
            "Scholium needs renewed access to '\(recovery.expectedPath)' so it can use the portable .scholium folder beside Works."
        }
    }

    func restoreWorkspaceAccess(using selectedURL: URL) async throws {
        guard let recovery = workspaceAccessRecovery,
              let assignment = workspaceAssignment,
              let analyses = assignment.vault(for: .paperAnalysis),
              let topics = assignment.vault(for: .topicKnowledge),
              let works = assignment.vault(for: .output)
        else { throw WorkspaceRegistryError.incompleteWorkspace }

        let selected = selectedURL.resolvingSymlinksInPath().standardizedFileURL
        let analysesURL = URL(fileURLWithPath: analyses.canonicalPath, isDirectory: true)
        let topicsURL = URL(fileURLWithPath: topics.canonicalPath, isDirectory: true)
        let worksURL = URL(fileURLWithPath: works.canonicalPath, isDirectory: true)
        let expected = URL(
            fileURLWithPath: recovery.expectedPath,
            isDirectory: true
        ).resolvingSymlinksInPath().standardizedFileURL.path

        let replacementAnalyses = analysesURL.resolvingSymlinksInPath().standardizedFileURL.path
            == expected ? selected : analysesURL
        let replacementTopics = topicsURL.resolvingSymlinksInPath().standardizedFileURL.path
            == expected ? selected : topicsURL
        let replacementWorks = worksURL.resolvingSymlinksInPath().standardizedFileURL.path
            == expected ? selected : worksURL
        let portableURL: URL
        if recovery.kind == .portableControl {
            portableURL = selected
        } else {
            portableURL = await workspaceStore.portableContainerURL(forWorksURL: replacementWorks)
                ?? replacementWorks.deletingLastPathComponent()
        }

        try await configureTriptych(
            paperAnalysisURL: replacementAnalyses,
            topicKnowledgeURL: replacementTopics,
            outputURL: replacementWorks,
            portableContainerURL: portableURL,
            triptychID: assignment.id,
            triptychName: assignment.triptych.name
        )
        workspaceAccessRecovery = nil
        workspaceRecoveryMessage = nil
    }

    private func openRequestedTestNoteIfNeeded() {
        // A native-tab route owns its explicit initial document. The general
        // QA launch note applies only to un-routed windows; opening it first
        // would create a transient, incorrect tab identity before the routed
        // document replaces it.
        guard requestedInitialDocument == nil,
              let requested = ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_OPEN_NOTE"] else { return }
        let path = requested == "first"
            ? notes.sorted(by: notesAreOrdered).first?.relativePath
            : requested
        if let path { openNote(path) }
    }

    func refreshWindowProjection() async {
        // `WorkspaceStore` publishes the authoritative Triptych index and
        // Triptych graph. Keep this method as a window projection refresh for
        // existing callers; it must not create a second graph or index.
        projectionRefreshToken &+= 1
        let refreshToken = projectionRefreshToken
        let startingVaultID = currentRegisteredVault?.id
        await refreshIdentityState()
        guard refreshToken == projectionRefreshToken, currentRegisteredVault?.id == startingVaultID else { return }

        if let catalog = try? await discoveryController.discoverySnapshot().catalog {
            workspaceProjectionController.replaceCatalog(catalog)
        }
        guard refreshToken == projectionRefreshToken, currentRegisteredVault?.id == startingVaultID else { return }
        if let vaultID = startingVaultID,
           let vault = try? await documentController.workspaceSnapshot(vaultID: vaultID) {
            let snapshots = Dictionary(uniqueKeysWithValues: vault.documents.map { ($0.id.relativePath, $0) })
            workspaceProjectionController.refreshVisibleNoteSnapshots(snapshots)
        }
        guard refreshToken == projectionRefreshToken, currentRegisteredVault?.id == startingVaultID else { return }

        if noteLocationScope == .workspace, workspaceAssignment != nil {
            scheduleWorkspaceCatalogRefresh()
        }

        // Render on demand. Prewarming every note here runs on the main actor
        // and makes a successful save appear stuck while unrelated documents
        // are rendered.
    }

    private func scheduleWorkspaceCatalogRefresh() {
        workspaceProjectionController.scheduleCatalogRefresh()
    }

    func rescanVault() async throws {
        try await refreshNoteLocationScope()
    }

    func selectNoteLocationScope(_ scope: NoteLocationScope) async {
        guard let workspaceSlot = currentWorkspaceSlot else { return }
        guard scope != noteLocationScope
                || discoveryController.library.locationError != nil else { return }
        let request = discoveryController.beginLocationRequest(
            workspaceSlot: workspaceSlot,
            location: scope,
            presentation: .stagedReplacement
        )
        do {
            let loaded = try await loadNotes(
                for: scope,
                vaultID: currentRegisteredVault?.id
            )
            guard discoveryController.receiveLocationResult(for: request) else { return }
            workspaceProjectionController.replaceVisibleNotes(
                loaded.sorted(by: notesAreOrdered)
            )
            await refreshIdentityState()
            await refreshWindowProjection()
        } catch {
            discoveryController.failLocationRequest(
                error.localizedDescription,
                for: request
            )
            showToast(String(localized: "Could not open \(scope.rawValue): \(error.localizedDescription)", table: "Localizable", bundle: .module), kind: .error)
        }
    }

    func refreshNoteLocationScope() async throws {
        guard let workspaceSlot = currentWorkspaceSlot else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let request = discoveryController.beginLocationRequest(
            workspaceSlot: workspaceSlot,
            location: noteLocationScope
        )
        let loaded: [WindowDocumentLocation]
        do {
            loaded = try await loadNotes(
                for: request.location,
                vaultID: currentRegisteredVault?.id
            )
        } catch {
            discoveryController.failLocationRequest(error.localizedDescription, for: request)
            throw error
        }
        guard discoveryController.receiveLocationResult(for: request) else { return }
        workspaceProjectionController.replaceVisibleNotes(
            loaded.sorted(by: notesAreOrdered)
        )
        await refreshIdentityState()
        await refreshWindowProjection()
    }

    private func loadNotes(
        for scope: NoteLocationScope,
        vaultID: UUID?
    ) async throws -> [WindowDocumentLocation] {
        guard let vaultID else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let vault = try await currentWorkspaceVaultSnapshot(vaultID: vaultID)
        let lifecycle: WorkspaceDocumentLifecycle = switch scope {
        case .workspace: .active
        case .setAside: .setAside
        case .trash: .trash
        }
        return vault.documents
            .filter { $0.lifecycle == lifecycle }
            .map(WindowDocumentLocation.workspace)
    }

    /// Window publication is the first source for ordinary navigation. The
    /// Application operation remains the fallback when initial construction
    /// has not yet installed that immutable snapshot.
    private func currentWorkspaceVaultSnapshot(
        vaultID: UUID
    ) async throws -> WorkspaceVaultSnapshot {
        if let snapshot = workspaceProjectionController.vaultSnapshot(id: vaultID) {
            return snapshot
        }
        guard let snapshot = try await documentController.workspaceSnapshot(
            vaultID: vaultID
        ) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return snapshot
    }

    func lifecycleLocationItems(for scope: NoteLocationScope) async throws -> [LifecycleLocationItem] {
        guard scope == .setAside || scope == .trash,
              let vaultID = currentRegisteredVault?.id,
              let vault = try await documentController.workspaceSnapshot(vaultID: vaultID) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let lifecycle: WorkspaceDocumentLifecycle = scope == .setAside ? .setAside : .trash
        var items: [LifecycleLocationItem] = []
        for snapshot in vault.documents where snapshot.lifecycle == lifecycle {
            guard let noteID = snapshot.stableIdentity.resolvedID else {
                throw NoteIdentityRecoveryError.identityUnresolved(snapshot.id.relativePath)
            }
            let note = WindowDocumentLocation.workspace(snapshot)
            items.append(LifecycleLocationItem(
                note: note,
                revision: snapshot.fingerprint,
                noteID: noteID
            ))
        }
        return items.sorted { notesAreOrdered($0.note, $1.note) }
    }

    func prepareLifecycleOperation(_ item: LifecycleLocationItem) {
        noteIdentityByPath[item.note.relativePath] = item.noteID
        workspaceProjectionController.recordPreparedRevision(
            item.revision,
            at: item.note.relativePath
        )
    }

    func clearPreparedLifecycleOperation(at path: String) {
        guard WorkspaceDocumentLifecycle(relativePath: path) != .active else { return }
        noteIdentityByPath[path] = nil
        workspaceProjectionController.clearPreparedRevision(at: path)
    }

    func requestUntitledNoteCreation(in folderRelativePath: String?) {
        guard !isCreatingNote else { return }
        isCreatingNote = true
        enqueueDocumentTransition(preservingCurrentEditorState: false, { [weak self] in
            guard let self else { return }
            guard noteLocationScope == .workspace,
                  let vault = currentRegisteredVault else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            let document = try await documentController.createUntitledNote(
                inVault: vault.id,
                folderRelativePath: folderRelativePath
            )
            try await browseRegisteredVault(vault)
            guard let snapshot = workspaceProjectionController.cachedNote(
                vaultID: vault.id,
                relativePath: document.relativePath
            ) else {
                throw WindowNavigationError.noteUnavailable(document.relativePath)
            }
            guard let noteID = snapshot.stableIdentity.resolvedID else {
                throw NoteIdentityRecoveryError.identityUnresolved(document.relativePath)
            }
            try activateWorkspaceReference(
                VaultNoteReference(
                    vaultID: vault.id,
                    vaultName: vault.name,
                    vaultRole: vault.role,
                    relativePath: document.relativePath,
                    stableNoteID: noteID.uuidString.lowercased()
                ),
                tabActivation: .place(.replaceSelected)
            )
        }, didFail: { [weak self] error in
            guard let self else { return }
            showToast(
                String(
                    localized: "Could not create note: \(error.localizedDescription)",
                    table: "Localizable",
                    bundle: .module
                ),
                kind: .error
            )
        }, didFinish: { [weak self] in
            self?.isCreatingNote = false
        })
    }

    func requestUntitledFolderCreation(in parentRelativePath: String?) {
        guard !isMutatingFolder else { return }
        guard noteLocationScope == .workspace,
              let vault = currentRegisteredVault else {
            showToast(
                WorkspaceRegistryError.incompleteWorkspace.localizedDescription,
                kind: .error
            )
            return
        }
        isMutatingFolder = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isMutatingFolder = false }
            do {
                let folder = try await documentController.createUntitledFolder(
                    inVault: vault.id,
                    parentRelativePath: parentRelativePath
                )
                try await refreshCachedWorkspaceVaultSnapshot(vaultID: vault.id)
                try await browseRegisteredVault(vault)
                expandFolderAncestors(folder.rawValue, vaultID: vault.id)
                showToast(
                    String(
                        localized: "Folder created: \(folder.rawValue)",
                        table: "Localizable",
                        bundle: .module
                    )
                )
            } catch {
                showToast(
                    String(
                        localized: "Could not create folder: \(error.localizedDescription)",
                        table: "Localizable",
                        bundle: .module
                    ),
                    kind: .error
                )
            }
        }
    }

    func moveFolder(
        _ target: FolderLifecycleTarget,
        to destinationRelativePath: String
    ) async throws {
        guard !isMutatingFolder else { return }
        guard target.vaultID == currentRegisteredVault?.id,
              let assignment = workspaceAssignment,
              let vault = currentRegisteredVault else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        isMutatingFolder = true
        defer { isMutatingFolder = false }
        try await editorFlushCoordinator.flushAllEditors(in: assignment.id)
        let commit: FolderMoveCommit
        do {
            commit = try await documentController.moveFolder(
                inVault: target.vaultID,
                from: target.relativePath,
                to: destinationRelativePath
            )
        } catch {
            await refreshTransactionRecoveryRecords()
            throw error
        }
        projectFolderMove(commit)
        migrateFolderDisclosure(
            from: commit.sourceFolder.rawValue,
            to: commit.destinationFolder.rawValue,
            vaultID: target.vaultID
        )
        try await refreshCachedWorkspaceVaultSnapshot(vaultID: target.vaultID)
        try await browseRegisteredVault(vault)
        scheduleWorkspaceCatalogRefresh()
    }

    func moveFolderToTrash(_ relativePath: String) async throws {
        guard !isMutatingFolder else { return }
        guard let vaultID = currentRegisteredVault?.id,
              let assignment = workspaceAssignment else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        isMutatingFolder = true
        defer { isMutatingFolder = false }
        try await editorFlushCoordinator.flushAllEditors(in: assignment.id)
        let commit: FolderMoveCommit
        do {
            commit = try await documentController.moveFolderToTrash(
                inVault: vaultID,
                relativePath: relativePath
            )
        } catch {
            await refreshTransactionRecoveryRecords()
            throw error
        }
        projectFolderMove(commit)
        migrateFolderDisclosure(
            from: commit.sourceFolder.rawValue,
            to: nil,
            vaultID: vaultID
        )
        lifecycleMutationGeneration &+= 1
        try await refreshCachedWorkspaceVaultSnapshot(vaultID: vaultID)
        try await refreshNoteLocationScope()
        scheduleWorkspaceCatalogRefresh()
    }

    /// Folder mutations publish a new authoritative snapshot before returning,
    /// but the per-window Combine projection may still be queued on the main
    /// actor. Refresh the exact vault cache before rebuilding the visible tree
    /// so newly created empty folders and folder moves cannot be hidden by the
    /// preceding window generation.
    private func refreshCachedWorkspaceVaultSnapshot(vaultID: UUID) async throws {
        guard let snapshot = try await documentController.workspaceSnapshot(
            vaultID: vaultID
        ) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        workspaceProjectionController.replaceVaultSnapshot(snapshot)
    }

    private func projectFolderMove(_ commit: FolderMoveCommit) {
        for move in commit.noteMoves {
            migrateAppOwnedState(
                sourcePath: move.source.relativePath,
                destinationPath: move.destination.relativePath,
                noteID: move.stableNoteID,
                vaultID: commit.vaultID
            )
        }
    }

    private func expandFolderAncestors(_ relativePath: String, vaultID: UUID) {
        let visiblePath = stripKBRootFolder(relativePath)
        guard !visiblePath.isEmpty else { return }
        let scope = LibraryDisclosureScope(vaultID: vaultID, locationScope: .workspace)
        var expanded = discoveryController.expandedFolders(in: scope)
        let parts = visiblePath.split(separator: "/").map(String.init)
        for count in 1...parts.count {
            expanded.insert(parts.prefix(count).joined(separator: "/"))
        }
        discoveryController.setExpandedFolders(expanded, in: scope)
    }

    private func migrateFolderDisclosure(
        from sourceRelativePath: String,
        to destinationRelativePath: String?,
        vaultID: UUID
    ) {
        let scope = LibraryDisclosureScope(vaultID: vaultID, locationScope: .workspace)
        let source = stripKBRootFolder(sourceRelativePath)
        let destination = destinationRelativePath.map(stripKBRootFolder)
        guard !source.isEmpty else { return }
        let sourcePrefix = source + "/"
        var migrated: Set<String> = []
        for folder in discoveryController.expandedFolders(in: scope) {
            if folder == source || folder.hasPrefix(sourcePrefix) {
                guard let destination, !destination.isEmpty else { continue }
                migrated.insert(destination + folder.dropFirst(source.count))
            } else {
                migrated.insert(folder)
            }
        }
        if let destination, !destination.isEmpty {
            migrated.insert(destination)
        }
        discoveryController.setExpandedFolders(migrated, in: scope)
    }

    @discardableResult
    func duplicateNote(
        _ target: NoteLifecycleTarget,
        to requestedPath: String
    ) async throws -> NoteDocument {
        try await flushRegisteredEditorIfNeeded()
        guard let vault = workspaceAssignment?.vaults.values.first(where: {
            $0.id == target.documentID.vaultID
        }) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let expected = try lifecycleExpectedRevision(for: target)
        let destination = Self.markdownPath(requestedPath)
        let document = try await documentController.duplicate(
            target.documentID,
            to: destination,
            expectedRevision: expected
        )
        try await refreshCachedWorkspaceVaultSnapshot(vaultID: target.documentID.vaultID)
        try await browseRegisteredVault(vault)
        openNote(destination)
        return document
    }

    func moveNote(
        _ target: NoteLifecycleTarget,
        to requestedPath: String
    ) async throws {
        try await flushRegisteredEditorIfNeeded()
        guard let vault = workspaceAssignment?.vaults.values.first(where: {
            $0.id == target.documentID.vaultID
        }) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let expected = try lifecycleExpectedRevision(for: target)
        let requestedDestination = Self.markdownPath(requestedPath)
        let commit: TriptychMoveCommit
        do {
            commit = try await documentController.move(
                target.documentID,
                to: requestedDestination,
                expectedRevision: expected
            )
        } catch {
            await refreshTransactionRecoveryRecords()
            throw error
        }
        let destination = commit.destination.relativePath
        migrateAppOwnedState(
            sourcePath: target.relativePath,
            destinationPath: destination,
            noteID: target.stableNoteID,
            vaultID: target.documentID.vaultID
        )
        try await refreshCachedWorkspaceVaultSnapshot(vaultID: target.documentID.vaultID)
        try await browseRegisteredVault(vault)
        openNote(destination)
        scheduleWorkspaceCatalogRefresh()
    }

    func setAsideNote(_ path: String) async throws {
        try await flushRegisteredEditorIfNeeded()
        guard let noteID = try requireResolvedIdentity(for: path) else {
            throw NoteIdentityRecoveryError.identityUnresolved(path)
        }
        guard let vaultID = currentRegisteredVault?.id,
              let expected = documentRevisions[path] else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let commit = try await documentController.setAside(
            VaultQualifiedNoteID(vaultID: vaultID, relativePath: path),
            expectedRevision: expected
        )
        migrateAppOwnedState(
            sourcePath: path,
            destinationPath: commit.destination.relativePath,
            noteID: noteID,
            vaultID: vaultID
        )
        try await refreshNoteLocationScope()
    }

    func moveNoteToTrash(_ path: String) async throws {
        try await flushRegisteredEditorIfNeeded()
        guard let noteID = try requireResolvedIdentity(for: path) else {
            throw NoteIdentityRecoveryError.identityUnresolved(path)
        }
        guard let vaultID = currentRegisteredVault?.id,
              let expected = documentRevisions[path] else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let commit = try await documentController.moveToTrash(
            VaultQualifiedNoteID(vaultID: vaultID, relativePath: path),
            expectedRevision: expected
        )
        migrateAppOwnedState(
            sourcePath: path,
            destinationPath: commit.destination.relativePath,
            noteID: noteID,
            vaultID: vaultID
        )
        try await refreshNoteLocationScope()
    }

    func deleteNotePermanently(_ path: String) async throws {
        try await flushRegisteredEditorIfNeeded()
        try requireResolvedIdentity(for: path)
        guard WorkspaceDocumentLifecycle(relativePath: path) == .trash,
              let expected = documentRevisions[path],
              let vaultID = currentRegisteredVault?.id else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }

        let commit: PermanentDeletionCommit
        do {
            commit = try await documentController.deletePermanently(
                VaultQualifiedNoteID(vaultID: vaultID, relativePath: path),
                expectedRevision: expected
            )
        } catch {
            await refreshTransactionRecoveryRecords()
            throw error
        }

        noteIdentityByPath[path] = nil
        if let critiquePath = commit.removedCritiqueDocumentPath {
            noteIdentityByPath[critiquePath] = nil
        }
        let deletedPaths = Set([path, commit.removedCritiqueDocumentPath].compactMap { $0 })
        try removeDocumentTabs(vaultID: vaultID, removedPaths: deletedPaths)
        try await refreshNoteLocationScope()
        lifecycleMutationGeneration &+= 1
    }

    func refreshTransactionRecoveryRecords() async {
        do {
            transactionRecoveryRecords = try await researchController.recoveryRecords()
            transactionRecoveryError = nil
        } catch {
            transactionRecoveryRecords = []
            transactionRecoveryError = "Scholium could not read the durable recovery records. Their file remains unchanged. \(error.localizedDescription)"
        }
    }

    func markTransactionRecoveryResolved(_ id: UUID) async throws {
        try await researchController.resolveRecoveryRecord(id)
        await refreshTransactionRecoveryRecords()
    }

    func revealTransactionRecoveryRecordsInFinder() {
        guard let url = researchController.recoveryRecordsURL else { return }
        workspaceStore.revealInFinder(url)
    }

    private func migrateAppOwnedState(
        sourcePath: String,
        destinationPath: String,
        noteID: UUID,
        vaultID: UUID
    ) {
        // The application handle has already committed the portable identity
        // move and resumed any dependent record migrations. This method only
        // projects that successful commit into window-local presentation.
        migrateInMemoryPath(
            from: sourcePath,
            to: destinationPath,
            noteID: noteID,
            identityResolved: true,
            vaultID: vaultID
        )
        if WorkspaceDocumentLifecycle(relativePath: sourcePath) != .active
            || WorkspaceDocumentLifecycle(relativePath: destinationPath) != .active {
            lifecycleMutationGeneration &+= 1
        }
    }

    private func migrateInMemoryPath(
        from sourcePath: String,
        to destinationPath: String,
        noteID: UUID,
        identityResolved: Bool,
        vaultID: UUID
    ) {
        if currentRegisteredVault?.id == vaultID {
            noteIdentityByPath[sourcePath] = nil
            if identityResolved {
                noteIdentityByPath[destinationPath] = noteID
            }
        }
        if let descriptor = currentDocumentDescriptor,
           descriptor.reference.vaultID == vaultID,
           descriptor.reference.relativePath == sourcePath,
           descriptor.sessionKey.noteID == noteID {
            documentController.updateDocumentProjection(WindowDocumentDescriptor(
                sessionKey: descriptor.sessionKey,
                reference: VaultNoteReference(
                    vaultID: descriptor.reference.vaultID,
                    vaultName: descriptor.reference.vaultName,
                    vaultRole: descriptor.reference.vaultRole,
                    relativePath: destinationPath,
                    stableNoteID: descriptor.reference.stableNoteID
                )
            ))
        }
        if let tab = documentTabController.tabs.first(where: {
            $0.document.sessionKey == DocumentSessionKey(vaultID: vaultID, noteID: noteID)
        }), let descriptor = tab.document.workspaceDescriptor {
            let updatedReference = VaultNoteReference(
                vaultID: descriptor.reference.vaultID,
                vaultName: descriptor.reference.vaultName,
                vaultRole: descriptor.reference.vaultRole,
                relativePath: destinationPath,
                stableNoteID: descriptor.reference.stableNoteID
            )
            let updatedDocument = WindowSelectedDocument.workspace(
                WindowDocumentDescriptor(
                    sessionKey: descriptor.sessionKey,
                    reference: updatedReference
                )
            )
            let fallbackTitle = URL(fileURLWithPath: destinationPath)
                .deletingPathExtension()
                .lastPathComponent
            documentTabController.updateDocumentProjection(
                updatedDocument,
                title: fallbackTitle,
                toolTip: [fallbackTitle, descriptor.reference.vaultName, destinationPath]
                    .filter { !$0.isEmpty }
                    .joined(separator: " — ")
            )
        }
        documentController.migratePresentationPath(
            from: sourcePath,
            to: destinationPath,
            vaultID: vaultID
        )
    }

    private static func markdownPath(_ requestedPath: String) -> String {
        let trimmed = requestedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: trimmed).pathExtension.caseInsensitiveCompare("md") == .orderedSame
            ? trimmed
            : trimmed + ".md"
    }

    private func currentLexicalSearchEvidence(
        for hit: SearchHit,
        scope: SearchPresentationScope
    ) async -> WindowLexicalSearchEvidence {
        if scope == .thisNote {
            let snapshot = try? await currentSearchSourceSnapshot()
            return WindowLexicalSearchEvidence(
                freshness: snapshot.map(SearchFreshnessToken.currentNote),
                fingerprint: snapshot?.fingerprint
            )
        }
        let discovery = try? await discoveryController.discoverySnapshot()
        return WindowLexicalSearchEvidence(
            freshness: discovery?.searchGeneration.map(SearchFreshnessToken.triptych),
            fingerprint: workspaceProjectionController.cachedNote(
                vaultID: hit.vaultID,
                relativePath: hit.relativePath
            )?.fingerprint
        )
    }

    /// Captures CodeMirror's checked in-memory source without flushing or
    /// saving it. Identity is rechecked after the asynchronous bridge query so
    /// a superseded tab cannot become This Note Search authority.
    private func currentSearchSourceSnapshot() async throws -> SearchSourceSnapshot? {
        guard let descriptor = currentDocumentDescriptor,
              let note = currentNote else { return nil }
        let session = documentController.session(for: descriptor)
        let sessionID = session.editorSession.sessionID
        let source: String
        if session.isEditing || session.editorSession.hasRecoverableBuffer {
            source = try await session.editorSession.currentText(
                for: session.editorSession.bridgeDocumentID
            )
        } else {
            source = note.rawContent
        }
        guard currentDocumentDescriptor?.sessionKey == descriptor.sessionKey,
              documentController.session(for: descriptor) === session,
              session.editorSession.sessionID == sessionID else {
            throw CancellationError()
        }
        return SearchSourceSnapshot(
            noteID: VaultQualifiedNoteID(
                vaultID: descriptor.reference.vaultID,
                relativePath: note.relativePath
            ),
            editorSessionID: sessionID,
            source: source,
            editorRevision: UInt64(max(0, session.editorSession.generation))
        )
    }

    func openNote(
        _ path: String,
        tabActivation: DocumentTabActivation = .place(.replaceSelected)
    ) {
        guard let location = notes.first(where: { $0.relativePath == path }) else {
            showToast(String(localized: "Note not found: \(path)", table: "Localizable", bundle: .module), kind: .warning)
            return
        }
        PerformanceProbe.shared.beginReadActivation(documentID: path)
        if let snapshot = location.workspaceSnapshot,
           snapshot.stableIdentity.resolvedID != nil,
           let vault = currentRegisteredVault {
            documentController.installOpenedDocument(
                snapshot,
                vaultName: vault.name,
                vaultRole: vault.role
            )
        } else if let descriptor = selectionDescriptor(for: path) {
            documentController.selectDocument(descriptor)
        } else {
            showToast(
                String(localized: "Note not found: \(path)", table: "Localizable", bundle: .module),
                kind: .warning
            )
            return
        }
        synchronizeDocumentTabs(after: tabActivation)
    }

    private func openRestoredDocument(_ id: VaultQualifiedNoteID) {
        guard let vault = workspaceAssignment?.vaults.values.first(where: { $0.id == id.vaultID }),
              let snapshot = workspaceProjectionController.cachedNote(
                  vaultID: id.vaultID,
                  relativePath: id.relativePath
              ) else { return }
        PerformanceProbe.shared.beginReadActivation(documentID: id.relativePath)
        documentController.installOpenedDocument(
            snapshot,
            vaultName: vault.name,
            vaultRole: vault.role
        )
        synchronizeDocumentTabs(after: .place(.replaceSelected))
    }

    private func activateDocument(
        _ document: WindowSelectedDocument,
        tabActivation: DocumentTabActivation
    ) throws {
        switch document {
        case .workspace(let descriptor):
            try activateWorkspaceReference(
                descriptor.reference,
                tabActivation: tabActivation
            )
        case .unavailable(let vaultID, let relativePath):
            guard notes.contains(where: { $0.relativePath == relativePath }) else {
                throw WindowNavigationError.noteUnavailable(relativePath)
            }
            PerformanceProbe.shared.beginReadActivation(documentID: relativePath)
            documentController.selectUnavailableDocument(
                vaultID: vaultID,
                relativePath: relativePath
            )
            synchronizeDocumentTabs(after: tabActivation)
        }
    }

    private func activateWorkspaceReference(
        _ reference: VaultNoteReference,
        tabActivation: DocumentTabActivation
    ) throws {
        guard let vault = workspaceAssignment?.vaults.values.first(where: {
            $0.id == reference.vaultID
        }) else {
            throw WindowNavigationError.vaultUnavailable(reference.vaultName)
        }
        let requestedStableID = reference.stableNoteID.flatMap(UUID.init(uuidString:))
        guard let snapshot = workspaceProjectionController.cachedNote(
            vaultID: reference.vaultID,
            stableNoteID: requestedStableID,
            relativePath: reference.relativePath
        ) else {
            throw WindowNavigationError.noteUnavailable(reference.relativePath)
        }
        PerformanceProbe.shared.beginReadActivation(documentID: snapshot.id.relativePath)
        if snapshot.stableIdentity.resolvedID != nil {
            documentController.installOpenedDocument(
                snapshot,
                vaultName: vault.name,
                vaultRole: vault.role
            )
        } else {
            documentController.selectUnavailableDocument(
                vaultID: vault.id,
                relativePath: snapshot.id.relativePath
            )
        }
        synchronizeDocumentTabs(after: tabActivation)
    }

    private func synchronizeDocumentTabs(after activation: DocumentTabActivation) {
        guard let document = documentController.selectedDocument else { return }
        let presentation = documentTabPresentation(for: document)
        switch activation {
        case .place(let placement):
            documentTabController.activate(
                document: document,
                title: presentation.title,
                toolTip: presentation.toolTip,
                placement: placement
            )
        case .preserveTabMembership:
            documentTabController.updateDocumentProjection(
                document,
                title: presentation.title,
                toolTip: presentation.toolTip
            )
        }
        reconcileDocumentSessionLeases()
    }

    private func reconcileDocumentSessionLeases() {
        documentController.reconcileSessionLeases(
            leasedDocuments: documentTabController.tabs.map(\.document),
            selectedDocument: documentTabController.selectedTab?.document
        )
    }

    private func removeDocumentTabs(
        vaultID: UUID,
        removedPaths: Set<String>
    ) throws {
        let matchingIDs = documentTabController.tabs.compactMap { tab -> UUID? in
            guard let descriptor = tab.document.workspaceDescriptor,
                  descriptor.reference.vaultID == vaultID,
                  removedPaths.contains(descriptor.reference.relativePath) else {
                return nil
            }
            return tab.id
        }
        guard !matchingIDs.isEmpty else {
            if currentDocumentVaultID == vaultID {
                documentController.clearSelection(forRemovedPaths: removedPaths)
            }
            reconcileDocumentSessionLeases()
            return
        }

        // Remove inactive pages first so the selected page's close plan can
        // never choose another document that was deleted in the same commit.
        for id in matchingIDs where id != documentTabController.selectedTabID {
            if let plan = documentTabController.closePlan(forTabWithID: id) {
                documentTabController.apply(plan)
            }
        }
        guard let selectedID = documentTabController.selectedTabID,
              matchingIDs.contains(selectedID),
              let plan = documentTabController.closePlan(forTabWithID: selectedID) else {
            reconcileDocumentSessionLeases()
            return
        }
        if let documentToActivate = plan.documentToActivate {
            try activateDocument(
                documentToActivate,
                tabActivation: .preserveTabMembership
            )
        } else {
            documentController.clearSelectionAfterClosingLastTab()
        }
        documentTabController.apply(plan)
        reconcileDocumentSessionLeases()
    }

    private func refreshDocumentTabProjections() {
        for tab in documentTabController.tabs {
            guard case .workspace(let descriptor) = tab.document,
                  let snapshot = workspaceProjectionController.cachedNote(
                      vaultID: descriptor.reference.vaultID,
                      stableNoteID: descriptor.sessionKey.noteID,
                      relativePath: descriptor.reference.relativePath
                  ),
                  let vault = workspaceAssignment?.vaults.values.first(where: {
                      $0.id == descriptor.reference.vaultID
                  }) else { continue }
            let updated = WindowSelectedDocument.workspace(WindowDocumentDescriptor(
                sessionKey: descriptor.sessionKey,
                reference: VaultNoteReference(
                    vaultID: vault.id,
                    vaultName: vault.name,
                    vaultRole: vault.role,
                    relativePath: snapshot.id.relativePath,
                    stableNoteID: descriptor.reference.stableNoteID
                )
            ))
            let presentation = documentTabPresentation(for: updated)
            documentTabController.updateDocumentProjection(
                updated,
                title: presentation.title,
                toolTip: presentation.toolTip
            )
        }
    }

    private func documentTabPresentation(
        for document: WindowSelectedDocument
    ) -> (title: String, toolTip: String) {
        let location: WindowDocumentLocation? = if let sessionKey = document.sessionKey {
            workspaceProjectionController.cachedNote(
                vaultID: sessionKey.vaultID,
                stableNoteID: sessionKey.noteID,
                relativePath: document.relativePath
            )
                .map(WindowDocumentLocation.workspace)
        } else {
            notes.first(where: { $0.relativePath == document.relativePath })
        }
        let fallbackTitle = URL(fileURLWithPath: document.relativePath)
            .deletingPathExtension()
            .lastPathComponent
        let title = location?.title ?? location?.displayName ?? fallbackTitle
        let vaultName = document.workspaceDescriptor?.reference.vaultName
        let toolTip = [title, vaultName, document.relativePath]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " — ")
        return (title, toolTip)
    }

    private func documentSessionKey(for path: String) -> DocumentSessionKey? {
        guard let vaultID = currentRegisteredVault?.id,
              let noteID = noteIdentityByPath[path] else { return nil }
        return DocumentSessionKey(vaultID: vaultID, noteID: noteID)
    }

    private func documentDescriptor(for path: String) -> WindowDocumentDescriptor? {
        guard let key = documentSessionKey(for: path),
              let vault = currentRegisteredVault else { return nil }
        return WindowDocumentDescriptor(
            sessionKey: key,
            reference: VaultNoteReference(
                vaultID: vault.id,
                vaultName: vault.name,
                vaultRole: vault.role,
                relativePath: path,
                stableNoteID: key.noteID.uuidString
            )
        )
    }

    private func documentReference(for path: String) -> VaultNoteReference? {
        documentDescriptor(for: path)?.reference
    }

    private func selectionDescriptor(for path: String) -> WindowSelectedDocument? {
        if let descriptor = documentDescriptor(for: path) {
            return .workspace(descriptor)
        }
        guard let vaultID = notes.first(where: { $0.relativePath == path })?
            .workspaceSnapshot?.id.vaultID ?? currentRegisteredVault?.id else {
            return nil
        }
        return .unavailable(vaultID: vaultID, relativePath: path)
    }

    private func refreshSelectedDocumentProjection() {
        guard let selectedDocumentPath else { return }
        // Library refreshes must never reinterpret an existing vault-qualified
        // document through the newly browsed vault, especially when two vaults
        // contain the same relative path.
        guard documentController.activeDocument == nil else { return }
        if let descriptor = documentDescriptor(for: selectedDocumentPath) {
            documentController.selectDocument(.workspace(descriptor))
        } else if documentController.activeDocument == nil,
                  let descriptor = selectionDescriptor(for: selectedDocumentPath) {
            documentController.selectDocument(descriptor)
        }
        synchronizeDocumentTabs(after: .preserveTabMembership)
    }

    func showInFinder(_ path: String) {
        guard let vaultURL = vaultConfig?.path else { return }
        let fileURL = vaultURL.appendingPathComponent(path)
        workspaceStore.revealInFinder(fileURL)
    }

    func revealVaultInFinder() {
        guard let vaultURL = vaultConfig?.path else { return }
        workspaceStore.revealInFinder(vaultURL)
    }

    func openExternalURL(_ url: URL) {
        _ = workspaceStore.openExternal(url)
    }

    func openWorkspaceReference(
        _ reference: VaultNoteReference,
        line: Int? = nil,
        mode: NotePresentationMode = .source
    ) async {
        enqueueDocumentTransition(preservingCurrentEditorState: false) { [weak self] in
            guard let self else { return }
            try self.activateWorkspaceReference(
                reference,
                tabActivation: .place(.replaceSelected)
            )
            if let line {
                self.pendingSourceRange = nil
                self.pendingSourceLine = max(1, line)
                self.requestPresentationMode = mode
            }
        }
    }

    private func openWorkspaceReference(
        _ reference: VaultNoteReference,
        sourceRange: SearchSourceRange?,
        fallbackLine: Int
    ) {
        enqueueDocumentTransition(preservingCurrentEditorState: false) { [weak self] in
            guard let self else { return }
            try self.activateWorkspaceReference(
                reference,
                tabActivation: .place(.replaceSelected)
            )
            self.pendingSourceRange = sourceRange
            self.pendingSourceLine = sourceRange?.line ?? max(1, fallbackLine)
            self.requestPresentationMode = .source
        }
    }

    func openInternalLink(_ targetWithFragment: String, from sourcePath: String) {
        guard let sourceContext = activeDocumentContext(for: sourcePath),
              let graph = workspaceCatalog?.graph else {
            showToast(String(localized: "Connections are still refreshing. Try the link again shortly.", table: "Localizable", bundle: .module), kind: .information)
            return
        }
        let parts = targetWithFragment.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let target = String(parts.first ?? "").removingPercentEncoding ?? String(parts.first ?? "")
        let rawFragment = parts.count == 2 ? String(parts[1]) : nil
        let fragment = rawFragment.flatMap { $0.removingPercentEncoding ?? $0 }
        let source = VaultQualifiedNoteID(vaultID: sourceContext.vaultID, relativePath: sourcePath)
        let matching = graph.outgoing[source, default: []].filter { edge in
            let occurrenceTarget = edge.occurrence.target.removingPercentEncoding
                ?? edge.occurrence.target
            let occurrenceFragment = edge.occurrence.fragment.flatMap {
                $0.removingPercentEncoding ?? $0
            }
            return occurrenceTarget == target && occurrenceFragment == fragment
        }
        let resolved = matching.compactMap { edge -> (VaultQualifiedNoteID, Int?)? in
            guard let destination = edge.destination else { return nil }
            return (destination.note, destination.span?.start.line)
        }
        var destinations: [(note: VaultQualifiedNoteID, line: Int?)] = []
        for (destination, line) in resolved
        where !destinations.contains(where: { $0.note == destination }) {
            destinations.append((destination, line))
        }

        guard destinations.count == 1, let destination = destinations.first else {
            let hasAmbiguity = matching.contains {
                if case .ambiguous = $0.occurrence.resolution { return true }
                return false
            }
            showToast(
                hasAmbiguity
                    ? "This Connection is ambiguous. Open Incoming or Outgoing to choose a source-located candidate."
                    : "This Connection is broken or its destination no longer exists.",
                kind: .warning
            )
            return
        }
        guard let reference = workspaceCatalog?.notes.first(where: {
            $0.reference.vaultID == destination.note.vaultID
                && $0.reference.relativePath == destination.note.relativePath
        })?.reference else {
            showToast(String(localized: "The resolved note is not available in the current Triptych catalog.", table: "Localizable", bundle: .module), kind: .warning)
            return
        }
        Task { await openWorkspaceReference(reference, line: destination.line, mode: .read) }
    }

    @discardableResult
    func saveProperties(
        for note: WindowDocumentLocation,
        proposedFrontmatter: [String: YAMLValue],
        expectedRevision: DocumentFingerprint,
        researchUnitEdit: ResearchUnitEdit? = nil
    ) async throws -> WindowDocumentLocation {
        guard let context = activeDocumentContext(for: note.relativePath) else {
            throw VaultRepositoryError.fileDoesNotExist(note.relativePath)
        }
        let original = context.note

        var edits = PropertyEditorModel.frontmatterEdits(
            from: original.frontmatter,
            to: proposedFrontmatter
        )
        if let researchUnitEdit {
            edits["research_unit"] = researchUnitEdit.coreValue
        }
        do {
            let result = try await documentController.save(
                VaultQualifiedNoteID(vaultID: context.vaultID, relativePath: note.relativePath),
                changeSet: .frontmatter(edits),
                expectedRevision: expectedRevision
            )
            guard let saved = await replaceSavedDocument(result.document) else {
                throw WindowNavigationError.noteUnavailable(note.relativePath)
            }
            lastSaveError = nil
            return saved
        } catch {
            lastSaveError = error.localizedDescription
            throw error
        }
    }

    func diskDocument(for path: String) async throws -> NoteDocument {
        guard let context = activeDocumentContext(for: path) else {
            throw VaultRepositoryError.fileDoesNotExist(path)
        }
        return try await documentController.load(
            VaultQualifiedNoteID(vaultID: context.vaultID, relativePath: path)
        )
    }

    func showToast(_ message: String, kind: WindowToast.Kind = .success) {
        shellState.showToast(message, kind: kind)
    }

    private func refreshIdentityState() async {
        identityRefreshGeneration &+= 1
        let refreshGeneration = identityRefreshGeneration
        guard let vault = currentRegisteredVault else {
            noteIdentityByPath = [:]
            identityAmbiguities = []
            pendingIdentityRebindings = []
            identityMigrationFailures = []
            return
        }
        let locationScope = noteLocationScope
        guard refreshGeneration == identityRefreshGeneration,
              currentRegisteredVault?.id == vault.id,
              noteLocationScope == locationScope else { return }
        let recovery: NoteIdentityRecoveryState
        do {
            guard let vaultSnapshot = try await documentController.workspaceSnapshot(
                vaultID: vault.id
            ) else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            recovery = vaultSnapshot.identityRecovery
        } catch {
            guard refreshGeneration == identityRefreshGeneration,
                  currentRegisteredVault?.id == vault.id,
                  noteLocationScope == locationScope else { return }
            noteIdentityByPath = [:]
            identityResolutionError = error.localizedDescription
            return
        }
        guard refreshGeneration == identityRefreshGeneration,
              currentRegisteredVault?.id == vault.id,
              noteLocationScope == locationScope else { return }
        let identities = recovery.identities

        for rebinding in recovery.completedRebindings {
            migrateInMemoryPath(
                from: rebinding.previousRelativePath,
                to: rebinding.relativePath,
                noteID: rebinding.id,
                identityResolved: true,
                vaultID: vault.id
            )
        }
        noteIdentityByPath = identities.mapValues(\.id)
        identityAmbiguities = recovery.ambiguities
        pendingIdentityRebindings = recovery.pendingRebindings
        identityMigrationFailures = recovery.failures
        if let selectedIdentityAmbiguity,
           !identityAmbiguities.contains(where: { $0.id == selectedIdentityAmbiguity.id }) {
            self.selectedIdentityAmbiguity = nil
        }
        if let vaultSnapshot = try? await documentController.workspaceSnapshot(vaultID: vault.id) {
            let snapshots = Dictionary(
                uniqueKeysWithValues: vaultSnapshot.documents.map { ($0.id.relativePath, $0) }
            )
            workspaceProjectionController.refreshVisibleNoteSnapshots(snapshots)
        }
        refreshSelectedDocumentProjection()
    }

    private func resetWindowSession() {
        presentationRouter.dismissAll()
        documentController.removeAll(retainingSessions: true)
        searchController.resetExecution()
        discoveryController.reset()
        researchController.reset()
        workspaceProjectionController.reset()
        documentController.resetPresentationState()
        pendingSourceLine = nil
        pendingSourceRange = nil
        clearMetadataFilters()
        currentRegisteredVault = nil
        currentVaultRole = .other
        noteIdentityByPath = [:]
        identityAmbiguities = []
        pendingIdentityRebindings = []
        identityMigrationFailures = []
        identityResolutionError = nil
    }

    private func receiveWorkspaceEvents(_ events: [UUID: WorkspaceEvent]) {
        guard let capabilities = activeWorkspaceCapabilities,
              let event = events[capabilities.id] else { return }

        if case .researchConfigurationInvalidated = event {
            Task { [weak self] in
                await self?.refreshResearchActionAvailability()
            }
        }

        if case .inventoryChanged(let change) = event,
           let vaultID = currentRegisteredVault?.id {
            for move in change.moved where move.previousLocation.vaultID == vaultID
                && move.location.vaultID == vaultID {
                migrateInMemoryPath(
                    from: move.previousLocation.relativePath,
                    to: move.location.relativePath,
                    noteID: move.stableNoteID,
                    identityResolved: true,
                    vaultID: vaultID
                )
            }
        }

        if case .researchConfigurationInvalidated = event {
            _ = workspaceProjectionController.receive(
                event,
                runtimeIdentity: capabilities.runtimeIdentity,
                context: workspaceProjectionContext
            )
            return
        }

        documentController.receive(event.snapshot)
        researchController.receive(event.snapshot)
        agentNoteChangeWindowController.refreshForWorkspaceSnapshot(
            triptychID: event.snapshot.triptych.id
        )
        if let commit = workspaceProjectionController.receive(
            event,
            runtimeIdentity: capabilities.runtimeIdentity,
            context: workspaceProjectionContext
        ) {
            applyWorkspaceProjectionCommit(commit)
        }
    }

    private var workspaceProjectionContext: WindowWorkspaceProjectionContext {
        WindowWorkspaceProjectionContext(
            selectedVaultID: currentRegisteredVault?.id,
            locationScope: noteLocationScope,
            currentDocumentVaultID: currentDocumentVaultID,
            selectedDocumentPath: selectedDocumentPath,
            editingDocumentPath: documentController.editingDocumentPath
        )
    }

    private func applyWorkspaceProjectionCommit(
        _ commit: WindowWorkspaceProjectionCommit
    ) {
        refreshDocumentTabProjections()
        if commit.searchGenerationChanged {
            searchController.searchGenerationDidChange()
        }
        switch commit.derivedRefreshStatus {
        case .current:
            if refreshStatusText == "Derived state is stale"
                || refreshStatusText == "Derived refresh failed" {
                refreshStatusText = nil
            }
        case .stale:
            if refreshStatusText?.hasPrefix("Conflict:") != true {
                refreshStatusText = "Derived state is stale"
            }
        case .failed:
            if refreshStatusText?.hasPrefix("Conflict:") != true {
                refreshStatusText = "Derived refresh failed"
            }
        }
        if commit.retainedDeletedEditorPath != nil {
            refreshStatusText = "Conflict: note deleted outside Scholium"
        }
        Task { [weak self] in
            await self?.refreshIdentityState()
        }
    }

    private func replaceCachedWorkspaceNote(_ note: WorkspaceNoteSnapshot) {
        guard let vault = workspaceProjectionController.recordCommittedNote(
            note,
            visibleVaultID: currentRegisteredVault?.id,
            visibleLocationScope: noteLocationScope
        ) else { return }
        refreshDocumentTabProjections()
        documentController.recordCommittedSnapshot(
            note,
            vaultName: vault.name,
            vaultRole: vault.role
        )
    }

    /// Publishes authoritative document bytes before refreshing disposable
    /// projections. A parse or index failure can make derived state stale, but
    /// must never make the editor retry an already committed repository write
    /// or reject a disk revision the researcher explicitly accepted.
    private func replaceSavedDocument(_ document: NoteDocument) async -> WindowDocumentLocation? {
        guard let context = activeDocumentContext(for: document.relativePath) else {
            return nil
        }
        let previous = workspaceProjectionController.cachedNote(
            vaultID: context.vaultID,
            stableNoteID: context.noteID,
            relativePath: document.relativePath
        )
        let loaded = try? await documentController.noteSnapshot(VaultQualifiedNoteID(
            vaultID: context.vaultID,
            relativePath: document.relativePath
        ))
        let savedSnapshot: WorkspaceNoteSnapshot
        if let loaded, loaded.fingerprint == document.fingerprint {
            savedSnapshot = loaded
        } else {
            // Only the active Note needs an immediate source-bound title and
            // outline before the Triptych-wide derived refresh catches up.
            // Parse it off the main actor once, then publish the immutable
            // projection; SwiftUI views never parse Markdown in `body`.
            let semantic = await Task.detached(priority: .utility) {
                MarkdownSemanticDocument(parsing: document)
            }.value
            let metadata: WorkspaceFileMetadata
            let identity: WorkspaceNoteIdentityState
            let lifecycle: WorkspaceDocumentLifecycle
            let graphCounts: WorkspaceGraphCounts
            if let previous {
                metadata = WorkspaceFileMetadata(
                    byteCount: document.sourceBytes.count,
                    creationDate: previous.fileMetadata.creationDate,
                    modificationDate: previous.fileMetadata.modificationDate
                )
                identity = previous.stableIdentity
                lifecycle = previous.lifecycle
                graphCounts = previous.graphCounts
            } else {
                metadata = WorkspaceFileMetadata(
                    byteCount: document.sourceBytes.count,
                    creationDate: nil,
                    modificationDate: nil
                )
                identity = .resolved(context.noteID)
                lifecycle = .active
                graphCounts = WorkspaceGraphCounts(
                    incoming: 0,
                    outgoing: 0,
                    broken: 0,
                    ambiguous: 0
                )
            }
            savedSnapshot = WorkspaceNoteSnapshot(
                id: VaultQualifiedNoteID(
                    vaultID: context.vaultID,
                    relativePath: document.relativePath
                ),
                vaultRole: context.vaultRole,
                stableIdentity: identity,
                document: document,
                fileMetadata: metadata,
                lifecycle: lifecycle,
                graphCounts: graphCounts,
                headings: semantic.headings,
                cachedTitleProjection: WorkspaceNoteTitleProjection(
                    document: document,
                    vaultRole: context.vaultRole,
                    semantic: semantic
                )
            )
        }

        replaceCachedWorkspaceNote(savedSnapshot)
        let saved = WindowDocumentLocation.workspace(savedSnapshot)
        if currentRegisteredVault?.id == context.vaultID {
            return notes.first(where: { $0.relativePath == document.relativePath }) ?? saved
        }
        return saved
    }

}

private enum ClipboardWorkflowError: LocalizedError {
    case copyFailed(recovery: String?)

    var errorDescription: String? {
        switch self {
        case .copyFailed(let recovery):
            if let recovery {
                return String(localized: "macOS did not accept the text on the clipboard. \(recovery)", table: "Localizable", bundle: .module)
            }
            return String(localized: "macOS did not accept the text on the clipboard. Try copying again.", table: "Localizable", bundle: .module)
        }
    }
}
