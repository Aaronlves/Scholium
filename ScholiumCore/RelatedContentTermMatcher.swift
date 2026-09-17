import Foundation
import ScholiumContracts

/// Query-sized matcher over either a shared token scan or revision-bound
/// prepared word counts. Phrases and Unicode substring rules retain the exact
/// Search matcher; this value owns no source authority or corpus lifecycle.
struct RelatedContentTermMatcher {
    let terms: [String]
    let needles: [String]
    private let wordIndices: [String: [Int]]
    private let otherIndices: [Int]
    private let cjkIndices: Set<Int>

    init(terms: [String]) {
        self.terms = terms
        let normalized = terms.map(SearchTextNormalization.lexicalNormalize)
        needles = normalized
        var words: [String: [Int]] = [:]
        var other: [Int] = []
        for (index, needle) in needles.enumerated() {
            if !needle.isEmpty,
                needle.utf8.allSatisfy({
                    (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95
                })
            {
                words[needle, default: []].append(index)
            } else {
                other.append(index)
            }
        }
        wordIndices = words
        otherIndices = other
        cjkIndices = Set(normalized.indices.filter { SearchTokenization.containsCJK(normalized[$0]) })
    }

    func counts(in normalizedText: String) -> [Int] {
        guard !normalizedText.isEmpty else { return Array(repeating: 0, count: terms.count) }
        guard wordIndices.count >= 4 else { return exactCounts(in: normalizedText) }
        var complexTokenBoundary = false
        let words = normalizedText.split { character in
            var allTokenScalars = true
            var anyTokenScalar = false
            for scalar in character.unicodeScalars {
                let tokenScalar = CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
                allTokenScalars = allTokenScalars && tokenScalar
                anyTokenScalar = anyTokenScalar || tokenScalar
            }
            // A combining grapheme can contain a word scalar while the whole
            // Character is a boundary. Leave those partial-grapheme cases to
            // the existing exact matcher rather than invent token semantics.
            if !allTokenScalars && anyTokenScalar { complexTokenBoundary = true }
            return !allTokenScalars
        }
        guard !complexTokenBoundary else { return exactCounts(in: normalizedText) }
        var result = Array(repeating: 0, count: terms.count)
        for word in words {
            guard let indices = wordIndices[String(word)] else { continue }
            for index in indices { result[index] += 1 }
        }
        for index in otherIndices {
            result[index] = relatedContentOccurrenceCount(
                term: terms[index], text: normalizedText, normalizedNeedle: needles[index])
        }
        return result
    }

    func counts(in normalizedText: String, index: RelatedContentTextIndex) -> [Int] {
        guard let words = index.words else { return exactCounts(in: normalizedText) }
        var result = Array(repeating: 0, count: terms.count)
        for (word, indices) in wordIndices {
            let count = words[word, default: 0]
            for i in indices { result[i] = count }
        }
        for i in otherIndices {
            if !index.containsCJK && cjkIndices.contains(i) { continue }
            result[i] = relatedContentOccurrenceCount(term: terms[i], text: normalizedText, normalizedNeedle: needles[i])
        }
        return result
    }

    func matchingTerms(in normalizedText: String, index: RelatedContentTextIndex) -> Set<String> {
        let counts = counts(in: normalizedText, index: index)
        return Set(terms.indices.compactMap { counts[$0] > 0 ? terms[$0] : nil })
    }

    func matchingTerms(in normalizedText: String) -> Set<String> {
        let frequencies = counts(in: normalizedText)
        return Set(terms.indices.compactMap { frequencies[$0] > 0 ? terms[$0] : nil })
    }

    private func exactCounts(in normalizedText: String) -> [Int] {
        terms.indices.map {
            relatedContentOccurrenceCount(term: terms[$0], text: normalizedText, normalizedNeedle: needles[$0])
        }
    }
}
