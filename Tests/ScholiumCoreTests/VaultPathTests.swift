import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Vault-relative path normalization")
struct VaultPathTests {
    @Test("Equivalent tmp spellings preserve the complete relative path")
    func tmpAlias() throws {
        let root = URL(
            fileURLWithPath: "/tmp/Scholium-VaultPathTests-\(UUID().uuidString)/03-works",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let critiques = root.appendingPathComponent("Critiques", isDirectory: true)
        try FileManager.default.createDirectory(at: critiques, withIntermediateDirectories: true)
        let file = critiques.appendingPathComponent("QA Critique.md")
        try Data("# Critique\n".utf8).write(to: file)

        let enumerator = try #require(FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        ))
        let enumeratedFile = try #require(enumerator.allObjects
            .compactMap { $0 as? URL }
            .first { $0.lastPathComponent == file.lastPathComponent })

        #expect(
            VaultPath.relativePath(for: enumeratedFile, in: root)
                == "Critiques/QA Critique.md"
        )
    }

    @Test("Root and outside paths are not vault-relative files")
    func containment() {
        let root = URL(fileURLWithPath: "/tmp/Scholium-VaultPathTests/root", isDirectory: true)
        let outside = URL(fileURLWithPath: "/tmp/Scholium-VaultPathTests/peer.md")

        #expect(VaultPath.relativePath(for: root, in: root) == nil)
        #expect(VaultPath.relativePath(for: outside, in: root) == nil)
    }
}
