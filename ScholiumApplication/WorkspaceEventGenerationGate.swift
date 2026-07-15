import ScholiumContracts
/// A small delivery-neutral cursor for consumers of `WorkspaceEvent`.
///
/// Event sources publish monotonically increasing generations, but a delivery
/// adapter can still receive work out of order when it performs asynchronous
/// projection. Keeping the acceptance rule here gives the GUI and future
/// headless consumers the same stale-result behavior without turning commands
/// into events.
public struct WorkspaceEventGenerationGate: Sendable {
    public private(set) var latestAcceptedGeneration: UInt64?

    public init(latestAcceptedGeneration: UInt64? = nil) {
        self.latestAcceptedGeneration = latestAcceptedGeneration
    }

    /// Accepts the first generation and every strictly newer generation.
    /// Duplicate or older generations leave the cursor unchanged.
    @discardableResult
    public mutating func accept(generation: UInt64) -> Bool {
        if let latestAcceptedGeneration,
           generation <= latestAcceptedGeneration {
            return false
        }
        latestAcceptedGeneration = generation
        return true
    }

    @discardableResult
    public mutating func accept(_ event: WorkspaceEvent) -> Bool {
        accept(generation: event.generation)
    }

    public mutating func reset() {
        latestAcceptedGeneration = nil
    }
}
