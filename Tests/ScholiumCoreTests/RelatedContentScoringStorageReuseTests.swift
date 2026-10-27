import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Related-content independently decoded scorer storage reuse")
struct RelatedContentScoringStorageReuseTests {
    @Test("Equal independently decoded Note scorers share long storage without changing passages or scores")
    func decodedProjectionReuse() throws {
        let prose = Array(repeating: "needle Café 自由 😀", count: 32).joined(separator: " ")
        let source =
            "\u{FEFF}---\r\ntitle: Storage fixture\r\nunknown: 'unchanged'\r\n---\r\n# Heading\r\n\r\n\(prose).\r\n\r\nSecond independent paragraph.\r\n"
        let note = NoteDocument(relativePath: "Cafe\u{301}.md", rawContent: source)
        let original = try RelatedContentSourceProjection(document: note)
        let lexical = RelatedContentLexicalProjection(
            projection: SearchDocumentProjection(document: note), scoringDocument: original.noteScoringDocument)
        let passageBytes = try original.encoded()
        let lexicalBytes = try lexical.encoded()
        let decoded = try RelatedContentSourceProjection.decode(
            passageBytes, checksum: RelatedContentSourceProjection.checksum(passageBytes), sourceUTF16Count: source.utf16.count)
        let background = try RelatedContentLexicalProjection.decode(
            lexicalBytes, checksum: RelatedContentSourceProjection.checksum(lexicalBytes))
        let beforeBody = try #require(decoded.noteScoringDocument.fields["body"])
        let canonicalBody = try #require(background.scoringDocument.fields["body"])
        try #require(beforeBody.utf8.count > 512)
        try #require(beforeBody.utf8.elementsEqual(canonicalBody.utf8))
        try #require(!sharesUTF8Storage(beforeBody, canonicalBody))

        let reused = decoded.sharingNoteScoringStorage(with: background.scoringDocument)
        let reusedBody = try #require(reused.noteScoringDocument.fields["body"])
        #expect(sharesUTF8Storage(reusedBody, canonicalBody))
        #expect(decoded.noteScoringDocument.hasSameContents(as: background.scoringDocument))
        #expect(try canonicalBytes(reused) == canonicalBytes(decoded))
        #expect(reused.estimatedByteCount == decoded.estimatedByteCount)
        #expect(reused.paragraphs.map(\.range) == decoded.paragraphs.map(\.range))
        #expect(sharesParagraphStorage(reused.paragraphs, decoded.paragraphs))
        try #require(reused.paragraphs.count == 2)
        let firstRange = try #require(
            Range(
                NSRange(
                    location: reused.paragraphs[0].range.utf16LowerBound,
                    length: reused.paragraphs[0].range.utf16UpperBound - reused.paragraphs[0].range.utf16LowerBound), in: source))
        #expect(source[firstRange].utf8.elementsEqual((prose + ".").utf8))
        #expect(note.sourceBytes == Data(source.utf8))
        let matcher = RelatedContentTermMatcher(terms: ["needle", "cafe", "自由"])
        let bodyIndex = try #require(reused.noteScoringDocument.textIndexes["body"])
        #expect(matcher.counts(in: reusedBody, index: bodyIndex) == [32, 32, 32])

        let other = try RelatedContentSourceProjection(
            document: NoteDocument(
                relativePath: "Other.md", rawContent: "needle geology.\n\nIndependent context."))
        let terms = ["needle", "cafe", "自由", "geology"]
        let before = try RelatedContentBM25F.evaluate(
            documents: [decoded.noteScoringDocument, other.noteScoringDocument], terms: terms)
        let after = try RelatedContentBM25F.evaluate(
            documents: [reused.noteScoringDocument, other.noteScoringDocument], terms: terms)
        #expect(after.scores == before.scores)
        #expect(after.coverage == before.coverage)
        #expect(after.hasDistinctiveMatch == before.hasDistinctiveMatch)

        let refused = decoded.sharingNoteScoringStorage(with: other.noteScoringDocument)
        let refusedBody = try #require(refused.noteScoringDocument.fields["body"])
        #expect(try canonicalBytes(refused) == canonicalBytes(decoded))
        #expect(sharesParagraphStorage(refused.paragraphs, decoded.paragraphs))
        #expect(sharesUTF8Storage(refusedBody, beforeBody))
    }

    enum Difference: String, CaseIterable, Sendable {
        case fieldSet, fieldText, unicodeBytes, fieldKeyBytes, signedZero, wordCount, nilVersusEmptyWords, cjk
    }

    @Test("A changed scorer component rejects substitution in both directions", arguments: Difference.allCases)
    func exactContentsBoundary(_ difference: Difference) throws {
        let body = Array(repeating: "Café needle 自由", count: 24).joined(separator: " ")
        var left = try scorerWire(body: body)
        let right: String
        switch difference {
        case .fieldSet:
            right = try scorerWire(body: body, annotation: true)
        case .fieldText:
            right = try scorerWire(body: body + " changed")
        case .unicodeBytes:
            right = try scorerWire(body: body.decomposedStringWithCanonicalMapping)
        case .fieldKeyBytes:
            // This exercises the value comparator alone, not projection admission.
            // Canonically equivalent arbitrary keys must not authorize substitution.
            left = try scorerWire(body: body, field: "Café")
            right = try scorerWire(body: body, field: "Cafe\u{301}")
        case .signedZero:
            right = try scorerWire(body: body, length: "-0.0")
        case .wordCount:
            right = try scorerWire(body: body, words: #"{"needle":2}"#)
        case .nilVersusEmptyWords:
            left = try scorerWire(body: body, words: "null")
            right = try scorerWire(body: body, words: "{}")
        case .cjk:
            right = try scorerWire(body: body, cjk: false)
        }
        let lhs = try JSONDecoder().decode(RelatedContentBM25F.Document.self, from: Data(left.utf8))
        let rhs = try JSONDecoder().decode(RelatedContentBM25F.Document.self, from: Data(right.utf8))
        #expect(!lhs.hasSameContents(as: rhs))
        #expect(!rhs.hasSameContents(as: lhs))
        for (original, candidate) in [(lhs, rhs), (rhs, lhs)] {
            let result = original.sharingStorage(with: candidate)
            #expect(try canonicalBytes(result) == canonicalBytes(original))
            #expect(result.fieldLengths.mapValues(\.bitPattern) == original.fieldLengths.mapValues(\.bitPattern))
            let key = try #require(original.fields.keys.first(where: { $0 != "annotation" }))
            let resultText = try #require(result.fields[key])
            let originalText = try #require(original.fields[key])
            #expect(sharesUTF8Storage(resultText, originalText))
        }
        if difference == .signedZero {
            #expect(lhs.fieldLengths["body"]?.bitPattern == 0.0.bitPattern)
            #expect(rhs.fieldLengths["body"]?.bitPattern == (-0.0).bitPattern)
        }
        if difference == .nilVersusEmptyWords {
            #expect(lhs.textIndexes["body"]?.count(forASCIIWord: "needle") == nil)
            #expect(rhs.textIndexes["body"]?.count(forASCIIWord: "needle") == 0)
        }
    }

    @Test("Storage lookup selects the current exact row revision without granting a projection hit")
    func candidateIdentity() throws {
        let first = try lexicalDocument("needle orchard")
        let second = try lexicalDocument("needle geology")
        let generation = generation()
        var memo = RelatedContentBackgroundPreparation()
        #expect(memo.scoringStorage(rowID: 11, fingerprint: first.fingerprint) == nil)
        _ = try admit(&memo, rowID: 11, generation: generation, value: first)
        let statistics = memo.statistics
        let bytes = memo.estimatedByteCount
        let candidate = try #require(memo.scoringStorage(rowID: 11, fingerprint: first.fingerprint))
        #expect(try canonicalBytes(candidate) == canonicalBytes(first.scorer))
        #expect(memo.scoringStorage(rowID: 12, fingerprint: first.fingerprint) == nil)
        #expect(memo.scoringStorage(rowID: 11, fingerprint: second.fingerprint) == nil)
        #expect(memo.statistics == statistics && memo.estimatedByteCount == bytes)
        _ = try admit(&memo, rowID: 11, generation: generation, value: second)
        #expect(memo.entryCount == 1)
        #expect(memo.scoringStorage(rowID: 11, fingerprint: first.fingerprint) == nil)
        let replacement = try #require(memo.scoringStorage(rowID: 11, fingerprint: second.fingerprint))
        #expect(try canonicalBytes(replacement) == canonicalBytes(second.scorer))
    }

    @Test("Immutable storage lookup changes neither statistics, accounting nor row LRU")
    func candidateLookupDoesNotTouchLRU() throws {
        let value = try lexicalDocument("needle orchard")
        let generation = generation()
        var probe = RelatedContentBackgroundPreparation()
        _ = try admit(&probe, rowID: 11, generation: generation, value: value)
        var memo = RelatedContentBackgroundPreparation(maximumByteCount: probe.estimatedByteCount * 2)
        _ = try admit(&memo, rowID: 11, generation: generation, value: value)
        _ = try admit(&memo, rowID: 22, generation: generation, value: value)
        let statistics = memo.statistics
        let bytes = memo.estimatedByteCount
        for _ in 0..<3 {
            let candidate = try #require(memo.scoringStorage(rowID: 11, fingerprint: value.fingerprint))
            #expect(try canonicalBytes(candidate) == canonicalBytes(value.scorer))
        }
        #expect(memo.statistics == statistics && memo.estimatedByteCount == bytes)
        _ = try admit(&memo, rowID: 33, generation: generation, value: value)
        #expect(memo.statistics.evictions == statistics.evictions + 1)
        #expect(memo.scoringStorage(rowID: 11, fingerprint: value.fingerprint) == nil)
        #expect(memo.scoringStorage(rowID: 22, fingerprint: value.fingerprint) != nil)
        #expect(memo.scoringStorage(rowID: 33, fingerprint: value.fingerprint) != nil)
        #expect(memo.entryCount == 2 && memo.estimatedByteCount == bytes)
    }

    private func scorerWire(
        body: String, field: String = "body", length: String = "0.0",
        words: String = #"{"needle":1}"#, cjk: Bool = true, annotation: Bool = false
    ) throws -> String {
        let key = try jsonString(field)
        let extraText = annotation ? #", "annotation":"annotation context""# : ""
        let extraLength = annotation ? #", "annotation":2.0"# : ""
        let extraIndex = annotation ? #", "annotation":{"words":{"annotation":1,"context":1},"containsCJK":false}"# : ""
        return """
            {"fields":{\(key):\(try jsonString(body))\(extraText)},"fieldLengths":{\(key):\(length)\(extraLength)},
            "textIndexes":{\(key):{"words":\(words),"containsCJK":\(cjk)}\(extraIndex)}}
            """
    }

    private struct LexicalPayload {
        let data: Data
        let checksum: String
        let fingerprint: DocumentFingerprint
        let scorer: RelatedContentBM25F.Document
    }

    private func lexicalDocument(_ source: String) throws -> LexicalPayload {
        let note = NoteDocument(relativePath: "Material.md", rawContent: source)
        let search = SearchDocumentProjection(document: note)
        let scorer = RelatedContentBM25F.Document(segments: search.segments)
        let projection = RelatedContentLexicalProjection(projection: search, scoringDocument: scorer)
        let data = try projection.encoded()
        return .init(data: data, checksum: RelatedContentSourceProjection.checksum(data), fingerprint: note.fingerprint, scorer: scorer)
    }

    private func generation() -> SearchGenerationID {
        .init(triptychID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, sequence: 1, sourceManifestHash: "manifest")
    }

    private func admit(
        _ memo: inout RelatedContentBackgroundPreparation, rowID: Int, generation: SearchGenerationID, value: LexicalPayload
    ) throws -> RelatedContentLexicalProjection {
        let protection = memo.scanProtection(generation: generation, rowIDs: [])
        return try memo.projection(
            rowID: rowID, generation: generation, fingerprint: value.fingerprint,
            data: value.data, checksum: value.checksum, protection: protection)
    }

    private func canonicalBytes<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func jsonString(_ value: String) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    private func sharesUTF8Storage(_ lhs: String, _ rhs: String) -> Bool {
        var lhs = lhs
        var rhs = rhs
        return lhs.withUTF8 { left in
            rhs.withUTF8 { right in left.baseAddress == right.baseAddress && left.count == right.count }
        }
    }

    private func sharesParagraphStorage(
        _ lhs: [RelatedContentSourceProjection.Paragraph], _ rhs: [RelatedContentSourceProjection.Paragraph]
    ) -> Bool {
        lhs.withUnsafeBufferPointer { left in
            rhs.withUnsafeBufferPointer { right in left.baseAddress == right.baseAddress && left.count == right.count }
        }
    }
}
