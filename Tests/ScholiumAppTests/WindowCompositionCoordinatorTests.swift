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

    @Test("Window teardown cancels an in-flight document transition")
    func documentTransitionCancellation() async {
        let coordinator = DocumentTransitionCoordinator()
        var events: [String] = []

        coordinator.enqueue(
            prepare: {},
            operation: {
                events.append("started")
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch is CancellationError {
                    events.append("cancelled")
                    throw CancellationError()
                }
            },
            didFail: { error in
                Issue.record("Cancellation surfaced as failure: \(error)")
            },
            didSucceed: { events.append("success") },
            didFinish: { events.append("finish") }
        )
        for _ in 0..<100 where !events.contains("started") { await Task.yield() }

        coordinator.cancelAll()
        for _ in 0..<100 where !events.contains("finish") { await Task.yield() }

        #expect(events == ["started", "cancelled", "finish"])
    }

    @Test("Window teardown cancels the running and queued document transitions")
    func documentTransitionQueueCancellation() async {
        let coordinator = DocumentTransitionCoordinator()
        var runningStarted = false
        var runningCancelled = false
        var runningFinished = false
        var queuedStarted = false
        var queuedFinished = false

        coordinator.enqueue(
            prepare: {},
            operation: {
                runningStarted = true
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch is CancellationError {
                    runningCancelled = true
                    throw CancellationError()
                }
            },
            didFail: { error in
                Issue.record("Running cancellation surfaced as failure: \(error)")
            },
            didFinish: { runningFinished = true }
        )
        for _ in 0..<100 where !runningStarted { await Task.yield() }

        coordinator.enqueue(
            prepare: { queuedStarted = true },
            operation: {},
            didFail: { error in
                Issue.record("Queued cancellation surfaced as failure: \(error)")
            },
            didFinish: { queuedFinished = true }
        )

        coordinator.cancelAll()
        await coordinator.waitForIdle()

        #expect(runningStarted)
        #expect(runningCancelled)
        #expect(runningFinished)
        #expect(!queuedStarted)
        #expect(queuedFinished)
    }

    @Test("A committed old transition cannot present after a newer request")
    func newerRequestSuppressesOldPresentation() async throws {
        let coordinator = DocumentTransitionCoordinator()
        var resumeOld: CheckedContinuation<Void, Never>?
        var events: [String] = []

        coordinator.enqueueCurrencyAware(
            prepare: {},
            operation: { isCurrent in
                events.append("old commit")
                await withCheckedContinuation { resumeOld = $0 }
                if isCurrent() { events.append("old presentation") }
            },
            didFail: { error in
                Issue.record("Unexpected old transition failure: \(error)")
            }
        )
        for _ in 0..<100 where resumeOld == nil { await Task.yield() }
        let continuation = try #require(resumeOld)

        coordinator.enqueue(
            prepare: {},
            operation: { events.append("new presentation") },
            didFail: { error in
                Issue.record("Unexpected new transition failure: \(error)")
            }
        )
        continuation.resume()
        await coordinator.waitForIdle()

        #expect(events == ["old commit", "new presentation"])
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
