import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Transactional vault repository")
struct VaultRepositoryTests {
    private func fixture() throws -> (root: URL, support: URL, note: URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let root = base.appendingPathComponent("vault", isDirectory: true)
        let support = base.appendingPathComponent("support", isDirectory: true)
        let note = root.appendingPathComponent("topics/note.md")
        try FileManager.default.createDirectory(at: note.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "---\ntitle: Note\nmodified: 2025-01-01\n---\nOriginal\n".write(to: note, atomically: true, encoding: .utf8)
        return (root, support, note)
    }

    @Test("Save records immutable prewrite recovery without exposing delivery restore")
    func saveRecordsPrewriteRecovery() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(vaultURL: f.root, identity: identity, applicationSupportURL: f.support)
        let original = try await repository.load(relativePath: "topics/note.md")
        let saved = try await repository.save(
            relativePath: "topics/note.md",
            changeSet: .body("Changed\n"),
            expectedRevision: original.fingerprint
        )
        let savedContent = try String(contentsOf: f.note, encoding: .utf8)
        #expect(savedContent.contains("Changed"))
        let firstRecovery = await repository.recoveryEntries(relativePath: "topics/note.md")
        #expect(firstRecovery.count == 1)
        #expect(try await repository.recoveryContent(entryID: firstRecovery[0].id) == original.rawContent)

        _ = try await repository.save(
            relativePath: "topics/note.md",
            changeSet: .body("Changed again\n"),
            expectedRevision: saved.document.fingerprint
        )
        #expect((await repository.recoveryEntries(relativePath: "topics/note.md")).count == 2)
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

    @Test("History is isolated per vault and capped at ten")
    func isolationAndRetention() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let firstID = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let first = try VaultRepository(vaultURL: f.root, identity: firstID, applicationSupportURL: f.support)

        var document = try await first.load(relativePath: "topics/note.md")
        for index in 0..<12 {
            let result = try await first.save(
                relativePath: "topics/note.md",
                changeSet: .body("Change \(index)\n"),
                expectedRevision: document.fingerprint
            )
            document = result.document
        }
        #expect((await first.recoveryEntries(relativePath: "topics/note.md")).count == 10)

        let secondID = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let second = try VaultRepository(vaultURL: f.root, identity: secondID, applicationSupportURL: f.support)
        #expect((await second.recoveryEntries(relativePath: "topics/note.md")).isEmpty)
    }

    @Test("A corrupt legacy recovery index blocks writes without replacing evidence")
    func corruptVersionIndexIsPreserved() async throws {
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
        #expect(await repository.recoveryLedgerHealthDiagnostic() != nil)
        let original = try await repository.load(relativePath: "topics/note.md")
        await #expect(throws: VaultRepositoryError.self) {
            _ = try await repository.save(
                relativePath: original.relativePath,
                changeSet: .body("Must not be written\n"),
                expectedRevision: original.fingerprint
            )
        }

        #expect(try Data(contentsOf: index) == corrupt)
        #expect(try await repository.load(relativePath: original.relativePath).rawContent == original.rawContent)
    }

    @Test("A tampered recovery blob is rejected before use")
    func tamperedRecoveryBlobIsRejected() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        let original = try await repository.load(relativePath: "topics/note.md")
        let saved = try await repository.save(
            relativePath: original.relativePath,
            changeSet: .body("Changed\n"),
            expectedRevision: original.fingerprint
        )
        let recovery = try #require(await repository.recoveryEntries(relativePath: original.relativePath).first)
        let versionsRoot = f.support
            .appendingPathComponent("Vaults", isDirectory: true)
            .appendingPathComponent(identity.id.uuidString, isDirectory: true)
            .appendingPathComponent("recovery-v2", isDirectory: true)
            .appendingPathComponent("objects", isDirectory: true)
            .appendingPathComponent(recovery.id.uuidString.lowercased(), isDirectory: true)
        let blob = versionsRoot.appendingPathComponent("source.md")
        #expect(FileManager.default.fileExists(atPath: blob.path))
        try Data("tampered".utf8).write(to: blob, options: .atomic)

        await #expect(throws: VaultRepositoryError.self) {
            _ = try await repository.recoveryContent(entryID: recovery.id)
        }
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
        #expect((await repository.recoveryEntries(relativePath: relativePath)).isEmpty)
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

    @Test("Moves preserve bytes and Set Aside and Trash are locations")
    func moveSetAsideAndTrash() async throws {
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

        let setAside = try await repository.setAside(
            relativePath: moved.relativePath,
            expectedRevision: moved.document.fingerprint
        )
        #expect(setAside.relativePath == "Set Aside/Knowledge/Renamed.md")

        let trashed = try await repository.moveToTrash(
            relativePath: setAside.relativePath,
            expectedRevision: setAside.document.fingerprint
        )
        #expect(trashed.relativePath == "Trash/Set Aside/Knowledge/Renamed.md")
        #expect(try await repository.load(relativePath: trashed.relativePath).rawContent == original.rawContent)
    }

    @Test("Confirmed moves preserve prewrite recovery at the destination path")
    func movedRecoveryLedger() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(
            vaultURL: f.root,
            identity: identity,
            applicationSupportURL: f.support
        )
        let original = try await repository.load(relativePath: "topics/note.md")
        let saved = try await repository.save(
            relativePath: original.relativePath,
            changeSet: .body("Changed\n"),
            expectedRevision: original.fingerprint
        )
        let savedRecovery = try #require(
            await repository.recoveryEntries(relativePath: original.relativePath).first
        )
        let moved = try await repository.move(
            relativePath: saved.document.relativePath,
            to: "Knowledge/Renamed.md",
            expectedRevision: saved.document.fingerprint
        )

        try await repository.migrateRecoveryLedger(
            from: "topics/note.md",
            to: "Knowledge/Renamed.md"
        )

        #expect((await repository.recoveryEntries(relativePath: "topics/note.md")).isEmpty)
        let recoveryEntries = await repository.recoveryEntries(relativePath: "Knowledge/Renamed.md")
        #expect(recoveryEntries.count == 2)
        #expect(try await repository.recoveryContent(entryID: savedRecovery.id) == original.rawContent)
        #expect(try await repository.load(relativePath: "Knowledge/Renamed.md").rawContent == moved.document.rawContent)

        // Retrying after an interrupted caller is idempotent.
        try await repository.migrateRecoveryLedger(
            from: "topics/note.md",
            to: "Knowledge/Renamed.md"
        )
        #expect((await repository.recoveryEntries(relativePath: "Knowledge/Renamed.md")).count == 2)
    }

    @Test("Permanent deletion is revision checked and purges repository recovery bytes")
    func permanentDeletion() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(vaultURL: f.root, identity: identity, applicationSupportURL: f.support)
        let original = try await repository.load(relativePath: "topics/note.md")

        let deletion = try await repository.deletePermanently(
            relativePath: "topics/note.md",
            expectedRevision: original.fingerprint
        )
        #expect(!FileManager.default.fileExists(atPath: f.note.path))
        #expect(deletion.fingerprint == original.fingerprint)
        #expect(await repository.recoveryEntries(relativePath: "topics/note.md").isEmpty)
    }

    @Test("Prepared deletion never replaces a concurrently recreated path and retains recovery bytes")
    func preparedDeletionConflictRetainsRecovery() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root.deletingLastPathComponent()) }
        let identity = VaultIdentity(id: UUID(), canonicalPath: f.root.path, bookmarkData: nil)
        let repository = try VaultRepository(vaultURL: f.root, identity: identity, applicationSupportURL: f.support)
        let original = try await repository.load(relativePath: "topics/note.md")
        let prepared = try await repository.preparePermanentDeletion(
            relativePath: original.relativePath,
            expectedRevision: original.fingerprint
        )

        try await repository.applyPreparedPermanentDeletion(prepared)
        try FileManager.default.createDirectory(
            at: f.note.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "Concurrent replacement\n".write(to: f.note, atomically: true, encoding: .utf8)
        await #expect(throws: VaultRepositoryError.self) {
            try await repository.rollbackPreparedPermanentDeletion(prepared)
        }

        #expect(try String(contentsOf: f.note, encoding: .utf8) == "Concurrent replacement\n")
        #expect(await repository.recoveryEntries(relativePath: original.relativePath).contains {
            $0.id == prepared.recoveryReference.id && $0.fingerprint == original.fingerprint
        })

        try FileManager.default.removeItem(at: f.note)
        try await repository.rollbackPreparedPermanentDeletion(prepared)
        #expect(try String(contentsOf: f.note, encoding: .utf8) == original.rawContent)
        #expect(await repository.recoveryEntries(relativePath: original.relativePath).isEmpty)
    }

    @Test("Lifecycle paths reject traversal, non-Markdown targets, and symlink parents")
    func lifecyclePathSafety() async throws {
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

    @Test("Paper profile saves keep time in app history instead of injecting YAML")
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
