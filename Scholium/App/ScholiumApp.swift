import ScholiumContracts
import AppKit
import Combine
import QuartzCore
import ScholiumApplication
import SwiftUI
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
        // Keep AppKit's native tab-group commands available. Each Scholium
        // window opts out before it is shown, so Command-N remains an
        // independent work session until the researcher explicitly merges it.
        NSWindow.allowsAutomaticWindowTabbing = true
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
        .defaultSize(
            width: ScholiumMetrics.Triptych.preferredWidth,
            height: ScholiumMetrics.Triptych.preferredHeight
        )
        .windowToolbarStyle(.unified)
        .commands { ScholiumCommands() }

        Settings {
            ScholiumSettingsRoot(workspaceStore: workspaceStore)
        }
    }
}

private enum ScholiumWindowPresentation: Equatable {
    case setup
    case library
    case document

    var minimumContentSize: NSSize {
        switch self {
        case .setup, .library:
            NSSize(
                width: ScholiumMetrics.Triptych.minimumWidth,
                height: ScholiumMetrics.Triptych.minimumHeight
            )
        case .document: NSSize(width: 760, height: 520)
        }
    }
}

private struct ScholiumWindowRoot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SceneStorage("scholium.windowSessionID") private var storedWindowSessionID = ""
    @Binding private var route: TriptychWindowRoute?
    @StateObject private var appState: WindowModel
    @State private var registeredTerminationID: UUID?

    init(workspaceStore: WorkspaceStore, route: Binding<TriptychWindowRoute?>) {
        _route = route
        let requestedRoute = route.wrappedValue
        _appState = StateObject(wrappedValue: WindowModel(
            workspaceStore: workspaceStore,
            requestedTriptychID: requestedRoute?.triptychID,
            createsTriptych: requestedRoute?.createsTriptych == true
        ))
    }

    var body: some View {
        ContentView()
            .environmentObject(appState)
            .tint(ScholiumColorRole.accent.color)
            .focusedSceneValue(\.scholiumWindowModel, appState)
            .background(
                WindowCloseGuard(
                    appState: appState,
                    presentation: windowPresentation,
                    reduceMotion: reduceMotion
                )
            )
            .frame(minWidth: 320, minHeight: 520)
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

    private var windowPresentation: ScholiumWindowPresentation {
        guard appState.hasCompletedInitialRestore, appState.vaultConfig != nil else {
            return .setup
        }
        return appState.currentNote == nil ? .library : .document
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
    let appState: WindowModel
    let presentation: ScholiumWindowPresentation
    let reduceMotion: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            appState: appState,
            presentation: presentation,
            reduceMotion: reduceMotion
        )
    }

    func makeNSView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.onWindowAttachment = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: WindowAttachmentView, context: Context) {
        context.coordinator.update(
            appState: appState,
            presentation: presentation,
            reduceMotion: reduceMotion
        )
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
        var appState: WindowModel
        private var presentation: ScholiumWindowPresentation
        private var reduceMotion: Bool
        private weak var window: NSWindow?
        nonisolated(unsafe) private weak var previousDelegate: (any NSWindowDelegate)?
        private var closeIsAuthorized = false
        private var flushInFlight = false
        private var appliedPresentation: ScholiumWindowPresentation?
        private var preferredDocumentContentSize: NSSize?
        private var presentationGeneration: UInt64 = 0
        private weak var observedToolbar: NSToolbar?
        private var toolbarObserver: NSObjectProtocol?
        private var windowUpdateObserver: NSObjectProtocol?

        init(
            appState: WindowModel,
            presentation: ScholiumWindowPresentation,
            reduceMotion: Bool
        ) {
            self.appState = appState
            self.presentation = presentation
            self.reduceMotion = reduceMotion
            super.init()
        }

        func update(
            appState: WindowModel,
            presentation: ScholiumWindowPresentation,
            reduceMotion: Bool
        ) {
            self.appState = appState
            self.presentation = presentation
            self.reduceMotion = reduceMotion
            if let window {
                installToolbarObserver(for: window)
            }
            schedulePresentationUpdate()
        }

        func attach(to window: NSWindow) {
            if self.window === window, window.delegate === self {
                installToolbarObserver(for: window)
                schedulePresentationUpdate()
                return
            }
            detach()
            self.window = window
            window.tabbingMode = .disallowed
            window.tabbingIdentifier = "scholium-main"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            ScholiumWindowGroupingState.shared.invalidate()
            previousDelegate = window.delegate
            window.delegate = self
            windowUpdateObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didUpdateNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let self, let window else { return }
                    self.installToolbarObserver(for: window)
                }
            }
            installToolbarObserver(for: window)
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
            let attachedSize = window.contentLayoutRect.size
            preferredDocumentContentSize = attachedSize.width >= 760
                ? attachedSize
                : NSSize(width: 1180, height: 760)
            applyPresentationIfNeeded()
        }

        func detach() {
            if let toolbarObserver {
                NotificationCenter.default.removeObserver(toolbarObserver)
            }
            toolbarObserver = nil
            observedToolbar = nil
            if let windowUpdateObserver {
                NotificationCenter.default.removeObserver(windowUpdateObserver)
            }
            windowUpdateObserver = nil
            if let window, window.delegate === self {
                window.delegate = previousDelegate
            }
            window = nil
            previousDelegate = nil
            appliedPresentation = nil
        }

        private func schedulePresentationUpdate() {
            presentationGeneration &+= 1
            let generation = presentationGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.presentationGeneration else { return }
                self.applyPresentationIfNeeded()
            }
        }

        private func installToolbarObserver(for window: NSWindow) {
            guard let toolbar = window.toolbar else {
                if let toolbarObserver {
                    NotificationCenter.default.removeObserver(toolbarObserver)
                }
                toolbarObserver = nil
                observedToolbar = nil
                return
            }
            guard observedToolbar !== toolbar else {
                suppressSystemSidebarToggle()
                return
            }
            if let toolbarObserver {
                NotificationCenter.default.removeObserver(toolbarObserver)
            }
            observedToolbar = toolbar
            toolbarObserver = NotificationCenter.default.addObserver(
                forName: NSToolbar.willAddItemNotification,
                object: toolbar,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.suppressSystemSidebarToggle()
                }
            }
            suppressSystemSidebarToggle()
        }

        private func suppressSystemSidebarToggle() {
            guard let toolbar = window?.toolbar else { return }
            while let index = toolbar.items.firstIndex(where: {
                $0.itemIdentifier == .toggleSidebar
                    || $0.action == #selector(NSSplitViewController.toggleSidebar(_:))
                    || $0.itemIdentifier.rawValue.localizedCaseInsensitiveContains("sidebar")
                    || ["Hide Sidebar", "Show Sidebar", "Toggle Sidebar"].contains($0.label)
            }) {
                toolbar.removeItem(at: index)
            }
        }

        private func applyPresentationIfNeeded() {
            guard let window, appliedPresentation != presentation else { return }

            if appliedPresentation == .document, presentation != .document {
                preferredDocumentContentSize = window.contentLayoutRect.size
            }

            let previousPresentation = appliedPresentation
            let targetSize = targetContentSize(for: presentation, window: window)
            window.contentMinSize = presentation.minimumContentSize

            if presentation != .document {
                appState.sidebarVisible = true
                appState.setResearchInspectorVisible(false, animated: false)
                appState.setNoteHistoryVisible(false, animated: false)
            } else {
                if targetSize.width < 1200 {
                    appState.setResearchInspectorVisible(false, animated: false)
                    appState.setNoteHistoryVisible(false, animated: false)
                }
                if targetSize.width < 980 {
                    appState.sidebarVisible = false
                }
            }

            let targetFrame = frame(
                forContentSize: targetSize,
                presentation: presentation,
                previousPresentation: previousPresentation,
                window: window
            )
            appliedPresentation = presentation
            if previousPresentation != nil, !reduceMotion {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.42
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    context.allowsImplicitAnimation = true
                    window.animator().setFrame(targetFrame, display: true)
                }
            } else {
                window.setFrame(targetFrame, display: true)
            }
            appState.windowWidth = targetSize.width
        }

        private func targetContentSize(
            for presentation: ScholiumWindowPresentation,
            window: NSWindow
        ) -> NSSize {
            let visibleSize = (window.screen ?? NSScreen.main)?.visibleFrame.size
                ?? NSSize(width: 1440, height: 900)
            let maximumWidth = max(presentation.minimumContentSize.width, visibleSize.width)
            let maximumHeight = max(presentation.minimumContentSize.height, visibleSize.height)

            let preferred: NSSize
            switch presentation {
            case .setup:
                preferred = NSSize(
                    width: ScholiumMetrics.Triptych.preferredWidth,
                    height: ScholiumMetrics.Triptych.preferredHeight
                )
            case .library:
                preferred = NSSize(
                    width: ScholiumMetrics.Triptych.preferredWidth,
                    height: ScholiumMetrics.Triptych.preferredHeight
                )
            case .document:
                preferred = preferredDocumentContentSize ?? NSSize(width: 1180, height: 760)
            }

            return NSSize(
                width: min(maximumWidth, max(presentation.minimumContentSize.width, preferred.width)),
                height: min(maximumHeight, max(presentation.minimumContentSize.height, preferred.height))
            )
        }

        private func frame(
            forContentSize contentSize: NSSize,
            presentation: ScholiumWindowPresentation,
            previousPresentation: ScholiumWindowPresentation?,
            window: NSWindow
        ) -> NSRect {
            let oldFrame = window.frame
            var target = window.frameRect(
                forContentRect: NSRect(origin: .zero, size: contentSize)
            )

            guard let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame else {
                target.origin = oldFrame.origin
                return target
            }

            switch presentation {
            case .setup, .library:
                // The Triptych Interface is a stable workflow anchor: one half
                // of its own width from the screen's leading edge and vertically
                // centered. Documents return to this exact origin when retracted.
                target.origin = NSPoint(
                    x: visibleFrame.minX + target.width / 2,
                    y: visibleFrame.midY - target.height / 2
                )
            case .document:
                if previousPresentation == .setup || previousPresentation == .library {
                    // Keep the Interface fixed while the document drawer grows
                    // to its trailing side.
                    target.origin = NSPoint(
                        x: oldFrame.minX,
                        y: oldFrame.midY - target.height / 2
                    )
                } else {
                    target.origin = NSPoint(
                        x: oldFrame.minX,
                        y: oldFrame.maxY - target.height
                    )
                }
            }

            if target.maxX > visibleFrame.maxX {
                target.origin.x = visibleFrame.maxX - target.width
            }
            if target.minX < visibleFrame.minX {
                target.origin.x = visibleFrame.minX
            }
            if target.minY < visibleFrame.minY {
                target.origin.y = visibleFrame.minY
            }
            if target.maxY > visibleFrame.maxY {
                target.origin.y = visibleFrame.maxY - target.height
            }
            return target
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
    @StateObject private var settingsModel: WorkspaceSettingsModel

    init(workspaceStore: WorkspaceStore) {
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
            .task {
                await settingsModel.restorePreferredWorkspaceIfNeeded()
            }
    }
}

private struct ScholiumWindowModelFocusedKey: FocusedValueKey {
    typealias Value = WindowModel
}

struct ScholiumSearchActions {
    let begin: (SearchPresentationScope) -> Void
}

struct ScholiumSearchActionsFocusedKey: FocusedValueKey {
    typealias Value = ScholiumSearchActions
}

struct ScholiumFocusedEditorActions {
    let isAvailable: (MarkdownEditorCommand) -> Bool
    let perform: (MarkdownEditorCommand) -> Void
    let performWithArgument: (MarkdownEditorCommand, String) -> Void
    let addComment: () -> Void
}

struct ScholiumFocusedEditorActionsKey: FocusedValueKey {
    typealias Value = ScholiumFocusedEditorActions
}

extension FocusedValues {
    var scholiumWindowModel: WindowModel? {
        get { self[ScholiumWindowModelFocusedKey.self] }
        set { self[ScholiumWindowModelFocusedKey.self] = newValue }
    }

    var scholiumSearchActions: ScholiumSearchActions? {
        get { self[ScholiumSearchActionsFocusedKey.self] }
        set { self[ScholiumSearchActionsFocusedKey.self] = newValue }
    }

    var scholiumEditorActions: ScholiumFocusedEditorActions? {
        get { self[ScholiumFocusedEditorActionsKey.self] }
        set { self[ScholiumFocusedEditorActionsKey.self] = newValue }
    }
}

struct RecentNoteDestination: Identifiable {
    let id: VaultQualifiedNoteID
    let reference: VaultNoteReference
    let title: String
}

@MainActor
private final class ScholiumWindowGroupingState: ObservableObject {
    static let shared = ScholiumWindowGroupingState()

    @Published private(set) var generation: UInt64 = 0

    func invalidate() {
        generation &+= 1
    }
}

@MainActor
private enum ScholiumWindowGrouping {
    static var canMerge: Bool {
        let windows = documentWindows
        guard windows.count > 1 else { return false }
        guard let first = windows.first else { return false }
        return windows.contains { window in
            guard window !== first else { return false }
            return first.tabGroup?.windows.contains(where: { $0 === window }) != true
        }
    }

    static var canMoveFocusedTabToNewWindow: Bool {
        guard let focusedDocumentWindow else { return false }
        return (focusedDocumentWindow.tabGroup?.windows.count ?? 0) > 1
    }

    static func merge() {
        let windows = documentWindows
        guard windows.count > 1 else { return }
        let primary = focusedDocumentWindow ?? windows[0]
        primary.tabbingMode = .automatic
        for window in windows where window !== primary {
            guard primary.tabGroup?.windows.contains(where: { $0 === window }) != true else {
                continue
            }
            window.tabbingMode = .automatic
            primary.addTabbedWindow(window, ordered: .above)
        }
        primary.tabGroup?.selectedWindow = primary
        primary.makeKeyAndOrderFront(nil)
        ScholiumWindowGroupingState.shared.invalidate()
        DispatchQueue.main.async {
            ScholiumWindowGroupingState.shared.invalidate()
        }
    }

    static func moveFocusedTabToNewWindow() {
        guard let focusedDocumentWindow,
              (focusedDocumentWindow.tabGroup?.windows.count ?? 0) > 1 else { return }
        focusedDocumentWindow.moveTabToNewWindow(nil)
        focusedDocumentWindow.tabbingMode = .disallowed
        focusedDocumentWindow.makeKeyAndOrderFront(nil)
        ScholiumWindowGroupingState.shared.invalidate()
        DispatchQueue.main.async {
            ScholiumWindowGroupingState.shared.invalidate()
        }
    }

    private static var focusedDocumentWindow: NSWindow? {
        let key = NSApplication.shared.keyWindow
        return isDocumentWindow(key) ? key : documentWindows.first
    }

    private static var documentWindows: [NSWindow] {
        NSApplication.shared.windows.filter(isDocumentWindow)
    }

    private static func isDocumentWindow(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return window.tabbingIdentifier == "scholium-main" && window.canBecomeKey
    }
}

private struct ScholiumCommands: Commands {
    @ObservedObject private var windowGroupingState = ScholiumWindowGroupingState.shared
    @FocusedValue(\.scholiumWindowModel) private var appState
    @FocusedValue(\.scholiumSearchActions) private var searchActions
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
            Button("Paste as Markdown") {
                guard let payload = markdownPasteboardPayload() else { return }
                editorActions?.performWithArgument(.pasteMarkdown, payload)
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .disabled(editorActions?.isAvailable(.pasteMarkdown) != true)
            Divider()
            Button("Search This Note…") {
                searchActions?.begin(.thisNote)
            }
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(searchActions == nil)
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
                .disabled(editorActions == nil)
        }
        CommandGroup(replacing: .sidebar) {
            Button("Collapse Note") {
                appState?.requestCollapseNote()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(appState?.currentNote == nil)
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
            Menu("Document Text Size") {
                Button("Increase Text Size") { appState?.adjustDocumentTextScale(by: 0.1) }
                    .keyboardShortcut("=", modifiers: [.command])
                    .disabled(appState?.currentNote == nil || appState?.documentTextScale == 2.0)
                Button("Decrease Text Size") { appState?.adjustDocumentTextScale(by: -0.1) }
                    .keyboardShortcut("-", modifiers: [.command])
                    .disabled(appState?.currentNote == nil || appState?.documentTextScale == 1.0)
                Button("Actual Size (100%)") { appState?.resetDocumentTextScale() }
                    .keyboardShortcut("0", modifiers: [.command])
                    .disabled(appState?.currentNote == nil || appState?.documentTextScale == 1.0)
                Divider()
                Button("150%") { appState?.setDocumentTextScale(1.5) }
                    .disabled(appState?.currentNote == nil || appState?.documentTextScale == 1.5)
                Button("200%") { appState?.setDocumentTextScale(2.0) }
                    .disabled(appState?.currentNote == nil || appState?.documentTextScale == 2.0)
            }
            .disabled(appState?.currentNote == nil)
            Menu("Appearance") {
                Button("Use System Appearance") { appState?.colorScheme = .system }
                Button("Light") { appState?.colorScheme = .light }
                Button("Dark") { appState?.colorScheme = .dark }
            }
        }
        CommandGroup(before: .windowList) {
            Button("Merge Scholium Windows") {
                ScholiumWindowGrouping.merge()
            }
            .disabled(!canMergeScholiumWindows)
            Button("Move Scholium Tab to New Window") {
                ScholiumWindowGrouping.moveFocusedTabToNewWindow()
            }
            .disabled(!canMoveFocusedScholiumTabToNewWindow)
            Divider()
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
            Button("Search Triptych…") { searchActions?.begin(.triptych) }
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

    private var recentNotes: [RecentNoteDestination] {
        appState?.recentNoteDestinations ?? []
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

    private func recentNoteCommandLabel(_ destination: RecentNoteDestination) -> String {
        let matchingTitles = recentNotes.count { candidate in
            candidate.title.localizedCaseInsensitiveCompare(destination.title) == .orderedSame
        }
        let role = destination.reference.vaultRole.displayName
        if matchingTitles > 1 {
            return "\(destination.title) — \(role) — \(destination.reference.relativePath)"
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

    private var canMergeScholiumWindows: Bool {
        _ = windowGroupingState.generation
        return ScholiumWindowGrouping.canMerge
    }

    private var canMoveFocusedScholiumTabToNewWindow: Bool {
        _ = windowGroupingState.generation
        return ScholiumWindowGrouping.canMoveFocusedTabToNewWindow
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
    @Published var notes: [WindowDocumentLocation] = []
    @Published private(set) var lifecycleMutationGeneration: UInt64 = 0
    @Published var openTabs: [String] = []
    @Published var activeTab: String?
    @Published var documentModes: [String: String] = [:]
    @Published var documentScrollPositions: [String: Double] = [:]
    @Published var sidebarVisible = true
    // Keep the document primary on a fresh window. The trailing inspector is
    // always one toolbar/menu action away and restores only when a window
    // explicitly persisted it as visible.
    @Published var windowWidth: CGFloat = 1380
    @Published private(set) var hasCompletedInitialRestore = false
    @Published var toastMessage: Toast?
    @Published var colorScheme: ColorSchemeChoice = .system {
        didSet {
            UserDefaults.standard.set(colorScheme.rawValue, forKey: "colorScheme")
        }
    }
    @Published var allTags: [String] = []
    @Published var savedSearches: [SavedSearch] = []
    @Published var documentTextScale: Double = 1.0
    @Published var pendingSourceLine: Int?
    @Published var documentRevisions: [String: DocumentFingerprint] = [:]
    @Published var lastSaveError: String?
    @Published var changedSinceReviewPaths: Set<String> = []
    @Published var requestPresentationMode: NotePresentationMode?
    @Published var pendingCommentSelection: MarkdownReviewSelection?
    @Published var focusedResearcherCommentID: UUID?
    @Published var humanReviewRecords: [String: HumanReviewRecord] = [:]
    @Published var noteIdentityByPath: [String: UUID] = [:]
    @Published var identityAmbiguities: [NoteIdentityAmbiguity] = []
    @Published var pendingIdentityRebindings: [NoteIdentityPendingRebinding] = []
    @Published var identityMigrationFailures: [NoteIdentityMigrationFailure] = []
    @Published var isResolvingIdentity = false
    @Published var identityResolutionError: String?
    @Published var triptychSettings = TriptychSettings()
    @Published var dialogueInitialNotes: Set<VaultQualifiedNoteID> = []
    @Published var checkpointListingError: String?
    @Published var workspaceAssignment: ThreeVaultWorkspaceAssignment?
    @Published var registeredTriptychs: [TriptychAssignment] = []
    @Published var workspaceRecoveryMessage: String?
    @Published var workspaceCatalog: WorkspaceCatalogSnapshot?
    @Published var isRefreshingWorkspaceCatalog = false
    @Published var refreshStatusText: String?
    @Published private(set) var derivedRefreshStatus: WorkspaceDerivedRefreshStatus?
    @Published var workspaceCatalogError: String?
    @Published var registeredVaults: [RegisteredVault] = []
    @Published var transactionRecoveryRecords: [TriptychMutationRecoveryRecord] = []
    @Published var transactionRecoveryError: String?
    @Published var windowSessionPersistenceError: String?
    let presentationRouter = WindowPresentationRouter()
    lazy var discoveryController = DiscoveryController { [weak self] intent in
        self?.handleWindowIntent(intent)
    }
    lazy var documentController = DocumentController { [weak self] intent in
        self?.handleWindowIntent(intent)
    }
    lazy var researchController = ResearchController { [weak self] intent in
        self?.handleWindowIntent(intent)
    }

    // Compatibility projections while Library leaves still consume WindowModel
    // values. DiscoveryController is the sole mutable owner.
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

    var scholiaSection: ScholiaSection {
        get { researchController.scholia.section }
        set { researchController.selectScholiaSection(newValue) }
    }

    var inspectorModeRaw: String {
        get { researchController.inspector.modeRawValue }
        set { researchController.selectInspectorMode(newValue) }
    }

    var backlinksVisible: Bool {
        get { researchController.inspector.showsResearchInspector }
        set { researchController.showResearchInspector(newValue) }
    }

    var noteHistoryVisible: Bool {
        get { researchController.inspector.showsNoteHistory }
        set { researchController.showNoteHistory(newValue) }
    }

    var advancedSearchState: SearchWorkspaceState {
        get { discoveryController.search.criteria }
        set { discoveryController.replaceSearchCriteria(newValue) }
    }

    var advancedSearchHits: [SearchHit] {
        discoveryController.search.hits
    }

    var relatedSearchItems: [RelatedSearchItem] {
        discoveryController.search.relatedItems
    }

    var advancedSearchError: String? {
        discoveryController.search.errorMessage
    }

    var isSearchRunning: Bool {
        discoveryController.search.isRunning
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

    var showQuickOpen: Bool {
        get {
            guard case .quickOpen = presentationRouter.sheet else { return false }
            return true
        }
        set {
            if newValue {
                presentationRouter.present(.quickOpen)
            } else {
                presentationRouter.dismissSheet(if: "quick-open")
            }
        }
    }

    var showSearchSurface: Bool {
        get { presentationRouter.presentsOverlay(.search) }
        set { presentationRouter.setOverlay(.search, isPresented: newValue) }
    }

    var editingNotePath: String? {
        get {
            guard case .frontmatter(let path) = presentationRouter.sheet else { return nil }
            return path
        }
        set {
            if let newValue {
                presentationRouter.present(.frontmatter(path: newValue))
            } else if case .frontmatter = presentationRouter.sheet {
                presentationRouter.dismissSheet()
            }
        }
    }

    var showFrontmatterEditor: Bool {
        get { editingNotePath != nil }
        set {
            if newValue, let path = editingNotePath ?? currentNote?.relativePath {
                presentationRouter.present(.frontmatter(path: path))
            } else if !newValue, case .frontmatter = presentationRouter.sheet {
                presentationRouter.dismissSheet()
            }
        }
    }

    var vaultError: String? {
        get { presentationRouter.alert?.message }
        set { presentationRouter.alert = newValue.map(WindowAlertRoute.actionFailure) }
    }

    var qualityReviewPath: String? {
        get {
            guard case .qualityReview(let path) = presentationRouter.sheet else { return nil }
            return path
        }
        set {
            if let newValue {
                presentationRouter.present(.qualityReview(path: newValue))
            } else if case .qualityReview = presentationRouter.sheet {
                presentationRouter.dismissSheet()
            }
        }
    }

    var showQualityReview: Bool {
        get { qualityReviewPath != nil }
        set {
            if newValue, let path = qualityReviewPath ?? currentNote?.relativePath {
                presentationRouter.present(.qualityReview(path: path))
            } else if !newValue, case .qualityReview = presentationRouter.sheet {
                presentationRouter.dismissSheet()
            }
        }
    }

    var researcherCommentsPath: String? {
        get {
            guard case .researcherComments(let path) = presentationRouter.sheet else { return nil }
            return path
        }
        set {
            if let newValue {
                presentationRouter.present(.researcherComments(path: newValue))
            } else if case .researcherComments = presentationRouter.sheet {
                presentationRouter.dismissSheet()
            }
        }
    }

    var showResearcherComments: Bool {
        get { researcherCommentsPath != nil }
        set {
            if newValue, let path = researcherCommentsPath ?? currentNote?.relativePath {
                presentationRouter.present(.researcherComments(path: path))
            } else if !newValue, case .researcherComments = presentationRouter.sheet {
                presentationRouter.dismissSheet()
            }
        }
    }

    var showScholia: Bool {
        get {
            guard case .scholia = presentationRouter.sheet else { return false }
            return true
        }
        set {
            if newValue, let path = currentNote?.relativePath {
                researchController.beginScholiaPresentation(
                    id: UUID(),
                    section: researchController.scholia.section
                )
                presentationRouter.present(.scholia(path: path))
            } else if !newValue, case .scholia = presentationRouter.sheet {
                presentationRouter.dismissSheet()
            }
        }
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

    var pendingCritiquePath: String? {
        get {
            guard case .critique(let path) = presentationRouter.sheet else { return nil }
            return path
        }
        set {
            if let newValue {
                presentationRouter.present(.critique(path: newValue))
            } else if case .critique = presentationRouter.sheet {
                presentationRouter.dismissSheet()
            }
        }
    }

    var showWorkspaceSetup: Bool {
        get {
            guard case .workspaceSetup = presentationRouter.sheet else { return false }
            return true
        }
        set {
            presentationRouter.setWorkspaceSetupPresented(
                newValue,
                rootSetupOwnsPresentation: vaultConfig == nil
            )
        }
    }

    var showAttentionQueues: Bool {
        get {
            guard case .attention = presentationRouter.sheet else { return false }
            return true
        }
        set {
            if newValue {
                presentationRouter.present(.attention)
            } else {
                presentationRouter.dismissSheet(if: "attention")
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
    private let requestedTriptychID: UUID?
    private let createsTriptych: Bool
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
    private var workspaceCatalogRefreshTask: Task<Void, Never>?
    private var workspaceCatalogNeedsAnotherRefresh = false
    private var isRestoringWindowSession = false
    private var didRestoreWindowSession = false
    private var transitionGeneration: UInt64 = 0
    private var identityReviewRefreshGeneration: UInt64 = 0
    private var transitionTail: Task<Void, Never>?
    private var savedSearchMutationTail: Task<Void, Never>?

    init(
        workspaceStore: WorkspaceStore,
        requestedTriptychID: UUID? = nil,
        createsTriptych: Bool = false
    ) {
        self.workspaceStore = workspaceStore
        self.requestedTriptychID = requestedTriptychID
        self.createsTriptych = createsTriptych
        cssSnippetStore = workspaceStore.cssSnippetStore
        zoteroBridge = workspaceStore.zoteroBridge
        presentationRouter.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &workspaceCancellables)
        discoveryController.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &workspaceCancellables)
        researchController.objectWillChange
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

    // MARK: Computed Properties
    var currentNote: WindowDocumentLocation? {
        guard let tab = activeTab else { return nil }
        return notes.first { $0.relativePath == tab }
    }

    var layoutMode: LayoutMode { LayoutMode(windowWidth: windowWidth) }
    var usesCompactWindowLayout: Bool { layoutMode == .compact }
    var usesWideWindowLayout: Bool { layoutMode == .wide }

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
        guard noteLocationScope == .workspace,
              currentVaultRole.allowsHumanReview,
              let path = currentNote?.relativePath else { return false }
        return noteIdentityByPath[path] != nil
    }

    var canCommentCurrentNote: Bool {
        guard noteLocationScope == .workspace,
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
        await refreshIdentityAndReviewState()
    }

    @discardableResult
    private func requireResolvedIdentity(for path: String) throws -> UUID? {
        if noteLocationScope == .unclassified { return nil }
        guard let noteID = noteIdentityByPath[path] else {
            throw NoteIdentityRecoveryError.identityUnresolved(path)
        }
        return noteID
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

    /// Opens the single workspace Search surface with an explicit scope.
    /// Quick Open remains a separate Triptych-wide title/path/alias command.
    func beginSearch(mode: SearchPresentationScope) {
        advancedSearchState.scope = mode.canonical
        showSearchSurface = true
        Task { await refreshAdvancedSearch() }
    }

    /// The only cross-feature routing boundary. Feature controllers emit a
    /// closed intent and never reach into a peer controller's mutable state.
    private func handleWindowIntent(_ intent: WindowIntent) {
        switch intent {
        case .openDocument(let route):
            Task { [weak self] in
                await self?.openWorkspaceReference(
                    route.reference,
                    line: route.sourceLocator?.line,
                    mode: route.sourceLocator == nil ? .read : .source,
                    inNewTab: route.opensInNewTab
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
                    try await self.openRegisteredVault(vault)
                } catch {
                    self.vaultError = error.localizedDescription
                }
            }
        case .presentScholia(let route):
            Task { [weak self] in
                guard let self else { return }
                await self.openWorkspaceReference(route.reference)
                self.openScholia(section: route.section)
            }
        case .presentLifecycle(let request):
            noteLifecycleRequest = request
        }
    }

    func requestOpenNote(_ path: String, inNewTab: Bool = false) {
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
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
            self.requestPresentationMode = mode
        }
    }

    func requestSelectTab(_ path: String) {
        guard path != activeTab else { return }
        enqueueDocumentTransition { [weak self] in
            guard let self, self.openTabs.contains(path) else { return }
            self.activeTab = path
            if let key = self.documentSessionKey(for: path) {
                self.documentController.activateDocument(key)
            }
            self.recordNavigationVisit(path)
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

    /// Retracts the active document into the Triptych Interface without
    /// discarding its open-tab session. Selecting that note reveals it again.
    func requestCollapseNote() {
        guard activeTab != nil else { return }
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            self.activeTab = nil
            self.sidebarVisible = true
            self.setResearchInspectorVisible(false, animated: false)
            self.setNoteHistoryVisible(false, animated: false)
            self.persistWindowSessionNow()
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
            noteID: noteID
        )
        try await refreshNoteLocationScope()
        if noteLocationScope == .workspace { openNote(destination) }
        scheduleWorkspaceCatalogRefresh()
    }

    func requestDocumentMode(_ mode: NotePresentationMode) {
        guard mode == .read || canEditCurrentNote else {
            showToast("This note is read-only in Scholium.", kind: .information)
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
        guard currentNote != nil else { return }
        scholiaSection = section
        showScholia = true
    }

    func requestOpenScholia(for path: String, section: ScholiaSection = .comments) {
        guard notes.contains(where: { $0.relativePath == path }) else { return }
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            self.openNote(path, inNewTab: false)
            self.scholiaSection = section
            self.showScholia = true
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

    var availablePropertyKeys: [String] {
        availablePropertyFilterOptions.keys
    }

    func availablePropertyValues(for key: String) -> [String] {
        availablePropertyFilterOptions.valuesByKey[key] ?? []
    }

    var availablePropertyFilterOptions: WindowPropertyFilterOptions {
        WindowPropertyFilterOptions(notes: notesInCurrentScope)
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

    /// Chronological Back/Forward visits across all three peer vaults.
    /// A relative path is never sufficient here because identical paths may
    /// legitimately exist in Analyses, Topics, and Works.
    @Published var navigationStack: [VaultQualifiedNoteID] = []
    @Published var navigationIndex: Int = -1
    @Published var recentNotesHistory = WindowRecentNotes()

    /// Menu-ready destinations remain routable from registered vault identity
    /// and relative paths even while the derived workspace catalog refreshes.
    var recentNoteDestinations: [RecentNoteDestination] {
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
            if visible, !self.usesWideWindowLayout, self.currentNote != nil {
                self.presentationRouter.present(.adaptiveContext)
            } else if !visible,
                      case .adaptiveContext = self.presentationRouter.sheet,
                      !self.noteHistoryVisible {
                self.presentationRouter.dismissSheet()
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
            if visible, !self.usesWideWindowLayout, self.currentNote != nil {
                self.presentationRouter.present(.adaptiveContext)
            } else if !visible,
                      case .adaptiveContext = self.presentationRouter.sheet,
                      !self.backlinksVisible {
                self.presentationRouter.dismissSheet()
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
            hasCompletedInitialRestore = true
            persistWindowSessionNow()
        }

        let stored: WindowSessionSnapshot?
        do {
            stored = try await workspaceStore.windowSession(id: id)
        } catch {
            showToast("The saved window layout could not be restored. Scholium opened a clean window instead.", kind: .warning)
            stored = nil
        }
        guard let stored else {
            await restoreWorkspaceIfNeeded()
            return
        }

        restoreQualifiedSessionState(from: stored)

        await refreshRegisteredVaults()
        await refreshWorkspaceAssignment(
            preferredTriptychID: requestedTriptychID ?? stored.triptychID
        )
        guard let restoredAssignment = workspaceAssignment else {
            attemptedVaultRestore = true
            showWorkspaceSetup = true
            return
        }
        restrictSessionState(to: restoredAssignment)

        do {
            if let vaultID = stored.vaultID,
               let vault = restoredAssignment.vaults.values.first(where: { $0.id == vaultID }) {
                attemptedVaultRestore = true
                try await openRegisteredVault(vault)
            } else {
                await restoreWorkspaceIfNeeded()
            }
        } catch {
            vaultError = error.localizedDescription
            showWorkspaceSetup = true
            return
        }

        inspectorModeRaw = stored.inspectorMode
        // A compact or medium window keeps the inspector available through its
        // toolbar/menu route, but must not restore it as an immediately blocking
        // sheet over the document. Wide windows can safely restore the trailing
        // inspector in place.
        backlinksVisible = usesWideWindowLayout && (stored.inspectorVisible ?? false)
        advancedSearchState = stored.searchState
        advancedSearchState.scope = advancedSearchState.scope.canonical
        documentTextScale = min(2.0, max(1.0, stored.documentTextScale ?? 1.0))
        _ = stored.contentDestination
    }

    func persistWindowSessionNow() {
        guard didRestoreWindowSession, !isRestoringWindowSession else { return }
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
            contentDestination: .document,
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
        // Publish the document's presentation state before activating its tab.
        // NoteContentView reads the restored mode in onAppear; publishing the
        // tab first can construct the view while the mode is still `.read`.
        openTabs = restored.openTabs
        documentModes = restored.documentModes
        documentScrollPositions = restored.scrollPositions
        activeTab = restored.activeTab
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
            researchController.$inspector.map { _ in () }.eraseToAnyPublisher(),
            discoveryController.$search.map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(changes)
            .dropFirst(changes.count)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] in self?.persistWindowSessionNow() }
            .store(in: &workspaceCancellables)
    }

    func adjustDocumentTextScale(by delta: Double) {
        setDocumentTextScale(documentTextScale + delta)
    }

    func setDocumentTextScale(_ requestedScale: Double) {
        let adjusted = min(2.0, max(1.0, requestedScale))
        documentTextScale = (adjusted * 10).rounded() / 10
    }

    func resetDocumentTextScale() {
        documentTextScale = 1.0
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
                if !createsTriptych {
                    workspaceRecoveryMessage = "This Triptych is no longer registered on this Mac. Open an existing Triptych or choose its three folders again."
                }
                return
            }
        } else if createsTriptych {
            stored = nil
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

    var isCreatingNewTriptych: Bool {
        createsTriptych && workspaceAssignment == nil
    }

    private func activateTriptychServices(
        assignment: ThreeVaultWorkspaceAssignment
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
            },
            saveErrorDidChange: { [weak self] message in
                self?.lastSaveError = message
            }
        )
        researchController.bind(to: capabilities.research, snapshot: snapshot)
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
        guard let vaultID = currentRegisteredVault?.id else { return [] }
        return try await researchController.noteCheckpoints(for: VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: path
        ))
    }

    func noteCheckpointContent(_ checkpointID: UUID, path: String) async throws -> String {
        guard let vaultID = currentRegisteredVault?.id else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return try await researchController.checkpointNoteContent(
            checkpointID,
            note: VaultQualifiedNoteID(vaultID: vaultID, relativePath: path)
        )
    }

    func restoreNote(_ path: String, from checkpointID: UUID) async throws {
        guard let vaultID = currentRegisteredVault?.id,
              let revision = documentRevisions[path],
              let assignment = workspaceAssignment else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        try await workspaceStore.flushEditors(in: assignment.id)
        _ = try await researchController.restoreNote(
            VaultQualifiedNoteID(vaultID: vaultID, relativePath: path),
            from: checkpointID,
            expectedRevision: revision
        )
        try await refreshNoteLocationScope()
    }

    func dialogueHistory(for path: String) async -> [DialogueEntry] {
        guard let noteID = noteIdentityByPath[path] else { return [] }
        return (try? await researchController.dialogueHistory(noteID: noteID)) ?? []
    }

    @discardableResult
    func recordDialogueReply(
        entryID: UUID,
        agentName: String,
        text: String,
        noteID: UUID? = nil,
        commentID: UUID? = nil
    ) async throws -> DialogueEntry {
        try await researchController.appendDialogueReply(
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
        try await researchController.appendDialogueFollowUpComment(
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
        return try? await researchController.critique(workNoteID: noteID)
    }

    func critiqueAssociation(forCritiquePath path: String) async -> CritiqueAssociation? {
        guard currentVaultRole.allowsCritique else { return nil }
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
              let target = notes.first(where: { $0.relativePath == path }) else { return }
        let document = NoteDocument(relativePath: path, rawContent: target.rawContent)
        if let line = finding.resolvedTargetLine(in: document) {
            requestOpenNote(path, sourceLine: line)
        } else {
            requestOpenNote(path)
        }
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

    func dialogueCandidates() async throws -> [DialogueNoteReference] {
        var result: [DialogueNoteReference] = []
        for vault in try await documentController.workspaceSnapshots() {
            for snapshot in vault.documents where snapshot.lifecycle == .active {
                guard let noteID = snapshot.stableIdentity.resolvedID else { continue }
                let document = snapshot.document
                let title = document.parsedFrontmatter["title"]?.scalarString
                    ?? (document.relativePath as NSString).lastPathComponent
                        .replacingOccurrences(of: ".md", with: "")
                result.append(DialogueNoteReference(
                    noteID: noteID,
                    vaultID: vault.vault.id,
                    vaultName: vault.slot.displayName,
                    title: title,
                    relativePath: document.relativePath,
                    fingerprint: document.fingerprint,
                    kind: vault.slot == .output
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
        anchor: ResearcherCommentAnchor?
    ) async throws -> HumanReviewRecord {
        let context = try researcherCommentContext(for: path)
        let record = try await researchController.addComment(
            to: VaultQualifiedNoteID(vaultID: context.vaultID, relativePath: path),
            text: text,
            anchor: anchor,
            expectedRevision: context.fingerprint
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
        let record = try await researchController.updateComment(
            noteID: context.noteID,
            commentID: commentID,
            text: text
        )
        humanReviewRecords[path] = record
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
        humanReviewRecords[path] = record
    }

    func deleteResearcherComment(at path: String, commentID: UUID) async throws {
        let context = try researcherCommentContext(for: path)
        humanReviewRecords[path] = try await researchController.deleteComment(
            noteID: context.noteID,
            commentID: commentID
        )
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
        humanReviewRecords[path] = record
    }

    @discardableResult
    func tryReattachingResearcherComments(at path: String) async throws -> HumanReviewRecord {
        let context = try researcherCommentContext(for: path)
        let record = try await researchController.reattachComments(
            to: VaultQualifiedNoteID(vaultID: context.vaultID, relativePath: path),
            expectedRevision: context.fingerprint
        )
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
        requestedDestination: String? = nil,
        responseProfile: DialogueResponseProfile? = nil
    ) async throws -> DialogueEntry {
        guard let assignment = workspaceAssignment else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        try await workspaceStore.flushEditors(in: assignment.id)
        let preparation = try await researchController.createDialogue(
            instruction: instruction,
            selectedNotes: selectedNotes,
            includedCommentIDs: includedCommentIDs,
            requestedDestination: requestedDestination,
            responseProfile: responseProfile
        )
        try copyTextToClipboard(
            preparation.instructions,
            recovery: "The Dialogue was saved in Note History. Reopen Dialogue to prepare new transport instructions."
        )
        return preparation.entry
    }

    func copyTextToClipboard(_ text: String, recovery: String? = nil) throws {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else {
            throw ClipboardWorkflowError.copyFailed(recovery: recovery)
        }
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
              let assignment = workspaceAssignment,
              let vaultID = currentRegisteredVault?.id,
              noteIdentityByPath[path] != nil,
              notes.contains(where: { $0.relativePath == path }) else {
            throw HumanReviewWorkflowError.unavailableForOutput
        }
        try await workspaceStore.flushEditors(in: assignment.id)
        let workID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: path)
        let document = try await documentController.load(workID)
        let preparation = try await researchController.requestCritique(
            for: workID,
            expectedRevision: document.fingerprint,
            scope: scope,
            lens: lens,
            selectedRanges: selectedRanges,
            additionalInstructions: additionalInstructions
        )
        try copyTextToClipboard(
            preparation.instructions,
            recovery: "The Critique request was saved. Reopen Request Critique to copy its prompt again."
        )
        do {
            try await rescanVault()
        } catch {
            refreshStatusText = "Derived refresh failed"
            workspaceCatalogError = error.localizedDescription
        }
        return preparation.association
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
            guard let vaultSnapshot = try await documentController.workspaceSnapshot(
                vaultID: registered.id
            ) else {
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

            captureCurrentVaultPresentation()
            resetWindowSession()

            currentRegisteredVault = registered
            currentVaultRole = registered.role
            activeTriptychServicesID = assignment.id
            activeWorkspaceCapabilities = capabilities
            vaultConfig = targetConfig
            notes = targetNotes
            restoreVaultPresentation(
                vaultID: registered.id,
                availablePaths: Set(targetNotes.map(\.relativePath))
            )
            refreshDocumentRevisions()
            await refreshIdentityAndReviewState()
            synchronizeDocumentControllerPresentation()
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
        if let fixtureRoot = ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_WORKSPACE_ROOT"] {
            let root = URL(fileURLWithPath: fixtureRoot, isDirectory: true)
            do {
                try await configureThreeVaultWorkspace(
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
            showWorkspaceSetup = true
            return
        }

        do {
            try await openWorkspaceVault(.paperAnalysis)
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

    func refreshWindowProjection(
        incrementalPaths: Set<String>? = nil,
        deletedPaths: Set<String> = []
    ) async {
        // `WorkspaceStore` publishes the authoritative per-vault index and
        // Triptych graph. Keep this method as a window projection refresh for
        // existing callers; it must not create a second graph or index.
        _ = incrementalPaths
        _ = deletedPaths
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
            synchronizeDocumentControllerPresentation()
            await refreshWindowProjection()
        } catch {
            showToast("Could not open \(scope.rawValue): \(error.localizedDescription)", kind: .error)
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
        researchUnitScope: String? = nil,
        researchUnitLimitations: [String] = []
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
            researchUnitScope: researchUnitScope,
            researchUnitLimitations: researchUnitLimitations
        ))
        try await refreshNoteLocationScope()
        openNote(document.relativePath)
        return document
    }

    @discardableResult
    func duplicateNote(_ sourcePath: String, to requestedPath: String) async throws -> NoteDocument {
        try await flushRegisteredEditorIfNeeded()
        try requireResolvedIdentity(for: sourcePath)
        guard noteLocationScope == .workspace,
              let vaultID = currentRegisteredVault?.id,
              let expected = documentRevisions[sourcePath] else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let destination = Self.markdownPath(requestedPath)
        let document = try await documentController.duplicate(
            VaultQualifiedNoteID(vaultID: vaultID, relativePath: sourcePath),
            to: destination,
            expectedRevision: expected
        )
        try await refreshNoteLocationScope()
        openNote(destination)
        return document
    }

    func moveNote(_ sourcePath: String, to requestedPath: String) async throws {
        try await flushRegisteredEditorIfNeeded()
        guard let noteID = try requireResolvedIdentity(for: sourcePath) else {
            throw NoteIdentityRecoveryError.identityUnresolved(sourcePath)
        }
        guard let vaultID = currentRegisteredVault?.id,
              let expected = documentRevisions[sourcePath] else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let requestedDestination = Self.markdownPath(requestedPath)
        let sourceID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: sourcePath)
        let commit: TriptychMoveCommit
        do {
            commit = try await documentController.move(
                sourceID,
                to: requestedDestination,
                expectedRevision: expected
            )
        } catch {
            await refreshTransactionRecoveryRecords()
            throw error
        }
        let destination = commit.destination.relativePath
        migrateAppOwnedState(
            sourcePath: sourcePath,
            destinationPath: destination,
            noteID: noteID
        )
        try await refreshNoteLocationScope()
        if noteLocationScope == .workspace { openNote(destination) }
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
            noteID: noteID
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
            noteID: noteID
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
        showToast("Classified as \(slot.displayName): \(destination)")
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
        noteID: UUID
    ) {
        // The application handle has already committed the portable identity
        // move and resumed any dependent record migrations. This method only
        // projects that successful commit into window-local presentation.
        migrateInMemoryPath(
            from: sourcePath,
            to: destinationPath,
            noteID: noteID,
            identityResolved: true
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

    func refreshAdvancedSearch() async {
        let state = advancedSearchState
        do {
            let currentNoteID: VaultQualifiedNoteID? = if let vault = currentRegisteredVault,
                                                          let note = currentNote {
                VaultQualifiedNoteID(vaultID: vault.id, relativePath: note.relativePath)
            } else {
                nil
            }
            try await discoveryController.executeSearch(
                state,
                context: DiscoverySearchExecutionContext(
                    workspaceIsAvailable: workspaceAssignment != nil,
                    currentNote: currentNoteID,
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
                try await self.workspaceStore.saveSavedSearches(proposed)
                guard !Task.isCancelled else { return }
                self.savedSearches = proposed
            } catch {
                self.showToast("Could not save search: \(error.localizedDescription)", kind: .error)
            }
        }
    }

    func openNote(_ path: String, inNewTab: Bool = false) {
        guard notes.contains(where: { $0.relativePath == path }) else {
            showToast("Note not found: \(path)", kind: .warning)
            return
        }
        PerformanceProbe.shared.beginReadActivation(documentID: path)
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
        if let descriptor = documentDescriptor(for: path) {
            documentController.installOpenedDocument(
                descriptor,
                inNewTab: inNewTab
            )
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
        if let key = documentSessionKey(for: path) {
            documentController.closeDocument(key)
        }
        openTabs.removeAll { $0 == path }
        if activeTab == path { activeTab = openTabs.last }
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

    private func synchronizeDocumentControllerPresentation() {
        documentController.removeAll()
        for path in openTabs {
            guard let descriptor = documentDescriptor(for: path) else { continue }
            documentController.installOpenedDocument(
                descriptor,
                inNewTab: true
            )
        }
        if let activeTab,
           let key = documentSessionKey(for: activeTab) {
            documentController.activateDocument(key)
        }
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
              noteIdentityByPath[path] != nil else {
            throw HumanReviewWorkflowError.unavailableForOutput
        }
        guard documentRevisions[path] == fingerprint else {
            throw HumanReviewWorkflowError.staleRevision
        }
        let record = try await researchController.saveHumanReviewDraft(
            for: VaultQualifiedNoteID(vaultID: vault.id, relativePath: path),
            expectedRevision: fingerprint,
            qualification: qualification,
            reviewNote: reviewNote
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
              noteIdentityByPath[path] != nil else {
            throw HumanReviewWorkflowError.unavailableForOutput
        }
        guard documentRevisions[path] == fingerprint else {
            throw HumanReviewWorkflowError.staleRevision
        }
        let record = try await researchController.completeHumanReview(
            for: VaultQualifiedNoteID(vaultID: vault.id, relativePath: path),
            expectedRevision: fingerprint,
            qualification: qualification,
            reviewNote: reviewNote
        )
        humanReviewRecords[path] = record
        changedSinceReviewPaths.remove(path)
        if let snapshot = try? await documentController.noteSnapshot(
            VaultQualifiedNoteID(vaultID: vault.id, relativePath: path)
        ), let index = notes.firstIndex(where: { $0.relativePath == path }) {
            notes[index] = .workspace(snapshot)
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
        mode: NotePresentationMode = .source,
        inNewTab: Bool = false
    ) async {
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            if self.currentRegisteredVault?.id != reference.vaultID {
                let vault = try await self.workspaceStore.resolveVault(reference.vaultID.uuidString)
                try await self.openRegisteredVault(vault)
            }
            guard self.notes.contains(where: { $0.relativePath == reference.relativePath }) else {
                self.showToast(
                    "The linked note is no longer present at \(reference.relativePath).",
                    kind: .warning
                )
                return
            }
            self.openNote(reference.relativePath, inNewTab: inNewTab)
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
    func saveProperties(
        for note: WindowDocumentLocation,
        proposedFrontmatter: [String: YAMLValue],
        expectedRevision: DocumentFingerprint,
        researchUnitEdit: ResearchUnitEdit? = nil
    ) async throws -> WindowDocumentLocation {
        try requireResolvedIdentity(for: note.relativePath)
        guard let vaultID = currentRegisteredVault?.id else {
            throw VaultRepositoryError.fileDoesNotExist(note.relativePath)
        }
        guard let original = notes.first(where: { $0.relativePath == note.relativePath }) else {
            throw VaultRepositoryError.fileDoesNotExist(note.relativePath)
        }

        var edits = PropertyEditorModel.frontmatterEdits(
            from: original.frontmatter,
            to: proposedFrontmatter
        )
        if let researchUnitEdit {
            edits["research_unit"] = researchUnitEdit.coreValue
        }
        do {
            let result = try await documentController.save(
                VaultQualifiedNoteID(vaultID: vaultID, relativePath: note.relativePath),
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

    @discardableResult
    func saveBody(_ body: String, for path: String, expectedRevision: DocumentFingerprint) async throws -> WindowDocumentLocation {
        try requireResolvedIdentity(for: path)
        guard notes.contains(where: { $0.relativePath == path }),
              let vaultID = currentRegisteredVault?.id else {
            throw VaultRepositoryError.fileDoesNotExist(path)
        }
        do {
            let result = try await documentController.save(
                VaultQualifiedNoteID(vaultID: vaultID, relativePath: path),
                changeSet: .body(body),
                expectedRevision: expectedRevision
            )
            lastSaveError = nil
            return await replaceSavedDocument(result.document)
        } catch {
            lastSaveError = error.localizedDescription
            throw error
        }
    }

    func diskDocument(for path: String) async throws -> NoteDocument {
        if noteLocationScope == .unclassified {
            return try await documentController.loadUnclassified(relativePath: path)
        }
        guard let vaultID = currentRegisteredVault?.id else {
            throw VaultRepositoryError.fileDoesNotExist(path)
        }
        return try await documentController.load(
            VaultQualifiedNoteID(vaultID: vaultID, relativePath: path)
        )
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
        let storedReviewRecords: [UUID: HumanReviewRecord]
        do {
            let snapshot = try await researchController.researchSnapshot()
            storedReviewRecords = Dictionary(
                snapshot.humanReviews.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        } catch {
            storedReviewRecords = [:]
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
                   guard let anchor = $0.anchor else { return false }
                   return anchor.fingerprint != fingerprint
               }) == true {
                guard refreshGeneration == identityReviewRefreshGeneration else { return }
                do {
                    record = try await researchController.reattachComments(
                        to: VaultQualifiedNoteID(vaultID: vault.id, relativePath: path),
                        expectedRevision: fingerprint
                    )
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
        if let vaultSnapshot = try? await documentController.workspaceSnapshot(vaultID: vault.id) {
            let snapshots = Dictionary(
                uniqueKeysWithValues: vaultSnapshot.documents.map { ($0.id.relativePath, $0) }
            )
            notes = notes.map { location in
                snapshots[location.relativePath].map(WindowDocumentLocation.workspace) ?? location
            }
        }
        humanReviewRecords = records
        changedSinceReviewPaths = changed
        if let commentRefreshFailure {
            refreshStatusText = "Researcher comments refresh failed"
            workspaceCatalogError = "Scholium left the existing comment records unchanged because their anchors could not be refreshed safely. \(commentRefreshFailure)"
        }
    }

    private func resetWindowSession() {
        presentationRouter.dismissAll()
        documentController.removeAll()
        discoveryController.reset()
        researchController.reset()
        notes = []
        openTabs = []
        activeTab = nil
        documentModes = [:]
        documentScrollPositions = [:]
        pendingSourceLine = nil
        clearMetadataFilters()
        currentRegisteredVault = nil
        currentVaultRole = .other
        pendingCommentSelection = nil
        focusedResearcherCommentID = nil
        humanReviewRecords = [:]
        noteIdentityByPath = [:]
        identityAmbiguities = []
        pendingIdentityRebindings = []
        identityMigrationFailures = []
        identityResolutionError = nil
        dialogueInitialNotes = []
        documentRevisions = [:]
        relationshipGraph = nil
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
                identityResolved: true
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
            guard let activeTab,
                  editingDocumentPath == activeTab,
                  !refreshed.contains(where: { $0.relativePath == activeTab }) else { return nil }
            return previousByPath[activeTab]
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

    /// Publishes authoritative document bytes before refreshing disposable
    /// projections. A parse or index failure can make derived state stale, but
    /// must never make the editor retry an already committed repository write
    /// or reject a disk revision the researcher explicitly accepted.
    private func replaceSavedDocument(_ document: NoteDocument) async -> WindowDocumentLocation {
        let previousIndex = notes.firstIndex(where: { $0.relativePath == document.relativePath })
        let previous = previousIndex.map { notes[$0] }
        let applicationSnapshot: WorkspaceNoteSnapshot? = if let vaultID = currentRegisteredVault?.id {
            try? await documentController.noteSnapshot(VaultQualifiedNoteID(
                vaultID: vaultID,
                relativePath: document.relativePath
            ))
        } else {
            nil
        }
        let saved: WindowDocumentLocation
        if noteLocationScope == .unclassified {
            saved = .unclassified(document)
        } else if let applicationSnapshot,
                  applicationSnapshot.fingerprint == document.fingerprint {
            saved = .workspace(applicationSnapshot)
        } else if let prior = previous?.workspaceSnapshot {
            saved = .workspace(WorkspaceNoteSnapshot(
                id: prior.id,
                vaultRole: prior.vaultRole,
                stableIdentity: prior.stableIdentity,
                document: document,
                fileMetadata: WorkspaceFileMetadata(
                    byteCount: document.sourceBytes.count,
                    creationDate: prior.fileMetadata.creationDate,
                    modificationDate: prior.fileMetadata.modificationDate
                ),
                lifecycle: prior.lifecycle,
                review: prior.review,
                graphCounts: prior.graphCounts
            ))
        } else if let vaultID = currentRegisteredVault?.id {
            saved = .workspace(WorkspaceNoteSnapshot(
                id: VaultQualifiedNoteID(
                    vaultID: vaultID,
                    relativePath: document.relativePath
                ),
                vaultRole: currentVaultRole,
                stableIdentity: noteIdentityByPath[document.relativePath]
                    .map(WorkspaceNoteIdentityState.resolved) ?? .unresolved,
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
            ))
        } else {
            saved = .unclassified(document)
        }
        if let previousIndex {
            notes[previousIndex] = saved
        } else {
            notes.append(saved)
            notes.sort(by: notesAreOrdered)
        }
        documentRevisions[document.relativePath] = document.fingerprint
        await refreshWindowProjection(incrementalPaths: [document.relativePath])
        return notes.first(where: { $0.relativePath == document.relativePath }) ?? saved
    }

    func setVaultRole(_ role: VaultRole) {
        guard let config = vaultConfig,
              let registered = currentRegisteredVault,
              role != currentVaultRole else { return }
        Task {
            do {
                let updated = try await workspaceStore.registerVault(
                    path: config.path,
                    name: registered.name,
                    role: role
                )
                await refreshWorkspaceAssignment(preferredTriptychID: workspaceAssignment?.id)
                try await openRegisteredVault(updated)
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
    case invalidResponseContract([String])

    var errorDescription: String? {
        switch self {
        case .contextChanged(let title):
            return "\(title) changed or moved while Dialogue was open. Reload the note list, review the current text, and copy the instructions again."
        case .invalidResponseContract(let issues):
            return "The selected Dialogue response contract is unavailable. \(issues.joined(separator: " "))"
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
