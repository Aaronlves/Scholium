import Darwin
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

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

    @Test("A replaced staging name cannot displace the original or delete the peer entry")
    func substitutedStageIsRestored() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("source.md")
        let peer = root.appendingPathComponent("peer.md")
        let original = Data("Original source\n".utf8)
        let peerBytes = Data("Peer source\n".utf8)
        try original.write(to: file)
        try peerBytes.write(to: peer)
        let (session, opened) = try ExternalMarkdownFileSession.open(file)
        await session.installBeforeSwapTestHook { stagingURL in
            _ = Darwin.unlink(stagingURL.path)
            _ = Darwin.symlink(peer.path, stagingURL.path)
        }

        await #expect(throws: ExternalMarkdownFileError.changed) {
            try await session.save(candidate: "Edited source\n", expected: opened)
        }
        #expect(try Data(contentsOf: file) == original)
        #expect(try Data(contentsOf: peer) == peerBytes)
        let stagedEntries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".source.md-scholium-") }
        #expect(stagedEntries.count == 1)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: stagedEntries[0].path) == peer.path)
        #expect(try await session.load().source == opened.source)
        await session.close()
    }

    @Test("Rollback does not hide a newer external file")
    func newerFileBeforeRollbackIsPreserved() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("source.md")
        let peer = root.appendingPathComponent("peer.md")
        let replacement = root.appendingPathComponent("new.md")
        let original = Data("Original source\n".utf8)
        let newer = Data("Newer external source\n".utf8)
        try original.write(to: file)
        try Data("Peer source\n".utf8).write(to: peer)
        try newer.write(to: replacement)
        let (session, opened) = try ExternalMarkdownFileSession.open(file)
        await session.installBeforeSwapTestHook { stagingURL in
            _ = Darwin.unlink(stagingURL.path)
            _ = Darwin.symlink(peer.path, stagingURL.path)
        }
        await session.installBeforeRollbackTestHook { originalURL in
            _ = Darwin.unlink(originalURL.path)
            _ = Darwin.rename(replacement.path, originalURL.path)
        }

        await #expect(throws: ExternalMarkdownFileError.commitUncertain) {
            try await session.save(candidate: "Edited source\n", expected: opened)
        }
        #expect(try Data(contentsOf: file) == newer)
        let stagedEntries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".source.md-scholium-") }
        #expect(stagedEntries.count == 1)
        #expect(try Data(contentsOf: stagedEntries[0]) == original)
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
