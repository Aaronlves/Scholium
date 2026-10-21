import AppKit
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

extension MarkdownEditorWebViewIntegrationTests {
    @Test(
        "Opt-in exact Format Matrix standalone reader preparation diagnostic",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_FORMAT_READER_DIAGNOSTIC"] == "1"))
    func exactFormatMatrixStandaloneReaderDiagnostic() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let buildRoot = repository.appendingPathComponent(".build", isDirectory: true).resolvingSymlinksInPath().path + "/"
        let fixture = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SCHOLIUM_STRESS_FIXTURE"]
                ?? repository.appendingPathComponent(".build/stress-audit/fixture-complex-508").path
        ).standardizedFileURL.resolvingSymlinksInPath()
        try #require(fixture.path.hasPrefix(buildRoot))
        let manifest = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appendingPathComponent("stress-manifest.json"))) as? [String: Any])
        let scenarios = try #require(manifest["scenarios"] as? [String: String])
        let path = try #require(scenarios["format_matrix"])
        let inventory = try #require((manifest["files"] as? [String: [String: Any]])?[path])
        let file = fixture.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        try #require(file.path.hasPrefix(fixture.path + "/"))
        let bytes = try Data(contentsOf: file)
        let fingerprint = DocumentFingerprint(data: bytes)
        let expectedSHA256 = try #require(inventory["sha256"] as? String)
        let expectedByteCount = try #require(inventory["bytes"] as? Int)
        try #require(fingerprint.sha256 == expectedSHA256 && bytes.count == expectedByteCount)
        let source = try #require(NoteDocument.decodeUTF8PreservingBOM(bytes))
        try #require(source.components(separatedBy: "```mermaid\n").count - 1 == 120)
        let relativePath = path.split(separator: "/").dropFirst().joined(separator: "/")
        let document = NoteDocument(relativePath: relativePath, rawContent: source)
        try #require(document.sourceBytes == bytes)
        let rendered = SafeMarkdownRenderer.render(document)
        let harness = ReadHarness(
            source: source, htmlBody: rendered.htmlBody, fingerprint: fingerprint.sha256,
            initialAnchor: nil, initialScrollFraction: 0, documentTitle: "Stress Format Matrix",
            presentsDocumentPreparation: true, laysOutForNativePreview: true, relativePath: relativePath)
        defer {
            harness.close()
            #expect((try? Data(contentsOf: file)) == bytes)
        }
        harness.beginFormatDiagnostic(phase: "standalone_reader")
        harness.emitFormatDiagnostic(
            event: "fixture",
            extra: [
                "source_bytes": bytes.count, "source_sha256": fingerprint.sha256, "mermaid_source_blocks": 120,
                "boundary":
                    "Exact source and production standalone reader/coordinator preparation. No CodeMirror, editor save, catalog, previews or app mode handoff.",
                "failure_boundary":
                    "onRenderingFailure exposes its original String only; no underlying NSError domain, code or userInfo is available through that production callback.",
            ])
        try await harness.waitUntilReadPreparationAvailable()
        try await harness.installFormatWorkMetrics()
        try await harness.waitForFormatDiagnosticReady()
        try await harness.emitFormatWorkMetrics()
        try await harness.scroll(toFraction: 0.06128792086696526)
        _ = try await harness.callBridgeJavaScript("window.dispatchEvent(new Event('scroll'));")
        let anchorDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while harness.latestObservedScrollPosition.anchor == nil || harness.latestObservedScrollPosition.fraction <= 0 {
            try #require(ContinuousClock.now < anchorDeadline, "The standalone reader must publish an actual nonzero reading position and anchor")
            try await Task.sleep(for: .milliseconds(25))
        }
        let position = harness.latestObservedScrollPosition
        let anchor = try #require(position.anchor)
        harness.emitFormatDiagnostic(
            event: "reading_position",
            extra: [
                "fraction": position.fraction, "source_utf16_offset": anchor.sourceUTF16Offset,
                "block_utf16_start": anchor.blockUTF16LowerBound, "block_utf16_end": anchor.blockUTF16UpperBound,
            ])
        #expect(!harness.hasPendingRestoreRequest)
        #expect(anchor.sourceFingerprint == fingerprint.sha256)
        #expect(anchor.isValid(forUTF16Length: source.utf16.count))
        await harness.closeAndDrain()
    }

    @Test("Review original-image activation preserves reading context and authored linked-image navigation")
    func reviewOriginalImageActivation() async throws {
        let target = "Attachments/图%23%2525.png"
        let source = """
            Retained 🦉 é selection [focus](Anchor.md).

            ![Bare](\(target))

            [![Linked](Attachments/linked.png)](Other.md)
            """
        let document = NoteDocument(relativePath: "ReadFixture.md", rawContent: source)
        let image = try InlineImageFixture.inlinePNG.image()
        let rendered = SafeMarkdownRenderer.render(
            document,
            embeddedImages: [
                try #require(target.removingPercentEncoding): image, "Attachments/linked.png": image,
            ])
        let harness = ReadHarness(
            source: source, htmlBody: rendered.htmlBody, fingerprint: document.fingerprint.sha256,
            initialAnchor: nil, initialScrollFraction: 0, laysOutForNativePreview: true,
            imagePreviewsEnabled: true)
        defer { harness.close() }
        try await harness.waitUntilReady()
        try await harness.waitForReviewImageDecoding()
        _ = try await harness.callBridgeJavaScript(
            """
            const origin = document.querySelector('#scholium-document a'); origin.id = 'focus-origin';
            origin.focus({preventScroll:true});
            const text = document.querySelector('#scholium-document p').firstChild;
            const range = document.createRange(); range.setStart(text, 0); range.setEnd(text, 19);
            window.getSelection().removeAllRanges(); window.getSelection().addRange(range);
            window.imageContextBefore = {selection: window.getSelection().toString(),
                focus: document.activeElement.id, scroll: window.scrollY};
            """)
        try await harness.clickReviewImage(alt: "Bare")
        try await harness.waitForImagePreviews(1)
        #expect(harness.imagePreviewTargets == [target])
        #expect(
            try await harness.callBridgeJavaScript(
                "return window.getSelection().toString() === imageContextBefore.selection && document.activeElement.id === imageContextBefore.focus && Math.abs(window.scrollY-imageContextBefore.scroll)<1;"
            ) as? Bool == true)

        _ = try await harness.callBridgeJavaScript(
            """
            const image = document.querySelector('img[alt="Bare"]');
            image.focus({preventScroll:true});
            image.dispatchEvent(new KeyboardEvent('keydown', {key:'Enter', bubbles:true, cancelable:true}));
            """)
        try await harness.waitForImagePreviews(2)
        #expect(harness.imagePreviewTargets == [target, target])
        _ = try await harness.callBridgeJavaScript("document.querySelector('img[alt=\"Linked\"]').click();")
        try await harness.waitForReadLinks(1)
        #expect(harness.readLinkTargets == ["Other.md"])
        #expect(harness.imagePreviewTargets.count == 2)

        // Exercise the keyboard route in the named reader world, but capture
        // only the popup request: actual native menu tracking belongs to QA.
        let receipt = try #require(
            try await harness.callBridgeJavaScript(
                """
                const handler = window.webkit.messageHandlers.scholiumRead;
                const original = handler.postMessage;
                const requests = [];
                handler.postMessage = function(message) {
                    if (message.type === 'imageContextMenu') { requests.push(message); return; }
                    return original.call(this, message);
                };
                try {
                    const link = document.querySelector('img[alt="Linked"]').closest('a');
                    link.focus({preventScroll:true});
                    window.linkedImageContextBefore = {selection:window.getSelection().toString(), scroll:window.scrollY};
                    const event = new KeyboardEvent('keydown', {key:'F10', shiftKey:true, bubbles:true, cancelable:true});
                    link.dispatchEvent(event);
                    return {requests, prevented:event.defaultPrevented};
                } finally { handler.postMessage = original; }
                """) as? [String: Any])
        #expect(receipt["prevented"] as? Bool == true)
        let requests = try #require(receipt["requests"] as? [[String: Any]])
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        let envelope = try harness.readBridgeEnvelope()
        #expect(request["type"] as? String == "imageContextMenu")
        #expect(request["target"] as? String == "Attachments/linked.png")
        for key in ["documentID", "fingerprint"] {
            #expect(request[key] as? String == envelope[key] as? String)
        }
        for key in ["version", "loadGeneration"] {
            #expect(request[key] as? Int == envelope[key] as? Int)
        }
        #expect(request["payloadFingerprint"] as? String == document.fingerprint.sha256)
        #expect(try #require(request["clientX"] as? Double).isFinite)
        #expect(try #require(request["clientY"] as? Double).isFinite)
        #expect(harness.imagePreviewTargets == [target, target])
        #expect(harness.readLinkTargets == ["Other.md"])
        #expect(
            try await harness.callBridgeJavaScript(
                "return document.activeElement === document.querySelector('img[alt=\"Linked\"]').closest('a') && window.getSelection().toString() === linkedImageContextBefore.selection && Math.abs(window.scrollY-linkedImageContextBefore.scroll)<1;"
            ) as? Bool == true)
        #expect(document.rawContent.utf8.elementsEqual(source.utf8))
        await harness.closeAndDrain()
    }

    @Test("Review image actions reject failed media, missing capability, and stale bridge receipts")
    func reviewOriginalImageAdmission() async throws {
        let target = "Attachments/valid%20image.png"
        let source = "![Valid](\(target))\n\n![Failed](Attachments/broken.png)\n\n![Missing](Attachments/missing.png)"
        let document = NoteDocument(relativePath: "ReadFixture.md", rawContent: source)
        let valid = try InlineImageFixture.inlinePNG.image()
        let malformed = try RenderedMarkdownImage(
            data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), mimeType: "image/png")
        let rendered = SafeMarkdownRenderer.render(
            document,
            embeddedImages: [
                "Attachments/valid image.png": valid, "Attachments/broken.png": malformed,
            ])
        let harness = ReadHarness(
            source: source, htmlBody: rendered.htmlBody, fingerprint: document.fingerprint.sha256,
            initialAnchor: nil, initialScrollFraction: 0, imagePreviewsEnabled: true)
        defer { harness.close() }
        try await harness.waitUntilReady()
        try await harness.waitForReviewImageDecoding()
        #expect(
            try await harness.callBridgeJavaScript(
                """
                const images = [...document.querySelectorAll('img.scholium-embedded-image')];
                const failed = images.find(image => image.alt === 'Failed');
                failed.click();
                return images.length === 2 && failed.complete && failed.naturalWidth === 0
                    && !failed.hasAttribute('role') && !failed.hasAttribute('tabindex')
                    && !document.querySelector('[data-scholium-image-target="Attachments/missing.png"]');
                """) as? Bool == true)
        let oldEnvelope = try harness.readBridgeEnvelope()
        let mutations: [[String: Any]] = [
            ["fingerprint": "stale"], ["loadGeneration": -1], ["documentID": "Other.md"],
            ["target": ""], ["target": String(repeating: "🦉", count: 2_049)],
        ]
        for mutation in mutations {
            try await harness.postImageMessage(target: target, envelope: oldEnvelope, overrides: mutation)
        }
        try await harness.postImageMessage(target: target, envelope: oldEnvelope)
        try await harness.waitForImagePreviews(1)
        #expect(harness.imagePreviewTargets == [target])

        harness.setImagePreviewsEnabled(false)
        try await harness.waitForImageCapability(false)
        try await harness.postImageMessage(target: target, envelope: harness.readBridgeEnvelope())
        _ = try await harness.callBridgeJavaScript("document.querySelector('img[alt=\"Valid\"]').click();")
        harness.setImagePreviewsEnabled(true)
        try await harness.waitForImageCapability(true)
        try await harness.postImageMessage(target: target, envelope: oldEnvelope)
        try await harness.postImageMessage(target: target, envelope: harness.readBridgeEnvelope())
        try await harness.waitForImagePreviews(2)
        #expect(harness.imagePreviewTargets == [target, target])
        await harness.closeAndDrain()
    }

    @Test("Dismantling Review releases its named-world handler and captured callbacks")
    func reviewNamedWorldHandlerReleasesCoordinator() async throws {
        final class CallbackSentinel {
            func observeLink() {}
        }
        final class WeakBox<Object: AnyObject> {
            weak var value: Object?
        }

        _ = NSApplication.shared
        let coordinator = WeakBox<SafeMarkdownReadWebView.Coordinator>()
        let callback = WeakBox<CallbackSentinel>()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }

        func mountedWebView(in view: NSView) -> WKWebView? {
            if let webView = view as? WKWebView { return webView }
            for child in view.subviews {
                if let webView = mountedWebView(in: child) { return webView }
            }
            return nil
        }

        var retainedWebView: WKWebView?
        do {
            let sentinel = CallbackSentinel()
            callback.value = sentinel
            let source = "# Review teardown\n"
            let document = NoteDocument(relativePath: "Teardown.md", rawContent: source)
            let surface = SafeMarkdownReadWebView(
                documentID: document.relativePath,
                document: document,
                htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
                presentationCSS: "",
                userCSS: "",
                onLinkClick: { [sentinel] _ in sentinel.observeLink() },
                onOpenExternalURL: { _ in },
                onRenderingFailure: nil
            )
            var host: NSHostingController<AnyView>? = NSHostingController(
                rootView: AnyView(surface)
            )
            window.contentViewController = host
            window.orderFrontRegardless()

            let mountDeadline = ContinuousClock.now.advanced(by: .seconds(5))
            while retainedWebView == nil, ContinuousClock.now < mountDeadline {
                if let contentView = window.contentView {
                    retainedWebView = mountedWebView(in: contentView)
                }
                if retainedWebView == nil {
                    try await Task.sleep(for: .milliseconds(20))
                }
            }
            let webView = try #require(retainedWebView)
            coordinator.value = webView.navigationDelegate as? SafeMarkdownReadWebView.Coordinator
            _ = try #require(coordinator.value)
            #expect(callback.value != nil)

            host?.rootView = AnyView(EmptyView())
            window.contentViewController = nil
            host = nil
        }

        let releaseDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while coordinator.value != nil || callback.value != nil,
            ContinuousClock.now < releaseDeadline
        {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(retainedWebView != nil)
        #expect(coordinator.value == nil)
        #expect(callback.value == nil)
    }

    @Test("Review publishes source positions while scrolling continues")
    func reviewContinuousScrollReports() async throws {
        let source = (1...24).map { section in
            "## Section \(section)\r\n\r\n" + String(repeating: "Nonprivate 中文 😀 paragraph.\r\n\r\n", count: 15)
        }.joined()
        let document = NoteDocument(relativePath: "Scroll.md", rawContent: source)
        let harness = ReadHarness(
            source: source, htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: document.fingerprint.sha256, initialAnchor: nil, initialScrollFraction: 0)
        defer { harness.close() }
        try await harness.waitUntilReady()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var observedOffsets: [Int] = []
        var step = 0
        while observedOffsets.count < 2 {
            step += 1
            _ = try await harness.callBridgeJavaScript(
                """
                const extent = document.documentElement.scrollHeight - window.innerHeight;
                window.scrollTo({top: extent * fraction, behavior: 'auto'});
                window.dispatchEvent(new Event('scroll'));
                """, arguments: ["fraction": min(0.9, 0.1 + Double(step) * 0.008)])
            if let anchor = harness.latestObservedScrollPosition.anchor,
                anchor.sourceUTF16Offset > source.utf16.count / 4,
                observedOffsets.last.map({ abs($0 - anchor.sourceUTF16Offset) > 500 }) ?? true
            {
                observedOffsets.append(anchor.sourceUTF16Offset)
                #expect(anchor.sourceFingerprint == document.fingerprint.sha256)
            }
            try #require(ContinuousClock.now < deadline, "No Review section updates during continuous scroll")
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(observedOffsets.count == 2)
    }

    @Test("Received reply text is immediately readable and selectable")
    func chatReplyImmediateContent() async throws {
        let source = "Existing " + String(repeating: "中文 👩‍💻 e\u{301} reply. ", count: 20)
        let document = NoteDocument(relativePath: "Reply.md", rawContent: source)
        let harness = ReadHarness(
            source: source, htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: document.fingerprint.sha256, initialAnchor: nil, initialScrollFraction: 0,
            laysOutForNativePreview: true, replyProjection: true)
        defer { harness.close() }
        try await harness.waitUntilReady()
        let snapshot = try #require(
            try await harness.callBridgeJavaScript(
                """
                const root = document.getElementById('scholium-document');
                const before = {text: root.textContent.trim(), height: root.getBoundingClientRect().height};
                const selection = window.getSelection();
                const all = document.createRange(); all.selectNodeContents(root);
                selection.removeAllRanges(); selection.addRange(all);
                document.dispatchEvent(new Event('selectionchange'));
                return {...before,
                    selected: selection.toString().trim(), finalHeight: root.getBoundingClientRect().height};
                """) as? [String: Any])
        #expect(snapshot["text"] as? String == source.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(snapshot["selected"] as? String == snapshot["text"] as? String)
        #expect(snapshot["height"] as? Double == snapshot["finalHeight"] as? Double)
    }

    @Test("Chat selection menus stay inside the selection and preserve other Note and web link menus")
    func chatNoteContextTarget() async throws {
        let first = AgentChatReference.url(noteID: UUID())
        let second = AgentChatReference.url(noteID: UUID())
        let source = "[First](\(first.absoluteString)) [Second](\(second.absoluteString)) [Web](https://example.org)"
        let document = NoteDocument(relativePath: "Reply.md", rawContent: source)
        let harness = ReadHarness(
            source: source, htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: document.fingerprint.sha256, initialAnchor: nil, initialScrollFraction: 0,
            laysOutForNativePreview: true, replyProjection: true)
        defer { harness.close() }
        try await harness.waitUntilReady()
        let cancelled =
            try await harness.callBridgeJavaScript(
                """
                const links = document.querySelectorAll('#scholium-document a');
                const selection = window.getSelection();
                const range = document.createRange(); range.selectNodeContents(links[0]);
                selection.removeAllRanges(); selection.addRange(range);
                return [...links].map(link => {
                    const box = link.getBoundingClientRect();
                    const event = new MouseEvent('contextmenu', {bubbles:true, cancelable:true, clientX:box.x+1, clientY:box.y+1});
                    link.dispatchEvent(event); return event.defaultPrevented;
                });
                """) as? [Bool]
        #expect(cancelled == [true, true, false])
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !harness.replyEvents.contains(where: {
            if case .noteContext = $0 { return true }
            return false
        }) {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(20))
        }
        let targets = harness.replyEvents.compactMap { event -> URL? in
            if case .noteContext(let url, _, _) = event { return url }
            return nil
        }
        #expect(targets == [second])
        let selections = harness.replyEvents.compactMap { event -> String? in
            if case .selectionContext(let text, _, _) = event { return text }
            return nil
        }
        #expect(selections == ["First"])
    }

    @Test("Chat reader quotes one selection across prose, table and code")
    func chatReplyCrossObjectSelection() async throws {
        let source = "Reason 😀.\n\n| Claim | Evidence |\n|---|---|\n| A | B |\n\n```text\nlast line\n```"
        let document = NoteDocument(relativePath: "Reply.md", rawContent: source)
        let harness = ReadHarness(
            source: source, htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: document.fingerprint.sha256, initialAnchor: nil, initialScrollFraction: 0, laysOutForNativePreview: true, replyProjection: true)
        defer { harness.close() }
        try await harness.waitUntilReady()
        let selected = try #require(
            try await harness.callBridgeJavaScript(
                """
                const root = document.getElementById('scholium-document');
                const first = root.querySelector('p').firstChild;
                const last = root.querySelector('pre code').firstChild;
                const range = document.createRange(); range.setStart(first, 0); range.setEnd(last, last.length);
                const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
                root.dispatchEvent(new KeyboardEvent('keydown', {
                    key: 'r', metaKey: true, shiftKey: true, bubbles: true, cancelable: true
                }));
                return selection.toString();
                """) as? String)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !harness.replyEvents.contains(where: {
            if case .quote = $0 { return true }
            return false
        }) {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(20))
        }
        let excerpts = harness.replyEvents.compactMap { event -> String? in
            if case .quote(let text) = event { return text }
            return nil
        }
        #expect(excerpts == [selected])
        #expect(selected.contains("Reason 😀.") && selected.contains("Evidence") && selected.contains("last line"))
        #expect(AgentChatReplyQuotation.passage(.reader(source: source, excerpt: selected), in: source) == selected)
        #expect(AgentChatReplyQuotation.passage(.reader(source: source, excerpt: selected), in: "Changed") == nil)
        // WebKit reserves geometry; the surrounding native reply owns actions.
        let slots = try await harness.callBridgeJavaScript("return document.querySelectorAll('.scholium-reply-controls').length;") as? Int
        let controls = try await harness.callBridgeJavaScript("return document.querySelectorAll('.scholium-reply-controls button').length;") as? Int
        #expect(slots == 2 && controls == 0)
        let identities =
            try await harness.callBridgeJavaScript(
                "return [...document.querySelectorAll('[data-scholium-object]')].map(e => e.dataset.scholiumObject);") as? [String]
        #expect(identities == SafeMarkdownRenderer.render(document).objects.map(\.id))
    }

    @Test("Review restores an exact repeated-text range and rejects unrendered Markdown syntax")
    func reviewChatSourceRange() async throws {
        let source = "重复 😀 same same.\r\n\r\nFormatted **word**.\r\n"
        let document = NoteDocument(relativePath: "ChatRange.md", rawContent: source)
        let harness = ReadHarness(
            source: source, htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: document.fingerprint.sha256, initialAnchor: nil, initialScrollFraction: 0)
        defer { harness.close() }
        try await harness.waitUntilReady()
        let last = (source as NSString).range(of: "same", options: .backwards)
        harness.requestSourceRange(
            .init(
                utf16LowerBound: last.location, utf16UpperBound: NSMaxRange(last),
                line: 1, column: 1, endLine: 1, endColumn: 1))
        try await harness.waitUntilSourceLineReached(1)
        #expect(try await harness.callBridgeJavaScript("return window.getSelection().toString();") as? String == "same")
        harness.requestSourceRange(
            .init(
                utf16LowerBound: last.location, utf16UpperBound: NSMaxRange(last),
                line: 1, column: 1, endLine: 1, endColumn: 1), fingerprint: DocumentFingerprint(content: "Older revision").sha256)
        let revisionDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !harness.sourceRevisionChanged {
            try #require(ContinuousClock.now < revisionDeadline)
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!harness.sourceRangeUnavailable)
        #expect(try await harness.callBridgeJavaScript("return window.getSelection().toString();") as? String == "same")
        let offset =
            try await harness.callBridgeJavaScript(
                "const s=window.getSelection(); const r=document.createRange(); r.selectNodeContents(s.anchorNode.parentElement); r.setEnd(s.anchorNode,s.anchorOffset); return r.toString().length;"
            ) as? Int
        #expect(offset == last.location)
        let syntax = (source as NSString).range(of: "**word**")
        harness.requestSourceRange(
            .init(
                utf16LowerBound: syntax.location, utf16UpperBound: NSMaxRange(syntax),
                line: 3, column: 1, endLine: 3, endColumn: 1))
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !harness.sourceRangeUnavailable {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(try await harness.callBridgeJavaScript("return window.getSelection().toString();") as? String == "same")
    }

    @Test("Review arrival is temporary, repeatable and preserves a reading selection")
    func reviewArrivalFeedback() async throws {
        let source = "First paragraph.\n\nSecond paragraph. " + String(repeating: "Long wrapped context remains readable. ", count: 35) + "\n"
        let document = NoteDocument(relativePath: "Arrival.md", rawContent: source)
        let harness = ReadHarness(
            source: source,
            htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: document.fingerprint.sha256, initialAnchor: nil, initialScrollFraction: 0)
        defer { harness.close() }
        try await harness.waitUntilReady()
        let paragraphsHaveNoBackground =
            "return [...document.querySelectorAll('#scholium-document p')].every(p => getComputedStyle(p).backgroundColor === 'rgba(0, 0, 0, 0)');"
        #expect(try await harness.callBridgeJavaScript(paragraphsHaveNoBackground) as? Bool == true)
        _ = try await harness.callBridgeJavaScript("window.getSelection().selectAllChildren(document.querySelector('[data-source-line=\"1\"]'));")
        harness.requestSourceLine(3)
        try await harness.waitUntilSourceLineReached(3)
        let snapshot = try #require(
            try await harness.callBridgeJavaScript(
                "return {target:document.querySelector('.scholium-arrival-target')?.dataset.arrivalLine, selection:window.getSelection().toString(), markerHeight:document.querySelector('.scholium-arrival-target').getBoundingClientRect().height, paragraphHeight:document.querySelector('[data-source-line=\"3\"]').getBoundingClientRect().height};"
            ) as? [String: Any])
        #expect(snapshot["target"] as? String == "3")
        #expect(snapshot["selection"] as? String == "First paragraph.")
        let markerHeight = try #require(snapshot["markerHeight"] as? Double)
        let paragraphHeight = try #require(snapshot["paragraphHeight"] as? Double)
        #expect(markerHeight > 0 && markerHeight < paragraphHeight / 2)
        #expect(try await harness.callBridgeJavaScript(Self.arrivalAnimationProbe) as? Bool == true)
        #expect(try await harness.callBridgeJavaScript("return document.querySelectorAll('.scholium-arrival-target').length;") as? Int == 1)
        let expirationDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        var remaining = 1
        while remaining != 0 && ContinuousClock.now < expirationDeadline {
            remaining =
                try await harness.callBridgeJavaScript(
                    "return document.querySelectorAll('.scholium-arrival-target').length;"
                ) as? Int ?? -1
            if remaining != 0 { try await Task.sleep(for: .milliseconds(20)) }
        }
        #expect(remaining == 0)
        #expect(try await harness.callBridgeJavaScript(paragraphsHaveNoBackground) as? Bool == true)
        harness.requestSourceLine(3)
        try await harness.waitUntilSourceLineReached(3)
        #expect(try await harness.callBridgeJavaScript("return document.querySelectorAll('.scholium-arrival-target').length;") as? Int == 1)
        #expect(try await harness.callBridgeJavaScript("return window.scholiumReadNavigation.reveal(99);") as? Bool == false)
        #expect(try await harness.callBridgeJavaScript("return document.querySelectorAll('.scholium-arrival-target').length;") as? Int == 0)
    }

    @Test("Review find preserves prose layout and content")
    func reviewFindPreservesLayout() async throws {
        let source = "findtarget at the beginning.\n\n" + String(repeating: "Following paragraph.\n\n", count: 30)
        let document = NoteDocument(relativePath: "Find.md", rawContent: source)
        let harness = ReadHarness(
            source: source,
            htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: document.fingerprint.sha256,
            initialAnchor: nil,
            initialScrollFraction: 0
        )
        defer { harness.close() }
        try await harness.waitUntilReady()
        let snapshot = try #require(
            try await harness.callBridgeJavaScript(
                """
                const content = document.getElementById('scholium-document');
                const before = content.innerHTML;
                const geometry = () => JSON.stringify([getComputedStyle(content).paddingTop,
                  getComputedStyle(content).paddingBottom, content.offsetWidth, content.offsetHeight]);
                const beforeGeometry = geometry();
                window.scrollTo(0, 300);
                const scrollBefore = window.scrollY;
                window.scholiumReviewFind.perform({
                  query: 'findtarget', caseSensitive: false, wholeWord: false, action: 'present'
                });
                const preservesScroll = window.scrollY === scrollBefore;
                const result = window.scholiumReviewFind.perform({
                  query: 'findtarget', caseSensitive: false, wholeWord: false,
                  action: 'update'
                });
                const duringGeometry = geometry();
                window.scholiumReviewFind.perform({operation: 'clear'});
                return {total: result.total, unchanged: before === content.innerHTML, preservesScroll,
                  stable: beforeGeometry === duringGeometry && beforeGeometry === geometry()};
                """) as? [String: Any])
        #expect(snapshot["total"] as? Int == 1)
        #expect(snapshot["unchanged"] as? Bool == true)
        #expect(snapshot["preservesScroll"] as? Bool == true)
        #expect(snapshot["stable"] as? Bool == true)
    }

    @Test("Review Mermaid passes keep distinct source locations, isolated references and current themes")
    func reviewMermaidPassSourceAndThemeIsolation() async throws {
        let names = ["Alpha", "Beta", "Alpha", "Alpha", "Beta", "Gamma"]
        let diagrams = names.map { name in
            "flowchart LR\naccTitle: \(name) illustration\naccDescr: Synthetic \(name) description.\n  A[Start \(name)] --> B[Finish]\n"
        }
        let source =
            "# Diagrams\n\nSynthetic context stays source owned.\n\n"
            + diagrams.map { "```mermaid\n\($0)```\n\n" }.joined()
        let document = NoteDocument(relativePath: "ReadFixture.md", rawContent: source)
        let harness = ReadHarness(
            source: source, htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: document.fingerprint.sha256, initialAnchor: nil, initialScrollFraction: 0)
        defer { harness.close() }
        try await harness.waitUntilReadPreparationAvailable()
        try await harness.installFormatWorkMetrics()
        try await harness.waitUntilReady()
        let identity = try harness.webViewIdentity()
        let initialCounts = try #require(
            try await harness.callBridgeJavaScript(
                "const stats=window.__scholiumFormatWorkMetrics;return {renders:stats.render_calls,mounts:stats.mount_calls,sources:stats.sources.size};")
                as? [String: Int])
        #expect(initialCounts["renders"] == 3)
        #expect(initialCounts["mounts"] == 6)
        #expect(initialCounts["sources"] == 3)
        let snapshotScript = """
            const wrappers=[...document.querySelectorAll('.scholium-mermaid')];
            const roots=wrappers.map(wrapper=>wrapper.querySelector('.scholium-mermaid-output')?.shadowRoot);
            return {isolated:new Set(roots).size===wrappers.length && roots.every(Boolean),
              diagrams:wrappers.map((wrapper,index)=>{
                const root=roots[index], svg=root?.querySelector('svg');
                const elements=svg?[svg,...svg.querySelectorAll('*')]:[];
                const ids=elements.map(element=>element.id).filter(Boolean);
                const references=elements.flatMap(element=>['aria-labelledby','aria-describedby']
                  .flatMap(name=>(element.getAttribute(name)||'').split(/\\s+/).filter(Boolean)));
                const fragments=elements.flatMap(element=>[...element.attributes]
                  .flatMap(attribute=>[...attribute.value.matchAll(/url\\(#([^)]+)\\)/g)].map(match=>match[1])));
                return {source:wrapper.querySelector('.scholium-mermaid-source > code')?.textContent || '',
                  lower:Number(wrapper.dataset.sourceUtf16Start),upper:Number(wrapper.dataset.sourceUtf16End),
                  title:svg?.querySelector('title')?.textContent || '',description:svg?.querySelector('desc')?.textContent || '',
                  references_local:references.length>0 && references.concat(fragments).every(id=>!!root.getElementById(id)),
                  ids_unique:new Set(ids).size===ids.length,
                  role:svg?.getAttribute('role'),theme:!surface || !!svg?.outerHTML.includes(surface)};
              })};
            """
        let initial = try #require(try await harness.callBridgeJavaScript(snapshotScript, arguments: ["surface": ""]) as? [String: Any])
        #expect(initial["isolated"] as? Bool == true)
        let initialDiagrams = try #require(initial["diagrams"] as? [[String: Any]])
        #expect(initialDiagrams.count == diagrams.count)
        var locations: [[Int]] = []
        for (index, item) in initialDiagrams.enumerated() {
            #expect(item["source"] as? String == diagrams[index])
            #expect(item["references_local"] as? Bool == true)
            #expect(item["ids_unique"] as? Bool == true)
            #expect(item["role"] as? String == "img")
            #expect(item["title"] as? String == "\(names[index]) illustration")
            #expect(item["description"] as? String == "Synthetic \(names[index]) description.")
            let lower = try #require(item["lower"] as? Int)
            let upper = try #require(item["upper"] as? Int)
            locations.append([lower, upper])
            #expect((source as NSString).substring(with: NSRange(location: lower, length: upper - lower)).contains(diagrams[index]))
        }
        #expect(Set(locations.map { $0[0] }).count == diagrams.count)
        try await harness.scroll(toFraction: 0.25)
        let beforeAnchor = try await harness.waitUntilCapturedAnchor(stage: "diagram theme update starting position") { $0.fallbackFraction > 0.1 }
        let beforeY = try #require(try await harness.callBridgeJavaScript("return scrollY;") as? Double)
        for (background, surface, ink, accent, separator) in [
            ("#111111", "#222222", "#eeeeee", "#aaccff", "#777777"),
            ("#fafafa", "#eeeeee", "#111111", "#3355aa", "#888888"),
        ] {
            let css =
                ":root {--scholium-color-document-background:\(background);--scholium-color-surface-background:\(surface);--scholium-color-primary-text:\(ink);--scholium-color-accent:\(accent);--scholium-color-separator:\(separator);}"
            let result = try await harness.callBridgeJavaScript(
                """
                const stats=window.__scholiumFormatWorkMetrics;
                stats.render_calls=0;stats.mount_calls=0;stats.sources.clear();
                // Match the native DocumentWebEnvironment projection, whose
                // inline semantic colors take precedence over :root rules.
                for (const [name,value] of Object.entries(palette)) document.documentElement.style.setProperty(name,value);
                return await window.scholiumSetPresentationCSS(css,'');
                """,
                arguments: [
                    "css": css,
                    "palette": [
                        "--scholium-color-document-background": background,
                        "--scholium-color-surface-background": surface,
                        "--scholium-color-primary-text": ink,
                        "--scholium-color-accent": accent,
                        "--scholium-color-separator": separator,
                    ],
                ])
            #expect(result as? Bool == true)
            let counts = try #require(
                try await harness.callBridgeJavaScript(
                    "return {renders:window.__scholiumFormatWorkMetrics.render_calls,mounts:window.__scholiumFormatWorkMetrics.mount_calls};") as? [String: Int]
            )
            #expect(counts["renders"] == 3)
            #expect(counts["mounts"] == 6)
            let updated = try #require(try await harness.callBridgeJavaScript(snapshotScript, arguments: ["surface": surface]) as? [String: Any])
            #expect(updated["isolated"] as? Bool == true)
            let updatedDiagrams = try #require(updated["diagrams"] as? [[String: Any]])
            #expect(updatedDiagrams.count == diagrams.count)
            for (index, item) in updatedDiagrams.enumerated() {
                #expect(item["source"] as? String == diagrams[index])
                #expect(item["lower"] as? Int == locations[index][0])
                #expect(item["upper"] as? Int == locations[index][1])
                #expect(item["title"] as? String == initialDiagrams[index]["title"] as? String)
                #expect(item["description"] as? String == initialDiagrams[index]["description"] as? String)
                for key in ["references_local", "ids_unique", "theme"] { #expect(item[key] as? Bool == true, "Diagram \(index): \(key)") }
            }
            #expect(try harness.webViewIdentity() == identity)
            let afterY = try #require(try await harness.callBridgeJavaScript("return scrollY;") as? Double)
            #expect(abs(afterY - beforeY) <= 1)
        }
        #expect(harness.latestObservedScrollPosition.anchor?.sourceFingerprint == beforeAnchor.sourceFingerprint)
        #expect(try await harness.callBridgeJavaScript("return configuration.fingerprint;") as? String == document.fingerprint.sha256)
        await harness.closeAndDrain()
    }

    @Test("Review renders inert Mermaid and keeps unsupported source visible")
    func reviewMermaidProjectionFailsClosed() async throws {
        let source = """
            ```MERMAID
            flowchart LR
            accTitle: Argument structure
            accDescr: A reason supports a conclusion.
            A --> B
            ```

            ```mermaid
            not-a-diagram
            ```
            """
        let htmlBody = #"""
            <pre dir="ltr" data-source-utf16-start="0" data-source-utf16-end="117"><code dir="ltr" class="language-MERMAID">flowchart LR
            accTitle: Argument structure
            accDescr: A reason supports a conclusion.
            A --&gt; B
            </code></pre>
            <pre dir="ltr" data-source-utf16-start="119" data-source-utf16-end="155"><code dir="ltr" class="language-mermaid">not-a-diagram
            </code></pre>
            """#
        let harness = ReadHarness(
            source: source,
            htmlBody: htmlBody,
            fingerprint: DocumentFingerprint(content: source).sha256,
            initialAnchor: nil,
            initialScrollFraction: 0
        )
        defer { harness.close() }
        try await harness.waitUntilReady()
        let diagramSize = try #require(harness.diagramSize)
        #expect(diagramSize.width > 0 && diagramSize.height > 0)
        let result = try #require(
            try await harness.callBridgeJavaScript(
                """
                const familySources = [
                  'sequenceDiagram\\nA->>B: Reason',
                  'stateDiagram-v2\\n[*] --> Draft',
                  'classDiagram\\nClaim <|-- Objection',
                  'erDiagram\\nCLAIM ||--o{ REASON : has',
                  'mindmap\\n  root((Argument))\\n    Reason\\n    Objection'
                ];
                let staticFamilyCount = 0;
                for (const source of familySources) {
                  const rendered = await window.scholiumMermaid.render({source});
                  if (rendered.ok) staticFamilyCount += 1;
                }
                const architectureSecurityResult = await window.scholiumMermaid.render({
                  source: [
                    'architecture-beta',
                    '  group mermaidPrototypePollutionMarker(cloud)[Marker]',
                    '  service a(server)[A] in __proto__',
                    '  service b(server)[B] in mermaidPrototypePollutionMarker',
                    '  a:R -- L:b'
                  ].join('\\n')
                });
                const prototypePolluted = Object.prototype.hasOwnProperty.call(
                  Object.prototype,
                  'mermaidPrototypePollutionMarker'
                );
                delete Object.prototype.mermaidPrototypePollutionMarker;
                const outputs = [...document.querySelectorAll('.scholium-mermaid-output')];
                const shadowRoots = outputs.map(output => output.shadowRoot).filter(Boolean);
                return {
                  runtime: window.scholiumMermaid?.version || 0,
                  staticFamilyCount,
                  pele: shadowRoots.every(root => !!root.querySelector("svg.pele")),
                  architectureSecuritySettled: typeof architectureSecurityResult?.ok === 'boolean',
                  prototypePolluted,
                  rendered: shadowRoots.filter(root => root.querySelector('svg')).length,
                  errors: document.querySelectorAll('.scholium-mermaid-error').length,
                  links: shadowRoots.reduce((count, root) => count + root.querySelectorAll('a').length, 0),
                  scripts: shadowRoots.reduce((count, root) => count + root.querySelectorAll('script').length, 0),
                  visibleFallbacks: [...document.querySelectorAll('.scholium-mermaid-source')]
                    .filter(element => getComputedStyle(element).display !== 'none').length,
                  mapped: document.querySelector('.scholium-mermaid-rendered')?.dataset.sourceUtf16Start || ''
                };
                """
            ) as? [String: Any])
        #expect(result["runtime"] as? Int == 3)
        #expect(result["staticFamilyCount"] as? Int == 5)
        #expect(result["pele"] as? Bool == true)
        #expect(result["architectureSecuritySettled"] as? Bool == true)
        #expect(result["prototypePolluted"] as? Bool == false)
        #expect(result["rendered"] as? Int == 1)
        #expect(result["errors"] as? Int == 1)
        #expect(result["visibleFallbacks"] as? Int == 1)
        #expect(result["links"] as? Int == 0)
        #expect(result["scripts"] as? Int == 0)
        #expect(result["mapped"] as? String == "0")
    }

    @Test("Read HTML template is inert markup with no inline scripts")
    func readHTMLTemplateIsInert() throws {
        let html = SafeMarkdownReadWebView.Coordinator.documentHTML(
            body: "<p>Fixture</p>"
        )

        #expect(!html.contains("<script"))
        #expect(!html.contains("</script>"))
        #expect(html.contains("<style id=\"scholium-presentation-css\"></style>"))
        #expect(html.contains("<style id=\"scholium-user-css\"></style>"))
        #expect(html.contains("script-src 'none'"))
    }

    @Test("Review projects an escaped app-owned title before authored content")
    func readHTMLProjectsDocumentTitleOutsideMarkdown() throws {
        let html = SafeMarkdownReadWebView.Coordinator.documentHTML(
            body: "<h1 aria-level=\"2\">Authored section</h1>",
            documentTitle: "Reasons < Emotion & Value"
        )

        #expect(
            html.contains(
                "class=\"scholium-note-title\" role=\"heading\" aria-level=\"1\""
            ))
        #expect(html.contains("Reasons &lt; Emotion &amp; Value"))
        #expect(html.contains("data-scholium-protected=\"note-title\""))
        let titleRange = try #require(html.range(of: "scholium-note-title"))
        let sectionRange = try #require(html.range(of: "Authored section"))
        #expect(titleRange.lowerBound < sectionRange.lowerBound)

        let emptyHTML = SafeMarkdownReadWebView.Coordinator.documentHTML(
            body: "",
            documentTitle: "Empty Argument"
        )
        #expect(!emptyHTML.contains("scholium-document-attachment-mount"))
        #expect(emptyHTML.contains("scholium-document-empty-state"))
        #expect(emptyHTML.contains("This note has no body content."))
    }

    @Test("Read loads its packaged prose font through the allowlisted scheme")
    func readLoadsAllowlistedPackagedFont() async throws {
        let source = "# Exact\n\nA rendered claim.\n"
        let document = NoteDocument(relativePath: "Font.md", rawContent: source)
        let harness = ReadHarness(
            source: source,
            htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: document.fingerprint.sha256,
            initialAnchor: nil,
            initialScrollFraction: 0
        )
        defer { harness.close() }

        try await harness.waitUntilReady()
        let loaded =
            try await harness.callBridgeJavaScript(
                "return document.fonts.check('16px Alegreya');"
            ) as? Bool
        #expect(loaded == true)
    }

    @Test("Read treats hostile CSS bytes as inert style text")
    func readHostileUserCSSCannotCreateNodes() async throws {
        let hostile = "</style><script id=\"scholium-proof\">0</script><style>"
        let source = "A claim.\n"
        let document = NoteDocument(relativePath: "Hostile.md", rawContent: source)
        let harness = ReadHarness(
            source: source,
            htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: DocumentFingerprint(content: source).sha256,
            initialAnchor: nil,
            initialScrollFraction: 0,
            userCSS: hostile
        )
        defer { harness.close() }
        try await harness.waitUntilReady()

        let page = try #require(
            try await harness.callPageJavaScript(
                """
                return {
                  scripts: document.querySelectorAll('script').length,
                  proof: document.getElementById('scholium-proof') !== null,
                  pageHandler: Boolean(window.webkit
                    && window.webkit.messageHandlers
                    && window.webkit.messageHandlers.scholiumRead)
                };
                """
            ) as? [String: Any])
        #expect(page["scripts"] as? Int == 0)
        #expect(page["proof"] as? Bool == false)
        #expect(page["pageHandler"] as? Bool == false)

        let bridge = try #require(
            try await harness.callBridgeJavaScript(
                """
                return {
                  ready: window.scholiumReadReady instanceof Promise,
                  handler: Boolean(window.webkit
                    && window.webkit.messageHandlers
                    && window.webkit.messageHandlers.scholiumRead),
                  appliedCSS: document.getElementById('scholium-user-css')?.textContent || ''
                };
                """
            ) as? [String: Any])
        #expect(bridge["ready"] as? Bool == true)
        #expect(bridge["handler"] as? Bool == true)
        #expect(bridge["appliedCSS"] as? String == hostile)
    }

    @Test("Read scroll observation does not replay one-shot restoration")
    func readScrollObservationDoesNotReplayRestoration() async throws {
        let fixture = Self.longDocumentFixture()
        let fingerprint = DocumentFingerprint(content: fixture.source).sha256
        let anchor = EditorScrollAnchor(
            sourceFingerprint: fingerprint,
            sourceUTF16Offset: fixture.anchorLowerBound,
            blockUTF16LowerBound: fixture.anchorLowerBound,
            blockUTF16UpperBound: fixture.anchorUpperBound,
            relativeBlockPosition: 0,
            fallbackFraction: 0.65
        )
        let harness = ReadHarness(
            source: fixture.source,
            htmlBody: fixture.htmlBody,
            fingerprint: fingerprint,
            initialAnchor: anchor,
            initialScrollFraction: 0
        )
        defer { harness.close() }
        var stage = "initial readiness"
        do {
            try await harness.waitUntilReady()
            stage = "initial runtime and one-shot anchor"
            let mermaidRuntime =
                try await harness.callBridgeJavaScript(
                    "return window.scholiumMermaid?.version || 0"
                ) as? Int
            #expect(mermaidRuntime == 0)
            _ = try await harness.waitUntilCapturedAnchor(stage: "initial one-shot restore") {
                $0.blockUTF16LowerBound == fixture.anchorLowerBound
                    && $0.blockUTF16UpperBound == fixture.anchorUpperBound
            }
            let registry = try await harness.scrollRegistrySnapshot()
            #expect(registry.count > 80)
            #expect(registry.visualOrderIsMonotonic)

            stage = "consumed request reapplication"
            let consumedCount = try await harness.restoreInvocationCount()
            harness.reapplyCurrentRestoreRequest()
            try await Task.sleep(for: .milliseconds(150))
            let countAfterReapplication = try await harness.restoreInvocationCount()
            #expect(countAfterReapplication == consumedCount)
            harness.clearRestoreRequest()

            stage = "scroll observation without restoration"
            try await harness.scroll(toFraction: 0.2)
            try await Task.sleep(for: .milliseconds(250))
            let countAfterObservation = try await harness.restoreInvocationCount()
            #expect(countAfterObservation == consumedCount)

            let observedBeforeRebuild = harness.latestObservedScrollPosition
            let observedAnchor = try #require(observedBeforeRebuild.anchor)
            stage = "rebuild readiness"
            harness.recreateSurface()
            try await harness.waitUntilReady()
            stage = "rebuild semantic anchor"
            let rebuiltAnchor = try await harness.waitUntilCapturedAnchor(stage: "WebView rebuild") {
                $0.blockUTF16LowerBound == observedAnchor.blockUTF16LowerBound
                    && $0.blockUTF16UpperBound == observedAnchor.blockUTF16UpperBound
            }
            #expect(rebuiltAnchor.sourceFingerprint == fingerprint)

            stage = "rapid presentation revisions"
            try await harness.applyRapidPresentationRevisions()

            stage = "source-line rebuild readiness"
            harness.recreateSurface(
                restoring: anchor,
                fallbackFraction: 0.65,
                targetSourceLine: 3
            )
            try await harness.waitUntilReady()
            stage = "initial source-line request"
            try await harness.waitUntilSourceLineReached(3)
            let requestedLineTop = try await harness.sourceLineTop(3)
            #expect(abs(requestedLineTop) <= 16)
            let requestedLineRange = try await harness.sourceLineRange(3)
            let observedAfterSourceLine = harness.latestObservedScrollPosition
            let sourceLineAnchor = try #require(observedAfterSourceLine.anchor)
            #expect(sourceLineAnchor.blockUTF16LowerBound == requestedLineRange.lowerBound)
            #expect(sourceLineAnchor.blockUTF16UpperBound == requestedLineRange.upperBound)
            #expect(sourceLineAnchor.fallbackFraction == observedAfterSourceLine.fraction)

            // A consumed locator must not suppress a later navigation to the same
            // source line in the retained Review page.
            stage = "repeated source-line request"
            try await harness.scroll(toFraction: 0.7)
            harness.requestSourceLine(3)
            try await harness.waitUntilSourceLineReached(3)
            #expect(abs(try await harness.sourceLineTop(3)) <= 16)

            stage = "fallback restoration"
            let beforeFallbackRestore = try await harness.restoreInvocationCount()
            harness.apply(initialAnchor: nil, fallbackFraction: 0.55)
            _ = try await harness.waitUntilCapturedAnchor(stage: "fallback restore") {
                $0.fallbackFraction > 0.4
            }
            let afterFallbackRestore = try await harness.restoreInvocationCount()
            #expect(afterFallbackRestore == beforeFallbackRestore + 1)
            stage = "cleanup"
            await harness.closeAndDrain()
        } catch {
            await harness.emitScrollRestorationFailure(stage: stage, error: error)
            Issue.record(Comment(rawValue: "Read scroll restoration journey failed during \(stage): \(error)"))
            throw error
        }
    }

    @Test("Review preserves the visible document title at the document start")
    func reviewDocumentStartAnchorKeepsTitleVisible() async throws {
        let source =
            "# First section\n\n"
            + (1...80)
            .map { "Research paragraph \($0) remains available." }
            .joined(separator: "\n\n") + "\n"
        let document = NoteDocument(relativePath: "Reasons.md", rawContent: source)
        let headingUpperBound = source.firstIndex(of: "\n")?.utf16Offset(in: source) ?? 0
        let anchor = EditorScrollAnchor(
            sourceFingerprint: document.fingerprint.sha256,
            sourceUTF16Offset: 0,
            blockUTF16LowerBound: 0,
            blockUTF16UpperBound: headingUpperBound,
            relativeBlockPosition: 0,
            fallbackFraction: 0
        )
        let harness = ReadHarness(
            source: source,
            htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: document.fingerprint.sha256,
            initialAnchor: anchor,
            initialScrollFraction: 0,
            documentTitle: "Reasons and Emotional Attitudes"
        )
        defer { harness.close() }
        try await harness.waitUntilReady()
        try await Task.sleep(for: .milliseconds(150))

        let result = try #require(
            try await harness.callPageJavaScript(
                """
                const title = document.querySelector('.scholium-note-title');
                if (!title) return null;
                const bounds = title.getBoundingClientRect();
                return {
                  scrollY: window.scrollY,
                  titleTop: bounds.top,
                  titleBottom: bounds.bottom
                };
                """
            ) as? [String: Any])
        let scrollY = (result["scrollY"] as? NSNumber)?.doubleValue ?? 100
        let titleTop = (result["titleTop"] as? NSNumber)?.doubleValue ?? 10_000
        let titleBottom = (result["titleBottom"] as? NSNumber)?.doubleValue ?? 0
        #expect(abs(scrollY) < 0.5)
        #expect(titleTop >= 0)
        #expect(titleBottom > 0)
        await harness.closeAndDrain()
    }

    @Test("Review places the app title before quiet authored YAML and the body", arguments: ["", "\n", " \t\n"])
    func reviewFrontmatterFollowsDocumentTitle(bodyBlankLine: String) async throws {
        let source =
            "---\ntitle: Fixture\nsummary: Read in place\n---\n" + bodyBlankLine + "# First section\n\n"
            + (1...40).map { "Research paragraph \($0) remains available." }
            .joined(separator: "\n\n") + "\n"
        let document = NoteDocument(relativePath: "Frontmatter.md", rawContent: source)
        let harness = ReadHarness(
            source: source,
            htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: document.fingerprint.sha256,
            initialAnchor: nil,
            initialScrollFraction: 0,
            documentTitle: "Fixture"
        )
        defer { harness.close() }
        try await harness.waitUntilReady()
        try await Task.sleep(for: .milliseconds(150))

        let result = try #require(
            try await harness.callPageJavaScript(
                """
                const scroller = document.scrollingElement;
                const frontmatter = document.querySelector('.scholium-frontmatter-source');
                const title = document.querySelector('.scholium-note-title');
                if (!scroller || !frontmatter || !title) return null;
                const titleBounds = title.getBoundingClientRect();
                const frontmatterBounds = frontmatter.getBoundingClientRect();
                const firstHeading = document.querySelector('#scholium-document > h1');
                const headingBounds = firstHeading?.getBoundingClientRect();
                const delimiters = Array.from(frontmatter.querySelectorAll('.scholium-frontmatter-delimiter-line'));
                return {
                  scrollY: window.scrollY,
                  frontmatterTop: frontmatterBounds.top,
                  frontmatterBottom: frontmatterBounds.bottom,
                  titleTop: titleBounds.top,
                  titleBottom: titleBounds.bottom,
                  headingTop: headingBounds?.top ?? -1,
                  yamlKeyCount: frontmatter.querySelectorAll('.cm-live-yaml-key').length,
                  yamlStringCount: frontmatter.querySelectorAll('.cm-live-yaml-string').length,
                  preservesBodyBlankLine: frontmatter.classList.contains('scholium-frontmatter-followed-by-blank-line'),
                  delimitersQuiet: delimiters.every(element => {
                    const style = getComputedStyle(element);
                    return element.getBoundingClientRect().height > 0.5
                      && style.display === 'block'
                      && style.opacity === '0';
                  })
                };
                """
            ) as? [String: Any])
        let scrollY = (result["scrollY"] as? NSNumber)?.doubleValue ?? 100
        let frontmatterTop = (result["frontmatterTop"] as? NSNumber)?.doubleValue ?? -10_000
        let frontmatterBottom = (result["frontmatterBottom"] as? NSNumber)?.doubleValue ?? 0
        let titleTop = (result["titleTop"] as? NSNumber)?.doubleValue ?? 0
        let titleBottom = (result["titleBottom"] as? NSNumber)?.doubleValue ?? 0
        let headingTop = (result["headingTop"] as? NSNumber)?.doubleValue ?? -1
        let yamlKeyCount = (result["yamlKeyCount"] as? NSNumber)?.intValue ?? 0
        let yamlStringCount = (result["yamlStringCount"] as? NSNumber)?.intValue ?? 0
        let delimitersQuiet = result["delimitersQuiet"] as? Bool ?? false
        #expect(abs(scrollY) < 0.5)
        #expect(frontmatterTop >= 0)
        #expect(titleTop < frontmatterTop)
        #expect(titleBottom <= frontmatterTop)
        #expect(frontmatterBottom <= headingTop)
        #expect(yamlKeyCount == 2)
        #expect(yamlStringCount == 0)
        #expect(result["preservesBodyBlankLine"] as? Bool == !bodyBlankLine.isEmpty)
        #expect(delimitersQuiet)
        await harness.closeAndDrain()
    }

    @Test("Review keeps punctuation with an interactive footnote locator")
    func reviewFootnoteLocatorDoesNotOrphanPunctuation() async throws {
        let source = "A philosophical claim[^note].\n\n[^note]: Supporting qualification.\n"
        let document = NoteDocument(relativePath: "Footnote.md", rawContent: source)
        let harness = ReadHarness(
            source: source,
            htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: document.fingerprint.sha256,
            initialAnchor: nil,
            initialScrollFraction: 0
        )
        defer { harness.close() }
        try await harness.waitUntilReady()

        let result = try #require(
            try await harness.callPageJavaScript(
                """
                const paragraph = document.querySelector('#scholium-document > p');
                const reference = paragraph?.querySelector('.footnote-reference-wrap');
                if (!paragraph || !reference) return null;
                const walker = document.createTreeWalker(paragraph, NodeFilter.SHOW_TEXT);
                let punctuationNode = null;
                while (walker.nextNode()) {
                  const node = walker.currentNode;
                  if ((reference.compareDocumentPosition(node) & Node.DOCUMENT_POSITION_FOLLOWING)
                      && (node.nodeValue || '').includes('.')) {
                    punctuationNode = node;
                    break;
                  }
                }
                if (!punctuationNode) return null;
                const punctuationOffset = punctuationNode.nodeValue.indexOf('.');
                const punctuationRange = document.createRange();
                punctuationRange.setStart(punctuationNode, punctuationOffset);
                punctuationRange.setEnd(punctuationNode, punctuationOffset + 1);
                paragraph.style.inlineSize = '360px';
                const sameLineOffset = punctuationRange.getBoundingClientRect().top
                  - reference.getBoundingClientRect().top;
                const lineHeight = Number.parseFloat(getComputedStyle(paragraph).lineHeight) || 20;
                let orphanWidth = 0;
                for (let width = 48; width <= 360; width += 1) {
                  paragraph.style.inlineSize = width + 'px';
                  const referenceTop = reference.getBoundingClientRect().top;
                  const punctuationTop = punctuationRange.getBoundingClientRect().top;
                  if (punctuationTop - referenceTop > sameLineOffset + lineHeight / 2) {
                    orphanWidth = width;
                    break;
                  }
                }
                paragraph.style.inlineSize = '';
                const style = getComputedStyle(paragraph);
                return {
                  orphanWidth,
                  lineBreak: style.lineBreak,
                  wordBreak: style.wordBreak,
                  overflowWrap: style.overflowWrap
                };
                """
            ) as? [String: Any])
        #expect(result["orphanWidth"] as? Int == 0, Comment(rawValue: "\(result)"))
        #expect(result["lineBreak"] as? String == "auto")
        #expect(result["wordBreak"] as? String == "normal")
        #expect(result["overflowWrap"] as? String == "break-word")
        await harness.closeAndDrain()
    }

    // Needs scroll bars configured as a Mac with a pointing device configures them.
    @Test("Review suppresses only overlay scroll bars during viewport reflow", .enabled(if: ScholiumTestEnvironment.providesDisplayEvidence))
    func reviewSuppressesOverlayScrollBarDuringViewportReflow() async throws {
        let fixture = Self.longDocumentFixture()
        let harness = ReadHarness(
            source: fixture.source,
            htmlBody: fixture.htmlBody,
            fingerprint: DocumentFingerprint(content: fixture.source).sha256,
            initialAnchor: nil,
            initialScrollFraction: 0
        )
        defer { harness.close() }
        try await harness.waitUntilReady()
        try await harness.scroll(toFraction: 0.4)
        try await Task.sleep(for: .milliseconds(250))

        let before = try await harness.viewportScrollBarSnapshot()
        #expect(!before.isSuppressed)
        #expect(before.scrollBarWidth == "auto")

        harness.resize(width: 470, height: 420, duration: 0.6)
        try await Task.sleep(for: .milliseconds(120))
        let during = try await harness.viewportScrollBarSnapshot()
        #expect(during.usesOverlayScrollBar)
        #expect(during.isSuppressed)
        #expect(during.scrollBarWidth == "none")

        try await harness.waitUntilViewportScrollBarRestored()
        let after = try await harness.viewportScrollBarSnapshot()
        #expect(!after.isSuppressed)
        #expect(after.scrollBarWidth == "auto")

        try await harness.scroll(toFraction: 0.65)
        try await Task.sleep(for: .milliseconds(250))
        let scrolled = try await harness.viewportScrollBarSnapshot()
        #expect(abs(scrolled.scrollY - after.scrollY) > 1)
        #expect(!scrolled.isSuppressed)
        await harness.closeAndDrain()
    }

    @Test("Read preparation keeps a real viewport while native input and accessibility are blocked")
    func readPreparationKeepsViewportWithoutInput() async throws {
        let source = "---\nunknown: 字😀\n---\n# Authored heading\n\nA real paragraph with 中文 and exact content.\n"
        let harness = ReadHarness(
            source: source,
            htmlBody: "<h1>Authored heading</h1><p>A real paragraph with 中文 and exact content.</p>",
            fingerprint: DocumentFingerprint(content: source).sha256,
            initialAnchor: nil,
            initialScrollFraction: 0,
            documentTitle: "Preparing sample",
            testingScrollRestoreDelayMilliseconds: 1500,
            presentsDocumentPreparation: true
        )
        defer { harness.close() }
        try await harness.waitUntilReadPreparationAvailable()
        let before = try await harness.preparationSnapshot()
        #expect(!harness.isReady)
        #expect(!before.isHidden && before.width >= 500 && before.height >= 300)
        #expect(!before.allowsInput && !before.acceptsPointer && before.accessibleChildCount == 0)
        #expect(before.geometry.count >= 4)
        #expect(before.geometry.allSatisfy { $0.count == 4 && $0[2] > 0 && $0[3] > 0 })
        try await harness.waitUntilReady()
        try await harness.waitUntilNativeInputIsEnabled()
        let after = try await harness.preparationSnapshot()
        #expect(after.allowsInput && after.acceptsPointer && after.accessibleChildCount == 1)
        #expect(after.geometry.count == before.geometry.count)
        for (actual, expected) in zip(after.geometry, before.geometry) {
            #expect(actual.count == expected.count)
            for (value, original) in zip(actual, expected) { #expect(abs(value - original) <= 0.5) }
        }
        await harness.closeAndDrain()
    }

    @Test("Read opening settles a late image before acknowledging its explicit locator")
    func readOpeningImageGeometryKeepsExplicitLocator() async throws {
        let source =
            "# Opening\n\n![Figure](Attachments/figure.png)\n\n"
            + (1...40).map { "Following paragraph \($0) remains authored content.\n\n" }.joined()
        let document = NoteDocument(relativePath: "Opening.md", rawContent: source)
        let landscape = try InlineImageFixture.landscapePNG.image()
        let portrait = try InlineImageFixture.portraitJPEG.image()
        let rendered = SafeMarkdownRenderer.render(document, embeddedImages: ["Attachments/figure.png": landscape])
        let harness = ReadHarness(
            source: source, htmlBody: rendered.htmlBody, fingerprint: document.fingerprint.sha256,
            initialAnchor: nil, initialScrollFraction: 0.8,
            testingScrollRestoreDelayMilliseconds: 1500, presentsDocumentPreparation: true)
        defer { harness.close() }
        harness.requestSourceLine(3)
        try await harness.waitUntilReadPreparationAvailable()
        _ = try await harness.callBridgeJavaScript(
            """
            const originalDecode = HTMLImageElement.prototype.decode;
            let heldDecode;
            let replacementInstalled = false;
            HTMLImageElement.prototype.decode = function() {
              if (this.dataset.scholiumImageTarget !== 'Attachments/figure.png' || replacementInstalled) {
                return originalDecode.call(this);
              }
              if (heldDecode) return heldDecode;
              window.readOpeningDecodeHeld = true;
              heldDecode = new Promise(resolve => {
                window.releaseReadOpeningImage = async () => {
                  // Readiness rechecks a changed src. Hold only the original
                  // resource; every decode of its replacement must really finish.
                  replacementInstalled = true;
                  this.src = replacementURL;
                  await originalDecode.call(this);
                  resolve();
                };
              });
              return heldDecode;
            };
            """,
            arguments: ["replacementURL": "data:\(portrait.mimeType);base64,\(portrait.data.base64EncodedString())"])
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while try await harness.callBridgeJavaScript("return window.readOpeningDecodeHeld === true;") as? Bool != true {
            if clock.now >= deadline { throw ScholiumWindowLifecycleError.timedOut(.routeReadiness) }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!harness.isReady)
        #expect(harness.pendingSourceLine == 3)
        _ = try await harness.callBridgeJavaScript("await window.releaseReadOpeningImage();")
        try await harness.waitUntilReady()
        try await harness.waitUntilSourceLineReached(3)
        #expect(harness.pendingSourceLine == nil)
        #expect(abs(try await harness.sourceLineTop(3)) <= 16)
        #expect(try await harness.callBridgeJavaScript("return document.querySelector('img').naturalHeight;") as? Int == InlineImageFixture.portraitJPEG.height)
        await harness.closeAndDrain()
    }

    @Test("Read caller restoration can be cancelled without cancelling rebuild restoration")
    func readCallerRestorationCancellationIsScoped() async throws {
        let fixture = Self.longDocumentFixture()
        let fingerprint = DocumentFingerprint(content: fixture.source).sha256
        let anchor = EditorScrollAnchor(
            sourceFingerprint: fingerprint,
            sourceUTF16Offset: fixture.anchorLowerBound,
            blockUTF16LowerBound: fixture.anchorLowerBound,
            blockUTF16UpperBound: fixture.anchorUpperBound,
            relativeBlockPosition: 0,
            fallbackFraction: 0.65
        )
        let harness = ReadHarness(
            source: fixture.source,
            htmlBody: fixture.htmlBody,
            fingerprint: fingerprint,
            initialAnchor: anchor,
            initialScrollFraction: 0,
            testingScrollRestoreDelayMilliseconds: 300
        )
        defer { harness.close() }

        try await harness.waitUntilWebViewAvailable()
        harness.clearRestoreRequest()
        try await harness.waitUntilReady()
        #expect(try await harness.restoreInvocationCount() == 0)
        #expect(!harness.hasPendingRestoreRequest)

        try await harness.scroll(toFraction: 0.3)
        try await Task.sleep(for: .milliseconds(250))
        let observedAnchor = try #require(harness.latestObservedScrollPosition.anchor)
        harness.recreateSurface()
        try await harness.waitUntilReady()
        let rebuiltAnchor = try await harness.waitUntilCapturedAnchor(stage: "coordinator rebuild") {
            $0.blockUTF16LowerBound == observedAnchor.blockUTF16LowerBound
                && $0.blockUTF16UpperBound == observedAnchor.blockUTF16UpperBound
        }
        #expect(rebuiltAnchor.sourceFingerprint == fingerprint)
        await harness.closeAndDrain()
    }

    @Test("Read finalization failure keeps restoration pending and can retry")
    func readFinalizationFailureDoesNotAcknowledgeRestoration() async throws {
        let fixture = Self.longDocumentFixture()
        let fingerprint = DocumentFingerprint(content: fixture.source).sha256
        let anchor = EditorScrollAnchor(
            sourceFingerprint: fingerprint,
            sourceUTF16Offset: fixture.anchorLowerBound,
            blockUTF16LowerBound: fixture.anchorLowerBound,
            blockUTF16UpperBound: fixture.anchorUpperBound,
            relativeBlockPosition: 0,
            fallbackFraction: 0.65
        )
        let harness = ReadHarness(
            source: fixture.source,
            htmlBody: fixture.htmlBody,
            fingerprint: fingerprint,
            initialAnchor: anchor,
            initialScrollFraction: 0,
            testingForcesFinalizationFailure: true
        )
        defer { harness.close() }

        try await harness.waitUntilFailure()
        #expect(!harness.isReady)
        #expect(harness.hasPendingRestoreRequest)
        #expect(try await harness.restoreInvocationCount() >= 1)

        harness.retryAfterFinalizationFailure()
        try await harness.waitUntilReady()
        #expect(!harness.hasPendingRestoreRequest)
        await harness.closeAndDrain()
    }

    @Test("A finalized retained Read page re-acknowledges reconstructed caller state")
    func finalizedReadPageReacknowledgesCallerReadiness() async throws {
        let source = "# Retained Review\n\nThe finalized page stays authoritative.\n"
        let document = NoteDocument(
            relativePath: "ReadFixture.md",
            rawContent: source
        )
        let harness = ReadHarness(
            source: source,
            htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: document.fingerprint.sha256,
            initialAnchor: nil,
            initialScrollFraction: 0
        )
        defer { harness.close() }

        try await harness.waitUntilReady()
        let webViewIdentity = try harness.webViewIdentity()
        #expect(
            try harness.webViewAccessibilityIdentifier()
                == "scholium.renderedDocument.ReadFixture.md"
        )

        harness.forgetCallerReadiness()
        try await harness.waitUntilReady()

        #expect(try harness.webViewIdentity() == webViewIdentity)
        #expect(
            try harness.webViewAccessibilityIdentifier()
                == "scholium.renderedDocument.ReadFixture.md"
        )
        await harness.closeAndDrain()
    }

    @Test("Explicit Review selection inquiry restores a dismissed or offscreen selection", arguments: [false, true])
    func reviewExplicitSelectionInquiryAfterEscape(offscreen: Bool) async throws {
        let text = "A source-owned claim 中文 😀 é for discussion."
        let source = "---\nkind: topic\n---\n\n" + text + "\n\n" + String(repeating: "Surrounding synthetic paragraph.\n\n", count: 40)
        let document = NoteDocument(relativePath: "Selection.md", rawContent: source)
        var captured: [AgentChatSelectionInquiry] = []
        let harness = ReadHarness(
            source: source, htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: document.fingerprint.sha256,
            initialAnchor: nil, initialScrollFraction: 0, laysOutForNativePreview: true,
            onAskAgent: { inquiry, validate in
                guard await validate() else { throw CancellationError() }
                captured.append(inquiry)
                return nil
            })
        defer { harness.close() }
        try await harness.waitUntilReady()
        try await harness.focusDocumentForSelectionActions()
        let pageIdentity = try #require(
            try await harness.callPageJavaScript(
                "return window.__scholiumTestingPageIdentity ??= `${Date.now()}:${Math.random()}`;") as? String)
        let selection = try await harness.selectVisibleText(text)
        let snapshot = try #require(MarkdownReviewSourceSelection.review(selection, source: source))
        #expect(snapshot.excerpt == text)
        try await harness.waitForSelectionActionState(stage: "native Review selection toolbar") {
            harness.nativeSelectionActionBar() != nil
        }
        _ = try await harness.callBridgeJavaScript(
            "document.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true, cancelable: true}));")
        try await harness.waitForSelectionActionState(stage: "Escape dismissed Review toolbar") {
            harness.nativeSelectionActionBar() == nil
        }
        #expect(try await harness.callPageJavaScript("return window.getSelection()?.toString();") as? String == text)
        if offscreen { try await harness.scroll(toFraction: 1) }
        // The actual coordinator awaits its JS operation then immediately
        // invokes the native owner, without waiting separately for admission.
        let invoked = try await harness.presentSelectionInquiry(.explain)
        #expect(invoked, Comment(rawValue: harness.selectionActionNativeState))
        guard invoked else { return }
        try await harness.waitForSelectionActionState(stage: "fixture Review source handler") {
            captured.count == 1
        }
        #expect(captured == [.explain])
        #expect(
            try await harness.callPageJavaScript(
                "const rect = window.getSelection().getRangeAt(0).getBoundingClientRect(); return rect.bottom >= 0 && rect.top <= window.innerHeight;") as? Bool
                == true)
        #expect(try await harness.callPageJavaScript("return window.getSelection()?.toString();") as? String == text)
        #expect(try await harness.callPageJavaScript("return window.__scholiumTestingPageIdentity;") as? String == pageIdentity)
        await harness.closeAndDrain()
    }

    @Test("Review footnotes preview, navigate, and return")
    func reviewFootnotesOwnInteraction() async throws {
        let previewSource = "First claim[^one], then another claim[^one].\n\n[^one]: Basis.\n"
        let source = previewSource + "\n\n" + String(repeating: "Synthetic surrounding paragraph.\n\n", count: 24)
        let document = NoteDocument(relativePath: "Footnotes.md", rawContent: source)
        let harness = ReadHarness(
            source: source,
            htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: DocumentFingerprint(content: source).sha256,
            initialAnchor: nil,
            initialScrollFraction: 0,
            laysOutForNativePreview: true
        )
        defer { harness.close() }
        try await harness.waitUntilReady()

        _ = try await harness.callBridgeJavaScript(
            "document.querySelectorAll('.footnote-reference')[1].dispatchEvent(new PointerEvent('pointerover', {bubbles: true}));")
        try await harness.waitForNativePreview(title: "Footnote 1")
        #expect(
            try await harness.callPageJavaScript(
                "return document.querySelectorAll('.footnote-reference')[1].getAttribute('aria-expanded');"
            ) as? String == "true"
        )
        #expect(try await harness.callNativePreview("return document.body.textContent.includes('Basis.');") as? Bool == true)
        _ = try await harness.callPageJavaScript("window.dispatchEvent(new Event('scroll'));")
        try await harness.waitForNativePreview(visible: false)
        #expect(
            try await harness.callPageJavaScript(
                "return document.querySelectorAll('.footnote-reference')[1].getAttribute('aria-expanded');"
            ) as? String == "false"
        )
        _ = try await harness.callPageJavaScript("document.querySelectorAll('.footnote-reference')[1].focus({preventScroll: true});")
        try await harness.waitForNativePreview(title: "Footnote 1")
        #expect(
            try await harness.callPageJavaScript(
                "return document.querySelectorAll('.footnote-reference')[1].getAttribute('aria-expanded');"
            ) as? String == "true"
        )
        _ = try await harness.callPageJavaScript("document.querySelectorAll('.footnote-reference')[1].blur();")
        try await harness.waitForNativePreview(visible: false)
        #expect(
            try await harness.callPageJavaScript(
                "return document.querySelectorAll('.footnote-reference')[1].getAttribute('aria-expanded');"
            ) as? String == "false"
        )
        let navigation = try #require(
            try await harness.callBridgeJavaScript(
                """
                const reference = document.querySelectorAll('.footnote-reference')[1];
                const origin = reference.closest('.footnote-reference-wrap');
                const definition = document.getElementById(reference.dataset.target);
                const back = definition.querySelector('.footnote-return');
                let navigated = false, returned = false;
                definition.scrollIntoView = () => { navigated = true; };
                origin.scrollIntoView = () => { returned = true; };
                reference.click();
                const definitionFocused = document.activeElement === definition;
                back.click();
                return {origin: origin.id, navigated, returned, definitionFocused,
                        referenceFocused: document.activeElement === reference};
                """) as? [String: Any])
        #expect(navigation["origin"] as? String == "fnref-1-2")
        for key in ["navigated", "returned", "definitionFocused", "referenceFocused"] {
            #expect(navigation[key] as? Bool == true)
        }
        await harness.closeAndDrain()
    }

    @Test("Review link previews converge when graph revisions arrive before the reader API is installed")
    func reviewLinkPreviewsConvergeDuringInitialPreparation() async throws {
        var source = ""
        var anchorLowerBound = 0
        for index in 0..<24 {
            if index == 12 {
                anchorLowerBound = source.utf16.count
                source += "[[Target]]\n\n"
            }
            source += "Synthetic surrounding paragraph \(index) preserves its exact source position.\n\n"
        }
        for index in 0..<10 {
            source += "```mermaid\nflowchart LR\n  A\(index)[Start] --> B\(index)[Finish]\n```\n\n"
        }
        let document = NoteDocument(relativePath: "ReadFixture.md", rawContent: source)
        let rendered = SafeMarkdownRenderer.render(document)
        let target = try #require(rendered.semanticDocument.links.first { $0.syntax == .wikilink })
        let anchor = EditorScrollAnchor(
            sourceFingerprint: document.fingerprint.sha256,
            sourceUTF16Offset: anchorLowerBound,
            blockUTF16LowerBound: anchorLowerBound,
            blockUTF16UpperBound: anchorLowerBound + "[[Target]]".utf16.count,
            relativeBlockPosition: 0, fallbackFraction: 0.3)
        let harness = ReadHarness(
            source: source, htmlBody: rendered.htmlBody, fingerprint: document.fingerprint.sha256,
            initialAnchor: anchor, initialScrollFraction: 0,
            presentsDocumentPreparation: true, laysOutForNativePreview: true,
            pageExtension: PreviewPreparationGatePage())
        defer { harness.close() }
        try await harness.waitUntilReadPreparationAvailable()
        #expect(!harness.isReady)

        // The fixture installs its gate at document start, before any reader
        // initialization can finish. No native polling interval orders setup.
        // Hold the real pending Mermaid render while both graph revisions arrive.
        try #require(
            try await harness.callBridgeJavaScript(
                """
                return window.__scholiumPreviewPreparationGate !== undefined
                  && typeof window.scholiumSetLinkPreviews === 'undefined';
                """) as? Bool == true)
        let pageIdentity = try #require(
            try await harness.callPageJavaScript("return window.__scholiumTestingPageIdentity ??= `${Date.now()}:${Math.random()}`;") as? String)
        let webViewIdentity = try harness.webViewIdentity()

        @MainActor
        func waitForPendingRevision(_ revision: String) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while true {
                let coordinator = try harness.formatDiagnosticCoordinator()
                let fields = Dictionary(
                    uniqueKeysWithValues: Mirror(reflecting: coordinator).children.compactMap { child in
                        child.label.map { ($0, child.value) }
                    })
                if fields["pageIsReady"] as? Bool == true,
                    fields["desiredLinkPreviewRevision"] as? String == revision,
                    try await harness.callBridgeJavaScript("return window.__scholiumPreviewPreparationGate.entered === true;") as? Bool == true
                {
                    #expect(fields["appliedLinkPreviewRevision"] as? String == "no-previews")
                    #expect(!harness.isReady)
                    #expect(try await harness.callBridgeJavaScript("return typeof window.scholiumSetLinkPreviews === 'undefined';") as? Bool == true)
                    return
                }
                try #require(
                    ContinuousClock.now < deadline, "The current native reader did not receive the graph revision while Mermaid preparation was pending")
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        harness.updateLinkPreviews([Self.linkPreview(at: target.span, title: "First target note")], revision: "graph-1")
        try await waitForPendingRevision("graph-1")
        harness.updateLinkPreviews(
            [Self.linkPreview(at: target.span, title: "Latest target note", htmlBody: "<p>Latest target preview body</p>")], revision: "graph-2")
        try await waitForPendingRevision("graph-2")
        _ = try await harness.callBridgeJavaScript("window.__scholiumPreviewPreparationGate.release();")
        try await harness.waitUntilReady()
        #expect(!harness.hasPendingRestoreRequest)
        let restored = try await harness.waitUntilCapturedAnchor(stage: "preview revision during initial reader preparation") {
            $0.blockUTF16LowerBound == anchor.blockUTF16LowerBound && $0.blockUTF16UpperBound == anchor.blockUTF16UpperBound
        }
        #expect(restored.sourceFingerprint == document.fingerprint.sha256)
        #expect(try harness.webViewIdentity() == webViewIdentity)
        #expect(try await harness.callPageJavaScript("return window.__scholiumTestingPageIdentity;") as? String == pageIdentity)
        #expect(try await harness.callBridgeJavaScript("return configuration.fingerprint;") as? String == document.fingerprint.sha256)
        #expect(try await harness.callBridgeJavaScript("return document.querySelectorAll('.scholium-mermaid-rendered').length;") as? Int == 10)
        // Rendering acknowledgement precedes SwiftUI's native input admission.
        // Synthetic DOM events must observe the same usable boundary as a pointer.
        try await harness.waitUntilNativeInputIsEnabled()
        _ = try await harness.callPageJavaScript(
            "document.querySelector('a.wiki-link')?.dispatchEvent(new PointerEvent('pointerover', {bubbles:true}));")
        try await harness.waitForNativePreview(title: "Latest target note")
        #expect(
            try await harness.callNativePreview("return document.querySelector('.scholium-preview-body')?.textContent || '';") as? String
                == "Latest target preview body")
        #expect(try await harness.callPageJavaScript("return window.__scholiumTestingPageIdentity;") as? String == pageIdentity)
        await harness.closeAndDrain()
    }

    @Test("A rendered footnote Mermaid keeps complete read-only source in its Native preview and retains the original isolated diagram")
    func footnoteMermaidPreviewRetainsSourceFallback() async throws {
        let diagram = "flowchart LR\naccTitle: Synthetic 图 e\u{0301}\naccDescr: Complete original diagram source.\n  A[Start] --> B[Finish]\n"
        let source = "\u{FEFF}A claim[^diagram].\r\n\r\n[^diagram]: Diagram context.\r\n\r\n"
            + "    ```mermaid\r\n"
            + diagram.split(separator: "\n", omittingEmptySubsequences: false).dropLast().map { "    \($0)\r\n" }.joined()
            + "    ```\r\n"
        let document = NoteDocument(relativePath: "ReadFixture.md", rawContent: source)
        let harness = ReadHarness(
            source: source, htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: document.fingerprint.sha256, initialAnchor: nil, initialScrollFraction: 0,
            laysOutForNativePreview: true)
        defer { harness.close() }
        try await harness.waitUntilReady()
        try await harness.waitUntilNativeInputIsEnabled()
        let originalSnapshot = """
            const wrapper = document.querySelector('.footnote-content .scholium-mermaid');
            const shadow = wrapper?.querySelector('.scholium-mermaid-output')?.shadowRoot;
            return {html:wrapper?.outerHTML, shadow:shadow?.innerHTML,
              rendered:wrapper?.classList.contains('scholium-mermaid-rendered') === true,
              svg:!!shadow?.querySelector('svg'), source:wrapper?.querySelector('.scholium-mermaid-source > code')?.textContent};
            """
        let before = try #require(try await harness.callBridgeJavaScript(originalSnapshot) as? [String: Any])
        try #require(before["rendered"] as? Bool == true && before["svg"] as? Bool == true)
        let originalHTML = try #require(before["html"] as? String)
        let originalShadow = try #require(before["shadow"] as? String)
        #expect(before["source"] as? String == diagram)
        let viewport = try #require(try await harness.callPageJavaScript("return [scrollX, scrollY];") as? [Double])
        _ = try await harness.callPageJavaScript("document.querySelector('.footnote-reference').focus({preventScroll: true});")
        try await harness.waitForNativePreview(title: "Footnote 1")
        let preview = try #require(try await harness.callNativePreview("""
            const source = document.querySelector('.scholium-mermaid-source');
            return {source:source?.querySelector('code')?.textContent,
              display:source ? getComputedStyle(source).display : 'missing',
              rendered:!!document.querySelector('.scholium-mermaid-rendered'),
              output:!!document.querySelector('.scholium-mermaid-output'),
              editable:source?.isContentEditable === true};
            """) as? [String: Any])
        #expect(preview["source"] as? String == diagram)
        #expect(preview["display"] as? String == "block")
        #expect(preview["rendered"] as? Bool == false && preview["output"] as? Bool == false)
        #expect(preview["editable"] as? Bool == false)
        let after = try #require(try await harness.callBridgeJavaScript(originalSnapshot) as? [String: Any])
        #expect(after["html"] as? String == originalHTML)
        #expect(after["shadow"] as? String == originalShadow)
        #expect(after["rendered"] as? Bool == true && after["svg"] as? Bool == true)
        #expect(try await harness.callPageJavaScript("return [scrollX, scrollY];") as? [Double] == viewport)
        #expect(document.sourceBytes == Data(source.utf8))
        await harness.closeAndDrain()
    }

    @Test("Standalone late preview mathematics installs in its named world with styles and preserves the source viewport")
    func standaloneLatePreviewMathematicsUsesNamedWorld() async throws {
        let source = "\u{FEFF}[[Target]]\r\n\r\nSynthetic 图 e\u{0301} paragraph.\r\n"
        let sourceBytes = Data(source.utf8)
        let document = NoteDocument(relativePath: "ReadFixture.md", rawContent: source)
        let rendered = SafeMarkdownRenderer.render(document)
        let target = try #require(rendered.semanticDocument.links.first { $0.syntax == .wikilink })
        let harness = ReadHarness(
            source: source, htmlBody: rendered.htmlBody, fingerprint: document.fingerprint.sha256,
            initialAnchor: nil, initialScrollFraction: 0, laysOutForNativePreview: true)
        defer { harness.close() }
        try await harness.waitUntilReady()
        try await harness.waitUntilNativeInputIsEnabled()
        #expect(try await harness.callBridgeJavaScript("return window.scholiumMath?.version === 1;") as? Bool == false)
        #expect(try await harness.callPageJavaScript("return window.scholiumMath?.version === 1;") as? Bool == false)
        #expect(try await harness.callBridgeJavaScript("return getComputedStyle(document.documentElement).getPropertyValue('--scholium-math-css-ready').trim();") as? String == "")
        let pageIdentity = try #require(try await harness.callPageJavaScript("return window.__latePreviewMathIdentity = 'retained';") as? String)
        let viewport = try #require(try await harness.callPageJavaScript("return [window.scrollX, window.scrollY, innerWidth, innerHeight, document.getElementById('scholium-document').getBoundingClientRect().height];") as? [Double])
        let native = try harness.formatDiagnosticCoordinator()
        let beforeFields = Dictionary(uniqueKeysWithValues: Mirror(reflecting: native).children.compactMap { child in child.label.map { ($0, child.value) } })
        #expect(Data(try #require(beforeFields["selectionSource"] as? String).utf8) == sourceBytes)
        let generation = try #require(beforeFields["loadGeneration"] as? UInt64)
        let peer = NoteDocument(relativePath: "Target.md", rawContent: "$$\nx^2 + y^2 = z^2\n$$\n")
        harness.updateLinkPreviews([
            Self.linkPreview(at: target.span, title: "Late mathematics", htmlBody: SafeMarkdownRenderer.render(peer).htmlBody)
        ], revision: "late-math")
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while true {
            let fields = Dictionary(uniqueKeysWithValues: Mirror(reflecting: native).children.compactMap { child in child.label.map { ($0, child.value) } })
            if fields["appliedLinkPreviewRevision"] as? String == "late-math" { break }
            try #require(ContinuousClock.now < deadline, "The Native late preview revision did not converge")
            try await Task.sleep(for: .milliseconds(20))
        }
        // The real named-world Reader requests the production Native loader;
        // no test-provided runtime, renderer, DOM output or event is installed.
        _ = try await harness.callPageJavaScript("document.querySelector('a.wiki-link').focus({preventScroll: true});")
        try await harness.waitForNativePreview(title: "Late mathematics")
        #expect(try await harness.callBridgeJavaScript("return window.scholiumMath?.version === 1;") as? Bool == true)
        #expect(try await harness.callPageJavaScript("return window.scholiumMath?.version === 1;") as? Bool == false)
        #expect(try await harness.callBridgeJavaScript("return document.querySelectorAll('#scholium-lazy-math-css').length;") as? Int == 1)
        #expect(try await harness.callNativePreview("return !!document.querySelector('.scholium-math-rendered .katex');") as? Bool == true)
        #expect(try await harness.callNativePreview("return getComputedStyle(document.querySelector('.katex')).fontFamily.includes('KaTeX_Main');") as? Bool == true)
        #expect(try await harness.callNativePreview("return document.fonts.check('16px KaTeX_Main');") as? Bool == true)
        #expect(try await harness.callPageJavaScript("return window.__latePreviewMathIdentity;") as? String == pageIdentity)
        #expect(try await harness.callPageJavaScript("return [window.scrollX, window.scrollY, innerWidth, innerHeight, document.getElementById('scholium-document').getBoundingClientRect().height];") as? [Double] == viewport)
        let afterFields = Dictionary(uniqueKeysWithValues: Mirror(reflecting: native).children.compactMap { child in child.label.map { ($0, child.value) } })
        #expect(afterFields["loadGeneration"] as? UInt64 == generation)
        #expect(Data(try #require(afterFields["selectionSource"] as? String).utf8) == sourceBytes)
        #expect(document.sourceBytes == sourceBytes)
        await harness.closeAndDrain()
    }

    @Test("Review link previews update without reloading the document page")
    func reviewLinkPreviewsConvergeInPlace() async throws {
        let previewSource = "[[Target]] then [[Unavailable]]\n"
        let source = previewSource + "\n\n" + String(repeating: "Synthetic surrounding paragraph.\n\n", count: 24)
        let document = NoteDocument(relativePath: "PreviewSource.md", rawContent: source)
        let harness = ReadHarness(
            source: source,
            htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: DocumentFingerprint(content: source).sha256,
            initialAnchor: nil,
            initialScrollFraction: 0,
            laysOutForNativePreview: true
        )
        defer { harness.close() }
        try await harness.waitUntilReady()
        let pageIdentity = try #require(
            try await harness.callPageJavaScript(
                "return window.__scholiumTestingPageIdentity ??= `${Date.now()}:${Math.random()}`"
            ) as? String)

        harness.updateLinkPreviews([Self.linkPreview(atUTF16: 0)], revision: "graph-1")
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        var previewTitle = ""
        while previewTitle != "Target note" {
            _ = try await harness.callPageJavaScript("document.querySelector('a.wiki-link')?.dispatchEvent(new PointerEvent('pointerover', {bubbles: true}));")
            previewTitle =
                (try? await harness.callNativePreview("return document.querySelector('.scholium-preview-title')?.textContent || '';")) as? String ?? ""
            if clock.now >= deadline {
                Issue.record("Review did not install the updated link preview in place.")
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(previewTitle == "Target note")
        let retainedIdentity = try #require(
            try await harness.callPageJavaScript(
                "return window.__scholiumTestingPageIdentity"
            ) as? String)
        #expect(retainedIdentity == pageIdentity)
        _ = try await harness.callPageJavaScript(
            """
            const links = document.querySelectorAll('a.wiki-link');
            links[0].dispatchEvent(new PointerEvent('pointerout', {bubbles: true, relatedTarget: links[1]}));
            links[1].dispatchEvent(new PointerEvent('pointerover', {bubbles: true, relatedTarget: links[0]}));
            """)
        try await harness.waitForNativePreview(visible: false)
        _ = try await harness.callPageJavaScript(
            "document.querySelectorAll('a.wiki-link')[1].focus({preventScroll: true});")
        try await harness.waitForNativePreview(visible: false)
        #expect(
            try await harness.callPageJavaScript("return window.__scholiumTestingPageIdentity") as? String == pageIdentity)
        await harness.closeAndDrain()
    }

    @Test("Review updates text presentation in place without reloading the document page")
    func reviewTextPresentationConvergesInPlace() async throws {
        let source =
            "---\ntitle: Zoomed YAML\n---\n\n"
            + (1...40).map { section in
                "## Section \(section)\n\n" + String(repeating: "Scrollable review text.\n\n", count: 4)
            }.joined()
        let document = NoteDocument(relativePath: "TextScale.md", rawContent: source)
        let harness = ReadHarness(
            source: source,
            htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: document.fingerprint.sha256,
            initialAnchor: nil,
            initialScrollFraction: 0
        )
        defer { harness.close() }
        try await harness.waitUntilReady()
        let pageIdentity = try #require(
            try await harness.callPageJavaScript(
                "return window.__scholiumTestingPageIdentity ??= `${Date.now()}:${Math.random()}`"
            ) as? String
        )
        let webViewIdentity = try harness.webViewIdentity()
        let initialFrontmatterFontSize = try #require(
            try await harness.callPageJavaScript(
                "return Number.parseFloat(getComputedStyle(document.querySelector('.scholium-frontmatter-source')).fontSize);"
            ) as? Double
        )

        harness.setPresentationCSS(ScholiumDocumentPresentationConfiguration(textScale: 2).css)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        var textScale = ""
        while textScale != "2.000000em" {
            textScale =
                (try? await harness.callPageJavaScript(
                    "return getComputedStyle(document.documentElement).getPropertyValue('--scholium-document-text-scale').trim();"
                ) as? String) ?? ""
            if clock.now >= deadline {
                Issue.record("Review did not apply the updated text scale in place.")
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(textScale == "2.000000em")
        #expect(harness.isReady)
        #expect(
            try await harness.callPageJavaScript(
                "return window.__scholiumTestingPageIdentity"
            ) as? String == pageIdentity
        )
        #expect(try harness.webViewIdentity() == webViewIdentity)
        let scaledFrontmatterFontSize = try #require(
            try await harness.callPageJavaScript(
                "return Number.parseFloat(getComputedStyle(document.querySelector('.scholium-frontmatter-source')).fontSize);"
            ) as? Double
        )
        #expect(scaledFrontmatterFontSize >= initialFrontmatterFontSize * 1.9)
        await harness.closeAndDrain()
    }

    @Test("Review shares link, preview, and finite embedded Note presentation")
    func reviewLinkAndEmbeddedNotePresentation() async throws {
        let previewSource = "[[Target]] and [External](https://example.com)\n\n![[Embedded]]\n"
        let source = previewSource + "\n\n" + String(repeating: "Synthetic surrounding paragraph.\n\n", count: 24)
        let document = NoteDocument(relativePath: "LinkedDocument.md", rawContent: source)
        let rendered = SafeMarkdownRenderer.render(document)
        let targetLink = try #require(
            rendered.semanticDocument.links.first {
                $0.syntax == .wikilink
            })
        let embeddedLink = try #require(
            rendered.semanticDocument.links.first {
                $0.syntax == .embed
            })
        let previewBody =
            "<h1>Target note</h1>"
            + String(
                repeating: "<p>Scrollable preview content.</p>",
                count: 60
            )
        let embeddedTail = "Complete embedded tail"
        let embeddedBody =
            "<h1>Embedded note</h1>"
            + String(
                repeating: "<p>Complete embedded content.</p>",
                count: 90
            ) + "<p>\(embeddedTail)</p>"
        let harness = ReadHarness(
            source: source,
            htmlBody: rendered.htmlBody,
            fingerprint: DocumentFingerprint(content: source).sha256,
            initialAnchor: nil,
            initialScrollFraction: 0,
            laysOutForNativePreview: true
        )
        defer { harness.close() }
        try await harness.waitUntilReady()
        harness.updateLinkPreviews(
            [
                Self.linkPreview(
                    at: targetLink.span,
                    title: "Target note",
                    htmlBody: previewBody
                ),
                Self.linkPreview(
                    at: embeddedLink.span,
                    title: "Embedded note",
                    syntax: .embed,
                    htmlBody: embeddedBody
                ),
            ], revision: "complete-embedded-note-1")

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while true {
            let count =
                try await harness.callPageJavaScript(
                    "return document.querySelectorAll('.scholium-embedded-note').length"
                ) as? Int ?? 0
            if count == 1 { break }
            if clock.now >= deadline {
                Issue.record("Review did not install the finite embedded Note projection.")
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }

        let snapshot = try #require(
            try await harness.callPageJavaScript(
                """
                const wiki = document.querySelector('a.wiki-link:not(.scholium-embedded-note-open)');
                const external = document.querySelector('a[href="https://example.com"]');
                const shell = document.querySelector('.scholium-embedded-note');
                const viewport = shell?.querySelector('.scholium-embedded-note-viewport');
                const embeddedBody = shell?.querySelector('.scholium-embedded-note-body');
                const open = shell?.querySelector('.scholium-embedded-note-open');
                if (!wiki || !external || !shell || !viewport || !embeddedBody || !open) return null;
                viewport.scrollTop = 160;
                const wikiStyle = getComputedStyle(wiki);
                const externalStyle = getComputedStyle(external);
                return {
                  sameAccent: wikiStyle.color === externalStyle.color,
                  wikiDecoration: wikiStyle.textDecorationLine,
                  externalDecoration: externalStyle.textDecorationLine,
                  inlineEmbedCount: document.querySelectorAll('a.scholium-embed').length,
                  embeddedUsesDocumentOwner: embeddedBody.classList.contains('scholium-document'),
                  embeddedDuplicateTitleCount: [...embeddedBody.querySelectorAll('h1')]
                    .filter(heading => (heading.textContent || '').trim() === 'Embedded note').length,
                  embeddedHasTail: (embeddedBody.textContent || '').includes('Complete embedded tail'),
                  embeddedScrollable: viewport.scrollHeight > viewport.clientHeight && viewport.scrollTop > 0,
                  embeddedSourceLocators: embeddedBody.querySelectorAll('[data-source-utf16-start]').length,
                  openBadgeCount: open.querySelectorAll('.scholium-system-symbol').length,
                  viewportTabIndex: viewport.tabIndex
                };
                """
            ) as? [String: Any])
        #expect(snapshot["sameAccent"] as? Bool == true)
        #expect((snapshot["wikiDecoration"] as? String)?.contains("underline") == true)
        #expect((snapshot["externalDecoration"] as? String)?.contains("underline") == true)
        #expect(snapshot["inlineEmbedCount"] as? Int == 0)
        #expect(snapshot["embeddedUsesDocumentOwner"] as? Bool == true)
        #expect(snapshot["embeddedDuplicateTitleCount"] as? Int == 0)
        #expect(snapshot["embeddedHasTail"] as? Bool == true)
        #expect(snapshot["embeddedScrollable"] as? Bool == true)
        #expect(snapshot["embeddedSourceLocators"] as? Int == 0)
        #expect(snapshot["openBadgeCount"] as? Int == 0)
        #expect(snapshot["viewportTabIndex"] as? Int == 0)
        _ = try await harness.callPageJavaScript(
            "document.querySelector('a.wiki-link:not(.scholium-embedded-note-open)').dispatchEvent(new PointerEvent('pointerover', {bubbles: true}));")
        try await harness.waitForNativePreview(title: "Target note")
        let preview = try #require(
            try await harness.callNativePreview(
                """
                window.scrollTo(0, 120);
                const body = document.querySelector('.scholium-preview-body');
                return {usesDocumentOwner: body.classList.contains('scholium-document'),
                        duplicates: body.querySelectorAll('h1').length,
                        scrolls: document.documentElement.scrollHeight > innerHeight,
                        metadataHidden: document.querySelector('.scholium-preview-metadata').hidden};
                """) as? [String: Any])
        #expect(preview["usesDocumentOwner"] as? Bool == true)
        #expect(preview["duplicates"] as? Int == 0)
        #expect(preview["scrolls"] as? Bool == true)
        #expect(preview["metadataHidden"] as? Bool == true)
        _ = try await harness.callPageJavaScript(
            "document.querySelector('a.wiki-link').dispatchEvent(new PointerEvent('pointerout', {bubbles: true, relatedTarget: document.body}));")
        try harness.hoverNativePreview(entered: true)
        try await Task.sleep(for: .milliseconds(220))
        #expect(harness.nativePreviewWebView() != nil)
        try harness.hoverNativePreview(entered: false)
        try await harness.waitForNativePreview(visible: false)
        await harness.closeAndDrain()
    }

    @Test("Review link previews open inside callouts")
    func reviewCalloutLinkPreviews() async throws {
        let previewSource = """
            > [!connect] Curated connections
            > - [[Target]]
            > - [[Support]]{{A scoped reason.}}
            """
        let source = previewSource + "\n\n" + String(repeating: "Synthetic surrounding paragraph.\n\n", count: 24)
        let document = NoteDocument(relativePath: "CalloutPreviews.md", rawContent: source)
        let rendered = SafeMarkdownRenderer.render(document)
        let links = rendered.semanticDocument.links
        #expect(links.count == 2)
        guard links.count == 2 else { return }

        let harness = ReadHarness(
            source: source,
            htmlBody: rendered.htmlBody,
            fingerprint: DocumentFingerprint(content: source).sha256,
            initialAnchor: nil,
            initialScrollFraction: 0,
            laysOutForNativePreview: true
        )
        defer { harness.close() }
        try await harness.waitUntilReady()
        harness.updateLinkPreviews(
            [
                Self.linkPreview(
                    at: links[0].linkSpan,
                    title: "Target note"
                ),
                Self.linkPreview(
                    at: links[1].linkSpan,
                    title: "Supporting note"
                ),
            ], revision: "callout-links-1")

        for (index, title) in ["Target note", "Supporting note"].enumerated() {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            var actual = ""
            while actual != title && ContinuousClock.now < deadline {
                _ = try await harness.callPageJavaScript(
                    "document.querySelectorAll('.scholium-callout a.wiki-link')[index]?.dispatchEvent(new PointerEvent('pointerover', {bubbles: true}));",
                    arguments: ["index": index])
                actual = (try? await harness.callNativePreview("return document.querySelector('.scholium-preview-title')?.textContent || '';")) as? String ?? ""
                if actual != title { try await Task.sleep(for: .milliseconds(25)) }
            }
            #expect(actual == title)
        }
        await harness.closeAndDrain()
    }

    @Test("Review Callouts keep nested Markdown and native disclosure interaction")
    func reviewCalloutDisclosureKeepsNestedContent() async throws {
        let source = """
            > [!cite]+ Source note
            > Intro with **strong** prose.
            >
            > > Inner quotation.
            > >
            > > - Nested item
            """ + "\n\n" + String(repeating: "Synthetic surrounding paragraph.\n\n", count: 16)
        let document = NoteDocument(relativePath: "CalloutDisclosure.md", rawContent: source)
        let harness = ReadHarness(
            source: source,
            htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: DocumentFingerprint(content: source).sha256,
            initialAnchor: nil,
            initialScrollFraction: 0
        )
        defer { harness.close() }
        try await harness.waitUntilReady()

        let collapsed = try #require(
            try await harness.callPageJavaScript(
                """
                const details = document.querySelector('details.scholium-callout-cite');
                const summary = details?.querySelector(':scope > summary');
                if (!details || !summary) return null;
                summary.focus();
                const initiallyOpen = details.open;
                summary.click();
                const afterFirstClick = details.open;
                summary.click();
                const body = details.querySelector(':scope > .scholium-callout-body');
                return {
                  initiallyOpen,
                  afterFirstClick,
                  reopened: details.open,
                  summaryFocused: document.activeElement === summary,
                  nestedListCount: details.querySelectorAll('.scholium-callout-content ul').length,
                  bodyVisible: Boolean(body && body.getClientRects().length > 0)
                };
                """
            ) as? [String: Any])
        #expect(collapsed["initiallyOpen"] as? Bool == true)
        #expect(collapsed["afterFirstClick"] as? Bool == false)
        #expect(collapsed["reopened"] as? Bool == true)
        #expect(collapsed["summaryFocused"] as? Bool == true)
        #expect(collapsed["nestedListCount"] as? Int == 1)
        #expect(collapsed["bodyVisible"] as? Bool == true)
        await harness.closeAndDrain()
    }

    @Test("Review carries authored quote depth into cumulative visual indentation")
    func reviewQuoteDepthUsesCumulativeInset() async throws {
        let source = "> 一级引用\n>\n> > 二级引用\n"
        let document = NoteDocument(relativePath: "QuoteDepth.md", rawContent: source)
        let harness = ReadHarness(
            source: source,
            htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: DocumentFingerprint(content: source).sha256,
            initialAnchor: nil,
            initialScrollFraction: 0
        )
        defer { harness.close() }
        try await harness.waitUntilReady()

        let geometry = try #require(
            try await harness.callPageJavaScript(
                """
                const quotes = [...document.querySelectorAll('#scholium-document blockquote')];
                const first = quotes.find(quote => !quote.parentElement?.closest('blockquote'));
                const second = first?.querySelector(':scope > blockquote');
                if (!first || !second) return null;
                return {
                  firstClass: first.className,
                  secondClass: second.className,
                  firstContainsSecond: first.contains(second),
                  firstInset: getComputedStyle(first).paddingInlineStart,
                  secondInset: getComputedStyle(second).paddingInlineStart,
                  secondBorder: getComputedStyle(second).borderInlineStartWidth
                };
                """
            ) as? [String: Any]
        )
        #expect(geometry["firstClass"] as? String == "")
        #expect(geometry["secondClass"] as? String == "")
        #expect(geometry["firstContainsSecond"] as? Bool == true)
        #expect(geometry["firstInset"] as? String == "16px")
        #expect(geometry["secondInset"] as? String == "16px")
        #expect(geometry["secondBorder"] as? String == "1px")
        await harness.closeAndDrain()
    }

    @Test("Review presents an annotated link in the shared anchored preview")
    func reviewAnnotatedLinkDisclosure() async throws {
        let previewSource = "[[Support]]{{First **reason**.\n\n- Second reason.}} followed by prose.\n"
        let source = previewSource + "\n\n" + String(repeating: "Synthetic surrounding paragraph.\n\n", count: 24)
        let document = NoteDocument(relativePath: "Links.md", rawContent: source)
        let harness = ReadHarness(
            source: source,
            htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: DocumentFingerprint(content: source).sha256,
            initialAnchor: nil,
            initialScrollFraction: 0,
            laysOutForNativePreview: true
        )
        defer { harness.close() }
        try await harness.waitUntilReady()

        let originalHeight = try await harness.callPageJavaScript("return document.documentElement.scrollHeight;") as? Double
        _ = try await harness.callPageJavaScript(
            "document.querySelector('.scholium-link-annotation-button').dispatchEvent(new PointerEvent('pointerover', {bubbles: true}));")
        try await harness.waitForNativePreview()
        #expect(try await harness.callNativePreview("return document.querySelector('strong')?.textContent;") as? String == "reason")
        #expect(try await harness.callNativePreview("return document.body.textContent.includes('Second reason.');") as? Bool == true)
        #expect(
            try await harness.callPageJavaScript("return document.querySelector('.scholium-link-annotation-button').getAttribute('aria-expanded');") as? String
                == "true")
        _ = try await harness.callPageJavaScript(
            """
            const button = document.querySelector('.scholium-link-annotation-button');
            button.click();
            button.dispatchEvent(new PointerEvent('pointerout', {bubbles: true, relatedTarget: document.body}));
            """)
        try await Task.sleep(for: .milliseconds(220))
        #expect(harness.nativePreviewWebView() != nil)
        _ = try await harness.callPageJavaScript("document.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true}));")
        try await harness.waitForNativePreview(visible: false)
        _ = try await harness.callPageJavaScript(
            "const button = document.querySelector('.scholium-link-annotation-button'); button.blur(); button.focus({preventScroll: true});")
        try await harness.waitForNativePreview()
        #expect(
            try await harness.callPageJavaScript("return document.activeElement === document.querySelector('.scholium-link-annotation-button');") as? Bool
                == true)
        #expect(try await harness.callPageJavaScript("return document.documentElement.scrollHeight;") as? Double == originalHeight)
        #expect(
            try await harness.callPageJavaScript("return document.querySelectorAll('#scholium-preview-popover, .scholium-link-annotation-panel').length;")
                as? Int == 0)
        _ = try await harness.callPageJavaScript("document.querySelector('.scholium-link-annotation-button').blur();")
        try await harness.waitForNativePreview(visible: false)
        await harness.closeAndDrain()
    }

    @Test("Review selection remains exact after a semantic table")
    func reviewSelectionAfterTableRemainsExact() async throws {
        let source = """
            | Claim | Status |
            |:---|:---:|
            | Fittingness | Open |

            After the table remains selectable.

            A final paragraph follows.
            """
        let document = NoteDocument(relativePath: "Selection.md", rawContent: source)
        let harness = ReadHarness(
            source: source,
            htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: DocumentFingerprint(content: source).sha256,
            initialAnchor: nil,
            initialScrollFraction: 0
        )
        defer { harness.close() }
        try await harness.waitUntilReady()

        let selection = try await harness.selectVisibleText(
            "After the table remains selectable."
        )
        #expect(selection.excerpt == "After the table remains selectable.")
        #expect(selection.startLine == 5)
        #expect(selection.endLine == 5)
        await harness.closeAndDrain()
    }

    @Test("Review selection presentation excludes layout-only block space")
    func reviewSelectionPresentationExcludesLayoutOnlyBlockSpace() async throws {
        let source = "First paragraph text.\n\nSecond paragraph text.\n"
        let htmlBody = """
            <p data-source-line="1">First paragraph text.</p>
            <p data-source-line="3">Second paragraph text.</p>
            """
        let harness = ReadHarness(
            source: source,
            htmlBody: htmlBody,
            fingerprint: DocumentFingerprint(content: source).sha256,
            initialAnchor: nil,
            initialScrollFraction: 0
        )
        defer { harness.close() }
        try await harness.waitUntilReady()

        let snapshot = try await harness.crossParagraphSelectionPresentation()
        #expect(snapshot.supported)
        #expect(snapshot.customHighlightInstalled)
        #expect(snapshot.selectedText.contains("paragraph text"))
        #expect(snapshot.presentedText == "paragraph text.Second paragraph")
        #expect(snapshot.nativeSelectionBackground == "rgba(0, 0, 0, 0)")
        #expect(snapshot.textRangeCount == 2)
        #expect(!snapshot.textRectangles.isEmpty)
        await harness.closeAndDrain()
    }

    @Test("Review and Edit share quiet Markdown highlight styling")
    func reviewConsumesSharedMarkdownHighlightStyling() async throws {
        let source = "A ==marked passage== remains distinct from selection.\n"
        let document = NoteDocument(relativePath: "Highlight.md", rawContent: source)
        let harness = ReadHarness(
            source: source,
            htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: DocumentFingerprint(content: source).sha256,
            initialAnchor: nil,
            initialScrollFraction: 0
        )
        defer { harness.close() }
        try await harness.waitUntilReady()

        let result = try #require(
            try await harness.callPageJavaScript(
                """
                const mark = document.querySelector('.scholium-highlight');
                if (!mark) return null;
                const style = getComputedStyle(mark);
                return {
                    background: style.backgroundColor,
                    color: style.color,
                    parentColor: getComputedStyle(mark.parentElement || mark).color,
                    shadow: style.boxShadow,
                    boxDecorationBreak: style.getPropertyValue('box-decoration-break')
                        || style.getPropertyValue('-webkit-box-decoration-break')
                };
                """
            ) as? [String: String])
        #expect(result["background"] != "rgb(255, 154, 0)")
        #expect(result["background"] != "rgba(0, 0, 0, 0)")
        #expect(result["color"] == result["parentColor"])
        #expect(result["shadow"] != "none")
        #expect(result["boxDecorationBreak"] == "clone")
        await harness.closeAndDrain()
    }

    @Test("Review derives a quieter Accent for static document content")
    func reviewUsesDerivedDocumentAccent() async throws {
        let source = "[A link](https://example.com)\n\n> A quotation.\n"
        let document = NoteDocument(relativePath: "DocumentAccent.md", rawContent: source)
        let harness = ReadHarness(
            source: source,
            htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: DocumentFingerprint(content: source).sha256,
            initialAnchor: nil,
            initialScrollFraction: 0
        )
        defer { harness.close() }
        try await harness.waitUntilReady()

        let result = try #require(
            try await harness.callPageJavaScript(
                """
                const rawProbe = document.createElement('span');
                const documentProbe = document.createElement('span');
                rawProbe.style.cssText = 'position:fixed;inline-size:0;block-size:0;color:var(--scholium-color-accent)';
                documentProbe.style.cssText = 'position:fixed;inline-size:0;block-size:0;color:var(--scholium-document-accent)';
                document.body.append(rawProbe, documentProbe);
                const link = document.querySelector('.scholium-document a:not(.wiki-link)');
                const quotation = document.querySelector('.scholium-document blockquote');
                const result = {
                    nativeAccent: document.documentElement.style.getPropertyValue('--scholium-color-accent'),
                    rawColor: getComputedStyle(rawProbe).color,
                    documentColor: getComputedStyle(documentProbe).color,
                    linkColor: link ? getComputedStyle(link).color : '',
                    quotationBorder: quotation ? getComputedStyle(quotation).borderInlineStartColor : ''
                };
                rawProbe.remove();
                documentProbe.remove();
                return result;
                """
            ) as? [String: String])
        #expect(!result["documentColor", default: ""].isEmpty)
        #expect(result["nativeAccent", default: ""].hasPrefix("#"))
        #expect(result["documentColor"] != result["rawColor"])
        #expect(result["linkColor"] == result["documentColor"])
        #expect(result["quotationBorder"] == result["documentColor"])
        await harness.closeAndDrain()
    }

    struct ReviewSelectionPresentationSnapshot: Decodable {
        struct Rectangle: Decodable {
            let left: Double
            let right: Double
            let top: Double
            let bottom: Double
            let width: Double
            let height: Double
        }

        let supported: Bool
        let selectedText: String
        let presentedText: String
        let nativeSelectionBackground: String
        let nativeRectangles: [Rectangle]
        let textRectangles: [Rectangle]
        let textRangeCount: Int
        let customHighlightInstalled: Bool
    }

    struct TestingPresentationScenario {
        let name: String
        let width: CGFloat
        let configuration: ScholiumDocumentPresentationConfiguration
        let appearanceName: NSAppearance.Name
        let lineWidthCharacterUnits: Double?
        let readUserCSS: String
        let liveUserCSS: String

        init(
            name: String,
            width: CGFloat,
            configuration: ScholiumDocumentPresentationConfiguration,
            appearanceName: NSAppearance.Name,
            lineWidthCharacterUnits: Double? = nil,
            readUserCSS: String = "",
            liveUserCSS: String = ""
        ) {
            self.name = name
            self.width = width
            self.configuration = configuration
            self.appearanceName = appearanceName
            self.lineWidthCharacterUnits = lineWidthCharacterUnits
            self.readUserCSS = readUserCSS
            self.liveUserCSS = liveUserCSS
        }

        var expectedTextScale: String {
            String(format: "%.6fem", locale: Locale(identifier: "en_US_POSIX"), configuration.textScale)
        }

        var expectedRootLineWidth: String {
            let value =
                lineWidthCharacterUnits
                ?? DocumentAppearanceSettings.defaultLineWidthCharacterUnits
            return "\(Int(value))ch"
        }

        func minimumInlineInset(viewportWidth: Double) -> Double {
            let compactBoundary = Double(configuration.compactThresholdRootEms) * 16
            return viewportWidth <= compactBoundary
                ? configuration.compactInlineInsetCSSPixels
                : configuration.regularInlineInsetCSSPixels
        }

        var presentationCSS: String {
            guard let lineWidthCharacterUnits else { return configuration.css }
            return configuration.css
                + String(
                    format: """

                        :root {
                          --scholium-document-line-width: %.15gch;
                          --scholium-document-half-line-width: %.15gch;
                        }
                        """,
                    locale: Locale(identifier: "en_US_POSIX"),
                    lineWidthCharacterUnits,
                    lineWidthCharacterUnits / 2
                )
        }

        var expectedParagraphGap: String {
            let body = DocumentAppearanceSettings.defaultSettings.body
            return String(
                format: "%.6fpx",
                locale: Locale(identifier: "en_US_POSIX"),
                body.paragraphSpacingEm
                    * body.fontSizePoints
                    * (96 / 72)
                    * configuration.textScale
            )
        }
    }

    static let testingPresentationScenarios: [TestingPresentationScenario] = [
        .init(name: "narrow", width: 520, configuration: .init(textScale: 1), appearanceName: .aqua),
        .init(name: "compact-boundary", width: 704, configuration: .init(textScale: 1), appearanceName: .aqua),
        .init(name: "two-hundred-percent", width: 900, configuration: .init(textScale: 2), appearanceName: .aqua),
        .init(name: "narrow-two-hundred-percent", width: 520, configuration: .init(textScale: 2), appearanceName: .aqua),
        .init(name: "dark", width: 720, configuration: .init(textScale: 1), appearanceName: .darkAqua),
        .init(
            name: "increased-contrast-dark",
            width: 720,
            configuration: .init(textScale: 1),
            appearanceName: .accessibilityHighContrastDarkAqua
        ),
        .init(name: "workspace-900", width: 900, configuration: .init(textScale: 1), appearanceName: .aqua),
        .init(name: "wide", width: 1_080, configuration: .init(textScale: 1), appearanceName: .aqua),
        .init(
            name: "custom-line-width",
            width: 1_080,
            configuration: .init(textScale: 1),
            appearanceName: .aqua,
            lineWidthCharacterUnits: 84
        ),
        .init(name: "ordinary-restored", width: 720, configuration: .init(textScale: 1), appearanceName: .aqua),
        .init(
            name: "sanitized-user-css",
            width: 900,
            configuration: .init(textScale: 1),
            appearanceName: .aqua,
            readUserCSS: """
                .scholium-document { max-width: calc(100% - 16px); }
                .scholium-document h2 { font-weight: 500; }
                .scholium-document p { line-height: 1.75; }
                """,
            liveUserCSS: """
                .cm-editor.scholium-live-mode .cm-content { max-width: calc(100% - 16px); }
                .scholium-live-mode .cm-live-h2 { font-weight: 500; }
                .scholium-live-mode .cm-live-paragraph { line-height: 1.75; }
                """
        ),
    ]

    func verifyReadSemanticScrollRestoration(
        liveScenarios: [(TestingPresentationScenario, MarkdownEditorSession.TestingPresentationSnapshot)]
    ) async throws {
        let fixture = Self.longDocumentFixture()
        let fingerprint = DocumentFingerprint(content: fixture.source).sha256
        let requestedAnchor = EditorScrollAnchor(
            sourceFingerprint: fingerprint,
            sourceUTF16Offset: fixture.anchorLowerBound,
            blockUTF16LowerBound: fixture.anchorLowerBound,
            blockUTF16UpperBound: fixture.anchorUpperBound,
            relativeBlockPosition: 0,
            fallbackFraction: 0.65
        )
        let harness = ReadHarness(
            source: fixture.source,
            htmlBody: fixture.htmlBody,
            fingerprint: fingerprint,
            initialAnchor: requestedAnchor,
            initialScrollFraction: 0
        )
        defer { harness.close() }
        try await harness.waitUntilReady()
        let registry = try await harness.scrollRegistrySnapshot()
        #expect(registry.count > 80)
        #expect(registry.visualOrderIsMonotonic)
        let readScenarios = try await harness.presentationSnapshots(for: Self.testingPresentationScenarios)
        #expect(readScenarios.count == liveScenarios.count)
        let cssPixels: (String) -> Double? = { value in
            guard value.hasSuffix("px") else { return nil }
            return Double(value.dropLast(2))
        }
        for (scenario, readSnapshot) in readScenarios {
            let liveSnapshot = try #require(liveScenarios.first { $0.0.name == scenario.name }?.1)
            expectSharedPresentationParity(read: readSnapshot, live: liveSnapshot)
            #expect(readSnapshot.rootTextScale == scenario.expectedTextScale)
            #expect(readSnapshot.rootContentTopInset == "32.000000px")
            #expect(readSnapshot.rootInlineRegular == "32.000000px")
            #expect(readSnapshot.rootInlineSource == "40.000000px")
            #expect(readSnapshot.rootInlineNarrow == "20.000000px")
            #expect(readSnapshot.rootLineWidth == scenario.expectedRootLineWidth)
            #expect(readSnapshot.rootParagraphGap == scenario.expectedParagraphGap)
            let actualInset = try #require(cssPixels(readSnapshot.documentPaddingInlineStart))
            #expect(
                actualInset + 0.5
                    >= scenario.minimumInlineInset(
                        viewportWidth: readSnapshot.viewportWidth
                    ))
            if scenario.readUserCSS.isEmpty {
                #expect(abs(readSnapshot.documentWidth - readSnapshot.viewportWidth) <= 1)
            }
            #expect(readSnapshot.pageHorizontalOverflow <= 1)
        }
        let narrowTwoHundred = try #require(
            readScenarios.first { $0.0.name == "narrow-two-hundred-percent" }?.1
        )
        #expect(narrowTwoHundred.mathScrollExtent > 0)
        #expect(narrowTwoHundred.mathOutputInternalOverflow <= 1)
        #expect(narrowTwoHundred.mathStartClipping <= 1)
        #expect(narrowTwoHundred.mathEndClipping <= 1)
        #expect(narrowTwoHundred.mathMiddleTrackWidth + 1 >= narrowTwoHundred.mathOutputWidth)
        #expect(narrowTwoHundred.mathRightTrackWidth > 0)
        let wide = try #require(readScenarios.first { $0.0.name == "wide" }?.1)
        let custom = try #require(readScenarios.first { $0.0.name == "custom-line-width" }?.1)
        let wideInset = try #require(cssPixels(wide.documentPaddingInlineStart))
        let customInset = try #require(cssPixels(custom.documentPaddingInlineStart))
        #expect(
            wide.rootLineWidth
                == "\(Int(DocumentAppearanceSettings.defaultLineWidthCharacterUnits))ch"
        )
        #expect(custom.rootLineWidth == "84ch")
        #expect(customInset < wideInset)
        // Responsive full-width presentation legitimately changes which block
        // occupies the viewport while the scenario matrix resizes the window.
        // Reapply the semantic request at the final geometry before asserting
        // the exact source block restored by that request.
        harness.apply(initialAnchor: requestedAnchor, fallbackFraction: 0.65)
        let captured = try await harness.waitUntilCapturedAnchor(stage: "initial") {
            $0.blockUTF16LowerBound == fixture.anchorLowerBound
                && $0.blockUTF16UpperBound == fixture.anchorUpperBound
        }
        #expect(captured.sourceFingerprint == fingerprint)
        #expect(captured.blockUTF16LowerBound == fixture.anchorLowerBound)
        #expect(captured.blockUTF16UpperBound == fixture.anchorUpperBound)
        #expect(captured.fallbackFraction > 0.2)
        let initialRestoreCount = try await harness.restoreInvocationCount()
        harness.reapplyCurrentRestoreRequest()
        try await Task.sleep(for: .milliseconds(150))
        let repeatedRestoreCount = try await harness.restoreInvocationCount()
        #expect(repeatedRestoreCount == initialRestoreCount)

        harness.apply(initialAnchor: nil, fallbackFraction: 0.1)
        _ = try await harness.waitUntilCapturedAnchor(stage: "intermediate fallback") {
            $0.fallbackFraction < 0.2
        }
        harness.apply(initialAnchor: captured, fallbackFraction: 0)
        let restored = try await harness.waitUntilCapturedAnchor(stage: "semantic restoration") {
            $0.blockUTF16LowerBound == captured.blockUTF16LowerBound
                && $0.blockUTF16UpperBound == captured.blockUTF16UpperBound
        }
        #expect(restored.sourceFingerprint == fingerprint)
        #expect(restored.blockUTF16LowerBound == captured.blockUTF16LowerBound)
        #expect(restored.blockUTF16UpperBound == captured.blockUTF16UpperBound)
        #expect(restored.sourceUTF16Offset >= restored.blockUTF16LowerBound)
        #expect(restored.sourceUTF16Offset <= restored.blockUTF16UpperBound)

        let staleAnchor = EditorScrollAnchor(
            sourceFingerprint: "stale-fingerprint",
            sourceUTF16Offset: captured.sourceUTF16Offset,
            blockUTF16LowerBound: captured.blockUTF16LowerBound,
            blockUTF16UpperBound: captured.blockUTF16UpperBound,
            relativeBlockPosition: captured.relativeBlockPosition,
            fallbackFraction: 0.55
        )
        harness.apply(initialAnchor: staleAnchor, fallbackFraction: 0.55)
        let fallback = try await harness.waitUntilCapturedAnchor(stage: "stale fallback") {
            $0.fallbackFraction > 0.2
        }
        #expect(fallback.sourceFingerprint == fingerprint)
        #expect(fallback.fallbackFraction > 0.2)
        await harness.closeAndDrain()
    }

    private static func longDocumentFixture() -> (
        source: String,
        htmlBody: String,
        anchorLowerBound: Int,
        anchorUpperBound: Int
    ) {
        var source = testingPresentationFixtureSource() + "\n"
        var anchorLowerBound = 0
        var anchorUpperBound = 0
        for index in 1...80 {
            let line = "Research paragraph \(index) develops a deliberately long philosophical claim for scroll restoration."
            let lowerBound = source.utf16.count
            let upperBound = lowerBound + line.utf16.count
            if index == 60 {
                anchorLowerBound = lowerBound
                anchorUpperBound = upperBound
            }
            source += line + "\n\n"
        }
        let document = NoteDocument(relativePath: "ReadFixture.md", rawContent: source)
        let body = SafeMarkdownRenderer.render(document).htmlBody
        return (source, body, anchorLowerBound, anchorUpperBound)
    }

    static func testingPresentationFixtureSource() -> String {
        """
        # Shared title

        Cursor anchor.

        ## Shared heading

        A shared paragraph establishes the editorial measure.

        LATIN_GRID_PROBE philosophical reasoning compares evidence, objections, replies, distinctions, and consequences across a deliberately long line of research prose that must wrap within the approved editorial measure.

        CJK_GRID_PROBE 哲学研究需要在论证证据反对意见回应概念区分与实际后果之间保持清楚的结构关系并且在放大文字以后继续自然换行而不产生整页横向滚动。

        > [!state] Shared claim
        > The same callout must retain its typographic hierarchy.

        > [!orient]
        > This orientation paragraph keeps a natural ragged edge.

        | **Claim** | Status |
        |:---|:---:|
        | Fittingness | Open |

        $$
        \\sum_{i=1}^{n} \\frac{w_i(v_i + c_i)}{1 + \\exp(-\\lambda_i t)} = \\operatorname*{arg\\,max}_{o \\in O} F(o, r, e, c)
        $$

        Claim[^parity].

        [^parity]: **Shared** footnote.

        """
    }

    private static func linkPreview(atUTF16 offset: Int) -> DocumentLinkPreview {
        linkPreview(
            at: SourceSpan(
                utf8LowerBound: offset,
                utf8UpperBound: offset + 10,
                utf16LowerBound: offset,
                utf16UpperBound: offset + 10,
                start: SourcePosition(line: 1, utf8Column: 1, utf16Column: 1),
                end: SourcePosition(line: 1, utf8Column: 11, utf16Column: 11)
            ),
            title: "Target note"
        )
    }

    private static func linkPreview(
        at span: SourceSpan,
        title: String,
        syntax: LinkSyntax = .wikilink,
        htmlBody: String = "<p>Target body</p>"
    ) -> DocumentLinkPreview {
        DocumentLinkPreview(
            sourceSpan: span,
            target: VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Target.md"),
            targetFingerprint: DocumentFingerprint(content: "Target body"),
            title: title,
            syntax: syntax,
            fragment: nil,
            htmlBody: htmlBody
        )
    }

    private func expectSharedPresentationParity(
        read: MarkdownEditorSession.TestingPresentationSnapshot,
        live: MarkdownEditorSession.TestingPresentationSnapshot
    ) {
        #expect(live.rootContentTopInset == read.rootContentTopInset)
        #expect(live.rootTextScale == read.rootTextScale)
        #expect(live.rootProseLineHeight == read.rootProseLineHeight)
        #expect(live.rootParagraphGap == read.rootParagraphGap)
        #expect(live.rootHeadingLineHeight == read.rootHeadingLineHeight)
        #expect(live.rootInlineRegular == read.rootInlineRegular)
        #expect(live.rootInlineSource == read.rootInlineSource)
        #expect(live.rootInlineNarrow == read.rootInlineNarrow)
        #expect(live.rootLineWidth == read.rootLineWidth)
        #expect(abs(live.viewportWidth - read.viewportWidth) <= 1)
        #expect(live.pageColor == read.pageColor)
        #expect(live.pageBackgroundColor == read.pageBackgroundColor)

        #expect(live.documentFontFamily == read.documentFontFamily)
        #expect(live.documentFontFamily.contains("Alegreya"))
        #expect(live.documentFontSize == read.documentFontSize)
        #expect(live.documentLineHeight == read.documentLineHeight)
        #expect(live.documentMaxWidth == read.documentMaxWidth)
        #expect(live.documentPaddingTop == read.documentPaddingTop)
        #expect(live.documentPaddingInlineStart == read.documentPaddingInlineStart)
        #expect(abs(live.documentWidth - read.documentWidth) <= 1)
        #expect(abs(live.documentLeft - read.documentLeft) <= 1)
        #expect(abs(live.documentRight - read.documentRight) <= 1)
        #expect(abs(live.firstGlyphLeft - read.firstGlyphLeft) <= 1)
        #expect(live.pageHorizontalOverflow <= 1)
        #expect(read.pageHorizontalOverflow <= 1)

        #expect(live.headingFontFamily == read.headingFontFamily)
        #expect(live.headingFontSize == read.headingFontSize)
        #expect(live.headingFontWeight == read.headingFontWeight)
        #expect(live.headingLineHeight == read.headingLineHeight)
        #expect(abs(live.headingBlockBefore - read.headingBlockBefore) <= 1)
        #expect(abs(live.headingBlockAfter - read.headingBlockAfter) <= 1)
        #expect(abs(live.headingWidth - read.headingWidth) <= 1)
        #expect(live.headingTextDecorationLine == read.headingTextDecorationLine)
        #expect(live.headingTextDecorationLine == "none")
        #expect(live.firstLevelHeadingTextDecorationLine == read.firstLevelHeadingTextDecorationLine)
        #expect(live.firstLevelHeadingTextDecorationLine == "none")
        #expect(abs(live.firstLevelHeadingWidth - read.firstLevelHeadingWidth) <= 1)

        #expect(live.calloutAccent == read.calloutAccent)
        #expect(live.calloutBorderColor == read.calloutBorderColor)
        #expect(live.calloutFontSize == read.calloutFontSize)
        #expect(live.calloutLineHeight == read.calloutLineHeight)
        #expect(abs(live.calloutWidth - read.calloutWidth) <= 1)
        #expect(live.calloutRolePosition == "absolute")
        #expect(live.calloutRoleWidth <= 1.5)
        #expect(live.calloutRoleHeight <= 1.5)
        #expect(live.calloutTitleColor == read.calloutTitleColor)
        #expect(live.calloutTitleFontFamily == read.calloutTitleFontFamily)
        #expect(live.calloutTitleFontSize == read.calloutTitleFontSize)
        #expect(live.calloutTitleFontWeight == read.calloutTitleFontWeight)
        #expect(live.calloutTitleLineHeight == read.calloutTitleLineHeight)
        #expect(live.calloutTitleLetterSpacing == read.calloutTitleLetterSpacing)
        #expect(live.calloutTitleTextTransform == read.calloutTitleTextTransform)
        #expect(read.calloutRolePosition == "static")
        #expect(read.calloutRoleWidth > 1)
        #expect(read.calloutRoleHeight > 1)
        #expect(live.orientationTextAlign == read.orientationTextAlign)
        #expect(read.orientationTextAlign == "start")

        #expect(live.tableOverflowX == read.tableOverflowX)
        #expect(abs(live.tableWidth - read.tableWidth) <= 1)
        #expect(live.tableCellFontFamily == read.tableCellFontFamily)
        #expect(live.tableCellFontSize == read.tableCellFontSize)
        #expect(live.tableCellLineHeight == read.tableCellLineHeight)
        #expect(live.tableCellPaddingBlockStart == read.tableCellPaddingBlockStart)
        #expect(live.tableCellPaddingInlineStart == read.tableCellPaddingInlineStart)
        #expect(live.tableCellBorderBottomWidth == read.tableCellBorderBottomWidth)
        #expect(live.tableCellBorderBottomColor == read.tableCellBorderBottomColor)

        #expect(live.mathOverflowX == read.mathOverflowX)
        #expect(live.mathColor == read.mathColor)
        #expect(live.mathFontSize == read.mathFontSize)
        #expect(live.mathLineHeight == read.mathLineHeight)
        // Review owns ordinary flow with component margins. Edit owns the
        // equivalent vertical geometry in a direct CodeMirror StateField so
        // the height map and pointer coordinates remain identical. Requiring
        // the adapter-local margin properties to match would double-count the
        // gap in Edit.
        #expect(live.mathMarginBlockStart == "0px")
        let readMathMargin = Double(read.mathMarginBlockStart.dropLast(2)) ?? -.infinity
        let sharedParagraphGap = Double(read.rootParagraphGap.dropLast(2)) ?? .infinity
        #expect(abs(readMathMargin - sharedParagraphGap) <= 0.02)
        #expect(live.mathPaddingBlockStart == read.mathPaddingBlockStart)
        #expect(abs(live.mathWidth - read.mathWidth) <= 1)
        #expect(abs(live.mathScrollExtent - read.mathScrollExtent) <= 1)
        #expect(abs(live.mathOutputWidth - read.mathOutputWidth) <= 1)
        #expect(live.mathOutputInternalOverflow <= 1)
        #expect(read.mathOutputInternalOverflow <= 1)
        #expect(live.mathStartClipping <= 1)
        #expect(read.mathStartClipping <= 1)
        #expect(live.mathEndClipping <= 1)
        #expect(read.mathEndClipping <= 1)
        #expect(abs(live.mathMiddleTrackWidth - read.mathMiddleTrackWidth) <= 1)
        #expect(abs(live.mathRightTrackWidth - read.mathRightTrackWidth) <= 1)
    }

    @MainActor
    private final class SourceBox: ObservableObject {
        struct Restoration: Equatable {
            var id: UInt64
            var anchor: EditorScrollAnchor?
            var fraction: Double
        }

        @Published var isReady = false
        var presentsDocumentPreparation = false
        var diagnosticEvent: ((String, String?) -> Void)?
        var diagramSize: CGSize?
        var replyEvents: [ReadReplyEvent] = []
        var imagePreviewTargets: [String] = []
        var readLinkTargets: [String] = []
        // Observation only; no objectWillChange or readiness/action mutation.
        var nativePreviewFailures: [String] = []
        @Published var imagePreviewsEnabled = false
        var chatPageExtension: AgentChatReadPageExtension?
        @Published var restoration: Restoration?
        @Published var capturedAnchor: EditorScrollAnchor?
        var failure: String?
        @Published var presentationCSS = ""
        @Published var userCSS = ""
        @Published var surfaceIdentity = 0
        @Published var sourceLocationRequest: DocumentSourceLocationRequest?
        func requestSourceLocation(line: Int?, range: SearchSourceRange? = nil, fingerprint: String? = nil) {
            sourceLocationRequest = line.map {
                .init(
                    id: UUID(), target: .unavailable(vaultID: UUID(), relativePath: "Fixture.md"),
                    line: $0, range: range, requiresExactSelection: range != nil, sourceFingerprint: fingerprint)
            }
        }
        var sourceRangeUnavailable = false
        var sourceRevisionChanged = false
        @Published var reachedSourceLine: Int?
        @Published var linkPreviews: [DocumentLinkPreview] = []
        @Published var linkPreviewRevision = "no-previews"
        @Published var selectionSurfaceIsActive = true
        var selection: MarkdownReviewSelection?
        var selectionActionPresenter: DocumentSelectionActionPresenter?
        #if DEBUG
            @Published var testingForcesFinalizationFailure = false
            let testingScrollRestoreDelayMilliseconds: Int
        #endif
        var observedScrollPosition: ObservedScrollPosition
        private var lastIssuedRestoration: Restoration
        private var nextRestoreRequestID: UInt64 = 1

        init(
            initialAnchor: EditorScrollAnchor?,
            initialScrollFraction: Double,
            userCSS: String,
            testingForcesFinalizationFailure: Bool,
            testingScrollRestoreDelayMilliseconds: Int
        ) {
            let restoration = Restoration(
                id: 1,
                anchor: initialAnchor,
                fraction: initialScrollFraction
            )
            self.restoration = restoration
            lastIssuedRestoration = restoration
            observedScrollPosition = ObservedScrollPosition(
                fraction: initialScrollFraction,
                anchor: initialAnchor
            )
            self.userCSS = userCSS
            #if DEBUG
                self.testingForcesFinalizationFailure = testingForcesFinalizationFailure
                self.testingScrollRestoreDelayMilliseconds = testingScrollRestoreDelayMilliseconds
            #endif
        }

        func requestRestore(anchor: EditorScrollAnchor?, fraction: Double) {
            nextRestoreRequestID &+= 1
            let restoration = Restoration(
                id: nextRestoreRequestID,
                anchor: anchor,
                fraction: fraction
            )
            self.restoration = restoration
            lastIssuedRestoration = restoration
        }

        func reapplyLastRestoreRequest() {
            restoration = lastIssuedRestoration
        }

        func clearRestoreRequest() {
            restoration = nil
        }

        func acknowledgeRestoreRequest(id: UInt64, fingerprint _: String) {
            guard restoration?.id == id else { return }
            restoration = nil
        }

        func observeScrollFraction(_ fraction: Double) {
            observedScrollPosition.updateFraction(fraction)
        }

        func observeScrollAnchor(_ anchor: EditorScrollAnchor) {
            observedScrollPosition.anchor = anchor
        }

        func retryAfterFinalizationFailure() {
            #if DEBUG
                testingForcesFinalizationFailure = false
            #endif
            failure = nil
        }

        func updateLinkPreviews(_ previews: [DocumentLinkPreview], revision: String) {
            linkPreviews = previews
            linkPreviewRevision = revision
        }

    }

    /// Only this fixture supplies a dedicated WebView. All native Review load,
    /// catalog convergence and finalization policies remain the product's.
    @MainActor
    private final class PreviewPreparationGatePage: ScholiumReadPageExtension {
        let requiresMathRuntime = false
        let replyProjectionEnabled = false

        func makeWebView(configuration: WKWebViewConfiguration) -> WKWebView {
            PreviewPreparationGateWebView(frame: .zero, configuration: configuration)
        }
        func preservesPage(currentDocumentID: String, nextDocumentID: String, hasLoadedPage: Bool) -> Bool { false }
        func canUpdateInPlace(currentDocumentID: String, nextDocumentID: String, hasLoadedPage: Bool) -> Bool { false }
        func acceptsMessageWithoutCurrentFingerprint(type: String) -> Bool { false }
        func willBeginLoad(fingerprint: String) {}
        func updateIfNeeded(
            body: String, source: String, fingerprint: String, signature: String, documentID: String,
            loadGeneration: UInt64, presentationCSS: String, userCSS: String, in webView: WKWebView,
            isCurrent: @escaping @MainActor () -> Bool,
            didApply: @escaping @MainActor (String, String) -> Void,
            didFail: @escaping @MainActor (any Error) -> Void
        ) -> Bool { false }
        func didFinishNavigation(_ navigation: WKNavigation?, isCurrent: @escaping @MainActor () -> Bool) {}
        func didFinalizePage(fingerprint: String) {}
        func handleMessage(type: String, payload: [String: Any], webView: WKWebView?) -> Bool { false }
        func cancel() {}
    }

    @MainActor
    private final class PreviewPreparationGateWebView: DocumentNativeWebView {
        override func loadHTMLString(_ string: String, baseURL: URL?) -> WKNavigation? {
            // The coordinator has now installed its scripts (and cleared old
            // scripts). Add only this fixture's barrier before navigation.
            configuration.userContentController.addUserScript(
                WKUserScript(
                    source: Self.gateScript, injectionTime: .atDocumentStart,
                    forMainFrameOnly: true, in: SafeMarkdownReadWebView.bridgeContentWorld))
            return super.loadHTMLString(string, baseURL: baseURL)
        }

        private static let gateScript = """
            (() => {
              const state = window.__scholiumPreviewPreparationGate = {entered:false, released:false, trace:[]};
              // Failure-only evidence for this held-initialization journey. Keep
              // the real event, graph update and native presentation paths intact.
              let builder;
              const describe = target => target instanceof Element
                ? `${target.tagName.toLowerCase()}${target.id ? '#'+target.id : ''}${target.className ? '.'+String(target.className).trim().replace(/\\s+/g,'.') : ''}`.slice(0,160)
                : target === window ? 'window' : target === document ? 'document' : null;
              const record = (type, extra = {}) => {
                state.trace.push({type, time:performance.now(), scrollX:window.scrollX, scrollY:window.scrollY,
                  builder:builder ? {hidden:builder.hidden, title:builder.querySelector('.scholium-preview-title')?.textContent || ''} : null,
                  ...extra});
                if (state.trace.length > 32) state.trace.shift();
              };
              const observeBuilder = candidate => {
                if (builder || !(candidate instanceof Element)) return;
                const found = candidate.id === 'scholium-preview-popover'
                  ? candidate : candidate.querySelector('#scholium-preview-popover');
                if (!found) return;
                builder = found;
                record('builderFound');
                new MutationObserver(records => {
                  for (const mutation of records) record('builderMutation', {
                    mutation:mutation.type, attribute:mutation.attributeName, oldValue:mutation.oldValue
                  });
                }).observe(builder, {subtree:true, childList:true, characterData:true,
                  attributes:true, attributeFilter:['hidden'], attributeOldValue:true});
              };
              new MutationObserver(records => {
                observeBuilder(document.documentElement);
                for (const mutation of records) for (const node of mutation.addedNodes) observeBuilder(node);
              }).observe(document, {subtree:true, childList:true});
              observeBuilder(document.documentElement);
              for (const type of ['pointerover','pointerout','focusin','focusout']) document.addEventListener(type, event => {
                record(type, {target:describe(event.target), relatedTarget:describe(event.relatedTarget), trusted:event.isTrusted});
              }, true);
              for (const type of ['scroll','resize']) window.addEventListener(type, event => {
                record(type, {target:describe(event.target), width:innerWidth, height:innerHeight});
              }, {capture:true, passive:true});
              let release;
              const gate = new Promise(resolve => {release=resolve;});
              state.release=()=>{record('release'); state.released=true; release();};
              const wrap=runtime=>!runtime || runtime.version!==3 ? runtime : {
                ...runtime,
                async render(request) {
                  state.entered=true;
                  await gate;
                  return await runtime.render(request);
                }
              };
              let runtime=wrap(window.scholiumMermaid);
              Object.defineProperty(window,'scholiumMermaid',{
                configurable:true, get:()=>runtime, set:value=>{runtime=wrap(value);}
              });
            })();
            """
    }

    @MainActor
    final class ReadHarness {
        private let source: String
        private let htmlBody: String
        private let fingerprint: String
        private let documentTitle: String
        private let sourceRelativePath: String
        private let sourceBox: SourceBox
        private let window: NSWindow
        private var hostingController: NSViewController?
        private var isClosed = false
        private var formatDiagnosticPhase = ""
        private var formatProbeTask: Task<Void, Never>?
        private var formatProbeID: UUID?

        init(
            source: String,
            htmlBody: String,
            fingerprint: String,
            initialAnchor: EditorScrollAnchor?,
            initialScrollFraction: Double,
            documentTitle: String = "",
            userCSS: String = "",
            testingForcesFinalizationFailure: Bool = false,
            testingScrollRestoreDelayMilliseconds: Int = 0,
            presentsDocumentPreparation: Bool = false,
            laysOutForNativePreview: Bool = false,
            replyProjection: Bool = false,
            imagePreviewsEnabled: Bool = false,
            onAskAgent: AgentSelectionInquiryHandler? = nil,
            relativePath: String = "ReadFixture.md",
            pageExtension: (any ScholiumReadPageExtension)? = nil
        ) {
            _ = NSApplication.shared
            self.source = source
            self.htmlBody = htmlBody
            self.fingerprint = fingerprint
            self.documentTitle = documentTitle
            sourceRelativePath = relativePath
            sourceBox = SourceBox(
                initialAnchor: initialAnchor,
                initialScrollFraction: initialScrollFraction,
                userCSS: userCSS,
                testingForcesFinalizationFailure: testingForcesFinalizationFailure,
                testingScrollRestoreDelayMilliseconds: testingScrollRestoreDelayMilliseconds
            )
            sourceBox.imagePreviewsEnabled = imagePreviewsEnabled
            sourceBox.presentsDocumentPreparation = presentsDocumentPreparation
            if replyProjection {
                let box = sourceBox
                sourceBox.chatPageExtension = AgentChatReadPageExtension {
                    box.replyEvents.append($0)
                }
            }
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            // The harness owns this window strongly. Prevent AppKit's legacy
            // close-release behavior from invalidating the Swift property
            // before ReadHarness itself is released.
            window.isReleasedWhenClosed = false
            let document = NoteDocument(relativePath: relativePath, rawContent: source)
            #expect(document.fingerprint.sha256 == fingerprint)
            let root = ReadHarnessRoot(
                document: document,
                htmlBody: htmlBody,
                documentTitle: documentTitle,
                userCSS: userCSS,
                sourceBox: sourceBox,
                laysOutForNativePreview: laysOutForNativePreview,
                pageExtension: pageExtension ?? sourceBox.chatPageExtension,
                onAskAgent: onAskAgent
            )
            let controller = NSHostingController(rootView: root)
            controller.sizingOptions = []
            hostingController = controller
            window.contentViewController = controller
            window.setContentSize(NSSize(width: 720, height: 420))
            controller.view.frame = window.contentView?.bounds ?? .zero
            controller.view.autoresizingMask = [.width, .height]
            window.orderFrontRegardless()
            if laysOutForNativePreview {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate()
            }
        }

        func waitUntilReady() async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(8))
            while !sourceBox.isReady {
                if let failure = sourceBox.failure {
                    Issue.record(Comment(rawValue: failure))
                    throw ReadHarnessError.renderingFailed
                }
                if clock.now >= deadline {
                    let diagnostic = try? await callBridgeJavaScript(
                        "return {state: document.readyState, fonts: document.fonts.status, native: typeof window.scholiumNativeFloatingEvent, ready: await Promise.race([Promise.resolve(window.scholiumReadReady).then(() => true, error => String(error)), new Promise(resolve => setTimeout(() => resolve('pending'), 500))]), width: innerWidth, height: innerHeight};"
                    )
                    print("READ READY DIAGNOSTIC", diagnostic ?? "nil")
                    Issue.record("The Read WKWebView did not report rendering readiness.")
                    throw ReadHarnessError.timedOut
                }
                try await Task.sleep(for: .milliseconds(25))
            }
        }

        func beginFormatDiagnostic(phase: String) {
            formatProbeTask?.cancel()
            formatProbeTask = nil
            formatProbeID = nil
            formatDiagnosticPhase = phase
            sourceBox.diagnosticEvent = { [weak self] event, error in
                self?.emitFormatDiagnostic(event: event, error: error)
            }
            emitFormatDiagnostic(event: "phase_begin")
        }

        func installFormatWorkMetrics() async throws {
            _ = try await callBridgeJavaScript(
                """
                const stats = window.__scholiumFormatWorkMetrics = {
                  initial_outputs:document.querySelectorAll('.scholium-mermaid-output').length,
                  render_calls:0,render_ms:0,mount_calls:0,mount_ms:0,presentation_calls:[],sources:new Set()
                };
                const wrap=runtime=>!runtime || runtime.version!==3 ? runtime : {
                  ...runtime,
                  async render(request) {
                    stats.render_calls++; stats.sources.add(request.source);
                    const start=performance.now();
                    try {return await runtime.render(request);} finally {stats.render_ms+=performance.now()-start;}
                  },
                  mount(host,svg) {
                    stats.mount_calls++; const start=performance.now();
                    try {return runtime.mount(host,svg);} finally {stats.mount_ms+=performance.now()-start;}
                  }
                };
                let runtime=wrap(window.scholiumMermaid);
                Object.defineProperty(window,'scholiumMermaid',{
                  configurable:true,get:()=>runtime,set:value=>{runtime=wrap(value);}
                });
                const setCSS=window.scholiumSetPresentationCSS;
                window.scholiumSetPresentationCSS=async(...args)=>{
                  const entry={unchanged:document.getElementById('scholium-presentation-css').textContent===args[0]
                    &&document.getElementById('scholium-user-css').textContent===args[1],ms:0};
                  stats.presentation_calls.push(entry); const start=performance.now();
                  try {return await setCSS(...args);} finally {entry.ms=performance.now()-start;}
                };
                """)
        }

        func emitFormatWorkMetrics() async throws {
            let metrics = try await callBridgeJavaScript(
                """
                const {sources,...stats}=window.__scholiumFormatWorkMetrics;
                return {...stats,distinct_sources:sources.size,
                  final_outputs:document.querySelectorAll('.scholium-mermaid-output').length};
                """)
            emitFormatDiagnostic(event: "reader_work", extra: ["work": metrics ?? NSNull()])
        }

        func formatDiagnosticCoordinator() throws -> SafeMarkdownReadWebView.Coordinator {
            let root = try #require(window.contentViewController?.view)
            return try #require(findWebView(in: root)?.navigationDelegate as? SafeMarkdownReadWebView.Coordinator)
        }

        func emitFormatDiagnostic(event: String, error: String? = nil, extra: [String: Any] = [:]) {
            var record: [String: Any] = [
                "phase": formatDiagnosticPhase, "event": event, "uptime_ns": DispatchTime.now().uptimeNanoseconds,
                "caller_ready": sourceBox.isReady, "restore_pending": sourceBox.restoration != nil,
                "native_preview_failures": sourceBox.nativePreviewFailures,
            ]
            if let error { record["error"] = error }
            if let failure = sourceBox.failure { record["rendering_failure"] = failure }
            if let root = window.contentViewController?.view, let webView = findWebView(in: root) {
                record["webview_present"] = true
                record["webview_loading"] = webView.isLoading
                record["webview_ax_identifier"] = webView.accessibilityIdentifier()
                if let coordinator = webView.navigationDelegate as? SafeMarkdownReadWebView.Coordinator {
                    record["coordinator_identity"] = String(describing: ObjectIdentifier(coordinator))
                    record["surface_visibility_active"] = coordinator.surfaceVisibility.isActive
                    // Read-only diagnostic reflection avoids adding product APIs
                    // or replacing the production navigation delegate.
                    let scalars: Set<String> = [
                        "loadGeneration", "hasLoadedPage", "pageIsReady", "renderingReadinessIsAcknowledged",
                        "loadedSignature", "activeLoadSignature", "finalizedSignature",
                        "desiredLinkPreviewRevision", "appliedLinkPreviewRevision", "loadingLinkPreviewRevision",
                    ]
                    let tasks: Set<String> = ["activeNavigation", "loadFinalizationTask", "deferredLoadTask", "presentationStyleTask", "linkPreviewUpdateTask"]
                    for child in Mirror(reflecting: coordinator).children {
                        guard let name = child.label else { continue }
                        let reflected = Mirror(reflecting: child.value)
                        if name == "floatingSurfaces", let surfaces = child.value as? DocumentFloatingSurfaceController {
                            // Same existing read-only diagnostic path; never
                            // replace the production owner/delegate/callback.
                            record["native_preview_is_shown"] = surfaces.isPreviewShown
                            record["native_preview_renderer_present"] = surfaces.previewWebView != nil
                            if let renderer = surfaces.previewWebView {
                                record["native_preview_renderer_loading"] = renderer.isLoading
                                record["native_preview_renderer_bounds"] = NSStringFromRect(renderer.bounds)
                                record["native_preview_renderer_window_visible"] = renderer.window?.isVisible ?? false
                            }
                        } else if tasks.contains(name) {
                            record[name + "_present"] = reflected.displayStyle != .optional || !reflected.children.isEmpty
                        } else if scalars.contains(name) {
                            let value: Any? = reflected.displayStyle == .optional ? reflected.children.first?.value : child.value
                            if let value = value as? String {
                                record[name] = value
                            } else if let value = value as? Bool {
                                record[name] = value
                            } else if let value = value as? UInt64 {
                                record[name] = value
                            } else {
                                record[name] = NSNull()
                            }
                        }
                    }
                }
            } else {
                record["webview_present"] = false
            }
            record.merge(extra) { _, new in new }
            if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
                FileHandle.standardOutput.write(Data("FORMAT_READER_DIAGNOSTIC ".utf8) + data + Data("\n".utf8))
            }
        }

        func emitScrollRestorationFailure(stage: String, error: any Error) async {
            func anchorValue(_ anchor: EditorScrollAnchor?) -> Any {
                guard let anchor else { return NSNull() }
                return [
                    "fingerprint": anchor.sourceFingerprint,
                    "offset": anchor.sourceUTF16Offset,
                    "lower": anchor.blockUTF16LowerBound,
                    "upper": anchor.blockUTF16UpperBound,
                    "relative": anchor.relativeBlockPosition,
                    "fallback": anchor.fallbackFraction,
                ] as [String: Any]
            }
            let observed = sourceBox.observedScrollPosition
            var extra: [String: Any] = [
                "phase": stage, "surface_identity": sourceBox.surfaceIdentity,
                "observed_fraction": observed.fraction, "observed_anchor": anchorValue(observed.anchor),
                "captured_anchor": anchorValue(sourceBox.capturedAnchor),
                "reached_source_line": sourceBox.reachedSourceLine.map { $0 as Any } ?? NSNull(),
                "source_range_unavailable": sourceBox.sourceRangeUnavailable,
                "source_revision_changed": sourceBox.sourceRevisionChanged,
                "caller_presentation_css": sourceBox.presentationCSS,
            ]
            if let request = sourceBox.restoration {
                extra["caller_restore"] = [
                    "id": request.id, "fraction": request.fraction, "anchor": anchorValue(request.anchor),
                ]
            }
            if let request = sourceBox.sourceLocationRequest {
                extra["caller_source_location"] = ["id": request.id.uuidString, "line": request.line.map { $0 as Any } ?? NSNull()]
            }
            if let root = window.contentViewController?.view, let webView = findWebView(in: root) {
                extra["webview_bounds"] = NSStringFromRect(webView.bounds)
                extra["webview_hidden"] = webView.isHiddenOrHasHiddenAncestor
                if let coordinator = webView.navigationDelegate as? SafeMarkdownReadWebView.Coordinator {
                    let fields = Dictionary(
                        uniqueKeysWithValues: Mirror(reflecting: coordinator).children.compactMap { child in
                            child.label.map { ($0, child.value) }
                        })
                    for name in ["sourceLineNavigationTask", "sourceLocationRequest", "lastReachedSourceLocationID", "presentationStyleRevision"] {
                        if let value = fields[name] { extra["native_" + name] = String(String(describing: value).prefix(1024)) }
                    }
                    for (desired, applied) in [("desiredPresentationCSS", "appliedPresentationCSS"), ("desiredUserCSS", "appliedUserCSS")] {
                        extra["native_" + desired + "_is_applied"] = (fields[desired] as? String) == (fields[applied] as? String)
                    }
                    if let restoration = fields["scrollRestoration"] as? SafeMarkdownReadScrollRestoration {
                        for child in Mirror(reflecting: restoration).children {
                            guard let name = child.label, ["request", "ownership", "inFlightClaim", "consumed"].contains(name) else { continue }
                            extra["native_restore_" + name] = String(String(describing: child.value).prefix(1024))
                        }
                    }
                }
            }
            // Observe already-settled promises without waiting for preparation,
            // fonts, animation frames or another restoration after the failure.
            let snapshot = try? await callBridgeJavaScript(
                """
                const promises = {};
                for (const [name, value] of [['reader',window.scholiumReadReady],['mermaid',window.scholiumMermaidReady]]) {
                  promises[name] = value ? 'pending' : 'notInstalled';
                  if (value) Promise.resolve(value).then(
                    () => {promises[name]='resolved';}, error => {promises[name]='rejected: '+String(error);});
                }
                await Promise.resolve();
                const extent = Math.max(0, document.documentElement.scrollHeight-innerHeight);
                const fraction = window.scholiumReadScroll?.fraction?.() ?? (extent > 0 ? scrollY/extent : 0);
                const target = document.querySelector('[data-source-line="3"]');
                const rect = target?.getBoundingClientRect();
                return {readyState:document.readyState, promises, fonts:document.fonts?.status,
                  scrollY, extent, fraction, width:innerWidth, height:innerHeight,
                  anchor:window.scholiumReadScroll?.current(fraction) ?? null,
                  restoreCount:window.scholiumReadScroll?.restoreCount ?? null,
                  registry:window.scholiumReadScroll?.testingSnapshot() ?? null,
                  presentationRevision:getComputedStyle(document.documentElement).getPropertyValue('--qa-load-revision').trim(),
                  sourceLine3:target ? {top:rect.top, height:rect.height,
                    lower:target.dataset.sourceUtf16Start, upper:target.dataset.sourceUtf16End} : null};
                """)
            extra["viewport"] = snapshot ?? NSNull()
            emitFormatDiagnostic(event: "scroll_restoration_failure", error: String(describing: error), extra: extra)
        }

        private func startFormatBridgeProbe() {
            guard formatProbeTask == nil else { return }
            let requestID = UUID()
            let phase = formatDiagnosticPhase
            formatProbeID = requestID
            formatProbeTask = Task { @MainActor [weak self] in
                guard let self else { return }
                defer {
                    if self.formatProbeID == requestID {
                        self.formatProbeTask = nil
                        self.formatProbeID = nil
                    }
                }
                do {
                    let snapshot = try await self.callBridgeJavaScript(
                        """
                        const state = window.__scholiumFormatReaderDiagnostic ??= {promises:{}, values:{}};
                        for (const [name,promise] of [['reader',window.scholiumReadReady],['mermaid',window.scholiumMermaidReady]]) {
                          if (!promise) { state.values[name]='not_installed'; continue; }
                          if (state.promises[name] === promise) continue;
                          state.promises[name]=promise; state.values[name]='pending';
                          Promise.resolve(promise).then(
                            ()=>{if(state.promises[name]===promise)state.values[name]='resolved';},
                            error=>{if(state.promises[name]===promise)state.values[name]='rejected: '+String(error);});
                        }
                        return {document_state:document.readyState, fonts:document.fonts?.status || 'unavailable',
                          reader_promise:state.values.reader, mermaid_promise:state.values.mermaid,
                          diagram_wrappers:document.querySelectorAll('.scholium-mermaid').length,
                          diagram_outputs:document.querySelectorAll('.scholium-mermaid-output').length,
                          diagram_errors:document.querySelectorAll('.scholium-mermaid-error').length,
                          viewport_width:innerWidth, viewport_height:innerHeight, scroll_y:scrollY};
                        """)
                    guard !Task.isCancelled, self.formatDiagnosticPhase == phase, self.formatProbeID == requestID else { return }
                    self.emitFormatDiagnostic(event: "bridge_probe", extra: ["bridge": snapshot ?? NSNull()])
                } catch {
                    guard !Task.isCancelled, self.formatDiagnosticPhase == phase, self.formatProbeID == requestID else { return }
                    let probeError = error as NSError
                    self.emitFormatDiagnostic(
                        event: "bridge_probe_error", error: String(describing: error),
                        extra: [
                            "probe_error_domain": probeError.domain, "probe_error_code": probeError.code,
                            "error_boundary": "NSError belongs to the test-only callAsyncJavaScript probe, not onRenderingFailure.",
                        ])
                }
            }
        }

        func waitForFormatDiagnosticReady() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(60))
            var nextObservation = ContinuousClock.now
            // Caller readiness survives unmount, just as the session's exact
            // ready fingerprint does. Require the new coordinator's actual AX
            // identity too; the stale acknowledgement alone cannot pass.
            while !sourceBox.isReady || (try? webViewAccessibilityIdentifier()) != "scholium.renderedDocument.\(sourceRelativePath)" {
                if ContinuousClock.now >= nextObservation {
                    emitFormatDiagnostic(event: "waiting")
                    startFormatBridgeProbe()
                    nextObservation = ContinuousClock.now.advanced(by: .seconds(1))
                }
                if sourceBox.failure != nil {
                    emitFormatDiagnostic(event: "phase_failed")
                    Issue.record(Comment(rawValue: sourceBox.failure ?? "Unknown reader failure"))
                    throw ReadHarnessError.renderingFailed
                }
                if ContinuousClock.now >= deadline {
                    emitFormatDiagnostic(event: "phase_timeout")
                    throw ReadHarnessError.timedOut
                }
                try await Task.sleep(for: .milliseconds(25))
            }
            emitFormatDiagnostic(event: "phase_ready")
        }

        func nativeSelectionActionBar() -> SelectionActionBar? {
            func find(in view: NSView) -> SelectionActionBar? {
                if let bar = view as? SelectionActionBar { return bar }
                return view.subviews.lazy.compactMap { find(in: $0) }.first
            }
            return window.contentView.flatMap { find(in: $0) }
        }

        func focusDocumentForSelectionActions() async throws {
            guard let rootView = window.contentViewController?.view,
                let webView = findWebView(in: rootView)
            else { throw ReadHarnessError.webViewUnavailable }
            // A reader's real text selection originates in this key window's
            // WebKit responder. Creating a DOM Range alone does not establish it.
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            try #require(window.makeFirstResponder(webView))
        }

        var selectionActionNativeState: String {
            let responder = window.firstResponder.map { NSStringFromClass(type(of: $0)) } ?? "nil"
            return "Review native selection state: keyWindow=\(window.isKeyWindow), firstResponder=\(responder), toolbar=\(nativeSelectionActionBar() != nil)."
        }

        func presentSelectionInquiry(_ inquiry: AgentChatSelectionInquiry) async throws -> Bool {
            guard let presenter = sourceBox.selectionActionPresenter else {
                throw ReadHarnessError.webViewUnavailable
            }
            return try await presenter(inquiry)
        }

        func waitForSelectionActionState(stage: String, _ predicate: () -> Bool) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(8))
            while !predicate() {
                if clock.now >= deadline {
                    Issue.record("Review did not reach \(stage).")
                    throw ReadHarnessError.timedOut
                }
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        func resize(width: CGFloat, height: CGFloat, duration: TimeInterval = 0) {
            guard duration > 0 else {
                window.setContentSize(NSSize(width: width, height: height))
                return
            }
            let targetContentRect = NSRect(origin: .zero, size: NSSize(width: width, height: height))
            let targetFrameSize = window.frameRect(forContentRect: targetContentRect).size
            var targetFrame = window.frame
            targetFrame.size = targetFrameSize
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.allowsImplicitAnimation = true
                window.animator().setFrame(targetFrame, display: true)
            }
        }

        func viewportScrollBarSnapshot() async throws -> ViewportScrollBarSnapshot {
            guard
                let snapshot = try await callBridgeJavaScript(
                    """
                    const root = document.documentElement;
                    return {
                      usesOverlayScrollBar: Math.abs(window.innerWidth - root.clientWidth) < 1,
                      isSuppressed: root.classList.contains(
                        'scholium-viewport-resize-suppresses-overlay-scrollbar'
                      ),
                      scrollBarWidth: getComputedStyle(root).scrollbarWidth,
                      scrollY: window.scrollY
                    };
                    """
                ) as? [String: Any]
            else {
                throw ReadHarnessError.invalidSnapshot
            }
            return ViewportScrollBarSnapshot(
                usesOverlayScrollBar: snapshot["usesOverlayScrollBar"] as? Bool ?? false,
                isSuppressed: snapshot["isSuppressed"] as? Bool ?? false,
                scrollBarWidth: snapshot["scrollBarWidth"] as? String ?? "",
                scrollY: snapshot["scrollY"] as? Double ?? 0
            )
        }

        func waitUntilViewportScrollBarRestored() async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(3))
            while try await viewportScrollBarSnapshot().isSuppressed {
                if clock.now >= deadline {
                    let snapshot = try await viewportScrollBarSnapshot()
                    Issue.record(
                        "Review scroll-bar suppression did not settle: \(snapshot); window content width: \(window.contentView?.bounds.width ?? 0)."
                    )
                    throw ReadHarnessError.timedOut
                }
                try await Task.sleep(for: .milliseconds(25))
            }
        }

        func nativePreviewWebView() -> WKWebView? {
            func findPreview(in view: NSView) -> WKWebView? {
                if let web = view as? WKWebView, web.accessibilityIdentifier() == "scholium.documentPreview.content" { return web }
                return view.subviews.lazy.compactMap { findPreview(in: $0) }.first
            }
            return (window.childWindows ?? []).filter(\.isVisible)
                .compactMap { $0.contentView }.compactMap { findPreview(in: $0) }.first
        }

        func waitForNativePreview(title: String? = nil, visible: Bool = true) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            var lastNativeTitle = ""
            while ContinuousClock.now < deadline {
                if let preview = nativePreviewWebView() {
                    let actual =
                        (try? await preview.evaluateJavaScript(
                            "document.querySelector('.scholium-preview-title')?.textContent || ''"
                        )) as? String ?? ""
                    lastNativeTitle = actual
                    if visible && !actual.isEmpty && (title == nil || actual == title) { return }
                } else if !visible {
                    return
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            // Failure-only evidence after the original deadline. No second
            // hover, readiness retry, presentation or timeout extension.
            let reader = try? await callBridgeJavaScript(
                """
                const link = document.querySelector('a.wiki-link');
                const rect = link?.getBoundingClientRect();
                const builder = document.getElementById('scholium-preview-popover');
                return {
                  readyState: document.readyState,
                  apiInstalled: typeof window.scholiumSetLinkPreviews === 'function',
                  scrollY: window.scrollY, width: innerWidth, height: innerHeight,
                  configuration: typeof configuration === 'undefined' ? null : {
                    documentID: configuration.documentID, fingerprint: configuration.fingerprint,
                    loadGeneration: configuration.loadGeneration
                  },
                  link: link ? {
                    range: [link.dataset.sourceUtf16Start, link.dataset.sourceUtf16End],
                    rect: [rect.left, rect.top, rect.width, rect.height]
                  } : null,
                  preparationTrace: window.__scholiumPreviewPreparationGate?.trace ?? null,
                  builder: builder ? {
                    hidden: builder.hidden,
                    title: builder.querySelector('.scholium-preview-title')?.textContent || '',
                    body: (builder.querySelector('.scholium-preview-body')?.textContent || '').slice(0, 512)
                  } : null
                };
                """)
            emitFormatDiagnostic(
                event: "native_preview_timeout",
                extra: [
                    "expected_preview_title": title ?? "any", "expected_preview_visible": visible,
                    "last_native_preview_title": lastNativeTitle,
                    "owner_window_visible": window.isVisible, "owner_window_key": window.isKeyWindow,
                    "owner_window_main": window.isMainWindow, "application_active": NSApp.isActive,
                    "owner_window_frame": NSStringFromRect(window.frame),
                    "owned_child_windows": (window.childWindows ?? []).map {
                        ["visible": $0.isVisible, "key": $0.isKeyWindow, "frame": NSStringFromRect($0.frame)] as [String: Any]
                    },
                    "reader_preview_state": reader ?? NSNull(),
                ])
            Issue.record("Native preview did not reach the expected visibility/title: \(title ?? "any"), visible=\(visible)")
            throw ReadHarnessError.timedOut
        }

        func callNativePreview(_ body: String) async throws -> Any? {
            guard let preview = nativePreviewWebView() else { throw ReadHarnessError.webViewUnavailable }
            return try await preview.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: .page)
        }

        func hoverNativePreview(entered: Bool) throws {
            let preview = try #require(nativePreviewWebView())
            let container = try #require(preview.superview)
            let previewWindow = try #require(preview.window)
            let event = try #require(
                NSEvent.mouseEvent(
                    with: .mouseMoved, location: .zero,
                    modifierFlags: [], timestamp: 0, windowNumber: previewWindow.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
            if entered { container.mouseEntered(with: event) } else { container.mouseExited(with: event) }
        }

        var imagePreviewTargets: [String] { sourceBox.imagePreviewTargets }
        var readLinkTargets: [String] { sourceBox.readLinkTargets }

        func setImagePreviewsEnabled(_ enabled: Bool) { sourceBox.imagePreviewsEnabled = enabled }

        func waitForReviewImageDecoding() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while try await callBridgeJavaScript(
                "return [...document.querySelectorAll('img.scholium-embedded-image')].every(image => image.complete);") as? Bool != true
            {
                try #require(ContinuousClock.now < deadline, "Review image decoding did not settle")
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        func waitForImageCapability(_ enabled: Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while true {
                let current =
                    try? await callBridgeJavaScript(
                        "return document.querySelector('img[alt=\"Valid\"]')?.getAttribute('role') === 'button';") as? Bool
                let configured = try? readBridgeEnvelope()["imagePreviewsEnabled"] as? Bool
                if current == enabled, configured == enabled, sourceBox.isReady { return }
                try #require(ContinuousClock.now < deadline, "Review image capability did not converge")
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        func waitForImagePreviews(_ count: Int) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while imagePreviewTargets.count < count {
                try #require(ContinuousClock.now < deadline, "Expected \(count) image previews, observed \(imagePreviewTargets)")
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        func waitForReadLinks(_ count: Int) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while readLinkTargets.count < count {
                try #require(ContinuousClock.now < deadline, "Expected \(count) links, observed \(readLinkTargets)")
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        func readBridgeEnvelope() throws -> [String: Any] {
            let rootView = try #require(window.contentViewController?.view)
            let webView = try #require(findWebView(in: rootView))
            let script = try #require(
                webView.configuration.userContentController.userScripts.first {
                    $0.source.contains("const encodedConfiguration = \"")
                })
            let prefix = try #require(script.source.range(of: "const encodedConfiguration = \""))
            let encoded = script.source[prefix.upperBound...].prefix { $0 != "\"" }
            let data = try #require(Data(base64Encoded: String(encoded)))
            return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }

        func postImageMessage(target: String, envelope: [String: Any], overrides: [String: Any] = [:]) async throws {
            var payload = envelope
            payload["type"] = "imagePreview"
            payload["target"] = target
            payload.merge(overrides) { _, override in override }
            _ = try await callBridgeJavaScript(
                "window.webkit.messageHandlers.scholiumRead.postMessage(payload);", arguments: ["payload": payload])
        }

        func clickReviewImage(alt: String) async throws {
            // This verifies WebKit gesture/bridge admission. Actual AppKit
            // pointer delivery belongs to the isolated QA app journey.
            _ = try await callBridgeJavaScript(
                """
                const image = [...document.querySelectorAll('img')].find(image => image.alt === alt);
                const rect = image.getBoundingClientRect();
                for (const type of ['mousedown', 'mouseup', 'click']) {
                  image.dispatchEvent(new MouseEvent(type, {bubbles:true, cancelable:true, button:0, detail:1,
                    clientX:rect.left + rect.width/2, clientY:rect.top + rect.height/2}));
                }
                """, arguments: ["alt": alt])
        }

        func callPageJavaScript(
            _ body: String,
            arguments: [String: Any] = [:]
        ) async throws -> Any? {
            guard let rootView = window.contentViewController?.view,
                let webView = findWebView(in: rootView)
            else {
                throw ReadHarnessError.webViewUnavailable
            }
            return try await webView.callAsyncJavaScript(
                body,
                arguments: arguments,
                in: nil,
                contentWorld: .page
            )
        }

        /// Runs JavaScript in the app-owned Read content world where the
        /// bridge globals (``window.scholiumReadReady``,
        /// ``window.scholiumReadScroll``, the Mermaid runtime, and the
        /// comment/selection surface) live.
        func callBridgeJavaScript(
            _ body: String,
            arguments: [String: Any] = [:]
        ) async throws -> Any? {
            guard let rootView = window.contentViewController?.view,
                let webView = findWebView(in: rootView)
            else {
                throw ReadHarnessError.webViewUnavailable
            }
            return try await webView.callAsyncJavaScript(
                body,
                arguments: arguments,
                in: nil,
                contentWorld: SafeMarkdownReadWebView.bridgeContentWorld
            )
        }

        func preparationSnapshot() async throws -> (
            geometry: [[Double]], isHidden: Bool, width: CGFloat, height: CGFloat,
            allowsInput: Bool, acceptsPointer: Bool, accessibleChildCount: Int
        ) {
            let payload =
                try await callBridgeJavaScript(
                    """
                    if (document.fonts?.ready) await document.fonts.ready;
                    return {
                      geometry: [...document.querySelectorAll('.scholium-note-title, .scholium-frontmatter-line, #scholium-document > h1, #scholium-document > p')]
                        .map(element => { const rect = element.getBoundingClientRect(); return [rect.left, rect.top, rect.width, rect.height]; })
                    };
                    """
                ) as? [String: Any]
            guard let payload,
                let geometry = payload["geometry"] as? [[Double]],
                let root = window.contentViewController?.view,
                let web = findWebView(in: root) as? DocumentNativeWebView,
                let container = web.superview as? DocumentWebViewContainer
            else { throw ReadHarnessError.webViewUnavailable }
            root.layoutSubtreeIfNeeded()
            return (
                geometry, container.isHiddenOrHasHiddenAncestor || web.isHiddenOrHasHiddenAncestor,
                web.bounds.width, web.bounds.height,
                web.documentSurfaceAllowsInput || web.acceptsFirstResponder || web.canBecomeKeyView,
                container.hitTest(NSPoint(x: container.bounds.midX, y: container.bounds.midY)) != nil,
                container.accessibilityChildren()?.count ?? 0
            )
        }

        func waitUntilNativeInputIsEnabled() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while true {
                let snapshot = try await preparationSnapshot()
                if !snapshot.isHidden, snapshot.allowsInput, snapshot.acceptsPointer, snapshot.accessibleChildCount > 0 { return }
                try #require(ContinuousClock.now < deadline, "Acknowledged Read document never became available to native input and accessibility.")
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        func waitUntilWebViewAvailable() async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(5))
            while true {
                if let rootView = window.contentViewController?.view,
                    findWebView(in: rootView) != nil
                {
                    return
                }
                if clock.now >= deadline { throw ReadHarnessError.timedOut }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        func waitUntilReadPreparationAvailable() async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(5))
            while true {
                if let failure = sourceBox.failure {
                    Issue.record(Comment(rawValue: failure))
                    throw ReadHarnessError.renderingFailed
                }
                let installed = try? await callBridgeJavaScript(
                    """
                    return typeof configuration !== 'undefined'
                      && configuration.documentID === expectedDocumentID
                      && configuration.fingerprint === expectedFingerprint
                      && Number.isSafeInteger(configuration.loadGeneration)
                      && typeof window.scholiumReadPreparation?.settle === 'function'
                      && document.getElementById('scholium-document') !== null;
                    """, arguments: ["expectedFingerprint": fingerprint, "expectedDocumentID": sourceRelativePath])
                if installed as? Bool == true { return }
                if clock.now >= deadline { throw ReadHarnessError.timedOut }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        func waitUntilFailure() async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(8))
            while sourceBox.failure == nil {
                if clock.now >= deadline { throw ReadHarnessError.timedOut }
                try await Task.sleep(for: .milliseconds(25))
            }
        }

        func waitUntilCapturedAnchor(
            stage: String,
            matching predicate: (EditorScrollAnchor) -> Bool
        ) async throws -> EditorScrollAnchor {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(5))
            while sourceBox.capturedAnchor.map(predicate) != true {
                if clock.now >= deadline {
                    Issue.record("Read mode did not publish the \(stage) semantic scroll anchor; latest: \(String(describing: sourceBox.capturedAnchor)).")
                    throw ReadHarnessError.timedOut
                }
                try await Task.sleep(for: .milliseconds(25))
            }
            return try #require(sourceBox.capturedAnchor)
        }

        func apply(initialAnchor: EditorScrollAnchor?, fallbackFraction: Double) {
            sourceBox.capturedAnchor = nil
            sourceBox.requestRestore(anchor: initialAnchor, fraction: fallbackFraction)
        }

        func reapplyCurrentRestoreRequest() {
            sourceBox.reapplyLastRestoreRequest()
        }

        func clearRestoreRequest() {
            sourceBox.clearRestoreRequest()
        }

        var latestObservedScrollPosition: ObservedScrollPosition {
            sourceBox.observedScrollPosition
        }

        var hasPendingRestoreRequest: Bool {
            sourceBox.restoration != nil
        }

        var replyEvents: [ReadReplyEvent] { sourceBox.replyEvents }
        var diagramSize: CGSize? { sourceBox.diagramSize }

        var isReady: Bool {
            sourceBox.isReady
        }

        func forgetCallerReadiness() {
            sourceBox.isReady = false
        }

        func webViewIdentity() throws -> ObjectIdentifier {
            guard let rootView = window.contentViewController?.view,
                let webView = findWebView(in: rootView)
            else {
                throw ReadHarnessError.webViewUnavailable
            }
            return ObjectIdentifier(webView)
        }

        func webViewAccessibilityIdentifier() throws -> String? {
            guard let rootView = window.contentViewController?.view,
                let webView = findWebView(in: rootView)
            else {
                throw ReadHarnessError.webViewUnavailable
            }
            return webView.accessibilityIdentifier()
        }

        func retryAfterFinalizationFailure() {
            sourceBox.retryAfterFinalizationFailure()
            // Recreate the failed native surface explicitly. Production
            // failure recovery changes the safe-mode configuration and gets a
            // new render identity through that route; the focused harness has
            // no CSS-safe-mode owner, so it must model the same retry boundary
            // rather than depend on a late SwiftUI update racing the failed
            // coordinator's nil load signature.
            sourceBox.surfaceIdentity += 1
        }

        func updateLinkPreviews(_ previews: [DocumentLinkPreview], revision: String) {
            sourceBox.updateLinkPreviews(previews, revision: revision)
        }

        func setPresentationCSS(_ css: String) {
            sourceBox.presentationCSS = css
        }

        func setSelectionSurfaceActive(_ active: Bool) {
            sourceBox.selectionSurfaceIsActive = active
        }

        func requestSourceLine(_ line: Int) {
            sourceBox.reachedSourceLine = nil
            sourceBox.requestSourceLocation(line: line)
        }

        var pendingSourceLine: Int? { sourceBox.sourceLocationRequest?.line }

        var sourceRangeUnavailable: Bool { sourceBox.sourceRangeUnavailable }
        var sourceRevisionChanged: Bool { sourceBox.sourceRevisionChanged }
        func requestSourceRange(_ range: SearchSourceRange, fingerprint: String? = nil) {
            sourceBox.sourceRangeUnavailable = false
            sourceBox.sourceRevisionChanged = false
            sourceBox.reachedSourceLine = nil
            sourceBox.requestSourceLocation(line: range.line, range: range, fingerprint: fingerprint)
        }

        func recreateSurface(targetSourceLine: Int? = nil) {
            sourceBox.isReady = false
            sourceBox.capturedAnchor = nil
            sourceBox.reachedSourceLine = nil
            sourceBox.requestSourceLocation(line: targetSourceLine)
            sourceBox.surfaceIdentity += 1
        }

        func recreateSurface(
            restoring anchor: EditorScrollAnchor?,
            fallbackFraction: Double,
            targetSourceLine: Int?
        ) {
            sourceBox.requestRestore(anchor: anchor, fraction: fallbackFraction)
            recreateSurface(targetSourceLine: targetSourceLine)
        }

        func waitUntilSourceLineReached(_ line: Int) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(5))
            while sourceBox.reachedSourceLine != line {
                if clock.now >= deadline { throw ReadHarnessError.timedOut }
                try await Task.sleep(for: .milliseconds(25))
            }
        }

        func sourceLineTop(_ line: Int) async throws -> Double {
            guard let rootView = window.contentViewController?.view,
                let webView = findWebView(in: rootView)
            else {
                throw ReadHarnessError.webViewUnavailable
            }
            let result = try await webView.callAsyncJavaScript(
                """
                const target = document.querySelector(`[data-source-line="${line}"]`);
                return target ? target.getBoundingClientRect().top : null;
                """,
                arguments: ["line": line],
                in: nil,
                contentWorld: .page
            )
            guard let top = (result as? NSNumber)?.doubleValue else {
                throw ReadHarnessError.invalidSnapshot
            }
            return top
        }

        func sourceLineRange(_ line: Int) async throws -> (lowerBound: Int, upperBound: Int) {
            guard let rootView = window.contentViewController?.view,
                let webView = findWebView(in: rootView)
            else {
                throw ReadHarnessError.webViewUnavailable
            }
            let result = try await webView.callAsyncJavaScript(
                """
                const target = document.querySelector(`[data-source-line="${line}"]`);
                if (!target) return null;
                return {
                  lowerBound: Number(target.dataset.sourceUtf16Start),
                  upperBound: Number(target.dataset.sourceUtf16End)
                };
                """,
                arguments: ["line": line],
                in: nil,
                contentWorld: .page
            )
            guard let payload = result as? [String: Any],
                let lowerBound = (payload["lowerBound"] as? NSNumber)?.intValue,
                let upperBound = (payload["upperBound"] as? NSNumber)?.intValue
            else {
                throw ReadHarnessError.invalidSnapshot
            }
            return (lowerBound, upperBound)
        }

        func applyRapidPresentationRevisions() async throws {
            sourceBox.isReady = false
            sourceBox.presentationCSS = ":root { --qa-load-revision: A; }"
            try await Task.sleep(for: .milliseconds(5))
            sourceBox.isReady = false
            sourceBox.presentationCSS = ":root { --qa-load-revision: B; }"

            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(5))
            while true {
                if sourceBox.isReady,
                    try await currentLoadRevision() == "B"
                {
                    return
                }
                if clock.now >= deadline { throw ReadHarnessError.timedOut }
                try await Task.sleep(for: .milliseconds(25))
            }
        }

        private func currentLoadRevision() async throws -> String {
            guard let rootView = window.contentViewController?.view,
                let webView = findWebView(in: rootView)
            else {
                throw ReadHarnessError.webViewUnavailable
            }
            let result = try await webView.callAsyncJavaScript(
                "return getComputedStyle(document.documentElement).getPropertyValue('--qa-load-revision').trim();",
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            return result as? String ?? ""
        }

        func restoreInvocationCount() async throws -> Int {
            guard let rootView = window.contentViewController?.view,
                let webView = findWebView(in: rootView)
            else {
                throw ReadHarnessError.webViewUnavailable
            }
            let result = try await webView.callAsyncJavaScript(
                "return window.scholiumReadScroll?.restoreCount ?? -1;",
                arguments: [:],
                in: nil,
                contentWorld: SafeMarkdownReadWebView.bridgeContentWorld
            )
            guard let count = (result as? NSNumber)?.intValue, count >= 0 else {
                throw ReadHarnessError.invalidSnapshot
            }
            return count
        }

        func scroll(toFraction fraction: Double) async throws {
            guard let rootView = window.contentViewController?.view,
                let webView = findWebView(in: rootView)
            else {
                throw ReadHarnessError.webViewUnavailable
            }
            _ = try await webView.callAsyncJavaScript(
                """
                const extent = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
                window.scrollTo({top: extent * fraction, behavior: 'auto'});
                return true;
                """,
                arguments: ["fraction": min(1, max(0, fraction))],
                in: nil,
                contentWorld: .page
            )
        }

        func selectVisibleText(_ requestedText: String) async throws -> MarkdownReviewSelection {
            guard let rootView = window.contentViewController?.view,
                let webView = findWebView(in: rootView)
            else {
                throw ReadHarnessError.webViewUnavailable
            }
            sourceBox.selection = nil
            let selected = try await webView.callAsyncJavaScript(
                """
                const root = document.getElementById('scholium-document');
                if (!root) return false;
                const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
                let node;
                while ((node = walker.nextNode())) {
                  const index = (node.textContent || '').indexOf(requestedText);
                  if (index < 0) continue;
                  const range = document.createRange();
                  range.setStart(node, index);
                  range.setEnd(node, index + requestedText.length);
                  const selection = window.getSelection();
                  selection.removeAllRanges();
                  selection.addRange(range);
                  document.dispatchEvent(new Event('selectionchange'));
                  return true;
                }
                return false;
                """,
                arguments: ["requestedText": requestedText],
                in: nil,
                contentWorld: .page
            )
            guard selected as? Bool == true else {
                throw ReadHarnessError.invalidSnapshot
            }
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(3))
            while sourceBox.selection == nil {
                if clock.now >= deadline { throw ReadHarnessError.timedOut }
                try await Task.sleep(for: .milliseconds(20))
            }
            return try #require(sourceBox.selection)
        }

        func crossParagraphSelectionPresentation() async throws -> ReviewSelectionPresentationSnapshot {
            let rawResult = try await callBridgeJavaScript(
                """
                const paragraphs = Array.from(document.querySelectorAll('#scholium-document > p'));
                if (paragraphs.length !== 2) return null;
                const first = paragraphs[0].firstChild;
                const second = paragraphs[1].firstChild;
                if (!(first instanceof Text) || !(second instanceof Text)) return null;
                const range = document.createRange();
                range.setStart(first, 6);
                range.setEnd(second, 16);
                const selection = window.getSelection();
                selection.removeAllRanges();
                selection.addRange(range);
                document.dispatchEvent(new Event('selectionchange'));
                return window.scholiumReviewSelection?.testingSnapshot() ?? null;
                """
            )
            guard JSONSerialization.isValidJSONObject(rawResult as Any),
                let data = try? JSONSerialization.data(withJSONObject: rawResult as Any),
                let snapshot = try? JSONDecoder().decode(
                    ReviewSelectionPresentationSnapshot.self,
                    from: data
                )
            else {
                throw ReadHarnessError.invalidSnapshot
            }
            return snapshot
        }

        func scrollRegistrySnapshot() async throws -> (
            count: Int,
            visualOrderIsMonotonic: Bool
        ) {
            guard let rootView = window.contentViewController?.view,
                let webView = findWebView(in: rootView)
            else {
                throw ReadHarnessError.webViewUnavailable
            }
            let result = try await webView.callAsyncJavaScript(
                "return window.scholiumReadScroll?.testingSnapshot() ?? null;",
                arguments: [:],
                in: nil,
                contentWorld: SafeMarkdownReadWebView.bridgeContentWorld
            )
            guard let payload = result as? [String: Any],
                let count = (payload["registryCount"] as? NSNumber)?.intValue,
                let visualOrderIsMonotonic = payload["visualOrderIsMonotonic"] as? Bool
            else {
                throw ReadHarnessError.invalidSnapshot
            }
            return (count, visualOrderIsMonotonic)
        }

        func presentationSnapshot() async throws -> MarkdownEditorSession.TestingPresentationSnapshot {
            guard let rootView = window.contentViewController?.view,
                let webView = findWebView(in: rootView)
            else {
                throw ReadHarnessError.webViewUnavailable
            }
            let rawResult = try await webView.callAsyncJavaScript(
                """
                const rootStyle = getComputedStyle(document.documentElement);
                const px = value => Number.parseFloat(value || '0') || 0;
                const style = selector => {
                    const element = document.querySelector(selector);
                    return element ? getComputedStyle(element) : null;
                };
                const width = selector => document.querySelector(selector)?.getBoundingClientRect().width || 0;
                const bounds = selector => document.querySelector(selector)?.getBoundingClientRect() || {left: 0, right: 0};
                const firstGlyphLeft = selector => {
                    const element = document.querySelector(selector);
                    if (!element) return 0;
                    const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
                let node;
                while ((node = walker.nextNode())) {
                    if (!node.textContent?.trim()) continue;
                    if (node.parentElement?.closest('.cm-widgetBuffer')) continue;
                    const offset = node.textContent.search(/\\S/);
                        const range = document.createRange();
                        range.setStart(node, Math.max(0, offset));
                        range.setEnd(node, Math.max(0, offset) + 1);
                        return range.getBoundingClientRect().left;
                    }
                    return 0;
                };
                const maximumGlyphsOnLine = marker => {
                    const element = Array.from(document.querySelectorAll('.scholium-document p'))
                        .find(candidate => candidate.textContent?.includes(marker));
                    if (!element) return 0;
                    const counts = new Map();
                    const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
                    let node;
                    while ((node = walker.nextNode())) {
                        let offset = 0;
                        for (const glyph of Array.from(node.textContent || '')) {
                            const nextOffset = offset + glyph.length;
                            if (!/[\\r\\n]/u.test(glyph)) {
                                const range = document.createRange();
                                range.setStart(node, offset);
                                range.setEnd(node, nextOffset);
                                const rect = range.getClientRects()[0];
                                if (rect) {
                                    const line = Math.round(rect.top * 2) / 2;
                                    counts.set(line, (counts.get(line) || 0) + 1);
                                }
                            }
                            offset = nextOffset;
                        }
                    }
                    return Math.max(0, ...counts.values());
                };
                const textStyle = selector => {
                    const element = document.querySelector(selector);
                    if (!element) return null;
                    const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
                    let node;
                    while ((node = walker.nextNode())) {
                        if (node.textContent?.trim()) return getComputedStyle(node.parentElement || element);
                    }
                    return getComputedStyle(element);
                };
                const documentStyle = style('.scholium-document');
                const headingBlockStyle = style('.scholium-document > h2');
                const headingStyle = textStyle('.scholium-document > h2');
                const firstLevelHeadingStyle = textStyle('.scholium-document > h1:first-child');
                const calloutStyle = style('.scholium-document > .scholium-callout-state');
                const calloutRoleStyle = style('.scholium-document > .scholium-callout-state .scholium-callout-role');
                const calloutTitleStyle = style('.scholium-document > .scholium-callout-state .scholium-callout-title');
                const orientationStyle = style('.scholium-document > .scholium-callout-orient .scholium-callout-body');
                const tableStyle = style('.scholium-document > .scholium-table-scroll');
                const tableCellStyle = style('.scholium-document > .scholium-table-scroll th');
                const mathStyle = style('.scholium-document > .scholium-math-display');
                const mathGeometry = (() => {
                    const display = document.querySelector('.scholium-document > .scholium-math-display');
                    const output = display?.querySelector(':scope > .scholium-math-output, :scope > .katex-display');
                    if (!display || !output) return {
                        scrollExtent: 0,
                        outputWidth: 0,
                        outputInternalOverflow: 0,
                        startClipping: 0,
                        endClipping: 0,
                        middleTrackWidth: 0,
                        rightTrackWidth: 0,
                    };
                    const originalScrollLeft = display.scrollLeft;
                    const displayBounds = display.getBoundingClientRect();
                    display.scrollLeft = 0;
                    const startBounds = output.getBoundingClientRect();
                    display.scrollLeft = display.scrollWidth;
                    const endBounds = output.getBoundingClientRect();
                    display.scrollLeft = originalScrollLeft;
                    const tracks = getComputedStyle(display).gridTemplateColumns
                        .split(/\\s+/)
                        .map(value => Number.parseFloat(value))
                        .filter(value => Number.isFinite(value));
                    return {
                        scrollExtent: Math.max(0, display.scrollWidth - display.clientWidth),
                        outputWidth: output.getBoundingClientRect().width,
                        outputInternalOverflow: Math.max(0, output.scrollWidth - output.clientWidth),
                        startClipping: Math.max(0, displayBounds.left - startBounds.left),
                        endClipping: Math.max(0, endBounds.right - displayBounds.right),
                        middleTrackWidth: tracks[1] || 0,
                        rightTrackWidth: tracks[2] || 0,
                    };
                })();
                return {
                    rootContentTopInset: rootStyle.getPropertyValue('--scholium-document-content-top-inset').trim(),
                    rootTextScale: rootStyle.getPropertyValue('--scholium-document-text-scale').trim(),
                    rootProseLineHeight: rootStyle.getPropertyValue('--scholium-rhythm-prose-line-height').trim(),
                    rootParagraphGap: rootStyle.getPropertyValue('--scholium-rhythm-paragraph-gap').trim(),
                    rootHeadingLineHeight: rootStyle.getPropertyValue('--scholium-rhythm-heading-line-height').trim(),
                    rootInlineRegular: rootStyle.getPropertyValue('--scholium-rhythm-inline-regular').trim(),
                    rootInlineSource: rootStyle.getPropertyValue('--scholium-rhythm-inline-source').trim(),
                    rootInlineNarrow: rootStyle.getPropertyValue('--scholium-rhythm-inline-narrow').trim(),
                    rootLineWidth: rootStyle.getPropertyValue('--scholium-document-line-width').trim(),
                    viewportWidth: document.documentElement.clientWidth,
                    pageColor: documentStyle?.color || '',
                    pageBackgroundColor: style('body')?.backgroundColor || '',
                    documentFontFamily: style('body')?.fontFamily || '',
                    documentFontSize: style('body')?.fontSize || '',
                    documentLineHeight: style('body')?.lineHeight || '',
                    documentMaxWidth: documentStyle?.maxWidth || '',
                    documentPaddingTop: documentStyle?.paddingTop || '',
                    documentPaddingInlineStart: documentStyle?.paddingInlineStart || '',
                    documentWidth: width('.scholium-document'),
                    documentLeft: bounds('.scholium-document').left,
                    documentRight: bounds('.scholium-document').right,
                    firstGlyphLeft: firstGlyphLeft('.scholium-document > h2'),
                    pageHorizontalOverflow: Math.max(0, document.documentElement.scrollWidth - document.documentElement.clientWidth),
                    latinGlyphsPerLine: maximumGlyphsOnLine('LATIN_GRID_PROBE'),
                    cjkGlyphsPerLine: maximumGlyphsOnLine('CJK_GRID_PROBE'),
                    headingFontFamily: headingStyle?.fontFamily || '',
                    headingFontSize: headingStyle?.fontSize || '',
                    headingFontWeight: headingStyle?.fontWeight || '',
                    headingLineHeight: headingStyle?.lineHeight || '',
                    headingBlockBefore: px(headingBlockStyle?.marginTop) + px(headingBlockStyle?.paddingTop),
                    headingBlockAfter: px(headingBlockStyle?.marginBottom) + px(headingBlockStyle?.paddingBottom),
                    headingWidth: width('.scholium-document > h2'),
                    headingTextDecorationLine: headingStyle?.textDecorationLine || '',
                    firstLevelHeadingTextDecorationLine: firstLevelHeadingStyle?.textDecorationLine || '',
                    firstLevelHeadingWidth: width('.scholium-document > h1:first-child'),
                    calloutAccent: calloutStyle?.getPropertyValue('--callout-accent').trim() || '',
                    calloutBorderColor: calloutStyle?.borderInlineStartColor || '',
                    calloutFontSize: calloutStyle?.fontSize || '',
                    calloutLineHeight: calloutStyle?.lineHeight || '',
                    calloutWidth: width('.scholium-document > .scholium-callout-state'),
                    calloutRolePosition: calloutRoleStyle?.position || '',
                    calloutRoleWidth: width('.scholium-document > .scholium-callout-state .scholium-callout-role'),
                    calloutRoleHeight: document.querySelector('.scholium-document > .scholium-callout-state .scholium-callout-role')?.getBoundingClientRect().height || 0,
                    calloutTitleColor: calloutTitleStyle?.color || '',
                    calloutTitleFontFamily: calloutTitleStyle?.fontFamily || '',
                    calloutTitleFontSize: calloutTitleStyle?.fontSize || '',
                    calloutTitleFontWeight: calloutTitleStyle?.fontWeight || '',
                    calloutTitleLineHeight: calloutTitleStyle?.lineHeight || '',
                    calloutTitleLetterSpacing: calloutTitleStyle?.letterSpacing || '',
                    calloutTitleTextTransform: calloutTitleStyle?.textTransform || '',
                    orientationTextAlign: orientationStyle?.textAlign || '',
                    tableOverflowX: tableStyle?.overflowX || '',
                    tableWidth: width('.scholium-document > .scholium-table-scroll'),
                    tableCellFontFamily: tableCellStyle?.fontFamily || '',
                    tableCellFontSize: tableCellStyle?.fontSize || '',
                    tableCellLineHeight: tableCellStyle?.lineHeight || '',
                    tableCellPaddingBlockStart: tableCellStyle?.paddingBlockStart || '',
                    tableCellPaddingInlineStart: tableCellStyle?.paddingInlineStart || '',
                    tableCellBorderBottomWidth: tableCellStyle?.borderBottomWidth || '',
                    tableCellBorderBottomColor: tableCellStyle?.borderBottomColor || '',
                    mathOverflowX: mathStyle?.overflowX || '',
                    mathColor: mathStyle?.color || '',
                    mathFontSize: mathStyle?.fontSize || '',
                    mathLineHeight: mathStyle?.lineHeight || '',
                    mathMarginBlockStart: mathStyle?.marginBlockStart || '',
                    mathPaddingBlockStart: mathStyle?.paddingBlockStart || '',
                    mathWidth: width('.scholium-document > .scholium-math-display'),
                    mathScrollExtent: mathGeometry.scrollExtent,
                    mathOutputWidth: mathGeometry.outputWidth,
                    mathOutputInternalOverflow: mathGeometry.outputInternalOverflow,
                    mathStartClipping: mathGeometry.startClipping,
                    mathEndClipping: mathGeometry.endClipping,
                    mathMiddleTrackWidth: mathGeometry.middleTrackWidth,
                    mathRightTrackWidth: mathGeometry.rightTrackWidth
                };
                """,
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            guard JSONSerialization.isValidJSONObject(rawResult as Any),
                let data = try? JSONSerialization.data(withJSONObject: rawResult as Any),
                let snapshot = try? JSONDecoder().decode(
                    MarkdownEditorSession.TestingPresentationSnapshot.self,
                    from: data
                )
            else {
                throw ReadHarnessError.invalidSnapshot
            }
            return snapshot
        }

        func presentationSnapshots(
            for scenarios: [TestingPresentationScenario]
        ) async throws -> [(TestingPresentationScenario, MarkdownEditorSession.TestingPresentationSnapshot)] {
            var snapshots: [(TestingPresentationScenario, MarkdownEditorSession.TestingPresentationSnapshot)] = []
            for scenario in scenarios {
                window.appearance = NSAppearance(named: scenario.appearanceName)
                window.setContentSize(NSSize(width: scenario.width, height: 420))
                sourceBox.userCSS = scenario.readUserCSS
                let nextCSS = scenario.presentationCSS
                if sourceBox.presentationCSS != nextCSS {
                    sourceBox.isReady = false
                    sourceBox.presentationCSS = nextCSS
                    try await waitUntilReady()
                }

                let clock = ContinuousClock()
                let deadline = clock.now.advanced(by: .seconds(5))
                while true {
                    let snapshot = try await presentationSnapshot()
                    if snapshot.rootTextScale == scenario.expectedTextScale,
                        snapshot.documentWidth > 0
                    {
                        try await Task.sleep(for: .milliseconds(100))
                        let stableSnapshot = try await presentationSnapshot()
                        guard stableSnapshot.rootTextScale == scenario.expectedTextScale,
                            stableSnapshot.documentWidth > 0
                        else { continue }
                        snapshots.append((scenario, stableSnapshot))
                        break
                    }
                    if clock.now >= deadline {
                        Issue.record("Read did not apply the \(scenario.name) presentation contract.")
                        throw ReadHarnessError.timedOut
                    }
                    try await Task.sleep(for: .milliseconds(25))
                }
            }
            return snapshots
        }

        func close() {
            guard !isClosed else { return }
            isClosed = true
            formatProbeTask?.cancel()
            formatProbeTask = nil
            formatProbeID = nil
            sourceBox.diagnosticEvent = nil
            window.orderOut(nil)
            window.contentViewController = nil
            hostingController = nil
            window.close()
        }

        func closeAndDrain() async {
            close()
            try? await Task.sleep(for: .milliseconds(300))
        }

        private enum ReadHarnessError: Error {
            case renderingFailed
            case timedOut
            case webViewUnavailable
            case invalidSnapshot
        }

        struct ViewportScrollBarSnapshot {
            let usesOverlayScrollBar: Bool
            let isSuppressed: Bool
            let scrollBarWidth: String
            let scrollY: Double
        }

        private func findWebView(in view: NSView) -> WKWebView? {
            if let webView = view as? WKWebView { return webView }
            for subview in view.subviews {
                if let webView = findWebView(in: subview) { return webView }
            }
            return nil
        }
    }

    private struct ReadHarnessRoot: View {
        let document: NoteDocument
        let htmlBody: String
        let documentTitle: String
        let userCSS: String
        @ObservedObject var sourceBox: SourceBox
        let laysOutForNativePreview: Bool
        let pageExtension: (any ScholiumReadPageExtension)?
        let onAskAgent: AgentSelectionInquiryHandler?

        var body: some View {
            var surface = SafeMarkdownReadWebView(
                documentID: document.relativePath,
                documentTitle: documentTitle,
                document: document,
                htmlBody: htmlBody,
                presentationCSS: sourceBox.presentationCSS,
                userCSS: sourceBox.userCSS,
                configurationRevision: "read-harness",
                linkPreviews: sourceBox.linkPreviews,
                linkPreviewRevision: sourceBox.linkPreviewRevision,
                onLinkClick: { sourceBox.readLinkTargets.append($0) },
                onImagePreview: sourceBox.imagePreviewsEnabled ? { sourceBox.imagePreviewTargets.append($0) } : nil,
                onOpenExternalURL: { _ in },
                onAskAgent: onAskAgent,
                onSelectionActionPresenterReady: { sourceBox.selectionActionPresenter = $0 },
                onPreviewFailure: { sourceBox.nativePreviewFailures.append(String(describing: $0)) },
                onSelectionChange: { sourceBox.selection = $0 },
                selectionSurfaceIsActive: sourceBox.selectionSurfaceIsActive,
                renderingReadinessIsAcknowledged: sourceBox.isReady,
                onRenderingFailure: {
                    sourceBox.failure = $0
                    sourceBox.diagnosticEvent?("onRenderingFailure", $0)
                },
                onRenderingLoading: {
                    sourceBox.isReady = false
                    sourceBox.diagnosticEvent?("onRenderingLoading", nil)
                },
                onRenderingReady: {
                    sourceBox.isReady = true
                    sourceBox.diagnosticEvent?("onRenderingReady", nil)
                },
                pageExtension: pageExtension,
                onRenderedDiagramSize: { sourceBox.diagramSize = $0 },
                observedScrollPosition: sourceBox.observedScrollPosition,
                scrollRestoreRequest: sourceBox.restoration.map { restoration in
                    ScrollRestoreRequest(
                        id: restoration.id,
                        fingerprint: document.fingerprint.sha256,
                        position: ObservedScrollPosition(
                            fraction: restoration.fraction,
                            anchor: restoration.anchor
                        ),
                        reason: .explicitNavigation
                    )
                },
                onScrollRestoreConsumed: sourceBox.acknowledgeRestoreRequest,
                onScrollFractionChange: sourceBox.observeScrollFraction,
                onScrollAnchorChange: {
                    sourceBox.observeScrollAnchor($0)
                    sourceBox.capturedAnchor = $0
                },
                sourceLocationRequest: sourceBox.sourceLocationRequest,
                onSourceRangeUnavailable: { id in
                    guard sourceBox.sourceLocationRequest?.id == id else { return }
                    sourceBox.sourceRangeUnavailable = true
                    sourceBox.sourceLocationRequest = nil
                },
                onSourceRevisionChanged: { id in
                    guard sourceBox.sourceLocationRequest?.id == id else { return }
                    sourceBox.sourceRevisionChanged = true
                    sourceBox.sourceLocationRequest = nil
                },
                onSourceLocationReached: { id in
                    guard sourceBox.sourceLocationRequest?.id == id else { return }
                    sourceBox.reachedSourceLine = sourceBox.sourceLocationRequest?.line
                    sourceBox.sourceLocationRequest = nil
                }
            )
            #if DEBUG
                surface.testingForcesFinalizationFailure = sourceBox.testingForcesFinalizationFailure
                surface.testingScrollRestoreDelayMilliseconds = sourceBox.testingScrollRestoreDelayMilliseconds
            #endif
            let reader = ZStack {
                surface.id(sourceBox.surfaceIdentity)
                    .environment(
                        \.scholiumDocumentSurfaceVisibility,
                        sourceBox.presentsDocumentPreparation && !sourceBox.isReady ? .preparing : .active
                    )
                if sourceBox.presentsDocumentPreparation && !sourceBox.isReady {
                    DocumentPreparationStatus(title: documentTitle)
                }
            }
            return reader.frame(width: laysOutForNativePreview ? 720 : nil, height: laysOutForNativePreview ? 420 : nil)
        }
    }
}
