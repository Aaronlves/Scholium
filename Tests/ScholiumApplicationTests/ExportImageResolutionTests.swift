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

        await #expect(throws: DocumentExportImageError.self) {
            _ = try await handle.documents.exportImages(
                for: fixture.analysisNoteID,
                markdownSource: "![Unregistered](\(external.path))"
            )
        }

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
        #expect(try ExportImageDataValidator.validate(Self.png, destination: "image.png").data == Self.png)
        #expect(throws: DocumentExportImageError.self) {
            _ = try ExportImageDataValidator.validate(Data("not an image".utf8), destination: "image.png")
        }
    }
}
