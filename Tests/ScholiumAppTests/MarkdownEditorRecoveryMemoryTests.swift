import AppKit
import ScholiumContracts
import Testing
import WebKit

@testable import ScholiumApp

#if DEBUG
    @MainActor
    @Suite("Markdown editor recovery retention", .serialized)
    struct MarkdownEditorRecoveryMemoryTests {
        private typealias Harness = MarkdownEditorWebViewIntegrationTests.EditorHarness

        @Test("Actual recovery capture retains exact source and Undo across reconstruction")
        func capturedHistoryAfterReconstructionAndInput() async throws {
            let paragraph = "Synthetic memory paragraph e\u{301} 中文 🧭.\r\n\r\n"
            let source = "\u{FEFF}# Synthetic recovery fixture\r\n\r\n" + String(repeating: paragraph, count: 4_096)
            let harness = Harness(source: source, initialMode: .source, ordersWindowFront: false)
            defer { harness.close() }
            try await harness.waitUntilReady()
            let end = source.replacingOccurrences(of: "\r\n", with: "\n").utf16.count
            harness.revealEditorRange(fromUTF16: end, toUTF16: end)
            try await harness.waitUntilSelection(head: end)
            try await harness.session.perform(.pastePlain, argument: "seed")
            let capturedSource = try await harness.session.currentText(for: harness.documentID)
            #expect(Data(capturedSource.utf8) == Data((source + "seed").utf8))
            let capturedSelection = harness.session.context?.selections
            try await harness.session.captureStateForViewReconstruction()
            let captured = harness.session.testingRecoveryRetentionStats
            #expect(captured.recoveryGeneration == captured.currentGeneration)
            #expect(captured.recoverySourceUTF8Bytes == capturedSource.utf8.count)
            #expect(captured.recoveryHistoryUTF8Bytes > capturedSource.utf8.count)
            record("captured", captured)

            try await harness.reconstructEditorView()
            try await harness.waitUntilReady()
            #expect(Data(try await harness.session.currentText(for: harness.documentID).utf8) == Data(capturedSource.utf8))
            #expect(harness.session.context?.selections == capturedSelection)
            #expect(harness.session.context?.undoLabel != nil)
            let restored = harness.session.testingRecoveryRetentionStats
            #expect(restored.recoveryHistoryUTF8Bytes == captured.recoveryHistoryUTF8Bytes)
            record("restored", restored)

            try await harness.session.perform(.pastePlain, argument: "!")
            #expect(Data(try await harness.session.currentText(for: harness.documentID).utf8) == Data((capturedSource + "!").utf8))
            let advanced = harness.session.testingRecoveryRetentionStats
            record("advanced", advanced)
            #expect(advanced.currentGeneration > restored.currentGeneration)
            expectReleased(advanced)
            #expect(harness.session.isDirty)
            _ = try await harness.callPageJavaScript(
                "document.querySelector('.cm-content').dispatchEvent(new KeyboardEvent('keydown', {key: 'z', code: 'KeyZ', metaKey: true, bubbles: true, cancelable: true}));"
            )
            #expect(Data(try await harness.session.currentText(for: harness.documentID).utf8) == Data(capturedSource.utf8))
            _ = try await harness.callPageJavaScript(
                "document.querySelector('.cm-content').dispatchEvent(new KeyboardEvent('keydown', {key: 'z', code: 'KeyZ', metaKey: true, bubbles: true, cancelable: true}));"
            )
            #expect(Data(try await harness.session.currentText(for: harness.documentID).utf8) == Data(source.utf8))
            let beforeTermination = try await harness.session.currentText(for: harness.documentID)
            let selectionBeforeTermination = try #require(harness.session.context?.selections)
            let dirtyBeforeTermination = harness.session.isDirty
            expectReleased(harness.session.testingRecoveryRetentionStats)
            #expect(dirtyBeforeTermination)
            #expect(harness.session.testingSimulateWebContentProcessTermination())
            try await harness.waitUntilReady()
            #expect(Data(try await harness.session.currentText(for: harness.documentID).utf8) == Data(beforeTermination.utf8))
            #expect(harness.session.context?.selections == selectionBeforeTermination)
            #expect(harness.session.isDirty == dirtyBeforeTermination)
            await harness.closeAndDrain()
        }

        @Test("Validated deltas and full snapshots release older captures", arguments: [false, true])
        func sourceAdvanceReleasesCapture(fullSnapshot: Bool) async throws {
            let source = "\u{FEFF}A synthetic e\u{301} 中文 🧭 paragraph.\r\n"
            let dispatcher = SnapshotDispatcher()
            let harness = Harness(
                source: source, bridgeDispatcher: dispatcher,
                initialMode: .source, ordersWindowFront: false)
            defer { harness.close() }
            try await harness.waitUntilReady()
            try await harness.session.captureStateForViewReconstruction()
            let captured = harness.session.testingRecoveryRetentionStats
            #expect(captured.recoveryHistoryUTF8Bytes > 0)
            let generation = harness.session.generation
            let end = source.replacingOccurrences(of: "\r\n", with: "\n").utf16.count
            let insertion = EditorBridgeChange(from: end, to: end, insert: "!", exactInsert: "!")
            #expect(
                !harness.session.acceptEditorChanges(
                    [insertion], baseGeneration: generation + 1, resultingGeneration: generation + 2))
            #expect(harness.session.testingRecoveryRetentionStats.recoveryHistoryUTF8Bytes == captured.recoveryHistoryUTF8Bytes)
            if fullSnapshot {
                // Isolate the native full-response admission path. Capture above
                // uses real CodeMirror; only this later response is controlled.
                dispatcher.nextSnapshotSource = source + "!"
                _ = try await harness.session.send(.queryText, in: try #require(harness.session.webView))
            } else {
                #expect(
                    harness.session.acceptEditorChanges(
                        [insertion], baseGeneration: generation, resultingGeneration: generation + 1))
            }
            #expect(harness.session.generation == generation + 1)
            #expect(Data(harness.session.checkedSource.utf8) == Data((source + "!").utf8))
            #expect(harness.session.isDirty)
            expectReleased(harness.session.testingRecoveryRetentionStats)
            await harness.closeAndDrain()
        }

        private func expectReleased(_ stats: MarkdownEditorSession.TestingRecoveryRetentionStats) {
            #expect(stats.recoveryGeneration == nil)
            #expect(stats.recoverySourceUTF8Bytes == 0)
            #expect(stats.recoveryHistoryUTF8Bytes == 0)
            #expect(stats.detachmentSourceUTF8Bytes == 0)
            #expect(stats.detachmentHistoryUTF8Bytes == 0)
        }

        @MainActor
        private final class SnapshotDispatcher: MarkdownEditorBridgeDispatching {
            private let production = WKWebViewMarkdownEditorBridgeDispatcher()
            var nextSnapshotSource: String?

            func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
                let request = try JSONDecoder().decode(MarkdownEditorRequest.self, from: Data(requestJSON.utf8))
                let result = try await production.dispatch(requestJSON: requestJSON, in: webView)
                guard case .queryText = request.operation,
                    let source = nextSnapshotSource,
                    var response = result as? [String: Any]
                else { return result }
                nextSnapshotSource = nil
                response["text"] = source
                response["resultingGeneration"] = request.knownGeneration + 1
                response["interactionRevision"] = (response["interactionRevision"] as? Int ?? 0) + 1
                return response
            }
        }

        private func record(_ stage: String, _ stats: MarkdownEditorSession.TestingRecoveryRetentionStats) {
            print(
                "Recovery retention \(stage): current_generation=\(stats.currentGeneration) recovery_generation=\(stats.recoveryGeneration.map(String.init) ?? "none") "
                    + "recovery_source_utf8_bytes=\(stats.recoverySourceUTF8Bytes) recovery_history_utf8_bytes=\(stats.recoveryHistoryUTF8Bytes) "
                    + "detachment_source_utf8_bytes=\(stats.detachmentSourceUTF8Bytes) detachment_history_utf8_bytes=\(stats.detachmentHistoryUTF8Bytes)")
        }
    }
#endif
