import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Search prepares only changed source projections")
struct SearchProjectionPreparationTests {
    @Test("Cold, unchanged, reopened and one-Note changes hydrate only required exact revisions")
    func incrementalPreparation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let cache = fixture.cache()
        let caches = [fixture.vaultID: cache]
        let index = try fixture.index()
        var sources = (0..<3).map {
            fixture.source("Note \($0).md", "# Note \($0)\n\nOriginal needle \($0).\n")
        }
        _ = try await index.synchronize(sources, sourceProjectionCaches: caches)
        let cold = try #require(await index.lastSynchronizationTimings)
        #expect(cold.projectedDocuments == 3 && cold.restoredSearchProjections == 0)
        for source in sources {
            #expect(cache.load(for: source.document) != nil, "Cold publication must persist each exact source projection: \(source.relativePath)")
        }

        let unchanged = try await index.synchronize(sources, sourceProjectionCaches: caches)
        #expect(unchanged.disposition == .unchanged)
        let warm = try #require(await index.lastSynchronizationTimings)
        #expect(warm.changedCount == 0 && warm.projectedDocuments == 0 && warm.restoredSearchProjections == 0)

        let reopened = try fixture.index()
        #expect(try await reopened.synchronize(sources, sourceProjectionCaches: caches).disposition == .unchanged)
        let reopen = try #require(await reopened.lastSynchronizationTimings)
        #expect(reopen.projectedDocuments == 0 && reopen.restoredSearchProjections == 0)

        sources[0] = fixture.source("Note 0.md", "# Note 0\n\nRevised café 自由 needle.\r\n")
        _ = try await reopened.synchronize(sources, sourceProjectionCaches: caches)
        let changed = try #require(await reopened.lastSynchronizationTimings)
        #expect(changed.changedCount == 1 && changed.projectedDocuments == 1 && changed.restoredSearchProjections == 0)
        for source in sources {
            #expect(cache.load(for: source.document) != nil, "Changed publication must retain every current projection: \(source.relativePath)")
        }
        let revised = try await reopened.testSearch(fixture.request("revised"))
        #expect(revised.noteResults.map(\.relativePath) == ["Note 0.md"])
        #expect(revised.noteResults.first?.sourceRange != nil)

        // A new generated database still restores checked persistent projections
        // from exactly the same authoritative source inventory.
        let rebuilt = try fixture.index(name: "rebuilt.sqlite")
        _ = try await rebuilt.synchronize(sources, sourceProjectionCaches: caches)
        let restored = try #require(await rebuilt.lastSynchronizationTimings)
        #expect(restored.projectedDocuments == 0)
        #expect(restored.restoredSearchProjections == 3)
        let rebuiltResults = try await rebuilt.testSearch(fixture.request("revised"))
        #expect(rebuiltResults.noteResults.map(\.relativePath) == revised.noteResults.map(\.relativePath))
        #expect(rebuiltResults.noteResults.map(\.sourceRange) == revised.noteResults.map(\.sourceRange))
    }

    @Test("Descriptor and dynamic changes publish despite identical source bytes")
    func metadataChanges() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        let source = "# Metadata\n\nNeedle.\n"
        let initialName = "Café"
        let renamed = "Cafe\u{301}"
        let original = fixture.source("Note.md", source, name: initialName)
        let cache = fixture.cache()
        _ = try await index.synchronize([original], sourceProjectionCaches: [fixture.vaultID: cache])
        #expect(cache.load(for: original.document) != nil)
        let replacement = fixture.source("Note.md", source, name: renamed)
        #expect(initialName == renamed && Data(initialName.utf8) != Data(renamed.utf8))
        #expect(try await index.synchronize([replacement]).disposition == .incrementallyUpdated)
        let renamedHit = try #require(try await index.testSearch(fixture.request("needle")).noteResults.first)
        #expect(renamedHit.vaultName.utf8.elementsEqual(renamed.utf8))

        let identity = UUID().uuidString.lowercased()
        let identified = fixture.source("Note.md", source, name: renamed, stableID: identity)
        #expect(try await index.synchronize([identified]).disposition == .incrementallyUpdated)
        let identifiedHit = try #require(try await index.testSearch(fixture.request("needle")).noteResults.first)
        #expect(identifiedHit.stableNoteID == identity)

        let rerouted = fixture.source("Note.md", source, name: renamed, role: .draftProject, stableID: identity)
        #expect(
            try await index.synchronize(
                [rerouted], sourceProjectionCaches: [fixture.vaultID: cache]
            ).disposition == .incrementallyUpdated)
        let timing = try #require(await index.lastSynchronizationTimings)
        #expect(timing.changedCount == 1 && timing.projectedDocuments == 1 && timing.restoredSearchProjections == 0)
        let updated = fixture.source(
            "Note.md", source, name: renamed, role: .draftProject, stableID: identity, broken: true)
        #expect(try await index.synchronize([updated]).disposition == .incrementallyUpdated)
        let hit = try #require(try await index.testSearch(fixture.request("needle has:broken-link")).noteResults.first)
        #expect(hit.vaultRole == .draftProject && hit.stableNoteID == identity)
        #expect(hit.evidentialLayer == .draftProse)
        #expect(try await index.synchronize([updated]).disposition == .unchanged)
    }

    @Test("A canonical-equivalent path rename deletes its byte-distinct old database key")
    func exactPathRename() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        let oldPath = "Café.md"
        let newPath = "Cafe\u{301}.md"
        #expect(oldPath == newPath && Data(oldPath.utf8) != Data(newPath.utf8))
        _ = try await index.synchronize([fixture.source(oldPath, "# Same\n\nNeedle.\n")])
        let changed = try await index.synchronize([fixture.source(newPath, "# Same\n\nNeedle.\n")])
        #expect(changed.disposition == .incrementallyUpdated)
        let result = try await index.testSearch(fixture.request("needle"))
        #expect(result.noteResults.count == 1)
        #expect(result.noteResults.first?.relativePath.utf8.elementsEqual(newPath.utf8) == true)
        #expect(result.totalResultCount == 1)
    }

    @Test("Simultaneous canonical-equivalent paths remain invalid in either input order", arguments: [false, true])
    func ambiguousCanonicalPaths(reverse: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        var sources = [
            fixture.source("Café.md", "# First\n\nNeedle.\n"),
            fixture.source("Cafe\u{301}.md", "# Second\n\nNeedle.\n"),
        ]
        if reverse { sources.reverse() }
        await #expect(throws: SearchIndexError.self) {
            _ = try await index.synchronize(sources)
        }
        #expect(try await index.generation() == nil)
    }

    @Test("A stale semantic projection cannot change canonical source hydration")
    func staleSemanticProjection() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let document = NoteDocument(relativePath: "Fresh.md", rawContent: "# Fresh\n\nCurrent needle.\n")
        let stale = MarkdownSemanticDocument(parsing: NoteDocument(relativePath: "Fresh.md", rawContent: "# Stale\n\nObsolete.\n"))
        let source = SearchIndexDocument(
            vaultID: fixture.vaultID, vaultName: "Analyses", vaultRole: .sourceCorpus,
            document: document, semantic: stale)
        #expect(source.semantic.fingerprint == document.fingerprint)
        let index = try fixture.index()
        _ = try await index.synchronize([source])
        #expect(try await index.testSearch(fixture.request("current needle")).noteResults.count == 1)
        #expect(try await index.testSearch(fixture.request("obsolete")).noteResults.isEmpty)
    }

    @Test(
        "Fresh and restored publication projections preserve complete generic Research material",
        arguments: [VaultRole.sourceCorpus, .topicKnowledge, .draftProject, .other])
    func relatedSourceSemanticEquivalence(role: VaultRole) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let vaultID = fixture.vaultID
        let nested =
            "\u{FEFF}---\r\nsummary: needle freedom\r\n---\r\n\r\n# Émotion 😀\r\n\r\n- nested needle freedom.\r\n\r\n> [[目标|行动]]{{needle freedom}}.\r\n"
        let fixtures = [
            nested,
            "---\nsummary: |\n  Exact Cafe\u{301} source.\nkeywords: [自由, evidence]\naliases: [Alias]\nauthors: [Author]\npublication_date: '2026'\nunknown: preserved\n---\n\n# Heading 😀\n\nOrdinary [[目标|行动]]{{annotation}} and $x$.\n\n> [!objection]\n> Callout argument.\n\n[^a]: Footnote wording.\n\n$$\nx + y\n$$\n",
            "---\r\nsummary: [unfinished\r\n---\r\n\r\nAmbiguous boundary 😀.\r\n",
            "",
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for (ordinal, text) in fixtures.enumerated() {
            let document = NoteDocument(relativePath: "Cafe\u{301}.md", rawContent: text)
            let rawBytes = Data(text.utf8)
            let standalone = try RelatedContentSourceProjection(document: document)
            for broken in [false, true] {
                let source = SearchIndexDocument(
                    vaultID: vaultID, vaultName: "Fixture", vaultRole: role,
                    document: document, stableNoteID: "00000000-0000-0000-0000-000000000002",
                    hasBrokenLink: broken)
                let cacheRoot = fixture.root.appendingPathComponent("\(role.rawValue)/\(ordinal)/\(broken)")
                try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
                let cache = SourceProjectionCache(
                    applicationSupportURL: cacheRoot,
                    vaultID: vaultID, role: role)
                let fresh = PreparedSearchIndexDocument(source: source, cache: cache)
                #expect(fresh.preparation.projectedDocuments == 1)
                #expect(fresh.preparation.restoredSearchProjections == 0)
                let restored = PreparedSearchIndexDocument(source: source, cache: cache)
                #expect(restored.preparation.projectedDocuments == 0)
                #expect(restored.preparation.restoredSearchProjections == 1)
                for prepared in [fresh, restored] {
                    let reused = try RelatedContentSourceProjection(prepared: prepared)
                    // Complete persisted material includes every scoring field, length,
                    // word index, display text and coordinate. Derived retained values
                    // are also checked rather than inferred from encoded equality.
                    #expect(try encoder.encode(reused) == encoder.encode(standalone))
                    #expect(reused.paragraphs.map(\.exactReadableText) == standalone.paragraphs.map(\.exactReadableText))
                    #expect(try encoder.encode(reused.paragraphs.map(\.textIndex)) == encoder.encode(standalone.paragraphs.map(\.textIndex)))
                    #expect(reused.estimatedByteCount == standalone.estimatedByteCount)
                    let bytes = try reused.encoded()
                    let decoded = try RelatedContentSourceProjection.decode(
                        bytes, checksum: RelatedContentSourceProjection.checksum(bytes), sourceUTF16Count: text.utf16.count)
                    #expect(try encoder.encode(decoded) == encoder.encode(standalone))
                    #expect(Data(source.document.rawContent.utf8) == rawBytes)
                    #expect(source.semantic.fingerprint == document.fingerprint)
                    for paragraph in reused.paragraphs {
                        let range = try #require(
                            Range(
                                NSRange(
                                    location: paragraph.range.utf16LowerBound,
                                    length: paragraph.range.utf16UpperBound - paragraph.range.utf16LowerBound),
                                in: text))
                        #expect(
                            paragraph.displayText.utf8.elementsEqual(
                                ResearchExcerptPresentation.readableText(String(text[range]), includingAnnotations: true).utf8))
                    }
                    if text.utf8.elementsEqual(nested.utf8) {
                        // These paragraphs are nested; replacing Research's semantic
                        // traversal with Search's top-level paragraph list loses both.
                        #expect(SearchDocumentProjection(document: document).paragraphs.isEmpty)
                        #expect(reused.paragraphs.map(\.displayText) == ["nested needle freedom.", "行动 (needle freedom)."])
                        #expect(reused.paragraphs.map { $0.range.line } == [7, 9])
                        try #require(reused.paragraphs.count == 2)
                        for (paragraph, exact) in zip(
                            reused.paragraphs, ["nested needle freedom.", "[[目标|行动]]{{needle freedom}}."])
                        {
                            let authoredRange = try #require(text.range(of: exact))
                            let authored = NSRange(authoredRange, in: text)
                            #expect(paragraph.range.utf16LowerBound == authored.location)
                            #expect(paragraph.range.utf16UpperBound == authored.location + authored.length)
                        }
                    }
                }
            }
        }
    }

    @Test("Stale supplied semantics cannot authorize obsolete Research wording")
    func relatedSourceStaleSemantic() throws {
        let vaultID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let document = NoteDocument(relativePath: "Current.md", rawContent: "[[目标|行动]]{{new Cafe\u{301} freedom}}.\r\n")
        let stale = MarkdownSemanticDocument(
            parsing: NoteDocument(relativePath: document.relativePath, rawContent: "[[目标|行动]]{{old needle}}.\r\n"))
        let source = SearchIndexDocument(
            vaultID: vaultID, vaultName: "Fixture", vaultRole: .sourceCorpus, document: document, semantic: stale)
        let reused = try RelatedContentSourceProjection(prepared: PreparedSearchIndexDocument(source: source, cache: nil))
        let standalone = try RelatedContentSourceProjection(document: document)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(source.semantic.fingerprint == document.fingerprint)
        #expect(source.semantic.fingerprint != stale.fingerprint)
        #expect(try encoder.encode(reused) == encoder.encode(standalone))
        #expect(reused.paragraphs.map(\.displayText) == ["行动 (new Cafe\u{301} freedom)."])
        #expect(reused.paragraphs.allSatisfy { !$0.displayText.contains("old needle") })
    }

    @Test("A cancelled publication cannot construct Research material from prepared semantics")
    func relatedSourceSemanticCancellation() async throws {
        let vaultID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let source = SearchIndexDocument(
            vaultID: vaultID, vaultName: "Fixture", vaultRole: .sourceCorpus,
            document: NoteDocument(relativePath: "Cancelled.md", rawContent: "Current wording."))
        let prepared = PreparedSearchIndexDocument(source: source, cache: nil)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try RelatedContentSourceProjection(prepared: prepared)
        }
        do {
            _ = try await cancelled.value
            Issue.record("Cancelled Research source preparation must throw")
        } catch is CancellationError {}
    }

    private struct Fixture {
        let root: URL
        let vaultID = UUID()
        let triptychID = UUID()

        init() throws {
            root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/search-projection-preparation/\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }

        func cache() -> SourceProjectionCache {
            .init(applicationSupportURL: root, vaultID: vaultID, role: .sourceCorpus)
        }

        func index(name: String = "search.sqlite") throws -> TriptychSearchIndex {
            try .init(isolatedDatabaseURL: root.appendingPathComponent(name), triptychID: triptychID)
        }

        func source(
            _ path: String, _ source: String, name: String = "Analyses", role: VaultRole = .sourceCorpus,
            stableID: String? = nil, broken: Bool = false
        ) -> SearchIndexDocument {
            .init(
                vaultID: vaultID, vaultName: name, vaultRole: role,
                document: NoteDocument(relativePath: path, rawContent: source),
                stableNoteID: stableID, hasBrokenLink: broken)
        }

        func request(_ query: String) -> SearchRequest {
            .init(query: query, presentationScope: .triptych, executionScope: .triptych, limit: 100)
        }
    }
}
