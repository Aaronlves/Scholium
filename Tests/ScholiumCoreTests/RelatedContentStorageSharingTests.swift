import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Related-content immutable storage fidelity")
struct RelatedContentStorageSharingTests {
    @Test("Persisted field references decode an independent fixture and reject missing targets")
    func independentStoredReferences() throws {
        let payload = Data(
            #"{"scoringDocument":{"fields":{"body":"needle needle 自由"},"fieldLengths":{"body":3},"textIndexes":{"body":{"words":{"needle":2},"containsCJK":true}}},"segments":[{"field":"body","material":{"scoringField":{"_0":"body"}}}]}"#
                .utf8)
        let value = try RelatedContentLexicalProjection.decode(payload, checksum: RelatedContentSourceProjection.checksum(payload))
        #expect(value.segments.map(\.text) == ["needle needle 自由"])
        let material = try #require(value.segments.first)
        #expect(RelatedContentTermMatcher(terms: ["needle", "自由"]).counts(in: material.text, index: material.index) == [2, 1])
        let missing = Data(String(decoding: payload, as: UTF8.self).replacingOccurrences(of: #""_0":"body""#, with: #""_0":"absent""#).utf8)
        #expect(throws: SearchIndexError.self) {
            try RelatedContentLexicalProjection.decode(missing, checksum: RelatedContentSourceProjection.checksum(missing))
        }

        let paragraph = Data(
            #"{"range":{"utf16LowerBound":0,"utf16UpperBound":16,"line":1,"column":1,"endLine":1,"endColumn":17},"matchingText":{"scoringField":{"_0":"body"}},"scoringDocument":{"fields":{"body":"needle needle 自由"},"fieldLengths":{"body":3},"textIndexes":{"body":{"words":{"needle":2},"containsCJK":true}}}}"#
                .utf8)
        let decoded = try JSONDecoder().decode(RelatedContentSourceProjection.Paragraph.self, from: paragraph)
        #expect(decoded.displayText == "needle needle 自由")
        #expect(decoded.normalizedDisplayText == decoded.displayText)
        #expect(decoded.range.utf16LowerBound == 0 && decoded.range.utf16UpperBound == 16)
        #expect(decoded.textIndex.words == ["needle": 2])
        let invalidParagraph = Data(String(decoding: paragraph, as: UTF8.self).replacingOccurrences(of: #""_0":"body""#, with: #""_0":"absent""#).utf8)
        #expect(throws: SearchIndexError.self) {
            try JSONDecoder().decode(RelatedContentSourceProjection.Paragraph.self, from: invalidParagraph)
        }
    }

    @Test("Sharing never substitutes canonical-equivalent bytes or different prepared counts")
    func exactValueBoundary() throws {
        let scoring = try JSONDecoder().decode(
            RelatedContentBM25F.Document.self,
            from: Data(#"{"fields":{"body":"é needle 自由"},"fieldLengths":{"body":3},"textIndexes":{"body":{"words":{"needle":1},"containsCJK":true}}}"#.utf8))
        let index = RelatedContentTextIndex("é needle 自由")
        let decomposed = "e\u{301} needle 自由"
        let distinctBytes = scoring.sharingPreparedText(decomposed, index: index)
        #expect(distinctBytes.text.utf8.elementsEqual(decomposed.utf8))
        #expect(!distinctBytes.text.utf8.elementsEqual(scoring.fields["body"]!.utf8))

        let differentCounts = try JSONDecoder().decode(
            RelatedContentTextIndex.self, from: Data(#"{"words":{"needle":2},"containsCJK":true}"#.utf8))
        let retainedCounts = scoring.sharingPreparedText("é needle 自由", index: differentCounts)
        #expect(retainedCounts.index.words?["needle"] == 2)
        let differentCJK = try JSONDecoder().decode(
            RelatedContentTextIndex.self, from: Data(#"{"words":{"needle":1},"containsCJK":false}"#.utf8))
        #expect(!scoring.sharingPreparedText("é needle 自由", index: differentCJK).index.containsCJK)
    }

    @Test("Fresh and decoded matching material preserves exact multilingual text, counts and source coordinates")
    func projectionRoundTrip() throws {
        let source = "\u{FEFF}# Émotion 😀\r\n\r\nCAFÉ cafe\u{301} needle needle 自由自由.\r\n\r\n[[Target|行动]]{{needle reasons}}.\r\n"
        let note = NoteDocument(relativePath: "Fixture.md", rawContent: source)
        let lexical = RelatedContentLexicalProjection(projection: SearchDocumentProjection(document: note))
        let bytes = try lexical.encoded()
        let decoded = try RelatedContentLexicalProjection.decode(bytes, checksum: RelatedContentSourceProjection.checksum(bytes))
        #expect(decoded.segments.count == lexical.segments.count)
        let matcher = RelatedContentTermMatcher(terms: ["needle", "café", "cafe\u{301}", "自由", "行动", "reasons"])
        for (actual, expected) in zip(decoded.segments, lexical.segments) {
            #expect(actual.field == expected.field)
            #expect(actual.text.utf8.elementsEqual(expected.text.utf8))
            #expect(actual.index.words == expected.index.words)
            #expect(actual.index.containsCJK == expected.index.containsCJK)
            #expect(matcher.counts(in: actual.text, index: actual.index) == matcher.counts(in: expected.text))
        }
        let passages = try RelatedContentSourceProjection(document: note)
        let passageBytes = try passages.encoded()
        let restored = try RelatedContentSourceProjection.decode(
            passageBytes, checksum: RelatedContentSourceProjection.checksum(passageBytes), sourceUTF16Count: source.utf16.count)
        #expect(restored.paragraphs.map(\.range) == passages.paragraphs.map(\.range))
        for (actual, expected) in zip(restored.paragraphs, passages.paragraphs) {
            #expect(actual.displayText.utf8.elementsEqual(expected.displayText.utf8))
            #expect(actual.normalizedDisplayText.utf8.elementsEqual(expected.normalizedDisplayText.utf8))
            #expect(actual.textIndex.words == expected.textIndex.words)
            #expect(actual.textIndex.containsCJK == expected.textIndex.containsCJK)
            #expect(matcher.counts(in: actual.normalizedDisplayText, index: actual.textIndex) == matcher.counts(in: expected.normalizedDisplayText))
        }
    }
}
