import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Source image Quick Look preparation")
struct SourceImagePreviewTests {
    private static let png = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    @Test("Unsaved images retain exact source, extensionless paths and one-pass destination decoding")
    func unsavedSourceImages() async throws {
        try await withFixture { fixture, handle, target in
            let sourceURL = fixture.analysesURL.appendingPathComponent(target.relativePath)
            let original = try Data(contentsOf: sourceURL)
            let cases = [
                ("Figure", "Figure", "![Figure](Figure)"),
                ("A&B%20.png", "A&B%2520.png", "![Entity and percent](A&amp;B%2520.png)"),
                ("A&amp;B.png", "A&amp;B.png", "![Literal entity](A&amp;amp;B.png)"),
                ("Question?.png", "Question%3F.png", "![Reserved](Question%3F.png)"),
                ("Reference.png", "Reference.png", "![Reference][figure]\n\n[figure]: Reference.png"),
            ]
            for (filename, destination, source) in cases {
                let imageURL = fixture.analysesURL.appendingPathComponent(filename)
                try Self.png.write(to: imageURL)
                let lease = try await handle.documents.prepareSourceImagePreview(
                    destination: destination, source: source, for: target
                )
                #expect(lease.fileURL.path.utf8.elementsEqual(imageURL.path.utf8))
                #expect(try Data(contentsOf: lease.fileURL) == Self.png)
                await handle.documents.releaseDocumentAttachmentPreview(accessToken: lease.accessToken)
            }
            #expect(try Data(contentsOf: sourceURL) == original)
            #expect(try await handle.documents.documentAttachments(for: target).isEmpty)
        }
    }

    @Test("Only current parsed images with admitted raster bytes and contained paths can open")
    func rejectsUnauthoredAndUnavailableImages() async throws {
        try await withFixture { fixture, handle, target in
            try Self.png.write(to: fixture.analysesURL.appendingPathComponent("Figure.png"))
            try Data("not an image".utf8).write(to: fixture.analysesURL.appendingPathComponent("Invalid.png"))
            let outside = fixture.rootURL.appendingPathComponent("Outside.png")
            try Self.png.write(to: outside)
            try FileManager.default.createSymbolicLink(
                at: fixture.analysesURL.appendingPathComponent("Symlink.png"), withDestinationURL: outside
            )
            let rejected = [
                ("Figure.png", "[File link](Figure.png)"),
                ("Figure.png", "`![Code](Figure.png)`"),
                ("Figure.png", "![Different](Missing.png)"),
                ("Missing.png", "![Missing](Missing.png)"),
                ("Invalid.png", "![Invalid](Invalid.png)"),
                ("Symlink.png", "![Symlink](Symlink.png)"),
                ("../Outside.png", "![Escape](../Outside.png)"),
                ("%2e%2e/Outside.png", "![Escape](%2e%2e/Outside.png)"),
                (outside.path, "![Unregistered](\(outside.path))"),
                ("https://example.com/image.png", "![Remote](https://example.com/image.png)"),
                ("file:///image.png", "![URL](file:///image.png)"),
                ("Figure.png", "---\ninvalid: [\n---\n![Malformed YAML](Figure.png)"),
                ("Figure.png", "![NUL](Figure.png)\0"),
            ]
            for (destination, source) in rejected {
                await #expect(throws: (any Error).self) {
                    _ = try await handle.documents.prepareSourceImagePreview(
                        destination: destination, source: source, for: target
                    )
                }
            }
            await #expect(throws: (any Error).self) {
                _ = try await handle.documents.prepareSourceImagePreview(
                    destination: "Figure.png",
                    source: "![Figure](Figure.png)" + String(repeating: "x", count: VaultSourceReadLimits.maximumNoteByteCount),
                    for: target
                )
            }
            await #expect(throws: DocumentAttachmentError.self) {
                _ = try await handle.documents.prepareSourceImagePreview(
                    destination: "Figure.png", source: "![Figure](Figure.png)",
                    for: SourceAttachmentTarget(noteID: UUID(), vaultID: target.vaultID, relativePath: target.relativePath)
                )
            }
        }
    }

    @Test("Indexed originals use releasable leases and cancelled or invalid preparation cannot succeed")
    func indexedImageLease() async throws {
        try await withFixture { fixture, handle, target in
            let original = fixture.rootURL.appendingPathComponent("Indexed.png")
            try Self.png.write(to: original)
            let prepared = try await handle.documents.indexImageAttachment(at: original, for: fixture.analysisNoteID)
            let destination = prepared.markdownDestination
            let source = "![Indexed](\(destination))"
            let first = try await handle.documents.prepareSourceImagePreview(
                destination: destination, source: source, for: target
            )
            let second = try await handle.documents.prepareSourceImagePreview(
                destination: destination, source: source, for: target
            )
            #expect(first.attachmentID == prepared.record.id)
            #expect(first.fileURL == original)
            #expect(first.accessToken != second.accessToken)
            await handle.documents.releaseDocumentAttachmentPreview(accessToken: first.accessToken)
            await handle.documents.releaseDocumentAttachmentPreview(accessToken: first.accessToken)
            #expect(try Data(contentsOf: second.fileURL) == Self.png)
            await handle.documents.releaseDocumentAttachmentPreview(accessToken: second.accessToken)

            let cancelled = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await handle.documents.prepareSourceImagePreview(
                    destination: destination, source: source, for: target
                )
            }
            await #expect(throws: CancellationError.self) { _ = try await cancelled.value }

            try Data("invalid image after indexing".utf8).write(to: original)
            await #expect(throws: DocumentExportImageError.self) {
                _ = try await handle.documents.prepareSourceImagePreview(
                    destination: destination, source: source, for: target
                )
            }
            try Self.png.write(to: original)
            let restored = try await handle.documents.prepareSourceImagePreview(
                destination: destination, source: source, for: target
            )
            await handle.documents.releaseDocumentAttachmentPreview(accessToken: restored.accessToken)
            try FileManager.default.moveItem(at: original, to: original.deletingLastPathComponent().appendingPathComponent("Moved.png"))
            await #expect(throws: (any Error).self) {
                _ = try await handle.documents.prepareSourceImagePreview(
                    destination: destination, source: source, for: target
                )
            }
        }
    }

    private func withFixture(
        _ operation: (ApplicationFixture, WorkspaceHandle, SourceAttachmentTarget) async throws -> Void
    ) async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try await ApplicationFixture.make(
            rootURL: repositoryRoot.appendingPathComponent(".build/source-image-preview-tests/\(UUID().uuidString)")
        )
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(
            configuration: .live(
                .init(
                    applicationSupportURL: fixture.applicationSupportURL,
                    workspaceRegistryStorageURL: fixture.registryStorageURL
                )))
        do {
            let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
            let summary = try #require(try await handle.snapshot().document(id: fixture.analysisNoteID))
            let target = SourceAttachmentTarget(
                noteID: try #require(summary.stableIdentity.resolvedID),
                vaultID: fixture.analysisNoteID.vaultID, relativePath: fixture.analysisNoteID.relativePath
            )
            try await operation(fixture, handle, target)
        } catch {
            await runtime.shutdown()
            throw error
        }
        await runtime.shutdown()
    }
}
