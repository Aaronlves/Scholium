import Foundation
import ScholiumContracts
import Testing

@Suite("Lexical normalization source ranges")
struct SearchNormalizationRangeTests {
    @Test("Unsorted and repeated requests recover exact graphemes and collapsed whitespace")
    func batchRanges() {
        let source = "\t ﬃ  cafe\u{301}\r\nλόγος 👩‍🔬  Z\n"
        #expect(SearchTextNormalization.lexicalNormalize(source) == "ffi cafe λογοσ 👩‍🔬 z")
        // These offsets are explicit UTF-16 positions in the normalized and
        // authored strings, independent of the implementation's offset map.
        let requested: [Range<Int>] = [
            15..<20, 1..<2, 9..<14, 4..<8, 3..<4, 8..<9, 20..<21,
            1..<2, 2..<5, 0..<22, 16..<17, 7..<8, 10..<11,
        ]
        let expected: [Range<Int>?] = [
            18..<23, 2..<3, 12..<17, 5..<10, 3..<5, 10..<12, 23..<25,
            2..<3, 2..<6, 2..<26, 18..<23, 8..<10, 13..<14,
        ]
        #expect(
            SearchTextNormalization.originalUTF16RangesForLexicalNormalization(
                in: source, requestedRanges: requested) == expected)
        for (range, original) in zip(requested, expected) {
            #expect(
                SearchTextNormalization.originalUTF16RangeForLexicalNormalization(
                    in: source, requestedRange: range) == original)
        }
    }

    @Test("Every code unit of an expansion or emoji maps to the complete source Character")
    func graphemeRanges() {
        let requested: [Range<Int>] = (0..<9).map { $0..<($0 + 1) }
        let expected: [Range<Int>?] = [
            0..<1, 0..<1, 0..<1, 1..<3, 3..<8, 3..<8, 3..<8, 3..<8, 3..<8,
        ]
        #expect(SearchTextNormalization.lexicalNormalize("ﬃe\u{301}👩‍🔬") == "ffie👩‍🔬")
        #expect(
            SearchTextNormalization.originalUTF16RangesForLexicalNormalization(
                in: "ﬃe\u{301}👩‍🔬", requestedRanges: requested) == expected)
    }

    @Test("Empty, negative and out-of-bounds requests return nil without clipping")
    func invalidRanges() {
        let requested = [-1..<1, -3..<(-1), 0..<0, 1..<1, 0..<4, 3..<4, 3..<3, (Int.max - 1)..<Int.max]
        let expected = [Range<Int>?](repeating: nil, count: requested.count)
        #expect(
            SearchTextNormalization.originalUTF16RangesForLexicalNormalization(
                in: " ﬃ ", requestedRanges: requested) == expected)
        for range in requested {
            #expect(
                SearchTextNormalization.originalUTF16RangeForLexicalNormalization(
                    in: " ﬃ ", requestedRange: range) == nil)
        }
        #expect(
            SearchTextNormalization.originalUTF16RangesForLexicalNormalization(
                in: "anything", requestedRanges: []
            ).isEmpty)
    }

    @Test("Empty and whitespace-only source have no normalized source span")
    func emptySource() {
        for source in ["", " \t\r\n\u{00A0}"] {
            #expect(
                SearchTextNormalization.originalUTF16RangesForLexicalNormalization(
                    in: source, requestedRanges: [0..<0, 0..<1]) == [nil, nil])
        }
    }
}
