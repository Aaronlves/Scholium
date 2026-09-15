import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Boolean Search over exact indexed sources")
struct BooleanSearchIndexTests {
    @Test("Independent link predicates preserve unknown exclusions and branch-local reasons")
    func independentLinkPredicates() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([fixture.note("A.md", "alpha"), fixture.note("B.md", "beta"), fixture.note("C.md", "gamma")])
        let a = VaultQualifiedNoteID(vaultID: fixture.vault.id, relativePath: "A.md")
        let b = VaultQualifiedNoteID(vaultID: fixture.vault.id, relativePath: "B.md")
        for (query, expected, unknown) in [
            ("from-note:Anchor OR to-note:Other", Set(["A.md", "B.md"]), 0),
            ("from-note:Anchor AND NOT to-note:Other", Set(["A.md"]), 0),
            ("NOT from-note:Anchor OR to-note:Other", Set(["B.md", "C.md"]), 0),
            ("NOT from-note:Anchor AND NOT to-note:Other", Set(["C.md"]), 0),
            ("NOT from-note:Anchor", Set(["C.md"]), 1),
        ] {
            let ast = try #require(SearchQueryParser.parse(query).ast)
            let links = Dictionary(
                uniqueKeysWithValues: ast.linkQueries.map { clause in
                    let id = clause.direction == .fromNote ? a : b
                    return (
                        clause,
                        SearchLinkResolution(
                            matches: [
                                id: SearchLinkMatch(
                                    direction: clause.direction,
                                    anchorIdentity: clause.noteIdentity, targetNote: id, occurrences: [])
                            ],
                            indeterminateNotes: clause.direction == .fromNote ? [b] : [])
                    )
                })
            let result = try await index.testSearch(fixture.request(query), linkMatches: links)
            #expect(Set(result.noteResults.map(\.relativePath)) == expected, "\(query)")
            #expect(result.indeterminateDocumentCount == unknown)
            let roundTrip = try JSONDecoder().decode(SearchResponse.self, from: JSONEncoder().encode(result))
            #expect(roundTrip.indeterminateDocumentCount == unknown)
            #expect(roundTrip.explanation.expression == ast.expression)
            if query == "from-note:Anchor OR to-note:Other" {
                #expect(result.noteResults.allSatisfy { $0.matchReasons.count == 1 })
            }
        }
    }

    @Test("OR, grouping and pure exclusion do not lose nonlexical candidates")
    func booleanResults() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([
            fixture.note("M1.md", "alpha beta"), fixture.note("M2.md", "beta gamma"),
            fixture.note("M3.md", "alpha"), fixture.note("M4.md", "unrelated"),
        ])
        let cases: [(String, Set<String>)] = [
            ("alpha beta", ["M1.md"]), ("alpha OR beta", ["M1.md", "M2.md", "M3.md"]),
            ("alpha OR beta AND gamma", ["M1.md", "M2.md", "M3.md"]),
            ("(alpha OR beta) AND gamma", ["M2.md"]), ("alpha NOT beta", ["M3.md"]),
            ("NOT (alpha OR beta)", ["M4.md"]), ("NOT NOT alpha", ["M1.md", "M3.md"]),
            ("alpha OR NOT beta", ["M1.md", "M3.md", "M4.md"]),
        ]
        for (query, expected) in cases {
            let result = try await index.testSearch(fixture.request(query))
            #expect(Set(result.noteResults.map(\.relativePath)) == expected, "\(query)")
            #expect(result.totalResultCount == expected.count)
            #expect(result.indeterminateDocumentCount == 0)
        }
        let result = try await index.testSearch(fixture.request("alpha OR (beta AND gamma)"))
        let m1 = try #require(result.noteResults.first { $0.relativePath == "M1.md" })
        #expect(m1.highlights.count == 1)
        #expect(m1.snippet.substringForUTF16Range(m1.highlights[0]) == "alpha")
        let excluded = try await index.testSearch(fixture.request("NOT alpha"))
        #expect(excluded.noteResults.allSatisfy { $0.highlights.isEmpty && $0.sourceRange == nil })
        #expect(excluded.noteResults.allSatisfy { if case .excluded = $0.primaryMatchReason { true } else { false } })
    }

    @Test("Unknown YAML remains unknown under NOT, while true alternatives still match")
    func propertyCompleteness() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        let documents = [
            fixture.note("Draft.md", "---\nstatus: draft\n---\nalpha"),
            fixture.note("Revised.md", "---\nstatus: revised\n---\nalpha"),
            fixture.note("Missing.md", "alpha"),
            fixture.note("Null.md", "---\nstatus: null\n---\nalpha"),
            fixture.note("List.md", "---\nstatus: [draft, revised]\n---\nalpha"),
            fixture.note("Broken.md", "---\nstatus: [\n---\nalpha"),
            fixture.note("Duplicate.md", "---\nstatus: draft\nstatus: revised\n---\nalpha"),
            fixture.note("Unclosed.md", "---\nstatus: draft\nalpha"),
        ]
        _ = try await index.synchronize(documents)
        let missing = try await index.testSearch(fixture.request("NOT property:status"))
        #expect(missing.noteResults.map(\.relativePath) == ["Missing.md"])
        #expect(missing.indeterminateDocumentCount == 3)
        let notDraft = try await index.testSearch(fixture.request("property:status AND NOT property:status=draft"))
        #expect(Set(notDraft.noteResults.map(\.relativePath)) == ["Revised.md", "Null.md"])
        #expect(notDraft.indeterminateDocumentCount == 3)
        let alternative = try await index.testSearch(fixture.request("title:Broken OR property:status=draft"))
        #expect(Set(alternative.noteResults.map(\.relativePath)) == ["Broken.md", "Draft.md", "List.md"])
        let broken = try #require(alternative.noteResults.first { $0.relativePath == "Broken.md" })
        #expect(!broken.matchReasons.contains { if case .property = $0 { true } else { false } })
        let reopened = try fixture.index()
        #expect(try await reopened.testSearch(fixture.request("NOT property:status")).indeterminateDocumentCount == 3)
        let repaired = documents.map { $0.relativePath == "Broken.md" ? fixture.note("Broken.md", "---\nstatus: revised\n---\nalpha") : $0 }
        _ = try await index.synchronize(repaired)
        let rebuilt = try fixture.index(name: "rebuilt.sqlite")
        _ = try await rebuilt.synchronize(repaired)
        let incremental = try await index.testSearch(fixture.request("NOT property:status=draft"))
        let clean = try await rebuilt.testSearch(fixture.request("NOT property:status=draft"))
        #expect(incremental.noteResults.map(\.relativePath) == clean.noteResults.map(\.relativePath))
        #expect(incremental.indeterminateDocumentCount == clean.indeterminateDocumentCount)
    }

    @Test("Paging equals a complete global ranking and duplicate branches do not boost a note")
    func pagingAndRanking() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        let documents = (0..<75).map { n in
            fixture.note(String(format: "N%03d.md", n), n.isMultiple(of: 2) ? "alpha beta" : "---\nstatus: draft\n---\nother")
        }
        _ = try await index.synchronize(documents)
        let query = "alpha OR property:status=draft"
        let whole = try await index.testSearch(fixture.request(query, limit: 100))
        var pages: [String] = []
        for offset in stride(from: 0, to: 75, by: 7) {
            let page = try await index.testSearch(fixture.request(query, limit: 7, offset: offset))
            pages.append(contentsOf: page.noteResults.map(\.relativePath))
            #expect(page.hasMore == (offset + page.noteResults.count < 75))
        }
        #expect(pages == whole.noteResults.map(\.relativePath))
        #expect(Set(pages).count == 75)
        let repeated = try await index.testSearch(fixture.request("alpha OR alpha OR property:status=draft", limit: 100))
        #expect(repeated.noteResults.map(\.relativePath) == pages)
        let unauthorized = try await index.testSearch(
            SearchRequest(
                query: "NOT missing", presentationScope: .triptych, executionScope: .triptych,
                limit: 100, includedVaultIDs: [UUID()]))
        #expect(unauthorized.results.isEmpty && unauthorized.indeterminateDocumentCount == 0)
    }

    @Test("This Note returns occurrences from every satisfied alternative with exact Unicode offsets")
    func allCurrentNoteOccurrences() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        let source = "\u{FEFF}# 草稿\r\n\r\n中文😀 alpha\r\n\r\nbeta e\u{301}\r\n\r\nalpha\r\n"
        let snapshot = SearchSourceSnapshot(
            noteID: .init(vaultID: fixture.vault.id, relativePath: "Draft.md"), editorSessionID: UUID(), source: source, editorRevision: 1)
        let request = SearchRequest(query: "alpha OR beta", presentationScope: .thisNote, executionScope: .currentNote(snapshot), limit: 100)
        let result = try await index.testSearch(request)
        let actual = result.noteResults.compactMap { hit -> String? in
            guard let range = hit.sourceRange else { return nil }
            return (source as NSString).substring(with: NSRange(location: range.utf16LowerBound, length: range.utf16UpperBound - range.utf16LowerBound))
        }
        #expect(actual == ["alpha", "beta", "alpha"])
        #expect(Set(result.noteResults.map(\.resultID)).count == 3)
    }

    private struct Fixture {
        let root: URL
        let triptych = UUID()
        let vault = RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: "/fixtures/topics")
        init() throws {
            root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(".build/boolean-search-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
        func index(name: String = "search.sqlite") throws -> TriptychSearchIndex {
            try TriptychSearchIndex(databaseURL: root.appendingPathComponent(name), triptychID: triptych, vaults: [vault])
        }
        func note(_ path: String, _ source: String) -> SearchIndexDocument {
            SearchIndexDocument(vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role, document: NoteDocument(relativePath: path, rawContent: source))
        }
        func request(_ query: String, limit: Int = 100, offset: Int = 0) -> SearchRequest {
            SearchRequest(query: query, presentationScope: .triptych, executionScope: .triptych, limit: limit, offset: offset)
        }
    }
}

private extension String {
    func substringForUTF16Range(_ range: SearchHighlight) -> String {
        (self as NSString).substring(with: NSRange(location: range.utf16LowerBound, length: range.utf16UpperBound - range.utf16LowerBound))
    }
}
