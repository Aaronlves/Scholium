import Darwin
import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Transactional vault repository")
struct VaultRepositoryTests {
    private enum SaveFault: Error {
        case beforeSwap
        case afterSwap
    }

    private func fixture() throws -> (root: URL, support: URL, note: URL) {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureID = String(UUID().uuidString.prefix(12)).lowercased()
        let base = repositoryRoot
            .appendingPathComponent(".build/vt", isDirectory: true)
            .appendingPathComponent(fixtureID, isDirectory: true)
        let root = base.appendingPathComponent("vault", isDirectory: true)
        let support = base.appendingPathComponent("support", isDirectory: true)
        let note = root.appendingPathComponent("topics/note.md")
        try FileManager.default.createDirectory(at: note.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "---\ntitle: Note\nmodified: 2025-01-01\n---\nOriginal\n".write(to: note, atomically: true, encoding: .utf8)
        return (root, support, note)
    }

    @Test("FIFO, socket, and directory leaves are rejected without blocking")
    func specialFilesAreRejectedWithoutBlocking() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil),
            applicationSupportURL: f.support
        )
        try FileManager.default.removeItem(at: f.note)

        #expect(mkfifo(f.note.path, 0o600) == 0)
        let clock = ContinuousClock()
        let fifoStart = clock.now
        await #expect(throws: (any Error).self) {
            _ = try await repository.load(relativePath: "topics/note.md")
        }
        #expect(fifoStart.duration(to: clock.now) < .seconds(1))
        try FileManager.default.removeItem(at: f.note)

        try FileManager.default.createDirectory(at: f.note, withIntermediateDirectories: false)
        await #expect(throws: (any Error).self) {
            _ = try await repository.load(relativePath: "topics/note.md")
        }
        try FileManager.default.removeItem(at: f.note)

        let socketDescriptor = try bindUnixSocket(at: f.note)
        defer { close(socketDescriptor) }
        let socketStart = clock.now
        await #expect(throws: (any Error).self) {
            _ = try await repository.load(relativePath: "topics/note.md")
        }
        #expect(socketStart.duration(to: clock.now) < .seconds(1))
    }

    @Test("Inventory enumeration fails closed when a vault subtree is unreadable")
    func unreadableInventoryIsNotTreatedAsDeletion() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: VaultIdentity(
                id: UUID(),
                canonicalPath: f.root.path,
                bookmarkData: nil
            ),
            applicationSupportURL: f.support
        )
        let unreadable = f.root.appendingPathComponent(
            "unreadable",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: unreadable,
            withIntermediateDirectories: false
        )
        try Data("# Hidden from an incomplete inventory\n".utf8).write(
            to: unreadable.appendingPathComponent("Hidden.md")
        )
        guard chmod(unreadable.path, 0) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { _ = chmod(unreadable.path, 0o700) }

        await #expect(throws: (any Error).self) {
            _ = try await repository.markdownRelativePaths()
        }
        await #expect(throws: (any Error).self) {
            _ = try await repository.folderRelativePaths()
        }
    }

    private func bindUnixSocket(at url: URL) throws -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var address = sockaddr_un()
        let bytes = Array(url.path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            close(descriptor)
            throw POSIXError(.ENAMETOOLONG)
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sa_family_t>.size + bytes.count)
        withUnsafeMutablePointer(to: &address.sun_path.0) { destination in
            bytes.withUnsafeBytes { source in
                _ = memcpy(destination, source.baseAddress, bytes.count)
            }
        }
        let addressLength = socklen_t(address.sun_len)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, addressLength)
            }
        }
        guard result == 0 else {
            let code = errno
            close(descriptor)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        return descriptor
    }

    @Test("External changes cause a conflict")
    func conflict() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(vaultURL: f.root, identity: identity, applicationSupportURL: f.support)
        let loaded = try await repository.load(relativePath: "topics/note.md")
        try "External edit".write(to: f.note, atomically: true, encoding: .utf8)

        await #expect(throws: VaultRepositoryError.self) {
            try await repository.save(
                relativePath: "topics/note.md",
                changeSet: .body("Local edit"),
                expectedRevision: loaded.fingerprint
            )
        }
        #expect(try String(contentsOf: f.note, encoding: .utf8) == "External edit")
    }

    @Test("Exact canonical candidate proves a save despite a post-replacement error")
    func postReplacementErrorStillCommits() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(
            id: UUID(),
            canonicalPath: f.root.path,
            bookmarkData: nil
        )
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support,
            mutationHooks: VaultMutationHooks(didReach: { phase in
                if phase == .replaced { throw SaveFault.afterSwap }
            })
        )
        let original = try await repository.load(relativePath: "topics/note.md")
        let candidate = "# Exact candidate\r\n\r\nPreserve bytes.\r\n"
        let outcome = try await repository.saveOutcome(
            relativePath: original.relativePath,
            changeSet: .exactContent(candidate),
            expectedRevision: original.fingerprint
        )

        guard case .committed(let result) = outcome else {
            Issue.record("Exact canonical readback did not prove the completed save.")
            return
        }
        #expect(result.document.rawContent == candidate)
        #expect(try Data(contentsOf: f.note) == Data(candidate.utf8))
        #expect(try await repository.interruptedSaveRecoveries().isEmpty)
    }

    @Test("A failed replacement with unchanged canonical source is retryable")
    func unchangedCanonicalReplacementFailureIsRetryable() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(
            id: UUID(),
            canonicalPath: f.root.path,
            bookmarkData: nil
        )
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support,
            mutationHooks: VaultMutationHooks(didReach: { phase in
                if phase == .replacing { throw SaveFault.beforeSwap }
            })
        )
        let original = try await repository.load(relativePath: "topics/note.md")

        do {
            _ = try await repository.saveOutcome(
                relativePath: original.relativePath,
                changeSet: .body("Retry this edit"),
                expectedRevision: original.fingerprint
            )
            Issue.record("A failed replacement unexpectedly reported a save.")
        } catch let error as VaultRepositoryError {
            guard case .writeFailed = error else {
                Issue.record("The unchanged source did not produce a retryable failure.")
                return
            }
        }

        #expect(try Data(contentsOf: f.note) == Data(original.rawContent.utf8))
        #expect(try await repository.interruptedSaveRecoveries().isEmpty)
    }

    @Test("A readback mismatch retains the candidate without replacing external bytes")
    func readbackMismatchRetainsCandidate() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(
            id: UUID(),
            canonicalPath: f.root.path,
            bookmarkData: nil
        )
        let external = Data("# External readback revision\n".utf8)
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support,
            mutationHooks: VaultMutationHooks(didReach: { phase in
                if phase == .readback {
                    try external.write(to: f.note, options: .atomic)
                }
            })
        )
        let original = try await repository.load(relativePath: "topics/note.md")
        let candidate = "# Exact candidate\r\n\r\nPreserve bytes.\r\n"
        let outcome = try await repository.saveOutcome(
            relativePath: original.relativePath,
            changeSet: .exactContent(candidate),
            expectedRevision: original.fingerprint
        )

        guard case .recoveryRequired(let recovery) = outcome else {
            Issue.record("A readback mismatch was not retained for recovery.")
            return
        }
        #expect(recovery.sourceState == .changed(DocumentFingerprint(data: external)))
        #expect(try await repository.interruptedSaveRecoveryContent(recovery).exactSource == candidate)
        #expect(try Data(contentsOf: f.note) == external)
    }

    @Test("Traversal, missing files, and symlink escapes are rejected")
    func pathSafety() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(vaultURL: f.root, identity: identity, applicationSupportURL: f.support)

        await #expect(throws: VaultRepositoryError.self) { try await repository.load(relativePath: "../outside.md") }
        await #expect(throws: VaultRepositoryError.self) { try await repository.load(relativePath: "topics/missing.md") }

        let outside = f.root.deletingLastPathComponent().appendingPathComponent("outside.md")
        try "outside".write(to: outside, atomically: true, encoding: .utf8)
        let link = f.root.appendingPathComponent("topics/link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        await #expect(throws: VaultRepositoryError.self) { try await repository.load(relativePath: "topics/link.md") }
    }

    @Test("Unsupported pre-use recovery data is ignored without mutation")
    func unsupportedRecoveryDataIsIgnored() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let versions = f.support
            .appendingPathComponent("Vaults", isDirectory: true)
            .appendingPathComponent(identity.id.uuidString, isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
        try FileManager.default.createDirectory(at: versions, withIntermediateDirectories: true)
        let index = versions.appendingPathComponent("index.json")
        let corrupt = Data("{damaged version index".utf8)
        try corrupt.write(to: index)

        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        #expect(await repository.recoveryLedgerHealthDiagnostic() == nil)
        let original = try await repository.load(relativePath: "topics/note.md")
        let saved = try await repository.save(
            relativePath: original.relativePath,
            changeSet: .body("Current schema save\n"),
            expectedRevision: original.fingerprint
        )

        #expect(try Data(contentsOf: index) == corrupt)
        #expect(try await repository.load(relativePath: original.relativePath).rawContent == saved.document.rawContent)
    }

    @Test("Create and duplicate never replace an existing note")
    func createAndDuplicate() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(vaultURL: f.root, identity: identity, applicationSupportURL: f.support)

        let created = try await repository.create(
            relativePath: "new/Created.md",
            content: "# Created\r\n\r\nExact body\r\n"
        )
        #expect(created.newlineStyle == .crlf)
        #expect(try String(contentsOf: f.root.appendingPathComponent("new/Created.md"), encoding: .utf8) == created.rawContent)

        await #expect(throws: VaultRepositoryError.self) {
            try await repository.create(relativePath: "new/Created.md", content: "Replacement")
        }

        let duplicate = try await repository.duplicate(
            relativePath: "new/Created.md",
            to: "new/Created copy.md",
            expectedRevision: created.fingerprint
        )
        #expect(duplicate.rawContent == created.rawContent)
        #expect(duplicate.relativePath == "new/Created copy.md")
    }

    @Test("Import preserves exact source bytes at the vault root and resolves collisions")
    func importPreservesExactSourceAndResolvesCollisions() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        let source = Data([0xEF, 0xBB, 0xBF]) + Data(
            "---\r\nunknown: [source material\r\n---\r\n# Imported\r\n".utf8
        )

        let first = try await repository.importMarkdown(
            preferredFilename: "Imported.md",
            sourceData: source
        )
        let second = try await repository.importMarkdown(
            preferredFilename: "Imported.md",
            sourceData: source
        )

        #expect(first.relativePath == "Imported.md")
        #expect(second.relativePath == "Imported 2.md")
        #expect(try Data(contentsOf: f.root.appendingPathComponent(first.relativePath)) == source)
        #expect(try Data(contentsOf: f.root.appendingPathComponent(second.relativePath)) == source)
        #expect(!FileManager.default.fileExists(
            atPath: f.root.appendingPathComponent(".scholium/unclassified").path
        ))
    }

    @Test("Import rejects non-Markdown and non-UTF-8 source material")
    func importRejectsUnsupportedSource() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )

        await #expect(throws: DocumentImportError.self) {
            _ = try await repository.importMarkdown(
                preferredFilename: "Imported.txt",
                sourceData: Data("# Imported\n".utf8)
            )
        }
        await #expect(throws: DocumentImportError.self) {
            _ = try await repository.importMarkdown(
                preferredFilename: "Imported.md",
                sourceData: Data([0xFF, 0xFE, 0x00])
            )
        }
    }

    @Test("Folder inventory includes empty directories and one directory move preserves all contents")
    func folderInventoryAndMove() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        let empty = try await repository.createFolder(relativePath: "topics/Empty")
        #expect(empty.rawValue == "topics/Empty")
        #expect(try await repository.folderRelativePaths().contains(empty))

        let attachment = f.root.appendingPathComponent("topics/source.bin")
        let attachmentBytes = Data([0, 1, 2, 255])
        try attachmentBytes.write(to: attachment)
        let original = try await repository.load(relativePath: "topics/note.md")
        let source = try VaultRelativeFolderPath("topics")
        let destination = try VaultRelativeFolderPath("Renamed")
        let moved = try await repository.moveFolder(
            from: source,
            to: destination,
            expectedDocuments: [original.relativePath: original.fingerprint]
        )

        #expect(moved.documents.map(\.relativePath) == ["Renamed/note.md"])
        #expect(moved.documents[0].rawContent == original.rawContent)
        #expect(try Data(contentsOf: f.root.appendingPathComponent("Renamed/source.bin")) == attachmentBytes)
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("topics").path))
        #expect(try await repository.folderRelativePaths().contains(destination))
    }

    @Test("Folder move rejects an inventory changed outside Scholium")
    func folderMoveRejectsChangedInventory() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        let original = try await repository.load(relativePath: "topics/note.md")
        try "# Added externally\n".write(
            to: f.root.appendingPathComponent("topics/Added.md"),
            atomically: true,
            encoding: .utf8
        )

        await #expect(throws: VaultRepositoryError.self) {
            _ = try await repository.moveFolder(
                from: VaultRelativeFolderPath("topics"),
                to: VaultRelativeFolderPath("Renamed"),
                expectedDocuments: [original.relativePath: original.fingerprint]
            )
        }
        #expect(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("topics").path))
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("Renamed").path))
    }

    @Test("Creation rollback is revision checked and does not create history")
    func creationRollback() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        let relativePath = "Critiques/Created Critique.md"
        let created = try await repository.create(relativePath: relativePath, content: "# Critique\n")

        try await repository.removeCreatedFileForRollback(
            relativePath: relativePath,
            createdRevision: created.fingerprint
        )

        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent(relativePath).path))
    }

    @Test("Creation rollback preserves a concurrently changed file")
    func creationRollbackConflict() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        let relativePath = "Critiques/Created Critique.md"
        let created = try await repository.create(relativePath: relativePath, content: "# Critique\n")
        let destination = f.root.appendingPathComponent(relativePath)
        try "External edit\n".write(to: destination, atomically: true, encoding: .utf8)

        await #expect(throws: VaultRepositoryError.self) {
            try await repository.removeCreatedFileForRollback(
                relativePath: relativePath,
                createdRevision: created.fingerprint
            )
        }

        #expect(try String(contentsOf: destination, encoding: .utf8) == "External edit\n")
    }

    @Test("Ordinary moves preserve bytes")
    func movePreservesBytes() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(vaultURL: f.root, identity: identity, applicationSupportURL: f.support)
        let original = try await repository.load(relativePath: "topics/note.md")

        let moved = try await repository.move(
            relativePath: "topics/note.md",
            to: "Knowledge/Renamed.md",
            expectedRevision: original.fingerprint
        )
        #expect(moved.document.rawContent == original.rawContent)
        #expect(!FileManager.default.fileExists(atPath: f.note.path))

        #expect(try await repository.load(relativePath: moved.relativePath).rawContent == original.rawContent)
    }

    @Test("Native system Trash is revision checked and leaves no internal copy")
    func systemTrashMove() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(vaultURL: f.root, identity: identity, applicationSupportURL: f.support)
        let original = try await repository.load(relativePath: "topics/note.md")

        let resultingURL = try await repository.moveToSystemTrash(
            relativePath: "topics/note.md",
            expectedRevision: original.fingerprint
        )
        defer {
            if let resultingURL {
                try? FileManager.default.removeItem(at: resultingURL)
            }
        }
        #expect(!FileManager.default.fileExists(atPath: f.note.path))
        if let resultingURL {
            #expect(FileManager.default.fileExists(atPath: resultingURL.path))
            #expect(try Data(contentsOf: resultingURL) == Data(original.rawContent.utf8))
        }
    }

    @Test("Native system Trash rejects a directory-entry exchange after exact-byte validation")
    func systemTrashRejectsDirectoryEntryExchange() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let replacement = Data("# External replacement\n".utf8)
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: VaultIdentity(
                id: UUID(),
                canonicalPath: f.root.path,
                bookmarkData: nil
            ),
            applicationSupportURL: f.support,
            mutationHooks: VaultMutationHooks(didReach: { phase in
                guard phase == .finalCheck else { return }
                try replacement.write(to: f.note, options: .atomic)
            })
        )
        let original = try await repository.load(relativePath: "topics/note.md")

        await #expect(throws: VaultRepositoryError.self) {
            _ = try await repository.moveToSystemTrash(
                relativePath: "topics/note.md",
                expectedRevision: original.fingerprint
            )
        }
        #expect(try Data(contentsOf: f.note) == replacement)
    }

    @Test("File-operation paths reject traversal, non-Markdown targets, and symlink parents")
    func fileOperationPathSafety() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(vaultURL: f.root, identity: identity, applicationSupportURL: f.support)

        await #expect(throws: VaultRepositoryError.self) {
            try await repository.create(relativePath: "../escape.md", content: "escape")
        }
        await #expect(throws: VaultRepositoryError.self) {
            try await repository.create(relativePath: "note.txt", content: "text")
        }

        let outside = f.root.deletingLastPathComponent().appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let linkedDirectory = f.root.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: outside)
        await #expect(throws: VaultRepositoryError.self) {
            try await repository.create(relativePath: "linked/escape.md", content: "escape")
        }
        #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("escape.md").path))
    }

    @Test("Paper profile saves preserve authored time instead of injecting YAML")
    func paperTimestampIsAppOwned() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("vault", isDirectory: true)
        let support = base.appendingPathComponent("support", isDirectory: true)
        let note = root.appendingPathComponent("papers/legacy.md")
        try FileManager.default.createDirectory(at: note.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "---\ntitle: Legacy\nmodified: 2025-01-01\n---\nOriginal\n".write(
            to: note,
            atomically: true,
            encoding: .utf8
        )
        let identity = VaultIdentity(id: UUID(), canonicalPath: root.path, bookmarkData: nil)
        let repository = try VaultRepository(
            vaultURL: root,
            identity: identity,
            applicationSupportURL: support,
            vaultRole: .sourceCorpus
        )
        let original = try await repository.load(relativePath: "papers/legacy.md")

        _ = try await repository.save(
            relativePath: "papers/legacy.md",
            changeSet: .body("Changed\n"),
            expectedRevision: original.fingerprint
        )
        let content = try String(contentsOf: note, encoding: .utf8)

        #expect(content.contains("modified: 2025-01-01"))
        #expect(content.contains("updated: ") == false)
        #expect(content.contains("analysis_updated_at:") == false)
    }

    @Test("Paper profile preserves an existing legacy timestamp without refreshing it")
    func legacyPaperTimestampCompatibility() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("vault", isDirectory: true)
        let support = base.appendingPathComponent("support", isDirectory: true)
        let note = root.appendingPathComponent("papers/legacy.md")
        try FileManager.default.createDirectory(at: note.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "---\ntitle: Legacy\nanalysis_updated_at: 2025-01-01\n---\nOriginal\n".write(
            to: note,
            atomically: true,
            encoding: .utf8
        )
        let identity = VaultIdentity(id: UUID(), canonicalPath: root.path, bookmarkData: nil)
        let repository = try VaultRepository(
            vaultURL: root,
            identity: identity,
            applicationSupportURL: support,
            vaultRole: .sourceCorpus
        )
        let original = try await repository.load(relativePath: "papers/legacy.md")

        _ = try await repository.save(
            relativePath: "papers/legacy.md",
            changeSet: .body("Changed\n"),
            expectedRevision: original.fingerprint
        )
        let content = try String(contentsOf: note, encoding: .utf8)

        #expect(content.contains("analysis_updated_at: 2025-01-01"))
        #expect(content.contains("\nupdated:") == false)
    }

    @Test("Topic and Work saves do not inject workflow review metadata")
    func nonSyntheticWorkflowMetadata() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("vault", isDirectory: true)
        let support = base.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let topic = root.appendingPathComponent("Concept.md")
        try "# Concept\n".write(to: topic, atomically: true, encoding: .utf8)
        let identity = VaultIdentity(id: UUID(), canonicalPath: root.path, bookmarkData: nil)
        let topicRepository = try VaultRepository(
            vaultURL: root,
            identity: identity,
            applicationSupportURL: support,
            vaultRole: .topicKnowledge
        )
        let topicDocument = try await topicRepository.load(relativePath: "Concept.md")
        _ = try await topicRepository.save(
            relativePath: "Concept.md",
            changeSet: .body("# Revised concept\n"),
            expectedRevision: topicDocument.fingerprint
        )
        #expect(try String(contentsOf: topic, encoding: .utf8) == "# Revised concept\n")

        let dossier = root.appendingPathComponent("ARG-001.md")
        let original = "---\nnote_type: argument_dossier\nlast_reviewed: 2026-07-01\nreview_status: needs_researcher_review\n---\nOpen\n"
        try original.write(to: dossier, atomically: true, encoding: .utf8)
        let workRepository = try VaultRepository(
            vaultURL: root,
            identity: identity,
            applicationSupportURL: support,
            vaultRole: .draftProject
        )
        let dossierDocument = try await workRepository.load(relativePath: "ARG-001.md")
        _ = try await workRepository.save(
            relativePath: "ARG-001.md",
            changeSet: .body("Revised\n"),
            expectedRevision: dossierDocument.fingerprint
        )
        let result = try String(contentsOf: dossier, encoding: .utf8)
        #expect(result.contains("last_reviewed: 2026-07-01"))
        #expect(result.contains("review_status: needs_researcher_review"))
        #expect(result.contains("modified:") == false)
    }
}
