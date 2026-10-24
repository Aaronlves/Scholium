import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Single Note export image resolution")
struct ExportImageResolutionTests {
    private static let png = Data(
        base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    @Test("Vault-contained image is embedded; unregistered absolute image is refused")
    func localAuthorization() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let image = fixture.analysesURL.appendingPathComponent("Figure one.png")
        try Self.png.write(to: image)
        let external = fixture.rootURL.appendingPathComponent("Unregistered.png")
        try Self.png.write(to: external)
        let runtime = WorkspaceRuntime(
            configuration: .live(
                .init(
                    applicationSupportURL: fixture.applicationSupportURL,
                    workspaceRegistryStorageURL: fixture.registryStorageURL
                )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)

        let embedded = try await handle.documents.exportImages(
            for: fixture.analysisNoteID,
            markdownSource: "![Figure](Figure%20one.png)"
        )
        #expect(embedded["Figure one.png"]?.data == Self.png)
        #expect(embedded["Figure one.png"]?.mimeType == "image/png")

        let unavailable = try await handle.documents.exportImages(
            for: fixture.analysisNoteID,
            markdownSource: "![Unregistered](\(external.path))"
        )
        #expect(unavailable[external.path] == nil)

        _ = try await handle.documents.indexImageAttachment(
            at: external, for: fixture.analysisNoteID
        )
        let indexed = try await handle.documents.exportImages(
            for: fixture.analysisNoteID,
            markdownSource: "![Registered](\(external.path))"
        )
        #expect(indexed[external.path]?.data == Self.png)
        await runtime.shutdown()
    }

    @Test("Oversized dimensions and invalid image bytes are rejected")
    func imageValidation() throws {
        #expect(
            try ExportImageDataValidator.validate(Self.png, destination: "image.png").data == Self.png)
        #expect(throws: DocumentExportImageError.self) {
            _ = try ExportImageDataValidator.validate(Data("not an image".utf8), destination: "image.png")
        }
    }

    @Test("Reference-style and footnote images resolve; a missing peer remains for format validation")
    func nestedImagePreparation() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        try Self.png.write(to: fixture.analysesURL.appendingPathComponent("Chart one.png"))
        try Self.png.write(to: fixture.analysesURL.appendingPathComponent("Inset.png"))
        let runtime = WorkspaceRuntime(
            configuration: .live(
                .init(
                    applicationSupportURL: fixture.applicationSupportURL,
                    workspaceRegistryStorageURL: fixture.registryStorageURL
                )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)

        let images = try await handle.documents.exportImages(
            for: fixture.analysisNoteID,
            markdownSource: """
                ![Chart][figure]

                [figure]: Chart%20one.png

                A note.[^detail]

                [^detail]: ![Inset](Inset.png) ![Missing](Missing.png)
                """
        )
        #expect(images["Chart one.png"]?.data == Self.png)
        #expect(images["Inset.png"]?.data == Self.png)
        #expect(images["Missing.png"] == nil)
        await runtime.shutdown()
    }

    @Test("A retained draft resolves its available images after external Note deletion without recreating source", arguments: [false, true])
    func retainedDraftAfterDeletion(includesImages: Bool) async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(
            configuration: .live(
                .init(
                    applicationSupportURL: fixture.applicationSupportURL,
                    workspaceRegistryStorageURL: fixture.registryStorageURL)))
        do {
            let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
            let image = fixture.analysesURL.appendingPathComponent("Retained image.png")
            try Self.png.write(to: image)
            let external = fixture.rootURL.appendingPathComponent("Unregistered.png")
            try Self.png.write(to: external)
            let source =
                "\u{FEFF}---\r\ncustom: 'keep' # unchanged\r\n---\r\nDraft 中文 e\u{301} 🦉 without final newline"
                + (includesImages ? "\r\n![Retained](Retained%20image.png)\r\n![Missing](Missing.png)\r\n![Unregistered](\(external.path))" : "")
            let original = fixture.analysesURL.appendingPathComponent(fixture.analysisNoteID.relativePath)
            try FileManager.default.removeItem(at: original)

            for _ in 0..<2 {
                let images = try await handle.documents.exportImages(for: fixture.analysisNoteID, markdownSource: source)
                #expect(images["Retained image.png"]?.data == (includesImages ? Self.png : nil))
                #expect(images["Missing.png"] == nil)
                #expect(images[external.path] == nil)
                #expect(!FileManager.default.fileExists(atPath: original.path))
                #expect(try Data(contentsOf: image) == Self.png)
                #expect(try Data(contentsOf: external) == Self.png)
            }
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
    }

    @Test("Retained-source export refuses unsafe origins and a replaced vault root")
    func retainedSourceDoesNotBroadenAuthorization() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(
            configuration: .live(
                .init(
                    applicationSupportURL: fixture.applicationSupportURL,
                    workspaceRegistryStorageURL: fixture.registryStorageURL)))
        do {
            let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
            for path in ["../Outside.md", "/Outside.md", "NotMarkdown.txt"] {
                await #expect(throws: (any Error).self) {
                    _ = try await handle.documents.exportImages(
                        for: .init(vaultID: fixture.analysisNoteID.vaultID, relativePath: path), markdownSource: "Retained")
                }
            }
            let sourceURL = fixture.analysesURL.appendingPathComponent(fixture.analysisNoteID.relativePath)
            let original = try Data(contentsOf: sourceURL)
            try FileManager.default.removeItem(at: sourceURL)
            try FileManager.default.createSymbolicLink(at: sourceURL, withDestinationURL: fixture.topicsURL.appendingPathComponent("Freedom.md"))
            await #expect(throws: (any Error).self) {
                _ = try await handle.documents.exportImages(for: fixture.analysisNoteID, markdownSource: "Retained")
            }
            try FileManager.default.removeItem(at: sourceURL)
            try original.write(to: sourceURL)
            let moved = fixture.rootURL.appendingPathComponent("Original Analyses")
            try FileManager.default.moveItem(at: fixture.analysesURL, to: moved)
            try FileManager.default.createDirectory(at: fixture.analysesURL, withIntermediateDirectories: false)
            try Data("Unrelated replacement".utf8).write(to: sourceURL)
            await #expect(throws: (any Error).self) {
                _ = try await handle.documents.exportImages(for: fixture.analysisNoteID, markdownSource: "Retained")
            }
            #expect(try Data(contentsOf: moved.appendingPathComponent(fixture.analysisNoteID.relativePath)) == original)
            #expect(try Data(contentsOf: sourceURL) == Data("Unrelated replacement".utf8))
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
    }

    @Test("A canceled retained-source export cannot finish a no-image preparation")
    func canceledRetainedSourceExport() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(
            configuration: .live(
                .init(
                    applicationSupportURL: fixture.applicationSupportURL,
                    workspaceRegistryStorageURL: fixture.registryStorageURL)))
        do {
            let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await handle.documents.exportImages(for: fixture.analysisNoteID, markdownSource: "Retained plain text")
            }
            await #expect(throws: CancellationError.self) { _ = try await task.value }
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
    }
}
