import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Related-content streaming admission parity")
struct RelatedContentAdmissionValidationTests {
    private static let scoring =
        #"{"fields":{"body":"reason reason value"},"fieldLengths":{"body":3},"textIndexes":{"body":{"words":{"reason":2,"value":1},"containsCJK":false}}}"#
    private static let shared = #"{"scoringField":{"_0":"body"}}"#
    private static let range =
        #"{"utf16LowerBound":0,"utf16UpperBound":19,"line":1,"column":1,"endLine":1,"endColumn":20}"#

    // Frozen pre-streaming storage composition: it intentionally materializes
    // complete Stored dictionaries and arrays, independently of Admission.
    private struct RawSource: Decodable {
        let noteScoringDocument: RelatedContentBM25F.Document.Stored
        let paragraphs: [RelatedContentSourceProjection.Paragraph.Stored]

        func validate(sourceCount: Int) throws {
            try noteScoringDocument.validate()
            for paragraph in paragraphs {
                guard SearchProjectionValidation.valid(paragraphRange: paragraph.range, sourceUTF16Count: sourceCount),
                    paragraph.range.utf16UpperBound - paragraph.range.utf16LowerBound
                        <= RelatedContentContract.maximumPassageUTF16Count
                else { throw SearchIndexError.corruptDatabase }
                try paragraph.scoringDocument.validate()
                try paragraph.matchingText.validate(in: paragraph.scoringDocument)
            }
        }
    }

    private struct RawLexical: Decodable {
        struct Segment: Decodable {
            let field: SearchMatchedField
            let material: RelatedContentBM25F.Document.StoredText
        }
        let scoringDocument: RelatedContentBM25F.Document.Stored
        let segments: [Segment]

        func validate() throws {
            try scoringDocument.validate()
            for segment in segments { try segment.material.validate(in: scoringDocument) }
        }
    }

    @Test("All stored enum shapes retain raw, query and admission acceptance")
    func storedTextShapes() {
        for material in [
            Self.shared,
            #"{"scoringField":{"_0":"body","ignored":[null]}}"#,
            #"{"scoringField":{"_0":"body"},"ignored":{"invalid":null}}"#,
            #"{"scoringField":{"_0":"missing"}}"#,
            #"{"scoringField":{"_0":null}}"#,
            #"{"scoringField":{"_0":true}}"#,
            #"{"scoringField":{}}"#,
            #"{"scoringField":[]}"#,
            #"{"scoringField":null}"#,
            #"{"scoringField":{"_0":"body"},"independent":{"text":"word","index":{"containsCJK":false}}}"#,
            #"{"ignored":{"_0":"body"}}"#,
            #"{}"#, #"null"#, #"[]"#,
            #"{"independent":{"text":"自由 e\u0301 😀 a\u200db","index":{"words":null,"containsCJK":true}}}"#,
            #"{"independent":{"text":"word","index":{"containsCJK":false}}}"#,
            #"{"independent":{"text":"","index":{"words":{},"containsCJK":false}}}"#,
            #"{"independent":{"text":false,"index":{"containsCJK":false}}}"#,
            #"{"independent":{"text":"word","index":null}}"#,
            #"{"independent":{"text":"word","index":{"words":{}}}}"#,
            #"{"independent":{"text":"word","index":{"words":{"word":1},"containsCJK":0}}}"#,
            #"{"independent":{"text":"word","index":{"words":{"word":1},"containsCJK":false},"ignored":null}}"#,
        ] {
            parity(source: source(material: material), lexical: lexical(material: material))
        }
    }

    @Test("Lexical fields retain the complete SearchMatchedField domain")
    func lexicalFieldDomain() {
        for field in ["title", "alias", "heading", "summary", "author", "body", "callout", "footnote",
                      "path", "keyword", "publication_date", "broken_link", "link_annotation"] {
            let value = Data(String(decoding: lexical(), as: UTF8.self).replacingOccurrences(
                of: #""field":"body""#, with: #""field":"\#(field)""#).utf8)
            parity(source: source(), lexical: value, expected: true)
        }
    }

    @Test("Discarded display text still has its optional String wire type checked")
    func optionalDisplayType() {
        for display in ["42", "true", "[]", "{}"] {
            let value = Data(String(decoding: source(), as: UTF8.self).replacingOccurrences(
                of: #""displayText":null"#, with: #""displayText":\#(display)"#).utf8)
            parity(source: value, lexical: lexical(), sourceExpected: false)
        }
    }

    @Test("Word admission preserves dictionary decoding, numeric bounds and nil versus empty storage")
    func wordsAndTypes() {
        for words in [
            #"null"#, #"{}"#, #"{"word":1}"#, #"{"WORD_9":4294967295}"#,
            #"{"word":1.0}"#, #"{"word":0}"#, #"{"word":-1}"#,
            #"{"word":4294967296}"#, #"{"word":9223372036854775808}"#,
            #"{"word":1.5}"#, #"{"word":true}"#, #"{"word":"1"}"#,
            #"{"word":null}"#, #"{"":1}"#, #"{"two words":1}"#,
            #"{"café":1}"#, #"{"自由":1}"#, #"{"a\u0000b":1}"#,
            #"{"\u0077ord":2}"#, #"{"word":0,"word":2}"#,
            #"{"word":2,"word":0}"#,
            #"{"word":"bad","word":2}"#, #"{"word":2,"word":"bad"}"#,
            #"{"word":null,"word":2}"#, #"{"word":2,"word":null}"#,
            #"{"word":true,"word":2}"#, #"{"word":2,"word":true}"#,
            #"{"\u0077ord":"bad","word":2}"#, #"{"word":2,"\u0077ord":"bad"}"#,
            #"[]"#, #"true"#, #"1"#,
        ] {
            let index = #"{"words":\#(words),"containsCJK":false}"#
            let material = #"{"independent":{"text":"word","index":\#(index)}}"#
            parity(source: source(material: material), lexical: lexical(material: material))
            let stored = Self.scoring.replacingOccurrences(
                of: #"{"words":{"reason":2,"value":1},"containsCJK":false}"#, with: index)
            parity(source: source(note: stored), lexical: lexical(scoring: stored))
            parity(source: source(scoring: stored), lexical: lexical(scoring: stored))
        }
    }

    @Test("Scoring-map shape and exact field value types retain acceptance")
    func scoringShapes() {
        for (before, after) in [
            (#""body""#, #""path""#),
            (#""fields":{"body":"reason reason value"}"#, #""fields":{"body":true}"#),
            (#""fields":{"body":"reason reason value"}"#, #""fields":null"#),
            (#""fieldLengths":{"body":3}"#, #""fieldLengths":{"body":-1}"#),
            (#""fieldLengths":{"body":3}"#, #""fieldLengths":{"body":true}"#),
            (#""fieldLengths":{"body":3}"#, #""fieldLengths":{"body":"3"}"#),
            (#""fieldLengths":{"body":3}"#, #""fieldLengths":{"body":1e309}"#),
            (#""fieldLengths":{"body":3}"#, #""fieldLengths":{"title":3}"#),
            (#""fieldLengths":{"body":3}"#, #""fieldLengths":{}"#),
            (#""textIndexes":{"body":"#, #""textIndexes":{"title":"#),
            (#""containsCJK":false"#, #""containsCJK":null"#),
            (#""containsCJK":false"#, #""containsCJK":"false""#),
        ] {
            let value = Self.scoring.replacingOccurrences(of: before, with: after)
            #expect(value != Self.scoring)
            parity(source: source(note: value), lexical: lexical(scoring: value), expected: false)
            parity(source: source(scoring: value), lexical: lexical(scoring: value), expected: false)
        }
    }

    @Test("Every streamed entry is validated, including a damaged final passage or segment")
    func corruptLastEntry() {
        let paragraphs = Array(repeating: paragraph(), count: 64)
        let segments = Array(repeating: segment(), count: 64)
        for material in [#"{"scoringField":{"_0":"missing"}}"#,
                         #"{"independent":{"text":"word","index":{"words":{"word":0},"containsCJK":false}}}"#] {
            let source = Data(#"{"noteScoringDocument":\#(Self.scoring),"paragraphs":[\#((paragraphs + [paragraph(material: material)]).joined(separator: ","))]}"#.utf8)
            let lexical = Data(#"{"scoringDocument":\#(Self.scoring),"segments":[\#((segments + [segment(material: material)]).joined(separator: ","))]}"#.utf8)
            parity(source: source, lexical: lexical, expected: false)
        }
        parity(source: source(), lexical: lexical(), expected: true)
    }

    @Test("Endpoint reduction retains inclusive source limits and empty-collection behavior")
    func sourceBoundsAndEmptyCollections() {
        let valid = source()
        for count in [Int.min, -1, 0, 18, 19, 20, Int.max] {
            parity(source: valid, lexical: lexical(), sourceCount: count,
                   sourceExpected: count >= 19)
        }
        let empty = #"{"fields":{},"fieldLengths":{},"textIndexes":{}}"#
        for count in [Int.min, -1, 0, 19, Int.max] {
            parity(source: Data(#"{"noteScoringDocument":\#(empty),"paragraphs":[]}"#.utf8),
                   lexical: Data(#"{"scoringDocument":\#(empty),"segments":[]}"#.utf8),
                   sourceCount: count, expected: true)
        }
        for upper in [32_000, 32_001] {
            let range = Self.range.replacingOccurrences(of: #""utf16UpperBound":19"#, with: #""utf16UpperBound":\#(upper)"#)
            parity(source: source(range: range), lexical: lexical(), sourceCount: upper,
                   sourceExpected: upper == 32_000)
        }
        let outside = Self.range.replacingOccurrences(of: #""utf16UpperBound":19"#, with: #""utf16UpperBound":20"#)
        for paragraphs in [[paragraph(range: outside), paragraph()], [paragraph(), paragraph(range: outside)]] {
            let value = Data(#"{"noteScoringDocument":\#(Self.scoring),"paragraphs":[\#(paragraphs.joined(separator: ","))]}"#.utf8)
            parity(source: value, lexical: lexical(), sourceCount: 19, sourceExpected: false)
        }
        let extremeRange = #"{"utf16LowerBound":\#(Int.max - 19),"utf16UpperBound":\#(Int.max),"line":1,"column":1,"endLine":1,"endColumn":20}"#
        parity(source: source(range: extremeRange), lexical: lexical(), sourceCount: Int.max, expected: true)
    }

    private func paragraph(material: String = Self.shared, range: String = Self.range,
                           scoring: String = Self.scoring) -> String {
        #"{"range":\#(range),"displayText":null,"matchingText":\#(material),"scoringDocument":\#(scoring)}"#
    }

    private func segment(material: String = Self.shared) -> String {
        #"{"field":"body","material":\#(material)}"#
    }

    private func source(material: String = Self.shared, range: String = Self.range,
                        scoring: String = Self.scoring, note: String = Self.scoring) -> Data {
        Data(#"{"noteScoringDocument":\#(note),"paragraphs":[\#(paragraph(material: material, range: range, scoring: scoring))]}"#.utf8)
    }

    private func lexical(material: String = Self.shared, scoring: String = Self.scoring) -> Data {
        Data(#"{"scoringDocument":\#(scoring),"segments":[\#(segment(material: material))]}"#.utf8)
    }

    private func accepts(_ operation: () throws -> Void) -> Bool {
        do { try operation(); return true } catch { return false }
    }

    private func parity(source: Data, lexical: Data, sourceCount: Int = 19,
                        expected: Bool? = nil, sourceExpected: Bool? = nil) {
        let rawSource = accepts { try JSONDecoder().decode(RawSource.self, from: source).validate(sourceCount: sourceCount) }
        let rawLexical = accepts { try JSONDecoder().decode(RawLexical.self, from: lexical).validate() }
        let admittedSource = accepts {
            try RelatedContentSourceProjection.validate(source, checksum: RelatedContentSourceProjection.checksum(source), sourceUTF16Count: sourceCount)
        }
        let admittedLexical = accepts {
            try RelatedContentLexicalProjection.validate(lexical, checksum: RelatedContentSourceProjection.checksum(lexical))
        }
        let queriedSource = accepts {
            _ = try RelatedContentSourceProjection.decode(source, checksum: RelatedContentSourceProjection.checksum(source), sourceUTF16Count: sourceCount)
        }
        let queriedLexical = accepts {
            _ = try RelatedContentLexicalProjection.decode(lexical, checksum: RelatedContentSourceProjection.checksum(lexical))
        }
        #expect(admittedSource == rawSource && queriedSource == rawSource)
        #expect(admittedLexical == rawLexical && queriedLexical == rawLexical)
        if let expected { #expect(admittedSource == expected && admittedLexical == expected) }
        if let sourceExpected { #expect(admittedSource == sourceExpected) }
    }
}
