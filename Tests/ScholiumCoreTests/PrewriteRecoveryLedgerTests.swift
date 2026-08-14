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

    @Test("Settled revisions are deduplicated and protected from temporary retention")
    func settledPinsAreDistinctDurableReferences() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let ledger = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        let noteID = UUID()
        let settledData = Data("settled exact bytes".utf8)

        let first = try ledger.pinSettled(
            relativePath: "Note.md",
            noteID: noteID,
            data: settledData
        )
        let duplicate = try ledger.pinSettled(
            relativePath: "Note.md",
            noteID: noteID,
            data: settledData
        )
        #expect(first.wasCreated)
        #expect(!duplicate.wasCreated)
        #expect(first.pin.id == duplicate.pin.id)

        for index in 0..<14 {
            let entry = try ledger.prepare(
                relativePath: "Note.md",
                data: Data("temporary-\(index)".utf8)
            )
            try ledger.commit(entry)
        }
        #expect(try ledger.settledPins(noteID: noteID).map(\.id) == [first.pin.id])
        #expect(try ledger.content(entryID: first.pin.entry.id) == settledData)
        #expect(try ledger.entries(relativePath: "Note.md").count == 11)
    }

    @Test("Settled pin manifests rebuild after database quarantine and are removed with tombstones")
    func settledPinsRebuildAndPurge() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let noteID = UUID()
        var ledger: PrewriteRecoveryLedger? = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        let pin = try #require(try ledger?.pinSettled(
            relativePath: "Note.md",
            noteID: noteID,
            data: Data("settled".utf8)
        ).pin)
        ledger = nil
        try Data("corrupt".utf8).write(
            to: fixture.recovery.appendingPathComponent("history.sqlite"),
            options: .atomic
        )

        ledger = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        #expect(try ledger?.settledPins(noteID: noteID).map(\.id) == [pin.id])
        try ledger?.tombstoneAndPurge(relativePath: "Note.md")
        ledger = nil

        let reopened = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        #expect(try reopened.settledPins(noteID: noteID).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(
            at: fixture.recovery.appendingPathComponent("settled", isDirectory: true),
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }.isEmpty)
    }

    @Test("An invalid settled manifest cannot remain authoritative through a derived database row")
    func invalidSettledManifestIsExcluded() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let noteID = UUID()
        var ledger: PrewriteRecoveryLedger? = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        let pin = try #require(try ledger?.pinSettled(
            relativePath: "Note.md",
            noteID: noteID,
            data: Data("settled".utf8)
        ).pin)
        ledger = nil
        try Data("not a manifest".utf8).write(
            to: fixture.recovery
                .appendingPathComponent("settled", isDirectory: true)
                .appendingPathComponent(pin.id.uuidString.lowercased() + ".json"),
            options: .atomic
        )

        let reopened = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        #expect(try reopened.settledPins(noteID: noteID).isEmpty)
        #expect(reopened.healthDiagnostic?.contains("settled snapshot reference") == true)
        #expect(try reopened.content(entryID: pin.entry.id) == Data("settled".utf8))
    }

    @Test("Settled retention removes only revisions beyond each Note limit")
    func settledRetentionIsPerNote() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let ledger = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        let firstNote = UUID()
        let secondNote = UUID()
        for index in 0..<12 {
            _ = try ledger.pinSettled(
                relativePath: "First.md",
                noteID: firstNote,
                data: Data("first-\(index)".utf8)
            )
        }
        for index in 0..<4 {
            _ = try ledger.pinSettled(
                relativePath: "Second.md",
                noteID: secondNote,
                data: Data("second-\(index)".utf8)
            )
        }

        let removals = try ledger.settledSnapshotIDsToRemove(maximumCount: 10)
        #expect(removals.count == 2)
        #expect(try ledger.removeSettledPins(removals) == 2)
        let retainedFirst = try ledger.settledPins(noteID: firstNote)
        #expect(retainedFirst.count == 10)
        #expect(Set(retainedFirst.map(\.entry.fingerprint)) == Set((2..<12).map {
            DocumentFingerprint(data: Data("first-\($0)".utf8))
        }))
        #expect(try ledger.settledPins(noteID: secondNote).count == 4)
        #expect(try ledger.settledSnapshotIDsToRemove(maximumCount: nil).isEmpty)
    }

    @Test("A valid manifest repairs a logically inconsistent derived SQLite row")
    func manifestRepairsMismatchedDerivedRow() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let noteID = UUID()
        var ledger: PrewriteRecoveryLedger? = try PrewriteRecoveryLedger(
            storageURL: fixture.storage
        )
        let pin = try #require(try ledger?.pinSettled(
            relativePath: "Note.md",
            noteID: noteID,
            data: Data("settled".utf8)
        ).pin)
        ledger = nil

        var database: OpaquePointer?
        #expect(sqlite3_open(fixture.recovery
            .appendingPathComponent("history.sqlite").path, &database) == SQLITE_OK)
        defer { if let database { sqlite3_close(database) } }
        let wrongNoteID = UUID()
        let sql = "UPDATE settled_snapshots SET note_id = '\(wrongNoteID.uuidString)', settled_at = 1, settled_order = 999 WHERE id = '\(pin.id.uuidString)'"
        #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
        if let openedDatabase = database {
            sqlite3_close(openedDatabase)
            database = nil
        }

        let reopened = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        let repaired = try #require(reopened.settledPins(noteID: noteID).first)
        #expect(repaired.id == pin.id)
        #expect(repaired.settledOrder == pin.settledOrder)
        #expect(try reopened.settledPins(noteID: wrongNoteID).isEmpty)
    }

    @Test("Settled retention follows durable per-Note order when wall time moves backward")
    func settledRetentionUsesMonotonicOrder() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let noteID = UUID()
        var ledger: PrewriteRecoveryLedger? = try PrewriteRecoveryLedger(
            storageURL: fixture.storage
        )
        let first = try #require(try ledger?.pinSettled(
            relativePath: "Note.md",
            noteID: noteID,
            data: Data("first".utf8),
            createdAt: Date(timeIntervalSince1970: 2_000)
        ).pin)
        let second = try #require(try ledger?.pinSettled(
            relativePath: "Note.md",
            noteID: noteID,
            data: Data("second".utf8),
            createdAt: Date(timeIntervalSince1970: 1_000)
        ).pin)
        #expect(try ledger?.settledPins(noteID: noteID).map(\.id) == [second.id, first.id])
        ledger = nil

        let reopened = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        #expect(try reopened.settledPins(noteID: noteID).map(\.id) == [second.id, first.id])
        let removals = try reopened.settledSnapshotIDsToRemove(maximumCount: 1)
        #expect(removals == Set([first.id]))
    }

    @Test("Two ledger instances allocate unique settled order under one durable lock")
    func settledOrderIsCoordinatedAcrossLedgerInstances() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let noteID = UUID()
        let first = SendableLedgerBox(
            try PrewriteRecoveryLedger(storageURL: fixture.storage)
        )
        let second = SendableLedgerBox(
            try PrewriteRecoveryLedger(storageURL: fixture.storage)
        )

        let firstTask = Task.detached {
            try first.ledger.pinSettled(
                relativePath: "Note.md",
                noteID: noteID,
                data: Data("first".utf8)
            ).pin
        }
        let secondTask = Task.detached {
            try second.ledger.pinSettled(
                relativePath: "Note.md",
                noteID: noteID,
                data: Data("second".utf8)
            ).pin
        }
        let pins = try await [firstTask.value, secondTask.value]
        #expect(Set(pins.map(\.settledOrder)) == [1, 2])

        let reopened = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        #expect(Set(try reopened.settledPins(noteID: noteID).map(\.settledOrder))
            == [1, 2])
    }

    @Test("Settled deletion and another ledger reconciliation cannot resurrect a manifest")
    func settledDeletionIsCoordinatedWithReconciliation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let noteID = UUID()
        let first = SendableLedgerBox(
            try PrewriteRecoveryLedger(storageURL: fixture.storage)
        )
        let oldPin = try first.ledger.pinSettled(
            relativePath: "Note.md",
            noteID: noteID,
            data: Data("old".utf8)
        ).pin
        let second = SendableLedgerBox(
            try PrewriteRecoveryLedger(storageURL: fixture.storage)
        )

        let deletion = Task.detached {
            try first.ledger.removeSettledPins([oldPin.id])
        }
        let reconciliationAndPin = Task.detached {
            try second.ledger.pinSettled(
                relativePath: "Note.md",
                noteID: noteID,
                data: Data("new".utf8)
            ).pin
        }
        _ = try await deletion.value
        let newPin = try await reconciliationAndPin.value

        let reopened = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        #expect(try reopened.settledPins(noteID: noteID).map(\.id) == [newPin.id])
        let manifests = try FileManager.default.contentsOfDirectory(
            at: fixture.recovery.appendingPathComponent("settled", isDirectory: true),
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }.map(\.lastPathComponent)
        #expect(manifests == [newPin.id.uuidString.lowercased() + ".json"])
    }

    @Test("Ambiguous order never removes pin protection from validated exact bytes")
    func ambiguousOrderBlocksWritesAndProtectsBytes() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let noteID = UUID()
        let staleLedger = try PrewriteRecoveryLedger(
            storageURL: fixture.storage
        )
        let first = try staleLedger.pinSettled(
            relativePath: "Note.md",
            noteID: noteID,
            data: Data("first-settled".utf8)
        ).pin
        let second = try staleLedger.pinSettled(
            relativePath: "Note.md",
            noteID: noteID,
            data: Data("second-settled".utf8)
        ).pin
        var pendingEntries: [PrewriteRecoveryReference] = []
        for index in 0..<14 {
            pendingEntries.append(try staleLedger.prepare(
                relativePath: "Note.md",
                data: Data("pending-\(index)".utf8)
            ))
        }

        let secondManifestURL = fixture.recovery
            .appendingPathComponent("settled", isDirectory: true)
            .appendingPathComponent(second.id.uuidString.lowercased() + ".json")
        var manifest = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: secondManifestURL))
                as? [String: Any]
        )
        manifest["settledOrder"] = first.settledOrder
        try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: secondManifestURL, options: .atomic)

        let reopened = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        #expect(reopened.healthDiagnostic?.contains("ambiguous durable order") == true)
        #expect(try reopened.settledPins(noteID: noteID).count == 2)
        #expect(throws: VaultRepositoryError.self) {
            _ = try reopened.settledSnapshotIDsToRemove(maximumCount: 1)
        }
        #expect(throws: VaultRepositoryError.self) {
            _ = try reopened.removeSettledPins([first.id])
        }
        #expect(throws: VaultRepositoryError.self) {
            _ = try staleLedger.settledSnapshotIDsToRemove(maximumCount: 1)
        }
        #expect(throws: VaultRepositoryError.self) {
            _ = try staleLedger.removeSettledPins([first.id])
        }
        for entry in pendingEntries {
            try reopened.commit(entry)
        }
        #expect(try reopened.content(entryID: first.entry.id)
            == Data("first-settled".utf8))
        #expect(try reopened.content(entryID: second.entry.id)
            == Data("second-settled".utf8))
        #expect(try reopened.entries(relativePath: "Note.md").count == 16)
        #expect(throws: VaultRepositoryError.self) {
            _ = try reopened.prepare(
                relativePath: "Note.md",
                data: Data("must be blocked".utf8)
            )
        }
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
