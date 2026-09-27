import Foundation
import ScholiumContracts

/// Actor-owned preparation for complete background candidate pools. Only
/// query-independent lexical projections survive a request; neither source
/// Markdown nor scores, reasons, access decisions or final results are cached.
struct RelatedContentBackgroundPreparation {
    struct Key: Hashable {
        let note: VaultQualifiedNoteID
        let pathUTF8: Data
        let fingerprint: DocumentFingerprint
        let generation: SearchGenerationID
        let roles: [RelatedContentCandidateRole]

        init(seed: RelatedContentSeedSnapshot, generation: SearchGenerationID, roles: [RelatedContentCandidateRole]) {
            note = seed.noteID
            pathUTF8 = Data(seed.noteID.relativePath.utf8)
            fingerprint = seed.fingerprint
            self.generation = generation
            self.roles = RelatedContentCandidateRole.allCases.filter { roles.contains($0) }
        }

        var estimatedByteCount: Int {
            320 + pathUTF8.count + note.relativePath.utf8.count + fingerprint.sha256.utf8.count
                + generation.sourceManifestHash.utf8.count + roles.count * 32
        }
    }

    struct LexicalDocument {
        let fingerprint: DocumentFingerprint
        let checksum: String
        let projection: RelatedContentLexicalProjection

        var estimatedByteCount: Int {
            160 + fingerprint.sha256.utf8.count + checksum.utf8.count + projection.estimatedByteCount
        }

        /// Even within one generation, read and hash the persisted payload.
        /// A cache hit must not conceal live corruption or a replaced payload.
        func matches(_ data: Data?, checksum: String?, fingerprint: DocumentFingerprint) -> Bool {
            guard self.fingerprint == fingerprint, self.checksum == checksum, let data else { return false }
            return RelatedContentSourceProjection.checksum(data) == self.checksum
        }
    }

    struct Value {
        var documents: [Int: LexicalDocument] = [:]
        var estimatedByteCount: Int {
            64 + documents.values.reduce(0) { $0 + 64 + $1.estimatedByteCount }
        }
    }

    struct Statistics: Equatable, Sendable {
        var hits = 0
        var misses = 0
        var evictions = 0
        var oversizeSkips = 0
    }

    private struct Entry {
        let value: Value
        let cost: Int
        var lastAccess: UInt64
    }

    static let maximumNotes = 2
    static let defaultMaximumByteCount = 16 * 1_024 * 1_024
    let maximumByteCount: Int
    private var entries: [Key: Entry] = [:]
    private var clock: UInt64 = 0
    private(set) var estimatedByteCount = 0
    private(set) var statistics = Statistics()
    var entryCount: Int { entries.count }

    init(maximumByteCount: Int = Self.defaultMaximumByteCount) {
        self.maximumByteCount = max(0, maximumByteCount)
    }

    mutating func prepared(for key: Key) throws -> Value? {
        try Task.checkCancellation()
        // Keep at most the latest exact revision/scope of a Note. A generation
        // change invalidates every slot, including other previously opened Notes.
        invalidateIncompatible(with: key)
        guard var entry = entries[key] else {
            statistics.misses += 1
            return nil
        }
        clock &+= 1
        entry.lastAccess = clock
        entries[key] = entry
        statistics.hits += 1
        return entry.value
    }

    mutating func store(_ value: Value, for key: Key) throws {
        try Task.checkCancellation()
        invalidateIncompatible(with: key)
        remove(key)
        let cost = key.estimatedByteCount + value.estimatedByteCount + 64
        guard fitsBudget(valueEstimatedByteCount: value.estimatedByteCount, for: key) else {
            statistics.oversizeSkips += 1
            return
        }
        while entries.count >= Self.maximumNotes || estimatedByteCount > maximumByteCount - cost {
            guard let victim = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key else { break }
            remove(victim)
            statistics.evictions += 1
        }
        clock &+= 1
        entries[key] = Entry(value: value, cost: cost, lastAccess: clock)
        estimatedByteCount += cost
    }

    /// The scanner can release an already over-budget complete pool before
    /// scoring. Admission and the skip count still belong to this memo owner.
    func fitsBudget(valueEstimatedByteCount: Int, for key: Key) -> Bool {
        let overhead = key.estimatedByteCount + 64
        return overhead <= maximumByteCount
            && valueEstimatedByteCount <= maximumByteCount - overhead
    }

    mutating func rejectOversizedCompletePool(for key: Key) throws {
        try Task.checkCancellation()
        invalidateIncompatible(with: key)
        remove(key)
        statistics.oversizeSkips += 1
    }

    /// Publication invalidates obsolete pools even when no later retrieval
    /// occurs. Keep the current generation through unchanged synchronization.
    mutating func retain(generation: SearchGenerationID) {
        for key in Array(entries.keys) where key.generation != generation {
            remove(key)
        }
    }

    private mutating func remove(_ key: Key) {
        if let removed = entries.removeValue(forKey: key) { estimatedByteCount -= removed.cost }
    }

    private mutating func invalidateIncompatible(with key: Key) {
        retain(generation: key.generation)
        for existing in Array(entries.keys)
        where existing.note == key.note && existing != key {
            remove(existing)
        }
    }
}
