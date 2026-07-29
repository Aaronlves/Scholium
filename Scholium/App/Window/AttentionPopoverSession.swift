import ScholiumContracts
import Combine
import Foundation

enum AttentionPopoverAnchor: String, Equatable, Sendable {
    case sidebar
    case inspector
}

/// Exact-Workspace adapter for the transient Attention popover. The owning
/// `WindowModel` supplies derived data and presentation state; this adapter
/// never searches global windows, broadcasts notifications, or duplicates
/// queue ownership.
@MainActor
final class AttentionPopoverSession: ObservableObject {
    @Published private(set) var presentedAnchor: AttentionPopoverAnchor?
    private weak var workspace: WindowModel?
    private var workspaceObservation: AnyCancellable?

    init(workspace: WindowModel) {
        self.workspace = workspace
        workspaceObservation = workspace.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

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

    func present(
        from anchor: AttentionPopoverAnchor,
        workspaceSlot: WorkspaceVaultSlot? = nil,
        noteScope: VaultQualifiedNoteID?
    ) {
        guard let workspace else { return }
        workspace.attentionPresentationState.present(
            workspaceSlot: workspaceSlot
                ?? workspace.discoveryController.library.workspaceSlot,
            noteScope: noteScope
        )
        presentedAnchor = anchor
    }

    func isPresented(from anchor: AttentionPopoverAnchor) -> Bool {
        presentedAnchor == anchor
    }

    func dismiss(resetFilter: Bool = false) {
        presentedAnchor = nil
        if resetFilter {
            workspace?.attentionPresentationState.resetForWorkspaceSwitch()
        }
    }

    func resetForWorkspaceSwitch() {
        dismiss(resetFilter: true)
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
        dismiss()
        let reference = item.materialChangedSinceUse?.material ?? item.note
        workspace?.discoveryController.requestOpen(
            reference,
            sourceLocator: item.materialChangedSinceUse == nil ? item.locator : nil
        )
    }

    func resynthesize(_ item: AttentionQueueItem) {
        dismiss()
        workspace?.requestResynthesis(item)
    }
}
