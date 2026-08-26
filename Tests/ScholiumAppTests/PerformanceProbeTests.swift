import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Performance probe")
@MainActor
struct PerformanceProbeTests {
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
                    "SCHOLIUM_PERFORMANCE_RESULTS_PATH": directory
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
                "SCHOLIUM_PERFORMANCE_RESULTS_PATH": directory
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
                "SCHOLIUM_PERFORMANCE_RESULTS_PATH": directory
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
        let runRoot = temporary
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
            2_000_000, 6_000_000, 11_000_000, 20_000_000,
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
        probe.markWarmLibraryWorkspaceReady()
        probe.markWarmLibraryProjectionReady()
        probe.markLibraryReady(noteCount: 267)
        #expect(fileManager.fileExists(atPath: result.path))

        var rejectedEnvironment = environment
        rejectedEnvironment["SCHOLIUM_PERFORMANCE_RESULTS_PATH"] = outside
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
                "SCHOLIUM_PERFORMANCE_RESULTS_PATH": directory
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
        #expect(!FileManager.default.fileExists(
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
            2_000_000, 6_000_000, 11_000_000, 20_000_000,
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
        probe.markWarmLibraryWorkspaceReady()
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
        #expect(Set(object.keys) == [
            "schema", "run_id", "sample", "metric", "duration_ms",
            "completed_uptime_ns", "observed_count",
            "process_to_window_model_init_duration_ms",
            "window_model_init_to_workspace_ready_duration_ms",
            "workspace_ready_to_projection_duration_ms",
            "projection_to_layout_duration_ms",
        ])
    }

    @Test("Editor Web metrics remain fixture-bound and privacy-safe")
    func editorWebMetricsRequireExpectedDocument() throws {
        let fileManager = FileManager.default
        let directory = URL(
            fileURLWithPath: "/private/tmp/scholium-performance-probe-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        let result = directory.appendingPathComponent("editor_cached_preview.jsonl")
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
            now: { 50_000_000 }
        )

        probe.recordEditorWebDuration(
            documentID: "Private.md",
            metric: .editorCachedPreview,
            durationMilliseconds: 8
        )
        #expect(!fileManager.fileExists(atPath: result.path))
        probe.recordEditorWebDuration(
            documentID: "Fixture.md",
            metric: .editorCachedPreview,
            durationMilliseconds: 8
        )

        let object = try #require(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: result)
            ) as? [String: Any]
        )
        #expect(object["metric"] as? String == "editor_cached_preview")
        #expect(object["duration_ms"] as? Double == 8)
        #expect(Set(object.keys) == [
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
        #expect(Set(object.keys) == [
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
        #expect(Set(object.keys) == [
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
        #expect(objects.allSatisfy {
            Set($0.keys) == ["sample", "transition", "mode"]
        })
    }
}
