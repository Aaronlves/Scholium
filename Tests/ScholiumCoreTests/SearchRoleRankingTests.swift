import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Search role field preferences")
struct SearchRoleRankingTests {
    @Test(
        "Comparable field matches reflect each vault's authored role",
        arguments: [
            ("---\nsummary: needle\n---\n\nordinary", "summary:needle", VaultRole.sourceCorpus),
            ("---\nkeywords: [needle]\n---\n\nordinary", "keyword:needle", VaultRole.topicKnowledge),
            // A lone scalar is the one-member case of the string-list projection.
            ("---\nkeywords: needle\n---\n\nordinary", "keyword:needle", VaultRole.topicKnowledge),
            ("---\naliases: [needle phrase]\n---\n\nordinary", "alias:needle", VaultRole.topicKnowledge),
            ("## needle\n\nordinary", "heading:needle", VaultRole.draftProject),
            ("needle ordinary", "body:needle", VaultRole.draftProject),
        ])
    func comparableFields(_ scenario: (String, String, VaultRole)) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        let documents = fixture.vaults.map { fixture.item($0, path: "Shared.md", source: scenario.0) }
        _ = try await index.synchronize(documents)
        let response = try await index.testSearch(fixture.request(scenario.1))
        #expect(response.noteResults.count == 3)
        #expect(response.noteResults.first?.vaultRole == scenario.2)
        #expect(Set(response.noteResults.map(\.vaultRole)) == Set(fixture.vaults.map(\.role)))
        for note in response.noteResults {
            #expect(note.fingerprint == DocumentFingerprint(content: scenario.0))
            let range = try #require(note.sourceRange)
            let currentRange = Range(
                NSRange(location: range.utf16LowerBound, length: range.utf16UpperBound - range.utf16LowerBound),
                in: scenario.0)
            #expect(currentRange != nil)
        }
    }

    @Test("Exact title and alias identity precede even repeated Works field matches")
    func identityPrecedesRoleWeights() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([
            fixture.item(fixture.analyses, path: "needle.md", source: "An unrelated discussion."),
            fixture.item(fixture.topics, path: "Alias.md", source: "---\naliases: [needle]\n---\n\nAn unrelated discussion."),
            fixture.item(fixture.works, path: "Draft.md", source: "## needle\n\n" + String(repeating: "needle ", count: 40)),
        ])
        let response = try await index.testSearch(fixture.request("needle"))
        #expect(response.noteResults.map(\.relativePath) == ["needle.md", "Alias.md", "Draft.md"])
        #expect(response.noteResults.map(\.rankReason) == [.exactTitle, .exactAlias, .lexicalRelevance])
    }

    @Test("Role weights retain exact field filters, Boolean exclusions and global pagination")
    func predicatesAndPaginationRemainExact() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([
            fixture.item(fixture.analyses, path: "Analysis.md", source: "---\nsummary: needle\n---\n\nordinary"),
            fixture.item(fixture.topics, path: "Topic.md", source: "needle ordinary"),
            fixture.item(fixture.works, path: "Draft.md", source: "needle ordinary"),
            fixture.item(fixture.works, path: "Excluded.md", source: "---\nsummary: needle\n---\n\nneedle excluded"),
        ])
        let query = "(summary:needle OR body:needle) AND NOT body:excluded"
        let complete = try await index.testSearch(fixture.request(query))
        #expect(Set(complete.noteResults.map(\.relativePath)) == ["Analysis.md", "Topic.md", "Draft.md"])
        #expect(complete.totalResultCount == 3)
        var paged: [String] = []
        for offset in 0..<3 {
            let page = try await index.testSearch(fixture.request(query, limit: 1, offset: offset))
            #expect(page.totalResultCount == 3)
            #expect(page.hasMore == (offset < 2))
            paged.append(contentsOf: page.noteResults.map(\.resultID))
        }
        #expect(paged == complete.noteResults.map(\.resultID))
        let summaryOnly = try await index.testSearch(fixture.request("summary:needle AND NOT body:excluded"))
        #expect(summaryOnly.noteResults.map(\.relativePath) == ["Analysis.md"])
    }

    private struct Fixture {
        let root: URL
        let triptychID = UUID()
        let analyses = RegisteredVault(name: "Analyses", role: .sourceCorpus, canonicalPath: "/fixtures/analyses")
        let topics = RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: "/fixtures/topics")
        let works = RegisteredVault(name: "Works", role: .draftProject, canonicalPath: "/fixtures/works")
        var vaults: [RegisteredVault] { [analyses, topics, works] }

        init() throws {
            root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent(".build/search-role-ranking-tests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func index() throws -> TriptychSearchIndex {
            try TriptychSearchIndex(databaseURL: root.appendingPathComponent("search.sqlite"), triptychID: triptychID, vaults: vaults)
        }

        func item(_ vault: RegisteredVault, path: String, source: String) -> SearchIndexDocument {
            .init(
                vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role,
                document: .init(relativePath: path, rawContent: source))
        }

        func request(_ query: String, limit: Int = 20, offset: Int = 0) -> SearchRequest {
            .init(query: query, presentationScope: .triptych, executionScope: .triptych, limit: limit, offset: offset)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
