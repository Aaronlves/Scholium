import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Current-source Search without generated-state admission")
struct CurrentSourceSearchTests {
    @Test("Database-free queries preserve complete empty-index responses across roles, fields and pages")
    func canonicalResponseParity() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        let generationBefore = try await index.generation()
        let richSource = """
            ---
            title: Café authority
            aliases: [Émotion]
            keywords: [reasons]
            summary: Summaryneedle and authority
            authors: [Simone]
            publication_date: '1943'
            note_id: forged
            ---
            # Résumé

            😀 needle café and cafe\u{301}. A认识论B 哲学研究。

            A second needle café appears beside [[Target]]{{annotationneedle}}.

            > [!state] A source-owned claim
            > Another needle and a reference [^note].

            [^note]: footneedle belongs to the authored footnote.
            """
        let sources = [richSource, "\u{FEFF}" + richSource.replacingOccurrences(of: "\n", with: "\r\n")]
        let queries = [
            "needle", "\"needle café\"", "cafe", "哲学", "A认识论B",
            "needle -absent", "needle OR café", "heading:résumé", "body:needle",
            "footnote:footneedle", "link_annotation:annotationneedle", "path:Draft",
            "needle keyword:reasons", "alias:emotion", "summary:summaryneedle", "author:Simone",
        ]
        for vault in fixture.vaults {
            for bytes in sources {
                let source = fixture.snapshot(bytes, vault: vault, stableNoteID: UUID())
                for query in queries {
                    let ast = try parsed(query)
                    for (offset, limit) in [(0, 4), (1, 1), (100, 20), (0, 0)] {
                        let request = request(query, source: source, limit: limit, offset: offset)
                        let expected = try await index.search(request, ast: ast)
                        let actual = try TriptychSearchIndex.searchCurrentSource(request, ast: ast, vault: vault)
                        #expect(actual == expected, "Complete response differs for \(vault.role), \(query), page \(offset)/\(limit)")
                        #expect(actual.freshnessToken == .currentNote(source))
                        #expect(actual.availability == .unavailable)
                        #expect(actual.noteResults.allSatisfy { $0.fingerprint == source.fingerprint })
                    }
                }
            }
        }
        #expect(try await index.generation() == generationBefore)
        await index.shutdown()
    }

    @Test("Exact live source supplies portable identity and independent Unicode occurrence coordinates")
    func exactSourceIdentityAndPagination() throws {
        let vault = RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: "/synthetic/topics")
        let stableID = UUID()
        let raw = "\u{FEFF}# Draft\r\n\r\n中文😀 needle\r\n\r\ncafe\u{301} needle\r\n\r\nlast needle\r\n"
        let source = SearchSourceSnapshot(
            noteID: .init(vaultID: vault.id, relativePath: "Unsaved/Draft.md"),
            stableNoteID: stableID, editorSessionID: UUID(), source: raw, editorRevision: 7)
        let ast = try parsed("needle")
        let all = try TriptychSearchIndex.searchCurrentSource(request("needle", source: source, limit: 100), ast: ast, vault: vault)
        try #require(all.noteResults.count == 3)
        #expect(all.noteResults.map(\.sourceLine) == [3, 5, 7])
        #expect(all.noteResults.map(\.stableNoteID) == Array(repeating: stableID.uuidString.lowercased(), count: 3))
        #expect(all.noteResults.allSatisfy { $0.noteReference == source.noteID && $0.fingerprint == source.fingerprint })
        #expect(Set(all.noteResults.map(\.resultID)).count == 3)
        var expectedRanges: [NSRange] = []
        let text = raw as NSString
        var cursor = 0
        while cursor < text.length {
            let found = text.range(of: "needle", range: NSRange(location: cursor, length: text.length - cursor))
            if found.location == NSNotFound { break }
            expectedRanges.append(found)
            cursor = NSMaxRange(found)
        }
        try #require(expectedRanges.count == 3)
        for (ordinal, hit) in all.noteResults.enumerated() {
            let range = try #require(hit.sourceRange)
            #expect(range.utf16LowerBound == expectedRanges[ordinal].location)
            #expect(range.utf16UpperBound == NSMaxRange(expectedRanges[ordinal]))
            #expect(range.line == [3, 5, 7][ordinal])
            #expect(range.column == [6, 7, 6][ordinal])
            #expect(text.substring(with: expectedRanges[ordinal]) == "needle")
        }
        var pages: [SearchResult] = []
        for offset in 0...3 {
            let page = try TriptychSearchIndex.searchCurrentSource(
                request("needle", source: source, limit: 1, offset: offset), ast: ast, vault: vault)
            #expect(page.results == Array(all.results.dropFirst(offset).prefix(1)))
            #expect(page.hasMore == (offset < 2))
            pages += page.results
        }
        #expect(pages == all.results)
        #expect(Data(source.source.utf8) == Data(raw.utf8))

        let next = SearchSourceSnapshot(
            noteID: source.noteID, stableNoteID: stableID, editorSessionID: source.editorSessionID,
            source: raw + "\r\nsourceonlyuniqueterm\r\n", editorRevision: 8)
        let revisedQuery = "sourceonlyuniqueterm"
        let revised = try TriptychSearchIndex.searchCurrentSource(
            request(revisedQuery, source: next), ast: parsed(revisedQuery), vault: vault)
        #expect(revised.results.count == 1)
        #expect(revised.freshnessToken == .currentNote(next))
        #expect(revised.freshnessToken != all.freshnessToken)
        #expect(revised.noteResults.first?.stableNoteID == stableID.uuidString.lowercased())
        #expect(revised.noteResults.first?.fingerprint == next.fingerprint)
        let noIdentity = SearchSourceSnapshot(
            noteID: source.noteID, editorSessionID: UUID(),
            source: "---\nnote_id: forged\n---\nneedle", editorRevision: 1)
        #expect(try TriptychSearchIndex.searchCurrentSource(
            request("needle", source: noIdentity), ast: ast, vault: vault).noteResults.map(\.stableNoteID) == [nil])
    }

    @Test("Unavailable admission and unsupported This Note filters retain the canonical diagnostics")
    func diagnosticsAndAdmissionState() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        let vault = fixture.vaults[0]
        let source = fixture.snapshot("# Draft\n\nneedle", vault: vault)
        for query in ["property:status", "callout:state", "-needle", "needle OR -absent"] {
            let ast = try parsed(query)
            let request = request(query, source: source)
            let response = try TriptychSearchIndex.searchCurrentSource(request, ast: ast, vault: vault)
            #expect(response == (try await index.search(request, ast: ast)))
            #expect(response.results.isEmpty && !response.hasMore)
            #expect(response.diagnostics.map(\.reason) == [.currentNoteRequiresPositiveText])
            #expect(response.diagnostics.first?.utf16UpperBound == query.utf16.count)
        }
        let availabilities: [SearchAvailability] = [
            .unavailable, .building(.init(completed: 0, total: 1)),
            .failed(lastGood: nil, reason: "Synthetic derived admission failure"),
        ]
        for availability in availabilities {
            let response = try TriptychSearchIndex.searchCurrentSource(
                request("needle", source: source), ast: parsed("needle"), vault: vault, availability: availability)
            #expect(response.results.count == 1)
            #expect(response.availability == availability)
            #expect(response.freshnessToken == .currentNote(source))
        }
        await index.shutdown()
    }

    @Test("Database-free Search rejects non-Note or mismatched authority and honors cancellation")
    func authorityAndCancellation() async throws {
        let vault = RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: "/synthetic/topics")
        let other = RegisteredVault(name: "Other", role: .other, canonicalPath: "/synthetic/other")
        let source = SearchSourceSnapshot(
            noteID: .init(vaultID: vault.id, relativePath: "Draft.md"),
            editorSessionID: UUID(), source: "needle", editorRevision: 1)
        let ast = try parsed("needle")
        let invalid = [
            (request("needle", source: source), other),
            (SearchRequest(query: "needle", presentationScope: .triptych, executionScope: .triptych, limit: 20), vault),
            (SearchRequest(query: "needle", presentationScope: .currentVault, executionScope: .currentVault(vault.id), limit: 20), vault),
            (SearchRequest(query: "needle", presentationScope: .triptych, executionScope: .currentNote(source), limit: 20), vault),
            (SearchRequest(query: "needle", presentationScope: .thisNote, executionScope: .currentNote(source), limit: 20, includedVaultIDs: [vault.id]), vault),
        ]
        for (request, descriptor) in invalid {
            do {
                _ = try TriptychSearchIndex.searchCurrentSource(request, ast: ast, vault: descriptor)
                Issue.record("A non-Note or mismatched authority reached current-source Search.")
            } catch let error as SearchIndexError {
                guard case .invalidDocuments = error else {
                    Issue.record("Unexpected authority rejection: \(error)")
                    continue
                }
            }
        }
        let request = request("needle", source: source)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try TriptychSearchIndex.searchCurrentSource(request, ast: ast, vault: vault)
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
    }

    private func parsed(_ query: String) throws -> SearchQueryAST {
        let result = SearchQueryParser.parse(query)
        #expect(result.diagnostics.isEmpty)
        return try #require(result.ast)
    }

    private func request(_ query: String, source: SearchSourceSnapshot, limit: Int = 20, offset: Int = 0) -> SearchRequest {
        SearchRequest(query: query, presentationScope: .thisNote, executionScope: .currentNote(source), limit: limit, offset: offset)
    }

    private struct Fixture {
        let root: URL
        let triptychID = UUID()
        let vaults = [
            RegisteredVault(name: "Analyses", role: .sourceCorpus, canonicalPath: "/synthetic/analyses"),
            RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: "/synthetic/topics"),
            RegisteredVault(name: "Works", role: .draftProject, canonicalPath: "/synthetic/works"),
        ]

        init() throws {
            root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(".build/current-source-search-tests/\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func index() throws -> TriptychSearchIndex {
            try TriptychSearchIndex(isolatedDatabaseURL: root.appendingPathComponent("search.sqlite"), triptychID: triptychID, vaults: vaults)
        }

        func snapshot(_ source: String, vault: RegisteredVault, stableNoteID: UUID? = nil) -> SearchSourceSnapshot {
            SearchSourceSnapshot(noteID: .init(vaultID: vault.id, relativePath: "Unsaved/Draft.md"), stableNoteID: stableNoteID,
                editorSessionID: UUID(), source: source, editorRevision: 1)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
