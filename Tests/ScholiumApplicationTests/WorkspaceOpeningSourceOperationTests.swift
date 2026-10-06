import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Workspace opening source operation lease")
struct WorkspaceOpeningSourceOperationTests {
    @Test("Opening refresh owns its lease across a queued save and caller cancellation", .timeLimit(.minutes(2)))
    func openingSaveAndRefreshCancellation() async throws {
        let fixture = try await ApplicationFixture.make(registerLiveAccess: true)
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(
            configuration: .live(
                .init(
                    applicationSupportURL: fixture.applicationSupportURL,
                    workspaceRegistryStorageURL: fixture.registryStorageURL)))
        let handle: WorkspaceHandle
        do {
            handle = try await runtime.openWorkspace(id: fixture.assignment.id, openingVault: .paperAnalysis)
        } catch {
            await runtime.shutdown()
            throw error
        }
        let barrier = WorkspaceOpeningLeaseBarrier()
        let lifecycle = WorkspaceOpeningLeaseLifecycle(runtime: runtime, handle: handle, barrier: barrier)
        try await withTaskCancellationHandler {
            do {
                await handle.setProgressiveActivationReconciliationBarrierForTesting {
                    await barrier.wait()
                }
                await handle.openingPresentationDidComplete()
                try #require(await barrier.waitUntilArrived())
                #expect(await handle.sourceOperationGate.refreshCycleIsActive)
                #expect(!(await handle.sourceOperationGate.sourceMutationIsActive))
                #expect(try await handle.snapshot().phase == .opening(availableVault: .paperAnalysis))

                let original = try await handle.documents.load(fixture.analysisNoteID)
                let target = try await capturedSaveTarget(handle, fixture.analysisNoteID, revision: original.fingerprint)
                let noteURL = fixture.analysesURL.appendingPathComponent(fixture.analysisNoteID.relativePath)
                let savedSource = original.rawContent + "\nDiagnostic queued save retains exact source bytes.\n"
                let save = Task {
                    try await handle.documents.save(target, changeSet: .source(savedSource))
                }
                await lifecycle.track(save)
                try await requireState("the real save is waiting behind opening refresh") {
                    await handle.sourceOperationGate.waitingCount == 1
                }
                #expect(try Data(contentsOf: noteURL) == original.sourceBytes)
                #expect(await handle.sourceOperationGate.refreshCycleIsActive)

                let coordinator = try #require(await handle.refreshCoordinator)
                let cancelledRefresh = Task { try await handle.discovery.refresh() }
                let survivingRefresh = Task { try await handle.discovery.refresh() }
                await lifecycle.track(cancelledRefresh)
                await lifecycle.track(survivingRefresh)
                try await requireState("both explicit refresh callers are queued behind the opening worker") {
                    await coordinator.queuedRequestCount == 2
                }
                cancelledRefresh.cancel()
                await #expect(throws: CancellationError.self) {
                    _ = try await cancelledRefresh.value
                }
                #expect(await handle.sourceOperationGate.refreshCycleIsActive)
                #expect(await handle.sourceOperationGate.waitingCount == 1)
                #expect(try Data(contentsOf: noteURL) == original.sourceBytes)

                await barrier.release()
                await handle.setProgressiveActivationReconciliationBarrierForTesting(nil)
                await handle.awaitOpeningCompletionForTesting()
                let saveOutcome = try await save.value
                let survivingSnapshot = try await survivingRefresh.value
                #expect(saveOutcome.derivedRefreshWarning == nil)
                #expect(saveOutcome.identityRecoveryWarning == nil)
                #expect(survivingSnapshot.phase.isComplete)
                #expect(survivingSnapshot.discovery.searchGeneration != nil)
                #expect(survivingSnapshot.discovery.catalog.graph != nil)
                #expect(try Data(contentsOf: noteURL) == Data(savedSource.utf8))

                let complete = try await handle.snapshot()
                let savedNote = try #require(complete.document(id: fixture.analysisNoteID))
                #expect(complete.phase.isComplete)
                #expect(complete.vaults.count == 3)
                #expect(complete.discovery.searchGeneration != nil)
                #expect(complete.discovery.catalog.graph != nil)
                #expect(savedNote.fingerprint == DocumentFingerprint(content: savedSource))
                #expect(savedNote.stableIdentity.resolvedID == target.stableNoteID)
                try await requireState("all admitted operations have released their leases") {
                    let refreshIsActive = await handle.sourceOperationGate.refreshCycleIsActive
                    let mutationIsActive = await handle.sourceOperationGate.sourceMutationIsActive
                    let waitingCount = await handle.sourceOperationGate.waitingCount
                    return !refreshIsActive && !mutationIsActive && waitingCount == 0
                }
                #expect(await coordinator.queuedRequestCount == 0)
                await lifecycle.cleanup()
                #expect(await handle.ownedBackgroundTaskCount == 0)
                #expect(!(await handle.sourceOperationGate.refreshCycleIsActive))
                #expect(!(await handle.sourceOperationGate.sourceMutationIsActive))
                #expect(await handle.sourceOperationGate.waitingCount == 0)
                #expect(try Data(contentsOf: noteURL) == Data(savedSource.utf8))
            } catch {
                await lifecycle.cleanup()
                throw error
            }
        } onCancel: {
            Task { await lifecycle.cleanup() }
        }
    }

    private func requireState(
        _ description: String,
        predicate: @Sendable () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(30))
        while clock.now < deadline {
            try Task.checkCancellation()
            if await predicate() { return }
            await Task.yield()
        }
        throw WorkspaceOpeningLeaseError.readinessTimeout(description)
    }
}

private enum WorkspaceOpeningLeaseError: Error {
    case readinessTimeout(String)
}

private actor WorkspaceOpeningLeaseBarrier {
    private let arrival = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private let releaseSignal = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))

    func wait() async {
        arrival.continuation.yield(())
        arrival.continuation.finish()
        var iterator = releaseSignal.stream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func waitUntilArrived() async -> Bool {
        var iterator = arrival.stream.makeAsyncIterator()
        return await iterator.next() != nil
    }

    func release() {
        releaseSignal.continuation.yield(())
        releaseSignal.continuation.finish()
        arrival.continuation.finish()
    }
}

private actor WorkspaceOpeningLeaseLifecycle {
    private let runtime: WorkspaceRuntime
    private let handle: WorkspaceHandle
    private let barrier: WorkspaceOpeningLeaseBarrier
    private var cancellations: [@Sendable () -> Void] = []
    private var drains: [@Sendable () async -> Void] = []
    private var cleanupTask: Task<Void, Never>?

    init(runtime: WorkspaceRuntime, handle: WorkspaceHandle, barrier: WorkspaceOpeningLeaseBarrier) {
        self.runtime = runtime
        self.handle = handle
        self.barrier = barrier
    }

    func track<Success: Sendable, Failure: Error>(_ task: Task<Success, Failure>) async {
        if cleanupTask != nil {
            task.cancel()
            _ = await task.result
            return
        }
        cancellations.append { task.cancel() }
        drains.append { _ = await task.result }
    }

    func cleanup() async {
        if let cleanupTask {
            await cleanupTask.value
            return
        }
        for cancel in cancellations { cancel() }
        let drains = drains
        let task = Task {
            await barrier.release()
            await handle.setProgressiveActivationReconciliationBarrierForTesting(nil)
            await runtime.shutdown()
            for drain in drains { await drain() }
        }
        cleanupTask = task
        await task.value
    }
}
