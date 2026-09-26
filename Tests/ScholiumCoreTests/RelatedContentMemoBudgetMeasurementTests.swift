import Darwin
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

/// Opt-in retained-heap and decode/ranking measurements. Payloads are already
/// in memory, so this is neither SQLite latency nor UI or peak-memory evidence.
@Suite(
    "Related-content memo budget measurement", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_RELATED_MEMO_BUDGET"] == "1"))
struct RelatedContentMemoBudgetMeasurementTests {
    private struct Payload {
        let data: Data
        let checksum: String
    }

    private struct Sample: Codable {
        let fixture: String
        let repetition: Int
        let budgetMiB: Int
        let scan: Int
        let elapsedMilliseconds: Double
        let decodedProjections: Int
        let hits: Int
        let evictions: Int
        let protectedAdmissionSkips: Int
        let memoEntries: Int
        let memoEstimatedBytes: Int
        let allocatorDeltaBytes: Int
        let orderedPassages: [String]
    }

    private struct FixtureReport: Codable {
        let name: String
        let noteCount: Int
        let sourceBytes: Int
        let encodedProjectionBytes: Int
        let samples: [Sample]
    }

    @Test("Compare 64, 24 and 16 MiB with complete repeated candidate scans")
    func completeCandidateScans() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixtureRoot = repository.appendingPathComponent("TestVaults", isDirectory: true)
        var reports: [FixtureReport] = []
        for stress in [false, true] {
            let name = stress ? "standard-500-plus-512-words" : "standard-500"
            let sources = try fixtureSources(root: fixtureRoot, stress: stress)
            #expect(sources.count == 500)
            let payloads = try Dictionary(
                uniqueKeysWithValues: sources.map { source in
                    try autoreleasepool {
                        let data = try RelatedContentSourceProjection(document: source.document).encoded()
                        return (source.candidate.note, Payload(data: data, checksum: RelatedContentSourceProjection.checksum(data)))
                    }
                })
            let focus = "aurora-fixture"
            let request = RelatedContentRequest(
                seed: .init(
                    noteID: .init(vaultID: UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!, relativePath: "Seed.md"),
                    source: focus, focuses: [.init(kind: .selectedPassage, text: focus)]))
            // Initialize decoder and ranking infrastructure before measuring
            // each budget; every measured memo still begins empty.
            _ = try autoreleasepool {
                try TriptychSearchIndex.rankRelatedPassages(request, sources: Array(sources.prefix(1))) { source in
                    let payload = payloads[source.candidate.note]!
                    return try RelatedContentSourceProjection.decode(
                        payload.data, checksum: payload.checksum, sourceUTF16Count: source.document.rawContent.utf16.count)
                }
            }
            print("Memo budget fixture \(name): notes=\(sources.count) sourceBytes=\(sources.reduce(0) { $0 + $1.document.sourceBytes.count })")
            var samples: [Sample] = []
            var expected: [RelatedContentPassage]?
            // Rotate budget order to expose ordinary allocator/thermal drift.
            for (repetition, budgets) in [[64, 24, 16], [24, 16, 64], [16, 64, 24]].enumerated() {
                for budget in budgets {
                    var memo = RelatedContentSourceProjectionMemo(maximumByteCount: budget * 1_024 * 1_024)
                    let baseline = allocatedBytes()
                    for scan in 0..<4 {
                        let before = memo.statistics
                        var decoded = 0
                        let started = DispatchTime.now().uptimeNanoseconds
                        let results = try autoreleasepool {
                            let protection = memo.scanProtection(for: sources)
                            return try TriptychSearchIndex.rankRelatedPassages(request, sources: sources) { source in
                                try memo.projection(for: source, protection: protection) { document in
                                    decoded += 1
                                    let payload = payloads[source.candidate.note]!
                                    return try RelatedContentSourceProjection.decode(
                                        payload.data, checksum: payload.checksum, sourceUTF16Count: document.rawContent.utf16.count)
                                }
                            }
                        }
                        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
                        let retainedBytes = allocatedBytes() - baseline
                        if let expected { #expect(results == expected) } else { expected = results }
                        #expect(!results.isEmpty)
                        #expect(memo.statistics.hits - before.hits + decoded == sources.count)
                        #expect(decoded == memo.statistics.misses - before.misses)
                        #expect(memo.estimatedByteCount <= memo.maximumByteCount)
                        let sample = Sample(
                            fixture: name, repetition: repetition, budgetMiB: budget, scan: scan,
                            elapsedMilliseconds: elapsed, decodedProjections: decoded,
                            hits: memo.statistics.hits - before.hits,
                            evictions: memo.statistics.evictions - before.evictions,
                            protectedAdmissionSkips: memo.statistics.protectedAdmissionSkips - before.protectedAdmissionSkips,
                            memoEntries: memo.entryCount, memoEstimatedBytes: memo.estimatedByteCount,
                            allocatorDeltaBytes: retainedBytes,
                            orderedPassages: results.map {
                                "\($0.candidate.note.vaultID.uuidString)/\($0.candidate.note.relativePath):\($0.range.utf16LowerBound)-\($0.range.utf16UpperBound)"
                            })
                        samples.append(sample)
                        print(
                            "Memo budget \(name) repeat=\(repetition) MiB=\(budget) scan=\(scan) "
                                + "ms=\(String(format: "%.2f", elapsed)) decoded=\(decoded) "
                                + "entries=\(memo.entryCount) estimated=\(memo.estimatedByteCount) allocatorDelta=\(retainedBytes)")
                    }
                    withExtendedLifetime(memo) {}
                }
            }
            reports.append(
                .init(
                    name: name, noteCount: sources.count,
                    sourceBytes: sources.reduce(0) { $0 + $1.document.sourceBytes.count },
                    encodedProjectionBytes: payloads.values.reduce(0) { $0 + $1.data.count }, samples: samples))
        }
        let destination = repository.appendingPathComponent(".build/memory-deep", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(reports).write(to: destination.appendingPathComponent("related-memo-budgets.json"), options: .atomic)
    }

    private func fixtureSources(root: URL, stress: Bool) throws -> [RelatedContentSource] {
        let vaults: [(String, VaultRole, String)] = [
            ("01-analyses", .sourceCorpus, "00000000-0000-0000-0000-000000000001"),
            ("02-topics", .topicKnowledge, "00000000-0000-0000-0000-000000000002"),
            ("03-works", .draftProject, "00000000-0000-0000-0000-000000000003"),
        ]
        let addition =
            "\n\n"
            + (0..<2).map { paragraph in
                (0..<256).map { "conceptualword\(paragraph)_\($0)" }.joined(separator: " ") + "."
            }.joined(separator: "\n\n") + "\n"
        var sources: [RelatedContentSource] = []
        for (directory, role, identifier) in vaults {
            let vaultRoot = root.appendingPathComponent(directory, isDirectory: true)
            let enumerator = try #require(FileManager.default.enumerator(at: vaultRoot, includingPropertiesForKeys: [.isRegularFileKey]))
            let urls = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "md" }.sorted { $0.path < $1.path }
            for url in urls {
                let relativePath = String(url.path.dropFirst(vaultRoot.path.count + 1))
                let bytes = try Data(contentsOf: url)
                var source = try #require(NoteDocument.decodeUTF8PreservingBOM(bytes))
                if stress, url.lastPathComponent != "QA Autosave A.md" { source += addition }
                let document = NoteDocument(relativePath: relativePath, rawContent: source)
                sources.append(
                    .init(
                        candidate: .init(
                            note: .init(vaultID: UUID(uuidString: identifier)!, relativePath: relativePath),
                            vaultRole: role, title: relativePath, fingerprint: document.fingerprint,
                            reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: []))), document: document))
            }
        }
        return sources
    }

    private func allocatedBytes() -> Int {
        var statistics = malloc_statistics_t()
        malloc_zone_statistics(nil, &statistics)
        return Int(statistics.size_in_use)
    }
}
