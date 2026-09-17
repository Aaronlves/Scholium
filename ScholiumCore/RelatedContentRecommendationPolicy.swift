import Foundation
import ScholiumContracts

/// Query-local lexical features, not inferred philosophical predicates. Values
/// combine only normalized signals with the same unit, never raw Note and
/// paragraph BM25 scores.
enum RelatedContentRecommendationPolicy {
    static func relevance(coverage: Double, score: Double, maximumScore: Double, phraseCoverage: Double) -> Double {
        let normalized = maximumScore > 0 ? score / maximumScore : 0
        return coverage * (0.65 + 0.35 * normalized) + 0.15 * phraseCoverage
    }

    struct TextSignature {
        let exact: String
        let words: Set<String>

        init(_ text: String) {
            exact = text.precomposedStringWithCanonicalMapping
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            words = Set(RelatedContentQueryTerms.orderedTokens(in: text))
        }

        func similarity(to other: Self) -> Double {
            if exact == other.exact { return 1 }
            // Short statements often differ by one philosophically decisive
            // word. Only downweight near copies of substantial paragraphs.
            guard words.count >= 12, other.words.count >= 12 else { return 0 }
            let intersection = words.intersection(other.words).count
            return Double(intersection) / Double(words.count + other.words.count - intersection)
        }
    }

    static func diverseScore(
        relevance: Double, strongest: Double, roleAlreadyRepresented: Bool, similarity: Double
    ) -> Double {
        let comparable = relevance >= strongest * 0.8
        let roleFactor = comparable && !roleAlreadyRepresented ? 1.1 : 1
        let diversified = comparable && similarity >= 0.85 ? max(strongest * 0.8, relevance * 0.85) : relevance
        return diversified * roleFactor
    }
}
