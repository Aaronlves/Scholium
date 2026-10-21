import AppKit
import Foundation
import ScholiumContracts
import Testing
import WebKit

@testable import ScholiumApp

extension ExternalMarkdownWindowLifecycleTests {
    @Test("The external shared Review preserves native selection, Find and read-only authority")
    func unifiedExternalReviewSelectionAndFind() async throws {
        let source = "\u{FEFF}---\r\nunknown: 'keep' # exact\r\n---\r\nPlain e\u{301} 🦉 sentence.\r\n\r\nAnother Plain paragraph.\r\n"
        try await withUnifiedExternalWindow(source: source, expectedText: "Plain") { host, model, webView in
            let editor = model.editorSession
            let review = try #require(
                try await webView.callAsyncJavaScript(
                    """
                    const main = document.querySelector('main#scholium-document');
                    return {mainCount: document.querySelectorAll('main#scholium-document').length,
                      projectionCount: document.querySelectorAll('.scholium-review-projection').length,
                      editable: document.querySelector('.cm-content').isContentEditable,
                      text: main.textContent};
                    """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any])
            #expect(review["mainCount"] as? Int == 1)
            #expect(review["projectionCount"] as? Int == 1)
            #expect(review["editable"] as? Bool == false)
            await #expect(throws: MarkdownEditorSession.SessionError.self) { try await editor.perform(.bold) }
            #expect(Data(try await editor.currentText().utf8) == Data(source.utf8))

            _ = try await webView.callAsyncJavaScript(
                """
                const paragraph = [...document.querySelectorAll('main#scholium-document p')]
                  .find(p => p.textContent.startsWith('Plain'));
                const range = document.createRange(); range.setStart(paragraph.firstChild, 0); range.setEnd(paragraph.firstChild, 5);
                const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
                document.dispatchEvent(new Event('selectionchange'));
                """, arguments: [:], in: nil, contentWorld: .page)
            try await host.waitUntil("native Review selection becomes the external Find query") {
                model.performFind(.useSelection)
                return model.documentFind.query == "Plain"
            }
            try await host.waitUntil("embedded Review Find completes") {
                !model.documentFind.hasPendingRequest && model.documentFind.result.total == 2
            }
            #expect(model.documentFind.errorMessage == nil)
            #expect(model.documentFind.result.current == 1)

            // First editing entry consumes the source-verified native selection,
            // even though Review has already initialized the CodeMirror state.
            try await host.selectModeWhenAvailable(.source)
            try await host.waitForEditor(containing: "Plain")
            let sourceRange = (source as NSString).range(of: "Plain")
            let offsetMap = EditorSourceOffsetMap(source: source)
            let from = try #require(offsetMap.editorUTF16Offset(forSourceUTF16Offset: sourceRange.location))
            let to = try #require(offsetMap.editorUTF16Offset(forSourceUTF16Offset: sourceRange.location + sourceRange.length))
            try await host.waitUntil("first editing selection uses exact Markdown offsets") {
                editor.context?.selections == [.init(anchor: from, head: to)]
            }
            #expect(editor.webView === webView)
            #expect(model.editorSession === editor)
            model.documentFind.dismiss()
            try await host.waitUntil("Find clearing before a retained editing selection") { !model.documentFind.hasPendingRequest }
            let retained = (source as NSString).range(of: "Another Plain paragraph.")
            let retainedFrom = try #require(offsetMap.editorUTF16Offset(forSourceUTF16Offset: retained.location))
            let retainedTo = try #require(offsetMap.editorUTF16Offset(forSourceUTF16Offset: retained.location + retained.length))
            editor.revealSourceRange(fromUTF16: retained.location, toUTF16: retained.location + retained.length)
            try await host.waitUntil("the existing editing selection is established") {
                editor.context?.selections == [.init(anchor: retainedFrom, head: retainedTo)]
            }
            try await host.selectModeWhenAvailable(.read)
            try await host.waitForReadText("Another Plain paragraph.")
            model.acceptReadSelection(
                .init(
                    startLine: 5, endLine: 5, excerpt: "Plain", utf16LowerBound: sourceRange.location,
                    utf16UpperBound: sourceRange.location + sourceRange.length),
                documentID: model.documentID, fingerprint: try #require(model.snapshot).fingerprint)
            try await host.selectModeWhenAvailable(.livePreview)
            try await host.waitForEditor(containing: "Another Plain paragraph.")
            #expect(editor.context?.selections == [.init(anchor: retainedFrom, head: retainedTo)])
            #expect(editor.webView === webView)
            #expect(!model.isDirty)
            #expect(try Data(contentsOf: model.originalURL) == Data(source.utf8))
        }
    }

    @Test("The external shared host retains complete Undo and Redo through saved Review and viewport handoffs")
    func unifiedExternalReviewHistoryAndViewport() async throws {
        let source =
            "\u{FEFF}# External history\r\n\r\n"
            + (0..<100).map { "Paragraph \($0). Exact **formatted** 中文 e\u{301} 🦉 writing.\r\n\r\n" }.joined()
        try await withUnifiedExternalWindow(source: source, expectedText: "Paragraph 0.") { host, model, webView in
            let editor = model.editorSession
            try await host.selectModeWhenAvailable(.source)
            try await host.waitForEditor(containing: "Paragraph 0.")
            try await editor.perform(.pastePlain, argument: "First ")
            let first = try await editor.currentText()
            try await editor.perform(.pastePlain, argument: "Second ")
            let second = try await editor.currentText()
            try await externalHistoryKey(in: webView, redo: false)
            try await host.waitUntil("Undo before the external Review save") { try await editor.currentText() == first }
            try await host.selectModeWhenAvailable(.read)
            try await host.waitForReadText("Paragraph 0.")
            await model.waitForModeTransition()
            #expect(try Data(contentsOf: model.originalURL) == Data(first.utf8))
            #expect(!model.isDirty)
            #expect(editor.webView === webView)

            _ = try await editor.send(.setScrollFraction(0.55), in: webView)
            try await host.waitUntil("external Review observes its nonzero viewport") {
                (model.readScrollPosition.anchor?.sourceUTF16Offset ?? 0) > 0
            }
            // A delayed native observation cannot turn into a second restore.
            model.observeScrollFraction(
                0, on: .read, documentID: model.documentID,
                fingerprint: try #require(model.snapshot).fingerprint.sha256)
            model.observeScrollAnchor(
                .init(
                    sourceFingerprint: try #require(model.snapshot).fingerprint.sha256,
                    sourceUTF16Offset: 0, blockUTF16LowerBound: 0, blockUTF16UpperBound: 0,
                    relativeBlockPosition: 0, fallbackFraction: 0), on: .read, documentID: model.documentID,
                fingerprint: try #require(model.snapshot).fingerprint.sha256)
            try await host.selectModeWhenAvailable(.livePreview)
            try await host.waitForEditor(containing: "Paragraph")
            try await host.selectModeWhenAvailable(.read)
            try await host.waitForReadText("Paragraph 0.")
            await model.waitForModeTransition()
            let before = try #require(
                try await webView.callAsyncJavaScript(
                    "return document.querySelector('.cm-scroller').scrollTop;",
                    arguments: [:], in: nil, contentWorld: .page) as? Double)
            try await Task.sleep(for: .milliseconds(180))
            let after = try #require(
                try await webView.callAsyncJavaScript(
                    "return document.querySelector('.cm-scroller').scrollTop;",
                    arguments: [:], in: nil, contentWorld: .page) as? Double)
            #expect(before > 0)
            #expect(abs(before - after) <= 1)

            try await host.selectModeWhenAvailable(.source)
            try await host.waitForEditor(containing: "Paragraph")
            try await externalHistoryKey(in: webView, redo: true)
            try await host.waitUntil("Redo branch survives the saved Review handoffs") { try await editor.currentText() == second }
            try await externalHistoryKey(in: webView, redo: false)
            try await host.waitUntil("Undo returns to the committed intermediate source") { try await editor.currentText() == first }
            try await externalHistoryKey(in: webView, redo: false)
            try await host.waitUntil("Undo reaches the exact original external Markdown") { try await editor.currentText() == source }
            #expect(editor.webView === webView)
            #expect(model.editorSession === editor)
            #expect(try Data(contentsOf: model.originalURL) == Data(first.utf8))
        }
    }

    @Test("Failed external Review delivery or acknowledgement recovers to exact writable Source", arguments: [false, true])
    func unifiedExternalReviewFailureRecoversToSource(losesAppliedModeAcknowledgement: Bool) async throws {
        let source = "\u{FEFF}# Exact recovery\r\n\r\nKeep **authored** 中文 e\u{301} 🦉 source.\r\n"
        try await withUnifiedExternalWindow(source: source, expectedText: "Keep authored") { host, model, webView in
            let editor = model.editorSession
            try await host.selectModeWhenAvailable(.source)
            try await host.waitForEditor(containing: "Keep **authored**")
            _ = try await webView.callAsyncJavaScript(
                """
                window.__externalReviewOriginalDispatch = window.scholiumEditor.dispatch;
                window.__externalInvalidReviewDeliveries = 0;
                window.__externalAnnouncementPending = false;
                window.scholiumEditor.dispatch = async function(request) {
                  if (request.operation.type === 'announceStatus') {
                    window.__externalAnnouncementPending = true;
                    await new Promise(resolve => setTimeout(resolve, 250));
                    window.__externalAnnouncementPending = false;
                  }
                  if (!losesAppliedModeAcknowledgement && request.operation.type === 'setPresentation' && request.operation.value?.reviewProjection) {
                    request.operation.value.reviewProjection.htmlBody = '<p>Invalid committed shell</p>';
                    window.__externalInvalidReviewDeliveries++;
                  }
                  if (losesAppliedModeAcknowledgement && request.operation.type === 'setMode' && request.operation.mode === 'review') {
                    await window.__externalReviewOriginalDispatch.call(this, request);
                    window.__externalInvalidReviewDeliveries++;
                    throw new Error('Synthetic lost mode acknowledgement');
                  }
                  return await window.__externalReviewOriginalDispatch.call(this, request);
                };
                """, arguments: ["losesAppliedModeAcknowledgement": losesAppliedModeAcknowledgement], in: nil, contentWorld: .page)
            model.setDocumentTextScale(1.1)
            try await host.selectModeWhenAvailable(.read)
            try await host.waitUntil("invalid external Review exposes its Source recovery") {
                guard model.mode == .read, editor.errorMessage != nil, model.canSelectMode(.source) else { return false }
                return try await webView.callAsyncJavaScript(
                    "return window.__externalAnnouncementPending;", arguments: [:], in: nil, contentWorld: .page) as? Bool == true
            }
            let failures =
                try await webView.callAsyncJavaScript(
                    "window.scholiumEditor.dispatch = window.__externalReviewOriginalDispatch; return window.__externalInvalidReviewDeliveries;",
                    arguments: [:], in: nil, contentWorld: .page) as? Int
            #expect((failures ?? 0) > 0)
            try await host.selectModeWhenAvailable(.source)
            editor.retryUnavailablePresentation()
            try await host.waitUntil("Source recovery clears its mode error and restores focus admission") {
                editor.errorMessage == nil
            }
            try await host.waitForEditor(containing: "Keep **authored**")
            #expect(editor.webView === webView)
            #expect(Data(try await editor.currentText().utf8) == Data(source.utf8))
            let editable =
                try await webView.callAsyncJavaScript(
                    "return document.querySelector('.cm-content').isContentEditable;",
                    arguments: [:], in: nil, contentWorld: .page) as? Bool
            #expect(editable == true)
            #expect(!model.isDirty)
            #expect(try Data(contentsOf: model.originalURL) == Data(source.utf8))
        }
    }

    private func externalHistoryKey(in webView: WKWebView, redo: Bool) async throws {
        let handled =
            try await webView.callAsyncJavaScript(
                """
                const event = new KeyboardEvent('keydown', {key: 'z', code: 'KeyZ', keyCode: 90, which: 90,
                  metaKey: true, shiftKey: redo, bubbles: true, cancelable: true});
                document.querySelector('.cm-content').dispatchEvent(event);
                return event.defaultPrevented;
                """, arguments: ["redo": redo], in: nil, contentWorld: .page) as? Bool
        #expect(handled == true)
    }

    private func withUnifiedExternalWindow(
        source: String, expectedText: String,
        operation: @MainActor (OffscreenExternalWindow, ExternalMarkdownWindowModel, WKWebView) async throws -> Void
    ) async throws {
        try await withFile { url, _ in
            try Data(source.utf8).write(to: url)
            let host = OffscreenExternalWindow(url: url)
            do {
                try await host.waitForReadText(expectedText)
                let model = try #require(host.model)
                let webView = try #require(model.editorSession.webView)
                try await operation(host, model, webView)
                await host.closeAndDrain()
            } catch {
                await host.closeAndDrain()
                throw error
            }
        }
    }
}

extension MarkdownEditorWebViewIntegrationTests {
    @Test("Cold shared Review defers its first editing selection and retains later editing selections")
    func coldReviewSelectionWaitsForWritableMode() async throws {
        let source = "\u{FEFF}# First entry\r\n\r\nPlain 中文 e\u{301} 🦉 passage.\r\n\r\nRetained editing passage.\r\n"
        let harness = EditorHarness(source: source, initialMode: .review, ordersWindowFront: false)
        defer { harness.close() }
        let document = NoteDocument(relativePath: harness.documentID, rawContent: source)
        harness.configureReview(
            SafeMarkdownReadWebView(
                documentID: harness.documentID, documentTitle: "First entry", document: document,
                htmlBody: SafeMarkdownRenderer.render(document).htmlBody, presentationCSS: "", userCSS: "",
                configurationRevision: document.fingerprint.sha256, onLinkClick: { _ in }, onOpenExternalURL: { _ in },
                onSelectionChange: { _ in }, onRenderingFailure: { Issue.record(Comment(rawValue: $0)) }))
        try await harness.waitUntilReady()
        try await harness.waitUntilPresentedMode(.review)
        let editor = harness.session
        let webView = try #require(editor.webView)
        let initialSelection = editor.context?.selections
        let first = (source as NSString).range(of: "Plain 中文 e\u{301} 🦉 passage.")
        let map = EditorSourceOffsetMap(source: source)
        let firstFrom = try #require(map.editorUTF16Offset(forSourceUTF16Offset: first.location))
        let firstTo = try #require(map.editorUTF16Offset(forSourceUTF16Offset: first.location + first.length))
        let superseded = (source as NSString).range(of: "First entry")
        editor.prepareReadSelection(superseded.location..<(superseded.location + superseded.length))
        _ = try await editor.send(.queryContext, in: webView)
        #expect(editor.context?.selections == initialSelection)
        // An editing request cancelled while Review is still presented must
        // not leave an older passage ahead of a later first-entry selection.
        editor.setMode(.review)
        editor.prepareReadSelection(first.location..<(first.location + first.length))
        harness.setMode(.livePreview)
        try await harness.waitUntilPresentedMode(.livePreview)
        try await harness.waitUntilSelection(anchor: firstFrom, head: firstTo)

        let retained = (source as NSString).range(of: "Retained editing passage.")
        let retainedFrom = try #require(map.editorUTF16Offset(forSourceUTF16Offset: retained.location))
        let retainedTo = try #require(map.editorUTF16Offset(forSourceUTF16Offset: retained.location + retained.length))
        editor.revealSourceRange(fromUTF16: retained.location, toUTF16: retained.location + retained.length)
        try await harness.waitUntilSelection(anchor: retainedFrom, head: retainedTo)
        harness.setMode(.review)
        try await harness.waitUntilPresentedMode(.review)
        editor.prepareReadSelection(first.location..<(first.location + first.length))
        harness.setMode(.source)
        try await harness.waitUntilPresentedMode(.source)
        try await harness.waitUntilSelection(anchor: retainedFrom, head: retainedTo)
        #expect(editor.webView === webView)
        #expect(!editor.isDirty)
        #expect(Data(try await editor.currentText().utf8) == Data(source.utf8))
        await harness.closeAndDrain()
    }
}
