import Foundation
@testable import ScholiumCore
import Testing

@Suite("Interrupted save transactions")
struct PrewriteRecoveryLedgerTests {
    @Test("A proven completed save leaves no transaction history")
    func completedMutationDisappears() throws {
        let fixture = try Fixture()
        let ledger = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        let transaction = try ledger.beginMutation(
            relativePath: "Topics/Value.md",
            expected: Data("before".utf8),
            candidate: Data("after".utf8)
        )
        try ledger.completeMutation(transaction)
        #expect(try ledger.retainedMutations().isEmpty)
        #expect(!FileManager.default.fileExists(
            atPath: fixture.transactionDirectory(transaction.id).path
        ))
    }

    @Test("Only explicitly retained uncertainty is researcher-visible")
    func retainedMutationKeepsExactCandidate() throws {
        let fixture = try Fixture()
        let ledger = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        let transaction = try ledger.beginMutation(
            relativePath: "Topics/Value.md",
            expected: Data("before".utf8),
            candidate: Data("after".utf8)
        )
        try ledger.retainMutation(transaction, reason: "Commit could not be proven.")
        let retained = try #require(ledger.retainedMutations().only)
        #expect(retained.id == transaction.id)
        #expect(retained.retainedReason == "Commit could not be proven.")
        #expect(try ledger.candidateData(for: retained) == Data("after".utf8))
    }

    @Test("Startup removes a transaction whose candidate is canonical")
    func replaySettlesCanonicalCandidate() throws {
        let fixture = try Fixture()
        try fixture.writeVault("after", path: "Topics/Value.md")
        let first = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        let transaction = try first.beginMutation(
            relativePath: "Topics/Value.md",
            expected: Data("before".utf8),
            candidate: Data("after".utf8)
        )
        _ = try PrewriteRecoveryLedger(
            storageURL: fixture.storage,
            vaultURL: fixture.vault
        )
        #expect(!FileManager.default.fileExists(
            atPath: fixture.transactionDirectory(transaction.id).path
        ))
    }

    @Test("Startup retains a candidate when canonical source stayed expected")
    func replayRetainsUncommittedCandidate() throws {
        let fixture = try Fixture()
        try fixture.writeVault("before", path: "Topics/Value.md")
        let first = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        _ = try first.beginMutation(
            relativePath: "Topics/Value.md",
            expected: Data("before".utf8),
            candidate: Data("after".utf8)
        )
        let reopened = try PrewriteRecoveryLedger(
            storageURL: fixture.storage,
            vaultURL: fixture.vault
        )
        let retained = try #require(reopened.retainedMutations().only)
        #expect(retained.relativePath == "Topics/Value.md")
        #expect(try reopened.candidateData(for: retained) == Data("after".utf8))
    }

    @Test("A retained transaction remaps with its Note path")
    func remapRetainedTransaction() throws {
        let fixture = try Fixture()
        let ledger = try PrewriteRecoveryLedger(storageURL: fixture.storage)
        let transaction = try ledger.beginMutation(
            relativePath: "Topics/Old.md",
            expected: Data("before".utf8),
            candidate: Data("after".utf8)
        )
        try ledger.retainMutation(transaction, reason: "Interrupted")
        try ledger.remapRetainedTransactions(
            from: "Topics/Old.md",
            to: "Topics/New.md"
        )
        #expect(try ledger.retainedMutation(id: transaction.id).relativePath
            == "Topics/New.md")
    }
}

private struct Fixture {
    let root: URL
    let storage: URL
    let vault: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = root.appendingPathComponent("Support", isDirectory: true)
        vault = root.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
    }

    func transactionDirectory(_ id: UUID) -> URL {
        storage.appendingPathComponent("save-transactions-v1", isDirectory: true)
            .appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    func writeVault(_ content: String, path: String) throws {
        let url = vault.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(content.utf8).write(to: url)
    }
}

private extension Collection {
    var only: Element? { count == 1 ? first : nil }
}
