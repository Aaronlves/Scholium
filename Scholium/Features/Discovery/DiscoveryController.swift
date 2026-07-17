import ScholiumContracts
import Combine
import Foundation

struct DiscoveryFilterState: Equatable, Sendable {
    var isReviewed = false
    var isUnqualified = false
    var isChangedSinceReview = false
    var needsAttention = false
    var hasExplicitConnections = false
    var hasMalformedMetadata = false
    var tag: String?
    var status: String?
    var author: String?
    var year: Int?
    var propertyKey: String?
    var propertyValue: String?
}

struct DiscoveryLibraryState: Equatable {
    /// The vault hierarchy currently being browsed in Library. This is
    /// deliberately independent of `DocumentController.selectedDocument` so a
    /// researcher can inspect another Triptych facet without disturbing the
    /// open document or its editor session.
    var workspaceSlot: WorkspaceVaultSlot = .paperAnalysis
    var locationScope: NoteLocationScope = .workspace
    var filters = DiscoveryFilterState()
    var sortOrder: NoteSortOrder = .modifiedNewest
    var expandedFolders: Set<String> = []
    var capturedWorkspaceNotes: [WindowDocumentLocation] = []
    var preparedLifecyclePath: String?
    var showsUnclassified = false
    var lifecycleScope: NoteLocationScope?
    var lifecycleItems: [LifecycleLocationItem] = []
    var lifecycleIsLoading = false
    var lifecycleError: String?
}

struct DiscoverySearchState: Equatable, Sendable {
    var criteria = SearchWorkspaceState()
    var ordinaryScope: SearchPresentationScope = .triptych
    var invocation: SearchInvocation = .general
    var hits: [SearchHit] = []
    var relatedItems: [RelatedSearchItem] = []
    var errorMessage: String?
    var isRunning = false
}

/// The one Search surface can be entered as ordinary workspace search or as
/// the temporary standard Find command for an open note.
enum SearchInvocation: Equatable, Sendable {
    case general
    case findInNote(previousScope: SearchPresentationScope)
}

struct DiscoverySearchRequest: Equatable, Sendable {
    let id: UUID
    let criteria: SearchWorkspaceState
}

struct DiscoverySearchExecutionContext: Equatable, Sendable {
    let workspaceIsAvailable: Bool
    let currentNote: VaultQualifiedNoteID?
    let currentVaultID: UUID?
}

enum DiscoverySearchExecutionError: LocalizedError, Equatable, Sendable {
    case workspaceUnavailable

    var errorDescription: String? {
        switch self {
        case .workspaceUnavailable:
            "Open a complete Triptych before searching."
        }
    }
}

struct DiscoveryLifecycleRequest: Equatable, Sendable {
    let id: UUID
    let scope: NoteLocationScope
}

/// Per-window owner for Library and Search presentation state.
/// It accepts immutable results from Application operations and emits only
/// closed `WindowIntent` values for cross-feature routing.
@MainActor
final class DiscoveryController: ObservableObject {
    typealias IntentHandler = @MainActor (WindowIntent) -> Void

    @Published private(set) var library: DiscoveryLibraryState
    @Published private(set) var search = DiscoverySearchState()

    private var activeLifecycleRequestID: UUID?
    private var activeSearchRequestID: UUID?
    private let intentHandler: IntentHandler
    private var operations: (any DiscoveryUseCases)?

    init(
        initialLibraryState: DiscoveryLibraryState = DiscoveryLibraryState(),
        intentHandler: @escaping IntentHandler = { _ in }
    ) {
        library = initialLibraryState
        self.intentHandler = intentHandler
    }

    func bind(to operations: any DiscoveryUseCases) {
        self.operations = operations
    }

    func unbind() {
        operations = nil
        cancelSearch()
    }

    func discoverySnapshot() async throws -> WorkspaceDiscoverySnapshot {
        try await requireOperations().snapshot()
    }

    @discardableResult
    func refreshWorkspace() async throws -> WorkspaceSnapshot {
        try await requireOperations().refresh()
    }

    func search(
        _ query: SearchQuery,
        scope: SearchScope = .workspace,
        limit: Int = 50
    ) async throws -> [SearchHit] {
        try await requireOperations().search(query, scope: scope, limit: limit)
    }

    func relatedResults(
        query: String,
        scope: SearchScope,
        excluding: Set<VaultQualifiedNoteID> = [],
        limit: Int = 12
    ) async throws -> [RelatedSearchItem] {
        try await requireOperations().related(
            query: query,
            scope: scope,
            excluding: excluding,
            limit: limit
        )
    }

    /// Owns the complete lexical-plus-direct-relationship Search use case for
    /// one window. The window shell supplies only its current navigation
    /// identities and handles presentation of a reported failure.
    func executeSearch(
        _ criteria: SearchWorkspaceState,
        context: DiscoverySearchExecutionContext
    ) async throws {
        let request = beginSearch(criteria)
        let query = request.criteria.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            cancelSearch()
            return
        }
        guard context.workspaceIsAvailable else {
            let error = DiscoverySearchExecutionError.workspaceUnavailable
            failSearch(error.localizedDescription, for: request)
            throw error
        }

        let scope = request.criteria.scope.canonical
        let applicationScope: SearchScope = switch scope {
        case .thisNote:
            context.currentNote.map(SearchScope.currentNote) ?? .roles([])
        case .currentVault:
            context.currentVaultID.map(SearchScope.currentVault) ?? .roles([])
        case .triptych:
            .workspace
        default:
            .roles([])
        }
        let limit = scope == .thisNote ? 50 : 100

        do {
            let hits = try await search(
                SearchQuery(query),
                scope: applicationScope,
                limit: limit
            )
            guard isCurrentSearch(request) else { return }
            let excluded = Set(hits.map {
                VaultQualifiedNoteID(vaultID: $0.vaultID, relativePath: $0.relativePath)
            })
            let related = try await relatedResults(
                query: query,
                scope: applicationScope,
                excluding: excluded
            )
            guard isCurrentSearch(request) else { return }
            receiveSearchResults(hits: hits, relatedItems: related, for: request)
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentSearch(request) else { return }
            failSearch(error.localizedDescription, for: request)
            throw error
        }
    }

    func selectLocationScope(_ scope: NoteLocationScope) {
        library.locationScope = scope
    }

    func selectWorkspaceSlot(_ slot: WorkspaceVaultSlot) {
        library.workspaceSlot = slot
        library.locationScope = .workspace
        dismissLifecycleListing()
    }

    func replaceFilters(_ filters: DiscoveryFilterState) {
        library.filters = filters
    }

    func selectSortOrder(_ order: NoteSortOrder) {
        library.sortOrder = order
    }

    func setExpandedFolders(_ folders: Set<String>) {
        library.expandedFolders = folders
    }

    func captureWorkspaceNotes(_ notes: [WindowDocumentLocation]) {
        library.capturedWorkspaceNotes = notes
    }

    func prepareLifecycle(path: String?) {
        library.preparedLifecyclePath = path
    }

    func showUnclassified(_ isPresented: Bool) {
        library.showsUnclassified = isPresented
    }

    func presentLifecycleListing(_ scope: NoteLocationScope) {
        activeLifecycleRequestID = nil
        library.lifecycleScope = scope
        library.lifecycleItems = []
        library.lifecycleError = nil
        library.lifecycleIsLoading = false
    }

    @discardableResult
    func beginLifecycleListing(_ scope: NoteLocationScope) -> DiscoveryLifecycleRequest {
        let request = DiscoveryLifecycleRequest(id: UUID(), scope: scope)
        activeLifecycleRequestID = request.id
        library.lifecycleScope = scope
        library.lifecycleItems = []
        library.lifecycleError = nil
        library.lifecycleIsLoading = true
        return request
    }

    func receiveLifecycleItems(
        _ items: [LifecycleLocationItem],
        for request: DiscoveryLifecycleRequest
    ) {
        guard isCurrent(request) else { return }
        library.lifecycleItems = items
        library.lifecycleError = nil
        library.lifecycleIsLoading = false
    }

    func failLifecycleListing(_ message: String, for request: DiscoveryLifecycleRequest) {
        guard isCurrent(request) else { return }
        library.lifecycleItems = []
        library.lifecycleError = message
        library.lifecycleIsLoading = false
    }

    func dismissLifecycleListing() {
        activeLifecycleRequestID = nil
        library.lifecycleScope = nil
        library.lifecycleItems = []
        library.lifecycleError = nil
        library.lifecycleIsLoading = false
    }

    func replaceSearchCriteria(_ criteria: SearchWorkspaceState) {
        let scope = criteria.scope.canonical
        search.criteria = SearchWorkspaceState(
            query: criteria.query,
            scope: scope,
            selectedRoles: criteria.selectedRoles,
            selectedResultID: criteria.selectedResultID
        )
        search.ordinaryScope = scope
        search.invocation = .general
        invalidateSearchProjection()
    }

    /// Clears transient results and installs the invocation-specific scope
    /// before the shared overlay appears.
    func presentSearch(_ invocation: SearchInvocation) {
        activeSearchRequestID = nil
        search.invocation = invocation
        search.criteria.query = ""
        search.criteria.selectedResultID = nil
        search.hits = []
        search.relatedItems = []
        search.errorMessage = nil
        search.isRunning = false
        switch invocation {
        case .general:
            search.criteria.scope = search.ordinaryScope.canonical
        case .findInNote(let previousScope):
            search.ordinaryScope = previousScope.canonical
            search.criteria.scope = .thisNote
        }
    }

    /// Dismissal retains only the ordinary scope. Query, selection, results,
    /// errors, and the active generation are deliberately transient.
    func dismissSearch() {
        activeSearchRequestID = nil
        let ordinaryScope: SearchPresentationScope = switch search.invocation {
        case .general:
            search.ordinaryScope.canonical
        case .findInNote(let previousScope):
            previousScope.canonical
        }
        search = DiscoverySearchState(
            criteria: SearchWorkspaceState(scope: ordinaryScope),
            ordinaryScope: ordinaryScope,
            invocation: .general
        )
    }

    func updateSearchQuery(_ query: String) {
        search.criteria.query = query
        invalidateSearchProjection()
    }

    func selectSearchScope(_ scope: SearchPresentationScope) {
        let canonical = scope.canonical
        search.criteria.scope = canonical
        search.criteria.selectedResultID = nil
        switch search.invocation {
        case .general:
            search.ordinaryScope = canonical
        case .findInNote:
            // An explicit scope choice converts temporary Find into ordinary
            // Search so closing it must not restore an older scope.
            search.ordinaryScope = canonical
            search.invocation = .general
        }
        invalidateSearchProjection()
    }

    /// A Search projection is meaningful only for the exact query and scope
    /// that produced it. Remove it synchronously while the replacement request
    /// is debounced so a visible row can never route through stale criteria.
    private func invalidateSearchProjection() {
        activeSearchRequestID = nil
        search.criteria.selectedResultID = nil
        search.hits = []
        search.relatedItems = []
        search.errorMessage = nil
        search.isRunning = !search.criteria.query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    @discardableResult
    func beginSearch(_ criteria: SearchWorkspaceState) -> DiscoverySearchRequest {
        let canonicalCriteria = SearchWorkspaceState(
            query: criteria.query,
            scope: criteria.scope.canonical,
            selectedRoles: criteria.selectedRoles,
            selectedResultID: nil
        )
        let request = DiscoverySearchRequest(id: UUID(), criteria: canonicalCriteria)
        activeSearchRequestID = request.id
        search.criteria = canonicalCriteria
        search.errorMessage = nil
        search.isRunning = !canonicalCriteria.query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        if !search.isRunning {
            search.hits = []
            search.relatedItems = []
        }
        return request
    }

    func receiveSearchResults(
        hits: [SearchHit],
        relatedItems: [RelatedSearchItem],
        for request: DiscoverySearchRequest
    ) {
        guard isCurrent(request) else { return }
        search.hits = hits
        search.relatedItems = relatedItems
        search.criteria.selectedResultID = hits.first.map(SearchResultIdentity.lexical)
            ?? relatedItems.first.map(SearchResultIdentity.related)
        search.errorMessage = nil
        search.isRunning = false
    }

    func failSearch(_ message: String, for request: DiscoverySearchRequest) {
        guard isCurrent(request) else { return }
        search.hits = []
        search.relatedItems = []
        search.criteria.selectedResultID = nil
        search.errorMessage = message
        search.isRunning = false
    }

    func cancelSearch() {
        dismissSearch()
    }

    func selectSearchResult(_ id: String?) {
        search.criteria.selectedResultID = id
    }

    func isCurrentSearch(_ request: DiscoverySearchRequest) -> Bool {
        isCurrent(request)
    }

    func reset() {
        activeLifecycleRequestID = nil
        activeSearchRequestID = nil
        library = DiscoveryLibraryState(
            workspaceSlot: library.workspaceSlot,
            sortOrder: library.sortOrder
        )
        let ordinaryScope = search.ordinaryScope
        search = DiscoverySearchState(
            criteria: SearchWorkspaceState(scope: ordinaryScope),
            ordinaryScope: ordinaryScope
        )
    }

    func requestOpen(
        _ reference: VaultNoteReference,
        sourceLocator: SourceLocator? = nil,
        disposition: WindowOpenDisposition = .replaceCurrent
    ) {
        intentHandler(.openDocument(WindowDocumentRoute(
            reference: reference,
            sourceLocator: sourceLocator,
            disposition: disposition
        )))
    }

    func requestOpen(
        _ result: SearchResultSelection,
        disposition: WindowOpenDisposition = .replaceCurrent
    ) {
        var route = result.documentRoute
        route = WindowDocumentRoute(
            reference: route.reference,
            sourceLocator: route.sourceLocator,
            disposition: disposition
        )
        intentHandler(.openDocument(route))
    }

    func requestSwitchVault(id: UUID) {
        intentHandler(.switchVault(id))
    }

    func requestLifecycle(_ request: NoteLifecycleRequest) {
        intentHandler(.presentLifecycle(request))
    }

    private func isCurrent(_ request: DiscoverySearchRequest) -> Bool {
        activeSearchRequestID == request.id
            && search.criteria.query == request.criteria.query
            && search.criteria.scope.canonical == request.criteria.scope.canonical
    }

    private func isCurrent(_ request: DiscoveryLifecycleRequest) -> Bool {
        activeLifecycleRequestID == request.id
            && library.lifecycleScope == request.scope
    }

    private func requireOperations() throws -> any DiscoveryUseCases {
        guard let operations else { throw WorkspaceRegistryError.incompleteWorkspace }
        return operations
    }
}
