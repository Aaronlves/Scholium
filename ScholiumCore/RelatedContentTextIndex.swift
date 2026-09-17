import Foundation
import ScholiumContracts

/// Disposable exact word counts prepared with the same Character boundaries
/// as the query matcher. Complex graphemes retain the canonical string path.
struct RelatedContentTextIndex: Codable, Sendable {
    let words: [String: Int]?
    let containsCJK: Bool

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
        words = complex ? nil : counts
        containsCJK = hasCJK
    }

    static func isASCIIWord<S: StringProtocol>(_ text: S) -> Bool {
        !text.isEmpty
            && text.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95
            }
    }

    var isValid: Bool {
        words?.allSatisfy { Self.isASCIIWord($0.key) && $0.value > 0 } ?? true
    }

    var estimatedByteCount: Int {
        32 + (words?.reduce(0) { $0 + $1.key.utf8.count + 48 } ?? 0)
    }
}
