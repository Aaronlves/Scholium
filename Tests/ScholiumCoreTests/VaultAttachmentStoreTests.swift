import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumCore

@Suite("Vault image attachments")
struct VaultAttachmentStoreTests {
    @Test("External images copy exactly and rollback only the unchanged import")
    func externalImageCopyAndRollback() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let attachmentID = UUID()
        let source = fixture.root.appendingPathComponent("Figure one.png")
        try Self.png.write(to: source, options: .withoutOverwriting)
        let store = VaultAttachmentStore(vaultURL: fixture.vault)

        let prepared = try await store.prepareImage(
            at: source,
            attachmentID: attachmentID,
            noteRelativePath: "Notes/Claim.md",
            management: .importIntoAttachments
        )

        let copiedPath = try #require(prepared.copiedRelativePath)
        #expect(copiedPath.rawValue
            == "Attachments/\(attachmentID.uuidString.lowercased())/Figure one.png")
        #expect(prepared.markdownDestination
            == "../Attachments/\(attachmentID.uuidString.lowercased())/Figure%20one.png")
        #expect(prepared.altText == "Figure one")
        let fingerprint = try #require(prepared.copiedFileFingerprint)
        let copied = fixture.vault.appendingPathComponent(copiedPath.rawValue)
        #expect(try Data(contentsOf: copied) == Self.png)

        try await store.removeCopiedImageIfExact(
            relativePath: copiedPath,
            expectedFingerprint: fingerprint
        )
        #expect(!FileManager.default.fileExists(atPath: copied.path))
    }

    @Test("Indexed images use absolute paths without copying or deletion authority")
    func indexedImage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let image = fixture.vault.appendingPathComponent("Figures/Diagram.png")
        try FileManager.default.createDirectory(
            at: image.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.png.write(to: image, options: .withoutOverwriting)
        let store = VaultAttachmentStore(vaultURL: fixture.vault)

        let prepared = try await store.prepareImage(
            at: image,
            attachmentID: UUID(),
            noteRelativePath: "Notes/Claim.md",
            management: .indexAbsolutePath
        )

        #expect(prepared.location == .absolutePath(image.path))
        #expect(prepared.markdownDestination == image.path)
        #expect(prepared.copiedFileFingerprint == nil)
        #expect(prepared.copiedRelativePath == nil)
        #expect(FileManager.default.fileExists(atPath: image.path))
    }

    @Test("Pasted bytes and pasted vault files always import into Attachments")
    func pastedImagesImport() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = VaultAttachmentStore(vaultURL: fixture.vault)
        let existing = fixture.vault.appendingPathComponent("Figures/Existing.png")
        try FileManager.default.createDirectory(
            at: existing.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.png.write(to: existing, options: .withoutOverwriting)

        let fileImport = try await store.prepareImage(
            at: existing,
            attachmentID: UUID(),
            noteRelativePath: "Claim.md",
            management: .importIntoAttachments
        )
        let dataImport = try await store.preparePastedImage(
            data: Self.png,
            preferredFilename: "Pasted Figure.png",
            attachmentID: UUID(),
            noteRelativePath: "Claim.md"
        )

        let filePath = try #require(fileImport.copiedRelativePath)
        let dataPath = try #require(dataImport.copiedRelativePath)
        #expect(filePath.rawValue.hasPrefix("Attachments/"))
        #expect(dataPath.rawValue.hasPrefix("Attachments/"))
        #expect(dataPath.rawValue.hasSuffix("/Pasted Figure.png"))
        #expect(fileImport.copiedFileFingerprint != nil)
        #expect(dataImport.copiedFileFingerprint != nil)
        #expect(try Data(contentsOf: fixture.vault.appendingPathComponent(
            dataPath.rawValue
        )) == Self.png)
        #expect(try Data(contentsOf: existing) == Self.png)
    }

    @Test("Rollback refuses a copied file whose bytes changed externally")
    func changedCopyIsPreserved() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("Figure.png")
        try Self.png.write(to: source, options: .withoutOverwriting)
        let store = VaultAttachmentStore(vaultURL: fixture.vault)
        let prepared = try await store.prepareImage(
            at: source,
            attachmentID: UUID(),
            noteRelativePath: "Claim.md",
            management: .importIntoAttachments
        )
        let fingerprint = try #require(prepared.copiedFileFingerprint)
        let copiedPath = try #require(prepared.copiedRelativePath)
        let copied = fixture.vault.appendingPathComponent(copiedPath.rawValue)
        try Data("externally changed".utf8).write(to: copied)

        await #expect(throws: ImageAttachmentError.self) {
            try await store.removeCopiedImageIfExact(
                relativePath: copiedPath,
                expectedFingerprint: fingerprint
            )
        }
        #expect(try Data(contentsOf: copied) == Data("externally changed".utf8))
    }

    private static let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    private struct Fixture {
        let root: URL
        let vault: URL

        init() throws {
            let repositoryRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            root = repositoryRoot
                .appendingPathComponent(".build/attachment-store-tests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
            vault = root.appendingPathComponent("Works", isDirectory: true)
            try FileManager.default.createDirectory(
                at: vault,
                withIntermediateDirectories: true
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
