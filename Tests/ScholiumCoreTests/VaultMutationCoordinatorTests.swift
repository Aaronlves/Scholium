import Foundation
import Testing
@testable import ScholiumContracts
@testable import ScholiumCore

@Suite("Vault mutation coordinator")
struct VaultMutationCoordinatorTests {
    @Test("An external writer before final authorization causes a conflict")
    func writerBeforeFinalCheck() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let external = Data("external".utf8)
        let coordinator = VaultMutationCoordinator(
            resolver: fixture.resolver,
            hooks: VaultMutationHooks(didReach: { phase in
                if phase == .staged { try external.write(to: fixture.note, options: .atomic) }
            })
        )

        #expect(throws: VaultRepositoryError.self) {
            try coordinator.updateExisting(
                path: fixture.path,
                expected: fixture.original,
                candidate: fixture.candidate
            )
        }
        #expect(try Data(contentsOf: fixture.note) == external)
    }

    @Test("A writer between final check and swap is restored and reported uncertain")
    func writerAtSwapBoundary() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let external = Data("external-at-swap".utf8)
        let coordinator = VaultMutationCoordinator(
            resolver: fixture.resolver,
            hooks: VaultMutationHooks(didReach: { phase in
                if phase == .finalCheck { try external.write(to: fixture.note, options: .atomic) }
            })
        )

        do {
            try coordinator.updateExisting(
                path: fixture.path,
                expected: fixture.original,
                candidate: fixture.candidate
            )
            Issue.record("The raced swap was incorrectly reported as saved")
        } catch VaultRepositoryError.commitUncertain {
            // Required outcome.
        } catch {
            Issue.record("Unexpected raced-swap error: \(error)")
        }
        #expect(try Data(contentsOf: fixture.note) == external)
        #expect(try fixture.stagedFiles().contains(where: { try Data(contentsOf: $0) == fixture.candidate }))
    }

    @Test("Delete and recreate at the swap boundary never reports Saved")
    func deleteRecreateAtBoundary() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let recreated = Data("recreated".utf8)
        let coordinator = VaultMutationCoordinator(
            resolver: fixture.resolver,
            hooks: VaultMutationHooks(didReach: { phase in
                guard phase == .finalCheck else { return }
                try FileManager.default.removeItem(at: fixture.note)
                try recreated.write(to: fixture.note)
            })
        )

        #expect(throws: VaultRepositoryError.self) {
            try coordinator.updateExisting(
                path: fixture.path,
                expected: fixture.original,
                candidate: fixture.candidate
            )
        }
        #expect(try Data(contentsOf: fixture.note) == recreated)
    }

    @Test("A symlink substitution cannot escape the descriptor-relative commit")
    func symlinkSubstitution() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = fixture.root.deletingLastPathComponent()
            .appendingPathComponent("outside-\(UUID().uuidString).md")
        try Data("outside".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let coordinator = VaultMutationCoordinator(
            resolver: fixture.resolver,
            hooks: VaultMutationHooks(didReach: { phase in
                guard phase == .finalCheck else { return }
                try FileManager.default.removeItem(at: fixture.note)
                try FileManager.default.createSymbolicLink(at: fixture.note, withDestinationURL: outside)
            })
        )

        #expect(throws: VaultRepositoryError.self) {
            try coordinator.updateExisting(
                path: fixture.path,
                expected: fixture.original,
                candidate: fixture.candidate
            )
        }
        #expect(try Data(contentsOf: outside) == Data("outside".utf8))
    }

    @Test("A permission change after swap is uncertain and restores the preimage")
    func permissionChangeAfterSwap() throws {
        let fixture = try Fixture()
        defer {
            for staged in (try? fixture.stagedFiles()) ?? [] {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: staged.path
                )
            }
            fixture.remove()
        }
        let coordinator = VaultMutationCoordinator(
            resolver: fixture.resolver,
            hooks: VaultMutationHooks(didReach: { phase in
                if phase == .swapped {
                    try FileManager.default.setAttributes(
                        [.posixPermissions: 0o000],
                        ofItemAtPath: fixture.note.path
                    )
                }
            })
        )

        #expect(throws: VaultRepositoryError.self) {
            try coordinator.updateExisting(
                path: fixture.path,
                expected: fixture.original,
                candidate: fixture.candidate
            )
        }
        #expect(try Data(contentsOf: fixture.note) == fixture.original)
    }

    @Test("An external replacement before readback is never reported saved")
    func externalReplacementBeforeReadback() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let external = Data("external-readback".utf8)
        let coordinator = VaultMutationCoordinator(
            resolver: fixture.resolver,
            hooks: VaultMutationHooks(didReach: { phase in
                if phase == .readback {
                    try external.write(to: fixture.note, options: .atomic)
                }
            })
        )

        do {
            try coordinator.updateExisting(
                path: fixture.path,
                expected: fixture.original,
                candidate: fixture.candidate
            )
            Issue.record("The replaced readback was incorrectly reported as saved")
        } catch VaultRepositoryError.commitUncertain {
            // Required outcome.
        } catch {
            Issue.record("Unexpected readback error: \(error)")
        }
        #expect(try Data(contentsOf: fixture.note) == external)
        #expect(!(try fixture.stagedFiles()).isEmpty)
    }

    @Test("Successful create, move, update, and delete preserve exact bytes")
    func successfulOperations() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let coordinator = VaultMutationCoordinator(resolver: fixture.resolver)
        try coordinator.updateExisting(
            path: fixture.path,
            expected: fixture.original,
            candidate: fixture.candidate
        )
        #expect(try Data(contentsOf: fixture.note) == fixture.candidate)

        let createdPath = try MarkdownRelativePath("Created.md")
        try coordinator.create(path: createdPath, data: fixture.original)
        let movedPath = try MarkdownRelativePath("Moved.md")
        try coordinator.move(source: createdPath, destination: movedPath, expected: fixture.original)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Created.md").path))
        #expect(try Data(contentsOf: fixture.root.appendingPathComponent("Moved.md")) == fixture.original)
        try coordinator.delete(path: movedPath, expected: fixture.original)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Moved.md").path))
    }

    private final class Fixture {
        let root: URL
        let note: URL
        let path: MarkdownRelativePath
        let resolver: VaultPathResolver
        let original = Data([0xEF, 0xBB, 0xBF] + Array("# 原始\r\n".utf8))
        let candidate = Data([0xEF, 0xBB, 0xBF] + Array("# 候选\r\n".utf8))

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("Scholium-Mutation-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            note = root.appendingPathComponent("Note.md")
            try original.write(to: note)
            path = try MarkdownRelativePath("Note.md")
            resolver = VaultPathResolver(
                rootURL: root,
                caseSensitive: true,
                normalizationSensitive: true
            )
        }

        func stagedFiles() throws -> [URL] {
            try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix(".scholium-swap-") }
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
