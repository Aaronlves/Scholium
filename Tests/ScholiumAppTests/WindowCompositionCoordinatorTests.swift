import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@MainActor
private final class WindowSessionPersistenceStoreProbe: WindowSessionPersistenceStore {
    var loadedSnapshot: WindowSessionSnapshot?
    var save: @MainActor (
        WindowSessionSnapshot,
        LifecycleAttemptID
    ) async throws -> Void = { _, _ in }

    func windowSession(id: UUID) async throws -> WindowSessionSnapshot? {
        guard loadedSnapshot?.id == id else { return nil }
        return loadedSnapshot
    }

    func saveWindowSession(
        _ snapshot: WindowSessionSnapshot,
        attempt: LifecycleAttemptID
    ) async throws {
        try await save(snapshot, attempt)
    }
}

@Suite("Window composition coordinators", .serialized)
@MainActor
struct WindowCompositionCoordinatorTests {
    @Test("The newest document transition wins and preserves preparation ordering")
    func newestTransitionWins() async {
        let coordinator = DocumentTransitionCoordinator()
        var events: [String] = []

        coordinator.enqueue(
            prepare: { events.append("obsolete prepare") },
            operation: { events.append("obsolete operation") },
            didFail: { _ in Issue.record("Obsolete transition failed") },
            didSucceed: { events.append("obsolete success") },
            didFinish: { events.append("obsolete finish") }
        )
        coordinator.enqueue(
            prepare: { events.append("prepare") },
            operation: { events.append("operation") },
            didFail: { error in Issue.record("Unexpected transition failure: \(error)") },
            didSucceed: { events.append("success") },
            didFinish: { events.append("finish") }
        )

        await coordinator.waitForIdle()
        #expect(events == [
            "obsolete finish", "prepare", "operation", "success", "finish",
        ])
    }

    @Test("A failed document transition finishes cleanup without reporting success")
    func failedTransitionDoesNotSucceed() async {
        struct ExpectedFailure: Error {}
        let coordinator = DocumentTransitionCoordinator()
        var events: [String] = []

        coordinator.enqueue(
            prepare: { events.append("prepare") },
            operation: {
                events.append("operation")
                throw ExpectedFailure()
            },
            didFail: { _ in events.append("failure") },
            didSucceed: { events.append("success") },
            didFinish: { events.append("finish") }
        )

        await coordinator.waitForIdle()
        #expect(events == ["prepare", "operation", "failure", "finish"])
    }

    @Test("A superseding presentation save cancels the older completion")
    func presentationSaveReplacement() async {
        let store = WindowSessionPersistenceStoreProbe()
        let coordinator = WindowSessionPersistenceCoordinator(
            store: store,
            lifecyclePolicy: ScholiumLifecyclePolicy()
        )
        var completedIDs: [UUID] = []
        var persistenceAttempts: [UInt64] = []
        let first = WindowSessionSnapshot(id: UUID())
        let second = WindowSessionSnapshot(id: UUID())

        store.save = { snapshot, attempt in
            persistenceAttempts.append(attempt.rawValue)
            if snapshot.id == first.id {
                try await Task.sleep(for: .seconds(1))
            }
        }
        coordinator.schedule(
            snapshot: first,
            completion: { _ in completedIDs.append(first.id) }
        )
        await Task.yield()
        coordinator.schedule(
            snapshot: second,
            completion: { result in
                if case .failure(let error) = result {
                    Issue.record("Unexpected persistence failure: \(error)")
                }
                completedIDs.append(second.id)
            }
        )
        for _ in 0..<10 where completedIDs.isEmpty {
            await Task.yield()
        }

        #expect(completedIDs == [second.id])
        #expect(persistenceAttempts.count == 2)
        #expect(persistenceAttempts[1] > persistenceAttempts[0])
    }

    @Test("Presentation restore is routed through the same persistence owner")
    func presentationRestoreOwnership() async throws {
        let snapshot = WindowSessionSnapshot(id: UUID())
        let store = WindowSessionPersistenceStoreProbe()
        store.loadedSnapshot = snapshot
        let coordinator = WindowSessionPersistenceCoordinator(
            store: store,
            lifecyclePolicy: ScholiumLifecyclePolicy()
        )

        #expect(try await coordinator.load(id: snapshot.id) == snapshot)
        #expect(try await coordinator.load(id: UUID()) == nil)
    }

    @Test("Final presentation persistence is bounded and does not claim content failure")
    func finalPersistenceDeadline() async {
        var policy = ScholiumLifecyclePolicy()
        policy.presentationSnapshot = .milliseconds(20)
        let store = WindowSessionPersistenceStoreProbe()
        let coordinator = WindowSessionPersistenceCoordinator(
            store: store,
            lifecyclePolicy: policy,
            finalSaver: { _, _ in
                try await Task.sleep(for: .seconds(10))
            }
        )

        let result = await coordinator.finalize(
            snapshot: WindowSessionSnapshot(),
            attemptIsCurrent: { true }
        )
        guard case .failed(let message) = result else {
            Issue.record("A hanging presentation save did not return a bounded diagnostic")
            return
        }
        #expect(message.contains("timed out"))
        #expect(!coordinator.isFinalizing)
    }
}
