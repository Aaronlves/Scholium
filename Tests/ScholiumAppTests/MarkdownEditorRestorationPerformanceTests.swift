import Foundation
import Testing
import WebKit

@testable import ScholiumApp

#if DEBUG
    /// Test-only controls select identical source bytes across independently
    /// built experiment assets. They do not add a product mode or bridge flag.
    enum EditorAblationDiagnosticConfiguration {
        enum Fixture: String {
            case small, plain, structured

            func source(label: String) -> String {
                let prefix = "\u{FEFF}# Synthetic \(label)\r\n\r\n"
                if self == .small {
                    return prefix + (0..<60).map { "Paragraph \($0): 中文 😀 e\u{301} synthetic source.\r\n\r\n" }.joined()
                }
                let paragraph = self == .plain
                    ? "Synthetic manuscript paragraph preserves 中文、🦉 and cafe\u{301}; no private research content.\r\n\r\n"
                    : "## Synthetic structure\r\n\r\nA **bold** and *emphasized* claim links [[Target]] and cites [@synthetic2026, p. 12].\r\n\r\n> [!note] A disposable callout\r\n> 中文 🦉 cafe\u{301} preserved.\r\n\r\n- First point\r\n- Second point with footnote[^fixture]\r\n\r\n| Claim | Source |\r\n| --- | --- |\r\n| Synthetic | [[Target]] |\r\n\r\n[^fixture]: Synthetic footnote.\r\n\r\n"
                let repetitions = (200 * 1_024 - prefix.utf8.count) / paragraph.utf8.count
                return prefix + String(repeating: paragraph, count: repetitions)
            }
        }

        static func fixture(default fallback: Fixture) throws -> Fixture {
            guard let raw = ProcessInfo.processInfo.environment["SCHOLIUM_EDITOR_ABLATION_FIXTURE"] else { return fallback }
            return try #require(Fixture(rawValue: raw))
        }

        static func mode() throws -> MarkdownEditorMode {
            guard let raw = ProcessInfo.processInfo.environment["SCHOLIUM_EDITOR_ABLATION_MODE"] else { return .livePreview }
            return try #require(MarkdownEditorMode(rawValue: raw))
        }

        static func label() throws -> String {
            let label = ProcessInfo.processInfo.environment["SCHOLIUM_EDITOR_RESTORATION_LABEL"] ?? "unlabeled"
            try #require((1...48).contains(label.utf8.count)
                && label.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 })
            return label
        }

        static var usesAblationFixture: Bool {
            ProcessInfo.processInfo.environment["SCHOLIUM_EDITOR_ABLATION_MODE"] != nil
        }

        @MainActor
        static func addSecondCaret(in session: MarkdownEditorSession) async throws {
            let web = try #require(session.webView)
            let end = EditorSourceOffsetMap(source: session.checkedSource).editorUTF16Length
            _ = try await session.send(.revealSourceRange(fromUTF16: end, toUTF16: end), in: web)
            let prevented = try await web.callAsyncJavaScript(
                """
                const content = document.querySelector('.cm-content');
                const event = new KeyboardEvent('keydown', {key:'ArrowUp', code:'ArrowUp', keyCode:38, which:38,
                    metaKey:true, altKey:true, bubbles:true, cancelable:true});
                content.dispatchEvent(event);
                return event.defaultPrevented;
                """, arguments: [:], in: nil, contentWorld: .page) as? Bool
            try #require(prevented == true)
            let receipt = try await session.send(.querySelection, in: web)
            try #require(receipt.selection?.ranges.count == 2)
        }

        static var expectsDeferredIndex: Bool {
            ProcessInfo.processInfo.environment["SCHOLIUM_EDITOR_EXPECT_DEFERRED_INDEX"] == "1"
        }

        static func emit(_ phases: [MarkdownEditorPerformanceSample], label: String, boundary: String, sample: Int) throws {
            let builds = phases.filter { $0.name == "projection-index" && ($0.observed["documentLength"] ?? 0) > 0 }
            if expectsDeferredIndex {
                let status = try #require(phases.last { $0.name == "ablation-index-status" })
                try #require(builds.isEmpty && status.observed["currentMaterialized"] == 0)
                if boundary == "cold-first-ready" || boundary == "fresh-recovery" {
                    try #require(status.observed["nonemptyBuildAttempts"] == 0)
                }
            }
            print("EDITOR_PROJECTION_BUILDS label=\(label) boundary=\(boundary) sample=\(sample) count=\(builds.count) duration_ms=\(builds.reduce(0) { $0 + $1.durationMilliseconds })")
            for phase in phases {
                let observations = phase.observed.keys.sorted().compactMap { key in
                    phase.observed[key].map { "\(key)=\($0)" }
                }.joined(separator: " ")
                print("EDITOR_RESTORATION_PHASE label=\(label) boundary=\(boundary) sample=\(sample) name=\(phase.name) duration_ms=\(phase.durationMilliseconds) \(observations)")
            }
        }
    }

    /// Run alone with the opt-in environment switch. Reconstruction includes
    /// the existing harness's bounded detach/ready polling and a fresh page;
    /// it measures elapsed lifecycle time, not visible paint or OS key delivery.
    @Suite("Editor restoration diagnostics", .serialized)
    @MainActor
    struct MarkdownEditorRestorationPerformanceTests {
        private typealias Harness = MarkdownEditorWebViewIntegrationTests.EditorHarness

        @Test(
            "Three real WebKit reconstructions preserve exact source, selection and editable Undo history",
            .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_EDITOR_RESTORATION"] == "1"))
        func repeatedRetainedDocumentRestoration() async throws {
            let label = try EditorAblationDiagnosticConfiguration.label()
            let mode = try EditorAblationDiagnosticConfiguration.mode()
            let fixture = try EditorAblationDiagnosticConfiguration.fixture(default: .plain)
            let source = fixture.source(label: "restoration")
            let dispatcher = RestorationBridgeRecorder()
            dispatcher.beginSample()
            let coldStarted = ContinuousClock.now
            let harness = Harness(source: source, bridgeDispatcher: dispatcher, initialMode: mode)
            defer { harness.close() }
            do {
                try await harness.waitUntilReady()
                let coldMilliseconds = Self.milliseconds(coldStarted.duration(to: .now))
                let coldBridges = dispatcher.endSample()
                try await emitPhases(in: harness, label: label, boundary: "cold-first-ready", sample: 0)
                print("EDITOR_COLD_OPEN label=\(label) mode=\(mode.rawValue) fixture=\(fixture.rawValue) source_bytes=\(source.utf8.count) ready_ms=\(coldMilliseconds) initialize_bridge_ms=\(coldBridges.initializeMilliseconds)")
                if EditorAblationDiagnosticConfiguration.expectsDeferredIndex {
                    let demandStarted = ContinuousClock.now
                    let receipt = try await harness.session.send(.queryContext, in: #require(harness.session.webView))
                    let demandMilliseconds = Self.milliseconds(demandStarted.duration(to: .now))
                    try #require(receipt.context != nil)
                    let phases = try await harness.session.queryPerformanceSamples()
                    let status = try #require(phases.last { $0.name == "ablation-index-status" })
                    try #require((status.observed["nonemptyBuildAttempts"] ?? 0) > 0)
                    print("EDITOR_SEMANTIC_DEMAND label=\(label) elapsed_ms=\(demandMilliseconds) index_ms=\(phases.filter { $0.name == "projection-index" }.reduce(0) { $0 + $1.durationMilliseconds })")
                }
                let editorEnd = EditorSourceOffsetMap(source: source).editorUTF16Length
                _ = try await harness.session.send(
                    .revealSourceRange(fromUTF16: editorEnd, toUTF16: editorEnd),
                    in: try #require(harness.session.webView))
                let insertion = "Retained edit e\u{301} 中文 🦉."
                // Forward the real typed editing command into CodeMirror so
                // its actual source/history fields own this Undo transaction.
                try await harness.session.perform(.pastePlain, argument: insertion)
                let edited = source + insertion
                try #require(Data(try await harness.session.currentText().utf8) == Data(edited.utf8))
                if EditorAblationDiagnosticConfiguration.usesAblationFixture {
                    try await EditorAblationDiagnosticConfiguration.addSecondCaret(in: harness.session)
                }
                let selection = try #require(harness.session.context?.selections)
                try #require(harness.session.context?.undoLabel != nil)
                try #require(harness.session.generation > 0 && harness.session.isDirty)

                for sample in 0..<3 {
                    let generation = harness.session.generation
                    dispatcher.beginSample()
                    let captureStarted = ContinuousClock.now
                    try await harness.session.captureStateForViewReconstruction(suspendForDetachment: true)
                    let captureMilliseconds = Self.milliseconds(captureStarted.duration(to: .now))
                    // Logical payload sizes are read after capture timing and
                    // require neither another bridge query nor retained copies.
                    let retained = harness.session.testingRecoveryRetentionStats
                    try #require(retained.detachmentSourceUTF8Bytes == edited.utf8.count)
                    try #require(retained.detachmentHistoryUTF8Bytes > 0)
                    let reconstructionStarted = ContinuousClock.now
                    try await harness.reconstructEditorView()
                    try await harness.waitUntilReady()
                    let reconstructionMilliseconds = Self.milliseconds(reconstructionStarted.duration(to: .now))
                    let bridges = dispatcher.endSample()

                    // Query only after the lifecycle timing ends. The bounded
                    // ring contains numeric phase costs, never document text.
                    try await emitPhases(in: harness, label: label, boundary: "fresh-recovery", sample: sample)

                    // Full-source and history oracles are outside all timings.
                    #expect(Data(try await harness.session.currentText().utf8) == Data(edited.utf8))
                    #expect(harness.session.generation == generation)
                    #expect(harness.session.context?.selections == selection)
                    #expect(harness.session.context?.undoLabel != nil && harness.session.isDirty)
                    try await applyHistory(in: harness, redo: false)
                    #expect(Data(try await harness.session.currentText().utf8) == Data(source.utf8))
                    try await applyHistory(in: harness, redo: true)
                    if EditorAblationDiagnosticConfiguration.usesAblationFixture {
                        try await EditorAblationDiagnosticConfiguration.addSecondCaret(in: harness.session)
                    }
                    #expect(Data(try await harness.session.currentText().utf8) == Data(edited.utf8))
                    #expect(harness.session.context?.selections == selection)
                    #expect(harness.session.context?.undoLabel != nil && harness.session.isDirty)

                    print(
                        "EDITOR_RESTORATION label=\(label) mode=\(mode.rawValue) fixture=\(fixture.rawValue) sample=\(sample) source_bytes=\(retained.detachmentSourceUTF8Bytes) "
                            + "history_bytes=\(retained.detachmentHistoryUTF8Bytes) capture_ms=\(captureMilliseconds) "
                            + "reconstruct_ready_ms=\(reconstructionMilliseconds) "
                            + "capture_bridge_count=\(bridges.captureCount) capture_bridge_ms=\(bridges.captureMilliseconds) "
                            + "initialize_count=\(bridges.initializeCount) initialize_bridge_ms=\(bridges.initializeMilliseconds) "
                            + "restore_recovery_count=\(bridges.restoreCount) restore_recovery_bridge_ms=\(bridges.restoreMilliseconds) "
                            + "announce_count=\(bridges.announceCount) announce_bridge_ms=\(bridges.announceMilliseconds)")
                }
                await harness.closeAndDrain()
            } catch {
                dispatcher.endSample()
                await harness.closeAndDrain()
                throw error
            }
        }

        @Test(
            "Measure initialization recovery within an already loaded real WebKit page",
            .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_EDITOR_SAME_PAGE"] == "1"))
        func samePageRecoveryInitialization() async throws {
            let label = try EditorAblationDiagnosticConfiguration.label()
            let mode = try EditorAblationDiagnosticConfiguration.mode()
            let fixture = try EditorAblationDiagnosticConfiguration.fixture(default: .plain)
            let source = fixture.source(label: "restoration")
            let dispatcher = RestorationBridgeRecorder()
            let harness = Harness(source: source, bridgeDispatcher: dispatcher, initialMode: mode)
            defer { harness.close() }
            do {
                try await harness.waitUntilReady()
                let editorEnd = EditorSourceOffsetMap(source: source).editorUTF16Length
                _ = try await harness.session.send(
                    .revealSourceRange(fromUTF16: editorEnd, toUTF16: editorEnd), in: #require(harness.session.webView))
                let insertion = "Retained edit e\u{301} 中文 🦉."
                try await harness.session.perform(.pastePlain, argument: insertion)
                let edited = source + insertion
                if EditorAblationDiagnosticConfiguration.usesAblationFixture {
                    try await EditorAblationDiagnosticConfiguration.addSecondCaret(in: harness.session)
                }
                let selection = try #require(harness.session.context?.selections)
                let web = try #require(harness.session.webView)
                let transport = harness.session.sessionID
                for sample in 0..<3 {
                    // Preserve the production full history proof. This boundary
                    // excludes capture and view transfer; it is initialization
                    // within one page, never a full application note switch.
                    try await harness.session.captureStateForViewReconstruction()
                    dispatcher.beginSample()
                    let started = ContinuousClock.now
                    harness.session.loadDocument(edited, documentID: harness.documentID, mode: mode)
                    try await harness.waitUntilReady()
                    let elapsed = Self.milliseconds(started.duration(to: .now))
                    let bridges = dispatcher.endSample()
                    try await emitPhases(in: harness, label: label, boundary: "same-page-recovery", sample: sample)
                    #expect(harness.session.webView === web && harness.session.sessionID == transport)
                    #expect(try await harness.session.currentText().utf8.elementsEqual(edited.utf8))
                    #expect(harness.session.context?.selections == selection)
                    #expect(harness.session.isDirty && harness.session.context?.undoLabel != nil)
                    try await applyHistory(in: harness, redo: false)
                    #expect(try await harness.session.currentText().utf8.elementsEqual(source.utf8))
                    try await applyHistory(in: harness, redo: true)
                    if EditorAblationDiagnosticConfiguration.usesAblationFixture {
                        try await EditorAblationDiagnosticConfiguration.addSecondCaret(in: harness.session)
                    }
                    #expect(try await harness.session.currentText().utf8.elementsEqual(edited.utf8))
                    #expect(harness.session.context?.selections == selection)
                    print("EDITOR_SAME_PAGE label=\(label) mode=\(mode.rawValue) fixture=\(fixture.rawValue) sample=\(sample) source_bytes=\(edited.utf8.count) ready_ms=\(elapsed) initialize_bridge_ms=\(bridges.initializeMilliseconds)")
                }
                await harness.closeAndDrain()
            } catch {
                dispatcher.endSample()
                await harness.closeAndDrain()
                throw error
            }
        }

        private func emitPhases(in harness: Harness, label: String, boundary: String, sample: Int) async throws {
            try EditorAblationDiagnosticConfiguration.emit(
                try await harness.session.queryPerformanceSamples(), label: label, boundary: boundary, sample: sample)
        }

        private func applyHistory(in harness: Harness, redo: Bool) async throws {
            let prevented = try await harness.callPageJavaScript(
                """
                const content = document.querySelector('.cm-content');
                const event = new KeyboardEvent('keydown', {
                    key: redo ? 'Z' : 'z', code: 'KeyZ', keyCode: 90, which: 90,
                    metaKey: true, shiftKey: redo, bubbles: true, cancelable: true
                });
                content.dispatchEvent(event);
                return event.defaultPrevented;
                """, arguments: ["redo": redo]) as? Bool
            try #require(prevented == true)
        }

        private static func milliseconds(_ duration: Duration) -> Double {
            let components = duration.components
            return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
        }

        private struct BridgeSample {
            var captureCount = 0
            var captureMilliseconds = 0.0
            var initializeCount = 0
            var initializeMilliseconds = 0.0
            var restoreCount = 0
            var restoreMilliseconds = 0.0
            var announceCount = 0
            var announceMilliseconds = 0.0

            mutating func record(_ operation: String, milliseconds: Double) {
                switch operation {
                case "captureRecovery", "suspendForDetachment":
                    captureCount += 1
                    captureMilliseconds += milliseconds
                case "initialize":
                    initializeCount += 1
                    initializeMilliseconds += milliseconds
                case "restoreRecovery":
                    restoreCount += 1
                    restoreMilliseconds += milliseconds
                case "announceStatus":
                    announceCount += 1
                    announceMilliseconds += milliseconds
                default:
                    break
                }
            }
        }

        /// Bounded per-sample counters wrap the production dispatcher without
        /// changing any request, result, source owner or scheduling policy.
        @MainActor
        private final class RestorationBridgeRecorder: MarkdownEditorBridgeDispatching {
            private struct RequestHeader: Decodable {
                struct Operation: Decodable { let type: String }
                let operation: Operation
            }

            private let production = WKWebViewMarkdownEditorBridgeDispatcher()
            private var sample: BridgeSample?

            func beginSample() { sample = BridgeSample() }

            @discardableResult
            func endSample() -> BridgeSample {
                let completed = sample ?? BridgeSample()
                sample = nil
                return completed
            }

            func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
                guard sample != nil else {
                    return try await production.dispatch(requestJSON: requestJSON, in: webView)
                }
                // Decode only the discriminator, before the measured await.
                let operation = try JSONDecoder().decode(RequestHeader.self, from: Data(requestJSON.utf8)).operation.type
                let started = ContinuousClock.now
                defer { sample?.record(operation, milliseconds: Self.elapsedMilliseconds(since: started)) }
                return try await production.dispatch(requestJSON: requestJSON, in: webView)
            }

            private static func elapsedMilliseconds(since started: ContinuousClock.Instant) -> Double {
                let components = started.duration(to: .now).components
                return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
            }
        }
    }
#endif
