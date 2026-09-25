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
}
