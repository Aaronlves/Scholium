import Foundation
import Testing
import WebKit

@testable import ScholiumApp

#if DEBUG
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
            let label = ProcessInfo.processInfo.environment["SCHOLIUM_EDITOR_RESTORATION_LABEL"] ?? "unlabeled"
            try #require(
                (1...48).contains(label.utf8.count)
                    && label.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 })
            let prefix = "\u{FEFF}# Synthetic restoration\r\n\r\n"
            let paragraph = "Synthetic manuscript paragraph preserves 中文、🦉 and cafe\u{301}; no private research content.\r\n\r\n"
            let repetitions = (200 * 1_024 - prefix.utf8.count) / paragraph.utf8.count
            let source = prefix + String(repeating: paragraph, count: repetitions)
            try #require((195 * 1_024...205 * 1_024).contains(source.utf8.count))
            let dispatcher = RestorationBridgeRecorder()
            let harness = Harness(source: source, bridgeDispatcher: dispatcher)
            defer { harness.close() }
            do {
                try await harness.waitUntilReady()
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

                    // Full-source and history oracles are outside all timings.
                    #expect(Data(try await harness.session.currentText().utf8) == Data(edited.utf8))
                    #expect(harness.session.generation == generation)
                    #expect(harness.session.context?.selections == selection)
                    #expect(harness.session.context?.undoLabel != nil && harness.session.isDirty)
                    try await applyHistory(in: harness, redo: false)
                    #expect(Data(try await harness.session.currentText().utf8) == Data(source.utf8))
                    try await applyHistory(in: harness, redo: true)
                    #expect(Data(try await harness.session.currentText().utf8) == Data(edited.utf8))
                    #expect(harness.session.context?.selections == selection)
                    #expect(harness.session.context?.undoLabel != nil && harness.session.isDirty)

                    print(
                        "EDITOR_RESTORATION label=\(label) sample=\(sample) source_bytes=\(retained.detachmentSourceUTF8Bytes) "
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
