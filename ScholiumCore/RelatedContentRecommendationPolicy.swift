import Foundation
import ScholiumContracts

/// Query-local lexical features, not inferred philosophical predicates. Values
/// combine only normalized signals with the same unit, never raw Note and
/// paragraph BM25 scores.
enum RelatedContentRecommendationPolicy {
    /// A complete Note name in both the explicit focus and the local paragraph
    /// is a lexical witness even when surrounding prose dilutes term coverage.
    /// Metadata alone, a partial name, or a name only in the surrounding Note
    /// cannot supply this witness. It changes admission, not relevance scores.
    static func focusedIdentityMentions(in document: NoteDocument, material: RelatedContentSeedMaterial) -> [RelatedContentIdentityMention] {
        // Reuse the identity matcher over the verified current source. The
        // bounded identity candidate channel must not decide paragraph admission.
        let properties = SearchPropertyProjection(document: document)
        let reason = material.identityMentionReason(
            title: ResearchNoteTitleResolver.resolve(document: document), aliases: properties.textValues(forExactKey: "aliases"))
        return (reason?.mentions ?? []).filter(isFocusedIdentity)
    }

    static func isFocusedIdentity(_ mention: RelatedContentIdentityMention) -> Bool {
        mention.seedKind != .sourceNote
            && RelatedContentQueryTerms.orderedTokens(in: mention.matchedIdentity).contains {
                !["not", "no", "never", "cannot", "only"].contains($0)
            }
    }

    static func locallyMatchesFocusedIdentity(_ identities: [String], normalizedText: String) -> Bool {
        identities.contains { identity in
            SearchMatcher.containsOccurrence(
                of: .phrase(identity), in: normalizedText, normalizedNeedle: SearchTextNormalization.lexicalNormalize(identity))
        }
    }

    /// Connectivity refines an already matching paragraph. It cannot admit
    /// unrelated prose or turn a path into a support/confidence judgment.
    static func graphFactor(_ context: RelatedContentGraphContext?) -> Double {
        guard let context, context.paths.contains(where: \.isValid), context.proximity.isFinite else { return 1 }
        return 1 + 0.15 * min(1, max(0, context.proximity))
    }

    static func relevance(coverage: Double, score: Double, maximumScore: Double, phraseCoverage: Double) -> Double {
        let normalized = maximumScore > 0 ? score / maximumScore : 0
        return coverage * (0.65 + 0.35 * normalized) + 0.15 * phraseCoverage
    }

    struct TextSignature {
        let exact: String
        let words: Set<String>

        init(_ text: String) {
            exact = Self.exact(in: text)
            words = Set(RelatedContentQueryTerms.orderedTokens(in: text))
        }

        /// Readable copies share canonical Unicode and whitespace; case and
        /// diacritics remain authored distinctions rather than lexical keys.
        static func exact(in text: String) -> String {
            text.precomposedStringWithCanonicalMapping
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
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
