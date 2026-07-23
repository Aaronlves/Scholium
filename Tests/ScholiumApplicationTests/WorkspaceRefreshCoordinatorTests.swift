import Foundation
import Testing
@testable import ScholiumApplication

@Suite("Workspace refresh coordinator")
struct WorkspaceRefreshCoordinatorTests {
    @Test("One worker serializes cycles, coalesces the next cycle, and scopes cancellation")
    func singleFlightAndCancellation() async throws {
        let probe = RefreshCycleProbe()
        let coordinator = WorkspaceRefreshCoordinator<Int, Int> {
            requestID, payloads in
            await probe.run(requestID: requestID, payloads: payloads)
        }

        let first = Task { try await coordinator.request(1) }
        await probe.waitUntilCyclesStarted(1)
        let cancelled = Task { try await coordinator.request(2) }
        await waitUntilQueued(1, coordinator: coordinator)
        let surviving = Task { try await coordinator.request(3) }
        await waitUntilQueued(2, coordinator: coordinator)
        cancelled.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await cancelled.value
        }

        await probe.releaseNext()
        #expect(try await first.value == 1)
        await probe.waitUntilCyclesStarted(2)
        await probe.releaseNext()
        #expect(try await surviving.value == 3)

        let evidence = await probe.evidence()
        #expect(evidence.maximumActive == 1)
        #expect(evidence.payloads == [[1], [2, 3]])
        #expect(evidence.requestIDs == [1, 3])
        await coordinator.shutdown()
    }

    @Test("Cancelling the active caller leaves its worker independent and retryable")
    func activeCallerCancellationDoesNotCancelWorker() async throws {
        let probe = RefreshCycleProbe()
        let coordinator = WorkspaceRefreshCoordinator<Int, Int> {
            requestID, payloads in
            await probe.run(requestID: requestID, payloads: payloads)
        }
        let cancelled = Task { try await coordinator.request(1) }
        await probe.waitUntilCyclesStarted(1)
        cancelled.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await cancelled.value
        }
        await probe.releaseNext()
        await probe.waitUntilCyclesCompleted(1)

        let retry = Task { try await coordinator.request(2) }
        await probe.waitUntilCyclesStarted(2)
        await probe.releaseNext()
        #expect(try await retry.value == 2)
        #expect((await probe.evidence()).maximumActive == 1)
        await coordinator.shutdown()
    }

    @Test("A failed cycle does not poison a later request")
    func failureThenRetry() async throws {
        let attempts = RefreshAttemptCounter()
        let coordinator = WorkspaceRefreshCoordinator<Int, Int> { _, payloads in
            if await attempts.next() == 1 {
                throw RefreshTestError.injected
            }
            return payloads.max() ?? 0
        }
        await #expect(throws: RefreshTestError.self) {
            _ = try await coordinator.request(1)
        }
        #expect(try await coordinator.request(2) == 2)
        await coordinator.shutdown()
    }

    @Test("A caller cancelled before enqueue cannot strand a continuation")
    func cancellationBeforeEnqueue() async throws {
        let gate = RefreshStartGate()
        let probe = RefreshCycleProbe()
        let coordinator = WorkspaceRefreshCoordinator<Int, Int> {
            requestID, payloads in
            await probe.run(requestID: requestID, payloads: payloads)
        }
        let cancelled = Task {
            await gate.wait()
            return try await coordinator.request(1)
        }
        await gate.waitUntilArrived()
        cancelled.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) {
            _ = try await cancelled.value
        }
        #expect((await probe.evidence()).payloads.isEmpty)

        let retry = Task { try await coordinator.request(2) }
        await probe.waitUntilCyclesStarted(1)
        await probe.releaseNext()
        #expect(try await retry.value == 2)
        await coordinator.shutdown()
    }

    private func waitUntilQueued(
        _ count: Int,
        coordinator: WorkspaceRefreshCoordinator<Int, Int>
    ) async {
        for _ in 0..<1_000 {
            if await coordinator.queuedRequestCount >= count { return }
            await Task.yield()
        }
    }
}

private actor RefreshStartGate {
    private var arrived = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        arrived = true
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilArrived() async {
        for _ in 0..<1_000 where !arrived {
            await Task.yield()
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor RefreshCycleProbe {
    struct Evidence: Sendable {
        let maximumActive: Int
        let payloads: [[Int]]
        let requestIDs: [UInt64]
    }

    private var active = 0
    private var maximumActive = 0
    private var payloads: [[Int]] = []
    private var requestIDs: [UInt64] = []
    private var releases: [CheckedContinuation<Void, Never>] = []
    private var completed = 0

    func run(requestID: RefreshRequestID, payloads: [Int]) async -> Int {
        active += 1
        maximumActive = max(maximumActive, active)
        self.payloads.append(payloads)
        requestIDs.append(requestID.rawValue)
        await withCheckedContinuation { continuation in
            releases.append(continuation)
        }
        active -= 1
        completed += 1
        return payloads.max() ?? 0
    }

    func waitUntilCyclesStarted(_ count: Int) async {
        for _ in 0..<1_000 where payloads.count < count {
            await Task.yield()
        }
    }

    func releaseNext() {
        guard !releases.isEmpty else { return }
        releases.removeFirst().resume()
    }

    func waitUntilCyclesCompleted(_ count: Int) async {
        for _ in 0..<1_000 where completed < count {
            await Task.yield()
        }
    }

    func evidence() -> Evidence {
        Evidence(
            maximumActive: maximumActive,
            payloads: payloads,
            requestIDs: requestIDs
        )
    }
}

private enum RefreshTestError: Error {
    case injected
}

private actor RefreshAttemptCounter {
    private var value = 0

    func next() -> Int {
        value += 1
        return value
    }
}
