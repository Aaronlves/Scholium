import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Persisted related-content validation")
struct RelatedContentProjectionValidationTests {
    // Hand-written storage fixtures deliberately avoid the production encoder.
    private static let scoring = #"{"fields":{"body":"reason reason value"},"fieldLengths":{"body":3},"textIndexes":{"body":{"words":{"reason":2,"value":1},"containsCJK":false}}}"#
    private static let shared = #"{"scoringField":{"_0":"body"}}"#
    private static let range = #"{"utf16LowerBound":0,"utf16UpperBound":19,"line":1,"column":1,"endLine":1,"endColumn":20}"#

    @Test("Literal shared storage validates and retains independently expected matching counts")
    func sharedStorage() throws {
        let source = sourcePayload()
        let lexical = lexicalPayload()
        try validateSource(source)
        try validateLexical(lexical)
        let paragraph = try #require(decodeSource(source).paragraphs.first)
        let segment = try #require(decodeLexical(lexical).segments.first)
        #expect(paragraph.displayText == "reason reason value")
        #expect(paragraph.exactReadableText == "reason reason value")
        #expect(paragraph.range.utf16LowerBound == 0 && paragraph.range.utf16UpperBound == 19)
        #expect(segment.field == .body)
        let matcher = RelatedContentTermMatcher(terms: ["reason", "value", "missing"])
        #expect(matcher.counts(in: paragraph.normalizedDisplayText, index: paragraph.textIndex) == [2, 1, 0])
        #expect(matcher.counts(in: segment.text, index: segment.index) == [2, 1, 0])
    }

    @Test("Independent Unicode material keeps fallback matching and authored readable text")
    func independentUnicodeStorage() throws {
        let material = #"{"independent":{"text":"cafe 自由 😀 a\u200db agency","index":{"words":null,"containsCJK":true}}}"#
        let display = #""Cafe\u0301 自由 😀 a\u200db agency""#
        let authored = "Cafe\u{301} 自由 😀 a\u{200D}b agency"
        let range = #"{"utf16LowerBound":0,"utf16UpperBound":\#(authored.utf16.count),"line":1,"column":1,"endLine":1,"endColumn":\#(authored.utf16.count + 1)}"#
        let source = sourcePayload(material: material, range: range, display: display)
        let lexical = lexicalPayload(material: material)
        try validateSource(source, sourceCount: authored.utf16.count)
        try validateLexical(lexical)
        let paragraph = try #require(decodeSource(source, sourceCount: authored.utf16.count).paragraphs.first)
        let segment = try #require(decodeLexical(lexical).segments.first)
        #expect(paragraph.displayText.utf8.elementsEqual(authored.utf8))
        #expect(paragraph.exactReadableText.utf8.elementsEqual("Café 自由 😀 a\u{200D}b agency".utf8))
        #expect(!paragraph.textIndex.hasPreparedWords && !segment.index.hasPreparedWords)
        let matcher = RelatedContentTermMatcher(terms: ["CAFÉ", "自由", "agency", "missing"])
        #expect(matcher.counts(in: paragraph.normalizedDisplayText, index: paragraph.textIndex) == [1, 1, 1, 0])
        #expect(matcher.counts(in: segment.text, index: segment.index) == [1, 1, 1, 0])
    }

    @Test("Empty, omitted, and maximum word counts retain existing acceptance", arguments: [
        (#"{"words":{},"containsCJK":false}"#, Optional(0)),
        (#"{"containsCJK":false}"#, nil),
        (#"{"words":{"word":4294967295},"containsCJK":false}"#, Optional(4_294_967_295)),
    ])
    func acceptedWordRepresentations(index: String, expectedCount: Int?) throws {
        let material = #"{"independent":{"text":"word","index":\#(index)}}"#
        let source = sourcePayload(material: material)
        let lexical = lexicalPayload(material: material)
        try validateSource(source)
        try validateLexical(lexical)
        let paragraph = try #require(decodeSource(source).paragraphs.first)
        let segment = try #require(decodeLexical(lexical).segments.first)
        #expect(paragraph.textIndex.count(forASCIIWord: "word") == expectedCount)
        #expect(segment.index.count(forASCIIWord: "word") == expectedCount)
    }

    @Test("Every scoring location rejects damaged maps and word records despite a matching checksum", arguments: [
        ("zero count", #""reason":2"#, #""reason":0"#),
        ("negative count", #""reason":2"#, #""reason":-1"#),
        ("count overflow", #""reason":2"#, #""reason":4294967296"#),
        ("fractional count", #""reason":2"#, #""reason":1.5"#),
        ("string count", #""reason":2"#, #""reason":"2""#),
        ("empty key", #""reason":2"#, #""":2"#),
        ("multiword key", #""reason":2"#, #""two words":2"#),
        ("non-ASCII key", #""reason":2"#, #""café":2"#),
        ("wrong word container", #""words":{"reason":2,"value":1}"#, #""words":[]"#),
        ("wrong CJK type", #""containsCJK":false"#, #""containsCJK":"false""#),
        ("unknown ranking field", #""body""#, #""path""#),
        ("missing length", #""fieldLengths":{"body":3}"#, #""fieldLengths":{}"#),
        ("extra length", #""fieldLengths":{"body":3}"#, #""fieldLengths":{"body":3,"title":1}"#),
        ("negative length", #""fieldLengths":{"body":3}"#, #""fieldLengths":{"body":-1}"#),
        ("wrong length type", #""fieldLengths":{"body":3}"#, #""fieldLengths":{"body":"3"}"#),
        ("missing field text", #""fields":{"body":"reason reason value"}"#, #""fields":{}"#),
        ("wrong field text type", #""fields":{"body":"reason reason value"}"#, #""fields":{"body":3}"#),
        ("missing index", #""textIndexes":{"body":{"words":{"reason":2,"value":1},"containsCJK":false}}"#, #""textIndexes":{}"#),
        ("mismatched index key", #""textIndexes":{"body":"#, #""textIndexes":{"title":"#),
    ])
    func damagedScoringMaps(name: String, original: String, replacement: String) {
        let damaged = Self.scoring.replacingOccurrences(of: original, with: replacement)
        #expect(damaged != Self.scoring, "Fixture mutation: \(name)")
        expectSourceCorrupt(sourcePayload(noteScoring: damaged))
        expectSourceCorrupt(sourcePayload(paragraphScoring: damaged))
        expectLexicalCorrupt(lexicalPayload(scoring: damaged))
    }

    @Test("Unresolvable references and malformed independent material are corrupt", arguments: [
        #"{"scoringField":{"_0":"title"}}"#,
        #"{"scoringField":{"_0":42}}"#,
        #"{"scoringField":{}}"#,
        #"{"independent":{"text":"reason","index":{"words":{"reason":0},"containsCJK":false}}}"#,
        #"{"independent":{"text":"reason","index":{"words":{"two words":1},"containsCJK":false}}}"#,
        #"{"independent":{"text":"reason"}}"#,
        #"{"independent":{"text":42,"index":{"containsCJK":false}}}"#,
        #"{"unknown":{"text":"reason"}}"#,
    ])
    func damagedStoredMaterial(material: String) {
        expectSourceCorrupt(sourcePayload(material: material))
        expectLexicalCorrupt(lexicalPayload(material: material))
    }

    @Test("Source bounds and paragraph coordinates are checked without weakening decode", arguments: [
        ("negative start", #""utf16LowerBound":0"#, #""utf16LowerBound":-1"#),
        ("empty passage", #""utf16UpperBound":19"#, #""utf16UpperBound":0"#),
        ("reversed passage", #""utf16UpperBound":19"#, #""utf16UpperBound":-1"#),
        ("outside source", #""utf16UpperBound":19"#, #""utf16UpperBound":20"#),
        ("invalid line", #""line":1"#, #""line":0"#),
        ("backward end line", #""endLine":1"#, #""endLine":0"#),
        ("invalid column", #""column":1"#, #""column":0"#),
        ("invalid end column", #""endColumn":20"#, #""endColumn":0"#),
        ("wrong coordinate type", #""utf16UpperBound":19"#, #""utf16UpperBound":"19""#),
    ])
    func damagedSourceRanges(name: String, original: String, replacement: String) {
        let range = Self.range.replacingOccurrences(of: original, with: replacement)
        #expect(range != Self.range, "Fixture mutation: \(name)")
        expectSourceCorrupt(sourcePayload(range: range))
    }

    @Test("Maximum passage length is inclusive and overlong source spans are rejected")
    func passageLengthBoundary() throws {
        let atLimit = Self.range.replacingOccurrences(of: #""utf16UpperBound":19"#, with: #""utf16UpperBound":32000"#)
        let tooLong = Self.range.replacingOccurrences(of: #""utf16UpperBound":19"#, with: #""utf16UpperBound":32001"#)
        let source = sourcePayload(range: atLimit)
        try validateSource(source, sourceCount: 32_001)
        #expect(try decodeSource(source, sourceCount: 32_001).paragraphs.first?.range.utf16UpperBound == 32_000)
        expectSourceCorrupt(sourcePayload(range: tooLong), sourceCount: 32_001)
        expectSourceCorrupt(sourcePayload(), sourceCount: -1)
    }

    @Test("Projection-level field and collection types remain mandatory")
    func damagedProjectionTypes() {
        expectSourceCorrupt(sourcePayload(display: "42"))
        expectSourceCorrupt(sourcePayload(range: "null"))
        expectSourceCorrupt(Data(#"{"noteScoringDocument":\#(Self.scoring),"paragraphs":{}}"#.utf8))
        expectLexicalCorrupt(lexicalPayload(field: "unknown"))
        expectLexicalCorrupt(Data(#"{"scoringDocument":\#(Self.scoring),"segments":{}}"#.utf8))
        expectSourceCorrupt(Data("{".utf8))
        expectLexicalCorrupt(Data("{".utf8))
    }

    @Test("Absent bytes or checksums and mismatched checksums cannot validate")
    func checksumBoundary() {
        let source = sourcePayload()
        let lexical = lexicalPayload()
        for checksum: String? in [nil, "incorrect"] {
            expectSourceCorrupt(source, checksum: checksum)
            expectLexicalCorrupt(lexical, checksum: checksum)
        }
        expectSourceCorrupt(nil)
        expectLexicalCorrupt(nil)
    }

    private func sourcePayload(
        noteScoring: String = Self.scoring, paragraphScoring: String = Self.scoring,
        material: String = Self.shared, range: String = Self.range, display: String = "null"
    ) -> Data {
        Data(#"{"noteScoringDocument":\#(noteScoring),"paragraphs":[{"range":\#(range),"displayText":\#(display),"matchingText":\#(material),"scoringDocument":\#(paragraphScoring)}]}"#.utf8)
    }

    private func lexicalPayload(
        scoring: String = Self.scoring, material: String = Self.shared, field: String = "body"
    ) -> Data {
        Data(#"{"scoringDocument":\#(scoring),"segments":[{"field":"\#(field)","material":\#(material)}]}"#.utf8)
    }

    private func validateSource(_ data: Data, sourceCount: Int = 19) throws {
        try RelatedContentSourceProjection.validate(
            data, checksum: RelatedContentSourceProjection.checksum(data), sourceUTF16Count: sourceCount)
    }

    private func validateLexical(_ data: Data) throws {
        try RelatedContentLexicalProjection.validate(data, checksum: RelatedContentSourceProjection.checksum(data))
    }

    private func decodeSource(_ data: Data, sourceCount: Int = 19) throws -> RelatedContentSourceProjection {
        try RelatedContentSourceProjection.decode(
            data, checksum: RelatedContentSourceProjection.checksum(data), sourceUTF16Count: sourceCount)
    }

    private func decodeLexical(_ data: Data) throws -> RelatedContentLexicalProjection {
        try RelatedContentLexicalProjection.decode(data, checksum: RelatedContentSourceProjection.checksum(data))
    }

    private func expectSourceCorrupt(_ data: Data?, sourceCount: Int = 19) {
        expectSourceCorrupt(data, checksum: data.map(RelatedContentSourceProjection.checksum), sourceCount: sourceCount)
    }

    private func expectSourceCorrupt(_ data: Data?, checksum: String?, sourceCount: Int = 19) {
        #expect {
            try RelatedContentSourceProjection.validate(data, checksum: checksum, sourceUTF16Count: sourceCount)
        } throws: { Self.isCorrupt($0) }
        #expect {
            _ = try RelatedContentSourceProjection.decode(data, checksum: checksum, sourceUTF16Count: sourceCount)
        } throws: { Self.isCorrupt($0) }
    }

    private func expectLexicalCorrupt(_ data: Data?) {
        expectLexicalCorrupt(data, checksum: data.map(RelatedContentSourceProjection.checksum))
    }

    private func expectLexicalCorrupt(_ data: Data?, checksum: String?) {
        #expect {
            try RelatedContentLexicalProjection.validate(data, checksum: checksum)
        } throws: { Self.isCorrupt($0) }
        #expect {
            _ = try RelatedContentLexicalProjection.decode(data, checksum: checksum)
        } throws: { Self.isCorrupt($0) }
    }

    private static func isCorrupt(_ error: any Error) -> Bool {
        if case SearchIndexError.corruptDatabase = error { return true }
        return false
    }
}
