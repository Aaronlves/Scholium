import Foundation
import SQLite3
import ScholiumContracts
import Testing
@testable import ScholiumCore

/// The original 17 lexical baselines are retained here, but execute against
/// the only user-reachable v3 engine. They are regression evidence, not a
/// second implementation contract.
@Suite("Search v3 retained lexical baselines")
struct SearchIndexTests {
    @Test("Phrases, prefixes, fields, CJK, and retrieval classification share one contract")
    func queryContract() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([
            fixture.item(fixture.analyses, "Papers/Reasons.md", """
            ---
            title: Normative Reasons
            authors: [T. Scanlon]
            year: 1998
            tags: [reasons, normativity]
            status: reviewed
            ---
            # Deliberative Control
            A reason can guide deliberation. 哲学研究需要概念精确。

            > [!state] Guidance
            > This is an argument about control.

            A claim.[^note]
            [^note]: A source-sensitive footnote.
            """),
            fixture.item(fixture.analyses, "Papers/Other.md", "---\ntitle: Other Work\n---\nA reason appears without deliberative control."),
        ])

        let phrase = try await index.search(fixture.request("\"deliberative control\" author:Scanlon"))
        #expect(phrase.results.map(\.relativePath) == ["Papers/Reasons.md"])
        #expect(phrase.results.first?.classification == .retrievalLead)
        #expect(try await index.search(fixture.request("delib* tag:reasons")).results.first?.relativePath == "Papers/Reasons.md")
        #expect(try await index.search(fixture.request("control -other")).results.map(\.relativePath) == ["Papers/Reasons.md"])
        #expect(try await index.search(fixture.request("哲")).results.first?.relativePath == "Papers/Reasons.md")
        #expect(try await index.search(fixture.request("哲学")).results.first?.relativePath == "Papers/Reasons.md")
        #expect(try await index.search(fixture.request("callout:state Guidance")).results.first?.matchedField == .callout)
        #expect(try await index.search(fixture.request("callout:argument Guidance")).diagnostics.first?.code == .unknownStructuredValue)
    }

    @Test("Canonical Unicode equivalence is searchable")
    func canonicalUnicodeEquivalence() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([
            fixture.item(fixture.analyses, "Papers/Cafe.md", "A Cafe\u{301} argument remains searchable."),
        ])
        #expect(try await index.search(fixture.request("Café")).results.map(\.relativePath) == ["Papers/Cafe.md"])
    }

    @Test("FTS diacritic folding preserves exact ranking and source ranges")
    func diacriticInsensitiveLexicalVerification() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try fixture.index()
        let source = "---\ntitle: Café Ethics\n---\nA naïve argument."
        _ = try await index.synchronize([
            fixture.item(fixture.analyses, "Papers/Café.md", source),
        ])

        let foldedTitle = try #require(
            await index.search(fixture.request("\"cafe ethics\"")).results.first
        )
        #expect(foldedTitle.rankReason == .lexicalRelevance)
        #expect(foldedTitle.matchedField == .title)
        let titleRange = try #require(foldedTitle.sourceRange)
        #expect((source as NSString).substring(
            with: NSRange(
                location: titleRange.utf16LowerBound,
                length: titleRange.utf16UpperBound - titleRange.utf16LowerBound
            )
        ) == "Café Ethics")

        let exactTitle = try #require(
            await index.search(fixture.request("\"Café Ethics\"")).results.first
        )
        #expect(exactTitle.rankReason == .exactTitle)

        let foldedBody = try #require(
            await index.search(fixture.request("naive")).results.first
        )
        let bodyRange = try #require(foldedBody.sourceRange)
        #expect((source as NSString).substring(
            with: NSRange(
                location: bodyRange.utf16LowerBound,
                length: bodyRange.utf16UpperBound - bodyRange.utf16LowerBound
            )
        ) == "naïve")
    }

    @Test("Cancellation rolls back a complete generation")
    func cancelledRebuildRollsBack() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try fixture.index()
        let original = fixture.item(fixture.analyses, "Original.md", "original-search-term")
        let first = try await index.synchronize([original])
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await index.synchronize([
                fixture.item(fixture.analyses, "Replacement.md", "replacement-search-term"),
            ])
        }
        await #expect(throws: CancellationError.self) { _ = try await cancelled.value }
        #expect(try await index.generation() == first.generation)
        #expect(try await index.search(fixture.request("original-search-term")).results.map(\.relativePath) == ["Original.md"])
        #expect(try await index.search(fixture.request("replacement-search-term")).results.isEmpty)
    }

    @Test("Cancellation rolls back an empty generation")
    func cancelledEmptyRebuildRollsBack() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try fixture.index()
        let original = fixture.item(fixture.analyses, "Original.md", "original-search-term")
        let first = try await index.synchronize([original])
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await index.synchronize([])
        }
        await #expect(throws: CancellationError.self) { _ = try await cancelled.value }
        #expect(try await index.generation() == first.generation)
    }

    @Test("Malformed clauses return query diagnostics without failing the index")
    func malformedQueryDiagnostics() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([fixture.item(fixture.analyses, "A.md", "searchable text")])
        #expect(try await index.search(fixture.request("\"missing close")).diagnostics.first?.code == .unclosedPhrase)
        let removed = try await index.search(fixture.request("role:analyses searchable"))
        #expect(removed.diagnostics.first?.code == .removedField)
        #expect(removed.diagnostics.first?.needsEditing == true)
        #expect(try await index.search(fixture.request("title:")).diagnostics.first?.code == .missingFieldValue)
        guard case .current = await index.availability() else {
            Issue.record("Query diagnostics changed index availability")
            return
        }
    }

    @Test("Result snippets expose semantic fields without YAML syntax")
    func cleanSearchPresentation() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([
            fixture.item(fixture.analyses, "Papers/Reasons.md", """
            ---
            title: Normative Reasons
            authors: [T. Scanlon]
            tags: [reasons, normativity]
            ---
            # Deliberative Control
            A reason can guide **deliberation**.
            """),
            fixture.item(fixture.analyses, "Papers/CJK.md", "---\ntitle: 价值理论\n---\n中文正文保持清晰。"),
        ])
        let title = try #require(await index.search(fixture.request("title:\"Normative Reasons\"")).results.first)
        #expect(title.matchedField == .title)
        #expect(title.snippet == "Normative Reasons")
        #expect(!title.snippet.contains("title:"))
        let author = try #require(await index.search(fixture.request("author:Scanlon")).results.first)
        #expect(author.snippet == "T. Scanlon")
        let body = try #require(await index.search(fixture.request("deliberation")).results.first)
        #expect(body.snippet.contains("guide deliberation"))
        #expect(!body.snippet.contains("**"))
        let cjk = try #require(await index.search(fixture.request("title:价值理论")).results.first)
        #expect(cjk.highlights.allSatisfy { $0.utf16UpperBound <= cjk.snippet.utf16.count })
    }

    @Test("Current Vault scope cannot be displaced by another vault")
    func exactVaultScope() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([
            fixture.item(fixture.analyses, "A.md", "target concept appears once"),
            fixture.item(fixture.works, "B.md", "target target target concept"),
        ])
        let response = try await index.search(fixture.request("target", scope: .currentVault(fixture.analyses.id), limit: 1))
        #expect(response.results.map(\.relativePath) == ["A.md"])
    }

    @Test("A 512-note fixture ranks exact title, alias, heading, then body")
    func explainableScholarlyRanking() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try fixture.index()
        var documents = (0..<508).map { number in
            fixture.item(fixture.analyses, "Background/Note-\(number).md", "---\ntitle: Background \(number)\n---\nA bounded note about evidence and inference.")
        }
        documents += [
            fixture.item(fixture.analyses, "Title.md", "---\ntitle: Deliberative Autonomy\n---\nA concise account."),
            fixture.item(fixture.analyses, "Alias.md", "---\ntitle: Agency Structure\naliases: [Deliberative Autonomy]\n---\nA concise account."),
            fixture.item(fixture.analyses, "Heading.md", "---\ntitle: Normative Architecture\n---\n# Deliberative Autonomy\nA concise account."),
            fixture.item(fixture.analyses, "Body.md", "---\ntitle: Practical Reason\n---\nThis develops deliberative autonomy."),
        ]
        _ = try await index.synchronize(documents)
        let hits = try await index.search(fixture.request("\"deliberative autonomy\"", limit: 10))
        #expect(hits.results.map(\.relativePath) == ["Title.md", "Alias.md", "Heading.md", "Body.md"])
        #expect(hits.results.map(\.matchedField) == [.title, .alias, .heading, .body])
    }

    @Test("Large collisions preserve deterministic field precedence")
    func largerExplainableRankingCollisionFixture() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try fixture.index()
        let leading = [
            fixture.item(fixture.analyses, "00-title.md", "---\ntitle: Practical Identity\n---\nShort."),
            fixture.item(fixture.analyses, "01-title.md", "---\ntitle: Practical Identity\n---\nShort."),
            fixture.item(fixture.analyses, "10-alias.md", "---\ntitle: Alpha\naliases: [Practical Identity]\n---\nShort."),
            fixture.item(fixture.analyses, "11-alias.md", "---\ntitle: Beta\naliases: [Practical Identity]\n---\nShort."),
            fixture.item(fixture.analyses, "20-heading.md", "---\ntitle: Gamma\n---\n# Practical Identity\nShort."),
            fixture.item(fixture.analyses, "21-heading.md", "---\ntitle: Delta\n---\n# Practical Identity\nShort."),
        ]
        let background = (0..<2_048).map {
            fixture.item(fixture.analyses, String(format: "Background/%04d.md", $0), "A note about practical identity.")
        }
        _ = try await index.synchronize(leading + background)
        let first = try await index.search(fixture.request("\"practical identity\"", limit: 20))
        #expect(first.results.prefix(6).map(\.relativePath) == [
            "00-title.md", "01-title.md", "10-alias.md", "11-alias.md",
            "21-heading.md", "20-heading.md",
        ])
        let repeated = try await index.search(fixture.request("\"practical identity\"", limit: 20))
        #expect(repeated.results.map(\.relativePath) == first.results.map(\.relativePath))
    }

    @Test("Exact filename and path rank before body occurrences")
    func exactNoteIdentityPrecedesBodyMatches() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([
            fixture.item(fixture.analyses, "Archive/Known Note.md", "---\ntitle: Archival Entry\n---\nNo matching prose."),
            fixture.item(fixture.analyses, "Body.md", "Known Note and Archive/Known Note.md appear here."),
        ])
        #expect(try await index.search(fixture.request("\"Known Note\"")).results.first?.rankReason == .exactFilename)
        #expect(try await index.search(fixture.request("\"Archive/Known Note.md\"")).results.first?.rankReason == .exactPath)
    }

    @Test("Incremental inventory synchronization converges with a clean rebuild")
    func incrementalParity() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let incremental = try fixture.index()
        let first = fixture.item(fixture.analyses, "A.md", "---\ntitle: Alpha\n---\nfirst concept")
        let second = fixture.item(fixture.analyses, "B.md", "---\ntitle: Beta\n---\nsecond concept")
        _ = try await incremental.synchronize([first, second])
        let edited = fixture.item(fixture.analyses, "A.md", "---\ntitle: Alpha Revised\n---\nsecond concept revised")
        let renamed = fixture.item(fixture.analyses, "C.md", second.document.rawContent)
        _ = try await incremental.synchronize([edited, renamed])

        let clean = try fixture.index(at: fixture.root.appendingPathComponent("clean.sqlite"))
        _ = try await clean.synchronize([edited, renamed])
        #expect(try await incremental.search(fixture.request("second")).results.map(\.relativePath)
            == clean.search(fixture.request("second")).results.map(\.relativePath))
        #expect(try await incremental.generation()?.sourceManifestHash == clean.generation()?.sourceManifestHash)
    }

    @Test("Synchronization tracks derived broken-link and review state")
    func synchronizationTracksDerivedState() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try fixture.index()
        let source = NoteDocument(relativePath: "A.md", rawContent: "---\ntitle: Alpha\n---\n[[Missing]]")
        let broken = fixture.item(fixture.analyses, document: source, hasBrokenLink: true)
        let repaired = fixture.item(fixture.analyses, document: source, review: "qualified")
        let first = try await index.synchronize([broken])
        #expect(try await index.search(fixture.request("Alpha has:broken-link")).results.map(\.relativePath) == ["A.md"])
        let brokenOnly = try await index.search(fixture.request("has:broken-link"))
        #expect(brokenOnly.results.first?.matchedFields == [.brokenLink])
        #expect(brokenOnly.results.first?.rankReason == .structuredFilter)
        let second = try await index.synchronize([repaired])
        #expect(second.generation.sequence > first.generation.sequence)
        #expect(try await index.search(fixture.request("Alpha has:broken-link")).results.isEmpty)
        #expect(try await index.search(fixture.request("Alpha review:reviewed")).results.map(\.relativePath) == ["A.md"])
        #expect(try await index.search(fixture.request("Alpha review:qualified")).results.map(\.relativePath) == ["A.md"])
        let reviewOnly = try await index.search(fixture.request("review:qualified"))
        #expect(reviewOnly.results.first?.matchedFields == [.review])
        #expect(reviewOnly.results.first?.rankReason == .structuredFilter)
        #expect(try await index.search(fixture.request("Alpha -review:reviewed")).results.isEmpty)
    }

    @Test("An unchanged inventory retains its generation")
    func unchangedInventoryMatchesPersistedDescriptor() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try fixture.index()
        let item = fixture.item(fixture.analyses, "A.md", "---\ntitle: Alpha\n---\nunchanged")
        let first = try await index.synchronize([item])
        let second = try await index.synchronize([item])
        #expect(second.disposition == .unchanged)
        #expect(second.generation == first.generation)
    }

    @Test("A corrupt generated database is staged and rebuilt")
    func corruptDatabaseRecoveryIsVisibleAndComplete() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        try Data("not a sqlite database".utf8).write(to: fixture.databaseURL)
        let opened = try TriptychSearchIndex.openRecovering(databaseURL: fixture.databaseURL, triptychID: fixture.triptychID)
        #expect(opened.recoveredCorruption)
        let result = try await opened.index.synchronize([
            fixture.item(fixture.analyses, "Recovered.md", "---\ntitle: Recovered\n---\nrecoverable concept"),
        ])
        #expect(result.disposition == .recoveredAndRebuilt)
        #expect(try await opened.index.search(fixture.request("recoverable")).results.map(\.relativePath) == ["Recovered.md"])
    }

    @Test("An incompatible v3 schema is replaced without touching source")
    func incompatibleContractRecoveryIsVisibleAndComplete() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        var index: TriptychSearchIndex? = try fixture.index()
        let source = fixture.item(fixture.analyses, "Preserved.md", "---\ntitle: Preserved\n---\nexact source remains external")
        _ = try await index?.synchronize([source])
        index = nil
        try setSchemaVersion(1, in: fixture.databaseURL)
        let opened = try TriptychSearchIndex.openRecovering(databaseURL: fixture.databaseURL, triptychID: fixture.triptychID)
        #expect(opened.recoveredCorruption)
        let result = try await opened.index.synchronize([source])
        #expect(result.generation.schemaVersion == SearchContractV3.schemaVersion)
        #expect(source.document.rawContent.contains("exact source remains external"))
    }

    @Test("Identical paths in different vaults remain scope-isolated")
    func vaultIdentityIsolation() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([
            fixture.item(fixture.analyses, "Shared.md", "first-domain-only"),
            fixture.item(fixture.works, "Shared.md", "second-domain-only"),
        ])
        #expect(try await index.search(fixture.request("first-domain-only", scope: .currentVault(fixture.analyses.id))).results.count == 1)
        #expect(try await index.search(fixture.request("second-domain-only", scope: .currentVault(fixture.analyses.id))).results.isEmpty)
        #expect(try await index.search(fixture.request("second-domain-only", scope: .currentVault(fixture.works.id))).results.count == 1)
    }

    @Test("Triptych search includes every configured vault")
    func completeTriptychSearch() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([
            fixture.item(fixture.analyses, "Paper.md", "Shared private phrase"),
            fixture.item(fixture.topics, "Topic.md", "Shared private phrase"),
            fixture.item(fixture.works, "Decision.md", "Shared private phrase"),
        ])
        let hits = try await index.search(fixture.request("private"))
        #expect(Set(hits.results.map(\.vaultRole)) == [.sourceCorpus, .topicKnowledge, .draftProject])
    }

    private final class Fixture: @unchecked Sendable {
        let root: URL
        let databaseURL: URL
        let triptychID = UUID()
        let analyses = RegisteredVault(name: "Analyses", role: .sourceCorpus, canonicalPath: "/fixtures/analyses")
        let topics = RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: "/fixtures/topics")
        let works = RegisteredVault(name: "Works", role: .draftProject, canonicalPath: "/fixtures/works")

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            databaseURL = root.appendingPathComponent("search-v3.sqlite")
        }

        func index(at url: URL? = nil) throws -> TriptychSearchIndex {
            try TriptychSearchIndex(databaseURL: url ?? databaseURL, triptychID: triptychID)
        }

        func item(_ vault: RegisteredVault, _ path: String, _ source: String) -> SearchIndexDocument {
            item(vault, document: NoteDocument(relativePath: path, rawContent: source))
        }

        func item(
            _ vault: RegisteredVault,
            document: NoteDocument,
            review: String? = nil,
            hasBrokenLink: Bool = false
        ) -> SearchIndexDocument {
            SearchIndexDocument(
                vaultID: vault.id,
                vaultName: vault.name,
                vaultRole: vault.role,
                document: document,
                review: review,
                hasBrokenLink: hasBrokenLink
            )
        }

        func request(
            _ query: String,
            scope: SearchExecutionScope = .triptych,
            limit: Int = 100
        ) -> SearchRequest {
            SearchRequest(
                query: query,
                presentationScope: scope.presentationScope,
                executionScope: scope,
                limit: limit
            )
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    private func setSchemaVersion(_ version: Int, in databaseURL: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            throw FixtureError.couldNotOpenDatabase
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(
            database,
            "UPDATE search_index_state SET schema_version = \(version) WHERE singleton = 1;",
            nil,
            nil,
            nil
        ) == SQLITE_OK else {
            throw FixtureError.couldNotSetSchemaVersion
        }
    }

    private enum FixtureError: Error { case couldNotOpenDatabase, couldNotSetSchemaVersion }
}

private extension SearchExecutionScope {
    var presentationScope: SearchPresentationScope {
        switch self {
        case .currentNote: .thisNote
        case .currentVault: .currentVault
        case .triptych: .triptych
        }
    }
}
