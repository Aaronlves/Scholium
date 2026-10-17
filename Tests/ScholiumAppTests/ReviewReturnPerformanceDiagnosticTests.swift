import AppKit
import Combine
import Foundation
import ScholiumContracts
import Testing
import WebKit

@testable import ScholiumApp

#if DEBUG
    /// Additional observations around the existing exact-source mode matrix.
    /// This reads one generated Note; it configures no workspace or disk writer.
    @MainActor
    @Suite("Warm Review return diagnostics", .serialized)
    struct ReviewReturnPerformanceDiagnosticTests {
        private typealias Shared = DocumentModeSwitchPerformanceDiagnosticTests

        @Test(
            "Observe generated long-prose reader loading during exact mode handoffs",
            .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_REVIEW_RETURN_FIXTURE"] != nil))
        func generatedLongProseReviewReturn() async throws {
            try #require(ProcessInfo.processInfo.environment["SCHOLIUM_MODE_ROUNDTRIP_ONLY"] != "1")
            let repository = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let build = repository.appendingPathComponent(".build", isDirectory: true).resolvingSymlinksInPath()
            let supplied = URL(
                fileURLWithPath: try #require(ProcessInfo.processInfo.environment["SCHOLIUM_REVIEW_RETURN_FIXTURE"])
            )
            .standardizedFileURL
            try #require(try supplied.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true)
            let fixture = supplied.resolvingSymlinksInPath()
            try #require(fixture.path.hasPrefix(build.path + "/"))
            let relativePath = "01-analyses/Stress/Stress Long Prose.md"
            let manifestFile = fixture.appendingPathComponent("stress-manifest.json")
            try #require(try manifestFile.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true)
            let manifest = try #require(
                JSONSerialization.jsonObject(with: Data(contentsOf: manifestFile))
                    as? [String: Any])
            try #require(manifest["schema_version"] as? Int == 1)
            try #require(manifest["synthetic_nonprivate"] as? Bool == true)
            try #require((manifest["scenarios"] as? [String: String])?["long_prose"] == relativePath)
            var sourceFile = fixture
            for component in relativePath.split(separator: "/") {
                sourceFile.appendPathComponent(String(component))
                try #require(try sourceFile.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true)
            }
            let originalBytes = try Data(contentsOf: sourceFile)
            let source = try #require(NoteDocument.decodeUTF8PreservingBOM(originalBytes))
            try #require(Data(source.utf8) == originalBytes)
            let paragraphs = source.split(separator: "\n").filter { $0.hasPrefix("Record ") && $0.contains(", paragraph ") }
            try #require(paragraphs.count > 1)
            let target = String(paragraphs[paragraphs.count / 2])
            let nsSource = source as NSString
            let targetRange = nsSource.range(of: target, options: .literal)
            try #require(targetRange.location != NSNotFound)
            try #require(
                nsSource.range(
                    of: target, options: .literal,
                    range: NSRange(location: NSMaxRange(targetRange), length: nsSource.length - NSMaxRange(targetRange))
                )
                .location == NSNotFound)
            let data = Shared.FixtureData(
                name: "review_return_stress_long_prose", source: source,
                viewportRange: targetRange, viewportText: target, editorViewportTexts: [target])
            let start = ContinuousClock.now
            let harness = try Shared.Harness(data: data, sourceFile: sourceFile)
            let observations = ReaderObservations(harness: harness, start: start)
            observations.record(
                "feature-construction-returned",
                values: [
                    "sourceUTF8Bytes": originalBytes.count,
                    "sourceSHA256": DocumentFingerprint(data: originalBytes).sha256,
                    "scope":
                        "Hidden native feature; exact shared source/selection/scroll/history checks. No workspace configuration, disk save, nonempty Undo seed, focus or visible paint.",
                    "observationScope":
                        "KVO load changes and 10ms container discovery; no navigation delegate replacement. JavaScript navigation timing is queried after native readiness and can slightly affect diagnostic elapsed times.",
                ])
            observations.start()
            do {
                try await harness.run()
                await observations.stop()
                await harness.closeAndDrain()
            } catch {
                await observations.stop()
                await harness.closeAndDrain()
                #expect(try Data(contentsOf: sourceFile) == originalBytes)
                throw error
            }
            #expect(try Data(contentsOf: sourceFile) == originalBytes)
        }

        @MainActor
        private final class ReaderObservations {
            @MainActor
            private final class Reader {
                weak var webView: WKWebView?
                let ordinal: Int
                var observation: NSKeyValueObservation?
                var lastLoading: Bool?

                init(webView: WKWebView, ordinal: Int) {
                    self.webView = webView
                    self.ordinal = ordinal
                }
            }

            private let harness: Shared.Harness
            private let startedAt: ContinuousClock.Instant
            private var readers: [ObjectIdentifier: Reader] = [:]
            private var nextOrdinal = 0
            private var intentOrdinal = 0
            private var cancellables = Set<AnyCancellable>()
            private var polling: Task<Void, Never>?
            private var queries: [UUID: Task<Void, Never>] = [:]

            init(harness: Shared.Harness, start: ContinuousClock.Instant) {
                self.harness = harness
                self.startedAt = start
            }

            func start() {
                harness.controller.$requestedPresentationMode.compactMap { $0 }.sink { [weak self] mode in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.intentOrdinal += 1
                        self.record("controller-intent", values: ["to": mode.rawValue])
                    }
                }.store(in: &cancellables)
                harness.controller.$currentPresentationMode.dropFirst().sink { [weak self] mode in
                    MainActor.assumeIsolated { self?.record("controller-mode", values: ["mode": mode.rawValue]) }
                }.store(in: &cancellables)
                harness.session.$renderedReadReadyFingerprint.removeDuplicates().sink { [weak self] fingerprint in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.record("reader-readiness", values: ["ready": fingerprint == self.harness.note.fingerprint.sha256])
                        if fingerprint == self.harness.note.fingerprint.sha256 {
                            self.discoverReaders()
                            for reader in self.readers.values { self.queryNavigation(reader) }
                        }
                    }
                }.store(in: &cancellables)
                discoverReaders()
                polling = Task { @MainActor [weak self] in
                    while !Task.isCancelled {
                        self?.discoverReaders()
                        do { try await Task.sleep(for: .milliseconds(10)) } catch { return }
                    }
                }
            }

            func stop() async {
                polling?.cancel()
                await polling?.value
                polling = nil
                cancellables.removeAll()
                for reader in readers.values { reader.observation?.invalidate() }
                readers.removeAll()
                let pending = Array(queries.values)
                for task in pending { task.cancel() }
                for task in pending { await task.value }
                queries.removeAll()
            }

            private func discoverReaders() {
                func containers(in view: NSView) -> [DocumentWebViewContainer] {
                    (view as? DocumentWebViewContainer).map { [$0] } ?? view.subviews.flatMap { containers(in: $0) }
                }
                let mounted = harness.window.contentView.map { containers(in: $0) } ?? []
                let webViews = mounted.map(\.webView).filter {
                    $0 !== harness.session.editorSession.webView
                        && ($0.accessibilityIdentifier()?.hasPrefix("scholium.renderedDocument") == true)
                }
                let identities = Set(webViews.map(ObjectIdentifier.init))
                for identity in readers.keys.filter({ !identities.contains($0) }) {
                    guard let reader = readers.removeValue(forKey: identity) else { continue }
                    reader.observation?.invalidate()
                    record("reader-unmounted", values: ["reader": reader.ordinal])
                }
                for webView in webViews where readers[ObjectIdentifier(webView)] == nil {
                    nextOrdinal += 1
                    let reader = Reader(webView: webView, ordinal: nextOrdinal)
                    readers[ObjectIdentifier(webView)] = reader
                    record("reader-discovered", values: ["reader": reader.ordinal, "loading": webView.isLoading])
                    reader.observation = webView.observe(\.isLoading, options: [.initial, .new]) { [weak self, weak reader] _, change in
                        MainActor.assumeIsolated {
                            guard let self, let reader, let loading = change.newValue, reader.lastLoading != loading else { return }
                            reader.lastLoading = loading
                            self.record("reader-loading", values: ["reader": reader.ordinal, "loading": loading])
                        }
                    }
                }
            }

            private func queryNavigation(_ reader: Reader) {
                let queryID = UUID()
                let ordinal = reader.ordinal
                let intent = intentOrdinal
                queries[queryID] = Task { @MainActor [weak self, weak reader] in
                    guard let self, let webView = reader?.webView, webView.window === self.harness.window else { return }
                    defer { self.queries[queryID] = nil }
                    do {
                        var result: Any?
                        try await withScholiumLifecycleDeadline(phase: .bridgeRequest, timeout: .seconds(2)) {
                            result = try await webView.callAsyncJavaScript(
                                """
                                return {
                                  nowMilliseconds: performance.now(), fontStatus: document.fonts.status,
                                  navigation: performance.getEntriesByType('navigation').map(entry => ({
                                    domInteractive: entry.domInteractive,
                                    domContentLoadedEventStart: entry.domContentLoadedEventStart,
                                    domContentLoadedEventEnd: entry.domContentLoadedEventEnd,
                                    domComplete: entry.domComplete,
                                    loadEventStart: entry.loadEventStart, loadEventEnd: entry.loadEventEnd,
                                    duration: entry.duration
                                  }))
                                };
                                """, arguments: [:], in: nil, contentWorld: SafeMarkdownReadWebView.bridgeContentWorld)
                        }
                        guard !Task.isCancelled, webView.window === self.harness.window else { return }
                        self.record(
                            "reader-navigation-after-ready",
                            values: [
                                "reader": ordinal, "observedIntent": intent, "navigationTiming": result ?? NSNull(),
                            ])
                    } catch {
                        if !Task.isCancelled {
                            self.record("reader-navigation-unavailable", values: ["reader": ordinal, "error": String(describing: error)])
                        }
                    }
                }
            }

            func record(_ phase: String, values: [String: Any] = [:]) {
                let duration = startedAt.duration(to: .now).components
                var row = values
                row["metric"] = "review-return-reader-phase"
                row["phase"] = phase
                row["elapsedMilliseconds"] = Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1_000_000_000_000_000
                row["intent"] = intentOrdinal
                do {
                    let json = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
                    try FileHandle.standardOutput.write(contentsOf: json + Data([0x0A]))
                } catch { Issue.record(error) }
            }
        }
    }
#endif
