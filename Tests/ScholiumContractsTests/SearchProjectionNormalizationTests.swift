import Foundation
import ScholiumContracts
import Testing

@Suite("Search projection normalization fidelity")
struct SearchProjectionNormalizationTests {
    @Test("ASCII comparison matches complete Foundation folding for both policies")
    func asciiFoundationParity() {
        let ascii = String(decoding: Array(UInt8(0)...UInt8(127)), as: UTF8.self)
        for source in ["", ascii, String(ascii.reversed()), "\r\n Agency\t \r\nEVIDENCE \u{0B}\u{0C} ", "I\0Z"] {
            for options: String.CompareOptions in [[.caseInsensitive], [.caseInsensitive, .diacriticInsensitive]] {
                let folded = source.precomposedStringWithCanonicalMapping.folding(
                    options: options, locale: Locale(identifier: "en_US_POSIX"))
                let expected = folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                    .precomposedStringWithCanonicalMapping
                let actual =
                    options.contains(.diacriticInsensitive)
                    ? SearchTextNormalization.lexicalNormalize(source)
                    : SearchTextNormalization.normalize(source)
                #expect(actual.utf8.elementsEqual(expected.utf8))
            }
        }
    }

    @Test("Unicode whitespace runs collapse between whole folded graphemes")
    func whitespaceRunsAndFoldedGraphemes() {
        for whitespace in [
            " ", "\t", "\n", "\r", "\r\n", "\u{0B}", "\u{0C}", "\u{85}", "\u{A0}",
            "\u{1680}", "\u{2000}", "\u{2003}", "\u{2009}", "\u{2028}", "\u{2029}",
            "\u{202F}", "\u{205F}", "\u{3000}",
        ] {
            let source = whitespace + "ÉCOLE" + whitespace + whitespace + "Cafe\u{301} 👩‍🔬" + whitespace
            #expect(SearchTextNormalization.normalize(source).utf8.elementsEqual("école café 👩‍🔬".utf8))
            #expect(SearchTextNormalization.lexicalNormalize(source).utf8.elementsEqual("ecole cafe 👩‍🔬".utf8))
            #expect(SearchTextNormalization.normalize(whitespace + whitespace).isEmpty)
            #expect(SearchTextNormalization.lexicalNormalize(whitespace + whitespace).isEmpty)
        }
    }

    @Test("ASCII case folding and Unicode grapheme maps match the lexical policy")
    func normalizationAndExactOffsets() throws {
        let source =
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789 "
            + "À cafe\u{301} ß ﬃ İ K Σςσ ＡＢＣ 🦉 👨‍👩‍👧‍👦\u{00A0}\tend"
        let projection = SearchDocumentProjection(document: NoteDocument(relativePath: "Unicode.md", rawContent: source))
        let body = try #require(projection.segments.first { $0.field == .body })
        var expectedText = ""
        var expectedMappings: [(normalized: Range<Int>, source: Range<Int>)] = []
        var sourceOffset = 0
        var normalizedOffset = 0
        var pendingWhitespace: Range<Int>?
        for character in source {
            let value = String(character)
            let range = sourceOffset..<(sourceOffset + value.utf16.count)
            sourceOffset = range.upperBound
            if character.isWhitespace {
                if !expectedText.isEmpty, pendingWhitespace == nil { pendingWhitespace = range }
                continue
            }
            if let pendingWhitespace {
                expectedText.append(" ")
                expectedMappings.append((normalizedOffset..<(normalizedOffset + 1), pendingWhitespace))
                normalizedOffset += 1
            }
            pendingWhitespace = nil
            let folded = SearchTextNormalization.lexicalNormalize(value)
            expectedText.append(folded)
            expectedMappings.append(
                (
                    normalizedOffset..<(normalizedOffset + folded.utf16.count), range
                ))
            normalizedOffset += folded.utf16.count
        }
        #expect(body.normalizedText == expectedText)
        #expect(body.offsetMap.count < expectedMappings.count)
        #expect(projection.paragraphs.first?.segments.first?.normalizedText == body.normalizedText)
        #expect(projection.paragraphs.first?.segments.first?.offsetMap == body.offsetMap)
        // Every normalized code unit recovers the same grapheme or collapsed
        // source span as the uncompressed per-character oracle.
        for index in 0..<expectedText.utf16.count {
            let expected = expectedMappings.filter {
                $0.normalized.lowerBound <= index && $0.normalized.upperBound > index
            }
            let expectedMapping = try #require(expected.first)
            #expect(
                body.sourceUTF16Range(forNormalizedUTF16Range: index..<(index + 1))
                    == expectedMapping.source)
        }
    }
}
