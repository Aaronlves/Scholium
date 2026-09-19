import AppKit
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import UniformTypeIdentifiers

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
            content: makeBootstrapWindowContent,
            defaultValue: {
                BootstrapWindowRoute(purpose: .firstConfiguration)
            }
        )
        .defaultSize(
            width: ScholiumMetrics.Onboarding.preferredWidth,
            height: ScholiumMetrics.Onboarding.preferredHeight
        )
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .environmentObject(applicationBootstrap)
        .environmentObject(applicationDelegate)

        WindowGroup(
            id: "scholium-main",
            for: TriptychWindowRoute.self,
            content: makeMainWindowContent,
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
        .windowToolbarStyle(.unified(showsTitle: true))
        .environmentObject(applicationBootstrap)
        .environmentObject(applicationDelegate)
        .commands {
            ScholiumCommands()
        }

        Settings {
            ScholiumSettingsWindowContent()
                .frame(minWidth: 780, minHeight: 560)
        }
        .defaultSize(width: 920, height: 700)
        .windowResizability(.contentMinSize)
        .environmentObject(applicationBootstrap)
        .environmentObject(applicationDelegate)
    }
}

// SwiftUI's macOS 27 scene content callbacks are declared nonisolated even
// though the view graph is delivered on the main thread. Keep this one
// framework boundary explicit and narrow; all stateful content remains owned
// by the main-actor environment views below.
private func makeBootstrapWindowContent(
    _ route: Binding<BootstrapWindowRoute>
) -> ScholiumBootstrapWindowContent {
    ScholiumBootstrapWindowContent(route: route)
}

private func makeMainWindowContent(
    _ route: Binding<TriptychWindowRoute>
) -> ScholiumMainWindowContent {
    ScholiumMainWindowContent(route: route)
}

private struct ScholiumBootstrapWindowContent: View {
    @Binding var route: BootstrapWindowRoute

    nonisolated init(route: Binding<BootstrapWindowRoute>) {
        self._route = route
    }

    var body: some View {
        ScholiumBootstrapWindowEnvironmentContent(route: $route)
            .modifier(SystemNotificationRouting())
    }
}

@MainActor
private struct ScholiumBootstrapWindowEnvironmentContent: View {
    @EnvironmentObject private var applicationBootstrap: ApplicationBootstrapController
    @Binding var route: BootstrapWindowRoute

    var body: some View {
        ApplicationBootstrapGate(controller: applicationBootstrap) {
            ScholiumBootstrapWindowReadyContent(route: $route)
        }
        .focusedSceneValue(
            \.scholiumApplicationBootstrapStatus,
            ScholiumApplicationBootstrapStatus(isReady: applicationBootstrap.isReady)
        )
    }
}

@MainActor
private struct ScholiumBootstrapWindowReadyContent: View {
    @EnvironmentObject private var applicationDelegate: ScholiumApplicationDelegate
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @Binding var route: BootstrapWindowRoute

    var body: some View {
        ScholiumBootstrapRoot(
            workspaceStore: workspaceStore,
            route: route,
            lifecycleRegistry: applicationDelegate.windowLifecycleRegistry
        )
    }
}

private struct ScholiumMainWindowContent: View {
    @Binding var route: TriptychWindowRoute

    nonisolated init(route: Binding<TriptychWindowRoute>) {
        self._route = route
    }

    var body: some View {
        ScholiumMainWindowEnvironmentContent(route: $route)
            .modifier(SystemNotificationRouting())
    }
}

@MainActor
private struct ScholiumMainWindowEnvironmentContent: View {
    @EnvironmentObject private var applicationBootstrap: ApplicationBootstrapController
    @Binding var route: TriptychWindowRoute

    var body: some View {
        ApplicationBootstrapGate(controller: applicationBootstrap) {
            ScholiumMainWindowReadyContent(route: $route)
        }
        .focusedSceneValue(
            \.scholiumApplicationBootstrapStatus,
            ScholiumApplicationBootstrapStatus(isReady: applicationBootstrap.isReady)
        )
    }
}

@MainActor
private struct ScholiumMainWindowReadyContent: View {
    @EnvironmentObject private var applicationDelegate: ScholiumApplicationDelegate
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @Binding var route: TriptychWindowRoute

    var body: some View {
        ScholiumWindowRoot(
            workspaceStore: workspaceStore,
            route: route,
            lifecycleRegistry: applicationDelegate.windowLifecycleRegistry
        )
    }
}

private struct ScholiumSettingsWindowContent: View {
    var body: some View {
        ScholiumSettingsWindowEnvironmentContent()
            .modifier(SystemNotificationRouting())
    }
}

@MainActor
private struct ScholiumSettingsWindowEnvironmentContent: View {
    @EnvironmentObject private var applicationBootstrap: ApplicationBootstrapController

    var body: some View {
        ApplicationBootstrapGate(controller: applicationBootstrap) {
            ScholiumSettingsWindowReadyContent()
        }
        .focusedSceneValue(
            \.scholiumApplicationBootstrapStatus,
            ScholiumApplicationBootstrapStatus(isReady: applicationBootstrap.isReady)
        )
    }
}

@MainActor
private struct ScholiumSettingsWindowReadyContent: View {
    @EnvironmentObject private var applicationDelegate: ScholiumApplicationDelegate
    @EnvironmentObject private var workspaceStore: WorkspaceStore

    var body: some View {
        ScholiumSettingsRoot(workspaceStore: workspaceStore)
    }
}
/// Triptych is available it opens a configured workspace window and closes.
private struct ScholiumBootstrapRoot: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    private let route: BootstrapWindowRoute
    private let lifecycleRegistry: ScholiumWindowLifecycleRegistry
    @StateObject private var model: ScholiumBootstrapModel
    @StateObject private var fileSelectionPresenter = ScholiumFileSelectionPresenter()
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
        _model = StateObject(
            wrappedValue: ScholiumBootstrapModel(
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
        .buttonStyle(.automatic)
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
        .onReceive(SystemNotificationService.shared.$notificationWindowID) { id in
            guard route.purpose == .firstConfiguration, let id else { return }
            didRouteToWorkspace = true
            destinationWindowID = id
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
        .scholiumFileSelectionScene(presenter: fileSelectionPresenter)
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
            prepareTriptychStructure: { parentURL, name in
                try await model.prepareTriptychStructure(
                    parentURL: parentURL,
                    name: name
                )
            },
            preserveUnsupportedPortableControl: { containerURL, worksURL, id in
                try await model.preserveUnsupportedPortableControl(
                    containerURL: containerURL,
                    worksURL: worksURL,
                    triptychID: id
                )
            },
            configure: { selection in
                try await model.configure(selection)
            },
            completeBootstrap: model.completeBootstrap,
            dismiss: { openConfiguredWorkspaceIfAvailable() }
        )
    }

    private func openConfiguredWorkspaceIfAvailable() {
        if route.purpose == .firstConfiguration,
            let notificationWindowID = SystemNotificationService.shared.notificationWindowID
        {
            didRouteToWorkspace = true
            destinationWindowID = notificationWindowID
            return
        }
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
            let windowID = ScholiumRuntimeIsolation.initialWindowSessionID(),
            !didRouteToWorkspace
        else { return false }
        openWorkspace(
            TriptychWindowRoute(
                windowID: windowID
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
    private let triptychStructurePreparer = BootstrapTriptychStructurePreparer()

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
                do {
                    workspaceAssignment = try await workspaceStore.defaultTriptych()
                } catch let error as WorkspaceRegistryError {
                    throw error
                } catch {
                    workspaceAssignment = nil
                }
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

    func prepareTriptychStructure(
        parentURL: URL,
        name: String
    ) async throws -> WorkspaceSetupSelection {
        let scopeStarted = parentURL.startAccessingSecurityScopedResource()
        defer {
            if scopeStarted {
                parentURL.stopAccessingSecurityScopedResource()
            }
        }

        let structure = try await triptychStructurePreparer.prepare(
            parentURL: parentURL,
            name: name
        )
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        return WorkspaceSetupSelection(
            paperAnalysisURL: structure.analysesURL,
            topicKnowledgeURL: structure.topicsURL,
            outputURL: structure.worksURL,
            portableContainerURL: structure.rootURL,
            triptychID: targetTriptychID,
            triptychName: trimmedName
        )
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
        registeredTriptychs.removeAll { $0.id == capabilities.assignment.id }
        registeredTriptychs.append(capabilities.assignment)
        recoveryMessage = nil
        isReadyToOpenWorkspace = false
    }

    func preserveUnsupportedPortableControl(
        containerURL: URL,
        worksURL: URL,
        triptychID: UUID?
    ) async throws -> URL {
        try await workspaceStore.preserveUnsupportedPortableControl(
            portableContainerURL: containerURL,
            worksURL: worksURL,
            triptychID: triptychID
        )
    }

    func completeBootstrap() {
        guard workspaceAssignment != nil else { return }
        isReadyToOpenWorkspace = true
    }
}

private struct ScholiumWindowRoot: View {
    private let route: TriptychWindowRoute
    private let lifecycleRegistry: ScholiumWindowLifecycleRegistry
    @StateObject private var appState: WindowModel
    @StateObject private var windowCoordinator: WorkspaceWindowCoordinator

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
        _windowCoordinator = StateObject(
            wrappedValue: WorkspaceWindowCoordinator(
                windowID: route.windowID,
                appState: model,
                lifecycleRegistry: lifecycleRegistry
            ))
    }

    var body: some View {
        ScholiumWindowObservedRoot(
            appState: appState,
            windowCoordinator: windowCoordinator,
            route: route,
            lifecycleRegistry: lifecycleRegistry
        )
    }
}

/// Receives the retained scene owners before deriving child observations.
/// Keeping this boundary below `ScholiumWindowRoot` prevents a SwiftUI root
/// reinitialization from pairing its retained `@StateObject` with children from
/// a newly constructed, discarded `WindowModel`.
struct ScholiumWindowObservedRoot: View {
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    let appState: WindowModel
    @ObservedObject private var windowCoordinator: WorkspaceWindowCoordinator
    @ObservedObject private var shellState: WindowShellState
    @ObservedObject private var presentationRouter: WindowPresentationRouter
    @ObservedObject private var windowWorkspaceController: WindowWorkspaceController
    @ObservedObject private var commandObservation: WindowCommandObservation
    @ObservedObject private var lifecycleRegistry: ScholiumWindowLifecycleRegistry
    private let route: TriptychWindowRoute
    @StateObject private var fileSelectionPresenter = ScholiumFileSelectionPresenter()
    @State private var destinationBootstrapWindowID: UUID?
    @State private var accessRecovery: WorkspaceAccessRecovery?

    init(
        appState: WindowModel,
        windowCoordinator: WorkspaceWindowCoordinator,
        route: TriptychWindowRoute,
        lifecycleRegistry: ScholiumWindowLifecycleRegistry
    ) {
        self.appState = appState
        _windowCoordinator = ObservedObject(wrappedValue: windowCoordinator)
        _shellState = ObservedObject(wrappedValue: appState.shellState)
        _presentationRouter = ObservedObject(wrappedValue: appState.presentationRouter)
        _windowWorkspaceController = ObservedObject(
            wrappedValue: appState.windowWorkspaceController
        )
        _commandObservation = ObservedObject(wrappedValue: appState.commandObservation)
        _lifecycleRegistry = ObservedObject(wrappedValue: lifecycleRegistry)
        self.route = route
        _accessRecovery = State(
            initialValue: appState.windowWorkspaceController.state.accessRecovery
        )
    }

    var body: some View {
        let openWindowAction = openWindow
        let hasReadyWorkspace =
            shellState.hasCompletedInitialRestore && appState.vaultConfig != nil
        ScholiumWindowObservedContent(
            isReady: hasReadyWorkspace,
            appState: appState,
            windowCoordinator: windowCoordinator
        )
        .navigationTitle(workspaceWindowTitle)
        .navigationSubtitle(workspaceWindowSubtitle)
        .toolbar(removing: .sidebarToggle)
        .toolbar(removing: .title)
        .buttonStyle(.automatic)
        .focusedSceneObject(appState)
        .focusedSceneObject(appState.commandObservation)
        .focusedSceneValue(\.scholiumWorkspaceWindowActions, windowCoordinator.actions)
        .background(
            WorkspaceWindowAttachment(
                coordinator: windowCoordinator,
                colorScheme: shellState.colorScheme
            )
        )
        .sheet(
            item: $accessRecovery,
            onDismiss: {
                windowWorkspaceController.dismissAccessRecovery()
            }
        ) { recovery in
            RestoreWorkspaceAccessView(
                recovery: recovery,
                restore: {
                    try await windowWorkspaceController.restoreWorkspaceAccess(using: $0)
                },
                rebuildPortableControl: {
                    try await windowWorkspaceController.rebuildUnsupportedPortableControl()
                },
                canRemoveRegistration:
                    windowWorkspaceController.canRemoveUnavailableTriptychRegistration,
                removeRegistration: {
                    try await windowWorkspaceController.removeUnavailableTriptychRegistration()
                    openOrdinaryBootstrapAfterRegistrationRemoval()
                },
                quitApplication: {
                    windowWorkspaceController.dismissAccessRecovery()
                    windowCoordinator.closeUnavailableWorkspaceAndTerminateApplication()
                }
            )
            .buttonStyle(.automatic)
        }
        .preferredColorScheme(shellState.colorScheme.swiftUIColorScheme)
        .onChange(of: windowWorkspaceController.state.accessRecovery) { _, recovery in
            accessRecovery = recovery
        }
        .onChange(of: appState.workspaceAssignment?.id, initial: true) { _, triptychID in
            lifecycleRegistry.updateWorkspaceTriptych(
                id: route.windowID,
                triptychID: triptychID
            )
        }
        .task(id: hasReadyWorkspace) {
            guard hasReadyWorkspace,
                let notification = SystemNotificationService.shared.takeOpeningRoute(windowID: route.windowID)
            else { return }
            if let sidebar = await appState.openSystemNotification(notification),
                !shellState.libraryVisible || shellState.sidebarContent != sidebar
            {
                windowCoordinator.actions.activateSidebar(sidebar)
            }
        }
        .task(id: presentationRouter.fileImport) {
            await selectMarkdownFilesForImportIfRequested()
        }
        .task(id: route.windowID) {
            windowCoordinator.update(reduceMotion: reduceMotion)
            await appState.restoreWindowSession(id: route.windowID)
            if let proofURL = ScholiumRuntimeIsolation.fileSelectionRecoveryProofURL() {
                _ = windowWorkspaceController.recordRecovery(
                    for: WorkspaceRegistryError.vaultAccessUnavailable(proofURL.path)
                )
            }
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
        .onAppear { [weak appState, weak windowCoordinator, openWindowAction] in
            guard let appState, let windowCoordinator else { return }
            if !appState.isDetachedDocumentWindow {
                appState.workspaceStore.documentLocations.openMainWindow = { route in
                    openWindowAction(id: "scholium-main", value: route)
                }
            }
            let displayWindow = AgentNoteDisplayWindow(
                state: { [weak appState, weak windowCoordinator] in
                    appState?.agentNoteDisplayState(canDisplay: windowCoordinator?.canAcceptAgentDisplay == true)
                },
                display: { [weak appState] target, admitted in
                    guard let appState else { throw WorkspaceStore.displayUnavailable() }
                    try await appState.displayAgentNote(target, admitted: admitted)
                })
            appState.registerNoteDisplayWindow(displayWindow)
            SystemNotificationService.shared.registerWindow(id: route.windowID) {
                [weak appState, weak windowCoordinator] notification in
                guard let appState, appState.workspaceAssignment?.id == notification.triptychID else { return false }
                windowCoordinator?.makeKeyAndOrderFront()
                Task {
                    if let sidebar = await appState.openSystemNotification(notification),
                        !appState.shellState.libraryVisible || appState.shellState.sidebarContent != sidebar
                    {
                        windowCoordinator?.actions.activateSidebar(sidebar)
                    }
                }
                return true
            }
            windowCoordinator.activate(
                showAttention: { request in
                    switch request {
                    case .queue(let anchor, let workspaceSlot, let noteScope):
                        appState.attentionPopoverSession.presentQueue(
                            anchor: anchor,
                            workspaceSlot: workspaceSlot,
                            noteScope: noteScope
                        )
                    }
                }
            )
            windowCoordinator.update(reduceMotion: reduceMotion)
        }
        .onChange(of: commandObservation.revision, initial: true) { _, _ in
            if appState.isDetachedDocumentWindow {
                windowCoordinator.updateOwnedWindowTitle(workspaceWindowTitle)
            }
        }
        .onChange(of: reduceMotion) { _, reduceMotion in
            windowCoordinator.update(reduceMotion: reduceMotion)
        }
        .onDisappear {
            appState.unregisterNoteDisplayWindow()
            SystemNotificationService.shared.unregisterWindow(id: route.windowID)
            windowCoordinator.detach()
        }
        .scholiumFileSelectionScene(presenter: fileSelectionPresenter)
    }

    private var workspaceWindowTitle: String {
        let _ = commandObservation.revision
        return appState.currentNote.map { $0.title ?? $0.displayName } ?? "Scholium"
    }

    private var workspaceWindowSubtitle: String {
        guard lifecycleRegistry.showsTriptychSubtitle(in: route.windowID) else {
            return ""
        }
        return appState.workspaceAssignment?.triptych.name ?? ""
    }

    private func selectMarkdownFilesForImportIfRequested() async {
        guard presentationRouter.fileImport == .markdown else { return }
        defer {
            if presentationRouter.fileImport == .markdown {
                presentationRouter.fileImport = nil
            }
        }

        do {
            guard
                let urls = try await fileSelectionPresenter.selectURLs(
                    ScholiumFileSelectionRequest(
                        prompt: String(
                            localized: "Import",
                            table: "Localizable",
                            bundle: .module
                        ),
                        kind: .files(
                            allowedContentTypes: [
                                UTType(filenameExtension: "md") ?? .plainText
                            ],
                            allowsMultipleSelection: true
                        )
                    )
                )
            else { return }
            appState.libraryMutationController.requestMarkdownImport(urls)
        } catch is CancellationError {
            return
        } catch {
            appState.vaultError = error.localizedDescription
        }
    }

    private func redirectUnconfiguredWindowToBootstrapIfNeeded() {
        guard shellState.hasCompletedInitialRestore,
            appState.vaultConfig == nil,
            windowWorkspaceController.state.accessRecovery == nil,
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

    private func openOrdinaryBootstrapAfterRegistrationRemoval() {
        guard destinationBootstrapWindowID == nil else { return }
        let destination = BootstrapWindowRoute(purpose: .firstConfiguration)
        windowCoordinator.failReadiness(
            ScholiumWindowLifecycleError.failed(
                "The unavailable Triptych registration was removed from this Mac."
            )
        )
        openWindow(id: "scholium-bootstrap", value: destination)
        destinationBootstrapWindowID = destination.windowID
    }

}

private struct ScholiumWindowObservedContent: View {
    let isReady: Bool
    let appState: WindowModel
    let windowCoordinator: WorkspaceWindowCoordinator

    var body: some View {
        if isReady {
            ContentView(
                appState: appState,
                windowCoordinator: windowCoordinator
            )
        } else {
            ScholiumLaunchPlaceholderView()
        }
    }
}

private struct ScholiumSettingsRoot: View {
    @AppStorage(WindowColorSchemeChoice.defaultsKey)
    private var storedColorScheme = WindowColorSchemeChoice.system.rawValue
    @ObservedObject private var workspaceStore: WorkspaceStore
    @StateObject private var settingsModel: WorkspaceSettingsModel
    @StateObject private var fileSelectionPresenter = ScholiumFileSelectionPresenter()

    init(workspaceStore: WorkspaceStore) {
        self.workspaceStore = workspaceStore
        _settingsModel = StateObject(
            wrappedValue: WorkspaceSettingsModel(
                capabilities: workspaceStore.settingsCapabilities(),
                cssSnippetStore: workspaceStore.cssSnippetStore,
                agentBridgeAvailability: { [weak workspaceStore] in
                    guard let workspaceStore else {
                        return .unavailable("Scholium is shutting down.")
                    }
                    if workspaceStore.appBridge != nil { return .available }
                    return .unavailable(
                        workspaceStore.appBridgeStartupFailure?.localizedDescription
                            ?? "The App bridge did not start."
                    )
                }
            )
        )
    }

    var body: some View {
        ScholiumSettingsView()
            .environmentObject(settingsModel)
            .environment(
                \.agentChatSettingsController,
                settingsModel.snapshot.activeTriptychID.map { workspaceStore.chatRegistry.controller(for: $0) }
            )
            .tint(nil)
            .buttonStyle(.automatic)
            .preferredColorScheme(
                WindowColorSchemeChoice(rawValue: storedColorScheme)?.swiftUIColorScheme
            )
            .task(id: workspaceStore.latestWorkspaceActivation?.runtimeIdentity.activationID) {
                await settingsModel.restorePreferredWorkspaceIfNeeded(
                    activeTriptychID: workspaceStore.latestWorkspaceActivation?.workspaceID
                )
            }
            .scholiumFileSelectionScene(presenter: fileSelectionPresenter)
    }
}
