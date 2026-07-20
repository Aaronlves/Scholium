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
    @StateObject private var workspaceStore = WorkspaceStore()

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
                ScholiumBootstrapRoot(
                    workspaceStore: workspaceStore,
                    route: route.wrappedValue,
                    lifecycleRegistry: applicationDelegate.windowLifecycleRegistry
                )
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
                ScholiumWindowRoot(
                    workspaceStore: workspaceStore,
                    route: route.wrappedValue,
                    lifecycleRegistry: applicationDelegate.windowLifecycleRegistry
                )
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
        .restorationBehavior(.automatic)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { ScholiumCommands() }

        UtilityWindow("Research Record", id: "scholium-research-record") {
            ScholiumResearchRecordUtilityRoot(appState: focusedWindowModel)
        }
        .defaultSize(width: 760, height: 680)
        .windowResizability(.automatic)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commandsRemoved()

        Settings {
            ScholiumSettingsRoot(workspaceStore: workspaceStore)
        }
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
                    "No Active Document",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Focus a Scholium workspace and open a note to view its Research Record.")
                )
            }
        }
        .scholiumSurface(.denseEvidence)
    }
}

private struct ScholiumResearchRecordFocusedContent: View {
    @ObservedObject var appState: WindowModel

    var body: some View {
        if let note = appState.currentNote,
           appState.documentController.editingDocumentPath == nil,
           appState.currentDocumentIdentityByPath[note.relativePath] != nil {
            ResearchRecordView(note: note, context: researchRecordContext)
                .id(appState.currentDocumentDescriptor?.sessionKey.noteID)
        } else {
            ContentUnavailableView(
                "No Research Record",
                systemImage: "clock.arrow.circlepath",
                description: Text("Open a note with a resolved identity to view its scholarly record.")
            )
        }
    }

    private var researchRecordContext: ResearchRecordContext {
        ResearchRecordContext(
            controller: appState.researchController,
            vaultRole: appState.currentDocumentVaultRole,
            documentRevisions: appState.currentDocumentRevisions,
            currentReview: { _ in appState.currentDocumentReviewRecord },
            loadDialogue: { await appState.dialogueHistory(for: $0) },
            loadCritique: { await appState.critiqueAssociationRelated(to: $0) },
            copyText: { try appState.copyTextToClipboard($0) },
            openNote: { appState.requestOpenNote($0) },
            notify: { appState.showToast($0) }
        )
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
                            appState.showToast(String(localized: "Imported \(imported.count) Markdown file\(imported.count == 1 ? "" : "s") into Unclassified.", table: "Localizable", bundle: .module))
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
                windowCoordinator.activate {
                    openWindow(id: "scholium-research-record")
                }
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

struct ScholiumFocusedResearchFunctionActions {
    let open: @MainActor (ResearchFunctionID) -> Void
}

struct ScholiumFocusedResearchFunctionActionsKey: FocusedValueKey {
    typealias Value = ScholiumFocusedResearchFunctionActions
}

struct ScholiumFocusedEditorActions {
    let documentID: String
    let isComposing: Bool
    let isAvailable: (MarkdownEditorCommand) -> Bool
    let canAddComment: () -> Bool
    let perform: (MarkdownEditorCommand) -> Void
    let performWithArgument: (MarkdownEditorCommand, String) -> Void
    let addComment: () -> Void
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

    var scholiumResearchFunctionActions: ScholiumFocusedResearchFunctionActions? {
        get { self[ScholiumFocusedResearchFunctionActionsKey.self] }
        set { self[ScholiumFocusedResearchFunctionActionsKey.self] = newValue }
    }

    var scholiumEditorActions: ScholiumFocusedEditorActions? {
        get { self[ScholiumFocusedEditorActionsKey.self] }
        set { self[ScholiumFocusedEditorActionsKey.self] = newValue }
    }
}

private struct ScholiumCommands: Commands {
    @FocusedObject private var appState: WindowModel?
    @FocusedValue(\.scholiumSearchActions) private var searchActions
    @FocusedValue(\.scholiumWorkspaceWindowActions) private var workspaceWindowActions
    @FocusedValue(\.scholiumResearchFunctionActions) private var researchFunctionActions
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
        }
        CommandGroup(after: .newItem) {
            Button("New Triptych…") {
                openWindow(
                    id: "scholium-bootstrap",
                    value: BootstrapWindowRoute(purpose: .newTriptych)
                )
            }
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
            Button("New Note…") { appState?.noteLifecycleRequest = .create }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(appState?.workspaceAssignment == nil || appState?.noteLocationScope != .workspace)
            Button("Import Markdown…") { appState?.showMarkdownImporter = true }
                .disabled(appState?.workspaceAssignment == nil)
            Divider()
            Button("Open in New Tab") {
                guard let reference = appState?.currentDocumentDescriptor?.reference else { return }
                appState?.requestOpenNote(reference, disposition: .newTab)
            }
            .disabled(appState?.currentDocumentDescriptor == nil)
            Divider()
            Button("Duplicate Note…") {
                guard let note = appState?.currentNote,
                      let target = NoteLifecycleTarget(note) else { return }
                appState?.noteLifecycleRequest = .duplicate(target)
            }
            .disabled(appState?.canEditCurrentNote != true || appState?.currentNoteIdentityIsResolved != true)
            Button("Move or Rename Note…") {
                guard let note = appState?.currentNote,
                      let target = NoteLifecycleTarget(note) else { return }
                appState?.noteLifecycleRequest = .move(target)
            }
            .disabled(appState?.canEditCurrentNote != true || appState?.currentNoteIdentityIsResolved != true)
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
                searchActions?.begin(.findInNote(previousScope: appState.ordinarySearchScope))
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
                Button("Supports Target") { editorActions?.perform(.vectorSupportsTarget) }
                    .disabled(editorActions?.isAvailable(.vectorSupportsTarget) != true)
                Button("Supported by Target") { editorActions?.perform(.vectorSupportedByTarget) }
                    .disabled(editorActions?.isAvailable(.vectorSupportedByTarget) != true)
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
            Button("Add Comment…") { editorActions?.addComment() }
                .disabled(
                    editorActions?.canAddComment() != true
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
            .disabled(appState?.currentNote == nil || workspaceWindowActions == nil)
            Menu("Document Mode") {
                Button("Read") { appState?.requestDocumentMode(.read) }
                Button("Live Preview") { appState?.requestDocumentMode(.livePreview) }
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
        CommandMenu("Research") {
            if let role = appState?.currentResearchFunctionTarget?.role {
                if role == .analysis || role == .topic {
                    Button("Dialogue") { researchFunctionActions?.open(.dialogue) }
                        .keyboardShortcut("r", modifiers: [.command])
                        .disabled(!researchFunctionIsAvailable(.dialogue))
                    Button("Develop") { researchFunctionActions?.open(.develop) }
                        .disabled(!researchFunctionIsAvailable(.develop))
                    Button("Fidelity") { researchFunctionActions?.open(.fidelity) }
                        .disabled(!researchFunctionIsAvailable(.fidelity))
                } else {
                    Button("Critique") { researchFunctionActions?.open(.critique) }
                        .keyboardShortcut("r", modifiers: [.command])
                        .disabled(!researchFunctionIsAvailable(.critique))
                    Button("Revise") { researchFunctionActions?.open(.revise) }
                        .disabled(!researchFunctionIsAvailable(.revise))
                    Button("Dialogue") { researchFunctionActions?.open(.dialogue) }
                        .keyboardShortcut("d", modifiers: [.command, .shift])
                        .disabled(!researchFunctionIsAvailable(.dialogue))
                    Button("Fidelity") { researchFunctionActions?.open(.fidelity) }
                        .disabled(!researchFunctionIsAvailable(.fidelity))
                    Button("Manuscript") { researchFunctionActions?.open(.manuscript) }
                        .disabled(!researchFunctionIsAvailable(.manuscript))
                }
            }
            Divider()
            WindowVisibilityToggle(windowID: "scholium-research-record")
            .disabled(appState?.currentNote == nil)
        }
        #if DEBUG
        if qaEditorFaultsAreEnabled {
            CommandMenu("QA") {
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
        }
        #endif
    }

    #if DEBUG
    private var qaEditorFaultsAreEnabled: Bool {
        Bundle.main.bundleIdentifier == "com.scholium.qa"
            && ProcessInfo.processInfo.arguments.contains("--scholium-editor-qa-faults")
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

    private func researchFunctionIsAvailable(_ function: ResearchFunctionID) -> Bool {
        guard let appState,
              researchFunctionActions != nil,
              appState.currentResearchFunctionTarget != nil else { return false }
        return appState.researchController.functions.availability[function]?.isEnabled == true
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

struct WindowPropertyFilterOptions: Equatable {
    let keys: [String]
    let valuesByKey: [String: [String]]

    init(notes: [WindowDocumentLocation]) {
        var accumulated: [String: Set<String>] = [:]
        for note in notes {
            for (key, values) in note.filterableProperties {
                let usableValues = values.filter { !$0.isEmpty && $0.count <= 80 }
                guard !usableValues.isEmpty else { continue }
                accumulated[key, default: []].formUnion(usableValues)
            }
        }

        keys = accumulated.keys.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        valuesByKey = accumulated.mapValues { values in
            values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
    }
}

@MainActor
final class WindowModel: ObservableObject {
    private struct EditorFlushRegistration {
        let token: UUID
        let relativePath: String
        let flush: @MainActor () async throws -> Void
        let captureForReconstruction: @MainActor () async throws -> Void
    }

    private enum DocumentTransitionError: LocalizedError {
        case staleEditorRegistration(expected: String, registered: String)

        var errorDescription: String? {
            switch self {
            case .staleEditorRegistration(let expected, let registered):
                String(localized: "Scholium kept the document open because the active editor changed from \(registered) to \(expected) before it could be saved.", table: "Localizable", bundle: .module)
            }
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

    enum DocumentTabActivation {
        case replaceSelectedTab
        case appendTab
        case preserveTabMembership
    }
    private(set) var windowSessionID = UUID()
    let nativeWindowID: UUID

    struct Toast: Equatable {
        enum Kind: Equatable {
            case success
            case information
            case warning
            case error

            var symbol: String {
                switch self {
                case .success: "checkmark.circle.fill"
                case .information: "info.circle.fill"
                case .warning: "exclamationmark.triangle.fill"
                case .error: "xmark.octagon.fill"
                }
            }

            var color: Color {
                switch self {
                case .success: ScholiumColorRole.confirmed.color
                case .information: ScholiumColorRole.information.color
                case .warning: ScholiumColorRole.attention.color
                case .error: ScholiumColorRole.destructive.color
                }
            }
        }

        let message: String
        let kind: Kind
    }

    enum ColorSchemeChoice: String, CaseIterable {
        case dark, light, system
    }

    // MARK: Published State
    @Published var vaultConfig: VaultConfig?
    @Published var currentRegisteredVault: RegisteredVault?
    @Published var currentVaultRole: VaultRole = .other
    @Published var notes: [WindowDocumentLocation] = [] {
        didSet {
            availablePropertyFilterOptions = WindowPropertyFilterOptions(notes: notes)
        }
    }
    private(set) var availablePropertyFilterOptions = WindowPropertyFilterOptions(notes: [])
    @Published private(set) var libraryFocusRequestGeneration: UInt64 = 0
    @Published var sidebarVisible = true
    @Published private(set) var hasCompletedInitialRestore = false
    @Published var toastMessage: Toast?
    @Published var colorScheme: ColorSchemeChoice = .system {
        didSet {
            UserDefaults.standard.set(colorScheme.rawValue, forKey: "colorScheme")
        }
    }
    @Published var allTags: [String] = []
    @Published var savedSearches: [SavedSearch] = []
    @Published var documentTextScale = ScholiumMetrics.Document.defaultTextScale
    @Published var documentRevisions: [String: DocumentFingerprint] = [:]
    @Published var triptychSettings = TriptychSettings()
    @Published var workspaceAssignment: TriptychAssignment?
    @Published var registeredTriptychs: [TriptychAssignment] = []
    @Published var workspaceRecoveryMessage: String?
    @Published var workspaceAccessRecovery: WorkspaceAccessRecovery?
    @Published var workspaceCatalog: WorkspaceCatalogSnapshot?
    @Published var isRefreshingWorkspaceCatalog = false
    @Published var refreshStatusText: String?
    @Published private(set) var derivedRefreshStatus: WorkspaceDerivedRefreshStatus?
    @Published var workspaceCatalogError: String?
    @Published private(set) var workspaceVaultSnapshotsByID: [UUID: WorkspaceVaultSnapshot] = [:]
    @Published var registeredVaults: [RegisteredVault] = []
    @Published var windowSessionPersistenceError: String?
    let presentationRouter = WindowPresentationRouter()
    private let peripheralPresentation = WindowPeripheralPresentationState()
    lazy var discoveryController = DiscoveryController(
        peripheralPresentation: peripheralPresentation
    ) { [weak self] intent in
        self?.handleWindowIntent(intent)
    }
    lazy var documentController = DocumentController { [weak self] intent in
        self?.handleWindowIntent(intent)
    }
    let documentTabController = DocumentTabController()
    lazy var researchController = ResearchController(
        peripheralPresentation: peripheralPresentation
    ) { [weak self] intent in
        self?.handleWindowIntent(intent)
    }

    // Window-level projections for Library leaves. DiscoveryController remains
    // the sole mutable owner.
    var noteLocationScope: NoteLocationScope {
        get { discoveryController.library.locationScope }
        set { discoveryController.selectLocationScope(newValue) }
    }

    var isReviewedFilter: Bool {
        get { discoveryController.library.filters.isReviewed }
        set { updateDiscoveryFilters { $0.isReviewed = newValue } }
    }

    var isUnqualifiedFilter: Bool {
        get { discoveryController.library.filters.isUnqualified }
        set { updateDiscoveryFilters { $0.isUnqualified = newValue } }
    }

    var isChangedSinceReviewFilter: Bool {
        get { discoveryController.library.filters.isChangedSinceReview }
        set { updateDiscoveryFilters { $0.isChangedSinceReview = newValue } }
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

    var selectedStatus: String? {
        get { discoveryController.library.filters.status }
        set { updateDiscoveryFilters { $0.status = newValue } }
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

    // Source-located semantic graph for the current vault. Triptych-wide
    // resolution is published through `workspaceCatalog.graph`.
    @Published var relationshipGraph: GraphSnapshot?

    // MARK: Window Presentation

    var researchInspectorMode: ResearchInspectorMode {
        get { researchController.inspector.mode }
        set { researchController.selectInspectorMode(newValue) }
    }

    var researchInspectorVisible: Bool {
        get { researchController.inspector.isVisible }
        set { researchController.showResearchInspector(newValue) }
    }

    var advancedSearchState: SearchWorkspaceState {
        get { discoveryController.search.criteria }
        set { discoveryController.replaceSearchCriteria(newValue) }
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
    private var activeWorkspaceCapabilities: WindowWorkspaceCapabilities?
    let cssSnippetStore: CSSSnippetStore
    let zoteroBridge: ZoteroBridge
    let agentApplicationHandoff: AgentApplicationHandoffController
    private let requestedTriptychID: UUID?
    private let requestedInitialDocument: VaultNoteReference?
    private var didOpenRequestedInitialDocument = false
    /// Published only after every shared Triptych service has been installed.
    /// Settings views use this readiness boundary instead of racing the earlier
    /// `workspaceAssignment` publication.
    @Published private(set) var activeTriptychServicesID: UUID?
    private var editorFlushRegistration: EditorFlushRegistration?
    private var workspaceProjectionTail: Task<Void, Never>?
    private var projectionRefreshToken: UInt64 = 0
    private var attemptedVaultRestore = false
    private let workspaceStore: WorkspaceStore
    private var workspaceCancellables: Set<AnyCancellable> = []
    private var windowSessionSaveTask: Task<Void, Never>?
    private var isFinalizingWindowSession = false
    private var workspaceCatalogRefreshTask: Task<Void, Never>?
    private var workspaceCatalogNeedsAnotherRefresh = false
    private var isRestoringWindowSession = false
    private var didRestoreWindowSession = false
    private var transitionGeneration: UInt64 = 0
    private var libraryBrowseGeneration: UInt64 = 0
    private var identityReviewRefreshGeneration: UInt64 = 0
    private var transitionTail: Task<Void, Never>?
    private var savedSearchMutationTail: Task<Void, Never>?
    private let documentPresentationDidChange = PassthroughSubject<Void, Never>()
    #if DEBUG
    private var qaPerformanceModeNotificationTokens: [Int32] = []
    #endif

    init(
        workspaceStore: WorkspaceStore,
        nativeWindowID: UUID? = nil,
        requestedTriptychID: UUID? = nil,
        requestedInitialDocument: VaultNoteReference? = nil
    ) {
        let resolvedWindowID = nativeWindowID ?? UUID()
        self.nativeWindowID = resolvedWindowID
        windowSessionID = resolvedWindowID
        self.workspaceStore = workspaceStore
        self.requestedTriptychID = requestedTriptychID
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
        researchController.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &workspaceCancellables)
        documentController.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &workspaceCancellables)
        documentTabController.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &workspaceCancellables)
        workspaceStore.$latestWorkspaceActivation
            .compactMap { $0 }
            .sink { [weak self] activation in
                self?.adoptWorkspaceActivation(activation)
            }
            .store(in: &workspaceCancellables)
        workspaceStore.$workspaceSnapshots
            .sink { [weak self] snapshots in
                self?.receiveWorkspaceSnapshots(snapshots)
            }
            .store(in: &workspaceCancellables)
        workspaceStore.$workspaceDerivedRefreshStatuses
            .sink { [weak self] statuses in
                self?.receiveWorkspaceDerivedRefreshStatuses(statuses)
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
        if let saved = UserDefaults.standard.string(forKey: "colorScheme"),
           let choice = ColorSchemeChoice(rawValue: saved) {
            colorScheme = choice
        }
        if let saved = UserDefaults.standard.string(forKey: "noteSortOrder"),
           let order = NoteSortOrder(rawValue: saved) {
            // Metadata filters are intentionally request-local and are not
            // restored. A Debate Importance ordering without one explicit
            // debate scope would compare incommensurable ratings.
            noteSortOrder = order == .debateImportanceDescending ? .modifiedNewest : order
        }
        UserDefaults.standard.removeObject(forKey: "libraryViewMode")
        Task { [weak self] in
            guard let self else { return }
            do {
                let searches = try await workspaceStore.savedSearches()
                await MainActor.run { self.savedSearches = searches }
            } catch {
                await MainActor.run {
                    self.vaultError = error.localizedDescription
                }
            }
        }
        observeWindowSessionChanges()
    }

    deinit {
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

    var lastSaveError: String? {
        get { documentController.lastSaveError }
        set { documentController.setSaveError(newValue) }
    }

    var changedSinceReviewPaths: Set<String> {
        get { documentController.changedSinceReviewPaths }
        set { documentController.changedSinceReviewPaths = newValue }
    }

    var requestPresentationMode: NotePresentationMode? {
        get { documentController.requestedPresentationMode }
        set { documentController.requestedPresentationMode = newValue }
    }

    var pendingCommentSelection: MarkdownReviewSelection? {
        get { documentController.pendingCommentSelection }
        set { documentController.pendingCommentSelection = newValue }
    }

    var focusedResearcherCommentID: UUID? {
        get { documentController.focusedResearcherCommentID }
        set { documentController.focusedResearcherCommentID = newValue }
    }

    var humanReviewRecords: [String: HumanReviewRecord] {
        get { documentController.humanReviewRecords }
        set { documentController.humanReviewRecords = newValue }
    }

    private(set) var humanReviewRecordsByNoteID: [UUID: HumanReviewRecord] {
        get { documentController.humanReviewRecordsByNoteID }
        set { documentController.humanReviewRecordsByNoteID = newValue }
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

    var dialogueInitialNotes: Set<VaultQualifiedNoteID> {
        get { researchController.dialogueInitialNotes }
        set { researchController.dialogueInitialNotes = newValue }
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
        return workspaceVaultSnapshotsByID[vaultID]
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
           let snapshot = workspaceVaultSnapshotsByID[descriptor.reference.vaultID]?.documents.first(where: {
               $0.stableIdentity.resolvedID == descriptor.sessionKey.noteID
                   || $0.id.relativePath == descriptor.reference.relativePath
           }) {
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

    var currentDocumentReviewRecord: HumanReviewRecord? {
        guard let noteID = currentDocumentDescriptor?.sessionKey.noteID else { return nil }
        return humanReviewRecordsByNoteID[noteID]
            ?? researchController.records?.humanReviews.first { $0.id == noteID }
    }

    var currentDocumentReviewDisplayState: HumanReviewDisplayState {
        guard let revision = currentNote?.document.fingerprint,
              let review = currentDocumentReviewRecord?.review(for: revision) else {
            return .notReviewed
        }
        return HumanReviewDisplayState(isReviewed: true, qualification: review.qualification)
    }

    var currentDocumentChangedSinceReview: Bool {
        guard let revision = currentNote?.document.fingerprint,
              let record = currentDocumentReviewRecord else { return false }
        return record.latestReview != nil && record.review(for: revision) == nil
    }

    var currentResearchFunctionTarget: ResearchFunctionTarget? {
        guard let descriptor = currentDocumentDescriptor,
              let note = currentNote,
              !CritiquePlacement.isManagedCritiquePath(note.relativePath),
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

    var currentResearchFunctionReference: VaultNoteReference? {
        currentDocumentDescriptor?.reference
    }

    var currentRecommendedBibliographyTarget: RecommendedBibliographyTarget? {
        guard let target = currentResearchFunctionTarget,
              target.role == .analysis else { return nil }
        return RecommendedBibliographyTarget(
            noteID: target.noteID,
            note: target.note,
            fingerprint: target.fingerprint,
            title: target.title
        )
    }

    var researchFunctionsPresentation: ResearchFunctionsPresentation {
        let target = currentResearchFunctionTarget
        let activeFunction = researchController.functions.target == target
            ? researchController.functions.activeFunction
            : nil
        return ResearchFunctionsPresentation.make(
            target: target,
            availability: researchController.functions.availability,
            activeFunction: activeFunction,
            runs: researchController.functions.targetRuns
        )
    }

    func refreshResearchFunctionAvailability() async {
        let target = currentResearchFunctionTarget
        researchController.setActiveDocument(currentResearchFunctionReference)
        researchController.functions.receive(
            researchController.records?.functionRuns ?? [],
            targetNoteID: target?.noteID
        )
        if let target,
           let presentationID = researchController.functions.presentationID,
           researchController.functions.activeFunction == .dialogue,
           presentationRouter.suspendsResearchFunction(presentationID: presentationID) {
            researchController.functions.resumeHumanReviewDraft(
                presentationID: presentationID,
                target: target
            )
        } else {
            researchController.functions.invalidateIfTargetChanged(target)
        }
        reconcileResearchFunctionPresentation()
        await researchController.functions.refreshAvailability(for: target)
        await researchController.bibliography.refresh(
            for: currentRecommendedBibliographyTarget
        )
    }

    private func reconcileResearchFunctionPresentation() {
        guard case .researchFunction(let route) = presentationRouter.sheet else { return }
        guard researchController.functions.presentationID == route.presentationID,
              researchController.functions.activeFunction == route.function,
              researchController.functions.target?.noteID == currentResearchFunctionTarget?.noteID else {
            presentationRouter.dismissSheet()
            return
        }
    }

    var canEditCurrentNote: Bool {
        if case .unclassified = documentController.selectedDocument {
            return currentNote != nil
        }
        guard let note = currentNote, currentDocumentDescriptor != nil else { return false }
        let isCritique = currentDocumentVaultRole.allowsCritique
            && (note.relativePath == "Critiques" || note.relativePath.hasPrefix("Critiques/"))
        return !isCritique
    }

    var currentNoteIdentityIsResolved: Bool {
        currentDocumentDescriptor != nil
    }

    var canCommentCurrentNote: Bool {
        guard currentDocumentDescriptor != nil else { return false }
        switch currentDocumentVaultRole {
        case .sourceCorpus, .topicKnowledge:
            return true
        case .draftProject:
            // Critique source remains read-only in Scholium, but the
            // researcher may attach app-owned comments to its rendered text.
            return true
        case .other:
            return false
        }
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
            await refreshIdentityAndReviewState()
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
        if noteLocationScope == .unclassified { return nil }
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

    private func storeHumanReviewRecord(
        _ record: HumanReviewRecord,
        path: String,
        vaultID: UUID
    ) {
        humanReviewRecordsByNoteID[record.id] = record
        if currentRegisteredVault?.id == vaultID {
            humanReviewRecords[path] = record
        }
    }

    func registerEditorFlush(
        for relativePath: String,
        token: UUID,
        flush: @escaping @MainActor () async throws -> Void,
        captureForReconstruction: @escaping @MainActor () async throws -> Void
    ) {
        if let previous = editorFlushRegistration,
           previous.token != token {
            workspaceStore.unregisterEditorFlush(token: previous.token)
        }
        editorFlushRegistration = EditorFlushRegistration(
            token: token,
            relativePath: relativePath,
            flush: flush,
            captureForReconstruction: captureForReconstruction
        )
        if let triptychID = workspaceAssignment?.id {
            workspaceStore.registerEditorFlush(
                token: token,
                triptychID: triptychID,
                windowID: windowSessionID,
                relativePath: relativePath,
                flush: flush
            )
        }
    }

    func unregisterEditorFlush(token: UUID) {
        guard let registration = editorFlushRegistration,
              registration.token == token else {
            workspaceStore.unregisterEditorFlush(token: token)
            return
        }
        // SwiftUI may detach and reattach NoteContentView while the same
        // document session remains selected. Its stable token is also used by
        // the replacement view, so treating that transient onDisappear as the
        // end of ownership can unregister the newly installed flush closure.
        // The selected session remains the owner until navigation replaces it,
        // the last tab closes, or window shutdown explicitly clears it.
        guard selectedDocumentPath != registration.relativePath else { return }
        workspaceStore.unregisterEditorFlush(token: token)
        editorFlushRegistration = nil
    }

    private func clearEditorFlushRegistration() {
        guard let registration = editorFlushRegistration else { return }
        workspaceStore.unregisterEditorFlush(token: registration.token)
        editorFlushRegistration = nil
    }

    private func flushRegisteredEditorIfNeeded() async throws {
        guard let registration = editorFlushRegistration else { return }
        if let selectedDocumentPath,
           selectedDocumentPath != registration.relativePath {
            throw DocumentTransitionError.staleEditorRegistration(
                expected: selectedDocumentPath,
                registered: registration.relativePath
            )
        }
        try await registration.flush()
    }

    private func captureRegisteredEditorForReconstructionIfNeeded() async throws {
        guard let registration = editorFlushRegistration else { return }
        try await registration.captureForReconstruction()
    }

    func prepareForWindowClose() async throws {
        try await flushRegisteredEditorIfNeeded()
        try await persistWindowSessionBeforeClose()
        clearEditorFlushRegistration()
    }

    /// Serializes every transition that can replace the active document view.
    /// The newest requested destination wins, but an already-running operation
    /// is allowed to finish before the next begins so vault state is never
    /// mutated concurrently by two window transitions.
    private func enqueueDocumentTransition(
        _ operation: @escaping @MainActor () async throws -> Void
    ) {
        transitionGeneration &+= 1
        let generation = transitionGeneration
        let previous = transitionTail
        transitionTail = Task { [weak self] in
            _ = await previous?.value
            guard let self, generation == self.transitionGeneration else { return }
            do {
                try await self.flushRegisteredEditorIfNeeded()
                try await self.captureRegisteredEditorForReconstructionIfNeeded()
                guard generation == self.transitionGeneration else { return }
                try await operation()
            } catch is CancellationError {
                return
            } catch let navigationError as WindowNavigationError {
                self.showToast(navigationError.localizedDescription, kind: .warning)
            } catch {
                self.lastSaveError = error.localizedDescription
                self.showToast(
                    "The current note could not be saved, so Scholium kept it open. \(error.localizedDescription)",
                    kind: .error
                )
            }
        }
    }

    var ordinarySearchScope: SearchPresentationScope {
        discoveryController.search.ordinaryScope
    }

    /// Opens the one shared Search surface. Standard Find temporarily uses
    /// This Note and leaves the researcher's ordinary scope untouched.
    func beginSearch(_ invocation: SearchInvocation) {
        if case .findInNote = invocation, currentNote == nil { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.flushRegisteredEditorIfNeeded()
                self.discoveryController.presentSearch(invocation)
                self.showSearchSurface = true
            } catch {
                self.lastSaveError = error.localizedDescription
                self.showToast(
                    "The current note could not be saved, so Search did not open. \(error.localizedDescription)",
                    kind: .error
                )
            }
        }
    }

    func dismissSearch() {
        discoveryController.dismissSearch()
        showSearchSurface = false
    }

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
        case .presentResearchFunction(let route):
            guard currentResearchFunctionReference == route.target,
                  researchController.functions.presentationID == route.presentationID,
                  researchController.functions.activeFunction == route.function else { return }
            presentationRouter.present(.researchFunction(route))
        case .presentLifecycle(let request):
            noteLifecycleRequest = request
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
        enqueueDocumentTransition { [weak self] in
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
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            try self.activateWorkspaceReference(
                reference,
                tabActivation: .replaceSelectedTab
            )
        }
    }

    func requestOpenNote(
        _ path: String,
        sourceLine: Int,
        mode: NotePresentationMode = .source
    ) {
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            self.pendingSourceLine = max(1, sourceLine)
            self.openNote(path)
            self.requestPresentationMode = mode
        }
    }

    func requestWorkspaceVault(_ slot: WorkspaceVaultSlot) {
        libraryBrowseGeneration &+= 1
        guard discoveryController.library.workspaceSlot != slot else { return }
        let generation = libraryBrowseGeneration
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.browseWorkspaceVault(slot, generation: generation)
            } catch is CancellationError {
                return
            } catch {
                guard generation == self.libraryBrowseGeneration else { return }
                self.showToast(
                    "Could not browse \(slot.displayName): \(error.localizedDescription)",
                    kind: .error
                )
            }
        }
    }

    func requestNoteLocationScope(_ scope: NoteLocationScope) {
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            await self.selectNoteLocationScope(scope)
        }
    }

    func requestLifecycleNote(_ path: String, in scope: NoteLocationScope) {
        guard scope == .setAside || scope == .trash else { return }
        enqueueDocumentTransition { [weak self] in
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
        if mode == .read {
            enqueueDocumentTransition { [weak self] in
                self?.requestPresentationMode = .read
            }
        } else {
            requestPresentationMode = mode
        }
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

        session.presentationMode = mode
        session.retainedEditorMode = mode
    }
    #endif

    func requestResearcherComments(
        at path: String,
        selection: MarkdownReviewSelection? = nil,
        focusedCommentID: UUID? = nil
    ) {
        guard canCommentCurrentNote,
              currentNote?.relativePath == path else { return }
        enqueueDocumentTransition { [weak self] in
            guard let self,
                  self.currentNote?.relativePath == path,
                  self.canCommentCurrentNote else { return }
            self.pendingCommentSelection = selection
            self.focusedResearcherCommentID = focusedCommentID
            let function: ResearchFunctionID = self.currentDocumentVaultRole.allowsCritique
                ? .critique
                : .dialogue
            self.openResearchFunction(
                function,
                focusCommentComposer: focusedCommentID == nil,
                permitsUnavailablePresentation: true
            )
        }
    }

    func openResearchFunction(
        _ function: ResearchFunctionID,
        selection: ResearcherCommentAnchor? = nil,
        focusCommentComposer: Bool = false,
        permitsUnavailablePresentation: Bool = false
    ) {
        guard let assignment = workspaceAssignment,
              let initialTarget = currentResearchFunctionTarget,
              function.allowedTargetRoles.contains(initialTarget.role),
              permitsUnavailablePresentation
                || researchController.functions.availability[function]?.isEnabled == true else {
            return
        }
        let initialNoteID = initialTarget.noteID

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.workspaceStore.flushEditors(in: assignment.id)
                guard let target = self.currentResearchFunctionTarget,
                      target.noteID == initialNoteID,
                      let reference = self.currentResearchFunctionReference else { return }
                await self.researchController.functions.refreshAvailability(for: target)
                guard let refreshedTarget = self.currentResearchFunctionTarget,
                      refreshedTarget == target,
                      let availability = self.researchController.functions.availability[function],
                      permitsUnavailablePresentation || availability.isEnabled else {
                    let reason = self.researchController.functions.availability[function]?
                        .repairReasons.first?.interfaceDescription
                        ?? "Scholium could not confirm that this function is available for the current note."
                    self.showToast(reason, kind: .information)
                    return
                }
                let capturedSelection: ResearcherCommentAnchor?
                if let selection, selection.fingerprint == target.fingerprint {
                    capturedSelection = selection
                } else {
                    capturedSelection = nil
                    if selection != nil {
                        self.showToast(
                            "The selected passage changed while Scholium saved the note. The function will open for the whole note.",
                            kind: .information
                        )
                    }
                }
                let presentationID = UUID()
                self.researchController.functions.begin(
                    target: target,
                    function: function,
                    selection: capturedSelection,
                    presentationID: presentationID
                )
                if function == .review
                    || (function == .dialogue
                        && (target.role == .analysis || target.role == .topic)) {
                    self.researchController.functions.beginHumanReviewDraft(
                        revision: target.fingerprint,
                        record: self.currentDocumentReviewRecord
                    )
                }
                self.researchController.requestPresentFunction(
                    function,
                    target: reference,
                    presentationID: presentationID,
                    focusCommentComposer: focusCommentComposer
                )
            } catch {
                self.showToast(
                    "Scholium could not save the current editor before opening \(function.interfaceTitle). \(error.localizedDescription)",
                    kind: .error
                )
            }
        }
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
            await applyWorkspaceSnapshot(snapshot, vaultID: vaultID)
            applyDerivedRefreshStatus(
                .current(WorkspaceDerivedRefreshEvidence(snapshot: snapshot))
            )
            refreshStatusText = nil
            workspaceCatalogError = nil
        } catch {
            refreshStatusText = "Triptych refresh failed"
            workspaceCatalogError = error.localizedDescription
        }
    }

    var filteredNotes: [WindowDocumentLocation] {
        var result = notes
        if isReviewedFilter { result = result.filter { !$0.isReviewed } }
        if isUnqualifiedFilter {
            result = result.filter {
                humanReviewRecords[$0.relativePath]?.latestReview?.qualification == .unqualified
            }
        }
        if isChangedSinceReviewFilter {
            result = result.filter { changedSinceReviewPaths.contains($0.relativePath) }
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
        if let status = selectedStatus { result = result.filter { $0.status == status } }
        if let author = selectedAuthor { result = result.filter { $0.authors.contains(author) } }
        if let year = selectedYear { result = result.filter { $0.year == year } }
        if let key = selectedPropertyKey, let value = selectedPropertyValue {
            result = result.filter { $0.property(at: key)?.appFilterValues.contains(value) == true }
        }
        return result.sorted(by: notesAreOrdered)
    }

    var activeResearchFilterCount: Int {
        [
            isChangedSinceReviewFilter,
            isNeedsAttentionFilter,
            isExplicitConnectionsFilter,
            isMalformedMetadataFilter,
        ].count(where: { $0 })
    }

    func clearResearchFilters() {
        isChangedSinceReviewFilter = false
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

    var availableStatuses: [String] {
        Set(notesInCurrentScope.compactMap(\.status)).sorted()
    }

    var availableAuthors: [String] {
        Set(notesInCurrentScope.flatMap(\.authors)).sorted()
    }

    var availableYears: [Int] {
        Set(notesInCurrentScope.compactMap(\.year)).sorted(by: >)
    }

    var activeMetadataFilterCount: Int {
        [
            selectedStatus != nil,
            selectedAuthor != nil,
            selectedYear != nil,
            selectedPropertyKey != nil && selectedPropertyValue != nil,
        ].count(where: { $0 })
    }

    func clearMetadataFilters() {
        selectedStatus = nil
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
                tabActivation: .appendTab
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
        }
    }

    func closeDocumentTab(withID id: UUID) {
        guard let plan = documentTabController.closePlan(forTabWithID: id) else {
            return
        }
        guard documentTabController.selectedTabID == id else {
            documentTabController.apply(plan)
            return
        }
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            if let documentToActivate = plan.documentToActivate {
                try self.activateDocument(
                    documentToActivate,
                    tabActivation: .preserveTabMembership
                )
            } else {
                self.documentController.clearSelectionAfterClosingLastTab()
            }
            self.documentTabController.apply(plan)
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
        isRestoringWindowSession = true
        defer {
            isRestoringWindowSession = false
            didRestoreWindowSession = true
            hasCompletedInitialRestore = true
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
            sidebarVisible = true
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
            .flatMap { workspaceVaultSnapshotsByID[$0] }
            .map { Set($0.documents.map(\.id.relativePath)) }
            ?? Set(notes.map(\.relativePath))
        let restoredPresentation = stored.normalized(availablePaths: restoredDocumentPaths)
        let hasRestorableDocument = requestedInitialDocument != nil
            || restoredPresentation.selectedDocument.map {
                restoredDocumentPaths.contains($0.relativePath)
            } == true
        sidebarVisible = hasRestorableDocument
            ? (restoredPresentation.libraryVisible ?? true)
            : true
        researchController.restoreInspector(
            storedMode: restoredPresentation.inspectorMode,
            isVisible: restoredPresentation.inspectorVisible
        )
        discoveryController.replaceSearchCriteria(SearchWorkspaceState(
            scope: restoredPresentation.searchState.scope
        ))
        documentTextScale = min(
            ScholiumMetrics.Document.maximumTextScale,
            max(
                ScholiumMetrics.Document.minimumTextScale,
                restoredPresentation.documentTextScale
                    ?? ScholiumMetrics.Document.defaultTextScale
            )
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
              !isFinalizingWindowSession else { return }
        windowSessionSaveTask?.cancel()
        let snapshot = currentWindowSessionSnapshot()
        windowSessionSaveTask = Task { [weak self, workspaceStore] in
            do {
                try await workspaceStore.saveWindowSession(snapshot)
                guard !Task.isCancelled else { return }
                self?.windowSessionPersistenceError = nil
                if self?.refreshStatusText == "Window state not saved" {
                    self?.refreshStatusText = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.windowSessionPersistenceError = error.localizedDescription
                self?.refreshStatusText = "Window state not saved"
            }
        }
    }

    /// A close or termination decision must not race the final per-window
    /// snapshot. Cancel and await any debounced predecessor, then propagate a
    /// final save failure so AppKit can keep the native tab open.
    private func persistWindowSessionBeforeClose() async throws {
        guard didRestoreWindowSession,
              !isRestoringWindowSession,
              !isFinalizingWindowSession else { return }
        isFinalizingWindowSession = true
        defer { isFinalizingWindowSession = false }

        while let pending = windowSessionSaveTask {
            windowSessionSaveTask = nil
            pending.cancel()
            _ = await pending.result
        }
        let snapshot = currentWindowSessionSnapshot()
        do {
            try await workspaceStore.saveWindowSession(snapshot)
            windowSessionPersistenceError = nil
            if refreshStatusText == "Window state not saved" {
                refreshStatusText = nil
            }
        } catch {
            windowSessionPersistenceError = error.localizedDescription
            refreshStatusText = "Window state not saved"
            throw error
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
            searchState: SearchWorkspaceState(scope: ordinarySearchScope),
            documentTextScale: documentTextScale
        )
    }

    private func observeWindowSessionChanges() {
        let stateChanges: [AnyPublisher<Void, Never>] = [
            $workspaceAssignment.map { _ in () }.eraseToAnyPublisher(),
            $currentRegisteredVault.map { _ in () }.eraseToAnyPublisher(),
            documentController.$selectedDocument.map { _ in () }.eraseToAnyPublisher(),
            $sidebarVisible.map { _ in () }.eraseToAnyPublisher(),
            $documentTextScale.map { _ in () }.eraseToAnyPublisher(),
            peripheralPresentation.$inspector.map { _ in () }.eraseToAnyPublisher(),
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
        setDocumentTextScale(documentTextScale + delta)
    }

    func setDocumentTextScale(_ requestedScale: Double) {
        let adjusted = min(
            ScholiumMetrics.Document.maximumTextScale,
            max(ScholiumMetrics.Document.minimumTextScale, requestedScale)
        )
        documentTextScale = (adjusted * 10).rounded() / 10
    }

    func resetDocumentTextScale() {
        documentTextScale = ScholiumMetrics.Document.defaultTextScale
    }

    func refreshWorkspaceAssignment(preferredTriptychID: UUID? = nil) async {
        let assignments: [TriptychAssignment]
        do {
            assignments = try await workspaceStore.registeredTriptychs()
        } catch {
            workspaceAssignment = nil
            workspaceRecoveryMessage = error.localizedDescription
            return
        }
        registeredTriptychs = assignments
        let selectedID = preferredTriptychID
            ?? workspaceAssignment?.id
            ?? requestedTriptychID
        let stored: TriptychAssignment?
        if let selectedID {
            stored = assignments.first(where: { $0.id == selectedID })
            if stored == nil {
                workspaceAssignment = nil
                workspaceRecoveryMessage = "This Triptych is no longer registered on this Mac. Open an existing Triptych or choose its three folders again."
                return
            }
        } else {
            stored = try? await workspaceStore.defaultTriptych()
        }
        guard let stored else {
            workspaceAssignment = nil
            return
        }
        do {
            let repaired = try await workspaceStore.reconcileTriptychIdentity(id: stored.id)
            workspaceAssignment = repaired
            try await activateTriptychServices(assignment: repaired)
            if repaired != stored {
                registeredTriptychs = (try? await workspaceStore.registeredTriptychs())
                    ?? registeredTriptychs
            }
        } catch {
            workspaceAssignment = stored
            let repairFailure = error.localizedDescription
            let activated = await activateTriptychServicesReportingFailure(assignment: stored)
            if activated {
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
        researchController.bind(to: capabilities.research, snapshot: snapshot)
        researchController.functions.bind(ResearchFunctionClient(
            availableFunctions: { target in
                try await capabilities.research.availableFunctions(for: target)
            },
            materialCandidates: { target, function in
                try await capabilities.research.materialCandidates(
                    for: target,
                    function: function
                )
            },
            dialogueResponseProfile: {
                try await capabilities.research.dialogueResponseProfile()
            },
            prepare: { [weak self] request in
                guard let self, let assignment = self.workspaceAssignment else {
                    throw ScholiumApplicationError.researchStoreUnavailable(
                        "No workspace is active."
                    )
                }
                try await self.workspaceStore.flushEditors(in: assignment.id)
                return try await capabilities.research.prepareFunction(request)
            },
            complete: { submission in
                try await capabilities.research.completeFunction(submission)
            },
            cancel: { runID in
                try await capabilities.research.cancelFunction(runID: runID)
            }
        ))
        researchController.bibliography.bind(RecommendedBibliographyClient(
            overview: { target in
                try await capabilities.research.recommendationOverview(for: target)
            },
            prepare: { [weak self] request in
                guard let self, let assignment = self.workspaceAssignment else {
                    throw ScholiumApplicationError.researchStoreUnavailable(
                        "No workspace is active."
                    )
                }
                try await self.workspaceStore.flushEditors(in: assignment.id)
                return try await capabilities.research.prepareRecommendation(request)
            },
            cancel: { id in
                try await capabilities.research.cancelRecommendation(id: id)
            },
            dismiss: { requestID, candidateID in
                try await capabilities.research.dismissRecommendation(
                    requestID: requestID,
                    candidateID: candidateID
                )
            }
        ))
        reconcileResearchFunctionPresentation()
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

        if previousIdentity?.triptychID != activation.workspaceID,
           let registration = editorFlushRegistration {
            workspaceStore.unregisterEditorFlush(token: registration.token)
            workspaceStore.registerEditorFlush(
                token: registration.token,
                triptychID: activation.workspaceID,
                windowID: windowSessionID,
                relativePath: registration.relativePath,
                flush: registration.flush
            )
        }
        receiveWorkspaceSnapshot(
            activation.snapshot,
            runtimeIdentity: activation.runtimeIdentity
        )
    }

    func saveTriptychSettings(_ settings: TriptychSettings) async throws {
        try await researchController.saveSettings(settings)
        triptychSettings = settings
    }

    func dialogueResponseProfile() async throws -> DialogueResponseProfile {
        try await researchController.dialogueResponseProfile()
    }

    func saveDialogueResponseProfile(_ profile: DialogueResponseProfile) async throws {
        try await researchController.saveDialogueResponseProfile(profile)
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
        try await workspaceStore.flushEditors(in: assignment.id)
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
        try await workspaceStore.flushEditors(in: assignment.id)
        _ = try await researchController.restoreNote(
            VaultQualifiedNoteID(vaultID: context.vaultID, relativePath: path),
            from: checkpointID,
            expectedRevision: context.fingerprint
        )
        await refreshWindowProjection()
    }

    func dialogueHistory(for path: String) async -> [DialogueEntry] {
        guard let context = activeDocumentContext(for: path) else { return [] }
        return (try? await researchController.dialogueHistory(noteID: context.noteID)) ?? []
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
        try await workspaceStore.flushEditors(in: assignment.id)
        let result = try await researchController.restoreCheckpoint(
            checkpointID,
            selection: selection
        )
        do {
            triptychSettings = try await researchController.settings()
            try await rescanVault()
        } catch {
            refreshStatusText = "Triptych refresh failed after restore"
            workspaceCatalogError = "The checkpoint restore committed successfully, but Scholium could not reload every restored setting or derived view. \(error.localizedDescription)"
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

    func importMarkdownFiles(_ urls: [URL]) async throws -> [URL] {
        var imported: [URL] = []
        for url in urls {
            imported.append(try await documentController.importUnclassifiedMarkdown(at: url))
        }
        return imported
    }

    /// Confirms an ambiguous read-only Zotero match by recording only the
    /// stable item key in the corresponding Analysis. Zotero itself is never
    /// modified. The save uses the same identity and revision checks as every
    /// other structured property edit.
    func confirmZoteroItemKey(
        _ rawItemKey: String,
        for reference: VaultNoteReference
    ) async throws {
        let itemKey = rawItemKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !itemKey.isEmpty,
              itemKey.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
              }) else {
            throw ZoteroBridgeError.invalidItemKey
        }
        guard reference.vaultRole == .sourceCorpus,
              let assignment = workspaceAssignment,
              assignment.vault(for: .paperAnalysis)?.id == reference.vaultID else {
            throw ZoteroBridgeError.invalidAnalysisReference
        }

        try await workspaceStore.flushEditors(in: assignment.id)
        let noteID = VaultQualifiedNoteID(
            vaultID: reference.vaultID,
            relativePath: reference.relativePath
        )
        guard let snapshot = try await documentController.noteSnapshot(noteID),
              snapshot.stableIdentity.resolvedID != nil else {
            throw NoteIdentityRecoveryError.identityUnresolved(reference.relativePath)
        }
        _ = try await documentController.save(
            noteID,
            changeSet: .frontmatter(["zotero_item_key": .string(itemKey)]),
            expectedRevision: snapshot.fingerprint
        )

        if currentRegisteredVault?.id == reference.vaultID {
            try await rescanVault()
        } else {
            scheduleWorkspaceCatalogRefresh()
        }
    }

    func comments(for noteID: UUID) async -> [ResearcherComment] {
        (try? await researchController.comments(noteID: noteID)) ?? []
    }

    @discardableResult
    func addResearcherComment(
        to path: String,
        text: String,
        anchor: ResearcherCommentAnchor
    ) async throws -> HumanReviewRecord {
        let context = try researcherCommentContext(for: path)
        let record = try await researchController.addComment(
            to: VaultQualifiedNoteID(vaultID: context.vaultID, relativePath: path),
            text: text,
            anchor: anchor,
            expectedRevision: context.fingerprint
        )
        storeHumanReviewRecord(record, path: path, vaultID: context.vaultID)
        return record
    }

    func updateResearcherComment(
        at path: String,
        commentID: UUID,
        text: String
    ) async throws {
        let context = try researcherCommentContext(for: path)
        let record = try await researchController.updateComment(
            noteID: context.noteID,
            commentID: commentID,
            text: text
        )
        storeHumanReviewRecord(record, path: path, vaultID: context.vaultID)
    }

    func setResearcherCommentResolved(
        at path: String,
        commentID: UUID,
        resolved: Bool
    ) async throws {
        let context = try researcherCommentContext(for: path)
        let record = try await researchController.setCommentResolved(
            noteID: context.noteID,
            commentID: commentID,
            resolved: resolved
        )
        storeHumanReviewRecord(record, path: path, vaultID: context.vaultID)
    }

    func deleteResearcherComment(at path: String, commentID: UUID) async throws {
        let context = try researcherCommentContext(for: path)
        let record = try await researchController.deleteComment(
            noteID: context.noteID,
            commentID: commentID
        )
        storeHumanReviewRecord(record, path: path, vaultID: context.vaultID)
    }

    func reattachResearcherComment(
        at path: String,
        commentID: UUID,
        anchor: ResearcherCommentAnchor
    ) async throws {
        let context = try researcherCommentContext(for: path)
        let record = try await researchController.reattachComment(
            to: VaultQualifiedNoteID(vaultID: context.vaultID, relativePath: path),
            commentID: commentID,
            anchor: anchor,
            expectedRevision: context.fingerprint
        )
        storeHumanReviewRecord(record, path: path, vaultID: context.vaultID)
    }

    @discardableResult
    func tryReattachingResearcherComments(at path: String) async throws -> HumanReviewRecord {
        let context = try researcherCommentContext(for: path)
        let record = try await researchController.reattachComments(
            to: VaultQualifiedNoteID(vaultID: context.vaultID, relativePath: path),
            expectedRevision: context.fingerprint
        )
        storeHumanReviewRecord(record, path: path, vaultID: context.vaultID)
        return record
    }

    private func researcherCommentContext(
        for path: String
    ) throws -> (noteID: UUID, vaultID: UUID, fingerprint: DocumentFingerprint) {
        guard canCommentCurrentNote,
              let context = activeDocumentContext(for: path) else {
            throw ResearcherCommentWorkflowError.unavailable
        }
        return (context.noteID, context.vaultID, context.fingerprint)
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
        generation: UInt64
    ) async throws {
        guard let vault = workspaceAssignment?.vault(for: slot) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        try await browseRegisteredVault(vault, slot: slot, generation: generation)
    }

    /// Reprojects Library onto another Triptych vault without touching the
    /// selected document. The target snapshot is staged completely before the
    /// browsed-vault identity changes, so a failed browse leaves both Library
    /// and the open editor intact.
    private func browseRegisteredVault(
        _ registered: RegisteredVault,
        slot: WorkspaceVaultSlot? = nil,
        generation: UInt64? = nil
    ) async throws {
        guard let vaultSnapshot = try await documentController.workspaceSnapshot(
            vaultID: registered.id
        ) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let targetConfig = await workspaceStore.vaultConfig(
            rootURL: URL(
                fileURLWithPath: registered.canonicalPath,
                isDirectory: true
            )
        )
        if let generation, generation != libraryBrowseGeneration {
            throw CancellationError()
        }

        let resolvedSlot = slot ?? workspaceSlot(for: registered)
        if let resolvedSlot {
            discoveryController.selectWorkspaceSlot(resolvedSlot)
        }
        noteLocationScope = .workspace
        currentRegisteredVault = registered
        currentVaultRole = registered.role
        vaultConfig = targetConfig
        workspaceVaultSnapshotsByID[registered.id] = vaultSnapshot
        notes = vaultSnapshot.documents
            .filter { $0.lifecycle == .active }
            .map(WindowDocumentLocation.workspace)
            .sorted(by: notesAreOrdered)
        refreshDocumentRevisions()
        await refreshIdentityAndReviewState()
        relationshipGraph = workspaceCatalog?.graph
        allTags = notes.orderedTags
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
        guard !isRefreshingWorkspaceCatalog else {
            workspaceCatalogNeedsAnotherRefresh = true
            return
        }
        isRefreshingWorkspaceCatalog = true
        workspaceCatalogNeedsAnotherRefresh = false
        workspaceCatalogError = nil
        defer {
            isRefreshingWorkspaceCatalog = false
            if workspaceCatalogNeedsAnotherRefresh { scheduleWorkspaceCatalogRefresh() }
        }

        do {
            workspaceCatalog = try await discoveryController.discoverySnapshot().catalog
        } catch {
            workspaceCatalogError = error.localizedDescription
        }
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

            workspaceVaultSnapshotsByID = Dictionary(
                uniqueKeysWithValues: workspaceVaultSnapshots.map { ($0.vault.id, $0) }
            )
            if let slot = workspaceSlot(for: registered) {
                discoveryController.selectWorkspaceSlot(slot)
            }
            currentRegisteredVault = registered
            currentVaultRole = registered.role
            activeTriptychServicesID = assignment.id
            activeWorkspaceCapabilities = capabilities
            vaultConfig = targetConfig
            notes = targetNotes
            refreshDocumentRevisions()
            await refreshIdentityAndReviewState()
            if let snapshot = workspaceStore.snapshot(for: capabilities.id) {
                receiveWorkspaceSnapshot(
                    snapshot,
                    runtimeIdentity: capabilities.runtimeIdentity
                )
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
        // `WorkspaceStore` publishes the authoritative per-vault index and
        // Triptych graph. Keep this method as a window projection refresh for
        // existing callers; it must not create a second graph or index.
        projectionRefreshToken &+= 1
        let refreshToken = projectionRefreshToken
        let startingVaultID = currentRegisteredVault?.id
        // Human Review, qualification, and comments share one atomic store.
        await refreshIdentityAndReviewState()
        let changed = changedSinceReviewPaths
        guard refreshToken == projectionRefreshToken, currentRegisteredVault?.id == startingVaultID else { return }
        changedSinceReviewPaths = changed

        relationshipGraph = try? await discoveryController.discoverySnapshot().catalog.graph
        guard refreshToken == projectionRefreshToken, currentRegisteredVault?.id == startingVaultID else { return }
        if let vaultID = startingVaultID,
           let vault = try? await documentController.workspaceSnapshot(vaultID: vaultID) {
            let snapshots = Dictionary(uniqueKeysWithValues: vault.documents.map { ($0.id.relativePath, $0) })
            notes = notes.map { location in
                snapshots[location.relativePath].map(WindowDocumentLocation.workspace) ?? location
            }
        }

        // Update tags
        let tags = notes.orderedTags
        guard refreshToken == projectionRefreshToken, currentRegisteredVault?.id == startingVaultID else { return }
        allTags = tags

        if noteLocationScope == .workspace, workspaceAssignment != nil {
            scheduleWorkspaceCatalogRefresh()
        }

        // Render on demand. Prewarming every note here runs on the main actor
        // and makes a successful save appear stuck while unrelated documents
        // are rendered.
    }

    private func scheduleWorkspaceCatalogRefresh() {
        workspaceCatalogNeedsAnotherRefresh = true
        workspaceCatalogRefreshTask?.cancel()
        workspaceCatalogRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            await self.refreshWorkspaceCatalog()
        }
    }

    func rescanVault() async throws {
        try await refreshNoteLocationScope()
    }

    func selectNoteLocationScope(_ scope: NoteLocationScope) async {
        guard scope != noteLocationScope else { return }
        do {
            let loaded = try await loadNotes(for: scope)
            noteLocationScope = scope
            documentController.removeAll(retainingSessions: true)
            documentController.resetPresentationState()
            notes = loaded.sorted(by: notesAreOrdered)
            refreshDocumentRevisions()
            await refreshIdentityAndReviewState()
            await refreshWindowProjection()
        } catch {
            showToast(String(localized: "Could not open \(scope.rawValue): \(error.localizedDescription)", table: "Localizable", bundle: .module), kind: .error)
        }
    }

    func refreshNoteLocationScope() async throws {
        notes = try await loadNotes(for: noteLocationScope).sorted(by: notesAreOrdered)
        refreshDocumentRevisions()
        await refreshIdentityAndReviewState()
        await refreshWindowProjection()
    }

    private func loadNotes(for scope: NoteLocationScope) async throws -> [WindowDocumentLocation] {
        if scope == .unclassified {
            let unclassified = try await documentController.unclassifiedDocuments()
            return unclassified.map(WindowDocumentLocation.unclassified)
        }
        guard let vaultID = currentRegisteredVault?.id,
              let vault = try await documentController.workspaceSnapshot(vaultID: vaultID) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let lifecycle: WorkspaceDocumentLifecycle = switch scope {
        case .workspace: .active
        case .setAside: .setAside
        case .trash: .trash
        case .unclassified: .active
        }
        return vault.documents
            .filter { $0.lifecycle == lifecycle }
            .map(WindowDocumentLocation.workspace)
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
        documentRevisions[item.note.relativePath] = item.revision
    }

    func clearPreparedLifecycleOperation(at path: String) {
        guard path.hasPrefix("Set Aside/") || path.hasPrefix("Trash/") else { return }
        noteIdentityByPath[path] = nil
        documentRevisions[path] = nil
    }

    @discardableResult
    func createNote(
        relativePath requestedPath: String,
        title: String,
        analysisResearchStatus: AnalysisResearchStatusChoice = .notYet
    ) async throws -> NoteDocument {
        try await flushRegisteredEditorIfNeeded()
        guard noteLocationScope == .workspace,
              let vaultID = currentRegisteredVault?.id else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let path = Self.markdownPath(requestedPath)
        if currentVaultRole.allowsCritique,
           CritiquePlacement.isManagedCritiquePath(path) {
            throw CritiquePlacementError.directCreationRequiresRequestCritique
        }
        let document = try await documentController.create(DocumentCreationRequest(
            id: VaultQualifiedNoteID(vaultID: vaultID, relativePath: path),
            title: title,
            analysisResearchStatus: analysisResearchStatus
        ))
        try await refreshNoteLocationScope()
        openNote(document.relativePath)
        return document
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
        guard path.hasPrefix("Trash/"),
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

        humanReviewRecords[path] = nil
        noteIdentityByPath[path] = nil
        if let critiquePath = commit.removedCritiqueDocumentPath {
            humanReviewRecords[critiquePath] = nil
            noteIdentityByPath[critiquePath] = nil
        }
        let deletedPaths = Set([path, commit.removedCritiqueDocumentPath].compactMap { $0 })
        try removeDocumentTabs(vaultID: vaultID, removedPaths: deletedPaths)
        try await refreshNoteLocationScope()
        lifecycleMutationGeneration &+= 1
    }

    func classifyUnclassified(
        _ path: String,
        into slot: WorkspaceVaultSlot,
        destination requestedPath: String
    ) async throws {
        try await flushRegisteredEditorIfNeeded()
        guard noteLocationScope == .unclassified,
              let expected = documentRevisions[path] else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let destination = Self.markdownPath(requestedPath)
        do {
            _ = try await documentController.classifyUnclassified(
                path,
                into: slot,
                destinationRelativePath: destination,
                expectedRevision: expected
            )
        } catch {
            await refreshTransactionRecoveryRecords()
            throw error
        }
        try await refreshNoteLocationScope()
        scheduleWorkspaceCatalogRefresh()
        showToast(String(localized: "Classified as \(slot.displayName): \(destination)", table: "Localizable", bundle: .module))
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
        if sourcePath.hasPrefix("Set Aside/")
            || sourcePath.hasPrefix("Trash/")
            || destinationPath.hasPrefix("Set Aside/")
            || destinationPath.hasPrefix("Trash/") {
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
            if identityResolved, let record = humanReviewRecords.removeValue(forKey: sourcePath) {
                humanReviewRecords[destinationPath] = record
            } else {
                humanReviewRecords[sourcePath] = nil
            }
            if changedSinceReviewPaths.remove(sourcePath) != nil {
                changedSinceReviewPaths.insert(destinationPath)
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

    func refreshAdvancedSearch() async {
        let state = advancedSearchState
        do {
            try await discoveryController.executeSearch(
                state,
                context: DiscoverySearchExecutionContext(
                    workspaceIsAvailable: workspaceAssignment != nil,
                    currentNote: selectedDocument,
                    currentVaultID: currentRegisteredVault?.id
                )
            )
            if refreshStatusText == "Search unavailable" { refreshStatusText = nil }
        } catch {
            refreshStatusText = "Search unavailable"
            if !(error is DiscoverySearchExecutionError) {
                workspaceCatalogError = "Search refresh failed. \(error.localizedDescription)"
            }
        }
    }

    func saveCurrentSearch(named requestedName: String) {
        let name = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !advancedSearchState.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let state = advancedSearchState
        enqueueSavedSearchMutation { searches in
            var searches = searches
            searches.insert(SavedSearch(name: name, state: state), at: 0)
            return searches
        }
    }

    func runSavedSearch(_ search: SavedSearch) {
        advancedSearchState = search.state
        showSearchSurface = true
        Task { await refreshAdvancedSearch() }
    }

    func deleteSavedSearch(_ id: UUID) {
        enqueueSavedSearchMutation { searches in
            searches.filter { $0.id != id }
        }
    }

    func renameSavedSearch(_ id: UUID, to requestedName: String) {
        let name = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        enqueueSavedSearchMutation { searches in
            var searches = searches
            guard let index = searches.firstIndex(where: { $0.id == id }) else { return searches }
            searches[index].name = name
            return searches
        }
    }

    func moveSavedSearch(_ id: UUID, by offset: Int) {
        guard offset != 0 else { return }
        enqueueSavedSearchMutation { searches in
            var searches = searches
            guard let source = searches.firstIndex(where: { $0.id == id }) else { return searches }
            let destination = min(max(0, source + offset), searches.count - 1)
            guard source != destination else { return searches }
            let search = searches.remove(at: source)
            searches.insert(search, at: destination)
            return searches
        }
    }

    private func enqueueSavedSearchMutation(
        _ mutation: @escaping @MainActor ([SavedSearch]) -> [SavedSearch]
    ) {
        let previous = savedSearchMutationTail
        savedSearchMutationTail = Task { [weak self] in
            _ = await previous?.value
            guard let self else { return }
            let proposed = mutation(self.savedSearches)
            guard proposed != self.savedSearches else { return }
            do {
                try await self.workspaceStore.saveSavedSearches(proposed)
                guard !Task.isCancelled else { return }
                self.savedSearches = proposed
            } catch {
                self.showToast(String(localized: "Could not save search: \(error.localizedDescription)", table: "Localizable", bundle: .module), kind: .error)
            }
        }
    }

    func openNote(
        _ path: String,
        tabActivation: DocumentTabActivation = .replaceSelectedTab
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
        } else {
            documentController.selectDocument(selectionDescriptor(for: path))
        }
        synchronizeDocumentTabs(after: tabActivation)
    }

    private func openRestoredDocument(_ id: VaultQualifiedNoteID) {
        guard let vault = workspaceAssignment?.vaults.values.first(where: { $0.id == id.vaultID }),
              let snapshot = workspaceVaultSnapshotsByID[id.vaultID]?.documents.first(where: {
                  $0.id.relativePath == id.relativePath
              }) else { return }
        PerformanceProbe.shared.beginReadActivation(documentID: id.relativePath)
        documentController.installOpenedDocument(
            snapshot,
            vaultName: vault.name,
            vaultRole: vault.role
        )
        synchronizeDocumentTabs(after: .replaceSelectedTab)
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
        case .unclassified(let relativePath):
            guard let location = notes.first(where: { $0.relativePath == relativePath }) else {
                throw WindowNavigationError.noteUnavailable(relativePath)
            }
            PerformanceProbe.shared.beginReadActivation(documentID: relativePath)
            documentController.selectUnclassifiedDocument(relativePath: relativePath)
            if location.workspaceSnapshot != nil {
                documentController.selectDocument(document)
            }
            synchronizeDocumentTabs(after: tabActivation)
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
        guard let snapshot = workspaceVaultSnapshotsByID[reference.vaultID]?.documents.first(where: {
            if let requestedStableID,
               $0.stableIdentity.resolvedID == requestedStableID {
                return true
            }
            return $0.id.relativePath == reference.relativePath
        }) else {
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
        case .replaceSelectedTab:
            documentTabController.replaceSelectedTab(
                with: document,
                title: presentation.title,
                toolTip: presentation.toolTip
            )
        case .appendTab:
            documentTabController.appendTab(
                for: document,
                title: presentation.title,
                toolTip: presentation.toolTip
            )
        case .preserveTabMembership:
            documentTabController.updateDocumentProjection(
                document,
                title: presentation.title,
                toolTip: presentation.toolTip
            )
        }
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
    }

    private func refreshDocumentTabProjections() {
        for tab in documentTabController.tabs {
            guard case .workspace(let descriptor) = tab.document,
                  let snapshot = workspaceVaultSnapshotsByID[descriptor.reference.vaultID]?
                    .documents.first(where: {
                        $0.stableIdentity.resolvedID == descriptor.sessionKey.noteID
                    }),
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
            workspaceVaultSnapshotsByID[sessionKey.vaultID]?.documents
                .first(where: { $0.stableIdentity.resolvedID == sessionKey.noteID })
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

    private func selectionDescriptor(for path: String) -> WindowSelectedDocument {
        if let descriptor = documentDescriptor(for: path) {
            return .workspace(descriptor)
        }
        if noteLocationScope == .unclassified {
            return .unclassified(relativePath: path)
        }
        guard let vaultID = notes.first(where: { $0.relativePath == path })?
            .workspaceSnapshot?.id.vaultID ?? currentRegisteredVault?.id else {
            return .unclassified(relativePath: path)
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
        } else if documentController.activeDocument == nil {
            documentController.selectDocument(selectionDescriptor(for: selectedDocumentPath))
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

    func reviewNote(at path: String) {
        guard let context = activeDocumentContext(for: path),
              context.vaultRole.allowsHumanReview else { return }
        openResearchFunction(.dialogue, permitsUnavailablePresentation: true)
    }

    func finishJudgmentPanelDismissal() {
        pendingCommentSelection = nil
        focusedResearcherCommentID = nil
    }

    func reviewDisplayState(for path: String) -> HumanReviewDisplayState {
        guard let revision = documentRevisions[path],
              let record = humanReviewRecords[path],
              let review = record.review(for: revision) else {
            return .notReviewed
        }
        return HumanReviewDisplayState(isReviewed: true, qualification: review.qualification)
    }

    func saveHumanReviewDraft(
        for path: String,
        fingerprint: DocumentFingerprint,
        qualification: NoteQualification?,
        reviewNote: String
    ) async throws {
        guard let context = activeDocumentContext(for: path),
              context.vaultRole.allowsHumanReview else {
            throw HumanReviewWorkflowError.unavailableForOutput
        }
        guard context.fingerprint == fingerprint else {
            throw HumanReviewWorkflowError.staleRevision
        }
        let record = try await researchController.saveHumanReviewDraft(
            for: VaultQualifiedNoteID(vaultID: context.vaultID, relativePath: path),
            expectedRevision: fingerprint,
            qualification: qualification,
            reviewNote: reviewNote
        )
        storeHumanReviewRecord(record, path: path, vaultID: context.vaultID)
    }

    func completeHumanReview(
        for path: String,
        fingerprint: DocumentFingerprint,
        qualification: NoteQualification?,
        reviewNote: String
    ) async throws {
        guard let context = activeDocumentContext(for: path),
              context.vaultRole.allowsHumanReview else {
            throw HumanReviewWorkflowError.unavailableForOutput
        }
        guard context.fingerprint == fingerprint else {
            throw HumanReviewWorkflowError.staleRevision
        }
        let record = try await researchController.completeHumanReview(
            for: VaultQualifiedNoteID(vaultID: context.vaultID, relativePath: path),
            expectedRevision: fingerprint,
            qualification: qualification,
            reviewNote: reviewNote
        )
        storeHumanReviewRecord(record, path: path, vaultID: context.vaultID)
        if currentRegisteredVault?.id == context.vaultID {
            changedSinceReviewPaths.remove(path)
        }
        if let snapshot = try? await documentController.noteSnapshot(
            VaultQualifiedNoteID(vaultID: context.vaultID, relativePath: path)
        ) {
            replaceCachedWorkspaceNote(snapshot)
            if currentRegisteredVault?.id == context.vaultID,
               let index = notes.firstIndex(where: { $0.relativePath == path }) {
                notes[index] = .workspace(snapshot)
            }
        }
        await refreshWorkspaceCatalog()
    }

    func openWorkspaceReference(
        _ reference: VaultNoteReference,
        line: Int? = nil,
        mode: NotePresentationMode = .source
    ) async {
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            try self.activateWorkspaceReference(
                reference,
                tabActivation: .replaceSelectedTab
            )
            if let line {
                self.pendingSourceLine = max(1, line)
                self.requestPresentationMode = mode
            }
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
            let saved = await replaceSavedDocument(result.document)
            lastSaveError = nil
            return saved
        } catch {
            lastSaveError = error.localizedDescription
            throw error
        }
    }

    func diskDocument(for path: String) async throws -> NoteDocument {
        if noteLocationScope == .unclassified {
            return try await documentController.loadUnclassified(relativePath: path)
        }
        guard let context = activeDocumentContext(for: path) else {
            throw VaultRepositoryError.fileDoesNotExist(path)
        }
        return try await documentController.load(
            VaultQualifiedNoteID(vaultID: context.vaultID, relativePath: path)
        )
    }

    func showToast(_ message: String, kind: Toast.Kind = .success) {
        let toast = Toast(message: message, kind: kind)
        toastMessage = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.toastMessage == toast { self?.toastMessage = nil }
        }
    }

    private func refreshDocumentRevisions() {
        documentRevisions = Dictionary(uniqueKeysWithValues: notes.map {
            ($0.relativePath, DocumentFingerprint(content: $0.rawContent))
        })
    }

    private func refreshIdentityAndReviewState() async {
        identityReviewRefreshGeneration &+= 1
        let refreshGeneration = identityReviewRefreshGeneration
        guard noteLocationScope != .unclassified,
              let vault = currentRegisteredVault else {
            noteIdentityByPath = [:]
            identityAmbiguities = []
            pendingIdentityRebindings = []
            identityMigrationFailures = []
            humanReviewRecords = [:]
            changedSinceReviewPaths = []
            return
        }
        let locationScope = noteLocationScope
        let noteSnapshot = notes
        let revisionSnapshot = Dictionary(uniqueKeysWithValues: noteSnapshot.map { note in
            (
                note.relativePath,
                documentRevisions[note.relativePath] ?? DocumentFingerprint(content: note.rawContent)
            )
        })
        guard refreshGeneration == identityReviewRefreshGeneration,
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
            guard refreshGeneration == identityReviewRefreshGeneration,
                  currentRegisteredVault?.id == vault.id,
                  noteLocationScope == locationScope else { return }
            noteIdentityByPath = [:]
            identityResolutionError = error.localizedDescription
            return
        }
        guard refreshGeneration == identityReviewRefreshGeneration,
              currentRegisteredVault?.id == vault.id,
              noteLocationScope == locationScope else { return }
        let identities = recovery.identities

        var records: [String: HumanReviewRecord] = [:]
        var changed: Set<String> = []
        var reviewStateByPath: [String: (isReviewed: Bool, reviewedAt: Date?)] = [:]
        var commentRefreshFailure: String?
        var storedReviewRecords = humanReviewRecordsByNoteID
        do {
            let snapshot = try await researchController.researchSnapshot()
            storedReviewRecords = Dictionary(
                snapshot.humanReviews.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        } catch {
            commentRefreshFailure = error.localizedDescription
        }
        for note in noteSnapshot {
            let path = note.relativePath
            guard let noteID = identities[path]?.id else {
                reviewStateByPath[path] = (false, nil)
                continue
            }
            let fingerprint = revisionSnapshot[path] ?? DocumentFingerprint(content: note.rawContent)
            var record = storedReviewRecords[noteID]
            if record?.comments.contains(where: {
                   $0.anchor.fingerprint != fingerprint
               }) == true {
                guard refreshGeneration == identityReviewRefreshGeneration else { return }
                do {
                    let reattached = try await researchController.reattachComments(
                        to: VaultQualifiedNoteID(vaultID: vault.id, relativePath: path),
                        expectedRevision: fingerprint
                    )
                    record = reattached
                    storedReviewRecords[noteID] = reattached
                } catch {
                    commentRefreshFailure = error.localizedDescription
                }
            }
            guard refreshGeneration == identityReviewRefreshGeneration else { return }
            guard let record else {
                guard refreshGeneration == identityReviewRefreshGeneration else { return }
                reviewStateByPath[path] = (false, nil)
                continue
            }
            guard refreshGeneration == identityReviewRefreshGeneration else { return }
            records[path] = record
            if let currentReview = record.review(for: fingerprint) {
                reviewStateByPath[path] = (true, currentReview.completedAt)
            } else {
                reviewStateByPath[path] = (false, record.latestReview?.completedAt)
                if record.latestReview != nil { changed.insert(path) }
            }
        }

        let currentRevisions = Dictionary(uniqueKeysWithValues: notes.map { note in
            (
                note.relativePath,
                documentRevisions[note.relativePath] ?? DocumentFingerprint(content: note.rawContent)
            )
        })
        guard refreshGeneration == identityReviewRefreshGeneration,
              currentRegisteredVault?.id == vault.id,
              noteLocationScope == locationScope,
              currentRevisions == revisionSnapshot else { return }

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
            notes = notes.map { location in
                snapshots[location.relativePath].map(WindowDocumentLocation.workspace) ?? location
            }
        }
        refreshSelectedDocumentProjection()
        humanReviewRecordsByNoteID = storedReviewRecords
        humanReviewRecords = records
        changedSinceReviewPaths = changed
        if let commentRefreshFailure {
            refreshStatusText = "Researcher comments refresh failed"
            workspaceCatalogError = "Scholium left the existing comment records unchanged because their anchors could not be refreshed safely. \(commentRefreshFailure)"
        }
    }

    private func resetWindowSession() {
        presentationRouter.dismissAll()
        documentController.removeAll(retainingSessions: true)
        discoveryController.reset()
        researchController.reset()
        notes = []
        documentController.resetPresentationState()
        pendingSourceLine = nil
        clearMetadataFilters()
        currentRegisteredVault = nil
        currentVaultRole = .other
        pendingCommentSelection = nil
        focusedResearcherCommentID = nil
        humanReviewRecords = [:]
        humanReviewRecordsByNoteID = [:]
        noteIdentityByPath = [:]
        identityAmbiguities = []
        pendingIdentityRebindings = []
        identityMigrationFailures = []
        identityResolutionError = nil
        dialogueInitialNotes = []
        documentRevisions = [:]
        relationshipGraph = nil
        workspaceVaultSnapshotsByID = [:]
        derivedRefreshStatus = nil
    }

    private func receiveWorkspaceSnapshots(
        _ snapshots: [UUID: WorkspaceSnapshot]
    ) {
        guard let capabilities = activeWorkspaceCapabilities,
              let snapshot = snapshots[capabilities.id] else { return }
        receiveWorkspaceSnapshot(snapshot, runtimeIdentity: capabilities.runtimeIdentity)
    }

    private func receiveWorkspaceEvents(_ events: [UUID: WorkspaceEvent]) {
        guard let capabilities = activeWorkspaceCapabilities,
              let event = events[capabilities.id],
              case .inventoryChanged(let change) = event,
              let vaultID = currentRegisteredVault?.id else { return }
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

    private func receiveWorkspaceSnapshot(
        _ snapshot: WorkspaceSnapshot,
        runtimeIdentity: TriptychRuntimeIdentity
    ) {
        guard activeWorkspaceCapabilities?.runtimeIdentity == runtimeIdentity else { return }
        documentController.receive(snapshot)
        researchController.receive(snapshot)
        guard let watchedVaultID = currentRegisteredVault?.id else { return }

        let predecessor = workspaceProjectionTail
        workspaceProjectionTail = Task { [weak self] in
            _ = await predecessor?.result
            guard !Task.isCancelled,
                  let self,
                  self.activeWorkspaceCapabilities?.runtimeIdentity == runtimeIdentity,
                  self.currentRegisteredVault?.id == watchedVaultID else { return }
            await self.applyWorkspaceSnapshot(snapshot, vaultID: watchedVaultID)
        }
    }

    private func receiveWorkspaceDerivedRefreshStatuses(
        _ statuses: [UUID: WorkspaceDerivedRefreshStatus]
    ) {
        guard let capabilities = activeWorkspaceCapabilities,
              let status = statuses[capabilities.id] else { return }
        let runtimeIdentity = capabilities.runtimeIdentity
        let predecessor = workspaceProjectionTail
        workspaceProjectionTail = Task { [weak self] in
            _ = await predecessor?.result
            guard !Task.isCancelled,
                  let self,
                  self.activeWorkspaceCapabilities?.runtimeIdentity == runtimeIdentity else { return }
            self.applyDerivedRefreshStatus(status)
        }
    }

    private func applyDerivedRefreshStatus(_ status: WorkspaceDerivedRefreshStatus) {
        derivedRefreshStatus = status
        switch status {
        case .current:
            if refreshStatusText == "Derived state is stale"
                || refreshStatusText == "Derived refresh failed" {
                refreshStatusText = nil
            }
            workspaceCatalogError = nil
        case .stale(let issue):
            if refreshStatusText?.hasPrefix("Conflict:") != true {
                refreshStatusText = "Derived state is stale"
            }
            workspaceCatalogError = issue.reason
        case .failed(let issue):
            if refreshStatusText?.hasPrefix("Conflict:") != true {
                refreshStatusText = "Derived refresh failed"
            }
            workspaceCatalogError = issue.reason
        }
    }

    private func applyWorkspaceSnapshot(
        _ snapshot: WorkspaceSnapshot,
        vaultID: UUID
    ) async {
        workspaceCatalog = snapshot.discovery.catalog
        workspaceVaultSnapshotsByID = Dictionary(
            uniqueKeysWithValues: snapshot.vaults.map { ($0.vault.id, $0) }
        )
        refreshDocumentTabProjections()
        guard noteLocationScope == .workspace else {
            try? await refreshNoteLocationScope()
            return
        }
        guard let vault = snapshot.vault(id: vaultID) else { return }

        let previousByPath = Dictionary(uniqueKeysWithValues: notes.map { ($0.relativePath, $0) })
        var refreshed = vault.documents
            .filter { $0.lifecycle == .active }
            .map(WindowDocumentLocation.workspace)
            .sorted {
                $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }
        let editingDocumentPath = documentController.editingDocumentPath
        let activeRecoveryNote: WindowDocumentLocation? = {
            guard currentDocumentVaultID == vaultID,
                  let selectedDocumentPath,
                  editingDocumentPath == selectedDocumentPath,
                  !refreshed.contains(where: { $0.relativePath == selectedDocumentPath }) else { return nil }
            return previousByPath[selectedDocumentPath]
        }()
        if let activeRecoveryNote {
            refreshed.append(activeRecoveryNote)
            refreshStatusText = "Conflict: note deleted outside Scholium"
        }

        notes = refreshed.sorted(by: notesAreOrdered)
        refreshDocumentRevisions()
        if let activeRecoveryNote {
            documentRevisions[activeRecoveryNote.relativePath] = previousByPath[activeRecoveryNote.relativePath]
                .map { DocumentFingerprint(content: $0.rawContent) }
        }
        await refreshIdentityAndReviewState()
        relationshipGraph = snapshot.discovery.catalog.graph
        allTags = notes.orderedTags
        workspaceCatalogError = nil
    }

    private func replaceCachedWorkspaceNote(_ note: WorkspaceNoteSnapshot) {
        guard let vaultSnapshot = workspaceVaultSnapshotsByID[note.id.vaultID] else { return }
        var documents = vaultSnapshot.documents
        if let noteID = note.stableIdentity.resolvedID,
           let index = documents.firstIndex(where: { $0.stableIdentity.resolvedID == noteID }) {
            documents[index] = note
        } else if let index = documents.firstIndex(where: { $0.id == note.id }) {
            documents[index] = note
        } else {
            documents.append(note)
        }
        workspaceVaultSnapshotsByID[note.id.vaultID] = WorkspaceVaultSnapshot(
            slot: vaultSnapshot.slot,
            vault: vaultSnapshot.vault,
            documents: documents,
            identityRecovery: vaultSnapshot.identityRecovery
        )
        refreshDocumentTabProjections()
        documentController.recordCommittedSnapshot(
            note,
            vaultName: vaultSnapshot.vault.name,
            vaultRole: vaultSnapshot.vault.role
        )
    }

    /// Publishes authoritative document bytes before refreshing disposable
    /// projections. A parse or index failure can make derived state stale, but
    /// must never make the editor retry an already committed repository write
    /// or reject a disk revision the researcher explicitly accepted.
    private func replaceSavedDocument(_ document: NoteDocument) async -> WindowDocumentLocation {
        if case .unclassified? = documentController.selectedDocument {
            let saved = WindowDocumentLocation.unclassified(document)
            if noteLocationScope == .unclassified,
               let index = notes.firstIndex(where: { $0.relativePath == document.relativePath }) {
                notes[index] = saved
            }
            return saved
        }

        guard let context = activeDocumentContext(for: document.relativePath) else {
            return .unclassified(document)
        }
        let previous = workspaceVaultSnapshotsByID[context.vaultID]?.documents.first(where: {
            $0.stableIdentity.resolvedID == context.noteID
                || $0.id.relativePath == document.relativePath
        })
        let loaded = try? await documentController.noteSnapshot(VaultQualifiedNoteID(
            vaultID: context.vaultID,
            relativePath: document.relativePath
        ))
        let savedSnapshot: WorkspaceNoteSnapshot
        if let loaded, loaded.fingerprint == document.fingerprint {
            savedSnapshot = loaded
        } else if let previous {
            savedSnapshot = WorkspaceNoteSnapshot(
                id: previous.id,
                vaultRole: previous.vaultRole,
                stableIdentity: previous.stableIdentity,
                document: document,
                fileMetadata: WorkspaceFileMetadata(
                    byteCount: document.sourceBytes.count,
                    creationDate: previous.fileMetadata.creationDate,
                    modificationDate: previous.fileMetadata.modificationDate
                ),
                lifecycle: previous.lifecycle,
                review: previous.review,
                graphCounts: previous.graphCounts
            )
        } else {
            savedSnapshot = WorkspaceNoteSnapshot(
                id: VaultQualifiedNoteID(
                    vaultID: context.vaultID,
                    relativePath: document.relativePath
                ),
                vaultRole: context.vaultRole,
                stableIdentity: .resolved(context.noteID),
                document: document,
                fileMetadata: WorkspaceFileMetadata(
                    byteCount: document.sourceBytes.count,
                    creationDate: nil,
                    modificationDate: nil
                ),
                lifecycle: .active,
                review: nil,
                graphCounts: WorkspaceGraphCounts(
                    incoming: 0,
                    outgoing: 0,
                    broken: 0,
                    ambiguous: 0
                )
            )
        }

        replaceCachedWorkspaceNote(savedSnapshot)
        let saved = WindowDocumentLocation.workspace(savedSnapshot)
        if currentRegisteredVault?.id == context.vaultID {
            if let index = notes.firstIndex(where: { $0.relativePath == document.relativePath }) {
                notes[index] = saved
            } else {
                notes.append(saved)
                notes.sort(by: notesAreOrdered)
            }
            documentRevisions[document.relativePath] = document.fingerprint
        }
        await refreshWindowProjection()
        if currentRegisteredVault?.id == context.vaultID {
            return notes.first(where: { $0.relativePath == document.relativePath }) ?? saved
        }
        return saved
    }

    private func knowledgeBase(for role: VaultRole) -> KnowledgeBase {
        switch role {
        case .sourceCorpus: .papers
        case .topicKnowledge: .topics
        case .draftProject, .other: .output
        }
    }

}

private enum HumanReviewWorkflowError: LocalizedError {
    case staleRevision
    case unavailableForOutput

    var errorDescription: String? {
        switch self {
        case .staleRevision:
            return String(localized: "The note changed while this review was open. Reopen Review and check the current text before saving.", table: "Localizable", bundle: .module)
        case .unavailableForOutput:
            return String(localized: "Human Review is unavailable in Works. Request a Critique for an ordinary Work note instead.", table: "Localizable", bundle: .module)
        }
    }
}

private enum ResearcherCommentWorkflowError: LocalizedError {
    case unavailable
    case staleRevision

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return String(localized: "Comments are unavailable until Scholium can identify this Analysis, Topic, or Work reliably.", table: "Localizable", bundle: .module)
        case .staleRevision:
            return String(localized: "The note changed before the Comment could be attached. Reopen the Review or Critique panel and select the current passage.", table: "Localizable", bundle: .module)
        }
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
