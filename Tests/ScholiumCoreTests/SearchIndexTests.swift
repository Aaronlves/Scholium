import Foundation
import Testing
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
}
