import Foundation
import Testing

@testable import ScholiumApplication

@Suite("Aggregate source processing admission")
struct VaultSourceProcessingBudgetTests {
    @Test("Many admitted sources stay within the byte budget; a queued cancellation releases nothing twice")
    func aggregateAndQueuedCancellation() async throws {
        let budget = VaultSourceProcessingBudget(maximumInFlightSourceByteCount: 2_048, reservationByteCount: 1_024)
        let gate = Gate()
        let running = Task {
            try await withThrowingTaskGroup(of: Int.self) { group in
                for _ in 0..<8 {
                    group.addTask {
                        try await budget.withReservation {
                            let source = Data(repeating: 0x20, count: 1_023)
                            await gate.arriveAndWait()
                            return source.count
                        }
                    }
                }
                var bytes = 0
                for try await count in group { bytes += count }
                return bytes
            }
        }
        await gate.waitForArrivals(2)
        let full = await budget.statistics()
        #expect(full.reservedBytes == 2_048)
        #expect(full.peakReservedBytes == 2_048)
        let cancelled = Task {
            try await budget.withReservation {
                Issue.record("A cancelled queued source must not begin parsing")
                return 0
            }
        }
        for _ in 0..<10_000 {
            if await budget.statistics().queued == 7 { break }
            await Task.yield()
        }
        #expect(await budget.statistics().queued == 7)
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(await budget.statistics().reservedBytes == 2_048)
        await gate.open()
        #expect(try await running.value == 8 * 1_023)
        let complete = await budget.statistics()
        #expect(complete.reservedBytes == 0)
        #expect(complete.queued == 0)
        #expect(complete.peakReservedBytes == 2_048)
    }

    @Test("A failing parser returns its reservation to the next source")
    func failedOperationReleasesReservation() async throws {
        enum ParseFailure: Error { case fixture }
        let budget = VaultSourceProcessingBudget(maximumInFlightSourceByteCount: 1_024, reservationByteCount: 1_024)
        await #expect(throws: ParseFailure.self) {
            try await budget.withReservation { throw ParseFailure.fixture }
        }
        #expect(try await budget.withReservation { 7 } == 7)
        #expect(await budget.statistics().reservedBytes == 0)
    }

    private actor Gate {
        private var arrivals = 0
        private var isOpen = false
        private var arrivalWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
        private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

        func arriveAndWait() async {
            arrivals += 1
            let ready = arrivalWaiters.filter { $0.0 <= arrivals }
            arrivalWaiters.removeAll { $0.0 <= arrivals }
            for (_, continuation) in ready { continuation.resume() }
            guard !isOpen else { return }
            await withCheckedContinuation { releaseWaiters.append($0) }
        }

        func waitForArrivals(_ count: Int) async {
            guard arrivals < count else { return }
            await withCheckedContinuation { arrivalWaiters.append((count, $0)) }
        }

        func open() {
            isOpen = true
            for continuation in releaseWaiters { continuation.resume() }
            releaseWaiters.removeAll()
        }
    }
}
