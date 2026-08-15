import CryptoKit
import Foundation
import SQLite3
import Testing
@testable import ScholiumContracts
@testable import ScholiumCore

@Suite("Prewrite recovery ledger")
struct PrewriteRecoveryLedgerTests {
    @Test("Prepared entries are durable, bounded, and discardable")
    func lifecycleAndRetention() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let ledger = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        let discarded = try ledger.prepare(relativePath: "Note.md", data: Data("discard".utf8))
        try ledger.discard(discarded)
        #expect(try ledger.entries(relativePath: "Note.md").isEmpty)

        for index in 0..<12 {
            let data = Data("version-\(index)".utf8)
            let entry = try ledger.prepare(relativePath: "Note.md", data: data)
            try ledger.commit(entry)
        }
        let retained = try ledger.entries(relativePath: "Note.md")
        #expect(retained.count == 10)
        #expect(retained.first?.sequence == 12)
        #expect(try ledger.content(entryID: try #require(retained.first?.id)) == Data("version-11".utf8))
    }

    @Test("Corrupt SQLite is quarantined and rebuilt from immutable objects")
    func corruptDatabaseRebuild() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var ledger: PrewriteRecoveryLedger? = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        let entry = try #require(try ledger?.prepare(relativePath: "Note.md", data: Data("safe".utf8)))
        try ledger?.commit(entry)
        ledger = nil
        let database = fixture.recovery.appendingPathComponent("history.sqlite")
        try Data("not sqlite".utf8).write(to: database, options: .atomic)

        let rebuilt = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        #expect(try rebuilt.entries(relativePath: "Note.md").map(\.id) == [entry.id])
        #expect(rebuilt.healthDiagnostic != nil)
        let quarantine = fixture.recovery.appendingPathComponent("quarantine")
        #expect(try FileManager.default.contentsOfDirectory(atPath: quarantine.path).contains {
            $0.hasPrefix("database-")
        })
    }

    @Test("Tombstones are applied before object rebuild")
    func tombstonePreventsResurrection() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var ledger: PrewriteRecoveryLedger? = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        let entry = try #require(try ledger?.prepare(relativePath: "Deleted.md", data: Data("secret".utf8)))
        try ledger?.commit(entry)
        try ledger?.tombstoneAndPurge(relativePath: "Deleted.md")
        ledger = nil
        try Data("corrupt".utf8).write(
            to: fixture.recovery.appendingPathComponent("history.sqlite"),
            options: .atomic
        )

        let rebuilt = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        #expect(try rebuilt.entries(relativePath: "Deleted.md").isEmpty)
    }

    @Test("A newly created note supersedes an old path tombstone")
    func newNoteClearsTombstone() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var ledger: PrewriteRecoveryLedger? = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        let deleted = try #require(
            try ledger?.prepare(relativePath: "Reused.md", data: Data("deleted".utf8))
        )
        try ledger?.commit(deleted)
        try ledger?.tombstoneAndPurge(relativePath: "Reused.md")
        let replacement = try #require(
            try ledger?.prepare(relativePath: "Reused.md", data: Data("new note".utf8))
        )
        try ledger?.commit(replacement)
        ledger = nil
        try Data("corrupt".utf8).write(
            to: fixture.recovery.appendingPathComponent("history.sqlite"),
            options: .atomic
        )

        let rebuilt = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        #expect(try rebuilt.entries(relativePath: "Reused.md").map(\.id) == [replacement.id])
        #expect(try rebuilt.content(entryID: replacement.id) == Data("new note".utf8))
    }

    @Test("Remap is idempotent and retains exact recovery bytes")
    func remap() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let ledger = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        let entry = try ledger.prepare(relativePath: "Before.md", data: Data("exact".utf8))
        try ledger.commit(entry)
        try ledger.remap(from: "Before.md", to: "Folder/After.md")
        try ledger.remap(from: "Before.md", to: "Folder/After.md")
        #expect(try ledger.entries(relativePath: "Before.md").isEmpty)
        #expect(try ledger.entries(relativePath: "Folder/After.md").map(\.id) == [entry.id])
        #expect(try ledger.content(entryID: entry.id) == Data("exact".utf8))
    }

    @Test("Startup replay retains uncommitted candidates and cleans canonical candidates")
    func mutationReplay() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let note = fixture.vault.appendingPathComponent("Note.md")
        let expected = Data("expected".utf8)
        let candidate = Data("candidate".utf8)
        try expected.write(to: note)

        var ledger: PrewriteRecoveryLedger? = try PrewriteRecoveryLedger(
            storageURL: fixture.storage
        )
        let interrupted = try #require(try ledger?.beginMutation(
            relativePath: "Note.md",
            expected: expected,
            candidate: candidate
        ))
        ledger = nil
        ledger = try PrewriteRecoveryLedger(storageURL: fixture.storage, vaultURL: fixture.vault)
        #expect(try ledger?.pendingMutations().map(\.id) == [interrupted.id])
        #expect(ledger?.healthDiagnostic?.contains("candidate bytes remain") == true)
        let interruptedCandidate = fixture.storage
            .appendingPathComponent("recovery-v2/transactions/mutations", isDirectory: true)
            .appendingPathComponent(interrupted.id.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("candidate.md")
        #expect(try Data(contentsOf: interruptedCandidate) == candidate)

        try ledger?.completeMutation(interrupted)
        try candidate.write(to: note)
        _ = try ledger?.beginMutation(
            relativePath: "Note.md",
            expected: expected,
            candidate: candidate
        )
        ledger = nil
        ledger = try PrewriteRecoveryLedger(storageURL: fixture.storage, vaultURL: fixture.vault)
        #expect(try ledger?.pendingMutations().isEmpty == true)

        try expected.write(to: note)
        let uncertain = try #require(try ledger?.beginMutation(
            relativePath: "Note.md",
            expected: expected,
            candidate: candidate
        ))
        try Data("external".utf8).write(to: note)
        ledger = nil
        ledger = try PrewriteRecoveryLedger(storageURL: fixture.storage, vaultURL: fixture.vault)
        #expect(try ledger?.pendingMutations().map(\.id) == [uncertain.id])
        #expect(ledger?.healthDiagnostic != nil)
    }

    @Test("Startup replay rejects a substituted parent symlink")
    func mutationReplayRejectsParentSymlink() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let folder = fixture.vault.appendingPathComponent("Folder", isDirectory: true)
        let note = folder.appendingPathComponent("Note.md")
        let detached = fixture.root.appendingPathComponent("Detached", isDirectory: true)
        let expected = Data("expected".utf8)
        let candidate = Data("candidate".utf8)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try expected.write(to: note)

        var ledger: PrewriteRecoveryLedger? = try PrewriteRecoveryLedger(
            storageURL: fixture.storage
        )
        let transaction = try #require(try ledger?.beginMutation(
            relativePath: "Folder/Note.md",
            expected: expected,
            candidate: candidate
        ))
        ledger = nil
        try FileManager.default.moveItem(at: folder, to: detached)
        try candidate.write(to: detached.appendingPathComponent("Note.md"))
        try FileManager.default.createSymbolicLink(
            at: folder,
            withDestinationURL: detached
        )

        let reopened = try PrewriteRecoveryLedger(
            storageURL: fixture.storage,
            vaultURL: fixture.vault
        )
        #expect(try reopened.pendingMutations().map(\.id) == [transaction.id])
        #expect(reopened.healthDiagnostic?.contains("could not be verified") == true)
        #expect(try Data(contentsOf: detached.appendingPathComponent("Note.md")) == candidate)
    }

    @Test("Startup replay rejects a substituted recovery candidate symlink")
    func mutationReplayRejectsCandidateSymlink() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let note = fixture.vault.appendingPathComponent("Note.md")
        let expected = Data("expected".utf8)
        let candidate = Data("candidate".utf8)
        try expected.write(to: note)

        var ledger: PrewriteRecoveryLedger? = try PrewriteRecoveryLedger(
            storageURL: fixture.storage
        )
        let transaction = try #require(try ledger?.beginMutation(
            relativePath: "Note.md",
            expected: expected,
            candidate: candidate
        ))
        ledger = nil
        let transactionDirectory = fixture.recovery
            .appendingPathComponent("transactions/mutations", isDirectory: true)
            .appendingPathComponent(
                transaction.id.uuidString.lowercased(),
                isDirectory: true
            )
        let candidateURL = transactionDirectory.appendingPathComponent("candidate.md")
        let detached = fixture.root.appendingPathComponent("Detached Candidate.md")
        try FileManager.default.moveItem(at: candidateURL, to: detached)
        try FileManager.default.createSymbolicLink(
            at: candidateURL,
            withDestinationURL: detached
        )

        let reopened = try PrewriteRecoveryLedger(
            storageURL: fixture.storage,
            vaultURL: fixture.vault
        )
        #expect(try reopened.pendingMutations().map(\.id) == [transaction.id])
        #expect(reopened.healthDiagnostic?.contains("could not be verified") == true)
        #expect(try reopened.retainedMutations().isEmpty)
        #expect(try Data(contentsOf: detached) == candidate)
        #expect(try Data(contentsOf: note) == expected)
    }

    private final class Fixture {
        let root: URL
        let storage: URL
        let vault: URL
        var recovery: URL { storage.appendingPathComponent("recovery-v2", isDirectory: true) }

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("Scholium-RecoveryLedger-\(UUID().uuidString)")
            storage = root.appendingPathComponent("Vault", isDirectory: true)
            vault = root.appendingPathComponent("Research", isDirectory: true)
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    private final class SendableLedgerBox: @unchecked Sendable {
        let ledger: PrewriteRecoveryLedger

        init(_ ledger: PrewriteRecoveryLedger) {
            self.ledger = ledger
        }
    }
}
