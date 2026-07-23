import Foundation
import ScholiumContracts
import SQLite3
import Testing
@testable import ScholiumCore

@Suite("Triptych Search v4 index")
struct TriptychSearchIndexTests {
    @Test("One corpus ranks exact identity before lexical results and applies vault scope")
    func unifiedCorpusAndScope() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL,
            triptychID: fixture.triptychID,
            vaults: [fixture.analyses, fixture.topics, fixture.works]
        )
        var documents = (0..<180).map { number in
            fixture.item(
                vault: fixture.analyses,
                path: "Background/\(number).md",
                source: "---\ntitle: Background \(number)\n---\nA note about autonomy and reasons."
            )
        }
        documents += [
            fixture.item(
                vault: fixture.topics,
                path: "Autonomy.md",
                source: "---\naliases: [Self-government]\n---\n# Autonomy\n\nA compact concept."
            ),
            fixture.item(
                vault: fixture.works,
                path: "Chapter.md",
                source: "# Chapter\n\nThis chapter develops autonomy."
            ),
        ]
        let publication = try await index.synchronize(documents)
        #expect(publication.generation.sequence == 1)

        let triptych = try await index.search(fixture.request("autonomy", scope: .triptych))
        #expect(triptych.results.first?.relativePath == "Autonomy.md")
        #expect(triptych.results.first?.rankReason == .exactTitle)
        #expect(triptych.results.contains { $0.vaultRole == .sourceCorpus })
        #expect(triptych.results.contains { $0.vaultRole == .draftProject })

        let vault = try await index.search(fixture.request(
            "autonomy",
            scope: .currentVault(fixture.works.id)
        ))
        #expect(vault.results.map(\.relativePath) == ["Chapter.md"])
        #expect(vault.results.allSatisfy { $0.vaultID == fixture.works.id })
    }

    @Test("Exact groups retain BM25 order and filename fallback is not a source title")
    func exactGroupRankingAndFilenameFallback() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL,
            triptychID: fixture.triptychID
        )
        _ = try await index.synchronize([
            fixture.item(
                vault: fixture.works,
                path: "A-weak.md",
                source: "# Autonomy\n\nA brief note."
            ),
            fixture.item(
                vault: fixture.works,
                path: "Z-strong.md",
                source: "# Autonomy\n\nAutonomy autonomy autonomy autonomy."
            ),
            fixture.item(
                vault: fixture.topics,
                path: "Fallback.md",
                source: "Fallback appears without a frontmatter title."
            ),
        ])

        let exact = try await index.search(fixture.request(
            "autonomy",
            scope: .triptych
        ))
        #expect(Array(exact.results.map(\.relativePath).prefix(2)) == ["Z-strong.md", "A-weak.md"])
        #expect(exact.results.prefix(2).allSatisfy { $0.rankReason == .exactTitle })

        let fielded = try await index.search(fixture.request(
            "title:Autonomy",
            scope: .triptych
        ))
        #expect(fielded.results.first?.rankReason == .exactTitle)

        let fallback = try await index.search(fixture.request("Fallback", scope: .triptych))
        #expect(fallback.results.first?.relativePath == "Fallback.md")
        #expect(fallback.results.first?.rankReason == .exactFilename)
    }

    @Test("Vault metadata changes republish unchanged source rows")
    func vaultMetadataRefreshesStoredResults() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL,
            triptychID: fixture.triptychID
        )
        let source = "---\ntitle: Stable Source\n---\nmetadata-refresh-term"
        let first = try await index.synchronize([
            fixture.item(vault: fixture.analyses, path: "Stable.md", source: source),
        ])
        let replacementVault = RegisteredVault(
            id: fixture.analyses.id,
            name: "Renamed Topics",
            role: .topicKnowledge,
            canonicalPath: fixture.analyses.canonicalPath
        )
        let second = try await index.synchronize([
            fixture.item(vault: replacementVault, path: "Stable.md", source: source),
        ])
        #expect(second.disposition == .incrementallyUpdated)
        #expect(second.generation.sequence == first.generation.sequence + 1)

        let response = try await index.search(fixture.request(
            "metadata-refresh-term",
            scope: .triptych
        ))
        #expect(response.results.first?.vaultName == "Renamed Topics")
        #expect(response.results.first?.vaultRole == .topicKnowledge)
        #expect(response.results.first?.evidentialLayer == .topicNote)
    }

    @Test("A stale workspace generation cannot replace the last complete index")
    func staleWorkspaceGenerationIsRejected() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL,
            triptychID: fixture.triptychID
        )
        let peerOpenedBeforePublication = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL,
            triptychID: fixture.triptychID
        )
        let current = fixture.item(
            vault: fixture.topics,
            path: "Current.md",
            source: "# Current\n\ncurrent-generation-term"
        )
        let stale = fixture.item(
            vault: fixture.topics,
            path: "Stale.md",
            source: "# Stale\n\nstale-generation-term"
        )
        let published = try await index.synchronize(
            [current],
            workspaceGeneration: 5
        )

        await #expect(throws: SearchIndexError.self) {
            _ = try await peerOpenedBeforePublication.synchronize(
                [stale],
                workspaceGeneration: 5
            )
        }

        await #expect(throws: SearchIndexError.self) {
            _ = try await index.synchronize(
                [stale],
                workspaceGeneration: 4
            )
        }
        #expect(try await index.generation() == published.generation)
        #expect(try await index.search(
            fixture.request("current-generation-term", scope: .triptych)
        ).results.map(\.relativePath) == ["Current.md"])
        #expect(try await index.search(
            fixture.request("stale-generation-term", scope: .triptych)
        ).results.isEmpty)

        let unchanged = try await index.synchronize(
            [current],
            workspaceGeneration: 6
        )
        #expect(unchanged.disposition == .unchanged)
        #expect(unchanged.generation == published.generation)

        let reopened = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL,
            triptychID: fixture.triptychID
        )
        await #expect(throws: SearchIndexError.self) {
            _ = try await reopened.synchronize(
                [stale],
                workspaceGeneration: 5
            )
        }
        #expect(try await reopened.generation() == published.generation)
    }

    @Test("Exact identity is never lost behind ten thousand filtered collisions")
    func exactIdentityHasNoCandidateCutoff() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL,
            triptychID: fixture.triptychID
        )
        var documents = (0..<10_000).map { number in
            fixture.item(
                vault: fixture.analyses,
                path: String(format: "Collisions/%05d.md", number),
                source: "---\ntitle: Autonomy\n---\n> [!orientation] Collision\n> Collision \(number)."
            )
        }
        documents.append(fixture.item(
            vault: fixture.works,
            path: "zzzz-target.md",
            source: "# Autonomy\n\n> [!state] Intended\n> The intended exact result."
        ))
        _ = try await index.synchronize(documents)

        let response = try await index.search(SearchRequest(
            query: "autonomy callout:state",
            presentationScope: .triptych,
            executionScope: .triptych,
            limit: 1
        ))
        #expect(response.results.map(\.relativePath) == ["zzzz-target.md"])
        #expect(response.results.first?.rankReason == .exactTitle)
    }

    @Test("Long CJK and mixed-script candidates are reverified as contiguous text")
    func cjkVerification() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL,
            triptychID: fixture.triptychID
        )
        _ = try await index.synchronize([
            fixture.item(vault: fixture.analyses, path: "Exact.md", source: "A认识论B 哲学"),
            fixture.item(vault: fixture.analyses, path: "False.md", source: "认识 gap 识论"),
        ])

        let long = try await index.search(fixture.request("认识论", scope: .triptych))
        #expect(long.results.map(\.relativePath) == ["Exact.md"])
        let single = try await index.search(fixture.request("哲", scope: .triptych))
        #expect(single.results.map(\.relativePath) == ["Exact.md"])
        let mixed = try await index.search(fixture.request("A认识论B", scope: .triptych))
        #expect(mixed.results.map(\.relativePath) == ["Exact.md"])
    }

    @Test("This Note searches an unsaved snapshot by occurrence without publishing it")
    func currentNoteOccurrences() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL,
            triptychID: fixture.triptychID,
            vaults: [fixture.analyses, fixture.topics, fixture.works]
        )
        let disk = fixture.item(
            vault: fixture.topics,
            path: "Set Aside/Current.md",
            source: "# Current\n\nDisk text."
        )
        _ = try await index.synchronize([])
        let editorSource = """
        # Current
        > [!state] In progress

        autonomy appears here.
        A second autonomy appears here.
        """
        let snapshot = SearchSourceSnapshot(
            noteID: VaultQualifiedNoteID(
                vaultID: fixture.topics.id,
                relativePath: disk.relativePath
            ),
            editorSessionID: UUID(),
            source: editorSource,
            editorRevision: 7
        )
        let request = SearchRequest(
            query: "autonomy callout:state",
            presentationScope: .thisNote,
            executionScope: .currentNote(snapshot),
            limit: 100
        )
        let response = try await index.search(request)
        #expect(response.results.count == 2)
        #expect(response.results.allSatisfy { $0.vaultRole == .topicKnowledge })
        #expect(response.results.allSatisfy { $0.sourceRange != nil })
        #expect(response.results.map(\.sourceLine) == [4, 5])
        #expect(response.freshnessToken.rawValue.contains(snapshot.editorSessionID.uuidString.lowercased()))

        let indexed = try await index.search(fixture.request("autonomy", scope: .triptych))
        #expect(indexed.results.isEmpty)
        let filterOnly = try await index.search(SearchRequest(
            query: "callout:state",
            presentationScope: .thisNote,
            executionScope: .currentNote(snapshot),
            limit: 100
        ))
        #expect(filterOnly.results.count == 1)
    }

    @Test("This Note enforces phrase and mixed-script boundaries and marks each occurrence")
    func currentNoteBoundariesAndOccurrenceHighlights() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL,
            triptychID: fixture.triptychID,
            vaults: [fixture.analyses]
        )
        _ = try await index.synchronize([])
        let source = "autonomy " + String(repeating: "context ", count: 45)
            + "autonomy article XA认识论BY A认识论B"
        let snapshot = SearchSourceSnapshot(
            noteID: VaultQualifiedNoteID(vaultID: fixture.analyses.id, relativePath: "Current.md"),
            editorSessionID: UUID(),
            source: source,
            editorRevision: 1
        )
        func request(_ query: String) -> SearchRequest {
            SearchRequest(
                query: query,
                presentationScope: .thisNote,
                executionScope: .currentNote(snapshot),
                limit: 100
            )
        }

        let occurrences = try await index.search(request("autonomy"))
        #expect(occurrences.results.count == 2)
        #expect(occurrences.results.map(\.snippet).allSatisfy { $0.count <= 240 })
        #expect(occurrences.results.map(\.highlights).allSatisfy { $0.count == 1 })
        #expect(occurrences.results[0].sourceRange != occurrences.results[1].sourceRange)

        #expect(try await index.search(request("\"art\"")).results.isEmpty)
        let mixed = try await index.search(request("A认识论B"))
        #expect(mixed.results.count == 1)
        let selected = try #require(mixed.results.first?.sourceRange)
        #expect((source as NSString).substring(with: NSRange(
            location: selected.utf16LowerBound,
            length: selected.utf16UpperBound - selected.utf16LowerBound
        )) == "A认识论B")
    }

    @Test("Query diagnostics are response data and never impersonate index failure")
    func queryDiagnostics() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL,
            triptychID: fixture.triptychID
        )
        _ = try await index.synchronize([
            fixture.item(vault: fixture.analyses, path: "A.md", source: "autonomy"),
        ])
        let response = try await index.search(fixture.request("role:analyses", scope: .triptych))
        #expect(response.results.isEmpty)
        #expect(response.diagnostics.first?.code == .removedField)
        guard case .current = response.availability else {
            Issue.record("A query error must not change a current index into a failed index")
            return
        }
    }

    @Test("Cancellation preserves the complete last-good generation")
    func cancellationRollsBack() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL,
            triptychID: fixture.triptychID
        )
        let original = fixture.item(
            vault: fixture.analyses,
            path: "Original.md",
            source: "original-search-term"
        )
        let first = try await index.synchronize([original])
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await index.synchronize([
                fixture.item(
                    vault: fixture.works,
                    path: "Replacement.md",
                    source: "replacement-search-term"
                ),
            ])
        }
        await #expect(throws: CancellationError.self) {
            _ = try await cancelled.value
        }
        #expect(try await index.generation() == first.generation)
        #expect(try await index.search(fixture.request(
            "original-search-term",
            scope: .triptych
        )).results.map(\.relativePath) == ["Original.md"])
        #expect(try await index.search(fixture.request(
            "replacement-search-term",
            scope: .triptych
        )).results.isEmpty)
    }

    @Test("A cancelled first build reports progress and publishes no generation")
    func cancelledInitialBuildRemainsUnavailable() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL,
            triptychID: fixture.triptychID
        )
        let documents = (0..<5_000).map { number in
            fixture.item(
                vault: fixture.analyses,
                path: "Initial/\(number).md",
                source: "---\ntitle: Initial \(number)\n---\nfirst-build-term"
            )
        }
        let build = Task { try await index.synchronize(documents) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        var observedProgress = false
        while ContinuousClock.now < deadline {
            if case .building(let progress) = await index.availability(),
               progress.completed > 0,
               progress.total == documents.count {
                observedProgress = true
                break
            }
            await Task.yield()
        }
        #expect(observedProgress)
        build.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await build.value
        }
        #expect(try await index.generation() == nil)
        #expect(await index.availability() == .unavailable)
        let response = try await index.search(fixture.request(
            "first-build-term",
            scope: .triptych,
            limit: 1
        ))
        #expect(response.results.isEmpty)
        #expect(response.availability == .unavailable)
    }

    @Test("A refreshing writer serves one fixed last-good read generation and cancellation rolls back")
    func concurrentReadGenerationAndMidRefreshCancellation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL,
            triptychID: fixture.triptychID
        )
        let original = (0..<3_000).map { number in
            fixture.item(
                vault: fixture.analyses,
                path: "Concurrent/\(number).md",
                source: "---\ntitle: Original \(number)\n---\nlast-good-term"
            )
        }
        let first = try await index.synchronize(original)
        let replacement = (0..<3_000).map { number in
            fixture.item(
                vault: fixture.works,
                path: "Concurrent/\(number).md",
                source: "---\ntitle: Replacement \(number)\n---\npublished-term"
            )
        }

        let refresh = Task { try await index.synchronize(replacement) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        var observedRefreshing = false
        while ContinuousClock.now < deadline {
            if case .refreshing(let lastGood) = await index.availability() {
                #expect(lastGood == first.generation)
                observedRefreshing = true
                break
            }
            await Task.yield()
        }
        #expect(observedRefreshing)

        let duringRefresh = try await index.search(fixture.request(
            "last-good-term",
            scope: .triptych,
            limit: 1
        ))
        #expect(duringRefresh.results.count == 1)
        #expect(duringRefresh.freshnessToken == .triptych(first.generation))
        guard case .refreshing(let readGeneration) = duringRefresh.availability else {
            Issue.record("The old WAL read should remain explicitly refreshing")
            refresh.cancel()
            _ = try? await refresh.value
            return
        }
        #expect(readGeneration == first.generation)

        refresh.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await refresh.value
        }
        #expect(try await index.generation() == first.generation)
        #expect(try await index.search(fixture.request(
            "published-term",
            scope: .triptych,
            limit: 1
        )).results.isEmpty)

        let published = try await index.synchronize(replacement)
        #expect(published.generation.sequence == first.generation.sequence + 1)
        let final = try await index.search(fixture.request(
            "published-term",
            scope: .triptych,
            limit: 1
        ))
        #expect(final.results.count == 1)
        #expect(final.freshnessToken == .triptych(published.generation))
    }

    @Test("Presentation scope cannot disguise another execution scope")
    func mismatchedScopeFailsClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL,
            triptychID: fixture.triptychID
        )
        _ = try await index.synchronize([
            fixture.item(vault: fixture.analyses, path: "A.md", source: "autonomy"),
        ])
        let response = try await index.search(SearchRequest(
            query: "autonomy",
            presentationScope: .currentVault,
            executionScope: .triptych,
            limit: 20
        ))
        #expect(response.results.isEmpty)
        #expect(response.diagnostics.first?.code == .invalidScope)
    }

    @Test("Corrupt generated state is staged and replaced without touching v1 or source")
    func corruptRecovery() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("not sqlite".utf8).write(to: fixture.databaseURL)
        let legacyURL = fixture.root.appendingPathComponent("search-v1.sqlite")
        let legacyBytes = Data("legacy generated state".utf8)
        try legacyBytes.write(to: legacyURL)
        let source = "---\ntitle: Preserved\n---\nrecoverable text"
        let opened = try TriptychSearchIndex.openRecovering(
            databaseURL: fixture.databaseURL,
            triptychID: fixture.triptychID
        )
        #expect(opened.recoveredCorruption)
        let result = try await opened.index.synchronize([
            fixture.item(vault: fixture.analyses, path: "Preserved.md", source: source),
        ])
        #expect(result.disposition == .recoveredAndRebuilt)
        #expect(try Data(contentsOf: legacyURL) == legacyBytes)
        #expect(try await opened.index.search(fixture.request(
            "recoverable",
            scope: .triptych
        )).results.map(\.relativePath) == ["Preserved.md"])
        #expect(source == "---\ntitle: Preserved\n---\nrecoverable text")
    }

    @Test("Index schema stores derived projection but no raw Markdown source")
    func noRawSourceColumn() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL,
            triptychID: fixture.triptychID
        )
        _ = try await index.synchronize([
            fixture.item(
                vault: fixture.analyses,
                path: "A.md",
                source: "---\nsecret_yaml_key: do-not-copy\ntitle: Visible\n---\n[Shown](https://secret.example/path)"
            ),
        ])
        var database: OpaquePointer?
        #expect(sqlite3_open_v2(fixture.databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(
            database,
            "SELECT sql FROM sqlite_master WHERE name IN ('search_documents', 'search_fts') ORDER BY name;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        var schema = ""
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) { schema += String(cString: text) }
        }
        #expect(!schema.lowercased().contains("raw_source"))
        #expect(!schema.lowercased().contains(" source "))

        let destination = try await index.search(fixture.request("secret.example", scope: .triptych))
        #expect(destination.results.isEmpty)
        let hiddenYAML = try await index.search(fixture.request("secret_yaml_key", scope: .triptych))
        #expect(hiddenYAML.results.isEmpty)
        let visible = try await index.search(fixture.request("shown", scope: .triptych))
        #expect(visible.results.map(\.relativePath) == ["A.md"])
    }

    private final class Fixture: @unchecked Sendable {
        let root: URL
        let databaseURL: URL
        let triptychID = UUID()
        let analyses = RegisteredVault(
            name: "Analyses",
            role: .sourceCorpus,
            canonicalPath: "/fixtures/analyses"
        )
        let topics = RegisteredVault(
            name: "Topics",
            role: .topicKnowledge,
            canonicalPath: "/fixtures/topics"
        )
        let works = RegisteredVault(
            name: "Works",
            role: .draftProject,
            canonicalPath: "/fixtures/works"
        )

        init() throws {
            root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent(".build", isDirectory: true)
                .appendingPathComponent("search-v4-test-artifacts", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            databaseURL = root.appendingPathComponent("search-v4.sqlite")
        }

        func item(
            vault: RegisteredVault,
            path: String,
            source: String,
            review: String? = nil,
            broken: Bool = false
        ) -> SearchIndexDocument {
            SearchIndexDocument(
                vaultID: vault.id,
                vaultName: vault.name,
                vaultRole: vault.role,
                document: NoteDocument(relativePath: path, rawContent: source),
                review: review,
                hasBrokenLink: broken
            )
        }

        enum Scope {
            case currentVault(UUID)
            case triptych
        }

        func request(_ query: String, scope: Scope, limit: Int = 100) -> SearchRequest {
            switch scope {
            case .currentVault(let vaultID):
                SearchRequest(
                    query: query,
                    presentationScope: .currentVault,
                    executionScope: .currentVault(vaultID),
                    limit: limit
                )
            case .triptych:
                SearchRequest(
                    query: query,
                    presentationScope: .triptych,
                    executionScope: .triptych,
                    limit: limit
                )
            }
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
