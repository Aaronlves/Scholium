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
        "Large mixed-content Triptych retains complete current generations through its lifecycle",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_STRESS_FIXTURE"] != nil)
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
                "Metadata-only logical file sizes under each application-support root; not allocated blocks or process memory. Snapshots are outside operation timers.",
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
                let stream = await handle.events.events()
                let completionStarted = ContinuousClock.now
                await handle.openingPresentationDidComplete()
                let complete = try await completeSnapshot(in: stream)
                let completionMilliseconds = milliseconds(completionStarted.duration(to: .now))
                await handle.awaitOpeningCompletionForTesting()
                try validateSnapshot(complete, oracle: oracle, assignment: assignment)
                let reopened = await handle.latestRefreshMeasurement
                #expect(reopened.projectedDocuments == 0)
                #expect(reopened.restoredSearchProjections == 0)
                var reopenReport = await refreshReport(
                    handle, stage: stage, wallMilliseconds: usableMilliseconds + completionMilliseconds)
                reopenReport["usable_open_ms"] = usableMilliseconds
                reopenReport["completion_after_presentation_ms"] = completionMilliseconds
                steps.append(reopenReport)
                try checkpoint("completed")

                stage = "unchanged_refresh"
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
            "restored_search_projections": value.restoredSearchProjections,
            "enumeration_work_ms": milliseconds(value.enumerationDuration),
            "read_work_ms": milliseconds(value.readDuration),
            "parse_work_ms": milliseconds(value.parseDuration),
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
            "sqlite_database", "sqlite_wal", "sqlite_shm", "source_projection_cache", "other",
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
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                errorHandler: { _, _ in
                    unreadableEntries += 1
                    return true
                })
        {
            enumerated = true
            for case let url as URL in entries {
                do {
                    let values = try url.resourceValues(forKeys: [
                        .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
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
                    } else {
                        group = "other"
                    }
                    var count = groups[group]!
                    count.files += 1
                    count.bytes += Int64(size)
                    groups[group] = count
                    totals.files += 1
                    totals.bytes += Int64(size)
                } catch {
                    unreadableEntries += 1
                }
            }
        }
        var result: [String: Any] = [
            "exists": exists, "enumeration_complete": enumerated && unreadableEntries == 0,
            "files": totals.files, "bytes": totals.bytes,
            "unreadable_entries": unreadableEntries, "skipped_symbolic_links": symbolicLinks,
        ]
        for label in labels {
            let count = groups[label]!
            result[label] = ["files": count.files, "bytes": count.bytes]
        }
        return result
    }

    fileprivate func writeReport(_ report: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: url, options: .atomic)
    }
}
