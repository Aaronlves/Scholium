import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Literal lexical lookup parity")
struct SearchLiteralMatcherTests {
    @Test("Literal lookup preserves Foundation ranges, counts and first-match stopping")
    func foundationParity() {
        let texts = [
            "", "agency agencywork workagency agency_ agency中文 中文agency agency.",
            "aaaa aa aa_ _aa foo_bar foo_barbar foo-bar.",
            "CAFÉ cafe\u{301} café cafe CAFE cafe中文 中文cafe.",
            "自由自在 自由自由 自由agency 自由agencywork agency自由.",
            "각 각 각행동 ΐ ι\u{308}\u{301} क कि क़ ﬀ ff K K k.",
            "a\u{20DD} a\u{200D}b a\u{301} a_b a-b a\r\na\t a.",
            "中\u{20DD} 中\u{FE0F} 中文 中中.",
            "😀 👩🏽‍🔬 🇨🇳 \u{FEFF}reason\r\nreason reasoning reason.",
            "not sufficiently not sufficient not sufficient.", "reason\0自由\0reason 自由",
        ]
        let terms = [
            "", "a", "aa", "agency", "foo_bar", "café", "cafe\u{301}", "自由", "自由agency", "agency自由",
            "各", "각", "각", "ΐ", "क", "ﬀ", "K", "中", "👩", "😀", "reason", "not sufficient", "\0",
            "reason\0自由",
        ]
        for source in texts {
            let normalized = SearchTextNormalization.lexicalNormalize(source)
            for text in [normalized, NSMutableString(string: normalized) as String] {
                for term in terms {
                    let needle = SearchTextNormalization.lexicalNormalize(term)
                    for value in [SearchLexicalValue.term(term), .phrase(term), .prefix(term)] {
                        var expected: [Range<Int>] = []
                        Self.foundationScan(value, text: text, needle: needle) {
                            expected.append(
                                $0.lowerBound.utf16Offset(in: text)..<$0.upperBound.utf16Offset(in: text))
                            return true
                        }
                        #expect(
                            SearchMatcher.occurrences(of: value, in: text, normalizedNeedle: needle) == expected)
                        #expect(
                            SearchMatcher.occurrenceCount(of: value, in: text, normalizedNeedle: needle)
                                == expected.count)
                        #expect(
                            SearchMatcher.containsOccurrence(of: value, in: text, normalizedNeedle: needle)
                                == !expected.isEmpty)
                        #expect(
                            SearchMatcher.occurrences(
                                of: value, in: text, normalizedNeedle: needle, firstOnly: true)
                                == Array(expected.prefix(1)))
                    }
                }
            }
        }
        #expect(SearchMatcher.occurrences(of: .term("自由"), in: "自由自由自由") == [0..<2, 2..<4, 4..<6])
        #expect(
            SearchMatcher.occurrences(of: .prefix("reason"), in: "reasoning reason") == [0..<6, 10..<16])
    }

    @Test(
        "Opt-in actual Stress text literal matching comparison",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_RELATED_MATCHING"] == "1"))
    func actualStressMatching() throws {
        let environment = ProcessInfo.processInfo.environment
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let build = repository.appendingPathComponent(".build", isDirectory: true)
        let fixture = URL(fileURLWithPath: try #require(environment["SCHOLIUM_STRESS_FIXTURE"]))
            .standardizedFileURL
        let output = URL(fileURLWithPath: try #require(environment["SCHOLIUM_STRESS_OUTPUT"]))
            .standardizedFileURL
        try #require(
            fixture.path.hasPrefix(build.path + "/") && fixture == fixture.resolvingSymlinksInPath())
        try #require(
            output.path.hasPrefix(build.path + "/") && output == output.resolvingSymlinksInPath())
        try #require(output != fixture && !output.path.hasPrefix(fixture.path + "/"))
        let manifestBytes = try Data(contentsOf: fixture.appendingPathComponent("stress-manifest.json"))
        let manifest = try #require(JSONSerialization.jsonObject(with: manifestBytes) as? [String: Any])
        try #require(manifest["synthetic_nonprivate"] as? Bool == true)
        let files = try #require(manifest["files"] as? [String: [String: Any]])
        let scenarios = try #require(manifest["scenarios"] as? [String: String])
        let oracles = try #require(manifest["search_oracles"] as? [[String: Any]])
        let shortPath = try #require(
            (oracles.first { $0["label"] as? String == "rare_body" }?["expected_paths"] as? [String])?
                .first)
        func document(_ path: String) throws -> NoteDocument {
            let bytes = try Data(contentsOf: fixture.appendingPathComponent(path))
            let expected = try #require(files[path])
            try #require(DocumentFingerprint(data: bytes).sha256 == expected["sha256"] as? String)
            let text = String(decoding: bytes, as: UTF8.self)
            try #require(Data(text.utf8) == bytes)
            return NoteDocument(relativePath: path, rawContent: text)
        }
        let seed = try document(shortPath)
        let range = try #require(
            NSRegularExpression(pattern: #"(?m)^Record [^\r\n]+"#).firstMatch(
                in: seed.rawContent, range: NSRange(location: 0, length: seed.rawContent.utf16.count))?
                .range)
        let focus = String(seed.rawContent[try #require(Range(range, in: seed.rawContent))])
        let material = RelatedContentSeedMaterial(
            projection: SearchDocumentProjection(document: seed),
            focuses: [.init(kind: .selectedPassage, text: focus)])
        let terms = material.termMatcher.terms
        let needles = terms.map(SearchTextNormalization.lexicalNormalize)
        var records: [[String: Any]] = []
        for (label, path) in [
            ("short", shortPath), ("long", try #require(scenarios["long_prose"])),
            ("dense", try #require(scenarios["dense_links"])),
        ] {
            let note = try document(path)
            let projection = SearchDocumentProjection(document: note)
            let texts = projection.segments.map(\.normalizedText)
            func evaluate(native: Bool) -> [Int] {
                var result: [Int] = []
                for text in texts {
                    for (index, term) in terms.enumerated() {
                        let value = SearchLexicalValue.term(term)
                        if native {
                            result.append(
                                SearchMatcher.occurrenceCount(of: value, in: text, normalizedNeedle: needles[index])
                            )
                            result.append(
                                SearchMatcher.containsOccurrence(
                                    of: value, in: text, normalizedNeedle: needles[index]) ? 1 : 0)
                        } else {
                            var count = 0
                            Self.foundationScan(value, text: text, needle: needles[index]) { _ in
                                count += 1
                                return true
                            }
                            var present = false
                            Self.foundationScan(value, text: text, needle: needles[index]) { _ in
                                present = true
                                return false
                            }
                            result.append(count)
                            result.append(present ? 1 : 0)
                        }
                    }
                }
                return result
            }
            // Preparation, oracle and warmups are excluded from samples. Alternate
            // order so every variant does not systematically run second.
            let expected = evaluate(native: false)
            try #require(evaluate(native: true) == expected)
            var samples: [[String: Any]] = []
            for pair in 0..<3 {
                for native in pair.isMultiple(of: 2) ? [false, true] : [true, false] {
                    let started = ContinuousClock.now
                    let result = evaluate(native: native)
                    let elapsed = started.duration(to: .now).components
                    try #require(result == expected)
                    samples.append([
                        "pair": pair, "variant": native ? "candidate" : "foundation",
                        "milliseconds": Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15,
                    ])
                }
            }
            records.append([
                "scenario": label, "source_sha256": note.fingerprint.sha256, "segments": texts.count,
                "normalized_utf8_bytes": texts.reduce(0) { $0 + $1.utf8.count }, "terms": terms.count,
                "non_ascii_terms": needles.filter { !$0.utf8.allSatisfy { $0 < 128 } }.count,
                "ordered_count_presence_sha256": DocumentFingerprint(
                    data: try JSONEncoder().encode(expected)
                ).sha256,
                "samples": samples,
            ])
            try #require(try document(path).sourceBytes == note.sourceBytes)
        }
        let report: [String: Any] = [
            "schema": "scholium-stress-literal-matcher-v1",
            "candidate_lookup": "Darwin.memmem with scoped UTF8 buffers",
            "fixture_manifest_sha256": DocumentFingerprint(data: manifestBytes).sha256,
            "boundary":
                "Counts plus first-presence per normalized Search segment and exact Short focus/source terms; direct matcher component, not prepared ASCII scoring or complete Related latency.",
            "sampling":
                "One excluded warmup per variant;3alternating measuredpairs. I/O,source/semantic preparation,oracle,encoding and equality checks excluded.",
            "records": records,
        ]
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("literal-matcher.json"), options: .atomic)
        print("Stress literal matcher:3sources x3paired samples; exact count/presence parity passed.")
    }

    /// Frozen pre-change literal search. Keep its Foundation lookup and canonical
    /// fallback independent of the production lookup; all stopping/boundary rules
    /// remain the prior contract, including when a literal hit splits a grapheme.
    private static func foundationScan(
        _ value: SearchLexicalValue, text: String, needle: String, visit: (Range<String.Index>) -> Bool
    ) {
        guard !needle.isEmpty, !text.isEmpty else { return }
        let hasCJKStart = value.text.unicodeScalars.first.map(SearchTokenization.isCJK) ?? false
        let hasCJKEnd = value.text.unicodeScalars.last.map(SearchTokenization.isCJK) ?? false
        func token(_ character: Character) -> Bool {
            if let ascii = character.asciiValue {
                return (48...57).contains(ascii) || (65...90).contains(ascii)
                    || (97...122).contains(ascii) || ascii == 95
            }
            return character.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || $0 == "_"
            }
        }
        var cursor = text.startIndex
        while cursor < text.endIndex {
            guard var range = text.range(of: needle, options: .literal, range: cursor..<text.endIndex)
            else { return }
            if range.lowerBound.samePosition(in: text) == nil
                || range.upperBound.samePosition(in: text) == nil
            {
                guard let canonical = text.range(of: needle, range: cursor..<text.endIndex) else { return }
                range = canonical
            }
            let leading =
                hasCJKStart || range.lowerBound == text.startIndex
                || !token(text[text.index(before: range.lowerBound)])
            let trailing: Bool
            switch value {
            case .prefix: trailing = true
            case .term, .phrase:
                trailing = hasCJKEnd || range.upperBound == text.endIndex || !token(text[range.upperBound])
            }
            if leading && trailing && !visit(range) { return }
            cursor = range.upperBound
        }
    }
}
