import CryptoKit
import Foundation
import ScholiumContracts

/// TriptychSearchIndex-owned candidate matching material. Every miss runs the
/// complete persisted-paragraph decoder supplied by that owner. Hits bind the
/// current blob as well as source bounds and revision; they supply no locators,
/// display text or authority to final result construction.
struct SearchParagraphMatchingMemo {
    struct Statistics: Equatable, Sendable {
        var hits = 0
        var misses = 0
        var evictions = 0
        var oversizeSkips = 0
        var protectedAdmissionSkips = 0
    }

    struct ScanProtection: Sendable {
        fileprivate let generation: SearchGenerationID?
        fileprivate let rowIDs: Set<Int>
        fileprivate let estimatedByteCount: Int

        static let none = Self(generation: nil, rowIDs: [], estimatedByteCount: 0)
    }

    private struct Entry {
        let fingerprint: DocumentFingerprint
        let sourceUTF16Count: Int
        let checksum: Data
        let paragraphs: [SearchParagraphProjection]
        let byteCount: Int
        var lastAccess: UInt64
    }

    static let defaultMaximumByteCount = 16 * 1_024 * 1_024
    let maximumByteCount: Int
    private var generation: SearchGenerationID?
    private var entries: [Int: Entry] = [:]
    private var accessClock: UInt64 = 0
    /// Bounded retained-payload accounting, not process or allocator footprint.
    private(set) var estimatedByteCount = 0
    private(set) var statistics = Statistics()
    var entryCount: Int { entries.count }

    init(maximumByteCount: Int = Self.defaultMaximumByteCount) {
        self.maximumByteCount = min(Self.defaultMaximumByteCount, max(0, maximumByteCount))
    }

    /// Capture the entire candidate row set before decoding its first miss.
    /// Resident rows in a scan larger than the budget survive earlier misses.
    /// Protection changes admission only; a hit still checks the current blob.
    mutating func scanProtection(generation: SearchGenerationID?, rowIDs: Set<Int>) -> ScanProtection {
        retainGeneration(generation)
        guard let generation else { return .none }
        var protected = Set<Int>()
        var byteCount = 0
        for rowID in rowIDs {
            guard let entry = entries[rowID] else { continue }
            protected.insert(rowID)
            byteCount += entry.byteCount
        }
        return .init(generation: generation, rowIDs: protected, estimatedByteCount: byteCount)
    }

    mutating func paragraphs(
        rowID: Int, generation: SearchGenerationID?, fingerprint: DocumentFingerprint,
        sourceUTF16Count: Int, data: Data?, protection: ScanProtection,
        decode: (Data?) throws -> [SearchParagraphProjection]
    ) throws -> [SearchParagraphProjection] {
        try Task.checkCancellation()
        retainGeneration(generation)
        // Never retain the raw blob. Hash every read, including memo hits: a
        // malformed or replaced blob under unchanged source metadata must miss.
        let checksum = data.map { Data(SHA256.hash(data: $0)) }
        try Task.checkCancellation()
        accessClock &+= 1
        if var entry = entries[rowID], entry.fingerprint == fingerprint,
            entry.sourceUTF16Count == sourceUTF16Count, entry.checksum == checksum
        {
            entry.lastAccess = accessClock
            entries[rowID] = entry
            statistics.hits += 1
            return entry.paragraphs
        }
        statistics.misses += 1
        // Do not keep an obsolete entry if decoding its replacement fails.
        invalidate(rowID)
        let decoded = try decode(data)
        try Task.checkCancellation()
        let paragraphs = try decoded.map { paragraph in
            try Task.checkCancellation()
            return SearchParagraphProjection(
                range: paragraph.range,
                segments: paragraph.segments.map { segment in
                    .init(
                        field: segment.field, ordinal: segment.ordinal, text: "", normalizedText: segment.normalizedText,
                        sourceRange: nil, offsetMap: [])
                })
        }
        try Task.checkCancellation()
        guard let generation, let checksum else { return paragraphs }
        let cost = Self.cost(of: paragraphs, fingerprint: fingerprint)
        guard cost <= maximumByteCount else {
            statistics.oversizeSkips += 1
            return paragraphs
        }
        let protected = protection.generation == generation ? protection : .none
        guard protected.estimatedByteCount <= maximumByteCount - cost else {
            statistics.protectedAdmissionSkips += 1
            return paragraphs
        }
        while estimatedByteCount > maximumByteCount - cost {
            guard
                let victim = entries.lazy.filter({ !protected.rowIDs.contains($0.key) }).min(by: { lhs, rhs in
                    if lhs.value.lastAccess != rhs.value.lastAccess { return lhs.value.lastAccess < rhs.value.lastAccess }
                    return lhs.key < rhs.key
                })?.key
            else {
                statistics.protectedAdmissionSkips += 1
                return paragraphs
            }
            invalidate(victim)
            statistics.evictions += 1
        }
        entries[rowID] = .init(
            fingerprint: fingerprint, sourceUTF16Count: sourceUTF16Count, checksum: checksum,
            paragraphs: paragraphs, byteCount: cost, lastAccess: accessClock)
        estimatedByteCount += cost
        return paragraphs
    }

    mutating func retainGeneration(_ generation: SearchGenerationID?) {
        guard self.generation != generation else { return }
        clear()
        self.generation = generation
    }

    /// Counters remain cumulative so callers can measure deltas across clears.
    mutating func clear() {
        entries.removeAll()
        estimatedByteCount = 0
        generation = nil
        accessClock = 0
    }

    private mutating func invalidate(_ rowID: Int) {
        if let removed = entries.removeValue(forKey: rowID) { estimatedByteCount -= removed.byteCount }
    }

    private static func cost(of paragraphs: [SearchParagraphProjection], fingerprint: DocumentFingerprint) -> Int {
        // Include containers, scalar metadata, digest, string headers and a
        // conservative two-byte allowance per retained UTF-8 byte. Stop once
        // the fixed ceiling is exceeded, avoiding arithmetic on oversized input.
        var cost = 256 + fingerprint.sha256.utf8.count
        for paragraph in paragraphs {
            guard cost <= defaultMaximumByteCount else { return defaultMaximumByteCount + 1 }
            cost += 128
            for segment in paragraph.segments {
                let bytes = segment.normalizedText.utf8.count
                guard bytes <= defaultMaximumByteCount / 2, cost <= defaultMaximumByteCount else {
                    return defaultMaximumByteCount + 1
                }
                cost += 160 + 2 * bytes
            }
        }
        return cost
    }
}
