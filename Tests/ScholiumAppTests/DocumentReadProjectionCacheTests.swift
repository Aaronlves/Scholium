import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Document read projection cache")
struct DocumentReadProjectionCacheTests {
    #if DEBUG
        @Test("QA cache stats count only retained HTML across workspaces")
        func qaDiagnosticStats() async {
            let cache = DocumentReadProjectionCache()
            let source = "# Exact\n"
            let first = await cache.html(
                for: key(workspaceID: UUID(), target: "first", path: "First.md", source: source),
                source: source
            )
            let second = await cache.html(
                for: key(workspaceID: UUID(), target: "second", path: "Second.md", source: source),
                source: source
            )
            let retained = await cache.qaDiagnosticStats()
            #expect(retained.entryCount == 2)
            #expect(retained.htmlUTF8ByteCount == first.utf8.count + second.utf8.count)
            await cache.removeAll()
            let cleared = await cache.qaDiagnosticStats()
            #expect(cleared.entryCount == 0)
            #expect(cleared.htmlUTF8ByteCount == 0)
        }
    #endif

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

    @Test("Repeated committed revisions retain only the last requested HTML and preserve other Notes")
    func supersededRevisionsReleaseHTML() async {
        let cache = DocumentReadProjectionCache()
        let workspaceID = UUID()
        let otherWorkspaceID = UUID()
        let otherSource = "# Other Note\n\nKeep this projection.\n"
        let otherHTML = await cache.html(
            for: key(workspaceID: workspaceID, target: "other", path: "Other.md", source: otherSource),
            source: otherSource)
        let otherWorkspaceHTML = await cache.html(
            for: key(workspaceID: otherWorkspaceID, source: otherSource), source: otherSource)
        let body = String(repeating: "A paragraph about memory and exact source.\n\n", count: 256)
        var latestHTML = ""
        for revision in 0..<32 {
            let source = "# Revision \(revision)\n\n" + body
            latestHTML = await cache.html(for: key(workspaceID: workspaceID, source: source), source: source)
            #expect(latestHTML.contains("Revision \(revision)"))
        }

        let retainedBytes = await cache.retainedHTMLByteCount(workspaceID: workspaceID)
        let expectedBytes = latestHTML.utf8.count + otherHTML.utf8.count
        print("Read HTML cache after 32 committed revisions: \(retainedBytes) retained UTF-8 bytes; latest revision plus other Note: \(expectedBytes) bytes")
        #expect(await cache.entryCount(workspaceID: workspaceID) == 2)
        #expect(retainedBytes == expectedBytes)
        #expect(await cache.entryCount(workspaceID: otherWorkspaceID) == 1)
        #expect(await cache.retainedHTMLByteCount(workspaceID: otherWorkspaceID) == otherWorkspaceHTML.utf8.count)

        // Undo or an older in-flight request may legitimately request exact old
        // bytes again. Retention follows requests, not monotonic revisions.
        let revertedSource = "# Revision 0\n\n" + body
        let revertedHTML = await cache.html(
            for: key(workspaceID: workspaceID, source: revertedSource), source: revertedSource)
        #expect(revertedHTML.contains("Revision 0"))
        #expect(await cache.entryCount(workspaceID: workspaceID) == 2)
        #expect(await cache.retainedHTMLByteCount(workspaceID: workspaceID) == revertedHTML.utf8.count + otherHTML.utf8.count)
    }

    @Test("An oversized revision releases old HTML without evicting another Note")
    func oversizedRevisionDiscardsSupersededHTML() async {
        let cache = DocumentReadProjectionCache(maximumBytesPerWorkspace: 4_096)
        let workspaceID = UUID()
        let source = "# Small\n"
        _ = await cache.html(for: key(workspaceID: workspaceID, source: source), source: source)
        let otherSource = "# Other\n"
        let otherHTML = await cache.html(
            for: key(workspaceID: workspaceID, target: "other", path: "Other.md", source: otherSource),
            source: otherSource)

        let oversizedSource = String(repeating: "A large revision.\n\n", count: 512)
        let oversizedHTML = await cache.html(
            for: key(workspaceID: workspaceID, source: oversizedSource), source: oversizedSource)
        #expect(oversizedHTML.utf8.count > 4_096)
        #expect(await cache.entryCount(workspaceID: workspaceID) == 1)
        #expect(await cache.retainedHTMLByteCount(workspaceID: workspaceID) == otherHTML.utf8.count)
    }

    @Test("A mismatched source cannot evict the valid revision")
    func invalidFingerprintPreservesCachedHTML() async {
        let cache = DocumentReadProjectionCache()
        let workspaceID = UUID()
        let source = "# Valid\n"
        let html = await cache.html(for: key(workspaceID: workspaceID, source: source), source: source)
        let rejectedHTML = await cache.html(
            for: key(workspaceID: workspaceID, source: "# Different revision\n"), source: "# Wrong bytes\n")

        #expect(rejectedHTML.isEmpty)
        #expect(await cache.entryCount(workspaceID: workspaceID) == 1)
        #expect(await cache.retainedHTMLByteCount(workspaceID: workspaceID) == html.utf8.count)
    }

    private func key(
        workspaceID: UUID, target: String = "changing-note", path: String = "Changing.md", source: String
    ) -> DocumentReadProjectionKey {
        .init(
            workspaceID: workspaceID, stableTarget: target, relativePath: path,
            fingerprint: DocumentFingerprint(content: source))
    }
}
