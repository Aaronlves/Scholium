import Darwin
import Foundation
import SQLite3
import ScholiumContracts
import Testing

@testable import ScholiumApplication

/// Real on-disk workspace diagnostics. These samples are neither UI latency nor a release gate.
@Suite(
    "Large vault workspace stress diagnostics", .serialized,
    .enabled(
        if: ProcessInfo.processInfo.environment["SCHOLIUM_STRESS_FIXTURE"] != nil
            || ProcessInfo.processInfo.environment["SCHOLIUM_STRESS_CACHED_SEED"] != nil)
)
struct LargeVaultStressDiagnosticTests {
    @Test(
        "Query-only Search and Related over the complete synthetic Stress Triptych",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_STRESS_RETRIEVAL"] == "1")
    )
    func queryOnlyRetrieval() async throws {
        let environment = ProcessInfo.processInfo.environment
        let phases = Set((environment["SCHOLIUM_STRESS_RETRIEVAL_PHASES"] ?? "documents,search").split(separator: ",").map(String.init))
        let relatedSeeds = Set((environment["SCHOLIUM_STRESS_RELATED_SEEDS"] ?? "short").split(separator: ",").map(String.init))
        try #require(!phases.isEmpty && phases.isSubset(of: ["documents", "search", "related"]))
        try #require(!relatedSeeds.isEmpty && relatedSeeds.isSubset(of: ["short", "long", "dense", "fidelity"]))
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let buildRoot = repository.appendingPathComponent(".build", isDirectory: true)
        let fixture = URL(fileURLWithPath: try #require(environment["SCHOLIUM_STRESS_FIXTURE"]))
            .standardizedFileURL
        let output = URL(
            fileURLWithPath: environment["SCHOLIUM_STRESS_OUTPUT"]
                ?? buildRoot.appendingPathComponent("stress-audit/retrieval-diagnostics").path,
            isDirectory: true
        ).standardizedFileURL
        try #require(fixture.path.hasPrefix(buildRoot.path + "/"))
        try #require(output.path.hasPrefix(buildRoot.path + "/"))
        try #require(output != fixture && !output.path.hasPrefix(fixture.path + "/"))
        try #require(fixture == fixture.resolvingSymlinksInPath())
        try #require(output == output.resolvingSymlinksInPath())
        try requireDiagnosticTreeWithoutLinks(fixture)
        let manifestBytes = try Data(contentsOf: fixture.appendingPathComponent("stress-manifest.json"))
        let manifest = try #require(JSONSerialization.jsonObject(with: manifestBytes) as? [String: Any])
        try #require(manifest["synthetic_nonprivate"] as? Bool == true)
        let counts = try #require(manifest["counts"] as? [String: Int])
        try #require(counts["notes"] == 5_000)
        try #require(manifest["registration_roots"] as? [String] == slots)
        let scenarios = try #require(manifest["scenarios"] as? [String: String])
        let searchScenarios = try searchScenarios(at: fixture)
        try #require(searchScenarios.count == 6)
        let shortPath = try #require(searchScenarios.first { $0.label == "rare_body" }?.expectedPaths?.first)
        let seeds = [
            ("short", shortPath, [#"(?m)^Record [^\r\n]+"#]),
            ("long", try #require(scenarios["long_prose"]), [#"(?m)^Record [^\r\n]+"#]),
            ("dense", try #require(scenarios["dense_links"]), [#"(?m)^\[\[Stress Note [^\r\n]+"#]),
            ("fidelity", try #require(scenarios["source_fidelity"]), [#"(?m)^全部内容[^\r\n]+"#, #"(?m)^中文 English[^\r\n]+"#]),
        ]
        let runID = UUID().uuidString.lowercased()
        let root = buildRoot.appendingPathComponent("stress-retrieval-runtime/\(runID)", isDirectory: true)
        let working = root.appendingPathComponent("fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try requireDiagnosticTreeWithoutLinks(output)
        let reportURL = output.appendingPathComponent("retrieval-\(runID).json")
        let original = try sourceOracle(at: fixture)
        try #require(original.count == 5_000)
        let oversizedSources = Set(
            try original.keys.filter { path in
                guard original[path]!.byteCount > RelatedContentContract.maximumSeedUTF16Count else { return false }
                return try exactSource(at: fixture.appendingPathComponent(path)).utf16.count > RelatedContentContract.maximumSeedUTF16Count
            })

        func inventory(_ directory: URL) throws -> [String: DocumentFingerprint] {
            let files = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]))
            var result: [String: DocumentFingerprint] = [:]
            for case let url as URL in files {
                if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                    result[String(url.path.dropFirst(directory.path.count + 1))] = DocumentFingerprint(data: try Data(contentsOf: url))
                }
            }
            return result
        }
        let originalInventory = try inventory(fixture)
        try FileManager.default.copyItem(at: fixture, to: working)
        try #require(try sourceOracle(at: working) == original)
        var report: [String: Any] = [
            "schema": "scholium-stress-retrieval-diagnostic-v1",
            "label": environment["SCHOLIUM_RETRIEVAL_LABEL"] ?? "diagnostic",
            "source_revision": environment["SCHOLIUM_RETRIEVAL_SOURCE_REVISION"] ?? "unrecorded",
            "phases": phases.sorted(), "related_seed_selection": relatedSeeds.sorted(),
            "fixture_manifest_sha256": DocumentFingerprint(data: manifestBytes).sha256,
            "fixture_source_sha256": sourceDigest(original), "fixture_note_count": original.count,
            "related_oversized_source_count": oversizedSources.count,
            "build_configuration": buildConfiguration,
            "operating_system": ProcessInfo.processInfo.operatingSystemVersionString,
            "measurement":
                "Backend APIs only; configuration, fixture copy, request construction and correctness checks are outside query timers. No native UI, scheduling debounce, visible paint, allocation tracing or release-gate claim.",
            "search_sampling": "Three excluded distinct-query warmups, then twenty distinct-query/immediate-repeat pairs per independent manifest oracle.",
            "search_digest_scope":
                "Ordered response digests retain disposable vault and stable Note UUIDs. Exact repeat equality is checked within each runtime; these raw digests do not establish equivalence across independently configured Triptychs.",
            "hydration_sampling":
                "Long Prose and Dense Links, four facade calls each for hydrate and documentPreviewCatalog, first then three repeats. Configuration may already warm source/identity state; no cold-cache claim. DEBUG identity counters are observed outside timers.",
            "related_sampling":
                "Configured seed selection, two distinct exact source ranges per selected seed; first request then three identical-request repeats per context. First requests are not OS/cache cold. Changed focus follows all repeats of the first context. No background preparation is requested.",
            "correctness_scope":
                "Current complete generation and source fingerprints/ranges; exact same-context response equality; role-normalized ordered full response digest. After all timed requests, full Core candidate recall independently proves omitted counts equal the recalled sources exceeding the exact UTF16 capacity. Stale publication is rejected; concurrent refresh/cancellation races are not induced.",
            "status": "configuring",
        ]
        func emit(_ record: [String: Any]) throws {
            let bytes = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            FileHandle.standardOutput.write(Data("STRESS_RETRIEVAL ".utf8) + bytes + Data([0x0A]))
        }
        try writeReport(report, to: reportURL)
        try emit(["phase": "configuration_begin", "report": reportURL.path])
        let runtime = WorkspaceRuntime(
            configuration: .live(
                .init(
                    applicationSupportURL: root.appendingPathComponent("state/Application Support"),
                    workspaceRegistryStorageURL: root.appendingPathComponent("state/Registry"))))
        do {
            let started = ContinuousClock.now
            let handle = try await runtime.configureTriptych(
                paperAnalysisURL: working.appendingPathComponent(slots[0]),
                topicKnowledgeURL: working.appendingPathComponent(slots[1]),
                outputURL: working.appendingPathComponent(slots[2]),
                portableContainerURL: working, triptychName: "Synthetic Stress Retrieval Diagnostic")
            let configurationMilliseconds = milliseconds(started.duration(to: .now))
            let snapshot = try await handle.snapshot()
            try requireReopenSnapshot(snapshot, oracle: original, assignment: handle.assignment)
            let generation = try #require(snapshot.discovery.searchGeneration)
            var roles: [String: String] = [:]
            for vault in handle.assignment.vaults.values {
                roles[vault.id.uuidString] = vault.role.rawValue
                roles[vault.id.uuidString.lowercased()] = vault.role.rawValue
            }
            report["configuration_ms"] = configurationMilliseconds
            report["configuration"] = await refreshReport(handle, stage: "query_setup", wallMilliseconds: configurationMilliseconds)
            report["status"] = "hydration_preview"
            try writeReport(report, to: reportURL)
            try emit(["phase": "configuration_complete", "milliseconds": configurationMilliseconds])
            let services = await handle.services
            let graph = try #require(snapshot.discovery.catalog.graph)
            func identityCounts() async -> [String: Int] {
                #if DEBUG
                    return [
                        "decodes": await services.controlStore.identitySnapshotDecodeCountForTesting,
                        "validations": await services.controlStore.identityInventoryValidationCountForTesting,
                        "source_reads": await services.controlStore.identityInventorySourceReadCountForTesting,
                    ]
                #else
                    return [:]
                #endif
            }
            var documentRecords: [[String: Any]] = []
            for (label, path, _) in seeds where phases.contains("documents") && (label == "long" || label == "dense") {
                let id = try noteID(path, assignment: handle.assignment)
                let summary = try #require(snapshot.document(id: id))
                let source = try exactSource(at: working.appendingPathComponent(path))
                var expectedPreview: DocumentPreviewCatalog?
                for sample in 0..<4 {
                    let beforeHydration = await identityCounts()
                    let hydrationStarted = ContinuousClock.now
                    let note = try await handle.documents.hydrate(summary)
                    let hydrationMilliseconds = milliseconds(hydrationStarted.duration(to: .now))
                    let afterHydration = await identityCounts()
                    try #require(note.summary == summary && note.fingerprint == original[path])
                    try #require(Data(note.document.rawContent.utf8) == Data(source.utf8))
                    let beforePreview = await identityCounts()
                    let previewStarted = ContinuousClock.now
                    let preview = try await handle.documents.documentPreviewCatalog(
                        source: id, sourceFingerprint: summary.fingerprint, graphGeneration: graph.generation)
                    let previewMilliseconds = milliseconds(previewStarted.duration(to: .now))
                    let afterPreview = await identityCounts()
                    try #require(preview.source == id && preview.sourceFingerprint == summary.fingerprint)
                    try #require(preview.graphGeneration == graph.generation)
                    try #require(preview.links.count <= DocumentPreviewCatalogBuilder.maximumLinkCount)
                    let admitted = (graph.outgoing[id] ?? [])
                        .sorted { $0.occurrence.span.utf16LowerBound < $1.occurrence.span.utf16LowerBound }
                        .prefix(DocumentPreviewCatalogBuilder.maximumLinkCount)
                    try #require(preview.links.count == admitted.filter { $0.destination != nil }.count)
                    if label == "dense" { try #require(!preview.links.isEmpty) }
                    for link in preview.links {
                        try #require(snapshot.document(id: link.target)?.fingerprint == link.targetFingerprint)
                        try #require(
                            admitted.contains {
                                $0.destination?.note == link.target && $0.occurrence.linkSpan == link.sourceSpan
                                    && $0.occurrence.syntax == link.syntax && $0.destination?.fragment == link.fragment
                            })
                        try #require(Range(link.sourceSpan.nsRange, in: source) != nil)
                    }
                    if let expectedPreview { try #require(preview == expectedPreview) } else { expectedPreview = preview }
                    try #require(try await handle.snapshot().discovery.searchGeneration == generation)
                    let row: [String: Any] = [
                        "seed": label, "sample": sample, "cache_condition": sample == 0 ? "first_facade_call" : "repeat",
                        "hydrate_ms": hydrationMilliseconds, "preview_catalog_ms": previewMilliseconds,
                        "preview_links": preview.links.count, "preview_unique_targets": Set(preview.links.map(\.target)).count,
                        "hydrate_identity_delta": afterHydration.merging(beforeHydration.mapValues { -$0 }, uniquingKeysWith: +),
                        "preview_identity_delta": afterPreview.merging(beforePreview.mapValues { -$0 }, uniquingKeysWith: +),
                    ]
                    documentRecords.append(row)
                    try emit(["phase": "hydration_preview_complete", "record": row])
                    report["hydration_preview"] = documentRecords
                    try writeReport(report, to: reportURL)
                }
            }
            report["status"] = "search"
            try writeReport(report, to: reportURL)
            if phases.contains("search") {
                report["search"] = try await measureSearch(handle, scenarios: searchScenarios, oracle: original, root: working)
            }
            try #require(try await handle.snapshot().discovery.searchGeneration == generation)
            report["status"] = "related"
            try writeReport(report, to: reportURL)

            // Exact UUID-valued identity fields become roles only in the comparison
            // hash. Source text, locators, reasons, scores and ordering stay intact.
            func normalizedIdentities(_ value: Any) -> Any {
                if let text = value as? String { return roles[text] ?? text }
                if let array = value as? [Any] { return array.map(normalizedIdentities) }
                if let object = value as? [String: Any] { return object.mapValues(normalizedIdentities) }
                return value
            }
            func responseDigest(_ response: RelatedContentResponse) throws -> String {
                let encoder = JSONEncoder()
                var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(response)) as? [String: Any])
                for key in ["requestID", "freshnessToken", "availability"] { object.removeValue(forKey: key) }
                return DocumentFingerprint(
                    data: try JSONSerialization.data(
                        withJSONObject: normalizedIdentities(object), options: [.sortedKeys])
                ).sha256
            }
            func validate(_ response: RelatedContentResponse, request: RelatedContentRequest) throws {
                try #require(response.requestID == request.id && response.seedFingerprint == request.seed.fingerprint)
                try #require(response.availability == .current(generation) && response.freshnessToken == .triptych(generation))
                if response.omittedSourceCount > 0 {
                    try #require(response.state == .partial)
                } else {
                    try #require(response.state == (response.passages.isEmpty ? .empty : .current))
                }
                try #require(response.passages.count <= RelatedContentContract.maximumPassages)
                let candidates = response.identityCandidates + response.lexicalCandidates + response.graphCandidates + response.passages.map(\.candidate)
                for candidate in candidates {
                    let path = try sourcePath(candidate.note, assignment: handle.assignment)
                    try #require(candidate.fingerprint == original[path])
                    try #require(snapshot.document(id: candidate.note)?.fingerprint == candidate.fingerprint)
                    try #require(handle.assignment.vaults.values.contains { $0.id == candidate.note.vaultID && $0.role == candidate.vaultRole })
                    try #require(candidate.note != request.seed.noteID)
                }
                for passage in response.passages {
                    let path = try sourcePath(passage.candidate.note, assignment: handle.assignment)
                    let source = try exactSource(at: working.appendingPathComponent(path))
                    let range = try #require(
                        Range(
                            NSRange(
                                location: passage.range.utf16LowerBound,
                                length: passage.range.utf16UpperBound - passage.range.utf16LowerBound), in: source))
                    try #require(Data(passage.source.utf8) == Data(source[range].utf8))
                    try #require(passage.candidate.fingerprint == DocumentFingerprint(content: source))
                }
            }
            var relatedRecords: [[String: Any]] = []
            var completedContexts: [(RelatedContentRequest, RelatedContentResponse, Int)] = []
            for (label, path, patterns) in seeds where phases.contains("related") && relatedSeeds.contains(label) {
                let source = try exactSource(at: working.appendingPathComponent(path))
                try #require(Data(source.utf8).count == original[path]?.byteCount)
                try #require(source.utf16.count <= RelatedContentContract.maximumSeedUTF16Count)
                let id = try noteID(path, assignment: handle.assignment)
                let fullRange = NSRange(location: 0, length: source.utf16.count)
                let ranges = try patterns.flatMap { pattern in
                    try NSRegularExpression(pattern: pattern).matches(in: source, range: fullRange).map(\.range)
                }
                let focusRanges = [try #require(ranges.first), try #require(ranges.last)]
                try #require(focusRanges[0] != focusRanges[1])
                for (focusIndex, focusRange) in focusRanges.enumerated() {
                    let range = try #require(Range(focusRange, in: source))
                    let focus = String(source[range])
                    try #require(focus.utf16.count <= RelatedContentContract.maximumFocusUTF16Count)
                    let request = RelatedContentRequest(seed: .init(noteID: id, source: source, focuses: [.init(kind: .selectedPassage, text: focus)]))
                    var expected: RelatedContentResponse?
                    var rows: [[String: Any]] = []
                    var warmMilliseconds: [Double] = []
                    for sample in 0..<4 {
                        try Task.checkCancellation()
                        try #require(try await handle.snapshot().discovery.searchGeneration == generation)
                        try emit(["phase": "related_begin", "seed": label, "focus": focusIndex, "sample": sample])
                        let started = ContinuousClock.now
                        let response = try await handle.discovery.relatedContent(request)
                        let elapsed = milliseconds(started.duration(to: .now))
                        let measurement = try #require(await handle.lastRelatedContentMeasurement)
                        try #require(measurement.requestID == request.id)
                        try #require(measurement.candidateCount == measurement.sourceCount + measurement.omittedSourceCount)
                        try #require(measurement.omittedSourceCount == response.omittedSourceCount)
                        try #require(
                            measurement.indexDuration + measurement.graphDuration + measurement.readDuration
                                + measurement.passageDuration + measurement.finalizationDuration == measurement.totalDuration)
                        try #require(milliseconds(measurement.totalDuration) <= elapsed)
                        try #require(try await handle.snapshot().discovery.searchGeneration == generation)
                        try validate(response, request: request)
                        if let expected { try #require(response == expected) } else { expected = response }
                        if sample > 0 { warmMilliseconds.append(elapsed) }
                        let row: [String: Any] = [
                            "seed": label, "focus": focusIndex, "sample": sample,
                            "cache_condition": sample == 0 ? (focusIndex == 0 ? "first_context" : "changed_focus") : "identical_request_repeat",
                            "seed_sha256": request.seed.fingerprint.sha256, "seed_utf16_count": source.utf16.count,
                            "focus_sha256": DocumentFingerprint(content: focus).sha256,
                            "focus_lower": focusRange.location, "focus_upper": NSMaxRange(focusRange),
                            "ordered_response_sha256": try responseDigest(response),
                            "milliseconds": elapsed, "backend_total_ms": milliseconds(measurement.totalDuration),
                            "index_ms": milliseconds(measurement.indexDuration), "graph_ms": milliseconds(measurement.graphDuration),
                            "read_ms": milliseconds(measurement.readDuration), "passage_ms": milliseconds(measurement.passageDuration),
                            "finalization_ms": milliseconds(measurement.finalizationDuration),
                            "candidates": measurement.candidateCount, "sources": measurement.sourceCount,
                            "omitted_sources": measurement.omittedSourceCount, "passages": response.passages.count,
                            "graph_used": measurement.graphUsed, "graph_candidates": measurement.graphCandidateCount,
                            "graph_contexts": measurement.graphContextCount,
                        ]
                        rows.append(row)
                        try emit(["phase": "related_complete", "record": row])
                    }
                    relatedRecords.append([
                        "seed": label, "focus": focusIndex, "samples": rows,
                        "warm_sample_count": warmMilliseconds.count, "warm_ms": distribution(warmMilliseconds),
                    ])
                    completedContexts.append((request, try #require(expected), try #require(rows.first?["candidates"] as? Int)))
                    report["related"] = relatedRecords
                    try writeReport(report, to: reportURL)
                }
            }
            // Run recall again only after every timed request, so this oracle
            // cannot warm an initial or changed-focus measurement. The response
            // preview limit never stands in for the full recalled source set.
            let index = try await services.searchIndex
            for (request, response, candidateCount) in completedContexts {
                let recall = try await index.relatedMaterialSourceCandidates(request)
                try #require(recall.availability == .current(generation) && recall.freshnessToken == .triptych(generation))
                let recalled = Set((recall.identityCandidates + recall.lexicalCandidates + response.graphCandidates).map(\.note))
                try #require(recalled.count == candidateCount)
                let expectedOmissions = try recalled.filter {
                    oversizedSources.contains(try sourcePath($0, assignment: handle.assignment))
                }.count
                try #require(response.omittedSourceCount == expectedOmissions)
            }
            let finalSnapshot = try await handle.snapshot()
            try requireReopenSnapshot(finalSnapshot, oracle: original, assignment: handle.assignment)
            try #require(finalSnapshot.discovery.searchGeneration == generation)
            await runtime.shutdown()
            try #require(try sourceOracle(at: working) == original)
            try #require(try inventory(fixture) == originalInventory)
            report["status"] = "completed"
            report["original_fixture_inventory_unchanged"] = true
            report["copied_note_sources_unchanged"] = true
            report["generation_unchanged"] = true
            if phases.contains("related") { report["omission_admission_oracle_passed"] = true }
            try writeReport(report, to: reportURL)
            try emit(["phase": "completed", "report": reportURL.path])
        } catch {
            await runtime.shutdown()
            report["status"] = "failed"
            report["error"] = String(describing: error)
            report["original_fixture_inventory_unchanged"] = (try? inventory(fixture)) == originalInventory
            report["copied_note_sources_unchanged"] = (try? sourceOracle(at: working)) == original
            try? writeReport(report, to: reportURL)
            try? emit(["phase": "failed", "report": reportURL.path, "error": String(describing: error)])
            throw error
        }
    }

    @Test(
        "Large mixed-content Triptych retains complete current generations through its lifecycle",
        .enabled(
            if: ProcessInfo.processInfo.environment["SCHOLIUM_STRESS_FIXTURE"] != nil
                && ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_REOPEN"] != "1")
    )
    func largeDiskTriptych() async throws {
        let environment = ProcessInfo.processInfo.environment
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let buildRoot = repository.appendingPathComponent(".build", isDirectory: true)
        let fixture = URL(fileURLWithPath: try #require(environment["SCHOLIUM_STRESS_FIXTURE"]))
            .resolvingSymlinksInPath().standardizedFileURL
        let output = URL(
            fileURLWithPath: environment["SCHOLIUM_STRESS_OUTPUT"]
                ?? buildRoot.appendingPathComponent("stress-audit/index-diagnostics").path,
            isDirectory: true
        ).resolvingSymlinksInPath().standardizedFileURL
        try #require(fixture.path.hasPrefix(buildRoot.path + "/"))
        try #require(output.path.hasPrefix(buildRoot.path + "/"))
        try #require(!output.path.hasPrefix(fixture.path + "/") && output != fixture)
        let runID = UUID().uuidString.lowercased()
        let root = buildRoot.appendingPathComponent(
            "large-vault-stress-runtime/\(runID)", isDirectory: true)
        let working = root.appendingPathComponent("fixture", isDirectory: true)
        let support = root.appendingPathComponent("state/Application Support", isDirectory: true)
        let rebuiltSupport = root.appendingPathComponent(
            "rebuilt-state/Application Support", isDirectory: true)
        let registry = root.appendingPathComponent("state/Registry", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let reportURL = output.appendingPathComponent("workspace-\(runID).json")
        let fixtureManifest = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appendingPathComponent("stress-manifest.json")))
                as? [String: Any])
        try #require(fixtureManifest["synthetic_nonprivate"] as? Bool == true)
        let fixtureCounts = try #require(fixtureManifest["counts"] as? [String: Int])
        let expectedNotes = try #require(fixtureCounts["notes"])
        try #require((508...20_000).contains(expectedNotes))
        let original = try sourceOracle(at: fixture)
        try #require(original.count == expectedNotes)
        try FileManager.default.copyItem(at: fixture, to: working)
        var oracle = try sourceOracle(at: working)
        #expect(oracle == original)
        var report: [String: Any] = [
            "schema": "scholium-large-vault-workspace-diagnostic-v1",
            "fixture_note_count": original.count,
            "fixture_source_bytes": original.values.reduce(0) { $0 + $1.byteCount },
            "fixture_source_sha256": sourceDigest(original),
            "operating_system": ProcessInfo.processInfo.operatingSystemVersionString,
            "physical_memory_bytes": ProcessInfo.processInfo.physicalMemory,
            "processor_count": ProcessInfo.processInfo.activeProcessorCount,
            "developer_directory": environment["DEVELOPER_DIR"] ?? "not set",
            "process_id": ProcessInfo.processInfo.processIdentifier,
            "build_configuration": buildConfiguration,
            "measurement":
                "Real disk workspace APIs; excludes UI, paint, file-copy and oracle work. No release-gate claim.",
            "commit_observation_boundary":
                "Source commit is timed through API return. Derived-ready timings are observation bounds including post-return fingerprint/byte checks and event observation, not pure derived-processing time.",
            "cold_definition":
                "Fresh runtime, registration and application-support index; operating-system filesystem caches are not purged.",
            "peak_memory_scope":
                "Whole diagnostic process, including source oracles and incremental/rebuilt graph comparison; not retained-app memory.",
            "storage_scope":
                "Metadata-only logical sizes and reported allocated bytes under each application-support root; not unique APFS physical extents or process memory. Snapshots are outside operation timers.",
            "search_sampling":
                "Three excluded distinct-query warmups, then twenty distinct-query/immediate-repeat pairs per scenario; p50 and nearest-rank p95 are separate for each scenario and cache condition.",
        ]
        var steps: [[String: Any]] = []
        var checkpoints: [[String: Any]] = []
        var stage = "cold_configuration"
        func checkpoint(_ state: String, iteration: Int? = nil, runStatus: String = "in_progress")
            throws
        {
            var record: [String: Any] = [
                "stage": stage, "state": state,
                "application_support": storageSummary(at: support),
                "rebuilt_application_support": storageSummary(at: rebuiltSupport),
            ]
            if let iteration { record["iteration"] = iteration }
            checkpoints.append(record)
            report["status"] = runStatus
            report["active_stage"] = stage
            report["steps"] = steps
            report["checkpoints"] = checkpoints
            report["process_peak_rss_bytes"] = processPeakResidentBytes()
            try writeReport(report, to: reportURL)
            diagnosticProgress("Large vault workspace checkpoint: \(stage), \(state)")
        }
        let configuration = WorkspaceRuntime.Configuration.live(
            .init(applicationSupportURL: support, workspaceRegistryStorageURL: registry))
        var runtime = WorkspaceRuntime(configuration: configuration)
        do {
            let scenarios = try searchScenarios(at: working)
            let assignment: TriptychAssignment
            do {
                diagnosticProgress(
                    "Large vault workspace begin: \(stage), \(original.count) Notes, pid \(ProcessInfo.processInfo.processIdentifier)"
                )
                try checkpoint("begun")
                let started = ContinuousClock.now
                let configured = try await runtime.configureTriptych(
                    paperAnalysisURL: working.appendingPathComponent(slots[0]),
                    topicKnowledgeURL: working.appendingPathComponent(slots[1]),
                    outputURL: working.appendingPathComponent(slots[2]),
                    portableContainerURL: working,
                    triptychName: "Large Synthetic Stress Diagnostic"
                )
                let coldMilliseconds = milliseconds(started.duration(to: .now))
                assignment = configured.assignment
                let cold = try await configured.snapshot()
                try validateSnapshot(cold, oracle: oracle, assignment: assignment)
                let coldMeasurement = await configured.latestRefreshMeasurement
                #expect(coldMeasurement.readFiles == original.count)
                #expect(coldMeasurement.parsedDocuments == original.count)
                #expect(coldMeasurement.projectedDocuments == original.count)
                steps.append(
                    await refreshReport(configured, stage: stage, wallMilliseconds: coldMilliseconds))
                report["cold_configuration_ms"] = coldMilliseconds
                try checkpoint("completed")
                await runtime.shutdown()
            }

            do {
                stage = "compatible_progressive_reopen"
                diagnosticProgress("Large vault workspace begin: \(stage)")
                try checkpoint("begun")
                runtime = WorkspaceRuntime(configuration: configuration)
                let openStarted = ContinuousClock.now
                let handle = try await runtime.openWorkspace(
                    id: assignment.id, openingVault: .paperAnalysis)
                let usableMilliseconds = milliseconds(openStarted.duration(to: .now))
                let opening = try await handle.snapshot()
                try #require(!opening.phase.isComplete)
                #expect(opening.discovery.searchGeneration == nil)
                let openingMeasurement = await handle.latestRefreshMeasurement
                #expect(openingMeasurement.parsedDocuments == 0)
                #expect(openingMeasurement.restoredCatalogProjections == openingMeasurement.readFiles)
                let stream = await handle.events.events()
                let completionStarted = ContinuousClock.now
                await handle.openingPresentationDidComplete()
                let complete = try await completeSnapshot(in: stream)
                let completionMilliseconds = milliseconds(completionStarted.duration(to: .now))
                await handle.awaitOpeningCompletionForTesting()
                try validateSnapshot(complete, oracle: oracle, assignment: assignment)
                let reopened = await handle.latestRefreshMeasurement
                #expect(reopened.parsedDocuments == 0)
                #expect(reopened.restoredCatalogProjections == reopened.readFiles)
                #expect(reopened.projectedDocuments == 0)
                #expect(reopened.restoredSearchProjections == 0)
                var reopenReport = await refreshReport(
                    handle, stage: stage, wallMilliseconds: usableMilliseconds + completionMilliseconds)
                reopenReport["usable_open_ms"] = usableMilliseconds
                reopenReport["completion_after_presentation_ms"] = completionMilliseconds
                reopenReport["opening_read_files"] = openingMeasurement.readFiles
                reopenReport["opening_parsed_documents"] = openingMeasurement.parsedDocuments
                reopenReport["opening_restored_catalog_projections"] = openingMeasurement.restoredCatalogProjections
                steps.append(reopenReport)
                try checkpoint("completed")

                stage = "unchanged_refresh"
                let retainedCacheStorage = storageSummary(at: support)
                for iteration in 0..<3 {
                    diagnosticProgress("Large vault workspace begin: \(stage), iteration \(iteration)")
                    try checkpoint("begun", iteration: iteration)
                    let refreshStarted = ContinuousClock.now
                    let unchanged = try await handle.discovery.refresh()
                    let elapsed = milliseconds(refreshStarted.duration(to: .now))
                    try validateSnapshot(unchanged, oracle: oracle, assignment: assignment)
                    let measurement = await handle.latestRefreshMeasurement
                    #expect(measurement.readFiles == 0)
                    #expect(measurement.parsedDocuments == 0)
                    #expect(measurement.projectedDocuments == 0)
                    let currentStorage = storageSummary(at: support)
                    for kind in ["source_projection_cache", "catalog_projection_cache"] {
                        let before = try #require(retainedCacheStorage[kind] as? [String: Int64])
                        let after = try #require(currentStorage[kind] as? [String: Int64])
                        #expect(after["files"] == before["files"])
                        #expect(after["bytes"] == before["bytes"])
                    }
                    var sample = await refreshReport(handle, stage: stage, wallMilliseconds: elapsed)
                    sample["iteration"] = iteration
                    steps.append(sample)
                    try checkpoint("completed", iteration: iteration)
                }

                stage = "warm_search"
                diagnosticProgress("Large vault workspace begin: \(stage)")
                try checkpoint("begun")
                report["search"] = try await measureSearch(
                    handle, scenarios: scenarios, oracle: oracle, root: working)
                try checkpoint("completed")
                await runtime.shutdown()
            }

            // Snapshot mode uses the same production composition and explicit refresh
            // operations without racing native watcher coalescing against this controlled batch.
            let smallPaths = oracle.keys.filter { oracle[$0]!.byteCount < 32_768 }.sorted()
            try #require(smallPaths.count >= 51)
            let sourcePath = try #require(smallPaths.first)
            let batchPaths = Array(smallPaths.dropFirst().prefix(50))
            let marker = "stresscommitneedleqx"
            let batchMarker = "stressexternalneedleqx"
            let comparisonQueries = scenarios.map(\.query) + [marker, batchMarker]
            let incrementalResponses: [Data]
            let incrementalGraph: GraphSnapshot
            let incrementalManifest: String
            do {
                stage = "mutation_workspace_open"
                diagnosticProgress("Large vault workspace begin: \(stage)")
                try checkpoint("begun")
                runtime = WorkspaceRuntime(
                    configuration: .snapshot(
                        .init(
                            applicationSupportURL: support, workspaceRegistryStorageURL: registry,
                            assignments: [assignment])))
                let mutationHandle = try await runtime.openWorkspace(id: assignment.id)
                try checkpoint("completed")
                let sourceID = try noteID(sourcePath, assignment: assignment)
                let sourceURL = working.appendingPathComponent(sourcePath)
                let sourceBefore = try exactSource(at: sourceURL)
                let intended = sourceBefore + "\n\n\(marker)\n"
                let intendedFingerprint = DocumentFingerprint(content: intended)
                let sourceDocument = try await mutationHandle.documents.load(sourceID)
                let target = try await capturedSaveTarget(
                    mutationHandle, sourceID, revision: sourceDocument.fingerprint)
                let committedEvents = await mutationHandle.events.events()
                stage = "editor_source_commit"
                diagnosticProgress("Large vault workspace begin: \(stage)")
                try checkpoint("begun")
                let commitStarted = ContinuousClock.now
                let committed = try await mutationHandle.documents.commit(
                    target, changeSet: .source(intended))
                let commitMilliseconds = milliseconds(commitStarted.duration(to: .now))
                #expect(committed.document.fingerprint == intendedFingerprint)
                #expect(try Data(contentsOf: sourceURL) == Data(intended.utf8))
                let derived = try await completeSnapshot(
                    in: committedEvents, expected: [sourceID: intendedFingerprint])
                let derivedMilliseconds = milliseconds(commitStarted.duration(to: .now))
                oracle[sourcePath] = intendedFingerprint
                try validateSnapshot(derived, oracle: oracle, assignment: assignment)
                let committedMeasurement = await mutationHandle.latestRefreshMeasurement
                #expect(committedMeasurement.readFiles == 1)
                #expect(committedMeasurement.parsedDocuments == 1)
                #expect(committedMeasurement.projectedDocuments == 1)
                var commitReport = await refreshReport(
                    mutationHandle, stage: stage, wallMilliseconds: derivedMilliseconds)
                commitReport["source_commit_ms"] = commitMilliseconds
                commitReport["derived_ready_from_commit_start_ms"] = derivedMilliseconds
                commitReport["derived_after_source_return_ms"] = derivedMilliseconds - commitMilliseconds
                steps.append(commitReport)
                try await assertSentinel(
                    marker, expectedPaths: [sourcePath], handle: mutationHandle, root: working, oracle: oracle
                )
                try checkpoint("completed")

                stage = "external_batch_explicit_refresh"
                diagnosticProgress("Large vault workspace begin: \(stage)")
                try checkpoint("begun")
                for path in batchPaths {
                    let url = working.appendingPathComponent(path)
                    var bytes = try Data(contentsOf: url)
                    bytes.append(contentsOf: "\n\n\(batchMarker)\n".utf8)
                    try bytes.write(to: url, options: .atomic)
                    oracle[path] = DocumentFingerprint(data: bytes)
                }
                let batchStarted = ContinuousClock.now
                let batch = try await mutationHandle.discovery.refresh()
                let batchMilliseconds = milliseconds(batchStarted.duration(to: .now))
                try validateSnapshot(batch, oracle: oracle, assignment: assignment)
                let batchMeasurement = await mutationHandle.latestRefreshMeasurement
                #expect(batchMeasurement.readFiles == 50)
                #expect(batchMeasurement.parsedDocuments == 50)
                #expect(batchMeasurement.projectedDocuments == 50)
                steps.append(
                    await refreshReport(mutationHandle, stage: stage, wallMilliseconds: batchMilliseconds))
                try await assertSentinel(
                    batchMarker, expectedPaths: Set(batchPaths), handle: mutationHandle, root: working,
                    oracle: oracle)
                incrementalResponses = try await comparisonResponses(
                    mutationHandle, queries: comparisonQueries)
                incrementalGraph = try #require(batch.discovery.catalog.graph)
                incrementalManifest = try #require(batch.discovery.searchGeneration).sourceManifestHash
                try checkpoint("completed")
                await runtime.shutdown()
            }

            do {
                stage = "clean_index_rebuild_current_bytes"
                diagnosticProgress("Large vault workspace begin: \(stage)")
                try checkpoint("begun")
                runtime = WorkspaceRuntime(
                    configuration: .snapshot(
                        .init(
                            applicationSupportURL: rebuiltSupport,
                            workspaceRegistryStorageURL: root.appendingPathComponent("rebuilt-state/Registry"),
                            assignments: [assignment])))
                let rebuildStarted = ContinuousClock.now
                let rebuiltHandle = try await runtime.openWorkspace(id: assignment.id)
                let rebuildMilliseconds = milliseconds(rebuildStarted.duration(to: .now))
                let rebuilt = try await rebuiltHandle.snapshot()
                try validateSnapshot(rebuilt, oracle: oracle, assignment: assignment)
                let rebuiltMeasurement = await rebuiltHandle.latestRefreshMeasurement
                #expect(rebuiltMeasurement.readFiles == original.count)
                #expect(rebuiltMeasurement.parsedDocuments == original.count)
                #expect(rebuiltMeasurement.projectedDocuments == original.count)
                let rebuiltGraph = try #require(rebuilt.discovery.catalog.graph)
                #expect(rebuilt.discovery.searchGeneration?.sourceManifestHash == incrementalManifest)
                #expect(rebuiltGraph.outgoing == incrementalGraph.outgoing)
                #expect(rebuiltGraph.incoming == incrementalGraph.incoming)
                #expect(rebuiltGraph.diagnostics == incrementalGraph.diagnostics)
                let rebuiltResponses = try await comparisonResponses(
                    rebuiltHandle, queries: comparisonQueries)
                #expect(rebuiltResponses == incrementalResponses)
                steps.append(
                    await refreshReport(rebuiltHandle, stage: stage, wallMilliseconds: rebuildMilliseconds))
                try await assertSentinel(
                    marker, expectedPaths: [sourcePath], handle: rebuiltHandle, root: working, oracle: oracle)
                try await assertSentinel(
                    batchMarker, expectedPaths: Set(batchPaths), handle: rebuiltHandle, root: working,
                    oracle: oracle)
                try checkpoint("completed")
                await runtime.shutdown()
            }
            #expect(try sourceOracle(at: working) == oracle)
            #expect(try sourceOracle(at: fixture) == original)
            report["status"] = "completed"
            report["mutated_source_sha256"] = sourceDigest(oracle)
            report["steps"] = steps
            report["checkpoints"] = checkpoints
            report["process_peak_rss_bytes"] = processPeakResidentBytes()
            report["closed_application_support"] = storageSummary(at: support)
            report["closed_rebuilt_application_support"] = storageSummary(at: rebuiltSupport)
            for closedRoot in [support, rebuiltSupport] {
                let closed = storageSummary(at: closedRoot)
                for kind in ["sqlite_wal", "sqlite_shm"] {
                    #expect((closed[kind] as? [String: Int64])?["files"] == 0)
                }
            }
            report["closed_index_storage_components"] = indexStorageComponents(at: support)
            try writeReport(report, to: reportURL)
            diagnosticProgress("LARGE_VAULT_STRESS_REPORT \(reportURL.path)")
        } catch {
            report["status"] = "failed"
            report["failed_stage"] = stage
            report["error"] = String(describing: error)
            // Preserve live WAL/cache sizes before normal shutdown checkpoints
            // databases or the test-owned runtime directory is removed.
            try? checkpoint("failed", runStatus: "failed")
            await runtime.shutdown()
            report["steps"] = steps
            report["checkpoints"] = checkpoints
            report["process_peak_rss_bytes"] = processPeakResidentBytes()
            try writeReport(report, to: reportURL)
            diagnosticProgress("LARGE_VAULT_STRESS_FAILED stage=\(stage) report=\(reportURL.path)")
            throw error
        }
    }

    @Test(
        "A retained synthetic Release seed reopens through three fresh live runtimes",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_REOPEN"] == "1")
    )
    func reusableLiveReopen() async throws {
        let environment = ProcessInfo.processInfo.environment
        try #require(buildConfiguration == "SwiftPM Release")
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let buildRoot = repository.appendingPathComponent(".build", isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        let fixture = URL(fileURLWithPath: try #require(environment["SCHOLIUM_STRESS_FIXTURE"]))
            .resolvingSymlinksInPath().standardizedFileURL
        let root = buildRoot.appendingPathComponent("Release-reopen-seed", isDirectory: true)
        let working = root.appendingPathComponent("fixture", isDirectory: true)
        let support = root.appendingPathComponent("state/Application Support", isDirectory: true)
        let registry = root.appendingPathComponent("state/Registry", isDirectory: true)
        let registryFile = registry.appendingPathComponent("workspace-registration-v3.json")
        let readyURL = root.appendingPathComponent("ready.json")
        let receiptURL = root.appendingPathComponent("ready.sha256")
        let stateURL = root.appendingPathComponent("run-state.json")
        let output = buildRoot.appendingPathComponent("Release-reopen-reports", isDirectory: true)
        try #require(fixture.path.hasPrefix(buildRoot.path + "/"))
        try #require(fixture != root && !fixture.path.hasPrefix(root.path + "/"))
        try #require(!root.path.hasPrefix(fixture.path + "/"))
        try requireDiagnosticTreeWithoutLinks(fixture)
        let manifestBytes = try Data(contentsOf: fixture.appendingPathComponent("stress-manifest.json"))
        let manifest = try #require(JSONSerialization.jsonObject(with: manifestBytes) as? [String: Any])
        try #require(manifest["synthetic_nonprivate"] as? Bool == true)
        let count = try #require((manifest["counts"] as? [String: Int])?["notes"])
        try #require(count == 5_000)
        let original = try sourceOracle(at: fixture)
        try #require(original.count == count)
        let manifestFingerprint = DocumentFingerprint(data: manifestBytes)
        let scenarios = try searchScenarios(at: fixture)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let decoder = JSONDecoder()
        let manager = FileManager.default
        // Exclusive test-owned lease. An abandoned lease or incomplete seed is
        // evidence to inspect, never authority to delete or initialize it again.
        let lease = buildRoot.appendingPathComponent("Release-reopen-seed.lock")
        let leaseDescriptor = lease.path.withCString {
            Darwin.open($0, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
        }
        try #require(leaseDescriptor >= 0)
        defer {
            _ = Darwin.close(leaseDescriptor)
            try? manager.removeItem(at: lease)
        }
        try manager.createDirectory(at: output, withIntermediateDirectories: true)
        try requireDiagnosticTreeWithoutLinks(output)
        let runID = UUID().uuidString.lowercased()
        let reportURL = output.appendingPathComponent("reopen-\(runID).json")
        var stage = "seed_admission"
        var runtime: WorkspaceRuntime?
        var samples: [[String: Any]] = []
        var ownsRunState = false
        var report: [String: Any] = [
            "schema": "scholium-retained-live-reopen-v1", "status": "in_progress",
            "build_configuration": buildConfiguration, "runtime_configuration": "live",
            "sample_count": 3, "fixture_note_count": count,
            "fixture_source_sha256": sourceDigest(original),
            "fixture_source_bytes": original.values.reduce(0) { $0 + $1.byteCount },
            "operating_system": ProcessInfo.processInfo.operatingSystemVersionString,
            "physical_memory_bytes": ProcessInfo.processInfo.physicalMemory,
            "processor_count": ProcessInfo.processInfo.activeProcessorCount,
            "developer_directory": environment["DEVELOPER_DIR"] ?? "not set",
            "measurement":
                "Fresh live runtime; initial timer includes membership and authoritative selected-library source admission. Generated-index admission and maintenance follow source readiness. Presentation-to-complete uses the existing lifecycle boundary. Seed creation, source oracles, full Search/Graph comparison and shutdown are outside timers. No UI or paint claim.",
            "cache_condition":
                "One retained closed compatible seed at identical paths; same source and portable identities. OS caches are not purged. Pre-sample source validation warms filesystem caches. No retained-memory claim.",
            "search_comparison":
                "Every result page for every fixture Search oracle; complete ordered note material except generation freshness tokens, independently checked against each current snapshot.",
        ]
        func emit(_ record: [String: Any]) throws {
            let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            diagnosticProgress("LIVE_REOPEN_DIAGNOSTIC \(String(decoding: data, as: UTF8.self))")
        }
        func runState(_ status: String) throws {
            try writeReport(
                [
                    "schema": "scholium-live-reopen-seed-state-v1", "status": status,
                    "run_id": runID, "stage": stage,
                ], to: stateURL)
        }
        func requireClosedState() throws {
            let summary = storageSummary(at: support)
            try #require(summary["exists"] as? Bool == true)
            try #require(summary["enumeration_complete"] as? Bool == true)
            try #require(((summary["sqlite_database"] as? [String: Int64])?["files"] ?? 0) > 0)
            try #require(summary["skipped_symbolic_links"] as? Int == 0)
            for kind in ["sqlite_wal", "sqlite_shm"] {
                try #require((summary[kind] as? [String: Int64])?["files"] == 0)
            }
        }
        let configuration = WorkspaceRuntime.Configuration.live(
            .init(applicationSupportURL: support, workspaceRegistryStorageURL: registry))
        do {
            let existed = manager.fileExists(atPath: root.path)
            if !existed {
                // No recovery/reinitialization branch exists for a preexisting root.
                try manager.createDirectory(at: root, withIntermediateDirectories: false)
                ownsRunState = true
                stage = "seed_preparation"
                try runState("preparing")
                report["active_stage"] = stage
                try writeReport(report, to: reportURL)
                try emit([
                    "phase": "seed_preparation_begun", "build_configuration": buildConfiguration,
                    "fixture_note_count": count, "preparation_excluded": true,
                ])
                let preparationStarted = ContinuousClock.now
                try manager.copyItem(at: fixture, to: working)
                try #require(try sourceOracle(at: working) == original)
                let preparationRuntime = WorkspaceRuntime(configuration: configuration)
                runtime = preparationRuntime
                let coldStarted = ContinuousClock.now
                let handle = try await preparationRuntime.configureTriptych(
                    paperAnalysisURL: working.appendingPathComponent(slots[0]),
                    topicKnowledgeURL: working.appendingPathComponent(slots[1]),
                    outputURL: working.appendingPathComponent(slots[2]),
                    portableContainerURL: working, triptychName: "Synthetic Release Reopen Seed")
                let coldMilliseconds = milliseconds(coldStarted.duration(to: .now))
                let snapshot = try await handle.snapshot()
                try requireReopenSnapshot(snapshot, oracle: original, assignment: handle.assignment)
                let graph = try #require(snapshot.discovery.catalog.graph)
                let generation = try #require(snapshot.discovery.searchGeneration)
                let measurement = await handle.latestRefreshMeasurement
                try #require(measurement.readFiles == count)
                try #require(measurement.parsedDocuments == count)
                try #require(measurement.projectedDocuments == count)
                let search = try await completeReopenSearchResponses(
                    handle, scenarios: scenarios, oracle: original, root: working)
                let assignment = handle.assignment
                await preparationRuntime.shutdown()
                runtime = nil
                try requireClosedState()
                try #require(try sourceOracle(at: working) == original)
                try #require(try sourceOracle(at: fixture) == original)
                let ready = ReopenReadySeed(
                    schema: "scholium-live-reopen-ready-v1", status: "closed_ready",
                    buildConfiguration: buildConfiguration, fixtureManifest: manifestFingerprint,
                    sourceDigest: sourceDigest(original), oracle: original,
                    triptych: assignment.triptych,
                    vaults: Dictionary(uniqueKeysWithValues: assignment.vaults.map { ($0.key.rawValue, $0.value) }),
                    hasCommonParent: assignment.hasCommonParent,
                    registryFingerprint: DocumentFingerprint(data: try Data(contentsOf: registryFile)),
                    searchGeneration: generation, workspaceGeneration: measurement.workspaceGeneration,
                    graph: graph, searchQueries: scenarios.map(\.query), searchPages: search,
                    coldConfigurationMilliseconds: coldMilliseconds,
                    preparationMilliseconds: milliseconds(preparationStarted.duration(to: .now)))
                let bytes = try encoder.encode(ready)
                try bytes.write(to: readyURL, options: .atomic)
                try Data((DocumentFingerprint(data: bytes).sha256 + "\n").utf8)
                    .write(to: receiptURL, options: .atomic)
                try runState("closed_ready")
                ownsRunState = false
            }
            try requireDiagnosticTreeWithoutLinks(root)
            let previousState = try #require(
                JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any])
            try #require(previousState["schema"] as? String == "scholium-live-reopen-seed-state-v1")
            try #require(previousState["status"] as? String == "closed_ready")
            let readyBytes = try Data(contentsOf: readyURL)
            let readyHash = DocumentFingerprint(data: readyBytes).sha256
            let receipt = String(decoding: try Data(contentsOf: receiptURL), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            try #require(receipt == readyHash)
            let ready = try decoder.decode(ReopenReadySeed.self, from: readyBytes)
            try #require(ready.schema == "scholium-live-reopen-ready-v1" && ready.status == "closed_ready")
            try #require(ready.buildConfiguration == buildConfiguration)
            try #require(ready.fixtureManifest == manifestFingerprint)
            try #require(ready.oracle == original && ready.sourceDigest == sourceDigest(original))
            try #require(ready.searchQueries == scenarios.map(\.query))
            try #require(ready.searchPages.count == scenarios.count)
            let vaults = try Dictionary(
                uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { slot in
                    (slot, try #require(ready.vaults[slot.rawValue]))
                })
            let assignment = TriptychAssignment(
                triptych: ready.triptych, vaults: vaults, hasCommonParent: ready.hasCommonParent)
            try #require(ready.vaults.count == 3)
            for (slot, folder) in zip(WorkspaceVaultSlot.allCases, slots) {
                try #require(assignment.vault(for: slot)?.canonicalPath == working.appendingPathComponent(folder).path)
            }
            try #require(assignment.triptych.portableControlAccess?.canonicalContainerPath == working.path)
            try #require(ready.searchGeneration.triptychID == assignment.id)
            try #require(ready.searchGeneration.schemaVersion == SearchContract.schemaVersion)
            try #require(ready.searchGeneration.queryContractVersion == SearchContract.currentVersion)
            try #require(ready.searchGeneration.tokenizerPolicyVersion == SearchContract.tokenizerPolicyVersion)
            try #require(ready.searchGeneration.rankingPolicyVersion == SearchContract.rankingPolicyVersion)
            try #require(ready.graph.contractVersion == GraphSnapshot.currentContractVersion)
            try #require(
                DocumentFingerprint(
                    data: try Data(
                        contentsOf:
                            working.appendingPathComponent("stress-manifest.json"))) == manifestFingerprint)
            try #require(try sourceOracle(at: working) == original)
            try #require(DocumentFingerprint(data: try Data(contentsOf: registryFile)) == ready.registryFingerprint)
            try requireClosedState()
            report["seed_reused"] = existed
            report["seed_material_sha256"] = readyHash
            report["seed_cold_configuration_ms"] = ready.coldConfigurationMilliseconds
            report["seed_preparation_ms"] = ready.preparationMilliseconds
            try emit([
                "phase": "seed_ready", "reused": existed,
                "seed_material_sha256": readyHash, "preparation_excluded": true,
                "build_configuration": buildConfiguration,
                "cold_configuration_ms": ready.coldConfigurationMilliseconds,
                "preparation_ms": ready.preparationMilliseconds,
            ])
            ownsRunState = true
            stage = "live_reopen_samples"
            try runState("sampling")
            try writeReport(report, to: reportURL)
            var previousWorkspaceGeneration = ready.workspaceGeneration
            for iteration in 0..<3 {
                stage = "live_reopen_\(iteration)"
                try runState("sampling")
                try #require(try sourceOracle(at: working) == original)
                try #require(DocumentFingerprint(data: try Data(contentsOf: registryFile)) == ready.registryFingerprint)
                try requireClosedState()
                let sampleRuntime = WorkspaceRuntime(configuration: configuration)
                runtime = sampleRuntime
                // Start the same fresh live runtime boundary. Registry listing,
                // source probes and full oracles stay outside the usable timer.
                let started = ContinuousClock.now
                let handle = try await sampleRuntime.openWorkspace(id: assignment.id, openingVault: .paperAnalysis)
                let usable = milliseconds(started.duration(to: .now))
                let stream = await handle.events.events()
                let opening = try await handle.snapshot()
                try #require(handle.assignment == assignment)
                try #require(!opening.phase.isComplete)
                try #require(opening.discovery.searchGeneration == nil)
                let initial = await handle.latestRefreshMeasurement
                let selectedCount = original.keys.filter { $0.hasPrefix(slots[0] + "/") }.count
                try #require(initial.readFiles == selectedCount)
                try #require(initial.parsedDocuments == 0 && initial.projectedDocuments == 0)
                try #require(initial.restoredCatalogProjections == initial.readFiles)
                // Probe actual source capabilities before signalling presentation.
                // The draft is never written to disk or installed as a generation.
                let probeNote = try #require(
                    opening.vaults.flatMap(\.documents).first {
                        $0.fingerprint.byteCount < 32_768
                    })
                let loadStarted = ContinuousClock.now
                let probeDocument = try await handle.documents.load(probeNote.id)
                let firstSourceLoadMilliseconds = milliseconds(loadStarted.duration(to: .now))
                try #require(probeDocument.fingerprint == probeNote.fingerprint)
                let stableID: UUID?
                if case .resolved(let value) = probeNote.stableIdentity { stableID = value } else { stableID = nil }
                let resolvedProbeID = try #require(stableID)
                let probeMarker = "startupbufferfindqzv"
                let probeBuffer = probeDocument.rawContent + "\n\n" + probeMarker + "\n"
                let sourceRequest = SearchRequest(
                    query: probeMarker, presentationScope: .thisNote,
                    executionScope: .currentNote(
                        .init(
                            noteID: probeNote.id, stableNoteID: stableID,
                            editorSessionID: UUID(), source: probeBuffer, editorRevision: 1)),
                    limit: 20)
                let findStarted = ContinuousClock.now
                let sourceResponse = try await handle.discovery.search(sourceRequest)
                let firstBufferSearchMilliseconds = milliseconds(findStarted.duration(to: .now))
                try #require(sourceResponse.diagnostics.isEmpty && sourceResponse.results.count == 1)
                try #require(!sourceResponse.hasMore && sourceResponse.freshnessToken.rawValue.hasPrefix("note:"))
                for result in sourceResponse.results {
                    switch result {
                    case .note(let hit):
                        try #require(hit.fingerprint == DocumentFingerprint(content: probeBuffer))
                        try #require(hit.stableNoteID == resolvedProbeID.uuidString.lowercased())
                        let locator = try #require(hit.sourceRange)
                        let range = try #require(
                            Range(
                                NSRange(
                                    location: locator.utf16LowerBound,
                                    length: locator.utf16UpperBound - locator.utf16LowerBound), in: probeBuffer))
                        try #require(String(probeBuffer[range]).contains(probeMarker))
                    }
                }
                let vaultResponse = try await handle.discovery.search(
                    .init(
                        query: probeMarker, presentationScope: .currentVault,
                        executionScope: .currentVault(probeNote.id.vaultID), limit: 20))
                try #require(vaultResponse.results.isEmpty)
                let vaultSearchIsBuilding: Bool
                if case .building = vaultResponse.availability { vaultSearchIsBuilding = true } else { vaultSearchIsBuilding = false }
                try #require(vaultSearchIsBuilding)
                var triptychSearchBlocked = false
                do { _ = try await handle.discovery.search(request(probeMarker, limit: 20)) } catch ScholiumApplicationError.workspaceStillLoading {
                    triptychSearchBlocked = true
                }
                try #require(triptychSearchBlocked)
                try #require(await handle.services.searchIndexOwner.readyIndex() == nil)
                let presentationStarted = ContinuousClock.now
                let gap = milliseconds(started.duration(to: presentationStarted)) - usable
                await handle.openingPresentationDidComplete()
                let complete = try await completeSnapshot(in: stream)
                let completion = milliseconds(presentationStarted.duration(to: .now))
                let initialToComplete = milliseconds(started.duration(to: .now))
                await handle.awaitOpeningCompletionForTesting()
                try requireReopenSnapshot(complete, oracle: original, assignment: assignment)
                let measurement = await handle.latestRefreshMeasurement
                // The initial library's installed catalog is current in this
                // second pass; work counters describe only newly read sources.
                try #require(measurement.readFiles == count - selectedCount)
                try #require(initial.readFiles + measurement.readFiles == count)
                try #require(measurement.parsedDocuments == 0 && measurement.projectedDocuments == 0)
                try #require(measurement.restoredCatalogProjections == measurement.readFiles)
                try #require(initial.restoredCatalogProjections + measurement.restoredCatalogProjections == count)
                try #require(measurement.restoredSearchProjections == 0)
                try #require(measurement.workspaceGeneration > previousWorkspaceGeneration)
                previousWorkspaceGeneration = measurement.workspaceGeneration
                try #require(complete.discovery.searchGeneration == ready.searchGeneration)
                let graph = try #require(complete.discovery.catalog.graph)
                try #require(graph.contractVersion == ready.graph.contractVersion)
                try #require(graph.sourceManifestHash == ready.graph.sourceManifestHash)
                try #require(graph.outgoing == ready.graph.outgoing && graph.incoming == ready.graph.incoming)
                try #require(graph.diagnostics == ready.graph.diagnostics)
                let search = try await completeReopenSearchResponses(
                    handle, scenarios: scenarios, oracle: original, root: working)
                try #require(search == ready.searchPages)
                var sample = await refreshReport(
                    handle, stage: stage, wallMilliseconds: usable + completion)
                sample["iteration"] = iteration
                sample["usable_open_ms"] = usable
                sample["completion_after_presentation_ms"] = completion
                sample["initial_to_complete_wall_ms"] = initialToComplete
                sample["validation_gap_before_presentation_ms"] = gap
                sample["first_source_load_after_usable_ms"] = firstSourceLoadMilliseconds
                sample["first_unsaved_buffer_search_ms"] = firstBufferSearchMilliseconds
                sample["source_ready_capabilities"] = [
                    "exact_source_loaded": true, "unsaved_buffer_this_note_search": true,
                    "exact_current_buffer_locator": true,
                    "vault_search_building_without_results": true,
                    "triptych_search_blocked": true, "derived_index_not_admitted": true,
                ]
                sample["capability_probe_scope"] =
                    "Backend source load and unsaved-buffer This Note Search before presentation; no native typing, layout, paint or save timing. Probe work is reported in the pre-presentation gap."
                sample["opening_read_files"] = initial.readFiles
                sample["opening_parsed_documents"] = initial.parsedDocuments
                sample["opening_restored_catalog_projections"] = initial.restoredCatalogProjections
                sample["combined_opening_read_files"] = initial.readFiles + measurement.readFiles
                sample["combined_opening_restored_catalog_projections"] =
                    initial.restoredCatalogProjections + measurement.restoredCatalogProjections
                sample["complete_snapshot_document_count"] = complete.vaults.flatMap(\.documents).count
                sample["full_search_graph_equivalent"] = true
                sample["search_sequence"] = ready.searchGeneration.sequence
                await sampleRuntime.shutdown()
                runtime = nil
                try requireClosedState()
                try #require(try sourceOracle(at: working) == original)
                try #require(try sourceOracle(at: fixture) == original)
                try #require(DocumentFingerprint(data: try Data(contentsOf: registryFile)) == ready.registryFingerprint)
                sample["closed_journals_verified"] = true
                sample["source_unchanged"] = true
                samples.append(sample)
                report["samples"] = samples
                try writeReport(report, to: reportURL)
                try emit([
                    "phase": "sample", "iteration": iteration,
                    "usable_open_ms": usable, "completion_after_presentation_ms": completion,
                    "initial_to_complete_wall_ms": initialToComplete,
                    "validation_gap_before_presentation_ms": gap,
                    "workspace_generation": measurement.workspaceGeneration,
                    "source_and_full_search_graph_verified": true, "closed_journals_verified": true,
                ])
            }
            stage = "completed"
            try runState("closed_ready")
            report["status"] = "completed"
            report["samples"] = samples
            report["usable_open_ms"] = distribution(try samples.map { try #require($0["usable_open_ms"] as? Double) })
            report["completion_after_presentation_ms"] = distribution(
                try samples.map { try #require($0["completion_after_presentation_ms"] as? Double) })
            try writeReport(report, to: reportURL)
            ownsRunState = false
            try emit([
                "phase": "completed", "sample_count": samples.count,
                "seed_material_sha256": readyHash, "build_configuration": buildConfiguration,
            ])
        } catch {
            await runtime?.shutdown()
            runtime = nil
            // Retain uncertain or failed state for inspection. No seed deletion,
            // reconfiguration or attempt to make a failed run look ready occurs.
            if ownsRunState { try? runState("failed") }
            report["status"] = "failed"
            report["failed_stage"] = stage
            report["samples"] = samples
            try? writeReport(report, to: reportURL)
            try? emit(["phase": "failed", "stage": stage, "seed_retained": true])
            throw error
        }
    }

    @Test(
        "An exact cached large Triptych refreshes unchanged sources and one committed revision",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_STRESS_CACHED_SEED"] != nil)
    )
    func exactCachedTriptychRefreshAndCommit() async throws {
        let environment = ProcessInfo.processInfo.environment
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let buildRoot = repository.appendingPathComponent(".build", isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        let seed = URL(fileURLWithPath: try #require(environment["SCHOLIUM_STRESS_CACHED_SEED"]))
            .resolvingSymlinksInPath().standardizedFileURL
        let output = URL(
            fileURLWithPath: environment["SCHOLIUM_STRESS_CACHED_OUTPUT"]
                ?? buildRoot.appendingPathComponent("stress-audit/cached-refresh-diagnostics").path,
            isDirectory: true
        ).resolvingSymlinksInPath().standardizedFileURL
        try #require(seed.path.hasPrefix(buildRoot.path + "/"))
        try #require(output.path.hasPrefix(buildRoot.path + "/"))
        try #require(seed != output && !output.path.hasPrefix(seed.path + "/"))
        let capture = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: seed.appendingPathComponent("capture.json")))
                as? [String: Any])
        try #require(capture["closed_original_state_verified"] as? Bool == true)
        let seedFixture = seed.appendingPathComponent("fixture", isDirectory: true)
        let seedState = seed.appendingPathComponent("state", isDirectory: true)
        let manifest = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: seedFixture.appendingPathComponent("stress-manifest.json")))
                as? [String: Any])
        try #require(manifest["synthetic_nonprivate"] as? Bool == true)
        let expectedNotes = try #require((manifest["counts"] as? [String: Int])?["notes"])
        try #require((508...20_000).contains(expectedNotes))
        // The captured source includes the completed seed run's mutations.
        // Its current exact bytes, not the generator's original hashes, are
        // the compatible index's source oracle.
        let seedOracle = try sourceOracle(at: seedFixture)
        try #require(seedOracle.count == expectedNotes)
        let seedRegistryURL = seedState.appendingPathComponent("Registry/workspace-registration-v3.json")
        let seedRegistryBytes = try Data(contentsOf: seedRegistryURL)
        let runID = UUID().uuidString.lowercased()
        let root = buildRoot.appendingPathComponent("large-vault-cached-runtime/\(runID)", isDirectory: true)
        let working = root.appendingPathComponent("fixture", isDirectory: true)
        let state = root.appendingPathComponent("state", isDirectory: true)
        let support = state.appendingPathComponent("Application Support", isDirectory: true)
        let registry = state.appendingPathComponent("Registry", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(at: seedFixture, to: working)
        try FileManager.default.copyItem(at: seedState, to: state)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var oracle = try sourceOracle(at: working)
        try #require(oracle == seedOracle)
        let reportURL = output.appendingPathComponent("cached-workspace-\(runID).json")
        var report: [String: Any] = [
            "schema": "scholium-large-vault-cached-refresh-diagnostic-v1",
            "status": "in_progress",
            "fixture_note_count": expectedNotes,
            "fixture_source_bytes": seedOracle.values.reduce(0) { $0 + $1.byteCount },
            "fixture_source_sha256": sourceDigest(seedOracle),
            "seed_capture": capture,
            "build_configuration": buildConfiguration,
            "process_id": ProcessInfo.processInfo.processIdentifier,
            "operating_system": ProcessInfo.processInfo.operatingSystemVersionString,
            "developer_directory": environment["DEVELOPER_DIR"] ?? "not set",
            "measurement":
                "Real production snapshot-runtime APIs over a private disposable copy of a closed compatible index. Open/refresh timers exclude file copying, source oracles, typed rebinding and result validation. Commit observation has the additional boundary stated below. No UI, paint, cold-index or release-gate claim.",
            "commit_observation_boundary":
                "Source commit is timed through API return. Derived-ready timings are observation bounds including post-return fingerprint/byte checks and event observation, not pure derived-processing time.",
            "cache_condition":
                "Copied persisted Search and source-projection cache with the same current source bytes and portable UUIDs; a fresh runtime still reconstructs its source catalog and Graph. OS caches are not purged.",
            "binding":
                "Original copied registration is read without opening its old roots. Contracts construct one same-UUID assignment with new canonical roots and fresh vault/container bookmarks; explicit production SnapshotConfiguration owns membership. Copied machine registration bytes remain unchanged and are not used as runtime membership.",
        ]
        var steps: [[String: Any]] = []
        var stage = "typed_snapshot_rebinding"
        func checkpoint(_ status: String) throws {
            report["status"] = status
            report["active_stage"] = stage
            report["steps"] = steps
            try writeReport(report, to: reportURL)
            diagnosticProgress("Cached large vault checkpoint: \(stage), \(status)")
        }
        var runtime: WorkspaceRuntime?
        do {
            try checkpoint("in_progress")
            let registrationReader = try await WorkspaceRuntime.snapshot(
                applicationSupportURL: support, workspaceRegistryStorageURL: registry)
            runtime = registrationReader
            let assignments = try await registrationReader.availableWorkspaces()
            try #require(assignments.count == 1)
            let previous = try #require(assignments.first)
            await registrationReader.shutdown()
            runtime = nil
            var reboundVaults: [WorkspaceVaultSlot: RegisteredVault] = [:]
            for (slot, folder) in zip(WorkspaceVaultSlot.allCases, slots) {
                let previousVault = try #require(previous.vault(for: slot))
                let url = working.appendingPathComponent(folder, isDirectory: true)
                    .resolvingSymlinksInPath().standardizedFileURL
                try #require(url.path.hasPrefix(working.path + "/"))
                reboundVaults[slot] = RegisteredVault(
                    id: previousVault.id, name: previousVault.name, role: previousVault.role,
                    canonicalPath: url.path,
                    bookmarkData: try url.bookmarkData(options: [.withSecurityScope]),
                    registeredAt: previousVault.registeredAt
                )
            }
            var reboundTriptych = previous.triptych
            reboundTriptych.portableControlAccess = PortableControlAccess(
                canonicalContainerPath: working.path,
                bookmarkData: try working.bookmarkData(options: [.withSecurityScope])
            )
            let assignment = TriptychAssignment(
                triptych: reboundTriptych, vaults: reboundVaults, hasCommonParent: true)
            try #require(assignment.id == previous.id)
            for slot in WorkspaceVaultSlot.allCases {
                try #require(assignment.vault(for: slot)?.id == previous.vault(for: slot)?.id)
            }
            let cachedRuntime = WorkspaceRuntime(
                configuration: .snapshot(
                    .init(applicationSupportURL: support, workspaceRegistryStorageURL: registry, assignments: [assignment])))
            runtime = cachedRuntime
            stage = "compatible_cached_open"
            try checkpoint("in_progress")
            let openStarted = ContinuousClock.now
            let handle = try await cachedRuntime.openWorkspace(id: assignment.id)
            let openedMilliseconds = milliseconds(openStarted.duration(to: .now))
            let opened = try await handle.snapshot()
            try validateSnapshot(opened, oracle: oracle, assignment: assignment)
            let openedMeasurement = await handle.latestRefreshMeasurement
            #expect(openedMeasurement.projectedDocuments == 0)
            #expect(openedMeasurement.restoredSearchProjections == 0)
            steps.append(await refreshReport(handle, stage: stage, wallMilliseconds: openedMilliseconds))
            try checkpoint("in_progress")

            stage = "cached_unchanged_refresh"
            for iteration in 0..<3 {
                let started = ContinuousClock.now
                let unchanged = try await handle.discovery.refresh()
                let elapsed = milliseconds(started.duration(to: .now))
                try validateSnapshot(unchanged, oracle: oracle, assignment: assignment)
                let measurement = await handle.latestRefreshMeasurement
                #expect(measurement.readFiles == 0)
                #expect(measurement.parsedDocuments == 0)
                #expect(measurement.projectedDocuments == 0)
                var sample = await refreshReport(handle, stage: stage, wallMilliseconds: elapsed)
                sample["iteration"] = iteration
                steps.append(sample)
                try checkpoint("in_progress")
            }

            let sourcePath = try #require(oracle.keys.sorted().first { oracle[$0]!.byteCount < 32_768 })
            let sourceID = try noteID(sourcePath, assignment: assignment)
            let sourceURL = working.appendingPathComponent(sourcePath)
            let before = try exactSource(at: sourceURL)
            let marker = "cachedstressnewsourceqzv"
            try await assertSentinel(marker, expectedPaths: [], handle: handle, root: working, oracle: oracle)
            let intended = before + "\n\n\(marker)\n"
            let fingerprint = DocumentFingerprint(content: intended)
            let loaded = try await handle.documents.load(sourceID)
            let target = try await capturedSaveTarget(handle, sourceID, revision: loaded.fingerprint)
            let events = await handle.events.events()
            stage = "cached_editor_source_commit"
            try checkpoint("in_progress")
            let commitStarted = ContinuousClock.now
            let committed = try await handle.documents.commit(target, changeSet: .source(intended))
            let sourceMilliseconds = milliseconds(commitStarted.duration(to: .now))
            #expect(committed.document.fingerprint == fingerprint)
            #expect(try Data(contentsOf: sourceURL) == Data(intended.utf8))
            let complete = try await completeSnapshot(in: events, expected: [sourceID: fingerprint])
            let derivedMilliseconds = milliseconds(commitStarted.duration(to: .now))
            oracle[sourcePath] = fingerprint
            try validateSnapshot(complete, oracle: oracle, assignment: assignment)
            let committedMeasurement = await handle.latestRefreshMeasurement
            #expect(committedMeasurement.readFiles == 1)
            #expect(committedMeasurement.parsedDocuments == 1)
            #expect(committedMeasurement.projectedDocuments == 1)
            var commitReport = await refreshReport(handle, stage: stage, wallMilliseconds: derivedMilliseconds)
            commitReport["source_commit_ms"] = sourceMilliseconds
            commitReport["derived_ready_from_commit_start_ms"] = derivedMilliseconds
            commitReport["derived_after_source_return_ms"] = derivedMilliseconds - sourceMilliseconds
            steps.append(commitReport)
            try await assertSentinel(marker, expectedPaths: [sourcePath], handle: handle, root: working, oracle: oracle)
            try checkpoint("in_progress")
            await cachedRuntime.shutdown()
            runtime = nil
            #expect(try sourceOracle(at: working) == oracle)
            try #require(try sourceOracle(at: seedFixture) == seedOracle)
            try #require(try Data(contentsOf: seedRegistryURL) == seedRegistryBytes)
            #expect(try Data(contentsOf: registry.appendingPathComponent("workspace-registration-v3.json")) == seedRegistryBytes)
            report["final_source_sha256"] = sourceDigest(oracle)
            report["seed_source_unchanged"] = true
            stage = "completed"
            try checkpoint("completed")
            diagnosticProgress("LARGE_VAULT_CACHED_STRESS_REPORT \(reportURL.path)")
        } catch {
            report["error"] = String(describing: error)
            try? checkpoint("failed")
            await runtime?.shutdown()
            throw error
        }
    }
}

extension LargeVaultStressDiagnosticTests {
    fileprivate struct ReopenReadySeed: Codable {
        let schema: String
        let status: String
        let buildConfiguration: String
        let fixtureManifest: DocumentFingerprint
        let sourceDigest: String
        let oracle: [String: DocumentFingerprint]
        let triptych: ScholiumTriptych
        let vaults: [String: RegisteredVault]
        let hasCommonParent: Bool
        let registryFingerprint: DocumentFingerprint
        let searchGeneration: SearchGenerationID
        let workspaceGeneration: UInt64
        let graph: GraphSnapshot
        let searchQueries: [String]
        let searchPages: [[Data]]
        let coldConfigurationMilliseconds: Double
        let preparationMilliseconds: Double
    }

    fileprivate func requireDiagnosticTreeWithoutLinks(_ root: URL) throws {
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        try #require(values.isDirectory == true && values.isSymbolicLink != true)
        let files = try #require(
            FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]))
        for case let url as URL in files {
            try #require(try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true)
        }
    }

    /// The retained-ready marker requires throwing assertions; the shared
    /// lifecycle helper's nonfatal expectations remain useful to other tests.
    fileprivate func requireReopenSnapshot(
        _ snapshot: WorkspaceSnapshot, oracle: [String: DocumentFingerprint],
        assignment: TriptychAssignment
    ) throws {
        try validateSnapshot(snapshot, oracle: oracle, assignment: assignment)
        try #require(snapshot.phase.isComplete && snapshot.vaults.count == 3)
        let summaries = snapshot.vaults.flatMap(\.documents)
        try #require(summaries.count == oracle.count)
        for summary in summaries {
            let path = try sourcePath(summary.id, assignment: assignment)
            try #require(summary.fingerprint == oracle[path] && summary.stableIdentity.resolvedID != nil)
        }
        let manifest = SearchSourceManifest.hash(
            summaries.map {
                SearchSourceManifestEntry(vaultID: $0.id.vaultID, relativePath: $0.id.relativePath, fingerprint: $0.fingerprint)
            })
        try #require(snapshot.discovery.searchGeneration?.sourceManifestHash == manifest)
        try #require(snapshot.discovery.catalog.graph?.sourceManifestHash == manifest)
        try #require(snapshot.research.healthIssues.isEmpty)
    }

    /// Full result material, including all pages; no ranked prefix is mistaken
    /// for complete Search equivalence. Only current-generation tokens differ.
    fileprivate func completeReopenSearchResponses(
        _ handle: WorkspaceHandle, scenarios: [SearchScenario],
        oracle: [String: DocumentFingerprint], root: URL
    ) async throws -> [[Data]] {
        // One generation owns the complete multi-query, multi-page comparison.
        let expectedGeneration: SearchGenerationID = try #require(
            (try await handle.snapshot()).discovery.searchGeneration)
        var queries: [[Data]] = []
        for scenario in scenarios {
            var pages: [Data] = []
            var offset = 0
            var seen: Set<VaultQualifiedNoteID> = []
            var paths: Set<String> = []
            while true {
                let response = try await handle.discovery.search(
                    SearchRequest(
                        query: scenario.query, presentationScope: .triptych, executionScope: .triptych,
                        limit: SearchContract.maximumNoteResults, offset: offset))
                try #require((try await handle.snapshot()).discovery.searchGeneration == expectedGeneration)
                try #require(response.availability == .current(expectedGeneration))
                try #require(response.freshnessToken == .triptych(expectedGeneration))
                try #require(response.diagnostics.isEmpty && response.indeterminateDocumentCount == 0)
                try #require(response.totalResultCount == scenario.expectedCount)
                for result in response.results {
                    switch result {
                    case .note(let note):
                        try #require(seen.insert(note.noteReference).inserted)
                        let path = try sourcePath(note.noteReference, assignment: handle.assignment)
                        paths.insert(path)
                        try #require(note.fingerprint == oracle[path] && note.stableNoteID != nil)
                        try #require(note.freshnessToken == response.freshnessToken)
                        let source = try exactSource(at: root.appendingPathComponent(path))
                        for range in note.paragraphRanges + (note.sourceRange.map { [$0] } ?? []) {
                            try #require(range.utf16LowerBound >= 0 && range.utf16UpperBound >= range.utf16LowerBound)
                            try #require(
                                Range(
                                    NSRange(
                                        location: range.utf16LowerBound,
                                        length: range.utf16UpperBound - range.utf16LowerBound), in: source) != nil)
                        }
                    }
                }
                pages.append(try comparableResponse(response))
                offset += response.results.count
                try #require(offset <= oracle.count)
                if !response.hasMore { break }
                try #require(!response.results.isEmpty && offset < scenario.expectedCount)
            }
            try #require(offset == scenario.expectedCount)
            if let expected = scenario.expectedPaths { try #require(paths == Set(expected)) }
            queries.append(pages)
        }
        try #require((try await handle.snapshot()).discovery.searchGeneration == expectedGeneration)
        return queries
    }

    fileprivate var slots: [String] { ["01-analyses", "02-topics", "03-works"] }

    fileprivate var buildConfiguration: String {
        #if DEBUG
            "SwiftPM Debug"
        #else
            "SwiftPM Release"
        #endif
    }

    fileprivate struct SearchScenario: Decodable, Sendable {
        let label: String
        let query: String
        let expectedCount: Int
        let expectedPaths: [String]?
    }

    fileprivate func searchScenarios(at root: URL) throws -> [SearchScenario] {
        let manifest =
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: root.appendingPathComponent("stress-manifest.json")))
            as? [String: Any]
        let oracles = try #require(manifest?["search_oracles"] as? [[String: Any]])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let scenarios = try decoder.decode(
            [SearchScenario].self, from: JSONSerialization.data(withJSONObject: oracles))
        try #require(scenarios.count >= 5)
        return scenarios
    }

    fileprivate func sourceOracle(at root: URL) throws -> [String: DocumentFingerprint] {
        var records: [String: DocumentFingerprint] = [:]
        for slot in slots {
            let vault = root.appendingPathComponent(slot, isDirectory: true)
            let enumerator = try #require(
                FileManager.default.enumerator(at: vault, includingPropertiesForKeys: [.isRegularFileKey]))
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "md" {
                guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                    continue
                }
                records[String(url.path.dropFirst(root.path.count + 1))] = DocumentFingerprint(
                    data: try Data(contentsOf: url))
            }
        }
        return records
    }

    fileprivate func sourceDigest(_ oracle: [String: DocumentFingerprint]) -> String {
        let records = oracle.keys.sorted().map {
            "\($0)\u{1F}\(oracle[$0]!.sha256)\u{1F}\(oracle[$0]!.byteCount)"
        }
        return DocumentFingerprint(content: records.joined(separator: "\u{1E}")).sha256
    }

    fileprivate func exactSource(at url: URL) throws -> String {
        let bytes = try Data(contentsOf: url)
        let source = String(decoding: bytes, as: UTF8.self)
        // Locator offsets include an authored BOM. Avoid Foundation's text-file
        // decoding, and prove that the oracle did not normalize any source byte.
        try #require(Data(source.utf8) == bytes)
        return source
    }

    fileprivate func noteID(_ path: String, assignment: TriptychAssignment) throws
        -> VaultQualifiedNoteID
    {
        let parts = path.split(separator: "/", maxSplits: 1).map(String.init)
        try #require(parts.count == 2)
        let index = try #require(slots.firstIndex(of: parts[0]))
        let slot = WorkspaceVaultSlot.allCases[index]
        return VaultQualifiedNoteID(
            vaultID: try #require(assignment.vault(for: slot)).id, relativePath: parts[1])
    }

    fileprivate func sourcePath(_ id: VaultQualifiedNoteID, assignment: TriptychAssignment) throws
        -> String
    {
        let index = try #require(
            WorkspaceVaultSlot.allCases.firstIndex { assignment.vault(for: $0)?.id == id.vaultID })
        return slots[index] + "/" + id.relativePath
    }

    fileprivate func validateSnapshot(
        _ snapshot: WorkspaceSnapshot, oracle: [String: DocumentFingerprint],
        assignment: TriptychAssignment
    ) throws {
        try #require(snapshot.phase.isComplete)
        #expect(snapshot.vaults.count == 3)
        let summaries = snapshot.vaults.flatMap(\.documents)
        #expect(summaries.count == oracle.count)
        for summary in summaries {
            let path = try sourcePath(summary.id, assignment: assignment)
            #expect(summary.fingerprint == oracle[path])
            #expect(summary.stableIdentity.resolvedID != nil)
        }
        let generation = try #require(snapshot.discovery.searchGeneration)
        let graph = try #require(snapshot.discovery.catalog.graph)
        let manifest = SearchSourceManifest.hash(
            summaries.map {
                SearchSourceManifestEntry(
                    vaultID: $0.id.vaultID, relativePath: $0.id.relativePath, fingerprint: $0.fingerprint)
            })
        #expect(generation.sourceManifestHash == manifest)
        #expect(graph.sourceManifestHash == manifest)
        #expect(snapshot.research.healthIssues.isEmpty)
    }

    fileprivate enum DiagnosticError: Error {
        case derivedRefreshFailed(String)
        case eventStreamEnded
        case timedOut
    }

    fileprivate func completeSnapshot(
        in stream: AsyncStream<WorkspaceEvent>,
        expected: [VaultQualifiedNoteID: DocumentFingerprint] = [:]
    ) async throws -> WorkspaceSnapshot {
        try await withThrowingTaskGroup(of: WorkspaceSnapshot.self) { group in
            group.addTask {
                for await event in stream {
                    if case .failed(let issue) = event.derivedRefreshStatus {
                        throw DiagnosticError.derivedRefreshFailed(issue.reason)
                    }
                    if case .stale(let issue) = event.derivedRefreshStatus {
                        throw DiagnosticError.derivedRefreshFailed(issue.reason)
                    }
                    guard event.snapshot.phase.isComplete,
                        expected.allSatisfy({ event.snapshot.document(id: $0.key)?.fingerprint == $0.value })
                    else { continue }
                    return event.snapshot
                }
                throw DiagnosticError.eventStreamEnded
            }
            group.addTask {
                try await Task.sleep(for: .seconds(300))
                throw DiagnosticError.timedOut
            }
            defer { group.cancelAll() }
            return try #require(try await group.next())
        }
    }

    fileprivate func refreshReport(_ handle: WorkspaceHandle, stage: String, wallMilliseconds: Double)
        async -> [String: Any]
    {
        let value = await handle.latestRefreshMeasurement
        var record: [String: Any] = [
            "stage": stage, "wall_ms": wallMilliseconds,
            "workspace_generation": value.workspaceGeneration,
            "enumerated_files": value.enumeratedFiles, "read_files": value.readFiles,
            "parsed_documents": value.parsedDocuments, "projected_documents": value.projectedDocuments,
            "restored_catalog_projections": value.restoredCatalogProjections,
            "restored_search_projections": value.restoredSearchProjections,
            "enumeration_work_ms": milliseconds(value.enumerationDuration),
            "read_work_ms": milliseconds(value.readDuration),
            "parse_work_ms": milliseconds(value.parseDuration),
            "catalog_cache_read_work_ms": milliseconds(value.catalogCacheReadDuration),
            "catalog_cache_write_work_ms": milliseconds(value.catalogCacheWriteDuration),
            "projection_work_ms": milliseconds(value.projectionDuration),
            "cache_read_work_ms": milliseconds(value.cacheReadDuration),
            "cache_write_work_ms": milliseconds(value.cacheWriteDuration),
            "identity_ms": milliseconds(value.identityProjectionDuration),
            "link_catalog_ms": milliseconds(value.linkCatalogProjectionDuration),
            "graph_ms": milliseconds(value.graphDuration),
            "search_document_projection_ms": milliseconds(value.searchDocumentProjectionDuration),
            "search_ms": milliseconds(value.searchDuration),
            "snapshot_assembly_ms": milliseconds(value.snapshotAssemblyDuration),
            "builder_total_ms": milliseconds(value.totalDuration),
            "snapshot_source_bytes": value.snapshotSourceBytes,
        ]
        if let cycle = await handle.latestRefreshCycleMeasurement,
            cycle.workspaceGeneration == value.workspaceGeneration
        {
            record["source_preparation_ms"] = milliseconds(cycle.sourcePreparationDuration)
            record["index_generation_wait_ms"] = milliseconds(cycle.indexGenerationWaitDuration)
            record["gate_wait_ms"] = milliseconds(cycle.gateWaitDuration)
            record["source_capture_lease_ms"] = milliseconds(cycle.sourceCaptureLeaseDuration)
            record["source_catalog_installation_leases_ms"] = milliseconds(cycle.sourceCatalogInstallationLeaseDuration)
            record["longest_source_catalog_installation_lease_ms"] = milliseconds(cycle.longestSourceCatalogInstallationLeaseDuration)
            record["publication_gate_wait_ms"] = milliseconds(cycle.publicationGateWaitDuration)
            record["review_initialization_ms"] = milliseconds(cycle.reviewInitializationDuration)
            record["publication_lease_ms"] = milliseconds(cycle.publicationLeaseDuration)
            record["publication_ms"] = milliseconds(cycle.publicationDuration)
            record["cycle_ms"] = milliseconds(cycle.totalDuration)
        }
        diagnosticProgress(
            "Large vault workspace phase: \(stage), \(String(format: "%.1f", wallMilliseconds)) ms")
        return record
    }

    fileprivate func measureSearch(
        _ handle: WorkspaceHandle, scenarios: [SearchScenario], oracle: [String: DocumentFingerprint],
        root: URL
    ) async throws -> [[String: Any]] {
        var reports: [[String: Any]] = []
        for scenario in scenarios {
            diagnosticProgress("Large vault Search begin: \(scenario.label)")
            let baseline = try await handle.discovery.search(request(scenario.query))
            try await validateSearch(baseline, handle: handle, root: root, oracle: oracle)
            #expect(baseline.totalResultCount == scenario.expectedCount)
            if let expectedPaths = scenario.expectedPaths {
                let paths = try baseline.results.map { result in
                    switch result {
                    case .note(let note):
                        return try sourcePath(note.noteReference, assignment: handle.assignment)
                    }
                }
                #expect(Set(paths) == Set(expectedPaths))
            }
            var freshSamples: [Double] = []
            var repeatedSamples: [Double] = []
            for iteration in 0..<23 {
                let query = scenario.query + " -keyword:stressabsentquery\(iteration)"
                let started = ContinuousClock.now
                let response = try await handle.discovery.search(request(query))
                let freshMilliseconds = milliseconds(started.duration(to: .now))
                let repeatedStarted = ContinuousClock.now
                let repeated = try await handle.discovery.search(request(query))
                let repeatedMilliseconds = milliseconds(repeatedStarted.duration(to: .now))
                #expect(response.results.map(\.id) == baseline.results.map(\.id))
                #expect(response.totalResultCount == scenario.expectedCount)
                #expect(repeated.results == response.results)
                #expect(repeated.totalResultCount == response.totalResultCount)
                #expect(response.freshnessToken == baseline.freshnessToken)
                #expect(response.diagnostics.isEmpty)
                if iteration >= 3 {
                    freshSamples.append(freshMilliseconds)
                    repeatedSamples.append(repeatedMilliseconds)
                }
                if iteration == 2 || (iteration >= 3 && (iteration - 2) % 5 == 0) {
                    diagnosticProgress(
                        "Large vault Search progress: \(scenario.label), \(freshSamples.count)/20 measured pairs"
                    )
                }
            }
            reports.append([
                "scenario": scenario.label, "expected_result_count": scenario.expectedCount,
                "sample_count": freshSamples.count, "fresh_query_ms": distribution(freshSamples),
                "immediate_repeat_ms": distribution(repeatedSamples),
                "fresh_query_samples_ms": freshSamples, "immediate_repeat_samples_ms": repeatedSamples,
                "ordered_base_result_sha256": DocumentFingerprint(data: try comparableResponse(baseline))
                    .sha256,
            ])
            diagnosticProgress(
                "Large vault Search scenario: \(scenario.label), fresh p95 \(String(format: "%.1f", distribution(freshSamples)["p95"]!)) ms"
            )
        }
        return reports
    }

    fileprivate func validateSearch(
        _ response: SearchResponse, handle: WorkspaceHandle, root: URL,
        oracle: [String: DocumentFingerprint]
    ) async throws {
        #expect(response.diagnostics.isEmpty)
        #expect(response.indeterminateDocumentCount == 0)
        guard case .current(let generation) = response.availability else {
            Issue.record("A complete workspace did not provide current Search")
            return
        }
        let snapshot = try await handle.snapshot()
        #expect(generation == snapshot.discovery.searchGeneration)
        #expect(response.freshnessToken == .triptych(generation))
        for result in response.results {
            switch result {
            case .note(let note):
                let path = try sourcePath(note.noteReference, assignment: handle.assignment)
                #expect(note.fingerprint == oracle[path])
                #expect(note.freshnessToken == response.freshnessToken)
                #expect(note.stableNoteID != nil)
                let source = try exactSource(at: root.appendingPathComponent(path))
                for range in note.paragraphRanges + (note.sourceRange.map { [$0] } ?? []) {
                    try #require(range.utf16LowerBound >= 0 && range.utf16UpperBound >= range.utf16LowerBound)
                    #expect(
                        Range(
                            NSRange(
                                location: range.utf16LowerBound,
                                length: range.utf16UpperBound - range.utf16LowerBound), in: source) != nil)
                }
            }
        }
    }

    fileprivate func assertSentinel(
        _ marker: String, expectedPaths: Set<String>, handle: WorkspaceHandle, root: URL,
        oracle: [String: DocumentFingerprint]
    ) async throws {
        let response = try await handle.discovery.search(request(marker, limit: 100))
        try await validateSearch(response, handle: handle, root: root, oracle: oracle)
        #expect(response.totalResultCount == expectedPaths.count)
        var paths: Set<String> = []
        for result in response.results {
            switch result {
            case .note(let note):
                let path = try sourcePath(note.noteReference, assignment: handle.assignment)
                paths.insert(path)
                let source = try exactSource(at: root.appendingPathComponent(path))
                let locator = try #require(note.sourceRange)
                let range = try #require(
                    Range(
                        NSRange(
                            location: locator.utf16LowerBound,
                            length: locator.utf16UpperBound - locator.utf16LowerBound), in: source))
                #expect(String(source[range]).contains(marker))
            }
        }
        #expect(paths == expectedPaths)
    }

    fileprivate func request(_ query: String, limit: Int = 50) -> SearchRequest {
        SearchRequest(
            query: query, presentationScope: .triptych, executionScope: .triptych, limit: limit)
    }

    fileprivate func comparisonResponses(_ handle: WorkspaceHandle, queries: [String]) async throws
        -> [Data]
    {
        var responses: [Data] = []
        for query in queries {
            responses.append(
                try comparableResponse(try await handle.discovery.search(request(query, limit: 100))))
        }
        return responses
    }

    fileprivate func comparableResponse(_ response: SearchResponse) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let results = try response.results.map { result -> [String: Any] in
            switch result {
            case .note(let note):
                var record = try #require(
                    JSONSerialization.jsonObject(with: encoder.encode(note)) as? [String: Any])
                record.removeValue(forKey: "freshnessToken")
                return record
            }
        }
        return try JSONSerialization.data(
            withJSONObject: [
                "results": results, "total": response.totalResultCount ?? -1, "has_more": response.hasMore,
            ],
            options: [.sortedKeys])
    }

    fileprivate func distribution(_ samples: [Double]) -> [String: Double] {
        let ordered = samples.sorted()
        return [
            "p50": ordered[max(0, Int(ceil(Double(ordered.count) * 0.50)) - 1)],
            "p95": ordered[max(0, Int(ceil(Double(ordered.count) * 0.95)) - 1)],
            "min": ordered.first ?? .infinity, "max": ordered.last ?? .infinity,
        ]
    }

    fileprivate func milliseconds(_ duration: Duration) -> Double {
        let value = duration.components
        return Double(value.seconds) * 1_000 + Double(value.attoseconds) / 1e15
    }

    fileprivate func processPeakResidentBytes() -> Int64 {
        var usage = rusage()
        return getrusage(RUSAGE_SELF, &usage) == 0 ? Int64(usage.ru_maxrss) : -1
    }

    fileprivate func diagnosticProgress(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }

    fileprivate struct StorageTotals {
        var files: Int64 = 0
        var bytes: Int64 = 0
        var allocatedBytes: Int64 = 0
        var allocationUnknownFiles: Int64 = 0
    }

    /// Metadata/aggregate byte counts only, after shutdown and outside timers.
    fileprivate func indexStorageComponents(at root: URL) -> [[String: Any]] {
        guard
            let entries = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        else { return [] }
        var reports: [[String: Any]] = []
        for case let url as URL in entries where url.pathExtension == "sqlite" {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                values.isRegularFile == true, values.isSymbolicLink != true
            else { continue }
            var database: OpaquePointer?
            guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
                if let database { sqlite3_close(database) }
                reports.append(["readable": false])
                continue
            }
            defer { sqlite3_close(database) }
            var report: [String: Any] = ["readable": true]
            func aggregate(_ sql: String, keys: [String]) {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                    if let statement { sqlite3_finalize(statement) }
                    return
                }
                defer { sqlite3_finalize(statement) }
                guard sqlite3_step(statement) == SQLITE_ROW else { return }
                for (index, key) in keys.enumerated() { report[key] = sqlite3_column_int64(statement, Int32(index)) }
            }
            aggregate("PRAGMA page_count;", keys: ["page_count"])
            aggregate("PRAGMA page_size;", keys: ["page_size"])
            aggregate("PRAGMA freelist_count;", keys: ["free_pages"])
            aggregate(
                "SELECT count(*), sum(length(paragraphs)), sum(length(related_projection)), sum(length(related_lexical)), sum(length(cast(line_starts AS BLOB))) FROM search_documents;",
                keys: ["documents", "paragraph_blob_bytes", "related_source_bytes", "related_lexical_bytes", "line_starts_bytes"])
            aggregate(
                "SELECT count(*), sum(length(offset_map)), sum(length(cast(text AS BLOB))), sum(length(cast(normalized_text AS BLOB))), sum(length(cast(related_ranking_text AS BLOB))) FROM search_segments;",
                keys: ["segments", "segment_offset_bytes", "segment_text_bytes", "segment_normalized_bytes", "segment_ranking_bytes"])
            aggregate("SELECT sum(length(block)) FROM search_fts_data;", keys: ["fts_data_bytes"])
            reports.append(report)
        }
        return reports
    }

    fileprivate func storageSummary(at root: URL) -> [String: Any] {
        let labels = [
            "sqlite_database", "sqlite_wal", "sqlite_shm", "source_projection_cache", "catalog_projection_cache", "other",
        ]
        var groups = Dictionary(uniqueKeysWithValues: labels.map { ($0, StorageTotals()) })
        var totals = StorageTotals()
        var unreadableEntries = 0
        var symbolicLinks = 0
        let exists = FileManager.default.fileExists(atPath: root.path)
        var enumerated = !exists
        if exists,
            let entries = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .totalFileAllocatedSizeKey],
                errorHandler: { _, _ in
                    unreadableEntries += 1
                    return true
                })
        {
            enumerated = true
            for case let url as URL in entries {
                do {
                    let values = try url.resourceValues(forKeys: [
                        .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .totalFileAllocatedSizeKey,
                    ])
                    if values.isSymbolicLink == true {
                        symbolicLinks += 1
                        entries.skipDescendants()
                        continue
                    }
                    guard values.isRegularFile == true else { continue }
                    guard let size = values.fileSize else {
                        unreadableEntries += 1
                        continue
                    }
                    let name = url.lastPathComponent.lowercased()
                    let group: String
                    if name.hasSuffix(".sqlite-wal") {
                        group = "sqlite_wal"
                    } else if name.hasSuffix(".sqlite-shm") {
                        group = "sqlite_shm"
                    } else if name.hasSuffix(".sqlite") {
                        group = "sqlite_database"
                    } else if name.hasSuffix(".projection.plist") {
                        group = "source_projection_cache"
                    } else if name.hasSuffix(".catalog.plist") {
                        group = "catalog_projection_cache"
                    } else {
                        group = "other"
                    }
                    var count = groups[group]!
                    count.files += 1
                    count.bytes += Int64(size)
                    count.allocatedBytes += Int64(values.totalFileAllocatedSize ?? 0)
                    if values.totalFileAllocatedSize == nil { count.allocationUnknownFiles += 1 }
                    groups[group] = count
                    totals.files += 1
                    totals.bytes += Int64(size)
                    totals.allocatedBytes += Int64(values.totalFileAllocatedSize ?? 0)
                    if values.totalFileAllocatedSize == nil { totals.allocationUnknownFiles += 1 }
                } catch {
                    unreadableEntries += 1
                }
            }
        }
        var result: [String: Any] = [
            "exists": exists, "enumeration_complete": enumerated && unreadableEntries == 0,
            "files": totals.files, "bytes": totals.bytes,
            "allocated_bytes": totals.allocatedBytes, "allocation_unknown_files": totals.allocationUnknownFiles,
            "unreadable_entries": unreadableEntries, "skipped_symbolic_links": symbolicLinks,
        ]
        for label in labels {
            let count = groups[label]!
            result[label] = [
                "files": count.files, "bytes": count.bytes,
                "allocated_bytes": count.allocatedBytes, "allocation_unknown_files": count.allocationUnknownFiles,
            ]
        }
        return result
    }

    fileprivate func writeReport(_ report: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: url, options: .atomic)
    }
}
