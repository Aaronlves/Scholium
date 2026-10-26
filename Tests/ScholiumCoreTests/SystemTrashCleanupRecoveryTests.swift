import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Targeted system-Trash cleanup", .timeLimit(.minutes(1)))
struct SystemTrashCleanupRecoveryTests {
    @Test("Cleanup targets one proved record and never moves a recreated original")
    func completedCleanupIsTargeted() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let completed = fixture.record(progress: .movedToSystemTrash)
        try await fixture.recovery.record(completed)
        let unrelated = fixture.record(progress: .outcomeUnknown)
        try await fixture.recovery.record(unrelated)
        let commit = try await fixture.coordinator().recoverInterruptedTransaction(completed.id)
        #expect(commit.planID == completed.id && commit.noteIDs == [fixture.noteID])
        #expect(commit.pendingCleanupRecovery == nil)
        #expect(try await fixture.recovery.pending() == [unrelated])
        #expect(try Data(contentsOf: fixture.note) == fixture.bytes)
    }

    @Test("Unknown or incomplete receipt sets cannot authorize cleanup or another move", arguments: [false, true])
    func unprovedRecordIsRetained(missingReceipt: Bool) async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let record = fixture.record(progress: .outcomeUnknown, missingReceipt: missingReceipt)
        try await fixture.recovery.record(record)
        await #expect(throws: TriptychTransactionError.self) {
            try await fixture.coordinator().recoverInterruptedTransaction(record.id)
        }
        #expect(try await fixture.recovery.pending() == [record])
        #expect(try Data(contentsOf: fixture.note) == fixture.bytes)
    }

    @Test("A partial plan interrupted before native dispatch remains recovery, never completed")
    func partialPlanCannotBecomeCompletion() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let original = fixture.source()
        let moved = SystemTrashDeletionSourceTarget(
            vaultID: fixture.vaultID, relativePath: "Already moved.md", kind: .note,
            notes: [.init(noteID: UUID(), relativePath: "Already moved.md", expectedRevision: .init(content: "earlier"))])
        let preview = SystemTrashDeletionPreview(triptychID: fixture.triptychID, sources: [moved, original])
        let plan = SystemTrashDeletionPlan(
            preview: preview,
            sourceReceipts: [
                .init(targetID: moved.id, progress: .movedToSystemTrash, resultingTrashPath: "/synthetic/Trash/Already moved.md"),
                .init(targetID: original.id, progress: .pending),
            ])
        let record = fixture.record(plan)
        try await fixture.recovery.record(record)
        let coordinator = fixture.coordinator(expectsDispatchBoundary: true)
        let attempt = Task { try await coordinator.recoverInterruptedTransaction(record.id) }
        defer { attempt.cancel() }
        do {
            _ = try await attempt.value
            Issue.record("Partial receipts cannot be reported as completed")
        } catch TriptychTransactionError.recoveryRequired(let retained) {
            #expect(retained.systemTrashDeletionPlan?.sourceReceipts.map(\.progress) == [.movedToSystemTrash, .outcomeUnknown])
        }
        #expect(try await fixture.recovery.pending().count == 1)
        #expect(try Data(contentsOf: fixture.note) == fixture.bytes)
    }

    @Test("A failed durable cleanup-record write cannot be downgraded to completed cleanup")
    func persistenceFailureRemainsFailure() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let record = fixture.record(progress: .movedToSystemTrash)
        try await fixture.recovery.record(record)
        let failing = try TriptychMutationRecoveryStore(
            storageURL: fixture.recovery.storageURL,
            preCommitFault: { name in if name.hasSuffix(".json") { throw CocoaError(.fileWriteNoPermission) } })
        do {
            _ = try await fixture.coordinator(recovery: failing).recoverInterruptedTransaction(record.id)
            Issue.record("Persistence failure must remain explicit")
        } catch TriptychTransactionError.recoveryPersistenceFailed(let retained, _) {
            #expect(retained.id == record.id)
            #expect(retained.systemTrashDeletionPlan?.sourceReceipts.allSatisfy { $0.progress == .movedToSystemTrash } == true)
        }
        #expect(try await fixture.recovery.pending() == [record])
        #expect(try Data(contentsOf: fixture.note) == fixture.bytes)
    }

    private struct Fixture {
        let root: URL
        let note: URL
        let bytes: Data
        let triptychID: UUID
        let vaultID: UUID
        let noteID: UUID
        let repository: VaultRepository
        let control: TriptychControlStore
        let recovery: TriptychMutationRecoveryStore

        static func make() async throws -> Self {
            let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let root = repositoryRoot.appendingPathComponent(".build/trash-cleanup-fixtures/\(UUID())", isDirectory: true)
            var completed = false
            defer { if !completed { try? FileManager.default.removeItem(at: root) } }
            let vault = root.appendingPathComponent("Vault", isDirectory: true)
            let works = root.appendingPathComponent("Works", isDirectory: true)
            for path in [vault, works] { try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true) }
            let note = vault.appendingPathComponent("Recreated.md")
            let bytes = Data("\u{FEFF}Recreated exact source e\u{301} 🦉.\r\n".utf8)
            try bytes.write(to: note)
            let triptychID = UUID()
            let vaultID = UUID()
            let repository = try VaultRepository(
                vaultURL: vault, identity: .init(id: vaultID, canonicalPath: vault.path, bookmarkData: nil),
                applicationSupportURL: root.appendingPathComponent("Support"))
            let control = TriptychControlStore(worksVaultURL: works)
            _ = try await control.bootstrap(
                vaultIDs: [.paperAnalysis: vaultID, .topicKnowledge: UUID(), .output: UUID()], preferredTriptychID: triptychID)
            let identity = try #require(
                try await control.identity(
                    forVaultID: vaultID, relativePath: note.lastPathComponent, fingerprint: .init(data: bytes)))
            let recovery = try TriptychMutationRecoveryStore(storageURL: root.appendingPathComponent("Recovery", isDirectory: true))
            completed = true
            return Self(
                root: root, note: note, bytes: bytes, triptychID: triptychID, vaultID: vaultID,
                noteID: identity.id, repository: repository, control: control, recovery: recovery)
        }

        func source() -> SystemTrashDeletionSourceTarget {
            .init(
                vaultID: vaultID, relativePath: note.lastPathComponent, kind: .note,
                notes: [.init(noteID: noteID, relativePath: note.lastPathComponent, expectedRevision: .init(data: bytes))])
        }

        func record(progress: SystemTrashDeletionSourceProgress, missingReceipt: Bool = false) -> TriptychMutationRecoveryRecord {
            let source = source()
            let preview = SystemTrashDeletionPreview(triptychID: triptychID, sources: [source])
            return record(
                .init(
                    preview: preview,
                    sourceReceipts: missingReceipt
                        ? []
                        : [
                            .init(
                                targetID: source.id, progress: progress,
                                resultingTrashPath: progress == .movedToSystemTrash ? "/synthetic/Trash/Recreated.md" : nil)
                        ]))
        }

        func record(_ plan: SystemTrashDeletionPlan) -> TriptychMutationRecoveryRecord {
            .init(
                id: plan.id, triptychID: triptychID, createdAt: Date(), failure: "Synthetic receipt",
                files: [], systemTrashDeletionPlan: plan)
        }

        func coordinator(recovery store: TriptychMutationRecoveryStore? = nil, expectsDispatchBoundary: Bool = false) -> NoteSystemTrashDeletionCoordinator {
            NoteSystemTrashDeletionCoordinator(
                triptychID: triptychID, repository: repository, controlStore: control, recoveryStore: store ?? recovery,
                faultPlan: .none,
                nativeDispatchBarrierForTesting: {
                    if !expectsDispatchBoundary { Issue.record("Recorded completion must not dispatch native Trash") }
                    // The controlled boundary cancels before Core can invoke native
                    // Trash. Even a regression cannot move this fixture's source.
                    withUnsafeCurrentTask { $0?.cancel() }
                })
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
