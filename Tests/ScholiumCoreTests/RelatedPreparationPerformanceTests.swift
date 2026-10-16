import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

/// Pure preparation attribution; neither a normal-run test nor a product gate.
@Suite(
    "Related preparation performance", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_RELATED_PREPARATION"] == "1"))
struct RelatedPreparationPerformanceTests {
    /// Keep this exact-source route independent of future production reuse.
    /// The complete wire shape matches RelatedContentSourceProjection.
    private struct Material: Encodable {
        let noteScoringDocument: RelatedContentBM25F.Document
        let paragraphs: [RelatedContentSourceProjection.Paragraph]
    }

    private struct StageTimes {
        var noteScoring = Duration.zero
        var sourceDocument = Duration.zero
        var semantic = Duration.zero
        var readable = Duration.zero
        var normalization = Duration.zero
        var sourceSegments = Duration.zero
        var textIndex = Duration.zero
        var paragraphScoring = Duration.zero
        var paragraphMaterialization = Duration.zero

        var milliseconds: [String: Double] {
            [
                "note_scoring_ms": Self.ms(noteScoring),
                "paragraph_source_document_ms": Self.ms(sourceDocument),
                "snippet_semantic_ms": Self.ms(semantic),
                "readable_rendering_ms": Self.ms(readable),
                "lexical_normalization_ms": Self.ms(normalization),
                "source_segments_ms": Self.ms(sourceSegments),
                "matching_text_index_ms": Self.ms(textIndex),
                "paragraph_scoring_ms": Self.ms(paragraphScoring),
                "paragraph_sharing_signature_ms": Self.ms(paragraphMaterialization),
            ]
        }

        static func ms(_ duration: Duration) -> Double {
            let value = duration.components
            return Double(value.seconds) * 1_000 + Double(value.attoseconds) / 1e15
        }
    }

    private struct ReplicaMeasurement {
        let material: Material
        let stages: StageTimes
        let totalMS: Double
    }

    @Test("Attribute exact 45- and 46-paragraph Related preparation with complete material equality")
    func exactLongNotePreparation() throws {
        // Identical bytes/path/vault identity to insertionPreparationAttribution.
        let unit = String(
            repeating: "Evidence, inference, objection, and source authority. 哲学概念需要精确分析。 ", count: 4)
        let paragraphs = (0..<45).map { "Paragraph \($0): \(unit)" }
        let original =
            "---\nkeywords: [fixture, cluster-0]\nstatus: draft\n---\n# Note 0\n\n"
            + paragraphs.joined(separator: "\n\n")
        let shapes = [
            (label: "original_45", source: original, paragraphCount: 45),
            (label: "changed_46", source: original + "\n\nChanged revision 0.", paragraphCount: 46),
        ]
        let vaultID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let warmups = 3
        let sampleCount = 20
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var shapeReports: [[String: Any]] = []
        for shape in shapes {
            let document = NoteDocument(relativePath: "Note-0.md", rawContent: shape.source)
            let source = SearchIndexDocument(
                vaultID: vaultID, vaultName: "Analyses", vaultRole: .sourceCorpus, document: document)
            let prepared = PreparedSearchIndexDocument(source: source, cache: nil)
            let standalone = try RelatedContentSourceProjection(document: document)
            let expectedBytes = try encoder.encode(standalone)
            let materialSHA = DocumentFingerprint(data: expectedBytes).sha256
            try #require(standalone.paragraphs.count == shape.paragraphCount)
            let sourceBytes = Data(shape.source.utf8)
            #expect(document.sourceBytes == sourceBytes)
            var stageSamples: [String: [Double]] = [:]
            var records: [[String: Any]] = []
            for iteration in 0..<(warmups + sampleCount) {
                try autoreleasepool {
                    let replica: ReplicaMeasurement
                    let production: RelatedContentSourceProjection
                    let productionMS: Double
                    // Alternate constructor order. Both results live through the
                    // oracles; source/Search preparation never enters a timer.
                    if iteration.isMultiple(of: 2) {
                        let start = ContinuousClock.now
                        production = try RelatedContentSourceProjection(prepared: prepared)
                        productionMS = StageTimes.ms(start.duration(to: .now))
                        replica = try measureReplica(prepared)
                    } else {
                        replica = try measureReplica(prepared)
                        let start = ContinuousClock.now
                        production = try RelatedContentSourceProjection(prepared: prepared)
                        productionMS = StageTimes.ms(start.duration(to: .now))
                    }
                    // No encoding, hashes or assertions occur inside timers.
                    let replicaBytes = try encoder.encode(replica.material)
                    let productionBytes = try encoder.encode(production)
                    #expect(replicaBytes == expectedBytes)
                    #expect(productionBytes == expectedBytes)
                    #expect(DocumentFingerprint(data: replicaBytes).sha256 == materialSHA)
                    #expect(DocumentFingerprint(data: productionBytes).sha256 == materialSHA)
                    #expect(replica.material.paragraphs.count == standalone.paragraphs.count)
                    for (actual, expected) in zip(replica.material.paragraphs, standalone.paragraphs) {
                        // Derived readable signatures are omitted from storage.
                        #expect(actual.exactReadableText.utf8.elementsEqual(expected.exactReadableText.utf8))
                        #expect(try encoder.encode(actual.textIndex) == encoder.encode(expected.textIndex))
                    }
                    for (actual, expected) in zip(production.paragraphs, standalone.paragraphs) {
                        #expect(actual.exactReadableText.utf8.elementsEqual(expected.exactReadableText.utf8))
                        #expect(try encoder.encode(actual.textIndex) == encoder.encode(expected.textIndex))
                    }
                    #expect(prepared.source.document.sourceBytes == sourceBytes)
                    #expect(prepared.source.semantic.fingerprint == document.fingerprint)
                    if iteration >= warmups {
                        var timings = replica.stages.milliseconds
                        let stageSum = timings.values.reduce(0, +)
                        timings["replica_stage_sum_ms"] = stageSum
                        timings["replica_total_ms"] = replica.totalMS
                        timings["production_constructor_ms"] = productionMS
                        for (stage, value) in timings { stageSamples[stage, default: []].append(value) }
                        records.append([
                            "sample": iteration - warmups,
                            "first": iteration.isMultiple(of: 2) ? "production" : "replica",
                            "stage_ms": timings,
                        ])
                    }
                }
            }
            shapeReports.append([
                "shape": shape.label, "source_sha256": document.fingerprint.sha256,
                "source_bytes": sourceBytes.count, "source_utf16_count": shape.source.utf16.count,
                "complete_material_sha256": materialSHA, "encoded_material_bytes": expectedBytes.count,
                "paragraph_count": shape.paragraphCount, "sample_count": sampleCount,
                "stage_ms": stageSamples.mapValues(Self.summary), "samples": records,
            ])
        }
        #if DEBUG
            let configuration = "debug"
        #else
            let configuration = "release"
        #endif
        let report: [String: Any] = [
            "schema": "scholium-related-preparation-attribution-v1",
            "build_configuration": configuration,
            "contract_version": SearchContract.currentVersion,
            "ranking_policy_version": SearchContract.rankingPolicyVersion,
            "warmup_count": warmups, "retained_sample_count": sampleCount,
            "fixture": "search-sync-433-note-zero-original-and-revision-zero",
            "measurement":
                "Exact source-bound Related constructor only; excludes source/Search preparation, encoding, hashing, assertions, I/O, SQLite/FTS and native publication.",
            "sampling":
                "Three warmups and twenty retained samples per shape; production and replica constructor order alternates. Stage durations sum over every admitted nested paragraph.",
            "replica_overhead":
                "Replica total includes stage clock reads, duration accumulation, loop and cancellation overhead; it is not additive to its stages. A small replica/production difference is not an optimization.",
            "oracle":
                "Complete sorted-key encoded material and SHA match the standalone constructor outside all timers; derived exact readable bytes and independent matching indexes also match.",
            "shapes": shapeReports,
        ]
        let bytes = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        // stdout and Swift Testing status output can interleave. Keep an atomic
        // artifact as the machine-readable source of truth for opt-in samples.
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/related-preparation-diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let reportURL = output.appendingPathComponent("related-\(UUID().uuidString.lowercased()).json")
        try bytes.write(to: reportURL, options: .atomic)
        print("RELATED_PREPARATION_DIAGNOSTIC \(String(decoding: bytes, as: UTF8.self))")
    }

    private func measureReplica(_ prepared: PreparedSearchIndexDocument) throws -> ReplicaMeasurement {
        let totalStart = ContinuousClock.now
        try Task.checkCancellation()
        let document = prepared.source.document
        let semantic = prepared.source.semantic
        var times = StageTimes()
        let noteStart = ContinuousClock.now
        let noteScoring = RelatedContentBM25F.Document(segments: prepared.projection.segments)
        times.noteScoring = noteStart.duration(to: .now)
        var paragraphs: [RelatedContentSourceProjection.Paragraph] = []
        for block in semantic.blocks where block.kind == .paragraph {
            try Task.checkCancellation()
            let sourceStart = ContinuousClock.now
            guard block.span.utf16Range.count <= RelatedContentContract.maximumPassageUTF16Count,
                let range = Range(block.span.nsRange, in: document.rawContent)
            else {
                times.sourceDocument += sourceStart.duration(to: .now)
                continue
            }
            let exact = String(document.rawContent[range])
            let snippet = NoteDocument(relativePath: document.relativePath, rawContent: exact)
            times.sourceDocument += sourceStart.duration(to: .now)
            let semanticStart = ContinuousClock.now
            let snippetSemantic = MarkdownSemanticDocument(parsing: snippet)
            times.semantic += semanticStart.duration(to: .now)
            let readableStart = ContinuousClock.now
            let display = ResearchExcerptPresentation.readableText(
                document: snippet, semantic: snippetSemantic, includingAnnotations: true)
            times.readable += readableStart.duration(to: .now)
            let normalizeStart = ContinuousClock.now
            let normalized = SearchTextNormalization.lexicalNormalize(display)
            times.normalization += normalizeStart.duration(to: .now)
            try Task.checkCancellation()
            let segmentsStart = ContinuousClock.now
            let segments = SearchDocumentProjection.sourceSegments(document: snippet, semantic: snippetSemantic).filter {
                $0.sourceRange != nil && $0.field != .title && $0.field != .alias
            }
            times.sourceSegments += segmentsStart.duration(to: .now)
            // Preserve production argument evaluation: matching index, scoring,
            // then Paragraph's sharing/signature and original source locator.
            let indexStart = ContinuousClock.now
            let textIndex = RelatedContentTextIndex(normalized)
            times.textIndex += indexStart.duration(to: .now)
            let scoringStart = ContinuousClock.now
            let scoring = RelatedContentBM25F.Document(segments: segments)
            times.paragraphScoring += scoringStart.duration(to: .now)
            let materialStart = ContinuousClock.now
            paragraphs.append(
                .init(
                    range: .init(
                        utf16LowerBound: block.span.utf16LowerBound, utf16UpperBound: block.span.utf16UpperBound,
                        line: block.span.start.line, column: block.span.start.utf16Column,
                        endLine: block.span.end.line, endColumn: block.span.end.utf16Column),
                    displayText: display, normalizedDisplayText: normalized,
                    textIndex: textIndex, scoringDocument: scoring))
            times.paragraphMaterialization += materialStart.duration(to: .now)
        }
        try Task.checkCancellation()
        let material = Material(noteScoringDocument: noteScoring, paragraphs: paragraphs)
        let totalMS = StageTimes.ms(totalStart.duration(to: .now))
        return .init(material: material, stages: times, totalMS: totalMS)
    }

    private static func summary(_ samples: [Double]) -> [String: Double] {
        let sorted = samples.sorted()
        let middle = sorted.count / 2
        return [
            "min": sorted[0], "median": (sorted[middle - 1] + sorted[middle]) / 2,
            "p95": sorted[max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)], "max": sorted[sorted.count - 1],
        ]
    }
}
