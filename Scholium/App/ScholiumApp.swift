import AppKit
import Combine
import SwiftUI
import ScholiumCore
import UniformTypeIdentifiers

@MainActor
private final class ScholiumTerminationCoordinator {
    static let shared = ScholiumTerminationCoordinator()
    private var flushers: [UUID: @MainActor () async throws -> Void] = [:]

    var hasRegisteredWindows: Bool { !flushers.isEmpty }

    func register(
        _ id: UUID,
        flush: @escaping @MainActor () async throws -> Void
    ) {
        flushers[id] = flush
    }

    func unregister(_ id: UUID) {
        flushers[id] = nil
    }

    func flushAll() async throws {
        for flush in Array(flushers.values) {
            try await flush()
        }
    }
}

@MainActor
private final class ScholiumApplicationDelegate: NSObject, NSApplicationDelegate {
    private var terminationInFlight = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard ScholiumTerminationCoordinator.shared.hasRegisteredWindows else {
            return .terminateNow
        }
        guard !terminationInFlight else { return .terminateLater }
        terminationInFlight = true
        Task { @MainActor in
            do {
                try await ScholiumTerminationCoordinator.shared.flushAll()
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
    let createsTriptych: Bool

    init(
        windowID: UUID = UUID(),
        triptychID: UUID? = nil,
        createsTriptych: Bool = false
    ) {
        self.windowID = windowID
        self.triptychID = triptychID
        self.createsTriptych = createsTriptych
    }
}

@main
struct ScholiumApp: App {
    @NSApplicationDelegateAdaptor(ScholiumApplicationDelegate.self) private var applicationDelegate
    @StateObject private var workspaceStore = WorkspaceStore()

    init() {
        // A New Window command must create an independent work session even
        // when the system preference normally opens documents as tabs. Users
        // can still group Scholium windows deliberately with native tabbing.
        NSWindow.allowsAutomaticWindowTabbing = false
        // Swift Package schemes run ScholiumApp as a raw executable rather
        // than through the packaged .app. On beta macOS/Xcode that process can
        // otherwise remain background-only even though SwiftUI created a scene.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let application = NSApplication.shared
            application.unhide(nil)
            for window in application.windows where window.canBecomeKey {
                window.makeKeyAndOrderFront(nil)
            }
            application.activate(ignoringOtherApps: true)
        }
        ScholiumFontRegistry.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup(id: "scholium-main", for: TriptychWindowRoute.self) { route in
            ScholiumWindowRoot(
                workspaceStore: workspaceStore,
                route: route
            )
        }
        .defaultSize(width: 1380, height: 880)
        .windowToolbarStyle(.unified)
        .commands { ScholiumCommands() }

        Settings {
            ScholiumSettingsRoot(workspaceStore: workspaceStore)
        }
    }
}

private struct ScholiumWindowRoot: View {
    @SceneStorage("scholium.windowSessionID") private var storedWindowSessionID = ""
    @Binding private var route: TriptychWindowRoute?
    @StateObject private var appState: AppState
    @State private var registeredTerminationID: UUID?

    init(workspaceStore: WorkspaceStore, route: Binding<TriptychWindowRoute?>) {
        _route = route
        let requestedRoute = route.wrappedValue
        _appState = StateObject(wrappedValue: AppState(
            workspaceStore: workspaceStore,
            requestedTriptychID: requestedRoute?.triptychID,
            createsTriptych: requestedRoute?.createsTriptych == true
        ))
    }

    var body: some View {
        ContentView()
            .environmentObject(appState)
            .focusedSceneValue(\.scholiumAppState, appState)
            .background(WindowCloseGuard(appState: appState))
            .frame(minWidth: 760, minHeight: 520)
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
                            appState.showToast("Imported \(imported.count) Markdown file\(imported.count == 1 ? "" : "s") into Unclassified.")
                        } catch {
                            appState.vaultError = error.localizedDescription
                        }
                    }
                case .failure(let error):
                    appState.vaultError = error.localizedDescription
                }
            }
            .preferredColorScheme(colorScheme)
            .task(id: resolvedWindowSessionID) {
                if storedWindowSessionID.isEmpty {
                    storedWindowSessionID = resolvedWindowSessionID.uuidString
                }
                await appState.restoreWindowSession(id: resolvedWindowSessionID)
                registerTerminationFlusher()
            }
            .onAppear {
                registerTerminationFlusher()
            }
            .onDisappear {
                if let registeredTerminationID {
                    ScholiumTerminationCoordinator.shared.unregister(registeredTerminationID)
                }
                registeredTerminationID = nil
                appState.persistWindowSessionNow()
            }
    }

    private var resolvedWindowSessionID: UUID {
        if let raw = ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_SESSION_ID"],
           let id = UUID(uuidString: raw) {
            return id
        }
        return UUID(uuidString: storedWindowSessionID) ?? appState.windowSessionID
    }

    private func registerTerminationFlusher() {
        let currentID = appState.windowSessionID
        if let registeredTerminationID, registeredTerminationID != currentID {
            ScholiumTerminationCoordinator.shared.unregister(registeredTerminationID)
        }
        guard registeredTerminationID != currentID else { return }
        ScholiumTerminationCoordinator.shared.register(currentID) {
            try await appState.prepareForWindowClose()
        }
        registeredTerminationID = currentID
    }

    private var colorScheme: ColorScheme? {
        switch appState.colorScheme {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}

private struct WindowCloseGuard: NSViewRepresentable {
    let appState: AppState

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    func makeNSView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.onWindowAttachment = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: WindowAttachmentView, context: Context) {
        context.coordinator.appState = appState
        if let window = nsView.window { context.coordinator.attach(to: window) }
    }

    static func dismantleNSView(_ nsView: WindowAttachmentView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class WindowAttachmentView: NSView {
        var onWindowAttachment: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            onWindowAttachment?(window)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        var appState: AppState
        private weak var window: NSWindow?
        nonisolated(unsafe) private weak var previousDelegate: (any NSWindowDelegate)?
        private var closeIsAuthorized = false
        private var flushInFlight = false

        init(appState: AppState) {
            self.appState = appState
            super.init()
        }

        func attach(to window: NSWindow) {
            guard self.window !== window || window.delegate !== self else { return }
            detach()
            self.window = window
            previousDelegate = window.delegate
            window.delegate = self
            if ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_WORKSPACE_ROOT"] != nil,
               let rawWidth = ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_WINDOW_WIDTH"],
               let requestedWidth = Double(rawWidth),
               requestedWidth > 0 {
                window.setContentSize(
                    NSSize(
                        width: requestedWidth,
                        height: window.contentLayoutRect.height
                    )
                )
            }
            appState.windowWidth = window.contentLayoutRect.width
        }

        func detach() {
            if let window, window.delegate === self {
                window.delegate = previousDelegate
            }
            window = nil
            previousDelegate = nil
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if closeIsAuthorized {
                closeIsAuthorized = false
                return true
            }
            guard !flushInFlight else { return false }
            flushInFlight = true
            Task { @MainActor [weak self, weak sender] in
                guard let self, let sender else { return }
                do {
                    try await appState.prepareForWindowClose()
                    closeIsAuthorized = true
                    flushInFlight = false
                    sender.performClose(nil)
                } catch {
                    flushInFlight = false
                    appState.lastSaveError = error.localizedDescription
                    appState.showToast(
                        "Scholium kept this window open because the current note could not be saved. \(error.localizedDescription)",
                        kind: .error
                    )
                }
            }
            return false
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || previousDelegate?.responds(to: selector) == true
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            if previousDelegate?.responds(to: selector) == true { return previousDelegate }
            return super.forwardingTarget(for: selector)
        }
    }
}

private struct ScholiumSettingsRoot: View {
    @StateObject private var appState: AppState
    init(workspaceStore: WorkspaceStore) {
        _appState = StateObject(wrappedValue: AppState(workspaceStore: workspaceStore))
    }
    var body: some View {
        ScholiumSettingsView()
            .environmentObject(appState)
            .frame(width: 700, height: 560)
            .task {
                await appState.refreshRegisteredVaults()
                if let rawID = UserDefaults.standard.string(forKey: "scholium.settings.triptychID"),
                   let triptychID = UUID(uuidString: rawID) {
                    await appState.activateRegisteredTriptych(id: triptychID)
                    if appState.workspaceAssignment == nil {
                        await appState.restoreLastVaultIfNeeded()
                    }
                } else {
                    await appState.restoreLastVaultIfNeeded()
                }
            }
    }
}

private struct ScholiumAppStateFocusedKey: FocusedValueKey {
    typealias Value = AppState
}

struct ScholiumSearchActions {
    let begin: (SearchPresentationScope) -> Void
}

struct ScholiumSearchActionsFocusedKey: FocusedValueKey {
    typealias Value = ScholiumSearchActions
}

extension FocusedValues {
    var scholiumAppState: AppState? {
        get { self[ScholiumAppStateFocusedKey.self] }
        set { self[ScholiumAppStateFocusedKey.self] = newValue }
    }

    var scholiumSearchActions: ScholiumSearchActions? {
        get { self[ScholiumSearchActionsFocusedKey.self] }
        set { self[ScholiumSearchActionsFocusedKey.self] = newValue }
    }
}

fileprivate struct RecentNoteDestination: Identifiable {
    let id: VaultQualifiedNoteID
    let reference: VaultNoteReference
    let title: String
}

private struct ScholiumCommands: Commands {
    @FocusedValue(\.scholiumAppState) private var appState
    @FocusedValue(\.scholiumSearchActions) private var searchActions
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
                    id: "scholium-main",
                    value: TriptychWindowRoute(
                        triptychID: UUID(),
                        createsTriptych: true
                    )
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
            Button("Duplicate Note…") {
                guard let path = appState?.currentNote?.relativePath else { return }
                appState?.noteLifecycleRequest = .duplicate(path)
            }
            .disabled(appState?.canEditCurrentNote != true || appState?.noteLocationScope != .workspace)
            Button("Move or Rename Note…") {
                guard let path = appState?.currentNote?.relativePath else { return }
                appState?.noteLifecycleRequest = .move(path)
            }
            .disabled(appState?.canEditCurrentNote != true || appState?.noteLocationScope != .workspace)
            Divider()
            Button("Close Tab") {
                guard let appState, let path = appState.activeTab else { return }
                appState.requestCloseTab(path)
            }
                .keyboardShortcut("w", modifiers: [.command])
                .disabled(appState?.activeTab == nil)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Search This Note…") {
                searchActions?.begin(.thisNote)
            }
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(searchActions == nil)
        }
        CommandGroup(after: .sidebar) {
            Button(appState?.sidebarVisible == true ? "Hide Sidebar" : "Show Sidebar") {
                appState?.sidebarVisible.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            Button(appState?.backlinksVisible == true ? "Hide Research Inspector" : "Show Research Inspector") {
                guard let appState else { return }
                appState.setResearchInspectorVisible(!appState.backlinksVisible, animated: false)
            }
            .keyboardShortcut("b", modifiers: [.command, .option])
            .disabled(appState?.currentNote == nil)
            Menu("Document Mode") {
                Button("Read") { appState?.requestDocumentMode(.read) }
                Button("Live Preview") { appState?.requestDocumentMode(.livePreview) }
                    .disabled(appState?.canEditCurrentNote != true)
                Button("Source") { appState?.requestDocumentMode(.source) }
                    .disabled(appState?.canEditCurrentNote != true)
            }
            .disabled(appState?.currentNote == nil)
            Divider()
            Button("Increase Document Text Size") { appState?.adjustDocumentTextScale(by: 0.1) }
                .keyboardShortcut("=", modifiers: [.command])
                .disabled(appState?.currentNote == nil || appState?.documentTextScale == 2.0)
            Button("Decrease Document Text Size") { appState?.adjustDocumentTextScale(by: -0.1) }
                .keyboardShortcut("-", modifiers: [.command])
                .disabled(appState?.currentNote == nil || appState?.documentTextScale == 1.0)
            Button("Actual Document Text Size") { appState?.resetDocumentTextScale() }
                .keyboardShortcut("0", modifiers: [.command])
                .disabled(appState?.currentNote == nil || appState?.documentTextScale == 1.0)
            Menu("Appearance") {
                Button("Use System Appearance") { appState?.colorScheme = .system }
                Button("Light") { appState?.colorScheme = .light }
                Button("Dark") { appState?.colorScheme = .dark }
            }
        }
        CommandMenu("Navigate") {
            Button("Back") { appState?.requestNavigateBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled((appState?.navigationIndex ?? 0) <= 0)
            Button("Forward") { appState?.requestNavigateForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled((appState?.navigationIndex ?? -1) >= (appState?.navigationStack.count ?? 0) - 1)
            Menu("Recent Notes") {
                if recentNotes.isEmpty {
                    Button("No Recent Notes") {}
                        .disabled(true)
                } else {
                    ForEach(recentNotes) { destination in
                        Button(recentNoteCommandLabel(destination)) {
                            appState?.requestOpenNote(destination.reference)
                        }
                    }
                    Divider()
                    Button("Clear Recent Notes") {
                        appState?.clearRecentNotes()
                    }
                }
            }
            .disabled(appState == nil)
            Divider()
            Button("Previous Document Tab") { appState?.requestSelectPreviousTab() }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .disabled((appState?.openTabs.count ?? 0) < 2)
            Button("Next Document Tab") { appState?.requestSelectNextTab() }
                .keyboardShortcut(.tab, modifiers: [.control])
                .disabled((appState?.openTabs.count ?? 0) < 2)
            Divider()
            Button("Go to Note…") { appState?.showQuickOpen = true }
                .keyboardShortcut("p", modifiers: [.command])
            Button("Search Workspace…") { searchActions?.begin(.triptych) }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(searchActions == nil)
        }
        CommandMenu("Research") {
            Button("Attention…") { appState?.showAttentionQueues = true }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Button("Open Scholia…") {
                appState?.openScholia()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(appState?.currentNoteIdentityIsResolved != true)
            Button("Open Scholia in Dialogue…") {
                appState?.openScholia(section: .dialogue)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(appState?.currentNoteIdentityIsResolved != true)
            Divider()
            Button("Create Checkpoint…") { appState?.showCreateCheckpoint = true }
            Button("Restore from Checkpoint…") { appState?.showCheckpointBrowser = true }
            Button("Reveal Checkpoints in Finder") { appState?.revealCheckpointsInFinder() }
            Divider()
            SettingsLink { Label("Manage Triptychs…", systemImage: "folder.badge.gearshape") }
            Button("Reveal Current Vault in Finder") { appState?.revealVaultInFinder() }
                .disabled(appState?.vaultConfig == nil)
            Divider()
            Button(isCurrentDocumentInReadMode ? "Edit in Live Preview" : "Read") {
                appState?.requestDocumentMode(isCurrentDocumentInReadMode ? .livePreview : .read)
            }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(appState?.canEditCurrentNote != true)
            Button("Edit Properties…") { appState?.showFrontmatterEditor = true }
                .disabled(appState?.canEditCurrentNote != true)
        }
    }

    private var recentNotes: [RecentNoteDestination] {
        appState?.recentNoteDestinations ?? []
    }

    private func recentNoteCommandLabel(_ destination: RecentNoteDestination) -> String {
        let matchingTitles = recentNotes.count { candidate in
            candidate.title.localizedCaseInsensitiveCompare(destination.title) == .orderedSame
        }
        let role = destination.reference.vaultRole.displayName
        if matchingTitles > 1 {
            return "\(destination.title) — \(role) · \(destination.reference.relativePath)"
        }
        return "\(destination.title) — \(role)"
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

    private var isCurrentDocumentInReadMode: Bool {
        guard let appState, let path = appState.currentNote?.relativePath else { return true }
        return appState.presentationMode(for: path) == .read
    }
}

// MARK: - App State

enum LayoutMode: String, Equatable, Sendable {
    case wide
    case medium
    case compact

    init(windowWidth: CGFloat) {
        if windowWidth >= 1200 {
            self = .wide
        } else if windowWidth >= 980 {
            self = .medium
        } else {
            self = .compact
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    private struct EditorFlushRegistration {
        let token: UUID
        let relativePath: String
        let flush: @MainActor () async throws -> Void
    }

    private enum DocumentTransitionError: LocalizedError {
        case staleEditorRegistration(expected: String, registered: String)

        var errorDescription: String? {
            switch self {
            case .staleEditorRegistration(let expected, let registered):
                "Scholium kept the document open because the active editor changed from \(registered) to \(expected) before it could be saved."
            }
        }
    }

    private enum WindowNavigationError: LocalizedError {
        case noteUnavailable(String)
        case vaultUnavailable(String)
        case visitUnavailable

        var errorDescription: String? {
            switch self {
            case .noteUnavailable(let path):
                "The visited note '\(path)' is no longer available. Scholium kept the current document open."
            case .vaultUnavailable(let name):
                "The \(name) vault is not available in this Triptych. Scholium kept the current document open."
            case .visitUnavailable:
                "That navigation visit is no longer available. Scholium kept the current document open."
            }
        }
    }
    private(set) var windowSessionID = UUID()
    enum NoteLocationScope: String, CaseIterable, Identifiable {
        case workspace = "Workspace"
        case unclassified = "Unclassified"
        case setAside = "Set Aside"
        case trash = "Trash"

        var id: String { rawValue }
        var prefix: String? {
            switch self {
            case .workspace, .unclassified: nil
            case .setAside: "Set Aside/"
            case .trash: "Trash/"
            }
        }
    }

    enum NoteLifecycleRequest: Identifiable, Equatable {
        case create
        case duplicate(String)
        case move(String)
        case restore(String)
        case classify(String)

        var id: String {
            switch self {
            case .create: "create"
            case .duplicate(let path): "duplicate:\(path)"
            case .move(let path): "move:\(path)"
            case .restore(let path): "restore:\(path)"
            case .classify(let path): "classify:\(path)"
            }
        }
    }
    enum NoteSortOrder: String, CaseIterable, Identifiable {
        case modifiedNewest
        case modifiedOldest
        case titleAscending
        case titleDescending

        var id: String { rawValue }

        var title: String {
            switch self {
            case .modifiedNewest: "Recently Modified"
            case .modifiedOldest: "Least Recently Modified"
            case .titleAscending: "Title, A to Z"
            case .titleDescending: "Title, Z to A"
            }
        }

        var symbol: String {
            switch self {
            case .modifiedNewest: "clock.arrow.circlepath"
            case .modifiedOldest: "clock"
            case .titleAscending: "textformat.abc"
            case .titleDescending: "textformat.abc.dottedunderline"
            }
        }
    }

    enum ScholiaSection: String, CaseIterable, Identifiable {
        case comments
        case dialogue

        var id: String { rawValue }
    }

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
                case .success: .green
                case .information: .accentColor
                case .warning: .orange
                case .error: .red
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
    @Published var notes: [Note] = []
    @Published var noteLocationScope: NoteLocationScope = .workspace
    @Published var noteLifecycleRequest: NoteLifecycleRequest?
    @Published var openTabs: [String] = []
    @Published var activeTab: String?
    @Published var documentModes: [String: String] = [:]
    @Published var documentScrollPositions: [String: Double] = [:]
    @Published var inspectorModeRaw = "incoming"
    @Published var isReviewedFilter = false
    @Published var isUnqualifiedFilter = false
    @Published var selectedTag: String?
    @Published var selectedStatus: String?
    @Published var selectedAuthor: String?
    @Published var selectedYear: Int?
    @Published var selectedPropertyKey: String?
    @Published var selectedPropertyValue: String?
    @Published var noteSortOrder: NoteSortOrder = .modifiedNewest {
        didSet { UserDefaults.standard.set(noteSortOrder.rawValue, forKey: "noteSortOrder") }
    }
    @Published var sidebarVisible = true
    @Published var backlinksVisible = true
    @Published var noteHistoryVisible = false
    @Published var windowWidth: CGFloat = 1380
    @Published var isLoading = false
    @Published var showMarkdownImporter = false
    @Published var showQuickOpen = false
    @Published var showSearchSurface = false
    @Published var showFrontmatterEditor = false
    @Published var editingNotePath: String?
    @Published var vaultError: String?
    @Published var toastMessage: Toast?
    @Published var colorScheme: ColorSchemeChoice = .system {
        didSet {
            UserDefaults.standard.set(colorScheme.rawValue, forKey: "colorScheme")
        }
    }
    @Published var allTags: [String] = []
    @Published var advancedSearchHits: [SearchHit] = []
    @Published var advancedSearchState = SearchWorkspaceState()
    @Published var savedSearches: [SavedSearch] = []
    @Published var advancedSearchError: String?
    @Published var documentTextScale: Double = 1.0
    @Published var pendingSourceLine: Int?
    @Published var documentRevisions: [String: DocumentFingerprint] = [:]
    @Published var isSearchRunning = false
    @Published var lastSaveError: String?
    @Published var changedSinceReviewPaths: Set<String> = []
    @Published var requestPresentationMode: NotePresentationMode?
    @Published var editingBodyPath: String?
    @Published private(set) var contentDestination: WindowContentDestination = .document
    @Published var showQualityReview = false
    @Published var qualityReviewPath: String?
    @Published var showResearcherComments = false
    @Published var researcherCommentsPath: String?
    @Published var showScholia = false
    @Published var scholiaSection: ScholiaSection = .comments
    @Published var pendingCommentSelection: MarkdownReviewSelection?
    @Published var focusedResearcherCommentID: UUID?
    @Published var humanReviewRecords: [String: HumanReviewRecord] = [:]
    @Published var noteIdentityByPath: [String: UUID] = [:]
    @Published var identityAmbiguities: [NoteIdentityAmbiguity] = []
    @Published var pendingIdentityRebindings: [NoteIdentityPendingRebinding] = []
    @Published var identityMigrationFailures: [NoteIdentityMigrationFailure] = []
    @Published var selectedIdentityAmbiguity: NoteIdentityAmbiguity?
    @Published var isResolvingIdentity = false
    @Published var identityResolutionError: String?
    @Published var triptychSettings = TriptychSettings()
    @Published var showDialogue = false
    @Published var dialogueInitialNotes: Set<VaultQualifiedNoteID> = []
    @Published var showCheckpointBrowser = false
    @Published var showCreateCheckpoint = false
    @Published var checkpointListingError: String?
    @Published var pendingCritiquePath: String?
    @Published var workspaceAssignment: ThreeVaultWorkspaceAssignment?
    @Published var registeredTriptychs: [TriptychAssignment] = []
    @Published var showWorkspaceSetup = false
    @Published var workspaceRecoveryMessage: String?
    @Published var showAttentionQueues = false
    @Published var workspaceCatalog: WorkspaceCatalogSnapshot?
    @Published var isRefreshingWorkspaceCatalog = false
    @Published var refreshStatusText: String?
    @Published var workspaceCatalogError: String?
    @Published var registeredVaults: [RegisteredVault] = []
    @Published var transactionRecoveryRecords: [TriptychMutationRecoveryRecord] = []
    @Published var transactionRecoveryError: String?
    @Published var windowSessionPersistenceError: String?
    @Published var showTransactionRecovery = false

    // Source-located semantic graph for the current vault. Triptych-wide
    // resolution is published through `workspaceCatalog.graph`.
    @Published var relationshipGraph: GraphSnapshot?

    // MARK: Services
    // Active vault services are owned by WorkspaceStore's SharedVaultRuntime.
    // These computed adapters keep the existing AppState call sites stable
    // while making the ownership boundary explicit during migration.
    private var vaultService: VaultService {
        sharedVaultRuntime?.vaultService ?? workspaceStore.unconfiguredVaultService
    }
    let markdownEngine = MarkdownEngine()
    let frontmatterService = FrontmatterService()
    var humanReviewStore: HumanReviewStore
    var dialogueStore: DialogueStore
    var critiqueRegistry: CritiqueRegistry
    private var searchEngine: SearchEngine {
        sharedVaultRuntime?.searchEngine ?? workspaceStore.unconfiguredSearchEngine
    }
    let cssSnippetStore: CSSSnippetStore
    let zoteroBridge: ZoteroBridge
    private var repository: VaultRepository? {
        sharedVaultRuntime?.repository
    }
    private var sharedVaultRuntime: SharedVaultRuntime?
    private let applicationSupportURL: URL
    private let lastVaultURL: URL
    private let identityRegistry: VaultIdentityRegistry
    private let portableControlAccessRegistry: PortableControlAccessRegistry
    private let workspaceRegistry: WorkspaceRegistry
    private let savedSearchStore: SavedSearchStore
    private let windowSessionStore: WindowSessionSnapshotStore
    private let requestedTriptychID: UUID?
    private let createsTriptych: Bool
    private(set) var triptychManifest: TriptychManifest?
    private(set) var triptychControlStore: TriptychControlStore?
    private(set) var researchSkillStore: ResearchSkillStore?
    /// Published only after every shared Triptych service has been installed.
    /// Settings views use this readiness boundary instead of racing the earlier
    /// `workspaceAssignment` publication.
    @Published private(set) var activeTriptychServicesID: UUID?
    private(set) var checkpointStore: TriptychCheckpointStore?
    private(set) var transactionRecoveryStore: TriptychMutationRecoveryStore?
    private var identityRecoveryCoordinator: NoteIdentityRecoveryCoordinator?
    private var editorFlushRegistration: EditorFlushRegistration?
    private var watcherTask: Task<Void, Never>?
    private var didRunWatcherRestartSmoke = false
    private var indexBuildToken: UInt64 = 0
    private var attemptedVaultRestore = false
    private let workspaceStore: WorkspaceStore
    private var workspaceCancellables: Set<AnyCancellable> = []
    private var windowSessionSaveTask: Task<Void, Never>?
    private var workspaceCatalogRefreshTask: Task<Void, Never>?
    private var workspaceCatalogNeedsAnotherRefresh = false
    private var isRestoringWindowSession = false
    private var didRestoreWindowSession = false
    private var transitionGeneration: UInt64 = 0
    private var transitionTail: Task<Void, Never>?
    private var savedSearchMutationTail: Task<Void, Never>?

    init(
        workspaceStore: WorkspaceStore? = nil,
        requestedTriptychID: UUID? = nil,
        createsTriptych: Bool = false
    ) {
        let workspaceStore = workspaceStore ?? WorkspaceStore()
        self.workspaceStore = workspaceStore
        self.requestedTriptychID = requestedTriptychID
        self.createsTriptych = createsTriptych
        let appSupport = workspaceStore.applicationSupportURL
        applicationSupportURL = appSupport
        lastVaultURL = appSupport.appendingPathComponent("last-vault.txt")
        identityRegistry = workspaceStore.identityRegistry
        portableControlAccessRegistry = workspaceStore.portableControlAccessRegistry
        workspaceRegistry = workspaceStore.workspaceRegistry
        savedSearchStore = workspaceStore.savedSearchStore
        windowSessionStore = workspaceStore.windowSessionStore
        cssSnippetStore = workspaceStore.cssSnippetStore
        zoteroBridge = workspaceStore.zoteroBridge
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        humanReviewStore = HumanReviewStore(storageURL: appSupport.appendingPathComponent("bootstrap-human-reviews", isDirectory: true))
        dialogueStore = DialogueStore(storageURL: appSupport.appendingPathComponent("bootstrap-dialogue", isDirectory: true))
        critiqueRegistry = CritiqueRegistry(controlURL: appSupport.appendingPathComponent("bootstrap-control", isDirectory: true))
        if let saved = UserDefaults.standard.string(forKey: "colorScheme"),
           let choice = ColorSchemeChoice(rawValue: saved) {
            colorScheme = choice
        }
        if let saved = UserDefaults.standard.string(forKey: "noteSortOrder"),
           let order = NoteSortOrder(rawValue: saved) {
            noteSortOrder = order
        }
        UserDefaults.standard.removeObject(forKey: "libraryViewMode")
        workspaceStore.$latestCommit
            .compactMap { $0 }
            .filter { [windowSessionID] in $0.originSessionID != windowSessionID }
            .receive(on: RunLoop.main)
            .sink { [weak self] commit in self?.receiveWorkspaceCommit(commit) }
            .store(in: &workspaceCancellables)
        workspaceStore.$latestVaultChange
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] change in self?.receiveSharedVaultChange(change) }
            .store(in: &workspaceCancellables)
        workspaceStore.$latestTriptychRuntimeReload
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] reload in self?.receiveTriptychRuntimeReload(reload) }
            .store(in: &workspaceCancellables)
        Task { [weak self] in
            guard let self else { return }
            do {
                let searches = try await savedSearchStore.load()
                await MainActor.run { self.savedSearches = searches }
            } catch {
                await MainActor.run {
                    self.vaultError = error.localizedDescription
                }
            }
        }
        observeWindowSessionChanges()
    }

    // MARK: Computed Properties
    var currentNote: Note? {
        guard let tab = activeTab else { return nil }
        return notes.first { $0.relativePath == tab }
    }

    var layoutMode: LayoutMode { LayoutMode(windowWidth: windowWidth) }
    var usesCompactWindowLayout: Bool { layoutMode == .compact }
    var usesWideWindowLayout: Bool { layoutMode == .wide }

    var isShowingSearchWorkspace: Bool { contentDestination == .search }

    var canEditCurrentNote: Bool {
        guard let note = currentNote else { return false }
        let isCritique = currentVaultRole.allowsCritique
            && (note.relativePath == "Critiques" || note.relativePath.hasPrefix("Critiques/"))
        if noteLocationScope == .unclassified { return !isCritique }
        return noteLocationScope == .workspace
            && noteIdentityByPath[note.relativePath] != nil
            && !isCritique
    }

    var currentNoteIdentityIsResolved: Bool {
        guard let path = currentNote?.relativePath else { return false }
        return noteIdentityByPath[path] != nil
    }

    var canHumanReviewCurrentNote: Bool {
        guard contentDestination == .document,
              noteLocationScope == .workspace,
              currentVaultRole.allowsHumanReview,
              let path = currentNote?.relativePath else { return false }
        return noteIdentityByPath[path] != nil
    }

    var canCommentCurrentNote: Bool {
        guard contentDestination == .document,
              noteLocationScope == .workspace,
              let note = currentNote,
              noteIdentityByPath[note.relativePath] != nil else { return false }
        switch currentVaultRole {
        case .sourceCorpus, .topicKnowledge:
            return true
        case .dissertationControl, .draftProject:
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

    func requestIdentityResolution(for path: String) {
        guard let ambiguity = identityAmbiguity(for: path) else { return }
        identityResolutionError = nil
        selectedIdentityAmbiguity = ambiguity
    }

    func resolveSelectedIdentity(candidateID: UUID?) async {
        guard let ambiguity = selectedIdentityAmbiguity,
              let repository,
              let identityRecoveryCoordinator else { return }
        isResolvingIdentity = true
        identityResolutionError = nil
        defer { isResolvingIdentity = false }
        let canvas = NamedCanvasStore(vaultStorageURL: await repository.storageURL)
        do {
            _ = try await identityRecoveryCoordinator.resolve(
                ambiguity,
                candidateID: candidateID,
                repository: repository,
                canvas: canvas,
                migrateCritiquePaths: currentWorkspaceSlot == .output
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
        await refreshIdentityAndReviewState()
    }

    private func requireResolvedIdentity(for path: String) throws {
        guard noteLocationScope == .unclassified || noteIdentityByPath[path] != nil else {
            throw NoteIdentityRecoveryError.identityUnresolved(path)
        }
    }

    func registerEditorFlush(
        for relativePath: String,
        token: UUID,
        flush: @escaping @MainActor () async throws -> Void
    ) {
        editorFlushRegistration = EditorFlushRegistration(
            token: token,
            relativePath: relativePath,
            flush: flush
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
        workspaceStore.unregisterEditorFlush(token: token)
        guard editorFlushRegistration?.token == token else { return }
        editorFlushRegistration = nil
    }

    private func flushRegisteredEditorIfNeeded() async throws {
        guard let registration = editorFlushRegistration else { return }
        if let activeTab, activeTab != registration.relativePath {
            throw DocumentTransitionError.staleEditorRegistration(
                expected: activeTab,
                registered: registration.relativePath
            )
        }
        try await registration.flush()
    }

    func prepareForWindowClose() async throws {
        try await flushRegisteredEditorIfNeeded()
        persistWindowSessionNow()
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

    func requestContentDestination(_ destination: WindowContentDestination) {
        guard destination != contentDestination else { return }
        enqueueDocumentTransition { [weak self] in
            self?.contentDestination = destination
        }
    }

    /// Opens the single workspace Search surface with an explicit scope.
    /// Quick Open remains a separate Triptych-wide title/path/alias command.
    func beginSearch(mode: SearchPresentationScope) {
        advancedSearchState.scope = mode.canonical
        showSearchSurface = true
        Task { await refreshAdvancedSearch() }
    }

    func requestOpenNote(_ path: String, inNewTab: Bool = false) {
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            self.contentDestination = .document
            self.openNote(path, inNewTab: inNewTab)
        }
    }

    func requestOpenNote(
        _ reference: VaultNoteReference,
        inNewTab: Bool = false
    ) {
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            if self.currentRegisteredVault?.id != reference.vaultID {
                guard let vault = self.workspaceAssignment?.vaults.values.first(where: {
                    $0.id == reference.vaultID
                }) else {
                    throw WindowNavigationError.vaultUnavailable(reference.vaultName)
                }
                try await self.openRegisteredVault(vault)
            }
            guard self.notes.contains(where: { $0.relativePath == reference.relativePath }) else {
                throw WindowNavigationError.noteUnavailable(reference.relativePath)
            }
            self.contentDestination = .document
            self.openNote(reference.relativePath, inNewTab: inNewTab)
        }
    }

    func requestOpenNote(
        _ path: String,
        sourceLine: Int,
        mode: NotePresentationMode = .source,
        inNewTab: Bool = false
    ) {
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            self.pendingSourceLine = max(1, sourceLine)
            self.openNote(path, inNewTab: inNewTab)
            self.contentDestination = .document
            self.requestPresentationMode = mode
        }
    }

    func requestSelectTab(_ path: String) {
        guard path != activeTab else { return }
        enqueueDocumentTransition { [weak self] in
            guard let self, self.openTabs.contains(path) else { return }
            self.activeTab = path
            self.recordNavigationVisit(path)
            self.contentDestination = .document
        }
    }

    func requestSelectPreviousTab() {
        requestSelectAdjacentTab(offset: -1)
    }

    func requestSelectNextTab() {
        requestSelectAdjacentTab(offset: 1)
    }

    private func requestSelectAdjacentTab(offset: Int) {
        guard openTabs.count > 1,
              let activeTab,
              let currentIndex = openTabs.firstIndex(of: activeTab) else { return }
        let targetIndex = (currentIndex + offset + openTabs.count) % openTabs.count
        requestSelectTab(openTabs[targetIndex])
    }

    func requestCloseTab(_ path: String) {
        enqueueDocumentTransition { [weak self] in
            self?.closeTab(path)
        }
    }

    func requestNavigateBack() {
        guard navigationIndex > 0 else { return }
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            try await self.navigate(toHistoryIndex: self.navigationIndex - 1)
        }
    }

    func requestNavigateForward() {
        guard navigationIndex < navigationStack.count - 1 else { return }
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            try await self.navigate(toHistoryIndex: self.navigationIndex + 1)
        }
    }

    func clearRecentNotes() {
        recentNotesHistory.removeAll()
    }

    func requestWorkspaceVault(_ slot: WorkspaceVaultSlot) {
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            try await self.openWorkspaceVault(slot)
            if let activeTab = self.activeTab {
                self.recordNavigationVisit(activeTab)
            }
            self.contentDestination = .document
        }
    }

    func requestNoteLocationScope(_ scope: NoteLocationScope) {
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            await self.selectNoteLocationScope(scope)
            self.contentDestination = .document
        }
    }

    func requestDocumentMode(_ mode: NotePresentationMode) {
        guard mode == .read || canEditCurrentNote else {
            showToast("This note is read-only in Scholium.", kind: .information)
            return
        }
        guard contentDestination == .document else { return }
        if mode == .read {
            enqueueDocumentTransition { [weak self] in
                self?.requestPresentationMode = .read
            }
        } else {
            requestPresentationMode = mode
        }
    }

    func requestHumanReview() {
        guard canHumanReviewCurrentNote, let path = currentNote?.relativePath else { return }
        enqueueDocumentTransition { [weak self] in
            self?.reviewNote(at: path)
        }
    }

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
            self.researcherCommentsPath = path
            self.pendingCommentSelection = selection
            self.focusedResearcherCommentID = focusedCommentID
            self.showResearcherComments = true
        }
    }

    func openScholia(section: ScholiaSection = .comments) {
        guard contentDestination == .document, currentNote != nil else { return }
        scholiaSection = section
        showScholia = true
    }

    func requestOpenScholia(for path: String, section: ScholiaSection = .comments) {
        guard notes.contains(where: { $0.relativePath == path }) else { return }
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            self.openNote(path, inNewTab: false)
            self.contentDestination = .document
            self.scholiaSection = section
            self.showScholia = true
        }
    }

    private func receiveWorkspaceCommit(_ commit: WorkspaceCommit) {
        guard currentRegisteredVault?.id == commit.vaultID else { return }
        if editingBodyPath == commit.relativePath {
            refreshStatusText = "Conflict: note changed in another window"
            showToast("This note was saved in another Scholium window. Reload, Compare, or cancel this edit before saving.", kind: .warning)
            return
        }
        Task {
            guard let repository else { return }
            do {
                let document = try await repository.load(relativePath: commit.relativePath)
                guard document.fingerprint == commit.revision else {
                    throw WorkspaceCommitRefreshError.revisionChangedAgain
                }
                documentRevisions[commit.relativePath] = commit.revision
                _ = await replaceSavedDocument(document)
            } catch {
                refreshStatusText = "Shared note refresh failed"
                workspaceCatalogError = "Another Scholium window saved \(commit.relativePath), but this window could not reload the committed file. \(error.localizedDescription)"
            }
        }
    }

    private func receiveSharedVaultChange(_ change: WorkspaceVaultChange) {
        guard let assignment = workspaceAssignment,
              let slot = WorkspaceVaultSlot.allCases.first(where: {
                  assignment.vault(for: $0)?.id == change.vaultID
              }) else { return }
        switch change.derivedState {
        case .failed(_, let message):
            refreshStatusText = "\(slot.displayName) refresh failed"
            workspaceCatalogError = message
        case .stale:
            if currentRegisteredVault?.id != change.vaultID {
                refreshStatusText = "Refreshing \(slot.displayName)…"
            }
        case .idle, .refreshing:
            break
        case .current:
            if !workspaceStore.vaultRefreshStates.values.contains(where: {
                if case .failed = $0 { return true }
                return false
            }), (refreshStatusText == "\(slot.displayName) refresh failed"
                || refreshStatusText == "Refreshing \(slot.displayName)…") {
                refreshStatusText = nil
            }
        }
        if currentRegisteredVault?.id != change.vaultID {
            scheduleWorkspaceCatalogRefresh()
        }
    }

    private func receiveTriptychRuntimeReload(_ reload: TriptychRuntimeReload) {
        guard let assignment = workspaceAssignment,
              assignment.id == reload.triptychID else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.activateTriptychServices(assignment: assignment)
                try await self.refreshNoteLocationScope()
            } catch {
                self.refreshStatusText = "Triptych control refresh failed"
                self.workspaceCatalogError = error.localizedDescription
            }
        }
    }

    var hasDerivedRefreshFailure: Bool {
        workspaceStore.vaultRefreshStates.values.contains {
            if case .failed = $0 { return true }
            return false
        }
    }

    func retryDerivedRefresh() async {
        guard let assignment = workspaceAssignment else { return }
        refreshStatusText = "Retrying Triptych refresh…"
        do {
            _ = try await workspaceStore.activateTriptych(assignment)
            await refreshWorkspaceCatalog()
            if !hasDerivedRefreshFailure {
                refreshStatusText = nil
                workspaceCatalogError = nil
            }
        } catch {
            refreshStatusText = "Triptych refresh failed"
            workspaceCatalogError = error.localizedDescription
        }
    }

    var filteredNotes: [Note] {
        var result = notes
        if isReviewedFilter { result = result.filter { !$0.isReviewed } }
        if isUnqualifiedFilter {
            result = result.filter {
                humanReviewRecords[$0.relativePath]?.latestReview?.qualification == .unqualified
            }
        }
        if let tag = selectedTag { result = result.filter { $0.tags.contains(tag) } }
        if let status = selectedStatus { result = result.filter { $0.status == status } }
        if let author = selectedAuthor { result = result.filter { $0.authors.contains(author) } }
        if let year = selectedYear { result = result.filter { $0.year == year } }
        if let key = selectedPropertyKey, let value = selectedPropertyValue {
            result = result.filter { $0.property(at: key)?.filterValues.contains(value) == true }
        }
        return result.sorted(by: notesAreOrdered)
    }

    func notesAreOrdered(_ lhs: Note, _ rhs: Note) -> Bool {
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
        }
        return lhsTitle.localizedStandardCompare(rhsTitle) == .orderedAscending
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

    var availablePropertyKeys: [String] {
        return Set(notesInCurrentScope.flatMap { note in
            note.filterableProperties.compactMap { key, values in
                let values = values.filter { !$0.isEmpty && $0.count <= 80 }
                return values.isEmpty ? nil : key
            }
        }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func availablePropertyValues(for key: String) -> [String] {
        Set(notesInCurrentScope
            .flatMap { $0.filterableProperties[key] ?? [] }
            .filter { !$0.isEmpty && $0.count <= 80 })
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
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
    }

    private var notesInCurrentScope: [Note] {
        notes
    }

    /// Chronological Back/Forward visits across all three peer vaults.
    /// A relative path is never sufficient here because identical paths may
    /// legitimately exist in Analyses, Topics, and Works.
    @Published var navigationStack: [VaultQualifiedNoteID] = []
    @Published var navigationIndex: Int = -1
    @Published var recentNotesHistory = WindowRecentNotes()

    /// Menu-ready destinations remain routable from registered vault identity
    /// and relative paths even while the derived workspace catalog refreshes.
    fileprivate var recentNoteDestinations: [RecentNoteDestination] {
        guard let assignment = workspaceAssignment else { return [] }
        return recentNotesHistory.references.compactMap { noteID in
            guard let vault = assignment.vaults.values.first(where: {
                $0.id == noteID.vaultID
            }) else { return nil }
            let catalogNote = workspaceCatalog?.notes.first(where: {
                $0.reference.vaultID == noteID.vaultID
                    && $0.reference.relativePath == noteID.relativePath
            })
            let pathTitle = URL(fileURLWithPath: noteID.relativePath)
                .deletingPathExtension()
                .lastPathComponent
            let title: String
            if let catalogTitle = catalogNote?.title, !catalogTitle.isEmpty {
                title = catalogTitle
            } else {
                title = pathTitle.isEmpty ? noteID.relativePath : pathTitle
            }
            let reference = catalogNote?.reference ?? VaultNoteReference(
                vaultID: vault.id,
                vaultName: vault.name,
                vaultRole: vault.role,
                relativePath: noteID.relativePath
            )
            return RecentNoteDestination(id: noteID, reference: reference, title: title)
        }
    }

    /// Tabs, modes, and scroll positions remain independent for each vault in
    /// this window. The published path-only properties above are the current
    /// vault's projection used by existing views.
    private var vaultPresentations: [UUID: WindowVaultPresentationSnapshot] = [:]

    // MARK: Actions

    /// Updates the inspector preference. Presentation-binding callbacks and
    /// adaptive layout changes must opt out of animation because AppKit can
    /// invoke them while an NSWindow constraint pass is already active.
    func setResearchInspectorVisible(_ visible: Bool, animated: Bool = true) {
        guard visible != backlinksVisible || (visible && noteHistoryVisible) else { return }
        let update = {
            if visible { self.noteHistoryVisible = false }
            if visible != self.backlinksVisible {
                self.backlinksVisible = visible
            }
        }
        if !animated || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, update)
        } else {
            withAnimation(.easeInOut(duration: 0.22), update)
        }
    }

    /// Note History and the Research inspector share one trailing region.
    /// Keeping the switch here preserves per-window ownership and prevents
    /// two contextual panels from competing for the same document width.
    func setNoteHistoryVisible(_ visible: Bool, animated: Bool = true) {
        guard visible != noteHistoryVisible || (visible && backlinksVisible) else { return }
        let update = {
            if visible { self.backlinksVisible = false }
            if visible != self.noteHistoryVisible {
                self.noteHistoryVisible = visible
            }
        }
        if !animated || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, update)
        } else {
            withAnimation(.easeInOut(duration: 0.22), update)
        }
    }

    func presentationMode(for path: String) -> NotePresentationMode {
        documentModes[path].flatMap(NotePresentationMode.init(rawValue:)) ?? .read
    }

    func rememberPresentationMode(_ mode: NotePresentationMode, for path: String) {
        guard documentModes[path] != mode.rawValue else { return }
        documentModes[path] = mode.rawValue
    }

    func scrollPosition(for path: String) -> Double {
        min(1, max(0, documentScrollPositions[path] ?? 0))
    }

    func rememberScrollPosition(_ fraction: Double, for path: String) {
        guard fraction.isFinite else { return }
        let normalized = min(1, max(0, fraction))
        guard abs((documentScrollPositions[path] ?? 0) - normalized) > 0.002 else { return }
        documentScrollPositions[path] = normalized
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
            persistWindowSessionNow()
        }

        if ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_WORKSPACE_ROOT"] != nil,
           ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_SESSION_ID"] == nil {
            await restoreLastVaultIfNeeded()
            return
        }

        let stored: WindowSessionSnapshot?
        do {
            stored = try await windowSessionStore.load(id: id)
        } catch {
            showToast("The saved window layout could not be restored. Scholium opened a clean window instead.", kind: .warning)
            stored = nil
        }
        guard let stored else {
            await restoreLastVaultIfNeeded()
            return
        }

        restoreQualifiedSessionState(from: stored)

        await refreshRegisteredVaults()
        await refreshWorkspaceAssignment(
            preferredTriptychID: requestedTriptychID ?? stored.triptychID
        )
        guard let workspaceAssignment else {
            attemptedVaultRestore = true
            showWorkspaceSetup = true
            return
        }
        restrictSessionState(to: workspaceAssignment)

        do {
            if let vaultID = stored.vaultID,
               let vault = workspaceAssignment.vaults.values.first(where: { $0.id == vaultID }) {
                attemptedVaultRestore = true
                try await openRegisteredVault(vault)
            } else {
                await restoreLastVaultIfNeeded()
            }
        } catch {
            vaultError = error.localizedDescription
            showWorkspaceSetup = true
            return
        }

        inspectorModeRaw = stored.inspectorMode
        backlinksVisible = stored.inspectorVisible ?? true
        advancedSearchState = stored.searchState
        advancedSearchState.scope = advancedSearchState.scope.canonical
        documentTextScale = min(2.0, max(1.0, stored.documentTextScale ?? 1.0))
        // Canvas was removed from the stable UI. Decode its historical
        // snapshot fields, but restore those sessions to the document surface.
        contentDestination = stored.contentDestination == .search ? .search : .document
    }

    func persistWindowSessionNow() {
        guard didRestoreWindowSession, !isRestoringWindowSession else { return }
        windowSessionSaveTask?.cancel()
        let snapshot = currentWindowSessionSnapshot()
        windowSessionSaveTask = Task { [weak self, windowSessionStore] in
            do {
                try await windowSessionStore.save(snapshot)
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

    private func currentWindowSessionSnapshot() -> WindowSessionSnapshot {
        var presentations = vaultPresentations
        if let current = currentVaultPresentation() {
            presentations[current.vaultID] = current
        }
        let currentVaultID = currentRegisteredVault?.id
        let legacyHistory = navigationStack
            .filter { $0.vaultID == currentVaultID }
            .map(\.relativePath)
        let legacyNavigationIndex: Int
        if navigationStack.indices.contains(navigationIndex),
           navigationStack[navigationIndex].vaultID == currentVaultID {
            legacyNavigationIndex = navigationStack[...navigationIndex]
                .count(where: { $0.vaultID == currentVaultID }) - 1
        } else {
            legacyNavigationIndex = legacyHistory.isEmpty ? -1 : legacyHistory.count - 1
        }
        return WindowSessionSnapshot(
            id: windowSessionID,
            triptychID: workspaceAssignment?.id,
            vaultID: currentVaultID,
            openTabs: openTabs,
            activeTab: activeTab,
            navigationHistory: legacyHistory,
            navigationIndex: legacyNavigationIndex,
            documentModes: documentModes,
            scrollPositions: documentScrollPositions,
            inspectorMode: inspectorModeRaw,
            inspectorVisible: backlinksVisible,
            // Historical Canvas fields remain decode-only compatibility.
            selectedCanvasID: nil,
            showsCanvas: false,
            contentDestination: contentDestination == .search ? .search : .document,
            searchState: advancedSearchState,
            documentTextScale: documentTextScale,
            qualifiedNavigationHistory: navigationStack,
            qualifiedNavigationIndex: navigationIndex,
            recentNotes: recentNotesHistory,
            vaultPresentations: presentations.values.sorted {
                $0.vaultID.uuidString < $1.vaultID.uuidString
            }
        )
    }

    private func restoreQualifiedSessionState(from stored: WindowSessionSnapshot) {
        vaultPresentations = [:]
        for presentation in stored.vaultPresentations ?? [] {
            // A damaged duplicate entry must not create two owners. The last
            // complete value in the decoded file wins deterministically.
            vaultPresentations[presentation.vaultID] = presentation
        }
        if let vaultID = stored.vaultID,
           vaultPresentations[vaultID] == nil {
            vaultPresentations[vaultID] = WindowVaultPresentationSnapshot(
                vaultID: vaultID,
                openTabs: stored.openTabs,
                activeTab: stored.activeTab,
                documentModes: stored.documentModes,
                scrollPositions: stored.scrollPositions
            )
        }

        if let qualified = stored.qualifiedNavigationHistory {
            navigationStack = qualified
        } else if let vaultID = stored.vaultID {
            navigationStack = stored.navigationHistory.map {
                VaultQualifiedNoteID(vaultID: vaultID, relativePath: $0)
            }
        } else {
            navigationStack = []
        }
        let storedNavigationIndex = stored.qualifiedNavigationHistory == nil
            ? stored.navigationIndex
            : (stored.qualifiedNavigationIndex ?? stored.navigationIndex)
        navigationIndex = navigationStack.isEmpty
            ? -1
            : min(max(0, storedNavigationIndex), navigationStack.count - 1)
        if let storedRecentNotes = stored.recentNotes {
            recentNotesHistory = storedRecentNotes
        } else {
            var migrated = WindowRecentNotes()
            for reference in navigationStack {
                migrated.record(reference)
            }
            if navigationStack.indices.contains(navigationIndex) {
                migrated.record(navigationStack[navigationIndex])
            }
            recentNotesHistory = migrated
        }
    }

    private func restrictSessionState(to assignment: TriptychAssignment) {
        let allowedVaultIDs = Set(assignment.vaults.values.map(\.id))
        vaultPresentations = vaultPresentations.filter { allowedVaultIDs.contains($0.key) }
        let oldIndex = navigationIndex
        var history: [VaultQualifiedNoteID] = []
        var restoredIndex = -1
        for (index, reference) in navigationStack.enumerated()
        where allowedVaultIDs.contains(reference.vaultID) {
            history.append(reference)
            if index <= oldIndex { restoredIndex = history.count - 1 }
        }
        navigationStack = history
        navigationIndex = history.isEmpty
            ? -1
            : min(max(0, restoredIndex), history.count - 1)
        recentNotesHistory = recentNotesHistory.restricted(to: allowedVaultIDs)
    }

    private func currentVaultPresentation() -> WindowVaultPresentationSnapshot? {
        guard let vaultID = currentRegisteredVault?.id else { return nil }
        return WindowVaultPresentationSnapshot(
            vaultID: vaultID,
            openTabs: openTabs,
            activeTab: activeTab,
            documentModes: documentModes,
            scrollPositions: documentScrollPositions
        )
    }

    private func captureCurrentVaultPresentation() {
        guard let current = currentVaultPresentation() else { return }
        vaultPresentations[current.vaultID] = current
    }

    private func restoreVaultPresentation(vaultID: UUID, availablePaths: Set<String>) {
        let restored = (vaultPresentations[vaultID]
            ?? WindowVaultPresentationSnapshot(vaultID: vaultID))
            .normalized(availablePaths: availablePaths)
        vaultPresentations[vaultID] = restored
        openTabs = restored.openTabs
        activeTab = restored.activeTab
        documentModes = restored.documentModes
        documentScrollPositions = restored.scrollPositions
        normalizeNavigationHistory(vaultID: vaultID, availablePaths: availablePaths)
    }

    private func normalizeNavigationHistory(vaultID: UUID, availablePaths: Set<String>) {
        let oldIndex = navigationIndex
        var normalized: [VaultQualifiedNoteID] = []
        var normalizedIndex = -1
        for (index, reference) in navigationStack.enumerated() {
            if reference.vaultID == vaultID,
               !availablePaths.contains(reference.relativePath) {
                continue
            }
            normalized.append(reference)
            if index <= oldIndex { normalizedIndex = normalized.count - 1 }
        }
        navigationStack = normalized
        recentNotesHistory = recentNotesHistory.normalized(
            vaultID: vaultID,
            availablePaths: availablePaths
        )
        guard !normalized.isEmpty else {
            navigationIndex = -1
            return
        }
        navigationIndex = oldIndex < 0
            ? -1
            : min(max(0, normalizedIndex), normalized.count - 1)
    }

    private func observeWindowSessionChanges() {
        let changes: [AnyPublisher<Void, Never>] = [
            $workspaceAssignment.map { _ in () }.eraseToAnyPublisher(),
            $currentRegisteredVault.map { _ in () }.eraseToAnyPublisher(),
            $openTabs.map { _ in () }.eraseToAnyPublisher(),
            $activeTab.map { _ in () }.eraseToAnyPublisher(),
            $navigationStack.map { _ in () }.eraseToAnyPublisher(),
            $navigationIndex.map { _ in () }.eraseToAnyPublisher(),
            $recentNotesHistory.map { _ in () }.eraseToAnyPublisher(),
            $documentModes.map { _ in () }.eraseToAnyPublisher(),
            $documentScrollPositions.map { _ in () }.eraseToAnyPublisher(),
            $documentTextScale.map { _ in () }.eraseToAnyPublisher(),
            $backlinksVisible.map { _ in () }.eraseToAnyPublisher(),
            $inspectorModeRaw.map { _ in () }.eraseToAnyPublisher(),
            $advancedSearchState.map { _ in () }.eraseToAnyPublisher(),
            $contentDestination.map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(changes)
            .dropFirst(changes.count)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] in self?.persistWindowSessionNow() }
            .store(in: &workspaceCancellables)
    }

    func adjustDocumentTextScale(by delta: Double) {
        let adjusted = min(2.0, max(1.0, documentTextScale + delta))
        documentTextScale = (adjusted * 10).rounded() / 10
    }

    func resetDocumentTextScale() {
        documentTextScale = 1.0
    }

    func refreshWorkspaceAssignment(preferredTriptychID: UUID? = nil) async {
        let assignments = await workspaceRegistry.allTriptychs()
        registeredTriptychs = assignments
        let selectedID = preferredTriptychID
            ?? workspaceAssignment?.id
            ?? requestedTriptychID
        let stored: TriptychAssignment?
        if let selectedID {
            stored = assignments.first(where: { $0.id == selectedID })
            if stored == nil {
                workspaceAssignment = nil
                if !createsTriptych {
                    workspaceRecoveryMessage = "This Triptych is no longer registered on this Mac. Open an existing Triptych or choose its three folders again."
                }
                return
            }
        } else if createsTriptych {
            stored = nil
        } else {
            stored = await workspaceRegistry.threeVaultWorkspace()
        }
        guard let stored else {
            workspaceAssignment = nil
            return
        }

        var identities: [WorkspaceVaultSlot: VaultIdentity] = [:]
        for slot in WorkspaceVaultSlot.allCases {
            guard let vault = stored.vault(for: slot),
                  let identity = await identityRegistry.identity(forCanonicalPath: vault.canonicalPath) else {
                workspaceAssignment = stored
                await activateTriptychServicesReportingFailure(assignment: stored)
                return
            }
            identities[slot] = identity
        }

        let needsRepair = WorkspaceVaultSlot.allCases.contains { slot in
            stored.vault(for: slot)?.id != identities[slot]?.id
        }
        guard needsRepair,
              let papers = stored.vault(for: .paperAnalysis),
              let topics = stored.vault(for: .topicKnowledge),
              let output = stored.vault(for: .output),
              let paperIdentity = identities[.paperAnalysis],
              let topicIdentity = identities[.topicKnowledge],
              let outputIdentity = identities[.output] else {
            workspaceAssignment = stored
            await activateTriptychServicesReportingFailure(assignment: stored)
            return
        }

        do {
            let repaired = try await workspaceRegistry.configureTriptych(
                id: stored.id,
                name: stored.triptych.name,
                paperAnalysis: (URL(fileURLWithPath: papers.canonicalPath, isDirectory: true), paperIdentity.id),
                topicKnowledge: (URL(fileURLWithPath: topics.canonicalPath, isDirectory: true), topicIdentity.id),
                output: (URL(fileURLWithPath: output.canonicalPath, isDirectory: true), outputIdentity.id)
            )
            workspaceAssignment = repaired
            try await activateTriptychServices(assignment: repaired)
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
            if let recovery = workspaceAccessRecoveryMessage(for: error) {
                workspaceRecoveryMessage = recovery
                vaultError = nil
                return false
            }
            let message = "Scholium could not activate this Triptych's shared files, search, and research history. The registered locations remain unchanged. \(error.localizedDescription)"
            workspaceRecoveryMessage = message
            vaultError = message
            return false
        }
    }

    func configureThreeVaultWorkspace(
        paperAnalysisURL: URL,
        topicKnowledgeURL: URL,
        outputURL: URL,
        portableContainerURL: URL,
        triptychID: UUID? = nil,
        triptychName: String? = nil
    ) async throws {
        let portableScopeStarted = portableContainerURL.startAccessingSecurityScopedResource()
        defer {
            if portableScopeStarted {
                portableContainerURL.stopAccessingSecurityScopedResource()
            }
        }
        _ = try await portableControlAccessRegistry.register(
            containerURL: portableContainerURL,
            forWorksURL: outputURL
        )
        let selections: [(WorkspaceVaultSlot, URL)] = [
            (.paperAnalysis, paperAnalysisURL),
            (.topicKnowledge, topicKnowledgeURL),
            (.output, outputURL),
        ]
        var identities: [WorkspaceVaultSlot: VaultIdentity] = [:]
        for (slot, url) in selections {
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            identities[slot] = try await identityRegistry.identity(for: url)
        }
        guard let paperIdentity = identities[.paperAnalysis],
              let topicIdentity = identities[.topicKnowledge],
              let outputIdentity = identities[.output] else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }

        let portableManifestID = try? await TriptychControlStore(
            worksVaultURL: outputURL
        ).manifest().id
        let intendedTriptychID = triptychID ?? workspaceAssignment?.id ?? requestedTriptychID
        let normalizedTriptychName = triptychName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let currentID = intendedTriptychID,
           let portableManifestID,
           currentID != portableManifestID,
           await workspaceRegistry.triptych(id: currentID) != nil {
            _ = try await workspaceRegistry.reidentifyTriptych(
                id: currentID,
                as: portableManifestID
            )
        }
        let assignment = try await workspaceRegistry.configureTriptych(
            id: portableManifestID ?? intendedTriptychID,
            name: (normalizedTriptychName?.isEmpty == false ? normalizedTriptychName : nil)
                ?? registeredTriptychs.first(where: { $0.id == triptychID })?.triptych.name
                ?? workspaceAssignment?.triptych.name,
            paperAnalysis: (paperAnalysisURL, paperIdentity.id),
            topicKnowledge: (topicKnowledgeURL, topicIdentity.id),
            output: (outputURL, outputIdentity.id)
        )
        workspaceAssignment = assignment
        registeredVaults = await workspaceRegistry.allVaults()
        registeredTriptychs = await workspaceRegistry.allTriptychs()
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
        guard let access = await portableControlAccessRegistry.access(forWorksURL: worksURL) else {
            return nil
        }
        var stale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: access.bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), !stale else {
            return nil
        }
        let canonical = resolved.resolvingSymlinksInPath().standardizedFileURL
        guard canonical.path == access.canonicalContainerPath,
              resolved.startAccessingSecurityScopedResource() else {
            return nil
        }
        resolved.stopAccessingSecurityScopedResource()
        return canonical
    }

    var isCreatingNewTriptych: Bool {
        createsTriptych && workspaceAssignment == nil
    }

    private func activateTriptychServices(
        assignment: ThreeVaultWorkspaceAssignment
    ) async throws {
        activeTriptychServicesID = nil
        let access = try await workspaceStore.access(for: assignment)
        let runtime = access.triptychRuntime
        triptychControlStore = runtime.controlStore
        researchSkillStore = runtime.researchSkillStore
        triptychManifest = runtime.manifest
        triptychSettings = try await runtime.controlStore.settings()
        if triptychSettings.properties.isEmpty {
            triptychSettings.properties = TriptychSettings.defaultProperties
            try await runtime.controlStore.saveSettings(triptychSettings)
        }
        humanReviewStore = runtime.humanReviewStore
        dialogueStore = runtime.dialogueStore
        critiqueRegistry = runtime.critiqueRegistry
        checkpointStore = runtime.checkpointStore
        transactionRecoveryStore = runtime.transactionRecoveryStore
        identityRecoveryCoordinator = runtime.identityRecoveryCoordinator
        let humanReviewHealth = await runtime.humanReviewStore.healthError()
        let dialogueHealth = await runtime.dialogueStore.healthError()
        let critiqueHealth = await runtime.critiqueRegistry.healthError()
        let recordHealthErrors = [humanReviewHealth, dialogueHealth, critiqueHealth]
            .compactMap { $0 }
        if !recordHealthErrors.isEmpty {
            vaultError = ([
                "Some Scholium research history could not be loaded. The affected files remain unchanged and edits to those records are blocked.",
            ] + recordHealthErrors).joined(separator: "\n\n")
        }
        var effectiveAssignment = assignment
        if runtime.manifest.id != assignment.id {
            let repaired = try await workspaceRegistry.reidentifyTriptych(
                id: assignment.id,
                as: runtime.manifest.id
            )
            workspaceAssignment = repaired
            effectiveAssignment = repaired
            registeredTriptychs = await workspaceRegistry.allTriptychs()
        }
        let effectiveAccess = try await workspaceStore.access(for: effectiveAssignment)
        for repository in effectiveAccess.repositories.values {
            let recoveryCoordinator = NotePermanentDeletionCoordinator(
                triptychID: runtime.manifest.id,
                repository: repository,
                humanReviewStore: runtime.humanReviewStore,
                dialogueStore: runtime.dialogueStore,
                critiqueRegistry: runtime.critiqueRegistry,
                checkpointStore: runtime.checkpointStore,
                controlStore: runtime.controlStore,
                recoveryStore: runtime.transactionRecoveryStore
            )
            do {
                try await recoveryCoordinator.recoverInterruptedTransactions()
            } catch {
                workspaceRecoveryMessage = "An interrupted permanent deletion still requires inspection. \(error.localizedDescription)"
            }
        }
        do {
            transactionRecoveryRecords = try await runtime.transactionRecoveryStore.pending()
            transactionRecoveryError = nil
        } catch {
            transactionRecoveryRecords = []
            transactionRecoveryError = "Scholium could not read the durable recovery records. Their file remains unchanged. \(error.localizedDescription)"
        }
        activeTriptychServicesID = effectiveAssignment.id
    }

    func saveTriptychSettings(_ settings: TriptychSettings) async throws {
        guard let control = triptychControlStore else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        try await control.saveSettings(settings)
        triptychSettings = settings
    }

    var currentWorkspaceSlot: WorkspaceVaultSlot? {
        guard let current = currentRegisteredVault else { return nil }
        return WorkspaceVaultSlot.allCases.first { slot in
            guard let assigned = workspaceAssignment?.vault(for: slot) else { return false }
            return assigned.id == current.id || assigned.canonicalPath == current.canonicalPath
        }
    }

    var currentPropertiesConfiguration: VaultPropertiesConfiguration? {
        guard noteLocationScope == .workspace,
              let slot = currentWorkspaceSlot else { return nil }
        return triptychSettings.properties[slot] ?? TriptychSettings.defaultProperties[slot]
    }

    /// Compatibility adapter for older AppState workflows. WorkspaceStore
    /// now resolves bookmarks, retains security-scope leases, and returns the
    /// shared repositories and roots. This method intentionally performs no
    /// per-window access or release operation.
    private typealias TriptychAccess = WorkspaceAccess

    private func triptychAccess() async throws -> WorkspaceAccess {
        guard let assignment = workspaceAssignment else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await workspaceStore.access(for: assignment)
    }

    private func releaseTriptychAccess(_ access: WorkspaceAccess) {
        // WorkspaceStore owns the lifetime of the shared security-scope lease.
        _ = access
    }

    func createCheckpoint(name: String, kind: TriptychCheckpointKind = .manual) async throws -> TriptychCheckpoint {
        guard let checkpointStore,
              let triptychID = workspaceAssignment?.id else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        try await workspaceStore.flushEditors(in: triptychID)
        let access = try await triptychAccess()
        defer { releaseTriptychAccess(access) }
        return try await checkpointStore.create(name: name, kind: kind, roots: access.roots)
    }

    func checkpoints() async -> [TriptychCheckpoint] {
        guard let checkpointStore else {
            checkpointListingError = nil
            return []
        }
        let listing = await checkpointStore.listing()
        checkpointListingError = listing.unreadableEntries.isEmpty
            ? nil
            : "Some checkpoint folders could not be read and remain unchanged.\n\n"
                + listing.unreadableEntries.joined(separator: "\n")
        return listing.checkpoints
    }

    func noteCheckpoints(for path: String) async throws -> [TriptychCheckpoint] {
        guard let checkpointStore,
              let area = checkpointArea(for: currentVaultRole),
              let noteID = noteIdentityByPath[path] else { return [] }
        var matches: [TriptychCheckpoint] = []
        for checkpoint in await checkpoints() {
            let direct = TriptychCheckpointFileKey(area: area, relativePath: path)
            let hasIdentitySnapshot = checkpoint.files.contains {
                $0.key == TriptychCheckpointFileKey(area: .control, relativePath: "identities.json")
            }
            let key = hasIdentitySnapshot
                ? try await checkpointStore.noteFileKey(
                    checkpointID: checkpoint.id,
                    noteID: noteID,
                    area: area
                )
                : (checkpoint.files.contains(where: { $0.key == direct }) ? direct : nil)
            if key != nil {
                matches.append(checkpoint)
            }
        }
        return matches
    }

    func noteCheckpointContent(_ checkpointID: UUID, path: String) async throws -> String {
        guard let checkpointStore,
              let area = checkpointArea(for: currentVaultRole) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let key = try await noteCheckpointKey(checkpointID, currentPath: path, area: area)
        let data = try await checkpointStore.fileData(
            checkpointID: checkpointID,
            key: key
        )
        guard let source = String(data: data, encoding: .utf8) else {
            throw TriptychCheckpointError.invalidRelativePath(path)
        }
        return source
    }

    func restoreNote(_ path: String, from checkpointID: UUID) async throws {
        guard let checkpointStore,
              let area = checkpointArea(for: currentVaultRole) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        try await flushRegisteredEditorIfNeeded()
        let sourceKey = try await noteCheckpointKey(checkpointID, currentPath: path, area: area)
        let destinationKey = TriptychCheckpointFileKey(area: area, relativePath: path)
        let access = try await triptychAccess()
        defer { releaseTriptychAccess(access) }
        _ = try await checkpointStore.restoreNoteFile(
            checkpointID: checkpointID,
            sourceKey: sourceKey,
            destinationKey: destinationKey,
            roots: access.roots,
            repositories: access.repositories
        )
        do {
            if let workspaceAssignment {
                try await workspaceStore.reconcileTriptychAfterRestore(workspaceAssignment)
            }
            try await rescanVault()
        } catch {
            refreshStatusText = "Derived refresh failed"
            workspaceCatalogError = "The note was restored successfully, but Scholium could not refresh every derived view. \(error.localizedDescription)"
        }
    }

    private func noteCheckpointKey(
        _ checkpointID: UUID,
        currentPath: String,
        area: TriptychCheckpointArea
    ) async throws -> TriptychCheckpointFileKey {
        guard let checkpointStore else { throw WorkspaceRegistryError.incompleteWorkspace }
        let checkpoint = try await checkpointStore.checkpoint(id: checkpointID)
        let direct = TriptychCheckpointFileKey(area: area, relativePath: currentPath)
        let hasIdentitySnapshot = checkpoint.files.contains {
            $0.key == TriptychCheckpointFileKey(area: .control, relativePath: "identities.json")
        }
        if !hasIdentitySnapshot, checkpoint.files.contains(where: { $0.key == direct }) { return direct }
        guard hasIdentitySnapshot,
              let noteID = noteIdentityByPath[currentPath],
              let historical = try await checkpointStore.noteFileKey(
                checkpointID: checkpointID,
                noteID: noteID,
                area: area
              ) else {
            throw TriptychCheckpointError.invalidRelativePath(currentPath)
        }
        return historical
    }

    func dialogueHistory(for path: String) async -> [DialogueEntry] {
        guard let noteID = noteIdentityByPath[path] else { return [] }
        return await dialogueStore.entries(noteID: noteID)
    }

    @discardableResult
    func recordDialogueReply(
        entryID: UUID,
        agentName: String,
        text: String,
        noteID: UUID? = nil,
        commentID: UUID? = nil
    ) async throws -> DialogueEntry {
        try await dialogueStore.appendReply(
            DialogueReply(
                agentName: agentName,
                text: text,
                noteID: noteID,
                commentID: commentID
            ),
            to: entryID
        )
    }

    @discardableResult
    func recordDialogueFollowUpComment(
        entryID: UUID,
        text: String,
        noteID: UUID? = nil,
        commentID: UUID? = nil
    ) async throws -> DialogueEntry {
        try await dialogueStore.appendFollowUpComment(
            DialogueFollowUpComment(
                text: text,
                noteID: noteID,
                commentID: commentID
            ),
            to: entryID
        )
    }

    func critiqueAssociation(for path: String) async -> CritiqueAssociation? {
        guard currentVaultRole.allowsCritique,
              let noteID = noteIdentityByPath[path] else { return nil }
        return await critiqueRegistry.association(workNoteID: noteID)
    }

    func critiqueAssociation(forCritiquePath path: String) async -> CritiqueAssociation? {
        guard currentVaultRole.allowsCritique else { return nil }
        return await critiqueRegistry.association(critiqueRelativePath: path)
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
              let target = notes.first(where: { $0.relativePath == path }) else { return }
        let document = NoteDocument(relativePath: path, rawContent: target.rawContent)
        if let line = finding.resolvedTargetLine(in: document) {
            requestOpenNote(path, sourceLine: line)
        } else {
            requestOpenNote(path)
        }
    }

    private func checkpointArea(for role: VaultRole) -> TriptychCheckpointArea? {
        switch role {
        case .sourceCorpus: .analyses
        case .topicKnowledge: .topics
        case .dissertationControl, .draftProject: .works
        case .other: nil
        }
    }

    func checkpointComparison(_ checkpointID: UUID) async throws -> [TriptychCheckpointChange] {
        guard let checkpointStore else { throw WorkspaceRegistryError.incompleteWorkspace }
        let access = try await triptychAccess()
        defer { releaseTriptychAccess(access) }
        return try await checkpointStore.comparison(checkpointID: checkpointID, roots: access.roots)
    }

    func restoreCheckpoint(
        _ checkpointID: UUID,
        selection: TriptychCheckpointRestoreSelection
    ) async throws -> TriptychCheckpointRestoreResult {
        guard let checkpointStore else { throw WorkspaceRegistryError.incompleteWorkspace }
        try await flushRegisteredEditorIfNeeded()
        let access = try await triptychAccess()
        defer { releaseTriptychAccess(access) }
        let result = try await checkpointStore.restore(
            checkpointID: checkpointID,
            selection: selection,
            roots: access.roots,
            repositories: access.repositories
        )
        do {
            if let workspaceAssignment {
                if result.restoredFiles.contains(where: { $0.area == .control }) {
                    _ = try await workspaceStore.reloadTriptychRuntime(
                        assignment: workspaceAssignment,
                        worksVaultURL: access.roots.works
                    )
                    try await activateTriptychServices(assignment: workspaceAssignment)
                }
                try await workspaceStore.reconcileTriptychAfterRestore(workspaceAssignment)
            }
            try await rescanVault()
        } catch {
            refreshStatusText = "Triptych refresh failed after restore"
            workspaceCatalogError = "The checkpoint restore committed successfully, but Scholium could not reload every restored setting or derived view. \(error.localizedDescription)"
        }
        return result
    }

    func revealCheckpointsInFinder() {
        guard let url = checkpointStore?.storageURL else { return }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func importMarkdownFiles(_ urls: [URL]) async throws -> [URL] {
        guard let control = triptychControlStore else { throw WorkspaceRegistryError.incompleteWorkspace }
        var imported: [URL] = []
        for url in urls {
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            imported.append(try await control.importMarkdown(at: url))
        }
        return imported
    }

    func dialogueCandidates() async throws -> [DialogueNoteReference] {
        guard let assignment = workspaceAssignment,
              let identityRecoveryCoordinator else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let access = try await triptychAccess()
        defer { releaseTriptychAccess(access) }
        var result: [DialogueNoteReference] = []
        for slot in WorkspaceVaultSlot.allCases {
            guard let repository = access.repositories[slot],
                  let vault = assignment.vault(for: slot) else { continue }
            var documents: [NoteDocument] = []
            for path in try await repository.markdownRelativePaths() {
                documents.append(try await repository.load(relativePath: path))
            }
            let canvas = NamedCanvasStore(vaultStorageURL: await repository.storageURL)
            let recovery = try await identityRecoveryCoordinator.reconcile(
                vaultID: vault.id,
                documents: documents.map { ($0.relativePath, $0.fingerprint) },
                repository: repository,
                canvas: canvas,
                migrateCritiquePaths: slot == .output
            )
            for document in documents {
                guard let noteID = recovery.identities[document.relativePath]?.id else { continue }
                let title = document.parsedFrontmatter["title"]?.scalarString
                    ?? (document.relativePath as NSString).lastPathComponent
                        .replacingOccurrences(of: ".md", with: "")
                result.append(DialogueNoteReference(
                    noteID: noteID,
                    vaultID: vault.id,
                    vaultName: slot.displayName,
                    title: title,
                    relativePath: document.relativePath,
                    fingerprint: document.fingerprint,
                    kind: slot == .output
                        ? document.parsedFrontmatter["kind"]?.scalarString
                        : nil
                ))
            }
        }
        return result.sorted {
            if $0.vaultName != $1.vaultName { return $0.vaultName < $1.vaultName }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
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
              assignment.vault(for: .paperAnalysis)?.id == reference.vaultID,
              let identityRecoveryCoordinator else {
            throw ZoteroBridgeError.invalidAnalysisReference
        }

        try await flushRegisteredEditorIfNeeded()
        let access = try await triptychAccess()
        defer { releaseTriptychAccess(access) }
        guard let repository = access.repositories[.paperAnalysis] else {
            throw ZoteroBridgeError.invalidAnalysisReference
        }

        var documents: [NoteDocument] = []
        for path in try await repository.markdownRelativePaths() {
            documents.append(try await repository.load(relativePath: path))
        }
        let recovery = try await identityRecoveryCoordinator.reconcile(
            vaultID: reference.vaultID,
            documents: documents.map { ($0.relativePath, $0.fingerprint) },
            repository: repository,
            canvas: NamedCanvasStore(vaultStorageURL: await repository.storageURL),
            migrateCritiquePaths: false
        )
        guard recovery.identities[reference.relativePath] != nil,
              let document = documents.first(where: { $0.relativePath == reference.relativePath }) else {
            throw NoteIdentityRecoveryError.identityUnresolved(reference.relativePath)
        }

        _ = try await repository.save(
            relativePath: reference.relativePath,
            changeSet: .frontmatter(["zotero_item_key": .string(itemKey)]),
            expectedRevision: document.fingerprint
        )

        if currentRegisteredVault?.id == reference.vaultID {
            try await rescanVault()
        } else {
            scheduleWorkspaceCatalogRefresh()
        }
    }

    func comments(for noteID: UUID) async -> [ResearcherComment] {
        await humanReviewStore.record(noteID: noteID)?.comments ?? []
    }

    @discardableResult
    func addResearcherComment(
        to path: String,
        text: String,
        anchor: ResearcherCommentAnchor?
    ) async throws -> HumanReviewRecord {
        let context = try researcherCommentContext(for: path)
        if let anchor, anchor.fingerprint != context.fingerprint {
            throw ResearcherCommentWorkflowError.staleRevision
        }
        let record = try await humanReviewStore.addComment(
            noteID: context.noteID,
            vaultID: context.vaultID,
            relativePath: path,
            comment: ResearcherComment(text: text, anchor: anchor)
        )
        humanReviewRecords[path] = record
        return record
    }

    func updateResearcherComment(
        at path: String,
        commentID: UUID,
        text: String
    ) async throws {
        let context = try researcherCommentContext(for: path)
        try await humanReviewStore.updateCommentText(
            noteID: context.noteID,
            commentID: commentID,
            text: text
        )
        humanReviewRecords[path] = await humanReviewStore.record(noteID: context.noteID)
    }

    func setResearcherCommentResolved(
        at path: String,
        commentID: UUID,
        resolved: Bool
    ) async throws {
        let context = try researcherCommentContext(for: path)
        try await humanReviewStore.setCommentResolvedByResearcher(
            noteID: context.noteID,
            commentID: commentID,
            resolved: resolved
        )
        humanReviewRecords[path] = await humanReviewStore.record(noteID: context.noteID)
    }

    func deleteResearcherComment(at path: String, commentID: UUID) async throws {
        let context = try researcherCommentContext(for: path)
        try await humanReviewStore.removeComment(noteID: context.noteID, commentID: commentID)
        humanReviewRecords[path] = await humanReviewStore.record(noteID: context.noteID)
    }

    func reattachResearcherComment(
        at path: String,
        commentID: UUID,
        anchor: ResearcherCommentAnchor
    ) async throws {
        let context = try researcherCommentContext(for: path)
        guard anchor.fingerprint == context.fingerprint else {
            throw ResearcherCommentWorkflowError.staleRevision
        }
        try await humanReviewStore.reattachComment(
            noteID: context.noteID,
            commentID: commentID,
            to: anchor
        )
        humanReviewRecords[path] = await humanReviewStore.record(noteID: context.noteID)
    }

    @discardableResult
    func tryReattachingResearcherComments(at path: String) async throws -> HumanReviewRecord {
        let context = try researcherCommentContext(for: path)
        let document = try await diskDocument(for: path)
        guard document.fingerprint == context.fingerprint else {
            throw ResearcherCommentWorkflowError.staleRevision
        }
        try await humanReviewStore.reattachComments(noteID: context.noteID, to: document)
        guard let record = await humanReviewStore.record(noteID: context.noteID) else {
            throw HumanReviewError.recordNotFound(context.noteID)
        }
        humanReviewRecords[path] = record
        return record
    }

    private func researcherCommentContext(
        for path: String
    ) throws -> (noteID: UUID, vaultID: UUID, fingerprint: DocumentFingerprint) {
        guard noteLocationScope == .workspace,
              currentNote?.relativePath == path,
              canCommentCurrentNote,
              let noteID = noteIdentityByPath[path],
              let vaultID = currentRegisteredVault?.id,
              let fingerprint = documentRevisions[path] else {
            throw ResearcherCommentWorkflowError.unavailable
        }
        return (noteID, vaultID, fingerprint)
    }

    @discardableResult
    func createDialogue(
        instruction: String,
        selectedNotes: [DialogueNoteReference],
        includedCommentIDs: Set<UUID>,
        requestedDestination: String? = nil
    ) async throws -> DialogueEntry {
        guard let manifest = triptychManifest,
              let control = triptychControlStore else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let currentSettings = try await control.settings()
        let template = currentSettings.activePromptTemplate(for: .dialogue)
        guard template.validationIssues.isEmpty else {
            throw ResearchGuidanceError.invalidActiveTemplate(.dialogue, template.validationIssues)
        }
        let skillInstructions = try await researchSkillStore?.instructionAssembly() ?? ""
        try await flushRegisteredEditorIfNeeded()
        let checkpoint = try await createCheckpoint(name: "Before Agent Work", kind: .automatic)
        try await verifyDialogueSelectionIsCurrent(selectedNotes)
        var comments: [DialogueIncludedComment] = []
        for note in selectedNotes {
            comments.append(contentsOf: await self.comments(for: note.noteID)
                .filter { includedCommentIDs.contains($0.id) }
                .map { DialogueIncludedComment(note: note, comment: $0) })
        }
        let linkedNoteSummary = dialogueLinkedNoteSummary(for: selectedNotes)
        let prompt = dialoguePrompt(
            instruction: instruction,
            selectedNotes: selectedNotes,
            comments: comments,
            requestedDestination: requestedDestination,
            template: template.source,
            skillInstructions: skillInstructions
        )
        let entry = DialogueEntry(
            triptychID: manifest.id,
            instruction: instruction,
            selectedNotes: selectedNotes,
            includedComments: comments,
            generatedPrompt: "",
            checkpointID: checkpoint.id,
            requestedDestination: requestedDestination,
            linkedNoteSummary: linkedNoteSummary
        )
        _ = try await dialogueStore.save(entry)
        try copyTextToClipboard(
            prompt,
            recovery: "The Dialogue was saved in Note History. Reopen Dialogue to prepare new transport instructions."
        )
        return entry
    }

    private func verifyDialogueSelectionIsCurrent(
        _ selectedNotes: [DialogueNoteReference]
    ) async throws {
        guard let assignment = workspaceAssignment else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let access = try await triptychAccess()
        defer { releaseTriptychAccess(access) }
        for reference in selectedNotes {
            guard let slot = WorkspaceVaultSlot.allCases.first(where: {
                assignment.vault(for: $0)?.id == reference.vaultID
            }), let repository = access.repositories[slot] else {
                throw DialogueWorkflowError.contextChanged(reference.title)
            }
            let document: NoteDocument
            do {
                document = try await repository.load(relativePath: reference.relativePath)
            } catch {
                throw DialogueWorkflowError.contextChanged(reference.title)
            }
            guard document.fingerprint == reference.fingerprint else {
                throw DialogueWorkflowError.contextChanged(reference.title)
            }
        }
    }

    func copyTextToClipboard(_ text: String, recovery: String? = nil) throws {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else {
            throw ClipboardWorkflowError.copyFailed(recovery: recovery)
        }
    }

    func dialoguePrompt(
        instruction: String,
        selectedNotes: [DialogueNoteReference],
        comments: [DialogueIncludedComment],
        requestedDestination: String? = nil,
        template: String? = nil,
        skillInstructions: String = ""
    ) -> String {
        let prompt = DialoguePromptBuilder.build(DialoguePromptContext(
            instruction: instruction,
            selectedNotes: selectedNotes,
            comments: comments,
            triptychSummary: dialogueTriptychSummary(),
            linkedNoteSummary: dialogueLinkedNoteSummary(for: selectedNotes),
            requestedDestination: requestedDestination
        ), template: template ?? triptychSettings.dialoguePromptTemplate)
        return skillInstructions.isEmpty ? prompt : prompt + "\n\n" + skillInstructions
    }

    private func dialogueTriptychSummary() -> String? {
        guard let assignment = workspaceAssignment else { return nil }
        var lines = ["Triptych: \(assignment.triptych.name)"]
        for slot in WorkspaceVaultSlot.allCases {
            guard let vault = assignment.vault(for: slot) else { continue }
            lines.append("- \(slot.displayName) root: \(vault.canonicalPath)")
        }
        return lines.joined(separator: "\n")
    }

    private func dialogueLinkedNoteSummary(
        for selectedNotes: [DialogueNoteReference]
    ) -> String? {
        guard let catalog = workspaceCatalog,
              let graph = catalog.graph else { return nil }
        let notesByID = Dictionary(uniqueKeysWithValues: catalog.notes.map { note in
            (
                VaultQualifiedNoteID(
                    vaultID: note.reference.vaultID,
                    relativePath: note.reference.relativePath
                ),
                note
            )
        })
        var lines: [String] = []
        for note in selectedNotes {
            let source = VaultQualifiedNoteID(
                vaultID: note.vaultID,
                relativePath: note.relativePath
            )
            for edge in graph.outgoing[source, default: []] {
                let targetName: String
                if let destination = edge.destination?.note {
                    targetName = notesByID[destination]?.title ?? destination.relativePath
                } else {
                    targetName = edge.occurrence.target
                }
                let relation = switch edge.occurrence.vectorKind {
                case .supportsTarget: "supports"
                case .supportedByTarget: "is supported by"
                case .incompatible: "is incompatible with"
                case .neutral, .none: "connects neutrally to"
                }
                lines.append(
                    "- \(note.title) \(relation) \(targetName) "
                        + "(declared on line \(edge.occurrence.span.start.line))"
                )
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    @discardableResult
    func copyCritiqueInstructions(
        for path: String,
        scope: CritiqueRequestScope,
        lens: String,
        selectedRanges: String,
        additionalInstructions: String
    ) async throws -> CritiqueAssociation {
        guard currentVaultRole.allowsCritique,
              let repository,
              let note = notes.first(where: { $0.relativePath == path }),
              let workNoteID = noteIdentityByPath[path],
              let control = triptychControlStore else {
            throw HumanReviewWorkflowError.unavailableForOutput
        }
        let settings = try await control.settings()
        let template = settings.activePromptTemplate(for: .critique)
        guard template.validationIssues.isEmpty else {
            throw ResearchGuidanceError.invalidActiveTemplate(.critique, template.validationIssues)
        }
        let skillInstructions = try await researchSkillStore?.instructionAssembly() ?? ""
        try await flushRegisteredEditorIfNeeded()
        let targetDocument = try await repository.load(relativePath: path)
        let fingerprint = targetDocument.fingerprint
        let workTitle = targetDocument.parsedFrontmatter["title"]?.scalarString
            ?? note.title
            ?? note.displayName
        let requestedAt = Date()
        if let healthError = await critiqueRegistry.healthError() {
            throw CritiqueRequestWorkflowError.registryUnavailable(healthError)
        }
        let checkpoint = try await createCheckpoint(name: "Before Agent Work", kind: .automatic)
        let recheckedTarget = try await repository.load(relativePath: path)
        guard recheckedTarget.fingerprint == fingerprint else {
            throw CritiqueRequestWorkflowError.targetChanged
        }

        let critiquePath: String
        var previousCritiqueDocument: NoteDocument?
        var writtenCritiqueRevision: DocumentFingerprint?
        var createdCritiqueRevision: DocumentFingerprint?
        if let existing = await critiqueRegistry.association(workNoteID: workNoteID) {
            guard CritiquePlacement.isActiveCritiquePath(existing.critiqueRelativePath) else {
                throw CritiquePlacementError.invalidCritiquePath(existing.critiqueRelativePath)
            }
            critiquePath = existing.critiqueRelativePath
            try requireResolvedIdentity(for: critiquePath)
            let critiqueDocument = try await repository.load(relativePath: critiquePath)
            previousCritiqueDocument = critiqueDocument
            if critiqueDocument.rawFrontmatter == nil {
                let source = try CritiqueDocumentContract.sourceByAddingRequestMetadata(
                    to: critiqueDocument,
                    targetRelativePath: path,
                    targetFingerprint: fingerprint,
                    scope: scope,
                    requestedAt: requestedAt
                )
                let result = try await repository.save(
                    relativePath: critiquePath,
                    changeSet: .exactContent(source),
                    expectedRevision: critiqueDocument.fingerprint
                )
                writtenCritiqueRevision = result.document.fingerprint
            } else {
                let result = try await repository.save(
                    relativePath: critiquePath,
                    changeSet: .frontmatter(CritiqueDocumentContract.requestEdits(
                        targetRelativePath: path,
                        targetFingerprint: fingerprint,
                        scope: scope,
                        requestedAt: requestedAt
                    )),
                    expectedRevision: critiqueDocument.fingerprint
                )
                writtenCritiqueRevision = result.document.fingerprint
            }
        } else {
            let base = (path as NSString).lastPathComponent
                .replacingOccurrences(of: ".md", with: "")
            critiquePath = try await availableCritiquePath(base: base, repository: repository)
            let scaffold = CritiqueDocumentContract.scaffold(
                title: workTitle,
                targetRelativePath: path,
                targetFingerprint: fingerprint,
                scope: scope,
                requestedAt: requestedAt
            )
            let created = try await repository.create(relativePath: critiquePath, content: scaffold)
            createdCritiqueRevision = created.fingerprint
        }
        let association: CritiqueAssociation
        do {
            association = try await critiqueRegistry.recordRequest(
                workNoteID: workNoteID,
                workRelativePath: path,
                targetFingerprint: fingerprint,
                critiqueRelativePath: critiquePath,
                checkpointID: checkpoint.id,
                scope: scope,
                requestedAt: requestedAt
            )
        } catch {
            let requestError = error
            do {
                if let previousCritiqueDocument, let writtenCritiqueRevision {
                    _ = try await repository.save(
                        relativePath: critiquePath,
                        changeSet: .exactContent(previousCritiqueDocument.rawContent),
                        expectedRevision: writtenCritiqueRevision
                    )
                } else if let createdCritiqueRevision {
                    try await repository.removeCreatedFileForRollback(
                        relativePath: critiquePath,
                        createdRevision: createdCritiqueRevision
                    )
                }
            } catch {
                throw CritiqueRequestWorkflowError.rollbackFailed(
                    requestError: requestError.localizedDescription,
                    rollbackError: error.localizedDescription
                )
            }
            throw requestError
        }
        let basePrompt = CritiquePromptBuilder.build(CritiquePromptContext(
            template: template.source,
            scope: scope,
            lens: lens,
            selectedRanges: selectedRanges,
            additionalInstructions: additionalInstructions,
            workTitle: workTitle,
            workRelativePath: path,
            workFingerprint: fingerprint,
            critiqueRelativePath: association.critiqueRelativePath
        ))
        let generated = skillInstructions.isEmpty
            ? basePrompt
            : basePrompt + "\n\n" + skillInstructions
        try copyTextToClipboard(
            generated,
            recovery: "The Critique request was saved. Reopen Request Critique to copy its prompt again."
        )
        do {
            try await rescanVault()
        } catch {
            refreshStatusText = "Derived refresh failed"
            workspaceCatalogError = error.localizedDescription
        }
        return association
    }

    private func availableCritiquePath(base: String, repository: VaultRepository) async throws -> String {
        let existing = Set(try await repository.markdownRelativePaths(includeLifecycle: true))
        let first = "Critiques/\(base) Critique.md"
        if !existing.contains(first) { return first }
        var index = 2
        while existing.contains("Critiques/\(base) Critique \(index).md") { index += 1 }
        return "Critiques/\(base) Critique \(index).md"
    }

    func refreshRegisteredVaults() async {
        registeredVaults = await workspaceRegistry.allVaults()
        registeredTriptychs = await workspaceRegistry.allTriptychs()
    }

    func openWorkspaceVault(_ slot: WorkspaceVaultSlot) async throws {
        guard let vault = workspaceAssignment?.vault(for: slot) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        try await openRegisteredVault(vault)
    }

    func openRegisteredVault(_ vault: RegisteredVault) async throws {
        // WorkspaceStore resolves and retains any bookmark security scope while
        // activating the shared Triptych runtime. AppState only subscribes to
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

        guard let workspaceAssignment else {
            workspaceCatalog = nil
            return
        }
        let vaults = WorkspaceVaultSlot.allCases.compactMap { workspaceAssignment.vault(for: $0) }
        var reviewStates: [String: WorkspaceReviewState] = [:]
        for record in await humanReviewStore.allRecords() {
            let latest = record.latestReview
            reviewStates["\(record.vaultID.uuidString):\(record.relativePath)"] = WorkspaceReviewState(
                qualification: latest?.qualification.rawValue,
                reviewedFingerprint: latest?.fingerprint,
                changedSinceReview: false
            )
        }
        do {
            let runtimes = try await workspaceStore.activateTriptych(workspaceAssignment)
            let workspaceGraph = try await workspaceStore.triptychGraph(for: workspaceAssignment)
            var documentsByVault: [UUID: [NoteDocument]] = [:]
            var identityAmbiguitiesByVault: [UUID: [NoteIdentityAmbiguity]] = [:]
            var catalogReviewStates = reviewStates
            for slot in WorkspaceVaultSlot.allCases {
                guard let vault = workspaceAssignment.vault(for: slot),
                      let runtime = runtimes[slot] else {
                    throw WorkspaceRegistryError.incompleteWorkspace
                }
                let documents = await runtime.graphDocuments()
                documentsByVault[vault.id] = documents
                if let identityRecoveryCoordinator {
                    let repository = runtime.repository
                    let canvas = NamedCanvasStore(vaultStorageURL: await repository.storageURL)
                    let recovery = try await identityRecoveryCoordinator.reconcile(
                        vaultID: vault.id,
                        documents: documents.map { ($0.relativePath, $0.fingerprint) },
                        repository: repository,
                        canvas: canvas,
                        migrateCritiquePaths: slot == .output
                    )
                    identityAmbiguitiesByVault[vault.id] = recovery.ambiguities
                }
                for document in documents {
                    let key = "\(vault.id.uuidString):\(document.relativePath)"
                    if let state = catalogReviewStates[key], let reviewed = state.reviewedFingerprint {
                        catalogReviewStates[key] = WorkspaceReviewState(
                            qualification: state.qualification,
                            reviewedFingerprint: reviewed,
                            changedSinceReview: reviewed != document.fingerprint
                        )
                    }
                }
            }
            workspaceCatalog = await Task.detached(priority: .utility) {
                return WorkspaceCatalogBuilder.build(
                    vaults: vaults,
                    documents: documentsByVault,
                    reviewStates: catalogReviewStates,
                    graph: workspaceGraph,
                    identityAmbiguitiesByVault: identityAmbiguitiesByVault
                )
            }.value
        } catch {
            workspaceCatalogError = error.localizedDescription
        }
    }

    private func loadVault(_ registered: RegisteredVault) async throws {
        isLoading = true
        vaultError = nil
        do {
            guard let assignment = workspaceAssignment,
                  let slot = WorkspaceVaultSlot.allCases.first(where: {
                      assignment.vault(for: $0)?.id == registered.id
                  }) else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            let access = try await workspaceStore.access(for: assignment)
            guard let runtime = access.runtimes[slot] else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            // Stage the complete target runtime and inventory before replacing
            // any visible window state. A failed vault open must leave the
            // current Triptych document and editor intact.
            let result = try await runtime.openVault(at: runtime.rootURL, role: registered.role)
            let targetRepository = runtime.repository

            watcherTask?.cancel()
            captureCurrentVaultPresentation()
            resetWindowSession()

            currentRegisteredVault = registered
            currentVaultRole = registered.role
            sharedVaultRuntime = runtime
            vaultConfig = result.config
            notes = result.notes
            restoreVaultPresentation(
                vaultID: registered.id,
                availablePaths: Set(result.notes.map(\.relativePath))
            )
            refreshDocumentRevisions()
            await refreshIdentityAndReviewState()
            startWatching()
            isLoading = false
            try? registered.id.uuidString.write(to: lastVaultURL, atomically: true, encoding: .utf8)
            refreshStatusText = nil
            await buildIndexes()
            let historyHealth = await targetRepository.versionHistoryHealthError()
            let humanReviewHealth = await humanReviewStore.healthError()
            let dialogueHealth = await dialogueStore.healthError()
            let critiqueHealth = await critiqueRegistry.healthError()
            let healthErrors = [historyHealth, humanReviewHealth, dialogueHealth, critiqueHealth]
                .compactMap { $0 }
            if !healthErrors.isEmpty {
                vaultError = healthErrors.joined(separator: "\n\n")
            }
        } catch {
            isLoading = false
            refreshStatusText = nil
            vaultError = error.localizedDescription
            throw error
        }
    }

    func restoreLastVaultIfNeeded() async {
        guard !attemptedVaultRestore, vaultConfig == nil else { return }
        attemptedVaultRestore = true
        if let fixtureRoot = ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_WORKSPACE_ROOT"] {
            let root = URL(fileURLWithPath: fixtureRoot, isDirectory: true)
            do {
                try await configureThreeVaultWorkspace(
                    paperAnalysisURL: root.appendingPathComponent("01-analyses", isDirectory: true),
                    topicKnowledgeURL: root.appendingPathComponent("02-topics", isDirectory: true),
                    outputURL: root.appendingPathComponent("03-works", isDirectory: true),
                    portableContainerURL: root
                )
#if DEBUG
                if let requestedSlot = ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_OPEN_SLOT"],
                   let slot = WorkspaceVaultSlot.allCases.first(where: {
                       switch $0 {
                       case .paperAnalysis: requestedSlot == "paper_analysis"
                       case .topicKnowledge: requestedSlot == "topic_knowledge"
                       case .output: requestedSlot == "output"
                       }
                   }) {
                    try await openWorkspaceVault(slot)
                }
#endif
                openRequestedTestNoteIfNeeded()
            } catch {
                vaultError = error.localizedDescription
            }
            return
        }
        await refreshRegisteredVaults()
        await refreshWorkspaceAssignment()
        guard let workspaceAssignment else {
            showWorkspaceSetup = true
            return
        }

        var slotToOpen: WorkspaceVaultSlot = .paperAnalysis
        if let rawID = try? String(contentsOf: lastVaultURL, encoding: .utf8),
           let id = UUID(uuidString: rawID.trimmingCharacters(in: .whitespacesAndNewlines)) {
            if let directSlot = WorkspaceVaultSlot.allCases.first(where: {
                workspaceAssignment.vault(for: $0)?.id == id
            }) {
                slotToOpen = directSlot
            } else if let identity = await identityRegistry.identity(id: id),
                      let pathSlot = WorkspaceVaultSlot.allCases.first(where: {
                          workspaceAssignment.vault(for: $0)?.canonicalPath == identity.canonicalPath
                      }) {
                slotToOpen = pathSlot
            }
        }

        do {
            try await openWorkspaceVault(slotToOpen)
            openRequestedTestNoteIfNeeded()
        } catch {
            if let recovery = workspaceAccessRecoveryMessage(for: error) {
                workspaceRecoveryMessage = recovery
                vaultError = nil
            } else {
                vaultError = error.localizedDescription
            }
            showWorkspaceSetup = true
        }
    }

    private func workspaceAccessRecoveryMessage(for error: Error) -> String? {
        guard let workspaceError = error as? WorkspaceRegistryError else { return nil }
        switch workspaceError {
        case .vaultAccessUnavailable(let path):
            return "Scholium needs renewed access to '\(path)'. Choose that folder again, then use these vaults."
        case .portableControlAccessUnavailable(let path):
            return "Scholium needs access to '\(path)' so it can use the portable .scholium folder beside Works. Authorize that folder, then save the Triptych."
        default:
            return nil
        }
    }

    private func openRequestedTestNoteIfNeeded() {
        guard let requested = ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_OPEN_NOTE"] else { return }
        let path = requested == "first"
            ? notes.sorted(by: notesAreOrdered).first?.relativePath
            : requested
        if let path { openNote(path) }
    }

    func buildIndexes(
        incrementalPaths: Set<String>? = nil,
        deletedPaths: Set<String> = []
    ) async {
        // `WorkspaceStore` publishes the authoritative per-vault index and
        // Triptych graph. Keep this method as a window projection refresh for
        // existing callers; it must not create a second graph or index.
        _ = incrementalPaths
        _ = deletedPaths
        indexBuildToken &+= 1
        let buildToken = indexBuildToken
        let startingVaultID = currentRegisteredVault?.id
        // Human Review, qualification, and comments share one atomic store.
        await refreshIdentityAndReviewState()
        let changed = changedSinceReviewPaths
        guard buildToken == indexBuildToken, currentRegisteredVault?.id == startingVaultID else { return }
        changedSinceReviewPaths = changed

        relationshipGraph = await sharedVaultRuntime?.currentGraph()
        guard buildToken == indexBuildToken, currentRegisteredVault?.id == startingVaultID else { return }
        for index in notes.indices {
            guard let vaultID = startingVaultID else {
                notes[index].linkCount = 0
                notes[index].backlinkCount = 0
                continue
            }
            let id = VaultQualifiedNoteID(vaultID: vaultID, relativePath: notes[index].relativePath)
            notes[index].linkCount = relationshipGraph?.outgoing[id]?.count ?? 0
            notes[index].backlinkCount = relationshipGraph?.incoming[id]?.count ?? 0
        }

        // Update tags
        let tags = await frontmatterService.allTags(notes: notes).map(\.tag)
        guard buildToken == indexBuildToken, currentRegisteredVault?.id == startingVaultID else { return }
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
            if noteLocationScope == .workspace {
                captureCurrentVaultPresentation()
            }
            noteLocationScope = scope
            openTabs = []
            activeTab = nil
            documentModes = [:]
            documentScrollPositions = [:]
            notes = loaded.sorted(by: notesAreOrdered)
            if scope == .workspace, let vaultID = currentRegisteredVault?.id {
                restoreVaultPresentation(
                    vaultID: vaultID,
                    availablePaths: Set(notes.map(\.relativePath))
                )
            }
            refreshDocumentRevisions()
            await refreshIdentityAndReviewState()
            await buildIndexes()
        } catch {
            showToast("Could not open \(scope.rawValue): \(error.localizedDescription)", kind: .error)
        }
    }

    func refreshNoteLocationScope() async throws {
        notes = try await loadNotes(for: noteLocationScope).sorted(by: notesAreOrdered)
        refreshDocumentRevisions()
        await refreshIdentityAndReviewState()
        await buildIndexes()
    }

    private func loadNotes(for scope: NoteLocationScope) async throws -> [Note] {
        if scope == .workspace {
            return try await vaultService.rescan()
        } else if scope == .unclassified {
            guard let control = triptychControlStore else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            let documents = try await control.unclassifiedDocuments()
            var loaded: [Note] = []
            for document in documents {
                let parsed = try await markdownEngine.parse(document.rawContent)
                loaded.append(Note(
                    relativePath: document.relativePath,
                    frontmatter: parsed.frontmatter,
                    body: parsed.body,
                    rawContent: document.rawContent,
                    vaultRole: .other,
                    fileModifiedAt: Date()
                ))
            }
            return loaded
        } else {
            guard let repository, let prefix = scope.prefix else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            var loaded: [Note] = []
            let paths = try await repository.markdownRelativePaths(includeLifecycle: true)
                .filter { $0.hasPrefix(prefix) }
            for path in paths {
                let document = try await repository.load(relativePath: path)
                let parsed = try await markdownEngine.parse(document.rawContent)
                let info = await vaultService.fileInfo(at: path)
                loaded.append(Note(
                    relativePath: path,
                    frontmatter: parsed.frontmatter,
                    body: parsed.body,
                    rawContent: document.rawContent,
                    vaultRole: currentVaultRole,
                    fileModifiedAt: info?.modified ?? Date()
                ))
            }
            return loaded
        }
    }

    @discardableResult
    func createNote(relativePath requestedPath: String, title: String) async throws -> NoteDocument {
        try await flushRegisteredEditorIfNeeded()
        guard noteLocationScope == .workspace, let repository else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let path = Self.markdownPath(requestedPath)
        if currentVaultRole.allowsCritique,
           CritiquePlacement.isManagedCritiquePath(path) {
            throw CritiquePlacementError.directCreationRequiresRequestCritique
        }
        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = heading.isEmpty ? "" : "# \(heading)\n"
        let document = try await repository.create(relativePath: path, content: content)
        try await refreshNoteLocationScope()
        openNote(document.relativePath)
        return document
    }

    @discardableResult
    func duplicateNote(_ sourcePath: String, to requestedPath: String) async throws -> NoteDocument {
        try await flushRegisteredEditorIfNeeded()
        try requireResolvedIdentity(for: sourcePath)
        guard noteLocationScope == .workspace,
              let repository,
              let expected = documentRevisions[sourcePath] else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let destination = Self.markdownPath(requestedPath)
        if currentVaultRole.allowsCritique,
           CritiquePlacement.isManagedCritiquePath(sourcePath) {
            throw CritiquePlacementError.duplicateNotSupported
        }
        if currentVaultRole.allowsCritique,
           CritiquePlacement.isManagedCritiquePath(destination) {
            throw CritiquePlacementError.directCreationRequiresRequestCritique
        }
        let document = try await repository.duplicate(
            relativePath: sourcePath,
            to: destination,
            expectedRevision: expected
        )
        if let control = triptychControlStore,
           let sourceID = noteIdentityByPath[sourcePath] {
            let identity = try await control.duplicateIdentity(
                from: sourceID,
                to: destination,
                fingerprint: document.fingerprint
            )
            noteIdentityByPath[destination] = identity.id
        }
        try await refreshNoteLocationScope()
        openNote(destination)
        return document
    }

    func moveNote(_ sourcePath: String, to requestedPath: String) async throws {
        try await flushRegisteredEditorIfNeeded()
        try requireResolvedIdentity(for: sourcePath)
        guard let repository,
              let recoveryStore = transactionRecoveryStore,
              let triptychID = triptychManifest?.id ?? workspaceAssignment?.id,
              let vaultID = currentRegisteredVault?.id,
              let expected = documentRevisions[sourcePath] else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let destination = Self.markdownPath(requestedPath)
        if currentVaultRole.allowsCritique {
            try CritiquePlacement.validateOrdinaryMove(from: sourcePath, to: destination)
        }
        let sourceID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: sourcePath)
        let destinationID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: destination)
        let repositories: [UUID: VaultRepository]
        let plan: IncomingLinkRewritePlan
        var accessToRelease: TriptychAccess?
        if noteLocationScope == .workspace {
            let access = try await triptychAccess()
            accessToRelease = access
            repositories = Dictionary(uniqueKeysWithValues: access.repositories.compactMap { slot, repository in
                workspaceAssignment?.vault(for: slot).map { ($0.id, repository) }
            })
            plan = try await workspaceMovePlan(
                repositories: repositories,
                moving: sourceID,
                to: destinationID
            )
        } else {
            repositories = [vaultID: repository]
            plan = IncomingLinkRewritePlan(
                movedNote: sourceID,
                destination: destinationID,
                graphGeneration: relationshipGraph?.generation ?? 0,
                rewrites: []
            )
        }
        defer {
            if let accessToRelease { releaseTriptychAccess(accessToRelease) }
        }

        let coordinator = TriptychMoveCoordinator(
            triptychID: triptychID,
            repositories: repositories,
            recoveryStore: recoveryStore
        )
        let commit: TriptychMoveCommit
        do {
            commit = try await coordinator.move(plan, expectedRevision: expected)
        } catch {
            await refreshTransactionRecoveryRecords()
            throw error
        }
        try await migrateAppOwnedState(
            sourcePath: sourcePath,
            destinationPath: destination,
            fingerprint: commit.committedRevision
        )
        try await refreshNoteLocationScope()
        if noteLocationScope == .workspace { openNote(destination) }
        scheduleWorkspaceCatalogRefresh()
    }

    func setAsideNote(_ path: String) async throws {
        try await flushRegisteredEditorIfNeeded()
        try requireResolvedIdentity(for: path)
        let destination = path.hasPrefix("Set Aside/") ? path : "Set Aside/" + path
        let commit = try await coordinatedLifecycleMove(from: path, to: destination)
        try await migrateAppOwnedState(
            sourcePath: path,
            destinationPath: destination,
            fingerprint: commit.committedRevision
        )
        try await refreshNoteLocationScope()
    }

    func moveNoteToTrash(_ path: String) async throws {
        try await flushRegisteredEditorIfNeeded()
        try requireResolvedIdentity(for: path)
        let destination = path.hasPrefix("Set Aside/")
            ? "Trash/" + String(path.dropFirst("Set Aside/".count))
            : (path.hasPrefix("Trash/") ? path : "Trash/" + path)
        let commit = try await coordinatedLifecycleMove(from: path, to: destination)
        try await migrateAppOwnedState(
            sourcePath: path,
            destinationPath: destination,
            fingerprint: commit.committedRevision
        )
        try await refreshNoteLocationScope()
    }

    private func coordinatedLifecycleMove(
        from sourcePath: String,
        to destinationPath: String
    ) async throws -> TriptychMoveCommit {
        guard sourcePath != destinationPath,
              let repository,
              let recoveryStore = transactionRecoveryStore,
              let triptychID = triptychManifest?.id ?? workspaceAssignment?.id,
              let vaultID = currentRegisteredVault?.id,
              let expected = documentRevisions[sourcePath] else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let source = VaultQualifiedNoteID(vaultID: vaultID, relativePath: sourcePath)
        let destination = VaultQualifiedNoteID(vaultID: vaultID, relativePath: destinationPath)
        let coordinator = TriptychMoveCoordinator(
            triptychID: triptychID,
            repositories: [vaultID: repository],
            recoveryStore: recoveryStore
        )
        do {
            return try await coordinator.move(
                IncomingLinkRewritePlan(
                    movedNote: source,
                    destination: destination,
                    graphGeneration: relationshipGraph?.generation ?? 0,
                    rewrites: []
                ),
                expectedRevision: expected
            )
        } catch {
            await refreshTransactionRecoveryRecords()
            throw error
        }
    }

    func deleteNotePermanently(_ path: String) async throws {
        try await flushRegisteredEditorIfNeeded()
        try requireResolvedIdentity(for: path)
        guard noteLocationScope == .trash,
              let repository,
              let expected = documentRevisions[path],
              let noteID = noteIdentityByPath[path],
              let vaultID = currentRegisteredVault?.id,
              let slot = currentWorkspaceSlot,
              let checkpointStore,
              let control = triptychControlStore,
              let recoveryStore = transactionRecoveryStore,
              let triptychID = triptychManifest?.id ?? workspaceAssignment?.id else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }

        let coordinator = NotePermanentDeletionCoordinator(
            triptychID: triptychID,
            repository: repository,
            humanReviewStore: humanReviewStore,
            dialogueStore: dialogueStore,
            critiqueRegistry: critiqueRegistry,
            checkpointStore: checkpointStore,
            controlStore: control,
            recoveryStore: recoveryStore
        )
        let commit: PermanentDeletionCommit
        do {
            commit = try await coordinator.delete(
                noteID: noteID,
                vaultID: vaultID,
                relativePath: path,
                expectedRevision: expected,
                checkpointArea: Self.checkpointArea(for: slot)
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
        openTabs.removeAll { deletedPaths.contains($0) }
        if let activeTab, deletedPaths.contains(activeTab) { self.activeTab = openTabs.first }
        navigationStack.removeAll {
            $0.vaultID == vaultID && deletedPaths.contains($0.relativePath)
        }
        recentNotesHistory = recentNotesHistory.removing(
            vaultID: vaultID,
            paths: deletedPaths
        )
        navigationIndex = min(navigationIndex, navigationStack.count - 1)
        try await refreshNoteLocationScope()
    }

    private static func checkpointArea(for slot: WorkspaceVaultSlot) -> TriptychCheckpointArea {
        switch slot {
        case .paperAnalysis: .analyses
        case .topicKnowledge: .topics
        case .output: .works
        }
    }

    func classifyUnclassified(
        _ path: String,
        into slot: WorkspaceVaultSlot,
        destination requestedPath: String
    ) async throws {
        try await flushRegisteredEditorIfNeeded()
        guard noteLocationScope == .unclassified,
              let control = triptychControlStore,
              let recoveryStore = transactionRecoveryStore,
              let triptychID = triptychManifest?.id ?? workspaceAssignment?.id else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let document = try await control.loadUnclassified(relativePath: path)
        let access = try await triptychAccess()
        defer { releaseTriptychAccess(access) }
        guard let destinationRepository = access.repositories[slot] else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let destination = Self.markdownPath(requestedPath)
        guard let destinationVaultID = workspaceAssignment?.vault(for: slot)?.id else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let coordinator = UnclassifiedClassificationCoordinator(
            triptychID: triptychID,
            control: control,
            destinationVaultID: destinationVaultID,
            destinationRepository: destinationRepository,
            recoveryStore: recoveryStore
        )
        let commit: UnclassifiedClassificationCommit
        do {
            commit = try await coordinator.classify(
                sourceRelativePath: path,
                expectedRevision: document.fingerprint,
                destinationRelativePath: destination
            )
        } catch {
            await refreshTransactionRecoveryRecords()
            throw error
        }
        _ = try await control.identity(
            forVaultID: destinationVaultID,
            relativePath: commit.destination.relativePath,
            fingerprint: commit.committedRevision
        )
        try await refreshNoteLocationScope()
        scheduleWorkspaceCatalogRefresh()
        showToast("Classified as \(slot.displayName): \(destination)")
    }

    private func workspaceMovePlan(
        repositories: [UUID: VaultRepository],
        moving source: VaultQualifiedNoteID,
        to destination: VaultQualifiedNoteID
    ) async throws -> IncomingLinkRewritePlan {
        var documents: [VaultQualifiedNoteID: NoteDocument] = [:]
        for (vaultID, repository) in repositories {
            for path in try await repository.markdownRelativePaths() {
                let document = try await repository.load(relativePath: path)
                documents[VaultQualifiedNoteID(vaultID: vaultID, relativePath: path)] = document
            }
        }
        let semantics = documents.mapValues(MarkdownSemanticDocument.init(parsing:))
        let catalog = documents.map { id, document in
            LinkCatalogNote(vaultID: id.vaultID, document: document, semantic: semantics[id])
        }
        let graph = LinkGraphBuilder.build(
            generation: (workspaceCatalog?.graph?.generation ?? 0) + 1,
            catalog: catalog,
            documents: semantics,
            resolutionScope: .workspace
        )
        return IncomingLinkRewriter.plan(
            documents: documents,
            graph: graph,
            moving: source,
            to: destination
        )
    }

    func refreshTransactionRecoveryRecords() async {
        guard let transactionRecoveryStore else {
            transactionRecoveryRecords = []
            transactionRecoveryError = nil
            return
        }
        do {
            transactionRecoveryRecords = try await transactionRecoveryStore.pending()
            transactionRecoveryError = nil
        } catch {
            transactionRecoveryRecords = []
            transactionRecoveryError = "Scholium could not read the durable recovery records. Their file remains unchanged. \(error.localizedDescription)"
        }
    }

    func markTransactionRecoveryResolved(_ id: UUID) async throws {
        guard let transactionRecoveryStore else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        try await transactionRecoveryStore.resolve(id)
        await refreshTransactionRecoveryRecords()
    }

    func revealTransactionRecoveryRecordsInFinder() {
        guard let url = transactionRecoveryStore?.storageURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func migrateAppOwnedState(
        sourcePath: String,
        destinationPath: String,
        fingerprint: DocumentFingerprint
    ) async throws {
        guard let noteID = noteIdentityByPath[sourcePath] else {
            throw NoteIdentityRecoveryError.identityUnresolved(sourcePath)
        }
        guard let control = triptychControlStore,
              let repository,
              let vaultID = currentRegisteredVault?.id,
              let identityRecoveryCoordinator else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        _ = try await control.moveIdentity(
            id: noteID,
            to: destinationPath,
            fingerprint: fingerprint
        )
        let canvasStore = NamedCanvasStore(vaultStorageURL: await repository.storageURL)
        let failures = await identityRecoveryCoordinator.resumePendingRebindings(
            vaultID: vaultID,
            repository: repository,
            canvas: canvasStore,
            migrateCritiquePaths: currentWorkspaceSlot == .output
        )
        pendingIdentityRebindings = try await control.pendingIdentityRebindings(vaultID: vaultID)
        identityMigrationFailures = failures
        let didComplete = !pendingIdentityRebindings.contains { $0.noteID == noteID }
        migrateInMemoryPath(
            from: sourcePath,
            to: destinationPath,
            noteID: noteID,
            identityResolved: didComplete
        )
    }

    private func migrateInMemoryPath(
        from sourcePath: String,
        to destinationPath: String,
        noteID: UUID,
        identityResolved: Bool
    ) {
        noteIdentityByPath[sourcePath] = nil
        if identityResolved {
            noteIdentityByPath[destinationPath] = noteID
        }
        if identityResolved, let record = humanReviewRecords.removeValue(forKey: sourcePath) {
            humanReviewRecords[destinationPath] = record
        } else {
            humanReviewRecords[sourcePath] = nil
        }
        openTabs = openTabs.map { $0 == sourcePath ? destinationPath : $0 }
        if activeTab == sourcePath { activeTab = destinationPath }
        if let vaultID = currentRegisteredVault?.id {
            navigationStack = navigationStack.map { reference in
                guard reference.vaultID == vaultID,
                      reference.relativePath == sourcePath else { return reference }
                return VaultQualifiedNoteID(vaultID: vaultID, relativePath: destinationPath)
            }
            recentNotesHistory = recentNotesHistory.migratingPath(
                vaultID: vaultID,
                from: sourcePath,
                to: destinationPath
            )
            if let presentation = vaultPresentations[vaultID] {
                vaultPresentations[vaultID] = presentation.migratingPath(
                    from: sourcePath,
                    to: destinationPath
                )
            }
        }
        if let mode = documentModes.removeValue(forKey: sourcePath) {
            documentModes[destinationPath] = mode
        }
        if let scroll = documentScrollPositions.removeValue(forKey: sourcePath) {
            documentScrollPositions[destinationPath] = scroll
        }
        if changedSinceReviewPaths.remove(sourcePath) != nil {
            changedSinceReviewPaths.insert(destinationPath)
        }
    }

    private static func markdownPath(_ requestedPath: String) -> String {
        let trimmed = requestedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: trimmed).pathExtension.caseInsensitiveCompare("md") == .orderedSame
            ? trimmed
            : trimmed + ".md"
    }

    func quickOpenResults(for query: String, limit: Int = 40) -> [WorkspaceCatalogNote] {
        workspaceCatalog?.quickOpenResults(for: query, limit: limit) ?? []
    }

    func refreshAdvancedSearch() async {
        let state = advancedSearchState
        let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            advancedSearchHits = []
            advancedSearchError = nil
            return
        }
        isSearchRunning = true
        defer { isSearchRunning = false }
        guard let workspaceAssignment else {
            advancedSearchHits = []
            refreshStatusText = "Search unavailable"
            advancedSearchError = "Open a complete Triptych before searching."
            return
        }
        do {
            var hits = try await workspaceStore.federatedSearch(
                SearchQuery(query),
                in: workspaceAssignment,
                limit: 200
            )
            switch state.scope.canonical {
            case .thisNote:
                guard let path = currentNote?.relativePath,
                      let vaultID = currentRegisteredVault?.id else {
                    hits = []
                    break
                }
                hits.removeAll { $0.relativePath != path || $0.vaultID != vaultID }
            case .triptych:
                break
            default:
                break
            }
            advancedSearchHits = hits
            advancedSearchError = nil
            if refreshStatusText == "Search unavailable" { refreshStatusText = nil }
        } catch {
            advancedSearchHits = []
            refreshStatusText = "Search unavailable"
            advancedSearchError = error.localizedDescription
            workspaceCatalogError = "Search refresh failed. \(error.localizedDescription)"
        }
    }

    func saveCurrentSearch(named requestedName: String) {
        let name = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !advancedSearchState.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var state = advancedSearchState
        state.scope = state.scope.canonical
        enqueueSavedSearchMutation { searches in
            var searches = searches
            searches.insert(SavedSearch(name: name, state: state), at: 0)
            return searches
        }
    }

    func runSavedSearch(_ search: SavedSearch) {
        advancedSearchState = search.state
        advancedSearchState.scope = advancedSearchState.scope.canonical
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
                try await self.savedSearchStore.save(proposed)
                guard !Task.isCancelled else { return }
                self.savedSearches = proposed
            } catch {
                self.showToast("Could not save search: \(error.localizedDescription)", kind: .error)
            }
        }
    }

    func openSearchHit(_ hit: SearchHit) {
        showSearchSurface = false
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            if self.currentRegisteredVault?.id != hit.vaultID {
                guard let vault = self.registeredVaults.first(where: { $0.id == hit.vaultID }) else {
                    throw WorkspaceRegistryError.vaultNotFound(hit.vaultID.uuidString)
                }
                try await self.openRegisteredVault(vault)
            }
            self.pendingSourceLine = hit.sourceLine
            self.openNote(hit.relativePath)
            self.contentDestination = .document
        }
    }

    func openNote(_ path: String, inNewTab: Bool = false) {
        guard notes.contains(where: { $0.relativePath == path }) else {
            showToast("Note not found: \(path)", kind: .warning)
            return
        }
        if inNewTab {
            if !openTabs.contains(path) { openTabs.append(path) }
            activeTab = path
        } else if openTabs.contains(path) {
            activeTab = path
        } else if let activeTab,
                  let activeIndex = openTabs.firstIndex(of: activeTab) {
            // Ordinary sidebar navigation replaces the current tab. New tabs
            // are created only by the explicit Open in New Tab command.
            openTabs[activeIndex] = path
            self.activeTab = path
        } else {
            openTabs = [path]
            activeTab = path
        }
        recordNavigationVisit(path)
    }

    private func recordNavigationVisit(_ path: String) {
        guard noteLocationScope == .workspace,
              let vaultID = currentRegisteredVault?.id else { return }
        let reference = VaultQualifiedNoteID(vaultID: vaultID, relativePath: path)
        recentNotesHistory.record(reference)
        if navigationStack.indices.contains(navigationIndex),
           navigationStack[navigationIndex] == reference {
            return
        }
        if navigationIndex < navigationStack.count - 1 {
            navigationStack.removeSubrange((navigationIndex + 1)...)
        }
        navigationStack.append(reference)
        navigationIndex = navigationStack.count - 1
        // Navigation history is chronological. It intentionally allows A → B → A.
    }

    func openRelationshipSource(_ locator: SourceLocator) {
        guard notes.contains(where: { $0.relativePath == locator.file }) else {
            showToast("Relationship source not found: \(locator.file)", kind: .warning)
            return
        }
        requestOpenNote(locator.file, sourceLine: locator.line, mode: .source)
    }

    func closeTab(_ path: String) {
        openTabs.removeAll { $0 == path }
        if activeTab == path { activeTab = openTabs.last }
    }

    func closeCurrentTab() {
        guard let tab = activeTab else { return }
        requestCloseTab(tab)
    }

    private func navigate(toHistoryIndex requestedIndex: Int) async throws {
        guard navigationStack.indices.contains(requestedIndex) else { return }
        let target = navigationStack[requestedIndex]
        let targetOccurrence = navigationStack[...requestedIndex].count(where: { $0 == target }) - 1
        if currentRegisteredVault?.id != target.vaultID {
            // One window belongs to one complete Triptych. A corrupt or stale
            // session must never use history to switch this window into an
            // unrelated registered Triptych.
            guard let vault = workspaceAssignment?.vaults.values.first(where: {
                $0.id == target.vaultID
            }) else {
                throw WorkspaceRegistryError.vaultNotFound(target.vaultID.uuidString)
            }
            try await openRegisteredVault(vault)
        }
        guard notes.contains(where: { $0.relativePath == target.relativePath }) else {
            throw WindowNavigationError.noteUnavailable(target.relativePath)
        }
        let matchingIndices = navigationStack.indices.filter { navigationStack[$0] == target }
        guard matchingIndices.indices.contains(targetOccurrence) else {
            throw WindowNavigationError.visitUnavailable
        }
        navigationIndex = matchingIndices[targetOccurrence]
        activeTab = target.relativePath
        if !openTabs.contains(target.relativePath) {
            openTabs.append(target.relativePath)
        }
        recentNotesHistory.record(target)
        contentDestination = .document
    }

    func showInFinder(_ path: String) {
        guard let vaultURL = vaultConfig?.path else { return }
        let fileURL = vaultURL.appendingPathComponent(path)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func revealVaultInFinder() {
        guard let vaultURL = vaultConfig?.path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([vaultURL])
    }

    func reviewNote(at path: String) {
        guard currentVaultRole.allowsHumanReview,
              notes.contains(where: { $0.relativePath == path }) else { return }
        qualityReviewPath = path
        showQualityReview = true
    }

    func humanReviewRecord(for path: String) -> HumanReviewRecord? {
        humanReviewRecords[path]
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
        guard currentVaultRole.allowsHumanReview,
              let vault = currentRegisteredVault,
              let noteID = noteIdentityByPath[path] else {
            throw HumanReviewWorkflowError.unavailableForOutput
        }
        guard documentRevisions[path] == fingerprint else {
            throw HumanReviewWorkflowError.staleRevision
        }
        let record = try await humanReviewStore.saveDraft(
            noteID: noteID,
            vaultID: vault.id,
            relativePath: path,
            draft: HumanReviewDraft(
                fingerprint: fingerprint,
                qualification: qualification,
                reviewNote: reviewNote
            )
        )
        humanReviewRecords[path] = record
    }

    func completeHumanReview(
        for path: String,
        fingerprint: DocumentFingerprint,
        qualification: NoteQualification?,
        reviewNote: String
    ) async throws {
        guard currentVaultRole.allowsHumanReview,
              let vault = currentRegisteredVault,
              let noteID = noteIdentityByPath[path] else {
            throw HumanReviewWorkflowError.unavailableForOutput
        }
        guard documentRevisions[path] == fingerprint else {
            throw HumanReviewWorkflowError.staleRevision
        }
        let record = try await humanReviewStore.completeReview(
            noteID: noteID,
            vaultID: vault.id,
            relativePath: path,
            fingerprint: fingerprint,
            qualification: qualification,
            reviewNote: reviewNote
        )
        humanReviewRecords[path] = record
        changedSinceReviewPaths.remove(path)
        if let index = notes.firstIndex(where: { $0.relativePath == path }),
           let latest = record.review(for: fingerprint) {
            notes[index].isReviewed = true
            notes[index].reviewedAt = latest.completedAt
        }
        await refreshWorkspaceCatalog()
    }

    func requestCritique(of path: String) {
        guard currentVaultRole.allowsCritique,
              !CritiquePlacement.isManagedCritiquePath(path),
              noteIdentityByPath[path] != nil,
              notes.contains(where: { $0.relativePath == path }) else { return }
        pendingCritiquePath = path
    }

    func openWorkspaceReference(
        _ reference: VaultNoteReference,
        line: Int? = nil,
        mode: NotePresentationMode = .source
    ) async {
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            if self.currentRegisteredVault?.id != reference.vaultID {
                let vault = try await self.workspaceRegistry.resolve(reference.vaultID.uuidString)
                try await self.openRegisteredVault(vault)
            }
            guard self.notes.contains(where: { $0.relativePath == reference.relativePath }) else {
                self.showToast(
                    "The linked note is no longer present at \(reference.relativePath).",
                    kind: .warning
                )
                return
            }
            self.openNote(reference.relativePath)
            self.contentDestination = .document
            if let line {
                self.pendingSourceLine = max(1, line)
                self.requestPresentationMode = mode
            }
        }
    }

    func openInternalLink(_ targetWithFragment: String, from sourcePath: String) {
        guard let sourceVaultID = currentRegisteredVault?.id,
              let graph = workspaceCatalog?.graph else {
            showToast("Connections are still refreshing. Try the link again shortly.", kind: .information)
            return
        }
        let parts = targetWithFragment.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let target = String(parts.first ?? "").removingPercentEncoding ?? String(parts.first ?? "")
        let rawFragment = parts.count == 2 ? String(parts[1]) : nil
        let fragment = rawFragment.flatMap { $0.removingPercentEncoding ?? $0 }
        let source = VaultQualifiedNoteID(vaultID: sourceVaultID, relativePath: sourcePath)
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
            showToast("The resolved note is not available in the current Triptych catalog.", kind: .warning)
            return
        }
        Task { await openWorkspaceReference(reference, line: destination.line, mode: .read) }
    }

    @discardableResult
    func saveNote(_ note: Note, expectedRevision: DocumentFingerprint) async throws -> Note {
        try requireResolvedIdentity(for: note.relativePath)
        guard let repository else { throw VaultRepositoryError.fileDoesNotExist(note.relativePath) }
        guard let original = notes.first(where: { $0.relativePath == note.relativePath }) else {
            throw VaultRepositoryError.fileDoesNotExist(note.relativePath)
        }

        var edits: [String: FrontmatterEditValue] = [:]
        let keys = Set(original.frontmatter.keys).union(note.frontmatter.keys)
        for key in keys where original.frontmatter[key] != note.frontmatter[key] {
            if let value = note.frontmatter[key] {
                edits[key] = Self.coreValue(value)
            } else {
                edits[key] = .remove
            }
        }
        let bodyChanged = original.body != note.body
        let changeSet: NoteChangeSet
        if bodyChanged && !edits.isEmpty {
            changeSet = .composite(body: note.body, frontmatter: edits)
        } else if bodyChanged {
            changeSet = .body(note.body)
        } else {
            changeSet = .frontmatter(edits)
        }

        do {
            let result = try await repository.save(
                relativePath: note.relativePath,
                changeSet: changeSet,
                expectedRevision: expectedRevision
            )
            let saved = await replaceSavedDocument(result.document)
            if let vaultID = currentRegisteredVault?.id {
                workspaceStore.publishCommit(WorkspaceCommit(
                    originSessionID: windowSessionID,
                    vaultID: vaultID,
                    relativePath: note.relativePath,
                    revision: result.document.fingerprint
                ))
            }
            lastSaveError = nil
            return saved
        } catch {
            lastSaveError = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func saveBody(_ body: String, for path: String, expectedRevision: DocumentFingerprint) async throws -> Note {
        guard var note = notes.first(where: { $0.relativePath == path }) else {
            throw VaultRepositoryError.fileDoesNotExist(path)
        }
        note.body = body
        return try await saveNote(note, expectedRevision: expectedRevision)
    }

    @discardableResult
    func saveSource(
        _ source: String,
        for path: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> Note {
        if noteLocationScope == .unclassified {
            guard let control = triptychControlStore else {
                throw VaultRepositoryError.fileDoesNotExist(path)
            }
            do {
                let document = try await control.saveUnclassified(
                    relativePath: path,
                    content: source,
                    expectedRevision: expectedRevision
                )
                guard let index = notes.firstIndex(where: { $0.relativePath == path }) else {
                    throw VaultRepositoryError.fileDoesNotExist(path)
                }
                do {
                    let parsed = try await markdownEngine.parse(document.rawContent)
                    notes[index] = Note(
                        relativePath: path,
                        frontmatter: parsed.frontmatter,
                        body: parsed.body,
                        rawContent: document.rawContent,
                        vaultRole: .other,
                        fileModifiedAt: Date()
                    )
                } catch {
                    notes[index].rawContent = document.rawContent
                    notes[index].body = document.body
                    notes[index].wordCount = document.body.split(whereSeparator: \Character.isWhitespace).count
                    refreshStatusText = "Derived refresh failed"
                    workspaceCatalogError = "The imported note was saved, but Scholium could not refresh its metadata projection. \(error.localizedDescription)"
                }
                documentRevisions[path] = document.fingerprint
                lastSaveError = nil
                return notes[index]
            } catch {
                lastSaveError = error.localizedDescription
                throw error
            }
        }
        try requireResolvedIdentity(for: path)
        guard let repository else { throw VaultRepositoryError.fileDoesNotExist(path) }
        do {
            let result = try await repository.save(
                relativePath: path,
                changeSet: .source(source),
                expectedRevision: expectedRevision
            )
            let saved = await replaceSavedDocument(result.document)
            if let vaultID = currentRegisteredVault?.id {
                workspaceStore.publishCommit(WorkspaceCommit(
                    originSessionID: windowSessionID,
                    vaultID: vaultID,
                    relativePath: path,
                    revision: result.document.fingerprint
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
        if noteLocationScope == .unclassified {
            guard let control = triptychControlStore else {
                throw VaultRepositoryError.fileDoesNotExist(path)
            }
            return try await control.loadUnclassified(relativePath: path)
        }
        guard let repository else { throw VaultRepositoryError.fileDoesNotExist(path) }
        return try await repository.load(relativePath: path)
    }

    /// Accepts only the disk revision that was presented in conflict
    /// comparison. This uses the existing incremental projection path instead
    /// of requiring a full-vault rescan for a document-scoped recovery action.
    @discardableResult
    func reloadDocumentFromDisk(
        for path: String,
        expectedDiskRevision: DocumentFingerprint
    ) async throws -> Note {
        let document = try await diskDocument(for: path)
        guard document.fingerprint == expectedDiskRevision else {
            throw VaultRepositoryError.conflict(
                expected: expectedDiskRevision,
                current: document.fingerprint
            )
        }
        return await replaceSavedDocument(document)
    }

    func showToast(_ message: String, kind: Toast.Kind = .success) {
        let toast = Toast(message: message, kind: kind)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            toastMessage = toast
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                if self?.toastMessage == toast { self?.toastMessage = nil }
            }
        }
    }

    private func refreshDocumentRevisions() {
        documentRevisions = Dictionary(uniqueKeysWithValues: notes.map {
            ($0.relativePath, DocumentFingerprint(content: $0.rawContent))
        })
    }

    private func refreshIdentityAndReviewState() async {
        guard noteLocationScope != .unclassified,
              let vault = currentRegisteredVault,
              let repository,
              let identityRecoveryCoordinator else {
            noteIdentityByPath = [:]
            identityAmbiguities = []
            pendingIdentityRebindings = []
            identityMigrationFailures = []
            humanReviewRecords = [:]
            changedSinceReviewPaths = []
            return
        }
        let documents = notes.map { note in
            (
                relativePath: note.relativePath,
                fingerprint: documentRevisions[note.relativePath] ?? DocumentFingerprint(content: note.rawContent)
            )
        }
        let canvas = NamedCanvasStore(vaultStorageURL: await repository.storageURL)
        let recovery: NoteIdentityRecoveryState
        do {
            recovery = try await identityRecoveryCoordinator.reconcile(
                vaultID: vault.id,
                documents: documents,
                repository: repository,
                canvas: canvas,
                migrateCritiquePaths: currentWorkspaceSlot == .output
            )
        } catch {
            noteIdentityByPath = [:]
            identityResolutionError = error.localizedDescription
            return
        }
        let identities = recovery.identities
        for rebinding in recovery.completedRebindings {
            migrateInMemoryPath(
                from: rebinding.previousRelativePath,
                to: rebinding.relativePath,
                noteID: rebinding.id,
                identityResolved: true
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

        var records: [String: HumanReviewRecord] = [:]
        var changed: Set<String> = []
        for index in notes.indices {
            let path = notes[index].relativePath
            guard let noteID = identities[path]?.id else {
                notes[index].isReviewed = false
                notes[index].reviewedAt = nil
                continue
            }
            let fingerprint = documentRevisions[path] ?? DocumentFingerprint(content: notes[index].rawContent)
            if let existing = await humanReviewStore.record(noteID: noteID),
               existing.comments.contains(where: {
                   guard let anchor = $0.anchor else { return false }
                   return anchor.fingerprint != fingerprint
               }) {
                do {
                    try await humanReviewStore.reattachComments(
                        noteID: noteID,
                        to: NoteDocument(relativePath: path, rawContent: notes[index].rawContent)
                    )
                } catch {
                    refreshStatusText = "Researcher comments refresh failed"
                    workspaceCatalogError = "Scholium left the existing comment records unchanged because their anchors could not be refreshed safely. \(error.localizedDescription)"
                }
            }
            guard let record = await humanReviewStore.record(noteID: noteID) else {
                notes[index].isReviewed = false
                notes[index].reviewedAt = nil
                continue
            }
            records[path] = record
            if let currentReview = record.review(for: fingerprint) {
                notes[index].isReviewed = true
                notes[index].reviewedAt = currentReview.completedAt
            } else {
                notes[index].isReviewed = false
                notes[index].reviewedAt = record.latestReview?.completedAt
                if record.latestReview != nil { changed.insert(path) }
            }
        }
        humanReviewRecords = records
        changedSinceReviewPaths = changed
    }

    private func resetWindowSession() {
        notes = []
        noteLocationScope = .workspace
        noteLifecycleRequest = nil
        openTabs = []
        activeTab = nil
        documentModes = [:]
        documentScrollPositions = [:]
        advancedSearchState = SearchWorkspaceState()
        advancedSearchHits = []
        advancedSearchError = nil
        pendingSourceLine = nil
        selectedTag = nil
        isReviewedFilter = false
        isUnqualifiedFilter = false
        clearMetadataFilters()
        currentRegisteredVault = nil
        currentVaultRole = .other
        showQualityReview = false
        qualityReviewPath = nil
        showResearcherComments = false
        researcherCommentsPath = nil
        pendingCommentSelection = nil
        focusedResearcherCommentID = nil
        humanReviewRecords = [:]
        noteIdentityByPath = [:]
        identityAmbiguities = []
        pendingIdentityRebindings = []
        identityMigrationFailures = []
        selectedIdentityAmbiguity = nil
        identityResolutionError = nil
        pendingCritiquePath = nil
        showDialogue = false
        dialogueInitialNotes = []
        editingBodyPath = nil
        contentDestination = .document
        documentRevisions = [:]
        relationshipGraph = nil
    }

    private func startWatching() {
        watcherTask?.cancel()
        guard let watchedVaultID = currentRegisteredVault?.id,
              let runtime = sharedVaultRuntime else { return }
        watcherTask = Task { [weak self] in
            guard let self else { return }
            let updates = await runtime.updates(subscriberID: self.windowSessionID)
            for await update in updates {
                guard !Task.isCancelled,
                      self.currentRegisteredVault?.id == watchedVaultID else { return }
                await self.applySharedRuntimeUpdate(update, runtime: runtime)
            }
        }
        if ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_RESTART_WATCHER"] == "1",
           !didRunWatcherRestartSmoke {
            didRunWatcherRestartSmoke = true
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.watcherTask?.cancel()
                self.startWatching()
            }
        }
    }

    private func applySharedRuntimeUpdate(
        _ update: VaultRuntimeUpdate,
        runtime: SharedVaultRuntime
    ) async {
        if update.event.rootChanged {
            refreshStatusText = "Vault location changed"
            vaultError = "The watched vault moved or became unavailable. Re-select it in Manage Triptychs."
            return
        }
        if case .failed(_, let message) = update.derivedState {
            refreshStatusText = "Derived refresh failed"
            vaultError = message
            return
        }
        guard noteLocationScope == .workspace else {
            scheduleWorkspaceCatalogRefresh()
            return
        }

        let previousByPath = Dictionary(uniqueKeysWithValues: notes.map { ($0.relativePath, $0) })
        var refreshed = await runtime.currentNotes()
        let activeRecoveryNote: Note? = {
            guard let activeTab,
                  editingBodyPath == activeTab,
                  !refreshed.contains(where: { $0.relativePath == activeTab }) else { return nil }
            return previousByPath[activeTab]
        }()
        if let activeRecoveryNote {
            refreshed.append(activeRecoveryNote)
            refreshStatusText = "Conflict: note deleted outside Scholium"
            lastSaveError = "The open note was deleted outside Scholium. Its editor remains open so you can recover the text."
        }
        if let editingBodyPath,
           let previous = previousByPath[editingBodyPath],
           let current = refreshed.first(where: { $0.relativePath == editingBodyPath }),
           DocumentFingerprint(content: previous.rawContent) != DocumentFingerprint(content: current.rawContent) {
            refreshStatusText = "Conflict: note changed outside Scholium"
            lastSaveError = "The note changed on disk while this window had an editing buffer. Reload, Compare, or keep editing."
        }

        notes = refreshed.sorted(by: notesAreOrdered)
        refreshDocumentRevisions()
        if let activeRecoveryNote {
            documentRevisions[activeRecoveryNote.relativePath] = previousByPath[activeRecoveryNote.relativePath]
                .map { DocumentFingerprint(content: $0.rawContent) }
        }
        await refreshIdentityAndReviewState()
        relationshipGraph = await runtime.currentGraph()
        let brokenPaths = Set(relationshipGraph?.diagnostics.compactMap {
            $0.code == .broken && $0.source.vaultID == currentRegisteredVault?.id
                ? $0.source.relativePath
                : nil
        } ?? [])
        if let graph = relationshipGraph,
           let vaultID = currentRegisteredVault?.id {
            for index in notes.indices {
                let id = VaultQualifiedNoteID(vaultID: vaultID, relativePath: notes[index].relativePath)
                notes[index].linkCount = graph.outgoing[id]?.count ?? 0
                notes[index].backlinkCount = graph.incoming[id]?.count ?? 0
            }
        }
        allTags = await frontmatterService.allTags(notes: notes).map(\.tag)
        if let currentRegisteredVault {
            do {
                _ = try await searchEngine.synchronize(
                    notes: notes.filter { $0.relativePath != activeRecoveryNote?.relativePath },
                    vault: currentRegisteredVault,
                    applicationSupportURL: applicationSupportURL,
                    brokenLinkPaths: brokenPaths
                )
                if refreshStatusText == "Derived refresh failed" { refreshStatusText = nil }
            } catch {
                refreshStatusText = "Derived refresh failed"
                vaultError = "The search index could not refresh. Retry after checking vault access."
            }
        }
        scheduleWorkspaceCatalogRefresh()
    }

    /// Publishes authoritative document bytes before refreshing disposable
    /// projections. A parse or index failure can make derived state stale, but
    /// must never make the editor retry an already committed repository write
    /// or reject a disk revision the researcher explicitly accepted.
    private func replaceSavedDocument(_ document: NoteDocument) async -> Note {
        let previousIndex = notes.firstIndex(where: { $0.relativePath == document.relativePath })
        let previous = previousIndex.map { notes[$0] }
        let parsed: (frontmatter: [String: FrontmatterValue], body: String)
        do {
            parsed = try await markdownEngine.parse(document.rawContent)
        } catch {
            if let previousIndex {
                notes[previousIndex].rawContent = document.rawContent
                notes[previousIndex].body = document.body
                notes[previousIndex].wordCount = document.body.split(whereSeparator: { $0.isWhitespace }).count
                documentRevisions[document.relativePath] = document.fingerprint
                refreshStatusText = "Derived refresh failed"
                workspaceCatalogError = "The note bytes are current, but Scholium could not refresh its metadata projection. \(error.localizedDescription)"
                scheduleWorkspaceCatalogRefresh()
                return notes[previousIndex]
            }
            let recovered = Note(
                relativePath: document.relativePath,
                frontmatter: [:],
                body: document.body,
                rawContent: document.rawContent,
                vaultRole: noteLocationScope == .unclassified ? .other : currentVaultRole
            )
            notes.append(recovered)
            notes.sort(by: notesAreOrdered)
            documentRevisions[document.relativePath] = document.fingerprint
            refreshStatusText = "Derived refresh failed"
            workspaceCatalogError = "The note bytes are current, but Scholium could not refresh its metadata projection. \(error.localizedDescription)"
            scheduleWorkspaceCatalogRefresh()
            return recovered
        }
        let info = await vaultService.fileInfo(at: document.relativePath)
        let saved = Note(
            relativePath: document.relativePath,
            frontmatter: parsed.frontmatter,
            body: parsed.body,
            rawContent: document.rawContent,
            vaultRole: noteLocationScope == .unclassified ? .other : currentVaultRole,
            isReviewed: previous?.isReviewed ?? false,
            reviewedAt: previous?.reviewedAt,
            fileModifiedAt: info?.modified ?? Date()
        )
        if let previousIndex {
            notes[previousIndex] = saved
        } else {
            notes.append(saved)
            notes.sort(by: notesAreOrdered)
        }
        documentRevisions[document.relativePath] = document.fingerprint
        await buildIndexes(incrementalPaths: [document.relativePath])
        return notes.first(where: { $0.relativePath == document.relativePath }) ?? saved
    }

    /// Applies an external FSEvent batch without rereading every note or
    /// rebuilding the lexical index. Link and workflow projections are
    /// recomputed from the in-memory catalog so newly resolved links remain
    /// correct; SQLite publishes only the affected file generation.
    private func applyWatchEvent(
        _ event: VaultWatchEvent
    ) async throws {
        if noteLocationScope != .workspace {
            try await refreshNoteLocationScope()
            return
        }
        guard let repository else { throw VaultRepositoryError.fileDoesNotExist("vault") }
        let isWorkspacePath: (String) -> Bool = {
            !$0.hasPrefix("Set Aside/") && !$0.hasPrefix("Trash/")
        }
        let deleted = Set(event.deleted.filter(isWorkspacePath))
        let changed = Set((event.added + event.modified).filter(isWorkspacePath)).subtracting(deleted)
        let retainedDeletedPath: String? = {
            guard let activeTab,
                  deleted.contains(activeTab),
                  editorFlushRegistration?.relativePath == activeTab else { return nil }
            return activeTab
        }()

        if !deleted.isEmpty {
            notes.removeAll {
                deleted.contains($0.relativePath) && $0.relativePath != retainedDeletedPath
            }
            for path in deleted {
                if path == retainedDeletedPath {
                    refreshStatusText = "Conflict: note deleted outside Scholium"
                    lastSaveError = "The open note was deleted outside Scholium. Its editor remains open so you can recover the text."
                    showToast(
                        "The open note was deleted outside Scholium. Scholium kept its document session open for recovery.",
                        kind: .warning
                    )
                    continue
                }
                documentRevisions[path] = nil
                if activeTab == path { activeTab = nil }
                openTabs.removeAll { $0 == path }
            }
        }

        for path in changed.sorted() {
            let document = try await repository.load(relativePath: path)
            let previous = notes.first(where: { $0.relativePath == path })
            let parsed = try await markdownEngine.parse(document.rawContent)
            let info = await vaultService.fileInfo(at: path)
            let replacement = Note(
                relativePath: path,
                frontmatter: parsed.frontmatter,
                body: parsed.body,
                rawContent: document.rawContent,
                vaultRole: currentVaultRole,
                isReviewed: previous?.isReviewed ?? false,
                reviewedAt: previous?.reviewedAt,
                fileModifiedAt: info?.modified ?? Date()
            )
            if let index = notes.firstIndex(where: { $0.relativePath == path }) {
                notes[index] = replacement
            } else {
                notes.append(replacement)
            }
            documentRevisions[path] = document.fingerprint
        }

        notes.sort(by: notesAreOrdered)
        await buildIndexes(incrementalPaths: changed, deletedPaths: deleted)
    }

    func setVaultRole(_ role: VaultRole) {
        guard let config = vaultConfig, let registered = currentRegisteredVault,
              role != currentVaultRole else { return }
        Task {
            do {
                let updated = try await workspaceRegistry.register(
                    path: config.path,
                    name: registered.name,
                    role: role
                )
                currentRegisteredVault = updated
                currentVaultRole = role
                await vaultService.setVaultRole(role)
                try await rescanVault()
                showToast("Vault role changed to \(role.displayName)")
            } catch {
                showToast("Could not change vault role: \(error.localizedDescription)", kind: .error)
            }
        }
    }

    private func knowledgeBase(for role: VaultRole) -> KnowledgeBase {
        switch role {
        case .sourceCorpus: .papers
        case .topicKnowledge: .topics
        case .dissertationControl, .draftProject, .other: .output
        }
    }

    /// Atomic self-writes can produce the same FSEvent as an external edit. If
    /// every reported path has the exact fingerprint already held in memory,
    /// the event is only an acknowledgement and a full rescan is unnecessary.
    private func eventMatchesCurrentDocuments(
        _ event: VaultWatchEvent
    ) async -> Bool {
        let reportedPaths = Set(event.added + event.modified + event.deleted)
        guard !reportedPaths.isEmpty, let repository else { return false }
        for path in reportedPaths {
            guard let expected = documentRevisions[path],
                  let document = try? await repository.load(relativePath: path),
                  document.fingerprint == expected else { return false }
        }
        return true
    }

    private static func coreValue(_ value: FrontmatterValue) -> FrontmatterEditValue {
        switch value {
        case .string(let value): return .string(value)
        case .int(let value): return .integer(value)
        case .double(let value): return .double(value)
        case .bool(let value): return .boolean(value)
        case .date(let value):
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
            return .string(formatter.string(from: value))
        case .array(let value): return .array(value)
        case .dictionary:
            // Unknown/nested mappings are preserved byte-for-byte and are not
            // editable through the current top-level schema form.
            return .string("")
        }
    }

}

private enum HumanReviewWorkflowError: LocalizedError {
    case staleRevision
    case unavailableForOutput

    var errorDescription: String? {
        switch self {
        case .staleRevision:
            return "The note changed while this review was open. Reopen Review and check the current text before saving."
        case .unavailableForOutput:
            return "Human Review is unavailable in Works. Request a Critique for an ordinary Work note instead."
        }
    }
}

private enum ResearcherCommentWorkflowError: LocalizedError {
    case unavailable
    case staleRevision

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Comments are unavailable until Scholium can identify this Analysis, Topic, or Work reliably."
        case .staleRevision:
            return "The note changed before the comment could be attached. Reopen Comments and select the current passage."
        }
    }
}

private enum ClipboardWorkflowError: LocalizedError {
    case copyFailed(recovery: String?)

    var errorDescription: String? {
        switch self {
        case .copyFailed(let recovery):
            if let recovery {
                return "macOS did not accept the text on the clipboard. \(recovery)"
            }
            return "macOS did not accept the text on the clipboard. Try copying again."
        }
    }
}

private enum DialogueWorkflowError: LocalizedError {
    case contextChanged(String)

    var errorDescription: String? {
        switch self {
        case .contextChanged(let title):
            return "\(title) changed or moved while Dialogue was open. Reload the note list, review the current text, and copy the instructions again."
        }
    }
}

private enum CritiqueRequestWorkflowError: LocalizedError {
    case registryUnavailable(String)
    case rollbackFailed(requestError: String, rollbackError: String)
    case targetChanged

    var errorDescription: String? {
        switch self {
        case .registryUnavailable(let reason):
            return reason
        case .rollbackFailed(let requestError, let rollbackError):
            return "Scholium could not record the Critique request and could not restore the Critique file automatically. \(requestError) Recovery also failed: \(rollbackError) Use Before Agent Work in Note History before continuing."
        case .targetChanged:
            return "The Work changed while Scholium was creating Before Agent Work. Review the current Work and request its Critique again."
        }
    }
}

private enum WorkspaceCommitRefreshError: LocalizedError {
    case revisionChangedAgain

    var errorDescription: String? {
        "The file changed again before this window could load the shared commit."
    }
}

// MARK: - KB Color Helpers

func kbColor(_ kb: KnowledgeBase) -> Color {
    switch kb {
    case .papers: return .blue
    case .topics: return .green
    case .output: return .orange
    }
}

func kbBorderColor(_ kb: KnowledgeBase) -> Color {
    switch kb {
    case .papers: return .blue.opacity(0.6)
    case .topics: return .green.opacity(0.6)
    case .output: return .orange.opacity(0.6)
    }
}
