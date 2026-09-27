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

    @Test("Presence skips invalid prefixes and retains all aliases without counting repeated matches")
    func canonicalPresence() {
        let terms = ["agency", "agency", "café", "cafe\u{301}", "自由", "自由agency", "not sufficient", "missing", ""]
        for prefix in ["", "a\u{200D}b "] {
            let text = SearchTextNormalization.lexicalNormalize(
                prefix + "agencywork caféine 自由agencywork not sufficiently "
                    + String(repeating: "agency CAFÉ 自由 自由agency not sufficient ", count: 100))
            let index = RelatedContentTextIndex(text)
            let expected = Set(terms.filter { canonicalCount(term: $0, text: text) > 0 })
            #expect(RelatedContentTermMatcher(terms: terms).matchingTerms(in: text, index: index) == expected)
            #expect(expected == Set(["agency", "café", "cafe\u{301}", "自由", "自由agency", "not sufficient"]))
        }
    }

    @Test("Complex graphemes retain the canonical fallback after persistence")
    func persistedComplexBoundary() throws {
        let text = SearchTextNormalization.lexicalNormalize("a\u{200D}b a agency reason freedom value")
        let index = RelatedContentTextIndex(text)
        #expect(!index.hasPreparedWords)
        let restored = try JSONDecoder().decode(RelatedContentTextIndex.self, from: JSONEncoder().encode(index))
        #expect(!restored.hasPreparedWords)
        let terms = ["a", "agency", "reason", "freedom", "value"]
        let matcher = RelatedContentTermMatcher(terms: terms)
        #expect(matcher.counts(in: text, index: restored) == terms.map { canonicalCount(term: $0, text: text) })
    }

    @Test("Independent word-object payloads retain counts and reject malformed keys and ranges")
    func persistedValidation() throws {
        let original = RelatedContentTextIndex("reason reason value foo_bar")
        let restored = try JSONDecoder().decode(RelatedContentTextIndex.self, from: JSONEncoder().encode(original))
        #expect(restored.hasPreparedWords)
        #expect(restored.hasSameWordCounts(as: original))
        #expect(restored.count(forASCIIWord: "reason") == 2)
        #expect(restored.count(forASCIIWord: "value") == 1)
        #expect(restored.count(forASCIIWord: "foo_bar") == 1)
        #expect(restored.count(forASCIIWord: "absent") == 0)
        let independent = try JSONDecoder().decode(
            RelatedContentTextIndex.self,
            from: Data(#"{"words":{"z_9":3,"a":1},"containsCJK":true}"#.utf8))
        #expect(independent.containsCJK)
        #expect(independent.count(forASCIIWord: "z_9") == 3)
        #expect(independent.count(forASCIIWord: "a") == 1)
        let maximumCount = try JSONDecoder().decode(
            RelatedContentTextIndex.self,
            from: Data(#"{"words":{"word":4294967295},"containsCJK":false}"#.utf8))
        #expect(maximumCount.count(forASCIIWord: "word") == Int(UInt32.max))
        for malformed in [
            #"{"words":{"reason":0},"containsCJK":false}"#,
            #"{"words":{"reason":-1},"containsCJK":false}"#,
            #"{"words":{"two words":1},"containsCJK":false}"#,
            #"{"words":{"é":1},"containsCJK":false}"#,
            #"{"words":{"reason":4294967296},"containsCJK":false}"#,
        ] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(RelatedContentTextIndex.self, from: Data(malformed.utf8))
            }
        }
    }

    @Test("Compact lookup preserves long ASCII prefix ordering and nil versus empty preparation")
    func compactPrefixLookup() throws {
        var counts = Dictionary(
            uniqueKeysWithValues: (0..<512).map { ("conceptualword0_\($0)", ($0 % 3) + 1) })
        counts["conceptualword0_5extra"] = 4
        let payload = try JSONSerialization.data(withJSONObject: [
            "words": counts, "containsCJK": false,
        ])
        let index = try JSONDecoder().decode(RelatedContentTextIndex.self, from: payload)
        #expect(index.hasPreparedWords)
        for (word, count) in counts { #expect(index.count(forASCIIWord: word) == count) }
        for absent in ["conceptualword0", "conceptualword0_", "conceptualword0_51extra", "conceptualword0_512"] {
            #expect(index.count(forASCIIWord: absent) == 0)
        }
        let adjacent = RelatedContentTextIndex("a aa a0 a_ aa")
        #expect(adjacent.count(forASCIIWord: "a") == 1)
        #expect(adjacent.count(forASCIIWord: "aa") == 2)
        #expect(adjacent.count(forASCIIWord: "a0") == 1)
        #expect(adjacent.count(forASCIIWord: "a_") == 1)
        #expect(adjacent.count(forASCIIWord: "a1") == 0)
        let text = counts.sorted { $0.key < $1.key }
            .flatMap { Array(repeating: $0.key, count: $0.value) }.joined(separator: " ")
        let normalized = SearchTextNormalization.lexicalNormalize(text)
        let terms = ["conceptualword0_5", "conceptualword0_5extra", "conceptualword0_50", "conceptualword0_512"]
        let matcher = RelatedContentTermMatcher(terms: terms)
        #expect(matcher.counts(in: normalized, index: index) == matcher.counts(in: normalized))
        #expect(matcher.matchingTerms(in: normalized, index: index) == matcher.matchingTerms(in: normalized))

        let empty = try JSONDecoder().decode(
            RelatedContentTextIndex.self, from: Data(#"{"words":{},"containsCJK":false}"#.utf8))
        let fallback = try JSONDecoder().decode(
            RelatedContentTextIndex.self, from: Data(#"{"words":null,"containsCJK":false}"#.utf8))
        #expect(empty.hasPreparedWords && empty.count(forASCIIWord: "agency") == 0)
        #expect(!fallback.hasPreparedWords && fallback.count(forASCIIWord: "agency") == nil)
        let freshEmpty = RelatedContentTextIndex("")
        let restoredEmpty = try JSONDecoder().decode(
            RelatedContentTextIndex.self, from: JSONEncoder().encode(freshEmpty))
        #expect(freshEmpty.hasPreparedWords && restoredEmpty.hasPreparedWords)
        #expect(restoredEmpty.count(forASCIIWord: "agency") == 0)
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
