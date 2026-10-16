import Darwin
import Dispatch
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
                let range = try #require(
                    Range(
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
            offsetMap: [
                .init(
                    normalizedUTF16LowerBound: 0, normalizedUTF16UpperBound: 5,
                    sourceUTF16LowerBound: 3, sourceUTF16UpperBound: 8, mappingKind: .linear)
            ])
        var document = fixture.stored
        document.segments = [segment]
        let hit = NoteSearchResultBuilder.hit(
            candidate: .init(document: document, identityPriority: 3, lexicalRank: 0),
            ast: fixture.ast, freshness: fixture.freshness, linkMatches: [:])
        #expect(hit.snippet.utf8.elementsEqual("   哲学 哲学   ".utf8))
        #expect(
            hit.highlights == [
                SearchHighlight(utf16LowerBound: 3, utf16UpperBound: 5),
                SearchHighlight(utf16LowerBound: 6, utf16UpperBound: 8),
            ])
        #expect(
            hit.sourceRange
                == SearchSourceRange(
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

    @Test("Winning display maps preserve all highlights for distinct selection and snippet range batches")
    func hitLocalMappingParity() throws {
        let padding = String(repeating: "padding ", count: 60)
        for (source, query) in [
            (String(repeating: "哲学概念需要精确分析。", count: 128), "body:哲学"),
            (String(repeating: "Agency 自由 café\r\n", count: 20), "body:自由"),
            ("\t Cafe\u{301} 😀 café 哲学\r\n哲学\t", "body:cafe body:哲学"),
            ("alpha " + padding + "beta " + padding + "alpha beta.", "body:alpha body:beta"),
            ("# 哲学\n\n哲学 repeats 哲学.", "body:哲学 OR body:哲学"),
            ("# Heading\n\n自由 evidence and 自由 evidence.", "body:\"自由 evidence\""),
            ("# Heading\n\nalpha beta.\n\nOther alpha beta.", "paragraph:(alpha AND beta)"),
            ("# Heading\n\n[[Target|Visible]]{{自由 evidence}} café.", "自由"),
        ] {
            let fixture = try Fixture(source: source, query: query)
            let paragraphLead = SearchMatcher.paragraphWitnesses(fixture.ast, document: fixture.stored).first
            let ast = fixture.ast.positiveLexicalClauses.isEmpty ? (paragraphLead?.ast ?? fixture.ast) : fixture.ast
            let document = fixture.ast.positiveLexicalClauses.isEmpty ? (paragraphLead?.document ?? fixture.stored) : fixture.stored
            let matched = try #require(NoteSearchResultBuilder.bestMatch(ast: ast, document: document, preferredField: .body))
            let fresh = NoteSearchResultBuilder.snippet(
                segment: matched.segment, normalizedRange: matched.contextRange, positiveClauses: ast.positiveLexicalClauses)
            let reused = NoteSearchResultBuilder.snippet(
                segment: matched.segment, normalizedRange: matched.contextRange, positiveClauses: ast.positiveLexicalClauses,
                preparedDisplayRangeMapping: matched.preparedDisplayRangeMapping)
            #expect(reused.text.utf8.elementsEqual(fresh.text.utf8))
            #expect(reused.highlights == fresh.highlights)
            #expect(fixture.document.sourceBytes == Data(source.utf8))
        }
    }

    @Test("A map for canonically equal byte-distinct text or different normalized inputs is rejected")
    func mappingInputIsolation() throws {
        let source = "Cafe\u{301} 自由 and 自由."
        let fixture = try Fixture(source: source, query: "body:自由")
        // Bind authored NFD display bytes directly rather than depending on
        // the Markdown parser's presentation choices in this isolation test.
        let body = SearchTextSegment(
            field: .body, ordinal: 0, text: source,
            normalizedText: SearchTextNormalization.lexicalNormalize(source),
            sourceRange: nil, offsetMap: [])
        let canonicalOther = body.text.precomposedStringWithCanonicalMapping
        try #require(canonicalOther == body.text && !canonicalOther.utf8.elementsEqual(body.text.utf8))
        let mappings = [
            NoteSearchResultBuilder.PreparedDisplayRangeMapping(in: canonicalOther, normalizedText: body.normalizedText),
            NoteSearchResultBuilder.PreparedDisplayRangeMapping(in: body.text, normalizedText: body.normalizedText + "different"),
        ]
        let target = try #require(SearchMatcher.occurrences(of: .term("自由"), in: body.normalizedText).first)
        let fresh = NoteSearchResultBuilder.snippet(
            segment: body, normalizedRange: target, positiveClauses: fixture.ast.positiveLexicalClauses)
        for mapping in mappings {
            #expect(!mapping.matches(in: body.text, normalizedText: body.normalizedText))
            let result = NoteSearchResultBuilder.snippet(
                segment: body, normalizedRange: target, positiveClauses: fixture.ast.positiveLexicalClauses,
                preparedDisplayRangeMapping: mapping)
            #expect(result.text.utf8.elementsEqual(fresh.text.utf8))
            #expect(result.highlights == fresh.highlights)
        }
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
            "warmups": warmups, "samples": samples, "stage_ms": summaries, "samples_ms": timings,
            "fixture": "dense_cjk", "build_configuration": diagnosticBuildConfiguration,
            "complete_result": try JSONSerialization.jsonObject(with: encoder.encode(expected)),
            "scope": directPresentationScope,
        ]
        try emitSnippetDiagnostic(report, prefix: "SEARCH_SNIPPET_DIAGNOSTIC")
    }

    @Test(
        "Measure complete Search hits over exact mixed folded and CJK long-note display text",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_SEARCH_SNIPPETS"] == "1"),
        arguments: [1_024, 8_192, 32_768])
    func mixedFoldedCJKMeasurement(repetitions: Int) throws {
        let fixture = try mixedFoldedCJKFixture(repetitions: repetitions)
        let expected = try verifyMixedFoldedCJK(fixture)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let oracle = try encoder.encode(expected)
        let warmups = 3
        let samples = 20
        var timings: [Double] = []
        for iteration in 0..<(warmups + samples) {
            let hit = measured { fixture.hit() }
            // Every field and every String's encoded bytes are checked outside
            // the timer. The explicit locator/highlight oracle above is separate.
            try #require(try encoder.encode(hit.0) == oracle)
            guard iteration >= warmups else { continue }
            timings.append(hit.1)
        }
        try #require(timings.count == samples)
        let sorted = timings.sorted()
        let report: [String: Any] = [
            "schema": "scholium-search-snippet-mixed-diagnostic-v1",
            "fixture": "mixed_uppercase_nfd_accent_cjk_emoji", "repetitions": repetitions,
            "build_configuration": diagnosticBuildConfiguration,
            "source_bytes": fixture.document.sourceBytes.count,
            "source_sha256": fixture.document.fingerprint.sha256,
            "query": "body:自由", "warmups": warmups, "samples": samples,
            "stage_ms": [
                "complete_hit": [
                    "median": (sorted[9] + sorted[10]) / 2, "p95": sorted[18], "min": sorted[0], "max": sorted[19],
                ]
            ],
            "samples_ms": ["complete_hit": timings],
            "result_sha256": DocumentFingerprint(data: oracle).sha256,
            "complete_result": try JSONSerialization.jsonObject(with: oracle),
            "all_timed_outputs_byte_equal_oracle": true,
            "canonical_fallback_forced_by_display_bytes": true,
            "allocation_sampling_during_timings": false,
            "oracle":
                "Authored NFD source remains byte exact; projected display adds one unmapped trailing LF. Authored first source range 12..<14 at line 1 / column 13; 174-Character exact source prefix plus ellipsis; ten complete visible CJK highlights at explicit UTF-16 offsets. Full sorted-key encoded NoteSearchResult equality for all 23 calls, including warmups.",
            "scope": directPresentationScope,
        ]
        try emitSnippetDiagnostic(report, prefix: "SEARCH_SNIPPET_MIXED_DIAGNOSTIC")
    }

    @Test(
        "Separately sample live malloc allocations during mixed long-note complete Search hits",
        .enabled(
            if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_SEARCH_SNIPPETS"] == "1"
                && ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_SEARCH_SNIPPET_ALLOCATIONS"] == "1"),
        arguments: [32_768])
    func mixedFoldedCJKAllocationMeasurement(repetitions: Int) throws {
        let fixture = try mixedFoldedCJKFixture(repetitions: repetitions)
        let expected = try verifyMixedFoldedCJK(fixture)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let oracle = try encoder.encode(expected)
        var observations: [[String: Int]] = []
        for sample in 0..<3 {
            let sampler = SnippetAllocationSampler()
            let queue = DispatchQueue(label: "scholium.search.snippet.allocation")
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(1), leeway: .microseconds(100))
            timer.setEventHandler { sampler.sample() }
            timer.resume()
            let hit = fixture.hit()
            var observation = sampler.stop()
            timer.cancel()
            queue.sync {}
            try #require(try encoder.encode(hit) == oracle)
            try #require((observation["timer_sample_count"] ?? 0) > 0)
            observation["sample"] = sample
            observations.append(observation)
        }
        let report: [String: Any] = [
            "schema": "scholium-search-snippet-allocator-diagnostic-v1",
            "fixture": "mixed_uppercase_nfd_accent_cjk_emoji", "repetitions": repetitions,
            "build_configuration": diagnosticBuildConfiguration,
            "source_bytes": fixture.document.sourceBytes.count,
            "source_sha256": fixture.document.fingerprint.sha256,
            "result_sha256": DocumentFingerprint(data: oracle).sha256,
            "complete_result": try JSONSerialization.jsonObject(with: oracle),
            "samples": observations, "sampling_interval_ms": 1,
            "allocation_api": "malloc_zone_statistics(nil).size_in_use",
            "scope":
                "Separate observer-enabled process malloc sampling during one complete Search hit; source projection, fixture/oracle setup and assertions excluded. Observed sampled high-water only, not exact peak, RSS, unique Search allocations, retained growth or native UI latency. No latency values are collected in this pass.",
        ]
        try emitSnippetDiagnostic(report, prefix: "SEARCH_SNIPPET_ALLOCATION_DIAGNOSTIC")
    }

    @Test(
        "Attribute the largest mixed Search hit to scanning, checked mapping and presentation",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_MIXED_SEARCH_STAGES"] == "1"),
        .timeLimit(.minutes(2)))
    func mixedSearchStageAttribution() throws {
        let repetitions = 32_768
        let fixture = try mixedFoldedCJKFixture(repetitions: repetitions)
        let expected = try verifyMixedFoldedCJK(fixture)
        let body = try #require(fixture.stored.segments.first { $0.field == .body })
        let normalizedUnit = "agency cafe 自由😀 evidence cafe 自由. "
        try #require(normalizedUnit.utf16.count == 35)
        // Two authored occurrences per unit. NFD source has one extra UTF16
        // unit before the second occurrence; the visible collector adds one LF.
        let normalizedRanges: [Range<Int>] = (0..<repetitions).flatMap { unit in
            [12, 31].map { offset in (unit * 35 + offset)..<(unit * 35 + offset + 2) }
        }
        let displayRanges: [Range<Int>?] = (0..<repetitions).flatMap { unit in
            [12, 32].map { offset in
                Optional((unit * 36 + offset)..<(unit * 36 + offset + 2))
            }
        }
        try #require(normalizedRanges.count == repetitions * 2)
        let first = try #require(normalizedRanges.first)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let fullResultBytes = try encoder.encode(expected)
        let warmups = 1
        let samples = 3
        var timings: [String: [Double]] = [:]
        for iteration in 0..<(warmups + samples) {
            let occurrences = measured {
                SearchMatcher.occurrences(of: .term("自由"), in: body.normalizedText)
            }
            let mapping = measured {
                SearchTextNormalization.prepareOriginalUTF16RangesForLexicalNormalization(in: body.text)
            }
            let batch = measured {
                mapping.0.originalUTF16Ranges(for: normalizedRanges)
            }
            let match = measured {
                NoteSearchResultBuilder.bestMatch(ast: fixture.ast, document: fixture.stored, preferredField: .body)
            }
            let freshSnippet = measured {
                NoteSearchResultBuilder.snippet(
                    segment: body, normalizedRange: first,
                    positiveClauses: fixture.ast.positiveLexicalClauses)
            }
            let hit = measured { fixture.hit() }
            // All manual/equality checks, complete encoding and hashes remain
            // outside timers. No allocator observer participates in this case.
            try #require(occurrences.0 == normalizedRanges)
            try #require(batch.0 == displayRanges)
            let selected = try #require(match.0)
            try #require(selected.range == first && selected.contextRange == first && selected.coverage == 1)
            try #require(selected.preparedDisplayRangeMapping.matches(in: body.text, normalizedText: body.normalizedText))
            try #require(freshSnippet.0.text.utf8.elementsEqual(expected.snippet.utf8))
            try #require(freshSnippet.0.highlights == expected.highlights)
            try #require(try encoder.encode(hit.0) == fullResultBytes)
            guard iteration >= warmups else { continue }
            for (stage, elapsed) in [
                ("all_occurrences", occurrences.1),
                ("checked_mapping_preparation", mapping.1),
                ("checked_batch_mapping", batch.1),
                ("best_match", match.1),
                ("fresh_snippet", freshSnippet.1),
                ("complete_hit", hit.1),
            ] {
                timings[stage, default: []].append(elapsed)
            }
        }
        try #require(timings.values.allSatisfy { $0.count == samples })
        let summaries = timings.mapValues { values in
            let sorted = values.sorted()
            return ["min": sorted[0], "median": sorted[1], "max": sorted[2]]
        }
        let report: [String: Any] = [
            "schema": "scholium-mixed-search-stage-attribution-v1",
            "fixture": "mixed_uppercase_nfd_accent_cjk_emoji", "repetitions": repetitions,
            "build_configuration": diagnosticBuildConfiguration,
            "source_bytes": fixture.document.sourceBytes.count,
            "source_sha256": fixture.document.fingerprint.sha256,
            "display_sha256": DocumentFingerprint(data: Data(body.text.utf8)).sha256,
            "normalized_sha256": DocumentFingerprint(data: Data(body.normalizedText.utf8)).sha256,
            "occurrence_count": normalizedRanges.count,
            "normalized_ranges_sha256": DocumentFingerprint(data: try encoder.encode(normalizedRanges)).sha256,
            "display_ranges_sha256": DocumentFingerprint(data: try encoder.encode(displayRanges)).sha256,
            "result_sha256": DocumentFingerprint(data: fullResultBytes).sha256,
            "complete_result": try JSONSerialization.jsonObject(with: fullResultBytes),
            "warmups": warmups, "samples": samples,
            "stage_ms": summaries, "samples_ms": timings,
            "all_outputs_equal_manual_or_full_result_oracle": true,
            "allocation_sampling_during_timings": false,
            "scope":
                "Prepared exact 1572863-byte mixed fixture; source/projection setup excluded. Mapping preparation and its range batch are separate elapsed stages. Stage durations overlap causally and are not additive. Only one warmup plus three samples; no original 23-call timing method or allocator observer is enabled by this flag.",
        ]
        try emitSnippetDiagnostic(report, prefix: "SEARCH_MIXED_STAGE_DIAGNOSTIC")
    }

    private func mixedFoldedCJKFixture(repetitions: Int) throws -> Fixture {
        let unit = "Agency CAFÉ 自由😀 evidence Cafe\u{301} 自由. "
        try #require(unit.count == 34 && unit.utf16.count == 36 && unit.utf8.count == 48)
        let source = String(String(repeating: unit, count: repetitions).dropLast())
        let fixture = try Fixture(source: source, query: "body:自由")
        let body = try #require(fixture.stored.segments.first { $0.field == .body })
        // The visible-text collector appends one unmapped paragraph LF.
        // The authored NFD bytes remain otherwise exact; do not NFC-fold the oracle.
        let expectedDisplay = source + "\n"
        let displayBytesMatch = body.text.utf8.elementsEqual(expectedDisplay.utf8)
        try #require(
            displayBytesMatch,
            "Expected raw display plus paragraph LF; actual bytes \(body.text.utf8.count), expected \(expectedDisplay.utf8.count); suffix \(String(body.text.suffix(12)).debugDescription)"
        )
        // Keep the case-folding mismatch that rejects the identity/linear map,
        // independently of the collector's trailing paragraph separator.
        try #require(!body.text.utf8.elementsEqual(body.normalizedText.utf8))
        try #require(body.text != body.normalizedText)
        try #require(body.text.utf8.first == 65 && body.normalizedText.utf8.first == 97)
        let normalizedUnit = "agency cafe 自由😀 evidence cafe 自由. "
        let expectedNormalized = String(String(repeating: normalizedUnit, count: repetitions).dropLast())
        let normalizedBytesMatch = body.normalizedText.utf8.elementsEqual(expectedNormalized.utf8)
        try #require(normalizedBytesMatch)
        let sourceBytesMatch = fixture.document.sourceBytes == Data(source.utf8)
        try #require(sourceBytesMatch)
        return fixture
    }

    private func verifyMixedFoldedCJK(_ fixture: Fixture) throws -> NoteSearchResult {
        let hit = fixture.hit()
        let source = fixture.document.rawContent
        let expectedSnippet = String(source.prefix(174)) + "…"
        let expectedHighlights: [SearchHighlight] = (0..<5).flatMap { unit in
            [12, 32].map { offset in
                SearchHighlight(utf16LowerBound: unit * 36 + offset, utf16UpperBound: unit * 36 + offset + 2)
            }
        }
        try #require(hit.snippet.utf8.elementsEqual(expectedSnippet.utf8))
        try #require(hit.highlights == expectedHighlights)
        try #require(
            hit.sourceRange
                == SearchSourceRange(
                    utf16LowerBound: 12, utf16UpperBound: 14, line: 1, column: 13, endLine: 1, endColumn: 15))
        try #require(hit.matchedField == .body && hit.matchedFields == [.body])
        try #require(hit.fingerprint == fixture.document.fingerprint)
        let exact = try #require(Range(NSRange(location: 12, length: 2), in: source))
        try #require(String(source[exact]).utf8.elementsEqual("自由".utf8))
        for highlight in hit.highlights {
            let range = try #require(
                Range(
                    NSRange(location: highlight.utf16LowerBound, length: highlight.utf16UpperBound - highlight.utf16LowerBound),
                    in: hit.snippet))
            try #require(String(hit.snippet[range]).utf8.elementsEqual("自由".utf8))
        }
        return hit
    }

    private var diagnosticBuildConfiguration: String {
        #if DEBUG
            "Debug"
        #else
            "Release"
        #endif
    }

    private var directPresentationScope: String {
        "SwiftPM \(diagnosticBuildConfiguration) direct Search result presentation; excludes source projection, SQLite hydration, I/O, correctness assertions, native capture and paint; no release-gate claim"
    }

    private func emitSnippetDiagnostic(_ report: [String: Any], prefix: String) throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = repository.appendingPathComponent(".build/search-snippet-diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(prefix.lowercased())-\(UUID().uuidString.lowercased()).json")
        var record = report
        record["artifact_path"] = url.path
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        try data.write(to: url, options: .atomic)
        FileHandle.standardOutput.write(Data("\(prefix) \(String(decoding: data, as: UTF8.self))\n".utf8))
    }

    /// The same existing Darwin allocator and DispatchSource pattern used by
    /// RelatedContentLexicalPoolPeakMeasurementTests; never enabled by timing.
    private final class SnippetAllocationSampler: @unchecked Sendable {
        private let lock = NSLock()
        private let before: Int
        private var peak: Int
        private var samples = 0
        private var active = true

        init() {
            let bytes = Self.allocatedBytes()
            before = bytes
            peak = bytes
        }

        func sample() {
            let bytes = Self.allocatedBytes()
            lock.lock()
            defer { lock.unlock() }
            guard active else { return }
            samples += 1
            peak = max(peak, bytes)
        }

        func stop() -> [String: Int] {
            let after = Self.allocatedBytes()
            lock.lock()
            defer { lock.unlock() }
            peak = max(peak, after)
            active = false
            return [
                "before_bytes": before, "after_bytes": after,
                "observed_peak_bytes": peak, "observed_peak_delta_bytes": max(0, peak - before),
                "timer_sample_count": samples,
            ]
        }

        private static func allocatedBytes() -> Int {
            var statistics = malloc_statistics_t()
            malloc_zone_statistics(nil, &statistics)
            return Int(statistics.size_in_use)
        }
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
            NoteSearchResultBuilder.hit(
                candidate: .init(document: stored, identityPriority: 3, lexicalRank: 0), ast: ast, freshness: freshness, linkMatches: [:])
        }
    }
}
