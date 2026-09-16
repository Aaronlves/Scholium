import Foundation
import ScholiumContracts
import Testing

@Suite("Search projection normalization fidelity")
struct SearchProjectionNormalizationTests {
    @Test("ASCII case folding and Unicode grapheme maps match the lexical policy")
    func normalizationAndExactOffsets() throws {
        let source =
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789 "
            + "À cafe\u{301} ß ﬃ İ K Σςσ ＡＢＣ 🦉 👨‍👩‍👧‍👦\u{00A0}\tend"
        let projection = SearchDocumentProjection(document: NoteDocument(relativePath: "Unicode.md", rawContent: source))
        let body = try #require(projection.segments.first { $0.field == .body })
        var expectedText = ""
        var expectedMap: [SearchSegmentOffset] = []
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
                expectedMap.append(
                    SearchSegmentOffset(
                        normalizedUTF16LowerBound: normalizedOffset,
                        normalizedUTF16UpperBound: normalizedOffset + 1,
                        sourceUTF16LowerBound: pendingWhitespace.lowerBound, sourceUTF16UpperBound: pendingWhitespace.upperBound))
                normalizedOffset += 1
            }
            pendingWhitespace = nil
            let folded = SearchTextNormalization.lexicalNormalize(value)
            expectedText.append(folded)
            expectedMap.append(
                SearchSegmentOffset(
                    normalizedUTF16LowerBound: normalizedOffset,
                    normalizedUTF16UpperBound: normalizedOffset + folded.utf16.count,
                    sourceUTF16LowerBound: range.lowerBound, sourceUTF16UpperBound: range.upperBound))
            normalizedOffset += folded.utf16.count
        }
        #expect(body.normalizedText == expectedText)
        #expect(body.offsetMap == expectedMap)
        #expect(projection.paragraphs.first?.segments.first?.normalizedText == body.normalizedText)
        #expect(projection.paragraphs.first?.segments.first?.offsetMap == body.offsetMap)
        // Every folded unit, including expansions and surrogate pairs, recovers
        // the complete original grapheme rather than slicing its source encoding.
        for offset in expectedMap where offset.normalizedUTF16UpperBound > offset.normalizedUTF16LowerBound {
            for index in offset.normalizedUTF16LowerBound..<offset.normalizedUTF16UpperBound {
                #expect(
                    body.sourceUTF16Range(forNormalizedUTF16Range: index..<(index + 1))
                        == offset.sourceUTF16LowerBound..<offset.sourceUTF16UpperBound)
            }
        }
    }
}
