import AppKit
import Foundation
import ScholiumContracts
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Native preview admitted image resources", .serialized)
@MainActor
struct DocumentPreviewResourceTests {
    @Test("Preview messages require bounded unique resource keys")
    func boundedResourceKeys() throws {
        let surface: [String: Any] = [
            "id": 1, "left": 10, "top": 20, "bottom": 30,
            "html": "<p>Preview</p>", "css": "", "imageResourceKeys": ["a%25&b.png"],
        ]
        #expect(DocumentFloatingEvent.decode(["type": "previewSurface", "surface": surface]) != nil)
        var missing = surface
        missing.removeValue(forKey: "imageResourceKeys")
        #expect(DocumentFloatingEvent.decode(["type": "previewSurface", "surface": missing]) == nil)
        for invalid in [
            [""], ["same", "same"], [String(repeating: "x", count: 16_385)],
            (0...8_192).map(String.init),
        ] {
            var value = surface
            value["imageResourceKeys"] = invalid
            #expect(DocumentFloatingEvent.decode(["type": "previewSurface", "surface": value]) == nil)
        }
    }

    @Test("A size failure reaches the existing document feedback owner and cannot dismiss a newer surface")
    func explicitSizeFailure() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let value: [String: Any] = ["type": "previewFailure", "id": 2, "reason": "size"]
        let decoded = try #require(DocumentFloatingEvent.decode(value))
        #expect(DocumentFloatingEvent.decode(["type": "previewFailure", "id": 2, "reason": "unknown"]) == nil)
        let invalidIDs: [Any] = [true, false, 0, -1, 1.5, "2"]
        for id in invalidIDs {
            #expect(DocumentFloatingEvent.decode(["type": "previewFailure", "id": id, "reason": "size"]) == nil)
        }
        var failures = 0
        fixture.controller.onPreviewFailure = { failure in
            if case .size = failure { failures += 1 }
        }
        fixture.controller.present(decoded, in: fixture.owner) { _, _, _ in true }
        #expect(failures == 1)
        fixture.controller.present(
            .preview(.init(id: 3, left: 20, top: 40, bottom: 60, html: "<p>Current</p>", css: "")), in: fixture.owner
        ) { _, _, _ in true }
        try await fixture.waitForShown()
        fixture.controller.present(decoded, in: fixture.owner) { _, _, _ in true }
        #expect(failures == 1 && fixture.controller.isPreviewShown)
    }

    @Test("A large admitted raster decodes without entering floating HTML, and unknown keys stay unavailable")
    func largeAdmittedImage() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let png = try previewNoisePNG()
        let resource = "data:image/png;base64,\(png.base64EncodedString())"
        try #require(resource.utf8.count > 500_000)
        let peer = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNwaDgAAAKEAYEml6crAAAAAElFTkSuQmCC"
        let html = """
            <h2 class="scholium-preview-title">Synthetic image fixture</h2>
            <div class="scholium-preview-body scholium-document">
            <img class="scholium-embedded-image" data-scholium-image-resource="a%25&amp;b.png" alt="Current Note image">
            <img class="scholium-embedded-image" data-scholium-image-resource="missing.png" alt="Unavailable image">
            <img class="scholium-embedded-image peer" src="\(peer)" alt="Peer same filename">
            </div>
            """
        let value = DocumentPreviewSurface(
            id: 1, left: 20, top: 40, bottom: 60, html: html, css: "",
            imageResourceKeys: ["a%25&b.png", "missing.png"])
        #expect(value.html.utf8.count < 2_000)
        fixture.controller.present(.preview(value), in: fixture.owner, imageResources: ["a%25&b.png": resource]) { _, _, _ in true }
        try await fixture.waitForShown()
        let preview = try #require(fixture.controller.previewWebView)
        let actual = try #require(
            try await preview.evaluateJavaScript(
                """
                [document.images[0].complete, document.images[0].naturalWidth,
                 document.images[0].getAttribute('data-scholium-image-resource'),
                 document.querySelector('.peer').getAttribute('src'),
                 document.querySelector('.scholium-media-placeholder').textContent]
                """) as? [Any])
        #expect(actual[0] as? Bool == true)
        #expect(actual[1] as? Int == 400)
        #expect(actual[2] as? String == "a%25&b.png")
        #expect(actual[3] as? String == peer)
        #expect((actual[4] as? String)?.contains("Unavailable image") == true)
        #expect(fixture.window.firstResponder === fixture.originalResponder)
    }

    @Test("Pending same-key resource replacement and dismissal expose only the latest raster")
    func resourceReplacementCancellation() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        func resource(_ width: Int) throws -> String {
            let bitmap = try #require(
                NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: width,
                    bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let pixels = try #require(bitmap.bitmapData)
            for index in 0..<(bitmap.bytesPerRow * bitmap.pixelsHigh) { pixels[index] = UInt8(width * 30) }
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            return "data:image/png;base64,\(png.base64EncodedString())"
        }
        let html = "<img class='scholium-embedded-image' data-scholium-image-resource='same.png' alt='Current raster'>"
        let first = try resource(2)
        let second = try resource(3)
        let latest = try resource(4)
        func present(_ id: Int, _ bytes: String) {
            fixture.controller.present(
                .preview(.init(id: id, left: 20, top: 40, bottom: 60, html: html, css: "", imageResourceKeys: ["same.png"])),
                in: fixture.owner, imageResources: ["same.png": bytes]
            ) { _, _, _ in true }
        }
        present(1, first)
        let renderer = fixture.controller.previewWebView
        present(2, second)
        fixture.controller.dismiss()
        present(3, latest)
        try await fixture.waitForShown()
        let preview = try #require(fixture.controller.previewWebView)
        #expect(preview === renderer)
        #expect(try await preview.evaluateJavaScript("document.images.length") as? Int == 1)
        #expect(try await preview.evaluateJavaScript("document.images[0].naturalWidth") as? Int == 4)
        #expect(try await preview.evaluateJavaScript("document.images[0].getAttribute('src')") as? String == latest)
        #expect(try await preview.evaluateJavaScript("document.querySelector('.scholium-media-placeholder') === null") as? Bool == true)
        fixture.controller.dismiss()
        await Task.yield()
        #expect(!fixture.controller.isPreviewShown && fixture.controller.previewWebView == nil)
    }

    @Test("An open preview follows the originating appearance and semantic color refresh without reloading or scrolling")
    func appearanceLifecycle() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.owner.appearance = NSAppearance(named: .aqua)
        let html =
            "<h2>Preview</h2><div class='scholium-preview-body scholium-document'>"
            + String(repeating: "<p>Synthetic long reading content.</p>", count: 80) + "</div>"
        fixture.controller.present(
            .preview(.init(id: 1, left: 20, top: 40, bottom: 60, html: html, css: "")), in: fixture.owner
        ) { _, _, _ in true }
        try await fixture.waitForShown()
        let preview = try #require(fixture.controller.previewWebView)
        _ = try await preview.evaluateJavaScript("window.scrollTo(0, 160); document.body.dataset.identity = 'retained';")
        let offset = try #require(try await preview.evaluateJavaScript("window.scrollY") as? Double)
        #expect(offset > 0)
        fixture.owner.appearance = NSAppearance(named: .darkAqua)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        var dark = false
        while !dark && ContinuousClock.now < deadline {
            dark = try await preview.evaluateJavaScript("matchMedia('(prefers-color-scheme: dark)').matches") as? Bool == true
            if !dark { try await Task.sleep(for: .milliseconds(20)) }
        }
        #expect(dark)
        #expect(preview.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        #expect(try await preview.evaluateJavaScript("window.scrollY") as? Double == offset)
        #expect(try await preview.evaluateJavaScript("document.body.dataset.identity") as? String == "retained")
        _ = try await preview.evaluateJavaScript("document.getElementById('scholium-native-preview-css').textContent += '/* stale-color-proof */';")
        NotificationCenter.default.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
        let refreshed =
            try await preview.evaluateJavaScript("!document.getElementById('scholium-native-preview-css').textContent.includes('stale-color-proof')") as? Bool
        #expect(refreshed == true)
        #expect(try await preview.evaluateJavaScript("window.scrollY") as? Double == offset)
        #expect(fixture.window.firstResponder === fixture.originalResponder)
        fixture.controller.reset()
        fixture.owner.appearance = NSAppearance(named: .aqua)
        NotificationCenter.default.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
        #expect(!fixture.controller.isPreviewShown && fixture.controller.previewWebView == nil)
    }

    @MainActor
    private final class Fixture {
        let owner: WKWebView
        let window: NSWindow
        let controller = DocumentFloatingSurfaceController()
        let originalResponder: NSResponder?

        init() {
            _ = NSApplication.shared
            owner = WKWebView()
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = DocumentWebViewContainer(webView: owner)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(owner)
            originalResponder = window.firstResponder
        }

        func waitForShown() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(8))
            while !controller.isPreviewShown && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            try #require(controller.isPreviewShown)
        }

        func close() {
            controller.reset()
            owner.stopLoading()
            window.close()
        }
    }
}

@MainActor
fileprivate func previewNoisePNG(width: Int = 400, height: Int = 400) throws -> Data {
    let bitmap = try #require(
        NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let pixels = try #require(bitmap.bitmapData)
    var random: UInt32 = 0x1234_5678
    for index in 0..<(bitmap.bytesPerRow * bitmap.pixelsHigh) {
        random ^= random << 13
        random ^= random >> 17
        random ^= random << 5
        pixels[index] = UInt8(truncatingIfNeeded: random)
    }
    return try #require(bitmap.representation(using: .png, properties: [:]))
}

extension MarkdownEditorWebViewIntegrationTests {
    @Test("Delayed Edit floating projections cannot enter Source or Review", arguments: [MarkdownEditorMode.source, .review])
    func editFloatingProjectionRespectsCurrentMode(mode: MarkdownEditorMode) async throws {
        let source = "\u{FEFF}A source-preserved paragraph.\r\n"
        let harness = EditorHarness(source: source, initialMode: .source, laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()
        if mode == .review {
            let document = NoteDocument(relativePath: harness.documentID, rawContent: source)
            harness.configureReview(
                SafeMarkdownReadWebView(
                    documentID: harness.documentID, document: document,
                    htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
                    presentationCSS: "", userCSS: "", onLinkClick: { _ in }, onOpenExternalURL: { _ in },
                    onSelectionChange: { _ in }, onRenderingFailure: { Issue.record(Comment(rawValue: $0)) }))
            harness.setMode(.review)
            try await harness.waitUntilPresentedMode(.review)
        }
        let owner = try #require(harness.session.webView)
        let session = harness.session
        let generation = session.generation
        // This explicitly delays a valid same-source Edit projection past the
        // mode boundary; it does not assume that normal WebKit delivery does so.
        let payload: [String: Any] = [
            "protocolVersion": markdownEditorProtocolVersion, "sessionID": session.sessionID.uuidString,
            "documentID": harness.documentID, "startingFingerprint": session.startingFingerprint,
            "documentVersion": generation, "type": "floatingSurface",
            "event": [
                "type": "suggestionSurface",
                "surface": [
                    "id": 9_000, "left": 20, "top": 30, "bottom": 50,
                    "items": [["label": "Departed Edit candidate", "detail": "", "disabled": false]], "selected": 0,
                ],
            ],
        ]
        try #require(DocumentFloatingEvent.decode(payload["event"]) != nil)
        _ = try await harness.callPageJavaScript(
            "window.webkit.messageHandlers.scholium.postMessage(payload);", arguments: ["payload": payload])
        _ = try await harness.session.currentText(for: harness.documentID)
        #expect(owner.superview?.subviews.contains { $0 is NSGlassEffectView } == false)
        #expect(!session.floatingSurfaces.isPreviewShown)
        #expect(session.generation == generation)
        #expect(Data(session.checkedSource.utf8) == Data(source.utf8))
        await harness.closeAndDrain()
    }

    @Test("Shared Review floating previews resolve large admitted images and retain source, selection and Undo")
    func sharedReviewLargePreviewResourcesPreserveHistory() async throws {
        let image = try RenderedMarkdownImage(data: previewNoisePNG(), mimeType: "image/png")
        let resource = "data:image/png;base64,\(image.data.base64EncodedString())"
        try #require(resource.utf8.count > 500_000)
        let key = "Attachments/large.png"
        let annotationProse = String(repeating: "Synthetic annotation reading content. ", count: 120)
        let original =
            "\u{FEFF}Opening 图 e\u{0301} paragraph.\r\n\r\nReference[^image].\r\n\r\n"
            + "[[Peer]]{{![Annotation image](\(key))\r\n\r\n\(annotationProse)}}\r\n\r\n"
            + "[^image]: ![Footnote image](\(key))\r\n\r\n"
            + (0..<24).map { "    Synthetic footnote reading paragraph \($0).\r\n\r\n" }.joined()
        let insertion = try #require(original.range(of: "Opening")?.lowerBound.utf16Offset(in: original))
        let harness = EditorHarness(
            source: original, initialMode: .source, initialSourceRange: insertion..<insertion,
            laysOutForPointerTesting: true, imageResourcesQuery: { _ in [key: image] })
        defer { harness.close() }
        try await harness.waitUntilReady()
        try await harness.session.focusAndWait()
        let caret = try #require(EditorSourceOffsetMap(source: original).editorUTF16Offset(forSourceUTF16Offset: insertion))
        try await harness.waitUntilSelection(head: caret)
        try await harness.session.perform(.pastePlain, argument: "Added ")
        let source = (original as NSString).replacingCharacters(in: NSRange(location: insertion, length: 0), with: "Added ")
        try await harness.waitUntilText(source)
        let sourceBytes = Data(source.utf8)
        _ = try await harness.session.acknowledgeCommittedSnapshot(
            expectedText: source, committedText: source, fingerprint: DocumentFingerprint(content: source), documentID: harness.documentID)
        harness.synchronizeLifecycleSourceFromSession()
        let document = NoteDocument(relativePath: harness.documentID, rawContent: source)
        let html = SafeMarkdownRenderer.render(document, embeddedImages: [key: image], imageDelivery: .resourceCatalog).htmlBody
        try #require(!html.contains("base64,") && html.components(separatedBy: "data-scholium-image-resource=").count - 1 == 2)
        harness.configureReview(
            SafeMarkdownReadWebView(
                documentID: harness.documentID, document: document, htmlBody: html,
                presentationCSS: "", userCSS: "", configurationRevision: document.fingerprint.sha256,
                onLinkClick: { _ in }, onOpenExternalURL: { _ in },
                onPreviewFailure: { Issue.record(Comment(rawValue: $0.message)) },
                onSelectionChange: { _ in }, onRenderingFailure: { Issue.record(Comment(rawValue: $0)) }))
        harness.setMode(.review)
        try await harness.waitUntilPresentedMode(.review)
        try await harness.waitUntilNativeInputIsEnabled()
        let owner = try #require(harness.session.webView)
        let editorCoordinator = try #require(owner.navigationDelegate as? MarkdownEditorWebView.Coordinator)
        let readerCoordinator = try #require(editorCoordinator.reviewCoordinator)
        let generation = harness.session.generation
        try #require(generation > 0)
        let selection = try #require(harness.session.context?.selections)
        let undo = try #require(harness.session.context?.undoLabel)
        let redo = harness.session.context?.redoLabel
        #expect(harness.session.deliveredPreviewImageResources(for: [key])[key] == resource)
        let viewport = try #require(
            try await harness.callPageJavaScript(
                "return [document.querySelector('.cm-scroller').scrollLeft, document.querySelector('.cm-scroller').scrollTop];") as? [Double])

        for (selector, expectedAlt) in [
            (".footnote-reference", "Footnote image"), (".scholium-link-annotation-button", "Annotation image"),
        ] {
            _ = try await harness.callPageJavaScript(
                """
                const anchor = document.querySelector(selector);
                if (!anchor) throw new Error('The source-owned preview control is missing.');
                anchor.dispatchEvent(new PointerEvent('pointerover', {bubbles: true}));
                """, arguments: ["selector": selector])
            let deadline = ContinuousClock.now.advanced(by: .seconds(8))
            var currentTargetIsShown = false
            while !currentTargetIsShown && ContinuousClock.now < deadline {
                if readerCoordinator.testingIsPreviewShown,
                    let candidate = readerCoordinator.testingPreviewWebView
                {
                    currentTargetIsShown = try await candidate.evaluateJavaScript("document.images[0]?.alt") as? String == expectedAlt
                }
                if !currentTargetIsShown { try await Task.sleep(for: .milliseconds(20)) }
            }
            if !currentTargetIsShown {
                let page = try? await harness.callPageJavaScript(
                    """
                    const anchor = document.querySelector(selector);
                    const rect = anchor?.getBoundingClientRect();
                    const image = document.querySelector('#scholium-document .footnote-content img');
                    return {selector, anchorPresent: !!anchor, anchorExpanded: anchor?.getAttribute('aria-expanded'),
                      anchorRect: rect ? [rect.left, rect.top, rect.bottom, rect.width, rect.height] : null,
                      readerAPI: typeof window.scholiumDismissPreview,
                      reviewDOM: document.querySelectorAll('.scholium-review-projection').length,
                      imagePresent: !!image, imageSourceLength: image?.getAttribute('src')?.length || 0,
                      imageComplete: image?.complete, imageNaturalWidth: image?.naturalWidth,
                      imageKey: image?.getAttribute('data-scholium-image-resource')};
                    """, arguments: ["selector": selector])
                let readerPreview = readerCoordinator.testingPreviewWebView
                let previewState = try? await readerPreview?.evaluateJavaScript(
                    "({title:document.querySelector('.scholium-preview-title')?.textContent, images:document.images.length, placeholders:document.querySelectorAll('.scholium-media-placeholder').length, firstAlt:document.images[0]?.alt, text:document.body.textContent.slice(0,200)})"
                )
                print(
                    "SHARED_PREVIEW_FAILURE",
                    [
                        "selector": selector, "expected_alt": expectedAlt,
                        "editor_shown": harness.session.floatingSurfaces.isPreviewShown,
                        "editor_preview_present": harness.session.floatingSurfaces.previewWebView != nil,
                        "reader_shown": readerCoordinator.testingIsPreviewShown,
                        "reader_preview_present": readerPreview != nil,
                        "page": page ?? "nil", "reader_preview": previewState as Any,
                    ])
            }
            try #require(currentTargetIsShown)
            let preview = try #require(readerCoordinator.testingPreviewWebView)
            #expect(try await preview.evaluateJavaScript("document.images[0].complete && document.images[0].naturalWidth === 400") as? Bool == true)
            #expect(try await preview.evaluateJavaScript("document.images[0].getAttribute('src')") as? String == resource)
            _ = try await preview.evaluateJavaScript("window.scrollTo(0, 160); document.body.dataset.previewIdentity = 'retained';")
            let offset = try #require(try await preview.evaluateJavaScript("window.scrollY") as? Double)
            #expect(offset > 0)
            // Real DOM focus follows the same target's hover. The source owner
            // must not rebuild/repost it or reset the Native reading viewport.
            _ = try await harness.callPageJavaScript("document.querySelector(selector).focus({preventScroll: true});", arguments: ["selector": selector])
            #expect(readerCoordinator.testingPreviewWebView === preview)
            #expect(try await preview.evaluateJavaScript("document.body.dataset.previewIdentity") as? String == "retained")
            #expect(try await preview.evaluateJavaScript("window.scrollY") as? Double == offset)
            #expect(harness.session.webView === owner)
            #expect(Data(try await harness.session.currentText().utf8) == sourceBytes)
            #expect(harness.session.generation == generation)
            #expect(harness.session.context?.selections == selection)
            #expect(harness.session.context?.undoLabel == undo && harness.session.context?.redoLabel == redo)
            #expect(
                try await harness.callPageJavaScript(
                    "return [document.querySelector('.cm-scroller').scrollLeft, document.querySelector('.cm-scroller').scrollTop];") as? [Double] == viewport)
            _ = try await harness.callPageJavaScript("window.scholiumDismissPreview();")
        }
        // The reader's popover is a separate native window. Hiding its shared
        // editor host must revoke both that window and the retained Web target.
        _ = try await harness.callPageJavaScript(
            "document.querySelector('.footnote-reference').dispatchEvent(new PointerEvent('pointerover', {bubbles:true}));")
        let shownDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !readerCoordinator.testingIsPreviewShown && ContinuousClock.now < shownDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(readerCoordinator.testingIsPreviewShown)
        harness.setSurfaceVisibility(.retained)
        let hiddenDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while readerCoordinator.testingIsPreviewShown && ContinuousClock.now < hiddenDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!readerCoordinator.testingIsPreviewShown)
        harness.setSurfaceVisibility(.active)
        let container = try #require(owner.superview as? DocumentWebViewContainer)
        let activeDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !container.surfaceVisibility.isActive && ContinuousClock.now < activeDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        _ = try await harness.callPageJavaScript(
            "document.querySelector('.footnote-reference').dispatchEvent(new PointerEvent('pointerover', {bubbles:true}));")
        let reopenedDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !readerCoordinator.testingIsPreviewShown && ContinuousClock.now < reopenedDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(readerCoordinator.testingIsPreviewShown)
        #expect(harness.session.webView === owner)
        #expect(harness.session.context?.selections == selection)
        #expect(harness.session.context?.undoLabel == undo && harness.session.context?.redoLabel == redo)
        harness.setMode(.source)
        try await harness.waitUntilPresentedMode(.source)
        #expect(!readerCoordinator.testingIsPreviewShown)
        try await harness.session.focusAndWait()
        for (isRedo, expected) in [(false, original), (true, source)] {
            let handled =
                try await harness.callPageJavaScript(
                    """
                    const event = new KeyboardEvent('keydown', {key: 'z', code: 'KeyZ', keyCode: 90, which: 90,
                      metaKey: true, shiftKey: redo, bubbles: true, cancelable: true});
                    document.querySelector('.cm-content').dispatchEvent(event);
                    return event.defaultPrevented;
                    """, arguments: ["redo": isRedo]) as? Bool
            #expect(handled == true)
            try await harness.waitUntilText(expected)
            #expect(Data(try await harness.session.currentText().utf8) == Data(expected.utf8))
        }
        await harness.closeAndDrain()
    }
}
