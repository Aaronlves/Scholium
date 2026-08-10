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
final class ScholiumApplicationDelegate: NSObject, NSApplicationDelegate {
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
        .windowStyle(.hiddenTitleBar)
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
                        lifecycleRegistry: applicationDelegate.windowLifecycleRegistry,
                        researchRecordsWindowCoordinator:
                            applicationDelegate.researchRecordsWindowCoordinator,
                        researchResultNotificationCoordinator:
                            applicationDelegate.researchResultNotificationCoordinator
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

        WindowGroup(
            "Research Records",
            id: "scholium-research-records",
            for: UUID.self,
            content: { triptychID in
                ApplicationBootstrapGate(controller: applicationBootstrap) { workspaceStore in
                    ScholiumResearchRecordsRoot(
                        workspaceStore: workspaceStore,
                        triptychID: triptychID.wrappedValue,
                        coordinator: applicationDelegate.researchRecordsWindowCoordinator
                    )
                }
            },
            defaultValue: { UUID() }
        )
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 760, height: 680)
        .windowResizability(.contentMinSize)
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
            usesFullHeightContent: browserModel.route.recordID != nil
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
        }
        .onReceive(workspaceStore.$workspaceActivations) { activations in
            guard let activation = activations[triptychID] else { return }
            capabilities = activation.capabilities
            recordLoadIssues = researchRecordIssues(in: activation.snapshot)
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
                    saveResponse: {
                        recordID, draft, expectedEvaluationRevision,
                        expectedMethodFeedbackRevision, resultFingerprint in
                        try await capabilities.research.records
                            .saveResearcherResponse(
                                recordID: recordID,
                                draft: draft,
                                expectedEvaluationRevision: expectedEvaluationRevision,
                                expectedMethodFeedbackRevision:
                                    expectedMethodFeedbackRevision,
                                expectedResultFingerprint: resultFingerprint
                            )
                    },
                    reloadRecord: { recordID in
                        let records = try await capabilities.research.records
                            .finishedResearchRecords(noteID: nil)
                        guard let record = records.first(where: {
                            $0.id == recordID
                        }) else {
                            throw PortableResearcherResponseMutationError
                                .recordUnavailable
                        }
                        return record
                    },
                    changeReviewState: { recordID in
                        try await capabilities.research.records
                            .researchRecordChangeReviewState(recordID: recordID)
                    },
                    keepChanges: {
                        recordID, expectedReviewRevision, resultFingerprint in
                        try await capabilities.research.records
                            .keepResearchRecordChanges(
                                recordID: recordID,
                                expectedReviewRevision: expectedReviewRevision,
                                expectedResultFingerprint: resultFingerprint
                            )
                    },
                    finishReview: {
                        recordID, expectedReviewRevision, resultFingerprint in
                        try await capabilities.research.records
                            .finishResearchRecordReviewWithCurrentState(
                                recordID: recordID,
                                expectedReviewRevision: expectedReviewRevision,
                                expectedResultFingerprint: resultFingerprint
                            )
                    },
                    comparison: { recordID, noteID in
                        try await capabilities.research.records
                            .researchRecordComparison(
                                recordID: recordID,
                                noteID: noteID
                            )
                    },
                    undoChanges: {
                        recordID, noteIDs, expectedReviewRevision,
                        resultFingerprint in
                        try await capabilities.research.records
                            .undoResearchRecordChanges(
                                recordID: recordID,
                                selectedNoteIDs: noteIDs,
                                expectedReviewRevision: expectedReviewRevision,
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
            } else {
                let research = try await capabilities.research.records.snapshot()
                records = research.finishedResearchRecords
                fingerprints = research.finishedResearchRecordFingerprints
                recordLoadIssues = []
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
            commandLineToolStatus: { await model.commandLineToolStatus() },
            installCommandLineTool: { try await model.installCommandLineTool() },
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
    private let commandLineToolInstaller = CommandLineToolInstaller()
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

    func commandLineToolStatus() async -> CommandLineToolStatus {
        await commandLineToolInstaller.commandLineToolStatus()
    }

    func installCommandLineTool() async throws -> CommandLineToolStatus {
        try await commandLineToolInstaller.installCommandLineTool()
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
    private let route: TriptychWindowRoute
    private let lifecycleRegistry: ScholiumWindowLifecycleRegistry
    private let researchRecordsWindowCoordinator: ResearchRecordsWindowCoordinator
    private let researchResultNotificationCoordinator:
        ResearchResultNotificationCoordinator
    @State private var destinationBootstrapWindowID: UUID?

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
        self.route = route
        self.lifecycleRegistry = lifecycleRegistry
        self.researchRecordsWindowCoordinator = researchRecordsWindowCoordinator
        self.researchResultNotificationCoordinator =
            researchResultNotificationCoordinator
    }

    var body: some View {
        Group {
            if shellState.hasCompletedInitialRestore, appState.vaultConfig != nil {
                ContentView(
                    appState: appState,
                    windowCoordinator: windowCoordinator
                )
            } else {
                ScholiumLaunchPlaceholderView()
            }
        }
            .toolbar(removing: .sidebarToggle)
            .tint(ScholiumColorRole.accent.color)
            .focusedSceneObject(appState)
            .focusedSceneObject(appState.commandObservation)
            .focusedSceneValue(\.scholiumWorkspaceWindowActions, windowCoordinator.actions)
            .background(
                WorkspaceWindowAttachment(coordinator: windowCoordinator)
            )
            .fileImporter(
                isPresented: Binding(
                    get: { presentationRouter.fileImport == .markdown },
                    set: { presentationRouter.fileImport = $0 ? .markdown : nil }
                ),
                allowedContentTypes: [UTType(filenameExtension: "md") ?? .plainText],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    appState.requestMarkdownImport(urls)
                case .failure(let error):
                    appState.vaultError = error.localizedDescription
                }
            }
            .sheet(item: Binding(
                get: { windowWorkspaceController.state.accessRecovery },
                set: { windowWorkspaceController.setAccessRecovery($0) }
            )) { recovery in
                RestoreWorkspaceAccessView(
                    recovery: recovery,
                    restore: { try await appState.restoreWorkspaceAccess(using: $0) },
                    closeWindow: { dismissWindow() }
                )
            }
            .preferredColorScheme(shellState.colorScheme.swiftUIColorScheme)
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
                    showAttention: { anchor, workspaceSlot, noteScope in
                        appState.attentionPopoverSession.present(
                            from: anchor,
                            workspaceSlot: workspaceSlot,
                            noteScope: noteScope
                        )
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
            .onDisappear {
                windowCoordinator.detach()
                appState.persistWindowSessionNow()
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
    @FocusedObject private var commandObservation: WindowCommandObservation?
    @FocusedValue(\.scholiumSearchActions) private var searchActions
    @FocusedValue(\.scholiumWorkspaceWindowActions) private var workspaceWindowActions
    @FocusedValue(\.scholiumResearchActionActions) private var researchActionActions
    @FocusedValue(\.scholiumEditorActions) private var editorActions
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        let _ = commandObservation?.revision
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
            Button("Rename Note…") {
                guard let note = appState?.currentNote,
                      let target = NoteLifecycleTarget(note) else { return }
                appState?.noteLifecycleRequest = .rename(target)
            }
            .disabled(appState?.currentDocumentCapabilities.allows(.move) != true)
            Button("Move Note…") {
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
            Button("Italic") { editorActions?.perform(.emphasis) }
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
            Button("Markdown Comment") { editorActions?.perform(.markdownComment) }
                .disabled(editorActions?.isAvailable(.markdownComment) != true)
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
                        Text(verbatim: action.buttonName)
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
            Button("Triptych Records") {
                workspaceWindowActions?.showTriptychResearchRecords()
            }
            .disabled(
                appState?.workspaceAssignment == nil
                    || workspaceWindowActions == nil
            )
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

    struct MarkdownImportFailure: Sendable {
        let sourceName: String
        let reason: String
    }

    struct MarkdownImportBatchOutcome: Sendable {
        let destinationName: String
        let documents: [NoteDocument]
        let failures: [MarkdownImportFailure]
        let derivedRefreshWarnings: [String]
        let identityRecoveryWarnings: [String]
        let cleanupWarnings: [SaveCleanupWarning]
        let presentationWarning: String?

        init(
            destinationName: String,
            documents: [NoteDocument],
            failures: [MarkdownImportFailure],
            derivedRefreshWarnings: [String],
            identityRecoveryWarnings: [String],
            cleanupWarnings: [SaveCleanupWarning] = [],
            presentationWarning: String?
        ) {
            self.destinationName = destinationName
            self.documents = documents
            self.failures = failures
            self.derivedRefreshWarnings = derivedRefreshWarnings
            self.identityRecoveryWarnings = identityRecoveryWarnings
            self.cleanupWarnings = cleanupWarnings
            self.presentationWarning = presentationWarning
        }
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

    private enum WindowFileTreeMutationError: LocalizedError {
        case folderMutationInProgress

        var errorDescription: String? {
            switch self {
            case .folderMutationInProgress:
                String(
                    localized: "Another folder operation is already in progress.",
                    table: "Localizable",
                    bundle: .module
                )
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
        let location: NoteLocationScope
        let vaultSnapshot: WorkspaceVaultSnapshot
        let vaultConfig: VaultConfig
        let notes: [WindowDocumentLocation]
        let request: DiscoveryLocationRequest?
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
    private let libraryTreeProjectionCache = LibraryTreeProjectionCache()
    lazy var commandObservation = WindowCommandObservation(
        shellState: shellState,
        workspaceController: windowWorkspaceController,
        discoveryController: discoveryController,
        documentController: documentController,
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
            refresh: { [weak self] in
                await self?.refreshWorkspaceCatalog()
            },
            resynthesize: { [weak self] item in
                self?.requestResynthesis(item)
            }
        )
    )
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
    private var libraryRevealTask: Task<Void, Never>?
    private var requestedWorkspaceSelection: WorkspaceVaultSlot?
    private var markdownImportTask: Task<Void, Never>?
    private var researchActionOpenRequestID: UUID?
    private var discussionPresentationRequestID: UUID?
    private var isRestoringWindowSession = false
    private var didRestoreWindowSession = false
    private var closeAttemptSequence: UInt64 = 0
    private var currentCloseAttemptID = LifecycleAttemptID(rawValue: 0)
    private var identityRefreshGeneration: UInt64 = 0
    private let documentPresentationDidChange = PassthroughSubject<Void, Never>()
    private var presentResearchRecordSearchResult:
        @MainActor (RecordSearchResult) -> Void = { _ in }
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
        cssSnippetStore = workspaceStore.cssSnippetStore
        zoteroBridge = workspaceStore.zoteroBridge
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

    func bindResearchRecordSearchPresentation(
        _ present: @escaping @MainActor (RecordSearchResult) -> Void
    ) {
        presentResearchRecordSearchResult = present
    }

    deinit {
        researchActionOpenTask?.cancel()
        libraryRevealTask?.cancel()
        markdownImportTask?.cancel()
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
        let lifecycle = currentNote?.workspaceSnapshot?.lifecycle ?? .active
        return snapshot.documents
            .filter { $0.lifecycle == lifecycle }
            .map(WindowDocumentLocation.workspace)
            .sorted(by: notesAreOrdered)
    }

    var currentLibraryFolders: [String] {
        guard let vaultID = currentRegisteredVault?.id,
              let snapshot = workspaceProjectionController.vaultSnapshot(
                  id: vaultID
              ) else { return [] }
        let lifecycle = noteLocationScope.documentLifecycle
        return snapshot.folders
            .map(\.rawValue)
            .filter {
                WorkspaceDocumentLifecycle(
                    relativePath: $0 + "/placeholder.md"
                ) == lifecycle
            }
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

    var currentResearchFunctionTarget: ResearchFunctionTarget? {
        guard let descriptor = currentDocumentDescriptor,
              let note = currentNote,
              note.workspaceSnapshot?.derivedProjectionState == .current,
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
        researchController.setActiveDocument(currentResearchFunctionReference)
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
            let outcome = try await documentController.resolveIdentity(
                ambiguity,
                candidateID: candidateID
            )
            selectedIdentityAmbiguity = nil
            await refreshIdentityState()
            reportCommittedMutationWarnings(outcome)
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

    private func flushRegisteredEditorIfMutatingActiveDocument(
        _ target: NoteLifecycleTarget
    ) async throws {
        guard WorkspaceDocumentLifecycle(relativePath: target.relativePath) == .active,
              let descriptor = currentDocumentDescriptor,
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
        return ClosePreparationOutcome(presentationWarning: presentationWarning)
    }

    /// Releases cross-window flush capabilities only after AppKit has
    /// committed to closing this exact window. A successful prepare can be
    /// followed by a cancelled application quit when another window fails;
    /// preparation therefore cannot surrender this still-open window's save
    /// ownership.
    func finalizeWindowClose() {
        markdownImportTask?.cancel()
        markdownImportTask = nil
        libraryRevealTask?.cancel()
        libraryRevealTask = nil
        editorFlushCoordinator.shutdown()
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
        case .result(.note(let note)):
            let reference = VaultNoteReference(
                vaultID: note.vaultID,
                vaultName: note.vaultName,
                vaultRole: note.vaultRole,
                relativePath: note.relativePath,
                stableNoteID: note.stableNoteID
            )
            let isCurrentDocument = currentDocumentDescriptor?.reference.vaultID == note.vaultID
                && currentDocumentDescriptor?.reference.relativePath == note.relativePath
            if isCurrentDocument {
                pendingSourceRange = note.sourceRange
                pendingSourceLine = note.sourceRange?.line ?? note.sourceLine
                requestPresentationMode = .source
            } else if disposition == .newTab {
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
        guard item.kind == .materialChangedSinceUse,
              let context = item.materialChangedSinceUse else { return }
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
                || destination.locationError != nil else { return }
        requestedWorkspaceSelection = slot
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            let targetTab = self.documentTabController.selectedTab(in: slot)
            try await self.prepareWorkspaceSelection(
                slot,
                location: destination.locationScope,
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

    func putBackNote(_ target: NoteLifecycleTarget) async throws {
        // Set Aside and Trash documents are read-only. A rapid Put Back may
        // race the previous read presentation's editor-host teardown, so an
        // unrelated current-editor flush would reject the safe source move as
        // a stale registration. The lifecycle revision below is the complete
        // write authority for this direct reversible operation.
        let outcome: WorkspaceMutationOutcome<TriptychMoveCommit>
        do {
            outcome = try await documentController.putBack(target)
        } catch {
            await refreshTransactionRecoveryRecords()
            throw error
        }
        let commit = outcome.committedValue
        let presentationWarning = await presentCommittedLifecycleMove(
            commit,
            noteID: target.stableNoteID,
            identityResolved: outcome.identityRecoveryWarning == nil,
            vaultID: target.documentID.vaultID
        )
        scheduleWorkspaceCatalogRefresh()
        reportCommittedMutationWarnings(
            outcome,
            presentationWarning: presentationWarning
        )
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
        documentController.rememberPresentationMode(mode)
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

    func openResearchActionStatus(
        _ activity: WorkspaceResearchActivity,
        relatedResult: WorkspaceResearchActivity?
    ) {
        guard let target = currentResearchActionTarget,
              target.noteID == activity.targetNoteID,
              let reference = currentResearchFunctionReference,
              !researchController.actions.hasCancellationBarrier else { return }
        let availability = researchController.actions.availability.first {
            $0.id == activity.actionID
        }
        let presentationID = UUID()
        guard researchController.actions.beginStatus(
            target: target,
            availability: availability,
            activity: activity,
            relatedResult: relatedResult,
            presentationID: presentationID
        ) else { return }
        researchController.requestPresentAction(
            activity.actionID,
            target: reference,
            presentationID: presentationID
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
        switch noteSortOrder {
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
        return lhs.displayName.localizedStandardCompare(
            rhs.displayName
        ) == .orderedAscending
    }

    var hasScopedDebateImportanceFilter: Bool {
        selectedPropertyKey == "debate_importance_scope"
            && selectedPropertyValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var availableAuthors: [String] {
        workspaceProjectionController.authors
    }

    var availableYears: [Int] {
        workspaceProjectionController.years
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
            showToast(String(localized: "The saved window layout could not be restored. Scholium opened a clean window instead.", table: "Localizable", bundle: .module), kind: .warning)
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

        await refreshRegisteredVaults()
        await refreshWorkspaceAssignment(
            preferredTriptychID: requestedTriptychID ?? stored.triptychID
        )
        guard let restoredAssignment = workspaceAssignment else {
            attemptedVaultRestore = true
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
            attemptedVaultRestore = true
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
            guard let session = restoredPresentation.workspaceSession(for: workspace),
                  let location = NoteLocationScope(rawValue: session.location) else {
                continue
            }
            discoveryController.synchronizeLibrarySelection(
                workspaceSlot: workspace,
                location: location
            )
            if let vaultID = session.vaultID {
                documentController.restorePresentationState(
                    scrollPositions: session.scrollPositions,
                    vaultID: vaultID
                )
            }
        }
        if discoveryController.libraryState(for: selectedWorkspace).locationScope
            != .workspace {
            do {
                try await prepareWorkspaceSelection(
                    selectedWorkspace,
                    location: discoveryController.libraryState(
                        for: selectedWorkspace
                    ).locationScope
                )
            } catch {
                vaultError = error.localizedDescription
                return
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

        for workspace in WorkspaceVaultSlot.allCases {
            guard let session = restoredPresentation.workspaceSession(for: workspace) else {
                continue
            }
            let tabs = session.openDocuments.compactMap(restoredDocumentTab)
            let selectedID = session.selectedDocument.flatMap { selected in
                tabs.first { tab in
                    vaultQualifiedID(for: tab.document) == selected
                }?.id
            }
            documentTabController.restoreTabs(
                tabs,
                selectedTabID: selectedID,
                in: workspace
            )
        }

        if let requestedInitialDocument {
            do {
                try activateWorkspaceReferenceInSelectedWorkspace(
                    requestedInitialDocument,
                    tabActivation: .place(.replaceSelected)
                )
            } catch {
                documentController.clearSelectionAfterClosingLastTab()
                showToast(error.localizedDescription, kind: .warning)
            }
        } else if let selected = documentTabController.selectedTab(
            in: selectedWorkspace
        )?.document {
            do {
                try activateDocumentInSelectedWorkspace(
                    selected,
                    tabActivation: .preserveTabMembership
                )
            } catch {
                documentController.clearSelectionAfterClosingLastTab()
                showToast(error.localizedDescription, kind: .warning)
            }
        }
        reconcileDocumentSessionLeases()

        let hasRestorableDocument = documentTabController.selectedTab(
            in: selectedWorkspace
        ) != nil
        shellState.restoreLibraryVisibility(
            hasRestorableDocument
                ? (restoredPresentation.libraryVisible ?? true)
                : true
        )
        discoveryController.replaceSearchCriteria(SearchWorkspaceState(
            scope: restoredPresentation.searchState.scope
        ))
        shellState.setDocumentTextScale(
            restoredPresentation.documentTextScale
                ?? ScholiumMetrics.Document.defaultTextScale
        )
    }

    func persistWindowSessionNow() {
        guard didRestoreWindowSession,
              !isRestoringWindowSession,
              !windowSessionPersistenceCoordinator.isFinalizing else { return }
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
                location: discoveryController.libraryState(for: workspace)
                    .locationScope.rawValue,
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
                .map { $0.assignment?.id }
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
            $currentRegisteredVault.map { _ in () }.eraseToAnyPublisher(),
            documentController.$selectedDocument.map { _ in () }.eraseToAnyPublisher(),
            documentController.$currentPresentationMode.map { _ in () }.eraseToAnyPublisher(),
            shellState.$libraryVisible.map { _ in () }.eraseToAnyPublisher(),
            shellState.$documentTextScale.map { _ in () }.eraseToAnyPublisher(),
            shellState.$selectedWorkspace.map { _ in () }.eraseToAnyPublisher(),
            shellState.$inspector.map { _ in () }.eraseToAnyPublisher(),
            discoveryController.$search.map { _ in () }.eraseToAnyPublisher(),
        ]
        let changes = stateChanges.map { $0.dropFirst().eraseToAnyPublisher() }
            + [
                documentTabController.objectWillChange.eraseToAnyPublisher(),
                discoveryController.objectWillChange.eraseToAnyPublisher(),
                documentPresentationDidChange.eraseToAnyPublisher(),
            ]
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
        case .unavailablePreserving(let assignments, let assignment, let message):
            registeredTriptychs = assignments
            workspaceAssignment = assignment
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
        registeredVaults = try await workspaceStore.registeredVaults()
        registeredTriptychs = try await workspaceStore.registeredTriptychs()
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
        await refreshTransactionRecoveryRecords()
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
            documentDidCommit: { [weak self] result in
                guard let self else { return }
                _ = await self.replaceSavedDocument(result.document)
                if let warning = result.cleanupWarning {
                    self.reportCommittedMutationWarnings(
                        derivedRefreshWarnings: [],
                        identityRecoveryWarnings: [],
                        cleanupWarnings: [warning]
                    )
                }
            }
        )
        researchController.bind(
            to: ResearchControllerCapabilities(
                documents: capabilities.documents,
                records: capabilities.research.records,
                checkpoints: capabilities.research.checkpoints,
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
            await self?.workspaceStore.refreshPendingResearchAgentPermissions(
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
        researchAgentPermissionWindowController.refreshForWorkspaceSnapshot(
            triptychID: activation.snapshot.triptych.id
        )
    }

    func saveTriptychSettings(_ settings: TriptychSettings) async throws {
        try await researchController.saveSettings(settings)
        triptychSettings = settings
    }

    var currentWorkspaceSlot: WorkspaceVaultSlot? {
        let selected = shellState.selectedWorkspace
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
        if !result.cleanupWarnings.isEmpty {
            reportCommittedMutationWarnings(
                derivedRefreshWarnings: [],
                identityRecoveryWarnings: [],
                cleanupWarnings: result.cleanupWarnings
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

    func requestMarkdownImport(_ urls: [URL]) {
        guard markdownImportTask == nil else {
            showToast(
                String(
                    localized: "A Markdown import is already in progress.",
                    table: "Localizable",
                    bundle: .module
                ),
                kind: .information
            )
            return
        }

        markdownImportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.markdownImportTask = nil }
            do {
                let outcome = try await self.importMarkdownFiles(urls)
                try Task.checkCancellation()
                self.presentMarkdownImportOutcome(outcome)
            } catch is CancellationError {
                // Closing the owning window cancels the remaining batch. Any
                // files committed before cancellation remain authoritative and
                // will be discovered by the next bounded workspace refresh.
            } catch {
                self.vaultError = error.localizedDescription
            }
        }
    }

    func importMarkdownFiles(_ urls: [URL]) async throws -> MarkdownImportBatchOutcome {
        guard let vault = currentRegisteredVault,
              let destinationWorkspaceID = workspaceAssignment?.id else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        var imported: [NoteDocument] = []
        var failures: [MarkdownImportFailure] = []
        var derivedRefreshWarnings: [String] = []
        var identityRecoveryWarnings: [String] = []
        var cleanupWarnings: [SaveCleanupWarning] = []
        for url in urls {
            try Task.checkCancellation()
            guard workspaceAssignment?.id == destinationWorkspaceID else {
                throw CancellationError()
            }
            do {
                let outcome = try await documentController.importMarkdown(
                    at: url,
                    intoVault: vault.id
                )
                imported.append(outcome.committedValue)
                if let warning = outcome.derivedRefreshWarning {
                    derivedRefreshWarnings.append(warning)
                }
                if let warning = outcome.identityRecoveryWarning {
                    identityRecoveryWarnings.append(warning)
                }
                cleanupWarnings.append(contentsOf: outcome.cleanupWarnings)
                guard workspaceAssignment?.id == destinationWorkspaceID else {
                    throw CancellationError()
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append(MarkdownImportFailure(
                    sourceName: url.lastPathComponent,
                    reason: error.localizedDescription
                ))
            }
        }

        var presentationWarning: String?
        if !imported.isEmpty {
            guard workspaceAssignment?.id == destinationWorkspaceID else {
                throw CancellationError()
            }
            do {
                try await refreshCachedWorkspaceVaultSnapshot(vaultID: vault.id)
                if currentRegisteredVault?.id == vault.id {
                    try await browseRegisteredVault(vault)
                }
            } catch {
                presentationWarning = error.localizedDescription
            }
        }

        return MarkdownImportBatchOutcome(
            destinationName: workspaceSlot(for: vault)?.displayName ?? vault.name,
            documents: imported,
            failures: failures,
            derivedRefreshWarnings: derivedRefreshWarnings,
            identityRecoveryWarnings: identityRecoveryWarnings,
            cleanupWarnings: cleanupWarnings,
            presentationWarning: presentationWarning
        )
    }

    func presentMarkdownImportOutcome(_ outcome: MarkdownImportBatchOutcome) {
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
        if !outcome.cleanupWarnings.isEmpty {
            warnings.append(String(
                localized: "The imported source is committed, but machine-local cleanup is still pending. Do not import the files again; Scholium will retry cleanup when the vault reopens.",
                table: "Localizable",
                bundle: .module
            ))
            warnings.append(localizedCleanupWarnings(outcome.cleanupWarnings).joined(separator: " "))
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
            showToast(successSummary)
        } else {
            showToast(([successSummary] + warnings).joined(separator: " "), kind: .warning)
        }
    }

    func copyTextToClipboard(_ text: String, recovery: String? = nil) throws {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else {
            throw ClipboardWorkflowError.copyFailed(recovery: recovery)
        }
    }

    func refreshRegisteredVaults() async {
        do {
            let vaults = try await workspaceStore.registeredVaults()
            let triptychs = try await workspaceStore.registeredTriptychs()
            registeredVaults = vaults
            registeredTriptychs = triptychs
        } catch {
            vaultError = error.localizedDescription
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
        location: NoteLocationScope,
        validateDestination: () throws -> Void = {}
    ) async throws {
        guard let vault = workspaceAssignment?.vault(for: slot) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let request = discoveryController.beginLocationRequest(
            workspaceSlot: slot,
            location: location,
            presentation: .stagedReplacement
        )
        do {
            let staged = try await stageRegisteredVault(
                vault,
                slot: slot,
                locationRequest: request
            )
            try validateDestination()
            try commitStagedWorkspaceLibrarySelection(staged)
        } catch {
            if discoveryController.isCurrentLocationRequest(request) {
                discoveryController.failLocationRequest(
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
        locationRequest: DiscoveryLocationRequest? = nil
    ) async throws {
        let staged = try await stageRegisteredVault(
            registered,
            slot: slot,
            locationRequest: locationRequest
        )
        try commitStagedWorkspaceLibrarySelection(staged)
        await refreshIdentityState()
        scheduleWorkspaceCatalogRefresh()
    }

    private func stageRegisteredVault(
        _ registered: RegisteredVault,
        slot: WorkspaceVaultSlot? = nil,
        locationRequest: DiscoveryLocationRequest? = nil
    ) async throws -> StagedWorkspaceLibrarySelection {
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

        guard let resolvedSlot = slot ?? workspaceSlot(for: registered) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let targetLocation = locationRequest?.location
            ?? discoveryController.libraryState(for: resolvedSlot).locationScope
        let lifecycle = targetLocation.documentLifecycle
        let targetNotes = vaultSnapshot.documents
            .filter { $0.lifecycle == lifecycle }
            .map(WindowDocumentLocation.workspace)
            .sorted(by: notesAreOrdered)

        if let locationRequest,
           !discoveryController.isCurrentLocationRequest(locationRequest) {
            throw CancellationError()
        }
        return StagedWorkspaceLibrarySelection(
            registeredVault: registered,
            workspace: resolvedSlot,
            location: targetLocation,
            vaultSnapshot: vaultSnapshot,
            vaultConfig: targetConfig,
            notes: targetNotes,
            request: locationRequest
        )
    }

    private func commitStagedWorkspaceLibrarySelection(
        _ staged: StagedWorkspaceLibrarySelection
    ) throws {
        if let request = staged.request,
           !discoveryController.isCurrentLocationRequest(request) {
            throw CancellationError()
        }
        currentRegisteredVault = staged.registeredVault
        currentVaultRole = staged.registeredVault.role
        vaultConfig = staged.vaultConfig
        if let request = staged.request {
            guard discoveryController.receiveLocationResult(for: request) else {
                throw CancellationError()
            }
        } else {
            discoveryController.synchronizeLibrarySelection(
                workspaceSlot: staged.workspace,
                location: staged.location
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
                shellState.selectWorkspace(slot)
                documentController.selectWorkspace(slot)
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
        let lifecycle = scope.documentLifecycle
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

    func requestUntitledNoteCreation(in folderRelativePath: String?) {
        guard !isCreatingNote else { return }
        isCreatingNote = true
        enqueueDocumentTransition(preservingCurrentEditorState: false, { [weak self] in
            guard let self else { return }
            guard noteLocationScope == .workspace,
                  let vault = currentRegisteredVault else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            let outcome = try await documentController.createUntitledNote(
                inVault: vault.id,
                folderRelativePath: folderRelativePath
            )
            let commit = outcome.committedValue
            let document = commit.document
            do {
                let sourceAheadSnapshot = commit.sourceAheadSnapshot
                guard workspaceProjectionController.recordCommittedNote(
                    sourceAheadSnapshot,
                    visibleVaultID: currentRegisteredVault?.id,
                    visibleLocationScope: noteLocationScope
                ) != nil else {
                    throw WorkspaceRegistryError.incompleteWorkspace
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
                        tabActivation: .place(.replaceSelected)
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
                let outcome = try await documentController.createUntitledFolder(
                    inVault: vault.id,
                    parentRelativePath: parentRelativePath
                )
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
                        showToast(
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
        guard !isMutatingFolder else {
            throw WindowFileTreeMutationError.folderMutationInProgress
        }
        guard target.vaultID == currentRegisteredVault?.id,
              let assignment = workspaceAssignment else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        isMutatingFolder = true
        defer { isMutatingFolder = false }
        try await editorFlushCoordinator.flushAllEditors(in: assignment.id)
        let outcome: WorkspaceMutationOutcome<FolderMoveCommit>
        do {
            outcome = try await documentController.moveFolder(
                inVault: target.vaultID,
                from: target.relativePath,
                to: destinationRelativePath
            )
        } catch {
            await refreshTransactionRecoveryRecords()
            throw error
        }
        let commit = outcome.committedValue
        projectFolderMove(
            commit,
            identityResolved: outcome.identityRecoveryWarning == nil
        )
        migrateFolderDisclosure(
            from: commit.sourceFolder.rawValue,
            to: commit.destinationFolder.rawValue,
            vaultID: target.vaultID
        )
        var presentationWarning: String?
        if outcome.identityRecoveryWarning == nil,
           let projection = workspaceProjectionController.recordCommittedFolderMove(
               commit,
               visibleVaultID: currentRegisteredVault?.id,
               visibleLocationScope: noteLocationScope
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

    func moveFolderToTrash(_ target: FolderLifecycleTarget) async throws {
        guard !isMutatingFolder else {
            throw WindowFileTreeMutationError.folderMutationInProgress
        }
        guard let assignment = workspaceAssignment,
              assignment.vaults.values.contains(where: {
                  $0.id == target.vaultID
              }) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let vaultID = target.vaultID
        isMutatingFolder = true
        defer { isMutatingFolder = false }
        try await editorFlushCoordinator.flushAllEditors(in: assignment.id)
        let outcome: WorkspaceMutationOutcome<FolderMoveCommit>
        do {
            outcome = try await documentController.moveFolderToTrash(
                inVault: vaultID,
                relativePath: target.relativePath
            )
        } catch {
            await refreshTransactionRecoveryRecords()
            throw error
        }
        let commit = outcome.committedValue
        projectFolderMove(
            commit,
            identityResolved: outcome.identityRecoveryWarning == nil
        )
        migrateFolderDisclosure(
            from: commit.sourceFolder.rawValue,
            to: nil,
            vaultID: vaultID
        )
        lifecycleMutationGeneration &+= 1
        var presentationWarning: String?
        if outcome.identityRecoveryWarning == nil,
           let projection = workspaceProjectionController.recordCommittedFolderMove(
               commit,
               visibleVaultID: currentRegisteredVault?.id,
               visibleLocationScope: noteLocationScope
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
            if WorkspaceDocumentLifecycle(relativePath: move.source.relativePath)
                != WorkspaceDocumentLifecycle(relativePath: move.destination.relativePath) {
                removePresentedDocumentAfterLifecycleMove(
                    sessionKey: sessionKey,
                    wasSelected: wasSelected
                )
            }
        }
    }

    private func expandFolderAncestors(_ relativePath: String, vaultID: UUID) {
        let visiblePath = libraryCategoryRelativeFolderPath(relativePath)
        guard !visiblePath.isEmpty else { return }
        let scope = LibraryDisclosureScope(vaultID: vaultID, locationScope: .workspace)
        var expanded = discoveryController.expandedFolders(in: scope)
        let parts = visiblePath.split(separator: "/").map(String.init)
        for count in 1...parts.count {
            expanded.insert(parts.prefix(count).joined(separator: "/"))
        }
        discoveryController.setExpandedFolders(expanded, in: scope)
    }

    private func revealCreatedNoteInLibrary(_ relativePath: String, vaultID: UUID) {
        let invalidatesDebateImportanceSort = noteSortOrder == .debateImportanceDescending
        let scope = LibraryDisclosureScope(vaultID: vaultID, locationScope: .workspace)
        discoveryController.prepareCreatedNoteReveal(
            relativePath: relativePath,
            folderAncestors: libraryFolderAncestors(forDocumentPath: relativePath),
            in: scope
        )
        if invalidatesDebateImportanceSort {
            noteSortOrder = .modifiedNewest
        }
    }

    private func migrateFolderDisclosure(
        from sourceRelativePath: String,
        to destinationRelativePath: String?,
        vaultID: UUID
    ) {
        let scope = LibraryDisclosureScope(vaultID: vaultID, locationScope: .workspace)
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

    @discardableResult
    func duplicateNote(
        _ target: NoteLifecycleTarget,
        to requestedPath: String
    ) async throws -> NoteDocument {
        try await flushRegisteredEditorIfMutatingActiveDocument(target)
        guard let vault = workspaceAssignment?.vaults.values.first(where: {
            $0.id == target.documentID.vaultID
        }) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let expected = try lifecycleExpectedRevision(for: target)
        let authorizedTarget = NoteLifecycleTarget(
            documentID: target.documentID,
            stableNoteID: target.stableNoteID,
            revision: expected
        )
        let destination = Self.markdownPath(requestedPath)
        let outcome = try await documentController.duplicate(
            authorizedTarget,
            to: destination
        )
        let document = outcome.committedValue
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
        return document
    }

    func moveNote(
        _ target: NoteLifecycleTarget,
        to requestedPath: String
    ) async throws {
        try await flushRegisteredEditorIfMutatingActiveDocument(target)
        guard let vault = workspaceAssignment?.vaults.values.first(where: {
            $0.id == target.documentID.vaultID
        }) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let expected = try lifecycleExpectedRevision(for: target)
        let authorizedTarget = NoteLifecycleTarget(
            documentID: target.documentID,
            stableNoteID: target.stableNoteID,
            revision: expected
        )
        let requestedDestination = Self.markdownPath(requestedPath)
        let outcome: WorkspaceMutationOutcome<TriptychMoveCommit>
        do {
            outcome = try await documentController.move(
                authorizedTarget,
                to: requestedDestination
            )
        } catch {
            await refreshTransactionRecoveryRecords()
            throw error
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
               visibleLocationScope: noteLocationScope
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

    func setAsideNote(_ target: NoteLifecycleTarget) async throws {
        try await flushRegisteredEditorIfMutatingActiveDocument(target)
        let expected = try lifecycleExpectedRevision(for: target)
        let authorizedTarget = NoteLifecycleTarget(
            documentID: target.documentID,
            stableNoteID: target.stableNoteID,
            revision: expected
        )
        let outcome = try await documentController.setAside(authorizedTarget)
        let commit = outcome.committedValue
        let presentationWarning = await presentCommittedLifecycleMove(
            commit,
            noteID: target.stableNoteID,
            identityResolved: outcome.identityRecoveryWarning == nil,
            vaultID: target.documentID.vaultID
        )
        reportCommittedMutationWarnings(
            outcome,
            presentationWarning: presentationWarning
        )
    }

    func moveNoteToTrash(_ target: NoteLifecycleTarget) async throws {
        try await flushRegisteredEditorIfMutatingActiveDocument(target)
        let expected = try lifecycleExpectedRevision(for: target)
        let authorizedTarget = NoteLifecycleTarget(
            documentID: target.documentID,
            stableNoteID: target.stableNoteID,
            revision: expected
        )
        let outcome = try await documentController.moveToTrash(authorizedTarget)
        let commit = outcome.committedValue
        let presentationWarning = await presentCommittedLifecycleMove(
            commit,
            noteID: target.stableNoteID,
            identityResolved: outcome.identityRecoveryWarning == nil,
            vaultID: target.documentID.vaultID
        )
        reportCommittedMutationWarnings(
            outcome,
            presentationWarning: presentationWarning
        )
    }

    func deleteNotePermanently(_ target: NoteLifecycleTarget) async throws {
        guard WorkspaceDocumentLifecycle(relativePath: target.relativePath) == .trash else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }

        let outcome: WorkspaceMutationOutcome<PermanentDeletionCommit>
        do {
            outcome = try await documentController.deletePermanently(target)
        } catch {
            await refreshTransactionRecoveryRecords()
            throw error
        }
        let commit = outcome.committedValue

        if currentRegisteredVault?.id == target.documentID.vaultID {
            noteIdentityByPath[target.relativePath] = nil
            if let critiquePath = commit.removedCritiqueDocumentPath {
                noteIdentityByPath[critiquePath] = nil
            }
        }
        let deletedPaths = Set([
            target.relativePath,
            commit.removedCritiqueDocumentPath,
        ].compactMap { $0 })
        var presentationWarnings: [String] = []
        do {
            try removeDocumentTabs(
                vaultID: target.documentID.vaultID,
                removedPaths: deletedPaths
            )
        } catch {
            presentationWarnings.append(error.localizedDescription)
            if currentDocumentVaultID == target.documentID.vaultID {
                documentController.clearSelection(forRemovedPaths: deletedPaths)
            }
        }
        do {
            try await refreshCachedWorkspaceVaultSnapshot(
                vaultID: target.documentID.vaultID
            )
            if currentRegisteredVault?.id == target.documentID.vaultID {
                try await refreshNoteLocationScope()
            }
        } catch {
            presentationWarnings.append(error.localizedDescription)
        }
        lifecycleMutationGeneration &+= 1
        reportCommittedMutationWarnings(
            outcome,
            presentationWarning: presentationWarnings.isEmpty
                ? nil
                : presentationWarnings.joined(separator: " ")
        )
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
        if let cleanup = outcome.committedValue.recoveryCleanupWarning {
            warnings.append(cleanup)
        }
        warnings.append(contentsOf: localizedCleanupWarnings(outcome.cleanupWarnings))
        if warnings.isEmpty {
            showToast(
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
            showToast(warnings.joined(separator: " "), kind: .warning)
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
        if WorkspaceDocumentLifecycle(relativePath: sourcePath) != .active
            || WorkspaceDocumentLifecycle(relativePath: destinationPath) != .active {
            lifecycleMutationGeneration &+= 1
        }
    }

    /// Applies a proven source move to this window without waiting for graph,
    /// Search, or research projections. A rare identity-recovery failure keeps
    /// the previous synchronous recovery path rather than claiming a resolved
    /// document session.
    private func presentCommittedLifecycleMove(
        _ commit: TriptychMoveCommit,
        noteID: UUID,
        identityResolved: Bool,
        vaultID: UUID
    ) async -> String? {
        let key = DocumentSessionKey(vaultID: vaultID, noteID: noteID)
        let wasSelected = currentDocumentDescriptor?.sessionKey == key
        migrateAppOwnedState(
            sourcePath: commit.movedNote.relativePath,
            destinationPath: commit.destination.relativePath,
            noteID: noteID,
            identityResolved: identityResolved,
            vaultID: vaultID
        )
        removePresentedDocumentAfterLifecycleMove(
            sessionKey: key,
            wasSelected: wasSelected
        )

        if identityResolved,
           let projection = workspaceProjectionController.recordCommittedNoteMove(
               commit,
               stableIdentity: .resolved(noteID),
               visibleVaultID: currentRegisteredVault?.id,
               visibleLocationScope: noteLocationScope
           ) {
            documentController.recordCommittedSnapshot(
                projection.note,
                vaultName: projection.vault.name,
                vaultRole: projection.vault.role
            )
            return nil
        }

        do {
            try await refreshCachedWorkspaceVaultSnapshot(vaultID: vaultID)
            try await refreshNoteLocationScope()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// A Note that leaves its visible Location must not remain presented as if
    /// it were still selected there. Other open document pages remain
    /// available, but the lifecycle action deliberately returns the central
    /// Document region to its no-document state instead of activating a
    /// neighboring page implicitly.
    private func removePresentedDocumentAfterLifecycleMove(
        sessionKey: DocumentSessionKey,
        wasSelected: Bool
    ) {
        let matchingTabIDs = Set(documentTabController.allTabs.compactMap { tab in
            tab.document.sessionKey == sessionKey ? tab.id : nil
        })
        guard wasSelected || !matchingTabIDs.isEmpty else { return }

        if wasSelected {
            documentController.finishEditing(
                session: documentController.session(for: sessionKey),
                target: .workspace(sessionKey)
            )
        }
        documentTabController.removeTabs(withIDs: matchingTabIDs)
        if wasSelected {
            documentController.clearSelectionAfterClosingLastTab()
        }
        reconcileDocumentSessionLeases()
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.documentController.reapDetachedSessions()
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

    private func restoredDocumentTab(
        _ id: VaultQualifiedNoteID
    ) -> DocumentTabItem? {
        guard let vault = workspaceAssignment?.vaults.values.first(where: {
            $0.id == id.vaultID
        }), let snapshot = workspaceProjectionController.cachedNote(
            vaultID: id.vaultID,
            relativePath: id.relativePath
        ) else { return nil }
        let document: WindowSelectedDocument
        if let noteID = snapshot.stableIdentity.resolvedID {
            document = .workspace(WindowDocumentDescriptor(
                sessionKey: DocumentSessionKey(vaultID: vault.id, noteID: noteID),
                reference: VaultNoteReference(
                    vaultID: vault.id,
                    vaultName: vault.name,
                    vaultRole: vault.role,
                    relativePath: snapshot.id.relativePath,
                    stableNoteID: noteID.uuidString.lowercased()
                )
            ))
        } else {
            document = .unavailable(
                vaultID: vault.id,
                relativePath: snapshot.id.relativePath
            )
        }
        let presentation = documentTabPresentation(for: document)
        return DocumentTabItem(
            document: document,
            title: presentation.title,
            toolTip: presentation.toolTip
        )
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
        tabActivation: DocumentTabActivation
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
                location: .workspace,
                validateDestination: {
                    try self.validateDocumentIsAvailable(document)
                }
            )
        }
        try activateDocumentInSelectedWorkspace(
            document,
            tabActivation: tabActivation
        )
    }

    private func activateDocumentInSelectedWorkspace(
        _ document: WindowSelectedDocument,
        tabActivation: DocumentTabActivation
    ) throws {
        switch document {
        case .workspace(let descriptor):
            try activateWorkspaceReferenceInSelectedWorkspace(
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
                location: .workspace,
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
            tabActivation: tabActivation
        )
    }

    private func activateWorkspaceReferenceInSelectedWorkspace(
        _ reference: VaultNoteReference,
        tabActivation: DocumentTabActivation
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
                placement: placement,
                in: shellState.selectedWorkspace
            )
            if !isCreatingNote {
                scheduleLibraryReveal(for: document)
            }
        case .preserveTabMembership:
            documentTabController.updateDocumentProjection(
                document,
                title: presentation.title,
                toolTip: presentation.toolTip
            )
        }
        reconcileDocumentSessionLeases()
    }

    /// Every successful in-app document activation converges on this one
    /// presentation path. It changes only Library presentation: the target
    /// vault and active Location, filters that hide the selected Note, folder
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
              let snapshot = workspaceProjectionController.cachedNote(
                  vaultID: vaultID,
                  stableNoteID: document.sessionKey?.noteID,
                  relativePath: document.relativePath
              ),
              snapshot.lifecycle == .active,
              let vault = workspaceAssignment?.vaults.values.first(where: {
                  $0.id == vaultID
              }),
              let slot = workspaceSlot(for: vault) else { return }

        let scope = LibraryDisclosureScope(
            vaultID: vaultID,
            locationScope: .workspace
        )
        let needsProjection = currentRegisteredVault?.id != vaultID
            || discoveryController.library.locationScope != .workspace
            || discoveryController.locationRequestIsActive

        if needsProjection {
            let request = discoveryController.beginLocationRequest(
                workspaceSlot: slot,
                location: .workspace,
                presentation: .stagedReplacement
            )
            do {
                try await browseRegisteredVault(
                    vault,
                    slot: slot,
                    locationRequest: request
                )
            } catch is CancellationError {
                return
            } catch {
                guard discoveryController.isCurrentLocationRequest(request) else { return }
                discoveryController.failLocationRequest(
                    error.localizedDescription,
                    for: request
                )
                showToast(
                    "Could not reveal the current note. \(error.localizedDescription)",
                    kind: .error
                )
                return
            }
        }

        guard !Task.isCancelled,
              documentController.selectedDocument == document,
              currentRegisteredVault?.id == vaultID,
              discoveryController.library.locationScope == .workspace else { return }

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
        if clearsFilters,
           noteSortOrder == .debateImportanceDescending {
            noteSortOrder = .modifiedNewest
        }
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
            showToast(
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
            let outcome = try await documentController.save(
                VaultQualifiedNoteID(vaultID: context.vaultID, relativePath: note.relativePath),
                changeSet: .frontmatter(edits),
                expectedRevision: expectedRevision
            )
            let result = outcome.committedValue
            let saved = await replaceSavedDocument(result.document)
            let presentationWarning = saved == nil
                ? WindowNavigationError.noteUnavailable(note.relativePath).localizedDescription
                : nil
            let didWarn = reportCommittedMutationWarnings(
                outcome,
                presentationWarning: presentationWarning
            )
            if !didWarn {
                showToast(String(
                    localized: "Frontmatter saved",
                    table: "Localizable",
                    bundle: .module
                ))
            }
            lastSaveError = nil
            return saved ?? original
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

    /// Presents post-commit repair truth without turning a durable file
    /// operation into a retryable failure. Returns `true` when a warning was
    /// shown so callers do not immediately replace it with a success toast.
    @discardableResult
    private func reportCommittedMutationWarnings<CommittedValue: Sendable>(
        _ outcome: WorkspaceMutationOutcome<CommittedValue>,
        presentationWarning: String? = nil
    ) -> Bool {
        reportCommittedMutationWarnings(
            derivedRefreshWarnings: outcome.derivedRefreshWarning.map { [$0] } ?? [],
            identityRecoveryWarnings: outcome.identityRecoveryWarning.map { [$0] } ?? [],
            cleanupWarnings: outcome.cleanupWarnings,
            presentationWarning: presentationWarning
        )
    }

    @discardableResult
    private func reportCommittedMutationWarnings(
        derivedRefreshWarnings: [String],
        identityRecoveryWarnings: [String],
        cleanupWarnings: [SaveCleanupWarning] = [],
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
        if !cleanupWarnings.isEmpty {
            messages.append(String(
                localized: "The file operation completed, but machine-local cleanup is still pending. Do not repeat the action; Scholium will retry cleanup when the vault reopens.",
                table: "Localizable",
                bundle: .module
            ))
            messages.append(localizedCleanupWarnings(cleanupWarnings).joined(separator: " "))
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
        showToast(messages.joined(separator: " "), kind: .warning)
        return true
    }

    private func localizedCleanupWarnings(
        _ warnings: [SaveCleanupWarning]
    ) -> [String] {
        warnings.map { warning in
            switch warning.kind {
            case .displacedSourceCopy:
                String(
                    localized: "The old exact source copy could not be removed. Scholium will retry cleanup when this vault reopens.",
                    table: "Localizable",
                    bundle: .module
                )
            case .transactionRecord:
                String(
                    localized: "The machine-local transaction record could not be removed. Scholium will retry cleanup when this vault reopens.",
                    table: "Localizable",
                    bundle: .module
                )
            }
        }
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
        libraryRevealTask?.cancel()
        libraryRevealTask = nil
        requestedWorkspaceSelection = nil
        presentationRouter.dismissAll()
        documentController.removeAll(retainingSessions: true)
        documentTabController.removeAll()
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

    private func receiveWorkspaceEvents(_ events: [UUID: WorkspaceEvent]) {
        guard let capabilities = activeWorkspaceCapabilities,
              let event = events[capabilities.id] else { return }
        guard workspaceProjectionController.canReceive(
            event,
            runtimeIdentity: capabilities.runtimeIdentity
        ) else { return }

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
            locationScope: noteLocationScope,
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
        if commit.retainedDeletedDocumentPath != nil {
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
                derivedProjectionState: .sourceAhead,
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
