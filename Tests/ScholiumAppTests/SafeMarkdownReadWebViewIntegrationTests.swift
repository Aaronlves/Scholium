import AppKit
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

extension MarkdownEditorWebViewIntegrationTests {
    @Test("Chat note context menus target the pointed link and leave web links native")
    func chatNoteContextTarget() async throws {
        let first = AgentChatReference.url(noteID: UUID())
        let second = AgentChatReference.url(noteID: UUID())
        let source = "[First](\(first.absoluteString)) [Second](\(second.absoluteString)) [Web](https://example.org)"
        let document = NoteDocument(relativePath: "Reply.md", rawContent: source)
        let harness = ReadHarness(
            source: source, htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: document.fingerprint.sha256, initialAnchor: nil, initialScrollFraction: 0,
            laysOutForNativePreview: true, chatReply: true)
        defer { harness.close() }
        try await harness.waitUntilReady()
        let cancelled =
            try await harness.callBridgeJavaScript(
                """
                const links = document.querySelectorAll('#scholium-document a');
                return [links[1], links[2]].map(link => {
                    const box = link.getBoundingClientRect();
                    const event = new MouseEvent('contextmenu', {bubbles:true, cancelable:true, clientX:box.x+1, clientY:box.y+1});
                    link.dispatchEvent(event); return event.defaultPrevented;
                });
                """) as? [Bool]
        #expect(cancelled == [true, false])
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
    }

    @Test("Chat reader quotes one selection across prose, table and code")
    func chatReplyCrossObjectSelection() async throws {
        let source = "Reason 😀.\n\n| Claim | Evidence |\n|---|---|\n| A | B |\n\n```text\nlast line\n```"
        let document = NoteDocument(relativePath: "Reply.md", rawContent: source)
        let harness = ReadHarness(
            source: source, htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: document.fingerprint.sha256, initialAnchor: nil, initialScrollFraction: 0, laysOutForNativePreview: true, chatReply: true)
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
                window.scholiumQuoteReplySelection(); return selection.toString();
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
        let controls = try await harness.callBridgeJavaScript("return document.querySelectorAll('.scholium-reply-controls button').length;") as? Int
        #expect(controls == 4)
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

    @Test("Initial Review consumes only a finished source-free prewarmed WebView")
    func readConsumesPreparedWebView() async throws {
        let prewarmer = ScholiumWebKitProcessPrewarmer.shared
        prewarmer.finish()
        prewarmer.start()
        let preparedIdentity = try #require(prewarmer.testingPreparedWebViewIdentity)
        #expect(!prewarmer.testingPreparedWebViewIsReady)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while !prewarmer.testingPreparedWebViewIsReady {
            try #require(
                clock.now < deadline,
                "The isolated prewarm page did not finish before the bounded handoff window."
            )
            try await Task.sleep(for: .milliseconds(20))
        }
        let source = "# Prepared Review\n\nThe exact source remains authoritative.\n"
        let document = NoteDocument(relativePath: "Prepared.md", rawContent: source)
        let harness = ReadHarness(
            source: source,
            htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: document.fingerprint.sha256,
            initialAnchor: nil,
            initialScrollFraction: 0,
            userCSS: "#scholium-document p { background-color: rgb(0, 0, 255); box-shadow: none; }"
        )
        defer {
            harness.close()
            prewarmer.finish()
        }

        try await harness.waitUntilReady()

        #expect(try harness.webViewIdentity() == preparedIdentity)
        #expect(!prewarmer.isActive)
        #expect(
            try harness.webViewAccessibilityIdentifier()
                == "scholium.renderedDocument.ReadFixture.md"
        )
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
        #expect(result["runtime"] as? Int == 2)
        #expect(result["staticFamilyCount"] as? Int == 5)
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
        try await harness.waitUntilReady()
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

        let consumedCount = try await harness.restoreInvocationCount()
        harness.reapplyCurrentRestoreRequest()
        try await Task.sleep(for: .milliseconds(150))
        let countAfterReapplication = try await harness.restoreInvocationCount()
        #expect(countAfterReapplication == consumedCount)
        harness.clearRestoreRequest()

        try await harness.scroll(toFraction: 0.2)
        try await Task.sleep(for: .milliseconds(250))
        let countAfterObservation = try await harness.restoreInvocationCount()
        #expect(countAfterObservation == consumedCount)

        let observedBeforeRebuild = harness.latestObservedScrollPosition
        let observedAnchor = try #require(observedBeforeRebuild.anchor)
        harness.recreateSurface()
        try await harness.waitUntilReady()
        let rebuiltAnchor = try await harness.waitUntilCapturedAnchor(stage: "WebView rebuild") {
            $0.blockUTF16LowerBound == observedAnchor.blockUTF16LowerBound
                && $0.blockUTF16UpperBound == observedAnchor.blockUTF16UpperBound
        }
        #expect(rebuiltAnchor.sourceFingerprint == fingerprint)

        try await harness.applyRapidPresentationRevisions()

        harness.recreateSurface(
            restoring: anchor,
            fallbackFraction: 0.65,
            targetSourceLine: 3
        )
        try await harness.waitUntilReady()
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
        try await harness.scroll(toFraction: 0.7)
        harness.requestSourceLine(3)
        try await harness.waitUntilSourceLineReached(3)
        #expect(abs(try await harness.sourceLineTop(3)) <= 16)

        let beforeFallbackRestore = try await harness.restoreInvocationCount()
        harness.apply(initialAnchor: nil, fallbackFraction: 0.55)
        _ = try await harness.waitUntilCapturedAnchor(stage: "fallback restore") {
            $0.fallbackFraction > 0.4
        }
        let afterFallbackRestore = try await harness.restoreInvocationCount()
        #expect(afterFallbackRestore == beforeFallbackRestore + 1)
        await harness.closeAndDrain()
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

    @Test("Review places the app title before quiet authored YAML and the body")
    func reviewFrontmatterFollowsDocumentTitle() async throws {
        let source =
            "---\ntitle: Fixture\nsummary: Read in place\n---\n# First section\n\n"
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

    @Test("Review suppresses only overlay scroll bars during viewport reflow")
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
        try await harness.waitUntilRestoreInvocationCount(1)

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

    @Test("Review link previews update without reloading the document page")
    func reviewLinkPreviewsConvergeInPlace() async throws {
        let previewSource = "[[Target]]\n"
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
        var diagramSize: CGSize?
        var chatReplyEnabled = false
        var replyEvents: [ReadReplyEvent] = []
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

    @MainActor
    final class ReadHarness {
        private let source: String
        private let htmlBody: String
        private let fingerprint: String
        private let documentTitle: String
        private let sourceBox: SourceBox
        private let window: NSWindow
        private var hostingController: NSViewController?
        private var isClosed = false

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
            laysOutForNativePreview: Bool = false,
            chatReply: Bool = false
        ) {
            _ = NSApplication.shared
            self.source = source
            self.htmlBody = htmlBody
            self.fingerprint = fingerprint
            self.documentTitle = documentTitle
            sourceBox = SourceBox(
                initialAnchor: initialAnchor,
                initialScrollFraction: initialScrollFraction,
                userCSS: userCSS,
                testingForcesFinalizationFailure: testingForcesFinalizationFailure,
                testingScrollRestoreDelayMilliseconds: testingScrollRestoreDelayMilliseconds
            )
            sourceBox.chatReplyEnabled = chatReply
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
            let root = ReadHarnessRoot(
                source: source,
                htmlBody: htmlBody,
                fingerprint: fingerprint,
                documentTitle: documentTitle,
                userCSS: userCSS,
                sourceBox: sourceBox,
                laysOutForNativePreview: laysOutForNativePreview
            )
            let controller = NSHostingController(rootView: root)
            hostingController = controller
            window.contentViewController = controller
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
                        "return {state: document.readyState, fonts: document.fonts.status, native: typeof window.scholiumNativeFloatingEvent, ready: await Promise.race([Promise.resolve(window.scholiumReadReady).then(() => true, error => String(error)), new Promise(resolve => setTimeout(() => resolve('pending'), 500))]), quote: typeof window.scholiumQuoteReplySelection, width: innerWidth, height: innerHeight};"
                    )
                    print("READ READY DIAGNOSTIC", diagnostic ?? "nil")
                    Issue.record("The Read WKWebView did not report rendering readiness.")
                    throw ReadHarnessError.timedOut
                }
                try await Task.sleep(for: .milliseconds(25))
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
            guard let root = window.contentViewController?.view,
                let owner = findWebView(in: root)
            else { return nil }
            return (owner.superview?.subviews ?? []).compactMap { $0 as? NSGlassEffectView }
                .compactMap { $0.contentView as? WKWebView }.first
        }

        func waitForNativePreview(title: String? = nil, visible: Bool = true) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while ContinuousClock.now < deadline {
                if let preview = nativePreviewWebView() {
                    let actual =
                        (try? await preview.evaluateJavaScript(
                            "document.querySelector('.scholium-preview-title')?.textContent || ''"
                        )) as? String ?? ""
                    if visible && !actual.isEmpty && (title == nil || actual == title) { return }
                } else if !visible {
                    return
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            Issue.record("Native preview did not reach the expected visibility/title: \(title ?? "any"), visible=\(visible)")
            throw ReadHarnessError.timedOut
        }

        func callNativePreview(_ body: String) async throws -> Any? {
            guard let preview = nativePreviewWebView() else { throw ReadHarnessError.webViewUnavailable }
            return try await preview.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: .page)
        }

        func hoverNativePreview(entered: Bool) throws {
            let root = try #require(window.contentViewController?.view)
            let owner = try #require(findWebView(in: root))
            let glass = try #require(owner.superview?.subviews.compactMap { $0 as? NSGlassEffectView }.first)
            let event = try #require(
                NSEvent.mouseEvent(
                    with: .mouseMoved, location: .zero,
                    modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
            if entered { glass.mouseEntered(with: event) } else { glass.mouseExited(with: event) }
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

        func setSelectionSurfaceActive(_ active: Bool) {
            sourceBox.selectionSurfaceIsActive = active
        }

        func requestSourceLine(_ line: Int) {
            sourceBox.reachedSourceLine = nil
            sourceBox.requestSourceLocation(line: line)
        }

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

        func waitUntilRestoreInvocationCount(_ expected: Int) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(5))
            while clock.now < deadline {
                if (try? await restoreInvocationCount()) == expected {
                    return
                }
                try await Task.sleep(for: .milliseconds(25))
            }
            Issue.record(
                "Read mode did not retain the expected restoration invocation count \(expected)."
            )
            throw ReadHarnessError.timedOut
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
        let source: String
        let htmlBody: String
        let fingerprint: String
        let documentTitle: String
        let userCSS: String
        @ObservedObject var sourceBox: SourceBox
        let laysOutForNativePreview: Bool

        var body: some View {
            var surface = SafeMarkdownReadWebView(
                documentID: "ReadFixture.md",
                documentTitle: documentTitle,
                fingerprint: fingerprint,
                source: source,
                htmlBody: htmlBody,
                presentationCSS: sourceBox.presentationCSS,
                userCSS: sourceBox.userCSS,
                configurationRevision: "read-harness:\(sourceBox.presentationCSS.hashValue):\(sourceBox.userCSS.hashValue)",
                linkPreviews: sourceBox.linkPreviews,
                linkPreviewRevision: sourceBox.linkPreviewRevision,
                onLinkClick: { _ in },
                onOpenExternalURL: { _ in },
                onSelectionChange: { sourceBox.selection = $0 },
                selectionSurfaceIsActive: sourceBox.selectionSurfaceIsActive,
                renderingReadinessIsAcknowledged: sourceBox.isReady,
                onRenderingFailure: { sourceBox.failure = $0 },
                onRenderingLoading: { sourceBox.isReady = false },
                onRenderingReady: { sourceBox.isReady = true },
                onReplyEvent: sourceBox.chatReplyEnabled ? { sourceBox.replyEvents.append($0) } : nil,
                onRenderedDiagramSize: { sourceBox.diagramSize = $0 },
                observedScrollPosition: sourceBox.observedScrollPosition,
                scrollRestoreRequest: sourceBox.restoration.map { restoration in
                    ScrollRestoreRequest(
                        id: restoration.id,
                        fingerprint: fingerprint,
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
            return surface.id(sourceBox.surfaceIdentity)
                .frame(width: laysOutForNativePreview ? 720 : nil, height: laysOutForNativePreview ? 420 : nil)
        }
    }
}
