import Foundation
import ScholiumContracts

/// Actor-owned, query-independent decoded lexical rows. Candidate membership,
/// role/path authorization, reasons and ranking always come from the current scan.
struct RelatedContentBackgroundPreparation {
    struct Statistics: Equatable, Sendable {
        var hits = 0
        var misses = 0
        var evictions = 0
        var oversizeSkips = 0
        var protectedAdmissionSkips = 0
    }

    /// Protect only rows resident when this scan began. Protection owns no
    /// projections and never authorizes a hit without validating current bytes.
    struct ScanProtection: Sendable {
        fileprivate let generation: SearchGenerationID
        fileprivate let rowIDs: Set<Int>
        fileprivate let estimatedByteCount: Int
    }

    private struct Entry {
        let fingerprint: DocumentFingerprint
        let checksum: String
        let projection: RelatedContentLexicalProjection
        let cost: Int
        var lastAccess: UInt64
    }

    /// The same 16 MiB budget now accounts individual decoded lexical rows,
    /// including key/entry metadata. entryCount and statistics count rows, not seeds.
    static let defaultMaximumByteCount = 16 * 1_024 * 1_024
    let maximumByteCount: Int
    private var generation: SearchGenerationID?
    private var entries: [Int: Entry] = [:]
    private var clock: UInt64 = 0
    private(set) var estimatedByteCount = 0
    private(set) var statistics = Statistics()
    var entryCount: Int { entries.count }

    init(maximumByteCount: Int = Self.defaultMaximumByteCount) {
        self.maximumByteCount = max(0, maximumByteCount)
    }

    mutating func scanProtection(generation: SearchGenerationID, rowIDs: Set<Int>) -> ScanProtection {
        retain(generation: generation)
        let resident = rowIDs.intersection(entries.keys)
        return .init(
            generation: generation, rowIDs: resident,
            estimatedByteCount: resident.reduce(0) { $0 + entries[$1]!.cost })
    }

    mutating func projection(
        rowID: Int, generation: SearchGenerationID, fingerprint: DocumentFingerprint,
        data: Data?, checksum: String?, protection: ScanProtection
    ) throws -> RelatedContentLexicalProjection {
        try Task.checkCancellation()
        retain(generation: generation)
        if var entry = entries[rowID], entry.fingerprint == fingerprint,
            entry.checksum == checksum, let data,
            RelatedContentSourceProjection.checksum(data) == entry.checksum
        {
            clock &+= 1
            entry.lastAccess = clock
            entries[rowID] = entry
            statistics.hits += 1
            return entry.projection
        }
        statistics.misses += 1
        // A failed or oversized replacement cannot leave an earlier revision
        // available to the immutable-storage sharing lookup.
        remove(rowID)
        let projection = try RelatedContentLexicalProjection.decode(data, checksum: checksum)
        try Task.checkCancellation()
        let cost =
            256 + generation.sourceManifestHash.utf8.count
            + fingerprint.sha256.utf8.count + (checksum?.utf8.count ?? 0) + projection.estimatedByteCount
        guard cost <= maximumByteCount else {
            statistics.oversizeSkips += 1
            return projection
        }
        let protectedRows = protection.generation == generation ? protection.rowIDs : []
        let protectedBytes = protection.generation == generation ? protection.estimatedByteCount : 0
        // Conservative if a protected row was invalidated during the scan.
        // A later scan takes a fresh snapshot; no valid result depends on admission.
        guard protectedBytes <= maximumByteCount - cost else {
            statistics.protectedAdmissionSkips += 1
            return projection
        }
        while estimatedByteCount > maximumByteCount - cost {
            guard
                let victim = entries.lazy.filter({ !protectedRows.contains($0.key) }).min(by: {
                    $0.value.lastAccess == $1.value.lastAccess
                        ? $0.key < $1.key : $0.value.lastAccess < $1.value.lastAccess
                })?.key
            else {
                statistics.protectedAdmissionSkips += 1
                return projection
            }
            remove(victim)
            statistics.evictions += 1
        }
        clock &+= 1
        // Successful decode proves a nonnil checksum matching these bytes.
        entries[rowID] = .init(
            fingerprint: fingerprint, checksum: checksum!, projection: projection,
            cost: cost, lastAccess: clock)
        estimatedByteCount += cost
        return projection
    }

    /// A storage-sharing candidate only. Callers still validate the current
    /// persisted projection and compare every scorer value before substitution.
    /// This does not refresh LRU, statistics or conservative accounting.
    func scoringStorage(rowID: Int, fingerprint: DocumentFingerprint) -> RelatedContentBM25F.Document? {
        guard let entry = entries[rowID], entry.fingerprint == fingerprint else { return nil }
        return entry.projection.scoringDocument
    }

    mutating func retain(generation: SearchGenerationID) {
        guard self.generation != generation else { return }
        entries.removeAll(keepingCapacity: false)
        estimatedByteCount = 0
        self.generation = generation
    }

    private mutating func remove(_ rowID: Int) {
        if let removed = entries.removeValue(forKey: rowID) { estimatedByteCount -= removed.cost }
    }
}
