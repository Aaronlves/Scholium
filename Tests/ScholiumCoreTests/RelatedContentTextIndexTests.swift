import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Prepared related-content text counts")
struct RelatedContentTextIndexTests {
    @Test("Prepared counts retain canonical word boundaries for small and mixed queries")
    func canonicalCountEquivalence() {
        let groups = [
            ["agency"],
            ["agency", "reason"],
            ["agency", "reason", "value"],
            ["agency", "reason", "value", "freedom"],
            ["agency", "reason", "value", "freedom", "autonomy"],
            ["café", "cafe\u{301}", "cafe", "CAFÉ", ""],
            ["a", "aa", "foo_bar", "_", "foo", "bar", "a-b", "not sufficient"],
            ["自由", "意志", "行動", "自由agency", "agency自由", "각", "각"],
            ["i", "I", "İ", "ı", "ΐ", "क", "ﬀ", "K"],
        ]
        let sources = [
            "agency agencywork workagency agency_ reason value freedom autonomy agency.",
            "agency中文 中文agency 自由agency 自由agencywork agency自由 agency自由意志 自由自由.",
            "CAFÉ cafe\u{301} café cafe CAFE cafe_ caféine.",
            "aaaa aa aa_ _aa foo_bar foo_barbar foo-bar _ foo_bar. not sufficient not sufficiently.",
            "自由意志自由 行動 各个 各自 각 각 각행동.",
            "I i İ ı i\u{307} ΐ ι\u{308}\u{301} क कि क़ ﬀ ff K K k.",
            "😀 a\u{301} a\u{200D}b a\u{20DD} a_b a-b a\r\na\t a.",
            "a\u{20DD} agency reason value freedom autonomy",
            "",
        ]
        for source in sources {
            let text = SearchTextNormalization.lexicalNormalize(source)
            let index = RelatedContentTextIndex(text)
            #expect(index.isValid)
            for terms in groups {
                let matcher = RelatedContentTermMatcher(terms: terms)
                let expected = terms.map { canonicalCount(term: $0, text: text) }
                #expect(matcher.counts(in: text, index: index) == expected)
                #expect(matcher.counts(in: text, index: index) == matcher.counts(in: text))
                #expect(matcher.matchingTerms(in: text, index: index) == Set(terms.indices.compactMap { expected[$0] > 0 ? terms[$0] : nil }))
            }
        }
    }

    @Test("Repeated and normalization-equivalent query terms keep individual count slots")
    func independentExpectedCounts() {
        let text = SearchTextNormalization.lexicalNormalize("café CAFÉ cafe\u{301} freedom free foo_bar foo-bar 自由自由自由")
        let terms = ["café", "cafe", "cafe\u{301}", "freedom", "freedom", "free", "foo_bar", "foo", "自由"]
        let matcher = RelatedContentTermMatcher(terms: terms)
        #expect(matcher.counts(in: text, index: RelatedContentTextIndex(text)) == [3, 3, 3, 1, 1, 1, 1, 1, 3])
    }

    @Test("Complex graphemes retain the canonical fallback after persistence")
    func persistedComplexBoundary() throws {
        let text = SearchTextNormalization.lexicalNormalize("a\u{200D}b a agency reason freedom value")
        let index = RelatedContentTextIndex(text)
        #expect(index.words == nil)
        let restored = try JSONDecoder().decode(RelatedContentTextIndex.self, from: JSONEncoder().encode(index))
        #expect(restored.words == nil)
        let terms = ["a", "agency", "reason", "freedom", "value"]
        let matcher = RelatedContentTermMatcher(terms: terms)
        #expect(matcher.counts(in: text, index: restored) == terms.map { canonicalCount(term: $0, text: text) })
    }

    @Test("Persistent prepared counts reject malformed keys and nonpositive counts")
    func persistedValidation() throws {
        let original = RelatedContentTextIndex("reason reason value foo_bar")
        let restored = try JSONDecoder().decode(RelatedContentTextIndex.self, from: JSONEncoder().encode(original))
        #expect(restored.isValid)
        #expect(restored.words == ["reason": 2, "value": 1, "foo_bar": 1])
        for malformed in [
            #"{"words":{"reason":0},"containsCJK":false}"#, #"{"words":{"reason":-1},"containsCJK":false}"#, #"{"words":{"two words":1},"containsCJK":false}"#,
        ] {
            let decoded = try JSONDecoder().decode(RelatedContentTextIndex.self, from: Data(malformed.utf8))
            #expect(!decoded.isValid)
        }
    }

    /// Frozen canonical string-search policy, independent of prepared word
    /// dictionaries and the optimized literal matcher.
    private func canonicalCount(term: String, text: String) -> Int {
        let needle = SearchTextNormalization.lexicalNormalize(term)
        guard !needle.isEmpty else { return 0 }
        func isToken(_ character: Character) -> Bool {
            character.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "_" }
        }
        var cursor = text.startIndex
        var count = 0
        while cursor < text.endIndex, let range = text.range(of: needle, range: cursor..<text.endIndex) {
            let leading =
                (term.unicodeScalars.first.map(SearchTokenization.isCJK) ?? false)
                || range.lowerBound == text.startIndex || !isToken(text[text.index(before: range.lowerBound)])
            let trailing =
                (term.unicodeScalars.last.map(SearchTokenization.isCJK) ?? false)
                || range.upperBound == text.endIndex || !isToken(text[range.upperBound])
            if leading && trailing { count += 1 }
            cursor = range.upperBound
        }
        return count
    }
}
