import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApplication

@Suite("Workspace source operation gate")
struct WorkspaceSourceOperationGateTests {
    @Test("Cancelling a queued operation removes it before authority is granted")
    func queuedCancellation() async throws {
        let gate = WorkspaceSourceOperationGateHarness()
        let holder = try await gate.acquire(.sourceMutation)
        let cancelled = Task { try await gate.acquire(.refreshCycle) }
        #expect(await gate.waitUntilWaitingCount(1))

        cancelled.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await cancelled.value
        }
        #expect(await gate.waitingCount == 0)
        #expect(await gate.sourceMutationIsActive)

        await gate.release(holder)
        let retry = try await gate.acquire(.refreshCycle)
        #expect(await gate.refreshCycleIsActive)
        await gate.release(retry)
    }

    @Test("A task cancelled before enqueue never enters the wait queue")
    func cancellationBeforeEnqueue() async throws {
        let start = WorkspaceSourceOperationStartGate()
        let gate = WorkspaceSourceOperationGateHarness()
        let cancelled = Task {
            await start.wait()
            return try await gate.acquire(.sourceMutation)
        }
        #expect(await start.waitUntilArrived())

        cancelled.cancel()
        await start.release()
        await #expect(throws: CancellationError.self) {
            _ = try await cancelled.value
        }
        #expect(await gate.waitingCount == 0)
        #expect(!(await gate.sourceMutationIsActive))
        #expect(!(await gate.refreshCycleIsActive))
    }

    @Test("Cancelling one waiter cannot poison a surviving peer")
    func cancellationIsWaiterScoped() async throws {
        let gate = WorkspaceSourceOperationGateHarness()
        let holder = try await gate.acquire(.sourceMutation)
        let cancelled = Task { try await gate.acquire(.refreshCycle) }
        let surviving = Task { try await gate.acquire(.sourceMutation) }
        #expect(await gate.waitUntilWaitingCount(2))

        cancelled.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await cancelled.value
        }
        #expect(await gate.waitingCount == 1)

        await gate.release(holder)
        let survivingLease = try await surviving.value
        #expect(survivingLease.kind == .sourceMutation)
        #expect(await gate.sourceMutationIsActive)
        await gate.release(survivingLease)
    }

    @Test("Cancellation racing release never strands the gate")
    func cancellationReleaseRace() async throws {
        let gate = WorkspaceSourceOperationGateHarness()

        for _ in 0..<100 {
            let holder = try await gate.acquire(.sourceMutation)
            let contender = Task { try await gate.acquire(.refreshCycle) }
            #expect(await gate.waitUntilWaitingCount(1))

            contender.cancel()
            await gate.release(holder)
            do {
                let lease = try await contender.value
                await gate.release(lease)
            } catch is CancellationError {
                // Cancellation won the wake-up race, as intended.
            }

            #expect(await gate.waitingCount == 0)
            let retry = try await gate.acquire(.sourceMutation)
            await gate.release(retry)
        }
    }

    @Test("Shutdown fails waiters without revoking an acquired transaction")
    func shutdownBoundary() async throws {
        let gate = WorkspaceSourceOperationGateHarness()
        let holder = try await gate.acquire(.sourceMutation)
        let waiting = Task { try await gate.acquire(.refreshCycle) }
        #expect(await gate.waitUntilWaitingCount(1))

        await gate.shutDown()
        await #expect(throws: WorkspaceSourceOperationGateError.self) {
            _ = try await waiting.value
        }
        #expect(await gate.waitingCount == 0)
        #expect(await gate.sourceMutationIsActive)
        await #expect(throws: WorkspaceSourceOperationGateError.self) {
            _ = try await gate.acquire(.sourceMutation)
        }

        // The holder already crossed the acquisition boundary. Its owner must
        // finish or recover the transaction before releasing it.
        await gate.release(holder)
        #expect(!(await gate.sourceMutationIsActive))
    }

    @Test("A cancelled Workspace save never receives deferred write authority")
    func cancelledWorkspaceSaveDoesNotWrite() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let original = try await handle.documents.load(fixture.analysisNoteID)
        let holder = try await handle.acquireWorkspaceSourceOperation(.refreshCycle)
        let cancelled = Task {
            try await handle.documents.save(
                fixture.analysisNoteID,
                changeSet: .body("This cancelled write must never commit.\n"),
                expectedRevision: original.fingerprint
            )
        }
        #expect(await waitUntilWorkspaceWaiterCount(1, handle: handle))

        cancelled.cancel()
        #expect(await waitUntilWorkspaceWaiterCount(0, handle: handle))
        await handle.releaseWorkspaceSourceOperation(holder)
        await #expect(throws: CancellationError.self) {
            _ = try await cancelled.value
        }

        let reloaded = try await handle.documents.load(fixture.analysisNoteID)
        #expect(reloaded.rawContent == original.rawContent)
        #expect(reloaded.fingerprint == original.fingerprint)
        await runtime.shutdown()
    }

    private func waitUntilWorkspaceWaiterCount(
        _ expected: Int,
        handle: WorkspaceHandle
    ) async -> Bool {
        for _ in 0..<1_000 {
            if await handle.sourceOperationGate.waitingCount == expected {
                return true
            }
            await Task.yield()
        }
        return await handle.sourceOperationGate.waitingCount == expected
    }
}

private actor WorkspaceSourceOperationGateHarness:
    WorkspaceSourceOperationGateOwner
{
    var sourceOperationGate = WorkspaceSourceOperationGate()

    func acquire(
        _ kind: WorkspaceSourceOperationKind
    ) async throws -> WorkspaceSourceOperationLease {
        try await acquireWorkspaceSourceOperation(kind)
    }

    func release(_ lease: WorkspaceSourceOperationLease) {
        releaseWorkspaceSourceOperation(lease)
    }

    func shutDown() {
        shutDownWorkspaceSourceOperationGate()
    }

    var waitingCount: Int { sourceOperationGate.waitingCount }
    var sourceMutationIsActive: Bool {
        sourceOperationGate.sourceMutationIsActive
    }
    var refreshCycleIsActive: Bool {
        sourceOperationGate.refreshCycleIsActive
    }

    func waitUntilWaitingCount(_ expected: Int) async -> Bool {
        for _ in 0..<1_000 {
            if sourceOperationGate.waitingCount == expected { return true }
            await Task.yield()
        }
        return sourceOperationGate.waitingCount == expected
    }
}

private actor WorkspaceSourceOperationStartGate {
    private var arrived = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        arrived = true
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilArrived() async -> Bool {
        for _ in 0..<1_000 {
            if arrived { return true }
            await Task.yield()
        }
        return arrived
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
