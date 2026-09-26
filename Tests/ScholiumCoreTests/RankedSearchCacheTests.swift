import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Ranked Search cache retention")
struct RankedSearchCacheTests {
    @Test("Distinct completed searches remain bounded without changing pagination or revisions")
    func boundedSearchRetentionPreservesResults() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build/ranked-search-cache-tests/\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: "/fixtures/topics")
        let index = try TriptychSearchIndex(
            databaseURL: root.appendingPathComponent("search.sqlite"), triptychID: UUID(), vaults: [vault])
        func document(_ number: Int, source: String) -> SearchIndexDocument {
            SearchIndexDocument(
                vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role,
                document: NoteDocument(relativePath: String(format: "Note %03d.md", number), rawContent: source))
        }
        var documents = (0..<500).map { document($0, source: "# Neutral\n\nNeedle café 行动.\n") }
        _ = try await index.synchronize(documents)
        func request(_ number: Int, offset: Int = 0) -> SearchRequest {
            SearchRequest(
                query: "needle -absent\(number)", presentationScope: .currentVault,
                executionScope: .currentVault(vault.id), limit: 5, offset: offset)
        }
        let first = try await index.testSearch(request(0))
        #expect(first.noteResults.map(\.relativePath) == (0..<5).map { String(format: "Note %03d.md", $0) })
        #expect(first.hasMore)
        #expect(first.noteResults.allSatisfy { $0.sourceRange != nil })
        for number in 1..<64 {
            let response = try await index.testSearch(request(number))
            #expect(response.noteResults.map(\.relativePath) == first.noteResults.map(\.relativePath))
            if [7, 15, 31, 63].contains(number) {
                let retained = await index.rankedSearchCacheRetention
                print("Ranked Search retention after \(number + 1) queries: \(retained.queries) entries, \(retained.results) result items")
            }
        }
        let retained = await index.rankedSearchCacheRetention
        #expect(retained.queries <= 8)
        #expect(retained.results <= 8 * 500)

        let replayed = try await index.testSearch(request(0))
        #expect(replayed.noteResults == first.noteResults)
        #expect(replayed.totalResultCount == first.totalResultCount)
        #expect(replayed.hasMore == first.hasMore)
        let nextPage = try await index.testSearch(request(0, offset: 5))
        #expect(nextPage.noteResults.map(\.relativePath) == (5..<10).map { String(format: "Note %03d.md", $0) })
        #expect(nextPage.hasMore)

        documents[0] = document(0, source: "# Neutral\n\nRevised unrelated source.\n")
        _ = try await index.synchronize(documents)
        #expect(await index.rankedSearchCacheRetention.queries == 0)
        let revised = try await index.testSearch(request(0))
        #expect(revised.noteResults.map(\.relativePath) == (1..<6).map { String(format: "Note %03d.md", $0) })
    }
}
