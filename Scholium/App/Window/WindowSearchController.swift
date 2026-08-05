import Combine
import Foundation
import ScholiumContracts

struct WindowSearchResultEvidence: Equatable, Sendable {
    let freshness: SearchFreshnessToken?
    let fingerprint: DocumentFingerprint?
}

/// Owns one window's Search execution, stale-result validation, and Saved
/// Search persistence lifecycle. `DiscoveryController` remains the owner of
/// the visible Search projection; the window composition root supplies only
/// current document evidence and navigation/presentation side effects.
@MainActor
final class WindowSearchController: ObservableObject {
    struct Dependencies {
        let loadSavedSearches: @MainActor () async throws -> [SavedSearch]
        let saveSavedSearches: @MainActor ([SavedSearch]) async throws -> Void
        let executionContext: @MainActor (
            SearchWorkspaceState
        ) async throws -> DiscoverySearchExecutionContext
        let resultEvidence: @MainActor (
            SearchResult,
            SearchPresentationScope
        ) async -> WindowSearchResultEvidence
        let open: @MainActor (
            SearchResultSelection,
            WindowOpenDisposition
        ) async -> Void
        let hasCurrentNote: @MainActor () -> Bool
        let isPresented: @MainActor () -> Bool
        let setPresented: @MainActor (Bool) -> Void
        let reportInformation: @MainActor (String) -> Void
        let reportLoadFailure: @MainActor (String) -> Void
        let reportSaveFailure: @MainActor (String) -> Void
        let setAvailabilityStatus: @MainActor (String?) -> Void
        let reportCatalogFailure: @MainActor (String) -> Void
    }

    @Published private(set) var savedSearches: [SavedSearch] = []

    private let discoveryController: DiscoveryController
    private let dependencies: Dependencies
    private var loadTask: Task<Void, Never>?
    private var savedSearchMutationTail: Task<Void, Never>?
    private var executionTask: Task<Void, Never>?
    private var executionID: UUID?

    init(
        discoveryController: DiscoveryController,
        dependencies: Dependencies
    ) {
        self.discoveryController = discoveryController
        self.dependencies = dependencies
    }

    deinit {
        loadTask?.cancel()
        executionTask?.cancel()
        savedSearchMutationTail?.cancel()
    }

    var criteria: SearchWorkspaceState {
        get { discoveryController.search.criteria }
        set { discoveryController.replaceSearchCriteria(newValue) }
    }

    var ordinaryScope: SearchPresentationScope {
        discoveryController.search.ordinaryScope
    }

    func loadSavedSearches() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let searches = try await dependencies.loadSavedSearches()
                guard !Task.isCancelled, savedSearches != searches else { return }
                savedSearches = searches
            } catch {
                dependencies.reportLoadFailure(error.localizedDescription)
            }
        }
    }

    /// Opens the one shared Search surface. Standard Find temporarily uses
    /// This Note and leaves the researcher's ordinary scope untouched.
    func begin(_ invocation: SearchInvocation) {
        if case .findInNote = invocation, !dependencies.hasCurrentNote() { return }
        discoveryController.presentSearch(invocation)
        dependencies.setPresented(true)
    }

    func dismiss() {
        cancelExecution()
        discoveryController.dismissSearch()
        dependencies.setPresented(false)
    }

    func refresh() async {
        executionTask?.cancel()
        let requestID = UUID()
        executionID = requestID
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performSearch(executionID: requestID)
        }
        executionTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if executionID == requestID {
            executionTask = nil
            executionID = nil
        }
    }

    func open(
        _ result: SearchResultSelection,
        disposition: WindowOpenDisposition
    ) async {
        guard case .result(let searchResult) = result else { return }
        guard discoveryController.search.freshnessToken == searchResult.freshnessToken else {
            await refreshAfterStaleResult(searchResult)
            return
        }
        let evidence = await dependencies.resultEvidence(
            searchResult,
            discoveryController.search.criteria.scope
        )
        guard evidence.freshness == searchResult.freshnessToken,
              evidence.fingerprint == searchResult.fingerprint else {
            await refreshAfterStaleResult(searchResult)
            return
        }
        await dependencies.open(.result(searchResult), disposition)
        dismiss()
    }

    func searchGenerationDidChange() {
        guard dependencies.isPresented(),
              !criteria.query.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ).isEmpty else { return }
        executionTask?.cancel()
        Task { [weak self] in await self?.refresh() }
    }

    func resetExecution() {
        cancelExecution()
    }

    #if DEBUG
    func waitForPendingWorkForTesting() async {
        await loadTask?.value
        await savedSearchMutationTail?.value
        await executionTask?.value
    }
    #endif

    func saveCurrent(named requestedName: String) {
        let name = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !criteria.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let state = criteria
        enqueueSavedSearchMutation { searches in
            var searches = searches
            searches.insert(SavedSearch(
                name: name,
                definition: SearchDefinition(
                    query: state.query,
                    presentationScope: state.scope
                )
            ), at: 0)
            return searches
        }
    }

    func run(_ search: SavedSearch) {
        if let diagnostic = search.needsEditingDiagnostic {
            cancelExecution()
            discoveryController.presentSavedSearchForEditing(
                search.definition,
                diagnostic: diagnostic
            )
            dependencies.setPresented(true)
            dependencies.reportInformation(diagnostic.message)
            return
        }
        criteria = SearchWorkspaceState(
            query: search.definition.query,
            scope: search.definition.presentationScope
        )
        dependencies.setPresented(true)
        Task { [weak self] in await self?.refresh() }
    }

    func delete(_ id: UUID) {
        enqueueSavedSearchMutation { searches in
            searches.filter { $0.id != id }
        }
    }

    func rename(_ id: UUID, to requestedName: String) {
        let name = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        enqueueSavedSearchMutation { searches in
            var searches = searches
            guard let index = searches.firstIndex(where: { $0.id == id }) else {
                return searches
            }
            searches[index].name = name
            return searches
        }
    }

    func move(_ id: UUID, by offset: Int) {
        guard offset != 0 else { return }
        enqueueSavedSearchMutation { searches in
            var searches = searches
            guard let source = searches.firstIndex(where: { $0.id == id }) else {
                return searches
            }
            let destination = min(max(0, source + offset), searches.count - 1)
            guard source != destination else { return searches }
            let search = searches.remove(at: source)
            searches.insert(search, at: destination)
            return searches
        }
    }

    private func performSearch(executionID: UUID) async {
        let state = criteria
        do {
            let context = try await dependencies.executionContext(state)
            try await discoveryController.executeSearch(state, context: context)
            dependencies.setAvailabilityStatus(nil)
        } catch is CancellationError {
            return
        } catch {
            guard self.executionID == executionID else { return }
            discoveryController.failPendingSearch(error.localizedDescription, for: state)
            dependencies.setAvailabilityStatus("Search unavailable")
            if !(error is DiscoverySearchExecutionError) {
                dependencies.reportCatalogFailure(
                    "Search refresh failed. \(error.localizedDescription)"
                )
            }
        }
    }

    private func refreshAfterStaleResult(_ result: SearchResult) async {
        let message = switch result {
        case .note:
            String(
                localized: "The note changed. Search results were refreshed.",
                table: "Localizable",
                bundle: .module
            )
        case .record:
            String(
                localized: "The Research Record changed. Search results were refreshed.",
                table: "Localizable",
                bundle: .module
            )
        }
        dependencies.reportInformation(
            message
        )
        await refresh()
    }

    private func cancelExecution() {
        executionTask?.cancel()
        executionTask = nil
        executionID = nil
    }

    private func enqueueSavedSearchMutation(
        _ mutation: @escaping @MainActor ([SavedSearch]) -> [SavedSearch]
    ) {
        let initialLoad = loadTask
        let previous = savedSearchMutationTail
        savedSearchMutationTail = Task { [weak self] in
            await initialLoad?.value
            _ = await previous?.value
            guard let self else { return }
            let proposed = mutation(savedSearches)
            guard proposed != savedSearches else { return }
            do {
                try await dependencies.saveSavedSearches(proposed)
                guard !Task.isCancelled else { return }
                savedSearches = proposed
            } catch {
                dependencies.reportSaveFailure(
                    String(
                        localized: "Could not save search: \(error.localizedDescription)",
                        table: "Localizable",
                        bundle: .module
                    )
                )
            }
        }
    }
}
