import ScholiumContracts
import Testing
@testable import ScholiumCore

extension TriptychSearchIndex {
    /// Core tests execute only an already validated Note plan. Parser
    /// diagnostics belong to the Contracts target; the index never reparses.
    func testSearch(
        _ request: SearchRequest,
        linkMatches: [VaultQualifiedNoteID: SearchLinkMatch] = [:],
        eligibleDocuments: [VaultQualifiedNoteID: SearchIndexDocumentEligibility]? = nil
    ) async throws -> SearchResponse {
        let ast = try #require(SearchQueryParser.parse(request.query).ast)
        await Task.yield()
        return try search(
            request,
            ast: ast,
            linkMatches: linkMatches,
            eligibleDocuments: eligibleDocuments
        )
    }
}

extension SearchResponse {
    /// A typed test view over the provider-discriminated result union.
    var noteResults: [NoteSearchResult] {
        results.compactMap { result in
            guard case .note(let note) = result else { return nil }
            return note
        }
    }
}
