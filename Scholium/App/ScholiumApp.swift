import ScholiumContracts
import AppKit
import Combine
import notify
import QuartzCore
import ScholiumApplication
import ScholiumResearchRecordsFeature
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ScholiumApplicationDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let windowLifecycleRegistry = ScholiumWindowLifecycleRegistry()
    let researchRecordsWindowCoordinator = ResearchRecordsWindowCoordinator()
    let researchResultNotificationCoordinator =
        ResearchResultNotificationCoordinator()
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

        WindowGroup(
            "Research Records",
            id: "scholium-research-records",
            for: UUID.self,
            content: makeResearchRecordsWindowContent,
            defaultValue: { UUID() }
        )
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 760, height: 680)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .environmentObject(applicationBootstrap)
        .environmentObject(applicationDelegate)
        .commandsRemoved()

        Settings {
            ScholiumSettingsWindowContent()
            .frame(width: 700, height: 560, alignment: .topLeading)
            .background {
                ScholiumSettingsWindowBackground()
            }
            .background(SettingsWindowAttachment())
            .containerBackground(for: .window) {
                ScholiumSettingsWindowBackground()
            }
        }
        .environmentObject(applicationBootstrap)
        .environmentObject(applicationDelegate)

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

private func makeResearchRecordsWindowContent(
    _ triptychID: Binding<UUID>
) -> ScholiumResearchRecordsWindowContent {
    ScholiumResearchRecordsWindowContent(triptychID: triptychID)
}

private struct ScholiumBootstrapWindowContent: View {
    @Binding var route: BootstrapWindowRoute

    nonisolated init(route: Binding<BootstrapWindowRoute>) {
        self._route = route
    }

    var body: some View {
        ScholiumBootstrapWindowEnvironmentContent(route: $route)
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
            lifecycleRegistry: applicationDelegate.windowLifecycleRegistry,
            researchRecordsWindowCoordinator:
                applicationDelegate.researchRecordsWindowCoordinator,
            researchResultNotificationCoordinator:
                applicationDelegate.researchResultNotificationCoordinator
        )
    }
}

private struct ScholiumResearchRecordsWindowContent: View {
    @Binding var triptychID: UUID

    nonisolated init(triptychID: Binding<UUID>) {
        self._triptychID = triptychID
    }

    var body: some View {
        ScholiumResearchRecordsWindowEnvironmentContent(triptychID: $triptychID)
    }
}

@MainActor
private struct ScholiumResearchRecordsWindowEnvironmentContent: View {
    @EnvironmentObject private var applicationBootstrap: ApplicationBootstrapController
    @Binding var triptychID: UUID

    var body: some View {
        ApplicationBootstrapGate(controller: applicationBootstrap) {
            ScholiumResearchRecordsWindowReadyContent(triptychID: $triptychID)
        }
        .focusedSceneValue(
            \.scholiumApplicationBootstrapStatus,
            ScholiumApplicationBootstrapStatus(isReady: applicationBootstrap.isReady)
        )
    }
}

@MainActor
private struct ScholiumResearchRecordsWindowReadyContent: View {
    @EnvironmentObject private var applicationDelegate: ScholiumApplicationDelegate
    @EnvironmentObject private var workspaceStore: WorkspaceStore
    @Binding var triptychID: UUID

    var body: some View {
        ScholiumResearchRecordsRoot(
            workspaceStore: workspaceStore,
            triptychID: triptychID,
            coordinator: applicationDelegate.researchRecordsWindowCoordinator
        )
    }
}

private struct ScholiumSettingsWindowContent: View {
    var body: some View {
        ScholiumSettingsWindowEnvironmentContent()
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
        ScholiumSettingsRoot(
            workspaceStore: workspaceStore,
            researchResultNotificationCoordinator:
                applicationDelegate.researchResultNotificationCoordinator
        )
    }
}

/// One nonmodal auxiliary window bound permanently to its Triptych identity.
/// It reads the Triptych snapshot and narrow record capability directly from
/// WorkspaceStore; focused workspace changes cannot retarget it.
private struct ScholiumResearchRecordsRoot: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.layoutDirection) private var inheritedLayoutDirection
    @AppStorage(WindowColorSchemeChoice.defaultsKey)
    private var storedColorScheme = WindowColorSchemeChoice.system.rawValue
    @ObservedObject private var workspaceStore: WorkspaceStore
    private let triptychID: UUID
    private let coordinator: ResearchRecordsWindowCoordinator
    @State private var browserModel = ResearchRecordBrowserModel()
    @State private var capabilities: WindowWorkspaceCapabilities?
    @State private var currentRequest: ResearchRecordsWindowRequest
    @State private var recordsEndpointToken: UUID?
    @State private var isPrepared = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var recordLoadIssues: [String] = []
    @State private var proseNavigation = ResearchRecordProseNavigation.empty

    init(
        workspaceStore: WorkspaceStore,
        triptychID: UUID,
        coordinator: ResearchRecordsWindowCoordinator
    ) {
        _workspaceStore = ObservedObject(wrappedValue: workspaceStore)
        self.triptychID = triptychID
        self.coordinator = coordinator
        _currentRequest = State(initialValue: ResearchRecordsWindowRequest(
            triptychID: triptychID
        ))
    }

    var body: some View {
        Group {
            if let capabilities {
                recordsContent(capabilities)
            } else if isLoading {
                ScholiumContentStateView(
                    "Loading Research Records…",
                    indicator: .progress
                )
            } else {
                ScholiumContentStateView(
                    "Research Records Unavailable",
                    detail: Text(
                        errorMessage ?? "This Triptych is not available on this Mac."
                    ),
                    indicator: .symbol("exclamationmark.triangle", role: .attention)
                )
            }
        }
        .frame(minWidth: 700, minHeight: 520)
        .scholiumSurface(.document)
        .tint(ScholiumColorRole.accent.color)
        .preferredColorScheme(
            WindowColorSchemeChoice(rawValue: storedColorScheme)?.swiftUIColorScheme
        )
        .environment(\.layoutDirection, recordsLayoutDirection)
        .background(ResearchRecordsWindowAttachment(
            triptychID: triptychID,
            colorScheme:
                WindowColorSchemeChoice(rawValue: storedColorScheme) ?? .system
        ))
        .task(id: triptychID) { await loadCapabilities() }
        .onAppear { registerRecordsEndpoint() }
        .onDisappear { unregisterRecordsEndpoint() }
        .onReceive(workspaceStore.$workspaceEvents) { events in
            guard let event = events[triptychID], isPrepared else { return }
            let snapshot = event.snapshot
            browserModel.receive(
                triptychID: triptychID,
                records: snapshot.research.finishedResearchRecords,
                fingerprints: snapshot.research.finishedResearchRecordFingerprints
            )
            recordLoadIssues = researchRecordIssues(in: snapshot)
            proseNavigation = ResearchRecordProseNavigation(snapshot: snapshot)
        }
        .onReceive(workspaceStore.$workspaceActivations) { activations in
            guard let activation = activations[triptychID] else { return }
            capabilities = activation.capabilities
            recordLoadIssues = researchRecordIssues(in: activation.snapshot)
            proseNavigation = ResearchRecordProseNavigation(snapshot: activation.snapshot)
            if isPrepared {
                browserModel.receive(
                    triptychID: triptychID,
                    records: activation.snapshot.research.finishedResearchRecords,
                    fingerprints:
                        activation.snapshot.research.finishedResearchRecordFingerprints
                )
            }
        }
    }

    private var recordsLayoutDirection: LayoutDirection {
        switch ScholiumRuntimeIsolation.layoutDirectionOverride() {
        case .leftToRight:
            .leftToRight
        case .rightToLeft:
            .rightToLeft
        case nil:
            inheritedLayoutDirection
        }
    }

    private func recordsContent(
        _ capabilities: WindowWorkspaceCapabilities
    ) -> some View {
            ResearchRecordBrowserView(
                model: browserModel,
                loadIssues: recordLoadIssues,
                context: ResearchRecordBrowserContext(
                    proseNavigation: proseNavigation,
                    setRecommendationDisposition: { recordID, recommendationID, status in
                        try await capabilities.research.records
                            .setResearchRecordRecommendationDisposition(
                                recordID: recordID,
                                recommendationID: recommendationID,
                                status: status
                            )
                    },
                    setRecommendationNote: { recordID, recommendationID, note in
                        try await capabilities.research.records
                            .setResearchRecordRecommendationNote(
                                recordID: recordID,
                                recommendationID: recommendationID,
                                note: note
                            )
                    },
                    followUpContext: { recordID, resultFingerprint in
                        try await capabilities.research.actions.followUpContext(
                            recordID: recordID,
                            expectedFinalizedResultFingerprint: resultFingerprint
                        )
                    },
                    followUpClient: ResearchActionClient(
                        availableActions: { target in
                            try await capabilities.research.actions.availableActions(
                                for: target
                            )
                        },
                        materialCandidates: { target, definition in
                            try await capabilities.research.actions.materialCandidates(
                                for: target,
                                actionID: definition.id
                            )
                        },
                        sourceAccess: { target in
                            try await capabilities.research.sourceAccess.sourceAccess(
                                for: target
                            )
                        },
                        bindLocalSource: { target, url in
                            try await capabilities.research.sourceAccess.bindSourceAccess(
                                ResearchSourceBindingRequest(
                                    target: target,
                                    selection: .localFile(url)
                                )
                            )
                        },
                        prepare: { request, _ in
                            try await capabilities.research.actions.prepareAction(request)
                        },
                        prepareFollowUp: { request in
                            try await capabilities.research.actions.prepareFollowUp(request)
                        },
                        actionRun: { runID in
                            try await capabilities.research.actions.actionRun(id: runID)
                        },
                        handoff: { runID in
                            try await capabilities.research.actions.issueAgentHandoff(
                                runID: runID,
                                validity: 10 * 60
                            )
                        },
                        cancel: { runID in
                            try await capabilities.research.actions.cancelAction(
                                runID: runID
                            )
                        },
                        openActiveDiscussion: { _ in }
                    ),
                    reloadRecord: { recordID in
                        let records = try await capabilities.research.records
                            .finishedResearchRecords(noteID: nil)
                        guard let record = records.first(where: {
                            $0.id == recordID
                        }) else {
                            throw PortableResearchMethodFeedbackMutationError
                                .recordUnavailable
                        }
                        return record
                    },
                    changeState: { recordID in
                        try await capabilities.research.records
                            .researchRecordChangeState(recordID: recordID)
                    },
                    comparison: { recordID, noteID in
                        try await capabilities.research.records
                            .researchRecordComparison(
                                recordID: recordID,
                                noteID: noteID
                            )
                    },
                    undoChanges: {
                        recordID, noteIDs, resultFingerprint in
                        try await capabilities.research.records
                            .undoResearchRecordChanges(
                                recordID: recordID,
                                selectedNoteIDs: noteIDs,
                                expectedResultFingerprint: resultFingerprint
                            )
                    },
                    startMethodImprovement: { recordID in
                        try await capabilities.research.records
                            .issueMethodImprovementHandoff(
                                recordID: recordID,
                                validity: 10 * 60
                            )
                    },
                    deletePermanently: { id in
                        try await capabilities.research.records
                            .deleteResearchRecordPermanently(id: id)
                    },
                    openNote: { noteID, note, sourceLine in
                        openNote(
                            stableNoteID: noteID,
                            note: note,
                            sourceLine: sourceLine,
                            assignment: capabilities.assignment
                        )
                    }
                )
            )
    }

    private func loadCapabilities() async {
        isLoading = true
        errorMessage = nil
        do {
            let capabilities = try await workspaceStore.workspaceCapabilities(id: triptychID)
            try Task.checkCancellation()
            self.capabilities = capabilities
            browserModel.bindRecordSearch { request in
                try await capabilities.discovery.search(request)
            }
            let records: [PortableResearchRecord]
            let fingerprints: [UUID: DocumentFingerprint]
            if let snapshot = workspaceStore.workspaceSnapshots[triptychID] {
                records = snapshot.research.finishedResearchRecords
                fingerprints = snapshot.research.finishedResearchRecordFingerprints
                recordLoadIssues = researchRecordIssues(in: snapshot)
                proseNavigation = ResearchRecordProseNavigation(snapshot: snapshot)
            } else {
                let research = try await capabilities.research.records.snapshot()
                records = research.finishedResearchRecords
                fingerprints = research.finishedResearchRecordFingerprints
                recordLoadIssues = []
                proseNavigation = .empty
            }
            browserModel.prepareForOpen(
                triptychID: triptychID,
                records: records,
                fingerprints: fingerprints,
                request: currentRequest
            )
            isPrepared = true
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            capabilities = nil
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func registerRecordsEndpoint() {
        guard recordsEndpointToken == nil else { return }
        recordsEndpointToken = coordinator.registerRecordsWindow(
            triptychID: triptychID
        ) { request in
            currentRequest = request
            if isPrepared { browserModel.apply(request) }
        }
    }

    private func unregisterRecordsEndpoint() {
        guard let recordsEndpointToken else { return }
        coordinator.unregisterRecordsWindow(
            triptychID: triptychID,
            token: recordsEndpointToken
        )
        self.recordsEndpointToken = nil
    }

    private func openNote(
        stableNoteID: UUID,
        note: VaultQualifiedNoteID,
        sourceLine: Int?,
        assignment: TriptychAssignment
    ) {
        if coordinator.openInExistingWorkspace(
            triptychID: triptychID,
            noteID: stableNoteID,
            note: note,
            sourceLine: sourceLine
        ) {
            return
        }
        guard let vault = assignment.vaults.values.first(where: {
            $0.id == note.vaultID
        }) else {
            browserModel.presentError(
                "The recorded Analysis vault is no longer part of this Triptych."
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
        openWindow(
            id: "scholium-main",
            value: TriptychWindowRoute(
                triptychID: triptychID,
                initialDocument: reference
            )
        )
    }

    private func researchRecordIssues(in snapshot: WorkspaceSnapshot) -> [String] {
        snapshot.research.healthIssues.filter {
            $0.hasPrefix("Portable Research Record ")
        }
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
        .ignoresSafeArea(.container, edges: .top)
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
        .scholiumFileSelectionScene(presenter: fileSelectionPresenter)
    }

    private var workspaceSetupContext: WorkspaceSetupContext {
        WorkspaceSetupContext(
            isCreatingNewTriptych: model.isCreatingNewTriptych,
            offersAgentPreparation: model.offersAgentPreparation,
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

    /// Machine-level preparation appears only after the first Triptych is
    /// registered. A later launch with an existing registration goes directly
    /// to the workspace and never turns this optional step into a gate.
    var offersAgentPreparation: Bool {
        route.purpose == .firstConfiguration
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
        registeredTriptychs = try await workspaceStore.registeredTriptychs()
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
    private let researchRecordsWindowCoordinator: ResearchRecordsWindowCoordinator
    private let researchResultNotificationCoordinator:
        ResearchResultNotificationCoordinator
    @StateObject private var appState: WindowModel
    @StateObject private var windowCoordinator: WorkspaceWindowCoordinator

    init(
        workspaceStore: WorkspaceStore,
        route: TriptychWindowRoute,
        lifecycleRegistry: ScholiumWindowLifecycleRegistry,
        researchRecordsWindowCoordinator: ResearchRecordsWindowCoordinator,
        researchResultNotificationCoordinator:
            ResearchResultNotificationCoordinator
    ) {
        self.route = route
        self.lifecycleRegistry = lifecycleRegistry
        self.researchRecordsWindowCoordinator = researchRecordsWindowCoordinator
        self.researchResultNotificationCoordinator =
            researchResultNotificationCoordinator
        researchResultNotificationCoordinator.bind(to: workspaceStore)
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
            lifecycleRegistry: lifecycleRegistry,
            researchRecordsWindowCoordinator: researchRecordsWindowCoordinator,
                researchResultNotificationCoordinator:
                researchResultNotificationCoordinator
        ))
    }

    var body: some View {
        ScholiumWindowObservedRoot(
            appState: appState,
            windowCoordinator: windowCoordinator,
            route: route,
            lifecycleRegistry: lifecycleRegistry,
            researchRecordsWindowCoordinator: researchRecordsWindowCoordinator,
            researchResultNotificationCoordinator:
                researchResultNotificationCoordinator
        )
    }
}

/// Receives the retained scene owners before deriving child observations.
/// Keeping this boundary below `ScholiumWindowRoot` prevents a SwiftUI root
/// reinitialization from pairing its retained `@StateObject` with children from
/// a newly constructed, discarded `WindowModel`.
private struct ScholiumWindowObservedRoot: View {
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    let appState: WindowModel
    @ObservedObject private var windowCoordinator: WorkspaceWindowCoordinator
    @ObservedObject private var shellState: WindowShellState
    @ObservedObject private var presentationRouter: WindowPresentationRouter
    @ObservedObject private var windowWorkspaceController: WindowWorkspaceController
    @ObservedObject private var commandObservation: WindowCommandObservation
    private let route: TriptychWindowRoute
    private let lifecycleRegistry: ScholiumWindowLifecycleRegistry
    private let researchRecordsWindowCoordinator: ResearchRecordsWindowCoordinator
    private let researchResultNotificationCoordinator:
        ResearchResultNotificationCoordinator
    @StateObject private var fileSelectionPresenter = ScholiumFileSelectionPresenter()
    @State private var destinationBootstrapWindowID: UUID?
    @State private var accessRecovery: WorkspaceAccessRecovery?

    init(
        appState: WindowModel,
        windowCoordinator: WorkspaceWindowCoordinator,
        route: TriptychWindowRoute,
        lifecycleRegistry: ScholiumWindowLifecycleRegistry,
        researchRecordsWindowCoordinator: ResearchRecordsWindowCoordinator,
        researchResultNotificationCoordinator:
            ResearchResultNotificationCoordinator
    ) {
        self.appState = appState
        _windowCoordinator = ObservedObject(wrappedValue: windowCoordinator)
        _shellState = ObservedObject(wrappedValue: appState.shellState)
        _presentationRouter = ObservedObject(wrappedValue: appState.presentationRouter)
        _windowWorkspaceController = ObservedObject(
            wrappedValue: appState.windowWorkspaceController
        )
        _commandObservation = ObservedObject(wrappedValue: appState.commandObservation)
        self.route = route
        self.lifecycleRegistry = lifecycleRegistry
        self.researchRecordsWindowCoordinator = researchRecordsWindowCoordinator
        self.researchResultNotificationCoordinator =
            researchResultNotificationCoordinator
        _accessRecovery = State(
            initialValue: appState.windowWorkspaceController.state.accessRecovery
        )
    }

    var body: some View {
        let hasReadyWorkspace =
            shellState.hasCompletedInitialRestore && appState.vaultConfig != nil
        ScholiumWindowObservedContent(
            isReady: hasReadyWorkspace,
            appState: appState,
            windowCoordinator: windowCoordinator
        )
            .navigationTitle(workspaceWindowTitle)
            .toolbar(removing: .sidebarToggle)
            .tint(ScholiumColorRole.accent.color)
            .focusedSceneObject(appState)
            .focusedSceneObject(appState.commandObservation)
            .focusedSceneValue(\.scholiumWorkspaceWindowActions, windowCoordinator.actions)
            .background(
                WorkspaceWindowAttachment(
                    coordinator: windowCoordinator,
                    colorScheme: shellState.colorScheme
                )
            )
            .sheet(item: $accessRecovery, onDismiss: {
                windowWorkspaceController.dismissAccessRecovery()
            }) { recovery in
                RestoreWorkspaceAccessView(
                    recovery: recovery,
                    restore: {
                        try await windowWorkspaceController.restoreWorkspaceAccess(using: $0)
                    },
                    rebuildPortableControl: {
                        try await windowWorkspaceController.rebuildUnsupportedPortableControl()
                    },
                    archiveNoteMetadataRecord: {
                        try await windowWorkspaceController.archiveInvalidNoteMetadataRecord()
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
            }
            .preferredColorScheme(shellState.colorScheme.swiftUIColorScheme)
            .onChange(of: windowWorkspaceController.state.accessRecovery) { _, recovery in
                accessRecovery = recovery
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
            .onAppear {
                windowCoordinator.activate(
                    showNoteResearchRecords: {
                        guard let triptychID = appState.workspaceAssignment?.id,
                              let noteID = appState.documentController.activeDocument?
                                .sessionKey.noteID else { return }
                        researchRecordsWindowCoordinator.submit(
                            ResearchRecordsWindowRequest(
                                triptychID: triptychID,
                                noteID: noteID,
                                initialView: .records
                            )
                        )
                        openWindow(
                            id: "scholium-research-records",
                            value: triptychID
                        )
                    },
                    showTriptychResearchRecords: {
                        guard let triptychID = appState.workspaceAssignment?.id else {
                            return
                        }
                        researchRecordsWindowCoordinator.submit(
                            ResearchRecordsWindowRequest(
                                triptychID: triptychID,
                                initialView: .records
                            )
                        )
                        openWindow(
                            id: "scholium-research-records",
                            value: triptychID
                        )
                    },
                    showResearchRecordsWindow: {
                        guard let triptychID = appState.workspaceAssignment?.id else {
                            return
                        }
                        openWindow(
                            id: "scholium-research-records",
                            value: triptychID
                        )
                    },
                    reviewResearchResult: { destination in
                        researchRecordsWindowCoordinator.submit(
                            ResearchRecordsWindowRequest(
                                triptychID: destination.triptychID,
                                initialView: .records,
                                purpose: .reviewResult,
                                recordID: destination.recordID,
                                expectedFinalizedResultFingerprint:
                                    destination.finalizedResultFingerprint
                            )
                        )
                        openWindow(
                            id: "scholium-research-records",
                            value: destination.triptychID
                        )
                    },
                    showAttention: { request in
                        switch request {
                        case .queue(let anchor, let workspaceSlot, let noteScope):
                            appState.attentionPopoverSession.presentQueue(
                                anchor: anchor,
                                workspaceSlot: workspaceSlot,
                                noteScope: noteScope
                            )
                        case .actionStack:
                            appState.shellState
                                .requestActionNotificationStackExpansion()
                        }
                    }
                )
                windowCoordinator.updateResearchRecordsRouting(
                    triptychID: windowWorkspaceController.state.assignment?.id
                )
                windowCoordinator.update(reduceMotion: reduceMotion)
            }
            .onChange(
                of: windowWorkspaceController.state.assignment?.id,
                initial: true
            ) { _, triptychID in
                windowCoordinator.updateResearchRecordsRouting(triptychID: triptychID)
            }
            .onChange(of: reduceMotion) { _, reduceMotion in
                windowCoordinator.update(reduceMotion: reduceMotion)
            }
            .onChange(
                of: presentationRouter.researchRecordsWindowRequest
            ) { _, request in
                guard let request else { return }
                researchRecordsWindowCoordinator.submit(request)
                openWindow(
                    id: "scholium-research-records",
                    value: request.triptychID
                )
                presentationRouter.researchRecordsWindowRequest = nil
            }
            .onDisappear {
                windowCoordinator.detach()
            }
            .scholiumFileSelectionScene(presenter: fileSelectionPresenter)
    }

    private var workspaceWindowTitle: String {
        let _ = commandObservation.revision
        return appState.currentNote.map { $0.title ?? $0.displayName } ?? "Scholium"
    }

    private func selectMarkdownFilesForImportIfRequested() async {
        guard presentationRouter.fileImport == .markdown else { return }
        defer {
            if presentationRouter.fileImport == .markdown {
                presentationRouter.fileImport = nil
            }
        }

        do {
            guard let urls = try await fileSelectionPresenter.selectURLs(
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
            ) else { return }
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
    @ObservedObject private var researchResultNotificationCoordinator:
        ResearchResultNotificationCoordinator
    @StateObject private var settingsModel: WorkspaceSettingsModel
    @StateObject private var fileSelectionPresenter = ScholiumFileSelectionPresenter()

    init(
        workspaceStore: WorkspaceStore,
        researchResultNotificationCoordinator:
            ResearchResultNotificationCoordinator
    ) {
        self.workspaceStore = workspaceStore
        self.researchResultNotificationCoordinator =
            researchResultNotificationCoordinator
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
            .environmentObject(researchResultNotificationCoordinator)
            .tint(ScholiumColorRole.accent.color)
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

struct ScholiumSearchActions {
    let begin: (SearchInvocation) -> Void
}

struct ScholiumApplicationBootstrapStatus: Equatable, Sendable {
    let isReady: Bool
}

struct ScholiumApplicationBootstrapStatusFocusedKey: FocusedValueKey {
    typealias Value = ScholiumApplicationBootstrapStatus
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
    let allowsReplace: Bool
    let isAvailable: (MarkdownEditorCommand) -> Bool
    let canCommentOnSelectedPassage: () -> Bool
    let perform: (MarkdownEditorCommand) -> Void
    let performWithArgument: (MarkdownEditorCommand, String) -> Void
    let startComment: () -> Void
    let presentFind: () -> Void
    let findNext: () -> Void
    let findPrevious: () -> Void
    let useSelectionForFind: () -> Void
    let announceDocumentStatistics: () -> Void
    let importImage: () -> Void
    let indexImage: () -> Void
}

struct ScholiumFocusedEditorActionsKey: FocusedValueKey {
    typealias Value = ScholiumFocusedEditorActions
}

extension FocusedValues {
    var scholiumApplicationBootstrapStatus: ScholiumApplicationBootstrapStatus? {
        get { self[ScholiumApplicationBootstrapStatusFocusedKey.self] }
        set { self[ScholiumApplicationBootstrapStatusFocusedKey.self] = newValue }
    }

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

private struct ScholiumNewWindowCommandContent: View {
    let storageReady: Bool
    @Environment(\.openWindow) private var openWindow
    @FocusedObject private var appState: WindowModel?

    var body: some View {
        Button("New Window") {
            openWindow(
                id: "scholium-main",
                value: TriptychWindowRoute(triptychID: appState?.workspaceAssignment?.id)
            )
        }
        .keyboardShortcut("n", modifiers: [.command])
        .disabled(!storageReady)
    }
}

private struct ScholiumAfterNewItemCommandContent: View {
    let storageReady: Bool
    @Environment(\.openWindow) private var openWindow
    @FocusedObject private var appState: WindowModel?

    var body: some View {
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
            appState?.libraryMutationController.requestUntitledNoteCreation(in: nil)
        }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(
                appState?.workspaceAssignment == nil
                    || appState?.noteSourceScope != .library
                    || appState?.libraryMutationController.isCreatingNote == true
            )
        Button("Import Markdown…") { appState?.showMarkdownImporter = true }
            .disabled(appState?.workspaceAssignment == nil)
        Divider()
        Button("Duplicate Note…") {
            guard let note = appState?.currentNote,
                  let target = NoteMutationTarget(note) else { return }
            appState?.noteFileRequest = .duplicate(target)
        }
        .disabled(appState?.currentDocumentCapabilities.allows(.duplicate) != true)
        Button("Rename Note…") {
            guard let note = appState?.currentNote,
                  let target = NoteMutationTarget(note) else { return }
            appState?.noteFileRequest = .rename(target)
        }
        .disabled(appState?.currentDocumentCapabilities.allows(.move) != true)
        Button("Move Note…") {
            guard let note = appState?.currentNote,
                  let target = NoteMutationTarget(note) else { return }
            appState?.noteFileRequest = .move(target)
        }
        .disabled(appState?.currentDocumentCapabilities.allows(.move) != true)
        Button("Move to Trash…") {
            appState?.requestCurrentNoteSystemTrash()
        }
        .keyboardShortcut(.delete, modifiers: [.command])
        .disabled(
            appState?.currentDocumentCapabilities.allows(.moveToSystemTrash)
                != true
        )
        Divider()
        Button("Reveal Current Vault in Finder") { appState?.revealVaultInFinder() }
            .disabled(appState?.vaultConfig == nil)
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

private struct ScholiumPasteboardCommandContent: View {
    @FocusedObject private var appState: WindowModel?
    @FocusedValue(\.scholiumEditorActions) private var editorActions

    var body: some View {
        Button("Paste as Markdown") {
            guard let payload = markdownPasteboardPayload() else { return }
            editorActions?.performWithArgument(.pasteMarkdown, payload)
        }
        .keyboardShortcut("v", modifiers: [.command, .shift])
        .disabled(editorActions?.isAvailable(.pasteMarkdown) != true)
        Divider()
        Menu("Find") {
            Button("Find…") { editorActions?.presentFind() }
                .keyboardShortcut("f", modifiers: [.command])
                .disabled(editorActions == nil)
            Button("Find and Replace…") { editorActions?.presentFind() }
                .disabled(editorActions?.allowsReplace != true)
            Divider()
            Button("Find Next") { editorActions?.findNext() }
                .keyboardShortcut("g", modifiers: [.command])
                .disabled(editorActions == nil)
            Button("Find Previous") { editorActions?.findPrevious() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(editorActions == nil)
            Button("Use Selection for Find") { editorActions?.useSelectionForFind() }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(editorActions == nil)
        }
        .disabled(appState?.currentNote == nil)
        Button("Document Statistics") {
            editorActions?.announceDocumentStatistics()
        }
        .disabled(editorActions == nil || appState?.currentNote == nil)
        Button("Edit Metadata…") { appState?.showMetadataEditor = true }
            .disabled(appState?.canEditCurrentNote != true)
    }

    private func markdownPasteboardPayload() -> String? {
        let pasteboard = NSPasteboard.general
        let plainText = pasteboard.string(forType: .string) ?? ""
        let html = pasteboard.string(forType: .html)
        guard !plainText.isEmpty || html?.isEmpty == false else { return nil }
        var payload = ["plainText": plainText]
        if let html, !html.isEmpty { payload["html"] = html }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

private struct ScholiumTextFormattingCommandContent: View {
    @FocusedValue(\.scholiumEditorActions) private var editorActions

    var body: some View {
        Divider()
        Button("Bold") { editorActions?.perform(.bold) }
            .keyboardShortcut("b", modifiers: [.command])
            .disabled(editorActions?.isAvailable(.bold) != true)
        Button("Italic") { editorActions?.perform(.emphasis) }
            .keyboardShortcut("i", modifiers: [.command])
            .disabled(editorActions?.isAvailable(.emphasis) != true)
        Button("Strikethrough") { editorActions?.perform(.strikethrough) }
            .disabled(editorActions?.isAvailable(.strikethrough) != true)
        Button("Highlight") { editorActions?.perform(.highlight) }
            .disabled(editorActions?.isAvailable(.highlight) != true)
        Button("Inline Code") { editorActions?.perform(.inlineCode) }
            .disabled(editorActions?.isAvailable(.inlineCode) != true)
        Button("Import Image…") { editorActions?.importImage() }
            .disabled(editorActions?.isAvailable(.insertImage) != true)
        Button("Index Image…") { editorActions?.indexImage() }
            .disabled(editorActions?.isAvailable(.insertImage) != true)
        Divider()
        Menu("Heading") {
            Button("Paragraph") { editorActions?.perform(.paragraph) }
                .disabled(editorActions?.isAvailable(.paragraph) != true)
            ForEach(1...6, id: \.self) { level in
                Button("Heading \(level)") {
                    editorActions?.perform(headingCommand(level))
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
        Button("Markdown Comment") { editorActions?.perform(.markdownComment) }
            .disabled(editorActions?.isAvailable(.markdownComment) != true)
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
}

private struct ScholiumInsertCommandContent: View {
    @AppStorage(ScholiumHotkeyPreferences.defaultsKey)
    private var hotkeyPreferencesData = ScholiumHotkeyPreferences.defaultData
    @FocusedValue(\.scholiumEditorActions) private var editorActions

    var body: some View {
        Button("Import Image…") { editorActions?.importImage() }
            .disabled(editorActions?.isAvailable(.insertImage) != true)
        Button("Index Image…") { editorActions?.indexImage() }
            .disabled(editorActions?.isAvailable(.insertImage) != true)
        Divider()
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
            .scholiumKeyboardShortcut(shortcut(for: .commentOnSelection))
            .disabled(
                editorActions?.canCommentOnSelectedPassage() != true
                    || editorActions?.isComposing == true
            )
    }

    private func shortcut(for command: ScholiumHotkeyCommand) -> ScholiumHotkeyBinding? {
        ScholiumHotkeyPreferences.binding(
            for: command,
            data: hotkeyPreferencesData
        )
    }
}

private struct ScholiumSidebarCommandContent: View {
    @AppStorage(ScholiumHotkeyPreferences.defaultsKey)
    private var hotkeyPreferencesData = ScholiumHotkeyPreferences.defaultData
    @FocusedObject private var appState: WindowModel?
    @FocusedValue(\.scholiumSearchActions) private var searchActions
    @FocusedValue(\.scholiumWorkspaceWindowActions) private var workspaceWindowActions
    @FocusedValue(\.scholiumEditorActions) private var editorActions

    var body: some View {
        Button("Back") {
            appState?.navigateDocumentHistory(.back)
        }
        .disabled(appState?.documentNavigationHistoryController.canGoBack != true)
        Button("Forward") {
            appState?.navigateDocumentHistory(.forward)
        }
        .disabled(appState?.documentNavigationHistoryController.canGoForward != true)
        Divider()
        Button(
            ScholiumL10n.dynamicString(
                appState?.sidebarVisible == true ? "Hide Sidebar" : "Show Sidebar"
            )
        ) {
            guard let appState else { return }
            workspaceWindowActions?.setLibraryVisible(!appState.sidebarVisible)
        }
        .scholiumKeyboardShortcut(shortcut(for: .toggleLibrary))
        .disabled(workspaceWindowActions == nil)
        Divider()
        Button("Search…") {
            searchActions?.begin(.general)
        }
        .scholiumKeyboardShortcut(shortcut(for: .searchResearch))
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
        .scholiumKeyboardShortcut(shortcut(for: .toggleResearchInspector))
        .disabled(
            workspaceWindowActions == nil
                || (appState?.researchInspectorVisible != true
                    && appState?.currentNote == nil)
        )
        Menu("Document Mode") {
            if appState?.presentedDocumentMode == .read {
                Button("Review") { appState?.requestDocumentMode(.read) }
                Button("Edit") { appState?.requestDocumentMode(.livePreview) }
                    .scholiumKeyboardShortcut(shortcut(for: .toggleReviewEdit))
                    .disabled(appState?.canEditCurrentNote != true)
            } else {
                Button("Review") { appState?.requestDocumentMode(.read) }
                    .scholiumKeyboardShortcut(shortcut(for: .toggleReviewEdit))
                Button("Edit") { appState?.requestDocumentMode(.livePreview) }
                    .disabled(appState?.canEditCurrentNote != true)
            }
            Button("Source") { appState?.requestDocumentMode(.source) }
                .scholiumKeyboardShortcut(shortcut(for: .showSource))
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

    private func shortcut(for command: ScholiumHotkeyCommand) -> ScholiumHotkeyBinding? {
        ScholiumHotkeyPreferences.binding(
            for: command,
            data: hotkeyPreferencesData
        )
    }
}

private struct ScholiumAttentionCommandContent: View {
    @AppStorage(ScholiumHotkeyPreferences.defaultsKey)
    private var hotkeyPreferencesData = ScholiumHotkeyPreferences.defaultData
    @FocusedValue(\.scholiumWorkspaceWindowActions) private var workspaceWindowActions

    var body: some View {
        Button("Notifications") {
            workspaceWindowActions?.showPreferredAttention()
        }
        .scholiumKeyboardShortcut(shortcut(for: .showAttention))
        .disabled(workspaceWindowActions?.canShowAttention() != true)
    }

    private func shortcut(for command: ScholiumHotkeyCommand) -> ScholiumHotkeyBinding? {
        ScholiumHotkeyPreferences.binding(
            for: command,
            data: hotkeyPreferencesData
        )
    }
}

private struct ScholiumResearchCommandContent: View {
    @AppStorage(ScholiumHotkeyPreferences.defaultsKey)
    private var hotkeyPreferencesData = ScholiumHotkeyPreferences.defaultData
    @FocusedObject private var appState: WindowModel?
    @FocusedValue(\.scholiumResearchActionActions) private var researchActionActions
    @FocusedValue(\.scholiumWorkspaceWindowActions) private var workspaceWindowActions

    var body: some View {
        if let appState, researchActionActions != nil {
            ForEach(appState.researchController.actions.availability) { action in
                Button {
                    researchActionActions?.open(action.id)
                } label: {
                    Text(verbatim: action.buttonName)
                }
                .disabled(
                    !action.canPresentInInterface
                        || !appState.hasConfirmedCurrentResearchActionAvailability
                        || appState.researchController.actions.hasCancellationBarrier
                )
            }
        }
        Divider()
        Button("Triptych Records") {
            workspaceWindowActions?.showTriptychResearchRecords()
        }
        .scholiumKeyboardShortcut(shortcut(for: .showTriptychRecords))
        .disabled(
            appState?.workspaceAssignment == nil
                || workspaceWindowActions == nil
        )
    }

    private func shortcut(for command: ScholiumHotkeyCommand) -> ScholiumHotkeyBinding? {
        ScholiumHotkeyPreferences.binding(
            for: command,
            data: hotkeyPreferencesData
        )
    }
}

#if DEBUG
enum QAActionNotificationProof {
    static func notifications(
        triptychID: UUID,
        arrivals: [WorkspaceResearchResultArrival]
    ) -> [ResearchActivityNotification] {
        arrivals.sorted {
            if $0.finishedAt != $1.finishedAt {
                return $0.finishedAt > $1.finishedAt
            }
            return $0.runID.uuidString < $1.runID.uuidString
        }
        .prefix(2)
        .map { arrival in
            let destination = ResearchResultReviewDestination(
                triptychID: triptychID,
                arrival: arrival
            )
            return ResearchActivityNotification(
                triptychID: triptychID,
                runID: arrival.runID,
                actionID: arrival.actionID,
                targetNoteID: arrival.originNoteID,
                targetTitle: arrival.targetTitle,
                state: .resultReady,
                activity: nil,
                result: destination,
                affectedNotes: arrival.affectedNotes,
                updatedAt: arrival.finishedAt
            )
        }
    }
}

private struct ScholiumQACommandContent: View {
    @Environment(\.openWindow) private var openWindow
    @FocusedObject private var appState: WindowModel?
    @FocusedValue(\.scholiumEditorActions) private var editorActions

    var body: some View {
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
        if qaEditorFaultsAreEnabled
            && (qaFeedbackProofsAreEnabled || qaResearchWorkflowProofsAreEnabled) {
            Divider()
        }
        if qaFeedbackProofsAreEnabled {
            Button("Present Window Feedback Proof") {
                appState?.presentFeedback(
                    "QA transient confirmation",
                    kind: .confirmation
                )
                appState?.presentFeedback(
                    "QA persistent warning",
                    kind: .warning
                )
            }
            .disabled(appState == nil)
            Button("Present Action Notification Proof") {
                appState?.presentQAActionNotificationProof()
            }
            .disabled(appState == nil)
        }
        if qaFeedbackProofsAreEnabled && qaResearchWorkflowProofsAreEnabled {
            Divider()
        }
        if qaResearchWorkflowProofsAreEnabled {
            Button("Open Research Workflow Interface Proofs") {
                openWindow(id: "scholium-research-workflow-proofs")
            }
        }
    }

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

    private var qaFeedbackProofsAreEnabled: Bool {
        Bundle.main.bundleIdentifier == "com.scholium.qa"
            && ProcessInfo.processInfo.arguments.contains(
                "--scholium-feedback-proofs"
            )
    }
}
#endif

private struct ScholiumCommands: Commands {
    @FocusedValue(\.scholiumApplicationBootstrapStatus)
    private var applicationBootstrapStatus
    @FocusedObject private var commandObservation: WindowCommandObservation?

    var body: some Commands {
        let _ = commandObservation?.revision
        let storageReady = applicationBootstrapStatus?.isReady == true
        let newWindowCommand = ScholiumNewWindowCommandContent(
            storageReady: storageReady
        )
        let afterNewItemCommand = ScholiumAfterNewItemCommandContent(
            storageReady: storageReady
        )
        let pasteboardCommand = ScholiumPasteboardCommandContent()
        let textFormattingCommand = ScholiumTextFormattingCommandContent()
        let insertCommand = ScholiumInsertCommandContent()
        let sidebarCommand = ScholiumSidebarCommandContent()
        let attentionCommand = ScholiumAttentionCommandContent()
        let researchCommand = ScholiumResearchCommandContent()
        #if DEBUG
        let qaCommand = ScholiumQACommandContent()
        #endif
        CommandGroup(replacing: .newItem) {
            newWindowCommand
        }
        CommandGroup(after: .newItem) {
            afterNewItemCommand
        }
        CommandGroup(after: .pasteboard) {
            pasteboardCommand
        }
        CommandGroup(after: .textFormatting) {
            textFormattingCommand
        }
        CommandMenu("Insert") {
            insertCommand
        }
        CommandGroup(replacing: .sidebar) {
            sidebarCommand
        }
        CommandGroup(after: .windowArrangement) {
            attentionCommand
        }
        CommandMenu("Research") {
            researchCommand
        }
        #if DEBUG
        if qaEditorFaultsAreEnabled
            || qaFeedbackProofsAreEnabled
            || qaResearchWorkflowProofsAreEnabled {
            CommandMenu("QA") {
                qaCommand
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

    private var qaFeedbackProofsAreEnabled: Bool {
        Bundle.main.bundleIdentifier == "com.scholium.qa"
            && ProcessInfo.processInfo.arguments.contains(
                "--scholium-feedback-proofs"
            )
    }
    #endif

}

private final class WindowModelObserverRelay: @unchecked Sendable {
    weak var model: WindowModel?

    init(model: WindowModel) {
        self.model = model
    }
}

// Combine may synchronously replay the current @Published value while a
// subscription is installed. Keep this transform outside the @MainActor
// WindowModel method so that replay does not perform an invalid executor
// check before the window has finished constructing.
private func nonisolatedWorkspaceActivation(
    _ activation: WorkspaceActivation?
) -> WorkspaceActivation? {
    activation
}

private func nonisolatedWorkspaceAssignmentID(
    _ state: WindowWorkspaceSessionState
) -> UUID? {
    state.assignment?.id
}

private func nonisolatedDiscardPublisherValue<Value>(_ _: Value) {}

private func deliverWorkspaceActivation(
    _ activation: WorkspaceActivation,
    to model: WindowModel?
) {
    Task { @MainActor in
        model?.adoptWorkspaceActivation(activation)
    }
}

private func deliverWorkspaceEvents(
    _ events: [UUID: WorkspaceEvent],
    to model: WindowModel?
) {
    Task { @MainActor in
        model?.receiveWorkspaceEvents(events)
    }
}

private func deliverWindowSessionPersistence(to model: WindowModel?) {
    Task { @MainActor in
        model?.persistWindowSessionNow()
    }
}

// MARK: - App State

@MainActor
final class WindowModel: ObservableObject {
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

    private struct StagedWorkspaceLibrarySelection {
        let registeredVault: RegisteredVault
        let workspace: WorkspaceVaultSlot
        let sourceScope: LibrarySourceScope
        let vaultSnapshot: WorkspaceVaultSnapshot
        let vaultConfig: VaultConfig
        let notes: [WindowDocumentLocation]
        let request: DiscoveryLibraryRequest?
    }

    private(set) var windowSessionID = UUID()
    let nativeWindowID: UUID

    // MARK: Published State
    @Published var vaultConfig: VaultConfig?
    @Published var currentRegisteredVault: RegisteredVault?
    @Published var currentVaultRole: VaultRole = .other
    @Published private(set) var libraryFocusRequestGeneration: UInt64 = 0
    @Published var triptychSettings = TriptychSettings()
    @Published private(set) var triptychPropertiesAreAuthoritative = false
    /// One-shot routing from Actions to one portable active Discussion. The
    /// document view consumes and clears it without changing record state.
    @Published var requestedDiscussionID: UUID? = nil
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
            recoverSavedSearches: { [workspaceStore] in
                try await workspaceStore.preserveUnreadableSavedSearchesAndReset()
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
            resultEvidence: { [weak self] result, scope in
                guard let self else {
                    return WindowSearchResultEvidence(
                        freshness: nil,
                        fingerprint: nil
                    )
                }
                return await self.currentSearchResultEvidence(
                    for: result,
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
                self?.presentFeedback(message, kind: .information)
            },
            reportLoadFailure: { [weak self] message in
                self?.vaultError = message
            },
            reportSaveFailure: { [weak self] message in
                self?.presentFeedback(message, kind: .error)
            },
            setAvailabilityStatus: { [weak self] status in
                guard let self else { return }
                if let status {
                    self.refreshStatusText = status
                } else if let refreshStatusText = self.refreshStatusText,
                          ["Search unavailable", "Search failed"].contains(
                              refreshStatusText
                          ) {
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
    lazy var libraryMutationController = WindowLibraryMutationController(
        dependencies: WindowLibraryMutationDependencies(
            context: { [weak self] in
                guard let self,
                      let assignment = self.workspaceAssignment,
                      let vault = self.currentRegisteredVault else { return nil }
                return WindowLibraryMutationContext(
                    assignmentID: assignment.id,
                    vault: vault,
                    sourceScope: self.noteSourceScope
                )
            },
            enqueueDocumentTransition: { [weak self] operation, didFail, didFinish in
                self?.enqueueCurrencyAwareDocumentTransition(
                    preservingCurrentEditorState: false,
                    operation,
                    didFail: didFail,
                    didFinish: didFinish
                )
            },
            flushEditors: { [weak self] triptychID in
                guard let self else { throw CancellationError() }
                try await self.editorFlushCoordinator.flushAllEditors(in: triptychID)
            },
            flushActiveTarget: { [weak self] target in
                guard let self else { throw CancellationError() }
                try await self.flushRegisteredEditorIfMutatingActiveDocument(target)
            },
            expectedRevision: { [weak self] target in
                guard let self else { throw CancellationError() }
                return try self.mutationExpectedRevision(for: target)
            },
            committedNoteCreated: { [weak self] outcome, isCurrent in
                await self?.publishCommittedNoteCreation(outcome, isCurrent: isCurrent)
            },
            committedFolderCreated: { [weak self] outcome in
                await self?.publishCommittedFolderCreation(outcome)
            },
            committedFolderMoved: { [weak self] outcome in
                await self?.publishCommittedFolderMove(outcome)
            },
            committedNoteDuplicated: { [weak self] outcome, target, destination in
                await self?.publishCommittedNoteDuplication(
                    outcome,
                    target: target,
                    destination: destination
                )
            },
            committedNoteMoved: { [weak self] outcome, target in
                await self?.publishCommittedNoteMove(outcome, target: target)
            },
            committedSystemTrash: { [weak self] preview, outcome in
                await self?.publishSystemTrashResult(preview, outcome: outcome)
            },
            importedDocumentsCommitted: { [weak self] vault in
                guard let self else { throw CancellationError() }
                try await self.refreshCachedWorkspaceVaultSnapshot(vaultID: vault.id)
                if self.currentRegisteredVault?.id == vault.id {
                    try await self.browseRegisteredVault(vault)
                }
            },
            presentImportOutcome: { [weak self] outcome in
                self?.presentMarkdownImportOutcome(outcome)
            },
            presentSystemTrash: { [weak self] preview in
                self?.presentationRouter.present(.systemTrash(preview))
            },
            presentLocalExecutionRecovery: { [weak self] recovery in
                self?.presentationRouter.alert = .localExecutionRecovery(recovery)
            },
            clearPresentedAlert: { [weak self] in
                self?.presentationRouter.alert = nil
            },
            reportError: { [weak self] message in
                self?.presentFeedback(message, kind: .error)
            },
            reportInformation: { [weak self] message in
                self?.presentFeedback(message, kind: .information)
            },
            refreshTransactionRecovery: { [weak self] in
                await self?.refreshTransactionRecoveryRecords()
            }
        )
    )
    lazy var zoteroCoordinator = WindowZoteroCoordinator(
        bridge: workspaceStore.zoteroBridge,
        dependencies: WindowZoteroDependencies(
            capability: { [weak self] in
                (
                    self?.workspaceAssignment?.id,
                    self?.windowWorkspaceController.activeCapabilities?.zoteroBindings
                )
            },
            reportInformation: { [weak self] message in
                self?.presentFeedback(message, kind: .information)
            }
        )
    )
    let documentTabController = DocumentTabController()
    let documentNavigationHistoryController = DocumentNavigationHistoryController()
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
    private let libraryTreeProjectionCache = LibraryTreeProjectionCache()
    lazy var commandObservation = WindowCommandObservation(
        shellState: shellState,
        workspaceController: windowWorkspaceController,
        libraryMutationController: libraryMutationController,
        discoveryController: discoveryController,
        documentController: documentController,
        documentNavigationHistoryController: documentNavigationHistoryController,
        workspaceProjectionController: workspaceProjectionController,
        researchActionController: researchController.actions
    )
    let attentionPresentationState = AttentionPresentationState()
    lazy var attentionPopoverSession = AttentionPopoverSession(
        presentation: attentionPresentationState,
        discoveryController: discoveryController,
        workspaceController: windowWorkspaceController,
        projectionController: workspaceProjectionController,
        dismissalDays: triptychSettings.attentionDismissalDays,
        dependencies: .init(
            dismissalDaysChanges: $triptychSettings
                .map(\.attentionDismissalDays)
                .eraseToAnyPublisher(),
            activityChanges: shellState.$researchActivityNotifications
                .eraseToAnyPublisher(),
            refresh: { [weak self] in
                await self?.refreshWorkspaceCatalog()
            },
            resynthesize: { [weak self] item in
                self?.requestResynthesis(item)
            },
            openAction: { [weak self] notification in
                guard let activity = notification.activity else { return }
                self?.openResearchActionRecovery(runIDs: [activity.runID])
            },
            endAction: { [weak self] notification in
                self?.researchController.actions.endActivity(
                    runID: notification.runID
                )
            },
            reviewResult: { [weak self] notification in
                guard let result = notification.result else { return }
                self?.presentationRouter.researchRecordsWindowRequest =
                    ResearchRecordsWindowRequest(
                        triptychID: result.triptychID,
                        initialView: .records,
                        purpose: .reviewResult,
                        recordID: result.recordID,
                        expectedFinalizedResultFingerprint:
                            result.finalizedResultFingerprint
                    )
            },
            followUp: { [weak self] notification in
                guard let result = notification.result else { return }
                self?.presentationRouter.researchRecordsWindowRequest =
                    ResearchRecordsWindowRequest(
                        triptychID: result.triptychID,
                        initialView: .records,
                        purpose: .followUp,
                        recordID: result.recordID,
                        expectedFinalizedResultFingerprint:
                            result.finalizedResultFingerprint
                    )
            },
            dismissActivity: { [weak self] notification in
                guard let self else { return }
                #if DEBUG
                if self.dismissQAActionNotificationProof(notification) {
                    return
                }
                #endif
                guard let result = notification.result else { return }
                self.researchResultNotificationDismissal?(result)
            }
        )
    )
    var researchResultNotificationDismissal:
        (@MainActor (ResearchResultReviewDestination) -> Void)?
    lazy var researchAgentPermissionWindowController =
        ResearchAgentPermissionWindowController(
            windowID: nativeWindowID,
            presentationRouter: presentationRouter,
            claimCoordinator: workspaceStore.researchAgentPermissionClaims,
            dependencies: .init(
            refreshWriteSet: { [workspaceStore] requestID, triptychID in
                try await workspaceStore.refreshResearchWriteSetExtension(
                    id: requestID,
                    in: triptychID
                )
            },
            resolveWriteSet: { [workspaceStore] triptychID, requestID, state, handles in
                try await workspaceStore.resolveResearchWriteSetExtension(
                    triptychID: triptychID,
                    requestID: requestID,
                    state: state,
                    allowedHandles: handles
                )
            },
            refreshContinuation: {
                [workspaceStore] triptychID, parentRunID, requestID in
                try await workspaceStore.refreshResearchContinuation(
                    triptychID: triptychID,
                    parentRunID: parentRunID,
                    requestID: requestID
                )
            },
            resolveContinuation: {
                [workspaceStore] triptychID, parentRunID, requestID, allow in
                try await workspaceStore.resolveResearchContinuation(
                    triptychID: triptychID,
                    parentRunID: parentRunID,
                    requestID: requestID,
                    allow: allow
                )
            }
        ),
        reportError: { [weak self] message in
            self?.presentFeedback(message, kind: .error)
        }
    )

    var sidebarVisible: Bool {
        get { shellState.libraryVisible }
        set { shellState.recordLibraryVisibility(newValue) }
    }

    var hasCompletedInitialRestore: Bool {
        shellState.hasCompletedInitialRestore
    }

    var feedbackItems: [WindowFeedback] {
        shellState.feedbackItems
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
        windowWorkspaceController.state.assignment
    }

    var registeredVaults: [RegisteredVault] {
        windowWorkspaceController.state.registeredVaults
    }

    var registeredTriptychs: [TriptychAssignment] {
        windowWorkspaceController.state.registeredTriptychs
    }

    var activeTriptychServicesID: UUID? {
        windowWorkspaceController.state.activeServicesID
    }

    var notes: [WindowDocumentLocation] { workspaceProjectionController.notes }

    func libraryTreeProjection(
        preorderedNotes: [WindowDocumentLocation],
        folderRelativePaths: [String]
    ) -> LibraryTreeProjectionVersion {
        libraryTreeProjectionCache.projection(
            preorderedNotes: preorderedNotes,
            folderRelativePaths: folderRelativePaths
        )
    }

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
    var noteSourceScope: LibrarySourceScope {
        discoveryController.library.sourceScope
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

    var selectedPropertyKey: String? {
        get { discoveryController.library.filters.propertyKey }
        set { updateDiscoveryFilters { $0.propertyKey = newValue } }
    }

    var selectedPropertyValue: String? {
        get { discoveryController.library.filters.propertyValue }
        set { updateDiscoveryFilters { $0.propertyValue = newValue } }
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

    var noteFileRequest: NoteFileRequest? {
        get {
            guard case .noteFileOperation(let request) = presentationRouter.sheet else { return nil }
            return request
        }
        set {
            if let newValue {
                presentationRouter.present(.noteFileOperation(newValue))
            } else if case .noteFileOperation = presentationRouter.sheet {
                presentationRouter.dismissSheet()
            }
        }
    }

    var folderFileRequest: FolderFileRequest? {
        get {
            guard case .folderFileOperation(let request) = presentationRouter.sheet else {
                return nil
            }
            return request
        }
        set {
            if let newValue {
                presentationRouter.present(.folderFileOperation(newValue))
            } else if case .folderFileOperation = presentationRouter.sheet {
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
            guard case .metadata(let route) = presentationRouter.sheet else { return nil }
            return route.path
        }
        set {
            if let newValue {
                presentationRouter.presentMetadata(path: newValue)
            } else if case .metadata = presentationRouter.sheet {
                presentationRouter.dismissSheet()
            }
        }
    }

    var showMetadataEditor: Bool {
        get { editingNotePath != nil }
        set {
            if newValue, let path = editingNotePath ?? currentNote?.relativePath {
                presentationRouter.presentMetadata(path: path)
            } else if !newValue, case .metadata = presentationRouter.sheet {
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
    let cssSnippetStore: CSSSnippetStore
    private var requestedTriptychID: UUID? {
        windowWorkspaceController.requestedTriptychID
    }
    private let requestedInitialDocument: VaultNoteReference?
    private var didOpenRequestedInitialDocument = false
    private var presentedOpeningRuntimeIdentity: TriptychRuntimeIdentity?
    private var projectionRefreshToken: UInt64 = 0
    private let workspaceStore: WorkspaceStore
    private let lifecyclePolicy: ScholiumLifecyclePolicy
    private let documentTransitionCoordinator = DocumentTransitionCoordinator()
    private let editorFlushCoordinator: WindowEditorFlushCoordinator
    private let windowSessionPersistenceCoordinator: WindowSessionPersistenceCoordinator
    lazy var windowCloseCoordinator = WindowCloseCoordinator(
        lifecyclePolicy: lifecyclePolicy,
        persistenceCoordinator: windowSessionPersistenceCoordinator,
        flushContent: { [weak self] in
            guard let self else {
                throw ScholiumWindowLifecycleError.unregisteredBeforeReady
            }
            try await self.flushRegisteredEditorIfNeeded()
        },
        presentationSnapshot: { [weak self] in
            guard let self,
                  self.didRestoreWindowSession,
                  !self.isRestoringWindowSession else { return nil }
            return self.currentWindowSessionSnapshot()
        },
        recordPersistenceFailure: { [weak self] message in
            guard let self else { return }
            if let message {
                self.shellState.recordWindowSessionPersistenceFailure(message)
            } else {
                self.shellState.clearWindowSessionPersistenceFailure()
            }
        },
        finalizeDependencies: { [weak self] in
            guard let self else { return }
            self.libraryMutationController.unbind()
            self.zoteroCoordinator.cancelAll()
            self.windowWorkspaceController.cancelAll()
            self.documentTransitionCoordinator.cancelAll()
            self.libraryRevealTask?.cancel()
            self.libraryRevealTask = nil
            self.editorFlushCoordinator.shutdown()
        }
    )
    let windowWorkspaceController: WindowWorkspaceController
    private var workspaceCancellables: Set<AnyCancellable> = []
    private var researchActionOpenTask: Task<Void, Never>?
    private var libraryRevealTask: Task<Void, Never>?
    private var requestedWorkspaceSelection: WorkspaceVaultSlot?
    private var researchActionOpenRequestID: UUID?
    private var discussionPresentationRequestID: UUID?
    private var isRestoringWindowSession = false
    private var didRestoreWindowSession = false
    private var identityRefreshGeneration: UInt64 = 0
    private let documentPresentationDidChange = PassthroughSubject<Void, Never>()
    private var presentResearchRecordSearchResult:
        @MainActor (RecordSearchResult) -> Void = { _ in }
    private var performanceModeNotificationTokens: [Int32] = []

    init(
        workspaceStore: WorkspaceStore,
        nativeWindowID: UUID? = nil,
        requestedTriptychID: UUID? = nil,
        requestedInitialDocument: VaultNoteReference? = nil,
        lifecyclePolicy: ScholiumLifecyclePolicy = ScholiumLifecyclePolicy(),
        finalWindowSessionSaver: WindowSessionPersistenceCoordinator.Saver? = nil
    ) {
        PerformanceProbe.shared.markWarmLibraryWindowModelInitializationStarted()
        let resolvedWindowID = nativeWindowID ?? UUID()
        self.nativeWindowID = resolvedWindowID
        windowSessionID = resolvedWindowID
        self.workspaceStore = workspaceStore
        self.lifecyclePolicy = lifecyclePolicy
        self.editorFlushCoordinator = WindowEditorFlushCoordinator(
            windowID: resolvedWindowID,
            registry: workspaceStore
        )
        self.windowSessionPersistenceCoordinator = WindowSessionPersistenceCoordinator(
            store: workspaceStore,
            lifecyclePolicy: lifecyclePolicy,
            finalSaver: finalWindowSessionSaver
        )
        self.windowWorkspaceController = WindowWorkspaceController(
            workspaceStore: workspaceStore,
            requestedTriptychID: requestedTriptychID
        )
        self.requestedInitialDocument = requestedInitialDocument
        if (requestedInitialDocument != nil
            || ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_OPEN_NOTE"] != nil)
            && !PerformanceProbe.shared.measuresEditorRetainedMemory {
            ScholiumWebKitProcessPrewarmer.shared.start()
        }
        cssSnippetStore = workspaceStore.cssSnippetStore
        windowWorkspaceController.bindDependencies(
            WindowWorkspaceDependencies(
                installSession: { [weak self] capabilities, snapshot in
                    guard let self else { throw CancellationError() }
                    return try await self.installWindowWorkspaceSession(
                        capabilities: capabilities,
                        snapshot: snapshot
                    )
                },
                didRemoveRegistration: { [weak self] assignment in
                    guard let self else { return }
                    let removedVaultIDs = Set(assignment.vaults.values.map(\.id))
                    if self.currentRegisteredVault.map({ removedVaultIDs.contains($0.id) }) == true {
                        self.currentRegisteredVault = nil
                        self.vaultConfig = nil
                    }
                },
                reportInformation: { [weak self] message in
                    self?.presentFeedback(message, kind: .information)
                }
            )
        )
        if PerformanceProbe.shared.isEnabled,
           ProcessInfo.processInfo.arguments.contains(
               "--scholium-performance-editor-mode-notifications"
           ) {
            let requests = [
                "com.scholium.qa.performance-editor-mode.live-preview",
                "com.scholium.qa.performance-editor-mode.source",
                "com.scholium.qa.performance-editor-activation",
                "com.scholium.qa.performance-editor-review",
                "com.scholium.qa.performance-editor-cached-preview",
                "com.scholium.qa.performance-editor-visible-projection",
                "com.scholium.qa.performance-editor-cjk-correctness",
            ]
            for name in requests {
                var token: Int32 = 0
                let status = notify_register_dispatch(name, &token, .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.handlePerformanceEditorRequest(name)
                    }
                }
                if status == NOTIFY_STATUS_OK {
                    performanceModeNotificationTokens.append(token)
                }
            }
        }
        searchController.loadSavedSearches()
        startWorkspaceObservers()
    }

    private func startWorkspaceObservers() {
        let relay = WindowModelObserverRelay(model: self)
        let activationHandler: @Sendable (WorkspaceActivation) -> Void = { activation in
            deliverWorkspaceActivation(activation, to: relay.model)
        }
        workspaceStore.$latestWorkspaceActivation
            .compactMap(nonisolatedWorkspaceActivation)
            .sink(receiveValue: activationHandler)
            .store(in: &workspaceCancellables)

        let workspaceEventsHandler: @Sendable ([UUID: WorkspaceEvent]) -> Void = { events in
            deliverWorkspaceEvents(events, to: relay.model)
        }
        workspaceStore.$workspaceEvents
            .sink(receiveValue: workspaceEventsHandler)
            .store(in: &workspaceCancellables)

        observeWindowSessionChanges()
    }

    func bindResearchRecordSearchPresentation(
        _ present: @escaping @MainActor (RecordSearchResult) -> Void
    ) {
        presentResearchRecordSearchResult = present
    }

    deinit {
        researchActionOpenTask?.cancel()
        libraryRevealTask?.cancel()
        for token in performanceModeNotificationTokens {
            notify_cancel(token)
        }
    }

    // MARK: Computed Properties
    private(set) var sourceMutationGeneration: UInt64 {
        get { documentController.sourceMutationGeneration }
        set { documentController.sourceMutationGeneration = newValue }
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

    var transactionRecoveryRecords: [TriptychMutationRecoveryRecord] {
        get { researchController.transactionRecoveryRecords }
        set { researchController.transactionRecoveryRecords = newValue }
    }

    var transactionRecoveryError: String? {
        get { researchController.transactionRecoveryError }
        set { researchController.transactionRecoveryError = newValue }
    }

    var interruptedSaveRecoveries: [InterruptedSaveRecovery] {
        get { researchController.interruptedSaveRecoveries }
        set { researchController.interruptedSaveRecoveries = newValue }
    }

    var interruptedSaveRecoveryError: String? {
        get { researchController.interruptedSaveRecoveryError }
        set { researchController.interruptedSaveRecoveryError = newValue }
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
        guard noteSourceScope == .library,
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
        guard currentNote != nil else { return .other }
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
            .map(WindowDocumentLocation.workspace)
            .sorted(by: notesAreOrdered)
    }

    var currentLibraryFolders: [String] {
        guard let vaultID = currentRegisteredVault?.id,
              let snapshot = workspaceProjectionController.vaultSnapshot(
                  id: vaultID
              ) else { return [] }
        return snapshot.folders
            .map(\.rawValue)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var currentLibraryPathComparisonPolicy: VaultPathComparisonPolicy? {
        guard let vaultID = currentRegisteredVault?.id else { return nil }
        return workspaceProjectionController
            .vaultSnapshot(id: vaultID)?
            .pathComparisonPolicy
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

    var currentResearchActionTarget: ResearchActionNoteSnapshot? {
        guard let descriptor = currentDocumentDescriptor,
              let note = currentNote,
              note.workspaceSnapshot?.derivedProjectionState == .current,
              currentDocumentCapabilities.canUseResearchActions,
              let role = ResearchActionTargetRole(vaultRole: descriptor.reference.vaultRole) else {
            return nil
        }
        return ResearchActionNoteSnapshot(
            noteID: descriptor.sessionKey.noteID,
            note: VaultQualifiedNoteID(
                vaultID: descriptor.reference.vaultID,
                relativePath: note.relativePath
            ),
            role: role,
            fingerprint: note.document.fingerprint,
            title: note.title ?? note.displayName
        )
    }

    var hasConfirmedCurrentResearchActionAvailability: Bool {
        guard let target = currentResearchActionTarget else { return false }
        let actions = researchController.actions
        return actions.availabilityTarget == target
            && !actions.isRefreshingAvailability
            && actions.availabilityError == nil
    }

    var currentResearchActionReference: VaultNoteReference? {
        currentDocumentDescriptor?.reference
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
            endingActivityRunIDs:
                researchController.actions.endingActivityRunIDs,
            activeDiscussions: researchController.records?.activeDiscussions ?? [],
            settlements: researchController.records?.settlements ?? [],
            activities: researchController.records?.activities ?? []
        )
    }

    func refreshResearchActionAvailability() async {
        let target = currentResearchActionTarget
        researchController.setActiveDocument(currentResearchActionReference)
        researchController.actions.invalidateIfTargetChanged(target)
        reconcileResearchActionPresentation()
        await researchController.actions.refreshAvailability(for: target)
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
        guard currentNote != nil else {
            return DocumentCapabilities(
                role: currentDocumentVaultRole,
                identity: .unresolved,
                isManagedCritique: false
            )
        }
        return DocumentCapabilities(
            role: currentDocumentVaultRole,
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
            let outcome = try await documentController.resolveIdentity(
                ambiguity,
                candidateID: candidateID
            )
            selectedIdentityAmbiguity = nil
            await refreshIdentityState()
            reportCommittedMutationWarnings(outcome)
        } catch {
            identityResolutionError = error.localizedDescription
            try? await refreshLibrarySourceScope()
            if let refreshed = identityAmbiguity(for: ambiguity.relativePath) {
                selectedIdentityAmbiguity = refreshed
            }
        }
    }

    func retryIdentityRecovery() async {
        do {
            try await refreshLibrarySourceScope()
        } catch {
            identityResolutionError = error.localizedDescription
        }
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
    /// by the mutation route, never those of the Library's browsed hierarchy.
    private func mutationExpectedRevision(
        for target: NoteMutationTarget
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

    private func flushRegisteredEditorIfMutatingActiveDocument(
        _ target: NoteMutationTarget
    ) async throws {
        guard let descriptor = currentDocumentDescriptor,
              descriptor.reference.vaultID == target.documentID.vaultID,
              descriptor.reference.relativePath == target.relativePath,
              descriptor.sessionKey.noteID == target.stableNoteID else { return }
        try await flushRegisteredEditorIfNeeded()
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
                    self.presentFeedback(navigationError.localizedDescription, kind: .warning)
                } else {
                    self.lastSaveError = error.localizedDescription
                    self.presentFeedback(
                        String(
                            localized: "The current note could not be saved, so Scholium kept it open. \(error.localizedDescription)",
                            table: "Localizable",
                            bundle: .module
                        ),
                        kind: .error
                    )
                }
            },
            didSucceed: { didSucceed?() },
            didFinish: { didFinish?() }
        )
    }

    private func enqueueCurrencyAwareDocumentTransition(
        preservingCurrentEditorState: Bool = true,
        _ operation: @escaping @MainActor (
            DocumentTransitionCoordinator.Currency
        ) async throws -> Void,
        didFail customFailure: (@MainActor (Error) -> Void)? = nil,
        didSucceed: (@MainActor () -> Void)? = nil,
        didFinish: (@MainActor () -> Void)? = nil
    ) {
        documentTransitionCoordinator.enqueueCurrencyAware(
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
                    self.presentFeedback(
                        navigationError.localizedDescription,
                        kind: .warning
                    )
                } else {
                    self.lastSaveError = error.localizedDescription
                    self.presentFeedback(
                        String(
                            localized: "The current note could not be saved, so Scholium kept it open. \(error.localizedDescription)",
                            table: "Localizable",
                            bundle: .module
                        ),
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
            guard currentResearchActionReference == route.target,
                  researchController.actions.presentationID == route.presentationID,
                  researchController.actions.activeActionID == route.actionID else { return }
            presentationRouter.present(.researchAction(route))
        case .presentNoteFileOperation(let request):
            noteFileRequest = request
        }
    }

    private func openSearchSelection(
        _ result: SearchResultSelection,
        disposition: WindowOpenDisposition
    ) async {
        switch result {
        case .result(.note(let note)):
            let reference = VaultNoteReference(
                vaultID: note.vaultID,
                vaultName: note.vaultName,
                vaultRole: note.vaultRole,
                relativePath: note.relativePath,
                stableNoteID: note.stableNoteID
            )
            if disposition == .newTab {
                requestOpenNote(reference, disposition: .newTab)
            } else {
                openWorkspaceReference(
                    reference,
                    sourceRange: note.sourceRange,
                    fallbackLine: note.sourceLine
                )
            }
        case .result(.record(let record)):
            presentResearchRecordSearchResult(record)
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
            presentFeedback(String(localized: "The selected vault is no longer available.", table: "Localizable", bundle: .module), kind: .warning)
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
            try await self.activateWorkspaceReference(
                reference,
                tabActivation: .place(.replaceSelected)
            )
        }
    }

    /// Opens the common Synthesize sheet for one exact, derived
    /// Topic/Analysis revision condition. Preparation remains fail-closed at
    /// the Application boundary if either source or record changed meanwhile.
    func requestResynthesis(_ item: AttentionQueueItem) {
        guard item.kind == .synthesisMaterialChanged,
              let context = item.synthesisMaterialChanged else { return }
        enqueueDocumentTransition(preservingCurrentEditorState: false, { [weak self] in
            guard let self else { return }
            try await self.activateWorkspaceReference(
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
            self?.presentFeedback(error.localizedDescription, kind: .warning)
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
            presentFeedback(
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
            try await self.activateWorkspaceReference(
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

    func requestTriptychWorkspace(_ slot: WorkspaceVaultSlot) {
        let destination = discoveryController.libraryState(for: slot)
        guard requestedWorkspaceSelection != slot,
              shellState.selectedWorkspace != slot
                || requestedWorkspaceSelection != nil
                || destination.sourceError != nil else { return }
        requestedWorkspaceSelection = slot
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            let targetTab = self.documentTabController.selectedTab(in: slot)
            try await self.prepareWorkspaceSelection(
                slot,
                sourceScope: destination.sourceScope,
                validateDestination: {
                    guard self.requestedWorkspaceSelection == slot else {
                        throw CancellationError()
                    }
                    if let targetDocument = targetTab?.document {
                        try self.validateDocumentIsAvailable(targetDocument)
                    }
                }
            )
            if let targetDocument = targetTab?.document {
                try self.activateDocumentInSelectedWorkspace(
                    targetDocument,
                    tabActivation: .preserveTabMembership
                )
            } else {
                self.documentController.clearSelectionAfterClosingLastTab()
            }
            self.reconcileDocumentSessionLeases()
        } didFinish: { [weak self] in
            guard self?.requestedWorkspaceSelection == slot else { return }
            self?.requestedWorkspaceSelection = nil
        }
    }

    func requestLibrarySourceScope(_ scope: LibrarySourceScope) {
        Task { [weak self] in await self?.selectLibrarySourceScope(scope) }
    }

    func requestDocumentMode(_ mode: NotePresentationMode) {
        guard mode == .read || canEditCurrentNote else {
            presentFeedback(String(localized: "This note is read-only in Scholium.", table: "Localizable", bundle: .module), kind: .information)
            return
        }
        requestPresentationMode = mode
    }

    /// Drives the retained-editor performance scenario through the current
    /// document session instead of a one-shot SwiftUI presentation request.
    /// The editor bridge still performs the real mode transition and reports
    /// readiness only after CodeMirror acknowledges it.
    private func requestPerformanceEditorMode(_ mode: NotePresentationMode) {
        guard PerformanceProbe.shared.isEnabled,
              ProcessInfo.processInfo.arguments.contains(
                  "--scholium-performance-editor-mode-notifications"
              ),
              mode != .read,
              canEditCurrentNote,
              let descriptor = currentDocumentDescriptor else { return }

        // The CJK correctness journey is not a latency measurement. Route it
        // through the same presentation-intent owner as the researcher menu so
        // it verifies the complete retained-editor transition without making
        // XCUITest traverse a system submenu while a 100k document is active.
        if PerformanceProbe.shared.exercisesLargeCJKCorrectness {
            requestDocumentMode(mode)
            return
        }

        let session = documentController.session(for: descriptor)
        guard session.isEditing, session.editorSession.isLoaded else {
            requestDocumentMode(mode)
            return
        }
        guard session.editorSession.context?.composing != true else { return }

        guard let editorMode = mode.editorMode else { return }
        PerformanceProbe.shared.beginEditorModeTransition(
            documentID: descriptor.reference.relativePath,
            mode: editorMode
        )
        session.switchEditorMode(to: editorMode)
        documentController.rememberPresentationMode(mode)
    }

    private func handlePerformanceEditorRequest(_ name: String) {
        switch name {
        case "com.scholium.qa.performance-editor-mode.live-preview":
            requestPerformanceEditorMode(.livePreview)
        case "com.scholium.qa.performance-editor-mode.source":
            requestPerformanceEditorMode(.source)
        case "com.scholium.qa.performance-editor-activation":
            requestPerformanceEditActivation()
        case "com.scholium.qa.performance-editor-review":
            if currentNote == nil {
                // First-use Review is measured from the Library click. Arm
                // the workspace's presentation intent before a document
                // exists so setup does not create an unmeasured Editor.
                documentController.rememberPresentationMode(.read)
            } else {
                requestDocumentMode(.read)
            }
        case "com.scholium.qa.performance-editor-cached-preview":
            requestPerformanceCachedPreview()
        case "com.scholium.qa.performance-editor-visible-projection":
            guard let descriptor = currentDocumentDescriptor else { return }
            documentController.session(for: descriptor)
                .editorSession.measureVisibleProjection()
        case "com.scholium.qa.performance-editor-cjk-correctness":
            guard PerformanceProbe.shared.exercisesLargeCJKCorrectness,
                  let descriptor = currentDocumentDescriptor else { return }
            let session = documentController.session(for: descriptor)
            PerformanceProbe.shared.recordLargeCJKCorrectness(
                documentID: descriptor.reference.relativePath,
                source: session.editingSource
            )
        default:
            return
        }
    }

    private func requestPerformanceEditActivation() {
        guard canEditCurrentNote,
              let descriptor = currentDocumentDescriptor else { return }
        let session = documentController.session(for: descriptor)
        guard !session.isEditing else { return }
        PerformanceProbe.shared.beginEditActivation(
            documentID: descriptor.reference.relativePath
        )
        requestDocumentMode(.livePreview)
    }

    private func requestPerformanceCachedPreview() {
        guard let descriptor = currentDocumentDescriptor else { return }
        let session = documentController.session(for: descriptor)
        guard session.isEditing else { return }
        Task { @MainActor in
            for _ in 0..<200 {
                guard currentDocumentDescriptor?.sessionKey == descriptor.sessionKey,
                      session.isEditing else { return }
                if let preview = session.previewCatalog?.links.first {
                    await session.editorSession.showPreview(
                        for: preview,
                        in: session.editingSource
                    )
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    func openResearchAction(
        _ actionID: ResearchActionID,
        selection: CommentAnchor? = nil,
        initialMaterialNoteIDs: Set<UUID> = [],
        resynthesisContext: SynthesisMaterialChangedAttentionContext? = nil
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
            presentFeedback(
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
                      let reference = self.currentResearchActionReference else { return }
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
                    self.presentFeedback(reason, kind: .information)
                    return
                }
                let capturedSelection: CommentAnchor?
                if let selection, selection.fingerprint == target.fingerprint {
                    capturedSelection = selection
                } else {
                    capturedSelection = nil
                    if selection != nil {
                        self.presentFeedback(
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
                    self.presentFeedback(
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
                self.presentFeedback(
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

    func openResearchActionStatus(
        _ activity: WorkspaceResearchActivity
    ) {
        guard let target = currentResearchActionTarget,
              target.noteID == activity.targetNoteID,
              let reference = currentResearchActionReference,
              !researchController.actions.hasCancellationBarrier else { return }
        let availability = researchController.actions.availability.first {
            $0.id == activity.actionID
        }
        let presentationID = UUID()
        guard researchController.actions.beginStatus(
            target: target,
            availability: availability,
            activity: activity,
            presentationID: presentationID
        ) else { return }
        researchController.requestPresentAction(
            activity.actionID,
            target: reference,
            presentationID: presentationID
        )
    }

    /// Routes a blocked file operation to the existing Action status surface.
    /// The Run identity remains an internal lookup key; the researcher sees
    /// the participating Note and the one executable recovery path.
    func openResearchActionRecovery(runIDs: [UUID]) {
        let requestedRunIDs = Set(runIDs)
        let activities = researchController.records?.activities.filter {
            requestedRunIDs.contains($0.runID)
        } ?? []
        guard let activity = ResearchActionActivityPresentation.make(
            activities: activities
        )?.primary else {
            presentFeedback(
                TriptychTransactionError.activeResearchActions(runIDs)
                    .localizedDescription,
                kind: .warning
            )
            return
        }
        if currentResearchActionTarget?.noteID == activity.targetNoteID {
            openResearchActionStatus(activity)
            return
        }
        guard let reference = workspaceCatalog?.notes.first(where: {
            $0.reference.stableNoteID.flatMap(UUID.init(uuidString:))
                == activity.targetNoteID
        })?.reference else {
            presentFeedback(
                String(
                    localized: "Open the participating Note, then choose its active Action to continue recovery.",
                    table: "Localizable",
                    bundle: .module
                ),
                kind: .warning
            )
            return
        }
        enqueueDocumentTransition(
            preservingCurrentEditorState: false,
            { [weak self] in
                guard let self else { return }
                try await self.activateWorkspaceReference(
                    reference,
                    tabActivation: .place(.replaceSelected)
                )
                guard let target = self.currentResearchActionTarget,
                      target.noteID == activity.targetNoteID else {
                    throw WindowNavigationError.noteUnavailable(
                        reference.relativePath
                    )
                }
                await self.researchController.actions.refreshAvailability(
                    for: target
                )
            },
            didSucceed: { [weak self] in
                self?.openResearchActionStatus(activity)
            }
        )
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
        case .opening, .current, .none:
            false
        }
    }

    func retryDerivedRefresh() async {
        _ = await refreshWorkspaceProjection(
            refreshingStatus: "Retrying Triptych refresh…"
        )
    }

    func refreshAfterResearchHandoff() async -> WorkspaceSnapshot? {
        await refreshWorkspaceProjection(refreshingStatus: nil)
    }

    private func refreshWorkspaceProjection(
        refreshingStatus: String?
    ) async -> WorkspaceSnapshot? {
        guard let vaultID = currentRegisteredVault?.id else { return nil }
        if let refreshingStatus { refreshStatusText = refreshingStatus }
        do {
            let snapshot = try await discoveryController.refreshWorkspace()
            guard currentRegisteredVault?.id == vaultID,
                  let capabilities = windowWorkspaceController.activeCapabilities,
                  let commit = workspaceProjectionController.replaceSnapshot(
                      snapshot,
                      runtimeIdentity: capabilities.runtimeIdentity,
                      status: .current(WorkspaceDerivedRefreshEvidence(snapshot: snapshot)),
                      context: workspaceProjectionContext
                  ) else { return nil }
            applyWorkspaceProjectionCommit(commit)
            refreshStatusText = nil
            workspaceProjectionController.reportCatalogError(nil)
            return snapshot
        } catch {
            refreshStatusText = "Triptych refresh failed"
            workspaceProjectionController.reportCatalogError(error.localizedDescription)
            return nil
        }
    }

    var filteredNotes: [WindowDocumentLocation] {
        var result = notes
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
        if let key = selectedPropertyKey, let value = selectedPropertyValue {
            let catalog = workspaceProjectionController.metadataCatalog
            result = result.filter {
                $0.semanticProperty(at: key, catalog: catalog)?
                    .appFilterValues.contains(value) == true
            }
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
        switch discoveryController.library.sortOrder {
        case .modifiedNewest:
            if lhs.fileModifiedAt != rhs.fileModifiedAt { return lhs.fileModifiedAt > rhs.fileModifiedAt }
        case .modifiedOldest:
            if lhs.fileModifiedAt != rhs.fileModifiedAt { return lhs.fileModifiedAt < rhs.fileModifiedAt }
        case .titleAscending:
            return lhs.displayName.localizedStandardCompare(
                rhs.displayName
            ) == .orderedAscending
        case .titleDescending:
            return lhs.displayName.localizedStandardCompare(
                rhs.displayName
            ) == .orderedDescending
        }
        return lhs.displayName.localizedStandardCompare(
            rhs.displayName
        ) == .orderedAscending
    }

    var availableAuthors: [String] {
        workspaceProjectionController.authors
    }

    var activeMetadataFilterCount: Int {
        [
            selectedAuthor != nil,
            selectedPropertyKey != nil && selectedPropertyValue != nil,
        ].count(where: { $0 })
    }

    func clearMetadataFilters() {
        selectedAuthor = nil
        selectedPropertyKey = nil
        selectedPropertyValue = nil
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
            try await self.activateWorkspaceReference(
                reference,
                tabActivation: .place(.newTab)
            )
        }
    }

    func selectDocumentTab(withID id: UUID) {
        let workspace = shellState.selectedWorkspace
        guard documentTabController.selectedTabID(in: workspace) != id,
              let tab = documentTabController.tabs(in: workspace).first(where: {
                  $0.id == id
              }) else {
            return
        }
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            try await self.activateDocument(
                tab.document,
                tabActivation: .preserveTabMembership
            )
            self.documentTabController.selectTab(withID: id)
            self.reconcileDocumentSessionLeases()
        }
    }

    func navigateDocumentHistory(_ direction: DocumentNavigationDirection) {
        enqueueDocumentTransition { [weak self] in
            guard let self,
                  let target = self.documentNavigationHistoryController.target(
                      for: direction
                  ) else { return }
            try await self.activateDocument(
                target,
                tabActivation: .place(.replaceSelected),
                recordsNavigationHistory: false
            )
            self.documentNavigationHistoryController.commit(direction, to: target)
        }
    }

    func closeDocumentTab(withID id: UUID) {
        guard let plan = documentTabController.closePlan(forTabWithID: id) else {
            return
        }
        guard plan.workspace == shellState.selectedWorkspace,
              let closingDocument = documentTabController.tabs(in: plan.workspace)
                .first(where: { $0.id == id })?.document else {
            return
        }
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            try await self.documentController.flushBeforeClosing(closingDocument)
            if let documentToActivate = plan.documentToActivate {
                try await self.activateDocument(
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

    var currentPresentationMode: NotePresentationMode {
        documentController.currentPresentationMode
    }

    /// The workspace retains its desired mode across Notes, while chrome must
    /// report the mode the selected session is actually presenting. This keeps
    /// read-only and managed Critique documents truthfully in Review
    /// without changing the workspace's retained Edit selection.
    var presentedDocumentMode: NotePresentationMode {
        guard currentNote != nil else { return currentPresentationMode }
        return documentController.chromeProjection.mode
    }

    func rememberPresentationMode(_ mode: NotePresentationMode) {
        documentController.rememberPresentationMode(mode)
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
            stored = try await windowSessionPersistenceCoordinator.load(id: id)
        } catch {
            presentFeedback(String(localized: "The saved window layout could not be restored. Scholium opened a clean window instead.", table: "Localizable", bundle: .module), kind: .warning)
            stored = nil
        }
        guard let stored else {
            // New configured windows keep the stable three-region shell.
            // Visibility changes only after a direct researcher action.
            shellState.restoreLibraryVisibility(true)
            researchController.restoreInspector(
                modesByWorkspace: [:],
                isVisible: nil
            )
            await restoreWorkspaceIfNeeded()
            return
        }

        if ScholiumRuntimeIsolation.fixtureRootURL() != nil {
            // A disposable QA fixture is reconstructed from its explicit root
            // on every process launch. Its saved window presentation is still
            // real, but it cannot authorize restoration before that isolated
            // workspace has installed its current capabilities and document
            // projection in this process.
            await restoreWorkspaceIfNeeded()
        } else {
            await windowWorkspaceController.refreshRegistrations()
            await refreshWorkspaceAssignment(
                preferredTriptychID: requestedTriptychID ?? stored.triptychID
            )
        }
        guard let restoredAssignment = workspaceAssignment else {
            windowWorkspaceController.markInitialRestoreAttempted()
            return
        }
        let requestedWorkspace = requestedInitialDocument.flatMap { requested in
            WorkspaceVaultSlot.allCases.first { workspace in
                restoredAssignment.vault(for: workspace)?.id == requested.vaultID
            }
        }
        let selectedWorkspace = requestedWorkspace ?? stored.selectedWorkspace
        do {
            guard let vault = restoredAssignment.vault(for: selectedWorkspace) else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            windowWorkspaceController.markInitialRestoreAttempted()
            try await openRegisteredVault(vault)
        } catch {
            vaultError = error.localizedDescription
            return
        }

        let availablePathsByVault = Dictionary(uniqueKeysWithValues:
            restoredAssignment.vaults.values.map { vault in
                (
                    vault.id,
                    Set(
                        workspaceProjectionController.vaultSnapshot(id: vault.id)?
                            .documents.map(\.id.relativePath) ?? []
                    )
                )
            }
        )
        let restoredPresentation = stored.normalized(
            availablePathsByVault: availablePathsByVault
        )

        for workspace in WorkspaceVaultSlot.allCases {
            guard let session = restoredPresentation.workspaceSession(for: workspace) else {
                continue
            }
            discoveryController.synchronizeLibrarySelection(
                workspaceSlot: workspace,
                sourceScope: .library
            )
            if let vaultID = session.vaultID {
                documentController.restorePresentationState(
                    scrollPositions: session.scrollPositions,
                    vaultID: vaultID
                )
            }
        }
        let inspectorModes = Dictionary(uniqueKeysWithValues:
            WorkspaceVaultSlot.allCases.map { workspace in
                (
                    workspace,
                    restoredPresentation.workspaceSession(for: workspace)?
                        .inspectorMode ?? "overview"
                )
            }
        )
        let documentModes = Dictionary(uniqueKeysWithValues:
            WorkspaceVaultSlot.allCases.map { workspace in
                (
                    workspace,
                    restoredPresentation.workspaceSession(for: workspace)
                        .flatMap { NotePresentationMode(rawValue: $0.documentMode) }
                        ?? .read
                )
            }
        )
        shellState.selectWorkspace(selectedWorkspace)
        documentController.selectWorkspace(selectedWorkspace)
        documentController.restorePresentationModes(documentModes)
        researchController.restoreInspector(
            modesByWorkspace: inspectorModes,
            isVisible: restoredPresentation.inspectorVisible
        )

        reconcileDocumentSessionLeases()

        shellState.restoreLibraryVisibility(
            restoredPresentation.libraryVisible ?? true
        )
        discoveryController.replaceSearchCriteria(SearchWorkspaceState(
            scope: restoredPresentation.searchState.scope
        ))
        shellState.setDocumentTextScale(
            restoredPresentation.documentTextScale
                ?? ScholiumMetrics.Document.defaultTextScale
        )
        if ScholiumRuntimeIsolation.fixtureRootURL() != nil {
            // The stored presentation contains no editor bytes, but it does
            // retain the selected committed document for each window. Restore
            // that identity before falling back to the launch-only QA note so
            // multiple fixture windows do not all converge on the same note.
            if let selected = restoredPresentation
                .workspaceSession(for: selectedWorkspace)?.selectedDocument,
               selected.vaultID == restoredAssignment.vault(for: selectedWorkspace)?.id {
                openNote(selected.relativePath)
            } else {
                openRequestedTestNoteIfNeeded()
            }
        }
    }

    func persistWindowSessionNow() {
        guard didRestoreWindowSession,
              !isRestoringWindowSession,
              !windowSessionPersistenceCoordinator.isFinalizing,
              !windowSessionPersistenceCoordinator.isClosed else { return }
        let snapshot = currentWindowSessionSnapshot()
        windowSessionPersistenceCoordinator.schedule(
            snapshot: snapshot,
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

    private func currentWindowSessionSnapshot() -> WindowSessionSnapshot {
        let workspaceSessions = WorkspaceVaultSlot.allCases.map { workspace in
            let vaultID = workspaceAssignment?.vault(for: workspace)?.id
            let tabs = documentTabController.tabs(in: workspace)
            return WindowWorkspaceSessionSnapshot(
                workspace: workspace,
                vaultID: vaultID,
                openDocuments: tabs.compactMap { vaultQualifiedID(for: $0.document) },
                selectedDocument: documentTabController.selectedTab(in: workspace)
                    .flatMap { vaultQualifiedID(for: $0.document) },
                scrollPositions: documentController.presentationSnapshot(
                    vaultID: vaultID
                ).scrollPositions,
                inspectorMode: shellState.inspectorMode(for: workspace).rawValue,
                documentMode: documentController.presentationMode(for: workspace).rawValue
            )
        }
        return WindowSessionSnapshot(
            id: windowSessionID,
            triptychID: workspaceAssignment?.id,
            selectedWorkspace: shellState.selectedWorkspace,
            workspaceSessions: workspaceSessions,
            libraryVisible: sidebarVisible,
            inspectorVisible: researchInspectorVisible,
            searchState: SearchWorkspaceState(scope: searchController.ordinaryScope),
            documentTextScale: documentTextScale
        )
    }

    private func observeWindowSessionChanges() {
        let stateChanges: [AnyPublisher<Void, Never>] = [
            windowWorkspaceController.$state
                .map(nonisolatedWorkspaceAssignmentID)
                .removeDuplicates()
                .map(nonisolatedDiscardPublisherValue)
                .eraseToAnyPublisher(),
            $currentRegisteredVault.map(nonisolatedDiscardPublisherValue).eraseToAnyPublisher(),
            documentController.$selectedDocument
                .map(nonisolatedDiscardPublisherValue)
                .eraseToAnyPublisher(),
            documentController.$currentPresentationMode
                .map(nonisolatedDiscardPublisherValue)
                .eraseToAnyPublisher(),
            shellState.$libraryVisible
                .map(nonisolatedDiscardPublisherValue)
                .eraseToAnyPublisher(),
            shellState.$documentTextScale
                .map(nonisolatedDiscardPublisherValue)
                .eraseToAnyPublisher(),
            shellState.$selectedWorkspace
                .map(nonisolatedDiscardPublisherValue)
                .eraseToAnyPublisher(),
            shellState.$inspector
                .map(nonisolatedDiscardPublisherValue)
                .eraseToAnyPublisher(),
            discoveryController.$search
                .map(nonisolatedDiscardPublisherValue)
                .eraseToAnyPublisher(),
        ]
        var changes: [AnyPublisher<Void, Never>] = []
        changes.reserveCapacity(stateChanges.count + 3)
        for stateChange in stateChanges {
            changes.append(stateChange.dropFirst().eraseToAnyPublisher())
        }
        changes.append(contentsOf: [
            documentTabController.objectWillChange.eraseToAnyPublisher(),
            discoveryController.objectWillChange.eraseToAnyPublisher(),
            documentPresentationDidChange.eraseToAnyPublisher(),
        ])
        let relay = WindowModelObserverRelay(model: self)
        let persistenceHandler: @Sendable () -> Void = {
            deliverWindowSessionPersistence(to: relay.model)
        }
        Publishers.MergeMany(changes)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink(receiveValue: persistenceHandler)
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
        let outcome = await windowWorkspaceController.refreshWorkspaceAssignment(
            preferredTriptychID: preferredTriptychID,
            openingVault: shellState.selectedWorkspace
        )
        switch outcome {
        case .unavailable, .activated:
            break
        case .recoveryRequired:
            vaultError = nil
        case .failed(let message):
            vaultError = message
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
        let openingVault = requestedInitialWorkspaceSlot
        let assignment = try await windowWorkspaceController.configureTriptych(
            paperAnalysisURL: paperAnalysisURL,
            topicKnowledgeURL: topicKnowledgeURL,
            outputURL: outputURL,
            portableContainerURL: portableContainerURL,
            triptychID: triptychID,
            triptychName: triptychName,
            openingVault: openingVault
        )
        PerformanceProbe.shared.markWarmLibraryWorkspaceReady()
        if let current = currentRegisteredVault,
           let assignedCurrent = assignment.vaults.values.first(where: {
               $0.id == current.id || $0.canonicalPath == current.canonicalPath
           }) {
            currentRegisteredVault = assignedCurrent
            currentVaultRole = assignedCurrent.role
            return
        }
        try await openWorkspaceVault(openingVault)
    }

    var requestedTriptychIDForRecovery: UUID? { requestedTriptychID }

    private func installWindowWorkspaceSession(
        capabilities: WindowWorkspaceCapabilities,
        snapshot: WorkspaceSnapshot
    ) async throws -> [String] {
        triptychPropertiesAreAuthoritative = false
        bindApplicationCapabilities(
            to: capabilities,
            snapshot: snapshot
        )
        var activationIssues = snapshot.research.healthIssues
        if let settingsIssue = try await loadTriptychSettingsProjection() {
            activationIssues.append(settingsIssue)
        }
        if !activationIssues.isEmpty {
            vaultError = ([
                "Some Scholium research history could not be loaded. The affected files remain unchanged and edits to those records are blocked.",
            ] + activationIssues).joined(separator: "\n\n")
        }
        let recoveryIssues = try await libraryMutationController.recoverInterruptedTransactions()
        await refreshTransactionRecoveryRecords()
        PerformanceProbe.shared.markStartupSafetyReady()
        return recoveryIssues
    }

    private func loadTriptychSettingsProjection() async throws -> String? {
        let state = try await researchController.settingsLoadState()
        triptychPropertiesAreAuthoritative = state.authorizesAboutProjection
        switch state {
        case .current(let snapshot):
            triptychSettings = snapshot.settings
            return nil
        case .needsReview(let settings, _, let reason):
            triptychSettings = settings
            return TriptychControlError.settingsNeedsReview(reason).localizedDescription
        case .missing:
            triptychSettings = TriptychSettings()
            return TriptychControlError.settingsMissing.localizedDescription
        case .oldSchema(let version):
            triptychSettings = TriptychSettings()
            return TriptychControlError.settingsOldSchema(version).localizedDescription
        case .futureSchema(let version):
            triptychSettings = TriptychSettings()
            return TriptychControlError.settingsFutureSchema(version).localizedDescription
        case .corrupted:
            triptychSettings = TriptychSettings()
            return TriptychControlError.settingsCorrupted.localizedDescription
        }
    }

    private func bindApplicationCapabilities(
        to capabilities: WindowWorkspaceCapabilities,
        snapshot: WorkspaceSnapshot? = nil
    ) {
        discoveryController.bind(to: capabilities.discovery)
        libraryMutationController.bind(to: capabilities.libraryMutations)
        documentController.bind(
            to: capabilities.documents,
            snapshot: snapshot,
            documentDidCommit: { [weak self] result in
                guard let self else { return }
                _ = await self.replaceSavedDocument(result.document)
            }
        )
        researchController.bind(
            to: ResearchControllerCapabilities(
                documents: capabilities.documents,
                records: capabilities.research.records,
                actions: capabilities.research.actions,
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
                    for: target
                )
            },
            bindLocalSource: { target, url in
                try await capabilities.research.sourceAccess.bindSourceAccess(
                    ResearchSourceBindingRequest(
                        target: target,
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
            prepareFollowUp: { request in
                try await capabilities.research.actions.prepareFollowUp(request)
            },
            actionRun: { runID in
                try await capabilities.research.actions.actionRun(id: runID)
            },
            handoff: { runID in
                try await capabilities.research.actions.issueAgentHandoff(
                    runID: runID,
                    validity: 10 * 60
                )
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
        reconcileResearchActionPresentation()
    }

    fileprivate func adoptWorkspaceActivation(_ activation: WorkspaceActivation) {
        guard let replacement = windowWorkspaceController.adopt(activation) else { return }
        PerformanceProbe.shared.markWarmLibraryWorkspaceReady()

        let previousAssignment = replacement.previousAssignment
        let previousVault = currentRegisteredVault
        bindApplicationCapabilities(
            to: activation.capabilities,
            snapshot: activation.snapshot
        )
        editorFlushCoordinator.activateTriptych(activation.workspaceID) { [weak self] in
            guard let self else { return }
            try await self.documentController.flushLeasedOrPinnedSessions()
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
        if currentRegisteredVault != nil {
            PerformanceProbe.shared.markWarmLibraryProjectionReady()
        }
        researchAgentPermissionWindowController.refreshForWorkspaceSnapshot(
            triptychID: activation.snapshot.triptych.id
        )
    }

    var currentWorkspaceSlot: WorkspaceVaultSlot? {
        let selected = shellState.selectedWorkspace
        return workspaceAssignment?.vault(for: selected) == nil ? nil : selected
    }

    var currentDocumentAboutConfiguration: VaultAboutConfiguration? {
        guard let vault = currentDocumentVault,
              let slot = WorkspaceVaultSlot.allCases.first(where: {
                  workspaceAssignment?.vault(for: $0)?.id == vault.id
              }) else { return nil }
        return WorkspaceAboutConfiguration.configuration(
            settings: triptychSettings,
            slot: slot,
            isAuthoritative: triptychPropertiesAreAuthoritative
        )
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

    func presentMarkdownImportOutcome(_ outcome: WindowMarkdownImportBatchOutcome) {
        let failureDetails = outcome.failures
            .map { "\($0.sourceName): \($0.reason)" }
            .joined(separator: " ")

        guard !outcome.documents.isEmpty else {
            let summary = String(
                localized: "No Markdown files were imported.",
                table: "Localizable",
                bundle: .module
            )
            vaultError = failureDetails.isEmpty ? summary : "\(summary) \(failureDetails)"
            return
        }

        vaultError = nil
        let successSummary = String(
            localized: "Imported \(outcome.documents.count) Markdown file\(outcome.documents.count == 1 ? "" : "s") into \(outcome.destinationName).",
            table: "Localizable",
            bundle: .module
        )
        var warnings: [String] = []
        if !outcome.failures.isEmpty {
            warnings.append(String(
                localized: "Some selected files were not imported. The imported files are already committed; do not import them again.",
                table: "Localizable",
                bundle: .module
            ))
            warnings.append(failureDetails)
        }
        if !outcome.derivedRefreshWarnings.isEmpty {
            warnings.append(String(
                localized: "Library, Search, or other derived views may be stale. Use Refresh instead of importing the files again.",
                table: "Localizable",
                bundle: .module
            ))
            warnings.append(outcome.derivedRefreshWarnings.joined(separator: " "))
        }
        if !outcome.identityRecoveryWarnings.isEmpty {
            warnings.append(String(
                localized: "The file operation completed, but stable note identity recovery is incomplete. Identity-dependent actions remain unavailable until recovery succeeds.",
                table: "Localizable",
                bundle: .module
            ))
            warnings.append(outcome.identityRecoveryWarnings.joined(separator: " "))
        }
        if let presentationWarning = outcome.presentationWarning {
            warnings.append(String(
                localized: "This window could not refresh the imported documents. Use Refresh instead of importing the files again.",
                table: "Localizable",
                bundle: .module
            ))
            warnings.append(presentationWarning)
        }

        if warnings.isEmpty {
            presentFeedback(successSummary)
        } else {
            presentFeedback(([successSummary] + warnings).joined(separator: " "), kind: .warning)
        }
    }

    func copyTextToClipboard(_ text: String, recovery: String? = nil) throws {
        guard ScholiumPasteboardWriter.general.writeText(text) else {
            throw ClipboardWorkflowError.copyFailed(recovery: recovery)
        }
    }

    func openWorkspaceVault(_ slot: WorkspaceVaultSlot) async throws {
        guard let vault = workspaceAssignment?.vault(for: slot) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        try await openRegisteredVault(vault)
    }

    private func prepareWorkspaceSelection(
        _ slot: WorkspaceVaultSlot,
        sourceScope: LibrarySourceScope,
        validateDestination: () throws -> Void = {}
    ) async throws {
        guard let vault = workspaceAssignment?.vault(for: slot) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let request = discoveryController.beginLibraryRequest(
            workspaceSlot: slot,
            sourceScope: sourceScope,
            presentation: .stagedReplacement
        )
        do {
            let staged = try await stageRegisteredVault(
                vault,
                slot: slot,
                libraryRequest: request
            )
            try validateDestination()
            try commitStagedWorkspaceLibrarySelection(staged)
        } catch {
            if discoveryController.isCurrentLibraryRequest(request) {
                discoveryController.failLibraryRequest(
                    error.localizedDescription,
                    for: request
                )
            }
            throw error
        }
        documentController.clearSelectionAfterClosingLastTab()
        shellState.selectWorkspace(slot)
        documentController.selectWorkspace(slot)
        attentionPresentationState.selectWorkspaceSlot(slot)
        await refreshIdentityState()
        scheduleWorkspaceCatalogRefresh()
    }

    private func validateDocumentIsAvailable(
        _ document: WindowSelectedDocument
    ) throws {
        guard let vaultID = document.vaultID,
              workspaceProjectionController.cachedNote(
                vaultID: vaultID,
                stableNoteID: document.sessionKey?.noteID,
                relativePath: document.relativePath
              ) != nil else {
            throw WindowNavigationError.noteUnavailable(document.relativePath)
        }
    }

    /// Reprojects Library onto another Triptych vault without touching the
    /// selected document. The target snapshot is staged completely before the
    /// browsed-vault identity changes, so a failed browse leaves both Library
    /// and the open editor intact.
    private func browseRegisteredVault(
        _ registered: RegisteredVault,
        slot: WorkspaceVaultSlot? = nil,
        libraryRequest: DiscoveryLibraryRequest? = nil
    ) async throws {
        let staged = try await stageRegisteredVault(
            registered,
            slot: slot,
            libraryRequest: libraryRequest
        )
        try commitStagedWorkspaceLibrarySelection(staged)
        await refreshIdentityState()
        scheduleWorkspaceCatalogRefresh()
    }

    private func stageRegisteredVault(
        _ registered: RegisteredVault,
        slot: WorkspaceVaultSlot? = nil,
        libraryRequest: DiscoveryLibraryRequest? = nil
    ) async throws -> StagedWorkspaceLibrarySelection {
        let vaultSnapshot = try await currentWorkspaceVaultSnapshot(
            vaultID: registered.id
        )
        let targetConfig = await windowWorkspaceController.vaultConfig(
            rootURL: URL(
                fileURLWithPath: registered.canonicalPath,
                isDirectory: true
            )
        )
        if let libraryRequest,
           !discoveryController.isCurrentLibraryRequest(libraryRequest) {
            throw CancellationError()
        }

        guard let resolvedSlot = slot ?? workspaceSlot(for: registered) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let targetSourceScope = libraryRequest?.sourceScope
            ?? discoveryController.libraryState(for: resolvedSlot).sourceScope
        let targetNotes = vaultSnapshot.documents
            .map(WindowDocumentLocation.workspace)
            .sorted(by: notesAreOrdered)

        if let libraryRequest,
           !discoveryController.isCurrentLibraryRequest(libraryRequest) {
            throw CancellationError()
        }
        return StagedWorkspaceLibrarySelection(
            registeredVault: registered,
            workspace: resolvedSlot,
            sourceScope: targetSourceScope,
            vaultSnapshot: vaultSnapshot,
            vaultConfig: targetConfig,
            notes: targetNotes,
            request: libraryRequest
        )
    }

    private func commitStagedWorkspaceLibrarySelection(
        _ staged: StagedWorkspaceLibrarySelection
    ) throws {
        if let request = staged.request,
           !discoveryController.isCurrentLibraryRequest(request) {
            throw CancellationError()
        }
        currentRegisteredVault = staged.registeredVault
        currentVaultRole = staged.registeredVault.role
        vaultConfig = staged.vaultConfig
        if let request = staged.request {
            guard discoveryController.receiveLibraryResult(for: request) else {
                throw CancellationError()
            }
        } else {
            discoveryController.synchronizeLibrarySelection(
                workspaceSlot: staged.workspace,
                sourceScope: staged.sourceScope
            )
        }
        attentionPresentationState.selectWorkspaceSlot(staged.workspace)
        workspaceProjectionController.commitVaultSelection(
            snapshot: staged.vaultSnapshot,
            notes: staged.notes
        )
    }

    private func workspaceSlot(for vault: RegisteredVault) -> WorkspaceVaultSlot? {
        WorkspaceVaultSlot.allCases.first { slot in
            guard let assigned = workspaceAssignment?.vault(for: slot) else { return false }
            return assigned.id == vault.id || assigned.canonicalPath == vault.canonicalPath
        }
    }

    func openRegisteredVault(_ vault: RegisteredVault) async throws {
        // The Workspace controller resolves and retains the one capability
        // session. This root applies only the selected Library projection.
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
            let session = try await windowWorkspaceController.activeSession(
                for: assignment,
                openingVault: workspaceSlot(for: registered) ?? shellState.selectedWorkspace
            )
            let capabilities = session.capabilities
            let workspaceSnapshot = session.snapshot
            let workspaceVaultSnapshots = workspaceSnapshot.vaults
            guard let vaultSnapshot = workspaceVaultSnapshots.first(where: {
                $0.vault.id == registered.id
            }) else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            // Stage the complete target runtime and inventory before replacing
            // any visible window state. A failed vault open must leave the
            // current Triptych document and editor intact.
            let targetNotes = vaultSnapshot.documents
                .map(WindowDocumentLocation.workspace)
                .sorted {
                    $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
                }
            let targetConfig = await windowWorkspaceController.vaultConfig(
                rootURL: URL(
                    fileURLWithPath: registered.canonicalPath,
                    isDirectory: true
                )
            )
            PerformanceProbe.shared.markVaultConfigurationReady()

            resetWindowSession()

            workspaceProjectionController.replaceVaultSnapshots(workspaceVaultSnapshots)
            if let slot = workspaceSlot(for: registered) {
                discoveryController.synchronizeLibrarySelection(
                    workspaceSlot: slot,
                    sourceScope: .library
                )
                shellState.selectWorkspace(slot)
                documentController.selectWorkspace(slot)
                attentionPresentationState.selectWorkspaceSlot(slot)
            }
            currentRegisteredVault = registered
            currentVaultRole = registered.role
            vaultConfig = targetConfig
            workspaceProjectionController.replaceVisibleNotes(targetNotes)
            let commit = workspaceProjectionController.activate(
                snapshot: workspaceSnapshot,
                runtimeIdentity: capabilities.runtimeIdentity,
                context: workspaceProjectionContext
            )
            applyWorkspaceProjectionCommit(commit)
            PerformanceProbe.shared.markWarmLibraryProjectionReady()
            isLoading = false
            // `activate` has already published the authoritative catalog and
            // all Vault snapshots, and identity state was refreshed above.
            // Do not hold initial document restoration behind a duplicate
            // window refresh; later Workspace generations own reconciliation.
            if !workspaceSnapshot.research.healthIssues.isEmpty {
                vaultError = workspaceSnapshot.research.healthIssues.joined(separator: "\n\n")
            }
        } catch {
            isLoading = false
            refreshStatusText = nil
            vaultError = error.localizedDescription
            throw error
        }
    }

    func restoreWorkspaceIfNeeded() async {
        guard windowWorkspaceController.beginInitialRestoreIfNeeded(
            isConfigured: vaultConfig != nil
        ) else { return }
        if let root = ScholiumRuntimeIsolation.fixtureRootURL() {
            do {
                let analysesURL = root.appendingPathComponent(
                    "01-analyses",
                    isDirectory: true
                )
                let topicsURL = root.appendingPathComponent(
                    "02-topics",
                    isDirectory: true
                )
                let worksURL = root.appendingPathComponent(
                    "03-works",
                    isDirectory: true
                )
                let fixtureURLs: [WorkspaceVaultSlot: URL] = [
                    .paperAnalysis: analysesURL,
                    .topicKnowledge: topicsURL,
                    .output: worksURL,
                ]
                await windowWorkspaceController.refreshRegistrations()
                let registered = registeredTriptychs.first { assignment in
                    WorkspaceVaultSlot.allCases.allSatisfy { slot in
                        guard let expected = fixtureURLs[slot],
                              let actual = assignment.vault(for: slot) else { return false }
                        return actual.canonicalPath == expected.resolvingSymlinksInPath()
                            .standardizedFileURL.path
                    }
                }
                if let registered,
                   let openingVault = registered.vault(for: requestedInitialWorkspaceSlot) {
                    shellState.selectWorkspace(requestedInitialWorkspaceSlot)
                    await refreshWorkspaceAssignment(preferredTriptychID: registered.id)
                    guard workspaceAssignment?.id == registered.id else {
                        throw WorkspaceRegistryError.incompleteWorkspace
                    }
                    try await openRegisteredVault(openingVault)
                } else {
                    try await configureTriptych(
                        paperAnalysisURL: analysesURL,
                        topicKnowledgeURL: topicsURL,
                        outputURL: worksURL,
                        portableContainerURL: root
                    )
                }
                // Either the already-registered reopen or `configureTriptych`
                // opens the requested Vault exactly once before this route.
                preparePerformancePresentationModeIfNeeded()
                openRequestedTestNoteIfNeeded()
            } catch {
                vaultError = error.localizedDescription
            }
            return
        }
        await windowWorkspaceController.refreshRegistrations()
        await refreshWorkspaceAssignment()
        guard workspaceAssignment != nil else {
            return
        }

        do {
            try await openWorkspaceVault(.paperAnalysis)
            openRequestedTestNoteIfNeeded()
        } catch {
            if windowWorkspaceController.recordRecovery(for: error) {
                vaultError = nil
            } else {
                vaultError = error.localizedDescription
            }
        }
    }

    private var requestedInitialWorkspaceSlot: WorkspaceVaultSlot {
        let allowsRequestedSlot: Bool = {
#if DEBUG
            true
#else
            PerformanceProbe.shared.isEnabled
#endif
        }()
        guard allowsRequestedSlot,
              let rawValue = ProcessInfo.processInfo.environment[
                "SCHOLIUM_UI_TEST_OPEN_SLOT"
              ],
              let requested = WorkspaceVaultSlot(rawValue: rawValue) else {
            return shellState.selectedWorkspace
        }
        return requested
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

    private func preparePerformancePresentationModeIfNeeded() {
        guard PerformanceProbe.shared.requiresInitialReviewPresentation else {
            return
        }
        documentController.rememberPresentationMode(.read)
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

        if noteSourceScope == .library, workspaceAssignment != nil {
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
        try await refreshLibrarySourceScope()
    }

    func selectLibrarySourceScope(_ scope: LibrarySourceScope) async {
        guard let workspaceSlot = currentWorkspaceSlot else { return }
        guard scope != noteSourceScope
                || discoveryController.library.sourceError != nil else { return }
        let request = discoveryController.beginLibraryRequest(
            workspaceSlot: workspaceSlot,
            sourceScope: scope,
            presentation: .stagedReplacement
        )
        do {
            let loaded = try await loadNotes(
                for: scope,
                vaultID: currentRegisteredVault?.id
            )
            guard discoveryController.receiveLibraryResult(for: request) else { return }
            workspaceProjectionController.replaceVisibleNotes(
                loaded.sorted(by: notesAreOrdered)
            )
            await refreshIdentityState()
            await refreshWindowProjection()
        } catch {
            discoveryController.failLibraryRequest(
                error.localizedDescription,
                for: request
            )
            presentFeedback(String(localized: "Could not open \(scope.rawValue): \(error.localizedDescription)", table: "Localizable", bundle: .module), kind: .error)
        }
    }

    func refreshLibrarySourceScope() async throws {
        guard let workspaceSlot = currentWorkspaceSlot else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let request = discoveryController.beginLibraryRequest(
            workspaceSlot: workspaceSlot,
            sourceScope: noteSourceScope
        )
        let loaded: [WindowDocumentLocation]
        do {
            loaded = try await loadNotes(
                for: request.sourceScope,
                vaultID: currentRegisteredVault?.id
            )
        } catch {
            discoveryController.failLibraryRequest(error.localizedDescription, for: request)
            throw error
        }
        guard discoveryController.receiveLibraryResult(for: request) else { return }
        workspaceProjectionController.replaceVisibleNotes(
            loaded.sorted(by: notesAreOrdered)
        )
        await refreshIdentityState()
        await refreshWindowProjection()
    }

    private func loadNotes(
        for scope: LibrarySourceScope,
        vaultID: UUID?
    ) async throws -> [WindowDocumentLocation] {
        guard let vaultID else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let vault = try await currentWorkspaceVaultSnapshot(vaultID: vaultID)
        return vault.documents
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

    private func publishCommittedNoteCreation(
        _ outcome: WorkspaceMutationOutcome<WorkspaceManagedNoteCommit>,
        isCurrent: @MainActor () -> Bool
    ) async {
        guard let vault = currentRegisteredVault else { return }
        let commit = outcome.committedValue
        let document = commit.document
        do {
            let sourceAheadSnapshot = commit.sourceAheadSnapshot
            guard workspaceProjectionController.recordCommittedNote(
                sourceAheadSnapshot,
                visibleVaultID: currentRegisteredVault?.id,
                visibleSourceScope: noteSourceScope
            ) != nil else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            guard isCurrent() else {
                reportCommittedMutationWarnings(outcome)
                return
            }
            if let noteID = sourceAheadSnapshot.stableIdentity.resolvedID {
                try await activateWorkspaceReference(
                    VaultNoteReference(
                        vaultID: vault.id,
                        vaultName: vault.name,
                        vaultRole: vault.role,
                        relativePath: document.relativePath,
                        stableNoteID: noteID.uuidString.lowercased()
                    ),
                    tabActivation: .place(.replaceSelected),
                    managedCreationBodyStartUTF16: document.bodyUTF16Offset
                )
            } else {
                PerformanceProbe.shared.beginReadActivation(
                    documentID: document.relativePath
                )
                documentController.selectUnavailableDocument(
                    vaultID: vault.id,
                    relativePath: document.relativePath
                )
                synchronizeDocumentTabs(after: .place(.replaceSelected))
            }
            revealCreatedNoteInLibrary(document.relativePath, vaultID: vault.id)
            reportCommittedMutationWarnings(outcome)
        } catch {
            reportCommittedMutationWarnings(
                outcome,
                presentationWarning: error.localizedDescription
            )
        }
    }

    private func publishCommittedFolderCreation(
        _ outcome: WorkspaceMutationOutcome<VaultRelativeFolderPath>
    ) async {
        guard let vault = currentRegisteredVault else { return }
        let folder = outcome.committedValue
        do {
            guard workspaceProjectionController.recordCommittedFolder(
                folder,
                vaultID: vault.id
            ) != nil else {
                try await refreshCachedWorkspaceVaultSnapshot(vaultID: vault.id)
                try await browseRegisteredVault(vault)
                expandFolderAncestors(folder.rawValue, vaultID: vault.id)
                reportCommittedMutationWarnings(outcome)
                return
            }
            expandFolderAncestors(folder.rawValue, vaultID: vault.id)
            if !reportCommittedMutationWarnings(outcome) {
                presentFeedback(
                    String(
                        localized: "Folder created: \(folder.rawValue)",
                        table: "Localizable",
                        bundle: .module
                    )
                )
            }
        } catch {
            reportCommittedMutationWarnings(
                outcome,
                presentationWarning: error.localizedDescription
            )
        }
    }

    private func publishCommittedFolderMove(
        _ outcome: WorkspaceMutationOutcome<FolderMoveCommit>
    ) async {
        let commit = outcome.committedValue
        projectFolderMove(
            commit,
            identityResolved: outcome.identityRecoveryWarning == nil
        )
        migrateFolderDisclosure(
            from: commit.sourceFolder.rawValue,
            to: commit.destinationFolder.rawValue,
            vaultID: commit.vaultID
        )
        var presentationWarning: String?
        if outcome.identityRecoveryWarning == nil,
           let projection = workspaceProjectionController.recordCommittedFolderMove(
               commit,
               visibleVaultID: currentRegisteredVault?.id,
               visibleSourceScope: noteSourceScope
           ) {
            for note in projection.notes {
                documentController.recordCommittedSnapshot(
                    note,
                    vaultName: projection.vault.name,
                    vaultRole: projection.vault.role
                )
            }
        } else {
            presentationWarning = String(
                localized: "The folder moved, but this window is waiting for the committed refresh.",
                table: "Localizable",
                bundle: .module
            )
        }
        scheduleWorkspaceCatalogRefresh()
        reportCommittedMutationWarnings(
            outcome,
            presentationWarning: presentationWarning
        )
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

    private func projectFolderMove(
        _ commit: FolderMoveCommit,
        identityResolved: Bool
    ) {
        for move in commit.noteMoves {
            let sessionKey = DocumentSessionKey(
                vaultID: commit.vaultID,
                noteID: move.stableNoteID
            )
            let wasSelected = currentDocumentDescriptor?.sessionKey == sessionKey
            migrateAppOwnedState(
                sourcePath: move.source.relativePath,
                destinationPath: move.destination.relativePath,
                noteID: move.stableNoteID,
                identityResolved: identityResolved,
                vaultID: commit.vaultID
            )
            _ = wasSelected
        }
    }

    private func expandFolderAncestors(_ relativePath: String, vaultID: UUID) {
        let visiblePath = libraryCategoryRelativeFolderPath(relativePath)
        guard !visiblePath.isEmpty else { return }
        let scope = LibraryDisclosureScope(vaultID: vaultID, sourceScope: .library)
        var expanded = discoveryController.expandedFolders(in: scope)
        let parts = visiblePath.split(separator: "/").map(String.init)
        for count in 1...parts.count {
            expanded.insert(parts.prefix(count).joined(separator: "/"))
        }
        discoveryController.setExpandedFolders(expanded, in: scope)
    }

    private func revealCreatedNoteInLibrary(_ relativePath: String, vaultID: UUID) {
        let scope = LibraryDisclosureScope(vaultID: vaultID, sourceScope: .library)
        discoveryController.prepareCreatedNoteReveal(
            relativePath: relativePath,
            folderAncestors: libraryFolderAncestors(forDocumentPath: relativePath),
            in: scope
        )
    }

    private func migrateFolderDisclosure(
        from sourceRelativePath: String,
        to destinationRelativePath: String?,
        vaultID: UUID
    ) {
        let scope = LibraryDisclosureScope(vaultID: vaultID, sourceScope: .library)
        let source = libraryCategoryRelativeFolderPath(sourceRelativePath)
        let destination = destinationRelativePath.map(libraryCategoryRelativeFolderPath)
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
            let parts = destination.split(separator: "/").map(String.init)
            if parts.count > 1 {
                for count in 1..<parts.count {
                    migrated.insert(parts.prefix(count).joined(separator: "/"))
                }
            }
        }
        discoveryController.setExpandedFolders(migrated, in: scope)
    }

    private func publishCommittedNoteDuplication(
        _ outcome: WorkspaceMutationOutcome<NoteDocument>,
        target: NoteMutationTarget,
        destination: String
    ) async {
        guard let vault = workspaceAssignment?.vaults.values.first(where: {
            $0.id == target.documentID.vaultID
        }) else {
            reportCommittedMutationWarnings(
                outcome,
                presentationWarning: WorkspaceRegistryError.incompleteWorkspace.localizedDescription
            )
            return
        }
        var presentationWarning: String?
        do {
            try await refreshCachedWorkspaceVaultSnapshot(vaultID: target.documentID.vaultID)
            try await browseRegisteredVault(vault)
            openNote(destination)
        } catch {
            presentationWarning = error.localizedDescription
        }
        reportCommittedMutationWarnings(
            outcome,
            presentationWarning: presentationWarning
        )
    }

    private func publishCommittedNoteMove(
        _ outcome: WorkspaceMutationOutcome<TriptychMoveCommit>,
        target: NoteMutationTarget
    ) async {
        guard let vault = workspaceAssignment?.vaults.values.first(where: {
            $0.id == target.documentID.vaultID
        }) else {
            reportCommittedMutationWarnings(
                outcome,
                presentationWarning: WorkspaceRegistryError.incompleteWorkspace.localizedDescription
            )
            return
        }
        let commit = outcome.committedValue
        let destination = commit.destination.relativePath
        migrateAppOwnedState(
            sourcePath: target.relativePath,
            destinationPath: destination,
            noteID: target.stableNoteID,
            identityResolved: outcome.identityRecoveryWarning == nil,
            vaultID: target.documentID.vaultID
        )
        var presentationWarning: String?
        if outcome.identityRecoveryWarning == nil,
           let projection = workspaceProjectionController.recordCommittedNoteMove(
               commit,
               stableIdentity: .resolved(target.stableNoteID),
               visibleVaultID: currentRegisteredVault?.id,
               visibleSourceScope: noteSourceScope
           ) {
            documentController.recordCommittedSnapshot(
                projection.note,
                vaultName: projection.vault.name,
                vaultRole: projection.vault.role
            )
            do {
                try await activateWorkspaceReference(
                    VaultNoteReference(
                        vaultID: projection.note.id.vaultID,
                        vaultName: projection.vault.name,
                        vaultRole: projection.vault.role,
                        relativePath: projection.note.id.relativePath,
                        stableNoteID: target.stableNoteID.uuidString.lowercased()
                    ),
                    tabActivation: .place(.replaceSelected)
                )
                revealCreatedNoteInLibrary(
                    projection.note.id.relativePath,
                    vaultID: projection.note.id.vaultID
                )
            } catch {
                presentationWarning = error.localizedDescription
            }
        } else {
            do {
                try await refreshCachedWorkspaceVaultSnapshot(
                    vaultID: target.documentID.vaultID
                )
                try await browseRegisteredVault(vault)
                openNote(destination)
            } catch {
                presentationWarning = error.localizedDescription
            }
        }
        scheduleWorkspaceCatalogRefresh()
        reportCommittedMutationWarnings(
            outcome,
            presentationWarning: presentationWarning
        )
    }

    func requestCurrentNoteSystemTrash() {
        guard let currentNote,
              let target = NoteMutationTarget(currentNote),
              currentDocumentCapabilities.allows(.moveToSystemTrash) else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await libraryMutationController.prepareNoteSystemTrash(target)
            } catch is CancellationError {
                return
            } catch {
                presentFeedback(error.localizedDescription, kind: .error)
            }
        }
    }

    private func publishSystemTrashResult(
        _ preview: SystemTrashDeletionPreview,
        outcome: WorkspaceMutationOutcome<SystemTrashDeletionCommit>?
    ) async {
        guard let outcome else {
            _ = try? await discoveryController.refreshWorkspace()
            await synchronizeSystemTrashPresentation(preview)
            return
        }
        await synchronizeSystemTrashPresentation(preview)
        sourceMutationGeneration &+= 1
        reportCommittedMutationWarnings(
            outcome,
            presentationWarning: nil
        )
    }

    private func synchronizeSystemTrashPresentation(
        _ preview: SystemTrashDeletionPreview
    ) async {
        guard let vaultID = preview.sources.first?.vaultID else { return }
        try? await refreshCachedWorkspaceVaultSnapshot(vaultID: vaultID)
        let currentPaths = Set(
            workspaceProjectionController.vaultSnapshot(id: vaultID)?
                .documents.map { $0.id.relativePath } ?? []
        )
        let plannedPaths = Set(preview.sources.flatMap(\.notes).map(\.relativePath))
        let removedPaths = plannedPaths.subtracting(currentPaths)
        guard !removedPaths.isEmpty else { return }
        do {
            try removeDocumentTabs(vaultID: vaultID, removedPaths: removedPaths)
        } catch {
            if currentDocumentVaultID == vaultID {
                documentController.clearSelection(forRemovedPaths: removedPaths)
            }
        }
        if currentRegisteredVault?.id == vaultID {
            try? await refreshLibrarySourceScope()
        }
        scheduleWorkspaceCatalogRefresh()
    }

    func refreshTransactionRecoveryRecords() async {
        do {
            transactionRecoveryRecords = try await researchController.recoveryRecords()
            transactionRecoveryError = nil
        } catch {
            transactionRecoveryRecords = []
            transactionRecoveryError = "Scholium could not read the durable recovery records. Their file remains unchanged. \(error.localizedDescription)"
        }
        do {
            interruptedSaveRecoveries = try await researchController
                .loadInterruptedSaveRecoveries()
            interruptedSaveRecoveryError = nil
        } catch {
            interruptedSaveRecoveries = []
            interruptedSaveRecoveryError = String(
                localized: "Scholium could not verify the interrupted save candidates. Their exact bytes remain unchanged. \(error.localizedDescription)",
                table: "Localizable",
                bundle: .module
            )
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

    func interruptedSaveRecoveryContent(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> InterruptedSaveRecoveryContent {
        try await researchController.interruptedSaveRecoveryContent(recovery)
    }

    func revealInterruptedSaveRecoveryInFinder(
        _ recovery: InterruptedSaveRecovery
    ) async throws {
        let url = try await researchController
            .prepareInterruptedSaveRecoveryLocation(recovery)
        workspaceStore.revealInFinder(url)
    }

    @discardableResult
    func restoreInterruptedSaveRecovery(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> InterruptedSaveRecoveryRestoreCommit {
        guard let assignment = workspaceAssignment else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        // A recovery write may target a Note open in any window. Flush first so
        // unsaved researcher text either commits and causes Core's exact
        // revision check to refuse the restore, or remains available on a flush
        // failure. Recovery never writes around a retained dirty buffer.
        try await editorFlushCoordinator.flushAllEditors(in: assignment.id)
        let outcome = try await researchController.restoreInterruptedSaveRecovery(recovery)
        await refreshTransactionRecoveryRecords()
        await refreshWindowProjection()

        var warnings: [String] = []
        if let derived = outcome.derivedRefreshWarning {
            warnings.append(String(
                localized: "The candidate was restored, but Library, Search, or another derived view may be stale. Use Refresh instead of repeating recovery. \(derived)",
                table: "Localizable",
                bundle: .module
            ))
        }
        if warnings.isEmpty {
            presentFeedback(
                outcome.committedValue.didReplaceSource
                    ? String(
                        localized: "Interrupted save restored",
                        table: "Localizable",
                        bundle: .module
                    )
                    : String(
                        localized: "Interrupted save recovery completed",
                        table: "Localizable",
                        bundle: .module
                    )
            )
        } else {
            presentFeedback(warnings.joined(separator: " "), kind: .warning)
        }
        return outcome.committedValue
    }

    private func migrateAppOwnedState(
        sourcePath: String,
        destinationPath: String,
        noteID: UUID,
        identityResolved: Bool,
        vaultID: UUID
    ) {
        // Source movement is already durable. Portable identity is projected
        // as resolved only when Application also proved its migration; a
        // post-commit recovery warning must keep identity-dependent actions
        // unavailable without discarding the retained editor session.
        migrateInMemoryPath(
            from: sourcePath,
            to: destinationPath,
            noteID: noteID,
            identityResolved: identityResolved,
            vaultID: vaultID
        )
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
        if let tab = documentTabController.allTabs.first(where: {
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

    private func currentSearchResultEvidence(
        for result: SearchResult,
        scope: SearchPresentationScope
    ) async -> WindowSearchResultEvidence {
        switch result {
        case .note(let note):
            if scope == .thisNote {
                let snapshot = try? await currentSearchSourceSnapshot()
                return WindowSearchResultEvidence(
                    freshness: snapshot.map(SearchFreshnessToken.currentNote),
                    fingerprint: snapshot?.fingerprint
                )
            }
            let discovery = try? await discoveryController.discoverySnapshot()
            return WindowSearchResultEvidence(
                freshness: discovery?.searchGeneration.map(SearchFreshnessToken.triptych),
                fingerprint: workspaceProjectionController.cachedNote(
                    vaultID: note.vaultID,
                    stableNoteID: note.stableNoteID.flatMap(UUID.init(uuidString:)),
                    relativePath: note.relativePath
                )?.fingerprint
            )
        case .record(let record):
            guard let snapshot = try? await researchController.researchSnapshot(),
                  snapshot.finishedResearchRecordProjectionIsComplete,
                  let fingerprint = snapshot.finishedResearchRecordFingerprints[
                    record.recordID
                  ], let triptychID = workspaceAssignment?.id else {
                return WindowSearchResultEvidence(
                    freshness: nil,
                    fingerprint: nil
                )
            }
            let generation = RecordSearchGenerationID(
                triptychID: triptychID,
                sourceManifestHash: snapshot.finishedResearchRecordSourceManifestHash
            )
            return WindowSearchResultEvidence(
                freshness: .record(generation),
                fingerprint: fingerprint
            )
        }
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
            stableNoteID: note.workspaceSnapshot?.stableIdentity.resolvedID,
            editorSessionID: sessionID,
            source: source,
            editorRevision: UInt64(max(0, session.editorSession.generation)),
            metadata: note.workspaceSnapshot?.metadata,
            metadataCatalog: workspaceProjectionController.metadataCatalog
        )
    }

    func openNote(
        _ path: String,
        tabActivation: DocumentTabActivation = .place(.replaceSelected)
    ) {
        guard let location = notes.first(where: { $0.relativePath == path }) else {
            presentFeedback(String(localized: "Note not found: \(path)", table: "Localizable", bundle: .module), kind: .warning)
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
            presentFeedback(
                String(localized: "Note not found: \(path)", table: "Localizable", bundle: .module),
                kind: .warning
            )
            return
        }
        synchronizeDocumentTabs(after: tabActivation)
    }

    func openingDocumentPresentationDidComplete() {
        guard let capabilities = windowWorkspaceController.activeCapabilities,
              presentedOpeningRuntimeIdentity != capabilities.runtimeIdentity else { return }
        presentedOpeningRuntimeIdentity = capabilities.runtimeIdentity
        ScholiumWebKitProcessPrewarmer.shared.finish()
        Task {
            await capabilities.openingPresentationDidComplete()
        }
    }

    private func vaultQualifiedID(
        for document: WindowSelectedDocument
    ) -> VaultQualifiedNoteID? {
        guard let vaultID = document.vaultID else { return nil }
        return VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: document.relativePath
        )
    }

    private func activateDocument(
        _ document: WindowSelectedDocument,
        tabActivation: DocumentTabActivation,
        recordsNavigationHistory: Bool = true
    ) async throws {
        guard let vaultID = document.vaultID,
              let vault = workspaceAssignment?.vaults.values.first(where: {
                  $0.id == vaultID
              }),
              let workspace = workspaceSlot(for: vault) else {
            throw WindowNavigationError.noteUnavailable(document.relativePath)
        }
        if shellState.selectedWorkspace != workspace {
            try await prepareWorkspaceSelection(
                workspace,
                sourceScope: .library,
                validateDestination: {
                    try self.validateDocumentIsAvailable(document)
                }
            )
        }
        try activateDocumentInSelectedWorkspace(
            document,
            tabActivation: tabActivation,
            recordsNavigationHistory: recordsNavigationHistory
        )
    }

    private func activateDocumentInSelectedWorkspace(
        _ document: WindowSelectedDocument,
        tabActivation: DocumentTabActivation,
        recordsNavigationHistory: Bool = true
    ) throws {
        switch document {
        case .workspace(let descriptor):
            try activateWorkspaceReferenceInSelectedWorkspace(
                descriptor.reference,
                tabActivation: tabActivation,
                recordsNavigationHistory: recordsNavigationHistory
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
            synchronizeDocumentTabs(
                after: tabActivation,
                recordsNavigationHistory: recordsNavigationHistory
            )
        }
    }

    private func activateWorkspaceReference(
        _ reference: VaultNoteReference,
        tabActivation: DocumentTabActivation,
        recordsNavigationHistory: Bool = true,
        managedCreationBodyStartUTF16: Int? = nil
    ) async throws {
        guard let vault = workspaceAssignment?.vaults.values.first(where: {
            $0.id == reference.vaultID
        }), let workspace = workspaceSlot(for: vault) else {
            throw WindowNavigationError.vaultUnavailable(reference.vaultName)
        }
        let requestedStableID = reference.stableNoteID.flatMap(UUID.init(uuidString:))
        guard workspaceProjectionController.cachedNote(
            vaultID: reference.vaultID,
            stableNoteID: requestedStableID,
            relativePath: reference.relativePath
        ) != nil else {
            throw WindowNavigationError.noteUnavailable(reference.relativePath)
        }
        if shellState.selectedWorkspace != workspace {
            try await prepareWorkspaceSelection(
                workspace,
                sourceScope: .library,
                validateDestination: {
                    guard self.workspaceProjectionController.cachedNote(
                        vaultID: reference.vaultID,
                        stableNoteID: requestedStableID,
                        relativePath: reference.relativePath
                    ) != nil else {
                        throw WindowNavigationError.noteUnavailable(
                            reference.relativePath
                        )
                    }
                }
            )
        }
        try activateWorkspaceReferenceInSelectedWorkspace(
            reference,
            tabActivation: tabActivation,
            recordsNavigationHistory: recordsNavigationHistory,
            managedCreationBodyStartUTF16: managedCreationBodyStartUTF16
        )
    }

    private func activateWorkspaceReferenceInSelectedWorkspace(
        _ reference: VaultNoteReference,
        tabActivation: DocumentTabActivation,
        recordsNavigationHistory: Bool = true,
        managedCreationBodyStartUTF16: Int? = nil
    ) throws {
        guard let vault = workspaceAssignment?.vaults.values.first(where: {
            $0.id == reference.vaultID
        }), workspaceSlot(for: vault) == shellState.selectedWorkspace else {
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
        if managedCreationBodyStartUTF16 == nil {
            PerformanceProbe.shared.beginReadActivation(
                documentID: snapshot.id.relativePath
            )
        }
        if snapshot.stableIdentity.resolvedID != nil {
            documentController.installOpenedDocument(
                snapshot,
                vaultName: vault.name,
                vaultRole: vault.role,
                managedCreationBodyStartUTF16: managedCreationBodyStartUTF16
            )
        } else {
            documentController.selectUnavailableDocument(
                vaultID: vault.id,
                relativePath: snapshot.id.relativePath
            )
        }
        synchronizeDocumentTabs(
            after: tabActivation,
            recordsNavigationHistory: recordsNavigationHistory
        )
    }

    private func synchronizeDocumentTabs(
        after activation: DocumentTabActivation,
        recordsNavigationHistory: Bool = true
    ) {
        guard let document = documentController.selectedDocument else { return }
        let presentation = documentTabPresentation(for: document)
        switch activation {
        case .place(let placement):
            documentTabController.activate(
                document: document,
                title: presentation.title,
                toolTip: presentation.toolTip,
                placement: placement,
                in: shellState.selectedWorkspace
            )
            if !libraryMutationController.isCreatingNote {
                scheduleLibraryReveal(for: document)
            }
        case .preserveTabMembership:
            documentTabController.updateDocumentProjection(
                document,
                title: presentation.title,
                toolTip: presentation.toolTip
            )
        }
        if recordsNavigationHistory {
            documentNavigationHistoryController.record(document)
        }
        reconcileDocumentSessionLeases()
        PerformanceProbe.shared.markFirstReadDocumentSelected(
            documentID: document.relativePath
        )
    }

    /// Every successful in-app document activation converges on this one
    /// presentation path. It changes only Library presentation: the target
    /// vault and Library view, filters that hide the selected Note, folder
    /// disclosure, and the minimum scroll needed to expose its row.
    private func scheduleLibraryReveal(for document: WindowSelectedDocument) {
        libraryRevealTask?.cancel()
        libraryRevealTask = Task { [weak self] in
            guard let self else { return }
            await self.revealDocumentInLibrary(document)
        }
    }

    private func revealDocumentInLibrary(_ document: WindowSelectedDocument) async {
        guard let vaultID = document.vaultID,
              workspaceProjectionController.cachedNote(
                  vaultID: vaultID,
                  stableNoteID: document.sessionKey?.noteID,
                  relativePath: document.relativePath
              ) != nil,
              let vault = workspaceAssignment?.vaults.values.first(where: {
                  $0.id == vaultID
              }),
              let slot = workspaceSlot(for: vault) else { return }

        let scope = LibraryDisclosureScope(
            vaultID: vaultID,
            sourceScope: .library
        )
        let needsProjection = currentRegisteredVault?.id != vaultID
            || discoveryController.library.sourceScope != .library
            || discoveryController.libraryRequestIsActive

        if needsProjection {
            let request = discoveryController.beginLibraryRequest(
                workspaceSlot: slot,
                sourceScope: .library,
                presentation: .stagedReplacement
            )
            do {
                try await browseRegisteredVault(
                    vault,
                    slot: slot,
                    libraryRequest: request
                )
            } catch is CancellationError {
                return
            } catch {
                guard discoveryController.isCurrentLibraryRequest(request) else { return }
                discoveryController.failLibraryRequest(
                    error.localizedDescription,
                    for: request
                )
                presentFeedback(
                    String(
                        localized: "Could not reveal the current note. \(error.localizedDescription)",
                        table: "Localizable",
                        bundle: .module
                    ),
                    kind: .error
                )
                return
            }
        }

        guard !Task.isCancelled,
              documentController.selectedDocument == document,
              currentRegisteredVault?.id == vaultID,
              discoveryController.library.sourceScope == .library else { return }

        let clearsFilters = !filteredNotes.contains {
            $0.relativePath == document.relativePath
        }
        discoveryController.prepareLibraryNoteReveal(
            relativePath: document.relativePath,
            folderAncestors: libraryFolderAncestors(
                forDocumentPath: document.relativePath
            ),
            clearFilters: clearsFilters,
            in: scope
        )
    }

    private func reconcileDocumentSessionLeases() {
        let workspace = shellState.selectedWorkspace
        documentController.reconcileSessionLeases(
            leasedDocuments: documentTabController.allTabs.map(\.document),
            selectedDocument: documentTabController.selectedTab(in: workspace)?.document
        )
    }

    private func removeDocumentTabs(
        vaultID: UUID,
        removedPaths: Set<String>
    ) throws {
        let matchingIDs = Set(documentTabController.allTabs.compactMap { tab -> UUID? in
            guard let descriptor = tab.document.workspaceDescriptor,
                  descriptor.reference.vaultID == vaultID,
                  removedPaths.contains(descriptor.reference.relativePath) else {
                return nil
            }
            return tab.id
        })
        guard !matchingIDs.isEmpty else {
            if currentDocumentVaultID == vaultID {
                documentController.clearSelection(forRemovedPaths: removedPaths)
            }
            reconcileDocumentSessionLeases()
            return
        }
        try removeDocumentTabs(withIDs: matchingIDs)
    }

    private func removeDocumentTabs(withIDs matchingIDs: Set<UUID>) throws {
        guard !matchingIDs.isEmpty else {
            reconcileDocumentSessionLeases()
            return
        }

        // Remove inactive pages first so the selected page's close plan can
        // never choose another document that was deleted in the same commit.
        let currentWorkspace = shellState.selectedWorkspace
        let selectedIDs = Set(WorkspaceVaultSlot.allCases.compactMap {
            documentTabController.selectedTabID(in: $0)
        })
        for id in matchingIDs where !selectedIDs.contains(id) {
            if let plan = documentTabController.closePlan(forTabWithID: id) {
                documentTabController.apply(plan)
            }
        }
        for workspace in WorkspaceVaultSlot.allCases {
            guard let selectedID = documentTabController.selectedTabID(in: workspace),
                  matchingIDs.contains(selectedID),
                  let plan = documentTabController.closePlan(forTabWithID: selectedID) else {
                continue
            }
            if workspace == currentWorkspace {
                if let documentToActivate = plan.documentToActivate {
                    try activateDocumentInSelectedWorkspace(
                        documentToActivate,
                        tabActivation: .preserveTabMembership
                    )
                } else {
                    documentController.clearSelectionAfterClosingLastTab()
                }
            }
            documentTabController.apply(plan)
        }
        reconcileDocumentSessionLeases()
    }

    private func removeExternallyDeletedDocumentTabs(
        _ documents: Set<WindowSelectedDocument>
    ) {
        guard !documents.isEmpty else { return }
        let targets = Set(documents.map(\.editingTarget))
        let matchingIDs = Set(documentTabController.allTabs.compactMap { tab in
            targets.contains(tab.document.editingTarget) ? tab.id : nil
        })
        do {
            try removeDocumentTabs(withIDs: matchingIDs)
        } catch {
            documentTabController.removeTabs(withIDs: matchingIDs)
            documentController.clearSelectionAfterClosingLastTab()
            reconcileDocumentSessionLeases()
            presentFeedback(
                String(
                    localized: "The deleted note was removed, but Scholium could not activate the adjacent tab. Choose a document to continue. \(error.localizedDescription)",
                    table: "Localizable",
                    bundle: .module
                ),
                kind: .warning
            )
        }
    }

    private func refreshDocumentTabProjections() {
        for tab in documentTabController.allTabs {
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
            try await self.activateWorkspaceReference(
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
            try await self.activateWorkspaceReference(
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
            presentFeedback(String(localized: "Connections are still refreshing. Try the link again shortly.", table: "Localizable", bundle: .module), kind: .information)
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
            let message = hasAmbiguity
                ? String(
                    localized: "This Connection is ambiguous. Open Incoming or Outgoing to choose a source-located candidate.",
                    table: "Localizable",
                    bundle: .module
                )
                : String(
                    localized: "This Connection is broken or its destination no longer exists.",
                    table: "Localizable",
                    bundle: .module
                )
            presentFeedback(
                message,
                kind: .warning
            )
            return
        }
        guard let reference = workspaceCatalog?.notes.first(where: {
            $0.reference.vaultID == destination.note.vaultID
                && $0.reference.relativePath == destination.note.relativePath
        })?.reference else {
            presentFeedback(String(localized: "The resolved note is not available in the current Triptych catalog.", table: "Localizable", bundle: .module), kind: .warning)
            return
        }
        Task { await openWorkspaceReference(reference, line: destination.line, mode: .read) }
    }

    @discardableResult
    func saveMetadata(
        for note: WindowDocumentLocation,
        proposedFields: [String: YAMLValue],
        expectedRevision: DocumentFingerprint?
    ) async throws -> WindowDocumentLocation {
        guard let context = activeDocumentContext(for: note.relativePath) else {
            throw VaultRepositoryError.fileDoesNotExist(note.relativePath)
        }
        let original = context.note
        guard let originalSnapshot = original.workspaceSnapshot else {
            throw VaultRepositoryError.fileDoesNotExist(note.relativePath)
        }
        do {
            let outcome = try await documentController.saveMetadata(
                VaultQualifiedNoteID(vaultID: context.vaultID, relativePath: note.relativePath),
                fields: proposedFields,
                expectedRevision: expectedRevision
            )
            let savedSnapshot = originalSnapshot.applyingCommittedMetadata(
                outcome.committedValue
            )
            replaceCachedWorkspaceNote(savedSnapshot)
            let saved = WindowDocumentLocation.workspace(savedSnapshot)
            let didWarn = reportCommittedMutationWarnings(outcome)
            if !didWarn {
                presentFeedback(String(
                    localized: "Metadata saved",
                    table: "Localizable",
                    bundle: .module
                ))
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

    func reloadMetadata(
        for path: String
    ) async throws -> (note: WindowDocumentLocation, revision: DocumentFingerprint?) {
        guard let current = notes.first(where: { $0.relativePath == path })
                ?? (currentNote?.relativePath == path ? currentNote : nil),
              let snapshot = current.workspaceSnapshot else {
            throw VaultRepositoryError.fileDoesNotExist(path)
        }
        let metadata = try await documentController.metadata(snapshot.id)
        let refreshed: WindowDocumentLocation
        if let metadata {
            let updated = snapshot.applyingCommittedMetadata(metadata)
            replaceCachedWorkspaceNote(updated)
            refreshed = .workspace(updated)
        } else {
            refreshed = current
        }
        return (refreshed, metadata?.revision)
    }

    func presentFeedback(
        _ message: String,
        kind: ScholiumFeedbackKind = .confirmation
    ) {
        shellState.presentFeedback(message, kind: kind)
    }

    #if DEBUG
    func presentQAActionNotificationProof() {
        guard Bundle.main.bundleIdentifier == "com.scholium.qa",
              ProcessInfo.processInfo.arguments.contains(
                  "--scholium-feedback-proofs"
              ),
              let triptychID = workspaceAssignment?.id else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await researchController.researchSnapshot()
                guard workspaceAssignment?.id == triptychID else { return }
                let notifications = QAActionNotificationProof.notifications(
                    triptychID: triptychID,
                    arrivals: snapshot.resultArrivals
                )
                guard !notifications.isEmpty else {
                    presentQAActionNotificationProofUnavailable()
                    return
                }
                shellState.presentQAResearchActivityNotifications(notifications)
            } catch {
                guard workspaceAssignment?.id == triptychID else { return }
                presentQAActionNotificationProofUnavailable()
            }
        }
    }

    private func dismissQAActionNotificationProof(
        _ notification: ResearchActivityNotification
    ) -> Bool {
        shellState.dismissQAResearchActivityNotification(
            runID: notification.runID
        )
    }

    private func presentQAActionNotificationProofUnavailable() {
        presentFeedback(
            String(
                localized: "QA Action notification proof is unavailable until the Triptych research projection is ready.",
                table: "Localizable",
                bundle: .module
            ),
            kind: .information
        )
    }
    #endif

    /// Presents post-commit repair truth without turning a durable file
    /// operation into a retryable failure. Returns `true` when a warning was
    /// shown so callers do not immediately add a redundant confirmation.
    @discardableResult
    private func reportCommittedMutationWarnings<CommittedValue: Sendable>(
        _ outcome: WorkspaceMutationOutcome<CommittedValue>,
        presentationWarning: String? = nil
    ) -> Bool {
        reportCommittedMutationWarnings(
            derivedRefreshWarnings: outcome.derivedRefreshWarning.map { [$0] } ?? [],
            identityRecoveryWarnings: outcome.identityRecoveryWarning.map { [$0] } ?? [],
            portableMetadataRecoveryWarnings: outcome.portableMetadataRecoveryWarning.map { [$0] } ?? [],
            presentationWarning: presentationWarning
        )
    }

    @discardableResult
    private func reportCommittedMutationWarnings(
        derivedRefreshWarnings: [String],
        identityRecoveryWarnings: [String],
        portableMetadataRecoveryWarnings: [String] = [],
        presentationWarning: String? = nil
    ) -> Bool {
        var messages: [String] = []
        if !derivedRefreshWarnings.isEmpty {
            messages.append(String(
                localized: "The file operation completed, but Library, Search, or other derived views may be stale. Use Refresh instead of repeating the action.",
                table: "Localizable",
                bundle: .module
            ))
            messages.append(derivedRefreshWarnings.joined(separator: " "))
        }
        if !identityRecoveryWarnings.isEmpty {
            messages.append(String(
                localized: "The file operation completed, but stable note identity recovery is incomplete. Identity-dependent actions remain unavailable until recovery succeeds.",
                table: "Localizable",
                bundle: .module
            ))
            messages.append(identityRecoveryWarnings.joined(separator: " "))
        }
        if !portableMetadataRecoveryWarnings.isEmpty {
            messages.append(String(
                localized: "The file operation completed, but portable Note metadata recovery is incomplete. Inspect Metadata before continuing.",
                table: "Localizable",
                bundle: .module
            ))
            messages.append(portableMetadataRecoveryWarnings.joined(separator: " "))
        }
        if let presentationWarning {
            messages.append(String(
                localized: "The file operation completed, but this window could not refresh its document view. Use Refresh instead of repeating the action.",
                table: "Localizable",
                bundle: .module
            ))
            messages.append(presentationWarning)
        }
        guard !messages.isEmpty else { return false }
        presentFeedback(messages.joined(separator: " "), kind: .warning)
        return true
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
        let sourceScope = noteSourceScope
        guard refreshGeneration == identityRefreshGeneration,
              currentRegisteredVault?.id == vault.id,
              noteSourceScope == sourceScope else { return }
        let recovery: NoteIdentityRecoveryState
        let vaultSnapshot: WorkspaceVaultSnapshot
        do {
            guard let snapshot = try await documentController.workspaceSnapshot(
                vaultID: vault.id
            ) else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            vaultSnapshot = snapshot
            recovery = snapshot.identityRecovery
        } catch {
            guard refreshGeneration == identityRefreshGeneration,
                  currentRegisteredVault?.id == vault.id,
                  noteSourceScope == sourceScope else { return }
            noteIdentityByPath = [:]
            identityResolutionError = error.localizedDescription
            return
        }
        guard refreshGeneration == identityRefreshGeneration,
              currentRegisteredVault?.id == vault.id,
              noteSourceScope == sourceScope else { return }
        installIdentityState(
            recovery,
            vault: vault,
            sourceScope: sourceScope,
            refreshGeneration: refreshGeneration,
            visibleSnapshots: vaultSnapshot.documents
        )
    }

    /// Applies identity state carried by the exact accepted Workspace
    /// generation. Publication callers must not ask Application to return the
    /// same snapshot again before Document restoration can continue.
    private func refreshIdentityState(from vaultSnapshot: WorkspaceVaultSnapshot) {
        identityRefreshGeneration &+= 1
        let refreshGeneration = identityRefreshGeneration
        guard let vault = currentRegisteredVault,
              vault.id == vaultSnapshot.vault.id else { return }
        let sourceScope = noteSourceScope
        installIdentityState(
            vaultSnapshot.identityRecovery,
            vault: vault,
            sourceScope: sourceScope,
            refreshGeneration: refreshGeneration,
            visibleSnapshots: nil
        )
    }

    private func installIdentityState(
        _ recovery: NoteIdentityRecoveryState,
        vault: RegisteredVault,
        sourceScope: LibrarySourceScope,
        refreshGeneration: UInt64,
        visibleSnapshots: [WorkspaceNoteSnapshot]?
    ) {
        guard refreshGeneration == identityRefreshGeneration,
              currentRegisteredVault?.id == vault.id,
              noteSourceScope == sourceScope else { return }
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
        if let visibleSnapshots {
            let snapshots = Dictionary(
                uniqueKeysWithValues: visibleSnapshots.map { ($0.id.relativePath, $0) }
            )
            workspaceProjectionController.refreshVisibleNoteSnapshots(snapshots)
        }
        refreshSelectedDocumentProjection()
    }

    private func resetWindowSession() {
        libraryRevealTask?.cancel()
        libraryRevealTask = nil
        requestedWorkspaceSelection = nil
        presentationRouter.dismissAll()
        documentController.removeAll(retainingSessions: true)
        documentTabController.removeAll()
        documentNavigationHistoryController.removeAll()
        searchController.resetExecution()
        discoveryController.reset()
        researchController.reset()
        workspaceProjectionController.reset()
        shellState.resetWorkspaceSessions()
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

    fileprivate func receiveWorkspaceEvents(_ events: [UUID: WorkspaceEvent]) {
        guard let capabilities = windowWorkspaceController.activeCapabilities,
              let event = events[capabilities.id] else { return }
        guard workspaceProjectionController.canReceive(
            event,
            runtimeIdentity: capabilities.runtimeIdentity
        ) else { return }

        if case .vaultAccessInvalidated(let invalidation) = event,
           let path = WorkspaceVaultSlot.allCases.compactMap({ slot -> String? in
               guard let vaultID = workspaceAssignment?.vault(for: slot)?.id else {
                   return nil
               }
               return invalidation.unavailableVaultPaths[vaultID]
           }).first {
            _ = windowWorkspaceController.recordRecovery(
                for: WorkspaceRegistryError.vaultAccessUnavailable(path)
            )
        }

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

        let documentReconciliation = documentController.receive(
            event.snapshot,
            openDocuments: documentTabController.allTabs.map(\.document)
        )
        researchController.receive(event.snapshot)
        researchAgentPermissionWindowController.refreshForWorkspaceSnapshot(
            triptychID: event.snapshot.triptych.id
        )
        if let commit = workspaceProjectionController.receive(
            event,
            runtimeIdentity: capabilities.runtimeIdentity,
            context: workspaceProjectionContext
        ) {
            applyWorkspaceProjectionCommit(
                commit,
                documentReconciliation: documentReconciliation
            )
        }
    }

    private var workspaceProjectionContext: WindowWorkspaceProjectionContext {
        WindowWorkspaceProjectionContext(
            selectedVaultID: currentRegisteredVault?.id,
            sourceScope: noteSourceScope,
            currentDocumentVaultID: currentDocumentVaultID,
            selectedDocumentPath: selectedDocumentPath,
            retainedDeletedDocumentPath: documentController.retainedDeletedDocumentPath
        )
    }

    private func applyWorkspaceProjectionCommit(
        _ commit: WindowWorkspaceProjectionCommit,
        documentReconciliation: DocumentWorkspaceReconciliation = .unchanged
    ) {
        refreshDocumentTabProjections()
        removeExternallyDeletedDocumentTabs(
            documentReconciliation.removedDocuments
        )
        if commit.searchGenerationChanged {
            searchController.searchGenerationDidChange()
        }
        switch commit.derivedRefreshStatus {
        case .opening:
            if refreshStatusText?.hasPrefix("Conflict:") != true {
                refreshStatusText = String(localized: "Refreshing derived state…")
            }
        case .current:
            if refreshStatusText == String(localized: "Refreshing derived state…")
                || refreshStatusText == "Derived state is stale"
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
        if commit.retainedDeletedDocumentPath != nil {
            refreshStatusText = "Conflict: note deleted outside Scholium"
        }
        if let vaultID = currentRegisteredVault?.id,
           let vaultSnapshot = workspaceProjectionController.vaultSnapshot(id: vaultID) {
            refreshIdentityState(from: vaultSnapshot)
        }
    }

    private func replaceCachedWorkspaceNote(_ note: WorkspaceNoteSnapshot) {
        guard let vault = workspaceProjectionController.recordCommittedNote(
            note,
            visibleVaultID: currentRegisteredVault?.id,
            visibleSourceScope: noteSourceScope
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
            let graphCounts: WorkspaceGraphCounts
            if let previous {
                metadata = WorkspaceFileMetadata(
                    byteCount: document.sourceBytes.count,
                    creationDate: previous.fileMetadata.creationDate,
                    modificationDate: previous.fileMetadata.modificationDate
                )
                identity = previous.stableIdentity
                graphCounts = previous.graphCounts
            } else {
                metadata = WorkspaceFileMetadata(
                    byteCount: document.sourceBytes.count,
                    creationDate: nil,
                    modificationDate: nil
                )
                identity = .resolved(context.noteID)
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
                graphCounts: graphCounts,
                metadata: previous?.metadata,
                headings: semantic.headings,
                derivedProjectionState: .sourceAhead,
                cachedSemanticDocument: semantic,
                cachedTitleProjection: WorkspaceNoteTitleProjection(
                    document: document,
                    vaultRole: context.vaultRole,
                    metadata: previous?.metadata,
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
