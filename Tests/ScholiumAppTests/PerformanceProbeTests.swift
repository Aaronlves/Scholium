import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

#if DEBUG
    import WebKit
#endif

@Suite("Performance probe")
@MainActor
struct PerformanceProbeTests {
    #if DEBUG
        @Test("Editor phase exports require QA isolation and remain bounded and content-free")
        func qaEditorWorkIsolationAndBounds() throws {
            let fixture = try makeQAReaderFailureFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let result = fixture.home.appendingPathComponent("qa-editor-work.jsonl")
            let sample = MarkdownEditorPerformanceSample(
                name: "projection-index-map", durationMilliseconds: 1.25,
                observed: [
                    "documentLength": 500, "semanticMapMilliseconds": 0.5,
                    "private-field": 12, "inlineCount": .infinity,
                ])
            var disabled = fixture.environment
            disabled["SCHOLIUM_QA_MEMORY_OWNER_DIAGNOSTICS"] = nil
            for (environment, identity) in [
                (disabled, ScholiumRuntimeIsolation.qaBundleIdentifier),
                (fixture.environment, ScholiumRuntimeIsolation.productionBundleIdentifier),
            ] {
                PerformanceProbe(environment: environment, bundleID: identity, bundleURL: fixture.bundle)
                    .recordQAEditorWork([sample])
                #expect(!FileManager.default.fileExists(atPath: result.path))
            }
            let probe = PerformanceProbe(
                environment: fixture.environment,
                bundleID: ScholiumRuntimeIsolation.qaBundleIdentifier, bundleURL: fixture.bundle)
            probe.recordQAEditorWork(Array(repeating: sample, count: 257))
            probe.recordQAEditorWork([.init(name: "untrusted source text", durationMilliseconds: 1, observed: [:])])
            #expect(!FileManager.default.fileExists(atPath: result.path))
            for _ in 0..<20 { probe.recordQAEditorWork([sample]) }
            let data = try Data(contentsOf: result)
            let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
            #expect(lines.count == 16)
            for line in lines {
                let object = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
                let values = try #require(object["measurements"] as? [[String: Any]])
                let observed = try #require(values.first?["observed"] as? [String: Double])
                #expect(observed == ["documentLength": 500, "semanticMapMilliseconds": 0.5])
            }
            try FileManager.default.removeItem(at: result)
            let protected = fixture.root.appendingPathComponent("untouched.jsonl")
            let original = Data("unchanged".utf8)
            try original.write(to: protected)
            try FileManager.default.createSymbolicLink(at: result, withDestinationURL: protected)
            let fresh = PerformanceProbe(
                environment: fixture.environment,
                bundleID: ScholiumRuntimeIsolation.qaBundleIdentifier, bundleURL: fixture.bundle)
            fresh.recordQAEditorWork([sample])
            #expect(try Data(contentsOf: protected) == original)
        }

        @Test("Save stage diagnostics require the existing synthetic QA authorization")
        func qaSaveStagesRequireExistingIsolation() throws {
            let fixture = try makeQAReaderFailureFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let result = fixture.home.appendingPathComponent("qa-save-stages.jsonl")
            var disabled = fixture.environment
            disabled["SCHOLIUM_QA_MEMORY_OWNER_DIAGNOSTICS"] = nil
            var vaultHome = fixture.environment
            vaultHome["SCHOLIUM_HOME"] = fixture.environment["SCHOLIUM_UI_TEST_WORKSPACE_ROOT"]
            for (environment, bundleID) in [
                (disabled, ScholiumRuntimeIsolation.qaBundleIdentifier),
                (fixture.environment, ScholiumRuntimeIsolation.productionBundleIdentifier),
                (vaultHome, ScholiumRuntimeIsolation.qaBundleIdentifier),
            ] {
                let probe = PerformanceProbe(
                    environment: environment, bundleID: bundleID, bundleURL: fixture.bundle)
                var payloadEvaluations = 0
                func flags() -> [PerformanceProbe.QASaveFlag: Bool] {
                    payloadEvaluations += 1
                    return [.actionsPresent: true]
                }
                func counts() -> [PerformanceProbe.QASaveCount: Int] {
                    payloadEvaluations += 1
                    return [.generation: 0]
                }
                probe.recordQASaveStage(.nativeMenuEntry, flags: flags(), counts: counts())
                #expect(payloadEvaluations == 0)
                #expect(!FileManager.default.fileExists(atPath: result.path))
            }
        }

        @Test("Save stage diagnostics contain closed scalar metadata and stop after 512 records")
        func qaSaveStagesArePrivateAndBounded() throws {
            let fixture = try makeQAReaderFailureFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let probe = PerformanceProbe(
                environment: fixture.environment, bundleID: ScholiumRuntimeIsolation.qaBundleIdentifier,
                bundleURL: fixture.bundle, now: { 42 })
            let sessionID = UUID()
            let saveToken = UUID()
            probe.recordQASaveStage(.controllerSnapshot, counts: [.generation: -1])
            var flagEvaluations = 0
            var countEvaluations = 0
            func flags() -> [PerformanceProbe.QASaveFlag: Bool] {
                flagEvaluations += 1
                return [.dirty: true, .sourceMatchesCommitted: false]
            }
            func counts(_ generation: Int) -> [PerformanceProbe.QASaveCount: Int] {
                countEvaluations += 1
                return [.generation: generation, .snapshotGeneration: generation]
            }
            for generation in 0..<520 {
                probe.recordQASaveStage(
                    .controllerSnapshot, sessionID: sessionID, saveToken: saveToken,
                    flags: flags(), counts: counts(generation))
            }
            #expect(flagEvaluations == 512)
            #expect(countEvaluations == 512)
            let data = try Data(contentsOf: fixture.home.appendingPathComponent("qa-save-stages.jsonl"))
            let text = try #require(String(data: data, encoding: .utf8))
            let objects = try text.split(separator: "\n").map {
                try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
            }
            #expect(objects.count == 512)
            #expect(data.count <= 512 * 1_024)
            #expect(objects.compactMap { $0["sample"] as? Int } == Array(0..<512))
            #expect(
                objects.compactMap { ($0["counts"] as? [String: Int])?["generation"] } == Array(0..<512))
            let keys: Set<String> = [
                "schema", "sample", "completed_uptime_ns", "stage", "flags", "counts", "session_id",
                "save_token",
            ]
            #expect(objects.allSatisfy { Set($0.keys) == keys })
            #expect(objects.allSatisfy { $0["schema"] as? String == "scholium-qa-save-stages-v1" })
            #expect(objects.allSatisfy { $0["completed_uptime_ns"] as? Int == 42 })
            #expect(objects.allSatisfy { $0["stage"] as? String == "controller_snapshot" })
            #expect(objects.allSatisfy { $0["session_id"] as? String == sessionID.uuidString })
            #expect(objects.allSatisfy { $0["save_token"] as? String == saveToken.uuidString })
            #expect(
                objects.allSatisfy {
                    $0["flags"] as? [String: Bool] == ["dirty": true, "source_matches_committed": false]
                })
            #expect(!text.contains(fixture.root.path))
        }

        @Test("Save stage artifacts reject symlinks and an already full destination")
        func qaSaveStagesRejectUnsafeOrFullDestination() throws {
            let fixture = try makeQAReaderFailureFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let probe = PerformanceProbe(
                environment: fixture.environment, bundleID: ScholiumRuntimeIsolation.qaBundleIdentifier,
                bundleURL: fixture.bundle)
            let result = fixture.home.appendingPathComponent("qa-save-stages.jsonl")
            let outsideHome = fixture.root.appendingPathComponent("outside-home.jsonl")
            try FileManager.default.createSymbolicLink(at: result, withDestinationURL: outsideHome)
            probe.recordQASaveStage(.nativeMenuEntry)
            #expect(!FileManager.default.fileExists(atPath: outsideHome.path))
            let sentinel = Data("unchanged test-owned destination".utf8)
            try sentinel.write(to: outsideHome)
            probe.recordQASaveStage(.nativeMenuEntry)
            #expect(try Data(contentsOf: outsideHome) == sentinel)
            try FileManager.default.removeItem(at: result)
            let full = Data(repeating: 0x20, count: 512 * 1_024)
            try full.write(to: result)
            probe.recordQASaveStage(.nativeMenuEntry)
            #expect(try Data(contentsOf: result) == full)
            try FileManager.default.removeItem(at: result)
            probe.recordQASaveStage(.nativeMenuEntry)
            let line = try #require(
                String(contentsOf: result, encoding: .utf8).split(separator: "\n").first)
            let object = try #require(
                JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            #expect(object["sample"] as? Int == 0)
        }

        @Test(
            "Reader failure diagnostics stay disabled without the verified synthetic QA authorization")
        func qaReaderFailuresRequireExistingIsolation() throws {
            let fixture = try makeQAReaderFailureFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let result = fixture.home.appendingPathComponent("qa-reader-failures.jsonl")
            var disabled = fixture.environment
            disabled["SCHOLIUM_QA_MEMORY_OWNER_DIAGNOSTICS"] = nil
            var vaultHome = fixture.environment
            vaultHome["SCHOLIUM_HOME"] = fixture.environment["SCHOLIUM_UI_TEST_WORKSPACE_ROOT"]
            let configurations = [
                ([:], ScholiumRuntimeIsolation.qaBundleIdentifier, fixture.bundle),
                (disabled, ScholiumRuntimeIsolation.qaBundleIdentifier, fixture.bundle),
                (fixture.environment, ScholiumRuntimeIsolation.productionBundleIdentifier, fixture.bundle),
                (vaultHome, ScholiumRuntimeIsolation.qaBundleIdentifier, fixture.bundle),
                (
                    fixture.environment, ScholiumRuntimeIsolation.qaBundleIdentifier,
                    fixture.root.deletingLastPathComponent().deletingLastPathComponent()
                        .appendingPathComponent("Scholium-QA.app")
                ),
            ]
            for (environment, bundleID, bundleURL) in configurations {
                let probe = PerformanceProbe(
                    environment: environment, bundleID: bundleID, bundleURL: bundleURL)
                #expect(!probe.measuresQAMemoryOwners)
                probe.recordQAReaderFailure(
                    phase: .finalization, generation: 7, error: CocoaError(.coderReadCorrupt))
                #expect(!FileManager.default.fileExists(atPath: result.path))
            }
        }

        @Test("Authorized reader failures contain only classified metadata and stop after 32 records")
        func qaReaderFailuresArePrivateAndBounded() throws {
            let fixture = try makeQAReaderFailureFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let probe = PerformanceProbe(
                environment: fixture.environment, bundleID: ScholiumRuntimeIsolation.qaBundleIdentifier,
                bundleURL: fixture.bundle, now: { 42 })
            #expect(!probe.isEnabled)
            #expect(probe.measuresQAMemoryOwners)
            let privatePayload = "Synthetic private source /Users/fixture-only/research/Private Note.md"
            func javascriptError(_ message: String) -> NSError {
                NSError(
                    domain: WKErrorDomain, code: WKError.Code.javaScriptExceptionOccurred.rawValue,
                    userInfo: [
                        "WKJavaScriptExceptionMessage": message,
                        NSLocalizedDescriptionKey: privatePayload,
                        "WKJavaScriptExceptionSourceURL": privatePayload,
                    ])
            }
            probe.recordQAReaderFailure(
                phase: .finalization, generation: 7,
                error: javascriptError("Error: stale reader preparation"))
            probe.recordQAReaderFailure(
                phase: .presentationUpdate, generation: 8,
                error: javascriptError("stale presentation update"))
            probe.recordQAReaderFailure(
                phase: .finalization, generation: 9, error: javascriptError(privatePayload))
            probe.recordQAReaderFailure(
                phase: .navigation, generation: 10,
                error: NSError(
                    domain: NSURLErrorDomain, code: NSURLErrorCancelled,
                    userInfo: [NSURLErrorKey: privatePayload]))
            probe.recordQAReaderFailure(
                phase: .finalization, generation: 11,
                error: ScholiumWindowLifecycleError.timedOut(.bridgeRequest))
            probe.recordQAReaderFailure(
                phase: .provisionalNavigation, generation: 12, error: ScholiumWindowLifecycleError.cancelled
            )
            probe.recordQAReaderFailure(phase: .finalization, generation: 13, error: CancellationError())
            probe.recordQAReaderFailure(phase: .processTerminated, generation: 14)
            probe.recordQAReaderFailure(
                phase: .finalization, generation: 15, error: CocoaError(.userCancelled))
            probe.recordQAReaderFailure(
                phase: .finalization, generation: 16,
                error: javascriptError("Error: stale reader preparation " + privatePayload))
            for index in 0..<40 {
                probe.recordQAReaderFailure(
                    phase: .finalization, generation: UInt64(100 + index),
                    error: CocoaError(.coderReadCorrupt))
            }
            let data = try Data(
                contentsOf: fixture.home.appendingPathComponent("qa-reader-failures.jsonl"))
            let text = try #require(String(data: data, encoding: .utf8))
            let lines = text.split(separator: "\n")
            let objects = try lines.map {
                try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
            }
            #expect(objects.count == 32)
            #expect(objects.compactMap { $0["sample"] as? Int } == Array(0..<32))
            #expect(objects.allSatisfy { $0["completed_uptime_ns"] as? Int == 42 })
            #expect(objects[0]["phase"] as? String == "finalization")
            #expect(objects[0]["generation"] as? Int == 7)
            #expect(objects[0]["error_domain"] as? String == WKErrorDomain)
            #expect(objects[0]["error_code"] as? Int == WKError.Code.javaScriptExceptionOccurred.rawValue)
            #expect(objects[0]["javascript_exception"] as? String == "stale_reader_preparation")
            #expect(objects[1]["phase"] as? String == "presentation_update")
            #expect(objects[1]["javascript_exception"] as? String == "stale_presentation_update")
            #expect(objects[2]["javascript_exception"] as? String == "other")
            #expect(objects[3]["phase"] as? String == "navigation")
            #expect(objects[3]["category"] as? String == "cancelled")
            #expect(objects[4]["category"] as? String == "deadline")
            #expect(objects[5]["phase"] as? String == "provisional_navigation")
            #expect(objects[5]["category"] as? String == "cancelled")
            #expect(objects[6]["category"] as? String == "cancelled")
            #expect(objects[7]["phase"] as? String == "process_terminated")
            #expect(objects[7]["category"] as? String == "process_terminated")
            #expect(objects[8]["category"] as? String == "cancelled")
            #expect(objects[9]["javascript_exception"] as? String == "other")
            let commonKeys: Set<String> = [
                "schema", "sample", "completed_uptime_ns", "phase", "generation", "category",
            ]
            #expect(
                Set(objects[0].keys)
                    == commonKeys.union(["error_domain", "error_code", "javascript_exception"]))
            #expect(Set(objects[3].keys) == commonKeys.union(["error_domain", "error_code"]))
            #expect(Set(objects[7].keys) == commonKeys)
            #expect(
                objects.allSatisfy {
                    Set($0.keys).isSubset(
                        of: commonKeys.union(["error_domain", "error_code", "javascript_exception"]))
                })
            #expect(!text.contains(privatePayload))
            #expect(!text.contains(fixture.root.path))
            #expect(!text.contains("Error: stale reader preparation"))
            #expect(!text.contains("NSLocalizedDescription"))
            #expect(
                !FileManager.default.fileExists(
                    atPath: fixture.home.appendingPathComponent("qa-memory-owner-diagnostics.jsonl").path))
        }

        @Test("Reader failure artifacts reject dangling and existing symlink destinations")
        func qaReaderFailuresRejectSymlinks() throws {
            let fixture = try makeQAReaderFailureFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let probe = PerformanceProbe(
                environment: fixture.environment, bundleID: ScholiumRuntimeIsolation.qaBundleIdentifier,
                bundleURL: fixture.bundle)
            let result = fixture.home.appendingPathComponent("qa-reader-failures.jsonl")
            let outsideHome = fixture.root.appendingPathComponent("outside-home.jsonl")
            try FileManager.default.createSymbolicLink(at: result, withDestinationURL: outsideHome)
            probe.recordQAReaderFailure(phase: .processTerminated, generation: 1)
            #expect(!FileManager.default.fileExists(atPath: outsideHome.path))
            try FileManager.default.removeItem(at: result)
            probe.recordQAReaderFailure(phase: .processTerminated, generation: 2)
            let line = try #require(
                String(contentsOf: result, encoding: .utf8).split(separator: "\n").first)
            let object = try #require(
                JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            #expect(object["sample"] as? Int == 0)
            #expect(object["generation"] as? Int == 2)
            try FileManager.default.removeItem(at: result)
            let sentinel = Data("unchanged test-owned destination".utf8)
            try sentinel.write(to: outsideHome)
            try FileManager.default.createSymbolicLink(at: result, withDestinationURL: outsideHome)
            probe.recordQAReaderFailure(phase: .processTerminated, generation: 3)
            #expect(try Data(contentsOf: outsideHome) == sentinel)
        }

        private func makeQAReaderFailureFixture() throws -> (
            root: URL, home: URL, bundle: URL, environment: [String: String]
        ) {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/qa-reader-failure-probe-\(UUID())")
            let home = root.appendingPathComponent("home", isDirectory: true)
            let fixture = root.appendingPathComponent("fixtures", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
            } catch {
                try? FileManager.default.removeItem(at: root)
                throw error
            }
            return (
                root, home, root.appendingPathComponent("Scholium-QA.app", isDirectory: true),
                [
                    "SCHOLIUM_QA_MEMORY_OWNER_DIAGNOSTICS": "1",
                    "SCHOLIUM_HOME": home.path,
                    "SCHOLIUM_UI_TEST_WORKSPACE_ROOT": fixture.path,
                ]
            )
        }

        @Test("QA memory-owner snapshots require an explicit isolated home and contain counts only")
        func qaMemoryOwnerSnapshotIsolation() async throws {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/qa-memory-owner-probe-\(UUID())")
            let home = root.appendingPathComponent("home", isDirectory: true)
            let fixture = root.appendingPathComponent("fixtures", isDirectory: true)
            let bundle = root.appendingPathComponent("Scholium-QA.app", isDirectory: true)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }

            let environment = [
                "SCHOLIUM_QA_MEMORY_OWNER_DIAGNOSTICS": "1",
                "SCHOLIUM_HOME": home.path,
                "SCHOLIUM_UI_TEST_WORKSPACE_ROOT": fixture.path,
            ]
            let probe = PerformanceProbe(
                environment: environment,
                bundleID: ScholiumRuntimeIsolation.qaBundleIdentifier,
                bundleURL: bundle,
                now: { 42 }
            )
            #expect(!probe.isEnabled)
            #expect(probe.measuresQAMemoryOwners)
            let controller = DocumentController()
            let empty = await controller.qaMemoryOwnerStats()
            #expect(empty.retainedSessions == 0)
            #expect(empty.fullSnapshots == 0)
            #expect(empty.readProjectionEntries == 0)
            probe.recordQAMemoryOwners(empty)

            _ = controller.session(for: DocumentSessionKey(vaultID: UUID(), noteID: UUID()))
            let retained = await controller.qaMemoryOwnerStats()
            #expect(retained.retainedSessions == 1)
            #expect(retained.leasedSessions == 0)
            probe.recordQAMemoryOwners(retained)

            let result = home.appendingPathComponent("qa-memory-owner-diagnostics.jsonl")
            let lines = try String(contentsOf: result, encoding: .utf8).split(separator: "\n")
            #expect(lines.count == 2)
            let objects = try lines.map { line in
                try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            }
            #expect(objects[0]["sample"] as? Int == 0)
            #expect(objects[1]["sample"] as? Int == 1)
            #expect(objects[0]["retained_sessions"] as? Int == 0)
            #expect(objects[1]["retained_sessions"] as? Int == 1)
            #expect(
                Set(objects[0].keys)
                    == Set([
                        "schema", "sample", "completed_uptime_ns", "retained_sessions",
                        "leased_sessions", "pinned_sessions", "attached_webview_sessions",
                        "full_snapshots", "pending_hydrations",
                        "read_projection_entries", "read_projection_html_utf8_bytes",
                        "editor_pool_idle", "editor_pool_attached", "editor_pool_preparing",
                        "editor_pool_abandoned_live", "editor_pool_waiting",
                    ]))

            var disabledEnvironment = environment
            disabledEnvironment["SCHOLIUM_QA_MEMORY_OWNER_DIAGNOSTICS"] = nil
            #expect(
                !PerformanceProbe(
                    environment: disabledEnvironment,
                    bundleID: ScholiumRuntimeIsolation.qaBundleIdentifier,
                    bundleURL: bundle
                ).measuresQAMemoryOwners)
            #expect(
                !PerformanceProbe(
                    environment: environment,
                    bundleID: ScholiumRuntimeIsolation.productionBundleIdentifier,
                    bundleURL: bundle
                ).measuresQAMemoryOwners)
            var vaultHomeEnvironment = environment
            vaultHomeEnvironment["SCHOLIUM_HOME"] = fixture.path
            #expect(
                !PerformanceProbe(
                    environment: vaultHomeEnvironment,
                    bundleID: ScholiumRuntimeIsolation.qaBundleIdentifier,
                    bundleURL: bundle
                ).measuresQAMemoryOwners)

            // Reject a dangling link before file creation can follow it out
            // of the isolated home.
            try FileManager.default.removeItem(at: result)
            let outside = root.appendingPathComponent("outside-home.jsonl")
            try FileManager.default.createSymbolicLink(
                at: result,
                withDestinationURL: outside
            )
            probe.recordQAMemoryOwners(retained)
            #expect(!FileManager.default.fileExists(atPath: outside.path))
        }
    #endif

    @Test(
        "Chat entry timing rejects a cancelled visit and records only its replacement's ready viewport")
    func chatEntryBindsItsMountedLifetime() async throws {
        let runID = "chat_entry_\(UUID().uuidString)"
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/performance-\(runID)/app-state/raw")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(
                at: directory.deletingLastPathComponent().deletingLastPathComponent())
        }
        let result = directory.appendingPathComponent("chat.jsonl")
        var timestamp: UInt64 = 100_000_000
        let probe = PerformanceProbe(
            environment: [
                "SCHOLIUM_PERFORMANCE_RESULTS_PATH": result.path,
                "SCHOLIUM_PERFORMANCE_METRIC": "chat_entry",
                "SCHOLIUM_PERFORMANCE_RUN_ID": runID,
                "SCHOLIUM_PERFORMANCE_SAMPLE": "0",
                "SCHOLIUM_PERFORMANCE_SAMPLE_COUNT": "2",
            ], bundleID: "com.scholium.qa", now: { timestamp })
        #expect(probe.measuresChatEntry)
        let conversationID = UUID()
        probe.beginChatEntry(in: conversationID, messageCount: 72)
        let cancelled = try #require(probe.chatEntryID(in: conversationID))
        timestamp = 110_000_000
        probe.markChatDetailMounted(cancelled, readerCount: 4)
        timestamp = 120_000_000
        probe.markChatReadersHydrated(cancelled) { false }
        probe.cancelChatEntry()

        timestamp = 1_000_000_000
        probe.beginChatEntry(in: conversationID, messageCount: 72)
        let replacement = try #require(probe.chatEntryID(in: conversationID))
        #expect(replacement != cancelled)
        timestamp = 1_010_000_000
        probe.markChatDetailMounted(replacement, readerCount: 4)
        probe.markChatReadersHydrated(cancelled) { true }
        timestamp = 1_020_000_000
        probe.markChatReadersHydrated(replacement) { true }
        timestamp = 1_050_000_000
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !FileManager.default.fileExists(atPath: result.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        let lines = try String(contentsOf: result, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 1)
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        #expect(object["duration_ms"] as? Double == 50)
        #expect(object["detail_mount_ms"] as? Double == 10)
        #expect(object["reply_hydration_ms"] as? Double == 10)
        #expect(object["viewport_position_ms"] as? Double == 30)
        #expect(object["observed_count"] as? Int == 72)
        #expect(object["mounted_reader_count"] as? Double == 4)
        #expect(!lines[0].contains(conversationID.uuidString))
    }

    @Test("Search phases preserve the committed-input and visible-result boundary")
    func searchRecordsDispatchPhase() throws {
        let runID = "search_phase_\(UUID().uuidString)"
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/performance-\(runID)/app-state/raw")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(
                at: directory.deletingLastPathComponent().deletingLastPathComponent()
            )
        }
        let result = directory.appendingPathComponent("indexed_search.jsonl")
        var times: [UInt64] = [1_000_000, 11_000_000, 31_000_000]
        let probe = PerformanceProbe(
            environment: [
                "SCHOLIUM_PERFORMANCE_RESULTS_PATH": result.path,
                "SCHOLIUM_PERFORMANCE_METRIC": "indexed_search",
                "SCHOLIUM_PERFORMANCE_RUN_ID": runID,
                "SCHOLIUM_PERFORMANCE_SAMPLE": "0",
                "SCHOLIUM_PERFORMANCE_SAMPLE_COUNT": "1",
                "SCHOLIUM_PERFORMANCE_EXPECTED_QUERY": "Fixture",
                "SCHOLIUM_PERFORMANCE_EXPECTED_COUNT": "1",
            ],
            bundleID: "com.scholium.qa",
            now: { times.removeFirst() }
        )
        probe.beginSearch(query: "Fixture")
        probe.markSearchDispatched(query: "Fixture")
        probe.markSearchResultsReady(query: "Fixture", resultCount: 1)

        let line = try #require(
            String(contentsOf: result, encoding: .utf8).split(separator: "\n").first)
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        )
        #expect(object["duration_ms"] as? Double == 30)
        #expect(object["search_input_to_dispatch_duration_ms"] as? Double == 10)
        #expect(object["search_dispatch_to_ready_duration_ms"] as? Double == 20)
    }

    @Test("Read and first-use Edit metrics establish Review before selection")
    func reviewSetupIsMetricBound() throws {
        let directory = URL(
            fileURLWithPath: "/private/tmp/scholium-performance-review-setup-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        for metric in [
            PerformanceProbe.Metric.warmReadActivation,
            .firstReadActivation,
            .firstEditActivation,
        ] {
            let probe = PerformanceProbe(
                environment: [
                    "SCHOLIUM_PERFORMANCE_RESULTS_PATH":
                        directory
                        .appendingPathComponent("\(metric.rawValue).jsonl").path,
                    "SCHOLIUM_PERFORMANCE_METRIC": metric.rawValue,
                    "SCHOLIUM_PERFORMANCE_RUN_ID": "review_setup_test",
                    "SCHOLIUM_PERFORMANCE_SAMPLE": "0",
                    "SCHOLIUM_PERFORMANCE_SAMPLE_COUNT": "1",
                ],
                bundleID: "com.scholium.qa"
            )
            #expect(probe.requiresInitialReviewPresentation)
        }

        let search = PerformanceProbe(
            environment: [
                "SCHOLIUM_PERFORMANCE_RESULTS_PATH":
                    directory
                    .appendingPathComponent("indexed_search.jsonl").path,
                "SCHOLIUM_PERFORMANCE_METRIC": "indexed_search",
                "SCHOLIUM_PERFORMANCE_RUN_ID": "review_setup_test",
                "SCHOLIUM_PERFORMANCE_SAMPLE": "0",
                "SCHOLIUM_PERFORMANCE_SAMPLE_COUNT": "1",
            ],
            bundleID: "com.scholium.qa"
        )
        #expect(!search.requiresInitialReviewPresentation)

        let memory = PerformanceProbe(
            environment: [
                "SCHOLIUM_PERFORMANCE_RESULTS_PATH":
                    directory
                    .appendingPathComponent("editor_retained_memory.jsonl").path,
                "SCHOLIUM_PERFORMANCE_METRIC": "editor_retained_memory",
                "SCHOLIUM_PERFORMANCE_RUN_ID": "review_setup_test",
                "SCHOLIUM_PERFORMANCE_SAMPLE": "0",
                "SCHOLIUM_PERFORMANCE_SAMPLE_COUNT": "51",
            ],
            bundleID: "com.scholium.qa"
        )
        #expect(memory.measuresEditorRetainedMemory)
        #expect(!memory.requiresInitialReviewPresentation)
    }

    @Test("Packaged probe writes only inside its explicit performance run")
    func packagedProbeRequiresDriverOwnedResultRoot() throws {
        let fileManager = FileManager.default
        let temporary = URL(
            fileURLWithPath: "/private/tmp/scholium-packaged-performance-probe-\(UUID().uuidString)",
            isDirectory: true
        )
        let runID = "packaged_probe_test"
        let runRoot =
            temporary
            .appendingPathComponent("Performance Runs", isDirectory: true)
            .appendingPathComponent(runID, isDirectory: true)
        let home = runRoot.appendingPathComponent(
            "home-warm-library",
            isDirectory: true
        )
        let raw = runRoot.appendingPathComponent("raw", isDirectory: true)
        let outside = runRoot.appendingPathComponent("outside", isDirectory: true)
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: raw, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: outside,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: temporary) }

        let result = raw.appendingPathComponent("warm_library_launch.jsonl")
        let environment = [
            "SCHOLIUM_HOME": home.path,
            "SCHOLIUM_PERFORMANCE_RESULTS_PATH": result.path,
            "SCHOLIUM_PERFORMANCE_METRIC": "warm_library_launch",
            "SCHOLIUM_PERFORMANCE_RUN_ID": runID,
            "SCHOLIUM_PERFORMANCE_SAMPLE": "0",
            "SCHOLIUM_PERFORMANCE_SAMPLE_COUNT": "1",
            "SCHOLIUM_PERFORMANCE_EXPECTED_COUNT": "267",
            "SCHOLIUM_PERFORMANCE_STARTED_NS": "1000000",
        ]
        var times: [UInt64] = [
            2_000_000, 4_000_000, 6_000_000,
            8_000_000, 11_000_000, 20_000_000,
        ]
        let probe = PerformanceProbe(
            environment: environment,
            arguments: [
                "Scholium",
                ScholiumRuntimeIsolation.packagedPerformanceIsolationArgument,
            ],
            bundleID: "com.scholium.app",
            now: { times.removeFirst() }
        )
        #expect(probe.isEnabled)
        probe.markWarmLibraryWindowModelInitializationStarted()
        probe.markStartupSafetyReady()
        probe.markWarmLibraryWorkspaceReady()
        probe.markVaultConfigurationReady()
        probe.markWarmLibraryProjectionReady()
        probe.markLibraryReady(noteCount: 267)
        #expect(fileManager.fileExists(atPath: result.path))

        var rejectedEnvironment = environment
        rejectedEnvironment["SCHOLIUM_PERFORMANCE_RESULTS_PATH"] =
            outside
            .appendingPathComponent("warm_library_launch.jsonl").path
        let wrongRoot = PerformanceProbe(
            environment: rejectedEnvironment,
            arguments: [
                "Scholium",
                ScholiumRuntimeIsolation.packagedPerformanceIsolationArgument,
            ],
            bundleID: "com.scholium.app"
        )
        #expect(!wrongRoot.isEnabled)

        let ordinaryRelease = PerformanceProbe(
            environment: environment,
            arguments: ["Scholium"],
            bundleID: "com.scholium.app"
        )
        #expect(!ordinaryRelease.isEnabled)
    }

    @Test("Large CJK correctness remains distinct from latency measurement")
    func largeCJKCorrectnessHasDedicatedProbeMode() throws {
        let directory = URL(
            fileURLWithPath: "/private/tmp/scholium-performance-cjk-probe-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = PerformanceProbe(
            environment: [
                "SCHOLIUM_PERFORMANCE_RESULTS_PATH":
                    directory
                    .appendingPathComponent("correctness.jsonl").path,
                "SCHOLIUM_PERFORMANCE_METRIC": "editor_large_cjk_correctness",
                "SCHOLIUM_PERFORMANCE_RUN_ID": "cjk_probe_test",
                "SCHOLIUM_PERFORMANCE_SAMPLE": "0",
                "SCHOLIUM_PERFORMANCE_SAMPLE_COUNT": "1",
                "SCHOLIUM_PERFORMANCE_EXPECTED_DOCUMENT": "Canonical.md",
            ],
            bundleID: "com.scholium.qa"
        )

        #expect(probe.exercisesLargeCJKCorrectness)
        #expect(!probe.measuresEditorModeTransition)
        probe.recordLargeCJKCorrectness(
            documentID: "Wrong.md",
            source: String(repeating: "研", count: 100_000)
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("correctness.jsonl").path
            ))

        probe.recordLargeCJKCorrectness(
            documentID: "Canonical.md",
            source: String(repeating: "研", count: 100_000)
        )
        let object = try #require(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: directory.appendingPathComponent("correctness.jsonl"))
            ) as? [String: Any]
        )
        #expect(object["schema"] as? String == "scholium-cjk-correctness-v1")
        #expect(object["character_count"] as? Int == 100_000)
        #expect(object["exact_source_restored"] as? Bool == true)
    }

    @Test("Warm Library launch records only numeric owner phases and the expected count")
    func warmLibraryLaunchRecordsOwnerPhases() throws {
        let fileManager = FileManager.default
        let directory = URL(
            fileURLWithPath: "/private/tmp/scholium-performance-probe-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        let result = directory.appendingPathComponent("warm_library_launch.jsonl")
        var times: [UInt64] = [
            2_000_000, 4_000_000, 6_000_000,
            8_000_000, 11_000_000, 20_000_000,
        ]
        let probe = PerformanceProbe(
            environment: [
                "SCHOLIUM_PERFORMANCE_RESULTS_PATH": result.path,
                "SCHOLIUM_PERFORMANCE_METRIC": "warm_library_launch",
                "SCHOLIUM_PERFORMANCE_RUN_ID": "warm_library_test",
                "SCHOLIUM_PERFORMANCE_SAMPLE": "0",
                "SCHOLIUM_PERFORMANCE_SAMPLE_COUNT": "1",
                "SCHOLIUM_PERFORMANCE_EXPECTED_COUNT": "267",
                "SCHOLIUM_PERFORMANCE_STARTED_NS": "1000000",
            ],
            bundleID: "com.scholium.qa",
            now: { times.removeFirst() }
        )

        probe.markWarmLibraryWindowModelInitializationStarted()
        probe.markStartupSafetyReady()
        probe.markWarmLibraryWorkspaceReady()
        probe.markVaultConfigurationReady()
        probe.markWarmLibraryProjectionReady()
        probe.markLibraryReady(noteCount: 267)

        let line = try #require(
            String(contentsOf: result, encoding: .utf8)
                .split(separator: "\n").first
        )
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        )
        #expect(object["duration_ms"] as? Double == 19)
        #expect(object["observed_count"] as? Int == 267)
        #expect(object["process_to_window_model_init_duration_ms"] as? Double == 1)
        #expect(object["window_model_init_to_workspace_ready_duration_ms"] as? Double == 4)
        #expect(object["workspace_ready_to_projection_duration_ms"] as? Double == 5)
        #expect(object["projection_to_layout_duration_ms"] as? Double == 9)
        #expect(object["workspace_ready_to_startup_safety_ready_duration_ms"] as? Double == 0)
        #expect(object["startup_safety_ready_to_vault_configuration_ready_duration_ms"] as? Double == 2)
        #expect(object["vault_configuration_ready_to_projection_duration_ms"] as? Double == 3)
        #expect(
            Set(object.keys) == [
                "schema", "run_id", "sample", "metric", "duration_ms",
                "completed_uptime_ns", "observed_count",
                "process_to_window_model_init_duration_ms",
                "window_model_init_to_workspace_ready_duration_ms",
                "workspace_ready_to_projection_duration_ms",
                "projection_to_layout_duration_ms",
                "workspace_ready_to_startup_safety_ready_duration_ms",
                "startup_safety_ready_to_vault_configuration_ready_duration_ms",
                "vault_configuration_ready_to_projection_duration_ms",
            ])
    }

    @Test("Cached preview records only its native visible boundary")
    func cachedPreviewRequiresExpectedVisibleDocument() throws {
        let fileManager = FileManager.default
        let directory = URL(
            fileURLWithPath: "/private/tmp/scholium-performance-probe-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        let result = directory.appendingPathComponent("editor_cached_preview.jsonl")
        var clock: UInt64 = 50_000_000
        let probe = PerformanceProbe(
            environment: [
                "SCHOLIUM_PERFORMANCE_RESULTS_PATH": result.path,
                "SCHOLIUM_PERFORMANCE_METRIC": "editor_cached_preview",
                "SCHOLIUM_PERFORMANCE_RUN_ID": "cached_preview_test",
                "SCHOLIUM_PERFORMANCE_SAMPLE": "0",
                "SCHOLIUM_PERFORMANCE_SAMPLE_COUNT": "1",
                "SCHOLIUM_PERFORMANCE_EXPECTED_DOCUMENT": "Fixture.md",
            ],
            bundleID: "com.scholium.qa",
            now: { clock }
        )

        probe.beginEditorCachedPreview(documentID: "Private.md")
        probe.markEditorCachedPreviewVisible(documentID: "Private.md")
        #expect(!fileManager.fileExists(atPath: result.path))
        probe.recordEditorWebDuration(
            documentID: "Fixture.md",
            metric: .editorCachedPreview,
            durationMilliseconds: 1
        )
        #expect(!fileManager.fileExists(atPath: result.path))
        probe.beginEditorCachedPreview(documentID: "Fixture.md")
        clock += 8_000_000
        probe.markEditorCachedPreviewVisible(documentID: "Private.md")
        #expect(!fileManager.fileExists(atPath: result.path))
        probe.markEditorCachedPreviewVisible(documentID: "Fixture.md")

        let object = try #require(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: result)
            ) as? [String: Any]
        )
        #expect(object["metric"] as? String == "editor_cached_preview")
        #expect(object["duration_ms"] as? Double == 8)
        #expect(
            Set(object.keys) == [
                "schema", "run_id", "sample", "metric", "duration_ms",
                "completed_uptime_ns",
            ])
    }

    @Test("Warm Edit activation ends only at the matching visible editor")
    func warmEditActivationRequiresMatchingVisibleDocument() throws {
        let fileManager = FileManager.default
        let directory = URL(
            fileURLWithPath: "/private/tmp/scholium-performance-probe-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        let result = directory.appendingPathComponent("warm_edit_activation.jsonl")
        var times: [UInt64] = [10_000_000, 35_000_000]
        let probe = PerformanceProbe(
            environment: [
                "SCHOLIUM_PERFORMANCE_RESULTS_PATH": result.path,
                "SCHOLIUM_PERFORMANCE_METRIC": "warm_edit_activation",
                "SCHOLIUM_PERFORMANCE_RUN_ID": "warm_edit_test",
                "SCHOLIUM_PERFORMANCE_SAMPLE": "2",
                "SCHOLIUM_PERFORMANCE_SAMPLE_COUNT": "1",
                "SCHOLIUM_PERFORMANCE_EXPECTED_DOCUMENT": "Fixture.md",
            ],
            bundleID: "com.scholium.qa",
            now: { times.removeFirst() }
        )

        probe.beginEditActivation(documentID: "Fixture.md")
        probe.markEditorVisible(documentID: "Other.md")
        #expect(!fileManager.fileExists(atPath: result.path))
        probe.markEditorVisible(documentID: "Fixture.md")

        let line = try #require(
            String(contentsOf: result, encoding: .utf8)
                .split(separator: "\n").first
        )
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        )
        #expect(object["sample"] as? Int == 2)
        #expect(object["duration_ms"] as? Double == 25)
    }

    @Test("First Edit starts at the researcher request, not process launch")
    func firstEditStartsAtResearcherRequest() throws {
        let fileManager = FileManager.default
        let directory = URL(
            fileURLWithPath: "/private/tmp/scholium-performance-probe-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        let result = directory.appendingPathComponent("first_edit_activation.jsonl")
        var times: [UInt64] = [1_010_000_000, 1_085_000_000]
        let probe = PerformanceProbe(
            environment: [
                "SCHOLIUM_PERFORMANCE_RESULTS_PATH": result.path,
                "SCHOLIUM_PERFORMANCE_METRIC": "first_edit_activation",
                "SCHOLIUM_PERFORMANCE_RUN_ID": "first_edit_test",
                "SCHOLIUM_PERFORMANCE_SAMPLE": "0",
                "SCHOLIUM_PERFORMANCE_SAMPLE_COUNT": "1",
                "SCHOLIUM_PERFORMANCE_EXPECTED_DOCUMENT": "Fixture.md",
                "SCHOLIUM_PERFORMANCE_STARTED_NS": "10000000",
            ],
            bundleID: "com.scholium.qa",
            now: { times.removeFirst() }
        )

        probe.markEditorVisible(documentID: "Fixture.md")
        #expect(!fileManager.fileExists(atPath: result.path))
        probe.beginEditActivation(documentID: "Fixture.md")
        probe.markEditorVisible(documentID: "Fixture.md")

        let object = try #require(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: result)
            ) as? [String: Any]
        )
        #expect(object["metric"] as? String == "first_edit_activation")
        #expect(object["duration_ms"] as? Double == 75)
    }

    @Test(
        "Edit phases accept only ordered first observations and reset between samples",
        arguments: ["warm_edit_activation", "first_edit_activation", "indexed_search"]
    )
    func editActivationPhasesAreOrderedAndSampleLocal(metric: String) throws {
        let fileManager = FileManager.default
        let runID = "edit_phases_\(UUID().uuidString)"
        let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent(".build/performance-\(runID)", isDirectory: true)
        let directory = root.appendingPathComponent("app-state/raw", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        let result = directory.appendingPathComponent("edit_phases.jsonl")
        var timestamp: UInt64 = 5_000_000
        let probe = PerformanceProbe(
            environment: [
                "SCHOLIUM_PERFORMANCE_RESULTS_PATH": result.path,
                "SCHOLIUM_PERFORMANCE_METRIC": metric,
                "SCHOLIUM_PERFORMANCE_RUN_ID": runID,
                "SCHOLIUM_PERFORMANCE_SAMPLE": "0",
                "SCHOLIUM_PERFORMANCE_SAMPLE_COUNT": "3",
                "SCHOLIUM_PERFORMANCE_EXPECTED_DOCUMENT": "Fixture.md",
            ],
            arguments: [], bundleID: "com.scholium.qa", now: { timestamp }
        )
        try #require(probe.isEnabled)
        func markPhases(documentID: String) {
            probe.markEditActivationAttached(documentID: documentID, reusedPage: false)
            probe.markEditActivationRendererReady(documentID: documentID)
            probe.markEditActivationLoaded(documentID: documentID)
        }
        markPhases(documentID: "Fixture.md")
        probe.markEditorVisible(documentID: "Fixture.md")
        #expect(!fileManager.fileExists(atPath: result.path))
        timestamp = 10_000_000
        probe.beginEditActivation(documentID: "Fixture.md")
        markPhases(documentID: "Other.md")
        timestamp = 9_000_000
        probe.markEditActivationAttached(documentID: "Fixture.md", reusedPage: false)
        timestamp = 20_000_000
        probe.markEditActivationAttached(documentID: "Fixture.md", reusedPage: true)
        timestamp = 25_000_000
        probe.markEditActivationAttached(documentID: "Fixture.md", reusedPage: false)
        timestamp = 19_000_000
        probe.markEditActivationRendererReady(documentID: "Fixture.md")
        timestamp = 40_000_000
        probe.markEditActivationRendererReady(documentID: "Fixture.md")
        timestamp = 45_000_000
        probe.markEditActivationRendererReady(documentID: "Fixture.md")
        timestamp = 39_000_000
        probe.markEditActivationLoaded(documentID: "Fixture.md")
        timestamp = 60_000_000
        probe.markEditActivationLoaded(documentID: "Fixture.md")
        timestamp = 70_000_000
        probe.markEditActivationLoaded(documentID: "Fixture.md")
        probe.markEditorVisible(documentID: "Other.md")
        timestamp = 90_000_000
        probe.markEditorVisible(documentID: "Fixture.md")

        timestamp = 100_000_000
        probe.beginEditActivation(documentID: "Fixture.md")
        timestamp = 110_000_000
        probe.markEditActivationAttached(documentID: "Fixture.md", reusedPage: false)
        timestamp = 130_000_000
        probe.markEditActivationRendererReady(documentID: "Fixture.md")
        timestamp = 150_000_000
        probe.markEditorVisible(documentID: "Fixture.md")
        probe.markEditActivationLoaded(documentID: "Fixture.md")

        timestamp = 160_000_000
        probe.beginEditActivation(documentID: "Fixture.md")
        probe.markEditActivationRendererReady(documentID: "Fixture.md")
        probe.markEditActivationLoaded(documentID: "Fixture.md")
        timestamp = 180_000_000
        probe.markEditorVisible(documentID: "Fixture.md")
        probe.beginEditActivation(documentID: "Fixture.md")
        markPhases(documentID: "Fixture.md")
        probe.markEditorVisible(documentID: "Fixture.md")

        if metric == "indexed_search" {
            #expect(!fileManager.fileExists(atPath: result.path))
            return
        }
        let lines = try String(contentsOf: result, encoding: .utf8).split(separator: "\n")
        try #require(lines.count == 3)
        let objects = try lines.map { line in
            try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        }
        let commonKeys: Set<String> = [
            "schema", "run_id", "sample", "metric", "duration_ms", "completed_uptime_ns",
        ]
        let phaseKeys = [
            "request_to_attached_duration_ms", "attached_to_renderer_ready_duration_ms",
            "renderer_ready_to_loaded_observed_duration_ms", "loaded_observed_to_visible_duration_ms",
        ]
        #expect(Set(objects[0].keys) == commonKeys.union(phaseKeys).union(["pool_reused_page"]))
        #expect(phaseKeys.compactMap { objects[0][$0] as? Double } == [10, 20, 20, 30])
        #expect(
            phaseKeys.compactMap { objects[0][$0] as? Double }.reduce(0, +) == objects[0]["duration_ms"]
                as? Double)
        #expect(objects[0]["pool_reused_page"] as? Bool == true)
        #expect(
            Set(objects[1].keys) == commonKeys.union(phaseKeys.prefix(2)).union(["pool_reused_page"]))
        #expect(objects[1][phaseKeys[0]] as? Double == 10)
        #expect(objects[1][phaseKeys[1]] as? Double == 20)
        #expect(objects[1]["duration_ms"] as? Double == 50)
        #expect(objects[1]["pool_reused_page"] as? Bool == false)
        #expect(Set(objects[2].keys) == commonKeys)
        #expect(objects[2]["duration_ms"] as? Double == 20)
        #expect(objects.enumerated().allSatisfy { index, object in object["sample"] as? Int == index })
    }

    private func noteOpeningFixture(
        metric: String = "note_open_to_input", sampleCount: Int = 1, now: @escaping () -> UInt64
    ) throws -> (probe: PerformanceProbe, root: URL, result: URL) {
        let runID = "note_opening_\(UUID().uuidString)"
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/performance-\(runID)", isDirectory: true)
        let directory = root.appendingPathComponent("app-state/raw", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = directory.appendingPathComponent("opening.jsonl")
        let probe = PerformanceProbe(
            environment: [
                "SCHOLIUM_PERFORMANCE_RESULTS_PATH": result.path, "SCHOLIUM_PERFORMANCE_METRIC": metric,
                "SCHOLIUM_PERFORMANCE_RUN_ID": runID, "SCHOLIUM_PERFORMANCE_SAMPLE": "0",
                "SCHOLIUM_PERFORMANCE_SAMPLE_COUNT": String(sampleCount),
                "SCHOLIUM_PERFORMANCE_EXPECTED_DOCUMENT": "Fixture.md",
            ], arguments: [], bundleID: "com.scholium.qa", now: now)
        return (probe, root, result)
    }

    @Test(
        "Full opening ends only after matching visibility and input receipts", arguments: [true, false])
    func noteOpeningRequiresVisibleAndFocused(focusFirst: Bool) throws {
        var timestamp: UInt64 = 10_000_000
        let fixture = try noteOpeningFixture { timestamp }
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let probe = fixture.probe
        try #require(probe.isEnabled)
        let attempt = try #require(
            probe.beginNoteOpening(documentID: "Fixture.md", startNanoseconds: timestamp))
        let sessionID = UUID()
        #expect(
            probe.bindNoteOpening(
                attemptID: attempt, documentID: "Fixture.md", editorSessionID: sessionID))
        #expect(!probe.bindNoteOpening(attemptID: attempt, editorSessionID: UUID()))
        timestamp = 15_000_000
        probe.markNoteOpeningPhase(.transitionStarted, attemptID: UUID())
        probe.markNoteOpeningPhase(.transitionStarted, attemptID: attempt, documentID: "Other.md")
        let serialPhases: [PerformanceProbe.NoteOpeningPhase] = [
            .transitionStarted, .prepared, .hydrationStarted, .hydrated, .documentInstalled, .attached,
            .rendererReady, .loaded,
        ]
        for (index, phase) in serialPhases.enumerated() {
            if phase == .rendererReady {
                timestamp = 65_000_000
                probe.markNoteOpeningPhase(phase, attemptID: attempt, editorSessionID: sessionID)
            }
            timestamp = UInt64(index + 2) * 10_000_000
            probe.markNoteOpeningPhase(
                phase, attemptID: attempt, documentID: "Fixture.md", editorSessionID: sessionID)
            timestamp += 5_000_000
            probe.markNoteOpeningPhase(phase, attemptID: attempt, editorSessionID: sessionID)
        }
        timestamp = 100_000_000
        probe.recordNoteOpeningBridge(
            operation: .initialize, attemptID: attempt, editorSessionID: sessionID,
            dispatchNanoseconds: 70_000_000, returnedNanoseconds: 75_000_000,
            validatedNanoseconds: 78_000_000)
        let offsets: [UInt64] = [79_000_000, 84_000_000]
        for offset in offsets {
            probe.recordNoteOpeningBridge(
                operation: .completePreparation, attemptID: attempt, editorSessionID: sessionID,
                dispatchNanoseconds: offset, returnedNanoseconds: offset + 3_000_000,
                validatedNanoseconds: offset + 4_000_000)
        }
        probe.recordNoteOpeningBridge(
            operation: .releasePreparation, attemptID: attempt, editorSessionID: sessionID,
            dispatchNanoseconds: 88_000_000, returnedNanoseconds: 89_000_000,
            validatedNanoseconds: 90_000_000)
        for (invalidAttempt, invalidSession, returned, validated) in [
            (UUID(), sessionID, UInt64(99_000_000), UInt64(100_000_000)),
            (attempt, UUID(), 99_000_000, 100_000_000), (attempt, sessionID, 89_000_000, 100_000_000),
            (attempt, sessionID, 100_000_000, 101_000_000),
        ] {
            probe.recordNoteOpeningBridge(
                operation: .initialize, attemptID: invalidAttempt, editorSessionID: invalidSession,
                dispatchNanoseconds: 90_000_000, returnedNanoseconds: returned,
                validatedNanoseconds: validated)
        }
        probe.markNoteOpeningEditorPhase(.stableVisible, editorSessionID: UUID())
        timestamp = 110_000_000
        probe.markNoteOpeningEditorPhase(
            focusFirst ? .focused : .stableVisible, editorSessionID: sessionID, attemptID: attempt)
        #expect(!FileManager.default.fileExists(atPath: fixture.result.path))
        timestamp = 115_000_000
        probe.markNoteOpeningEditorPhase(
            focusFirst ? .focused : .stableVisible, editorSessionID: sessionID, attemptID: attempt)
        timestamp = 120_000_000
        probe.markNoteOpeningEditorPhase(
            focusFirst ? .stableVisible : .focused, editorSessionID: sessionID, attemptID: attempt)
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixture.result)) as? [String: Any])
        let phaseKeys = [
            "click_to_transition_started_duration_ms", "transition_started_to_prepared_duration_ms",
            "prepared_to_hydration_started_duration_ms", "hydration_started_to_hydrated_duration_ms",
            "hydrated_to_document_installed_duration_ms", "document_installed_to_attached_duration_ms",
            "attached_to_renderer_ready_duration_ms", "renderer_ready_to_loaded_duration_ms",
        ]
        #expect(phaseKeys.compactMap { object[$0] as? Double } == Array(repeating: 10, count: 8))
        #expect(object["loaded_to_input_ready_duration_ms"] as? Double == 30)
        #expect(object["loaded_to_focused_duration_ms"] as? Double == (focusFirst ? 20 : 30))
        #expect(object["loaded_to_stable_visible_duration_ms"] as? Double == (focusFirst ? 30 : 20))
        #expect(
            phaseKeys.compactMap { object[$0] as? Double }.reduce(30, +) == object["duration_ms"]
                as? Double)
        #expect(object["initialize_bridge_duration_ms"] as? Double == 8)
        #expect(object["initialize_bridge_dispatch_to_return_duration_ms"] as? Double == 5)
        #expect(object["initialize_bridge_return_to_validated_duration_ms"] as? Double == 3)
        #expect(object["initialize_bridge_count"] as? Double == 1)
        #expect(object["complete_preparation_bridge_duration_ms"] as? Double == 8)
        #expect(object["complete_preparation_bridge_count"] as? Double == 2)
        #expect(object["release_preparation_bridge_duration_ms"] as? Double == 2)
        let bridgeKeys = ["initialize", "complete_preparation", "release_preparation"].flatMap {
            operation in
            [
                "\(operation)_bridge_duration_ms", "\(operation)_bridge_count",
                "\(operation)_bridge_dispatch_to_return_duration_ms",
                "\(operation)_bridge_return_to_validated_duration_ms",
            ]
        }
        #expect(
            Set(object.keys)
                == Set(
                    phaseKeys + bridgeKeys + [
                        "schema", "run_id", "sample", "metric", "duration_ms", "completed_uptime_ns",
                        "loaded_to_input_ready_duration_ms", "loaded_to_focused_duration_ms",
                        "loaded_to_stable_visible_duration_ms",
                    ]))
        #expect(probe.beginNoteOpening(documentID: "Fixture.md") == nil)
        // An exhausted measurement request invalidates the old diagnostic receipt.
        #expect(
            probe.completedNoteOpeningSample(documentID: "Fixture.md", editorSessionID: sessionID) == nil)
    }

    @Test("Opening tokens reject same-path stale work, cancellation and absent disk hydration")
    func noteOpeningRejectsStaleAttemptsAndResets() throws {
        var timestamp: UInt64 = 10_000_000
        let fixture = try noteOpeningFixture(sampleCount: 2) { timestamp }
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let probe = fixture.probe
        let sessionID = UUID()
        let old = try #require(probe.beginNoteOpening(documentID: "Fixture.md"))
        #expect(probe.bindNoteOpening(attemptID: old, editorSessionID: sessionID))
        timestamp = 50_000_000
        let current = try #require(probe.beginNoteOpening(documentID: "Fixture.md"))
        probe.markNoteOpeningPhase(.focused, attemptID: current, editorSessionID: sessionID)
        #expect(probe.bindNoteOpening(attemptID: current, editorSessionID: sessionID))
        #expect(!probe.bindNoteOpening(attemptID: old, editorSessionID: sessionID))
        probe.cancelNoteOpening(attemptID: old)
        probe.cancelNoteOpening(attemptID: nil)
        probe.markNoteOpeningPhase(.hydrationStarted, attemptID: old)
        probe.markNoteOpeningEditorPhase(.focused, editorSessionID: sessionID, attemptID: old)
        probe.recordNoteOpeningBridge(
            operation: .initialize, attemptID: old, editorSessionID: sessionID,
            dispatchNanoseconds: timestamp, returnedNanoseconds: timestamp,
            validatedNanoseconds: timestamp)
        #expect(probe.currentNoteOpeningAttempt(documentID: "Other.md") == nil)
        #expect(probe.currentNoteOpeningAttempt(editorSessionID: sessionID) == current)
        let currentPhases: [(PerformanceProbe.NoteOpeningPhase, UInt64)] = [
            (.hydrationStarted, 60_000_000), (.hydrated, 70_000_000), (.stableVisible, 80_000_000),
            (.focused, 100_000_000),
        ]
        for (phase, time) in currentPhases {
            timestamp = time
            probe.markNoteOpeningPhase(phase, attemptID: current, editorSessionID: sessionID)
        }
        #expect(
            probe.completedNoteOpeningSample(documentID: "Fixture.md", editorSessionID: sessionID) == 0)
        timestamp = 110_000_000
        let unhydrated = try #require(probe.beginNoteOpening(documentID: "Fixture.md"))
        #expect(probe.bindNoteOpening(attemptID: unhydrated, editorSessionID: sessionID))
        probe.markNoteOpeningEditorPhase(
            .stableVisible, editorSessionID: sessionID, attemptID: unhydrated)
        probe.markNoteOpeningEditorPhase(.focused, editorSessionID: sessionID, attemptID: unhydrated)
        #expect(
            probe.completedNoteOpeningSample(documentID: "Fixture.md", editorSessionID: sessionID) == nil)
        probe.cancelNoteOpening(attemptID: unhydrated)
        #expect(
            probe.beginNoteOpening(documentID: "Fixture.md", startNanoseconds: timestamp + 1) == nil)
        let abandoned = try #require(probe.beginNoteOpening(documentID: "Fixture.md"))
        #expect(probe.beginNoteOpening(documentID: "Other.md") == nil)
        probe.markNoteOpeningPhase(.hydrated, attemptID: abandoned)
        #expect(probe.currentNoteOpeningAttempt(documentID: "Fixture.md") == nil)
        timestamp = 150_000_000
        let final = try #require(probe.beginNoteOpening(documentID: "Fixture.md"))
        #expect(probe.bindNoteOpening(attemptID: final, editorSessionID: sessionID))
        let finalPhases: [(PerformanceProbe.NoteOpeningPhase, UInt64)] = [
            (.hydrationStarted, 160_000_000), (.hydrated, 170_000_000), (.stableVisible, 180_000_000),
            (.focused, 190_000_000),
        ]
        for (phase, time) in finalPhases {
            timestamp = time
            probe.markNoteOpeningPhase(phase, attemptID: final, editorSessionID: sessionID)
        }
        let objects = try String(contentsOf: fixture.result, encoding: .utf8).split(separator: "\n").map {
            try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
        try #require(objects.count == 2)
        #expect(objects.compactMap { $0["duration_ms"] as? Double } == [50, 40])
        #expect(objects.compactMap { $0["sample"] as? Int } == [0, 1])
        #expect(
            objects.allSatisfy {
                Set($0.keys) == [
                    "schema", "run_id", "sample", "metric", "duration_ms", "completed_uptime_ns",
                    "hydration_started_to_hydrated_duration_ms",
                ]
            })
        #expect(
            probe.completedNoteOpeningSample(documentID: "Fixture.md", editorSessionID: sessionID) == 1)
    }

    @Test(
        "Opening diagnostics do nothing for other metrics or unarmed sessions",
        arguments: ["indexed_search", "warm_edit_activation"])
    func noteOpeningRejectsOtherMetrics(metric: String) throws {
        var clockReads = 0
        let fixture = try noteOpeningFixture(metric: metric) {
            clockReads += 1
            return 10
        }
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let probe = fixture.probe
        #expect(probe.isEnabled)
        #expect(probe.beginNoteOpening(documentID: "Fixture.md") == nil)
        #expect(probe.currentNoteOpeningAttempt(documentID: "Fixture.md") == nil)
        let sessionID = UUID()
        #expect(!probe.bindNoteOpening(attemptID: UUID(), editorSessionID: sessionID))
        probe.markNoteOpeningEditorPhase(.focused, editorSessionID: sessionID)
        probe.markNoteOpeningPhase(.hydrated, attemptID: UUID())
        probe.recordNoteOpeningBridge(
            operation: .initialize, attemptID: UUID(), editorSessionID: sessionID,
            dispatchNanoseconds: 0, returnedNanoseconds: 1, validatedNanoseconds: 2)
        #expect(clockReads == 0)
        #expect(!FileManager.default.fileExists(atPath: fixture.result.path))
    }

    @Test(
        "Opening milestones retain one matching receipt and reject stale or out-of-lifetime observations"
    )
    func noteOpeningMilestonesRespectLifetime() throws {
        var timestamp: UInt64 = 10_000_000
        let fixture = try noteOpeningFixture { timestamp }
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let probe = fixture.probe
        let stale = try #require(probe.beginNoteOpening(documentID: "Fixture.md"))
        timestamp = 20_000_000
        let attempt = try #require(probe.beginNoteOpening(documentID: "Fixture.md"))
        let sessionID = UUID()
        try #require(probe.bindNoteOpening(attemptID: attempt, editorSessionID: sessionID))

        timestamp = 19_000_000
        probe.markNoteOpeningMilestone(
            .containerPrepared, attemptID: attempt, editorSessionID: sessionID)
        timestamp = 21_000_000
        probe.markNoteOpeningMilestone(.pageAcquired, attemptID: stale, editorSessionID: sessionID)
        probe.markNoteOpeningMilestone(.webViewPrepared, attemptID: attempt, editorSessionID: UUID())
        probe.markNoteOpeningMilestone(.sessionPrepared, attemptID: nil, editorSessionID: sessionID)
        timestamp = 25_000_000
        probe.markNoteOpeningMilestone(.mountRequested, attemptID: attempt, editorSessionID: sessionID)
        timestamp = 27_000_000
        probe.markNoteOpeningMilestone(.mountRequested, attemptID: attempt, editorSessionID: sessionID)
        timestamp = 30_000_000
        probe.markNoteOpeningMilestone(.sessionLoaded, attemptID: attempt, editorSessionID: sessionID)
        timestamp = 33_000_000
        probe.markNoteOpeningMilestone(.sessionLoaded, attemptID: attempt, editorSessionID: sessionID)

        for (phase, time): (PerformanceProbe.NoteOpeningPhase, UInt64) in [
            (.hydrationStarted, 40_000_000), (.hydrated, 45_000_000), (.loaded, 50_000_000),
            (.focused, 55_000_000),
        ] {
            timestamp = time
            probe.markNoteOpeningPhase(phase, attemptID: attempt, editorSessionID: sessionID)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.result.path))
        timestamp = 60_000_000
        probe.markNoteOpeningEditorPhase(.stableVisible, editorSessionID: sessionID, attemptID: attempt)
        let completed = try Data(contentsOf: fixture.result)
        let object = try #require(JSONSerialization.jsonObject(with: completed) as? [String: Any])
        #expect(object["mount_requested_since_click_ms"] as? Double == 5)
        #expect(object["session_loaded_since_click_ms"] as? Double == 10)
        #expect(
            Set(object.keys.filter { $0.hasSuffix("_since_click_ms") })
                == ["mount_requested_since_click_ms", "session_loaded_since_click_ms"])
        #expect(object["duration_ms"] as? Double == 40)
        #expect(object["loaded_to_input_ready_duration_ms"] as? Double == 10)

        timestamp = 70_000_000
        probe.markNoteOpeningMilestone(.initialized, attemptID: attempt, editorSessionID: sessionID)
        probe.markNoteOpeningEditorPhase(.focused, editorSessionID: sessionID, attemptID: attempt)
        #expect(try Data(contentsOf: fixture.result) == completed)
    }

    @Test(
        "Opening work preserves operation values, aggregates numeric diagnostics and keeps the input endpoint"
    )
    func noteOpeningWorkAggregatesWithoutContent() throws {
        var timestamp: UInt64 = 10_000_000
        var clockReads = 0
        let fixture = try noteOpeningFixture {
            clockReads += 1
            return timestamp
        }
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let probe = fixture.probe
        let attempt = try #require(probe.beginNoteOpening(documentID: "Fixture.md"))
        let sessionID = UUID()
        try #require(probe.bindNoteOpening(attemptID: attempt, editorSessionID: sessionID))
        let privateValue = "Private research quotation and author metadata"
        var operationCount = 0
        let readsBeforeRejection = clockReads
        for (document, session) in [("Other Private Note.md", sessionID), ("Fixture.md", UUID())] {
            let result = probe.measureNoteOpeningWork(
                .citationPresentation, documentID: document, editorSessionID: session
            ) {
                operationCount += 1
                return privateValue
            }
            #expect(result == privateValue)
        }
        #expect(operationCount == 2)
        #expect(clockReads == readsBeforeRejection)

        for (start, elapsed): (UInt64, UInt64) in [
            (20_000_000, 4_000_000), (30_000_000, 7_000_000), (40_000_000, 0),
        ] {
            timestamp = start
            let result = probe.measureNoteOpeningWork(
                .citationPresentation, documentID: "Fixture.md", editorSessionID: sessionID
            ) {
                operationCount += 1
                timestamp += elapsed
                return privateValue
            }
            #expect(result == privateValue)
        }
        timestamp = 45_000_000
        let outline = probe.measureNoteOpeningWork(
            .outlineProjection, documentID: "Fixture.md", editorSessionID: sessionID
        ) {
            operationCount += 1
            timestamp = 48_000_000
            return [3, 5, 8]
        }
        #expect(outline == [3, 5, 8])
        #expect(operationCount == 6)
        for (phase, time): (PerformanceProbe.NoteOpeningPhase, UInt64) in [
            (.hydrationStarted, 55_000_000), (.hydrated, 60_000_000), (.loaded, 65_000_000),
            (.focused, 70_000_000),
        ] {
            timestamp = time
            probe.markNoteOpeningPhase(phase, attemptID: attempt, editorSessionID: sessionID)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.result.path))
        timestamp = 75_000_000
        probe.markNoteOpeningEditorPhase(.stableVisible, editorSessionID: sessionID, attemptID: attempt)
        let completed = try Data(contentsOf: fixture.result)
        let object = try #require(JSONSerialization.jsonObject(with: completed) as? [String: Any])
        let expectedWork: [String: Double] = [
            "citation_presentation_work_total_ms": 11, "citation_presentation_work_max_ms": 7,
            "citation_presentation_work_count": 3,
            "outline_projection_work_total_ms": 3, "outline_projection_work_max_ms": 3,
            "outline_projection_work_count": 1,
        ]
        #expect(Set(object.keys.filter { $0.contains("_work_") }) == Set(expectedWork.keys))
        for (key, expected) in expectedWork {
            #expect(object[key] as? Double == expected)
        }
        #expect(object["duration_ms"] as? Double == 65)
        #expect(object["completed_uptime_ns"] as? UInt64 == 75_000_000)
        #expect(object["loaded_to_input_ready_duration_ms"] as? Double == 10)
        #expect(
            Set(object.keys)
                == Set(expectedWork.keys).union([
                    "schema", "run_id", "sample", "metric", "duration_ms", "completed_uptime_ns",
                    "hydration_started_to_hydrated_duration_ms", "loaded_to_input_ready_duration_ms",
                    "loaded_to_focused_duration_ms", "loaded_to_stable_visible_duration_ms",
                ]))
        let text = try #require(String(data: completed, encoding: .utf8))
        #expect(!text.contains(privateValue))
        #expect(!text.contains("Fixture.md"))
        #expect(!text.contains("Other Private Note.md"))
        #expect(!text.contains(sessionID.uuidString))
        #expect(!text.contains(attempt.uuidString))
        let readsAfterCompletion = clockReads
        let returned = probe.measureNoteOpeningWork(
            .citationPresentation, documentID: "Fixture.md", editorSessionID: sessionID
        ) {
            operationCount += 1
            return privateValue
        }
        #expect(returned == privateValue)
        #expect(operationCount == 7)
        #expect(clockReads == readsAfterCompletion)
        #expect(try Data(contentsOf: fixture.result) == completed)
    }

    @Test(
        "Disabled, other-metric and unarmed work execute without reading the clock or recording",
        arguments: ["disabled", "indexed_search", "unarmed"])
    func noteOpeningWorkRequiresArmedMetric(scenario: String) throws {
        var clockReads = 0
        let fixture = try noteOpeningFixture(
            metric: scenario == "indexed_search" ? scenario : "note_open_to_input"
        ) {
            clockReads += 1
            return 10_000_000
        }
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let probe =
            scenario == "disabled"
            ? PerformanceProbe(
                environment: [:], arguments: [], bundleID: "com.scholium.qa",
                now: {
                    clockReads += 1
                    return 10_000_000
                }) : fixture.probe
        #expect(probe.isEnabled == (scenario != "disabled"))
        var operationCount = 0
        let value = probe.measureNoteOpeningWork(
            .outlineProjection, documentID: "Fixture.md", editorSessionID: UUID()
        ) {
            operationCount += 1
            return ["Exact", "operation", "value"]
        }
        #expect(value == ["Exact", "operation", "value"])
        #expect(operationCount == 1)
        #expect(clockReads == 0)
        #expect(!FileManager.default.fileExists(atPath: fixture.result.path))
    }

    @Test(
        "Work crossing attempt replacement or an invalid clock cannot contaminate the current opening")
    func noteOpeningWorkRejectsReplacedAttemptAndInvalidClock() throws {
        var timestamp: UInt64 = 10_000_000
        let fixture = try noteOpeningFixture { timestamp }
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let probe = fixture.probe
        let stale = try #require(probe.beginNoteOpening(documentID: "Fixture.md"))
        let oldSessionID = UUID()
        try #require(probe.bindNoteOpening(attemptID: stale, editorSessionID: oldSessionID))
        let sessionID = UUID()
        var replacement: UUID?
        timestamp = 20_000_000
        let value = probe.measureNoteOpeningWork(
            .citationPresentation, documentID: "Fixture.md", editorSessionID: oldSessionID
        ) {
            timestamp = 25_000_000
            replacement = probe.beginNoteOpening(documentID: "Fixture.md")
            _ = probe.bindNoteOpening(attemptID: replacement, editorSessionID: sessionID)
            timestamp = 30_000_000
            return 77
        }
        #expect(value == 77)
        let attempt = try #require(replacement)
        #expect(attempt != stale)
        #expect(probe.currentNoteOpeningAttempt(editorSessionID: sessionID) == attempt)
        timestamp = 24_000_000
        let preStart = probe.measureNoteOpeningWork(
            .citationPresentation, documentID: "Fixture.md", editorSessionID: sessionID
        ) {
            timestamp = 24_500_000
            return 88
        }
        #expect(preStart == 88)
        timestamp = 35_000_000
        probe.measureNoteOpeningWork(
            .citationPresentation, documentID: "Fixture.md", editorSessionID: sessionID
        ) {
            timestamp = 34_000_000
        }
        timestamp = 40_000_000
        probe.measureNoteOpeningWork(
            .outlineProjection, documentID: "Fixture.md", editorSessionID: sessionID
        ) {
            timestamp = 42_000_000
        }
        for (phase, time): (PerformanceProbe.NoteOpeningPhase, UInt64) in [
            (.hydrationStarted, 45_000_000), (.hydrated, 50_000_000), (.loaded, 55_000_000),
            (.stableVisible, 60_000_000), (.focused, 65_000_000),
        ] {
            timestamp = time
            probe.markNoteOpeningPhase(phase, attemptID: attempt, editorSessionID: sessionID)
        }
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixture.result)) as? [String: Any])
        #expect(!object.keys.contains(where: { $0.hasPrefix("citation_presentation_work_") }))
        #expect(object["outline_projection_work_total_ms"] as? Double == 2)
        #expect(object["outline_projection_work_max_ms"] as? Double == 2)
        #expect(object["outline_projection_work_count"] as? Double == 1)
        #expect(object["duration_ms"] as? Double == 40)
        #expect(
            probe.completedNoteOpeningSample(documentID: "Fixture.md", editorSessionID: sessionID) == 0)
    }

    @Test("Opening Web diagnostics are bounded, private and bound to the completed sample")
    func noteOpeningWebSamplesAreBoundedAndPrivate() throws {
        var timestamp: UInt64 = 10_000_000
        let fixture = try noteOpeningFixture(sampleCount: 2) { timestamp }
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let probe = fixture.probe
        let sessionID = UUID()
        let attempt = try #require(probe.beginNoteOpening(documentID: "Fixture.md"))
        #expect(probe.bindNoteOpening(attemptID: attempt, editorSessionID: sessionID))
        for phase: PerformanceProbe.NoteOpeningPhase in [
            .hydrationStarted, .hydrated, .loaded, .focused,
        ] {
            probe.markNoteOpeningPhase(phase, attemptID: attempt, editorSessionID: sessionID)
        }
        timestamp = 20_000_000
        probe.markNoteOpeningEditorPhase(.stableVisible, editorSessionID: sessionID, attemptID: attempt)
        let sample = try #require(
            probe.completedNoteOpeningSample(documentID: "Fixture.md", editorSessionID: sessionID))
        let web = fixture.result.deletingPathExtension().appendingPathExtension("web.jsonl")
        let safe = MarkdownEditorPerformanceSample(
            name: "opening-preparation", durationMilliseconds: 3, observed: ["loopCount": 2])
        for invalid in [
            MarkdownEditorPerformanceSample(
                name: "Private Research.md", durationMilliseconds: 1, observed: [:]),
            MarkdownEditorPerformanceSample(
                name: "document-load", durationMilliseconds: .nan, observed: [:]),
            MarkdownEditorPerformanceSample(
                name: "document-load", durationMilliseconds: -1, observed: [:]),
            MarkdownEditorPerformanceSample(
                name: "document-load", durationMilliseconds: 1, observed: ["source": 1]),
            MarkdownEditorPerformanceSample(
                name: "document-load", durationMilliseconds: 1, observed: ["documentLength": .infinity]),
        ] {
            probe.recordNoteOpeningWebSamples([invalid], documentID: "Fixture.md", sample: sample)
        }
        probe.recordNoteOpeningWebSamples(
            Array(repeating: safe, count: 257), documentID: "Fixture.md", sample: sample)
        probe.recordNoteOpeningWebSamples([safe], documentID: "Other.md", sample: sample)
        probe.recordNoteOpeningWebSamples([safe], documentID: "Fixture.md", sample: sample + 1)
        #expect(!FileManager.default.fileExists(atPath: web.path))
        let ring =
            Array(repeating: safe, count: 253) + [
                MarkdownEditorPerformanceSample(
                    name: "startup", durationMilliseconds: 2, observed: ["documentLength": 0]),
                MarkdownEditorPerformanceSample(
                    name: "memory-sample", durationMilliseconds: 0,
                    observed: ["documentLength": 10, "usedJSHeapBytes": 100]),
                MarkdownEditorPerformanceSample(
                    name: "projection", durationMilliseconds: 1,
                    observed: ["selectionScoped": 1, "widgetReuseCount": 0]),
            ]
        probe.recordNoteOpeningWebSamples(ring, documentID: "Fixture.md", sample: sample)
        let first = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: web)) as? [String: Any])
        #expect(Set(first.keys) == ["schema", "run_id", "sample", "samples"])
        #expect(first["schema"] as? String == "scholium-note-opening-web-v1")
        #expect(first["sample"] as? Int == 0)
        let values = try #require(first["samples"] as? [[String: Any]])
        #expect(values.count == 256)
        #expect(values.allSatisfy { Set($0.keys) == ["name", "duration_ms", "observed"] })
        #expect(
            try String(contentsOf: fixture.result, encoding: .utf8).split(separator: "\n").count == 1)

        timestamp = 30_000_000
        let replacement = try #require(probe.beginNoteOpening(documentID: "Fixture.md"))
        probe.recordNoteOpeningWebSamples([safe], documentID: "Fixture.md", sample: sample)
        #expect(probe.bindNoteOpening(attemptID: replacement, editorSessionID: sessionID))
        for phase: PerformanceProbe.NoteOpeningPhase in [
            .hydrationStarted, .hydrated, .loaded, .focused, .stableVisible,
        ] {
            probe.markNoteOpeningPhase(phase, attemptID: replacement, editorSessionID: sessionID)
        }
        probe.recordNoteOpeningWebSamples([safe], documentID: "Fixture.md", sample: sample)
        #expect(try String(contentsOf: web, encoding: .utf8).split(separator: "\n").count == 1)
        probe.recordNoteOpeningWebSamples([safe], documentID: "Fixture.md", sample: sample + 1)
        #expect(try String(contentsOf: web, encoding: .utf8).split(separator: "\n").count == 2)
        let outside = fixture.root.appendingPathComponent("outside.jsonl")
        try FileManager.default.removeItem(at: web)
        try FileManager.default.createSymbolicLink(at: web, withDestinationURL: outside)
        probe.recordNoteOpeningWebSamples([safe], documentID: "Fixture.md", sample: sample + 1)
        #expect(!FileManager.default.fileExists(atPath: outside.path))
    }

    @Test("First Read records activation-to-interactive phase decomposition")
    func firstReadRecordsActivationPhases() throws {
        let fileManager = FileManager.default
        let directory = URL(
            fileURLWithPath: "/private/tmp/scholium-performance-probe-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        let result = directory.appendingPathComponent("first_read_activation.jsonl")
        var times: [UInt64] = [
            10_000_000, 20_000_000, 30_000_000, 50_000_000,
            60_000_000, 80_000_000, 100_000_000,
        ]
        let probe = PerformanceProbe(
            environment: [
                "SCHOLIUM_PERFORMANCE_RESULTS_PATH": result.path,
                "SCHOLIUM_PERFORMANCE_METRIC": "first_read_activation",
                "SCHOLIUM_PERFORMANCE_RUN_ID": "first_read_test",
                "SCHOLIUM_PERFORMANCE_SAMPLE": "0",
                "SCHOLIUM_PERFORMANCE_SAMPLE_COUNT": "1",
                "SCHOLIUM_PERFORMANCE_EXPECTED_DOCUMENT": "Fixture.md",
            ],
            bundleID: "com.scholium.qa",
            now: { times.removeFirst() }
        )

        probe.beginReadActivation(documentID: "Fixture.md")
        probe.markFirstReadDocumentSelected(documentID: "Fixture.md")
        probe.markReadTaskStarted(documentID: "Fixture.md")
        probe.markReadHTMLReady(documentID: "Fixture.md")
        probe.markReadNavigationStarted(documentID: "Fixture.md")
        probe.markReadNavigationFinished(documentID: "Fixture.md")
        probe.markReadReady(documentID: "Fixture.md")

        let line = try #require(
            String(contentsOf: result, encoding: .utf8)
                .split(separator: "\n").first
        )
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        )
        #expect(object["duration_ms"] as? Double == 90)
        #expect(object["activation_to_document_selection_duration_ms"] as? Double == 10)
        #expect(
            object["document_selection_to_read_task_start_duration_ms"] as? Double
                == 10
        )
        #expect(object["read_task_start_to_html_ready_duration_ms"] as? Double == 20)
        #expect(
            object["read_html_ready_to_navigation_start_duration_ms"] as? Double
                == 10
        )
        #expect(object["read_navigation_duration_ms"] as? Double == 20)
        #expect(object["read_navigation_to_ready_duration_ms"] as? Double == 20)
    }

    @Test("Painted key latency accepts only a finite sample for the requested fixture")
    func editorKeyToPaintRequiresExpectedDocument() throws {
        let fileManager = FileManager.default
        let directory = URL(
            fileURLWithPath: "/private/tmp/scholium-performance-probe-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        let result = directory.appendingPathComponent("editor_key_to_paint.jsonl")
        let probe = PerformanceProbe(
            environment: [
                "SCHOLIUM_PERFORMANCE_RESULTS_PATH": result.path,
                "SCHOLIUM_PERFORMANCE_METRIC": "editor_key_to_paint",
                "SCHOLIUM_PERFORMANCE_RUN_ID": "key_paint_test",
                "SCHOLIUM_PERFORMANCE_SAMPLE": "4",
                "SCHOLIUM_PERFORMANCE_SAMPLE_COUNT": "1",
                "SCHOLIUM_PERFORMANCE_EXPECTED_DOCUMENT": "Fixture.md",
            ],
            bundleID: "com.scholium.qa",
            now: { 42_000_000 }
        )

        probe.recordEditorKeyToPaint(
            documentID: "Private/Research.md",
            durationMilliseconds: 12.5
        )
        probe.recordEditorKeyToPaint(documentID: "Fixture.md", durationMilliseconds: .nan)
        #expect(!fileManager.fileExists(atPath: result.path))
        probe.recordEditorKeyToPaint(documentID: "Fixture.md", durationMilliseconds: 12.5)

        let line = try #require(
            String(contentsOf: result, encoding: .utf8)
                .split(separator: "\n")
                .first
        )
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        )
        #expect(object["metric"] as? String == "editor_key_to_paint")
        #expect(object["sample"] as? Int == 4)
        #expect(object["duration_ms"] as? Double == 12.5)
        #expect(
            Set(object.keys) == [
                "schema",
                "run_id",
                "sample",
                "metric",
                "duration_ms",
                "completed_uptime_ns",
            ])
    }

    @Test("Editor mode latency records only the requested visible mode without research content")
    func editorModeTransitionRequiresMatchingVisibleMode() throws {
        let fileManager = FileManager.default
        let directory = URL(
            fileURLWithPath: "/private/tmp/scholium-performance-probe-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        let result = directory.appendingPathComponent("editor_mode_transition.jsonl")
        var times: [UInt64] = [1_000_000, 6_000_000, 21_000_000, 31_000_000]
        let probe = PerformanceProbe(
            environment: [
                "SCHOLIUM_PERFORMANCE_RESULTS_PATH": result.path,
                "SCHOLIUM_PERFORMANCE_METRIC": "editor_mode_transition",
                "SCHOLIUM_PERFORMANCE_RUN_ID": "probe_test",
                "SCHOLIUM_PERFORMANCE_SAMPLE": "0",
                "SCHOLIUM_PERFORMANCE_SAMPLE_COUNT": "1",
                "SCHOLIUM_PERFORMANCE_EXPECTED_DOCUMENT": "Fixture.md",
            ],
            bundleID: "com.scholium.qa",
            now: { times.removeFirst() }
        )

        probe.beginEditorModeTransition(documentID: "Private/Research.md", mode: .source)
        probe.markEditorModeVisible(documentID: "Private/Research.md", mode: .source)
        #expect(!fileManager.fileExists(atPath: result.path))

        probe.beginEditorModeTransition(documentID: "Fixture.md", mode: .source)
        probe.markEditorModeVisible(documentID: "Fixture.md", mode: .livePreview)
        #expect(!fileManager.fileExists(atPath: result.path))
        probe.markEditorModeBridgeStarted(mode: .source)
        probe.markEditorModeAcknowledged(documentID: "Fixture.md", mode: .source)
        probe.markEditorModeVisible(documentID: "Fixture.md", mode: .source)

        let line = try #require(
            String(contentsOf: result, encoding: .utf8)
                .split(separator: "\n")
                .first
        )
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        )
        #expect(object["metric"] as? String == "editor_mode_transition")
        #expect(object["observed_mode"] as? String == "source")
        #expect(object["duration_ms"] as? Double == 30)
        #expect(object["acknowledged_duration_ms"] as? Double == 20)
        #expect(object["bridge_started_duration_ms"] as? Double == 5)
        #expect(object["bridge_roundtrip_duration_ms"] as? Double == 15)
        #expect(object["layout_duration_ms"] as? Double == 10)
        #expect(
            Set(object.keys) == [
                "schema",
                "run_id",
                "sample",
                "metric",
                "duration_ms",
                "completed_uptime_ns",
                "observed_mode",
                "acknowledged_duration_ms",
                "bridge_started_duration_ms",
                "bridge_roundtrip_duration_ms",
                "layout_duration_ms",
            ])
    }

    @Test("Retained Editor progress accepts only the expected fixture projection")
    func retainedEditorProgressRequiresExpectedDocument() throws {
        let fileManager = FileManager.default
        let directory = URL(
            fileURLWithPath: "/private/tmp/scholium-performance-probe-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        let result = directory.appendingPathComponent("editor_retained_memory.jsonl")
        let probe = PerformanceProbe(
            environment: [
                "SCHOLIUM_PERFORMANCE_RESULTS_PATH": result.path,
                "SCHOLIUM_PERFORMANCE_METRIC": "editor_retained_memory",
                "SCHOLIUM_PERFORMANCE_RUN_ID": "memory_test",
                "SCHOLIUM_PERFORMANCE_SAMPLE": "0",
                "SCHOLIUM_PERFORMANCE_SAMPLE_COUNT": "2",
                "SCHOLIUM_PERFORMANCE_EXPECTED_DOCUMENT": "Fixture.md",
            ],
            bundleID: "com.scholium.qa"
        )

        probe.markEditorModeReady(documentID: UUID().uuidString, mode: .livePreview)
        #expect(!fileManager.fileExists(atPath: result.path))
        probe.markEditorModeReady(documentID: "Fixture.md", mode: .livePreview)
        probe.markEditorModeReady(documentID: "Fixture.md", mode: .source)

        let objects = try String(contentsOf: result, encoding: .utf8)
            .split(separator: "\n")
            .map { line in
                try #require(
                    try JSONSerialization.jsonObject(with: Data(line.utf8))
                        as? [String: Any]
                )
            }
        #expect(objects.count == 2)
        #expect(objects.compactMap { $0["mode"] as? String } == ["live_preview", "source"])
        #expect(
            objects.allSatisfy {
                Set($0.keys) == ["sample", "transition", "mode"]
            })
    }
}
