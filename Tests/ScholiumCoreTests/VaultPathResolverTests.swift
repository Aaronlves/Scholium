import Foundation
import Testing
@testable import ScholiumContracts
@testable import ScholiumCore

@Suite("Vault path resolver")
struct VaultPathResolverTests {
    @Test("Case and canonical-equivalence collisions fail closed")
    func collisionDetection() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Scholium-PathResolver-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("existing".utf8).write(to: root.appendingPathComponent("CAFÉ.md"))
        let resolver = VaultPathResolver(
            rootURL: root,
            caseSensitive: false,
            normalizationSensitive: false
        )

        #expect(throws: VaultRepositoryError.self) {
            try resolver.validateNoCollision(for: MarkdownRelativePath("cafe\u{301}.md"))
        }
    }

    @Test("Backslash does not become a directory separator")
    func backslashLiteral() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Scholium-PathResolver-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let resolver = VaultPathResolver(
            rootURL: root,
            caseSensitive: true,
            normalizationSensitive: true
        )
        let candidate = try resolver.unresolvedURL(for: MarkdownRelativePath(#"Folder\Note.md"#))
        #expect(candidate.deletingLastPathComponent() == root.standardizedFileURL)
        #expect(candidate.lastPathComponent == #"Folder\Note.md"#)
    }
}
