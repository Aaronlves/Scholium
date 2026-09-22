import Foundation
import SQLite3
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Two-layer related-content preparation")
struct RelatedContentBackgroundPreparationTests {
    @Test("Cold, background-prepared, reopened and rebuilt requests preserve exact candidates and passages")
    func coldAndPreparedEquivalence() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let cold = try fixture.index(name: "cold.sqlite")
        let prepared = try fixture.index()
        let rebuilt = try fixture.index(name: "rebuilt.sqlite")
        for index in [cold, prepared, rebuilt] { _ = try await index.synchronize(fixture.documents) }
        let background = fixture.request()
        let focus = fixture.request(focus: "magnetic compass calibration")
        let backgroundResponse = try await prepared.relatedMaterialSourceCandidates(background)
        #expect(Set(backgroundResponse.lexicalCandidates.map(\.note.relativePath)) == ["Context.md", "Shared.md"])
        try await prepared.prepareRelatedPassages(background, sources: fixture.sources(backgroundResponse))
        let warmedMemo = await prepared.relatedPassagePreparationStatistics
        #expect(warmedMemo.misses == 2)

        let expected = try await cold.relatedMaterialSourceCandidates(focus)
        let actual = try await prepared.relatedMaterialSourceCandidates(focus)
        assertCandidates(actual, equalTo: expected)
        #expect(Set(actual.lexicalCandidates.map(\.note.relativePath)) == ["Shared.md", "Fresh.md"])
        #expect(actual.lexicalCandidates.count == Set(actual.lexicalCandidates.map(\.note)).count)
        #expect(actual.lexicalCandidates.count > focus.lexicalLimit)
        #expect(actual.lexicalHasMore)
        #expect((actual.identityCandidates + actual.lexicalCandidates).allSatisfy { $0.note != focus.seed.noteID })
        let shared = try #require(actual.lexicalCandidates.first { $0.note.relativePath == "Shared.md" })
        guard case .lexicalOverlap(let reason) = shared.reason else {
            Issue.record("Prepared material must receive a current lexical reason")
            return
        }
        #expect(reason.seedMatches.map(\.seedKind) == [.selectedPassage, .sourceNote])
        let fresh = try #require(actual.lexicalCandidates.first { $0.note.relativePath == "Fresh.md" })
        guard case .lexicalOverlap(let focusedReason) = fresh.reason else {
            Issue.record("New focus-only material must carry a focus reason")
            return
        }
        #expect(focusedReason.seedMatches.contains { $0.seedKind == .selectedPassage })
        let stats = await prepared.relatedBackgroundPreparationStatistics
        #expect(stats.hits == 1)

        let sources = fixture.sources(actual)
        let expectedPassages = try await cold.relatedPassages(focus, sources: fixture.sources(expected))
        let passages = try await prepared.relatedPassages(focus, sources: sources)
        #expect(passages == expectedPassages)
        #expect(Set(passages.map(\.candidate.note.relativePath)) == ["Shared.md", "Fresh.md"])
        #expect(try TriptychSearchIndex.relatedPassages(focus, sources: sources) == passages)
        #expect(try TriptychSearchIndex.relatedPassages(focus, sources: sources.reversed()) == passages)
        let after = await prepared.relatedPassagePreparationStatistics
        #expect(after.hits >= warmedMemo.hits + 1)
        for passage in passages {
            let source = try #require(sources.first { $0.candidate.note == passage.candidate.note })
            let range = try #require(
                Range(
                    NSRange(
                        location: passage.range.utf16LowerBound,
                        length: passage.range.utf16UpperBound - passage.range.utf16LowerBound), in: source.document.rawContent))
            #expect(passage.source == String(source.document.rawContent[range]))
        }
        let reopened = try fixture.index()
        for index in [rebuilt, reopened] {
            let response = try await index.relatedMaterialSourceCandidates(focus)
            assertCandidates(response, equalTo: expected)
            #expect(try await index.relatedPassages(focus, sources: fixture.sources(response)) == passages)
        }
        // Foreground requests do not publish their subset as background preparation.
        let repeatedCold = try await cold.relatedMaterialSourceCandidates(focus)
        assertCandidates(repeatedCold, equalTo: expected)
        let coldStatistics = await cold.relatedBackgroundPreparationStatistics
        #expect(coldStatistics.hits == 0 && coldStatistics.misses == 2)
    }

    @Test("Broad Note preparation cannot expand a rare focus response or its source-read set")
    func rareFocusDoesNotReadBackground() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        let distractors = (0..<25).map {
            fixture.item(fixture.analyses, "Background\($0).md", "Orchard geology sediment.")
        }
        let documents =
            fixture.documents + distractors + [
                fixture.item(fixture.analyses, "Rare.md", "Quantum resonance calibrates this separate experiment.")
            ]
        _ = try await index.synchronize(documents)
        let request = fixture.request(focus: "quantum")
        let cold = try await index.relatedMaterialSourceCandidates(request)
        let background = try await index.relatedMaterialSourceCandidates(fixture.request())
        #expect(background.lexicalCandidates.count == 27)
        #expect(!background.lexicalCandidates.contains { $0.note.relativePath == "Rare.md" })
        try await index.prepareRelatedPassages(fixture.request(), sources: fixture.sources(background, documents: documents))
        let warm = try await index.relatedMaterialSourceCandidates(request)
        assertCandidates(warm, equalTo: cold)
        #expect(warm.identityCandidates.isEmpty)
        #expect(warm.lexicalCandidates.map(\.note.relativePath) == ["Rare.md"])
        let sources = fixture.sources(warm, documents: documents)
        #expect(sources.count == 1)
        let paragraphs = try TriptychSearchIndex.relatedPassages(request, sources: sources)
        #expect(!paragraphs.isEmpty)
        #expect(try await index.relatedPassages(request, sources: sources) == paragraphs)

        // The unrelated lexical payload is outside this focus read. This would
        // fail if foreground synchronously rescanned the whole background pool.
        // Open the unprepared reader before damage: index-open integrity checks
        // deliberately validate the complete database, unlike a scoped query.
        let unprepared = try fixture.index()
        try fixture.execute("UPDATE search_documents SET related_lexical_hash = 'damaged' WHERE relative_path = 'Context.md';")
        let withoutBackgroundRead = try await index.relatedMaterialSourceCandidates(request)
        assertCandidates(withoutBackgroundRead, equalTo: cold)
        let uncached = try await unprepared.relatedMaterialSourceCandidates(request)
        assertCandidates(uncached, equalTo: cold)
        do {
            _ = try await index.relatedMaterialSourceCandidates(fixture.request())
            Issue.record("A background scan must still validate its own eligible payloads")
        } catch SearchIndexError.corruptDatabase {}
    }

    @Test("Narrow scope, exact source revision, seed identity and new generation invalidate preparation")
    func invalidationAndIncrementalEquivalence() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize(fixture.documents)
        _ = try await index.relatedMaterialSourceCandidates(fixture.request())
        let narrowed = fixture.request(focus: "magnetic compass calibration", roles: [.analysis])
        let restricted = try await index.relatedMaterialSourceCandidates(narrowed)
        #expect(restricted.lexicalCandidates.allSatisfy { $0.vaultRole == .sourceCorpus })
        #expect(!restricted.lexicalCandidates.contains { $0.note.relativePath == "Shared.md" })
        var statistics = await index.relatedBackgroundPreparationStatistics
        #expect(statistics.hits == 0 && statistics.misses == 2)

        let changedSeed = fixture.request(source: "orchard geology é")
        let canonicallyEquivalentSeed = fixture.request(source: "orchard geology e\u{301}")
        #expect(changedSeed.seed.source == canonicallyEquivalentSeed.seed.source)
        #expect(changedSeed.seed.fingerprint != canonicallyEquivalentSeed.seed.fingerprint)
        _ = try await index.relatedMaterialSourceCandidates(changedSeed)
        _ = try await index.relatedMaterialSourceCandidates(canonicallyEquivalentSeed)
        _ = try await index.relatedMaterialSourceCandidates(fixture.request(path: "OtherDraft.md"))
        statistics = await index.relatedBackgroundPreparationStatistics
        #expect(statistics.hits == 0 && statistics.misses == 5)

        var changed = fixture.documents.filter { $0.relativePath != "Context.md" }
        changed.append(fixture.item(fixture.analyses, "Replacement.md", "Orchard geology and magnetic compass calibration are recorded."))
        _ = try await index.synchronize(changed)
        let focus = fixture.request(focus: "magnetic compass calibration")
        let incremental = try await index.relatedMaterialSourceCandidates(focus)
        #expect(!incremental.lexicalCandidates.contains { $0.note.relativePath == "Context.md" })
        #expect(incremental.lexicalCandidates.contains { $0.note.relativePath == "Replacement.md" })
        statistics = await index.relatedBackgroundPreparationStatistics
        #expect(statistics.hits == 0 && statistics.misses == 6)
        let rebuilt = try fixture.index(name: "rebuilt.sqlite")
        _ = try await rebuilt.synchronize(Array(changed.reversed()))
        let clean = try await rebuilt.relatedMaterialSourceCandidates(focus)
        assertCandidates(incremental, equalTo: clean)
        let sources = fixture.sources(incremental, documents: changed)
        let currentPassages = try await index.relatedPassages(focus, sources: sources)
        let rebuiltPassages = try await rebuilt.relatedPassages(focus, sources: sources)
        #expect(currentPassages == rebuiltPassages)
    }

    @Test("Foreground metadata and identity candidates retain their original comparison-set admission")
    func foregroundComparisonSetIsPreserved() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        let documents =
            fixture.documents + [
                fixture.item(
                    fixture.analyses, "Annotated.md", "---\nkeywords: [magnetic, compass, calibration]\n---\n\nOrchard geology remains unrelated prose."),
                fixture.item(fixture.analyses, "Magnetic Compass Calibration.md", "Orchard geology remains unrelated prose."),
            ]
        _ = try await index.synchronize(documents)
        let request = fixture.request(focus: "magnetic compass calibration")
        let response = try await index.relatedMaterialSourceCandidates(request)
        let sources = fixture.sources(response, documents: documents)
        let metadata = try #require(sources.first { $0.candidate.note.relativePath == "Annotated.md" })
        guard case .lexicalOverlap(let reason) = metadata.candidate.reason else {
            Issue.record("Metadata fixture must exercise the foreground lexical path")
            return
        }
        #expect(reason.seedMatches.contains { $0.seedKind == .selectedPassage })
        let identity = try #require(sources.first { $0.candidate.note.relativePath == "Magnetic Compass Calibration.md" })
        guard case .identityMention = identity.candidate.reason else {
            Issue.record("Named fixture must exercise the identity path")
            return
        }
        var diagnostics: [RelatedContentRankingDiagnostic] = []
        _ = try TriptychSearchIndex.relatedPassages(request, sources: sources) { diagnostics.append($0) }
        for path in ["Annotated.md", "Magnetic Compass Calibration.md"] {
            // These Notes still contribute comparison data before their actual
            // paragraphs are rejected, just as before two-layer preparation.
            let events = diagnostics.filter { $0.note.relativePath == path }
            #expect(!events.isEmpty)
            #expect(events.allSatisfy { $0.stage == .noLocalMatch && $0.range != nil })
        }
        #expect(!sources.contains { $0.candidate.note.relativePath == "Context.md" })
        #expect(!diagnostics.contains { $0.note.relativePath == "Context.md" })
    }

    enum Damage: Sendable { case checksum, payload, negativeLength }

    @Test("Warm preparation still detects runtime payload damage in the same generation", arguments: [Damage.checksum, .payload, .negativeLength])
    func corruptionAfterPreparation(damage: Damage) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize(fixture.documents)
        _ = try await index.relatedMaterialSourceCandidates(fixture.request())
        let generation = try await index.generation()
        let mutation: String
        switch damage {
        case .checksum: mutation = "related_lexical_hash = 'incorrect'"
        case .payload:
            // Matching the new digest is not enough: it must decode and validate.
            let digest = RelatedContentSourceProjection.checksum(Data([0]))
            mutation = "related_lexical = X'00', related_lexical_hash = '\(digest)'"
        case .negativeLength: mutation = "source_utf16_count = -1"
        }
        try fixture.execute("UPDATE search_documents SET \(mutation) WHERE relative_path = 'Shared.md';")
        #expect(try await index.generation() == generation)
        do {
            _ = try await index.relatedMaterialSourceCandidates(fixture.request(focus: "magnetic compass calibration"))
            Issue.record("An eligible focus payload must still be checked after background preparation")
        } catch SearchIndexError.corruptDatabase {}
    }

    @Test("Cancelled preparation cannot return candidates or populate either memo")
    func cancellation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize(fixture.documents)
        let request = fixture.request()
        let cancelledCandidates = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await index.relatedMaterialSourceCandidates(request)
        }
        do {
            _ = try await cancelledCandidates.value
            Issue.record("Cancelled candidate preparation must throw")
        } catch is CancellationError {}
        let before = await index.relatedBackgroundPreparationStatistics
        #expect(before == .init())
        let response = try await index.relatedMaterialSourceCandidates(request)
        let sources = fixture.sources(response)
        let cancelledPassages = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await index.prepareRelatedPassages(request, sources: sources)
        }
        do {
            try await cancelledPassages.value
            Issue.record("Cancelled passage preparation must throw")
        } catch is CancellationError {}
        let memo = await index.relatedPassagePreparationStatistics
        #expect(memo == .init())
        try await index.prepareRelatedPassages(request, sources: sources)
        #expect(try await index.relatedPassages(request, sources: sources) == TriptychSearchIndex.relatedPassages(request, sources: sources))
    }

    @Test("Passage warmup excludes the seed and out-of-scope or mismatched current documents")
    func prewarmSourceValidation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize(fixture.documents)
        let response = try await index.relatedMaterialSourceCandidates(fixture.request())
        let sources = fixture.sources(response)
        let valid = try #require(sources.first { $0.candidate.note.relativePath == "Context.md" })
        let wrongRevision = RelatedContentSource(candidate: valid.candidate, document: .init(relativePath: "Context.md", rawContent: "Changed."))
        let wrongPath = RelatedContentSource(candidate: valid.candidate, document: .init(relativePath: "Elsewhere.md", rawContent: valid.document.rawContent))
        let seed = try #require(fixture.documents.first { $0.relativePath == "Draft.md" })
        let seedSource = RelatedContentSource(
            candidate: .init(
                note: fixture.request().seed.noteID, vaultRole: .draftProject, title: "Draft", fingerprint: seed.document.fingerprint,
                reason: valid.candidate.reason), document: seed.document)
        let narrowed = fixture.request(roles: [.analysis, .work])
        try await index.prepareRelatedPassages(narrowed, sources: [wrongRevision, wrongPath, seedSource] + sources + sources)
        let statistics = await index.relatedPassagePreparationStatistics
        #expect(statistics.misses == 1)
        #expect(statistics.hits == 0)
        let request = fixture.request(focus: "orchard geology", roles: [.analysis])
        #expect(try await index.relatedPassages(request, sources: sources) == TriptychSearchIndex.relatedPassages(request, sources: [valid]))
        let updated = NoteDocument(relativePath: "Context.md", rawContent: "Orchard geology revised source.\r\n")
        let current = RelatedContentSource(
            candidate: .init(
                note: valid.candidate.note, vaultRole: valid.candidate.vaultRole, title: valid.candidate.title,
                fingerprint: updated.fingerprint, reason: valid.candidate.reason), document: updated)
        // Index is still old: both APIs must use the exact current document fallback.
        try await index.prepareRelatedPassages(request, sources: [current])
        #expect(try await index.relatedPassages(request, sources: [current]) == TriptychSearchIndex.relatedPassages(request, sources: [current]))
        #expect(try await index.relatedPassages(request, sources: [wrongRevision]).isEmpty)
    }

    private func assertCandidates(_ actual: RelatedContentResponse, equalTo expected: RelatedContentResponse) {
        #expect(actual.identityCandidates == expected.identityCandidates)
        #expect(actual.lexicalCandidates == expected.lexicalCandidates)
        #expect(actual.identityHasMore == expected.identityHasMore)
        #expect(actual.lexicalHasMore == expected.lexicalHasMore)
        #expect(actual.seedFingerprint == expected.seedFingerprint)
        #expect(actual.state == expected.state)
    }

    private struct Fixture {
        let root: URL
        let triptychID = UUID()
        let analyses = RegisteredVault(name: "Analyses", role: .sourceCorpus, canonicalPath: "/fixtures/analyses")
        let topics = RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: "/fixtures/topics")
        let works = RegisteredVault(name: "Works", role: .draftProject, canonicalPath: "/fixtures/works")

        init() throws {
            root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent(".build/related-background/\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        var documents: [SearchIndexDocument] {
            [
                item(analyses, "Context.md", "Orchard geology records sediment and roots."),
                item(topics, "Shared.md", "\u{FEFF}Orchard geology records the sample.\r\n\r\nMagnetic compass calibration checks instrument readings.\r\n"),
                item(analyses, "Fresh.md", "Magnetic compass calibration corrects an instrument before measurement."),
                item(works, "Draft.md", "Orchard geology and magnetic compass calibration in the saved seed."),
            ]
        }

        func item(_ vault: RegisteredVault, _ path: String, _ text: String) -> SearchIndexDocument {
            .init(vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role, document: .init(relativePath: path, rawContent: text))
        }

        func request(
            focus: String? = nil, source: String = "orchard geology", path: String = "Draft.md",
            roles: [RelatedContentCandidateRole] = RelatedContentCandidateRole.allCases
        ) -> RelatedContentRequest {
            .init(
                seed: .init(
                    noteID: .init(vaultID: works.id, relativePath: path), source: source,
                    focuses: focus.map { [.init(kind: .selectedPassage, text: $0)] } ?? []),
                candidateRoles: roles, identityLimit: 3, lexicalLimit: 1)
        }

        func sources(_ response: RelatedContentResponse, documents: [SearchIndexDocument]? = nil) -> [RelatedContentSource] {
            var seen = Set<VaultQualifiedNoteID>()
            return (response.identityCandidates + response.lexicalCandidates).compactMap { candidate in
                guard seen.insert(candidate.note).inserted,
                    let item = (documents ?? self.documents).first(where: {
                        $0.vaultID == candidate.note.vaultID && $0.relativePath == candidate.note.relativePath
                    })
                else { return nil }
                return .init(candidate: candidate, document: item.document)
            }
        }

        func index(name: String = "search.sqlite") throws -> TriptychSearchIndex {
            try .init(databaseURL: root.appendingPathComponent(name), triptychID: triptychID, vaults: [analyses, topics, works])
        }

        func execute(_ sql: String) throws {
            var handle: OpaquePointer?
            let opened = sqlite3_open_v2(root.appendingPathComponent("search.sqlite").path, &handle, SQLITE_OPEN_READWRITE, nil)
            defer { sqlite3_close(handle) }
            try #require(opened == SQLITE_OK)
            try #require(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
