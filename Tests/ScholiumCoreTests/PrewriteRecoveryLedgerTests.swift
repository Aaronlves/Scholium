import CryptoKit
import Foundation
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

    @Test("Verified v1 bytes migrate without modifying the legacy store")
    func verifiedLegacyMigration() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let legacy = fixture.storage.appendingPathComponent("versions", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let data = Data("legacy exact".utf8)
        let entry = PrewriteRecoveryReference(
            id: UUID(),
            relativePath: "Legacy.md",
            sequence: 1,
            createdAt: Date(),
            fingerprint: DocumentFingerprint(data: data)
        )
        let digest = SHA256.hash(data: Data(entry.relativePath.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let objectDirectory = legacy.appendingPathComponent(digest, isDirectory: true)
        try FileManager.default.createDirectory(at: objectDirectory, withIntermediateDirectories: true)
        let blob = objectDirectory.appendingPathComponent(entry.id.uuidString + ".md")
        try data.write(to: blob)
        let encoder = JSONEncoder()
        try encoder.encode(LegacyIndex(entries: [entry.relativePath: [entry]])).write(
            to: legacy.appendingPathComponent("index.json")
        )
        let originalIndex = try Data(contentsOf: legacy.appendingPathComponent("index.json"))

        let ledger = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        #expect(try ledger.entries(relativePath: entry.relativePath).map(\.id) == [entry.id])
        #expect(try ledger.content(entryID: entry.id) == data)
        #expect(try Data(contentsOf: blob) == data)
        #expect(try Data(contentsOf: legacy.appendingPathComponent("index.json")) == originalIndex)
        #expect(FileManager.default.fileExists(
            atPath: fixture.recovery.appendingPathComponent("v1-migration-complete.json").path
        ))
    }

    private struct LegacyIndex: Codable { let entries: [String: [PrewriteRecoveryReference]] }

    private final class Fixture {
        let root: URL
        let storage: URL
        var recovery: URL { storage.appendingPathComponent("recovery-v2", isDirectory: true) }

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("Scholium-RecoveryLedger-\(UUID().uuidString)")
            storage = root.appendingPathComponent("Vault", isDirectory: true)
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
