import ScholiumContracts
import Foundation

/// Records synthetic-fixture performance boundaries only when an explicit
/// `/tmp` JSONL destination and one supported metric are supplied. Records
/// contain timing and count metadata only—never queries, paths, or note text.
@MainActor
final class PerformanceProbe {
    enum Metric: String {
        case warmLibraryLaunch = "warm_library_launch"
        case indexedSearch = "indexed_search"
        case warmReadActivation = "warm_read_activation"
        case coldReadActivation = "cold_read_activation"
        case editorKeyToPaint = "editor_key_to_paint"
        case editorModeTransition = "editor_mode_transition"
        case editorCachedPreview = "editor_cached_preview"
        case warmEditActivation = "warm_edit_activation"
        case coldEditActivation = "cold_edit_activation"
        case editorVisibleProjection = "editor_visible_projection"
        case editorRetainedMemory = "editor_retained_memory"
    }

    static let shared = PerformanceProbe()

    private struct Configuration {
        let resultURL: URL
        let runID: String
        let firstSample: Int
        let sampleCount: Int
        let metric: Metric
        let expectedQuery: String?
        let expectedDocument: String?
        let expectedCount: Int?
        let externalStartNanoseconds: UInt64?
    }

    private let configuration: Configuration?
    private let now: () -> UInt64
    private var searchStartNanoseconds: UInt64?
    private var readStartNanoseconds: UInt64?
    private var editorModeTransition: (
        documentID: String,
        mode: MarkdownEditorMode,
        startNanoseconds: UInt64,
        bridgeStartedNanoseconds: UInt64?,
        acknowledgedNanoseconds: UInt64?
    )?
    private var editActivation: (
        documentID: String,
        startNanoseconds: UInt64
    )?
    private var warmLibraryWindowModelInitializationNanoseconds: UInt64?
    private var warmLibraryWorkspaceReadyNanoseconds: UInt64?
    private var warmLibraryProjectionNanoseconds: UInt64?
    private var searchIsArmed = true
    private var readIsArmed = true
    private var recordedSampleCount = 0

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleID: String? = Bundle.main.bundleIdentifier,
        now: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) {
        self.now = now
        let requestedSampleCount = environment["SCHOLIUM_PERFORMANCE_SAMPLE_COUNT"]
            .flatMap(Int.init) ?? 1
        guard let rawURL = environment["SCHOLIUM_PERFORMANCE_RESULTS_PATH"],
              let rawMetric = environment["SCHOLIUM_PERFORMANCE_METRIC"],
              let metric = Metric(rawValue: rawMetric),
              let rawRunID = environment["SCHOLIUM_PERFORMANCE_RUN_ID"],
              Self.isSafeRunID(rawRunID),
              let bundleID,
              let resultURL = Self.safeResultURL(rawURL, runID: rawRunID, bundleID: bundleID),
              let rawSample = environment["SCHOLIUM_PERFORMANCE_SAMPLE"],
              let sample = Int(rawSample),
              sample >= 0,
              requestedSampleCount > 0,
              requestedSampleCount <= 1_000,
              sample <= Int.max - requestedSampleCount else {
            configuration = nil
            return
        }
        configuration = Configuration(
            resultURL: resultURL,
            runID: rawRunID,
            firstSample: sample,
            sampleCount: requestedSampleCount,
            metric: metric,
            expectedQuery: environment["SCHOLIUM_PERFORMANCE_EXPECTED_QUERY"],
            expectedDocument: environment["SCHOLIUM_PERFORMANCE_EXPECTED_DOCUMENT"],
            expectedCount: environment["SCHOLIUM_PERFORMANCE_EXPECTED_COUNT"].flatMap(Int.init),
            externalStartNanoseconds: environment["SCHOLIUM_PERFORMANCE_STARTED_NS"].flatMap(UInt64.init)
        )
    }

    var isEnabled: Bool { configuration != nil }
    var measuresWarmLibraryLaunch: Bool {
        configuration?.metric == .warmLibraryLaunch
    }
    var measuresEditorModeTransition: Bool {
        configuration?.metric == .editorModeTransition
    }
    var measuresEditorKeyToPaint: Bool {
        configuration?.metric == .editorKeyToPaint
    }
    var measuresEditorCachedPreview: Bool {
        configuration?.metric == .editorCachedPreview
    }
    var measuresEditorVisibleProjection: Bool {
        configuration?.metric == .editorVisibleProjection
    }
    var measuresEditorVisibility: Bool {
        configuration?.metric == .editorModeTransition
            || configuration?.metric == .warmEditActivation
            || configuration?.metric == .coldEditActivation
    }

    func markWarmLibraryWindowModelInitializationStarted() {
        guard configuration?.metric == .warmLibraryLaunch,
              warmLibraryWindowModelInitializationNanoseconds == nil else { return }
        warmLibraryWindowModelInitializationNanoseconds = now()
    }

    func markWarmLibraryWorkspaceReady() {
        guard configuration?.metric == .warmLibraryLaunch,
              warmLibraryWorkspaceReadyNanoseconds == nil else { return }
        warmLibraryWorkspaceReadyNanoseconds = now()
    }

    func markWarmLibraryProjectionReady() {
        guard configuration?.metric == .warmLibraryLaunch,
              warmLibraryProjectionNanoseconds == nil else { return }
        warmLibraryProjectionNanoseconds = now()
    }

    func beginSearch(query: String) {
        guard let configuration, configuration.metric == .indexedSearch else { return }
        guard query == configuration.expectedQuery else {
            searchStartNanoseconds = nil
            searchIsArmed = true
            return
        }
        guard searchIsArmed else { return }
        searchIsArmed = false
        searchStartNanoseconds = now()
    }

    func markSearchResultsReady(query: String, resultCount: Int) {
        guard let configuration,
              configuration.metric == .indexedSearch,
              query == configuration.expectedQuery,
              configuration.expectedCount.map({ $0 == resultCount }) ?? true,
              let start = searchStartNanoseconds else { return }
        record(startNanoseconds: start, observedCount: resultCount)
    }

    func beginReadActivation(documentID: String) {
        guard let configuration, configuration.metric == .warmReadActivation else { return }
        guard documentID == configuration.expectedDocument else {
            readStartNanoseconds = nil
            readIsArmed = true
            return
        }
        guard readIsArmed else { return }
        readIsArmed = false
        readStartNanoseconds = now()
    }

    func markReadReady(documentID: String) {
        guard let configuration,
              documentID == configuration.expectedDocument else { return }
        switch configuration.metric {
        case .warmReadActivation:
            guard let start = readStartNanoseconds else { return }
            record(startNanoseconds: start, observedCount: nil)
        case .coldReadActivation:
            guard let start = configuration.externalStartNanoseconds else { return }
            record(startNanoseconds: start, observedCount: nil)
        default:
            return
        }
    }

    func beginEditorModeTransition(
        documentID: String,
        mode: MarkdownEditorMode
    ) {
        guard let configuration,
              configuration.metric == .editorModeTransition,
              documentID == configuration.expectedDocument,
              recordedSampleCount < configuration.sampleCount else {
            editorModeTransition = nil
            return
        }
        editorModeTransition = (
            documentID: documentID,
            mode: mode,
            startNanoseconds: now(),
            bridgeStartedNanoseconds: nil,
            acknowledgedNanoseconds: nil
        )
    }

    func markEditorModeBridgeStarted(mode: MarkdownEditorMode) {
        guard let configuration,
              configuration.metric == .editorModeTransition,
              var transition = editorModeTransition,
              transition.mode == mode,
              transition.bridgeStartedNanoseconds == nil else { return }
        transition.bridgeStartedNanoseconds = now()
        editorModeTransition = transition
    }

    func markEditorModeAcknowledged(
        documentID: String,
        mode: MarkdownEditorMode
    ) {
        guard let configuration,
              configuration.metric == .editorModeTransition,
              documentID == configuration.expectedDocument,
              var transition = editorModeTransition,
              transition.documentID == documentID,
              transition.mode == mode,
              transition.acknowledgedNanoseconds == nil else { return }
        transition.acknowledgedNanoseconds = now()
        editorModeTransition = transition
    }

    /// Completes only after the acknowledged editor mode has crossed the
    /// native layout boundary that exposes it to accessibility. The bridge
    /// acknowledgment alone is intentionally not a visible-latency endpoint.
    func markEditorModeVisible(
        documentID: String,
        mode: MarkdownEditorMode
    ) {
        guard let configuration,
              configuration.metric == .editorModeTransition,
              documentID == configuration.expectedDocument,
              let transition = editorModeTransition,
              transition.documentID == documentID,
              transition.mode == mode,
              let bridgeStarted = transition.bridgeStartedNanoseconds,
              let acknowledged = transition.acknowledgedNanoseconds else { return }
        let completed = now()
        guard bridgeStarted >= transition.startNanoseconds,
              acknowledged >= bridgeStarted,
              completed >= acknowledged else { return }
        editorModeTransition = nil
        record(
            startNanoseconds: transition.startNanoseconds,
            observedCount: nil,
            observedMode: mode == .livePreview ? "live_preview" : "source",
            completedNanoseconds: completed,
            phaseDurations: [
                "acknowledged_duration_ms": Double(
                    acknowledged - transition.startNanoseconds
                ) / 1_000_000,
                "bridge_started_duration_ms": Double(
                    bridgeStarted - transition.startNanoseconds
                ) / 1_000_000,
                "bridge_roundtrip_duration_ms": Double(
                    acknowledged - bridgeStarted
                ) / 1_000_000,
                "layout_duration_ms": Double(completed - acknowledged) / 1_000_000,
            ]
        )
    }

    func recordEditorKeyToPaint(
        documentID: String,
        durationMilliseconds: Double
    ) {
        guard let configuration,
              configuration.metric == .editorKeyToPaint,
              documentID == configuration.expectedDocument,
              durationMilliseconds.isFinite,
              durationMilliseconds > 0,
              durationMilliseconds < 600_000,
              recordedSampleCount < configuration.sampleCount else { return }
        let completed = now()
        let object: [String: Any] = [
            "schema": "scholium-performance-v1",
            "run_id": configuration.runID,
            "sample": configuration.firstSample + recordedSampleCount,
            "metric": configuration.metric.rawValue,
            "duration_ms": durationMilliseconds,
            "completed_uptime_ns": completed,
        ]
        guard append(object, to: configuration.resultURL) else { return }
        recordedSampleCount += 1
    }

    func recordEditorWebDuration(
        documentID: String,
        metric: Metric,
        durationMilliseconds: Double
    ) {
        guard let configuration,
              configuration.metric == metric,
              metric == .editorCachedPreview || metric == .editorVisibleProjection,
              documentID == configuration.expectedDocument,
              durationMilliseconds.isFinite,
              durationMilliseconds > 0,
              durationMilliseconds < 600_000,
              recordedSampleCount < configuration.sampleCount else { return }
        let completed = now()
        let object: [String: Any] = [
            "schema": "scholium-performance-v1",
            "run_id": configuration.runID,
            "sample": configuration.firstSample + recordedSampleCount,
            "metric": configuration.metric.rawValue,
            "duration_ms": durationMilliseconds,
            "completed_uptime_ns": completed,
        ]
        guard append(object, to: configuration.resultURL) else { return }
        recordedSampleCount += 1
    }

    func beginWarmEditActivation(documentID: String) {
        guard let configuration,
              configuration.metric == .warmEditActivation,
              documentID == configuration.expectedDocument,
              recordedSampleCount < configuration.sampleCount else {
            editActivation = nil
            return
        }
        editActivation = (documentID: documentID, startNanoseconds: now())
    }

    func markEditorVisible(documentID: String) {
        guard let configuration,
              documentID == configuration.expectedDocument else { return }
        switch configuration.metric {
        case .warmEditActivation:
            guard let activation = editActivation,
                  activation.documentID == documentID else { return }
            editActivation = nil
            record(startNanoseconds: activation.startNanoseconds, observedCount: nil)
        case .coldEditActivation:
            guard let start = configuration.externalStartNanoseconds else { return }
            record(startNanoseconds: start, observedCount: nil)
        default:
            return
        }
    }

    func markLibraryReady(noteCount: Int) {
        guard let configuration,
              configuration.metric == .warmLibraryLaunch,
              configuration.expectedCount.map({ $0 == noteCount }) ?? true,
              let start = configuration.externalStartNanoseconds else { return }
        let completed = now()
        var phases: [String: Double] = [:]
        if let windowModelInitialization = warmLibraryWindowModelInitializationNanoseconds,
           let workspaceReady = warmLibraryWorkspaceReadyNanoseconds,
           let projection = warmLibraryProjectionNanoseconds,
           windowModelInitialization >= start,
           workspaceReady >= windowModelInitialization,
           projection >= workspaceReady,
           completed >= projection {
            phases = [
                "process_to_window_model_init_duration_ms": milliseconds(
                    windowModelInitialization - start
                ),
                "window_model_init_to_workspace_ready_duration_ms": milliseconds(
                    workspaceReady - windowModelInitialization
                ),
                "workspace_ready_to_projection_duration_ms": milliseconds(
                    projection - workspaceReady
                ),
                "projection_to_layout_duration_ms": milliseconds(completed - projection),
            ]
        }
        record(
            startNanoseconds: start,
            observedCount: noteCount,
            completedNanoseconds: completed,
            phaseDurations: phases
        )
    }

    /// Publishes the retained Editor handshake only after the WebKit bridge
    /// has acknowledged the requested mode. The UI-test driver can read the
    /// sampler acknowledgment, but it deliberately cannot write into the app
    /// container that owns this probe file.
    func markEditorModeReady(documentID: String, mode: MarkdownEditorMode) {
        guard let configuration,
              configuration.metric == .editorRetainedMemory,
              documentID == configuration.expectedDocument,
              recordedSampleCount < configuration.sampleCount else { return }
        let expectedMode: MarkdownEditorMode = recordedSampleCount.isMultiple(of: 2)
            ? .livePreview
            : .source
        guard mode == expectedMode else { return }
        let object: [String: Any] = [
            "sample": configuration.firstSample + recordedSampleCount,
            "transition": configuration.firstSample + recordedSampleCount,
            "mode": mode == .livePreview ? "live_preview" : "source",
        ]
        guard append(object, to: configuration.resultURL) else { return }
        recordedSampleCount += 1
    }

    private func record(
        startNanoseconds: UInt64,
        observedCount: Int?,
        observedMode: String? = nil,
        completedNanoseconds: UInt64? = nil,
        phaseDurations: [String: Double] = [:]
    ) {
        guard let configuration,
              recordedSampleCount < configuration.sampleCount else { return }
        let end = completedNanoseconds ?? now()
        guard end >= startNanoseconds else { return }
        let elapsed = end - startNanoseconds
        guard elapsed < 600_000_000_000 else { return }
        var object: [String: Any] = [
            "schema": "scholium-performance-v1",
            "run_id": configuration.runID,
            "sample": configuration.firstSample + recordedSampleCount,
            "metric": configuration.metric.rawValue,
            "duration_ms": Double(elapsed) / 1_000_000,
            "completed_uptime_ns": end,
        ]
        if let observedCount { object["observed_count"] = observedCount }
        if let observedMode { object["observed_mode"] = observedMode }
        object.merge(phaseDurations) { _, phaseDuration in phaseDuration }
        guard append(object, to: configuration.resultURL) else { return }
        recordedSampleCount += 1
        searchStartNanoseconds = nil
        readStartNanoseconds = nil
    }

    private func milliseconds(_ nanoseconds: UInt64) -> Double {
        Double(nanoseconds) / 1_000_000
    }

    private func append(_ object: [String: Any], to resultURL: URL) -> Bool {
        guard let encoded = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        ) else { return false }
        do {
            if !FileManager.default.fileExists(atPath: resultURL.path) {
                guard FileManager.default.createFile(atPath: resultURL.path, contents: nil) else {
                    return false
                }
            }
            let values = try resultURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { return false }
            let handle = try FileHandle(forWritingTo: resultURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: encoded + Data([0x0A]))
            try handle.close()
            return true
        } catch {
            // Performance evidence is optional and must never affect product
            // behavior or expose a research path through user-facing errors.
            return false
        }
    }

    private static func safeResultURL(
        _ rawPath: String,
        runID: String,
        bundleID: String
    ) -> URL? {
        guard bundleID == "com.scholium.app" || bundleID == "com.scholium.qa" else {
            return nil
        }
        let candidate = URL(fileURLWithPath: rawPath).standardizedFileURL
        guard candidate.pathExtension == "jsonl",
              candidate.lastPathComponent == (rawPath as NSString).lastPathComponent else {
            return nil
        }
        let parent = candidate.deletingLastPathComponent().resolvingSymlinksInPath()
        let sandboxSuffix = "/Library/Containers/\(bundleID)/Data/tmp/"
            + "scholium-performance-\(runID)/raw"
        let isSystemTemporary = parent.path == "/tmp"
            || parent.path.hasPrefix("/tmp/")
            || parent.path == "/private/tmp"
            || parent.path.hasPrefix("/private/tmp/")
        let sandboxRaw = parent.path.components(separatedBy: sandboxSuffix).first.map {
            $0 + sandboxSuffix
        }
        let isIsolatedSandboxTemporary = parent.path.hasPrefix("/Users/")
            && sandboxRaw.map {
                parent.path == $0 || parent.path.hasPrefix($0 + "/")
            } == true
        guard isSystemTemporary || isIsolatedSandboxTemporary else {
            return nil
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return parent.appendingPathComponent(candidate.lastPathComponent, isDirectory: false)
    }

    private static func isSafeRunID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 80 && value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        }
    }
}
