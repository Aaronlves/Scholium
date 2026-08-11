import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Performance probe")
@MainActor
struct PerformanceProbeTests {
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
