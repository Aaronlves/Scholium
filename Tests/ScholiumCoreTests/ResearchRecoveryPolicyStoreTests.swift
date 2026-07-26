import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Research recovery policy store")
struct ResearchRecoveryPolicyStoreTests {
    @Test("Settled retention exposes only the four bounded policies")
    func retentionContract() {
        #expect(Set(SettledSnapshotRetention.allCases) == [
            .keep10, .keep30, .keep50, .neverDelete,
        ])
        #expect(SettledSnapshotRetention.defaultValue == .keep30)
        #expect(SettledSnapshotRetention.keep10.maximumCount == 10)
        #expect(SettledSnapshotRetention.keep30.maximumCount == 30)
        #expect(SettledSnapshotRetention.keep50.maximumCount == 50)
        #expect(SettledSnapshotRetention.neverDelete.maximumCount == nil)
    }

    @Test("The policy defaults to thirty and saves with revision checking")
    func defaultsAndRevisionChecking() async throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let triptychID = UUID()
        let store = try ResearchRecoveryPolicyStore(
            storageURL: root.appendingPathComponent("policy", isDirectory: true),
            triptychID: triptychID
        )

        let initial = try await store.snapshot()
        #expect(initial.retention == .keep30)
        #expect(initial.revision == nil)
        let saved = try await store.save(.keep10, expectedRevision: nil)
        #expect(saved.retention == .keep10)
        #expect(saved.revision != nil)
        await #expect(throws: ResearchRecoveryPolicyError.staleRevision) {
            _ = try await store.save(.keep50, expectedRevision: nil)
        }

        let reopened = try ResearchRecoveryPolicyStore(
            storageURL: root.appendingPathComponent("policy", isDirectory: true),
            triptychID: triptychID
        )
        #expect(try await reopened.snapshot().retention == .keep10)
    }

    @Test("A policy file bound to another Triptych fails closed")
    func triptychBinding() async throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let storage = root.appendingPathComponent("policy", isDirectory: true)
        let first = try ResearchRecoveryPolicyStore(
            storageURL: storage,
            triptychID: UUID()
        )
        _ = try await first.save(.neverDelete, expectedRevision: nil)
        let second = try ResearchRecoveryPolicyStore(
            storageURL: storage,
            triptychID: UUID()
        )
        await #expect(throws: ResearchRecoveryPolicyError.corruptStore) {
            _ = try await second.snapshot()
        }
    }

    @Test("Approved removals survive interruption and clear only after idempotent completion")
    func pendingRemovalJournal() async throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let triptychID = UUID()
        let storage = root.appendingPathComponent("policy", isDirectory: true)
        let store = try ResearchRecoveryPolicyStore(
            storageURL: storage,
            triptychID: triptychID
        )
        let approved = Set([UUID(), UUID()])
        let pending = try await store.beginChange(
            .keep10,
            approvedSnapshotIDsToRemove: approved,
            expectedRevision: nil
        )
        #expect(pending.snapshot.retention == .keep10)
        #expect(pending.pendingSnapshotIDsToRemove == approved)
        await #expect(throws: ResearchRecoveryPolicyError.stalePreview) {
            _ = try await store.save(
                .keep50,
                expectedRevision: pending.snapshot.revision
            )
        }

        let reopened = try ResearchRecoveryPolicyStore(
            storageURL: storage,
            triptychID: triptychID
        )
        #expect(try await reopened.state().pendingSnapshotIDsToRemove == approved)
        let completed = try await reopened.finishPendingChange(
            retention: .keep10,
            approvedSnapshotIDsToRemove: approved,
            expectedRevision: pending.snapshot.revision
        )
        #expect(completed.retention == .keep10)
        #expect(try await reopened.state().pendingSnapshotIDsToRemove.isEmpty)
        #expect(try await reopened.finishPendingChange(
            retention: .keep10,
            approvedSnapshotIDsToRemove: approved,
            expectedRevision: pending.snapshot.revision
        ).retention == .keep10)
    }

    @Test("The pending journal safely exceeds the former 64 KiB boundary")
    func pendingJournalHasAlignedCapacity() async throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let triptychID = UUID()
        let storage = root.appendingPathComponent("policy", isDirectory: true)
        let store = try ResearchRecoveryPolicyStore(
            storageURL: storage,
            triptychID: triptychID
        )
        let approved = Set((0..<2_000).map { _ in UUID() })

        let pending = try await store.beginChange(
            .keep10,
            approvedSnapshotIDsToRemove: approved,
            expectedRevision: nil
        )
        #expect(pending.pendingSnapshotIDsToRemove == approved)
        let bytes = try Data(contentsOf: storage.appendingPathComponent("policy.json"))
        #expect(bytes.count > 64 * 1_024)

        let reopened = try ResearchRecoveryPolicyStore(
            storageURL: storage,
            triptychID: triptychID
        )
        #expect(try await reopened.state().pendingSnapshotIDsToRemove == approved)
    }

    private func fixtureRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/recovery-policy-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
