import ScholiumContracts
import Combine
import Foundation

enum AttentionPopoverAnchor: String, Equatable, Sendable {
    case sidebar
    case inspector
}

enum AttentionQueuePopoverAnchor: Equatable, Sendable {
    case sidebar
    case inspector

    var popoverAnchor: AttentionPopoverAnchor {
        switch self {
        case .sidebar: .sidebar
        case .inspector: .inspector
        }
    }
}

/// One window-level Notifications request opens the complete queue from a
/// stable anchor.
enum AttentionPresentationRequest: Equatable, Sendable {
    case queue(
        anchor: AttentionQueuePopoverAnchor,
        workspaceSlot: WorkspaceVaultSlot?,
        noteScope: VaultQualifiedNoteID?
    )
}

/// Exact-Workspace adapter for the transient Notifications popover. It observes
/// only the owners whose state appears in the popover and borrows closed
/// refresh/navigation effects from the window composition root. It never
/// searches global windows, broadcasts notifications, or duplicates queue
/// ownership.
@MainActor
final class AttentionPopoverSession: ObservableObject {
    struct Dependencies {
        let dismissalDaysChanges: AnyPublisher<Int, Never>
        let settlementRequirementChanges:
            AnyPublisher<[WorkspaceSettlementRequirement], Never>
        let refresh: @MainActor () async -> Void
    }

    @Published private(set) var presentedAnchor: AttentionPopoverAnchor?
    @Published private(set) var dismissalDays: Int
    @Published private(set) var settlementRequirements:
        [WorkspaceSettlementRequirement] = []

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
        dependencies.settlementRequirementChanges
            .removeDuplicates()
            .sink { [weak self] requirements in
                self?.settlementRequirements = requirements
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

    func presentQueue(
        anchor: AttentionQueuePopoverAnchor,
        workspaceSlot: WorkspaceVaultSlot?,
        noteScope: VaultQualifiedNoteID?
    ) {
        let resolvedWorkspaceSlot = workspaceSlot ?? noteScope.flatMap { note in
            workspaceController.state.assignment?.vaults.first(where: {
                $0.value.id == note.vaultID
            })?.key
        }
        presentation.present(
            workspaceSlot: resolvedWorkspaceSlot,
            noteScope: noteScope
        )
        presentedAnchor = anchor.popoverAnchor
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
        return (projectionController.catalog?.attention ?? []).filter { item in
            if let workspaceSlot = presentation.workspaceSlot {
                guard let vaultID = workspaceController.state.assignment?
                        .vault(for: workspaceSlot)?.id,
                      item.note.vaultID == vaultID else { return false }
            }
            guard let noteScope = presentation.noteScope else { return true }
            return item.note.vaultID == noteScope.vaultID
                && item.note.relativePath == noteScope.relativePath
        }
    }

    func visibleSettlementRequirements(
        for presentation: AttentionPresentationState,
        locale: Locale = .current
    ) -> [WorkspaceSettlementRequirement] {
        guard presentation.notificationFilter.showsSettlements else { return [] }
        let workspaceVaultID = presentation.workspaceSlot.flatMap {
            workspaceController.state.assignment?.vault(for: $0)?.id
        }
        let query = presentation.filter.query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: locale
            )
        return settlementRequirements.filter { requirement in
            if let workspaceVaultID,
               requirement.note.vaultID != workspaceVaultID {
                return false
            }
            if let noteScope = presentation.noteScope,
               requirement.note != noteScope {
                return false
            }
            guard !query.isEmpty else { return true }
            let searchable = [
                ScholiumL10n.string("Current Revision Not Settled", locale: locale),
                ScholiumL10n.string("Review Changes", locale: locale),
                ScholiumL10n.string("Settle", locale: locale),
                requirement.title,
                requirement.note.relativePath,
            ].joined(separator: " ")
            return searchable.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: locale
            ).contains(query)
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
        discoveryController.requestOpen(
            item.note,
            sourceLocator: item.locator
        )
    }

}
