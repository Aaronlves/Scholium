import Darwin
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Bounded vault source reads")
struct VaultBoundedReadTests {
    @Test("The Note limit accepts exact bytes; one extra byte is typed and never written")
    func noteBoundaryAndPreservation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let atLimit = Data(repeating: 0x20, count: VaultSourceReadLimits.maximumNoteByteCount)
        try atLimit.write(to: fixture.note)
        let loaded = try await fixture.repository.load(relativePath: "Note.md")
        #expect(loaded.sourceBytes == atLimit)

        var oversized = atLimit
        oversized.append(0x20)
        try oversized.write(to: fixture.note)
        await #expect {
            try await fixture.repository.load(relativePath: "Note.md")
        } throws: { Self.isTooLarge($0, path: "Note.md") }
        #expect(try Data(contentsOf: fixture.note) == oversized)
        #expect(try await fixture.repository.markdownRelativePaths() == ["Note.md"])
    }

    @Test("Growing an admitted descriptor stops at the byte allowance")
    func descriptorGrowth() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data([0x41]).write(to: fixture.note)
        let descriptor = Darwin.open(fixture.note.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        #expect(descriptor >= 0)
        defer { Darwin.close(descriptor) }
        #expect {
            try VaultDescriptorAccess.readAll(
                from: descriptor, maximumByteCount: 1,
                afterChunkForTesting: { count in
                    #expect(count == 1)
                    let writer = try FileHandle(forWritingTo: fixture.note)
                    defer { try? writer.close() }
                    try writer.seekToEnd()
                    try writer.write(contentsOf: Data([0x42]))
                }
            )
        } throws: { ($0 as? CocoaError)?.code == .fileReadTooLarge }
        #expect(try Data(contentsOf: fixture.note) == Data([0x41, 0x42]))
    }

    @Test("Oversized save, create, and import candidates cannot leave unreadable source")
    func oversizedWritesHaveNoEffects() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = Data("Original\r\n".utf8)
        try original.write(to: fixture.note)
        let document = try await fixture.repository.load(relativePath: "Note.md")
        let oversized = Data(repeating: 0x20, count: VaultSourceReadLimits.maximumNoteByteCount + 1)
        let source = String(decoding: oversized, as: UTF8.self)
        await #expect {
            try await fixture.repository.saveOutcome(
                relativePath: "Note.md", changeSet: .exactContent(source), expectedRevision: document.fingerprint
            )
        } throws: { Self.isTooLarge($0, path: "Note.md") }
        await #expect {
            try await fixture.repository.create(relativePath: "New.md", content: source)
        } throws: { Self.isTooLarge($0, path: "New.md") }
        await #expect {
            try await fixture.repository.importMarkdown(preferredFilename: "Imported.md", sourceData: oversized)
        } throws: { Self.isTooLarge($0, path: "Imported.md") }
        #expect(try Data(contentsOf: fixture.note) == original)
        #expect(try await fixture.repository.markdownRelativePaths() == ["Note.md"])
        #expect(try await fixture.repository.interruptedSaveRecoveries().isEmpty)
    }

    private static func isTooLarge(_ error: any Error, path: String) -> Bool {
        guard let repositoryError = error as? VaultRepositoryError,
            case .sourceTooLarge(let relativePath, let maximumByteCount) = repositoryError
        else {
            return false
        }
        return relativePath == path && maximumByteCount == VaultSourceReadLimits.maximumNoteByteCount
    }

    private struct Fixture {
        let root: URL
        let note: URL
        let repository: VaultRepository

        init() throws {
            root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(".build/security-hardening/read-fixtures/\(UUID())", isDirectory: true)
            let vault = root.appendingPathComponent("Vault", isDirectory: true)
            try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
            note = vault.appendingPathComponent("Note.md")
            repository = try VaultRepository(
                vaultURL: vault,
                identity: VaultIdentity(id: UUID(), canonicalPath: vault.path, bookmarkData: nil),
                applicationSupportURL: root.appendingPathComponent("Support", isDirectory: true)
            )
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
