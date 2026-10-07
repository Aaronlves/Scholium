import AppKit
import Combine
import ScholiumContracts
import SwiftUI
import UniformTypeIdentifiers

/// The application entry for Finder, File > Open and Chat. Scene opening is
/// bound once available; requests received during launch retain their URLs.
@MainActor
final class MarkdownFileOpeningController: ObservableObject {
    enum LaunchPresentation: Equatable {
        case awaitingLaunch
        case defaultWorkspace
        case requestedScene
    }

    static let contentType = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
    @Published private(set) var launchPresentation = LaunchPresentation.awaitingLaunch
    private var pending: [URL] = []
    private var task: Task<Void, Never>?
    private var bootstrapObservation: AnyCancellable?
    private var bootstrapResolved = false
    private var workspaceStore: WorkspaceStore?
    private weak var bootstrapController: ApplicationBootstrapController?
    private var openExternalWindow: ((ExternalMarkdownWindowRoute) -> Void)?
    private var openWorkspaceWindow: ((TriptychWindowRoute) -> Void)?
    private var lifecycleRegistry: ScholiumWindowLifecycleRegistry?
    private var selectionPanel: NSOpenPanel?
    private var acceptsRequests = true
    private var launchSuppressionConsumed = false

    /// AppKit names the launch intent even when its file event arrives later.
    /// A saved-scene, file, notification or service launch already has another
    /// route; only a default launch may create the initial workspace.
    func finishLaunching(isDefaultLaunch: Bool) {
        guard launchPresentation == .awaitingLaunch else { return }
        launchPresentation = isDefaultLaunch ? .defaultWorkspace : .requestedScene
    }

    func consumeLaunchBootstrapSuppression() -> Bool {
        guard launchPresentation == .requestedScene, !launchSuppressionConsumed else { return false }
        launchSuppressionConsumed = true
        return true
    }

    func prepareTermination() {
        acceptsRequests = false
        task?.cancel()
        pending.removeAll()
        selectionPanel?.cancel(nil)
    }

    func cancelTermination() {
        acceptsRequests = true
        drain()
    }

    func connect(
        bootstrap: ApplicationBootstrapController,
        openWindow: OpenWindowAction,
        lifecycleRegistry: ScholiumWindowLifecycleRegistry
    ) {
        connect(
            bootstrap: bootstrap,
            openExternalWindow: { openWindow(id: "scholium-external-markdown", value: $0) },
            openWorkspaceWindow: { openWindow(id: "scholium-main", value: $0) },
            lifecycleRegistry: lifecycleRegistry
        )
    }

    func connect(
        bootstrap: ApplicationBootstrapController,
        openExternalWindow: @escaping (ExternalMarkdownWindowRoute) -> Void,
        openWorkspaceWindow: @escaping (TriptychWindowRoute) -> Void,
        lifecycleRegistry: ScholiumWindowLifecycleRegistry
    ) {
        bootstrapController = bootstrap
        self.lifecycleRegistry = lifecycleRegistry
        self.openExternalWindow = openExternalWindow
        self.openWorkspaceWindow = openWorkspaceWindow
        if bootstrapObservation == nil {
            bootstrapObservation = bootstrap.$state.sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .starting:
                    self.bootstrapResolved = false
                    self.workspaceStore = nil
                case .ready(let store):
                    self.bootstrapResolved = true
                    self.workspaceStore = store
                    store.markdownFileOpening = self
                case .storageUnavailable, .registryRecovery:
                    self.bootstrapResolved = true
                    self.workspaceStore = nil
                }
                self.drain()
            }
        }
        bootstrap.startIfNeeded()
        drain()
    }

    func requestOpen(_ urls: [URL]) {
        guard acceptsRequests, !urls.isEmpty else { return }
        if launchPresentation == .awaitingLaunch {
            launchPresentation = .requestedScene
        }
        for url in urls where !pending.contains(where: { ExternalMarkdownWindowRegistry.referToSameFile($0, url) }) {
            pending.append(url)
        }
        drain()
    }

    func chooseFiles() {
        guard acceptsRequests, selectionPanel == nil else { return }
        let panel = NSOpenPanel()
        panel.title = ScholiumL10n.string("Open Markdown…")
        panel.allowedContentTypes = [Self.contentType]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = false
        selectionPanel = panel
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
            guard let self, let panel else { return }
            self.selectionPanel = nil
            if response == .OK { self.requestOpen(panel.urls) }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    func openImported(_ reference: VaultNoteReference, in triptychID: UUID) async throws {
        try Task.checkCancellation()
        guard acceptsRequests, let workspaceStore, let openWorkspaceWindow else {
            throw ScholiumFileSelectionError.presenterUnavailable
        }
        if try await workspaceStore.documentLocations.openInExistingWindow(reference, triptychID: triptychID) { return }
        try Task.checkCancellation()
        guard acceptsRequests else { throw CancellationError() }
        openWorkspaceWindow(TriptychWindowRoute(triptychID: triptychID, initialDocument: reference))
    }

    func retryExternalOwnership(_ model: ExternalMarkdownWindowModel) async {
        await model.retryOwnership {
            if self.workspaceStore == nil, let bootstrap = self.bootstrapController {
                bootstrap.retry()
                for await state in bootstrap.$state.values {
                    try Task.checkCancellation()
                    if case .starting = state { continue }
                    break
                }
            }
            guard self.acceptsRequests, let store = self.workspaceStore else {
                throw ScholiumFileSelectionError.presenterUnavailable
            }
            let assignments = try await store.registeredTriptychs()
            try Task.checkCancellation()
            guard self.acceptsRequests else { throw CancellationError() }
            if let note = Self.managedNote(at: model.originalURL, assignments: assignments) {
                return .managed(note.reference, triptychID: note.triptychID)
            }
            return .external
        }
    }

    func openManagedPreview(_ model: ExternalMarkdownWindowModel) async throws {
        guard acceptsRequests, model.canOpenManagedNote, let note = model.managedNote else {
            throw ScholiumFileSelectionError.presenterUnavailable
        }
        try await openImported(note.reference, in: note.triptychID)
    }

    func openRecovery(
        _ record: TriptychMutationRecoveryRecord,
        persistenceFailure: String? = nil
    ) async throws {
        guard acceptsRequests, let workspaceStore, let openWorkspaceWindow, let lifecycleRegistry else {
            throw ScholiumFileSelectionError.presenterUnavailable
        }
        if try await workspaceStore.documentLocations.presentRecoveryInExistingMainWindow(
            record, persistenceFailure: persistenceFailure
        ) {
            return
        }
        try Task.checkCancellation()
        guard acceptsRequests else { throw CancellationError() }
        let route = TriptychWindowRoute(windowID: UUID(), triptychID: record.triptychID)
        openWorkspaceWindow(route)
        try await lifecycleRegistry.waitUntilReady(id: route.windowID)
        try Task.checkCancellation()
        guard acceptsRequests else { throw CancellationError() }
        guard
            try await workspaceStore.documentLocations.presentRecoveryInExistingMainWindow(
                record, persistenceFailure: persistenceFailure, windowID: route.windowID
            )
        else { throw ScholiumFileSelectionError.presenterUnavailable }
    }

    /// Excludes known non-Note paths without scanning a Triptych. Guarded Note
    /// navigation remains the owner of access, source and stable identity.
    static func managedMarkdownRelativePath(at url: URL, in vaultRoot: URL) -> String? {
        guard url.isFileURL, url.pathExtension.lowercased() == "md" else { return nil }
        let path = url.standardizedFileURL.path
        let root = vaultRoot.standardizedFileURL.path + "/"
        guard path.hasPrefix(root) else { return nil }
        let relativePath = String(path.dropFirst(root.count))
        guard WorkspaceLibraryVisibility.includes(relativePath),
            !relativePath.split(separator: "/").contains(where: { $0.hasPrefix(".") })
        else { return nil }
        return relativePath
    }

    private static func managedNote(
        at url: URL, assignments: [TriptychAssignment]
    ) -> (reference: VaultNoteReference, triptychID: UUID)? {
        for assignment in assignments {
            for vault in assignment.vaults.values {
                guard
                    let path = managedMarkdownRelativePath(
                        at: url, in: URL(fileURLWithPath: vault.canonicalPath)
                    )
                else { continue }
                return (
                    VaultNoteReference(
                        vaultID: vault.id, vaultName: vault.name,
                        vaultRole: vault.role, relativePath: path), assignment.id
                )
            }
        }
        return nil
    }

    private func drain() {
        guard acceptsRequests, !pending.isEmpty, task == nil, bootstrapResolved, openExternalWindow != nil else { return }
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.task = nil
                self.drain()
            }
            while !self.pending.isEmpty {
                guard !Task.isCancelled, self.acceptsRequests else { return }
                let url = self.pending.removeFirst()
                do { try await self.open(url) } catch is CancellationError { return } catch {
                    guard !Task.isCancelled, self.acceptsRequests else { return }
                    let alert = NSAlert()
                    alert.messageText = ScholiumL10n.string("Markdown Could Not Be Opened")
                    alert.informativeText = error.localizedDescription
                    if let window = NSApp.keyWindow { await alert.beginSheetModal(for: window) } else { alert.runModal() }
                }
            }
        }
    }

    private func open(_ url: URL) async throws {
        try Task.checkCancellation()
        guard url.isFileURL, ["md", "markdown"].contains(url.pathExtension.lowercased()) else {
            throw ScholiumFileSelectionError.rejectedSelection(message: ScholiumL10n.string("Choose a Markdown file (.md or .markdown)."))
        }
        if url.pathExtension.lowercased() == "md", let workspaceStore {
            // A registered root is a routing hint; the normal Note open still
            // validates access, containment, source and identity.
            let assignments: [TriptychAssignment]
            do {
                assignments = try await workspaceStore.registeredTriptychs()
            } catch {
                try Task.checkCancellation()
                guard acceptsRequests else { throw CancellationError() }
                // A retained reader already owns its exact file session. A
                // later registry failure cannot prevent revealing that buffer.
                if ExternalMarkdownWindowRegistry.shared.reveal(url) { return }
                openExternalWindow?(ExternalMarkdownWindowRoute(fileURL: url, needsOwnershipResolution: true))
                return
            }
            try Task.checkCancellation()
            guard acceptsRequests else { throw CancellationError() }
            if let note = Self.managedNote(at: url, assignments: assignments) {
                try ExternalMarkdownWindowRegistry.shared.closeForManagedOpen(url)
                try await openImported(note.reference, in: note.triptychID)
                return
            }
        }
        try Task.checkCancellation()
        if ExternalMarkdownWindowRegistry.shared.reveal(url) { return }
        openExternalWindow?(
            ExternalMarkdownWindowRoute(
                fileURL: url,
                needsOwnershipResolution: url.pathExtension.lowercased() == "md" && workspaceStore == nil
            ))
    }
}

struct MarkdownFileOpeningRouting: ViewModifier {
    @EnvironmentObject private var applicationDelegate: ScholiumApplicationDelegate
    @EnvironmentObject private var bootstrap: ApplicationBootstrapController
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            applicationDelegate.markdownFiles.connect(
                bootstrap: bootstrap, openWindow: openWindow,
                lifecycleRegistry: applicationDelegate.windowLifecycleRegistry
            )
        }
    }
}
