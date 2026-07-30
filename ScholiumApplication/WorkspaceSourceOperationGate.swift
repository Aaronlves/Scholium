import Foundation

enum WorkspaceSourceOperationKind: Equatable, Sendable {
    case sourceMutation
    case refreshCycle
}

struct WorkspaceSourceOperationLease: Equatable, Sendable {
    let id: UUID
    let kind: WorkspaceSourceOperationKind
}

enum WorkspaceSourceOperationGateError: Error, Equatable {
    case shutDown
}

/// Owns only the mutual-exclusion state and cancellation-aware waiters shared
/// by authoritative source mutations and derived refresh cycles.
///
/// The enclosing `WorkspaceHandle` actor remains the isolation and lifetime
/// owner. This value performs no I/O, recovery, or post-acquisition
/// cancellation policy, so extracting it does not split a durable transaction
/// or add another actor hop to the source-operation fast path.
struct WorkspaceSourceOperationGate {
    private typealias Waiter = CheckedContinuation<
        Result<Void, any Error>,
        Never
    >

    private var activeLease: WorkspaceSourceOperationLease?
    private var waiters: [UUID: Waiter] = [:]
    private(set) var isShutDown = false

    var sourceMutationIsActive: Bool {
        activeLease?.kind == .sourceMutation
    }

    var refreshCycleIsActive: Bool {
        activeLease?.kind == .refreshCycle
    }

    var waitingCount: Int { waiters.count }

    mutating func acquireIfAvailable(
        _ kind: WorkspaceSourceOperationKind
    ) throws -> WorkspaceSourceOperationLease? {
        guard !isShutDown else {
            throw WorkspaceSourceOperationGateError.shutDown
        }
        guard activeLease == nil else { return nil }
        let lease = WorkspaceSourceOperationLease(id: UUID(), kind: kind)
        activeLease = lease
        return lease
    }

    mutating func release(_ lease: WorkspaceSourceOperationLease) {
        precondition(activeLease == lease)
        activeLease = nil
        signalChange()
    }

    mutating func enqueueWaiter(
        id: UUID,
        continuation: CheckedContinuation<Result<Void, any Error>, Never>
    ) {
        guard !isShutDown else {
            continuation.resume(
                returning: .failure(WorkspaceSourceOperationGateError.shutDown)
            )
            return
        }
        precondition(waiters[id] == nil)
        waiters[id] = continuation
    }

    mutating func cancelWaiter(id: UUID) {
        waiters.removeValue(forKey: id)?.resume(
            returning: .failure(CancellationError())
        )
    }

    mutating func signalChange() {
        let pending = waiters.values
        waiters.removeAll()
        for waiter in pending {
            waiter.resume(returning: .success(()))
        }
    }

    mutating func shutDown() {
        guard !isShutDown else { return }
        isShutDown = true
        let pending = waiters.values
        waiters.removeAll()
        for waiter in pending {
            waiter.resume(
                returning: .failure(WorkspaceSourceOperationGateError.shutDown)
            )
        }
    }
}

/// Supplies the cancellation bridge while keeping the gate value isolated by
/// its owning actor. Test harnesses use this same implementation so races are
/// exercised at the production acquisition boundary rather than re-created in
/// test-only code.
protocol WorkspaceSourceOperationGateOwner: Actor {
    var sourceOperationGate: WorkspaceSourceOperationGate { get set }
}

extension WorkspaceSourceOperationGateOwner {
    func acquireWorkspaceSourceOperation(
        _ kind: WorkspaceSourceOperationKind
    ) async throws -> WorkspaceSourceOperationLease {
        while true {
            try Task.checkCancellation()
            if let lease = try sourceOperationGate.acquireIfAvailable(kind) {
                do {
                    // Cancellation can race the wake-up that made the lease
                    // available. Refuse and release before returning authority.
                    try Task.checkCancellation()
                    return lease
                } catch {
                    sourceOperationGate.release(lease)
                    throw error
                }
            }
            try await waitForWorkspaceSourceOperationChange()
        }
    }

    func releaseWorkspaceSourceOperation(_ lease: WorkspaceSourceOperationLease) {
        sourceOperationGate.release(lease)
    }

    func shutDownWorkspaceSourceOperationGate() {
        sourceOperationGate.shutDown()
    }

    private func waitForWorkspaceSourceOperationChange() async throws {
        try Task.checkCancellation()
        let waiterID = UUID()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation {
                (continuation: CheckedContinuation<
                    Result<Void, any Error>,
                    Never
                >) in
                // `onCancel` may run before this actor regains execution.
                // Inspecting the current task closes that enqueue race.
                if Task.isCancelled {
                    continuation.resume(returning: .failure(CancellationError()))
                } else {
                    sourceOperationGate.enqueueWaiter(
                        id: waiterID,
                        continuation: continuation
                    )
                }
            }
        } onCancel: {
            Task { await self.cancelWorkspaceSourceOperationWaiter(waiterID) }
        }
        return try result.get()
    }

    private func cancelWorkspaceSourceOperationWaiter(_ id: UUID) {
        sourceOperationGate.cancelWaiter(id: id)
    }
}
