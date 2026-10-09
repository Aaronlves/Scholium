import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Search result continuity and accessibility")
@MainActor
struct SearchResultPresentationTests {
    private let triptychID = UUID()
    private let vaultID = UUID()

    @Test("A same-query refresh retains only a still-present keyboard target", arguments: [true, false])
    func selectionSurvivesRefresh(retained: Bool) {
        let (controller, original) = selectedSearch()
        let refresh = controller.beginSearch(controller.search.criteria)
        #expect(controller.search.selectedResultID == original.id)

        let current = result(id: retained ? original.id : "another", sequence: 2)
        controller.receiveSearchResponse(response(for: refresh, results: [current], sequence: 2), for: refresh)

        #expect(controller.search.selectedResultID == (retained ? current.id : nil))
        #expect(controller.search.results == [current])
        #expect(controller.search.freshnessToken == current.freshnessToken)
    }

    @Test(
        "Beginning a different query or scope cannot inherit the previous keyboard target",
        arguments: [
            SearchWorkspaceState(query: "different", scope: .triptych),
            SearchWorkspaceState(query: "result", scope: .currentVault),
        ]
    )
    func directCriteriaChangeClearsSelection(criteria: SearchWorkspaceState) {
        let (controller, original) = selectedSearch()
        let replacement = controller.beginSearch(criteria)
        #expect(controller.search.selectedResultID == nil)

        controller.receiveSearchResponse(response(for: replacement, results: [original]), for: replacement)
        #expect(controller.search.selectedResultID == nil)
    }

    enum SearchChange: CaseIterable {
        case query, scope, replacement, dismissal
    }

    @Test("Editing or closing Search clears selection and rejects its pending response", arguments: SearchChange.allCases)
    func changedSearchCannotReviveSelection(change: SearchChange) {
        let (controller, original) = selectedSearch()
        let pending = controller.beginSearch(controller.search.criteria)
        switch change {
        case .query:
            controller.updateSearchQuery("different")
        case .scope:
            controller.selectSearchScope(.currentVault)
        case .replacement:
            controller.replaceSearchCriteria(.init(query: "saved", scope: .currentVault))
        case .dismissal:
            controller.dismissSearch()
        }
        #expect(controller.search.selectedResultID == nil)
        let expected = controller.search

        controller.receiveSearchResponse(response(for: pending, results: [original]), for: pending)
        #expect(controller.search == expected)
    }

    @Test("A superseded refresh cannot erase the selection in a newer response")
    func staleResponsePreservesNewSelection() {
        let (controller, original) = selectedSearch()
        let earlier = controller.beginSearch(controller.search.criteria)
        let later = controller.beginSearch(controller.search.criteria)
        let current = result(id: "current", sequence: 2)
        controller.receiveSearchResponse(response(for: later, results: [current], sequence: 2), for: later)
        controller.selectSearchResult(current.id)
        let expected = controller.search

        controller.receiveSearchResponse(response(for: earlier, results: [original]), for: earlier)
        #expect(controller.search == expected)
    }

    @Test("Search failure releases the previously selected result")
    func failedRefreshClearsSelection() {
        let (controller, _) = selectedSearch()
        let refresh = controller.beginSearch(controller.search.criteria)
        controller.failSearch(.failed("Fixture Search failure"), for: refresh)
        #expect(controller.search.selectedResultID == nil)
        #expect(controller.search.results.isEmpty)
    }

    @Test("Results without a source range do not announce a fabricated line", arguments: [false, true])
    func unlocatedResultAccessibility(exclusion: Bool) {
        let reason: NoteSearchMatchReason =
            exclusion
            ? .excluded(.lexical(.init(field: nil, value: .term("alpha"), sourceRange: 0..<5)))
            : .lexical
        let note = note(primaryMatchReason: reason)
        let label = SearchResultAccessibilityPresentation.label(for: note)
        #expect(label.contains(note.title))
        #expect(label.contains(note.vaultName))
        #expect(!label.contains(String(localized: "Line \(1)")))
        if exclusion {
            #expect(label.contains("NOT ("))
            #expect(label.contains("alpha"))
        }
    }

    @Test("A located result announces the exact source range's line")
    func locatedResultAccessibility() {
        let range = SearchSourceRange(
            utf16LowerBound: 80, utf16UpperBound: 85, line: 7, column: 1, endLine: 7, endColumn: 6)
        let label = SearchResultAccessibilityPresentation.label(for: note(sourceRange: range))
        #expect(label.contains(String(localized: "Line \(7)")))
        #expect(!label.contains(String(localized: "Line \(1)")))
    }

    private func selectedSearch() -> (DiscoveryController, SearchResult) {
        let controller = DiscoveryController()
        let original = result(id: "selected")
        let request = controller.beginSearch(.init(query: "result", scope: .triptych))
        controller.receiveSearchResponse(response(for: request, results: [original]), for: request)
        controller.selectSearchResult(original.id)
        return (controller, original)
    }

    private func generation(_ sequence: Int) -> SearchGenerationID {
        SearchGenerationID(triptychID: triptychID, sequence: sequence, sourceManifestHash: "manifest-\(sequence)")
    }

    private func result(id: String, sequence: Int = 1) -> SearchResult {
        .note(note(id: id, sequence: sequence))
    }

    private func note(
        id: String = "result", sequence: Int = 1,
        sourceRange: SearchSourceRange? = nil,
        primaryMatchReason: NoteSearchMatchReason = .lexical
    ) -> NoteSearchResult {
        NoteSearchResult(
            resultID: id, vaultID: vaultID, vaultName: "Topics", vaultRole: .topicKnowledge,
            relativePath: "Result.md", stableNoteID: nil, title: "Result", matchedField: .body,
            context: nil, sourceLine: 1, snippet: "Result", highlights: [],
            primaryMatchReason: primaryMatchReason, sourceRange: sourceRange,
            freshnessToken: .triptych(generation(sequence)), fingerprint: .init(content: "# Result\n"),
            evidentialLayer: .topicNote, classification: .retrievalLead)
    }

    private func response(
        for request: DiscoverySearchRequest, results: [SearchResult], sequence: Int = 1
    ) -> SearchResponse {
        SearchResponse(
            requestID: request.id, scope: request.criteria.scope,
            explanation: .init(provider: .note, providerWasExplicit: false, scope: request.criteria.scope, expression: .and([])),
            freshnessToken: .triptych(generation(sequence)), availability: .current(generation(sequence)),
            results: results, hasMore: false)
    }
}
