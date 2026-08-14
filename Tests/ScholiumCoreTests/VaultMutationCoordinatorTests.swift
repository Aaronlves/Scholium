import Darwin
import Foundation
import Testing
@testable import ScholiumContracts
@testable import ScholiumCore

@Suite("Vault mutation coordinator")
struct VaultMutationCoordinatorTests {
    private struct InjectedFailure: Error {}

    @Test("An existing note uses coordinated system replacement and exact readback")
    func successfulExistingUpdate() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        try VaultMutationCoordinator(resolver: fixture.resolver).updateExisting(
            path: fixture.path,
            expected: fixture.original,
            candidate: fixture.candidate
        )

        #expect(try Data(contentsOf: fixture.note) == fixture.candidate)
        #expect(try fixture.replacementFiles().isEmpty)
    }

    @Test("Failures before replacement preserve the source and remove the candidate")
    func failureBeforeReplacement() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let coordinator = VaultMutationCoordinator(
            resolver: fixture.resolver,
            hooks: VaultMutationHooks(didReach: { phase in
                if phase == .replacing { throw InjectedFailure() }
            })
        )

        #expect(throws: InjectedFailure.self) {
            try coordinator.updateExisting(
                path: fixture.path,
                expected: fixture.original,
                candidate: fixture.candidate
            )
        }
        #expect(try Data(contentsOf: fixture.note) == fixture.original)
        #expect(try fixture.replacementFiles().isEmpty)
    }

    @Test("A failure after replacement does not perform a second source mutation")
    func failureAfterReplacement() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let coordinator = VaultMutationCoordinator(
            resolver: fixture.resolver,
            hooks: VaultMutationHooks(didReach: { phase in
                if phase == .replaced { throw InjectedFailure() }
            })
        )

        #expect(throws: InjectedFailure.self) {
            try coordinator.updateExisting(
                path: fixture.path,
                expected: fixture.original,
                candidate: fixture.candidate
            )
        }
        #expect(try Data(contentsOf: fixture.note) == fixture.candidate)
        #expect(try fixture.replacementFiles().isEmpty)
    }

    @Test("An external writer before final authorization causes a conflict")
    func writerBeforeFinalCheck() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let external = Data("external".utf8)
        let coordinator = VaultMutationCoordinator(
            resolver: fixture.resolver,
            hooks: VaultMutationHooks(didReach: { phase in
                if phase == .staged {
                    try external.write(to: fixture.note, options: .atomic)
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
        #expect(try Data(contentsOf: fixture.note) == external)
        #expect(try fixture.replacementFiles().isEmpty)
    }

    @Test("A symlink substitution cannot escape the vault")
    func symlinkSubstitution() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = fixture.root.deletingLastPathComponent()
            .appendingPathComponent("outside-\(UUID().uuidString).md")
        let outsideBytes = Data("outside".utf8)
        try outsideBytes.write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let coordinator = VaultMutationCoordinator(
            resolver: fixture.resolver,
            hooks: VaultMutationHooks(didReach: { phase in
                guard phase == .staged else { return }
                try FileManager.default.removeItem(at: fixture.note)
                try FileManager.default.createSymbolicLink(
                    at: fixture.note,
                    withDestinationURL: outside
                )
            })
        )

        #expect(throws: (any Error).self) {
            try coordinator.updateExisting(
                path: fixture.path,
                expected: fixture.original,
                candidate: fixture.candidate
            )
        }
        #expect(try Data(contentsOf: outside) == outsideBytes)
        #expect(try fixture.replacementFiles().isEmpty)
    }

    @Test("A parent-directory exchange cannot retarget the replacement")
    func parentSymlinkExchange() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let base = repositoryRoot
            .appendingPathComponent(".build/vault-parent-races", isDirectory: true)
            .appendingPathComponent(String(UUID().uuidString.prefix(12)).lowercased(), isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("Vault", isDirectory: true)
        let parent = root.appendingPathComponent("Folder", isDirectory: true)
        let detached = root.appendingPathComponent("Detached", isDirectory: true)
        let outside = base.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let original = Data("authorized original".utf8)
        let candidate = Data("candidate".utf8)
        let outsideBytes = Data("outside sentinel".utf8)
        try original.write(to: parent.appendingPathComponent("Note.md"))
        try outsideBytes.write(to: outside.appendingPathComponent("Note.md"))
        let path = try MarkdownRelativePath("Folder/Note.md")
        let coordinator = VaultMutationCoordinator(
            resolver: VaultPathResolver(
                rootURL: root,
                caseSensitive: true,
                normalizationSensitive: true
            ),
            hooks: VaultMutationHooks(didReach: { phase in
                guard phase == .finalCheck else { return }
                try FileManager.default.moveItem(at: parent, to: detached)
                try FileManager.default.createSymbolicLink(
                    at: parent,
                    withDestinationURL: outside
                )
            })
        )

        #expect(throws: (any Error).self) {
            try coordinator.updateExisting(
                path: path,
                expected: original,
                candidate: candidate
            )
        }
        #expect(try Data(contentsOf: detached.appendingPathComponent("Note.md")) == original)
        #expect(try Data(contentsOf: outside.appendingPathComponent("Note.md")) == outsideBytes)
    }

    @Test("A readback mismatch never reports success or rewrites the external bytes")
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

        #expect(throws: VaultRepositoryError.self) {
            try coordinator.updateExisting(
                path: fixture.path,
                expected: fixture.original,
                candidate: fixture.candidate
            )
        }
        #expect(try Data(contentsOf: fixture.note) == external)
        #expect(try fixture.replacementFiles().isEmpty)
    }

    @Test("Filesystem metadata changes do not become save failures")
    func metadataChangeIsNotASavePredicate() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let attributeName = "com.scholium.metadata-test"
        let coordinator = VaultMutationCoordinator(
            resolver: fixture.resolver,
            hooks: VaultMutationHooks(didReach: { phase in
                guard phase == .replaced else { return }
                try Data("provider-owned".utf8).withUnsafeBytes { bytes in
                    guard setxattr(
                        fixture.note.path,
                        attributeName,
                        bytes.baseAddress,
                        bytes.count,
                        0,
                        0
                    ) == 0 else {
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                }
            })
        )

        try coordinator.updateExisting(
            path: fixture.path,
            expected: fixture.original,
            candidate: fixture.candidate
        )
        #expect(try Data(contentsOf: fixture.note) == fixture.candidate)
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

        let createdPath = try MarkdownRelativePath("Created.md")
        try coordinator.create(path: createdPath, data: fixture.original)
        let movedPath = try MarkdownRelativePath("Moved.md")
        try coordinator.move(
            source: createdPath,
            destination: movedPath,
            expected: fixture.original
        )
        #expect(try Data(contentsOf: fixture.root.appendingPathComponent("Moved.md")) == fixture.original)
        try coordinator.delete(path: movedPath, expected: fixture.original)
        #expect(!FileManager.default.fileExists(
            atPath: fixture.root.appendingPathComponent("Moved.md").path
        ))
    }

    @Test("Deletion never converts a presence error into confirmed absence")
    func deletionPresenceErrorIsUncertain() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let coordinator = VaultMutationCoordinator(
            resolver: fixture.resolver,
            hooks: VaultMutationHooks(
                presenceOverride: { _ in .inaccessible(EACCES) }
            )
        )

        #expect(throws: VaultRepositoryError.self) {
            try coordinator.delete(path: fixture.path, expected: fixture.original)
        }
    }

    private final class Fixture {
        let root: URL
        let note: URL
        let path: MarkdownRelativePath
        let resolver: VaultPathResolver
        let original = Data([0xEF, 0xBB, 0xBF] + Array("# 原始\r\n".utf8))
        let candidate = Data([0xEF, 0xBB, 0xBF] + Array("# 候选\r\n".utf8))

        init() throws {
            let repositoryRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            root = repositoryRoot
                .appendingPathComponent(".build/vault-mutations", isDirectory: true)
                .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
            note = root.appendingPathComponent("Note.md")
            try original.write(to: note)
            path = try MarkdownRelativePath("Note.md")
            resolver = VaultPathResolver(
                rootURL: root,
                caseSensitive: true,
                normalizationSensitive: true
            )
        }

        func replacementFiles() throws -> [URL] {
            try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            ).filter { $0.lastPathComponent.hasPrefix(".scholium-replacement-") }
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
