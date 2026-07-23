import Foundation

private enum WorkspaceRefreshCoordinatorError: Error {
    case requestIDExhausted
}

struct RefreshRequestID: Hashable, Comparable, Sendable {
    let rawValue: UInt64

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Single-flight refresh ownership. Requests present when a cycle begins are
/// covered by that cycle; requests arriving while it runs are coalesced into
/// the next cycle. Cancelling one caller removes only that caller's wait.
actor WorkspaceRefreshCoordinator<Payload: Sendable, Output: Sendable> {
    typealias Cycle = @Sendable (
        _ coveringRequestID: RefreshRequestID,
        _ payloads: [Payload]
    ) async throws -> Output

    private struct Request: Sendable {
        let id: RefreshRequestID
        let token: UUID
        let payload: Payload
    }

    private let cycle: Cycle
    private var nextRequestValue: UInt64
    private var pending: [Request] = []
    private var waiters: [
        UUID: CheckedContinuation<Result<Output, any Error>, Never>
    ] = [:]
    private var liveTokens: Set<UUID> = []
    private var cancelledTokens: Set<UUID> = []
    private var worker: Task<Void, Never>?
    private var isShutDown = false

    init(startingAfter initialValue: UInt64 = 0, cycle: @escaping Cycle) {
        nextRequestValue = initialValue
        self.cycle = cycle
    }

    func request(_ payload: Payload) async throws -> Output {
        try Task.checkCancellation()
        guard !isShutDown else { throw CancellationError() }
        guard nextRequestValue < UInt64.max else {
            throw WorkspaceRefreshCoordinatorError.requestIDExhausted
        }
        nextRequestValue += 1
        let requestID = RefreshRequestID(rawValue: nextRequestValue)
        let token = UUID()
        liveTokens.insert(token)
        defer {
            liveTokens.remove(token)
            cancelledTokens.remove(token)
        }
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation {
                (continuation: CheckedContinuation<
                    Result<Output, any Error>, Never
                >) in
                enqueue(
                    Request(id: requestID, token: token, payload: payload),
                    continuation: continuation
                )
            }
        } onCancel: {
            Task { await self.cancelWait(token: token) }
        }
        return try result.get()
    }

    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        pending.removeAll()
        cancelledTokens.removeAll()
        let continuations = waiters.values
        waiters.removeAll()
        for continuation in continuations {
            continuation.resume(returning: .failure(CancellationError()))
        }
        worker?.cancel()
        worker = nil
    }

    var queuedRequestCount: Int { pending.count }

    private func enqueue(
        _ request: Request,
        continuation: CheckedContinuation<Result<Output, any Error>, Never>
    ) {
        guard !isShutDown else {
            continuation.resume(returning: .failure(CancellationError()))
            return
        }
        guard cancelledTokens.remove(request.token) == nil else {
            continuation.resume(returning: .failure(CancellationError()))
            return
        }
        pending.append(request)
        waiters[request.token] = continuation
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.runWorker()
        }
    }

    private func runWorker() async {
        while !isShutDown, !pending.isEmpty {
            let requests = pending
            pending.removeAll(keepingCapacity: true)
            guard let coveringID = requests.map(\.id).max() else { continue }
            let result: Result<Output, any Error>
            do {
                result = .success(try await cycle(
                    coveringID,
                    requests.map(\.payload)
                ))
            } catch {
                result = .failure(error)
            }
            for request in requests {
                waiters.removeValue(forKey: request.token)?
                    .resume(returning: result)
            }
        }
        worker = nil
        if !isShutDown, !pending.isEmpty {
            worker = Task { [weak self] in
                await self?.runWorker()
            }
        }
    }

    private func cancelWait(token: UUID) {
        if let continuation = waiters.removeValue(forKey: token) {
            continuation.resume(returning: .failure(CancellationError()))
        } else if liveTokens.contains(token) {
            cancelledTokens.insert(token)
        }
    }
}
