import Combine
import Foundation
import ScholiumContracts

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
        let showDocumentChange: @MainActor (DocumentChangeSummary) -> Bool
    }

    @Published private(set) var documentChanges: [DocumentChangeSummary]?
    @Published private(set) var documentChangesError: String?
    @Published private var refreshInProgress = false

    let presentation: AttentionPresentationState
    private let workspaceController: WindowWorkspaceController
    private let projectionController: WindowWorkspaceProjectionController
    private let dependencies: Dependencies
    private var observations: Set<AnyCancellable> = []
    private struct NoteIdentity: Hashable {
        let vaultID: UUID
        let noteID: UUID
    }

    private struct PresentationContext: Equatable {
        let triptychID: UUID?
        let runtimeIdentity: TriptychRuntimeIdentity?
    }

    @Published private var presentedContext: PresentationContext?
    private var titlesByStableID: [NoteIdentity: String] = [:]

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

        projectionController.$state
            .map { $0.catalog?.notes ?? [] }
            .removeDuplicates()
            .sink { [weak self] notes in self?.indexCatalog(notes) }
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

    var isPresented: Bool { presentedContext != nil }

    func present() {
        presentedContext = currentContext
    }

    func dismiss() {
        presentedContext = nil
    }

    func resetForWorkspaceSwitch() {
        dismiss()
        presentation.resetForWorkspaceSwitch()
    }

    func visibleDocumentChanges(locale: Locale = .current) -> [DocumentChangeSummary] {
        let query = normalized(presentation.filter.query, locale: locale)
        return (documentChanges ?? []).filter { change in
            guard !query.isEmpty else { return true }
            let searchable = [
                noteTitle(for: change), change.relativePath,
                ScholiumL10n.dynamicString(change.role.displayName),
                ScholiumL10n.string("Pending Changes", locale: locale),
            ].joined(separator: " ")
            return normalized(searchable, locale: locale).contains(query)
        }
        .sorted {
            let lhsDate = $0.savedAt ?? .distantPast
            let rhsDate = $1.savedAt ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            if $0.vaultID != $1.vaultID { return $0.vaultID.uuidString < $1.vaultID.uuidString }
            return $0.noteID.uuidString < $1.noteID.uuidString
        }
    }

    func noteTitle(for change: DocumentChangeSummary) -> String {
        if let title = titlesByStableID[NoteIdentity(vaultID: change.vaultID, noteID: change.noteID)],
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

    @discardableResult
    func inspect(_ change: DocumentChangeSummary) -> Bool {
        guard isPresented, presentedContext == currentContext,
            let current = visibleDocumentChanges().first(where: {
                $0.noteID == change.noteID && $0.vaultID == change.vaultID
            }),
            dependencies.showDocumentChange(current)
        else { return false }
        dismiss()
        return true
    }

    private var currentContext: PresentationContext {
        PresentationContext(
            triptychID: workspaceController.state.assignment?.id,
            runtimeIdentity: workspaceController.activeCapabilities?.runtimeIdentity
        )
    }

    /// Rebuilt only when the catalog's immutable Note projection changes. Query
    /// and row-selection updates never rescan the complete workspace catalog.
    private func indexCatalog(_ notes: [WorkspaceCatalogNote]) {
        titlesByStableID.removeAll(keepingCapacity: true)
        for note in notes {
            guard let id = note.reference.stableNoteID.flatMap(UUID.init(uuidString:)) else { continue }
            let identity = NoteIdentity(vaultID: note.reference.vaultID, noteID: id)
            if titlesByStableID[identity] == nil { titlesByStableID[identity] = note.title }
        }
    }

    private func normalized(_ value: String, locale: Locale) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: locale
            )
    }

}
