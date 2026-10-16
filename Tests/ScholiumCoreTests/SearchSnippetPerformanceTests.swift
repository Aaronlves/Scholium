import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

/// Direct presentation work over already prepared, exact synthetic source.
/// Timers exclude projection construction, database hydration and assertions.
@Suite("Search snippet construction", .serialized)
struct SearchSnippetPerformanceTests {
    @Test("Dense CJK keeps the first exact source occurrence and all visible highlights")
    func denseCJKPresentation() throws {
        try verifyDenseCJK(repetitions: 1_024)
    }

    @Test("Folded words retain complete Unicode source and snippet graphemes")
    func unicodeSourceLocators() throws {
        for (source, query, exact) in [
            ("\u{FEFF}# Heading\r\n\r\nCafe\u{301} 😀 and another café.\r\n", "body:cafe", "Cafe\u{301}"),
            ("# Heading\n\n👨‍👩‍👧‍👦 \t 哲学\r\n哲学 with e\u{301}.\n", "body:哲学", "哲学"),
            ("# Heading\n\nStraße and STRASSE.\n", "body:strasse", "Straße"),
        ] {
            let fixture = try Fixture(source: source, query: query)
            let hit = fixture.hit()
            let locator = try #require(hit.sourceRange)
            let expected = try #require(source.range(of: exact))
            let expectedRange = NSRange(expected, in: source)
            #expect(locator.utf16LowerBound == expectedRange.location)
            #expect(locator.utf16UpperBound == expectedRange.location + expectedRange.length)
            #expect(fixture.document.sourceBytes == Data(source.utf8))
            let words = try hit.highlights.map { highlight -> String in
                let range = try #require(Range(
                    NSRange(location: highlight.utf16LowerBound, length: highlight.utf16UpperBound - highlight.utf16LowerBound),
                    in: hit.snippet))
                return String(hit.snippet[range])
            }
            #expect(words.first?.utf8.elementsEqual(exact.utf8) == true)
        }
    }

    @Test("Edge tabs, spaces and CRLF preserve display highlights and exact source coordinates")
    func edgeWhitespaceCoordinates() throws {
        let source = "\t  哲学 哲学\r\n \t"
        let fixture = try Fixture(source: source, query: "body:哲学")
        let normalized = SearchTextNormalization.lexicalNormalize(source)
        try #require(normalized == "哲学 哲学")
        let canonicalRanges = SearchTextNormalization.originalUTF16RangesForLexicalNormalization(
            in: source, requestedRanges: [0..<2, 3..<5])
        #expect(canonicalRanges == [3..<5, 6..<8])
        // Exercise an already prepared display segment directly. Its exact
        // normalized-to-source run supplies an independent locator oracle.
        let segment = SearchTextSegment(
            field: .body, ordinal: 0, text: source, normalizedText: normalized,
            sourceRange: .init(utf16LowerBound: 0, utf16UpperBound: source.utf16.count, line: 1, column: 1, endLine: 2, endColumn: 3),
            offsetMap: [.init(
                normalizedUTF16LowerBound: 0, normalizedUTF16UpperBound: 5,
                sourceUTF16LowerBound: 3, sourceUTF16UpperBound: 8, mappingKind: .linear)])
        var document = fixture.stored
        document.segments = [segment]
        let hit = NoteSearchResultBuilder.hit(
            candidate: .init(document: document, identityPriority: 3, lexicalRank: 0),
            ast: fixture.ast, freshness: fixture.freshness, linkMatches: [:])
        #expect(hit.snippet.utf8.elementsEqual("   哲学 哲学   ".utf8))
        #expect(hit.highlights == [
            SearchHighlight(utf16LowerBound: 3, utf16UpperBound: 5),
            SearchHighlight(utf16LowerBound: 6, utf16UpperBound: 8),
        ])
        #expect(hit.sourceRange == SearchSourceRange(
            utf16LowerBound: 3, utf16UpperBound: 5, line: 1, column: 4, endLine: 1, endColumn: 6))
        #expect(fixture.document.sourceBytes == Data(source.utf8))
    }

    @Test("A later multi-predicate cluster outranks earlier isolated occurrences")
    func compactPredicateCluster() throws {
        let padding = String(repeating: "padding ", count: 60)
        let source = "alpha " + padding + "beta " + padding + "alpha beta."
        let fixture = try Fixture(source: source, query: "body:alpha body:beta")
        let hit = fixture.hit()
        let locator = try #require(hit.sourceRange)
        let expected = try #require(source.range(of: "alpha beta."))
        #expect(locator.utf16LowerBound == NSRange(expected, in: source).location)
        #expect(hit.snippet.contains("alpha beta."))
        #expect(hit.highlights.count == 2)
        #expect(hit.matchedFields == [.body])
    }

    @Test("Duplicate predicates retain one first-occurrence locator")
    func duplicatePredicateTie() throws {
        let source = "# 哲学\n\n哲学 repeats 哲学."
        let fixture = try Fixture(source: source, query: "body:哲学 OR body:哲学")
        let hit = fixture.hit()
        let locator = try #require(hit.sourceRange)
        let body = try #require(source.range(of: "哲学 repeats"))
        #expect(locator.utf16LowerBound == NSRange(body, in: source).location)
        #expect(hit.highlights.count == 2)
        #expect(hit.matchedField == .body)
    }

    @Test(
        "Measure dense CJK matching, passage selection, snippet and complete hit separately",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_SEARCH_SNIPPETS"] == "1"),
        arguments: [1_024, 8_192, 32_768])
    func denseCJKMeasurement(repetitions: Int) throws {
        let fixture = try denseCJKFixture(repetitions: repetitions)
        let expected = try verifyDenseCJK(repetitions: repetitions, fixture: fixture)
        let body = try #require(fixture.stored.segments.first { $0.field == .body })
        let warmups = 3
        let samples = 20
        var timings: [String: [Double]] = [:]
        for iteration in 0..<(warmups + samples) {
            let fields = measured { SearchMatcher.matchedFields(ast: fixture.ast, document: fixture.stored) }
            let match = measured { NoteSearchResultBuilder.bestMatch(ast: fixture.ast, document: fixture.stored, preferredField: .body) }
            let snippet = measured {
                NoteSearchResultBuilder.snippet(segment: body, normalizedRange: 0..<2, positiveClauses: fixture.ast.positiveLexicalClauses)
            }
            let hit = measured { fixture.hit() }
            #expect(fields.0 == [.body])
            #expect(match.0?.range == 0..<2 && match.0?.contextRange == 0..<2 && match.0?.coverage == 1)
            #expect(snippet.0.text.utf8.elementsEqual(expected.snippet.utf8))
            #expect(snippet.0.highlights == expected.highlights)
            #expect(hit.0 == expected)
            guard iteration >= warmups else { continue }
            for (stage, elapsed) in [("matched_fields", fields.1), ("best_match", match.1), ("snippet", snippet.1), ("complete_hit", hit.1)] {
                timings[stage, default: []].append(elapsed)
            }
        }
        let summaries = timings.mapValues { values in
            let sorted = values.sorted()
            return ["median": (sorted[9] + sorted[10]) / 2, "p95": sorted[18], "min": sorted[0], "max": sorted[19]]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let report: [String: Any] = [
            "schema": "scholium-search-snippet-diagnostic-v1", "repetitions": repetitions,
            "source_bytes": fixture.document.sourceBytes.count, "source_sha256": fixture.document.fingerprint.sha256,
            "result_sha256": DocumentFingerprint(data: try encoder.encode(expected)).sha256,
            "warmups": warmups, "samples": samples, "stage_ms": summaries,
            "scope": "SwiftPM Debug direct presentation; excludes projection, SQLite hydration, I/O and correctness oracle; no release-gate claim",
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        print("SEARCH_SNIPPET_DIAGNOSTIC \(String(decoding: data, as: UTF8.self))")
    }

    @discardableResult
    private func verifyDenseCJK(repetitions: Int, fixture supplied: Fixture? = nil) throws -> NoteSearchResult {
        let fixture = try supplied ?? denseCJKFixture(repetitions: repetitions)
        let hit = fixture.hit()
        let unit = "哲学概念需要精确分析。"
        let visibleCount = 162
        #expect(hit.snippet.utf8.elementsEqual((String(fixture.document.rawContent.prefix(visibleCount)) + "…").utf8))
        let highlights = stride(from: 0, to: visibleCount, by: unit.utf16.count).compactMap { offset in
            offset + 2 <= visibleCount ? SearchHighlight(utf16LowerBound: offset, utf16UpperBound: offset + 2) : nil
        }
        #expect(hit.highlights == highlights)
        #expect(hit.sourceRange == SearchSourceRange(utf16LowerBound: 0, utf16UpperBound: 2, line: 1, column: 1, endLine: 1, endColumn: 3))
        #expect(hit.matchedField == .body && hit.matchedFields == [.body])
        #expect(hit.fingerprint == fixture.document.fingerprint)
        return hit
    }

    private func denseCJKFixture(repetitions: Int) throws -> Fixture {
        try Fixture(source: String(repeating: "哲学概念需要精确分析。", count: repetitions), query: "body:哲学")
    }

    private func measured<Value>(_ operation: () -> Value) -> (Value, Double) {
        let start = ContinuousClock.now
        let value = operation()
        let duration = start.duration(to: .now).components
        return (value, Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
    }

    private struct Fixture {
        let document: NoteDocument
        let stored: StoredSearchDocument
        let ast: SearchQueryAST
        let freshness: SearchFreshnessToken

        init(source: String, query: String) throws {
            document = NoteDocument(relativePath: "Synthetic.md", rawContent: source)
            let projection = SearchDocumentProjection(document: document)
            let vaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
            ast = try #require(SearchQueryParser.parse(query).ast)
            stored = StoredSearchDocument(
                rowID: 1, vaultID: vaultID, vaultName: "Synthetic", vaultRole: .topicKnowledge,
                relativePath: document.relativePath, stableNoteID: nil, title: projection.title,
                normalizedTitle: SearchTextNormalization.normalize(projection.title), filenameKey: "synthetic", pathKey: "synthetic.md",
                aliases: projection.aliases, calloutRoles: projection.calloutRoles, hasBrokenLink: false,
                fingerprint: document.fingerprint, evidentialLayer: .topicNote, roleOrder: 1,
                sourceLineStarts: projection.sourceLineStartsUTF16, segments: projection.segments,
                paragraphs: projection.paragraphs, paragraphsAreComplete: true, properties: [], propertyIssues: [])
            freshness = .triptych(.init(triptychID: vaultID, sequence: 1, sourceManifestHash: document.fingerprint.sha256))
        }

        func hit() -> NoteSearchResult {
            NoteSearchResultBuilder.hit(candidate: .init(document: stored, identityPriority: 3, lexicalRank: 0), ast: ast, freshness: freshness, linkMatches: [:])
        }
    }
}
