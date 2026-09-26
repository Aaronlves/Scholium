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
