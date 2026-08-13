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
        case firstReadActivation = "first_read_activation"
        case editorKeyToPaint = "editor_key_to_paint"
        case editorModeTransition = "editor_mode_transition"
        case editorCachedPreview = "editor_cached_preview"
        case warmEditActivation = "warm_edit_activation"
        case firstEditActivation = "first_edit_activation"
        case editorVisibleProjection = "editor_visible_projection"
        case editorRetainedMemory = "editor_retained_memory"
        case editorLargeCJKCorrectness = "editor_large_cjk_correctness"
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
    private var startupSafetyReadyNanoseconds: UInt64?
    private var vaultConfigurationReadyNanoseconds: UInt64?
    private var warmLibraryProjectionNanoseconds: UInt64?
    private var firstReadDocumentSelectedNanoseconds: UInt64?
    private var firstReadTaskStartedNanoseconds: UInt64?
    private var firstReadHTMLReadyNanoseconds: UInt64?
    private var firstReadNavigationStartedNanoseconds: UInt64?
    private var firstReadNavigationFinishedNanoseconds: UInt64?
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
    var exercisesLargeCJKCorrectness: Bool {
        configuration?.metric == .editorLargeCJKCorrectness
    }
    var measuresEditorVisibility: Bool {
        configuration?.metric == .editorModeTransition
            || configuration?.metric == .warmEditActivation
            || configuration?.metric == .firstEditActivation
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

    func markStartupSafetyReady() {
        guard configuration?.metric == .warmLibraryLaunch,
              startupSafetyReadyNanoseconds == nil else { return }
        startupSafetyReadyNanoseconds = now()
    }

    func markVaultConfigurationReady() {
        guard configuration?.metric == .warmLibraryLaunch,
              vaultConfigurationReadyNanoseconds == nil else { return }
        vaultConfigurationReadyNanoseconds = now()
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
        guard let configuration,
              configuration.metric == .warmReadActivation
                || configuration.metric == .firstReadActivation else { return }
        guard documentID == configuration.expectedDocument else {
            readStartNanoseconds = nil
            readIsArmed = true
            return
        }
        guard readIsArmed else { return }
        readIsArmed = false
        readStartNanoseconds = now()
    }

    func markFirstReadDocumentSelected(documentID: String) {
        guard measuresExpectedFirstRead(documentID),
              firstReadDocumentSelectedNanoseconds == nil else { return }
        firstReadDocumentSelectedNanoseconds = now()
    }

    func markReadTaskStarted(documentID: String) {
        guard measuresExpectedFirstRead(documentID),
              firstReadTaskStartedNanoseconds == nil else { return }
        firstReadTaskStartedNanoseconds = now()
    }

    func markReadHTMLReady(documentID: String) {
        guard measuresExpectedFirstRead(documentID),
              firstReadHTMLReadyNanoseconds == nil else { return }
        firstReadHTMLReadyNanoseconds = now()
    }

    func markReadNavigationStarted(documentID: String) {
        guard measuresExpectedFirstRead(documentID),
              firstReadNavigationStartedNanoseconds == nil else { return }
        firstReadNavigationStartedNanoseconds = now()
    }

    func markReadNavigationFinished(documentID: String) {
        guard measuresExpectedFirstRead(documentID),
              firstReadNavigationFinishedNanoseconds == nil else { return }
        firstReadNavigationFinishedNanoseconds = now()
    }

    func markReadReady(documentID: String) {
        guard let configuration,
              documentID == configuration.expectedDocument else { return }
        switch configuration.metric {
        case .warmReadActivation:
            guard let start = readStartNanoseconds else { return }
            record(startNanoseconds: start, observedCount: nil)
        case .firstReadActivation:
            guard let start = readStartNanoseconds else { return }
            let completed = now()
            let phases = firstReadPhaseDurations(
                startNanoseconds: start,
                completedNanoseconds: completed
            )
            record(
                startNanoseconds: start,
                observedCount: nil,
                completedNanoseconds: completed,
                phaseDurations: phases
            )
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

    func beginEditActivation(documentID: String) {
        guard let configuration,
              (configuration.metric == .warmEditActivation
                || configuration.metric == .firstEditActivation),
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
        case .warmEditActivation, .firstEditActivation:
            guard let activation = editActivation,
                  activation.documentID == documentID else { return }
            editActivation = nil
            record(startNanoseconds: activation.startNanoseconds, observedCount: nil)
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
        record(
            startNanoseconds: start,
            observedCount: noteCount,
            completedNanoseconds: completed,
            phaseDurations: launchPhaseDurations(
                startNanoseconds: start,
                completedNanoseconds: completed
            )
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

    /// Persists the packaged CJK journey's final privacy-safe handshake only
    /// after the driver has restored the exact source and requested this
    /// record. The application owns the destination inside its sandbox.
    func recordLargeCJKCorrectness(documentID: String, source: String) {
        guard let configuration,
              configuration.metric == .editorLargeCJKCorrectness,
              documentID == configuration.expectedDocument,
              recordedSampleCount == 0 else { return }
        let characterCount = source.unicodeScalars.reduce(into: 0) { count, scalar in
            if (0x4E00...0x9FFF).contains(scalar.value) { count += 1 }
        }
        guard characterCount == 100_000 else { return }
        let object: [String: Any] = [
            "schema": "scholium-cjk-correctness-v1",
            "run_id": configuration.runID,
            "character_count": characterCount,
            "beginning_edit_undo": true,
            "middle_edit_undo": true,
            "end_edit_save": true,
            "mode_switching": true,
            "exact_source_restored": true,
        ]
        guard append(object, to: configuration.resultURL) else { return }
        recordedSampleCount = 1
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

    private func measuresExpectedFirstRead(_ documentID: String) -> Bool {
        configuration?.metric == .firstReadActivation
            && configuration?.expectedDocument == documentID
    }

    private func launchPhaseDurations(
        startNanoseconds: UInt64,
        completedNanoseconds: UInt64
    ) -> [String: Double] {
        guard let windowModelInitialization = warmLibraryWindowModelInitializationNanoseconds,
              let workspaceReady = warmLibraryWorkspaceReadyNanoseconds,
              let projection = warmLibraryProjectionNanoseconds,
              windowModelInitialization >= startNanoseconds,
              workspaceReady >= windowModelInitialization,
              projection >= workspaceReady,
              completedNanoseconds >= projection else { return [:] }
        var phases = [
            "process_to_window_model_init_duration_ms": milliseconds(
                windowModelInitialization - startNanoseconds
            ),
            "window_model_init_to_workspace_ready_duration_ms": milliseconds(
                workspaceReady - windowModelInitialization
            ),
            "workspace_ready_to_projection_duration_ms": milliseconds(
                projection - workspaceReady
            ),
            "projection_to_layout_duration_ms": milliseconds(
                completedNanoseconds - projection
            ),
        ]
        if let startupSafetyReady = startupSafetyReadyNanoseconds,
           let vaultConfigurationReady = vaultConfigurationReadyNanoseconds,
           startupSafetyReady >= workspaceReady,
           vaultConfigurationReady >= startupSafetyReady,
           projection >= vaultConfigurationReady {
            phases["workspace_ready_to_startup_safety_ready_duration_ms"] =
                milliseconds(startupSafetyReady - workspaceReady)
            phases["startup_safety_ready_to_vault_configuration_ready_duration_ms"] =
                milliseconds(vaultConfigurationReady - startupSafetyReady)
            phases["vault_configuration_ready_to_projection_duration_ms"] =
                milliseconds(projection - vaultConfigurationReady)
        }
        return phases
    }

    private func firstReadPhaseDurations(
        startNanoseconds: UInt64,
        completedNanoseconds: UInt64
    ) -> [String: Double] {
        guard let documentSelected = firstReadDocumentSelectedNanoseconds,
              let readTaskStarted = firstReadTaskStartedNanoseconds,
              let htmlReady = firstReadHTMLReadyNanoseconds,
              let navigationStarted = firstReadNavigationStartedNanoseconds,
              let navigationFinished = firstReadNavigationFinishedNanoseconds,
              documentSelected >= startNanoseconds,
              readTaskStarted >= documentSelected,
              htmlReady >= readTaskStarted,
              navigationStarted >= htmlReady,
              navigationFinished >= navigationStarted,
              completedNanoseconds >= navigationFinished else { return [:] }
        return [
            "activation_to_document_selection_duration_ms": milliseconds(
                documentSelected - startNanoseconds
            ),
            "document_selection_to_read_task_start_duration_ms": milliseconds(
                readTaskStarted - documentSelected
            ),
            "read_task_start_to_html_ready_duration_ms": milliseconds(
                htmlReady - readTaskStarted
            ),
            "read_html_ready_to_navigation_start_duration_ms": milliseconds(
                navigationStarted - htmlReady
            ),
            "read_navigation_duration_ms": milliseconds(
                navigationFinished - navigationStarted
            ),
            "read_navigation_to_ready_duration_ms": milliseconds(
                completedNanoseconds - navigationFinished
            ),
        ]
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
