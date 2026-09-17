import Foundation
import ScholiumContracts

/// Bounded lexical focus preparation. Sampling represents the complete authored
/// selection; it does not infer conceptual importance or corpus rarity.
enum RelatedContentQueryTerms {
    private static let ignoredLatinTerms: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "been", "being", "but",
        "by", "for", "from", "had", "has", "have", "if", "in", "is", "it",
        "its", "of", "on", "or", "that", "the", "these", "this",
        "those", "to", "was", "we", "were", "with",
    ]

    static func terms(in value: String, limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        let tokens = orderedTokens(in: value)
        var seen = Set<String>()
        let distinct = tokens.filter { seen.insert($0).inserted }
        guard distinct.count > limit else { return distinct }

        // Use actual ending occurrences before deduplication: a concluding
        // concept may already have appeared much earlier in the selection.
        let ending = Set(tokens.suffix(min(2, limit)))
        var selected = Set(distinct.indices.filter { ending.contains(distinct[$0]) })

        // Explicitly quoted wording receives up to half the query budget.
        let quoted = Set(quotedPhrases(in: value).flatMap { orderedTokens(in: $0) })
        let quotedIndices = distinct.indices.filter { quoted.contains(distinct[$0]) && !selected.contains($0) }
        selected.formUnion(quotedIndices.prefix(min(limit / 2, limit - selected.count)))

        // A long CJK passage must not erase its few authored non-CJK terms,
        // or vice versa. This is script coverage, not translation or salience.
        let cjk = distinct.indices.filter { SearchTokenization.containsCJK(distinct[$0]) }
        let other = distinct.indices.filter { !SearchTokenization.containsCJK(distinct[$0]) }
        if !cjk.isEmpty, !other.isEmpty, cjk.count != other.count {
            let minority = cjk.count < other.count ? cjk : other
            let available = minority.filter { !selected.contains($0) }
            selected.formUnion(sample(available, limit: min(limit / 4, limit - selected.count)))
        }

        let remaining = distinct.indices.filter { !selected.contains($0) }
        selected.formUnion(sample(remaining, limit: limit - selected.count))
        return distinct.indices.filter { selected.contains($0) }.map { distinct[$0] }
    }

    private static func sample(_ indices: [Int], limit: Int) -> [Int] {
        guard limit > 0 else { return [] }
        guard indices.count > limit else { return indices }
        guard limit > 1 else { return [indices[0]] }
        // Sample adjacent pairs to retain short local concepts across the span.
        var selected = Set<Int>()
        let pairs = limit / 2
        for pair in 0..<pairs {
            let position =
                pairs == 1
                ? indices.count - 2
                : Int((Double(pair) * Double(indices.count - 2) / Double(pairs - 1)).rounded())
            selected.insert(position)
            selected.insert(position + 1)
        }
        if !limit.isMultiple(of: 2) {
            let middle = pairs == 1 ? 0 : indices.count / 2
            let extra = indices.indices.filter { !selected.contains($0) }.min {
                let left = abs($0 - middle)
                let right = abs($1 - middle)
                return left == right ? $0 < $1 : left < right
            }
            if let extra { selected.insert(extra) }
        }
        return selected.sorted().map { indices[$0] }
    }

    /// Retains occurrence order, repetitions and explicit negation. This is the
    /// existing deterministic lexical/CJK projection, not linguistic stemming.
    static func orderedTokens(in value: String) -> [String] {
        let normalized = SearchTextNormalization.normalize(value)
        var result: [String] = []
        var current = ""
        var currentIsCJK: Bool?

        func finish() {
            guard !current.isEmpty else { return }
            let candidates = currentIsCJK == true ? SearchTokenization.queryTokens(for: current) : [current]
            for candidate in candidates {
                let token = SearchTextNormalization.normalize(candidate)
                let containsCJK = SearchTokenization.containsCJK(token)
                guard !token.isEmpty,
                    token.utf8.count <= 128,
                    containsCJK || token.count > 1,
                    containsCJK || !ignoredLatinTerms.contains(token)
                else { continue }
                result.append(token)
            }
            current = ""
            currentIsCJK = nil
        }

        for scalar in normalized.unicodeScalars {
            let isCJK = SearchTokenization.isCJK(scalar)
            guard isCJK || CharacterSet.alphanumerics.contains(scalar) else {
                finish()
                continue
            }
            if let currentIsCJK, currentIsCJK != isCJK { finish() }
            currentIsCJK = isCJK
            current.unicodeScalars.append(scalar)
        }
        finish()
        return result
    }

    /// Only closed, explicitly authored quotes supply phrase features. Keep
    /// function words and negation inside each phrase; do not invent bigrams.
    static func quotedPhrases(in value: String, limit: Int = 4) -> [String] {
        guard limit > 0 else { return [] }
        let closers: [Character: Character] = ["\"": "\"", "“": "”", "「": "」", "『": "』"]
        var closing: Character?
        var current = ""
        var escaped = false
        var result: [String] = []
        var seen = Set<String>()
        for character in value {
            if escaped {
                if closing != nil { current.append(character) }
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            if let expected = closing {
                if character == expected {
                    let phrase = SearchTextNormalization.lexicalNormalize(current)
                        .split(whereSeparator: \.isWhitespace).joined(separator: " ")
                    if !phrase.isEmpty, phrase.utf8.count <= 256,
                        phrase.split(whereSeparator: \.isWhitespace).count <= 16,
                        !orderedTokens(in: phrase).isEmpty,
                        seen.insert(phrase).inserted
                    {
                        result.append(phrase)
                        if result.count == limit { break }
                    }
                    closing = nil
                    current = ""
                } else {
                    current.append(character)
                }
            } else if let end = closers[character] {
                closing = end
            }
        }
        return result
    }
}
