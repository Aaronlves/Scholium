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
        #expect(decoded.textIndex.count(forASCIIWord: "needle") == 2)
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
        #expect(retainedCounts.index.count(forASCIIWord: "needle") == 2)
        let differentCJK = try JSONDecoder().decode(
            RelatedContentTextIndex.self, from: Data(#"{"words":{"needle":1},"containsCJK":false}"#.utf8))
        #expect(!scoring.sharingPreparedText("é needle 自由", index: differentCJK).index.containsCJK)
    }

    @Test("Fresh and decoded matching material preserves exact multilingual text, counts and source coordinates")
    func projectionRoundTrip() throws {
        let source = "\u{FEFF}# Émotion 😀\r\n\r\nCAFÉ cafe\u{301} needle needle 自由自由.\r\n\r\n[[Target|行动]]{{needle reasons}}.\r\n"
        let note = NoteDocument(relativePath: "Fixture.md", rawContent: source)
        let projection = SearchDocumentProjection(document: note)
        let lexical = RelatedContentLexicalProjection(
            projection: projection, scoringDocument: .init(segments: projection.segments))
        let bytes = try lexical.encoded()
        let decoded = try RelatedContentLexicalProjection.decode(bytes, checksum: RelatedContentSourceProjection.checksum(bytes))
        #expect(decoded.segments.count == lexical.segments.count)
        let matcher = RelatedContentTermMatcher(terms: ["needle", "café", "cafe\u{301}", "自由", "行动", "reasons"])
        for (actual, expected) in zip(decoded.segments, lexical.segments) {
            #expect(actual.field == expected.field)
            #expect(actual.text.utf8.elementsEqual(expected.text.utf8))
            #expect(actual.index.hasSameWordCounts(as: expected.index))
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
            #expect(actual.textIndex.hasSameWordCounts(as: expected.textIndex))
            #expect(actual.textIndex.containsCJK == expected.textIndex.containsCJK)
            #expect(matcher.counts(in: actual.normalizedDisplayText, index: actual.textIndex) == matcher.counts(in: expected.normalizedDisplayText))
        }
    }

    @Test("Repeated paragraphs share long immutable payloads while every exact source range survives")
    func repeatedParagraphPayloads() throws {
        let paragraph = Array(repeating: "Café cafe\u{301} needle 自由 👩‍🔬.", count: 12).joined(separator: " ")
        let independent = String(decoding: Array(paragraph.utf8), as: UTF8.self)
        try #require(paragraph.utf8.count > 128)
        #expect(paragraph.utf8.elementsEqual(independent.utf8))
        #expect(!sharesUTF8Storage(paragraph, independent))
        let prefix = "\u{FEFF}# Repeated 😀\r\n\r\n"
        let source = prefix + Array(repeating: paragraph, count: 3).joined(separator: "\r\n\r\n") + "\r\n"
        let document = NoteDocument(relativePath: "Repeats.md", rawContent: source)
        let fresh = try RelatedContentSourceProjection(document: document)
        let data = try fresh.encoded()
        let decoded = try RelatedContentSourceProjection.decode(
            data, checksum: RelatedContentSourceProjection.checksum(data), sourceUTF16Count: source.utf16.count)
        let expectedRanges = (0..<3).map { index in
            let start = prefix.utf16.count + index * (paragraph.utf16.count + 4)
            return SearchSourceRange(
                utf16LowerBound: start, utf16UpperBound: start + paragraph.utf16.count,
                line: 3 + index * 2, column: 1, endLine: 3 + index * 2, endColumn: paragraph.utf16.count + 1)
        }
        for projection in [fresh, decoded] {
            try #require(projection.paragraphs.count == 3)
            #expect(projection.paragraphs.map(\.range) == expectedRanges)
            let first = projection.paragraphs[0]
            for current in projection.paragraphs {
                let range = try #require(Range(
                    NSRange(location: current.range.utf16LowerBound, length: paragraph.utf16.count), in: source))
                #expect(source[range].utf8.elementsEqual(paragraph.utf8))
                #expect(current.displayText.utf8.elementsEqual(paragraph.utf8))
                #expect(sharesUTF8Storage(first.displayText, current.displayText))
                #expect(sharesUTF8Storage(first.exactReadableText, current.exactReadableText))
                #expect(sharesUTF8Storage(first.normalizedDisplayText, current.normalizedDisplayText))
                #expect(sharesUTF8Storage(
                    try #require(first.scoringDocument.fields["body"]),
                    try #require(current.scoringDocument.fields["body"])))
                #expect(current.textIndex.count(forASCIIWord: "needle") == 12)
            }
        }
        #expect(try canonicalJSON(decoded.encoded()) == canonicalJSON(data))
        #expect(document.rawContent.utf8.elementsEqual(source.utf8))
    }

    @Test("Per-source sharing preserves independent wire values, exact Unicode, indexes and signed lengths")
    func independentParagraphPayloadBoundary() throws {
        let display = Array(repeating: "Café needle 自由", count: 12).joined(separator: " ")
        // An independent persisted value may carry exact NFC/NFD strings. Its
        // admission does not normalize them; interning must not do so either.
        let normalized = display
        let decomposed = display.decomposedStringWithCanonicalMapping
        try #require(display.utf8.count > 128 && !display.utf8.elementsEqual(decomposed.utf8))
        func stored(
            _ index: Int, text: String? = nil, matching: String? = nil,
            matchingWords: String = #"{"needle":1}"#, matchingCJK: Bool = true,
            field: String = "body", fieldText: String? = nil, length: String = "0.0",
            fieldWords: String = #"{"needle":1}"#, fieldCJK: Bool = true, includeAnnotation: Bool = false
        ) throws -> String {
            let text = text ?? display
            let start = index * 1_000
            let annotation = includeAnnotation ? #", "annotation":"annotation needle""# : ""
            let annotationLength = includeAnnotation ? #", "annotation":2.0"# : ""
            let annotationIndex = includeAnnotation
                ? #", "annotation":{"words":{"annotation":1,"needle":1},"containsCJK":false}"# : ""
            return """
                {"range":{"utf16LowerBound":\(start),"utf16UpperBound":\(start + text.utf16.count),"line":\(index + 1),"column":1,"endLine":\(index + 1),"endColumn":\(text.utf16.count + 1)},
                "displayText":\(try jsonString(text)),
                "matchingText":{"independent":{"text":\(try jsonString(matching ?? normalized)),"index":{"words":\(matchingWords),"containsCJK":\(matchingCJK)}}},
                "scoringDocument":{"fields":{\(try jsonString(field)):\(try jsonString(fieldText ?? normalized))\(annotation)},"fieldLengths":{\(try jsonString(field)):\(length)\(annotationLength)},"textIndexes":{\(try jsonString(field)):{"words":\(fieldWords),"containsCJK":\(fieldCJK)}\(annotationIndex)}}}
                """
        }
        let fallbackDisplay = display + " fallback"
        let supersetFirstDisplay = display + " superset first"
        let subsetFirstDisplay = display + " subset first"
        let payloads = try [
            stored(0), stored(1),
            stored(2, matchingWords: #"{"needle":2}"#),
            stored(3, matchingWords: #"{"needle":2}"#),
            stored(4),
            stored(5, matchingCJK: false),
            stored(6, field: "annotation"),
            stored(7, fieldText: normalized + " distinct"),
            stored(8, length: "-0.0"),
            stored(9, fieldWords: #"{"needle":2}"#),
            stored(10, fieldCJK: false),
            stored(11, text: decomposed),
            stored(12, matching: decomposed),
            stored(13, fieldText: decomposed),
            stored(14, text: fallbackDisplay, matchingWords: "null"),
            stored(15, text: fallbackDisplay, matchingWords: "{}"),
            stored(16, text: decomposed),
            stored(17, text: supersetFirstDisplay, includeAnnotation: true),
            stored(18, text: supersetFirstDisplay),
            stored(19, text: subsetFirstDisplay),
            stored(20, text: subsetFirstDisplay, includeAnnotation: true),
        ]
        // Decode the expected paragraphs independently: this path never reaches
        // the root projection's interner or borrows another paragraph's payload.
        let expected = try payloads.map {
            try JSONDecoder().decode(RelatedContentSourceProjection.Paragraph.self, from: Data($0.utf8))
        }
        let wire = Data("""
            {"noteScoringDocument":{"fields":{},"fieldLengths":{},"textIndexes":{}},"paragraphs":[\(payloads.joined(separator: ","))]}
            """.utf8)
        let sourceUTF16Count = try #require(expected.map { $0.range.utf16UpperBound }.max())
        let projection = try RelatedContentSourceProjection.decode(
            wire, checksum: RelatedContentSourceProjection.checksum(wire), sourceUTF16Count: sourceUTF16Count)
        let actual = projection.paragraphs
        try #require(actual.count == expected.count)
        for (actual, expected) in zip(actual, expected) {
            #expect(actual.range == expected.range)
            #expect(try canonicalJSON(JSONEncoder().encode(actual)) == canonicalJSON(JSONEncoder().encode(expected)))
            #expect(actual.displayText.utf8.elementsEqual(expected.displayText.utf8))
            #expect(actual.exactReadableText.utf8.elementsEqual(expected.exactReadableText.utf8))
            #expect(actual.normalizedDisplayText.utf8.elementsEqual(expected.normalizedDisplayText.utf8))
            #expect(actual.textIndex.containsCJK == expected.textIndex.containsCJK)
            #expect(actual.textIndex.hasSameWordCounts(as: expected.textIndex))
            #expect(actual.scoringDocument.fieldLengths.mapValues { $0.bitPattern } == expected.scoringDocument.fieldLengths.mapValues { $0.bitPattern })
        }
        #expect(sharesUTF8Storage(actual[0].displayText, actual[1].displayText))
        #expect(sharesUTF8Storage(actual[0].displayText, actual[4].displayText))
        for index in 2..<actual.count where index != 4 {
            #expect(!sharesUTF8Storage(actual[0].displayText, actual[index].displayText))
        }
        // A differing payload never replaces the first canonical payload or
        // starts another bucket for the same display key.
        #expect(!sharesUTF8Storage(actual[2].displayText, actual[3].displayText))
        #expect(!sharesUTF8Storage(actual[14].displayText, actual[15].displayText))
        #expect(sharesUTF8Storage(actual[11].displayText, actual[16].displayText))
        #expect(actual[8].scoringDocument.fieldLengths["body"]?.bitPattern == (-0.0).bitPattern)
        #expect(actual[14].textIndex.count(forASCIIWord: "needle") == nil)
        #expect(actual[15].textIndex.count(forASCIIWord: "needle") == 0)
        #expect(Set(actual[17].scoringDocument.fields.keys) == ["body", "annotation"])
        #expect(Set(actual[18].scoringDocument.fields.keys) == ["body"])
        #expect(Set(actual[19].scoringDocument.fields.keys) == ["body"])
        #expect(Set(actual[20].scoringDocument.fields.keys) == ["body", "annotation"])
        #expect(!sharesUTF8Storage(actual[17].displayText, actual[18].displayText))
        #expect(!sharesUTF8Storage(actual[19].displayText, actual[20].displayText))
        let terms = ["needle", "café", "自由"]
        let expectedScores = try RelatedContentBM25F.evaluate(documents: expected.map(\.scoringDocument), terms: terms)
        let actualScores = try RelatedContentBM25F.evaluate(documents: actual.map(\.scoringDocument), terms: terms)
        #expect(actualScores.scores == expectedScores.scores)
        #expect(actualScores.coverage == expectedScores.coverage)
        #expect(actualScores.hasDistinctiveMatch == expectedScores.hasDistinctiveMatch)
    }

    private func sharesUTF8Storage(_ lhs: String, _ rhs: String) -> Bool {
        var lhs = lhs
        var rhs = rhs
        return lhs.withUTF8 { left in
            rhs.withUTF8 { right in left.baseAddress == right.baseAddress && left.count == right.count }
        }
    }

    private func jsonString(_ value: String) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    private func canonicalJSON(_ data: Data) throws -> Data {
        try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: data), options: [.sortedKeys])
    }
}
