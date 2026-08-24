import Foundation
import SQLite3
import ScholiumContracts
import Testing
@testable import ScholiumCore

/// The original 17 lexical baselines are retained here, but execute against
/// the only user-reachable Search v9 engine. They are regression evidence, not a
/// second implementation contract.
@Suite("Search v9 retained lexical baselines")
struct SearchIndexTests {
    @Test("Phrases, prefixes, fields, CJK, and retrieval classification share one contract")
    func queryContract() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([
            fixture.item(fixture.analyses, "Papers/Reasons.md", """
            ---
            keywords: [reasons, normativity]
            status: reviewed
            ---
            # Deliberative Control
            A reason can guide deliberation. 哲学研究需要概念精确。

            > [!state] Guidance
            > This is an argument about control.

            A claim.[^note]
            [^note]: A source-sensitive footnote.
            """, metadataFields: [
                "type": .string("journal_article"),
                "title": .string("Normative Reasons"),
                "authors": .array([.object([
                    "family": .string("Scanlon"),
                    "given": .string("T."),
                ])]),
                "publication_date": .string("1998"),
            ]),
            fixture.item(fixture.analyses, "Papers/Other.md", "---\ntitle: Other Work\n---\nA reason appears without deliberative control."),
        ])

        let phrase = try await index.testSearch(fixture.request("\"deliberative control\" author:Scanlon"))
        #expect(phrase.noteResults.map(\.relativePath) == ["Papers/Reasons.md"])
        #expect(phrase.noteResults.first?.classification == .retrievalLead)
        #expect(try await index.testSearch(fixture.request("delib* keyword:reasons")).noteResults.first?.relativePath == "Papers/Reasons.md")
        #expect(try await index.testSearch(fixture.request("control -other")).noteResults.map(\.relativePath) == ["Papers/Reasons.md"])
        #expect(try await index.testSearch(fixture.request("哲")).noteResults.first?.relativePath == "Papers/Reasons.md")
        #expect(try await index.testSearch(fixture.request("哲学")).noteResults.first?.relativePath == "Papers/Reasons.md")
        #expect(try await index.testSearch(fixture.request("callout:state Guidance")).noteResults.first?.matchedField == .callout)
        #expect(SearchQueryParser.parse("callout:argument Guidance").diagnostics.first?.code == .unknownStructuredValue)
    }

    @Test("Canonical Unicode equivalence is searchable")
    func canonicalUnicodeEquivalence() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([
            fixture.item(fixture.analyses, "Papers/Cafe.md", "A Cafe\u{301} argument remains searchable."),
        ])
        #expect(try await index.testSearch(fixture.request("Café")).noteResults.map(\.relativePath) == ["Papers/Cafe.md"])
    }

    @Test("FTS diacritic folding preserves exact ranking and source ranges")
    func diacriticInsensitiveLexicalVerification() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try fixture.index()
        let source = "A naïve argument."
        _ = try await index.synchronize([
            fixture.item(
                fixture.analyses,
                "Papers/Café.md",
                source,
                metadataFields: [
                    "type": .string("journal_article"),
                    "title": .string("Café Ethics"),
                ]
            ),
        ])

        let foldedTitle = try #require(
            await index.testSearch(fixture.request("\"cafe ethics\"")).noteResults.first
        )
        #expect(foldedTitle.rankReason == .lexicalRelevance)
        #expect(foldedTitle.matchedField == .title)
        #expect(foldedTitle.sourceRange == nil)

        let exactTitle = try #require(
            await index.testSearch(fixture.request("\"Café Ethics\"")).noteResults.first
        )
        #expect(exactTitle.rankReason == .exactTitle)

        let foldedBody = try #require(
            await index.testSearch(fixture.request("naive")).noteResults.first
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
        #expect(try await index.testSearch(fixture.request("original-search-term")).noteResults.map(\.relativePath) == ["Original.md"])
        #expect(try await index.testSearch(fixture.request("replacement-search-term")).noteResults.isEmpty)
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

    @Test("Parser diagnostics do not change current index availability")
    func parserDiagnosticsDoNotChangeAvailability() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([fixture.item(fixture.analyses, "A.md", "searchable text")])
        #expect(SearchQueryParser.parse("\"missing close").diagnostics.first?.code == .unclosedPhrase)
        #expect(SearchQueryParser.parse("title:").diagnostics.first?.code == .missingFieldValue)
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
            # Deliberative Control
            A reason can guide **deliberation**.
            """, metadataFields: [
                "type": .string("journal_article"),
                "title": .string("Normative Reasons"),
                "authors": .array([.object([
                    "family": .string("Scanlon"),
                    "given": .string("T."),
                ])]),
            ]),
            fixture.item(
                fixture.analyses,
                "Papers/CJK.md",
                "中文正文保持清晰。",
                metadataFields: [
                    "type": .string("journal_article"),
                    "title": .string("价值理论"),
                ]
            ),
        ])
        let title = try #require(await index.testSearch(fixture.request("title:\"Normative Reasons\"")).noteResults.first)
        #expect(title.matchedField == .title)
        #expect(title.snippet == "Normative Reasons")
        #expect(!title.snippet.contains("title:"))
        let author = try #require(await index.testSearch(fixture.request("author:Scanlon")).noteResults.first)
        #expect(author.snippet == "T. Scanlon")
        let authorPhraseRequest = fixture.request("author:\"T. Scanlon\"")
        let authorPhraseAST = try #require(
            SearchQueryParser.parse(authorPhraseRequest.query).ast
        )
        #expect(authorPhraseAST.positiveLexicalClauses.first?.value == .phrase("t. scanlon"))
        let authorPhrase = try await index.testSearch(authorPhraseRequest)
            .noteResults.first?.snippet
        #expect(authorPhrase == "T. Scanlon")
        let body = try #require(await index.testSearch(fixture.request("deliberation")).noteResults.first)
        #expect(body.snippet.contains("guide deliberation"))
        #expect(!body.snippet.contains("**"))
        let cjk = try #require(await index.testSearch(fixture.request("title:价值理论")).noteResults.first)
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
        let response = try await index.testSearch(fixture.request("target", scope: .currentVault(fixture.analyses.id), limit: 1))
        #expect(response.noteResults.map(\.relativePath) == ["A.md"])
    }

    @Test("A 512-note fixture ranks H1 and managed titles, then alias and body")
    func explainableScholarlyRanking() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try fixture.index()
        var documents = (0..<508).map { number in
            fixture.item(fixture.analyses, "Background/Note-\(number).md", "---\ntitle: Background \(number)\n---\nA bounded note about evidence and inference.")
        }
        documents += [
            fixture.item(fixture.analyses, "Title.md", "A concise account.", metadataFields: [
                "type": .string("journal_article"),
                "title": .string("Deliberative Autonomy"),
            ]),
            fixture.item(fixture.topics, "Alias.md", "# Agency Structure\nA concise account.", metadataFields: [
                "aliases": .array([.string("Deliberative Autonomy")]),
            ]),
            fixture.item(fixture.analyses, "Heading.md", "---\ntitle: Normative Architecture\n---\n# Deliberative Autonomy\nA concise account."),
            fixture.item(fixture.analyses, "Body.md", "---\ntitle: Practical Reason\n---\nThis develops deliberative autonomy."),
        ]
        _ = try await index.synchronize(documents)
        let hits = try await index.testSearch(fixture.request("\"deliberative autonomy\"", limit: 10))
        #expect(hits.noteResults.map(\.relativePath)
            == ["Heading.md", "Title.md", "Alias.md", "Body.md"])
        #expect(hits.noteResults.map(\.matchedField) == [.title, .title, .alias, .body])
    }

    @Test("Large collisions preserve deterministic field precedence")
    func largerExplainableRankingCollisionFixture() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try fixture.index()
        let leading = [
            fixture.item(fixture.analyses, "00-title.md", "Short.", metadataFields: ["type": .string("journal_article"), "title": .string("Practical Identity")]),
            fixture.item(fixture.analyses, "01-title.md", "Short.", metadataFields: ["type": .string("journal_article"), "title": .string("Practical Identity")]),
            fixture.item(fixture.topics, "10-alias.md", "# Alpha\nShort.", metadataFields: ["aliases": .array([.string("Practical Identity")])]),
            fixture.item(fixture.topics, "11-alias.md", "# Beta\nShort.", metadataFields: ["aliases": .array([.string("Practical Identity")])]),
            fixture.item(fixture.analyses, "20-heading.md", "---\ntitle: Gamma\n---\n# Practical Identity\nShort."),
            fixture.item(fixture.analyses, "21-heading.md", "---\ntitle: Delta\n---\n# Practical Identity\nShort."),
        ]
        let background = (0..<2_048).map {
            fixture.item(fixture.analyses, String(format: "Background/%04d.md", $0), "A note about practical identity.")
        }
        _ = try await index.synchronize(leading + background)
        let first = try await index.testSearch(fixture.request("\"practical identity\"", limit: 20))
        #expect(first.noteResults.prefix(6).map(\.relativePath) == [
            "20-heading.md", "21-heading.md", "00-title.md", "01-title.md",
            "10-alias.md", "11-alias.md",
        ])
        let repeated = try await index.testSearch(fixture.request("\"practical identity\"", limit: 20))
        #expect(repeated.noteResults.map(\.relativePath) == first.noteResults.map(\.relativePath))
    }

    @Test("Exact filename and path rank before body occurrences")
    func exactNoteIdentityPrecedesBodyMatches() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([
            fixture.item(fixture.analyses, "Archive/Known Note.md", "---\ntitle: Archival Entry\n---\nNo matching prose."),
            fixture.item(fixture.analyses, "Body.md", "Known Note and Archive/Known Note.md appear here."),
        ])
        #expect(try await index.testSearch(fixture.request("\"Known Note\"")).noteResults.first?.rankReason == .exactFilename)
        #expect(try await index.testSearch(fixture.request("\"Archive/Known Note.md\"")).noteResults.first?.rankReason == .exactPath)
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
        #expect(try await incremental.testSearch(fixture.request("second")).noteResults.map(\.relativePath)
            == clean.testSearch(fixture.request("second")).noteResults.map(\.relativePath))
        #expect(try await incremental.generation()?.sourceManifestHash == clean.generation()?.sourceManifestHash)
    }

    @Test("Synchronization tracks derived broken-link state")
    func synchronizationTracksDerivedState() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try fixture.index()
        let source = NoteDocument(relativePath: "A.md", rawContent: "[[Missing]]")
        let metadata: [String: YAMLValue] = ["type": .string("journal_article"), "title": .string("Alpha")]
        let broken = fixture.item(fixture.analyses, document: source, metadataFields: metadata, hasBrokenLink: true)
        let repaired = fixture.item(fixture.analyses, document: source, metadataFields: metadata)
        let first = try await index.synchronize([broken])
        #expect(try await index.testSearch(fixture.request("Alpha has:broken-link")).noteResults.map(\.relativePath) == ["A.md"])
        let brokenOnly = try await index.testSearch(fixture.request("has:broken-link"))
        #expect(brokenOnly.noteResults.first?.matchedFields == [.brokenLink])
        #expect(brokenOnly.noteResults.first?.rankReason == .structuredFilter)
        guard case .structured(let structuredMatch) = try #require(
            brokenOnly.noteResults.first?.primaryMatchReason
        ) else {
            Issue.record("Structured filter-only Search did not retain its typed reason.")
            return
        }
        #expect(structuredMatch.field == .has)
        #expect(structuredMatch.value == "broken-link")
        #expect(!structuredMatch.excluded)
        let second = try await index.synchronize([repaired])
        #expect(second.generation.sequence > first.generation.sequence)
        #expect(try await index.testSearch(fixture.request("Alpha has:broken-link")).noteResults.isEmpty)
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
        #expect(try await opened.index.testSearch(fixture.request("recoverable")).noteResults.map(\.relativePath) == ["Recovered.md"])
    }

    @Test("An incompatible prior schema is replaced without touching source")
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
        #expect(result.generation.schemaVersion == SearchContract.schemaVersion)
        #expect(source.document.rawContent.contains("exact source remains external"))
    }

    @Test("Malformed generated JSON is staged and rebuilt")
    func malformedGeneratedJSONRecoveryIsVisibleAndComplete() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        var index: TriptychSearchIndex? = try fixture.index()
        let source = fixture.item(
            fixture.analyses,
            "Preserved.md",
            "# Preserved\n\nexact source remains external"
        )
        _ = try await index?.synchronize([source])
        index = nil
        try execute(
            "UPDATE search_segments SET offset_map = 'malformed-json' WHERE ordinal = 0;",
            in: fixture.databaseURL
        )

        let opened = try TriptychSearchIndex.openRecovering(
            databaseURL: fixture.databaseURL,
            triptychID: fixture.triptychID
        )
        #expect(opened.recoveredCorruption)
        let result = try await opened.index.synchronize([source])
        #expect(result.disposition == .recoveredAndRebuilt)
        #expect(try await opened.index.testSearch(
            fixture.request("preserved")
        ).noteResults.first?.sourceLine == 1)
        #expect(source.document.rawContent.contains("exact source remains external"))
    }

    @Test("Typed and semantic generated JSON corruption is staged and rebuilt")
    func typedGeneratedJSONCorruptionIsVisibleAndComplete() async throws {
        let mutations = [
            "UPDATE search_documents SET line_starts = '[0,\"bad\"]';",
            "UPDATE search_documents SET line_starts = '[0,8,4]';",
            """
            UPDATE search_segments SET offset_map =
            '[{"normalizedUTF16LowerBound":"bad","normalizedUTF16UpperBound":1,"sourceUTF16LowerBound":0,"sourceUTF16UpperBound":1}]'
            WHERE ordinal = 0;
            """,
            """
            UPDATE search_segments SET offset_map =
            '[{"normalizedUTF16LowerBound":0,"normalizedUTF16UpperBound":999999,"sourceUTF16LowerBound":0,"sourceUTF16UpperBound":1}]'
            WHERE ordinal = 0;
            """,
        ]

        for mutation in mutations {
            let fixture = try Fixture()
            defer { fixture.remove() }
            var index: TriptychSearchIndex? = try fixture.index()
            let source = fixture.item(
                fixture.analyses,
                "Preserved.md",
                "# Preserved\n\nexact source remains external"
            )
            _ = try await index?.synchronize([source])
            index = nil
            try execute(mutation, in: fixture.databaseURL)

            let opened = try TriptychSearchIndex.openRecovering(
                databaseURL: fixture.databaseURL,
                triptychID: fixture.triptychID
            )
            #expect(opened.recoveredCorruption, Comment(rawValue: mutation))
            let result = try await opened.index.synchronize([source])
            #expect(result.disposition == .recoveredAndRebuilt)
            #expect(try await opened.index.testSearch(
                fixture.request("preserved")
            ).noteResults.map(\.relativePath) == ["Preserved.md"])
            #expect(source.document.rawContent.contains("exact source remains external"))
        }
    }

    @Test("Cancelled opening preserves the last-good generated database")
    func cancelledOpeningDoesNotRecoverValidDatabase() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var index: TriptychSearchIndex? = try fixture.index()
        let source = fixture.item(
            fixture.analyses,
            "Preserved.md",
            "# Preserved\n\nlast good generated state"
        )
        let generation = try await index?.synchronize([source]).generation
        index = nil

        let opening = Task {
            try TriptychSearchIndex.openRecovering(
                databaseURL: fixture.databaseURL,
                triptychID: fixture.triptychID
            )
        }
        opening.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await opening.value
        }

        let reopened = try TriptychSearchIndex.openRecovering(
            databaseURL: fixture.databaseURL,
            triptychID: fixture.triptychID
        )
        #expect(!reopened.recoveredCorruption)
        #expect(try await reopened.index.generation() == generation)
        #expect(try await reopened.index.testSearch(
            fixture.request("last good")
        ).noteResults.map(\.relativePath) == ["Preserved.md"])
    }

    @Test("Identical paths in different vaults remain scope-isolated")
    func vaultIdentityIsolation() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([
            fixture.item(fixture.analyses, "Shared.md", "first-domain-only"),
            fixture.item(fixture.works, "Shared.md", "second-domain-only"),
        ])
        #expect(try await index.testSearch(fixture.request("first-domain-only", scope: .currentVault(fixture.analyses.id))).noteResults.count == 1)
        #expect(try await index.testSearch(fixture.request("second-domain-only", scope: .currentVault(fixture.analyses.id))).noteResults.isEmpty)
        #expect(try await index.testSearch(fixture.request("second-domain-only", scope: .currentVault(fixture.works.id))).noteResults.count == 1)
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
        let hits = try await index.testSearch(fixture.request("private"))
        #expect(Set(hits.noteResults.map(\.vaultRole)) == [.sourceCorpus, .topicKnowledge, .draftProject])
    }

    private final class Fixture: @unchecked Sendable {
        let root: URL
        let databaseURL: URL
        let triptychID = UUID()
        let analyses = RegisteredVault(name: "Analyses", role: .sourceCorpus, canonicalPath: "/fixtures/analyses")
        let topics = RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: "/fixtures/topics")
        let works = RegisteredVault(name: "Works", role: .draftProject, canonicalPath: "/fixtures/works")

        init() throws {
            root = URL(
                fileURLWithPath: FileManager.default.currentDirectoryPath,
                isDirectory: true
            )
                .appendingPathComponent(".build/search-v9-retained-tests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            databaseURL = root.appendingPathComponent("search-v9.sqlite")
        }

        func index(at url: URL? = nil) throws -> TriptychSearchIndex {
            try TriptychSearchIndex(databaseURL: url ?? databaseURL, triptychID: triptychID)
        }

        func item(
            _ vault: RegisteredVault,
            _ path: String,
            _ source: String,
            metadataFields: [String: YAMLValue]? = nil
        ) -> SearchIndexDocument {
            item(
                vault,
                document: NoteDocument(relativePath: path, rawContent: source),
                metadataFields: metadataFields
            )
        }

        func item(
            _ vault: RegisteredVault,
            document: NoteDocument,
            metadataFields: [String: YAMLValue]? = nil,
            hasBrokenLink: Bool = false
        ) -> SearchIndexDocument {
            let noteID = UUID()
            return SearchIndexDocument(
                vaultID: vault.id,
                vaultName: vault.name,
                vaultRole: vault.role,
                document: document,
                stableNoteID: noteID.uuidString.lowercased(),
                metadata: metadataFields.map {
                    NoteMetadataSnapshot(
                        record: NoteMetadataRecord(noteID: noteID, fields: $0),
                        revision: DocumentFingerprint(content: String(describing: $0))
                    )
                },
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
        try execute(
            "UPDATE search_index_state SET schema_version = \(version) WHERE singleton = 1;",
            in: databaseURL
        )
    }

    private func execute(_ sql: String, in databaseURL: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            throw FixtureError.couldNotOpenDatabase
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(
            database,
            sql,
            nil,
            nil,
            nil
        ) == SQLITE_OK else {
            throw FixtureError.couldNotExecuteSQL
        }
    }

    private enum FixtureError: Error { case couldNotOpenDatabase, couldNotExecuteSQL }
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
