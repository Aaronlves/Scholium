import Combine
import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@MainActor
private final class WindowSearchPresentationProbe {
    var isPresented = false
    var hasCurrentNote = false
    var informationMessages: [String] = []
    var openCount = 0
}

@Suite("Window Search controller")
@MainActor
struct WindowSearchControllerTests {
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
        discovery.receiveSearchResponse(SearchResponse(
            requestID: request.id,
            scope: .triptych,
            explanation: explanation(provider: .note),
            freshnessToken: .triptych(generation),
            availability: .note(.current(generation)),
            results: [],
            hasMore: false
        ), for: request)

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

        discovery.replaceSearchCriteria(SearchWorkspaceState(
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
                hasCurrentNote: { probe.hasCurrentNote },
                isPresented: { probe.isPresented },
                setPresented: { probe.isPresented = $0 }
            )
        )

        controller.begin(.findInNote(previousScope: .currentVault))
        #expect(!probe.isPresented)

        probe.hasCurrentNote = true
        controller.begin(.findInNote(previousScope: .currentVault))
        #expect(probe.isPresented)
        #expect(controller.criteria.scope == .thisNote)
        #expect(controller.ordinaryScope == .currentVault)

        controller.dismiss()
        #expect(!probe.isPresented)
        #expect(controller.criteria.scope == .currentVault)
        #expect(controller.criteria.query.isEmpty)
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

    @Test("A stale Note result is never routed and refreshes the active query")
    func staleNoteResult() async {
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
        let request = discovery.beginSearch(SearchWorkspaceState(
            query: "current",
            scope: .triptych
        ))
        discovery.receiveSearchResponse(SearchResponse(
            requestID: request.id,
            scope: .triptych,
            explanation: explanation(provider: .note),
            freshnessToken: freshness,
            availability: .note(.current(generation)),
            results: [.note(hit)],
            hasMore: false
        ), for: request)

        let probe = WindowSearchPresentationProbe()
        probe.isPresented = true
        let controller = WindowSearchController(
            discoveryController: discovery,
            dependencies: WindowSearchController.Dependencies(
                loadSavedSearches: { [] },
                saveSavedSearches: { _ in },
                recoverSavedSearches: { nil },
                executionContext: { _ in
                    DiscoverySearchExecutionContext(
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
                isPresented: { probe.isPresented },
                setPresented: { probe.isPresented = $0 },
                reportInformation: { probe.informationMessages.append($0) },
                reportLoadFailure: { _ in },
                reportSaveFailure: { _ in },
                setAvailabilityStatus: { _ in },
                reportCatalogFailure: { _ in }
            )
        )

        await controller.open(.result(.note(hit)), disposition: .replaceCurrent)

        #expect(probe.openCount == 0)
        #expect(probe.informationMessages.count == 1)
        #expect(probe.informationMessages[0].contains("note changed"))
        #expect(probe.isPresented)
        #expect(discovery.search.executionIssue != nil)
    }

    @Test("A stale Research Record result is never routed")
    func staleRecordResult() async {
        let discovery = DiscoveryController()
        let generation = RecordSearchGenerationID(
            triptychID: UUID(),
            sourceManifestHash: "records"
        )
        let freshness = SearchFreshnessToken.record(generation)
        let fingerprint = DocumentFingerprint(content: #"{"record":"current"}"#)
        let hit = RecordSearchResult(
            recordID: UUID(),
            matchedField: .researcherStatement,
            matchedReason: "researcher statement matches ‘objection’",
            context: "Reasons and value",
            finishedAt: Date(timeIntervalSince1970: 100),
            participatingNotes: [],
            snippet: "A narrower objection is needed.",
            freshnessToken: freshness,
            fingerprint: fingerprint
        )
        let request = discovery.beginSearch(SearchWorkspaceState(
            query: "kind:record objection",
            scope: .triptych
        ))
        discovery.receiveSearchResponse(SearchResponse(
            requestID: request.id,
            scope: .triptych,
            explanation: explanation(provider: .record, explicit: true),
            freshnessToken: freshness,
            availability: .record(.current(generation)),
            results: [.record(hit)],
            hasMore: false
        ), for: request)

        let probe = WindowSearchPresentationProbe()
        probe.isPresented = true
        let controller = WindowSearchController(
            discoveryController: discovery,
            dependencies: dependencies(
                resultEvidence: { _, _ in
                    WindowSearchResultEvidence(
                        freshness: freshness,
                        fingerprint: DocumentFingerprint(
                            content: #"{"record":"changed"}"#
                        )
                    )
                },
                open: { _, _ in probe.openCount += 1 },
                isPresented: { probe.isPresented },
                setPresented: { probe.isPresented = $0 },
                reportInformation: { probe.informationMessages.append($0) }
            )
        )

        await controller.open(.result(.record(hit)), disposition: .replaceCurrent)

        #expect(probe.openCount == 0)
        #expect(probe.informationMessages.count == 1)
        #expect(
            probe.informationMessages[0].contains("Research Record changed")
        )
        #expect(probe.isPresented)
        #expect(discovery.search.executionIssue != nil)
    }

    @Test("Saved Searches from another Search contract require editing")
    func savedSearchContractMismatch() {
        let saved = SavedSearch(
            name: "Old semantics",
            definition: SearchDefinition(
                contractVersion: SearchContract.currentVersion - 1,
                query: "kind:record participant:researcher",
                presentationScope: .triptych
            )
        )

        let diagnostic = saved.needsEditingDiagnostic
        #expect(diagnostic?.code == .needsEditing)
        #expect(diagnostic?.needsEditing == true)
        #expect(diagnostic?.utf16UpperBound == saved.definition.query.utf16.count)
    }

    @Test("A stale Saved Search opens for editing without executing")
    func staleSavedSearchOpensForEditing() async {
        let rawQuery = "kind:record participant:researcher"
        let saved = SavedSearch(
            name: "Old contract",
            definition: SearchDefinition(
                contractVersion: SearchContract.currentVersion - 1,
                query: rawQuery,
                presentationScope: .currentVault
            )
        )
        let discovery = DiscoveryController()
        let probe = WindowSearchPresentationProbe()
        var executionContextCallCount = 0
        let controller = WindowSearchController(
            discoveryController: discovery,
            dependencies: dependencies(
                executionContext: { _ in
                    executionContextCallCount += 1
                    return DiscoverySearchExecutionContext(
                        workspaceIsAvailable: true,
                        currentNoteSnapshot: nil,
                        currentVaultID: UUID()
                    )
                },
                isPresented: { probe.isPresented },
                setPresented: { probe.isPresented = $0 },
                reportInformation: { probe.informationMessages.append($0) }
            )
        )

        controller.run(saved)
        await controller.waitForPendingWorkForTesting()

        #expect(probe.isPresented)
        #expect(controller.criteria.query == rawQuery)
        #expect(controller.criteria.scope == .currentVault)
        #expect(discovery.search.diagnostics.first?.code == .needsEditing)
        #expect(discovery.search.diagnostics.first?.needsEditing == true)
        #expect(probe.informationMessages.count == 1)
        #expect(executionContextCallCount == 0)
        #expect(!discovery.search.isRunning)
        #expect(discovery.search.results.isEmpty)

        discovery.updateSearchQuery("kind:record participant:agent")

        #expect(discovery.search.diagnostics.isEmpty)
        #expect(discovery.search.isRunning)
        #expect(executionContextCallCount == 0)
    }

    @Test("Search completion replaces only plain query text and follows provider capabilities")
    func completionContract() throws {
        let capabilities = SearchCapabilities.current
        let recordCompletion = try #require(
            capabilities.completions(
                for: "kind:record part",
                scope: .triptych
            ).first
        )
        #expect(recordCompletion.replacementText == "kind:record participant:")
        #expect(
            capabilities.completions(
                for: "kind:record prop",
                scope: .triptych
            ).isEmpty
        )
        #expect(
            capabilities.capability(for: .record)?.fields.contains {
                $0.name == "participant"
            } == true
        )
        #expect(
            capabilities.capability(for: .record)?.fields.contains {
                $0.name == "property"
            } == false
        )
        #expect(
            capabilities.capability(for: .note)?.fields.contains {
                $0.name == "property"
            } == true
        )

        let valueCompletion = try #require(
            capabilities.completions(
                for: "kind:record participant:r",
                scope: .triptych
            ).first
        )
        #expect(
            valueCompletion.replacementText
                == "kind:record participant:researcher"
        )
        let parsed = SearchQueryParser.parse(valueCompletion.replacementText)
        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.ast?.provider == .record)
        #expect(parsed.ast?.providerWasExplicit == true)
    }

    private func dependencies(
        loadSavedSearches: @escaping @MainActor () async throws -> [SavedSearch] = { [] },
        saveSavedSearches: @escaping @MainActor ([SavedSearch]) async throws -> Void = { _ in },
        recoverSavedSearches: @escaping @MainActor () async throws -> URL? = { nil },
        executionContext: @escaping @MainActor (
            SearchWorkspaceState
        ) async throws -> DiscoverySearchExecutionContext = { _ in
            DiscoverySearchExecutionContext(
                workspaceIsAvailable: false,
                currentNoteSnapshot: nil,
                currentVaultID: nil
            )
        },
        resultEvidence: @escaping @MainActor (
            SearchResult,
            SearchPresentationScope
        ) async -> WindowSearchResultEvidence = { _, _ in
            WindowSearchResultEvidence(freshness: nil, fingerprint: nil)
        },
        open: @escaping @MainActor (
            SearchResultSelection,
            WindowOpenDisposition
        ) async -> Void = { _, _ in },
        hasCurrentNote: @escaping @MainActor () -> Bool = { true },
        isPresented: @escaping @MainActor () -> Bool = { false },
        setPresented: @escaping @MainActor (Bool) -> Void = { _ in },
        reportInformation: @escaping @MainActor (String) -> Void = { _ in }
    ) -> WindowSearchController.Dependencies {
        WindowSearchController.Dependencies(
            loadSavedSearches: loadSavedSearches,
            saveSavedSearches: saveSavedSearches,
            recoverSavedSearches: recoverSavedSearches,
            executionContext: executionContext,
            resultEvidence: resultEvidence,
            open: open,
            hasCurrentNote: hasCurrentNote,
            isPresented: isPresented,
            setPresented: setPresented,
            reportInformation: reportInformation,
            reportLoadFailure: { _ in },
            reportSaveFailure: { _ in },
            setAvailabilityStatus: { _ in },
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
            clauses: []
        )
    }
}
