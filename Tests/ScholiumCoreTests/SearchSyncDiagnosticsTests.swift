import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

/// Opt-in diagnostic evidence; these measurements do not establish a release gate.
@Suite(
    "Search synchronization diagnostics", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_SEARCH_SYNC_DIAGNOSTIC"] == "1"))
struct SearchSyncDiagnosticsTests {
    @Test("Compare exact paragraph serialization with the existing lossless offset codec")
    func paragraphStorageSerialization() throws {
        let paragraph = String(
            repeating: "Evidence, inference, objection, and source authority. 哲学概念需要精确分析。 ", count: 4)
        let body = (0..<45).map { "Paragraph \($0): \(paragraph)" }.joined(separator: "\n\n")
        let projection = SearchDocumentProjection(
            document: NoteDocument(relativePath: "Codec.md", rawContent: body))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for sample in 0..<5 {
            let verboseStart = ContinuousClock.now
            let verbose = try encoder.encode(projection.paragraphs)
            let verboseMS = milliseconds(verboseStart.duration(to: .now))
            let compactStart = ContinuousClock.now
            let compact = try TriptychSearchIndex.encodedParagraphs(projection.paragraphs)
            let compactMS = milliseconds(compactStart.duration(to: .now))
            let verboseDecodeStart = ContinuousClock.now
            let original = try JSONDecoder().decode([SearchParagraphProjection].self, from: verbose)
            let verboseDecodeMS = milliseconds(verboseDecodeStart.duration(to: .now))
            let compactDecodeStart = ContinuousClock.now
            let decoded = try TriptychSearchIndex.decodedStoredParagraphs(
                from: compact)
            let compactDecodeMS = milliseconds(compactDecodeStart.duration(to: .now))
            #expect(original == projection.paragraphs)
            #expect(decoded == projection.paragraphs)
            print(
                "PARAGRAPH_STORAGE_DIAGNOSTIC sample=\(sample) verbose_bytes=\(verbose.count) compact_bytes=\(compact.count) verbose_encode_ms=\(verboseMS) compact_encode_ms=\(compactMS) verbose_decode_ms=\(verboseDecodeMS) compact_decode_ms=\(compactDecodeMS)"
            )
        }
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let value = duration.components
        return Double(value.seconds) * 1_000 + Double(value.attoseconds) / 1e15
    }

    @Test(
        "Record cold, reopened, repeated, and one-note publication over 433 long mixed-script Notes")
    func longNoteSynchronization() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(
            ".build/search-sync-diagnostics/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let vaults = [
            RegisteredVault(
                name: "Analyses", role: .sourceCorpus,
                canonicalPath: root.appendingPathComponent("analyses").path),
            RegisteredVault(
                name: "Topics", role: .topicKnowledge,
                canonicalPath: root.appendingPathComponent("topics").path),
            RegisteredVault(
                name: "Works", role: .draftProject, canonicalPath: root.appendingPathComponent("works").path
            ),
        ]
        let paragraph = String(
            repeating: "Evidence, inference, objection, and source authority. 哲学概念需要精确分析。 ", count: 4)
        let body = (0..<45).map { "Paragraph \($0): \(paragraph)" }.joined(separator: "\n\n")
        var documents = (0..<433).map { number in
            let vault = vaults[number % 3]
            return SearchIndexDocument(
                vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role,
                document: NoteDocument(
                    relativePath: "Note-\(number).md",
                    rawContent:
                        "---\nkeywords: [fixture, cluster-\(number % 7)]\nstatus: draft\n---\n# Note \(number)\n\n\(body)"
                ))
        }
        let totalBytes = documents.reduce(0) { $0 + $1.document.fingerprint.byteCount }
        let totalSegments = documents.reduce(0) {
            $0 + SearchDocumentProjection(document: $1.document, semantic: $1.semantic).segments.count
        }
        print(
            "SEARCH_SYNC_DIAGNOSTIC fixture notes=\(documents.count) bytes=\(totalBytes) segments=\(totalSegments)"
        )
        for sample in 0..<3 {
            let triptychID = UUID()
            let url = root.appendingPathComponent("sample-\(sample).sqlite")
            let cold = try TriptychSearchIndex(isolatedDatabaseURL: url, triptychID: triptychID, vaults: vaults)
            let initial = try await cold.synchronize(documents)
            #expect(initial.disposition == .rebuilt)
            try await report(cold, scenario: "cold", sample: sample, expectedChanged: documents.count)
            let reopened = try TriptychSearchIndex(
                isolatedDatabaseURL: url, triptychID: triptychID, vaults: vaults)
            let unchanged = try await reopened.synchronize(documents)
            #expect(unchanged.disposition == .unchanged)
            #expect(unchanged.generation == initial.generation)
            try await report(reopened, scenario: "reopened", sample: sample, expectedChanged: 0)
            let repeated = try await reopened.synchronize(documents)
            #expect(repeated.disposition == .unchanged)
            #expect(repeated.generation == initial.generation)
            try await report(reopened, scenario: "repeated", sample: sample, expectedChanged: 0)
            let request = SearchRequest(
                query: "changed", presentationScope: .triptych, executionScope: .triptych, limit: 50)
            #expect(try await reopened.testSearch(request).results.isEmpty)
            let original = documents[0]
            documents[0] = SearchIndexDocument(
                vaultID: original.vaultID, vaultName: original.vaultName,
                vaultRole: original.vaultRole,
                document: NoteDocument(
                    relativePath: original.relativePath,
                    rawContent: original.document.rawContent + "\n\nChanged revision \(sample)."))
            let changed = try await reopened.synchronize(documents)
            #expect(changed.disposition == .incrementallyUpdated)
            #expect(changed.generation.sequence > initial.generation.sequence)
            #expect(changed.generation.sourceManifestHash != initial.generation.sourceManifestHash)
            try await report(reopened, scenario: "one_note", sample: sample, expectedChanged: 1)
            // Timed publication ends before this oracle queries the exact changed
            // revision. A formerly cached empty query must see the new generation.
            let response = try await reopened.testSearch(request)
            #expect(response.noteResults.map(\.relativePath) == [original.relativePath])
            #expect(response.freshnessToken == .triptych(changed.generation))
            let result = try #require(response.noteResults.first)
            #expect(result.fingerprint == documents[0].document.fingerprint)
            #expect(result.vaultID == original.vaultID && result.vaultRole == original.vaultRole)
            let locator = try #require(result.sourceRange)
            let range = try #require(
                Range(
                    NSRange(location: locator.utf16LowerBound, length: locator.utf16UpperBound - locator.utf16LowerBound),
                    in: documents[0].document.rawContent))
            #expect(String(documents[0].document.rawContent[range]).localizedCaseInsensitiveContains("changed"))
            documents[0] = original
        }
    }

    @Test("Attribute insertion preparation for the exact 45- and 46-paragraph long-Note shapes")
    func insertionPreparationAttribution() throws {
        let paragraph = String(
            repeating: "Evidence, inference, objection, and source authority. 哲学概念需要精确分析。 ", count: 4)
        let paragraphs = (0..<45).map { "Paragraph \($0): \(paragraph)" }
        let original =
            "---\nkeywords: [fixture, cluster-0]\nstatus: draft\n---\n# Note 0\n\n"
            + paragraphs.joined(separator: "\n\n")
        let vaultID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let shapes = [
            (label: "original_45", text: original, paragraphs: paragraphs),
            (label: "changed_46", text: original + "\n\nChanged revision 0.", paragraphs: paragraphs + ["Changed revision 0."]),
        ]
        let warmups = 3
        let sampleCount = 20
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var shapeReports: [[String: Any]] = []
        for shape in shapes {
            let document = NoteDocument(relativePath: "Note-0.md", rawContent: shape.text)
            // The synchronization fixture constructs this semantic value before
            // publication. Keep the same boundary here; no source cache is supplied.
            let source = SearchIndexDocument(
                vaultID: vaultID, vaultName: "Analyses", vaultRole: .sourceCorpus, document: document)
            // The unchanged standalone constructor is an independent preparation
            // reference. Its complete material is checked outside every timer.
            let standaloneRelatedBytes = try encoder.encode(RelatedContentSourceProjection(document: document))
            let sourceUnits = Array(document.rawContent.utf16)
            let lineStarts = [0] + sourceUnits.indices.filter { sourceUnits[$0] == 10 }.map { $0 + 1 }
            func validateCoordinate(_ locator: SearchSourceRange) throws -> String {
                let range = try #require(
                    Range(
                        NSRange(location: locator.utf16LowerBound, length: locator.utf16UpperBound - locator.utf16LowerBound),
                        in: document.rawContent))
                let startLine = try #require(lineStarts.lastIndex { $0 <= locator.utf16LowerBound })
                let endLine = try #require(lineStarts.lastIndex { $0 <= locator.utf16UpperBound })
                #expect(locator.line == startLine + 1 && locator.endLine == endLine + 1)
                #expect(locator.column == locator.utf16LowerBound - lineStarts[startLine] + 1)
                #expect(locator.endColumn == locator.utf16UpperBound - lineStarts[endLine] + 1)
                return String(document.rawContent[range])
            }
            var records: [[String: Any]] = []
            var stageSamples: [String: [Double]] = [:]
            var baselineDigests: [String: String]?
            var byteCounts: [String: Int] = [:]
            for iteration in 0..<(warmups + sampleCount) {
                let preparedStart = ContinuousClock.now
                let prepared = PreparedSearchIndexDocument(source: source, cache: nil)
                let preparedMS = milliseconds(preparedStart.duration(to: .now))
                let relatedStart = ContinuousClock.now
                let related = try RelatedContentSourceProjection(prepared: prepared)
                let relatedMS = milliseconds(relatedStart.duration(to: .now))
                let relatedEncodeStart = ContinuousClock.now
                let relatedBytes = try related.encoded()
                let relatedEncodeMS = milliseconds(relatedEncodeStart.duration(to: .now))
                let lexicalStart = ContinuousClock.now
                let lexical = RelatedContentLexicalProjection(
                    projection: prepared.projection, scoringDocument: related.noteScoringDocument)
                let lexicalMS = milliseconds(lexicalStart.duration(to: .now))
                let lexicalEncodeStart = ContinuousClock.now
                let lexicalBytes = try lexical.encoded()
                let lexicalEncodeMS = milliseconds(lexicalEncodeStart.duration(to: .now))
                let paragraphEncodeStart = ContinuousClock.now
                let paragraphBytes = try TriptychSearchIndex.encodedParagraphs(prepared.projection.paragraphs)
                let paragraphEncodeMS = milliseconds(paragraphEncodeStart.duration(to: .now))
                let offsetEncodeStart = ContinuousClock.now
                let offsetBytes = try prepared.projection.segments.map { try SearchOffsetMapCodec.encode($0.offsetMap) }
                let offsetEncodeMS = milliseconds(offsetEncodeStart.duration(to: .now))
                // All seven groups end before decoding, hashing, coordinates or
                // assertions. Retain every constructed/encoded result through these
                // independent fidelity checks; no database or runtime is involved.
                #expect(try encoder.encode(related) == standaloneRelatedBytes)
                #expect(prepared.source.document.fingerprint == document.fingerprint)
                #expect(prepared.preparation.projectedDocuments == 1 && prepared.preparation.restoredSearchProjections == 0)
                try #require(prepared.projection.paragraphs.count == shape.paragraphs.count)
                try #require(related.paragraphs.count == shape.paragraphs.count)
                let decodedRelated = try RelatedContentSourceProjection.decode(
                    relatedBytes, checksum: RelatedContentSourceProjection.checksum(relatedBytes),
                    sourceUTF16Count: sourceUnits.count)
                let decodedLexical = try RelatedContentLexicalProjection.decode(
                    lexicalBytes, checksum: RelatedContentSourceProjection.checksum(lexicalBytes))
                #expect(try encoder.encode(decodedRelated) == encoder.encode(related))
                #expect(try encoder.encode(decodedLexical) == encoder.encode(lexical))
                #expect(decodedRelated.paragraphs.map(\.exactReadableText) == related.paragraphs.map(\.exactReadableText))
                let decodedParagraphs = try TriptychSearchIndex.decodedStoredParagraphs(
                    from: paragraphBytes)
                #expect(decodedParagraphs == prepared.projection.paragraphs)
                for (index, value) in related.paragraphs.enumerated() {
                    let exact = try validateCoordinate(value.range)
                    #expect(exact.trimmingCharacters(in: .whitespacesAndNewlines) == shape.paragraphs[index].trimmingCharacters(in: .whitespacesAndNewlines))
                }
                for (index, value) in prepared.projection.paragraphs.enumerated() {
                    let exact = try validateCoordinate(value.range)
                    #expect(exact.trimmingCharacters(in: .whitespacesAndNewlines) == shape.paragraphs[index].trimmingCharacters(in: .whitespacesAndNewlines))
                }
                for (segment, bytes) in zip(prepared.projection.segments, offsetBytes) {
                    #expect(try SearchOffsetMapCodec.decode(bytes) == segment.offsetMap)
                    try SearchOffsetMapCodec.validate(
                        bytes, normalizedUTF16Count: segment.normalizedText.utf16.count,
                        sourceUTF16Bounds: segment.sourceRange.map { (lower: $0.utf16LowerBound, upper: $0.utf16UpperBound) },
                        sourceUTF16Count: sourceUnits.count)
                    if let range = segment.sourceRange { _ = try validateCoordinate(range) }
                }
                let projectionBytes = try encoder.encode(prepared.projection)
                #expect(try JSONDecoder().decode(SearchDocumentProjection.self, from: projectionBytes) == prepared.projection)
                let entryBytes = try encoder.encode(prepared.properties.entries)
                let issueBytes = try encoder.encode(prepared.properties.issues)
                #expect(try JSONDecoder().decode([SearchPropertyProjection.Entry].self, from: entryBytes) == prepared.properties.entries)
                #expect(try JSONDecoder().decode([SearchPropertyProjection.Issue].self, from: issueBytes) == prepared.properties.issues)
                let digests = [
                    "search_projection": DocumentFingerprint(data: projectionBytes).sha256,
                    "property_entries": DocumentFingerprint(data: entryBytes).sha256,
                    "property_issues": DocumentFingerprint(data: issueBytes).sha256,
                    "related_source": DocumentFingerprint(data: try encoder.encode(related)).sha256,
                    "related_lexical": DocumentFingerprint(data: try encoder.encode(lexical)).sha256,
                    "paragraph_material": DocumentFingerprint(data: try encoder.encode(decodedParagraphs)).sha256,
                    "segment_offset_material": DocumentFingerprint(data: try encoder.encode(prepared.projection.segments.map(\.offsetMap))).sha256,
                ]
                if let baselineDigests { #expect(digests == baselineDigests) } else { baselineDigests = digests }
                byteCounts = [
                    "related_source": relatedBytes.count, "related_lexical": lexicalBytes.count,
                    "paragraph_storage": paragraphBytes.count, "segment_offset_storage": offsetBytes.reduce(0) { $0 + $1.count },
                ]
                if iteration >= warmups {
                    let timings = [
                        "prepared_search_ms": preparedMS, "related_source_construction_ms": relatedMS,
                        "related_source_encoding_ms": relatedEncodeMS, "related_lexical_construction_ms": lexicalMS,
                        "related_lexical_encoding_ms": lexicalEncodeMS, "paragraph_encoding_ms": paragraphEncodeMS,
                        "segment_offsets_encoding_ms": offsetEncodeMS,
                    ]
                    for (stage, duration) in timings { stageSamples[stage, default: []].append(duration) }
                    records.append(["sample": iteration - warmups, "stage_ms": timings])
                }
            }
            let summaries = stageSamples.mapValues { samples in
                let sorted = samples.sorted()
                let middle = sorted.count / 2
                return [
                    "min": sorted[0], "median": (sorted[middle - 1] + sorted[middle]) / 2,
                    "p95": sorted[max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)], "max": sorted[sorted.count - 1],
                ]
            }
            shapeReports.append([
                "shape": shape.label, "source_sha256": document.fingerprint.sha256,
                "source_bytes": document.fingerprint.byteCount, "source_utf16_count": sourceUnits.count,
                "paragraph_count": shape.paragraphs.count, "sample_count": sampleCount,
                "complete_material_sha256": try #require(baselineDigests), "encoded_bytes": byteCounts,
                "stage_ms": summaries, "samples": records,
            ])
        }
        #if DEBUG
            let configuration = "debug"
        #else
            let configuration = "release"
        #endif
        let report: [String: Any] = [
            "artifact_schema": "scholium-search-insertion-preparation-attribution-v1",
            "related_source_constructor": "exact-source-semantic-reuse",
            "build_configuration": configuration, "contract_version": SearchContract.currentVersion,
            "ranking_policy_version": SearchContract.rankingPolicyVersion,
            "operating_system": ProcessInfo.processInfo.operatingSystemVersionString,
            "fixture": "search-sync-433-note-zero-original-and-revision-zero", "warmup_count": warmups,
            "measurement":
                "Seven pure constructor/codec groups; excludes source construction, source I/O, SQLite/FTS, transaction validation/commit and native publication. Group sums do not measure publication wall time.",
            "sampling": "Three warmups and twenty retained iterations per exact source shape; stages run in fixed insertion order and shapes are not pooled.",
            "oracle":
                "Canonical complete material digests stable across iterations; all encoded outputs round-trip; exact generated paragraph slices, UTF-16 ranges and line/column coordinates checked outside timing.",
            "shapes": shapeReports,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        print("SEARCH_INSERTION_PREPARATION_DIAGNOSTIC \(String(decoding: data, as: UTF8.self))")
    }

    private func report(
        _ index: TriptychSearchIndex, scenario: String, sample: Int, expectedChanged: Int
    ) async throws {
        let timing = try #require(await index.lastSynchronizationTimings)
        #expect(timing.documentCount == 433)
        #expect(timing.changedCount == expectedChanged)
        // Projection/cache work durations are existing accumulated component work
        // within publication, not independent wall-clock stages to add to it.
        print(
            "SEARCH_SYNC_DIAGNOSTIC sample=\(sample) scenario=\(scenario) preparation_ms=\(timing.preparationMilliseconds) publication_ms=\(timing.publicationMilliseconds) projection_work_ms=\(milliseconds(timing.projectionDuration)) cache_read_work_ms=\(milliseconds(timing.cacheReadDuration)) cache_write_work_ms=\(milliseconds(timing.cacheWriteDuration)) changed=\(timing.changedCount) projected=\(timing.projectedDocuments) restored=\(timing.restoredSearchProjections)"
        )
    }
}
