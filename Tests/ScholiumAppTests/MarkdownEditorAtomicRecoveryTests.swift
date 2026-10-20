import Foundation
import Testing
import WebKit

@testable import ScholiumApp

#if DEBUG
@Suite("Atomic editor recovery", .serialized)
@MainActor
struct MarkdownEditorAtomicRecoveryTests {
    private typealias Harness = MarkdownEditorWebViewIntegrationTests.EditorHarness

    @Test("Initialization admits a retained generation and every selection together", arguments: [MarkdownEditorMode.source, .livePreview])
    func recoveredInitialization(mode: MarkdownEditorMode) async throws {
        let source = "\u{FEFF}# Cafe\u{301}\r\n\r\n中文 🦉\nTail\r\n"
        let dispatcher = RecoveryDispatcher()
        let harness = Harness(source: source, bridgeDispatcher: dispatcher, initialMode: mode)
        defer { harness.close() }
        try await harness.waitUntilReady()
        try await harness.session.perform(.pastePlain, argument: "new ")
        let edited = try await harness.session.currentText()
        let generation = harness.session.generation
        try #require(generation > 0)
        try await harness.session.captureStateForViewReconstruction()
        let selections = try #require(dispatcher.capturedRanges)
        try #require(selections.count == 2)
        try await harness.reconstructEditorView()
        try await harness.waitUntilReady()

        #expect(harness.session.generation == generation)
        #expect(harness.session.context?.selections == selections)
        #expect(harness.session.presentedMode == mode)
        #expect(harness.session.isDirty)
        #expect(Data(try await harness.session.currentText().utf8) == Data(edited.utf8))
        #expect(dispatcher.recoveredInitializations == 1)
        #expect(dispatcher.returnedHistoryReceipt == true)
        #expect(!dispatcher.returnedHistoryPayload)
        try await undo(in: harness)
        #expect(Data(try await harness.session.currentText().utf8) == Data(source.utf8))
        await harness.closeAndDrain()
    }

    @Test("A damaged retained history recovers exact bytes and reports the lost history")
    func damagedHistory() async throws {
        let source = "\u{FEFF}Cafe\u{301} 中文 🦉\r\nTail\n"
        let dispatcher = RecoveryDispatcher()
        dispatcher.damagesHistory = true
        let harness = Harness(source: source, bridgeDispatcher: dispatcher, initialMode: .source)
        defer { harness.close() }
        try await harness.waitUntilReady()
        try await harness.session.perform(.pastePlain, argument: "new ")
        let edited = try await harness.session.currentText()
        let generation = harness.session.generation
        try await harness.session.captureStateForViewReconstruction()
        try await harness.reconstructEditorView()
        try await harness.waitUntilReady()

        #expect(Data(try await harness.session.currentText().utf8) == Data(edited.utf8))
        #expect(harness.session.generation == generation && harness.session.isDirty)
        #expect(harness.session.context?.undoLabel == nil)
        #expect(dispatcher.returnedHistoryReceipt == false)
        #expect(!dispatcher.returnedHistoryPayload)
        #expect(harness.session.errorMessage?.contains("undo history") == true)
        await harness.closeAndDrain()
    }

    @Test("A source navigation before or during recovery supersedes the captured ranges", arguments: [false, true])
    func navigationDuringRecovery(beforeInitialization: Bool) async throws {
        let source = "\u{FEFF}Cafe\u{301} 中文 🦉\r\nTail\n"
        let dispatcher = RecoveryDispatcher()
        dispatcher.holdsRecoveredInitialization = !beforeInitialization
        let harness = Harness(source: source, bridgeDispatcher: dispatcher, initialMode: .source)
        defer {
            dispatcher.resume()
            harness.close()
        }
        try await harness.waitUntilReady()
        try await harness.session.perform(.pastePlain, argument: "new ")
        let edited = try await harness.session.currentText()
        try await harness.session.captureStateForViewReconstruction()
        try await harness.reconstructEditorView()
        if !beforeInitialization { try await dispatcher.waitUntilSuspended() }
        #expect(!harness.session.isLoaded)
        let target = EditorSourceOffsetMap(source: edited).editorUTF16Length
        harness.revealEditorRange(fromUTF16: target, toUTF16: target)
        dispatcher.resume()
        try await harness.waitUntilReady()
        try await harness.waitUntilSelection(head: target)
        #expect(Data(try await harness.session.currentText().utf8) == Data(edited.utf8))
        #expect(harness.session.isDirty && harness.session.context?.undoLabel != nil)
        try await undo(in: harness)
        #expect(Data(try await harness.session.currentText().utf8) == Data(source.utf8))
        await harness.closeAndDrain()
    }

    @Test("A false initialization receipt cannot advance the checked generation or expose the page", arguments: [false, true])
    func invalidReceipt(changesSource: Bool) async throws {
        let source = "\u{FEFF}Retained cafe\u{301} 中文 🦉\r\n"
        let dispatcher = RecoveryDispatcher()
        dispatcher.falsifiesReceipt = changesSource ? .source : .generation
        let harness = Harness(source: source, bridgeDispatcher: dispatcher, initialMode: .source)
        defer { harness.close() }
        try await harness.waitUntilReady()
        try await harness.session.perform(.pastePlain, argument: "new ")
        let edited = try await harness.session.currentText()
        try await harness.session.captureStateForViewReconstruction()
        try await harness.reconstructEditorView()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while harness.session.errorMessage == nil {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!harness.session.isLoaded)
        #expect(harness.session.generation == 0)
        let unavailable = try await harness.nativePreparationSnapshot()
        #expect(!unavailable.allowsInput && !unavailable.acceptsPointer && unavailable.accessibleChildCount == 0)
        #expect(Data(harness.session.checkedSource.utf8) == Data(edited.utf8))
        #expect(harness.session.testingRecoveryRetentionStats.recoverySourceUTF8Bytes == edited.utf8.count)
        await harness.closeAndDrain()
    }

    private func undo(in harness: Harness) async throws {
        _ = try await harness.callPageJavaScript(
            "document.querySelector('.cm-content').dispatchEvent(new KeyboardEvent('keydown', {key:'z', code:'KeyZ', metaKey:true, bubbles:true, cancelable:true}));")
    }

    /// Real CodeMirror owns the source and history. Controlled transport
    /// fixtures vary the latest capture's ranges/history and a returned receipt.
    private final class RecoveryDispatcher: MarkdownEditorBridgeDispatching {
        enum Falsification { case source, generation }
        let production = WKWebViewMarkdownEditorBridgeDispatcher()
        var damagesHistory = false
        var falsifiesReceipt: Falsification?
        var capturedRanges: [MarkdownEditorSelectionRange]?
        var recoveredInitializations = 0
        var returnedHistoryReceipt: Bool?
        var returnedHistoryPayload = false
        var holdsRecoveredInitialization = false
        private var continuation: CheckedContinuation<Void, Never>?

        func waitUntilSuspended() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while continuation == nil {
                try #require(ContinuousClock.now < deadline)
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        func resume() {
            continuation?.resume()
            continuation = nil
        }

        func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
            let request = try JSONDecoder().decode(MarkdownEditorRequest.self, from: Data(requestJSON.utf8))
            let raw = try await production.dispatch(requestJSON: requestJSON, in: webView)
            guard var result = raw as? [String: Any] else { return raw }
            if case .captureRecovery = request.operation, var recovery = result["recovery"] as? [String: Any] {
                let ranges = [MarkdownEditorSelectionRange(anchor: 1, head: 2), .init(anchor: 4, head: 5)]
                recovery["ranges"] = ranges.map { ["anchor": $0.anchor, "head": $0.head] }
                if damagesHistory { recovery["stateJSON"] = "damaged retained history" }
                capturedRanges = ranges
                result["recovery"] = recovery
            }
            if case .initialize(_, _, _, _, _, .some, _) = request.operation {
                recoveredInitializations += 1
                returnedHistoryReceipt = result["recoveryHistoryPreserved"] as? Bool
                returnedHistoryPayload = result["recovery"] != nil
                if holdsRecoveredInitialization {
                    await withCheckedContinuation { continuation = $0 }
                }
                switch falsifiesReceipt {
                case .source: result["text"] = "different source"
                case .generation: result["resultingGeneration"] = request.knownGeneration
                case nil: break
                }
            }
            return result
        }
    }
}
#endif
