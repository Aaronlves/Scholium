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

#if DEBUG
    extension RankedSearchCacheTests {
        @Test("Completed short and empty searches reuse rank and predicate work without losing counts or pages")
        func completedResultsReuseWork() async throws {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent(".build/ranked-search-cache-tests/\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let vault = RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: "/fixtures/topics")
            let index = try TriptychSearchIndex(
                databaseURL: root.appendingPathComponent("search.sqlite"), triptychID: UUID(), vaults: [vault])
            func document(_ path: String, _ source: String) -> SearchIndexDocument {
                SearchIndexDocument(
                    vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role,
                    document: NoteDocument(relativePath: path, rawContent: source))
            }
            var documents = [
                document("Hit.md", "# Example\n\nNeedle café 行动.\n"),
                document("Other.md", "A different discussion.\n"),
                document("Unknown.md", "---\nstate: [unterminated\n---\n\nUnrelated.\n"),
            ]
            _ = try await index.synchronize(documents)
            func request(_ query: String, limit: Int = 5, offset: Int = 0) -> SearchRequest {
                SearchRequest(
                    query: query, presentationScope: .triptych, executionScope: .triptych,
                    limit: limit, offset: offset)
            }
            for (query, total, unknown) in [
                ("needle", 1, 0), ("café OR 行动", 1, 0), ("missing", 0, 0),
                ("property:state=absent", 0, 1),
            ] {
                let first = try await index.testSearch(request(query))
                #expect(first.totalResultCount == total)
                #expect(first.indeterminateDocumentCount == unknown)
                #expect(!first.hasMore)
                let work = await index.rankedSearchExecutionCountsForTesting
                let replay = try await index.testSearch(request(query, limit: 100))
                #expect(replay.noteResults == first.noteResults)
                #expect(replay.totalResultCount == total)
                #expect(replay.indeterminateDocumentCount == unknown)
                #expect(!replay.hasMore)
                let pastEnd = try await index.testSearch(request(query, offset: 20))
                #expect(pastEnd.results.isEmpty && !pastEnd.hasMore)
                #expect(pastEnd.totalResultCount == total)
                #expect(pastEnd.indeterminateDocumentCount == unknown)
                let replayWork = await index.rankedSearchExecutionCountsForTesting
                #expect(replayWork.candidateScans == work.candidateScans)
                #expect(replayWork.rankingPasses == work.rankingPasses)
            }
            let work = await index.rankedSearchExecutionCountsForTesting
            let cancelled = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await index.testSearch(request("needle"))
            }
            await #expect(throws: CancellationError.self) { _ = try await cancelled.value }
            #expect(await index.rankedSearchExecutionCountsForTesting.candidateScans == work.candidateScans)

            // Opening eligibility never inherits a complete-generation cache entry.
            let ineligible = try await index.testSearch(request("needle"), eligibleDocuments: [:])
            #expect(ineligible.results.isEmpty && ineligible.totalResultCount == 0)
            #expect(await index.rankedSearchExecutionCountsForTesting.candidateScans == work.candidateScans + 1)

            // Previously empty and sparse queries must observe the newly published exact revision.
            documents[0] = document("Hit.md", "Revised unrelated source.\n")
            documents.append(document("Replacement.md", "Needle café 行动 and missing marker.\n"))
            _ = try await index.synchronize(documents)
            #expect(await index.rankedSearchCacheRetention.queries == 0)
            let rebuilt = try TriptychSearchIndex(
                databaseURL: root.appendingPathComponent("rebuilt.sqlite"), triptychID: UUID(), vaults: [vault])
            _ = try await rebuilt.synchronize(documents)
            for query in ["needle", "missing", "café OR 行动"] {
                let updated = try await index.testSearch(request(query))
                let clean = try await rebuilt.testSearch(request(query))
                #expect(updated.noteResults.map(\.relativePath) == ["Replacement.md"])
                #expect(updated.noteResults.map(\.relativePath) == clean.noteResults.map(\.relativePath))
                #expect(updated.noteResults.map(\.fingerprint) == clean.noteResults.map(\.fingerprint))
                #expect(updated.noteResults.map(\.sourceRange) == clean.noteResults.map(\.sourceRange))
                #expect(updated.noteResults.map(\.snippet) == clean.noteResults.map(\.snippet))
                #expect(updated.noteResults.map(\.matchedFields) == clean.noteResults.map(\.matchedFields))
                #expect(updated.noteResults.map(\.rankReason) == clean.noteResults.map(\.rankReason))
            }
        }
    }
#endif
