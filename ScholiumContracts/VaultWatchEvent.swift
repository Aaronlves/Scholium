import Foundation

/// One advisory filesystem event batch for a single vault.
///
/// Paths are always vault-relative and contain no research bytes. FSEvents is
/// not an authoritative inventory; `requiresFullRescan` tells consumers to
/// establish a new complete inventory before publishing derived state.
public struct VaultWatchEvent: Codable, Hashable, Sendable {
    public let added: [String]
    public let modified: [String]
    public let deleted: [String]
    public let sequence: UInt64
    public let requiresFullRescan: Bool
    public let rootChanged: Bool

    public init(
        added: [String],
        modified: [String],
        deleted: [String],
        sequence: UInt64,
        requiresFullRescan: Bool,
        rootChanged: Bool
    ) {
        self.added = added
        self.modified = modified
        self.deleted = deleted
        self.sequence = sequence
        self.requiresFullRescan = requiresFullRescan
        self.rootChanged = rootChanged
    }

    public static func reconciliationRequired(
        sequence: UInt64,
        rootChanged: Bool = false
    ) -> Self {
        Self(
            added: [],
            modified: [],
            deleted: [],
            sequence: sequence,
            requiresFullRescan: true,
            rootChanged: rootChanged
        )
    }
}

/// Bounded journal used while a vault's initial inventory is being scanned.
///
/// The journal preserves every event until its fixed capacity is reached. An
/// overflow never drops correctness: it records that a complete reconciliation
/// is mandatory. Draining coalesces paths only as an invalidation summary; the
/// filesystem inventory remains authoritative.
public struct VaultWatchEventJournal: Sendable {
    public let capacity: Int
    public private(set) var events: [VaultWatchEvent] = []
    public private(set) var overflowed = false
    public private(set) var highestSequence: UInt64 = 0
    public private(set) var rootChanged = false
    public private(set) var sequenceReset = false

    public init(capacity: Int = 256) {
        self.capacity = max(1, capacity)
    }

    public mutating func append(_ event: VaultWatchEvent) {
        if highestSequence > 0, event.sequence > 0, event.sequence < highestSequence {
            sequenceReset = true
        }
        highestSequence = max(highestSequence, event.sequence)
        rootChanged = rootChanged || event.rootChanged
        if events.count < capacity {
            events.append(event)
        } else {
            overflowed = true
        }
    }

    public var requiresReconciliation: Bool {
        overflowed || !events.isEmpty
    }

    /// Returns a deterministic invalidation summary and clears the journal.
    /// Overflow, dropped-stream flags, and root changes always force a full
    /// inventory reconciliation.
    public mutating func drain() -> VaultWatchEvent? {
        guard requiresReconciliation else { return nil }
        var added = Set<String>()
        var modified = Set<String>()
        var deleted = Set<String>()
        var fullRescan = overflowed || sequenceReset
        var changedRoot = rootChanged
        for event in events {
            added.formUnion(event.added)
            modified.formUnion(event.modified)
            deleted.formUnion(event.deleted)
            fullRescan = fullRescan || event.requiresFullRescan
            changedRoot = changedRoot || event.rootChanged
        }
        let result = VaultWatchEvent(
            added: added.sorted(),
            modified: modified.sorted(),
            deleted: deleted.sorted(),
            sequence: highestSequence,
            requiresFullRescan: fullRescan,
            rootChanged: changedRoot
        )
        events.removeAll(keepingCapacity: true)
        overflowed = false
        rootChanged = false
        sequenceReset = false
        return result
    }
}
