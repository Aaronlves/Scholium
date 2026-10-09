import AppKit
import ScholiumContracts
import Testing

@testable import ScholiumApp

extension MarkdownEditorWebViewIntegrationTests {
    @Test("Lower-corner image context clicks address the original image instead of the replacement boundary", arguments: [false, true])
    func editorImagePointerContextMenu(linked: Bool) async throws {
        let imageSource = "![Figure](Attachments/figure)"
        let imageLine = linked ? "[\(imageSource)](https://example.test)" : imageSource
        let source = "Before 🦉 é.\n\n\(imageLine)\n\nAfter.\n"
        let imageFrom = try #require(source.range(of: imageSource)?.lowerBound.utf16Offset(in: source))
        let after = try #require(source.range(of: "After.")?.lowerBound.utf16Offset(in: source))
        let image = try InlineImageFixture.inlinePNG.image()
        let harness = EditorHarness(
            source: source, initialSourceRange: after..<after, laysOutForPointerTesting: true,
            imageResourcesQuery: { _ in ["Attachments/figure": image] })
        defer { harness.close() }
        try await harness.waitUntilReady()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while try await harness.callPageJavaScript(
            "return document.querySelector('.cm-live-image img')?.naturalWidth > 0;") as? Bool != true
        {
            guard ContinuousClock.now < deadline else { throw CocoaError(.fileReadUnknown) }
            try await Task.sleep(for: .milliseconds(20))
        }
        let generation = harness.session.generation
        let undo = harness.session.context?.undoLabel
        // Capture the actual event's menu request without entering NSMenu's
        // tracking loop in SwiftPM's async-main host. All other bridge traffic,
        // including the preceding interaction flush, still reaches native code.
        let receipt = try #require(
            try await harness.callPageJavaScript(
                """
                const handler = window.webkit.messageHandlers.scholium;
                const original = handler.postMessage;
                const messages = [];
                let payload = null;
                handler.postMessage = function(message) {
                    messages.push(message.type);
                    if (message.type === 'contextMenuRequested') { payload = message; return; }
                    return original.call(this, message);
                };
                try {
                    const image = document.querySelector('.cm-live-image img');
                    const rect = image.getBoundingClientRect();
                    const event = new MouseEvent('contextmenu', {bubbles:true, cancelable:true, button:2,
                        clientX:rect.left+rect.width*.9, clientY:rect.top+rect.height*.9});
                    image.dispatchEvent(event);
                    return {payload, messages, prevented:event.defaultPrevented};
                } finally { handler.postMessage = original; }
                """) as? [String: Any])
        #expect(receipt["prevented"] as? Bool == true)
        let messages = try #require(receipt["messages"] as? [String])
        let interactionIndex = try #require(messages.firstIndex(of: "interactionChanged"))
        let menuIndex = try #require(messages.firstIndex(of: "contextMenuRequested"))
        #expect(interactionIndex < menuIndex)
        let payload = try #require(receipt["payload"] as? [String: Any])
        let decoded = try #require(EditorBridgeMessageDecoder.decode(payload))
        guard case .contextMenuRequested(let request) = decoded else {
            Issue.record("The image context event did not produce a typed menu request.")
            return
        }
        #expect(request.envelope.sessionID == harness.session.sessionID.uuidString)
        #expect(request.envelope.documentID == harness.documentID)
        #expect(request.envelope.startingFingerprint == harness.session.startingFingerprint)
        #expect(request.clientX.isFinite && request.clientY.isFinite)
        #expect(request.context.selections == [MarkdownEditorSelectionRange(anchor: imageFrom, head: imageFrom)])
        #expect(request.context.imageTarget == "Attachments/figure")
        // The native mirror must already match when the real item's guard runs.
        #expect(harness.session.context?.selections == request.context.selections)
        #expect(harness.session.context?.imageTarget == request.context.imageTarget)
        let webView = try #require(harness.session.webView as? WindowAttachedWebView)
        let menu = webView.makeEditorContextMenu(context: request.context, mode: request.mode, canPaste: false)
        let item = try #require(menu.items.first { $0.identifier?.rawValue == "scholium.editor.viewOriginalImage" })
        #expect(item.isEnabled)
        #expect(item.title == ScholiumL10n.string("View Original Image"))
        #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
        #expect(harness.previewedImages == ["Attachments/figure"])
        #expect(harness.activatedLinks.isEmpty)
        #expect(harness.session.context?.selections == [MarkdownEditorSelectionRange(anchor: imageFrom, head: imageFrom)])
        #expect(harness.session.generation == generation)
        #expect(harness.session.context?.undoLabel == undo)
        #expect(try await harness.session.currentText(for: harness.documentID).utf8.elementsEqual(source.utf8))
        #expect(!harness.session.isDirty)
        await harness.closeAndDrain()
    }
}
