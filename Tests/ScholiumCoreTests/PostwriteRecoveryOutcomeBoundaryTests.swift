import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Postwrite recovery outcome boundary")
struct PostwriteRecoveryOutcomeBoundaryTests {
    @Test("A changed recovery identity after replacement retains uncertainty and exact bytes")
    func postwriteRecoveryIdentityTamperRemainsUncertain() async throws {
        let fixture = try RecoveryOutcomeFixture()
        defer { fixture.remove() }
        let repository = try fixture.repository(
            hooks: VaultMutationHooks(didReach: { phase in
                if phase == .replaced { try fixture.tamperRecoveryCreationIdentity() }
            }))
        let before = try await repository.load(relativePath: fixture.relativePath)

        do {
            _ = try await repository.saveOutcome(
                relativePath: fixture.relativePath, changeSet: .source(fixture.candidate),
                expectedRevision: before.fingerprint)
            Issue.record("An unverified recovery identity must not produce a completed save.")
        } catch let error as VaultRepositoryError {
            if case .commitUncertain = error {
                // The source crossed replacement but its recovery binding is unproved.
            } else {
                Issue.record("Postwrite recovery refusal must retain commit uncertainty; received \(error).")
            }
            #expect(!error.localizedDescription.contains("did not modify the note"))
        }

        #expect(try Data(contentsOf: fixture.note) == Data(fixture.candidate.utf8))
        let directory = try fixture.onlyTransactionDirectory()
        let originalManifest = try Data(contentsOf: directory.appendingPathComponent("manifest-before-tamper.json"))
        let original = try fixture.decodeManifest(originalManifest)
        let changed = try fixture.decodeManifest(Data(contentsOf: directory.appendingPathComponent("manifest.json")))
        #expect(changed.createdAt != original.createdAt)
        #expect(changed.id == original.id)
        #expect(try Data(contentsOf: directory.appendingPathComponent("expected.md")) == fixture.before)
        #expect(try Data(contentsOf: directory.appendingPathComponent("candidate.md")) == Data(fixture.candidate.utf8))
        #expect(try Data(contentsOf: fixture.vault.appendingPathComponent(try original.backupPath.rawValue)) == fixture.before)
    }

    @Test("A recovery store obstruction before replacement truthfully leaves the source unchanged")
    func prewriteLedgerFailureRemainsDefinite() async throws {
        let fixture = try RecoveryOutcomeFixture()
        defer { fixture.remove() }
        let repository = try fixture.repository()
        let before = try await repository.load(relativePath: fixture.relativePath)
        // Keep every initialized store byte; only the disposable pathname is obstructed.
        try FileManager.default.moveItem(
            at: fixture.ledger,
            to: fixture.ledger.deletingLastPathComponent().appendingPathComponent("ledger-before-obstruction"))
        try Data("Synthetic prewrite obstruction".utf8).write(to: fixture.ledger)

        do {
            _ = try await repository.saveOutcome(
                relativePath: fixture.relativePath, changeSet: .source(fixture.candidate),
                expectedRevision: before.fingerprint)
            Issue.record("An unavailable prewrite ledger must refuse the save.")
        } catch let error as VaultRepositoryError {
            if case .recoveryLedgerUnavailable = error {
                #expect(error.localizedDescription.contains("did not modify the note"))
            } else {
                Issue.record("A prewrite ledger failure must keep its definite refusal; received \(error).")
            }
        }
        #expect(try Data(contentsOf: fixture.note) == fixture.before)
    }

    @Test("A replacement failure with proven unchanged source remains retryable")
    func unchangedCanonicalReplacementFailureRemainsRetryable() async throws {
        let fixture = try RecoveryOutcomeFixture()
        defer { fixture.remove() }
        let repository = try fixture.repository(
            hooks: VaultMutationHooks(didReach: { phase in
                if phase == .replacing { throw RecoveryOutcomeFixture.Fault.beforeReplacement }
            }))
        let before = try await repository.load(relativePath: fixture.relativePath)

        do {
            _ = try await repository.saveOutcome(
                relativePath: fixture.relativePath, changeSet: .source(fixture.candidate),
                expectedRevision: before.fingerprint)
            Issue.record("The injected pre-replacement failure must refuse the save.")
        } catch let error as VaultRepositoryError {
            if case .writeFailed = error {
                #expect(error.localizedDescription.contains("source remains unchanged"))
            } else {
                Issue.record("Proven unchanged source must remain retryable; received \(error).")
            }
        }
        #expect(try Data(contentsOf: fixture.note) == fixture.before)
        #expect(try await repository.interruptedSaveRecoveries().isEmpty)
    }
}

private struct RecoveryOutcomeFixture: Sendable {
    enum Fault: Error { case beforeReplacement }

    let root: URL
    let vault: URL
    let support: URL
    let identity: VaultIdentity
    let relativePath = "Note.md"
    let before = Data("\u{FEFF}# Before\r\nExact e\u{301} source.\r\n".utf8)
    let candidate = "\u{FEFF}# Candidate\r\nKeep 中文 e\u{301} 📝 exactly.\r\n"

    var note: URL { vault.appendingPathComponent(relativePath) }
    var ledger: URL {
        support.appendingPathComponent("Vaults", isDirectory: true)
            .appendingPathComponent(identity.id.uuidString, isDirectory: true)
            .appendingPathComponent("save-transactions-v2", isDirectory: true)
    }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScholiumRecoveryOutcome-\(UUID().uuidString)", isDirectory: true)
        vault = root.appendingPathComponent("Vault", isDirectory: true)
        support = root.appendingPathComponent("Support", isDirectory: true)
        identity = VaultIdentity(id: UUID(), canonicalPath: vault.path, bookmarkData: nil)
        do {
            try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            try before.write(to: vault.appendingPathComponent(relativePath))
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    func repository(hooks: VaultMutationHooks = .none) throws -> VaultRepository {
        try VaultRepository(
            vaultURL: vault, identity: identity, applicationSupportURL: support,
            mutationHooks: hooks)
    }

    func onlyTransactionDirectory() throws -> URL {
        let entries = try FileManager.default.contentsOfDirectory(
            at: ledger, includingPropertiesForKeys: nil
        )
        .filter { UUID(uuidString: $0.lastPathComponent) != nil }
        #expect(entries.count == 1)
        return try #require(entries.first)
    }

    func decodeManifest(_ data: Data) throws -> PrewriteRecoveryLedger.MutationTransaction {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PrewriteRecoveryLedger.MutationTransaction.self, from: data)
    }

    func tamperRecoveryCreationIdentity() throws {
        let directory = try onlyTransactionDirectory()
        let manifest = directory.appendingPathComponent("manifest.json")
        let originalData = try Data(contentsOf: manifest)
        let original = try decodeManifest(originalData)
        try originalData.write(to: directory.appendingPathComponent("manifest-before-tamper.json"))
        var fields = try #require(JSONSerialization.jsonObject(with: originalData) as? [String: Any])
        fields["createdAt"] = ISO8601DateFormatter().string(from: original.createdAt.addingTimeInterval(1))
        try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]).write(to: manifest, options: .atomic)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
