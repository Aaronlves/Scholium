import Foundation
import ScholiumContracts

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
        case editorModeTransition = "editor_mode_transition"
        case warmEditActivation = "warm_edit_activation"
        case firstEditActivation = "first_edit_activation"
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
    private var editorModeTransition:
        (
            documentID: String,
            mode: MarkdownEditorMode,
            startNanoseconds: UInt64,
            layoutStartedNanoseconds: UInt64?,
            appliedNanoseconds: UInt64?
        )?
    private var editActivation:
        (
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
    private var firstReadSourceReadyNanoseconds: UInt64?
    private var firstReadNativeLayoutStartedNanoseconds: UInt64?
    private var firstReadNativeLayoutFinishedNanoseconds: UInt64?
    private var searchIsArmed = true
    private var readIsArmed = true
    private var recordedSampleCount = 0

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments,
        bundleID: String? = Bundle.main.bundleIdentifier,
        now: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) {
        self.now = now
        let requestedSampleCount =
            environment["SCHOLIUM_PERFORMANCE_SAMPLE_COUNT"]
            .flatMap(Int.init) ?? 1
        guard let rawURL = environment["SCHOLIUM_PERFORMANCE_RESULTS_PATH"],
            let rawMetric = environment["SCHOLIUM_PERFORMANCE_METRIC"],
            let metric = Metric(rawValue: rawMetric),
            let rawRunID = environment["SCHOLIUM_PERFORMANCE_RUN_ID"],
            Self.isSafeRunID(rawRunID),
            let bundleID,
            Self.allowsConfiguration(
                environment: environment,
                bundleID: bundleID,
                arguments: arguments
            ),
            let resultURL = Self.safeResultURL(
                rawURL,
                runID: rawRunID,
                bundleID: bundleID,
                isolatedHomePath: environment["SCHOLIUM_HOME"]
            ),
            let rawSample = environment["SCHOLIUM_PERFORMANCE_SAMPLE"],
            let sample = Int(rawSample),
            sample >= 0,
            requestedSampleCount > 0,
            requestedSampleCount <= 1_000,
            sample <= Int.max - requestedSampleCount
        else {
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
    var exercisesLargeCJKCorrectness: Bool {
        configuration?.metric == .editorLargeCJKCorrectness
    }
    var measuresEditorRetainedMemory: Bool {
        configuration?.metric == .editorRetainedMemory
    }
    var requiresInitialReviewPresentation: Bool {
        configuration?.metric == .warmReadActivation
            || configuration?.metric == .firstReadActivation
            || configuration?.metric == .firstEditActivation
    }

    func markWarmLibraryWindowModelInitializationStarted() {
        guard configuration?.metric == .warmLibraryLaunch,
            warmLibraryWindowModelInitializationNanoseconds == nil
        else { return }
        warmLibraryWindowModelInitializationNanoseconds = now()
    }

    func markWarmLibraryWorkspaceReady() {
        guard configuration?.metric == .warmLibraryLaunch,
            warmLibraryWorkspaceReadyNanoseconds == nil
        else { return }
        warmLibraryWorkspaceReadyNanoseconds = now()
    }

    func markStartupSafetyReady() {
        guard configuration?.metric == .warmLibraryLaunch,
            startupSafetyReadyNanoseconds == nil
        else { return }
        startupSafetyReadyNanoseconds = now()
    }

    func markVaultConfigurationReady() {
        guard configuration?.metric == .warmLibraryLaunch,
            vaultConfigurationReadyNanoseconds == nil
        else { return }
        vaultConfigurationReadyNanoseconds = now()
    }

    func markWarmLibraryProjectionReady() {
        guard configuration?.metric == .warmLibraryLaunch,
            warmLibraryProjectionNanoseconds == nil
        else { return }
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
            let start = searchStartNanoseconds
        else { return }
        record(startNanoseconds: start, observedCount: resultCount)
    }

    func beginReadActivation(documentID: String) {
        guard let configuration,
            configuration.metric == .warmReadActivation
                || configuration.metric == .firstReadActivation
        else { return }
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
            firstReadDocumentSelectedNanoseconds == nil
        else { return }
        firstReadDocumentSelectedNanoseconds = now()
    }

    func markReadTaskStarted(documentID: String) {
        guard measuresExpectedFirstRead(documentID),
            firstReadTaskStartedNanoseconds == nil
        else { return }
        firstReadTaskStartedNanoseconds = now()
    }

    func markReadSourceReady(documentID: String) {
        guard measuresExpectedFirstRead(documentID),
            firstReadSourceReadyNanoseconds == nil
        else { return }
        firstReadSourceReadyNanoseconds = now()
    }

    func markReadNativeLayoutStarted(documentID: String) {
        guard measuresExpectedFirstRead(documentID),
            firstReadNativeLayoutStartedNanoseconds == nil
        else { return }
        firstReadNativeLayoutStartedNanoseconds = now()
    }

    func markReadNativeLayoutFinished(documentID: String) {
        guard measuresExpectedFirstRead(documentID),
            firstReadNativeLayoutFinishedNanoseconds == nil
        else { return }
        firstReadNativeLayoutFinishedNanoseconds = now()
    }

    func markReadReady(documentID: String) {
        guard let configuration,
            documentID == configuration.expectedDocument
        else { return }
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
            recordedSampleCount < configuration.sampleCount
        else {
            editorModeTransition = nil
            return
        }
        editorModeTransition = (
            documentID: documentID,
            mode: mode,
            startNanoseconds: now(),
            layoutStartedNanoseconds: nil,
            appliedNanoseconds: nil
        )
    }

    func markEditorModeLayoutStarted(mode: MarkdownEditorMode) {
        guard let configuration,
            configuration.metric == .editorModeTransition,
            var transition = editorModeTransition,
            transition.mode == mode,
            transition.layoutStartedNanoseconds == nil
        else { return }
        transition.layoutStartedNanoseconds = now()
        editorModeTransition = transition
    }

    func markEditorModeApplied(
        documentID: String,
        mode: MarkdownEditorMode
    ) {
        guard let configuration,
            configuration.metric == .editorModeTransition,
            documentID == configuration.expectedDocument,
            var transition = editorModeTransition,
            transition.documentID == documentID,
            transition.mode == mode,
            transition.appliedNanoseconds == nil
        else { return }
        transition.appliedNanoseconds = now()
        editorModeTransition = transition
    }

    /// Completes after the applied mode crosses the native container layout
    /// boundary. Source loading or configuration alone is not this endpoint.
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
            let layoutStarted = transition.layoutStartedNanoseconds,
            let applied = transition.appliedNanoseconds
        else { return }
        let completed = now()
        guard layoutStarted >= transition.startNanoseconds,
            applied >= layoutStarted,
            completed >= applied
        else { return }
        editorModeTransition = nil
        record(
            startNanoseconds: transition.startNanoseconds,
            observedCount: nil,
            observedMode: mode.rawValue,
            completedNanoseconds: completed,
            phaseDurations: [
                "applied_duration_ms": Double(
                    applied - transition.startNanoseconds
                ) / 1_000_000,
                "native_layout_started_duration_ms": Double(
                    layoutStarted - transition.startNanoseconds
                ) / 1_000_000,
                "native_layout_work_duration_ms": Double(
                    applied - layoutStarted
                ) / 1_000_000,
                "layout_duration_ms": Double(completed - applied) / 1_000_000,
            ]
        )
    }

    func beginEditActivation(documentID: String) {
        guard let configuration,
            configuration.metric == .warmEditActivation
                || configuration.metric == .firstEditActivation,
            documentID == configuration.expectedDocument,
            recordedSampleCount < configuration.sampleCount
        else {
            editActivation = nil
            return
        }
        editActivation = (documentID: documentID, startNanoseconds: now())
    }

    func markEditorVisible(documentID: String) {
        guard let configuration,
            documentID == configuration.expectedDocument
        else { return }
        switch configuration.metric {
        case .warmEditActivation, .firstEditActivation:
            guard let activation = editActivation,
                activation.documentID == documentID
            else { return }
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
            let start = configuration.externalStartNanoseconds
        else { return }
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

    /// Publishes the retained native editor handshake after visible layout.
    /// The UI-test driver can read the
    /// sampler acknowledgment, but it deliberately cannot write into the app
    /// container that owns this probe file.
    func markEditorModeReady(documentID: String, mode: MarkdownEditorMode) {
        guard let configuration,
            configuration.metric == .editorRetainedMemory,
            documentID == configuration.expectedDocument,
            recordedSampleCount < configuration.sampleCount
        else { return }
        let expectedMode: MarkdownEditorMode =
            recordedSampleCount.isMultiple(of: 2)
            ? .edit
            : .read
        guard mode == expectedMode else { return }
        let object: [String: Any] = [
            "sample": configuration.firstSample + recordedSampleCount,
            "transition": configuration.firstSample + recordedSampleCount,
            "mode": mode.rawValue,
        ]
        guard append(object, to: configuration.resultURL) else { return }
        recordedSampleCount += 1
    }

    /// Persists the packaged CJK journey's final privacy-safe handshake only
    /// after the driver has restored the exact source and requested this
    /// record. The performance driver owns the isolated destination.
    func recordLargeCJKCorrectness(documentID: String, source: String) {
        guard let configuration,
            configuration.metric == .editorLargeCJKCorrectness,
            documentID == configuration.expectedDocument,
            recordedSampleCount == 0
        else { return }
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
            recordedSampleCount < configuration.sampleCount
        else { return }
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
            completedNanoseconds >= projection
        else { return [:] }
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
            projection >= vaultConfigurationReady
        {
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
            let sourceReady = firstReadSourceReadyNanoseconds,
            let layoutStarted = firstReadNativeLayoutStartedNanoseconds,
            let layoutFinished = firstReadNativeLayoutFinishedNanoseconds,
            documentSelected >= startNanoseconds,
            readTaskStarted >= documentSelected,
            sourceReady >= readTaskStarted,
            layoutStarted >= sourceReady,
            layoutFinished >= layoutStarted,
            completedNanoseconds >= layoutFinished
        else { return [:] }
        return [
            "activation_to_document_selection_duration_ms": milliseconds(
                documentSelected - startNanoseconds
            ),
            "document_selection_to_read_task_start_duration_ms": milliseconds(
                readTaskStarted - documentSelected
            ),
            "read_task_start_to_source_ready_duration_ms": milliseconds(
                sourceReady - readTaskStarted
            ),
            "read_source_ready_to_layout_start_duration_ms": milliseconds(
                layoutStarted - sourceReady
            ),
            "read_native_layout_duration_ms": milliseconds(
                layoutFinished - layoutStarted
            ),
            "read_layout_to_ready_duration_ms": milliseconds(
                completedNanoseconds - layoutFinished
            ),
        ]
    }

    private func append(_ object: [String: Any], to resultURL: URL) -> Bool {
        guard
            let encoded = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys]
            )
        else { return false }
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
        bundleID: String,
        isolatedHomePath: String?
    ) -> URL? {
        guard bundleID == "com.scholium.app" || bundleID == "com.scholium.qa" else {
            return nil
        }
        let candidate = URL(fileURLWithPath: rawPath).standardizedFileURL
        guard candidate.pathExtension == "jsonl",
            candidate.lastPathComponent == (rawPath as NSString).lastPathComponent
        else {
            return nil
        }
        let parent = candidate.deletingLastPathComponent().resolvingSymlinksInPath()
        let isolatedSuffix = "/.build/performance-\(runID)/app-state/raw"
        let isSystemTemporary =
            bundleID == "com.scholium.qa"
            && (parent.path == "/tmp"
                || parent.path.hasPrefix("/tmp/")
                || parent.path == "/private/tmp"
                || parent.path.hasPrefix("/private/tmp/"))
        let isolatedRaw = parent.path.components(separatedBy: isolatedSuffix).first.map {
            $0 + isolatedSuffix
        }
        let isIsolatedBuildOutput =
            bundleID == "com.scholium.qa"
            && parent.path.hasPrefix("/Users/")
            && isolatedRaw.map {
                parent.path == $0 || parent.path.hasPrefix($0 + "/")
            } == true
        let packagedRunRoot = isolatedHomePath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .deletingLastPathComponent()
        }
        let packagedRawRoot = packagedRunRoot?.appendingPathComponent(
            "raw",
            isDirectory: true
        )
        let isPackagedOutput =
            bundleID == "com.scholium.app"
            && packagedRunRoot?.lastPathComponent == runID
            && packagedRunRoot?.deletingLastPathComponent().lastPathComponent
                == "Performance Runs"
            && packagedRawRoot.map {
                parent.path == $0.path || parent.path.hasPrefix($0.path + "/")
            } == true
        guard isSystemTemporary || isIsolatedBuildOutput || isPackagedOutput else {
            return nil
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { return nil }
        return parent.appendingPathComponent(candidate.lastPathComponent, isDirectory: false)
    }

    private static func allowsConfiguration(
        environment: [String: String],
        bundleID: String,
        arguments: [String]
    ) -> Bool {
        bundleID == "com.scholium.qa"
            || ScholiumRuntimeIsolation.allowsPackagedPerformanceIsolation(
                environment: environment,
                arguments: arguments,
                bundleIdentifier: bundleID
            )
    }

    private static func isSafeRunID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 80
            && value.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
            }
    }
}
