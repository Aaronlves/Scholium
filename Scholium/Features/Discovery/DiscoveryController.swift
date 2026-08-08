import ScholiumContracts
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
    /// The Library presentation retained for one Triptych workspace. The
    /// window transition owner changes it together with that workspace's tab,
    /// Document, and Inspector context.
    var workspaceSlot: WorkspaceVaultSlot = .paperAnalysis
    var locationScope: NoteLocationScope = .workspace
    var filters = DiscoveryFilterState()
    var sortOrder: NoteSortOrder = .modifiedNewest
    var locationIsLoading = false
    var locationError: String?
}

struct DiscoverySearchState: Equatable, Sendable {
    var criteria = SearchWorkspaceState()
    var ordinaryScope: SearchPresentationScope = .triptych
    var invocation: SearchInvocation = .general
    var explanation: SearchExplanation?
    var results: [SearchResult] = []
    var selectedResultID: String?
    var responseRequestID: UUID?
    var freshnessToken: SearchFreshnessToken?
    var availability: SearchProviderAvailability = .note(.unavailable)
    var diagnostics: [SearchQueryDiagnostic] = []
    var hasMore = false
    var executionIssue: SearchExecutionIssue?
    var isRunning = false
}

/// Search-owned classification for failures that occur before a provider can
/// return its typed availability. It preserves the distinction between a
/// missing execution prerequisite and an operation that actually failed.
enum SearchExecutionIssue: Equatable, Sendable {
    case unavailable(String)
    case failed(String)
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
    case currentNoteUnavailable
    case currentVaultUnavailable

    var errorDescription: String? {
        switch self {
        case .workspaceUnavailable:
            String(localized: "Open a complete Triptych before searching.", table: "Localizable", bundle: .module)
        case .currentNoteUnavailable:
            String(localized: "Open a note before searching This Note.", table: "Localizable", bundle: .module)
        case .currentVaultUnavailable:
            String(localized: "Select an available vault before searching This Vault.", table: "Localizable", bundle: .module)
        }
    }

    var searchIssue: SearchExecutionIssue {
        switch self {
        case .workspaceUnavailable, .currentNoteUnavailable, .currentVaultUnavailable:
            .unavailable(localizedDescription)
        }
    }
}

/// Identity for one asynchronous Source List replacement. A result is valid
/// only for the exact workspace and Location that requested it; a later
/// request for that workspace invalidates it before visible commit.
struct DiscoveryLocationRequest: Equatable, Sendable {
    let id: UUID
    let workspaceSlot: WorkspaceVaultSlot
    let location: NoteLocationScope
    let presentation: DiscoveryLocationRequestPresentation
}

enum DiscoveryLocationRequestPresentation: Equatable, Sendable {
    /// No trustworthy committed Source List is available for the requested
    /// projection, so the Location page must expose its loading/error states.
    case contentLoading
    /// Ordinary workspace/Location navigation stages a complete target while
    /// the last committed session remains visible, then replaces it atomically.
    case stagedReplacement
}

struct DiscoveryLibraryRevealRequest: Equatable, Sendable {
    enum Alignment: Equatable, Sendable {
        /// Scroll only as much as needed to expose a navigation destination.
        case nearest
        /// Center a newly created row so its successful appearance is clear.
        case center
    }

    let generation: UInt64
    let scope: LibraryDisclosureScope
    let relativePath: String
    let alignment: Alignment
}

/// Per-window owner for Library and Search presentation state. Document tabs
/// borrow one window-owned peripheral presentation so switching documents
/// never appears to rebuild the Library tree.
/// It accepts immutable results from Application operations and emits only
/// closed `WindowIntent` values for cross-feature routing.
@MainActor
final class DiscoveryController: ObservableObject {
    typealias IntentHandler = @MainActor (WindowIntent) -> Void

    @Published private var librariesByWorkspace: [WorkspaceVaultSlot: DiscoveryLibraryState]
    @Published private(set) var libraryRevealRequest: DiscoveryLibraryRevealRequest?
    @Published private(set) var search = DiscoverySearchState()

    private var activeLocationRequests: [WorkspaceVaultSlot: DiscoveryLocationRequest] = [:]
    private var activeSearchRequestID: UUID?
    private var nextLibraryRevealGeneration: UInt64 = 0
    private let intentHandler: IntentHandler
    private let shellState: WindowShellState
    private var operations: (any DiscoveryUseCases)?

    init(
        initialLibraryState: DiscoveryLibraryState = DiscoveryLibraryState(),
        shellState: WindowShellState = WindowShellState(),
        intentHandler: @escaping IntentHandler = { _ in }
    ) {
        librariesByWorkspace = Dictionary(
            uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { workspace in
                var state = initialLibraryState
                state.workspaceSlot = workspace
                return (workspace, state)
            }
        )
        self.shellState = shellState
        self.intentHandler = intentHandler
    }

    var library: DiscoveryLibraryState {
        libraryState(for: shellState.selectedWorkspace)
    }

    func libraryState(for workspace: WorkspaceVaultSlot) -> DiscoveryLibraryState {
        librariesByWorkspace[workspace] ?? DiscoveryLibraryState(workspaceSlot: workspace)
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

    /// Owns the complete Search use case for one window. The window shell
    /// supplies only current navigation identities and handles presentation
    /// of a reported failure.
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
            failSearch(error.searchIssue, for: request)
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
            let error: DiscoverySearchExecutionError = switch scope {
            case .thisNote:
                .currentNoteUnavailable
            case .currentVault:
                .currentVaultUnavailable
            case .triptych:
                .workspaceUnavailable
            }
            failSearch(error.searchIssue, for: request)
            throw error
        }
        let limit = SearchContract.maximumInterfaceResults

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
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentSearch(request) else { return }
            failSearch(.failed(error.localizedDescription), for: request)
            throw error
        }
    }

    /// Installs a coherent workspace/Location pair after an initial restore or a
    /// fully staged synchronous projection. Asynchronous browsing must use the
    /// request methods below so late results can be rejected.
    func synchronizeLibrarySelection(
        workspaceSlot: WorkspaceVaultSlot,
        location: NoteLocationScope
    ) {
        activeLocationRequests[workspaceSlot] = nil
        updateLibraryState(for: workspaceSlot) { library in
            library.workspaceSlot = workspaceSlot
            library.locationScope = location
            library.locationIsLoading = false
            library.locationError = nil
        }
    }

    @discardableResult
    func beginLocationRequest(
        workspaceSlot: WorkspaceVaultSlot,
        location: NoteLocationScope,
        presentation: DiscoveryLocationRequestPresentation = .contentLoading
    ) -> DiscoveryLocationRequest {
        let request = DiscoveryLocationRequest(
            id: UUID(),
            workspaceSlot: workspaceSlot,
            location: location,
            presentation: presentation
        )
        activeLocationRequests[workspaceSlot] = request
        updateLibraryState(for: workspaceSlot) { library in
            library.locationIsLoading = presentation == .contentLoading
            library.locationError = nil
        }
        return request
    }

    @discardableResult
    func receiveLocationResult(for request: DiscoveryLocationRequest) -> Bool {
        guard isCurrent(request) else { return false }
        activeLocationRequests[request.workspaceSlot] = nil
        updateLibraryState(for: request.workspaceSlot) { library in
            library.workspaceSlot = request.workspaceSlot
            library.locationScope = request.location
            library.locationIsLoading = false
            library.locationError = nil
        }
        return true
    }

    func failLocationRequest(
        _ message: String,
        for request: DiscoveryLocationRequest
    ) {
        guard isCurrent(request) else { return }
        activeLocationRequests[request.workspaceSlot] = nil
        updateLibraryState(for: request.workspaceSlot) { library in
            library.locationIsLoading = false
            library.locationError = request.presentation == .contentLoading ? message : nil
        }
    }

    func replaceFilters(_ filters: DiscoveryFilterState) {
        updateLibraryState(for: shellState.selectedWorkspace) { $0.filters = filters }
    }

    func selectSortOrder(_ order: NoteSortOrder) {
        updateLibraryState(for: shellState.selectedWorkspace) { $0.sortOrder = order }
    }

    func expandedFolders(in scope: LibraryDisclosureScope?) -> Set<String> {
        shellState.expandedFolders(in: scope)
    }

    func setExpandedFolders(
        _ folders: Set<String>,
        in scope: LibraryDisclosureScope?
    ) {
        shellState.setExpandedFolders(folders, in: scope)
    }

    /// Makes one successfully created Note visible without introducing a
    /// parallel tree or taking keyboard focus from the action's natural next
    /// destination. Sort remains independently owned and otherwise unchanged.
    func prepareCreatedNoteReveal(
        relativePath: String,
        folderAncestors: Set<String>,
        in scope: LibraryDisclosureScope
    ) {
        prepareLibraryNoteReveal(
            relativePath: relativePath,
            folderAncestors: folderAncestors,
            clearFilters: true,
            alignment: .center,
            in: scope
        )
    }

    /// Reveals one exact selected Note after any in-app navigation without
    /// moving keyboard focus. Filters are cleared only when they actually hide
    /// that destination; unrelated disclosure and sort state remain intact.
    func prepareLibraryNoteReveal(
        relativePath: String,
        folderAncestors: Set<String>,
        clearFilters: Bool,
        alignment: DiscoveryLibraryRevealRequest.Alignment = .nearest,
        in scope: LibraryDisclosureScope
    ) {
        if clearFilters {
            updateLibraryState(for: shellState.selectedWorkspace) {
                $0.filters = DiscoveryFilterState()
            }
        }
        var expanded = expandedFolders(in: scope)
        expanded.formUnion(folderAncestors)
        setExpandedFolders(expanded, in: scope)
        nextLibraryRevealGeneration &+= 1
        libraryRevealRequest = DiscoveryLibraryRevealRequest(
            generation: nextLibraryRevealGeneration,
            scope: scope,
            relativePath: relativePath,
            alignment: alignment
        )
    }

    func consumeLibraryRevealRequest(_ request: DiscoveryLibraryRevealRequest) {
        guard libraryRevealRequest == request else { return }
        libraryRevealRequest = nil
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
        search.explanation = nil
        search.selectedResultID = nil
        search.responseRequestID = nil
        search.freshnessToken = nil
        search.results = []
        search.diagnostics = []
        search.hasMore = false
        search.executionIssue = nil
        search.isRunning = false
        switch invocation {
        case .general:
            search.criteria.scope = search.ordinaryScope
        case .findInNote(let previousScope):
            search.ordinaryScope = previousScope
            search.criteria.scope = .thisNote
        }
    }

    /// Installs a stale Saved Search as visible, editable plain text without
    /// executing it under a newer contract. Editing the query clears this
    /// diagnostic through the ordinary invalidation path.
    func presentSavedSearchForEditing(
        _ definition: SearchDefinition,
        diagnostic: SearchQueryDiagnostic
    ) {
        activeSearchRequestID = nil
        search.invocation = .general
        search.criteria = SearchWorkspaceState(
            query: definition.query,
            scope: definition.presentationScope
        )
        search.ordinaryScope = definition.presentationScope
        search.explanation = nil
        search.results = []
        search.selectedResultID = nil
        search.responseRequestID = nil
        search.freshnessToken = nil
        search.diagnostics = [diagnostic]
        search.hasMore = false
        search.executionIssue = nil
        search.isRunning = false
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
        search.explanation = nil
        search.results = []
        search.diagnostics = []
        search.hasMore = false
        search.executionIssue = nil
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
        search.executionIssue = nil
        search.explanation = nil
        search.diagnostics = []
        search.hasMore = false
        search.isRunning = !canonicalCriteria.query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        if !search.isRunning {
            search.results = []
        }
        return request
    }

    func receiveSearchResponse(
        _ response: SearchResponse,
        for request: DiscoverySearchRequest
    ) {
        guard isCurrent(request), response.requestID == request.id else { return }
        search.results = response.results
        search.selectedResultID = nil
        search.responseRequestID = response.requestID
        search.freshnessToken = response.freshnessToken
        search.explanation = response.explanation
        search.availability = response.availability
        search.diagnostics = response.diagnostics
        search.hasMore = response.hasMore
        search.executionIssue = nil
        search.isRunning = false
    }

    func failSearch(
        _ issue: SearchExecutionIssue,
        for request: DiscoverySearchRequest
    ) {
        guard isCurrent(request) else { return }
        completeSearchFailure(issue)
    }

    /// Ends a Search that failed while preparing its execution context, before
    /// `executeSearch` could install a request ID. The criteria guard prevents
    /// a late editor-bridge failure from clearing a newer query or scope.
    func failPendingSearch(
        _ issue: SearchExecutionIssue,
        for criteria: SearchWorkspaceState
    ) {
        guard search.criteria == criteria else { return }
        activeSearchRequestID = nil
        completeSearchFailure(issue)
    }

    private func completeSearchFailure(_ issue: SearchExecutionIssue) {
        search.results = []
        search.selectedResultID = nil
        search.responseRequestID = nil
        search.freshnessToken = nil
        search.explanation = nil
        search.diagnostics = []
        search.hasMore = false
        search.executionIssue = issue
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
        activeLocationRequests = [:]
        activeSearchRequestID = nil
        libraryRevealRequest = nil
        librariesByWorkspace = Dictionary(
            uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { workspace in
                let current = libraryState(for: workspace)
                return (
                    workspace,
                    DiscoveryLibraryState(
                        workspaceSlot: workspace,
                        locationScope: current.locationScope,
                        sortOrder: current.sortOrder
                    )
                )
            }
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
        guard responseRequestIDIsCurrent else { return }
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
            && search.results.allSatisfy { $0.freshnessToken == search.freshnessToken }
    }

    func isCurrentLocationRequest(_ request: DiscoveryLocationRequest) -> Bool {
        isCurrent(request)
    }

    /// A second explicit workspace/Location choice must be able to supersede an
    /// in-flight request even when it chooses the still-visible committed
    /// value. The committed pair alone cannot reveal that pending intent.
    var locationRequestIsActive: Bool {
        activeLocationRequests[shellState.selectedWorkspace] != nil
    }

    private func isCurrent(_ request: DiscoveryLocationRequest) -> Bool {
        activeLocationRequests[request.workspaceSlot] == request
    }

    private func updateLibraryState(
        for workspace: WorkspaceVaultSlot,
        _ update: (inout DiscoveryLibraryState) -> Void
    ) {
        var state = libraryState(for: workspace)
        update(&state)
        librariesByWorkspace[workspace] = state
    }

    private func requireOperations() throws -> any DiscoveryUseCases {
        guard let operations else { throw WorkspaceRegistryError.incompleteWorkspace }
        return operations
    }
}
