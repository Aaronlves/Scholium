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

    @Test("A stale lexical result is never routed and refreshes the active query")
    func staleLexicalResult() async {
        let discovery = DiscoveryController()
        let generation = SearchGenerationID(
            triptychID: UUID(),
            sequence: 1,
            sourceManifestHash: "manifest"
        )
        let freshness = SearchFreshnessToken.triptych(generation)
        let fingerprint = DocumentFingerprint(content: "# Current\n")
        let hit = SearchHit(
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
            freshnessToken: freshness,
            availability: .current(generation),
            results: [hit],
            hasMore: false
        ), for: request)

        let probe = WindowSearchPresentationProbe()
        probe.isPresented = true
        let controller = WindowSearchController(
            discoveryController: discovery,
            dependencies: WindowSearchController.Dependencies(
                loadSavedSearches: { [] },
                saveSavedSearches: { _ in },
                executionContext: { _ in
                    DiscoverySearchExecutionContext(
                        workspaceIsAvailable: false,
                        currentNoteSnapshot: nil,
                        currentVaultID: nil
                    )
                },
                lexicalEvidence: { _, _ in
                    WindowLexicalSearchEvidence(
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

        await controller.open(.lexical(hit), disposition: .replaceCurrent)

        #expect(probe.openCount == 0)
        #expect(probe.informationMessages.count == 1)
        #expect(probe.isPresented)
        #expect(discovery.search.errorMessage != nil)
    }

    private func dependencies(
        loadSavedSearches: @escaping @MainActor () async throws -> [SavedSearch] = { [] },
        saveSavedSearches: @escaping @MainActor ([SavedSearch]) async throws -> Void = { _ in },
        hasCurrentNote: @escaping @MainActor () -> Bool = { true },
        isPresented: @escaping @MainActor () -> Bool = { false },
        setPresented: @escaping @MainActor (Bool) -> Void = { _ in }
    ) -> WindowSearchController.Dependencies {
        WindowSearchController.Dependencies(
            loadSavedSearches: loadSavedSearches,
            saveSavedSearches: saveSavedSearches,
            executionContext: { _ in
                DiscoverySearchExecutionContext(
                    workspaceIsAvailable: false,
                    currentNoteSnapshot: nil,
                    currentVaultID: nil
                )
            },
            lexicalEvidence: { _, _ in
                WindowLexicalSearchEvidence(
                    freshness: nil,
                    fingerprint: nil
                )
            },
            open: { _, _ in },
            hasCurrentNote: hasCurrentNote,
            isPresented: isPresented,
            setPresented: setPresented,
            reportInformation: { _ in },
            reportLoadFailure: { _ in },
            reportSaveFailure: { _ in },
            setAvailabilityStatus: { _ in },
            reportCatalogFailure: { _ in }
        )
    }
}
