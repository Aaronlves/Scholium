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

    @Test("A prepared map reuses the frozen Unicode mapping across different range batches")
    func preparedMappingParity() {
        for source in [
            "", " \t\r\n\u{00A0}", "哲学 自由自由", "\t ﬃ  cafe\u{301}\r\nλόγος 👩‍🔬  Z\n",
            "ﬃe\u{301}👩‍🔬", "Straße STRASSE", "Cafe\u{301} and café", "a\u{200D}b",
            "👨‍👩‍👧‍👦 😀 \t 自由\r\n自由", "\u{FEFF}ﬃ\nÉmotion", "한 한", "İıΣςσ",
        ] {
            let count = SearchTextNormalization.lexicalNormalize(source).utf16.count
            var ranges: [Range<Int>] = [-1..<1, 0..<0, count..<(count + 1), (Int.max - 1)..<Int.max]
            for lower in 0...count {
                for upper in lower...count { ranges.append(lower..<upper) }
            }
            ranges.reverse()
            ranges.append(contentsOf: ranges.prefix(7))
            let expected = frozenRanges(in: source, requestedRanges: ranges)
            let prepared = SearchTextNormalization.prepareOriginalUTF16RangesForLexicalNormalization(in: source)
            #expect(prepared.originalUTF16Ranges(for: ranges) == expected)
            #expect(prepared.originalUTF16Ranges(for: []).isEmpty)
            for offset in stride(from: 0, to: ranges.count, by: 7) {
                let end = min(offset + 7, ranges.count)
                #expect(prepared.originalUTF16Ranges(for: Array(ranges[offset..<end])) == Array(expected[offset..<end]))
            }
            #expect(SearchTextNormalization.originalUTF16RangesForLexicalNormalization(
                in: source, requestedRanges: ranges) == expected)
        }
    }

    @Test("Bounded Character fold reuse preserves the frozen map across distinct and oversized inputs")
    func boundedCharacterFoldParity() throws {
        let distinctCharacters = (0..<320).compactMap { Unicode.Scalar(0x4E00 + $0) }.map(String.init)
        try #require(distinctCharacters.count == 320)
        let distinct = distinctCharacters.joined(separator: " ")
        let repeated = "CAFÉ Cafe\u{301} ﬃ Straße İ \u{301} 👩‍🔬 \t"
        let longDiacritic = "a" + String(repeating: "\u{301}", count: 80)
        let longEmoji = String(repeating: "👩\u{200D}", count: 20) + "👩"
        try #require(longDiacritic.count == 1 && longDiacritic.utf8.count > 64)
        try #require(longEmoji.count == 1 && longEmoji.utf8.count > 64)
        let fixtures = [
            "", " \t\r\n\u{00A0}", "\u{301} \u{301} \u{301}",
            String(repeating: repeated, count: 24),
            // Populate beyond the 256-key cap before exercising repeated
            // expansion/empty folds and canonically equivalent byte spellings.
            distinct + " " + String(repeating: repeated, count: 12) + " " + distinct,
            String(repeating: longDiacritic + " " + longEmoji + " É e\u{301} ", count: 5),
        ]
        for source in fixtures {
            let count = SearchTextNormalization.lexicalNormalize(source).utf16.count
            var ranges: [Range<Int>] = [-1..<1, 0..<0, count..<(count + 1), (Int.max - 1)..<Int.max]
            if count > 0 {
                ranges.append(0..<count)
                for lower in 0..<count {
                    ranges.append(lower..<(lower + 1))
                    if lower.isMultiple(of: 5) {
                        ranges.append(max(0, lower - 1)..<min(count, lower + 4))
                    }
                }
            }
            ranges.reverse()
            ranges.append(contentsOf: ranges.prefix(11))
            let expected = frozenRanges(in: source, requestedRanges: ranges)
            let prepared = SearchTextNormalization.prepareOriginalUTF16RangesForLexicalNormalization(in: source)
            #expect(prepared.originalUTF16Ranges(for: ranges) == expected)
            #expect(SearchTextNormalization.originalUTF16RangesForLexicalNormalization(
                in: source, requestedRanges: ranges) == expected)
            for offset in stride(from: 0, to: ranges.count, by: 19) {
                let end = min(offset + 19, ranges.count)
                #expect(prepared.originalUTF16Ranges(for: Array(ranges[offset..<end])) == Array(expected[offset..<end]))
            }
        }
    }

    @Test("Equivalent NFC and NFD folds retain each authored Character's own UTF16 length")
    func repeatedCanonicalSpellingCoordinates() {
        let source = "é e\u{301} é e\u{301}"
        let requested = [0..<1, 2..<3, 4..<5, 6..<7, 1..<6]
        let expected: [Range<Int>?] = [0..<1, 2..<4, 5..<6, 7..<9, 1..<7]
        #expect(SearchTextNormalization.lexicalNormalize(source) == "e e e e")
        #expect(SearchTextNormalization.originalUTF16RangesForLexicalNormalization(
            in: source, requestedRanges: requested) == expected)
    }

    private func frozenRanges(
        in value: String,
        requestedRanges: [Range<Int>]
    ) -> [Range<Int>?] {
        let normalizer = SearchTextNormalization.lexicalNormalize
        guard !requestedRanges.isEmpty else { return [] }
        struct Offset {
            let normalized: Range<Int>
            let original: Range<Int>
        }

        var normalized = ""
        var normalizedUTF16Count = 0
        var offsets: [Offset] = []
        var originalCursor = 0
        var pendingWhitespace: Range<Int>?
        for character in value {
            let originalLength = String(character).utf16.count
            let originalRange = originalCursor..<(originalCursor + originalLength)
            originalCursor += originalLength
            if character.isWhitespace {
                guard !normalized.isEmpty else { continue }
                if let existing = pendingWhitespace {
                    pendingWhitespace = existing.lowerBound..<originalRange.upperBound
                } else {
                    pendingWhitespace = originalRange
                }
                continue
            }
            if let pendingWhitespace {
                let lower = normalizedUTF16Count
                normalized.append(" ")
                normalizedUTF16Count += 1
                offsets.append(
                    Offset(
                        normalized: lower..<(lower + 1),
                        original: pendingWhitespace
                    ))
            }
            pendingWhitespace = nil
            let folded = normalizer(String(character))
            let lower = normalizedUTF16Count
            normalized += folded
            normalizedUTF16Count += folded.utf16.count
            offsets.append(
                Offset(
                    normalized: lower..<normalizedUTF16Count,
                    original: originalRange
                ))
        }

        guard normalized == normalizer(value) else {
            return Array(repeating: nil, count: requestedRanges.count)
        }
        return requestedRanges.map { requestedRange in
            guard !requestedRange.isEmpty,
                requestedRange.lowerBound >= 0,
                requestedRange.upperBound <= normalizedUTF16Count
            else { return nil }

            var lower = 0
            var upper = offsets.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if offsets[middle].normalized.upperBound <= requestedRange.lowerBound {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            let first = lower
            upper = offsets.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if offsets[middle].normalized.lowerBound < requestedRange.upperBound {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            guard first < lower else { return nil }
            return offsets[first].original.lowerBound..<offsets[lower - 1].original.upperBound
        }
    }
}
