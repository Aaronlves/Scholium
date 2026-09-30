import Combine
import Foundation
import ScholiumContracts

enum AttentionPopoverAnchor: String, Equatable, Sendable {
    case toolbar
    case inspector
}

enum AttentionQueuePopoverAnchor: Equatable, Sendable {
    case toolbar
    case inspector

    var popoverAnchor: AttentionPopoverAnchor {
        switch self {
        case .toolbar: .toolbar
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
        let documentChangeChanges: AnyPublisher<[DocumentChangeSummary]?, Never>
        let documentChangeErrorChanges: AnyPublisher<String?, Never>
        let refresh: @MainActor () async -> Void
        let showDocumentChange: @MainActor (UUID) -> Void
    }

    @Published private(set) var presentedAnchor: AttentionPopoverAnchor?
    @Published private(set) var documentChanges: [DocumentChangeSummary]?
    @Published private(set) var documentChangesError: String?
    @Published private var refreshInProgress = false

    let presentation: AttentionPresentationState
    private let workspaceController: WindowWorkspaceController
    private let projectionController: WindowWorkspaceProjectionController
    private let dependencies: Dependencies
    private var observations: Set<AnyCancellable> = []

    init(
        presentation: AttentionPresentationState,
        workspaceController: WindowWorkspaceController,
        projectionController: WindowWorkspaceProjectionController,
        dependencies: Dependencies
    ) {
        self.presentation = presentation
        self.workspaceController = workspaceController
        self.projectionController = projectionController
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
        dependencies.documentChangeChanges
            .removeDuplicates()
            .sink { [weak self] changes in
                self?.documentChanges = changes
            }
            .store(in: &observations)
        dependencies.documentChangeErrorChanges
            .removeDuplicates()
            .sink { [weak self] error in
                self?.documentChangesError = error
            }
            .store(in: &observations)
    }

    var isRefreshing: Bool {
        refreshInProgress || projectionController.isRefreshingCatalog
    }

    var isLoadingInitialContent: Bool {
        (!catalogIsAvailable && catalogError == nil)
            || (documentChanges == nil && documentChangesError == nil)
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
        let resolvedWorkspaceSlot =
            workspaceSlot
            ?? noteScope.flatMap { note in
                workspaceController.state.assignment?.vaults.first(where: {
                    $0.value.id == note.vaultID
                })?.key
            }
        if anchor == .inspector {
            presentation.filter = AttentionQueueFilter()
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

    func visibleDocumentChanges(
        for presentation: AttentionPresentationState,
        locale: Locale = .current
    ) -> [DocumentChangeSummary] {
        let noteID = presentation.noteScope.flatMap(stableNoteID)
        let query = normalized(presentation.filter.query, locale: locale)
        return (documentChanges ?? []).filter { change in
            if let workspaceSlot = presentation.workspaceSlot,
                change.role != workspaceSlot.vaultRole
            {
                return false
            }
            if presentation.noteScope != nil, change.noteID != noteID {
                return false
            }
            guard !query.isEmpty else { return true }
            let searchable = [
                noteTitle(for: change), change.relativePath,
                ScholiumL10n.dynamicString(change.role.displayName),
                ScholiumL10n.string("Pending Changes", locale: locale),
            ].joined(separator: " ")
            return normalized(searchable, locale: locale).contains(query)
        }
        .sorted { ($0.savedAt ?? .distantPast) > ($1.savedAt ?? .distantPast) }
    }

    func noteTitle(for change: DocumentChangeSummary) -> String {
        if let title = catalogNotes(for: change.noteID).first?.title,
            !title.isEmpty
        {
            return title
        }
        return change.relativePath.split(separator: "/").last.map(String.init)
            ?? change.relativePath
    }

    func refresh() async {
        guard !refreshInProgress else { return }
        refreshInProgress = true
        defer { refreshInProgress = false }
        await dependencies.refresh()
    }

    func inspect(_ change: DocumentChangeSummary) {
        dismiss()
        dependencies.showDocumentChange(change.noteID)
    }

    private func stableNoteID(_ note: VaultQualifiedNoteID) -> UUID? {
        projectionController.catalog?.notes.first(where: {
            $0.reference.vaultID == note.vaultID
                && $0.reference.relativePath == note.relativePath
        })?.reference.stableNoteID.flatMap(UUID.init(uuidString:))
    }

    private func catalogNotes(for noteID: UUID) -> [WorkspaceCatalogNote] {
        projectionController.catalog?.notes.filter {
            $0.reference.stableNoteID.flatMap(UUID.init(uuidString:)) == noteID
        } ?? []
    }

    private func normalized(_ value: String, locale: Locale) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: locale
            )
    }

}
