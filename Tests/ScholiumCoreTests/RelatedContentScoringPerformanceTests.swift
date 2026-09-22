import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

/// Opt-in scorer diagnostics on prepared paragraphs, not retrieval or native latency.
@Suite(
    "Related-content scoring performance", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_RELATED_CONTENT_SCORING"] == "1"))
struct RelatedContentScoringPerformanceTests {
    private struct Checksum: Codable, Equatable {
        let scores: Double
        let coverage: Double
        let distinctive: Int

        init(_ evaluation: RelatedContentBM25F.Evaluation) {
            // Position weights detect reordered results as well as changed totals.
            scores = evaluation.scores.enumerated().reduce(0.0) { $0 + Double($1.offset + 1) * $1.element }
            coverage = evaluation.coverage.enumerated().reduce(0.0) { $0 + Double($1.offset + 1) * $1.element }
            distinctive = evaluation.hasDistinctiveMatch.enumerated().reduce(0) { $0 + ($1.element ? $1.offset + 1 : 0) }
        }
    }

    private struct Sample: Encodable {
        let seconds: Double
        let checksum: Checksum
        let orderedResultSHA256: String
    }

    private struct Scenario: Encodable {
        let termCount: Int
        let warmupCount: Int
        let sampleCount: Int
        let minimumSeconds: Double
        let medianSeconds: Double
        let maximumSeconds: Double
        let samples: [Sample]
    }

    private struct Report: Encodable {
        let schemaVersion = 1
        let fixtureVersion = 1
        let documentCount = 8_000
        let bodyOnlyCount = 2_000
        let bodyAndAnnotationCount = 2_000
        let annotationOnlyCount = 2_000
        let bodyAndEmptyAnnotationCount = 2_000
        let roleCounts: [String: Int]
        let buildConfiguration: String
        let osVersion: String
        let processorCount: Int
        let physicalMemoryBytes: UInt64
        let measurement =
            "Prepared BM25F.evaluate only; document preparation, checksums, assertions and report encoding excluded. Two warmups and five measured calls per workload; no percentile or native end-to-end claim."
        let oracle =
            "Position-weighted scalar checksums plus SHA256 of ordered score/coverage bit patterns and distinctive flags. Every repeated evaluation must equal the first warmup exactly. Compare before/after reports for behavior preservation; equality within one run alone cannot establish it."
        let scenarios: [Scenario]
    }

    @Test("Prepared 8000-paragraph scoring preserves exact results for 3 and 32 terms")
    func preparedParagraphs() throws {
        let documentCount = 8_000
        let warmupCount = 2
        let sampleCount = 5
        let vocabulary = (0..<32).map { "focusword\($0)" }
        let roleCycle: [VaultRole] = [.sourceCorpus, .topicKnowledge, .draftProject]
        var documents: [RelatedContentBM25F.Document] = []
        var roles: [VaultRole] = []
        var roleCounts: [String: Int] = [:]
        documents.reserveCapacity(documentCount)
        roles.reserveCapacity(documentCount)

        // Prepare all normalized fields, lengths and text indexes outside timing.
        // Field occupancy and role cycle are independent. Variable lengths and
        // frequencies exercise normalization, shared df, and repeated occurrences.
        // The 32nd query term is deliberately absent from the whole collection.
        for ordinal in 0..<documentCount {
            var body = String(repeating: "background context ", count: 1 + ordinal % 12)
            body += String(repeating: vocabulary[ordinal % 31] + " ", count: 1 + ordinal % 4)
            if ordinal.isMultiple(of: 2) { body += vocabulary[0] + " " }
            if ordinal.isMultiple(of: 3) { body += vocabulary[1] + " " }
            if ordinal.isMultiple(of: 37) { body += vocabulary[2] + " " }
            let annotation =
                "authored annotation context "
                + String(repeating: vocabulary[(ordinal * 7 + 3) % 31] + " ", count: 1 + ordinal % 3)
            let fields: [String: String]
            switch ordinal % 4 {
            case 0: fields = ["body": body]
            case 1: fields = ["body": body, "annotation": annotation]
            case 2: fields = ["annotation": annotation]
            default: fields = ["body": body, "annotation": ""]
            }
            documents.append(
                .init(segments: [
                    .init(
                        field: .body, ordinal: 0, text: "", normalizedText: "", sourceRange: nil,
                        offsetMap: [], relatedRankingText: fields)
                ]))
            let role = roleCycle[ordinal % roleCycle.count]
            roles.append(role)
            roleCounts[role.rawValue, default: 0] += 1
        }
        #expect(documents.allSatisfy { $0.isValid })

        var scenarios: [Scenario] = []
        for termCount in [3, 32] {
            let terms = Array(vocabulary.prefix(termCount))
            let expected = try RelatedContentBM25F.evaluate(documents: documents, terms: terms, roles: roles)
            let expectedChecksum = Checksum(expected)
            #expect(expected.scores.count == documentCount)
            #expect(expected.coverage.count == documentCount)
            #expect(expected.hasDistinctiveMatch.count == documentCount)
            #expect(expected.scores.allSatisfy { $0.isFinite && $0 >= 0 })
            #expect(expected.coverage.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 + 1e-12 })
            #expect(expectedChecksum.scores > 0)
            #expect(expectedChecksum.coverage > 0)
            #expect(expectedChecksum.distinctive > 0)
            for _ in 1..<warmupCount {
                let result = try RelatedContentBM25F.evaluate(documents: documents, terms: terms, roles: roles)
                try requireExact(result, expected)
            }

            var samples: [Sample] = []
            for _ in 0..<sampleCount {
                let started = ContinuousClock.now
                let result = try RelatedContentBM25F.evaluate(documents: documents, terms: terms, roles: roles)
                let elapsed = started.duration(to: .now).components
                let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                // Consume all outputs after stopping the clock; no source/query is emitted.
                try requireExact(result, expected)
                let checksum = Checksum(result)
                #expect(checksum == expectedChecksum)
                samples.append(.init(seconds: seconds, checksum: checksum, orderedResultSHA256: orderedDigest(result)))
            }
            let durations = samples.map(\.seconds).sorted()
            let scenario = Scenario(
                termCount: termCount, warmupCount: warmupCount, sampleCount: sampleCount,
                minimumSeconds: durations[0], medianSeconds: durations[sampleCount / 2],
                maximumSeconds: durations[sampleCount - 1], samples: samples)
            scenarios.append(scenario)
            print(
                "BM25F prepared paragraphs: documents=\(documentCount) terms=\(termCount) "
                    + "samples=\(sampleCount) seconds min/median/max="
                    + "\(scenario.minimumSeconds)/\(scenario.medianSeconds)/\(scenario.maximumSeconds) "
                    + "scoreChecksum=\(expectedChecksum.scores) coverageChecksum=\(expectedChecksum.coverage) "
                    + "distinctiveChecksum=\(expectedChecksum.distinctive)")
        }

        #if DEBUG
            let configuration = "debug"
        #else
            let configuration = "release"
        #endif
        let process = ProcessInfo.processInfo
        let report = Report(
            roleCounts: roleCounts, buildConfiguration: configuration,
            osVersion: process.operatingSystemVersionString, processorCount: process.processorCount,
            physicalMemoryBytes: process.physicalMemory, scenarios: scenarios)
        let label = process.environment["SCHOLIUM_SCORING_MEASUREMENT_LABEL"] ?? "diagnostic"
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        try #require(!label.isEmpty && label.allSatisfy { allowed.contains($0) })
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = repository.appendingPathComponent(".build/retrieval-optimization", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: directory.appendingPathComponent("\(label)-8000.json"), options: .atomic)
    }

    private func requireExact(_ actual: RelatedContentBM25F.Evaluation, _ expected: RelatedContentBM25F.Evaluation) throws {
        // Keep failures bounded rather than printing thousands of scalar values.
        let scoresMatch = actual.scores == expected.scores
        let coverageMatches = actual.coverage == expected.coverage
        let distinctiveMatches = actual.hasDistinctiveMatch == expected.hasDistinctiveMatch
        try #require(scoresMatch)
        try #require(coverageMatches)
        try #require(distinctiveMatches)
    }

    private func orderedDigest(_ evaluation: RelatedContentBM25F.Evaluation) -> String {
        // Fixed-width big-endian bit patterns avoid JSON floating-point formatting
        // or scalar checksum collisions obscuring a before/after output change.
        var bytes = Data()
        bytes.reserveCapacity(evaluation.scores.count * 17)
        for index in evaluation.scores.indices {
            for value in [evaluation.scores[index], evaluation.coverage[index]] {
                var bits = value.bitPattern.bigEndian
                withUnsafeBytes(of: &bits) { bytes.append(contentsOf: $0) }
            }
            bytes.append(evaluation.hasDistinctiveMatch[index] ? 1 : 0)
        }
        return DocumentFingerprint(data: bytes).sha256
    }
}
