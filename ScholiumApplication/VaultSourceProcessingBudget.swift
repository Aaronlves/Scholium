import Foundation
import ScholiumContracts

/// Shared admission across pooled vaults. Reserve the complete supported Note
/// size before reading: descriptor metadata cannot safely predict a file's size
/// after concurrent growth. The reservation lasts through all source parsing
/// and compact projection construction, and is released on failure/cancellation.
actor VaultSourceProcessingBudget {
    static let shared = VaultSourceProcessingBudget()

    nonisolated let maximumInFlightSourceByteCount: Int
    nonisolated let reservationByteCount: Int
    private var reservedByteCount = 0
    private var peakReservedByteCount = 0
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    init(
        maximumInFlightSourceByteCount: Int = VaultSourceReadLimits.maximumInFlightSourceByteCount,
        reservationByteCount: Int = VaultSourceReadLimits.maximumNoteByteCount
    ) {
        precondition(reservationByteCount > 0 && reservationByteCount <= maximumInFlightSourceByteCount)
        self.maximumInFlightSourceByteCount = maximumInFlightSourceByteCount
        self.reservationByteCount = reservationByteCount
    }

    func withReservation<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        try await acquire(UUID())
        defer { release() }
        try Task.checkCancellation()
        return try await operation()
    }

    private func acquire(_ id: UUID) async throws {
        try Task.checkCancellation()
        if reservedByteCount <= maximumInFlightSourceByteCount - reservationByteCount {
            reserve()
            return
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append((id, continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func reserve() {
        reservedByteCount += reservationByteCount
        peakReservedByteCount = max(peakReservedByteCount, reservedByteCount)
    }

    private func release() {
        reservedByteCount -= reservationByteCount
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            reserve()
            next.continuation.resume()
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    func statistics() -> (reservedBytes: Int, peakReservedBytes: Int, queued: Int) {
        (reservedByteCount, peakReservedByteCount, waiters.count)
    }
}
