import AppKit
import ScholiumContracts
import Testing
import WebKit

@testable import ScholiumApp

extension MarkdownEditorWebViewIntegrationTests {
    @Test("Images preserve proportion, fill block width within the height cap, and retain inline size", arguments: InlineImageFixture.allCases)
    func inlineImageGeometry(fixture: InlineImageFixture) async throws {
        let image = try fixture.image()
        let destination =
            switch fixture {
            case .entityDestinationPNG, .numericDestinationPNG: "Attachments/a&b.png"
            case .encodedReservedDestinationPNG: "Attachments/a#b?c.png"
            default: "Attachments/figure"
            }
        let imageLine =
            switch fixture {
            case .inlinePNG: "Text before ![fixture](Attachments/figure) text after."
            case .referencePNG: "![fixture][figure]\n\n[figure]: Attachments/figure \"Reference title\""
            case .entityDestinationPNG: "![fixture](Attachments/a&amp;b.png)"
            case .numericDestinationPNG: "![fixture](Attachments/a&#38;b.png)"
            case .encodedReservedDestinationPNG: "![fixture](Attachments/a%23b%3Fc.png)"
            case .nestedAltPNG: "![fixture![](Attachments/figure)](Attachments/figure)"
            case .linkedPNG: "[![fixture](Attachments/figure)](https://example.test)"
            default: "![fixture](Attachments/figure)"
            }
        let source = "Before fixture.\n\n" + imageLine + "\n\nAfter fixture.\n"
        let after = try #require(source.range(of: "After fixture.")?.lowerBound.utf16Offset(in: source))
        let editor = EditorHarness(
            source: source,
            initialSourceRange: after..<after,
            initialWindowSize: NSSize(width: 720, height: 820),
            imageResourcesQuery: { _ in [destination: image] }
        )
        defer { editor.close() }
        try await editor.waitUntilReady()
        let wide = try await waitForInlineImage(editor, naturalWidth: fixture.width)
        expectProportionalImage(wide, fixture: fixture)
        if fixture == .nestedAltPNG {
            #expect(try await editor.callPageJavaScript("return document.querySelectorAll('.cm-live-image img').length;") as? Int == 1)
        }
        editor.resize(width: 430, height: 820)
        let narrow = try await waitForInlineImage(editor, naturalWidth: fixture.width, narrowerThan: wide["readingWidth"])
        expectProportionalImage(narrow, fixture: fixture)
        if fixture == .nestedAltPNG {
            let imageStart = try #require(source.range(of: "![fixture")?.lowerBound.utf16Offset(in: source))
            editor.session.revealSourceRange(fromUTF16: imageStart, toUTF16: imageStart)
            try await editor.waitUntilSelection(head: imageStart)
            #expect(try await editor.callPageJavaScript("return document.querySelectorAll('.cm-live-image').length;") as? Int == 0)
            #expect(
                try await editor.callPageJavaScript(
                    "return document.querySelector('.cm-content').textContent.includes(imageLine);", arguments: ["imageLine": imageLine]) as? Bool == true)
        }
        #expect(try await editor.session.currentText(for: editor.documentID) == source)
        #expect(!editor.session.isDirty)
        await editor.closeAndDrain()

        let document = NoteDocument(relativePath: "Images.md", rawContent: source)
        let rendered = SafeMarkdownRenderer.render(document, embeddedImages: [destination: image])
        let review = ReadHarness(
            source: source, htmlBody: rendered.htmlBody,
            fingerprint: document.fingerprint.sha256,
            initialAnchor: nil, initialScrollFraction: 0
        )
        defer { review.close() }
        try await review.waitUntilReady()
        let reviewWide = try await waitForReviewImage(review, naturalWidth: fixture.width)
        expectProportionalImage(reviewWide, fixture: fixture)
        review.resize(width: 430, height: 420)
        let reviewNarrow = try await waitForReviewImage(review, naturalWidth: fixture.width, narrowerThan: reviewWide["readingWidth"])
        expectProportionalImage(reviewNarrow, fixture: fixture)
        await review.closeAndDrain()
    }

    @Test("Initial images arriving after presentation convergence remain visible when loading completes")
    func initialImageCatalogAfterConvergence() async throws {
        let image = try InlineImageFixture.landscapePNG.image()
        let source = "Before fixture.\n\n![fixture](Attachments/figure)\n\nAfter fixture.\n"
        let after = try #require(source.range(of: "After fixture.")?.lowerBound.utf16Offset(in: source))
        let gate = InlineImageQueryGate()
        let barrier = InlineImageStartupScrollBarrier()
        let harness = EditorHarness(
            source: source, bridgeDispatcher: barrier,
            initialSourceRange: after..<after, imageResourcesQuery: gate.query)
        defer {
            gate.releaseAll()
            barrier.resume()
            harness.close()
        }
        do {
            try await barrier.waitUntilSuspended()
            #expect(!harness.session.isLoaded)
            let selection = harness.session.context?.selections
            let generation = harness.session.generation
            let undoLabel = harness.session.context?.undoLabel
            // Resolve the admitted catalog through its existing synchronous
            // owner after convergence, while initial scroll restoration waits.
            harness.session.setImageResources(
                ["Attachments/figure": image], documentID: harness.documentID, generation: generation)
            #expect(barrier.nonemptyCatalogGenerations.isEmpty)
            barrier.resume()
            try await harness.waitUntilReady()
            _ = try await waitForInlineImage(harness, naturalWidth: InlineImageFixture.landscapePNG.width)
            #expect(barrier.nonemptyCatalogGenerations == [generation])
            #expect(try await harness.session.currentText() == source)
            #expect(harness.session.generation == generation)
            #expect(harness.session.context?.selections == selection)
            #expect(harness.session.context?.undoLabel == undoLabel)
            #expect(!harness.session.isDirty)
            await harness.closeAndDrain()
        } catch {
            barrier.resume()
            gate.releaseAll()
            await harness.closeAndDrain()
            throw error
        }
    }

    @Test("Image refresh remeasures the nearby caret and preserves exact source, selection, modes and Undo")
    func inlineImageRefreshPreservesEditorState() async throws {
        let landscape = try InlineImageFixture.landscapePNG.image()
        let portrait = try InlineImageFixture.portraitJPEG.image()
        let source = "\u{FEFF}Before 中文 👩🏽‍🔬.\r\n\r\n![fixture](Attachments/figure)\r\n\r\nAfter fixture 中文 😀.\r\n"
        let after = try #require(source.range(of: "After fixture")?.lowerBound.utf16Offset(in: source))
        let sourceCaret = after + "After".utf16.count
        let editorCaret = try #require(EditorSourceOffsetMap(source: source).editorUTF16Offset(forSourceUTF16Offset: sourceCaret))
        let harness = EditorHarness(
            source: source, initialSourceRange: sourceCaret..<sourceCaret,
            imageResourcesQuery: { _ in ["Attachments/figure": landscape] }
        )
        defer { harness.close() }
        try await harness.waitUntilReady()
        try await harness.session.focusAndWait()
        try await harness.waitUntilSelection(head: editorCaret)
        _ = try await waitForInlineImage(harness, naturalWidth: InlineImageFixture.landscapePNG.width)
        let selection = harness.session.context?.selections
        let generation = harness.session.generation
        let undoLabel = harness.session.context?.undoLabel

        harness.configureImageResources({ _ in ["Attachments/figure": portrait] }, contextKey: "portrait")
        _ = try await waitForInlineImage(harness, naturalWidth: InlineImageFixture.portraitJPEG.width)
        // This ordinary measured query flushes CodeMirror's pending layout;
        // the test does not request or repair image measurements itself.
        _ = try await harness.session.currentScrollAnchor()
        let caret = try #require(
            try await harness.callPageJavaScript(
                """
                const line = [...document.querySelectorAll('.cm-line')]
                  .find(candidate => candidate.textContent.includes('After fixture'));
                const cursor = document.querySelector('.cm-cursor-primary');
                const scroller = document.querySelector('.cm-scroller');
                if (!line || !cursor || !scroller) return null;
                const walker = document.createTreeWalker(line, NodeFilter.SHOW_TEXT);
                let node;
                while ((node = walker.nextNode())) {
                  const start = node.textContent.indexOf('After');
                  if (start < 0) continue;
                  const range = document.createRange();
                  range.setStart(node, start + 4); range.setEnd(node, start + 5);
                  const glyph = range.getBoundingClientRect();
                  const surface = scroller.getBoundingClientRect();
                  const left = parseFloat(cursor.style.left) + surface.left - scroller.scrollLeft;
                  const top = parseFloat(cursor.style.top) + surface.top - scroller.scrollTop;
                  const height = parseFloat(cursor.style.height);
                  return {horizontal: Math.abs(left - glyph.right),
                    vertical: Math.abs(top + height / 2 - (glyph.top + glyph.bottom) / 2)};
                }
                return null;
                """) as? [String: Double]
        )
        #expect(try #require(caret["horizontal"]) < 4, "Caret after image refresh: \(caret)")
        #expect(try #require(caret["vertical"]) < 4, "Caret after image refresh: \(caret)")
        #expect(harness.session.context?.selections == selection)
        #expect(harness.session.generation == generation)
        #expect(harness.session.context?.undoLabel == undoLabel)
        #expect(Data(try await harness.session.currentText().utf8) == Data(source.utf8))
        #expect(!harness.session.isDirty)

        _ = try await harness.callPageJavaScript("document.execCommand('insertText', false, insertion);", arguments: ["insertion": " revision"])
        let changed = (source as NSString).replacingCharacters(in: NSRange(location: sourceCaret, length: 0), with: " revision")
        #expect(Data(try await harness.session.currentText().utf8) == Data(changed.utf8))
        let editedSelection = harness.session.context?.selections
        let editedGeneration = harness.session.generation
        let editedUndo = try #require(harness.session.context?.undoLabel)
        // A stale resource result is unable to replace the current catalog.
        harness.session.setImageResources(["Attachments/figure": landscape], documentID: harness.documentID, generation: generation)
        _ = try await harness.session.currentText()
        _ = try await waitForInlineImage(harness, naturalWidth: InlineImageFixture.portraitJPEG.width)
        #expect(harness.session.generation == editedGeneration)
        #expect(harness.session.context?.selections == editedSelection)
        #expect(harness.session.context?.undoLabel == editedUndo)

        harness.session.setMode(.source)
        try await harness.waitUntilPresentedMode(.source)
        #expect(try await harness.callPageJavaScript("return document.querySelectorAll('.cm-live-image').length;") as? Int == 0)
        #expect(harness.session.context?.selections == editedSelection)
        #expect(harness.session.context?.undoLabel == editedUndo)
        try await inlineImageHistoryKey(harness, redo: false)
        #expect(Data(try await harness.session.currentText().utf8) == Data(source.utf8))
        try await inlineImageHistoryKey(harness, redo: true)
        #expect(Data(try await harness.session.currentText().utf8) == Data(changed.utf8))
        harness.session.setMode(.livePreview)
        try await harness.waitUntilPresentedMode(.livePreview)
        _ = try await waitForInlineImage(harness, naturalWidth: InlineImageFixture.portraitJPEG.width)
        await harness.closeAndDrain()
    }

    @Test("Image syntax remains editable and resources cannot authorize remote or missing destinations")
    func inlineImageSourceAndDeniedFallback() async throws {
        let image = try InlineImageFixture.landscapePNG.image()
        let denied = ["https://example.invalid/figure.png", "file:///private/figure.png", "Attachments/figure?raw=1", "Attachments/figure#cut", "Missing.png"]
        let source =
            "Before fixture.\n\n![fixture](Attachments/figure)\n\n"
            + denied.enumerated().map { "![denied\($0.offset)](\($0.element))" }.joined(separator: "\n\n")
            + "\n\nAfter fixture.\n"
        let resources = Dictionary(uniqueKeysWithValues: (["Attachments/figure"] + Array(denied.dropLast())).map { ($0, image) })
        let harness = EditorHarness(source: source, imageResourcesQuery: { _ in resources })
        defer { harness.close() }
        try await harness.waitUntilReady()
        _ = try await waitForInlineImage(harness, naturalWidth: InlineImageFixture.landscapePNG.width)
        let admitted = try #require(
            try await harness.callPageJavaScript(
                "return [...document.querySelectorAll('.cm-live-image img')].map(image => ({alt: image.alt, local: image.src.startsWith('data:image/')}));")
                as? [[String: Any]]
        )
        #expect(admitted.count == 1)
        #expect(admitted.first?["alt"] as? String == "fixture")
        #expect(admitted.first?["local"] as? Bool == true)

        let imageFrom = try #require(source.range(of: "![fixture]")?.lowerBound.utf16Offset(in: source))
        harness.session.revealSourceRange(fromUTF16: imageFrom, toUTF16: imageFrom)
        try await harness.waitUntilSelection(head: imageFrom)
        try await waitForNoInlineImages(harness)
        #expect(
            try await harness.callPageJavaScript("return document.querySelector('.cm-content').textContent.includes('![fixture](Attachments/figure)');")
                as? Bool == true)
        #expect(try await harness.session.currentText() == source)
        #expect(!harness.session.isDirty)
        await harness.closeAndDrain()

        let document = NoteDocument(relativePath: "Denied.md", rawContent: source)
        let rendered = SafeMarkdownRenderer.render(document, embeddedImages: resources)
        let review = ReadHarness(
            source: source, htmlBody: rendered.htmlBody, fingerprint: document.fingerprint.sha256,
            initialAnchor: nil, initialScrollFraction: 0
        )
        defer { review.close() }
        try await review.waitUntilReady()
        _ = try await waitForReviewImage(review, naturalWidth: InlineImageFixture.landscapePNG.width)
        let fallback = try #require(
            try await review.callBridgeJavaScript(
                """
                return {images: document.querySelectorAll('img.scholium-embedded-image').length,
                  placeholders: [...document.querySelectorAll('.scholium-embed, .scholium-media-placeholder')]
                    .map(span => ({text: span.textContent, height: span.getBoundingClientRect().height,
                      safeDestination: !span.hasAttribute('href') || span.getAttribute('href').startsWith('scholium-note:')}))};
                """) as? [String: Any]
        )
        #expect(fallback["images"] as? Int == 1)
        let placeholders = try #require(fallback["placeholders"] as? [[String: Any]])
        #expect(placeholders.count == denied.count)
        #expect(
            placeholders.allSatisfy {
                !($0["text"] as? String ?? "").isEmpty
                    && ($0["height"] as? Double ?? 0) > 0
                    && $0["safeDestination"] as? Bool == true
            })
        await review.closeAndDrain()
    }

    @Test("A document switch clears admitted images and rejects an earlier asynchronous resource reply")
    func inlineImageCatalogCannotCrossDocumentSwitch() async throws {
        let landscape = try InlineImageFixture.landscapePNG.image()
        let portrait = try InlineImageFixture.portraitJPEG.image()
        let first = "First fixture.\n\n![fixture](Attachments/figure)\n\nTail fixture.\n"
        let second = "Second fixture.\n\n![fixture](Attachments/figure)\n\nTail fixture.\n"
        let gate = InlineImageQueryGate()
        let harness = EditorHarness(source: first, usesSessionDocumentIdentity: true, imageResourcesQuery: gate.query)
        defer {
            gate.releaseAll()
            harness.close()
        }
        try await harness.waitUntilReady()
        try await gate.waitForRequests(1)
        #expect(gate.sources[0] == first)
        gate.resolve(0, with: ["Attachments/figure": landscape])
        _ = try await waitForInlineImage(harness, naturalWidth: InlineImageFixture.landscapePNG.width)

        harness.configureImageResources(gate.query, contextKey: "second-query")
        try await gate.waitForRequests(2)
        let originalID = harness.session.documentID
        harness.session.loadDocument(second, documentID: "SecondImages.md", mode: .livePreview)
        harness.synchronizeLifecycleSourceFromSession()
        try await harness.waitUntilLoaded(documentID: "SecondImages.md")
        try await gate.waitForRequests(3)
        #expect(gate.sources[2] == second)
        try await waitForNoInlineImages(harness)
        gate.resolve(2, with: ["Attachments/figure": portrait])
        _ = try await waitForInlineImage(harness, naturalWidth: InlineImageFixture.portraitJPEG.width)
        gate.resolve(1, with: ["Attachments/figure": landscape])
        try await gate.waitForCompletion(1)
        harness.session.setImageResources(["Attachments/figure": landscape], documentID: originalID, generation: harness.session.generation)
        // A bridge round trip follows the late reply before its observable check.
        #expect(try await harness.session.currentText(for: "SecondImages.md") == second)
        _ = try await waitForInlineImage(harness, naturalWidth: InlineImageFixture.portraitJPEG.width)
        #expect(!harness.session.isDirty)
        await harness.closeAndDrain()
    }

    @Test("Identical image resources still deliver after an intervening edit skips their first presentation")
    func inlineImageCatalogDeliversAfterPresentationGenerationRace() async throws {
        let image = try InlineImageFixture.landscapePNG.image()
        let source = "Before fixture.\n\n![fixture](Attachments/figure)\n\nAfter fixture.\n"
        let gate = InlineImageQueryGate()
        let dispatcher = InlineImagePresentationBarrier()
        let harness = EditorHarness(
            source: source, bridgeDispatcher: dispatcher,
            initialSourceRange: 6..<6, imageResourcesQuery: gate.query
        )
        defer {
            gate.releaseAll()
            dispatcher.resume()
            harness.close()
        }
        try await harness.waitUntilReady()
        try await harness.session.focusAndWait()
        try await harness.waitUntilSelection(head: 6)
        try await gate.waitForRequests(1)
        let originalGeneration = harness.session.generation

        dispatcher.arm()
        gate.resolve(0, with: ["Attachments/figure": image])
        try await dispatcher.waitUntilSuspended()
        // Page input continues while the serial native request queue awaits a
        // title acknowledgement. Query the checked native mirror rather than
        // sending another queued bridge operation through this barrier.
        _ = try await harness.callPageJavaScript("document.execCommand('insertText', false, 'revised ');")
        let changed = (source as NSString).replacingCharacters(in: NSRange(location: 6, length: 0), with: "revised ")
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while harness.session.generation == originalGeneration || harness.session.checkedSource != changed {
            if ContinuousClock.now >= deadline {
                Issue.record("Page input did not advance the checked source while presentation was suspended.")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let editedGeneration = harness.session.generation
        try await gate.waitForRequests(2)
        #expect(gate.sources[1] == changed)

        dispatcher.resume()
        try await dispatcher.waitForPresentationToReturn()
        #expect(try await harness.session.currentText() == changed)
        try await waitForNoInlineImages(harness)
        #expect(dispatcher.nonemptyCatalogGenerations.isEmpty)
        let selection = harness.session.context?.selections
        let undoLabel = harness.session.context?.undoLabel

        // The byte-identical catalog now belongs to the current generation.
        // Its first convergence skipped delivery, so equality alone cannot
        // establish that WebKit ever received it.
        gate.resolve(1, with: ["Attachments/figure": image])
        _ = try await waitForInlineImage(harness, naturalWidth: InlineImageFixture.landscapePNG.width)
        #expect(dispatcher.nonemptyCatalogGenerations == [editedGeneration])
        #expect(try await harness.session.currentText() == changed)
        #expect(harness.session.generation == editedGeneration)
        #expect(harness.session.context?.selections == selection)
        #expect(harness.session.context?.undoLabel == undoLabel)
        #expect(harness.session.isDirty)
        await harness.closeAndDrain()
    }

    @Test("Standalone image whitespace exposes exact source and Shift-click retains the original selection anchor")
    func inlineImageWhitespaceAndShiftClick() async throws {
        let image = try InlineImageFixture.inlinePNG.image()
        let imageSyntax = "![fixture](Attachments/figure)"
        let imageLine = "  " + imageSyntax + " \t "
        let source = "Before fixture.\n\n" + imageLine + "\n\nAfter fixture.\n"
        let imageFrom = try #require(source.range(of: imageSyntax)?.lowerBound.utf16Offset(in: source))
        let imageTo = imageFrom + imageSyntax.utf16.count
        let after = try #require(source.range(of: "After fixture.")?.lowerBound.utf16Offset(in: source))
        let harness = EditorHarness(
            source: source, initialSourceRange: 6..<6,
            imageResourcesQuery: { _ in ["Attachments/figure": image] }
        )
        defer { harness.close() }
        try await harness.waitUntilReady()
        try await harness.session.focusAndWait()
        _ = try await waitForInlineImage(harness, naturalWidth: InlineImageFixture.inlinePNG.width)
        let generation = harness.session.generation
        let undoLabel = harness.session.context?.undoLabel

        // Both whitespace positions belong to the replaced standalone line.
        // A caret there must expose source rather than remain hidden by its
        // block image, while preserving the authored whitespace byte for byte.
        for caret in [imageFrom - 1, imageTo + 1] {
            harness.session.revealSourceRange(fromUTF16: caret, toUTF16: caret)
            try await harness.waitUntilSelection(head: caret)
            try await waitForNoInlineImages(harness)
            #expect(
                try await harness.callPageJavaScript(
                    "return [...document.querySelectorAll('.cm-line')].some(line => line.textContent === imageLine);",
                    arguments: ["imageLine": imageLine]
                ) as? Bool == true
            )
            #expect(try await harness.session.currentText() == source)
            harness.session.revealSourceRange(fromUTF16: 6, toUTF16: 6)
            try await harness.waitUntilSelection(head: 6)
            _ = try await waitForInlineImage(harness, naturalWidth: InlineImageFixture.inlinePNG.width)
        }

        for (anchor, clickRight, head) in [(6, true, imageTo), (after + 5, false, imageFrom)] {
            harness.session.revealSourceRange(fromUTF16: anchor, toUTF16: anchor)
            try await harness.waitUntilSelection(head: anchor)
            _ = try await waitForInlineImage(harness, naturalWidth: InlineImageFixture.inlinePNG.width)
            let handled =
                try await harness.callPageJavaScript(
                    """
                    const image = document.querySelector('.cm-live-image img');
                    if (!image) return false;
                    const rect = image.getBoundingClientRect();
                    const event = new MouseEvent('mousedown', {
                      button: 0, buttons: 1, shiftKey: true, bubbles: true, cancelable: true,
                      clientX: rect.left + rect.width * (clickRight ? 0.75 : 0.25),
                      clientY: (rect.top + rect.bottom) / 2
                    });
                    image.dispatchEvent(event);
                    return event.defaultPrevented;
                    """, arguments: ["clickRight": clickRight]
                ) as? Bool
            #expect(handled == true)
            try await harness.waitUntilSelection(head: head)
            #expect(harness.session.context?.selections == [.init(anchor: anchor, head: head)])
            try await waitForNoInlineImages(harness)
            #expect(try await harness.session.currentText() == source)
        }
        #expect(harness.session.generation == generation)
        #expect(harness.session.context?.undoLabel == undoLabel)
        #expect(!harness.session.isDirty)
        await harness.closeAndDrain()
    }

    @Test("Vertical arrows enter image source through blank rows with a retained collapsed caret column")
    func inlineImageKeyboardRetainsVerticalGoalColumn() async throws {
        let image = try InlineImageFixture.inlinePNG.image()
        let lead = "0123456789012345678901234567890123456789"
        let imageSyntax = "![fixture](Attachments/figure)"
        let source = lead + "\n\n" + imageSyntax + "\n\n" + lead
        let imageFrom = lead.utf16.count + 2
        let imageTo = imageFrom + imageSyntax.utf16.count
        let afterFrom = imageTo + 2
        let harness = EditorHarness(
            source: source, initialSourceRange: 20..<20,
            laysOutForPointerTesting: true,
            imageResourcesQuery: { _ in ["Attachments/figure": image] }
        )
        defer { harness.close() }
        try await harness.waitUntilReady()
        try await harness.session.focusAndWait()
        _ = try await waitForInlineImage(harness, naturalWidth: InlineImageFixture.inlinePNG.width)
        let generation = harness.session.generation
        let undoLabel = harness.session.context?.undoLabel

        for (start, arrow, blank) in [
            (20, "ArrowDown", lead.utf16.count + 1),
            (afterFrom + 20, "ArrowUp", imageTo + 1),
        ] {
            harness.session.revealSourceRange(fromUTF16: start, toUTF16: start)
            try await harness.waitUntilSelection(head: start)
            _ = try await waitForInlineImage(harness, naturalWidth: InlineImageFixture.inlinePNG.width)
            try await harness.session.testingPressArrow(arrow)
            try await harness.waitUntilSelection(head: blank, stage: "blank row approaching image source")
            try await harness.session.testingPressArrow(arrow)
            // Flush the requested CodeMirror measure, then await the final
            // goal-column publication rather than its provisional edge caret.
            _ = try await harness.session.currentScrollAnchor()
            let head = try await harness.waitUntilSelection(in: (imageFrom + 3)..<(imageTo - 2))
            let selection = try #require(harness.session.context?.selections.first)
            #expect(selection.anchor == selection.head)
            #expect(head > imageFrom + 2 && head < imageTo - 2)
            try await waitForNoInlineImages(harness)
            #expect(
                try await harness.callPageJavaScript(
                    "return [...document.querySelectorAll('.cm-line')].some(line => line.textContent === imageSyntax);",
                    arguments: ["imageSyntax": imageSyntax]
                ) as? Bool == true
            )
            #expect(try await harness.session.currentText() == source)
        }
        #expect(harness.session.generation == generation)
        #expect(harness.session.context?.undoLabel == undoLabel)
        #expect(!harness.session.isDirty)
        await harness.closeAndDrain()
    }

    @Test("Horizontal arrows enter inline image syntax instead of skipping its source")
    func inlineImageKeyboardEntersInlineSyntax() async throws {
        let image = try InlineImageFixture.inlinePNG.image()
        let imageSyntax = "![fixture](Attachments/figure)"
        let source = "Before fixture.\n\nLeft " + imageSyntax + " Right.\n\nAfter fixture.\n"
        let imageFrom = try #require(source.range(of: imageSyntax)?.lowerBound.utf16Offset(in: source))
        let imageTo = imageFrom + imageSyntax.utf16.count
        let harness = EditorHarness(
            source: source, initialSourceRange: 6..<6,
            imageResourcesQuery: { _ in ["Attachments/figure": image] }
        )
        defer { harness.close() }
        try await harness.waitUntilReady()
        try await harness.session.focusAndWait()
        _ = try await waitForInlineImage(harness, naturalWidth: InlineImageFixture.inlinePNG.width)
        let generation = harness.session.generation
        let undoLabel = harness.session.context?.undoLabel

        for (start, arrow, boundary, inside) in [
            (imageFrom - 1, "ArrowRight", imageFrom, imageFrom + 1),
            (imageTo + 1, "ArrowLeft", imageTo, imageTo - 1),
        ] {
            harness.session.revealSourceRange(fromUTF16: start, toUTF16: start)
            try await harness.waitUntilSelection(head: start)
            _ = try await waitForInlineImage(harness, naturalWidth: InlineImageFixture.inlinePNG.width)
            try await harness.session.testingPressArrow(arrow)
            try await harness.waitUntilSelection(head: boundary, stage: "inline image source boundary")
            try await waitForNoInlineImages(harness)
            try await harness.session.testingPressArrow(arrow)
            try await harness.waitUntilSelection(head: inside, stage: "inline image source character")
            let selection = try #require(harness.session.context?.selections.first)
            #expect(selection.anchor == selection.head)
            #expect(try await harness.session.currentText() == source)
        }
        #expect(harness.session.generation == generation)
        #expect(harness.session.context?.undoLabel == undoLabel)
        #expect(!harness.session.isDirty)
        await harness.closeAndDrain()
    }

    private func waitForInlineImage(
        _ harness: EditorHarness, naturalWidth: Int, narrowerThan originalWidth: Double? = nil
    ) async throws -> [String: Double] {
        try await waitForImageGeometry(naturalWidth: naturalWidth, narrowerThan: originalWidth) {
            try await harness.callPageJavaScript(Self.inlineImageGeometryProbe) as? [String: Double]
        }
    }

    private func waitForReviewImage(
        _ harness: ReadHarness,
        naturalWidth: Int, narrowerThan originalWidth: Double? = nil
    ) async throws -> [String: Double] {
        try await waitForImageGeometry(naturalWidth: naturalWidth, narrowerThan: originalWidth) {
            try await harness.callBridgeJavaScript(Self.inlineImageGeometryProbe) as? [String: Double]
        }
    }

    private func waitForImageGeometry(
        naturalWidth: Int, narrowerThan originalWidth: Double?,
        observe: () async throws -> [String: Double]?
    ) async throws -> [String: Double] {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var last: [String: Double]?
        while ContinuousClock.now < deadline {
            last = try await observe()
            if let value = last, value["naturalWidth"] == Double(naturalWidth),
                (value["height"] ?? 0) > 0,
                originalWidth.map({ (value["readingWidth"] ?? 0) < $0 - 1 }) ?? true
            {
                return value
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        Issue.record("Inline image did not finish loading or resizing: \(String(describing: last)).")
        throw MarkdownEditorSession.SessionError.unavailable
    }

    private func expectProportionalImage(_ value: [String: Double], fixture: InlineImageFixture) {
        let width = value["width"] ?? 0
        let height = value["height"] ?? 0
        #expect(width > 0 && height > 0, "Image geometry: \(value)")
        #expect(abs(width / max(1, height) - Double(fixture.width) / Double(fixture.height)) < 0.02, "Image proportion: \(value)")
        let isBlock = fixture != .inlinePNG
        #expect(value["isBlock"] == (isBlock ? 1 : 0), "Only standalone images use block sizing: \(value)")
        let heightCap = value["heightCap"] ?? 0
        #expect(height <= heightCap + 1, "Images remain inside the reading height cap: \(value)")
        if isBlock {
            let ratio = Double(fixture.width) / Double(fixture.height)
            let containerWidth = value["containerWidth"] ?? 0
            let expectedWidth = min(containerWidth, heightCap * ratio)
            #expect(abs(width - expectedWidth) < 1.5, "A standalone image fills the available width until its height reaches the cap: \(value)")
            let leadingSpace = (value["left"] ?? 0) - (value["containerLeft"] ?? 0)
            let trailingSpace = (value["containerRight"] ?? 0) - (value["right"] ?? 0)
            #expect(abs(leadingSpace - trailingSpace) < 1.5, "A height-limited image remains centered: \(value)")
            if heightCap * ratio < containerWidth - 1 {
                #expect(abs(height - heightCap) < 1.5, "A tall image uses the height cap without changing its aspect ratio: \(value)")
            } else {
                #expect(abs(width - containerWidth) < 1.5, "A wide image reaches the full reading measure: \(value)")
            }
        } else {
            #expect(width <= Double(fixture.width) + 1, "An inline image is not enlarged beyond its native size: \(value)")
        }
        #expect(width <= (value["containerWidth"] ?? 0) + 1, "Image fits the reading width: \(value)")
        #expect(width <= (value["readingWidth"] ?? 0) + 1, "Image fits the resized reading viewport: \(value)")
        #expect((value["containerHeight"] ?? 0) + 1 >= height, "The containing image block must not collapse to a strip: \(value)")
        #expect((value["bottom"] ?? 0) <= (value["containerBottom"] ?? 0) + 1, "The containing image block must retain its entire image: \(value)")
    }

    private func waitForNoInlineImages(_ harness: EditorHarness) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            if try await harness.callPageJavaScript("return document.querySelectorAll('.cm-live-image').length;") as? Int == 0 { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Image widgets remained after source activation or document replacement.")
        throw MarkdownEditorSession.SessionError.unavailable
    }

    private func inlineImageHistoryKey(_ harness: EditorHarness, redo: Bool) async throws {
        let handled =
            try await harness.callPageJavaScript(
                """
                const event = new KeyboardEvent('keydown', {
                  key: 'z', code: 'KeyZ', keyCode: 90, which: 90,
                  metaKey: true, shiftKey: redo, bubbles: true, cancelable: true
                });
                document.querySelector('.cm-content').dispatchEvent(event);
                return event.defaultPrevented;
                """, arguments: ["redo": redo]) as? Bool
        #expect(handled == true)
    }

    private static let inlineImageGeometryProbe = """
        const image = document.querySelector('img.scholium-embedded-image[alt="fixture"]');
        if (!image || !image.complete || !image.naturalWidth
          || !image.style.getPropertyValue('--scholium-image-aspect-ratio')) return null;
        const rect = image.getBoundingClientRect();
        const container = image.closest('.cm-live-image-block') || image.closest('p') || image.parentElement;
        const block = container.getBoundingClientRect();
        const reading = document.querySelector('.cm-content') || document.querySelector('#scholium-document');
        return {width: rect.width, height: rect.height, naturalWidth: image.naturalWidth,
          naturalHeight: image.naturalHeight, bottom: rect.bottom,
          left: rect.left, right: rect.right,
          isBlock: image.classList.contains('scholium-embedded-image-block') ? 1 : 0,
          heightCap: Math.min(innerHeight * .7, parseFloat(getComputedStyle(document.documentElement).fontSize) * 40),
          readingWidth: reading.getBoundingClientRect().width,
          containerWidth: block.width, containerHeight: block.height, containerBottom: block.bottom,
          containerLeft: block.left, containerRight: block.right};
        """
}

enum InlineImageFixture: String, CaseIterable, Sendable {
    case landscapePNG, portraitJPEG, tinyGIF, panoramaPNG, inlinePNG, referencePNG
    case entityDestinationPNG, numericDestinationPNG
    case encodedReservedDestinationPNG
    case nestedAltPNG, linkedPNG

    var width: Int {
        switch self {
        case .landscapePNG, .referencePNG, .linkedPNG: 1_200
        case .portraitJPEG: 300
        case .tinyGIF: 24
        case .panoramaPNG: 1_600
        case .inlinePNG, .entityDestinationPNG, .numericDestinationPNG, .encodedReservedDestinationPNG, .nestedAltPNG: 360
        }
    }
    var height: Int {
        switch self {
        case .landscapePNG, .referencePNG, .linkedPNG: 600
        case .portraitJPEG: 900
        case .tinyGIF: 18
        case .panoramaPNG: 80
        case .inlinePNG, .entityDestinationPNG, .numericDestinationPNG, .encodedReservedDestinationPNG, .nestedAltPNG: 180
        }
    }

    @MainActor
    func image() throws -> RenderedMarkdownImage {
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
        try #require(bitmap.bitmapData).initialize(repeating: 180, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let format: NSBitmapImageRep.FileType = self == .portraitJPEG ? .jpeg : self == .tinyGIF ? .gif : .png
        let mimeType = self == .portraitJPEG ? "image/jpeg" : self == .tinyGIF ? "image/gif" : "image/png"
        return try RenderedMarkdownImage(data: #require(bitmap.representation(using: format, properties: [:])), mimeType: mimeType)
    }
}

@MainActor
private final class InlineImageQueryGate {
    private(set) var sources: [String] = []
    private var replies: [Int: CheckedContinuation<[String: RenderedMarkdownImage], Never>] = [:]
    private var completed: Set<Int> = []

    func query(_ source: String) async -> [String: RenderedMarkdownImage] {
        let index = sources.count
        let images: [String: RenderedMarkdownImage] = await withCheckedContinuation { continuation in
            sources.append(source)
            replies[index] = continuation
        }
        completed.insert(index)
        return images
    }

    func resolve(_ index: Int, with images: [String: RenderedMarkdownImage]) {
        replies.removeValue(forKey: index)?.resume(returning: images)
    }

    func releaseAll() {
        let pending = Array(replies.values)
        replies.removeAll()
        for reply in pending { reply.resume(returning: [:]) }
    }

    func waitForRequests(_ count: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while sources.count < count {
            if ContinuousClock.now >= deadline {
                Issue.record("Expected \(count) image queries, observed \(sources.count).")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func waitForCompletion(_ index: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !completed.contains(index) {
            if ContinuousClock.now >= deadline {
                Issue.record("Image query \(index) did not return its controlled reply.")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

@MainActor
private final class InlineImagePresentationBarrier: MarkdownEditorBridgeDispatching {
    private let production = WKWebViewMarkdownEditorBridgeDispatcher()
    private var isArmed = false
    private var didSuspend = false
    private var didResume = false
    private var presentationReturned = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var nonemptyCatalogGenerations: [Int] = []

    func arm() { isArmed = true }

    func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
        let request = try JSONDecoder().decode(MarkdownEditorRequest.self, from: Data(requestJSON.utf8))
        if isArmed, !didSuspend, case .setDocumentTitle = request.operation {
            didSuspend = true
            await withCheckedContinuation { continuation = $0 }
        }
        let result = try await production.dispatch(requestJSON: requestJSON, in: webView)
        if case .setImageResources(let resources) = request.operation, !resources.isEmpty {
            nonemptyCatalogGenerations.append(request.knownGeneration)
        }
        if didSuspend, didResume, case .setWritingIndexContext = request.operation {
            presentationReturned = true
        }
        return result
    }

    func resume() {
        didResume = true
        continuation?.resume()
        continuation = nil
    }

    func waitUntilSuspended() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while continuation == nil {
            if ContinuousClock.now >= deadline {
                Issue.record("Image presentation did not reach its title acknowledgement barrier.")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func waitForPresentationToReturn() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !presentationReturned {
            if ContinuousClock.now >= deadline {
                Issue.record("The suspended image convergence did not complete after its generation changed.")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class InlineImageStartupScrollBarrier: MarkdownEditorBridgeDispatching {
    private let production = WKWebViewMarkdownEditorBridgeDispatcher()
    private var didSuspend = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var nonemptyCatalogGenerations: [Int] = []

    func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
        let request = try JSONDecoder().decode(MarkdownEditorRequest.self, from: Data(requestJSON.utf8))
        if !didSuspend, !released, case .setScrollFraction = request.operation {
            didSuspend = true
            await withCheckedContinuation { continuation = $0 }
        }
        let result = try await production.dispatch(requestJSON: requestJSON, in: webView)
        if case .setImageResources(let resources) = request.operation, !resources.isEmpty {
            let reply = try #require(result as? [String: Any])
            #expect(reply["accepted"] as? Bool == true)
            nonemptyCatalogGenerations.append(request.knownGeneration)
        }
        return result
    }

    func resume() {
        released = true
        continuation?.resume()
        continuation = nil
    }

    func waitUntilSuspended() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while continuation == nil {
            try #require(ContinuousClock.now < deadline, "Initial restoration did not reach its post-convergence barrier.")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
