import Foundation
import Testing
@testable import ScholiumCore

@Suite("Indexed attachment access")
struct IndexedAttachmentAccessStoreTests {
    @Test("Absolute-path access becomes unavailable instead of following a moved file")
    func movedIndexedFileIsUnavailable() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let selected = fixture.root.appendingPathComponent("Figure.png")
        try Self.png.write(to: selected, options: .withoutOverwriting)
        let store = try IndexedAttachmentAccessStore(
            applicationSupportURL: fixture.support,
            triptychID: fixture.triptychID
        )
        let attachmentID = UUID()

        #expect(try await store.register(
            attachmentID: attachmentID,
            selectedURL: selected,
            expectedAbsolutePath: selected.path
        ))
        #expect(try await store.isAvailable(
            attachmentID: attachmentID,
            expectedAbsolutePath: selected.path
        ))
        let access = try await store.beginAccess(
            attachmentID: attachmentID,
            expectedAbsolutePath: selected.path
        )
        #expect(access.url.resolvingSymlinksInPath().standardizedFileURL.path
            == selected.path)
        await store.endAccess(access.token)

        let moved = fixture.root.appendingPathComponent("Moved.png")
        try FileManager.default.moveItem(at: selected, to: moved)
        #expect(try await store.isAvailable(
            attachmentID: attachmentID,
            expectedAbsolutePath: selected.path
        ) == false)

        try await store.removeIfPresent(attachmentID: attachmentID)
        #expect(try await store.isAvailable(
            attachmentID: attachmentID,
            expectedAbsolutePath: selected.path
        ) == false)
        #expect(FileManager.default.fileExists(atPath: moved.path))
    }

    private static let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    private struct Fixture {
        let root: URL
        let support: URL
        let triptychID = UUID()

        init() throws {
            let repositoryRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            root = repositoryRoot
                .appendingPathComponent(".build/indexed-attachment-access-tests")
                .appendingPathComponent(UUID().uuidString.lowercased())
            support = root.appendingPathComponent("Support", isDirectory: true)
            try FileManager.default.createDirectory(
                at: support,
                withIntermediateDirectories: true
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
