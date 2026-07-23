import Darwin
import Foundation
import Testing
@testable import ScholiumContracts
@testable import ScholiumCore

@Suite("Vault mutation coordinator")
struct VaultMutationCoordinatorTests {
    private struct InjectedFailure: Error {}

    @Test("Every injected update phase preserves or recovers the preimage", arguments: [
        VaultMutationPhase.initialRead,
        .staged,
        .finalCheck,
        .swapped,
        .readback,
    ])
    func injectedFailureAtEveryPhase(_ phase: VaultMutationPhase) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let coordinator = VaultMutationCoordinator(
            resolver: fixture.resolver,
            hooks: VaultMutationHooks(didReach: { observed in
                if observed == phase { throw InjectedFailure() }
            })
        )

        var wasCommitUncertain = false
        do {
            try coordinator.updateExisting(
                path: fixture.path,
                expected: fixture.original,
                candidate: fixture.candidate
            )
            Issue.record("An injected commit-stage failure was reported as Saved.")
        } catch VaultRepositoryError.commitUncertain {
            wasCommitUncertain = true
        } catch is InjectedFailure {
            // Pre-swap failures retain the ordinary typed error.
        }

        #expect(try Data(contentsOf: fixture.note) == fixture.original)
        if phase == .swapped || phase == .readback {
            #expect(wasCommitUncertain)
            #expect(try fixture.stagedFiles().contains {
                try Data(contentsOf: $0) == fixture.candidate
            })
        } else {
            #expect(!wasCommitUncertain)
            #expect(try fixture.stagedFiles().isEmpty)
        }
    }

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

    @Test(
        "A parent-directory symlink exchange cannot commit to a detached path",
        arguments: [VaultMutationPhase.finalCheck, .swapped]
    )
    func parentSymlinkExchange(at injectedPhase: VaultMutationPhase) throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let base = repositoryRoot
            .appendingPathComponent(".build/vault-parent-races", isDirectory: true)
            .appendingPathComponent(
                String(UUID().uuidString.prefix(12)).lowercased(),
                isDirectory: true
            )
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
                guard phase == injectedPhase else { return }
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

    @Test("Update preserves mode, owner/group, ACL, xattrs, Finder tags, flags, and birth time")
    func updatePreservesMetadata() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        guard chmod(fixture.note.path, 0o640) == 0,
              chflags(fixture.note.path, UInt32(UF_HIDDEN)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let attributeName = "com.scholium.metadata-test"
        let attribute = Data("preserve-xattr".utf8)
        let finderTagName = "com.apple.metadata:_kMDItemUserTags"
        let finderTag = try PropertyListSerialization.data(
            fromPropertyList: ["Stability\n6"],
            format: .binary,
            options: 0
        )
        try setExtendedAttribute(attribute, name: attributeName, at: fixture.note)
        try setExtendedAttribute(finderTag, name: finderTagName, at: fixture.note)
        try installReadACL(at: fixture.note)
        let aclBefore = try extendedACLText(at: fixture.note)
        var before = stat()
        #expect(stat(fixture.note.path, &before) == 0)

        try VaultMutationCoordinator(resolver: fixture.resolver).updateExisting(
            path: fixture.path,
            expected: fixture.original,
            candidate: fixture.candidate
        )

        var after = stat()
        #expect(stat(fixture.note.path, &after) == 0)
        #expect(after.st_mode & 0o7777 == before.st_mode & 0o7777)
        #expect(after.st_uid == before.st_uid)
        #expect(after.st_gid == before.st_gid)
        #expect(after.st_flags == before.st_flags)
        #expect(after.st_birthtimespec.tv_sec == before.st_birthtimespec.tv_sec)
        #expect(after.st_birthtimespec.tv_nsec == before.st_birthtimespec.tv_nsec)
        #expect(
            after.st_mtimespec.tv_sec > before.st_mtimespec.tv_sec
                || (after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec
                    && after.st_mtimespec.tv_nsec > before.st_mtimespec.tv_nsec)
        )
        #expect(try extendedAttribute(name: attributeName, at: fixture.note) == attribute)
        #expect(try extendedAttribute(name: finderTagName, at: fixture.note) == finderTag)
        #expect(try extendedACLText(at: fixture.note) == aclBefore)
    }

    @Test("Update accepts bounded system normalization of quarantine metadata")
    func updateAcceptsNormalizedQuarantineAttribute() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let quarantineName = "com.apple.quarantine"
        let quarantine = Data(
            "0081;66A1B2C3;Scholium;00000000-0000-0000-0000-000000000001".utf8
        )
        try setExtendedAttribute(
            quarantine,
            name: quarantineName,
            at: fixture.note
        )
        let rewritten = Data(
            "0081;6A620F27;;00000000-0000-0000-0000-000000000001".utf8
        )
        let coordinator = VaultMutationCoordinator(
            resolver: fixture.resolver,
            hooks: VaultMutationHooks(didReach: { phase in
                guard phase == .swapped else { return }
                try setExtendedAttribute(
                    rewritten,
                    name: quarantineName,
                    at: fixture.note
                )
            })
        )

        try coordinator.updateExisting(
            path: fixture.path,
            expected: fixture.original,
            candidate: fixture.candidate
        )

        #expect(
            try extendedAttribute(name: quarantineName, at: fixture.note)
                == rewritten
        )
        #expect(try Data(contentsOf: fixture.note) == fixture.candidate)
    }

    @Test("Update rejects a quarantine security or event identity change")
    func updateRejectsChangedQuarantineAuthority() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let quarantineName = "com.apple.quarantine"
        let quarantine = Data(
            "0081;66A1B2C3;Scholium;00000000-0000-0000-0000-000000000001".utf8
        )
        try setExtendedAttribute(
            quarantine,
            name: quarantineName,
            at: fixture.note
        )
        let changedAuthority = Data(
            "0181;6A620F27;;00000000-0000-0000-0000-000000000002".utf8
        )
        let coordinator = VaultMutationCoordinator(
            resolver: fixture.resolver,
            hooks: VaultMutationHooks(didReach: { phase in
                guard phase == .swapped else { return }
                try setExtendedAttribute(
                    changedAuthority,
                    name: quarantineName,
                    at: fixture.note
                )
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
        do {
            try coordinator.delete(path: fixture.path, expected: fixture.original)
            Issue.record("An inaccessible deletion check was reported as success.")
        } catch VaultRepositoryError.commitUncertain {
            // Required fail-closed outcome.
        } catch {
            Issue.record("Unexpected deletion verification error: \(error)")
        }
    }

    private func setExtendedAttribute(_ data: Data, name: String, at url: URL) throws {
        try data.withUnsafeBytes { bytes in
            guard setxattr(
                url.path,
                name,
                bytes.baseAddress,
                bytes.count,
                0,
                0
            ) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
    }

    private func extendedAttribute(name: String, at url: URL) throws -> Data {
        let count = getxattr(url.path, name, nil, 0, 0, 0)
        guard count >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var bytes = [UInt8](repeating: 0, count: count)
        let observed = getxattr(url.path, name, &bytes, bytes.count, 0, 0)
        guard observed == count else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return Data(bytes)
    }

    private func installReadACL(at url: URL) throws {
        _ = try commandOutput(
            executable: "/bin/chmod",
            arguments: ["+a", "everyone allow read", url.path]
        )
    }

    private func extendedACLText(at url: URL) throws -> [String] {
        try commandOutput(
            executable: "/bin/ls",
            arguments: ["-lde", url.path]
        )
        .split(separator: "\n")
        .dropFirst()
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    }

    private func commandOutput(
        executable: String,
        arguments: [String]
    ) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        return String(decoding: data, as: UTF8.self)
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
