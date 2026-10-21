import AppKit
import Foundation
import Testing
import WebKit

@testable import ScholiumApp

extension MarkdownEditorWebViewIntegrationTests {
    @Test("A current native context command edits the real page and retains exact Undo")
    func nativeContextCommandPreservesExactHistory() async throws {
        let source = "\u{FEFF}# Tasks\r\n\r\n- [ ] Synthetic task 中文 e\u{301} 🦉\r\n"
        let harness = EditorHarness(source: source)
        defer { harness.close() }
        try await harness.waitUntilReady()
        let position = (source.replacingOccurrences(of: "\r\n", with: "\n") as NSString).range(of: "Synthetic").location
        harness.revealEditorRange(fromUTF16: position, toUTF16: position)
        try await harness.waitUntilSelection(head: position)
        let webView = try #require(harness.session.webView as? WindowAttachedWebView)
        let menu = webView.makeEditorContextMenu(
            context: try #require(harness.session.context), mode: .livePreview, canPaste: false)
        let item = try #require(menu.item(withTitle: ScholiumL10n.string("Toggle Task")))
        #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
        let edited = source.replacingOccurrences(of: "[ ]", with: "[x]")
        try await harness.waitUntilText(edited, stage: "native context task toggle")
        #expect(Data(harness.session.checkedSource.utf8) == Data(edited.utf8))
        _ = try await harness.callPageJavaScript(
            "document.querySelector('.cm-content').dispatchEvent(new KeyboardEvent('keydown', {key:'z', code:'KeyZ', metaKey:true, bubbles:true, cancelable:true}));"
        )
        try await harness.waitUntilText(source, stage: "native context command Undo")
        #expect(Data(harness.session.checkedSource.utf8) == Data(source.utf8))
        await harness.closeAndDrain()
    }

    @Test("A pre-cancelled editor command never reaches the page")
    func preCancelledCommandDoesNotDispatch() async throws {
        let source = "\u{FEFF}Exact cafe\u{301} 中文 🦉\r\n"
        let dispatcher = LifecycleRequestDispatcher()
        let harness = EditorHarness(source: source, bridgeDispatcher: dispatcher, initialMode: .source)
        defer { harness.close() }
        try await harness.waitUntilReady()

        let command = Task { @MainActor in try await harness.session.perform(.pastePlain, argument: "cancelled ") }
        command.cancel()
        await expectCancellation(command)

        #expect(dispatcher.commands.isEmpty)
        #expect(Data(try await harness.session.currentText().utf8) == Data(source.utf8))
        #expect(!harness.session.isDirty)
        await harness.closeAndDrain()
    }

    @Test("Cancelling a command queued behind a source operation revokes its dispatch")
    func cancelledQueuedCommandDoesNotDispatch() async throws {
        let source = "\u{FEFF}Exact cafe\u{301} 中文 🦉\r\n"
        let dispatcher = LifecycleRequestDispatcher()
        let harness = EditorHarness(source: source, bridgeDispatcher: dispatcher, initialMode: .source)
        defer {
            dispatcher.resume()
            harness.close()
        }
        try await harness.waitUntilReady()
        dispatcher.heldOperation = .command
        let first = Task { @MainActor in try await harness.session.perform(.pastePlain, argument: "first ") }
        defer { first.cancel() }
        try await dispatcher.waitUntilHeld()
        let firstSource = try await harness.session.currentText()
        let queued = Task.immediate { @MainActor in try await harness.session.perform(.pastePlain, argument: "cancelled ") }
        defer { queued.cancel() }
        queued.cancel()
        dispatcher.resume()
        try await first.value
        await expectCancellation(queued)

        #expect(dispatcher.commands == [.pastePlain])
        #expect(Data(try await harness.session.currentText().utf8) == Data(firstSource.utf8))
        await harness.closeAndDrain()
    }

    @Test("Cancellation after dispatch drains the checked result before another source command")
    func cancellationDrainsAdmittedCommand() async throws {
        let source = "\u{FEFF}Exact cafe\u{301} 中文 🦉\r\n"
        let dispatcher = LifecycleRequestDispatcher()
        let harness = EditorHarness(source: source, bridgeDispatcher: dispatcher, initialMode: .source)
        defer {
            dispatcher.resume()
            harness.close()
        }
        try await harness.waitUntilReady()
        dispatcher.heldOperation = .command
        let first = Task { @MainActor in try await harness.session.perform(.pastePlain, argument: "first ") }
        defer { first.cancel() }
        try await dispatcher.waitUntilHeld()
        let firstSource = try await harness.session.currentText()
        first.cancel()
        let next = Task.immediate { @MainActor in try await harness.session.perform(.pastePlain, argument: "next ") }
        defer { next.cancel() }
        #expect(dispatcher.commands == [.pastePlain])
        #expect(!harness.session.canRecycleWebView)
        dispatcher.resume()
        try await first.value
        try await next.value

        #expect(dispatcher.commands == [.pastePlain, .pastePlain])
        #expect(Data(try await harness.session.currentText().utf8) == Data(firstSource.replacingOccurrences(of: "first ", with: "first next ").utf8))
        await harness.closeAndDrain()
    }

    @Test("Cancelling an executed departure capture releases only its own input freeze")
    func cancelledDepartureCaptureResumesInput() async throws {
        let source = "\u{FEFF}Exact cafe\u{301} 中文 🦉\r\n"
        let dispatcher = LifecycleRequestDispatcher()
        let harness = EditorHarness(source: source, bridgeDispatcher: dispatcher, initialMode: .source)
        defer {
            dispatcher.resume()
            harness.close()
        }
        try await harness.waitUntilReady()
        try await harness.session.perform(.pastePlain, argument: "retained ")
        let edited = try await harness.session.currentText()
        dispatcher.heldOperation = .suspend
        let capture = Task { @MainActor in try await harness.session.captureStateForViewReconstruction(suspendForDetachment: true) }
        defer { capture.cancel() }
        try await dispatcher.waitUntilHeld()
        capture.cancel()
        dispatcher.resume()
        await expectCancellation(capture)

        #expect(harness.session.detachmentSuspensionID == nil)
        #expect(Data(try await harness.session.currentText().utf8) == Data(edited.utf8))
        #expect(harness.session.isDirty)
        try await harness.session.perform(.pastePlain, argument: "continued ")
        #expect(try await harness.session.currentText() == edited.replacingOccurrences(of: "retained ", with: "retained continued "))
        #expect(harness.session.context?.undoLabel != nil)
        await harness.closeAndDrain()
    }

    private func expectCancellation(_ task: Task<Void, Error>) async {
        do {
            try await task.value
            Issue.record("The cancelled request completed instead of revoking its pending work.")
        } catch is CancellationError {
        } catch {
            Issue.record("Unexpected cancellation result: \(error)")
        }
    }
}

@MainActor
private final class LifecycleRequestDispatcher: MarkdownEditorBridgeDispatching {
    enum HeldOperation { case command, suspend }
    var heldOperation: HeldOperation?
    private(set) var commands: [MarkdownEditorCommand] = []
    private let production = WKWebViewMarkdownEditorBridgeDispatcher()
    private var continuation: CheckedContinuation<Void, Never>?

    func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
        let request = try JSONDecoder().decode(MarkdownEditorRequest.self, from: Data(requestJSON.utf8))
        if case .command(let command, _) = request.operation { commands.append(command) }
        let result = try await production.dispatch(requestJSON: requestJSON, in: webView)
        let holds: Bool =
            switch (heldOperation, request.operation) {
            case (.command, .command), (.suspend, .suspendForDetachment): true
            default: false
            }
        if holds {
            heldOperation = nil
            await withCheckedContinuation { continuation = $0 }
        }
        return result
    }

    func waitUntilHeld() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while continuation == nil {
            try #require(ContinuousClock.now < deadline, "The controlled dispatch did not reach its reply barrier.")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
