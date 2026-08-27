import Foundation
import ScholiumContracts
import SQLite3
import Testing
@testable import ScholiumCore

@Suite("Triptych Search v9 index")
struct TriptychSearchIndexTests {
    @Test("Related content uses an ephemeral Work seed and returns only explained Analyses and Topics")
    func relatedContentRestrictsCorpusAndTracksSeedSource() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let other = RegisteredVault(
            name: "Other",
            role: .other,
            canonicalPath: "/fixtures/other"
        )
        let index = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL,
            triptychID: fixture.triptychID,
            vaults: [fixture.analyses, fixture.topics, fixture.works, other]
        )
        let documents = [
            fixture.item(
                vault: fixture.analyses,
                path: "Fittingness.md",
                source: "# Fittingness Analysis\n\nFittingness gives reasons about value."
            ),
            fixture.item(
                vault: fixture.topics,
                path: "Reasons.md",
                source: "# Normative Reasons\n\nReasons and fittingness are distinct."
            ),
            fixture.item(
                vault: fixture.analyses,
                path: "Consequentialism.md",
                source: "# Consequentialism\n\nConsequentialism evaluates outcomes."
            ),
            fixture.item(
                vault: fixture.works,
                path: "Another Work.md",
                source: "# Another Work\n\nFittingness and reasons."
            ),
            fixture.item(
                vault: other,
                path: "Other.md",
                source: "# Other\n\nFittingness and reasons."
            ),
        ]
        _ = try await index.synchronize(documents)

        let workID = VaultQualifiedNoteID(
            vaultID: fixture.works.id,
            relativePath: "Live Draft.md"
        )
        let first = try await index.relatedContent(RelatedContentRequest(
            seed: RelatedContentSeedSnapshot(
                noteID: workID,
                source: "# Draft on fittingness\n\nFittingness and normative reasons shape value."
            )
        ))
        #expect(first.state == .current)
        #expect(Set(first.candidates.map(\.note.relativePath)) == [
            "Fittingness.md", "Reasons.md",
        ])
        #expect(first.candidates.allSatisfy {
            $0.vaultRole == .sourceCorpus || $0.vaultRole == .topicKnowledge
        })
        #expect(first.candidates.allSatisfy {
            !$0.lexicalReason.matchedFields.isEmpty
                && !$0.lexicalReason.matchedSeedTerms.isEmpty
        })

        let revised = try await index.relatedContent(RelatedContentRequest(
            seed: RelatedContentSeedSnapshot(
                noteID: workID,
                source: "# Consequentialism\n\nConsequentialism and outcomes."
            )
        ))
        #expect(revised.state == .current)
        #expect(revised.candidates.map(\.note.relativePath) == [
            "Consequentialism.md",
        ])
        #expect(revised.seedFingerprint != first.seedFingerprint)

        var updatedDocuments = documents
        updatedDocuments[0] = fixture.item(
            vault: fixture.analyses,
            path: "Fittingness.md",
            source: "# Revised Analysis\n\nA different subject."
        )
        _ = try await index.synchronize(updatedDocuments)
        let incremental = try await index.relatedContent(RelatedContentRequest(
            seed: RelatedContentSeedSnapshot(
                noteID: workID,
                source: "# Draft on fittingness\n\nFittingness and normative reasons shape value."
            )
        ))
        let cleanIndex = try TriptychSearchIndex(
            databaseURL: fixture.root.appendingPathComponent("clean-related.sqlite"),
            triptychID: fixture.triptychID,
            vaults: [fixture.analyses, fixture.topics, fixture.works, other]
        )
        _ = try await cleanIndex.synchronize(updatedDocuments)
        let clean = try await cleanIndex.relatedContent(RelatedContentRequest(
            seed: RelatedContentSeedSnapshot(
                noteID: workID,
                source: "# Draft on fittingness\n\nFittingness and normative reasons shape value."
            )
        ))
        #expect(incremental.candidates == clean.candidates)

        let invalid = try await index.relatedContent(RelatedContentRequest(
            seed: RelatedContentSeedSnapshot(noteID: workID, source: " \n")
        ))
        #expect(invalid.state == .invalidSeed)
        #expect(invalid.candidates.isEmpty)
    }

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

        let triptych = try await index.testSearch(fixture.request("autonomy", scope: .triptych))
        #expect(triptych.explanation.scope == .triptych)
        #expect(triptych.explanation.ordering == .noteExactIdentityThenBM25ThenTitleRolePath)
        #expect(triptych.noteResults.first?.relativePath == "Autonomy.md")
        #expect(triptych.noteResults.first?.rankReason == .exactTitle)
        #expect(triptych.noteResults.contains { $0.vaultRole == .sourceCorpus })
        #expect(triptych.noteResults.contains { $0.vaultRole == .draftProject })

        let vault = try await index.testSearch(fixture.request(
            "autonomy",
            scope: .currentVault(fixture.works.id)
        ))
        #expect(vault.explanation.scope == .currentVault)
        #expect(vault.noteResults.map(\.relativePath) == ["Chapter.md"])
        #expect(vault.noteResults.allSatisfy { $0.vaultID == fixture.works.id })
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

        let exact = try await index.testSearch(fixture.request(
            "autonomy",
            scope: .triptych
        ))
        #expect(Array(exact.noteResults.map(\.relativePath).prefix(2)) == ["Z-strong.md", "A-weak.md"])
        #expect(exact.noteResults.prefix(2).allSatisfy { $0.rankReason == .exactTitle })

        let fielded = try await index.testSearch(fixture.request(
            "title:Autonomy",
            scope: .triptych
        ))
        #expect(fielded.noteResults.first?.rankReason == .exactTitle)

        let fallback = try await index.testSearch(fixture.request("Fallback", scope: .triptych))
        #expect(fallback.noteResults.first?.relativePath == "Fallback.md")
        #expect(fallback.noteResults.first?.rankReason == .exactFilename)
    }

    @Test("Canonical summary is an independent lexical field with exact source recovery")
    func canonicalSummarySearch() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL,
            triptychID: fixture.triptychID
        )
        let source = """
        ---
        summary: "Maps the inheritance tension without settling it"
        custom: keep exactly
        ---
        # Neutral title

        Open this current Note before treating its summary as evidence.
        """
        _ = try await index.synchronize([
            fixture.item(vault: fixture.topics, path: "Summary.md", source: source),
            fixture.item(
                vault: fixture.analyses,
                path: "Body.md",
                source: "# Body\n\nThe ordinary body mentions inheritance."
            ),
        ])

        let fielded = try await index.testSearch(fixture.request(
            "summary:inheritance",
            scope: .triptych
        ))
        let result = try #require(fielded.noteResults.first)
        #expect(fielded.noteResults.map(\.relativePath) == ["Summary.md"])
        #expect(result.matchedField == .summary)
        #expect(result.matchedFields == [.summary])
        let range = try #require(result.sourceRange)
        #expect((source as NSString).substring(with: NSRange(
            location: range.utf16LowerBound,
            length: range.utf16UpperBound - range.utf16LowerBound
        )) == "inheritance")

        let unfielded = try await index.testSearch(fixture.request(
            "inheritance",
            scope: .triptych
        ))
        #expect(Set(unfielded.noteResults.map(\.relativePath)) == ["Summary.md", "Body.md"])
        #expect(unfielded.noteResults.first { $0.relativePath == "Summary.md" }?.matchedField == .summary)
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

        let response = try await index.testSearch(fixture.request(
            "metadata-refresh-term",
            scope: .triptych
        ))
        #expect(response.noteResults.first?.vaultName == "Renamed Topics")
        #expect(response.noteResults.first?.vaultRole == .topicKnowledge)
        #expect(response.noteResults.first?.evidentialLayer == .topicNote)
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
        #expect(try await index.testSearch(
            fixture.request("current-generation-term", scope: .triptych)
        ).noteResults.map(\.relativePath) == ["Current.md"])
        #expect(try await index.testSearch(
            fixture.request("stale-generation-term", scope: .triptych)
        ).noteResults.isEmpty)

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

        let response = try await index.testSearch(SearchRequest(
            query: "autonomy callout:state",
            presentationScope: .triptych,
            executionScope: .triptych,
            limit: 1
        ))
        #expect(response.noteResults.map(\.relativePath) == ["zzzz-target.md"])
        #expect(response.noteResults.first?.rankReason == .exactTitle)
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

        let long = try await index.testSearch(fixture.request("认识论", scope: .triptych))
        #expect(long.noteResults.map(\.relativePath) == ["Exact.md"])
        let single = try await index.testSearch(fixture.request("哲", scope: .triptych))
        #expect(single.noteResults.map(\.relativePath) == ["Exact.md"])
        let mixed = try await index.testSearch(fixture.request("A认识论B", scope: .triptych))
        #expect(mixed.noteResults.map(\.relativePath) == ["Exact.md"])
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
            path: "Archive/Current.md",
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
        let response = try await index.testSearch(request)
        #expect(response.noteResults.count == 2)
        #expect(response.noteResults.allSatisfy { $0.vaultRole == .topicKnowledge })
        #expect(response.noteResults.allSatisfy { $0.sourceRange != nil })
        #expect(response.noteResults.map(\.sourceLine) == [4, 5])
        #expect(response.freshnessToken.rawValue.contains(snapshot.editorSessionID.uuidString.lowercased()))

        let indexed = try await index.testSearch(fixture.request("autonomy", scope: .triptych))
        #expect(indexed.noteResults.isEmpty)
        let filterOnly = try await index.testSearch(SearchRequest(
            query: "callout:state",
            presentationScope: .thisNote,
            executionScope: .currentNote(snapshot),
            limit: 100
        ))
        #expect(filterOnly.noteResults.count == 1)
    }

    @Test("This Note reports only portable stable identity and ignores forged YAML identity")
    func currentNotePortableIdentity() async throws {
        let fixture = try Fixture(); defer { fixture.remove() }
        let index = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL,
            triptychID: fixture.triptychID,
            vaults: [fixture.topics]
        )
        _ = try await index.synchronize([])
        let stableID = UUID()
        let snapshot = SearchSourceSnapshot(
            noteID: VaultQualifiedNoteID(
                vaultID: fixture.topics.id,
                relativePath: "Current.md"
            ),
            stableNoteID: stableID,
            editorSessionID: UUID(),
            source: "---\nnote_id: forged\n---\nportable identity result",
            editorRevision: 1
        )
        let response = try await index.testSearch(SearchRequest(
            query: "portable",
            presentationScope: .thisNote,
            executionScope: .currentNote(snapshot),
            limit: 20
        ))
        #expect(response.noteResults.map(\.stableNoteID) == [stableID.uuidString.lowercased()])
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

        let occurrences = try await index.testSearch(request("autonomy"))
        #expect(occurrences.noteResults.count == 2)
        #expect(occurrences.noteResults.map(\.snippet).allSatisfy { $0.count <= 240 })
        #expect(occurrences.noteResults.map(\.highlights).allSatisfy { $0.count == 1 })
        #expect(occurrences.noteResults[0].sourceRange != occurrences.noteResults[1].sourceRange)

        #expect(try await index.testSearch(request("\"art\"")).noteResults.isEmpty)
        let mixed = try await index.testSearch(request("A认识论B"))
        #expect(mixed.noteResults.count == 1)
        let selected = try #require(mixed.noteResults.first?.sourceRange)
        #expect((source as NSString).substring(with: NSRange(
            location: selected.utf16LowerBound,
            length: selected.utf16UpperBound - selected.utf16LowerBound
        )) == "A认识论B")
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
        #expect(try await index.testSearch(fixture.request(
            "original-search-term",
            scope: .triptych
        )).noteResults.map(\.relativePath) == ["Original.md"])
        #expect(try await index.testSearch(fixture.request(
            "replacement-search-term",
            scope: .triptych
        )).noteResults.isEmpty)
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
        let response = try await index.testSearch(fixture.request(
            "first-build-term",
            scope: .triptych,
            limit: 1
        ))
        #expect(response.noteResults.isEmpty)
        #expect(response.availability == .note(.unavailable))
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

        let duringRefresh = try await index.testSearch(fixture.request(
            "last-good-term",
            scope: .triptych,
            limit: 1
        ))
        #expect(duringRefresh.noteResults.count == 1)
        #expect(duringRefresh.freshnessToken == .triptych(first.generation))
        guard case .note(.refreshing(let readGeneration)) = duringRefresh.availability else {
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
        #expect(try await index.testSearch(fixture.request(
            "published-term",
            scope: .triptych,
            limit: 1
        )).noteResults.isEmpty)

        let published = try await index.synchronize(replacement)
        #expect(published.generation.sequence == first.generation.sequence + 1)
        let final = try await index.testSearch(fixture.request(
            "published-term",
            scope: .triptych,
            limit: 1
        ))
        #expect(final.noteResults.count == 1)
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
        let response = try await index.testSearch(SearchRequest(
            query: "autonomy",
            presentationScope: .currentVault,
            executionScope: .triptych,
            limit: 20
        ))
        #expect(response.noteResults.isEmpty)
        #expect(response.diagnostics.first?.code == .notApplicable)
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
        #expect(try await opened.index.testSearch(fixture.request(
            "recoverable",
            scope: .triptych
        )).noteResults.map(\.relativePath) == ["Preserved.md"])
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
            "SELECT sql FROM sqlite_master WHERE name IN ('search_documents', 'search_fts', 'search_segments') ORDER BY name;",
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
        #expect(schema.lowercased().contains("offset_map blob not null"))
        #expect(schema.lowercased().contains("source_utf16_count integer not null"))

        let destination = try await index.testSearch(fixture.request("secret.example", scope: .triptych))
        #expect(destination.noteResults.isEmpty)
        let hiddenYAML = try await index.testSearch(fixture.request("secret_yaml_key", scope: .triptych))
        #expect(hiddenYAML.noteResults.isEmpty)
        let visible = try await index.testSearch(fixture.request("shown", scope: .triptych))
        #expect(visible.noteResults.map(\.relativePath) == ["A.md"])
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
                .appendingPathComponent("search-v9-test-artifacts", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            databaseURL = root.appendingPathComponent("search-v9.sqlite")
        }

        func item(
            vault: RegisteredVault,
            path: String,
            source: String,
            broken: Bool = false
        ) -> SearchIndexDocument {
            SearchIndexDocument(
                vaultID: vault.id,
                vaultName: vault.name,
                vaultRole: vault.role,
                document: NoteDocument(relativePath: path, rawContent: source),
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
