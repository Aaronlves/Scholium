import Synchronization

/// One bounded FIFO shared by a transport producer and its single consumer.
/// AsyncStream owns suspension/cancellation; this owner admits wire bytes and
/// elements together. The extra slot is exclusively for a disconnect marker.
final class CodexTransportBuffer<Element: Sendable>: Sendable {
    struct Usage: Sendable {
        let count: Int
        let bytes: Int
    }

    private struct Entry: Sendable {
        let value: Element
        let bytes: Int
        let isTerminal: Bool
    }

    private struct State {
        var count = 0
        var bytes = 0
        var terminalPending = false
        var isFinished = false
    }

    private let maximumCount: Int
    private let maximumBytes: Int
    private let state = Mutex(State())
    private let stream: AsyncStream<Entry>
    private let continuation: AsyncStream<Entry>.Continuation

    init(maximumCount: Int, maximumBytes: Int) {
        precondition(maximumCount > 0 && maximumCount < Int.max && maximumBytes > 0)
        self.maximumCount = maximumCount
        self.maximumBytes = maximumBytes
        let pair = AsyncStream<Entry>.makeStream(bufferingPolicy: .bufferingOldest(maximumCount + 1))
        stream = pair.stream
        continuation = pair.continuation
    }

    deinit { continuation.finish() }

    func offer(_ value: Element, bytes: Int) -> Bool {
        state.withLock { state in
            guard !state.isFinished, bytes >= 0, state.count < maximumCount,
                bytes <= maximumBytes - state.bytes
            else { return false }
            state.count += 1
            state.bytes += bytes
            switch continuation.yield(Entry(value: value, bytes: bytes, isTerminal: false)) {
            case .enqueued:
                return true
            case .dropped, .terminated:
                state.count -= 1
                state.bytes -= bytes
                return false
            @unknown default:
                state.count -= 1
                state.bytes -= bytes
                return false
            }
        }
    }

    /// Failure is observable even with a paused consumer and a full data FIFO.
    /// Repeated loss before that marker is consumed has the same disconnected
    /// outcome and does not allocate another control slot.
    func offerTerminal(_ value: Element) {
        state.withLock { state in
            guard !state.isFinished, !state.terminalPending else { return }
            switch continuation.yield(Entry(value: value, bytes: 0, isTerminal: true)) {
            case .enqueued:
                state.terminalPending = true
            case .terminated:
                state.isFinished = true
            case .dropped:
                // Count admission reserves this slot; data cannot occupy it.
                assertionFailure("The transport disconnect slot was not reserved")
            @unknown default:
                assertionFailure("Unknown transport stream admission result")
            }
        }
    }

    func next() async -> Element? {
        var iterator = stream.makeAsyncIterator()
        guard let entry = await iterator.next() else {
            finish()
            return nil
        }
        state.withLock { state in
            if entry.isTerminal {
                state.terminalPending = false
            } else {
                state.count -= 1
                state.bytes -= entry.bytes
            }
        }
        return entry.value
    }

    func finish() {
        state.withLock { state in
            guard !state.isFinished else { return }
            state.isFinished = true
            continuation.finish()
        }
    }

    var usage: Usage {
        state.withLock { Usage(count: $0.count, bytes: $0.bytes) }
    }
}

struct CodexTransportLimits: Sendable {
    // Bounds are transport safety ceilings, not target performance claims.
    // Keep one maximum-size frame admissible and cap both large frames and
    // bursts of tiny messages. A writer retains at most one additional envelope
    // bounded by outgoingBytes; incoming frames retain their separate 8 MiB cap.
    static let standard = CodexTransportLimits(
        incomingCount: 256, incomingBytes: 16 * 1_024 * 1_024,
        outgoingCount: 128, outgoingBytes: 16 * 1_024 * 1_024,
        pendingOperations: 128)

    let incomingCount: Int
    let incomingBytes: Int
    let outgoingCount: Int
    let outgoingBytes: Int
    let pendingOperations: Int
}
