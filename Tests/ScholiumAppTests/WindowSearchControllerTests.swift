import Combine
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@MainActor
private final class WindowSearchPresentationProbe {
    var hasCurrentNote = false
    var informationMessages: [String] = []
    var availabilityStatuses: [String?] = []
    var catalogFailureMessages: [String] = []
    var openCount = 0
}

@Suite("Window Search controller")
@MainActor
struct WindowSearchControllerTests {
    @Test("Late Search context cannot replace a newer query or revive dismissed Search", arguments: [false, true])
    func supersededContextIsDiscarded(dismissed: Bool) async {
        let discovery = DiscoveryController()
        let started = AsyncStream<Void>.makeStream()
        var release: CheckedContinuation<Void, Never>?
        var availability: [String?] = []
        let controller = WindowSearchController(
            discoveryController: discovery,
            dependencies: dependencies(
                executionContext: { state in
                    if state.query == "earlier" {
                        await withCheckedContinuation { continuation in
                            release = continuation
                            started.continuation.yield(())
                        }
                    }
                    return DiscoverySearchExecutionContext(
                        workspaceIsAvailable: false, currentNoteSnapshot: nil, currentVaultID: nil)
                },
                setAvailabilityStatus: { availability.append($0) }
            )
        )
        controller.begin(.general)
        controller.replaceQuery("earlier")
        let earlier = Task { await controller.refresh() }
        for await _ in started.stream { break }
        if dismissed {
            controller.dismiss()
        } else {
            controller.replaceQuery("current")
            await controller.refresh()
        }
        let expectedProjection = discovery.search
        let expectedAvailability = availability
        release?.resume()
        await earlier.value
        started.continuation.finish()
        #expect(discovery.search == expectedProjection)
        #expect(availability == expectedAvailability)
        #expect(controller.presentation == (dismissed ? .inactive : .sidebar))
    }

    @Test("Search request and response publish only changed coherent projections")
    func coherentProjectionPublication() {
        let discovery = DiscoveryController()
        var invalidations = 0
        let observation = discovery.objectWillChange.sink { invalidations += 1 }

        discovery.updateSearchQuery("indexed")
        #expect(invalidations == 1)

        invalidations = 0
        let request = discovery.beginSearch(discovery.search.criteria)
        discovery.selectSearchResult(nil)
        #expect(invalidations == 0)

        let generation = SearchGenerationID(
            triptychID: UUID(),
            sequence: 1,
            sourceManifestHash: "manifest"
        )
        discovery.receiveSearchResponse(
            SearchResponse(
                requestID: request.id,
                scope: .triptych,
                explanation: explanation(provider: .note),
                freshnessToken: .triptych(generation),
                availability: .current(generation),
                results: [],
                hasMore: false,
                indeterminateDocumentCount: 2
            ), for: request)

        #expect(discovery.search.indeterminateDocumentCount == 2)
        #expect(invalidations == 1)
        #expect(!discovery.search.isRunning)
        observation.cancel()
    }

    @Test("Discovery changes do not invalidate the Saved Search owner")
    func observationOwnership() async {
        let savedSearch = SavedSearch(
            name: "Owned Saved Search",
            definition: SearchDefinition(
                query: "ownership",
                presentationScope: .triptych
            )
        )
        let discovery = DiscoveryController()
        let controller = WindowSearchController(
            discoveryController: discovery,
            dependencies: dependencies(loadSavedSearches: { [savedSearch] })
        )
        var invalidations = 0
        let observation = controller.objectWillChange.sink { invalidations += 1 }

        discovery.replaceSearchCriteria(
            SearchWorkspaceState(
                query: "visible projection",
                scope: .currentVault
            ))
        #expect(invalidations == 0)

        controller.loadSavedSearches()
        await controller.waitForPendingWorkForTesting()
        #expect(controller.savedSearches == [savedSearch])
        #expect(invalidations == 1)
        observation.cancel()
    }

    @Test("Search presentation is owned without touching document persistence")
    func presentationLifecycle() {
        let discovery = DiscoveryController()
        let probe = WindowSearchPresentationProbe()
        let controller = WindowSearchController(
            discoveryController: discovery,
            dependencies: dependencies(
                hasCurrentNote: { probe.hasCurrentNote }
            )
        )

        controller.begin(.findInNote(previousScope: .currentVault))
        #expect(controller.presentation == .inactive)

        probe.hasCurrentNote = true
        controller.begin(.findInNote(previousScope: .currentVault))
        #expect(controller.presentation != .inactive)
        #expect(controller.criteria.scope == .thisNote)
        #expect(controller.ordinaryScope == .currentVault)

        controller.dismiss()
        #expect(controller.presentation == .inactive)
        #expect(controller.criteria.scope == .currentVault)
        #expect(controller.criteria.query.isEmpty)
    }

    @Test("Advanced Search retains the quick query and scope without a second session")
    func advancedSearchHandoff() {
        let discovery = DiscoveryController()
        let controller = WindowSearchController(discoveryController: discovery, dependencies: dependencies())
        controller.begin(.general)
        discovery.selectSearchScope(.currentVault)
        discovery.updateSearchQuery("aurora-fixture")
        let initialFocus = controller.focusRequestID
        controller.beginAdvanced()
        #expect(controller.presentation == .advanced)
        #expect(controller.criteria.query == "aurora-fixture")
        #expect(controller.criteria.scope == .currentVault)
        #expect(controller.focusRequestID > initialFocus)
        controller.begin(.general)
        #expect(controller.presentation == .sidebar)
        #expect(controller.criteria.query == "aurora-fixture")
        controller.dismiss()
        #expect(controller.presentation == .inactive)
        #expect(controller.criteria.query.isEmpty)
        #expect(controller.criteria.scope == .currentVault)
    }

    @Test("Saved Search loading and mutations are serialized by one owner")
    func savedSearchPersistence() async {
        let existing = SavedSearch(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            name: "Existing",
            definition: SearchDefinition(
                query: "existing",
                presentationScope: .currentVault
            ),
            createdAt: Date(timeIntervalSince1970: 1)
        )
        var savedSnapshots: [[SavedSearch]] = []
        let controller = WindowSearchController(
            discoveryController: DiscoveryController(),
            dependencies: dependencies(
                loadSavedSearches: {
                    try await Task.sleep(for: .milliseconds(10))
                    return [existing]
                },
                saveSavedSearches: {
                    savedSnapshots.append($0)
                }
            )
        )

        controller.loadSavedSearches()
        controller.criteria = SearchWorkspaceState(
            query: "current query",
            scope: .triptych
        )
        controller.saveCurrent(named: "First")
        controller.saveCurrent(named: "Second")
        await controller.waitForPendingWorkForTesting()

        #expect(controller.savedSearches.count == 3)
        #expect(savedSnapshots.count == 2)
        #expect(savedSnapshots[0].map(\.name) == ["First", "Existing"])
        #expect(savedSnapshots[1].map(\.name) == ["Second", "First", "Existing"])
        #expect(controller.savedSearches.map(\.name) == ["Second", "First", "Existing"])
    }

    @Test("Saved Search recovery clears the persistent load failure and reloads")
    func savedSearchRecovery() async {
        let recovered = SavedSearch(
            name: "Recovered",
            definition: SearchDefinition(query: "recovered", presentationScope: .triptych)
        )
        var needsRecovery = true
        let controller = WindowSearchController(
            discoveryController: DiscoveryController(),
            dependencies: dependencies(
                loadSavedSearches: {
                    if needsRecovery {
                        throw SavedSearchStoreError.unreadable("damaged")
                    }
                    return [recovered]
                },
                recoverSavedSearches: {
                    needsRecovery = false
                    return URL(fileURLWithPath: "/preserved/saved-searches.json")
                }
            )
        )

        controller.loadSavedSearches()
        await controller.waitForPendingWorkForTesting()
        #expect(controller.savedSearchLoadFailure != nil)

        await controller.recoverSavedSearches()

        #expect(controller.savedSearchLoadFailure == nil)
        #expect(controller.savedSearches.map(\.id) == [recovered.id])
    }

    @Test("A stale Note result preserves truthful recovery when refresh is unavailable or fails", arguments: [false, true])
    func staleNoteResult(refreshFails: Bool) async {
        let discovery = DiscoveryController()
        let generation = SearchGenerationID(
            triptychID: UUID(),
            sequence: 1,
            sourceManifestHash: "manifest"
        )
        let freshness = SearchFreshnessToken.triptych(generation)
        let fingerprint = DocumentFingerprint(content: "# Current\n")
        let hit = NoteSearchResult(
            vaultID: UUID(),
            vaultName: "Analyses",
            vaultRole: .sourceCorpus,
            relativePath: "Current.md",
            stableNoteID: nil,
            title: "Current",
            matchedField: .title,
            context: nil,
            sourceLine: 1,
            snippet: "Current",
            highlights: [],
            freshnessToken: freshness,
            fingerprint: fingerprint,
            evidentialLayer: .paperAnalysis,
            classification: .retrievalLead
        )
        let request = discovery.beginSearch(
            SearchWorkspaceState(
                query: "current",
                scope: .triptych
            ))
        discovery.receiveSearchResponse(
            SearchResponse(
                requestID: request.id,
                scope: .triptych,
                explanation: explanation(provider: .note),
                freshnessToken: freshness,
                availability: .current(generation),
                results: [.note(hit)],
                hasMore: false
            ), for: request)

        let probe = WindowSearchPresentationProbe()
        let refreshFailure = CocoaError(.fileReadUnknown)
        let controller = WindowSearchController(
            discoveryController: discovery,
            dependencies: WindowSearchController.Dependencies(
                loadSavedSearches: { [] },
                saveSavedSearches: { _ in },
                recoverSavedSearches: { nil },
                executionContext: { state in
                    #expect(state.query == "current")
                    #expect(state.scope == .triptych)
                    #expect(probe.informationMessages.count == 1)
                    #expect(probe.informationMessages.first?.contains("out of date") == true)
                    #expect(probe.informationMessages.first?.contains("were refreshed") == false)
                    if refreshFails { throw refreshFailure }
                    return DiscoverySearchExecutionContext(
                        workspaceIsAvailable: false,
                        currentNoteSnapshot: nil,
                        currentVaultID: nil
                    )
                },
                resultEvidence: { _, _ in
                    WindowSearchResultEvidence(
                        freshness: freshness,
                        fingerprint: DocumentFingerprint(content: "# Changed\n")
                    )
                },
                open: { _, _ in probe.openCount += 1 },
                hasCurrentNote: { true },
                reportInformation: { probe.informationMessages.append($0) },
                reportLoadFailure: { _ in },
                reportSaveFailure: { _ in },
                setAvailabilityStatus: { probe.availabilityStatuses.append($0) },
                reportCatalogFailure: { probe.catalogFailureMessages.append($0) }
            )
        )

        controller.beginAdvanced()
        #expect(await controller.open(.result(.note(hit)), disposition: .replaceCurrent) == false)

        #expect(probe.openCount == 0)
        #expect(probe.informationMessages.count == 1)
        #expect(probe.informationMessages[0].contains("Select a current result"))
        #expect(!probe.informationMessages[0].contains("were refreshed"))
        #expect(controller.presentation == .advanced)
        #expect(controller.criteria.query == "current")
        #expect(controller.criteria.scope == .triptych)
        #expect(!discovery.search.isRunning)
        if refreshFails {
            #expect(discovery.search.executionIssue == .failed(refreshFailure.localizedDescription))
            #expect(probe.availabilityStatuses.last == "Search failed")
            #expect(probe.catalogFailureMessages.count == 1)
            #expect(probe.catalogFailureMessages.first?.contains(refreshFailure.localizedDescription) == true)
        } else {
            #expect(discovery.search.executionIssue == DiscoverySearchExecutionError.workspaceUnavailable.searchIssue)
            #expect(probe.availabilityStatuses.last == "Search unavailable")
            #expect(probe.catalogFailureMessages.isEmpty)
        }
    }

    @Test("Current Saved Search runs through ordinary Search without a review step")
    func currentSavedSearchRuns() async {
        let saved = SavedSearch(
            name: "Emotion and reasons",
            definition: SearchDefinition(
                query: "paragraph:((情绪 OR emotion) AND reason)",
                presentationScope: .currentVault
            )
        )
        let discovery = DiscoveryController()
        let probe = WindowSearchPresentationProbe()
        var requestedStates: [SearchWorkspaceState] = []
        let controller = WindowSearchController(
            discoveryController: discovery,
            dependencies: dependencies(
                executionContext: { state in
                    requestedStates.append(state)
                    return DiscoverySearchExecutionContext(
                        workspaceIsAvailable: false,
                        currentNoteSnapshot: nil,
                        currentVaultID: nil
                    )
                },
                reportInformation: { probe.informationMessages.append($0) }
            )
        )
        controller.run(saved)
        await controller.refresh()
        #expect(controller.presentation != .inactive)
        #expect(controller.criteria.query == saved.definition.query)
        #expect(controller.criteria.scope == .currentVault)
        #expect(!requestedStates.isEmpty)
        #expect(requestedStates.allSatisfy { $0 == controller.criteria })
        #expect(probe.informationMessages.isEmpty)
        controller.dismiss()
    }

    @Test("Lexical completion uses the current Search scope")
    func lexicalCompletionUsesCurrentScope() async {
        let generation = SearchGenerationID(
            triptychID: UUID(),
            sequence: 4,
            sourceManifestHash: "completion-manifest"
        )
        var requests: [SearchCompletionRequest] = []
        let discovery = DiscoveryController()
        let controller = WindowSearchController(
            discoveryController: discovery,
            dependencies: dependencies(
                executionContext: { _ in
                    DiscoverySearchExecutionContext(
                        workspaceIsAvailable: true,
                        currentNoteSnapshot: nil,
                        currentVaultID: nil
                    )
                },
                searchCompletions: { request in
                    requests.append(request)
                    return SearchCompletionResponse(
                        requestID: request.id,
                        scope: request.presentationScope,
                        freshnessToken: .triptych(generation),
                        availability: .current(generation),
                        terms: [
                            SearchCompletionTerm(
                                text: "mitchell",
                                fields: [.body],
                                occurrenceCount: 3
                            )
                        ]
                    )
                }
            )
        )
        controller.criteria = SearchWorkspaceState(query: "mit", scope: .triptych)

        let terms = await controller.lexicalCompletionTerms(
            for: SearchCompletionLookup(partial: "mit")
        )

        #expect(terms.map(\.text) == ["mitchell"])
        #expect(requests.count == 1)
        #expect(requests.first?.presentationScope == .triptych)
        if case .triptych = requests.first?.executionScope {
            // The query's explicit presentation scope must remain the execution scope.
        } else {
            Issue.record("Lexical completion escaped the Triptych execution scope.")
        }
    }

    @Test("Search completion replaces only plain query text and follows Note capabilities")
    func completionContract() throws {
        let capabilities = SearchCapabilities.current
        let titleCompletion = try #require(
            capabilities.completions(
                for: "tit",
                scope: .triptych
            ).first
        )
        #expect(titleCompletion.replacementText == "title:")
        #expect(
            capabilities.capability(for: .note)?.fields.contains {
                $0.name == "property"
            } == true
        )
        #expect(
            capabilities.completions(
                for: "kind:unsupported part",
                scope: .triptych
            ).isEmpty)
    }

    private func dependencies(
        loadSavedSearches: @escaping @MainActor () async throws -> [SavedSearch] = { [] },
        saveSavedSearches: @escaping @MainActor ([SavedSearch]) async throws -> Void = { _ in },
        recoverSavedSearches: @escaping @MainActor () async throws -> URL? = { nil },
        executionContext:
            @escaping @MainActor (
                SearchWorkspaceState
            ) async throws -> DiscoverySearchExecutionContext = { _ in
                DiscoverySearchExecutionContext(
                    workspaceIsAvailable: false,
                    currentNoteSnapshot: nil,
                    currentVaultID: nil
                )
            },
        searchCompletions:
            @escaping @MainActor (
                SearchCompletionRequest
            ) async throws -> SearchCompletionResponse = { _ in
                throw CancellationError()
            },
        resultEvidence:
            @escaping @MainActor (
                SearchResult,
                SearchPresentationScope
            ) async -> WindowSearchResultEvidence = { _, _ in
                WindowSearchResultEvidence(freshness: nil, fingerprint: nil)
            },
        open:
            @escaping @MainActor (
                SearchResultSelection,
                WindowOpenDisposition
            ) async -> Void = { _, _ in },
        hasCurrentNote: @escaping @MainActor () -> Bool = { true },
        reportInformation: @escaping @MainActor (String) -> Void = { _ in },
        setAvailabilityStatus: @escaping @MainActor (String?) -> Void = { _ in }
    ) -> WindowSearchController.Dependencies {
        WindowSearchController.Dependencies(
            loadSavedSearches: loadSavedSearches,
            saveSavedSearches: saveSavedSearches,
            recoverSavedSearches: recoverSavedSearches,
            executionContext: executionContext,
            searchCompletions: searchCompletions,
            resultEvidence: resultEvidence,
            open: open,
            hasCurrentNote: hasCurrentNote,
            reportInformation: reportInformation,
            reportLoadFailure: { _ in },
            reportSaveFailure: { _ in },
            setAvailabilityStatus: setAvailabilityStatus,
            reportCatalogFailure: { _ in }
        )
    }

    private func explanation(
        provider: SearchProvider,
        explicit: Bool = false,
        scope: SearchPresentationScope = .triptych
    ) -> SearchExplanation {
        SearchExplanation(
            provider: provider,
            providerWasExplicit: explicit,
            scope: scope,
            expression: .and([])
        )
    }
}
