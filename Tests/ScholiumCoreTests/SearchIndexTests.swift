import Foundation
import SQLite3
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Persistent shared lexical search")
struct SearchIndexTests {
    @Test("Phrases, explicit prefixes, fields, CJK, and retrieval classification share one contract")
    func queryContract() async throws {
        let fixture = try Fixture()
        let index = try SQLiteSearchIndex(databaseURL: fixture.databaseURL, vaultID: fixture.vault.id)
        let documents = [
            fixture.item("Papers/Reasons.md", """
            ---
            title: Normative Reasons
            authors: [T. Scanlon]
            year: 1998
            tags: [reasons, normativity]
            status: reviewed
            ---
            # Deliberative Control
            A reason can guide deliberation. 哲学研究需要概念精确。

            > [!argument] Guidance
            > This is an argument about control.

            A claim.[^note]
            [^note]: A source-sensitive footnote.
            """),
            fixture.item("Papers/Other.md", "---\ntitle: Other Work\nauthors: [Someone Else]\n---\nA reason appears without deliberative control.")
        ]
        _ = try await index.rebuild(documents)

        let phrase = try await index.search(SearchQuery("\"deliberative control\" author:Scanlon"))
        #expect(phrase.map(\.relativePath) == ["Papers/Reasons.md"])
        #expect(phrase.first?.classification == .retrievalLead)
        #expect(phrase.first?.sourceLine == 8)

        let prefix = try await index.search(SearchQuery("delib* tag:reasons"))
        #expect(prefix.first?.relativePath == "Papers/Reasons.md")

        let excluded = try await index.search(SearchQuery("control -other"))
        #expect(excluded.map(\.relativePath) == ["Papers/Reasons.md"])

        let cjkCharacter = try await index.search(SearchQuery("哲"))
        let cjkBigram = try await index.search(SearchQuery("哲学"))
        #expect(cjkCharacter.first?.relativePath == "Papers/Reasons.md")
        #expect(cjkBigram.first?.relativePath == "Papers/Reasons.md")

        let callout = try await index.search(SearchQuery("callout:state Guidance"))
        #expect(callout.first?.matchedField == .callout)
        let legacyCallout = try await index.search(SearchQuery("callout:argument Guidance"))
        #expect(legacyCallout.first?.relativePath == "Papers/Reasons.md")
    }

    @Test("Malformed phrases and filters report query diagnostics")
    func malformedQueryDiagnostics() async throws {
        let fixture = try Fixture()
        let index = try SQLiteSearchIndex(databaseURL: fixture.databaseURL, vaultID: fixture.vault.id)
        _ = try await index.rebuild([fixture.item("A.md", "searchable text")])

        await #expect(throws: SearchIndexError.self) {
            _ = try await index.search(SearchQuery("\"missing close"))
        }
        await #expect(throws: SearchIndexError.self) {
            _ = try await index.search(SearchQuery("role:not-a-role searchable"))
        }
        await #expect(throws: SearchIndexError.self) {
            _ = try await index.search(SearchQuery("title: searchable"))
        }
    }

    @Test("Search results present clean field context without exposing YAML syntax")
    func cleanSearchPresentation() async throws {
        let fixture = try Fixture()
        let index = try SQLiteSearchIndex(databaseURL: fixture.databaseURL, vaultID: fixture.vault.id)
        _ = try await index.rebuild([
            fixture.item("Papers/Reasons.md", """
            ---
            title: Normative Reasons
            authors: [T. Scanlon]
            tags: [reasons, normativity]
            ---
            # Deliberative Control
            A reason can guide **deliberation**.
            """),
            fixture.item("Papers/CJK.md", """
            ---
            title: 价值理论
            ---
            中文正文保持清晰。
            """),
        ])

        let title = try #require(await index.search(SearchQuery("title:\"Normative Reasons\"")).first)
        #expect(title.title == "Normative Reasons")
        #expect(title.matchedField == .title)
        #expect(title.context == "Title")
        #expect(title.snippet == "Normative Reasons")
        #expect(!title.snippet.contains("---"))
        #expect(!title.snippet.contains("title:"))
        #expect(!title.highlights.isEmpty)

        let author = try #require(await index.search(SearchQuery("author:Scanlon")).first)
        #expect(author.snippet == "T. Scanlon")
        #expect(author.context == "Author")

        let body = try #require(await index.search(SearchQuery("deliberation")).first)
        #expect(body.context == "Body")
        #expect(body.sourceLine == 7)
        #expect(body.snippet.contains("guide deliberation"))
        #expect(!body.snippet.contains("authors:"))
        #expect(!body.snippet.contains("#"))
        #expect(!body.snippet.contains("**"))

        let cjk = try #require(await index.search(SearchQuery("title:价值理论")).first)
        #expect(cjk.title == "价值理论")
        #expect(cjk.snippet == "价值理论")
        #expect(cjk.highlights.allSatisfy {
            $0.utf16LowerBound >= 0 && $0.utf16UpperBound <= cjk.snippet.utf16.count
        })
    }

    @Test("A note-scoped query cannot be displaced by higher-ranked vault results")
    func exactNoteScope() async throws {
        let fixture = try Fixture()
        let index = try SQLiteSearchIndex(databaseURL: fixture.databaseURL, vaultID: fixture.vault.id)
        _ = try await index.rebuild([
            fixture.item("A.md", "target concept appears once"),
            fixture.item("B.md", "target target target concept"),
        ])

        let hits = try await index.search(
            SearchQuery("target"),
            filter: SearchFilter(relativePath: "A.md"),
            limit: 1
        )
        #expect(hits.map(\.relativePath) == ["A.md"])
    }

    @Test("A 512-note mixed-discipline fixture ranks title, alias, heading, then body")
    func explainableScholarlyRanking() async throws {
        let fixture = try Fixture()
        let index = try SQLiteSearchIndex(databaseURL: fixture.databaseURL, vaultID: fixture.vault.id)
        let profiles: [(slug: String, title: String, alias: String, heading: String, body: String)] = [
            ("ethics", "Normative Ethics", "Moral Reasons", "Practical Deliberation", "normative reasons"),
            ("aesthetics", "Aesthetic Judgment", "Artistic Value", "Interpretive Experience", "artistic value"),
            ("mind", "Philosophy of Mind", "Conscious Experience", "First-Person Access", "conscious experience"),
            ("politics", "Political Theory", "Civic Authority", "Collective Agency", "civic authority"),
            ("history", "History of Ideas", "Conceptual Change", "Historical Context", "conceptual change"),
            ("language", "Philosophy of Language", "Meaning and Use", "Semantic Practice", "meaning and use"),
            ("science", "Philosophy of Science", "Explanatory Models", "Scientific Practice", "explanatory models"),
            ("law", "Philosophy of Law", "Legal Reasons", "Institutional Norms", "legal reasons"),
        ]
        var documents = (0..<508).map { number in
            let profile = profiles[number % profiles.count]
            return fixture.item(
                "Background/\(profile.slug)/Note-\(number).md",
                "---\ntitle: \(profile.title) Note \(number)\naliases: [\(profile.alias) \(number)]\n---\n# \(profile.heading)\nA bounded synthetic note about \(profile.body) and evidence."
            )
        }
        documents.append(contentsOf: [
            fixture.item("Title.md", "---\ntitle: Deliberative Autonomy\n---\nA concise account."),
            fixture.item("Alias.md", "---\ntitle: Agency Structure\naliases: [Deliberative Autonomy]\n---\nA concise account."),
            fixture.item("Heading.md", "---\ntitle: Normative Architecture\n---\n# Deliberative Autonomy\nA concise account."),
            fixture.item("Body.md", "---\ntitle: Practical Reason\n---\nThis account develops deliberative autonomy in ordinary prose."),
        ])
        _ = try await index.rebuild(documents)

        let hits = try await index.search(SearchQuery("\"deliberative autonomy\""), limit: 10)
        #expect(hits.map(\.relativePath) == ["Title.md", "Alias.md", "Heading.md", "Body.md"])
        #expect(hits.map(\.matchedField) == [.title, .alias, .heading, .body])
        #expect(hits.map(\.context) == ["Title", "Alias", "Heading", "Body"])
        #expect(hits[1].snippet == "Deliberative Autonomy")
        #expect(hits[2].snippet == "Deliberative Autonomy")
        #expect(hits[2].sourceLine == 4)

        let aliasHits = try await index.search(SearchQuery("alias:\"Deliberative Autonomy\""))
        #expect(aliasHits.map(\.relativePath) == ["Alias.md"])
        let headingHits = try await index.search(SearchQuery("heading:\"Deliberative Autonomy\""))
        #expect(headingHits.map(\.relativePath) == ["Heading.md"])
    }

    @Test("A larger collision fixture preserves field precedence and deterministic paths")
    func largerExplainableRankingCollisionFixture() async throws {
        let fixture = try Fixture()
        let index = try SQLiteSearchIndex(databaseURL: fixture.databaseURL, vaultID: fixture.vault.id)
        let collisions = [
            fixture.item("00-title.md", "---\ntitle: Practical Identity\n---\nA short record."),
            fixture.item("01-title.md", "---\ntitle: Practical Identity\n---\nA short record."),
            fixture.item("10-alias.md", "---\ntitle: Concept Alpha\naliases: [Practical Identity]\n---\nA short record."),
            fixture.item("11-alias.md", "---\ntitle: Concept Beta\naliases: [Practical Identity]\n---\nA short record."),
            fixture.item("20-heading.md", "---\ntitle: Concept Heading\n---\n# Practical Identity\nA short record."),
            fixture.item("21-heading.md", "---\ntitle: Concept Heading\n---\n# Practical Identity\nA short record."),
            fixture.item("30-body.md", "---\ntitle: Body Alpha\n---\nThis body discusses practical identity."),
            fixture.item("31-body.md", "---\ntitle: Body Beta\n---\nThis body discusses practical identity."),
        ]
        let background = (0..<2_048).map { number in
            fixture.item(
                "Background/\(String(format: "%04d", number)).md",
                "---\ntitle: Background \(number)\n---\nA bounded note about practical identity in ordinary evidence."
            )
        }
        _ = try await index.rebuild(collisions + background)

        let hits = try await index.search(SearchQuery("\"practical identity\""), limit: 20)
        #expect(hits.count == 20)
        #expect(hits.prefix(6).map(\.matchedField) == [
            .title, .title, .alias, .alias, .heading, .heading,
        ])
        #expect(hits.prefix(6).map(\.relativePath) == [
            "00-title.md", "01-title.md", "10-alias.md", "11-alias.md",
            "20-heading.md", "21-heading.md",
        ])
        #expect(hits.dropFirst(6).allSatisfy { $0.matchedField == .body })

        let aliasHits = try await index.search(SearchQuery("alias:\"Practical Identity\""))
        #expect(aliasHits.map(\.relativePath) == ["10-alias.md", "11-alias.md"])
        let headingHits = try await index.search(SearchQuery("heading:\"Practical Identity\""))
        #expect(headingHits.map(\.relativePath) == ["20-heading.md", "21-heading.md"])
        let repeated = try await index.search(SearchQuery("\"practical identity\""), limit: 20)
        #expect(repeated.map(\.relativePath) == hits.map(\.relativePath))
    }

    @Test("Exact filename and path matches rank above body occurrences")
    func exactNoteIdentityPrecedesBodyMatches() async throws {
        let fixture = try Fixture()
        let index = try SQLiteSearchIndex(databaseURL: fixture.databaseURL, vaultID: fixture.vault.id)
        _ = try await index.rebuild([
            fixture.item(
                "Archive/Known Note.md",
                "---\ntitle: Archival Entry\n---\nNo matching prose here."
            ),
            fixture.item(
                "Body.md",
                "---\ntitle: Background\n---\nThis paragraph mentions Known Note and Archive/Known Note.md."
            ),
        ])

        let filenameHits = try await index.search(SearchQuery("\"Known Note\""))
        #expect(filenameHits.first?.relativePath == "Archive/Known Note.md")

        let pathHits = try await index.search(SearchQuery("\"Archive/Known Note.md\""))
        #expect(pathHits.first?.relativePath == "Archive/Known Note.md")
    }

    @Test("Incremental add, edit, rename, and delete converge with a clean rebuild")
    func incrementalParity() async throws {
        let fixture = try Fixture()
        let incremental = try SQLiteSearchIndex(databaseURL: fixture.databaseURL, vaultID: fixture.vault.id)
        let first = fixture.item("A.md", "---\ntitle: Alpha\n---\nfirst concept")
        let second = fixture.item("B.md", "---\ntitle: Beta\n---\nsecond concept")
        _ = try await incremental.rebuild([first, second])
        let edited = fixture.item("A.md", "---\ntitle: Alpha Revised\n---\nsecond concept revised")
        let renamed = fixture.item("C.md", second.document.rawContent)
        _ = try await incremental.apply([
            .upsert(edited),
            .delete(relativePath: "B.md"),
            .upsert(renamed)
        ])
        let incrementalHits = try await incremental.search(SearchQuery("second"))

        let cleanURL = fixture.root.appendingPathComponent("clean.sqlite")
        let clean = try SQLiteSearchIndex(databaseURL: cleanURL, vaultID: fixture.vault.id)
        _ = try await clean.rebuild([edited, renamed])
        let cleanHits = try await clean.search(SearchQuery("second"))

        #expect(incrementalHits.map(\.relativePath) == cleanHits.map(\.relativePath))
        #expect(try await incremental.generation().fingerprints == clean.generation().fingerprints)
    }

    @Test("Synchronization updates derived broken-link rows without source changes")
    func synchronizationTracksDerivedBrokenLinks() async throws {
        let fixture = try Fixture()
        let index = try SQLiteSearchIndex(databaseURL: fixture.databaseURL, vaultID: fixture.vault.id)
        let source = NoteDocument(relativePath: "A.md", rawContent: "---\ntitle: Alpha\n---\n[[Missing]]")
        let broken = SearchIndexDocument(
            vaultID: fixture.vault.id,
            vaultName: fixture.vault.name,
            vaultRole: fixture.vault.role,
            document: source,
            hasBrokenLink: true
        )
        let repaired = SearchIndexDocument(
            vaultID: fixture.vault.id,
            vaultName: fixture.vault.name,
            vaultRole: fixture.vault.role,
            document: source,
            hasBrokenLink: false
        )
        let reviewed = SearchIndexDocument(
            vaultID: fixture.vault.id,
            vaultName: fixture.vault.name,
            vaultRole: fixture.vault.role,
            document: source,
            review: "reviewed",
            hasBrokenLink: false
        )

        let first = try await index.synchronize(
            [broken],
            vaultName: fixture.vault.name,
            vaultRole: fixture.vault.role
        )
        #expect(first.disposition == .rebuilt)
        #expect(try await index.search(SearchQuery("Alpha has:broken-link")).map(\.relativePath) == ["A.md"])

        let second = try await index.synchronize(
            [repaired],
            vaultName: fixture.vault.name,
            vaultRole: fixture.vault.role
        )
        #expect(second.disposition == .incrementallyUpdated)
        #expect(second.generation.fingerprints == first.generation.fingerprints)
        #expect(try await index.search(SearchQuery("Alpha has:broken-link")).isEmpty)

        let third = try await index.synchronize(
            [reviewed],
            vaultName: fixture.vault.name,
            vaultRole: fixture.vault.role
        )
        #expect(third.disposition == .incrementallyUpdated)
        #expect(third.generation.fingerprints == first.generation.fingerprints)
        #expect(try await index.search(SearchQuery("Alpha review:reviewed")).map(\.relativePath) == ["A.md"])
    }

    @Test("An unchanged inventory can skip semantic reprojection")
    func unchangedInventoryMatchesPersistedDescriptor() async throws {
        let fixture = try Fixture()
        let index = try SQLiteSearchIndex(databaseURL: fixture.databaseURL, vaultID: fixture.vault.id)
        let item = fixture.item("A.md", "---\ntitle: Alpha\n---\nunchanged")
        _ = try await index.synchronize(
            [item],
            vaultName: fixture.vault.name,
            vaultRole: fixture.vault.role
        )

        let fingerprints = [item.relativePath: item.document.fingerprint]
        #expect(try await index.matches(
            fingerprints: fingerprints,
            vaultName: fixture.vault.name,
            vaultRole: fixture.vault.role
        ))
        #expect(try await !index.matches(
            fingerprints: fingerprints,
            vaultName: "Renamed Vault",
            vaultRole: fixture.vault.role
        ))
        #expect(try await !index.matches(
            fingerprints: [:],
            vaultName: fixture.vault.name,
            vaultRole: fixture.vault.role
        ))
    }

    @Test("A corrupt generated database is rebuilt instead of becoming an empty index")
    func corruptDatabaseRecoveryIsVisibleAndComplete() async throws {
        let fixture = try Fixture()
        try Data("not a sqlite database".utf8).write(to: fixture.databaseURL)

        let opened = try SQLiteSearchIndex.openRecovering(
            databaseURL: fixture.databaseURL,
            vaultID: fixture.vault.id
        )
        #expect(opened.recoveredCorruption)
        let result = try await opened.index.synchronize(
            [fixture.item("Recovered.md", "---\ntitle: Recovered\n---\nrecoverable concept")],
            vaultName: fixture.vault.name,
            vaultRole: fixture.vault.role,
            recoveredCorruption: opened.recoveredCorruption
        )

        #expect(result.disposition == .recoveredAndRebuilt)
        #expect(try await opened.index.search(SearchQuery("recoverable")).map(\.relativePath) == ["Recovered.md"])
    }

    @Test("An older generated search contract is replaced without touching source documents")
    func incompatibleContractRecoveryIsVisibleAndComplete() async throws {
        let fixture = try Fixture()
        var oldIndex: SQLiteSearchIndex? = try SQLiteSearchIndex(
            databaseURL: fixture.databaseURL,
            vaultID: fixture.vault.id
        )
        let source = fixture.item("Preserved.md", "---\ntitle: Preserved\n---\nexact source remains external")
        _ = try await oldIndex?.rebuild([source])
        oldIndex = nil
        try setContractVersion(1, in: fixture.databaseURL)

        let opened = try SQLiteSearchIndex.openRecovering(
            databaseURL: fixture.databaseURL,
            vaultID: fixture.vault.id
        )
        #expect(opened.recoveredCorruption)
        let result = try await opened.index.synchronize(
            [source],
            vaultName: fixture.vault.name,
            vaultRole: fixture.vault.role,
            recoveredCorruption: opened.recoveredCorruption
        )

        #expect(result.disposition == .recoveredAndRebuilt)
        #expect(result.generation.contractVersion == IndexGeneration.contractVersion)
        #expect(try await opened.index.search(SearchQuery("external")).map(\.relativePath) == ["Preserved.md"])
        #expect(source.document.rawContent == "---\ntitle: Preserved\n---\nexact source remains external")
    }

    @Test("Identical paths in different Triptychs remain isolated by vault identity")
    func vaultIdentityIsolation() async throws {
        let fixture = try Fixture()
        let otherID = UUID()
        let first = try SQLiteSearchIndex(databaseURL: fixture.databaseURL, vaultID: fixture.vault.id)
        let secondURL = fixture.root.appendingPathComponent("other.sqlite")
        let second = try SQLiteSearchIndex(databaseURL: secondURL, vaultID: otherID)
        _ = try await first.synchronize(
            [fixture.item("Shared.md", "first-domain-only")],
            vaultName: fixture.vault.name,
            vaultRole: fixture.vault.role
        )
        let otherDocument = SearchIndexDocument(
            vaultID: otherID,
            vaultName: "Other Analyses",
            vaultRole: .sourceCorpus,
            document: NoteDocument(relativePath: "Shared.md", rawContent: "second-domain-only")
        )
        _ = try await second.synchronize(
            [otherDocument],
            vaultName: "Other Analyses",
            vaultRole: .sourceCorpus
        )

        #expect(try await first.search(SearchQuery("first-domain-only")).count == 1)
        #expect(try await first.search(SearchQuery("second-domain-only")).isEmpty)
        #expect(try await second.search(SearchQuery("second-domain-only")).count == 1)
        #expect(try await second.search(SearchQuery("first-domain-only")).isEmpty)
    }

    @Test("Agent workspace search includes every vault in the selected Triptych")
    func completeTriptychSearch() async throws {
        let fixture = try Fixture()
        let sourceIndex = try SQLiteSearchIndex(databaseURL: fixture.databaseURL, vaultID: fixture.vault.id)
        _ = try await sourceIndex.rebuild([fixture.item("Paper.md", "Shared private phrase")])

        let controlID = UUID()
        let controlVault = RegisteredVault(name: "Control", role: .dissertationControl, canonicalPath: "/fixtures/control")
        let controlURL = fixture.root.appendingPathComponent("control.sqlite")
        let controlIndex = try SQLiteSearchIndex(databaseURL: controlURL, vaultID: controlID)
        let controlDocument = NoteDocument(relativePath: "Decision.md", rawContent: "Shared private phrase")
        _ = try await controlIndex.rebuild([SearchIndexDocument(
            vaultID: controlID,
            vaultName: controlVault.name,
            vaultRole: .dissertationControl,
            document: controlDocument
        )])

        let indexes = [(fixture.vault, sourceIndex), (controlVault, controlIndex)]
        let hits = try await FederatedSearchEngine.search(SearchQuery("private"), indexes: indexes)
        #expect(hits.contains { $0.vaultRole == .sourceCorpus })
        #expect(hits.contains { $0.vaultRole == .dissertationControl })
    }

    private struct Fixture {
        let root: URL
        let databaseURL: URL
        let vault: RegisteredVault

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            databaseURL = root.appendingPathComponent("search.sqlite")
            vault = RegisteredVault(name: "Sources", role: .sourceCorpus, canonicalPath: "/fixtures/sources")
        }

        func item(_ path: String, _ source: String) -> SearchIndexDocument {
            SearchIndexDocument(
                vaultID: vault.id,
                vaultName: vault.name,
                vaultRole: vault.role,
                document: NoteDocument(relativePath: path, rawContent: source)
            )
        }
    }

    private func setContractVersion(_ version: Int, in databaseURL: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            throw SearchIndexTestError.couldNotOpenDatabase
        }
        defer { sqlite3_close(database) }
        let sql = "UPDATE index_state SET value = \(version) WHERE key = 'contract_version';"
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SearchIndexTestError.couldNotSetContractVersion
        }
    }

    private enum SearchIndexTestError: Error {
        case couldNotOpenDatabase
        case couldNotSetContractVersion
    }
}
