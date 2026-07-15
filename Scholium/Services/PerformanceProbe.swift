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
    private var searchStartNanoseconds: UInt64?
    private var readStartNanoseconds: UInt64?
    private var searchIsArmed = true
    private var readIsArmed = true
    private var recordedSampleCount = 0

    private init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let requestedSampleCount = environment["SCHOLIUM_PERFORMANCE_SAMPLE_COUNT"]
            .flatMap(Int.init) ?? 1
        guard let rawURL = environment["SCHOLIUM_PERFORMANCE_RESULTS_PATH"],
              let rawMetric = environment["SCHOLIUM_PERFORMANCE_METRIC"],
              let metric = Metric(rawValue: rawMetric),
              let rawRunID = environment["SCHOLIUM_PERFORMANCE_RUN_ID"],
              Self.isSafeRunID(rawRunID),
              let bundleID = Bundle.main.bundleIdentifier,
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

    func beginSearch(query: String) {
        guard let configuration, configuration.metric == .indexedSearch else { return }
        guard query == configuration.expectedQuery else {
            searchStartNanoseconds = nil
            searchIsArmed = true
            return
        }
        guard searchIsArmed else { return }
        searchIsArmed = false
        searchStartNanoseconds = DispatchTime.now().uptimeNanoseconds
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
        readStartNanoseconds = DispatchTime.now().uptimeNanoseconds
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

    func markLibraryReady(noteCount: Int) {
        guard let configuration,
              configuration.metric == .warmLibraryLaunch,
              configuration.expectedCount.map({ $0 == noteCount }) ?? true,
              let start = configuration.externalStartNanoseconds else { return }
        record(startNanoseconds: start, observedCount: noteCount)
    }

    private func record(startNanoseconds: UInt64, observedCount: Int?) {
        guard let configuration,
              recordedSampleCount < configuration.sampleCount else { return }
        let end = DispatchTime.now().uptimeNanoseconds
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
        guard let encoded = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        ) else { return }
        do {
            if !FileManager.default.fileExists(atPath: configuration.resultURL.path) {
                guard FileManager.default.createFile(
                    atPath: configuration.resultURL.path,
                    contents: nil
                ) else { return }
            }
            let values = try configuration.resultURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { return }
            let handle = try FileHandle(forWritingTo: configuration.resultURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: encoded + Data([0x0A]))
            try handle.close()
            recordedSampleCount += 1
            searchStartNanoseconds = nil
            readStartNanoseconds = nil
        } catch {
            // Performance evidence is optional and must never affect product
            // behavior or expose a research path through user-facing errors.
            return
        }
    }

    private static func safeResultURL(
        _ rawPath: String,
        runID: String,
        bundleID: String
    ) -> URL? {
        guard bundleID == "com.kbmanager.app" || bundleID == "com.kbmanager.qa" else {
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
        let isIsolatedSandboxTemporary = parent.path.hasPrefix("/Users/")
            && parent.path.hasSuffix(sandboxSuffix)
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
