import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Conservative lexical Search admission")
struct SearchConservativeAdmissionTests {
    @Test("Indexed completion displays original lexical spelling rather than folded candidate text")
    func completionSpelling() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([fixture.note("Accent.md", "café λόγος concerns reasons.")])
        for (partial, expected) in [("caf", "café"), ("λογ", "λόγοσ")] {
            let terms = try await index.completionTerms(for: .init(partial: partial, field: .body))
            #expect(terms.map(\.text) == [expected])
        }
        _ = try await index.synchronize([fixture.note("Accent.md", "crème λόγος concerns reasons.")])
        #expect(try await index.completionTerms(for: .init(partial: "caf", field: .body)).isEmpty)
        #expect(try await index.completionTerms(for: .init(partial: "cre", field: .body)).map(\.text) == ["crème"])
        let reopened = try fixture.index()
        #expect(try await reopened.completionTerms(for: .init(partial: "cre", field: .body)).map(\.text) == ["crème"])
    }

    @Test("Native token categories cannot hide exact matches adjacent to symbols or private-use characters")
    func nativeBoundaryParity() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let documents = [
            fixture.note("Private.md", "\u{E000}agency concerns reasons."),
            fixture.note("Emoji.md", "🦉agency concerns reasons.\n\n自由🦉自在 concerns comparison."),
            fixture.note("Joined.md", "foo\u{200D}bar concerns reasons.\n\n自\u{200D}由 concerns comparison."),
        ]
        let index = try fixture.index()
        _ = try await index.synchronize(documents)
        let cases: [(String, Set<String>)] = [
            ("body:agency", ["Private.md", "Emoji.md"]),
            ("body:\"🦉agency\"", ["Emoji.md"]),
            ("body:\"\u{E000}agency\"", ["Private.md"]),
            ("body:\"自由🦉自在\"", ["Emoji.md"]),
            ("body:\"foo\u{200D}bar\"", ["Joined.md"]),
            ("body:fo", ["Joined.md"]),
            ("body:foo", []),
            ("body:bar", ["Joined.md"]),
            ("body:自", ["Emoji.md"]),
            ("body:\"自\u{200D}由\"", ["Joined.md"]),
        ]
        for (query, expected) in cases {
            let response = try await index.testSearch(fixture.request(query))
            #expect(Set(response.noteResults.map(\.relativePath)) == expected, "\(query)")
            for document in documents {
                let current = try await index.testSearch(
                    .init(
                        query: query, presentationScope: .thisNote,
                        executionScope: .currentNote(
                            .init(
                                noteID: .init(vaultID: document.vaultID, relativePath: document.relativePath),
                                editorSessionID: UUID(), source: document.document.rawContent, editorRevision: 1)), limit: 50))
                #expect(!current.results.isEmpty == expected.contains(document.relativePath), "\(query), \(document.relativePath)")
            }
        }
    }

    @Test("Indexed candidates preserve exact Unicode and symbol truth in Boolean and paragraph scopes")
    func exactMatchParity() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let documents = [
            fixture.note("Greek.md", "λόγος concerns reasons.\n\nA → B and ¬ P distinguish claims."),
            fixture.note("Mixed.md", "自由→agency concerns action.\n\nλόγος→agency combines notation.\n\n自由→自在 concerns a comparison."),
            fixture.note("Other.md", "Agency concerns responsibility."),
            fixture.note("PrivateUse.md", "\u{E000} concerns a private-use character."),
            fixture.note("Emoji.md", "🦉 concerns a visible symbol."),
        ]
        let index = try fixture.index()
        _ = try await index.synchronize(documents)
        let cases: [(String, Set<String>)] = [
            ("body:λογος", ["Greek.md", "Mixed.md"]),
            ("body:\"→\"", ["Greek.md"]),
            ("body:\"¬\"", ["Greek.md"]),
            ("body:\"🦉\"", ["Emoji.md"]),
            ("body:\"\u{E000}\"", ["PrivateUse.md"]),
            ("body:\"自由→agency\"", ["Mixed.md"]),
            ("body:\"自由→自在\"", ["Mixed.md"]),
            ("body:\"λογος→agency\"", ["Mixed.md"]),
            ("body:\"→\" AND body:reasons", ["Greek.md"]),
            ("body:\"🦉\" OR body:responsibility", ["Emoji.md", "Other.md"]),
            ("NOT body:\"🦉\" AND body:concerns", ["Greek.md", "Mixed.md", "Other.md", "PrivateUse.md"]),
            ("paragraph:(\"→\" AND claims)", ["Greek.md"]),
        ]
        for (query, expected) in cases {
            let response = try await index.testSearch(fixture.request(query))
            #expect(Set(response.noteResults.map(\.relativePath)) == expected, "\(query)")
            for document in documents {
                let current = try await index.testSearch(
                    .init(
                        query: query, presentationScope: .thisNote,
                        executionScope: .currentNote(
                            .init(
                                noteID: .init(vaultID: document.vaultID, relativePath: document.relativePath),
                                editorSessionID: UUID(), source: document.document.rawContent, editorRevision: 1)), limit: 50))
                #expect(!current.results.isEmpty == expected.contains(document.relativePath), "\(query), \(document.relativePath)")
            }
        }
        let scoped = try await index.testSearch(
            .init(
                query: "body:\"→\" OR body:\"🦉\"", presentationScope: .triptych,
                executionScope: .triptych, limit: 50, includedVaultIDs: [UUID()]))
        #expect(scoped.results.isEmpty)
        let otherVaultID = UUID()
        let scopedIndex = try fixture.index(name: "vault-scope.sqlite")
        _ = try await scopedIndex.synchronize(
            documents + [
                .init(
                    vaultID: otherVaultID, vaultName: "Other Topics", vaultRole: .topicKnowledge,
                    document: .init(relativePath: "Outside.md", rawContent: "A → B and 🦉 concern claims."))
            ])
        let authorized = try await scopedIndex.testSearch(
            .init(
                query: "body:\"→\" OR body:\"🦉\"", presentationScope: .triptych,
                executionScope: .triptych, limit: 50, includedVaultIDs: [fixture.vaultID]))
        #expect(Set(authorized.noteResults.map(\.relativePath)) == ["Greek.md", "Emoji.md"])
        #expect(authorized.noteResults.allSatisfy { $0.vaultID == fixture.vaultID })
    }

    @Test("Normalization-equivalent predicates contribute one rank without merging fields or match kinds")
    func normalizedPredicateRanks() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([
            fixture.note("A Agency.md", "agency thought."),
            fixture.note("B Cafe.md", "café thought."),
        ])
        let baseline = try await index.testSearch(fixture.request("body:cafe OR body:agency"))
        #expect(baseline.noteResults.map(\.relativePath) == ["A Agency.md", "B Cafe.md"])
        for duplicate in ["café", "CAFE", "cafe\u{301}"] {
            let response = try await index.testSearch(fixture.request("body:cafe OR body:agency OR body:\(duplicate)"))
            #expect(response.noteResults.map(\.relativePath) == baseline.noteResults.map(\.relativePath))
        }
        let phrase = try await index.testSearch(fixture.request("body:\"cafe thought\" OR body:agency"))
        let repeatedPhrase = try await index.testSearch(fixture.request("body:\"cafe thought\" OR body:agency OR body:\"café thought\""))
        #expect(repeatedPhrase.noteResults.map(\.relativePath) == phrase.noteResults.map(\.relativePath))
        let prefix = try await index.testSearch(fixture.request("body:caf* OR body:agency"))
        let repeatedPrefix = try await index.testSearch(fixture.request("body:caf* OR body:agency OR body:cáf*"))
        #expect(repeatedPrefix.noteResults.map(\.relativePath) == prefix.noteResults.map(\.relativePath))
        for distinct in ["title:cafe", "body:cafe*", "body:\"cafe\""] {
            let response = try await index.testSearch(fixture.request("body:cafe OR body:agency OR \(distinct)"))
            #expect(response.noteResults.map(\.relativePath) == ["B Cafe.md", "A Agency.md"])
        }
    }

    @Test(
        "Superseded lexical policies rebuild derived state and preserve source bytes",
        arguments: ["schema_version", "tokenizer_policy_version", "ranking_policy_version"])
    func incompatiblePolicyRebuild(_ policy: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = Data("---\r\ntitle: λόγος\r\nunknown: 'Élan'\r\n---\r\nλόγος → reasons.\r\n".utf8)
        let sourceURL = fixture.root.appendingPathComponent("Greek.md")
        try source.write(to: sourceURL)
        let documents = [fixture.note("Greek.md", String(decoding: source, as: UTF8.self))]
        let databaseURL = fixture.root.appendingPathComponent("index.sqlite")
        do {
            let index = try fixture.index()
            _ = try await index.synchronize(documents)
        }
        do {
            let database = try SearchSQLiteDatabase(path: databaseURL.path)
            try database.execute("UPDATE search_index_state SET \(policy) = \(policy) - 1;")
        }
        let opened = try TriptychSearchIndex.openRecovering(databaseURL: databaseURL, triptychID: fixture.triptychID)
        #expect(opened.recoveredCorruption)
        #expect(try await opened.index.synchronize(documents).disposition == .recoveredAndRebuilt)
        let response = try await opened.index.testSearch(fixture.request("body:λογος AND body:\"→\""))
        #expect(response.noteResults.map(\.relativePath) == ["Greek.md"])
        #expect(try Data(contentsOf: sourceURL) == source)
        let reopened = try fixture.index()
        #expect(try await reopened.testSearch(fixture.request("body:λογος")).noteResults.map(\.relativePath) == ["Greek.md"])
    }

    @Test("Edited, moved, deleted and recreated Unicode Notes agree with reopening and clean rebuilding")
    func mutationAndRebuildParity() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        var documents = [fixture.note("Greek.md", "λόγος → reasons.")]
        for step in 0..<5 {
            if step == 1 { documents = [fixture.note("Greek.md", "ѝ → agency.")] }
            if step == 2 { documents = [fixture.note("Moved.md", "ѝ → agency.")] }
            if step == 3 { documents = [] }
            if step == 4 { documents = [fixture.note("Greek.md", "λόγος ¬ reasons.")] }
            _ = try await index.synchronize(documents)
            let reopened = try fixture.index()
            let rebuilt = try fixture.index(name: "rebuilt-\(step).sqlite")
            _ = try await rebuilt.synchronize(documents)
            for query in ["body:λογος", "body:и", "body:\"→\"", "body:\"¬\""] {
                let current = try await index.testSearch(fixture.request(query))
                let restored = try await reopened.testSearch(fixture.request(query))
                let clean = try await rebuilt.testSearch(fixture.request(query))
                let presentQueries: [Set<String>] = [
                    ["body:λογος", "body:\"→\""], ["body:и", "body:\"→\""],
                    ["body:и", "body:\"→\""], [], ["body:λογος", "body:\"¬\""],
                ]
                let expected = presentQueries[step].contains(query) ? documents.map(\.relativePath) : []
                #expect(current.noteResults.map(\.relativePath) == expected)
                #expect(current.noteResults.map(\.relativePath) == restored.noteResults.map(\.relativePath))
                #expect(current.noteResults.map(\.relativePath) == clean.noteResults.map(\.relativePath))
                for note in current.noteResults {
                    #expect(documents.contains { $0.relativePath == note.relativePath && $0.document.fingerprint == note.fingerprint })
                }
            }
        }
    }

    private struct Fixture {
        let root: URL
        let triptychID = UUID()
        let vaultID = UUID()

        init() throws {
            root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(".build/search-conservative-admission/\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
        func index(name: String = "index.sqlite") throws -> TriptychSearchIndex {
            try TriptychSearchIndex(databaseURL: root.appendingPathComponent(name), triptychID: triptychID)
        }
        func note(_ path: String, _ source: String) -> SearchIndexDocument {
            .init(
                vaultID: vaultID, vaultName: "Topics", vaultRole: .topicKnowledge,
                document: .init(relativePath: path, rawContent: source))
        }
        func request(_ query: String) -> SearchRequest {
            .init(query: query, presentationScope: .triptych, executionScope: .triptych, limit: 50)
        }
    }
}
