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
    var hits: [SearchHit] = []
    var relatedItems: [RelatedSearchItem] = []
    var errorMessage: String?
    var isRunning = false
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

struct DiscoveryQuickOpenState: Equatable, Sendable {
    var query = ""
    var results: [WorkspaceCatalogNote] = []
    var selectedResultID: WorkspaceCatalogNote.ID?
}

struct DiscoveryQuickOpenRequest: Equatable, Sendable {
    let id: UUID
    let query: String
}

/// Per-window owner for Library, Search, and Quick Open presentation state.
/// It accepts immutable results from Application operations and emits only
/// closed `WindowIntent` values for cross-feature routing.
@MainActor
final class DiscoveryController: ObservableObject {
    typealias IntentHandler = @MainActor (WindowIntent) -> Void

    @Published private(set) var library: DiscoveryLibraryState
    @Published private(set) var search = DiscoverySearchState()
    @Published private(set) var quickOpen = DiscoveryQuickOpenState()

    private var activeLifecycleRequestID: UUID?
    private var activeSearchRequestID: UUID?
    private var activeQuickOpenRequestID: UUID?
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
        resetQuickOpen()
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

    func quickOpenResults(
        query: String,
        limit: Int = 40
    ) async throws -> [WorkspaceCatalogNote] {
        try await requireOperations().quickOpen(query: query, limit: limit)
    }

    func selectLocationScope(_ scope: NoteLocationScope) {
        library.locationScope = scope
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
        search.criteria = SearchWorkspaceState(
            query: criteria.query,
            scope: criteria.scope.canonical,
            selectedRoles: criteria.selectedRoles,
            selectedResultID: criteria.selectedResultID
        )
    }

    func updateSearchQuery(_ query: String) {
        search.criteria.query = query
        search.criteria.selectedResultID = nil
    }

    func selectSearchScope(_ scope: SearchPresentationScope) {
        search.criteria.scope = scope.canonical
        search.criteria.selectedResultID = nil
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
        activeSearchRequestID = nil
        search = DiscoverySearchState(criteria: search.criteria)
    }

    func selectSearchResult(_ id: String?) {
        search.criteria.selectedResultID = id
    }

    func isCurrentSearch(_ request: DiscoverySearchRequest) -> Bool {
        isCurrent(request)
    }

    @discardableResult
    func beginQuickOpen(_ query: String) -> DiscoveryQuickOpenRequest {
        let request = DiscoveryQuickOpenRequest(id: UUID(), query: query)
        activeQuickOpenRequestID = request.id
        quickOpen.query = query
        quickOpen.results = []
        quickOpen.selectedResultID = nil
        return request
    }

    func updateQuickOpenQuery(_ query: String) {
        quickOpen.query = query
    }

    func receiveQuickOpenResults(
        _ results: [WorkspaceCatalogNote],
        for request: DiscoveryQuickOpenRequest
    ) {
        guard activeQuickOpenRequestID == request.id,
              quickOpen.query == request.query else { return }
        quickOpen.results = results
        quickOpen.selectedResultID = results.first?.id
    }

    func selectQuickOpenResult(_ id: WorkspaceCatalogNote.ID?) {
        quickOpen.selectedResultID = id
    }

    func moveQuickOpenSelection(by delta: Int) {
        guard !quickOpen.results.isEmpty else { return }
        let current = quickOpen.selectedResultID.flatMap { selectedID in
            quickOpen.results.firstIndex(where: { $0.id == selectedID })
        } ?? 0
        let next = min(quickOpen.results.count - 1, max(0, current + delta))
        quickOpen.selectedResultID = quickOpen.results[next].id
    }

    func resetQuickOpen() {
        activeQuickOpenRequestID = nil
        quickOpen = DiscoveryQuickOpenState()
    }

    func reset() {
        activeLifecycleRequestID = nil
        activeSearchRequestID = nil
        activeQuickOpenRequestID = nil
        library = DiscoveryLibraryState(sortOrder: library.sortOrder)
        search = DiscoverySearchState()
        quickOpen = DiscoveryQuickOpenState()
    }

    func requestOpen(
        _ reference: VaultNoteReference,
        sourceLocator: SourceLocator? = nil,
        inNewTab: Bool = false
    ) {
        intentHandler(.openDocument(WindowDocumentRoute(
            reference: reference,
            sourceLocator: sourceLocator,
            opensInNewTab: inNewTab
        )))
    }

    func requestOpen(_ result: SearchResultSelection, inNewTab: Bool = false) {
        var route = result.documentRoute
        route = WindowDocumentRoute(
            reference: route.reference,
            sourceLocator: route.sourceLocator,
            opensInNewTab: inNewTab
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
