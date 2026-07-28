import ScholiumContracts
import Combine
import Foundation

struct DiscoveryFilterState: Equatable, Sendable {
    var needsAttention = false
    var hasExplicitConnections = false
    var hasMalformedMetadata = false
    var tag: String?
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
    var capturedWorkspaceNotes: [WindowDocumentLocation] = []
    var preparedLifecyclePath: String?
    var showsUnclassified = false
    var showsAttentionQueue = false
    /// Nil presents the Triptych-wide queue. Inspector entry supplies the
    /// current Note so the same Library-owned surface can present its bounded
    /// subset without creating a second Attention destination.
    var attentionNoteScope: VaultQualifiedNoteID?
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
    var relatedAvailability: RelatedSearchAvailability = .notApplicable
    var selectedResultID: String?
    var responseRequestID: UUID?
    var freshnessToken: SearchFreshnessToken?
    var availability: SearchAvailability = .unavailable
    var diagnostics: [SearchQueryDiagnostic] = []
    var hasMore = false
    var errorMessage: String?
    var relatedErrorMessage: String?
    var isLoadingRelated = false
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
    let currentNoteSnapshot: SearchSourceSnapshot?
    let currentVaultID: UUID?
}

enum DiscoverySearchExecutionError: LocalizedError, Equatable, Sendable {
    case workspaceUnavailable

    var errorDescription: String? {
        switch self {
        case .workspaceUnavailable:
            String(localized: "Open a complete Triptych before searching.", table: "Localizable", bundle: .module)
        }
    }
}

struct DiscoveryLifecycleRequest: Equatable, Sendable {
    let id: UUID
    let scope: NoteLocationScope
}

/// Per-window owner for Library and Search presentation state. Document tabs
/// borrow one window-owned peripheral presentation so switching documents
/// never appears to rebuild the Library tree.
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
    private let peripheralPresentation: WindowPeripheralPresentationState
    private var operations: (any DiscoveryUseCases)?
    private var cancellables: Set<AnyCancellable> = []

    init(
        initialLibraryState: DiscoveryLibraryState = DiscoveryLibraryState(),
        peripheralPresentation: WindowPeripheralPresentationState = WindowPeripheralPresentationState(),
        intentHandler: @escaping IntentHandler = { _ in }
    ) {
        library = initialLibraryState
        self.peripheralPresentation = peripheralPresentation
        self.intentHandler = intentHandler
        peripheralPresentation.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
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

    func search(_ request: SearchRequest) async throws -> SearchResponse {
        try await requireOperations().search(request)
    }

    func relatedResults(
        query: String,
        scope: SearchExecutionScope,
        searchGeneration: SearchGenerationID?,
        excluding: Set<VaultQualifiedNoteID> = [],
        limit: Int = 12
    ) async throws -> RelatedSearchResponse {
        try await requireOperations().related(
            query: query,
            scope: scope,
            searchGeneration: searchGeneration,
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

        let scope = request.criteria.scope
        let resolvedScope: SearchExecutionScope? = switch scope {
        case .thisNote:
            if let snapshot = context.currentNoteSnapshot {
                .currentNote(snapshot)
            } else {
                nil
            }
        case .currentVault:
            if let vaultID = context.currentVaultID {
                .currentVault(vaultID)
            } else {
                nil
            }
        case .triptych:
            .triptych
        }
        guard let applicationScope = resolvedScope else {
            let error = DiscoverySearchExecutionError.workspaceUnavailable
            failSearch(error.localizedDescription, for: request)
            throw error
        }
        let limit = SearchContractV4.maximumInterfaceResults

        do {
            let response = try await search(SearchRequest(
                id: request.id,
                query: query,
                presentationScope: scope,
                executionScope: applicationScope,
                limit: limit
            ))
            guard isCurrentSearch(request) else { return }
            receiveSearchResponse(response, for: request)
            guard response.diagnostics.isEmpty else { return }
            let excluded = Set(response.results.map {
                VaultQualifiedNoteID(vaultID: $0.vaultID, relativePath: $0.relativePath)
            })
            beginRelated(for: request)
            do {
                let related = try await relatedResults(
                    query: query,
                    scope: applicationScope,
                    searchGeneration: response.availability.lastGoodGeneration,
                    excluding: excluded
                )
                guard isCurrentSearch(request) else { return }
                receiveRelatedResults(related, for: request)
            } catch is CancellationError {
                return
            } catch {
                guard isCurrentSearch(request) else { return }
                failRelated(error.localizedDescription, for: request)
            }
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

    func expandedFolders(in scope: LibraryDisclosureScope?) -> Set<String> {
        peripheralPresentation.expandedFolders(in: scope)
    }

    func setExpandedFolders(
        _ folders: Set<String>,
        in scope: LibraryDisclosureScope?
    ) {
        peripheralPresentation.setExpandedFolders(folders, in: scope)
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

    func showAttentionQueue(
        _ isPresented: Bool,
        note: VaultQualifiedNoteID? = nil
    ) {
        library.showsAttentionQueue = isPresented
        library.attentionNoteScope = isPresented ? note : nil
        if isPresented { dismissLifecycleListing() }
    }

    func presentLifecycleListing(_ scope: NoteLocationScope) {
        activeLifecycleRequestID = nil
        library.showsAttentionQueue = false
        library.attentionNoteScope = nil
        library.lifecycleScope = scope
        library.lifecycleItems = []
        library.lifecycleError = nil
        library.lifecycleIsLoading = true
    }

    @discardableResult
    func beginLifecycleListing(_ scope: NoteLocationScope) -> DiscoveryLifecycleRequest {
        let request = DiscoveryLifecycleRequest(id: UUID(), scope: scope)
        activeLifecycleRequestID = request.id
        library.showsAttentionQueue = false
        library.attentionNoteScope = nil
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
        let scope = criteria.scope
        search.criteria = SearchWorkspaceState(
            query: criteria.query,
            scope: scope
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
        search.selectedResultID = nil
        search.responseRequestID = nil
        search.freshnessToken = nil
        search.hits = []
        search.relatedItems = []
        search.relatedAvailability = .notApplicable
        search.diagnostics = []
        search.hasMore = false
        search.errorMessage = nil
        search.relatedErrorMessage = nil
        search.isLoadingRelated = false
        search.isRunning = false
        switch invocation {
        case .general:
            search.criteria.scope = search.ordinaryScope
        case .findInNote(let previousScope):
            search.ordinaryScope = previousScope
            search.criteria.scope = .thisNote
        }
    }

    /// Dismissal retains only the ordinary scope. Query, selection, results,
    /// errors, and the active generation are deliberately transient.
    func dismissSearch() {
        activeSearchRequestID = nil
        let ordinaryScope: SearchPresentationScope = switch search.invocation {
        case .general:
            search.ordinaryScope
        case .findInNote(let previousScope):
            previousScope
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
        search.criteria.scope = scope
        search.selectedResultID = nil
        search.responseRequestID = nil
        search.freshnessToken = nil
        switch search.invocation {
        case .general:
            search.ordinaryScope = scope
        case .findInNote:
            // An explicit scope choice converts temporary Find into ordinary
            // Search so closing it must not restore an older scope.
            search.ordinaryScope = scope
            search.invocation = .general
        }
        invalidateSearchProjection()
    }

    /// A Search projection is meaningful only for the exact query and scope
    /// that produced it. Remove it synchronously before the replacement
    /// cancellable request so a visible row can never route through stale criteria.
    private func invalidateSearchProjection() {
        activeSearchRequestID = nil
        search.selectedResultID = nil
        search.responseRequestID = nil
        search.freshnessToken = nil
        search.hits = []
        search.relatedItems = []
        search.relatedAvailability = .notApplicable
        search.diagnostics = []
        search.hasMore = false
        search.errorMessage = nil
        search.relatedErrorMessage = nil
        search.isLoadingRelated = false
        search.isRunning = !search.criteria.query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    @discardableResult
    func beginSearch(_ criteria: SearchWorkspaceState) -> DiscoverySearchRequest {
        let canonicalCriteria = SearchWorkspaceState(
            query: criteria.query,
            scope: criteria.scope
        )
        let request = DiscoverySearchRequest(id: UUID(), criteria: canonicalCriteria)
        activeSearchRequestID = request.id
        search.criteria = canonicalCriteria
        search.responseRequestID = nil
        search.freshnessToken = nil
        search.errorMessage = nil
        search.relatedErrorMessage = nil
        search.diagnostics = []
        search.hasMore = false
        search.isRunning = !canonicalCriteria.query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        if !search.isRunning {
            search.hits = []
            search.relatedItems = []
            search.relatedAvailability = .notApplicable
        }
        return request
    }

    func receiveSearchResponse(
        _ response: SearchResponse,
        for request: DiscoverySearchRequest
    ) {
        guard isCurrent(request), response.requestID == request.id else { return }
        search.hits = response.results
        search.relatedItems = []
        search.relatedAvailability = .notApplicable
        search.selectedResultID = nil
        search.responseRequestID = response.requestID
        search.freshnessToken = response.freshnessToken
        search.availability = response.availability
        search.diagnostics = response.diagnostics
        search.hasMore = response.hasMore
        search.errorMessage = nil
        search.isRunning = false
    }

    private func beginRelated(for request: DiscoverySearchRequest) {
        guard isCurrent(request) else { return }
        search.isLoadingRelated = true
        search.relatedErrorMessage = nil
    }

    private func receiveRelatedResults(
        _ response: RelatedSearchResponse,
        for request: DiscoverySearchRequest
    ) {
        guard isCurrent(request) else { return }
        search.relatedItems = response.items
        search.relatedAvailability = response.availability
        search.relatedErrorMessage = nil
        search.isLoadingRelated = false
    }

    private func failRelated(_ message: String, for request: DiscoverySearchRequest) {
        guard isCurrent(request) else { return }
        search.relatedItems = []
        search.relatedAvailability = .notApplicable
        search.relatedErrorMessage = message
        search.isLoadingRelated = false
    }

    func failSearch(_ message: String, for request: DiscoverySearchRequest) {
        guard isCurrent(request) else { return }
        completeSearchFailure(message)
    }

    /// Ends a Search that failed while preparing its execution context, before
    /// `executeSearch` could install a request ID. The criteria guard prevents
    /// a late editor-bridge failure from clearing a newer query or scope.
    func failPendingSearch(_ message: String, for criteria: SearchWorkspaceState) {
        guard search.criteria == criteria else { return }
        activeSearchRequestID = nil
        completeSearchFailure(message)
    }

    private func completeSearchFailure(_ message: String) {
        search.hits = []
        search.relatedItems = []
        search.relatedAvailability = .notApplicable
        search.selectedResultID = nil
        search.responseRequestID = nil
        search.freshnessToken = nil
        search.diagnostics = []
        search.hasMore = false
        search.errorMessage = message
        search.relatedErrorMessage = nil
        search.isLoadingRelated = false
        search.isRunning = false
    }

    func cancelSearch() {
        dismissSearch()
    }

    func selectSearchResult(_ id: String?) {
        search.selectedResultID = id
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
        if case .lexical = result {
            guard responseRequestIDIsCurrent else { return }
        }
        intentHandler(.openSearchResult(result, disposition: disposition))
    }

    func requestLifecycle(_ request: NoteLifecycleRequest) {
        intentHandler(.presentLifecycle(request))
    }

    private func isCurrent(_ request: DiscoverySearchRequest) -> Bool {
        activeSearchRequestID == request.id
            && search.criteria.query == request.criteria.query
            && search.criteria.scope == request.criteria.scope
    }

    private var responseRequestIDIsCurrent: Bool {
        guard let responseRequestID = search.responseRequestID else { return false }
        return responseRequestID == activeSearchRequestID
            && search.hits.allSatisfy { $0.freshnessToken == search.freshnessToken }
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
