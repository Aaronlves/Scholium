import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Document read projection cache")
struct DocumentReadProjectionCacheTests {
    @Test("Read projections are revision-bound and reused")
    func revisionBoundReuse() async {
        let cache = DocumentReadProjectionCache()
        let source = "# Exact\n\nBody\n"
        let key = DocumentReadProjectionKey(
            workspaceID: UUID(),
            stableTarget: "note-1",
            relativePath: "Exact.md",
            fingerprint: DocumentFingerprint(content: source)
        )

        let first = await cache.html(for: key, source: source)
        let second = await cache.html(for: key, source: source)
        let stale = await cache.html(for: key, source: source + "changed")

        #expect(!first.isEmpty)
        #expect(second == first)
        #expect(stale.isEmpty)
        #expect(await cache.entryCount(workspaceID: key.workspaceID) == 1)
    }

    @Test("Read reuses an exact workspace semantic projection")
    func exactSemanticReuse() async {
        let cache = DocumentReadProjectionCache()
        let source = "# Exact\n\nA [[Target]] with *emphasis*.\n"
        let document = NoteDocument(relativePath: "Exact.md", rawContent: source)
        let semantic = MarkdownSemanticDocument(parsing: document)
        let key = DocumentReadProjectionKey(
            workspaceID: UUID(),
            stableTarget: "note-1",
            relativePath: document.relativePath,
            fingerprint: document.fingerprint
        )

        let reused = await cache.html(for: key, source: source, semantic: semantic)

        #expect(reused == SafeMarkdownRenderer.render(document).htmlBody)
    }

    @Test("Empty Markdown is retained as a valid read projection")
    func emptyMarkdownProjection() async {
        let cache = DocumentReadProjectionCache()
        let workspaceID = UUID()
        let key = DocumentReadProjectionKey(
            workspaceID: workspaceID,
            stableTarget: "empty-note",
            relativePath: "Untitled.md",
            fingerprint: DocumentFingerprint(content: "")
        )

        let first = await cache.html(for: key, source: "")
        let second = await cache.html(for: key, source: "")

        #expect(first.isEmpty)
        #expect(second == first)
        #expect(await cache.entryCount(workspaceID: workspaceID) == 1)
    }

    @Test("Each workspace evicts its least recently used projection independently")
    func boundedPerWorkspaceEviction() async {
        let cache = DocumentReadProjectionCache(
            maximumEntriesPerWorkspace: 2,
            maximumBytesPerWorkspace: 1_000_000
        )
        let firstWorkspace = UUID()
        let secondWorkspace = UUID()

        for index in 0..<3 {
            let source = "# First \(index)\n"
            _ = await cache.html(
                for: DocumentReadProjectionKey(
                    workspaceID: firstWorkspace,
                    stableTarget: "first-\(index)",
                    relativePath: "First \(index).md",
                    fingerprint: DocumentFingerprint(content: source)
                ),
                source: source
            )
        }
        let secondSource = "# Second\n"
        _ = await cache.html(
            for: DocumentReadProjectionKey(
                workspaceID: secondWorkspace,
                stableTarget: "second",
                relativePath: "Second.md",
                fingerprint: DocumentFingerprint(content: secondSource)
            ),
            source: secondSource
        )

        #expect(await cache.entryCount(workspaceID: firstWorkspace) == 2)
        #expect(await cache.entryCount(workspaceID: secondWorkspace) == 1)
    }
}
