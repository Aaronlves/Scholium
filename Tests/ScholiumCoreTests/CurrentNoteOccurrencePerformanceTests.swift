import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

/// Proposed test-only diagnostic. No production edits or on-disk index are needed.
@Suite("Current-buffer occurrence pagination", .serialized)
struct CurrentNoteOccurrencePerformanceTests {
    @Test("Eager reference preserves overlapping predicates, paragraph witnesses and full pages")
    func occurrenceFidelityMatrix() throws {
        let raw = """
            ---
            title: Needle source
            summary: needle source property
            ---
            # Needle heading

            😀 needle café and cafe\u{301}; needlework beside [[Target]]{{needle annotation}}.

            > Outer needle
            >
            > - Nested needle and café.

            Last needle and footnote [^ref].

            [^ref]: needle footnote.
            """
        let queries = [
            "needle",
            "body:needle OR body:needle* OR body:\"needle\"",
            "body:needle OR paragraph:(needle)",
            "paragraph:(needle OR cafe)",
            "heading:needle OR body:needle OR link_annotation:needle OR footnote:needle",
        ]
        for raw in [raw, "\u{FEFF}" + raw.replacingOccurrences(of: "\n", with: "\r\n")] {
            for query in queries {
                let fixture = try Fixture(raw: raw, query: query)
                for (offset, limit) in [(0, 1), (1, 2), (0, 20), (100, 20), (Int.max, 20)] {
                    let request = fixture.request(offset: offset, limit: limit)
                    let expected = referenceResponse(fixture, request: request)
                    let actual = try TriptychSearchIndex.searchCurrentSource(
                        request, ast: fixture.ast, vault: fixture.vault)
                    try #require(try encoded(actual) == encoded(expected))
                    #expect(actual.freshnessToken == .currentNote(fixture.source))
                    #expect(actual.results.allSatisfy { result in
                        guard case .note(let hit) = result else { return false }
                        return hit.fingerprint == fixture.note.fingerprint
                            && hit.stableNoteID == fixture.source.stableNoteID?.uuidString.lowercased()
                    })
                    for hit in noteHits(actual) {
                        if let range = hit.sourceRange {
                            try #require(range.utf16LowerBound >= 0 && range.utf16UpperBound <= raw.utf16.count)
                            let sourceRange = try #require(Range(NSRange(location: range.utf16LowerBound, length: range.utf16UpperBound - range.utf16LowerBound), in: raw))
                            #expect(!raw[sourceRange].isEmpty)
                        }
                    }
                }
            }
        }
    }

    @Test("Occurrence pages preserve complete fresh results across repeated and byte-distinct display segments")
    func occurrencePageMappingInputIsolation() throws {
        let nfd = "Cafe\u{301} 自由 and 自由."
        let nfc = "Café 自由 and 自由."
        try #require(nfd == nfc && !nfd.utf8.elementsEqual(nfc.utf8))
        for (raw, query) in [
            ("\u{FEFF}# Page\r\n\r\n" + nfd + "\r\n\r\n" + nfd + "\r\n\r\n" + nfc + "\r\n\r\n" + nfd + "\r\n", "paragraph:(自由)"),
            ("# 自由 same.\n\n自由 same.\n\n> 自由 same.\n\n[[Target]]{{自由 same.}}\n\n[^a]: 自由 same.\n", "自由 OR paragraph:(自由)"),
            ("# Page\r\n\r\n\t哲学哲学 \r\n\r\n哲学哲学\r\n\r\n哲学哲学\r\n", "paragraph:(哲学)"),
        ] {
            let fixture = try Fixture(raw: raw, query: query)
            for (offset, limit) in [(0, 1), (1, 3), (0, 20), (Int.max, 20)] {
                let request = fixture.request(offset: offset, limit: limit)
                let expected = referenceResponse(fixture, request: request)
                let actual = try TriptychSearchIndex.searchCurrentSource(
                    request, ast: fixture.ast, vault: fixture.vault)
                if offset == 0 { try #require(!expected.results.isEmpty) }
                #expect(actual == expected)
                try #require(try encoded(actual) == encoded(expected))
                #expect(fixture.note.sourceBytes == Data(raw.utf8))
            }
        }
    }

    @Test(
        "Measure bounded dense current-buffer pages and eager presentation attribution",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_CURRENT_NOTE_OCCURRENCES"] == "1"),
        .timeLimit(.minutes(1)),
        arguments: [50, 200])
    func denseOccurrencePages(occurrences: Int) throws {
        // 19 UTF-8 bytes per unit: about 1 KiB and 4 KiB, not a long-note stress run.
        let unit = "哲学 cafe\u{301} 😀 "
        let prefix = "\u{FEFF}# Occurrences\r\n\r\n"
        let raw = prefix + String(repeating: unit, count: occurrences) + "\r\n"
        let fixture = try Fixture(raw: raw, query: "body:哲学")
        try #require(fixture.note.sourceBytes == Data(raw.utf8))
        let allExpected = referenceOccurrenceHits(
            candidate: fixture.candidate, ast: fixture.matchedAST,
            freshnessToken: fixture.freshness, limit: Int.max)
        try #require(allExpected.count == occurrences)
        try verifyManualDenseLocators(allExpected, fixture: fixture, prefix: prefix, unit: unit, count: occurrences)
        let allCandidates = NoteSearchResultBuilder.occurrenceCandidates(
            candidate: fixture.candidate, ast: fixture.matchedAST,
            limit: Int.max, linkMatches: [:])
        let allActual = NoteSearchResultBuilder.materializeOccurrenceCandidates(
            allCandidates[...], freshness: fixture.freshness)
        try #require(try encoded(allActual) == encoded(allExpected))

        // Check tail and beyond-tail hasMore without increasing timed scenarios.
        for offset in [occurrences - 20, occurrences] {
            let request = fixture.request(offset: offset, limit: 20)
            let expected = referenceResponse(fixture, request: request)
            let actual = try TriptychSearchIndex.searchCurrentSource(request, ast: fixture.ast, vault: fixture.vault)
            try #require(try encoded(actual) == encoded(expected))
            #expect(actual.hasMore == false)
            #expect(actual.results == Array(allExpected.dropFirst(offset).prefix(20)).map(SearchResult.note))
        }

        let warmups = 1
        let samples = 3
        var pageRecords: [[String: Any]] = []
        for offset in [0, 20] {
            let request = fixture.request(offset: offset, limit: 20)
            let expected = referenceResponse(fixture, request: request)
            let expectedBytes = try encoded(expected)
            let required = offset + 20 + 1
            let expectedPrefix = referenceOccurrenceHits(
                candidate: fixture.candidate, ast: fixture.matchedAST,
                freshnessToken: fixture.freshness, limit: required)
            let expectedLocators = expectedPrefix.map(Locator.init)
            try #require(expected.results == Array(allExpected.dropFirst(offset).prefix(20)).map(SearchResult.note))
            #expect(expected.hasMore == (offset + 20 < occurrences))
            var timings: [String: [Double]] = [:]
            for iteration in 0..<(warmups + samples) {
                let api = try measured {
                    try TriptychSearchIndex.searchCurrentSource(request, ast: fixture.ast, vault: fixture.vault)
                }
                let prepared = measured {
                    preparedResponse(fixture, request: request)
                }
                let locators = measured {
                    locatorPrefix(candidate: fixture.candidate, ast: fixture.matchedAST, limit: required)
                }
                // Full response/result encoding, all assertions and hashing stay outside timers.
                try #require(try encoded(api.0) == expectedBytes)
                try #require(try encoded(prepared.0) == expectedBytes)
                try #require(locators.0 == expectedLocators)
                if iteration >= warmups {
                    for (stage, elapsed) in [("current_source_api", api.1), ("prepared_occurrence_page", prepared.1), ("enumeration_and_locators_only", locators.1)] {
                        timings[stage, default: []].append(elapsed)
                    }
                }
            }
            pageRecords.append([
                "offset": offset, "limit": 20, "required_prefix_with_probe": required,
                "stage_ms": timings.mapValues(summary), "samples_ms": timings,
                "response_sha256": DocumentFingerprint(data: expectedBytes).sha256,
                "complete_expected_response": try JSONSerialization.jsonObject(with: expectedBytes),
                "has_more": expected.hasMore,
                "all_timed_outputs_byte_equal_reference": true,
            ])
        }
        let report: [String: Any] = [
            "schema": "scholium-current-note-occurrence-diagnostic-v2",
            "build_configuration": buildConfiguration,
            "fixture": "bounded_single_paragraph_cjk_nfd_emoji_crlf_bom",
            "occurrences": occurrences, "source_bytes": fixture.note.sourceBytes.count,
            "source_sha256": fixture.note.fingerprint.sha256,
            "source_utf8": raw, "query": fixture.query,
            "full_ordered_occurrences_sha256": DocumentFingerprint(data: try encoded(allExpected)).sha256,
            "manual_source_locators": allExpected.compactMap(\.sourceRange).map {
                ["lower": $0.utf16LowerBound, "upper": $0.utf16UpperBound,
                 "line": $0.line, "column": $0.column, "end_line": $0.endLine, "end_column": $0.endColumn]
            },
            "warmups": warmups, "samples": samples, "pages": pageRecords,
            "scope": "Current-buffer This Note API includes fresh source projection; prepared occurrence stage excludes it; locator-only stage excludes all snippet/result materialization. No SQLite, file reads, UI/paint, allocation sampling, corpus truncation or long-note claim.",
            "oracle": "Frozen pre-change eager occurrence algorithm retains recursive per-child limits, exact sort/dedup and all result fields. Dense source coordinates are independently computed from authored unit offsets. Full sorted-key response bytes checked outside every timer.",
        ]
        try emit(report)
    }

    private func verifyManualDenseLocators(
        _ hits: [NoteSearchResult], fixture: Fixture, prefix: String, unit: String, count: Int
    ) throws {
        try #require(hits.count == count)
        for (ordinal, hit) in hits.enumerated() {
            let lower = prefix.utf16.count + ordinal * unit.utf16.count
            let expected = SearchSourceRange(
                utf16LowerBound: lower, utf16UpperBound: lower + 2,
                line: 3, column: ordinal * unit.utf16.count + 1,
                endLine: 3, endColumn: ordinal * unit.utf16.count + 3)
            try #require(hit.sourceRange == expected)
            #expect(hit.sourceLine == 3 && hit.matchedField == .body)
            #expect(hit.resultID == "\(fixture.vault.id.uuidString.lowercased()):Unsaved/Dense.md:\(lower):\(lower + 2)")
            let range = try #require(Range(NSRange(location: expected.utf16LowerBound, length: expected.utf16UpperBound - expected.utf16LowerBound), in: fixture.source.source))
            #expect(fixture.source.source[range].utf8.elementsEqual("哲学".utf8))
            #expect(hit.highlights.count == 1)
            let highlight = try #require(hit.highlights.first)
            let displayed = try #require(Range(
                NSRange(location: highlight.utf16LowerBound, length: highlight.utf16UpperBound - highlight.utf16LowerBound),
                in: hit.snippet))
            #expect(hit.snippet[displayed].utf8.elementsEqual("哲学".utf8))
        }
    }

    private func preparedResponse(_ fixture: Fixture, request: SearchRequest) -> SearchResponse {
        let limit = min(request.limit, SearchContract.maximumNoteResults)
        let required = requiredCount(offset: request.resultOffset, limit: limit)
        let candidates = NoteSearchResultBuilder.occurrenceCandidates(
            candidate: fixture.candidate, ast: fixture.matchedAST,
            limit: required, linkMatches: [:])
        let page = candidates.dropFirst(min(request.resultOffset, candidates.count))
        let results = NoteSearchResultBuilder.materializeOccurrenceCandidates(
            page.prefix(limit), freshness: fixture.freshness)
        return SearchResponse(
            requestID: request.id, scope: .thisNote,
            explanation: fixture.ast.explanation(scope: .thisNote),
            freshnessToken: fixture.freshness, availability: .unavailable,
            results: results.map(SearchResult.note), hasMore: page.count > limit)
    }

    private func requiredCount(offset: Int, limit: Int) -> Int {
        let upper = offset.addingReportingOverflow(limit)
        let probe = upper.partialValue.addingReportingOverflow(1)
        return upper.overflow || probe.overflow ? Int.max : probe.partialValue
    }

    private func referenceResponse(_ fixture: Fixture, request: SearchRequest) -> SearchResponse {
        let limit = min(request.limit, SearchContract.maximumNoteResults)
        let required = requiredCount(offset: request.resultOffset, limit: limit)
        let candidates = referenceOccurrenceHits(
            candidate: fixture.candidate, ast: fixture.matchedAST,
            freshnessToken: fixture.freshness, limit: required)
        let page = candidates.dropFirst(min(request.resultOffset, candidates.count))
        return SearchResponse(
            requestID: request.id, scope: .thisNote,
            explanation: fixture.ast.explanation(scope: .thisNote),
            freshnessToken: fixture.freshness, availability: .unavailable,
            results: page.prefix(limit).map(SearchResult.note), hasMore: page.count > limit)
    }

    // Independent eager pipeline retained as a correctness oracle for deferred presentation.
    private func referenceOccurrenceHits(
        candidate: SearchCandidate,
        ast: SearchQueryAST,
        freshnessToken: SearchFreshnessToken,
        limit: Int
    ) -> [NoteSearchResult] {
        let document = candidate.document
        let matchedFields = SearchMatcher.matchedFields(ast: ast, document: document)
        let reasons = NoteSearchResultBuilder.matchReasons(
            ast: ast,
            document: document,
            linkMatches: [:]
        )
        var hits: [NoteSearchResult] = []
        for lead in ast.positiveLexicalClauses {
            for segment in SearchMatcher.matchingSegments(for: lead, in: document) {
                for range in SearchMatcher.occurrences(of: lead.value, in: segment.normalizedText) {
                    let sourceRange = NoteSearchResultBuilder.sourceRange(
                        for: range,
                        segment: segment,
                        lineStarts: document.sourceLineStarts
                    )
                    let presentation = NoteSearchResultBuilder.snippet(
                        segment: segment,
                        normalizedRange: range,
                        positiveClauses: ast.positiveLexicalClauses,
                        occurrenceClause: lead
                    )
                    hits.append(
                        NoteSearchResult(
                            resultID:
                                "\(document.vaultID.uuidString.lowercased()):\(document.relativePath):\(sourceRange?.utf16LowerBound ?? segment.ordinal):\(sourceRange?.utf16UpperBound ?? segment.ordinal)",
                            vaultID: document.vaultID,
                            vaultName: document.vaultName,
                            vaultRole: document.vaultRole,
                            relativePath: document.relativePath,
                            stableNoteID: document.stableNoteID,
                            title: document.title,
                            matchedField: segment.field,
                            context: NoteSearchResultBuilder.context(for: segment.field),
                            sourceLine: sourceRange?.line ?? 1,
                            snippet: presentation.text,
                            highlights: presentation.highlights,
                            matchedFields: matchedFields,
                            rankReason: NoteSearchResultBuilder.rankReason(candidate.identityPriority, filterOnly: ast.isFilterOnly),
                            primaryMatchReason: reasons.first ?? .lexical,
                            additionalMatchReasons: Array(reasons.dropFirst()),
                            sourceRange: sourceRange,
                            freshnessToken: freshnessToken,
                            fingerprint: document.fingerprint,
                            evidentialLayer: document.evidentialLayer,
                            classification: .retrievalLead
                        ))
                }
            }
        }
        for paragraph in SearchMatcher.paragraphWitnesses(ast, document: document) {
            let local = SearchCandidate(document: paragraph.document, identityPriority: 0, lexicalRank: candidate.lexicalRank)
            hits.append(contentsOf: referenceOccurrenceHits(candidate: local, ast: paragraph.ast, freshnessToken: freshnessToken, limit: limit))
        }
        var seen: Set<String> = []
        return Array(
            hits.sorted {
                ($0.sourceRange?.utf16LowerBound ?? 0, $0.sourceRange?.utf16UpperBound ?? 0) < (
                    $1.sourceRange?.utf16LowerBound ?? 0, $1.sourceRange?.utf16UpperBound ?? 0
                )
            }.filter { seen.insert($0.resultID).inserted }.prefix(limit))
    }
    private struct Locator: Equatable {
        let resultID: String
        let range: SearchSourceRange?
        init(_ hit: NoteSearchResult) { resultID = hit.resultID; range = hit.sourceRange }
        init(resultID: String, range: SearchSourceRange?) { self.resultID = resultID; self.range = range }
    }

    /// Measurement-only lower-bound stage, not a proposed production engine.
    private func locatorPrefix(candidate: SearchCandidate, ast: SearchQueryAST, limit: Int) -> [Locator] {
        let document = candidate.document
        var values: [Locator] = []
        for lead in ast.positiveLexicalClauses {
            for segment in SearchMatcher.matchingSegments(for: lead, in: document) {
                for range in SearchMatcher.occurrences(of: lead.value, in: segment.normalizedText) {
                    let source = NoteSearchResultBuilder.sourceRange(for: range, segment: segment, lineStarts: document.sourceLineStarts)
                    values.append(.init(
                        resultID: "\(document.vaultID.uuidString.lowercased()):\(document.relativePath):\(source?.utf16LowerBound ?? segment.ordinal):\(source?.utf16UpperBound ?? segment.ordinal)",
                        range: source))
                }
            }
        }
        for paragraph in SearchMatcher.paragraphWitnesses(ast, document: document) {
            let local = SearchCandidate(document: paragraph.document, identityPriority: 0, lexicalRank: candidate.lexicalRank)
            values.append(contentsOf: locatorPrefix(candidate: local, ast: paragraph.ast, limit: limit))
        }
        var seen: Set<String> = []
        return Array(values.sorted {
            ($0.range?.utf16LowerBound ?? 0, $0.range?.utf16UpperBound ?? 0)
                < ($1.range?.utf16LowerBound ?? 0, $1.range?.utf16UpperBound ?? 0)
        }.filter { seen.insert($0.resultID).inserted }.prefix(limit))
    }

    private struct Fixture {
        let raw: String
        let query: String
        let vault: RegisteredVault
        let source: SearchSourceSnapshot
        let note: NoteDocument
        let ast: SearchQueryAST
        let matchedAST: SearchQueryAST
        let candidate: SearchCandidate
        let freshness: SearchFreshnessToken

        init(raw: String, query: String) throws {
            self.raw = raw
            self.query = query
            let vault = RegisteredVault(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
                name: "Synthetic Topics", role: .topicKnowledge,
                canonicalPath: "/synthetic/current-note-occurrences",
                registeredAt: Date(timeIntervalSince1970: 0))
            self.vault = vault
            let source = SearchSourceSnapshot(
                noteID: .init(vaultID: vault.id, relativePath: "Unsaved/Dense.md"),
                stableNoteID: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
                editorSessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
                source: raw, editorRevision: 7)
            self.source = source
            freshness = .currentNote(source)
            let note = NoteDocument(relativePath: source.noteID.relativePath, rawContent: raw)
            self.note = note
            let profile = WorkflowProfileResolver.resolve(vaultRole: vault.role)
            let projection = SearchDocumentProjection(document: note, profile: profile, hasBrokenLink: false)
            let properties = SearchPropertyProjection(document: note, profile: profile)
            let document = StoredSearchDocument(
                rowID: -1, vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role,
                relativePath: note.relativePath, stableNoteID: source.stableNoteID?.uuidString.lowercased(),
                title: projection.title, normalizedTitle: SearchTextNormalization.normalize(projection.title),
                filenameKey: SearchTextNormalization.normalize(((note.relativePath as NSString).lastPathComponent as NSString).deletingPathExtension),
                pathKey: SearchTextNormalization.normalize(note.relativePath), aliases: projection.aliases,
                calloutRoles: projection.calloutRoles, hasBrokenLink: false,
                fingerprint: note.fingerprint, evidentialLayer: .topicNote, roleOrder: 1,
                sourceLineStarts: projection.sourceLineStartsUTF16, segments: projection.segments,
                paragraphs: projection.paragraphs, paragraphsAreComplete: note.hasProvableBodyBoundary,
                properties: properties.entries, propertyIssues: properties.issues)
            let parsed = SearchQueryParser.parse(query)
            try #require(parsed.diagnostics.isEmpty)
            let ast = try #require(parsed.ast)
            self.ast = ast
            try #require(ast.scopeDiagnostic(scope: .thisNote, queryUTF16Count: query.utf16.count) == nil)
            let evaluation = SearchMatcher.evaluate(ast, document: document, linkMatches: [:])
            try #require(evaluation.truth == .yes)
            matchedAST = ast.matched(by: evaluation)
            candidate = SearchCandidate(
                document: document,
                identityPriority: SearchMatcher.identityPriority(identityNeedle: ast.identityNeedle, document: document),
                lexicalRank: 0)
        }

        func request(offset: Int, limit: Int) -> SearchRequest {
            SearchRequest(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000104")!,
                query: query, presentationScope: .thisNote, executionScope: .currentNote(source),
                limit: limit, offset: offset)
        }
    }

    private func noteHits(_ response: SearchResponse) -> [NoteSearchResult] {
        response.results.compactMap { result in
            guard case .note(let hit) = result else { return nil }
            return hit
        }
    }

    private func encoded<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func measured<Value>(_ operation: () throws -> Value) rethrows -> (Value, Double) {
        let start = ContinuousClock.now
        let value = try operation()
        let duration = start.duration(to: .now).components
        return (value, Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
    }

    private func summary(_ values: [Double]) -> [String: Double] {
        let sorted = values.sorted()
        return ["min": sorted[0], "median": sorted[sorted.count / 2], "max": sorted[sorted.count - 1]]
    }

    private var buildConfiguration: String {
        #if DEBUG
            "Debug"
        #else
            "Release"
        #endif
    }

    private func emit(_ report: [String: Any]) throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = repository.appendingPathComponent(".build/current-note-occurrence-diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("occurrences-\(report["occurrences"]!)-\(UUID().uuidString.lowercased()).json")
        let bytes = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        try bytes.write(to: target, options: .atomic)
        let compact: [String: Any] = [
            "artifact_path": target.path, "schema": report["schema"]!,
            "build_configuration": report["build_configuration"]!,
            "source_bytes": report["source_bytes"]!, "occurrences": report["occurrences"]!,
            "source_sha256": report["source_sha256"]!,
            "pages": (report["pages"] as! [[String: Any]]).map {
                ["offset": $0["offset"]!, "stage_ms": $0["stage_ms"]!, "response_sha256": $0["response_sha256"]!]
            },
        ]
        let line = try JSONSerialization.data(withJSONObject: compact, options: [.sortedKeys])
        FileHandle.standardOutput.write(Data("CURRENT_NOTE_OCCURRENCE_DIAGNOSTIC \(String(decoding: line, as: UTF8.self))\n".utf8))
    }
}
