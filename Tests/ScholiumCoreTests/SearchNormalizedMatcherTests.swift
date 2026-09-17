import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Normalized lexical matcher")
struct SearchNormalizedMatcherTests {
    @Test("Literal matching of NFC comparison text retains canonical matching counts and token boundaries")
    func canonicalEquivalence() {
        let terms = ["agency", "café", "cafe\u{301}", "aa", "foo_bar", "自由", "行動", "自由agency", "각", "각", "ΐ", "क", "ﬀ", "K", "a"]
        let sources = [
            "agency agencywork workagency agency_ agency中文 中文agency agency.",
            "CAFÉ cafe\u{301} café cafe CAFE cafe_ cafe中文 中文cafe.",
            "aaaa aa aa_ _aa foo_bar foo_barbar foo_bar.",
            "自由自在 自由自由 行動 自由agency 自由agencywork.",
            "각 각 각행동 ΐ ι\u{308}\u{301} क कि क़ ﬀ ff K K k.",
            "😀 a\u{301} a\u{200D}b a\u{20DD} a_b a-b a\r\na\t a.",
            "",
        ]
        let batch = RelatedContentTermMatcher(terms: terms)
        for source in sources {
            let text = SearchTextNormalization.lexicalNormalize(source)
            #expect(
                batch.counts(in: text)
                    == terms.map {
                        referenceCount(term: $0, needle: SearchTextNormalization.lexicalNormalize($0), text: text)
                    })
        }
        for term in terms {
            for source in sources {
                let text = SearchTextNormalization.lexicalNormalize(source)
                let needle = SearchTextNormalization.lexicalNormalize(term)
                #expect(
                    relatedContentOccurrenceCount(term: term, text: text) == referenceCount(term: term, needle: needle, text: text),
                    "Term: \(term); normalized text: \(text)")
            }
        }
        #expect(relatedContentOccurrenceCount(term: "café", text: SearchTextNormalization.lexicalNormalize("CAFE\u{301} cafe café")) == 3)
        #expect(relatedContentOccurrenceCount(term: "自由", text: "自由自由自由") == 3)
    }

    /// Frozen previous canonical-equivalence search, independent of the optimized
    /// literal scanner. Both use the established original-term boundary policy.
    private func referenceCount(term: String, needle: String, text: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        func token(_ character: Character) -> Bool {
            character.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "_" }
        }
        var cursor = text.startIndex
        var count = 0
        while cursor < text.endIndex, let range = text.range(of: needle, range: cursor..<text.endIndex) {
            let leading =
                (term.unicodeScalars.first.map(SearchTokenization.isCJK) ?? false)
                || range.lowerBound == text.startIndex || !token(text[text.index(before: range.lowerBound)])
            let trailing =
                (term.unicodeScalars.last.map(SearchTokenization.isCJK) ?? false)
                || range.upperBound == text.endIndex || !token(text[range.upperBound])
            if leading && trailing { count += 1 }
            cursor = range.upperBound
        }
        return count
    }
}
