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
        let revised = try await reopened.testSearch(fixture.request("revised"))
        #expect(revised.noteResults.map(\.relativePath) == ["Note 0.md"])
        #expect(revised.noteResults.first?.sourceRange != nil)

        // A new generated database still restores checked persistent projections
        // from exactly the same authoritative source inventory.
        let rebuilt = try fixture.index(name: "rebuilt.sqlite")
        _ = try await rebuilt.synchronize(sources, sourceProjectionCaches: caches)
        let restored = try #require(await rebuilt.lastSynchronizationTimings)
        #expect(restored.projectedDocuments == 0 && restored.restoredSearchProjections == 3)
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

        func cache() -> SourceSearchProjectionCache {
            .init(applicationSupportURL: root, vaultID: vaultID, role: .sourceCorpus)
        }

        func index(name: String = "search.sqlite") throws -> TriptychSearchIndex {
            try .init(databaseURL: root.appendingPathComponent(name), triptychID: triptychID)
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
