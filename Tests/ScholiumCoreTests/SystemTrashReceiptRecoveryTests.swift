import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Native Trash durable receipts")
struct SystemTrashReceiptRecoveryTests {
    @Test("The on-disk native-request boundary cannot replay a restored or recreated original path")
    func persistedStartedRequestCannotReplay() async throws {
        let gate = NativeTrashDispatchGate()
        let fixture = try await Fixture.make(barrier: { await gate.hold() })
        defer { fixture.remove() }
        let preview = try await fixture.preview()
        let interruptedProcess = Task {
            do { return try await fixture.coordinator.moveToSystemTrash(preview) } catch {
                await gate.failedBeforeEntry(error)
                throw error
            }
        }
        defer {
            interruptedProcess.cancel()
            Task { await gate.release() }
        }
        try await gate.waitUntilEntered()

        // Inspect only the durable store through a new owner while the original
        // invocation is still suspended: no thrown-error catch has run.
        let reopenedStore = try TriptychMutationRecoveryStore(storageURL: fixture.root.appendingPathComponent("Recovery", isDirectory: true))
        let durable = try #require(try await reopenedStore.pending().first)
        #expect(durable.systemTrashDeletionPlan?.sourceReceipts.first?.progress == .outcomeUnknown)
        try FileManager.default.moveItem(at: fixture.note, to: fixture.root.appendingPathComponent("Preserved original.md"))
        try fixture.bytes.write(to: fixture.note)
        let reopened = NoteSystemTrashDeletionCoordinator(
            triptychID: fixture.triptychID, repository: fixture.repository,
            controlStore: fixture.control, recoveryStore: reopenedStore)
        await #expect(throws: TriptychTransactionError.self) {
            try await reopened.recoverInterruptedTransactions()
        }
        #expect(try Data(contentsOf: fixture.note) == fixture.bytes)
        #expect(try await reopenedStore.pending().first?.systemTrashDeletionPlan?.sourceReceipts.first?.progress == .outcomeUnknown)

        interruptedProcess.cancel()
        await gate.release()
        await #expect(throws: TriptychTransactionError.self) { try await interruptedProcess.value }
        #expect(try Data(contentsOf: fixture.note) == fixture.bytes)
        try await reopened.resolveUnknownOutcome(recoveryRecordID: durable.id)
        #expect(try await reopenedStore.pending().isEmpty)
    }

    @Test("A native move whose receipt is interrupted remains unknown and cannot be dispatched again")
    func missingReceiptRetainsUnknownOutcome() async throws {
        let fixture = try await Fixture.make(point: .afterSystemTrashMoveBeforeReceipt)
        defer { fixture.remove() }
        let preview = try await fixture.preview()
        await #expect(throws: TriptychTransactionError.self) {
            try await fixture.coordinator.moveToSystemTrash(preview)
        }
        let record = try #require(try await fixture.recovery.pending().first)
        let receipt = try #require(record.systemTrashDeletionPlan?.sourceReceipts.first)
        #expect(receipt.progress == .outcomeUnknown)
        let destination = URL(fileURLWithPath: try #require(receipt.resultingTrashPath))
        defer { try? FileManager.default.removeItem(at: destination) }
        #expect(try Data(contentsOf: destination) == fixture.bytes)
        await #expect(throws: TriptychTransactionError.self) {
            try await fixture.coordinator.recoverInterruptedTransactions()
        }
        #expect(try await fixture.recovery.pending().first?.systemTrashDeletionPlan?.sourceReceipts.first?.resultingTrashPath == receipt.resultingTrashPath)
        // Researcher inspection/restoration releases only the unknown plan;
        // Scholium never infers a successful deletion from source absence.
        try FileManager.default.moveItem(at: destination, to: fixture.note)
        try await fixture.coordinator.resolveUnknownOutcome(recoveryRecordID: record.id)
        #expect(try await fixture.recovery.pending().isEmpty)
        #expect(try Data(contentsOf: fixture.note) == fixture.bytes)
        #expect(try await fixture.control.identityRecord(vaultID: fixture.vaultID, relativePath: fixture.note.lastPathComponent)?.id == fixture.noteID)
    }

    @Test("A persisted native move receipt resumes cleanup without another filesystem operation")
    func completedReceiptDoesNotRetryNativeMove() async throws {
        let fixture = try await Fixture.make(point: .afterSourceReceipts)
        defer { fixture.remove() }
        let preview = try await fixture.preview()
        await #expect(throws: TriptychTransactionError.self) {
            try await fixture.coordinator.moveToSystemTrash(preview)
        }
        let record = try #require(try await fixture.recovery.pending().first)
        let receipt = try #require(record.systemTrashDeletionPlan?.sourceReceipts.first)
        #expect(receipt.progress == .movedToSystemTrash)
        let destination = URL(fileURLWithPath: try #require(receipt.resultingTrashPath))
        defer { try? FileManager.default.removeItem(at: destination) }
        let resumed = NoteSystemTrashDeletionCoordinator(
            triptychID: fixture.triptychID, repository: fixture.repository,
            controlStore: fixture.control, recoveryStore: fixture.recovery)
        let commits = try await resumed.recoverInterruptedTransactions()
        #expect(commits.count == 1)
        #expect(commits.first?.resultingTrashPaths == [destination.path])
        #expect(try await fixture.recovery.pending().isEmpty)
        #expect(try Data(contentsOf: destination) == fixture.bytes)
        #expect(!FileManager.default.fileExists(atPath: fixture.note.path))
    }

    @Test("A proved predispatch source exchange releases its failed confirmation and accepts a fresh preview")
    func undispatchedFailureReleasesPlan() async throws {
        let replacement = Data("external revision\n".utf8)
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let repository = try VaultRepository(
            vaultURL: fixture.note.deletingLastPathComponent(),
            identity: await fixture.repository.identity,
            applicationSupportURL: fixture.root.appendingPathComponent("Support", isDirectory: true),
            mutationHooks: VaultMutationHooks(didReach: { phase in
                guard phase == .systemTrashReferenced else { return }
                // The final reference check fails before Finder receives anything.
                try replacement.write(to: fixture.note, options: .atomic)
            }))
        let coordinator = NoteSystemTrashDeletionCoordinator(
            triptychID: fixture.triptychID, repository: repository,
            controlStore: fixture.control, recoveryStore: fixture.recovery)
        let preview = try await fixture.preview()
        await #expect(throws: VaultRepositoryError.self) {
            try await coordinator.moveToSystemTrash(preview)
        }
        #expect(try await fixture.recovery.pending().isEmpty)
        #expect(try Data(contentsOf: fixture.note) == replacement)

        let identity = try #require(
            try await fixture.control.identity(
                forVaultID: fixture.vaultID, relativePath: fixture.note.lastPathComponent,
                fingerprint: DocumentFingerprint(data: replacement)))
        let fresh = try await fixture.coordinator.prepareNote(
            noteID: identity.id, vaultID: fixture.vaultID, relativePath: fixture.note.lastPathComponent,
            expectedRevision: DocumentFingerprint(data: replacement))
        let commit = try await fixture.coordinator.moveToSystemTrash(fresh)
        let destination = URL(fileURLWithPath: try #require(commit.resultingTrashPaths.first))
        defer { try? FileManager.default.removeItem(at: destination) }
        #expect(try Data(contentsOf: destination) == replacement)
        #expect(try await fixture.recovery.pending().isEmpty)
    }

    @Test("A restarted all-pending plan with a changed source releases its deletion gate without native dispatch")
    func restartedPreflightFailureReleasesPlan() async throws {
        let fixture = try await Fixture.make(point: .afterPlanPersistence)
        defer { fixture.remove() }
        let preview = try await fixture.preview()
        await #expect(throws: (any Error).self) {
            try await fixture.coordinator.moveToSystemTrash(preview)
        }
        #expect(try await fixture.recovery.pending().first?.systemTrashDeletionPlan?.sourceReceipts.first?.progress == .pending)
        let replacement = Data("changed while stopped\n".utf8)
        try replacement.write(to: fixture.note, options: .atomic)
        let resumed = NoteSystemTrashDeletionCoordinator(
            triptychID: fixture.triptychID, repository: fixture.repository,
            controlStore: fixture.control, recoveryStore: fixture.recovery)
        await #expect(throws: VaultRepositoryError.self) {
            try await resumed.recoverInterruptedTransactions()
        }
        #expect(try Data(contentsOf: fixture.note) == replacement)
        #expect(try await fixture.recovery.pending().isEmpty)
    }

    @Test("Missing, old and future request-receipt formats remain byte-unchanged and nonauthorizing", arguments: [nil, 1, 3] as [Int?])
    func unsupportedReceiptFormatIsNonauthorizing(version: Int?) async throws {
        let fixture = try await Fixture.make(point: .afterPlanPersistence)
        defer { fixture.remove() }
        let preview = try await fixture.preview()
        await #expect(throws: (any Error).self) {
            try await fixture.coordinator.moveToSystemTrash(preview)
        }
        let record = try #require(try await fixture.recovery.pending().first)
        let recordURL = fixture.root.appendingPathComponent(
            "Recovery/records/\(record.id.uuidString.lowercased()).json")
        var serialized = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: recordURL)) as? [String: Any])
        var plan = try #require(serialized["systemTrashDeletionPlan"] as? [String: Any])
        if let version { plan["schemaVersion"] = version } else { plan["schemaVersion"] = nil }
        serialized["systemTrashDeletionPlan"] = plan
        let unsupportedBytes = try JSONSerialization.data(withJSONObject: serialized, options: [.sortedKeys])
        try unsupportedBytes.write(to: recordURL, options: .atomic)

        let projected = try #require(try await fixture.recovery.pending().first)
        #expect(projected.files.first?.state == .unreadable)
        #expect(projected.systemTrashDeletionPlan == nil)
        let resumed = NoteSystemTrashDeletionCoordinator(
            triptychID: fixture.triptychID, repository: fixture.repository,
            controlStore: fixture.control, recoveryStore: fixture.recovery)
        #expect(try await resumed.recoverInterruptedTransactions().isEmpty)
        await #expect(throws: (any Error).self) { try await fixture.recovery.resolve(projected) }
        #expect(try Data(contentsOf: recordURL) == unsupportedBytes)
        #expect(try Data(contentsOf: fixture.note) == fixture.bytes)
    }

    private struct Fixture {
        let root: URL
        let note: URL
        let bytes: Data
        let vaultID: UUID
        let noteID: UUID
        let triptychID: UUID
        let repository: VaultRepository
        let control: TriptychControlStore
        let recovery: TriptychMutationRecoveryStore
        let coordinator: NoteSystemTrashDeletionCoordinator

        static func make(
            point: SystemTrashDeletionFaultPoint? = nil,
            barrier: (@Sendable () async -> Void)? = nil
        ) async throws -> Self {
            let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let root = repositoryRoot.appendingPathComponent(".build/file-operations-fixtures/\(UUID().uuidString)", isDirectory: true)
            var completed = false
            defer { if !completed { try? FileManager.default.removeItem(at: root) } }
            let vault = root.appendingPathComponent("Vault", isDirectory: true)
            let works = root.appendingPathComponent("Works", isDirectory: true)
            for url in [vault, works] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
            let note = vault.appendingPathComponent("Receipt-\(UUID().uuidString).md")
            let bytes = Data("exact receipt source\r\n".utf8)
            try bytes.write(to: note)
            let vaultID = UUID()
            let triptychID = UUID()
            let repository = try VaultRepository(
                vaultURL: vault, identity: VaultIdentity(id: vaultID, canonicalPath: vault.path, bookmarkData: nil),
                applicationSupportURL: root.appendingPathComponent("Support"))
            let control = TriptychControlStore(worksVaultURL: works)
            _ = try await control.bootstrap(
                vaultIDs: [.paperAnalysis: vaultID, .topicKnowledge: UUID(), .output: UUID()],
                preferredTriptychID: triptychID)
            let identity = try #require(
                try await control.identity(
                    forVaultID: vaultID, relativePath: note.lastPathComponent,
                    fingerprint: DocumentFingerprint(data: bytes)))
            let recovery = try TriptychMutationRecoveryStore(storageURL: root.appendingPathComponent("Recovery", isDirectory: true))
            let coordinator = NoteSystemTrashDeletionCoordinator(
                triptychID: triptychID, repository: repository, controlStore: control,
                recoveryStore: recovery,
                faultPlan: .init(failures: [], interruptions: Set(point.map { [$0] } ?? [])),
                nativeDispatchBarrierForTesting: barrier)
            completed = true
            return Self(
                root: root, note: note, bytes: bytes, vaultID: vaultID, noteID: identity.id,
                triptychID: triptychID, repository: repository, control: control, recovery: recovery,
                coordinator: coordinator)
        }

        func preview() async throws -> SystemTrashDeletionPreview {
            try await coordinator.prepareNote(
                noteID: noteID, vaultID: vaultID, relativePath: note.lastPathComponent,
                expectedRevision: DocumentFingerprint(data: bytes))
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}

private actor NativeTrashDispatchGate {
    private var entered = false
    private var arrival: CheckedContinuation<Void, any Error>?
    private var earlyFailure: (any Error)?
    private var continuation: CheckedContinuation<Void, Never>?

    func hold() async {
        entered = true
        arrival?.resume()
        arrival = nil
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilEntered() async throws {
        if entered { return }
        if let earlyFailure { throw earlyFailure }
        try await withCheckedThrowingContinuation { arrival = $0 }
    }

    func failedBeforeEntry(_ error: any Error) {
        guard !entered else { return }
        earlyFailure = error
        arrival?.resume(throwing: error)
        arrival = nil
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
