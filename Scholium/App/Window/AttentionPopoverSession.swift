import ScholiumContracts
import Combine
import Foundation

enum AttentionPopoverAnchor: String, Equatable, Sendable {
    case sidebar
    case inspector
}

/// Exact-Workspace adapter for the transient Attention popover. It observes
/// only the owners whose state appears in the popover and borrows closed
/// refresh/navigation effects from the window composition root. It never
/// searches global windows, broadcasts notifications, or duplicates queue
/// ownership.
@MainActor
final class AttentionPopoverSession: ObservableObject {
    struct Dependencies {
        let dismissalDaysChanges: AnyPublisher<Int, Never>
        let refresh: @MainActor () async -> Void
        let resynthesize: @MainActor (AttentionQueueItem) -> Void
    }

    @Published private(set) var presentedAnchor: AttentionPopoverAnchor?
    @Published private(set) var dismissalDays: Int

    let presentation: AttentionPresentationState
    private let discoveryController: DiscoveryController
    private let workspaceController: WindowWorkspaceController
    private let projectionController: WindowWorkspaceProjectionController
    private let dependencies: Dependencies
    private var observations: Set<AnyCancellable> = []

    init(
        presentation: AttentionPresentationState,
        discoveryController: DiscoveryController,
        workspaceController: WindowWorkspaceController,
        projectionController: WindowWorkspaceProjectionController,
        dismissalDays: Int,
        dependencies: Dependencies
    ) {
        self.presentation = presentation
        self.discoveryController = discoveryController
        self.workspaceController = workspaceController
        self.projectionController = projectionController
        self.dismissalDays = AttentionPreferences.normalizedDays(dismissalDays)
        self.dependencies = dependencies

        workspaceController.$state
            .map(\.assignment)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &observations)
        projectionController.$state
            .dropFirst()
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &observations)
        dependencies.dismissalDaysChanges
            .map(AttentionPreferences.normalizedDays)
            .removeDuplicates()
            .sink { [weak self] days in
                guard self?.dismissalDays != days else { return }
                self?.dismissalDays = days
            }
            .store(in: &observations)
    }

    var isRefreshing: Bool {
        projectionController.isRefreshingCatalog
    }

    var catalogIsAvailable: Bool {
        projectionController.catalog != nil
    }

    var catalogError: String? {
        projectionController.catalogError
    }

    var derivedRefreshStatus: WorkspaceDerivedRefreshStatus? {
        projectionController.derivedRefreshStatus
    }

    func present(
        from anchor: AttentionPopoverAnchor,
        workspaceSlot: WorkspaceVaultSlot? = nil,
        noteScope: VaultQualifiedNoteID?
    ) {
        presentation.present(
            workspaceSlot: workspaceSlot
                ?? discoveryController.library.workspaceSlot,
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
            presentation.resetForWorkspaceSwitch()
        }
    }

    func resetForWorkspaceSwitch() {
        dismiss(resetFilter: true)
    }

    func scopedItems(for presentation: AttentionPresentationState) -> [AttentionQueueItem] {
        guard let vaultID = workspaceController.state.assignment?
                .vault(for: presentation.workspaceSlot)?.id else { return [] }
        return (projectionController.catalog?.attention ?? []).filter { item in
            guard item.note.vaultID == vaultID else { return false }
            guard let noteScope = presentation.noteScope else { return true }
            return item.note.vaultID == noteScope.vaultID
                && item.note.relativePath == noteScope.relativePath
        }
    }

    func noteTitle(for item: AttentionQueueItem) -> String {
        if let title = projectionController.catalog?.notes.first(where: {
            $0.reference.vaultID == item.note.vaultID
                && $0.reference.relativePath == item.note.relativePath
        })?.title, !title.isEmpty {
            return title
        }
        return URL(fileURLWithPath: item.note.relativePath)
            .deletingPathExtension().lastPathComponent
    }

    func refresh() async {
        await dependencies.refresh()
    }

    func inspect(_ item: AttentionQueueItem) {
        dismiss()
        let reference = item.materialChangedSinceUse?.material ?? item.note
        discoveryController.requestOpen(
            reference,
            sourceLocator: item.materialChangedSinceUse == nil ? item.locator : nil
        )
    }

    func resynthesize(_ item: AttentionQueueItem) {
        dismiss()
        dependencies.resynthesize(item)
    }
}
