import Darwin
import Foundation
import ScholiumContracts

/// Disposable exact word counts prepared with the same Character boundaries
/// as the query matcher. Complex graphemes retain the canonical string path.
/// ASCII keys are stored once in sorted UTF-8 bytes instead of as dictionary
/// strings retained by every paragraph and scoring field.
struct RelatedContentTextIndex: Codable, Sendable {
    private struct WordEntry: Equatable, Sendable {
        let offset: UInt32
        let length: UInt32
        let count: UInt32
    }

    private struct PreparedWords: Equatable, Sendable {
        let entries: [WordEntry]
        let utf8: Data

        init?(_ counts: [String: Int]) {
            guard let byteCount = RelatedContentTextIndex.validatedByteCount(counts) else { return nil }
            let sorted = counts.keys.sorted()

            var entries: [WordEntry] = []
            entries.reserveCapacity(sorted.count)
            var utf8 = Data()
            utf8.reserveCapacity(byteCount)
            for word in sorted {
                entries.append(
                    WordEntry(
                        offset: UInt32(utf8.count), length: UInt32(word.utf8.count),
                        count: UInt32(counts[word]!)))
                utf8.append(contentsOf: word.utf8)
            }
            self.entries = entries
            self.utf8 = utf8
        }

        func count(for word: String) -> Int {
            guard !word.isEmpty else { return 0 }
            var word = word
            return word.withUTF8 { query in
                utf8.withUnsafeBytes { raw in
                    guard !entries.isEmpty else { return 0 }
                    let keys = raw.bindMemory(to: UInt8.self)
                    var lower = 0
                    var upper = entries.count
                    while lower < upper {
                        let middle = lower + (upper - lower) / 2
                        let entry = entries[middle]
                        let offset = Int(entry.offset)
                        let length = Int(entry.length)
                        let common = min(query.count, length)
                        let comparison = memcmp(query.baseAddress!, keys.baseAddress! + offset, common)
                        let order =
                            comparison == 0
                            ? (query.count == length ? 0 : (query.count < length ? -1 : 1))
                            : (comparison < 0 ? -1 : 1)
                        if order == 0 { return Int(entry.count) }
                        if order < 0 { upper = middle } else { lower = middle + 1 }
                    }
                    return 0
                }
            }
        }

        func dictionary() -> [String: Int] {
            utf8.withUnsafeBytes { raw in
                let bytes = raw.bindMemory(to: UInt8.self)
                var result: [String: Int] = [:]
                result.reserveCapacity(entries.count)
                for entry in entries {
                    let offset = Int(entry.offset)
                    let end = offset + Int(entry.length)
                    result[String(decoding: bytes[offset..<end], as: UTF8.self)] = Int(entry.count)
                }
                return result
            }
        }

        /// Accounting estimate for packed keys, entries and container overhead.
        var estimatedByteCount: Int { 160 + utf8.count + entries.count * 16 }
    }

    private let preparedWords: PreparedWords?
    let containsCJK: Bool

    /// The persisted value has the same admission rules as the packed query
    /// index. Opening validation needs these rules, not sorted query storage.
    struct Stored: Codable, Sendable {
        let words: [String: Int]?
        let containsCJK: Bool

        func validate() throws {
            if let words, RelatedContentTextIndex.validatedByteCount(words) == nil {
                throw SearchIndexError.corruptDatabase
            }
        }
    }

    private static func validatedByteCount(_ counts: [String: Int]) -> Int? {
        guard UInt32(exactly: counts.count) != nil else { return nil }
        var byteCount = 0
        for (word, count) in counts {
            guard isASCIIWord(word), count > 0, UInt32(exactly: count) != nil else { return nil }
            let (sum, overflow) = byteCount.addingReportingOverflow(word.utf8.count)
            guard !overflow, UInt32(exactly: sum) != nil else { return nil }
            byteCount = sum
        }
        return byteCount
    }

    var stored: Stored { .init(words: preparedWords?.dictionary(), containsCJK: containsCJK) }

    init(_ text: String) {
        var counts: [String: Int] = [:]
        var complex = false
        var hasCJK = false
        for word in text.split(whereSeparator: { character in
            var all = true
            var any = false
            for scalar in character.unicodeScalars {
                hasCJK = hasCJK || SearchTokenization.isCJK(scalar)
                let token = CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
                all = all && token
                any = any || token
            }
            if any && !all { complex = true }
            return !all
        }) where Self.isASCIIWord(word) {
            counts[String(word), default: 0] += 1
        }
        // A word count or byte offset that cannot fit the compact form uses
        // the established exact matcher, just like a complex grapheme.
        preparedWords = complex ? nil : PreparedWords(counts)
        containsCJK = hasCJK
    }

    init(from decoder: any Decoder) throws {
        let stored = try Stored(from: decoder)
        do {
            try self.init(stored: stored)
        } catch {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid prepared ASCII word counts"))
        }
    }

    init(stored: Stored) throws {
        containsCJK = stored.containsCJK
        if let words = stored.words {
            guard let prepared = PreparedWords(words) else { throw SearchIndexError.corruptDatabase }
            preparedWords = prepared
        } else {
            preparedWords = nil
        }
    }

    func encode(to encoder: any Encoder) throws {
        try stored.encode(to: encoder)
    }

    static func isASCIIWord<S: StringProtocol>(_ text: S) -> Bool {
        !text.isEmpty
            && text.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95
            }
    }

    var hasPreparedWords: Bool { preparedWords != nil }

    /// Nil means exact matching is required. Query terms have already been
    /// classified as ASCII by RelatedContentTermMatcher.
    func count(forASCIIWord word: String) -> Int? { preparedWords?.count(for: word) }

    func hasSameWordCounts(as other: Self) -> Bool { preparedWords == other.preparedWords }

    var estimatedByteCount: Int { preparedWords?.estimatedByteCount ?? 32 }
}
