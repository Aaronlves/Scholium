import Darwin
import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@Suite("External Markdown original files")
struct ExternalMarkdownFileStoreTests {
    private func fixture() throws -> URL {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/external-markdown-fixtures/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("A Markdown original round-trips BOM, CRLF, and a source-only edit")
    func exactSourceAndSave() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Research.markdown")
        let original = Data("\u{FEFF}---\r\ntitle: 'Quoted'\r\n---\r\n\r\n中文 😀\r\n".utf8)
        try original.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: file.path)
        let metadataName = "com.scholium.test.external-markdown"
        let metadata = Data("retained".utf8)
        let metadataWritten = metadata.withUnsafeBytes { raw in
            setxattr(file.path, metadataName, raw.baseAddress, raw.count, 0, 0)
        }
        #expect(metadataWritten == 0)

        let (session, opened) = try ExternalMarkdownFileSession.open(file)
        #expect(Data(opened.source.utf8) == original)
        #expect(opened.fingerprint == DocumentFingerprint(data: original))
        let edited = opened.source + "Another line\r\n"
        let saved = try await session.save(candidate: edited, expected: opened)
        #expect(saved.source == edited)
        #expect(saved.fingerprint == DocumentFingerprint(content: edited))
        #expect(saved.identity != opened.identity)
        #expect(try Data(contentsOf: file) == Data(edited.utf8))
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o640)
        var metadataRead = [UInt8](repeating: 0, count: metadata.count)
        let metadataCount = metadataRead.withUnsafeMutableBytes { raw in
            getxattr(file.path, metadataName, raw.baseAddress, raw.count, 0, 0)
        }
        #expect(metadataCount == metadata.count)
        #expect(Data(metadataRead) == metadata)
        let reread = try await session.load()
        #expect(reread.fingerprint == saved.fingerprint)
        await session.close()
        await #expect(throws: ExternalMarkdownFileError.closed) { try await session.load() }
    }

    @Test("A concurrent edit and same-byte path replacement both reject a stale save")
    func changedOriginalIsNeverOverwritten() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("source.md")
        try Data("A\n".utf8).write(to: file)
        let (session, original) = try ExternalMarkdownFileSession.open(file)
        let external = Data("B\n".utf8)
        try external.write(to: file)
        await #expect(throws: ExternalMarkdownFileError.changed) {
            try await session.save(candidate: "C\n", expected: original)
        }
        #expect(try Data(contentsOf: file) == external)
        let updated = try await session.load()
        #expect(updated.source == "B\n")

        let replacement = root.appendingPathComponent("replacement.md")
        try external.write(to: replacement)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: replacement, to: file)
        await #expect(throws: ExternalMarkdownFileError.changed) {
            try await session.save(candidate: "C\n", expected: updated)
        }
        #expect(try Data(contentsOf: file) == external)
        await #expect(throws: ExternalMarkdownFileError.changed) { try await session.load() }
        await session.close()
    }

    @Test("Only valid, bounded UTF-8 regular Markdown files can open")
    func unsuitableOriginals() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let wrongType = root.appendingPathComponent("notes.txt")
        try Data("Text".utf8).write(to: wrongType)
        #expect(throws: ExternalMarkdownFileError.unsupportedType) {
            try ExternalMarkdownFileSession.open(wrongType)
        }
        let invalid = root.appendingPathComponent("invalid.md")
        try Data([0xFF]).write(to: invalid)
        #expect(throws: ExternalMarkdownFileError.invalidUTF8) {
            try ExternalMarkdownFileSession.open(invalid)
        }
        let oversized = root.appendingPathComponent("oversized.md")
        try Data(repeating: 0x61, count: ExternalMarkdownFileSession.maximumBytes + 1).write(to: oversized)
        #expect(throws: ExternalMarkdownFileError.tooLarge) {
            try ExternalMarkdownFileSession.open(oversized)
        }
        let symlink = root.appendingPathComponent("linked.md")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: wrongType)
        #expect(throws: ExternalMarkdownFileError.notRegularFile) {
            try ExternalMarkdownFileSession.open(symlink)
        }
    }
}
