import ScholiumContracts
import AppKit
import Combine
import Foundation
import SwiftUI

/// App-scene bridge for the one Attention window. It retains only the exact
/// most recently presented Workspace and its activation callback; it performs
/// no window search, notification routing, or derived-state ownership.
@MainActor
final class AttentionWindowSession: ObservableObject {
    @Published private(set) var workspaceID: UUID?
    private var workspace: WindowModel?
    private var workspaceObservation: AnyCancellable?
    private weak var attentionWindow: NSWindow?
    private var activateWorkspaceAction: @MainActor () -> Void = {}

    var presentation: AttentionPresentationState? {
        workspace?.attentionPresentationState
    }

    var isRefreshing: Bool {
        workspace?.isRefreshingWorkspaceCatalog == true
    }

    var catalogIsAvailable: Bool {
        workspace?.workspaceCatalog != nil
    }

    var catalogError: String? {
        workspace?.workspaceCatalogError
    }

    var derivedRefreshStatus: WorkspaceDerivedRefreshStatus? {
        workspace?.derivedRefreshStatus
    }

    var dismissalDays: Int {
        workspace.map { AttentionPreferences.normalizedDays(
            $0.triptychSettings.attentionDismissalDays
        ) } ?? 7
    }

    /// A separate SwiftUI Scene does not inherit the Workspace root's
    /// preferred appearance. Project the exact owning Workspace choice so the
    /// auxiliary window never mixes a Dark surface with Light semantic text
    /// (or vice versa). System remains genuinely system-owned.
    var preferredColorScheme: ColorScheme? {
        switch workspace?.colorScheme {
        case .dark: .dark
        case .light: .light
        case .system, nil: nil
        }
    }

    func present(
        workspace: WindowModel,
        noteScope: VaultQualifiedNoteID?,
        activateWorkspace: @escaping @MainActor () -> Void
    ) {
        workspace.attentionPresentationState.present(
            workspaceSlot: workspace.discoveryController.library.workspaceSlot,
            noteScope: noteScope
        )
        self.workspace = workspace
        workspaceID = workspace.nativeWindowID
        workspaceObservation = workspace.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        activateWorkspaceAction = activateWorkspace
        focusAttentionWindow()
    }

    func attach(to window: NSWindow) {
        guard attentionWindow !== window else { return }
        attentionWindow = window
        focusAttentionWindow()
    }

    func detach(from window: NSWindow?) {
        guard attentionWindow === window else { return }
        attentionWindow = nil
    }

    private func focusAttentionWindow() {
        guard let attentionWindow else { return }
        NSApp.activate(ignoringOtherApps: true)
        attentionWindow.makeKeyAndOrderFront(nil)
    }

    func activateWorkspace() {
        activateWorkspaceAction()
    }

    func scopedItems(for presentation: AttentionPresentationState) -> [AttentionQueueItem] {
        guard let workspace,
              let vaultID = workspace.workspaceAssignment?
                .vault(for: presentation.workspaceSlot)?.id else { return [] }
        return (workspace.workspaceCatalog?.attention ?? []).filter { item in
            guard item.note.vaultID == vaultID else { return false }
            guard let noteScope = presentation.noteScope else { return true }
            return item.note.vaultID == noteScope.vaultID
                && item.note.relativePath == noteScope.relativePath
        }
    }

    func noteTitle(for item: AttentionQueueItem) -> String {
        if let title = workspace?.workspaceCatalog?.notes.first(where: {
            $0.reference.vaultID == item.note.vaultID
                && $0.reference.relativePath == item.note.relativePath
        })?.title, !title.isEmpty {
            return title
        }
        return URL(fileURLWithPath: item.note.relativePath)
            .deletingPathExtension().lastPathComponent
    }

    func refresh() async {
        await workspace?.refreshWorkspaceCatalog()
    }

    func inspect(_ item: AttentionQueueItem) {
        activateWorkspace()
        let reference = item.materialChangedSinceUse?.material ?? item.note
        workspace?.discoveryController.requestOpen(
            reference,
            sourceLocator: item.materialChangedSinceUse == nil ? item.locator : nil
        )
    }

    func resynthesize(_ item: AttentionQueueItem) {
        activateWorkspace()
        workspace?.requestResynthesis(item)
    }

    func detach(_ workspace: WindowModel) {
        guard self.workspace === workspace else { return }
        self.workspace = nil
        workspaceID = nil
        workspaceObservation = nil
        activateWorkspaceAction = {}
    }
}

/// Captures only the standard Attention Scene's own `NSWindow`. This gives the
/// Sidebar and Window menu a deterministic focus path without searching the
/// global window list or replacing native titlebar behavior.
struct AttentionWindowAttachment: NSViewRepresentable {
    let session: AttentionWindowSession

    func makeNSView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.onWindowAttachment = { [weak session] window in
            session?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: WindowAttachmentView, context: Context) {
        if let window = nsView.window { session.attach(to: window) }
    }

    static func dismantleNSView(
        _ nsView: WindowAttachmentView,
        coordinator: Void
    ) {
        nsView.onWindowAttachment = nil
    }
}
