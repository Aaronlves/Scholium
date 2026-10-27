import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Bounded Search paragraph matching memo")
struct SearchParagraphMatchingMemoTests {
    private let triptychID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    @Test("Hits preserve matcher fields and ranges while discarding presentation and source maps")
    func matchingProjection() throws {
        let payload = try Payload("\u{FEFF}# 中文😀\r\n\r\nÉmotion [[目标|行动]]{{自由}} alpha.\r\n\r\nGamma delta.\r\n")
        var memo = SearchParagraphMatchingMemo()
        var decodes = 0
        let cold = try load(&memo, payload: payload, generation: generation()) { decodes += 1 }
        let warm = try load(&memo, payload: payload, generation: generation()) { decodes += 1 }
        #expect(cold == warm && decodes == 1)
        #expect(memo.statistics.hits == 1 && memo.statistics.misses == 1)
        #expect(memo.entryCount == 1 && memo.estimatedByteCount <= memo.maximumByteCount)
        #expect(warm.count == payload.projection.paragraphs.count)
        for (actual, original) in zip(warm, payload.projection.paragraphs) {
            #expect(actual.range == original.range)
            #expect(actual.segments.count == original.segments.count)
            for (segment, source) in zip(actual.segments, original.segments) {
                #expect(segment.field == source.field && segment.ordinal == source.ordinal)
                #expect(segment.normalizedText.utf8.elementsEqual(source.normalizedText.utf8))
                #expect(segment.text.isEmpty && segment.sourceRange == nil && segment.offsetMap.isEmpty && segment.relatedRankingText.isEmpty)
            }
        }
        // The complete decoder still independently returns exact display and
        // locators; the memo result is deliberately unsuitable for rendering.
        let full = try Self.decode(payload.data, sourceUTF16Count: payload.source.utf16.count)
        #expect(full == payload.projection.paragraphs)
        #expect(full.flatMap(\.segments).contains { !$0.text.isEmpty && $0.sourceRange != nil && !$0.offsetMap.isEmpty })
    }

    @Test("Current blob changes and corruption under the same fingerprint never reuse an older decode")
    func currentBlobGate() throws {
        let first = try Payload("Alpha beta.\n\nGamma delta.")
        let changed = try Payload("Omega beta.\n\nGamma delta.")
        #expect(first.source.utf16.count == changed.source.utf16.count)
        var memo = SearchParagraphMatchingMemo()
        var decodes = 0
        _ = try load(&memo, payload: first, generation: generation()) { decodes += 1 }
        let replacement = try memo.paragraphs(
            rowID: 1, generation: generation(), fingerprint: first.document.fingerprint,
            sourceUTF16Count: first.source.utf16.count, data: changed.data, protection: .none
        ) { bytes in
            decodes += 1
            return try Self.decode(bytes, sourceUTF16Count: first.source.utf16.count)
        }
        #expect(replacement.flatMap(\.segments).contains { $0.normalizedText.contains("omega") })
        #expect(decodes == 2 && memo.statistics.hits == 0)
        // Both a missing blob and invalid framed JSON must reach the complete
        // decoder even though the row's source fingerprint is unchanged.
        let invalidPayloads: [Data?] = [nil, Data([0x01, 0xFF]), try SearchProjectionBlobCodec.encode(Data("{".utf8))]
        for invalid in invalidPayloads {
            #expect(throws: SearchIndexError.self) {
                try memo.paragraphs(
                    rowID: 1, generation: generation(), fingerprint: first.document.fingerprint,
                    sourceUTF16Count: first.source.utf16.count, data: invalid, protection: .none
                ) { try Self.decode($0, sourceUTF16Count: first.source.utf16.count) }
            }
            #expect(memo.entryCount == 0 && memo.estimatedByteCount == 0)
            _ = try load(&memo, payload: first, generation: generation())
        }
        // A syntactically valid blob with invalid coordinates is also a miss.
        let original = try #require(first.projection.paragraphs.first)
        let corrupt = SearchParagraphProjection(
            range: .init(utf16LowerBound: 0, utf16UpperBound: first.source.utf16.count + 1, line: 1, column: 1, endLine: 3, endColumn: 99),
            segments: original.segments)
        let corruptBytes = try TriptychSearchIndex.encodedParagraphs([corrupt])
        #expect(throws: SearchIndexError.self) {
            try memo.paragraphs(
                rowID: 1, generation: generation(), fingerprint: first.document.fingerprint,
                sourceUTF16Count: first.source.utf16.count, data: corruptBytes, protection: .none
            ) { try Self.decode($0, sourceUTF16Count: first.source.utf16.count) }
        }
        #expect(memo.entryCount == 0)
    }

    @Test("Source bounds, fingerprint and generation are independent hit gates; nil generation never resides")
    func revisionAndGeneration() throws {
        let payload = try Payload("Alpha beta.\n\nGamma delta.")
        let changedFingerprint = DocumentFingerprint(content: "other revision")
        var memo = SearchParagraphMatchingMemo()
        _ = try load(&memo, payload: payload, generation: generation())
        _ = try load(&memo, payload: payload, generation: generation(), fingerprint: changedFingerprint)
        #expect(memo.statistics.misses == 2 && memo.statistics.hits == 0)
        #expect(throws: SearchIndexError.self) {
            try load(
                &memo, payload: payload, generation: generation(), fingerprint: changedFingerprint,
                sourceUTF16Count: payload.source.utf16.count - 1)
        }
        #expect(memo.entryCount == 0)
        _ = try load(&memo, payload: payload, generation: generation())
        _ = try load(&memo, payload: payload, generation: generation(2))
        #expect(memo.statistics.misses == 5 && memo.entryCount == 1)
        let before = memo.statistics.misses
        for _ in 0..<2 { _ = try load(&memo, payload: payload, generation: nil) }
        #expect(memo.statistics.misses == before + 2 && memo.entryCount == 0 && memo.estimatedByteCount == 0)
        _ = try load(&memo, payload: payload, generation: generation())
        memo.retainGeneration(generation(2))
        #expect(memo.entryCount == 0 && memo.estimatedByteCount == 0)
        _ = try load(&memo, payload: payload, generation: generation(2))
        memo.clear()
        #expect(memo.entryCount == 0 && memo.estimatedByteCount == 0)
    }

    @Test("Whole-scan resident protection retains partial-budget hits across complete repeated scans")
    func partialBudgetDoesNotThrash() throws {
        let payload = try Payload("Orchard geology magnetic compass.")
        let generation = generation()
        var probe = SearchParagraphMatchingMemo()
        _ = try load(&probe, payload: payload, generation: generation)
        let cost = probe.estimatedByteCount
        #expect(cost > 0 && probe.maximumByteCount == 16 * 1_024 * 1_024)
        #expect(SearchParagraphMatchingMemo(maximumByteCount: Int.max).maximumByteCount == probe.maximumByteCount)
        var memo = SearchParagraphMatchingMemo(maximumByteCount: 2 * cost)
        let rows = Set(1...5)
        for scan in 0..<3 {
            let protection = memo.scanProtection(generation: generation, rowIDs: rows)
            for row in 1...5 {
                let result = try load(&memo, rowID: row, payload: payload, generation: generation, protection: protection)
                #expect(result.map(\.range) == payload.projection.paragraphs.map(\.range))
                #expect(memo.estimatedByteCount <= memo.maximumByteCount)
            }
            #expect(memo.entryCount == 2 && memo.estimatedByteCount == 2 * cost)
            #expect(memo.statistics.hits == 2 * scan && memo.statistics.misses == 5 + 3 * scan)
            #expect(memo.statistics.evictions == 3 && memo.statistics.protectedAdmissionSkips == 3 * scan)
        }
        let obsoleteProtection = memo.scanProtection(generation: generation, rowIDs: rows)
        _ = try load(&memo, rowID: 9, payload: payload, generation: self.generation(2), protection: obsoleteProtection)
        #expect(memo.entryCount == 1 && memo.estimatedByteCount == cost)

        var undersized = SearchParagraphMatchingMemo(maximumByteCount: cost - 1)
        for _ in 0..<2 { _ = try load(&undersized, payload: payload, generation: generation) }
        #expect(undersized.entryCount == 0 && undersized.estimatedByteCount == 0)
        #expect(undersized.statistics.oversizeSkips == 2 && undersized.statistics.misses == 2)
    }

    @Test("Full and matcher-only paragraphs preserve truth, successful clauses and incomplete-corpus semantics")
    func matcherEquivalence() throws {
        let payload = try Payload("\u{FEFF}# Heading\r\n\r\nAlpha beta.\r\n\r\nGamma delta.\r\n\r\nAlpha [[目标|行动]]{{自由}} 中文.\r\n")
        var memo = SearchParagraphMatchingMemo()
        let matching = try load(&memo, payload: payload, generation: generation())
        for complete in [true, false] {
            let full = stored(payload, paragraphs: payload.projection.paragraphs, complete: complete)
            let compact = stored(payload, paragraphs: matching, complete: complete)
            for query in [
                "paragraph:((alpha AND beta) OR (gamma AND delta))", "paragraph:(alpha NOT beta)",
                "NOT paragraph:(missing)", "paragraph:(missing) OR body:alpha", "paragraph:(中文 AND 自由)",
                "paragraph:(\"alpha beta\")", "NOT paragraph:(alpha AND beta)",
            ] {
                let parsed = SearchQueryParser.parse(query)
                try #require(parsed.diagnostics.isEmpty)
                let ast = try #require(parsed.ast)
                let expected = SearchMatcher.evaluate(ast, document: full, linkMatches: [:])
                let actual = SearchMatcher.evaluate(ast, document: compact, linkMatches: [:])
                #expect(actual.truth == expected.truth && actual.matches == expected.matches)
                #expect(
                    SearchMatcher.paragraphRankingClauses(ast.matched(by: actual), document: compact)
                        == SearchMatcher.paragraphRankingClauses(ast.matched(by: expected), document: full))
            }
        }
    }

    @Test("Cancellation during full decode cannot retain a new entry")
    func cancelledDecode() async throws {
        let payload = try Payload("Alpha beta.")
        let generation = generation()
        let task = Task {
            var memo = SearchParagraphMatchingMemo()
            do {
                _ = try memo.paragraphs(
                    rowID: 1, generation: generation, fingerprint: payload.document.fingerprint,
                    sourceUTF16Count: payload.source.utf16.count, data: payload.data, protection: .none
                ) { try Self.decode($0, sourceUTF16Count: payload.source.utf16.count) }
                _ = try memo.paragraphs(
                    rowID: 1, generation: generation, fingerprint: DocumentFingerprint(content: "replacement revision"),
                    sourceUTF16Count: payload.source.utf16.count, data: payload.data, protection: .none
                ) { bytes in
                    let decoded = try Self.decode(bytes, sourceUTF16Count: payload.source.utf16.count)
                    withUnsafeCurrentTask { $0?.cancel() }
                    return decoded
                }
                Issue.record("Cancelled decoding unexpectedly returned a matching projection")
            } catch is CancellationError {} catch { Issue.record(error) }
            return (memo.entryCount, memo.estimatedByteCount)
        }
        let result = await task.value
        #expect(result.0 == 0 && result.1 == 0)
    }

    private struct Payload: Sendable {
        let source: String
        let document: NoteDocument
        let projection: SearchDocumentProjection
        let data: Data
        init(_ source: String) throws {
            self.source = source
            document = NoteDocument(relativePath: "Paragraphs.md", rawContent: source)
            projection = SearchDocumentProjection(document: document)
            data = try TriptychSearchIndex.encodedParagraphs(projection.paragraphs)
        }
    }

    private func generation(_ sequence: Int = 1) -> SearchGenerationID {
        .init(triptychID: triptychID, sequence: sequence, sourceManifestHash: "paragraph-memo-\(sequence)")
    }

    private func load(
        _ memo: inout SearchParagraphMatchingMemo, rowID: Int = 1, payload: Payload,
        generation: SearchGenerationID?, fingerprint: DocumentFingerprint? = nil,
        sourceUTF16Count: Int? = nil, protection: SearchParagraphMatchingMemo.ScanProtection = .none,
        onDecode: () throws -> Void = {}
    ) throws -> [SearchParagraphProjection] {
        let bound = sourceUTF16Count ?? payload.source.utf16.count
        return try memo.paragraphs(
            rowID: rowID, generation: generation, fingerprint: fingerprint ?? payload.document.fingerprint,
            sourceUTF16Count: bound, data: payload.data, protection: protection
        ) {
            try onDecode()
            return try Self.decode($0, sourceUTF16Count: bound)
        }
    }

    /// The production storage decoder plus the full paragraph/offset checks,
    /// independent of the memo's compacting and hit/admission implementation.
    private static func decode(_ data: Data?, sourceUTF16Count: Int) throws -> [SearchParagraphProjection] {
        let paragraphs = try TriptychSearchIndex.decodedStoredParagraphs(from: data)
        for paragraph in paragraphs {
            guard SearchProjectionValidation.valid(paragraphRange: paragraph.range, sourceUTF16Count: sourceUTF16Count) else {
                throw SearchIndexError.corruptDatabase
            }
            for segment in paragraph.segments {
                guard
                    SearchProjectionValidation.valid(
                        offsets: segment.offsetMap, normalizedUTF16Count: segment.normalizedText.utf16.count,
                        sourceUTF16Bounds: segment.sourceRange.map { (lower: $0.utf16LowerBound, upper: $0.utf16UpperBound) },
                        sourceUTF16Count: sourceUTF16Count)
                else { throw SearchIndexError.corruptDatabase }
            }
        }
        return paragraphs
    }

    private func stored(_ payload: Payload, paragraphs: [SearchParagraphProjection], complete: Bool) -> StoredSearchDocument {
        let projection = payload.projection
        return .init(
            rowID: 1, vaultID: triptychID, vaultName: "Synthetic", vaultRole: .topicKnowledge,
            relativePath: payload.document.relativePath, stableNoteID: nil,
            title: projection.title, normalizedTitle: SearchTextNormalization.normalize(projection.title),
            filenameKey: "paragraphs", pathKey: "paragraphs.md", aliases: projection.aliases,
            calloutRoles: projection.calloutRoles, hasBrokenLink: false, fingerprint: payload.document.fingerprint,
            evidentialLayer: .topicNote, roleOrder: 1, sourceLineStarts: projection.sourceLineStartsUTF16,
            segments: projection.segments, paragraphs: paragraphs, paragraphsAreComplete: complete, properties: [], propertyIssues: [])
    }
}
