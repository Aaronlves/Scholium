import Darwin
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Performance regression microbenchmarks", .serialized)
struct PerformanceRegressionMicrobenchmarkTests {
    @Test("A generated long-note semantic projection remains under one second")
    func coldReadProjection() {
        let paragraph =
            "A philosophical argument distinguishes evidence, inference, objection, reply, source, authority, and conclusion with explicit uncertainty. "
        let body = (0..<500).map { index in
            index.isMultiple(of: 25)
                ? "\n## Section \(index / 25 + 1)\n\n> [!argument] Step \(index)\n> \(paragraph)\n\nClaim[^n\(index)].\n\n[^n\(index)]: \(paragraph)"
                : paragraph
        }.joined(separator: " ")
        let document = NoteDocument(relativePath: "Long.md", rawContent: body)
        let elapsed = measured { _ = SafeMarkdownRenderer.render(document) }
        #expect(elapsed < 1.0, "Cold Read projection took \(elapsed) seconds")
    }

    @Test("A 100,000-CJK-character Search source projection remains linear")
    func largeCJKSearchProjection() throws {
        let body = String(repeating: "哲学", count: 50_000)
        let document = NoteDocument(
            relativePath: "Large CJK.md",
            rawContent: body
        )
        let semantic = MarkdownSemanticDocument(parsing: document)
        var projection: SearchDocumentProjection?
        let elapsed = measured {
            projection = SearchDocumentProjection(
                document: document,
                semantic: semantic
            )
        }
        let bodySegment = try #require(
            projection?.segments.first { $0.field == .body }
        )
        #expect(bodySegment.normalizedText == body)
        let finalSourceRange = try #require(
            bodySegment.sourceUTF16Range(
                forNormalizedUTF16Range: (body.utf16.count - 1)..<body.utf16.count
            )
        )
        #expect(finalSourceRange == (body.utf16.count - 1)..<body.utf16.count)
        #expect(
            elapsed < 1.0,
            "100,000-CJK Search projection took \(elapsed) seconds"
        )
    }

    @Test("Search v10 records its 2,056-note cold, warm, and incremental acceptance evidence")
    func searchFoundationAcceptanceEvidence() async throws {
        let root =
            repositoryRoot
            .appendingPathComponent(".build/search-v10-performance-artifacts", isDirectory: true)
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let triptychID = UUID()
        let vaults = [
            RegisteredVault(name: "Analyses", role: .sourceCorpus, canonicalPath: "/fixture/analyses"),
            RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: "/fixture/topics"),
            RegisteredVault(name: "Works", role: .draftProject, canonicalPath: "/fixture/works"),
        ]
        let databaseURL = root.appendingPathComponent("search-v10.sqlite")
        let index = try TriptychSearchIndex(
            isolatedDatabaseURL: databaseURL,
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
        let warmQueries = [
            (label: "lexical_keyword", query: "deliberative keyword:cluster-3"),
            (label: "mixed_script_author", query: "哲学 author:Researcher"),
            (label: "property_only", query: "property:keywords=cluster-3"),
        ]
        var expectedResultIDs: [String: [String]] = [:]
        for scenario in warmQueries {
            let response = try await index.testSearch(request(scenario.query))
            #expect(response.results.count == 50)
            #expect(response.hasMore)
            expectedResultIDs[scenario.label] = response.results.map(\.id)
        }
        for _ in 0..<5 {
            for scenario in warmQueries {
                let response = try await index.testSearch(request(scenario.query))
                #expect(response.results.map(\.id) == expectedResultIDs[scenario.label])
            }
        }

        var samples: [Double] = []
        var samplesByScenario: [String: [Double]] = [:]
        for iteration in 0..<40 {
            let scenario = warmQueries[iteration % warmQueries.count]
            let started = ContinuousClock.now
            let response = try await index.testSearch(request(scenario.query))
            let elapsed = seconds(started.duration(to: .now))
            samples.append(elapsed)
            samplesByScenario[scenario.label, default: []].append(elapsed)
            #expect(response.results.map(\.id) == expectedResultIDs[scenario.label])
        }
        let warmQueryP95 = p95(samples)

        let paginationStart = ContinuousClock.now
        var pagedResultIDs: [String] = []
        for offset in stride(from: 0, to: 500, by: 100) {
            let response = try await index.testSearch(
                SearchRequest(
                    query: "deliberative",
                    presentationScope: .triptych,
                    executionScope: .triptych,
                    limit: 100,
                    offset: offset
                ))
            #expect(response.results.count == 100)
            #expect(response.hasMore)
            pagedResultIDs.append(contentsOf: response.results.map(\.id))
        }
        let firstFivePages = seconds(paginationStart.duration(to: .now))
        #expect(pagedResultIDs.count == 500)
        #expect(Set(pagedResultIDs).count == pagedResultIDs.count)

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
            "artifact_schema": "scholium-search-v10-performance-v2",
            "fixture": "synthetic-mixed-script-2056",
            "fixture_note_count": documents.count,
            "fixture_manifest": generation.sourceManifestHash,
            "triptych_distribution": [
                "analyses": documents.indices.count { $0 % 3 == 0 },
                "topics": documents.indices.count { $0 % 3 == 1 },
                "works": documents.indices.count { $0 % 3 == 2 },
            ],
            "contract_version": SearchContract.currentVersion,
            "schema_version": SearchContract.schemaVersion,
            "tokenizer_policy_version": SearchContract.tokenizerPolicyVersion,
            "ranking_policy_version": SearchContract.rankingPolicyVersion,
            "cold_rebuild_ms": coldRebuild * 1_000,
            "warm_query_p95_ms": warmQueryP95 * 1_000,
            "warm_query_p95_ms_by_scenario": samplesByScenario.mapValues {
                p95($0) * 1_000
            },
            "warm_query_result_count": 50,
            "first_five_100_result_pages_ms": firstFivePages * 1_000,
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
        print("SEARCH_V9_PERFORMANCE_REPORT \(reportURL.path)")
        print(String(decoding: reportData, as: UTF8.self))

        #expect(warmQueryP95 <= 0.100, "Warm Search v10 p95 was \(warmQueryP95) seconds")
        #expect(
            firstFivePages <= 0.500,
            "The first five 100-result Search pages took \(firstFivePages) seconds"
        )
        #expect(
            incrementalP95 <= 0.250,
            "Single-note Search v10 publication p95 was \(incrementalP95) seconds"
        )
    }

    #if DEBUG
        @Test(
            "Separate fresh-query rank work from immediate cache hits over 2,056 synthetic Notes",
            .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_SEARCH_QUERY_CACHE"] == "1"))
        func searchQueryCacheDiagnostics() async throws {
            let root = repositoryRoot.appendingPathComponent(
                ".build/search-query-cache-diagnostics/\(UUID().uuidString.lowercased())", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let vaults = [
                RegisteredVault(name: "Analyses", role: .sourceCorpus, canonicalPath: "/fixture/analyses"),
                RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: "/fixture/topics"),
                RegisteredVault(name: "Works", role: .draftProject, canonicalPath: "/fixture/works"),
            ]
            let documents = makeSearchFixture(vaults: vaults)
            let sources = Dictionary(
                uniqueKeysWithValues: documents.map {
                    (VaultQualifiedNoteID(vaultID: $0.vaultID, relativePath: $0.relativePath), $0)
                })
            let index = try TriptychSearchIndex(
                isolatedDatabaseURL: root.appendingPathComponent("search.sqlite"), triptychID: UUID(), vaults: vaults)
            let coldStart = ContinuousClock.now
            let publication = try await index.synchronize(documents)
            let coldMS = seconds(coldStart.duration(to: .now)) * 1_000
            #expect(publication.disposition == .rebuilt)
            let scenarios = [
                (label: "lexical_keyword", base: "deliberative keyword:cluster-3", absent: "keyword"),
                (label: "mixed_script_author", base: "哲学 author:Researcher", absent: "author"),
                (label: "property_only", base: "property:keywords=cluster-3", absent: "property"),
            ]
            let warmupCount = 3
            let sampleCount = 20
            var scenarioReports: [[String: Any]] = []
            for scenario in scenarios {
                let expected = try await index.testSearch(
                    SearchRequest(
                        query: scenario.base, presentationScope: .triptych, executionScope: .triptych, limit: 50))
                var missSamples: [Double] = []
                var hitSamples: [Double] = []
                var records: [[String: Any]] = []
                for iteration in 0..<(warmupCount + sampleCount) {
                    // Distinct absent predicates preserve the base result set while
                    // preventing a prior query from priming this AST's rank cache.
                    let query = "\(scenario.base) -\(scenario.absent):diagnosticabsent\(iteration)"
                    let parsed = SearchQueryParser.parse(query)
                    #expect(parsed.isValid)
                    let ast = try #require(parsed.ast)
                    let exclusions = ast.expression.predicates.filter(\.excluded)
                    #expect(exclusions.count == 1)
                    let exclusion = NoteSearchMatchReason.excluded(try #require(exclusions.first).clause)
                    let request = SearchRequest(
                        query: query, presentationScope: .triptych, executionScope: .triptych, limit: 50)
                    let before = await index.rankedSearchExecutionCountsForTesting
                    let missStart = ContinuousClock.now
                    let fresh = try await index.testSearch(request)
                    let missMS = seconds(missStart.duration(to: .now)) * 1_000
                    let afterMiss = await index.rankedSearchExecutionCountsForTesting
                    #expect(afterMiss.candidateScans == before.candidateScans + 1)
                    #expect(afterMiss.rankingPasses == before.rankingPasses + 1)
                    let hitStart = ContinuousClock.now
                    let repeated = try await index.testSearch(request)
                    let hitMS = seconds(hitStart.duration(to: .now)) * 1_000
                    let afterHit = await index.rankedSearchExecutionCountsForTesting
                    #expect(afterHit.candidateScans == afterMiss.candidateScans)
                    #expect(afterHit.rankingPasses == afterMiss.rankingPasses)
                    #expect(repeated == fresh)
                    // The distinct negative predicate intentionally adds exact
                    // exclusion evidence. Remove only that one reason when checking
                    // the base family's otherwise complete result presentation.
                    let normalized = try fresh.noteResults.map { result in
                        let matches = result.additionalMatchReasons.indices.filter {
                            result.additionalMatchReasons[$0] == exclusion
                        }
                        #expect(matches.count == 1)
                        let exclusionIndex = try #require(matches.first)
                        var remainingReasons = result.additionalMatchReasons
                        remainingReasons.remove(at: exclusionIndex)
                        #expect(!remainingReasons.contains(exclusion))
                        return NoteSearchResult(
                            resultID: result.resultID, vaultID: result.vaultID, vaultName: result.vaultName,
                            vaultRole: result.vaultRole, relativePath: result.relativePath,
                            stableNoteID: result.stableNoteID, title: result.title, matchedField: result.matchedField,
                            context: result.context, sourceLine: result.sourceLine, snippet: result.snippet,
                            highlights: result.highlights, matchedFields: result.matchedFields,
                            rankReason: result.rankReason, primaryMatchReason: result.primaryMatchReason,
                            additionalMatchReasons: remainingReasons,
                            paragraphRanges: result.paragraphRanges, sourceRange: result.sourceRange,
                            freshnessToken: result.freshnessToken, fingerprint: result.fingerprint,
                            evidentialLayer: result.evidentialLayer, classification: result.classification)
                    }
                    #expect(normalized == expected.noteResults)
                    #expect(fresh.totalResultCount == expected.totalResultCount)
                    #expect(fresh.results.count == 50 && fresh.hasMore)
                    #expect(fresh.freshnessToken == .triptych(publication.generation))
                    var resultRecords: [[String: Any]] = []
                    for result in fresh.noteResults {
                        let source = try #require(sources[result.noteReference])
                        #expect(result.fingerprint == source.document.fingerprint)
                        #expect(result.vaultRole == source.vaultRole)
                        #expect(result.stableNoteID == source.stableNoteID)
                        for locator in result.paragraphRanges + (result.sourceRange.map { [$0] } ?? []) {
                            #expect(
                                Range(
                                    NSRange(location: locator.utf16LowerBound, length: locator.utf16UpperBound - locator.utf16LowerBound),
                                    in: source.document.rawContent) != nil)
                        }
                        resultRecords.append([
                            "role": result.vaultRole.rawValue, "path": result.relativePath,
                            "source_sha256": result.fingerprint.sha256,
                            "source_lower": result.sourceRange?.utf16LowerBound ?? -1,
                            "source_upper": result.sourceRange?.utf16UpperBound ?? -1,
                            "snippet_sha256": DocumentFingerprint(content: result.snippet).sha256,
                            "matched_fields": result.matchedFields.map(\.rawValue),
                            "rank_reason": result.rankReason.rawValue,
                        ])
                    }
                    if iteration >= warmupCount {
                        missSamples.append(missMS)
                        hitSamples.append(hitMS)
                        records.append([
                            "sample": iteration - warmupCount, "miss_ms": missMS, "hit_ms": hitMS,
                            "query_sha256": DocumentFingerprint(content: query).sha256,
                            "ordered_result_sha256": DocumentFingerprint(
                                data: try JSONSerialization.data(withJSONObject: resultRecords, options: [.sortedKeys])
                            ).sha256,
                            "total_results": try #require(fresh.totalResultCount),
                        ])
                    }
                }
                func summary(_ samples: [Double]) -> [String: Double] {
                    let ordered = samples.sorted()
                    let middle = ordered.count / 2
                    return [
                        "min": ordered[0], "max": ordered[ordered.count - 1], "p95": p95(samples),
                        "median": (ordered[middle - 1] + ordered[middle]) / 2,
                    ]
                }
                scenarioReports.append([
                    "scenario": scenario.label, "sample_count": sampleCount,
                    "miss_ms": summary(missSamples), "hit_ms": summary(hitSamples), "samples": records,
                ])
            }
            let report: [String: Any] = [
                "artifact_schema": "scholium-search-query-cache-diagnostic-v1",
                "fixture": "synthetic-mixed-script-2056", "fixture_note_count": documents.count,
                "build_configuration": "debug", "cold_rebuild_ms": coldMS,
                "machine": hardwareModel(), "operating_system": ProcessInfo.processInfo.operatingSystemVersionString,
                "xcode": xcodeVersion(), "contract_version": SearchContract.currentVersion,
                "ranking_policy_version": SearchContract.rankingPolicyVersion,
                "measurement": "Backend only: each distinct AST's first query versus its immediate identical repeat; excludes native Search publication.",
                "sampling":
                    "Three distinct warmup pairs then twenty retained distinct pairs per scenario; missing keyword, author or Property predicates distinguish ASTs without matching fixture content. Scenarios are not pooled.",
                "oracle":
                    "Counter-proven miss/hit work; complete SearchResponse equality within each pair; current generation, exact fingerprints, roles, stable IDs and valid UTF-16 locations. Ordered digests exclude random vault UUIDs.",
                "scenarios": scenarioReports,
            ]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            print("SEARCH_QUERY_CACHE_DIAGNOSTIC \(String(decoding: data, as: UTF8.self))")
        }
    #endif

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
            publication_date: \(1950 + number % 77)
            summary: Synthetic fixture note \(number)
            keywords: [normativity, cluster-\(number % 9)]
            ---
            # Argument \(number)
            Deliberative control and normative reasons appear in note \(number). 哲学概念需要精确分析。
            Revision \(revision).
            """
        let noteID = fixtureNoteID(number)
        return SearchIndexDocument(
            vaultID: vault.id,
            vaultName: vault.name,
            vaultRole: vault.role,
            document: NoteDocument(relativePath: "Papers/Note-\(number).md", rawContent: content),
            stableNoteID: noteID.uuidString.lowercased(),
        )
    }

    private func fixtureNoteID(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
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
