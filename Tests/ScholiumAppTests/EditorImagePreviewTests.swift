import AppKit
import ScholiumContracts
import Testing

@testable import ScholiumApp

extension MarkdownEditorWebViewIntegrationTests {
    @Test("Edit original-image gestures and native menu preserve source, caret and Undo")
    func editOriginalImagePreview() async throws {
        let destination = "Attachments/A&B%2520.png"
        let source = "\u{FEFF}Before 中文.\r\n\r\n![Figure](Attachments/A&amp;B%2520.png)\r\n\r\nAfter 😀.\r\n"
        let image = try InlineImageFixture.inlinePNG.image()
        let after = try #require(source.range(of: "After")?.lowerBound.utf16Offset(in: source))
        let harness = EditorHarness(
            source: source, initialSourceRange: after..<after,
            imageResourcesQuery: { _ in ["Attachments/A&B%20.png": image] })
        defer { harness.close() }
        try await harness.waitUntilReady()
        let deadline = ContinuousClock().now.advanced(by: .seconds(5))
        while try await harness.callPageJavaScript("return document.querySelector('.cm-live-image img')?.naturalWidth > 0;") as? Bool != true {
            guard ContinuousClock().now < deadline else { throw CocoaError(.fileReadUnknown) }
            try await Task.sleep(for: .milliseconds(20))
        }
        let selection = harness.session.context?.selections
        let generation = harness.session.generation
        let undo = harness.session.context?.undoLabel
        _ = try await harness.callPageJavaScript(
            """
            const image = document.querySelector('.cm-live-image img');
            const rect = image.getBoundingClientRect();
            const options = {bubbles:true, cancelable:true, button:0, metaKey:true,
                clientX:rect.left+rect.width/2, clientY:rect.top+rect.height/2};
            for (const type of ['mousedown','mouseup','click']) image.dispatchEvent(new MouseEvent(type, options));
            """)
        try await waitForImagePreviewCount(harness, 1)
        #expect(harness.previewedImages == [destination])
        #expect(harness.activatedLinks.isEmpty)
        #expect(harness.session.context?.selections == selection)
        #expect(harness.session.generation == generation)
        #expect(harness.session.context?.undoLabel == undo)
        #expect(!harness.session.isDirty)
        #expect(try await harness.session.currentText(for: harness.documentID).utf8.elementsEqual(source.utf8))

        let imageStart = try #require(source.range(of: "![Figure]")?.lowerBound.utf16Offset(in: source))
        let editorOffset = try #require(EditorSourceOffsetMap(source: source).editorUTF16Offset(forSourceUTF16Offset: imageStart + 3))
        harness.session.revealSourceRange(fromUTF16: editorOffset, toUTF16: editorOffset)
        try await harness.waitUntilSelection(head: editorOffset)
        let context = try #require(harness.session.context)
        #expect(context.imageTarget == destination)
        let web = try #require(harness.session.webView as? WindowAttachedWebView)
        let menu = web.makeEditorContextMenu(context: context, mode: .livePreview, canPaste: true)
        let item = try #require(menu.items.first { $0.identifier?.rawValue == "scholium.editor.viewOriginalImage" })
        #expect(item.isEnabled)
        #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
        try await waitForImagePreviewCount(harness, 2)
        #expect(harness.previewedImages == [destination, destination])
        #expect(harness.session.context?.selections == context.selections)

        // A menu retained across another selection cannot act on its old image.
        let afterOffset = try #require(EditorSourceOffsetMap(source: source).editorUTF16Offset(forSourceUTF16Offset: after))
        harness.session.revealSourceRange(fromUTF16: afterOffset, toUTF16: afterOffset)
        try await harness.waitUntilSelection(head: afterOffset)
        #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
        #expect(harness.previewedImages.count == 2)
        #expect(harness.session.generation == generation)
        #expect(harness.session.context?.undoLabel == undo)
        #expect(try await harness.session.currentText(for: harness.documentID).utf8.elementsEqual(source.utf8))
        await harness.closeAndDrain()
    }

    private func waitForImagePreviewCount(_ harness: EditorHarness, _ count: Int) async throws {
        let deadline = ContinuousClock().now.advanced(by: .seconds(3))
        while harness.previewedImages.count < count, ContinuousClock().now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(harness.previewedImages.count == count)
    }
}
