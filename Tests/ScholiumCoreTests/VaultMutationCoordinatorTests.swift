import Darwin
import Foundation
import Testing

@testable import ScholiumContracts
@testable import ScholiumCore

@Suite("Vault mutation coordinator")
struct VaultMutationCoordinatorTests {
    private struct InjectedFailure: Error {}

    @Test("An existing note uses coordinated descriptor replacement and exact readback")
    func successfulExistingUpdate() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let backupID = UUID()

        try VaultMutationCoordinator(resolver: fixture.resolver).updateExisting(
            path: fixture.path,
            expected: fixture.original,
            candidate: fixture.candidate,
            backupID: backupID
        )

        #expect(try Data(contentsOf: fixture.note) == fixture.candidate)
        #expect(try Data(contentsOf: fixture.root.appendingPathComponent(VaultMutationCoordinator.replacementBackupName(backupID))) == fixture.original)
        #expect(try fixture.exchangeFiles().count == 1)
    }

    @Test("Failures before replacement preserve the source and remove the candidate")
    func failureBeforeReplacement() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let coordinator = try VaultMutationCoordinator(
            resolver: fixture.resolver,
            hooks: VaultMutationHooks(didReach: { phase in
                if phase == .replacing { throw InjectedFailure() }
            })
        )

        #expect(throws: InjectedFailure.self) {
            try coordinator.updateExisting(
                path: fixture.path,
                expected: fixture.original,
                candidate: fixture.candidate,
                backupID: UUID()
            )
        }
        #expect(try Data(contentsOf: fixture.note) == fixture.original)
        #expect(try fixture.exchangeFiles().isEmpty)
    }

    @Test("A peer's in-place edit to the exchange slot survives a refused commit")
    func changedExchangeSlotRemainsRecoverable() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let backupID = UUID()
        let slot = fixture.root.appendingPathComponent(VaultMutationCoordinator.replacementBackupName(backupID))
        let external = Data("unique external slot bytes".utf8)
        let coordinator = try VaultMutationCoordinator(
            resolver: fixture.resolver,
            hooks: VaultMutationHooks(didReach: { phase in
                if phase == .replacing { try external.write(to: slot) }
            }))

        #expect(throws: VaultRepositoryError.self) {
            try coordinator.updateExisting(
                path: fixture.path, expected: fixture.original, candidate: fixture.candidate, backupID: backupID)
        }
        #expect(try Data(contentsOf: fixture.note) == fixture.original)
        #expect(try Data(contentsOf: slot) == external)
    }

    @Test("A failure after replacement does not perform a second source mutation")
    func failureAfterReplacement() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let coordinator = try VaultMutationCoordinator(
            resolver: fixture.resolver,
            hooks: VaultMutationHooks(didReach: { phase in
                if phase == .replaced { throw InjectedFailure() }
            })
        )

        #expect(throws: InjectedFailure.self) {
            try coordinator.updateExisting(
                path: fixture.path,
                expected: fixture.original,
                candidate: fixture.candidate,
                backupID: UUID()
            )
        }
        #expect(try Data(contentsOf: fixture.note) == fixture.candidate)
        #expect(try fixture.exchangeFiles().count == 1)
        let retained = try #require(try fixture.exchangeFiles().first)
        #expect(try Data(contentsOf: retained) == fixture.original)
    }

    @Test("An external writer before final authorization causes a conflict")
    func writerBeforeFinalCheck() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let external = Data("external".utf8)
        let coordinator = try VaultMutationCoordinator(
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
                candidate: fixture.candidate,
                backupID: UUID()
            )
        }
        #expect(try Data(contentsOf: fixture.note) == external)
        #expect(try fixture.exchangeFiles().isEmpty)
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
        let coordinator = try VaultMutationCoordinator(
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
                candidate: fixture.candidate,
                backupID: UUID()
            )
        }
        #expect(try Data(contentsOf: outside) == outsideBytes)
        #expect(try fixture.exchangeFiles().isEmpty)
    }

    @Test("A parent-directory exchange cannot retarget the replacement", arguments: [false, true])
    func parentSymlinkExchange(afterFinalAuthorization: Bool) throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let base =
            repositoryRoot
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
        let backupID = UUID()
        try original.write(to: parent.appendingPathComponent("Note.md"))
        try outsideBytes.write(to: outside.appendingPathComponent("Note.md"))
        let path = try MarkdownRelativePath("Folder/Note.md")
        let coordinator = try VaultMutationCoordinator(
            resolver: VaultPathResolver(
                rootURL: root,
                caseSensitive: true,
                normalizationSensitive: true
            ),
            hooks: VaultMutationHooks(didReach: { phase in
                guard phase == (afterFinalAuthorization ? .replacing : .finalCheck) else { return }
                // A redirected absolute-URL replacement can find both operands
                // in the foreign directory. Descriptor-relative commit must
                // still affect only the originally authorized parent.
                for file in try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
                where file.lastPathComponent.hasPrefix(".scholium-") {
                    try FileManager.default.copyItem(at: file, to: outside.appendingPathComponent(file.lastPathComponent))
                }
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
                candidate: candidate,
                backupID: backupID
            )
        }
        #expect(try Data(contentsOf: outside.appendingPathComponent("Note.md")) == outsideBytes)
        if !afterFinalAuthorization {
            #expect(try Data(contentsOf: detached.appendingPathComponent("Note.md")) == original)
        } else {
            #expect(try Data(contentsOf: detached.appendingPathComponent("Note.md")) == candidate)
            let displaced = detached.appendingPathComponent(VaultMutationCoordinator.replacementBackupName(backupID))
            #expect(try Data(contentsOf: displaced) == original)
        }
    }

    @Test("Descriptor replacement preserves permissions, ACLs, attributes and creation date with a new modification time")
    func replacementPreservesMetadata() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let fileManager = FileManager.default
        let creationDate = Date(timeIntervalSince1970: 1_700_000_000)
        try fileManager.setAttributes(
            [.posixPermissions: 0o640, .creationDate: creationDate, .modificationDate: creationDate],
            ofItemAtPath: fixture.note.path)
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+a", "everyone allow read", fixture.note.path]
        try chmod.run()
        chmod.waitUntilExit()
        try #require(chmod.terminationStatus == 0)
        let originalACL = try aclText(at: fixture.note)
        let attributeName = "com.scholium.replacement-test"
        let attribute = Data("researcher-owned".utf8)
        try attribute.withUnsafeBytes { bytes in
            guard setxattr(fixture.note.path, attributeName, bytes.baseAddress, bytes.count, 0, 0) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
        let before = try fileManager.attributesOfItem(atPath: fixture.note.path)

        try VaultMutationCoordinator(resolver: fixture.resolver).updateExisting(
            path: fixture.path, expected: fixture.original, candidate: fixture.candidate, backupID: UUID())

        let after = try fileManager.attributesOfItem(atPath: fixture.note.path)
        #expect(after[.posixPermissions] as? NSNumber == before[.posixPermissions] as? NSNumber)
        #expect(after[.creationDate] as? Date == before[.creationDate] as? Date)
        #expect(try aclText(at: fixture.note) == originalACL)
        #expect(try #require(after[.modificationDate] as? Date) > creationDate)
        var observed = Data(count: attribute.count)
        let count = observed.withUnsafeMutableBytes {
            getxattr(fixture.note.path, attributeName, $0.baseAddress, $0.count, 0, 0)
        }
        #expect(count == attribute.count)
        #expect(observed == attribute)
        #expect(try Data(contentsOf: fixture.note) == fixture.candidate)
    }

    private func aclText(at url: URL) throws -> String {
        guard let acl = acl_get_file(url.path, ACL_TYPE_EXTENDED) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var count: ssize_t = 0
        guard let text = acl_to_text(acl, &count) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { acl_free(text) }
        return String(cString: text)
    }

    @Test("A readback mismatch never reports success or rewrites the external bytes")
    func externalReplacementBeforeReadback() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let external = Data("external-readback".utf8)
        let coordinator = try VaultMutationCoordinator(
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
                candidate: fixture.candidate,
                backupID: UUID()
            )
        }
        #expect(try Data(contentsOf: fixture.note) == external)
        #expect(try fixture.exchangeFiles().count == 1)
        let retained = try #require(try fixture.exchangeFiles().first)
        #expect(try Data(contentsOf: retained) == fixture.original)
    }

    @Test("Filesystem metadata changes do not become save failures")
    func metadataChangeIsNotASavePredicate() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let attributeName = "com.scholium.metadata-test"
        let coordinator = try VaultMutationCoordinator(
            resolver: fixture.resolver,
            hooks: VaultMutationHooks(didReach: { phase in
                guard phase == .replaced else { return }
                try Data("provider-owned".utf8).withUnsafeBytes { bytes in
                    guard
                        setxattr(
                            fixture.note.path,
                            attributeName,
                            bytes.baseAddress,
                            bytes.count,
                            0,
                            0
                        ) == 0
                    else {
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                }
            })
        )

        try coordinator.updateExisting(
            path: fixture.path,
            expected: fixture.original,
            candidate: fixture.candidate,
            backupID: UUID()
        )
        #expect(try Data(contentsOf: fixture.note) == fixture.candidate)
    }

    @Test("Successful create, move, update, and delete preserve exact bytes")
    func successfulOperations() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let coordinator = try VaultMutationCoordinator(resolver: fixture.resolver)
        try coordinator.updateExisting(
            path: fixture.path,
            expected: fixture.original,
            candidate: fixture.candidate,
            backupID: UUID()
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
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.root.appendingPathComponent("Moved.md").path
            ))
    }

    @Test("Deletion never converts a presence error into confirmed absence")
    func deletionPresenceErrorIsUncertain() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let coordinator = try VaultMutationCoordinator(
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
            root =
                repositoryRoot
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

        func exchangeFiles() throws -> [URL] {
            try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            ).filter { $0.lastPathComponent.hasPrefix(".scholium-save-backup-") }
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
