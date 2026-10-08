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

    @Test("Same-source companion revisions refresh bibliography layout without reusing stale semantics")
    func citationRevisionRefreshesProjection() async {
        let cache = DocumentReadProjectionCache()
        let workspaceID = UUID()
        let noteID = UUID()
        let vaultID = UUID()
        let source = "\u{FEFF}# References\r\n\r\n<!--cite-bibliography:cbib-->\r\n\r\nAuthor. *Current Title.*\r\n\r\n<!--/cite-bibliography-->\r\n"
        let sourceFingerprint = DocumentFingerprint(content: source)
        let code = "BIBL {} CSL_BIBLIOGRAPHY"
        func snapshot(indent: Double) -> ZoteroCitationSnapshot {
            ZoteroCitationSnapshot(
                noteID: noteID, vaultID: vaultID,
                revision: DocumentFingerprint(content: "companion-indent-\(indent)"),
                sourceFingerprint: sourceFingerprint,
                data: ZoteroCitationData(
                    fields: [.init(id: "cbib", kind: .bibliography, code: code, text: "CACHED TEXT")],
                    documentData: "opaque preferences",
                    bibliographyStyle: .init(
                        firstLineIndent: -indent, indent: indent, lineSpacing: 240,
                        entrySpacing: 0, tabStops: []),
                    acceptedFields: [.init(id: "cbib", code: code)]),
                status: .available)
        }
        func key(_ citation: ZoteroCitationSnapshot) -> DocumentReadProjectionKey {
            DocumentReadProjectionKey(
                workspaceID: workspaceID, stableTarget: noteID.uuidString,
                relativePath: "References.md", fingerprint: sourceFingerprint,
                citationRevision: citation.revision, citationStatus: citation.status)
        }
        let first = snapshot(indent: 720)
        let changed = snapshot(indent: 1_440)
        let firstDocument = NoteDocument(relativePath: "References.md", rawContent: source, citationSnapshot: first)
        let staleSemantic = MarkdownSemanticDocument(parsing: firstDocument)
        let initialHTML = await cache.html(
            for: key(first), source: source, semantic: staleSemantic, citationSnapshot: first)
        let changedHTML = await cache.html(
            for: key(changed), source: source, semantic: staleSemantic, citationSnapshot: changed)

        #expect(key(first) != key(changed))
        #expect(initialHTML.contains("margin-left:36.0pt;text-indent:-36.0pt;"))
        #expect(changedHTML.contains("margin-left:72.0pt;text-indent:-72.0pt;"))
        #expect(!changedHTML.contains("margin-left:36.0pt;"))
        #expect(changedHTML.contains("<em>Current Title.</em>"))
        #expect(!changedHTML.contains("CACHED TEXT"))
        #expect(await cache.html(for: key(changed), source: source, citationSnapshot: changed) == changedHTML)
        #expect(await cache.entryCount(workspaceID: workspaceID) == 1)
        #expect(firstDocument.sourceBytes == Data(source.utf8))
    }

    @Test("Authorized image availability and content participate in cache validity", arguments: [false, true])
    func imageRevisionControlsReuse(reuseSemantic: Bool) async throws {
        let cache = DocumentReadProjectionCache()
        let source = "\u{FEFF}---\r\ncustom: preserved\r\n---\r\n\r\n![Figure & Sample](Attachments/fixture/Figure%20Sample.png)\r\n"
        let document = NoteDocument(relativePath: "Image.md", rawContent: source)
        let semantic = reuseSemantic ? MarkdownSemanticDocument(parsing: document) : nil
        let key = key(workspaceID: UUID(), target: "image-note", path: document.relativePath, source: source)
        let destination = "Attachments/fixture/Figure Sample.png"
        let pngHeader: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let firstImage = try RenderedMarkdownImage(data: Data(pngHeader + [0]), mimeType: "image/png")
        let changedImage = try RenderedMarkdownImage(data: Data(pngHeader + [1]), mimeType: "image/png")
        let unavailable = await cache.html(for: key, source: source, semantic: semantic)
        #expect(!unavailable.contains("<img "))

        let available = await cache.html(
            for: key, source: source, semantic: semantic, embeddedImages: [destination: firstImage])
        #expect(available.contains("alt=\"Figure &amp; Sample\""))
        #expect(available.contains("src=\"data:image/png;base64,\(firstImage.data.base64EncodedString())\""))
        #expect(
            await cache.html(
                for: key, source: source, semantic: semantic, embeddedImages: [destination: firstImage]) == available)

        let changed = await cache.html(
            for: key, source: source, semantic: semantic, embeddedImages: [destination: changedImage])
        #expect(changed != available)
        #expect(changed.contains("src=\"data:image/png;base64,\(changedImage.data.base64EncodedString())\""))
        #expect(!changed.contains(firstImage.data.base64EncodedString()))
        #expect(
            await cache.html(
                for: key, source: source + "Changed", semantic: semantic, embeddedImages: [destination: firstImage]
            ).isEmpty)
        #expect(await cache.html(for: key, source: source, semantic: semantic).contains("<img ") == false)
        #expect(await cache.entryCount(workspaceID: key.workspaceID) == 1)
        #expect(document.rawContent == source)
    }

    @MainActor
    @Test("Review resolves vault-owned images through the authorized capability without rewriting source")
    func controllerResolvesAuthorizedImages() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repositoryRoot.appendingPathComponent(".build/review-image-fixtures/\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let vaults = ["Analyses", "Topics", "Works"].map { root.appendingPathComponent($0, isDirectory: true) }
        for vault in vaults { try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true) }
        let source =
            "\u{FEFF}---\r\ncustom: preserved\r\n---\r\n\r\n![Figure Sample](Attachments/fixture/Figure%20Sample.png)\r\n\r\n![Remote](https://example.invalid/private.png)\r\n"
        let noteURL = vaults[0].appendingPathComponent("Image.md")
        try Data(source.utf8).write(to: noteURL)
        let imageURL = vaults[0].appendingPathComponent("Attachments/fixture/Figure Sample.png")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        try png.write(to: imageURL)
        let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
        do {
            let capabilities = try await store.configureTriptychCapabilities(
                paperAnalysisURL: vaults[0], topicKnowledgeURL: vaults[1], outputURL: vaults[2],
                portableContainerURL: root, triptychName: "Review image fixture")
            let vault = try #require(try await capabilities.documents.snapshot().first { $0.vault.role == .sourceCorpus })
            let summary = try #require(vault.documents.first { $0.id.relativePath == "Image.md" })
            let snapshot = try await capabilities.documents.hydrate(summary)
            let controller = DocumentController()
            controller.bind(to: capabilities.documents)
            controller.installOpenedDocument(snapshot, vaultName: "Analyses", vaultRole: .sourceCorpus)
            let descriptor = try #require(controller.activeDocument)
            let target = DocumentEditingTarget.workspace(descriptor.sessionKey)
            func render() async -> String {
                await controller.readProjectionHTML(
                    target: target, relativePath: "Image.md", source: source,
                    fingerprint: snapshot.fingerprint, workspaceID: capabilities.id,
                    semantic: snapshot.cachedSemanticDocument)
            }
            let available = await render()
            #expect(available.contains("alt=\"Figure Sample\""))
            #expect(available.contains("src=\"data:image/png;base64,\(png.base64EncodedString())\""))
            #expect(!available.contains("src=\"https://"))
            try FileManager.default.removeItem(at: imageURL)
            #expect(await render().contains("<img ") == false)
            try png.write(to: imageURL)
            #expect(await render().contains("alt=\"Figure Sample\""))
            #expect(
                await controller.readProjectionHTML(
                    target: target, relativePath: "Image.md", source: source + "Changed",
                    fingerprint: snapshot.fingerprint, workspaceID: capabilities.id
                ).isEmpty)
            #expect(try Data(contentsOf: noteURL) == Data(source.utf8))
            #expect(try Data(contentsOf: imageURL) == png)
            controller.unbind()
            await store.shutdownApplicationRuntime()
        } catch {
            await store.shutdownApplicationRuntime()
            throw error
        }
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
