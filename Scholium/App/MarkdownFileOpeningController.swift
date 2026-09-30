import AppKit
import Combine
import ScholiumContracts
import SwiftUI
import UniformTypeIdentifiers

/// The application entry for Finder, File > Open and Chat. Scene opening is
/// bound once available; requests received during launch retain their URLs.
@MainActor
final class MarkdownFileOpeningController: ObservableObject {
    static let contentType = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
    @Published private(set) var handlesLaunchDocuments = false
    private var pending: [URL] = []
    private var task: Task<Void, Never>?
    private var bootstrapObservation: AnyCancellable?
    private var bootstrapResolved = false
    private var workspaceStore: WorkspaceStore?
    private var openExternalWindow: ((ExternalMarkdownWindowRoute) -> Void)?
    private var openWorkspaceWindow: ((TriptychWindowRoute) -> Void)?
    private var lifecycleRegistry: ScholiumWindowLifecycleRegistry?
    private var selectionPanel: NSOpenPanel?
    private var acceptsRequests = true
    private var launchFinished = false
    private var launchSuppressionConsumed = false

    /// AppKit delivers files used to launch the app before this boundary. Keep
    /// a queued launch token until the initial Bootstrap can consume it.
    func finishLaunching() { launchFinished = true }

    func consumeLaunchBootstrapSuppression() -> Bool {
        guard handlesLaunchDocuments, !launchSuppressionConsumed else { return false }
        launchSuppressionConsumed = true
        handlesLaunchDocuments = false
        return true
    }

    func prepareTermination() {
        acceptsRequests = false
        task?.cancel()
        pending.removeAll()
        selectionPanel?.cancel(nil)
    }

    func cancelTermination() { acceptsRequests = true }

    func connect(
        bootstrap: ApplicationBootstrapController,
        openWindow: OpenWindowAction,
        lifecycleRegistry: ScholiumWindowLifecycleRegistry
    ) {
        self.lifecycleRegistry = lifecycleRegistry
        openExternalWindow = { openWindow(id: "scholium-external-markdown", value: $0) }
        openWorkspaceWindow = { openWindow(id: "scholium-main", value: $0) }
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
        if !launchFinished && !launchSuppressionConsumed {
            handlesLaunchDocuments = true
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
        guard acceptsRequests, let workspaceStore, let openWorkspaceWindow else {
            throw ScholiumFileSelectionError.presenterUnavailable
        }
        if try await workspaceStore.documentLocations.openInExistingWindow(reference, triptychID: triptychID) { return }
        openWorkspaceWindow(TriptychWindowRoute(triptychID: triptychID, initialDocument: reference))
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

    private func drain() {
        guard acceptsRequests, task == nil, bootstrapResolved, openExternalWindow != nil else { return }
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.task = nil }
            while !self.pending.isEmpty {
                let url = self.pending.removeFirst()
                do { try await self.open(url) } catch is CancellationError { return } catch {
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
        if let workspaceStore {
            // A registered root is a routing hint; the normal Note open still
            // validates access, containment, source and identity.
            let assignments = try await workspaceStore.registeredTriptychs()
            try Task.checkCancellation()
            guard acceptsRequests else { throw CancellationError() }
            for assignment in assignments {
                for vault in assignment.vaults.values {
                    guard
                        let relativePath = Self.managedMarkdownRelativePath(
                            at: url, in: URL(fileURLWithPath: vault.canonicalPath)
                        )
                    else { continue }
                    let reference = VaultNoteReference(vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role, relativePath: relativePath)
                    try ExternalMarkdownWindowRegistry.shared.closeForManagedOpen(url)
                    try await openImported(reference, in: assignment.id)
                    return
                }
            }
        }
        try Task.checkCancellation()
        if ExternalMarkdownWindowRegistry.shared.reveal(url) { return }
        openExternalWindow?(ExternalMarkdownWindowRoute(fileURL: url))
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
