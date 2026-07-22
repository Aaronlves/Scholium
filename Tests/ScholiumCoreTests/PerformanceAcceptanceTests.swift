import Darwin
import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Performance regression microbenchmarks", .serialized)
struct PerformanceRegressionMicrobenchmarkTests {
    @Test("A generated long-note semantic projection remains under one second")
    func coldReadProjection() {
        let paragraph = "A philosophical argument distinguishes evidence, inference, objection, reply, source, authority, and conclusion with explicit uncertainty. "
        let body = (0..<500).map { index in
            index.isMultiple(of: 25)
                ? "\n## Section \(index / 25 + 1)\n\n> [!argument] Step \(index)\n> \(paragraph)\n\nClaim[^n\(index)].\n\n[^n\(index)]: \(paragraph)"
                : paragraph
        }.joined(separator: " ")
        let document = NoteDocument(relativePath: "Long.md", rawContent: body)
        let elapsed = measured { _ = SafeMarkdownRenderer.render(document) }
        #expect(elapsed < 1.0, "Cold Read projection took \(elapsed) seconds")
    }

    @Test("Search v3 records its 2,056-note cold, warm, and incremental acceptance evidence")
    func searchV3AcceptanceEvidence() async throws {
        let root = repositoryRoot
            .appendingPathComponent(".build/search-v3-performance-artifacts", isDirectory: true)
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let triptychID = UUID()
        let vaults = [
            RegisteredVault(name: "Analyses", role: .sourceCorpus, canonicalPath: "/fixture/analyses"),
            RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: "/fixture/topics"),
            RegisteredVault(name: "Works", role: .draftProject, canonicalPath: "/fixture/works"),
        ]
        let databaseURL = root.appendingPathComponent("search-v3.sqlite")
        let index = try TriptychSearchIndex(
            databaseURL: databaseURL,
            triptychID: triptychID
        )
        var documents = makeSearchFixture(vaults: vaults)
        let coldStart = ContinuousClock.now
        let coldPublication = try await index.synchronize(documents)
        let coldRebuild = seconds(coldStart.duration(to: .now))

        func request(_ query: String) -> SearchRequest {
            SearchRequest(
                query: query,
                presentationScope: .triptych,
                executionScope: .triptych,
                limit: 50
            )
        }
        for _ in 0..<5 {
            _ = try await index.search(request("deliberative tag:normativity"))
        }

        var samples: [Double] = []
        for iteration in 0..<40 {
            let started = ContinuousClock.now
            _ = try await index.search(
                request(iteration.isMultiple(of: 2)
                    ? "deliberative tag:cluster-3"
                    : "哲学 author:Researcher")
            )
            samples.append(seconds(started.duration(to: .now)))
        }
        let warmQueryP95 = p95(samples)

        var incrementalSamples: [Double] = []
        for iteration in 0..<45 {
            let documentNumber = iteration % documents.count
            let vault = vaults[documentNumber % vaults.count]
            documents[documentNumber] = makeSearchDocument(
                number: documentNumber,
                vault: vault,
                revision: iteration + 1
            )
            let started = ContinuousClock.now
            let publication = try await index.synchronize(documents)
            let elapsed = seconds(started.duration(to: .now))
            #expect(publication.disposition == .incrementallyUpdated)
            if iteration >= 5 { incrementalSamples.append(elapsed) }
        }
        let incrementalP95 = p95(incrementalSamples)
        let generation = try #require(await index.generation())
        let report: [String: Any] = [
            "artifact_schema": "scholium-search-v3-performance-v1",
            "fixture": "synthetic-mixed-script-2056",
            "fixture_note_count": documents.count,
            "fixture_manifest": generation.sourceManifestHash,
            "triptych_distribution": [
                "analyses": documents.indices.count { $0 % 3 == 0 },
                "topics": documents.indices.count { $0 % 3 == 1 },
                "works": documents.indices.count { $0 % 3 == 2 },
            ],
            "contract_version": SearchContractV3.contractVersion,
            "schema_version": SearchContractV3.schemaVersion,
            "tokenizer_policy_version": SearchContractV3.tokenizerPolicyVersion,
            "ranking_policy_version": SearchContractV3.rankingPolicyVersion,
            "cold_rebuild_ms": coldRebuild * 1_000,
            "warm_query_p95_ms": warmQueryP95 * 1_000,
            "incremental_publication_p95_ms": incrementalP95 * 1_000,
            "database_bytes": databaseFootprint(at: databaseURL),
            "process_peak_rss_bytes": processPeakResidentBytes(),
            "machine": hardwareModel(),
            "operating_system": ProcessInfo.processInfo.operatingSystemVersionString,
            "xcode": xcodeVersion(),
            "cold_disposition": String(describing: coldPublication.disposition),
        ]
        let reportData = try JSONSerialization.data(
            withJSONObject: report,
            options: [.prettyPrinted, .sortedKeys]
        )
        let reportURL = root.appendingPathComponent("report.json")
        try reportData.write(to: reportURL, options: .atomic)
        print("SEARCH_V3_PERFORMANCE_REPORT \(reportURL.path)")
        print(String(decoding: reportData, as: UTF8.self))

        #expect(warmQueryP95 <= 0.100, "Warm Search v3 p95 was \(warmQueryP95) seconds")
        #expect(
            incrementalP95 <= 0.250,
            "Single-note Search v3 publication p95 was \(incrementalP95) seconds"
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func makeSearchFixture(vaults: [RegisteredVault]) -> [SearchIndexDocument] {
        (0..<2_056).map { number in
            makeSearchDocument(
                number: number,
                vault: vaults[number % vaults.count],
                revision: 0
            )
        }
    }

    private func makeSearchDocument(
        number: Int,
        vault: RegisteredVault,
        revision: Int
    ) -> SearchIndexDocument {
        let content = """
        ---
        title: Philosophical Note \(number)
        authors: [Researcher \(number % 17)]
        year: \(1950 + number % 77)
        tags: [normativity, cluster-\(number % 9)]
        ---
        # Argument \(number)
        Deliberative control and normative reasons appear in note \(number). 哲学概念需要精确分析。
        Revision \(revision).
        """
        return SearchIndexDocument(
            vaultID: vault.id,
            vaultName: vault.name,
            vaultRole: vault.role,
            document: NoteDocument(
                relativePath: "Papers/Note-\(number).md",
                rawContent: content
            )
        )
    }

    private func p95(_ samples: [Double]) -> Double {
        let ordered = samples.sorted()
        guard !ordered.isEmpty else { return .infinity }
        let index = max(0, Int(ceil(Double(ordered.count) * 0.95)) - 1)
        return ordered[min(ordered.count - 1, index)]
    }

    private func databaseFootprint(at url: URL) -> Int {
        [url.path, url.path + "-wal", url.path + "-shm"].reduce(into: 0) { total, path in
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            total += attributes?[.size] as? Int ?? 0
        }
    }

    private func processPeakResidentBytes() -> Int64 {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return -1 }
        return Int64(usage.ru_maxrss)
    }

    private func hardwareModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else {
            return "unknown"
        }
        var value = [CChar](repeating: 0, count: size)
        let result = value.withUnsafeMutableBytes { bytes in
            sysctlbyname("hw.model", bytes.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { return "unknown" }
        return String(
            decoding: value.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )
    }

    private func xcodeVersion() -> String {
        guard let developerDirectory = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] else {
            return "DEVELOPER_DIR not set"
        }
        let versionURL = URL(fileURLWithPath: developerDirectory)
            .deletingLastPathComponent()
            .appendingPathComponent("version.plist")
        guard let values = NSDictionary(contentsOf: versionURL) as? [String: Any] else {
            return developerDirectory
        }
        let version = values["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = values["ProductBuildVersion"] as? String ?? "unknown"
        return "Xcode \(version) (\(build))"
    }

    private func measured(_ operation: () -> Void) -> Double {
        let started = ContinuousClock.now
        operation()
        return seconds(started.duration(to: .now))
    }

    private func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
    }
}
