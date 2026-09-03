import AppKit
import ScholiumContracts
import SwiftUI
import Testing
import WebKit
@testable import ScholiumApp

extension MarkdownEditorWebViewIntegrationTests {
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
        let result = try #require(try await harness.callBridgeJavaScript(
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

        #expect(html.contains(
            "class=\"scholium-note-title\" role=\"heading\" aria-level=\"1\""
        ))
        #expect(html.contains("Reasons &lt; Emotion &amp; Value"))
        #expect(html.contains("data-scholium-protected=\"note-title\""))
        let titleRange = try #require(html.range(of: "scholium-note-title"))
        let sectionRange = try #require(html.range(of: "Authored section"))
        #expect(titleRange.lowerBound < sectionRange.lowerBound)
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
        let loaded = try await harness.callBridgeJavaScript(
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

        let page = try #require(try await harness.callPageJavaScript(
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

        let bridge = try #require(try await harness.callBridgeJavaScript(
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
        let mermaidRuntime = try await harness.callBridgeJavaScript(
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

        let beforeFallbackRestore = try await harness.restoreInvocationCount()
        harness.apply(initialAnchor: nil, fallbackFraction: 0.55)
        _ = try await harness.waitUntilCapturedAnchor(stage: "fallback restore") {
            $0.fallbackFraction > 0.4
        }
        let afterFallbackRestore = try await harness.restoreInvocationCount()
        #expect(afterFallbackRestore == beforeFallbackRestore + 1)
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
        let source = "First claim[^one], then another claim[^one].\n\n[^one]: Basis.\n"
        let document = NoteDocument(relativePath: "Footnotes.md", rawContent: source)
        let harness = ReadHarness(
            source: source,
            htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: DocumentFingerprint(content: source).sha256,
            initialAnchor: nil,
            initialScrollFraction: 0
        )
        defer { harness.close() }
        try await harness.waitUntilReady()

        let interaction = try await harness.footnoteInteractionSnapshot()
        #expect(interaction.previewTitle == "Footnote 1")
        #expect(interaction.originID == "fnref-1-2")
        #expect(!interaction.previewHiddenAfterHover)
        #expect(interaction.previewHiddenAfterScroll)
        #expect(!interaction.previewHiddenAfterFocus)
        #expect(interaction.previewHiddenAfterFocusExit)
        #expect(!interaction.previewBackground.isEmpty)
        #expect(interaction.previewBackground != "rgba(0, 0, 0, 0)")
        #expect(!interaction.previewBorderColor.isEmpty)
        #expect(interaction.previewBackdropFilter == "none")
        #expect(interaction.navigatedToDefinition)
        #expect(interaction.definitionFocused)
        #expect(interaction.returnedToReference)
        #expect(interaction.referenceFocused)
        await harness.closeAndDrain()
    }

    @Test("Review link previews update without reloading the document page")
    func reviewLinkPreviewsConvergeInPlace() async throws {
        let source = "[[Target]]\n"
        let document = NoteDocument(relativePath: "PreviewSource.md", rawContent: source)
        let harness = ReadHarness(
            source: source,
            htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: DocumentFingerprint(content: source).sha256,
            initialAnchor: nil,
            initialScrollFraction: 0
        )
        defer { harness.close() }
        try await harness.waitUntilReady()
        let pageIdentity = try #require(try await harness.callPageJavaScript(
            "return window.__scholiumTestingPageIdentity ??= `${Date.now()}:${Math.random()}`"
        ) as? String)

        harness.updateLinkPreviews([Self.linkPreview(atUTF16: 0)], revision: "graph-1")
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        var previewTitle = ""
        while previewTitle != "Target note" {
            previewTitle = try await harness.callPageJavaScript(
                """
                const link = document.querySelector('a.wiki-link');
                link?.dispatchEvent(new PointerEvent('pointerover', {bubbles: true}));
                return document.querySelector('.scholium-preview-title')?.textContent || '';
                """
            ) as? String ?? ""
            if clock.now >= deadline {
                Issue.record("Review did not install the updated link preview in place.")
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(previewTitle == "Target note")
        let retainedIdentity = try #require(try await harness.callPageJavaScript(
            "return window.__scholiumTestingPageIdentity"
        ) as? String)
        #expect(retainedIdentity == pageIdentity)
        await harness.closeAndDrain()
    }

    @Test("Review shares link, preview, and finite embedded Note presentation")
    func reviewLinkAndEmbeddedNotePresentation() async throws {
        let source = "[[Target]] and [External](https://example.com)\n\n![[Embedded]]\n"
        let document = NoteDocument(relativePath: "LinkedDocument.md", rawContent: source)
        let rendered = SafeMarkdownRenderer.render(document)
        let targetLink = try #require(rendered.semanticDocument.links.first {
            $0.syntax == .wikilink
        })
        let embeddedLink = try #require(rendered.semanticDocument.links.first {
            $0.syntax == .embed
        })
        let previewBody = "<h1>Target note</h1>" + String(
            repeating: "<p>Scrollable preview content.</p>",
            count: 60
        )
        let embeddedTail = "Complete embedded tail"
        let embeddedBody = "<h1>Embedded note</h1>" + String(
            repeating: "<p>Complete embedded content.</p>",
            count: 90
        ) + "<p>\(embeddedTail)</p>"
        let harness = ReadHarness(
            source: source,
            htmlBody: rendered.htmlBody,
            fingerprint: DocumentFingerprint(content: source).sha256,
            initialAnchor: nil,
            initialScrollFraction: 0
        )
        defer { harness.close() }
        try await harness.waitUntilReady()
        harness.updateLinkPreviews([
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
            let count = try await harness.callPageJavaScript(
                "return document.querySelectorAll('.scholium-embedded-note').length"
            ) as? Int ?? 0
            if count == 1 { break }
            if clock.now >= deadline {
                Issue.record("Review did not install the finite embedded Note projection.")
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }

        let snapshot = try #require(try await harness.callPageJavaScript(
            """
            const wiki = document.querySelector('a.wiki-link:not(.scholium-embedded-note-open)');
            const external = document.querySelector('a[href="https://example.com"]');
            const shell = document.querySelector('.scholium-embedded-note');
            const viewport = shell?.querySelector('.scholium-embedded-note-viewport');
            const embeddedBody = shell?.querySelector('.scholium-embedded-note-body');
            const open = shell?.querySelector('.scholium-embedded-note-open');
            const popover = document.getElementById('scholium-preview-popover');
            if (!wiki || !external || !shell || !viewport || !embeddedBody || !open || !popover) {
              return null;
            }
            wiki.dispatchEvent(new PointerEvent('pointerover', {bubbles: true}));
            await new Promise(resolve => setTimeout(resolve, 25));
            const previewBody = popover.querySelector('.scholium-preview-body');
            const metadata = popover.querySelector('.scholium-preview-metadata');
            const previewDuplicateTitleCount = [...previewBody.querySelectorAll('h1')]
              .filter(heading => (heading.textContent || '').trim() === 'Target note').length;
            popover.scrollTop = 120;
            const previewScrollTop = popover.scrollTop;
            wiki.dispatchEvent(new PointerEvent('pointerout', {
              bubbles: true,
              relatedTarget: document.body
            }));
            await new Promise(resolve => setTimeout(resolve, 60));
            popover.dispatchEvent(new PointerEvent('pointerenter', {bubbles: false}));
            await new Promise(resolve => setTimeout(resolve, 220));
            const remainedVisibleInside = !popover.hidden;
            popover.dispatchEvent(new PointerEvent('pointerleave', {bubbles: false}));
            await new Promise(resolve => setTimeout(resolve, 220));
            const hiddenAfterGrace = popover.hidden;
            viewport.scrollTop = 160;
            const wikiStyle = getComputedStyle(wiki);
            const externalStyle = getComputedStyle(external);
            return {
              sameAccent: wikiStyle.color === externalStyle.color,
              wikiDecoration: wikiStyle.textDecorationLine,
              externalDecoration: externalStyle.textDecorationLine,
              metadataHidden: metadata.hidden,
              previewUsesDocumentOwner: previewBody.classList.contains('scholium-document'),
              previewDuplicateTitleCount,
              previewScrollTop,
              remainedVisibleInside,
              hiddenAfterGrace,
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
        #expect(snapshot["wikiDecoration"] as? String == "none")
        #expect((snapshot["externalDecoration"] as? String)?.contains("underline") == true)
        #expect(snapshot["metadataHidden"] as? Bool == true)
        #expect(snapshot["previewUsesDocumentOwner"] as? Bool == true)
        #expect(snapshot["previewDuplicateTitleCount"] as? Int == 0)
        #expect((snapshot["previewScrollTop"] as? Double ?? 0) > 0)
        #expect(snapshot["remainedVisibleInside"] as? Bool == true)
        #expect(snapshot["hiddenAfterGrace"] as? Bool == true)
        #expect(snapshot["inlineEmbedCount"] as? Int == 0)
        #expect(snapshot["embeddedUsesDocumentOwner"] as? Bool == true)
        #expect(snapshot["embeddedDuplicateTitleCount"] as? Int == 0)
        #expect(snapshot["embeddedHasTail"] as? Bool == true)
        #expect(snapshot["embeddedScrollable"] as? Bool == true)
        #expect(snapshot["embeddedSourceLocators"] as? Int == 0)
        #expect(snapshot["openBadgeCount"] as? Int == 0)
        #expect(snapshot["viewportTabIndex"] as? Int == 0)
        await harness.closeAndDrain()
    }

    @Test("Review link previews open inside callouts")
    func reviewCalloutLinkPreviews() async throws {
        let source = """
        > [!connect] Curated connections
        > - [[Target]]
        > - [[Support]]{{A scoped reason.}}
        """
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
            initialScrollFraction: 0
        )
        defer { harness.close() }
        try await harness.waitUntilReady()
        harness.updateLinkPreviews([
            Self.linkPreview(
                at: links[0].linkSpan,
                title: "Target note"
            ),
            Self.linkPreview(
                at: links[1].linkSpan,
                title: "Supporting note"
            ),
        ], revision: "callout-links-1")

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        var titles: [String] = []
        while titles != ["Target note", "Supporting note"] {
            titles = try await harness.callPageJavaScript(
                """
                return [...document.querySelectorAll('.scholium-callout a.wiki-link')].map(link => {
                  link.dispatchEvent(new PointerEvent('pointerover', {bubbles: true}));
                  return document.querySelector('.scholium-preview-title')?.textContent || '';
                });
                """
            ) as? [String] ?? []
            if clock.now >= deadline {
                Issue.record("Review did not resolve callout link previews from document source ranges.")
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(titles == ["Target note", "Supporting note"])
        await harness.closeAndDrain()
    }

    @Test("Review presents an annotated link through one accessible disclosure")
    func reviewAnnotatedLinkDisclosure() async throws {
        let source = "[[Support]]{{First **reason**.\n\n- Second reason.}}\n"
        let document = NoteDocument(relativePath: "Links.md", rawContent: source)
        let harness = ReadHarness(
            source: source,
            htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
            fingerprint: DocumentFingerprint(content: source).sha256,
            initialAnchor: nil,
            initialScrollFraction: 0
        )
        defer { harness.close() }
        try await harness.waitUntilReady()

        let snapshot = try #require(try await harness.callPageJavaScript(
            """
            const button = document.querySelector('.scholium-link-annotation-button');
            const icon = button?.querySelector('span');
            if (!button || !icon) return null;
            button.click();
            const panel = document.querySelector('.scholium-link-annotation-panel');
            return {
              expanded: button.getAttribute('aria-expanded'),
              panelRole: panel?.getAttribute('role') || '',
              panelText: panel?.textContent || '',
              strongText: panel?.querySelector('strong')?.textContent || '',
              sourceLocated: Boolean(panel?.querySelector('[data-source-utf16-start]')),
              inlineSVGCount: document.querySelectorAll('svg').length
            };
            """
        ) as? [String: Any])
        #expect(snapshot["expanded"] as? String == "true")
        #expect(snapshot["panelRole"] as? String == "note")
        #expect((snapshot["panelText"] as? String)?.contains("Second reason.") == true)
        #expect(snapshot["strongText"] as? String == "reason")
        #expect(snapshot["sourceLocated"] as? Bool == true)
        #expect(snapshot["inlineSVGCount"] as? Int == 0)
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

    @Test("Review and Edit consume the fixed Markdown highlight role")
    func reviewConsumesFixedMarkdownHighlightRole() async throws {
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

        let result = try #require(try await harness.callPageJavaScript(
            """
            const mark = document.querySelector('.scholium-highlight');
            if (!mark) return null;
            const style = getComputedStyle(mark);
            return {background: style.backgroundColor, color: style.color};
            """
        ) as? [String: String])
        #expect(result["background"] == "rgb(255, 154, 0)")
        #expect(result["color"] == "rgb(40, 36, 29)")
        await harness.closeAndDrain()
    }

    struct FootnoteInteractionSnapshot: Decodable {
        let previewTitle: String
        let originID: String
        let previewHiddenAfterHover: Bool
        let previewHiddenAfterScroll: Bool
        let previewHiddenAfterFocus: Bool
        let previewHiddenAfterFocusExit: Bool
        let previewBackground: String
        let previewBorderColor: String
        let previewBackdropFilter: String
        let navigatedToDefinition: Bool
        let definitionFocused: Bool
        let returnedToReference: Bool
        let referenceFocused: Bool
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
            let value = lineWidthCharacterUnits
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
            return configuration.css + String(
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
            .scholium-document { max-width: 46ch; }
            .scholium-document h2 { font-weight: 500; }
            .scholium-document p { line-height: 1.75; }
            """,
            liveUserCSS: """
            .cm-editor.scholium-live-mode .cm-content { max-width: 46ch; }
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
            #expect(actualInset + 0.5 >= scenario.minimumInlineInset(
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
        for index in 1 ... 80 {
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
        #expect(live.calloutRoleColor == read.calloutRoleColor)
        #expect(live.calloutRolePosition == read.calloutRolePosition)
        #expect(abs(live.calloutRoleWidth - read.calloutRoleWidth) <= 1)
        #expect(abs(live.calloutRoleHeight - read.calloutRoleHeight) <= 1)
        #expect(live.calloutRoleFontFamily == read.calloutRoleFontFamily)
        #expect(live.calloutRoleFontSize == read.calloutRoleFontSize)
        #expect(live.calloutRoleFontWeight == read.calloutRoleFontWeight)
        #expect(live.calloutRoleLineHeight == read.calloutRoleLineHeight)
        #expect(live.calloutRoleLetterSpacing == read.calloutRoleLetterSpacing)
        #expect(live.calloutRoleTextTransform == read.calloutRoleTextTransform)
        #expect(live.calloutTitleColor == read.calloutTitleColor)
        #expect(live.calloutTitleFontFamily == read.calloutTitleFontFamily)
        #expect(live.calloutTitleFontSize == read.calloutTitleFontSize)
        #expect(live.calloutTitleFontWeight == read.calloutTitleFontWeight)
        #expect(live.calloutTitleLineHeight == read.calloutTitleLineHeight)
        #expect(live.calloutTitleLetterSpacing == read.calloutTitleLetterSpacing)
        #expect(live.calloutTitleTextTransform == read.calloutTitleTextTransform)
        #expect(read.calloutRolePosition == "absolute")
        #expect(read.calloutRoleWidth <= 1)
        #expect(read.calloutRoleHeight <= 1)
        #expect(read.calloutTitleColor == read.calloutRoleColor)
        #expect(read.calloutTitleFontFamily == read.calloutRoleFontFamily)
        #expect(read.calloutTitleFontSize == read.calloutRoleFontSize)
        #expect(read.calloutTitleFontWeight == read.calloutRoleFontWeight)
        #expect(read.calloutTitleLineHeight == read.calloutRoleLineHeight)
        #expect(read.calloutTitleLetterSpacing == read.calloutRoleLetterSpacing)
        #expect(read.calloutTitleTextTransform == read.calloutRoleTextTransform)
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
        @Published var restoration: Restoration?
        @Published var capturedAnchor: EditorScrollAnchor?
        var failure: String?
        @Published var presentationCSS = ""
        @Published var userCSS = ""
        @Published var surfaceIdentity = 0
        @Published var targetSourceLine: Int?
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
            userCSS: String = "",
            testingForcesFinalizationFailure: Bool = false,
            testingScrollRestoreDelayMilliseconds: Int = 0
        ) {
            _ = NSApplication.shared
            self.source = source
            self.htmlBody = htmlBody
            self.fingerprint = fingerprint
            sourceBox = SourceBox(
                initialAnchor: initialAnchor,
                initialScrollFraction: initialScrollFraction,
                userCSS: userCSS,
                testingForcesFinalizationFailure: testingForcesFinalizationFailure,
                testingScrollRestoreDelayMilliseconds: testingScrollRestoreDelayMilliseconds
            )
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
                userCSS: userCSS,
                sourceBox: sourceBox
            )
            let controller = NSHostingController(rootView: root)
            hostingController = controller
            window.contentViewController = controller
            window.orderFrontRegardless()
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
            guard let snapshot = try await callBridgeJavaScript(
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
            ) as? [String: Any] else {
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

        func callPageJavaScript(
            _ body: String,
            arguments: [String: Any] = [:]
        ) async throws -> Any? {
            guard let rootView = window.contentViewController?.view,
                  let webView = findWebView(in: rootView) else {
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
                  let webView = findWebView(in: rootView) else {
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
                   findWebView(in: rootView) != nil {
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

        var isReady: Bool {
            sourceBox.isReady
        }

        func forgetCallerReadiness() {
            sourceBox.isReady = false
        }

        func webViewIdentity() throws -> ObjectIdentifier {
            guard let rootView = window.contentViewController?.view,
                  let webView = findWebView(in: rootView) else {
                throw ReadHarnessError.webViewUnavailable
            }
            return ObjectIdentifier(webView)
        }

        func webViewAccessibilityIdentifier() throws -> String? {
            guard let rootView = window.contentViewController?.view,
                  let webView = findWebView(in: rootView) else {
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

        func recreateSurface(targetSourceLine: Int? = nil) {
            sourceBox.isReady = false
            sourceBox.capturedAnchor = nil
            sourceBox.reachedSourceLine = nil
            sourceBox.targetSourceLine = targetSourceLine
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
                  let webView = findWebView(in: rootView) else {
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
                  let webView = findWebView(in: rootView) else {
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
                  let upperBound = (payload["upperBound"] as? NSNumber)?.intValue else {
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
                   try await currentLoadRevision() == "B" {
                    return
                }
                if clock.now >= deadline { throw ReadHarnessError.timedOut }
                try await Task.sleep(for: .milliseconds(25))
            }
        }

        private func currentLoadRevision() async throws -> String {
            guard let rootView = window.contentViewController?.view,
                  let webView = findWebView(in: rootView) else {
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
                  let webView = findWebView(in: rootView) else {
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
                  let webView = findWebView(in: rootView) else {
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

        func footnoteInteractionSnapshot() async throws -> FootnoteInteractionSnapshot {
            let rawResult = try await callBridgeJavaScript(
                """
                const references = Array.from(document.querySelectorAll('.footnote-reference'));
                const reference = references[1];
                const origin = reference && reference.closest('.footnote-reference-wrap');
                const definition = reference && document.getElementById(reference.dataset.target);
                const back = definition && definition.querySelector('.footnote-return');
                const popover = document.getElementById('scholium-preview-popover');
                const title = popover && popover.querySelector('.scholium-preview-title');
                if (!reference || !origin || !definition || !back || !popover || !title) return null;

                let navigatedToDefinition = false;
                let returnedToReference = false;
                definition.scrollIntoView = () => { navigatedToDefinition = true; };
                origin.scrollIntoView = () => { returnedToReference = true; };

                reference.dispatchEvent(new PointerEvent('pointerover', {bubbles: true}));
                const previewTitle = title.textContent || '';
                const previewHiddenAfterHover = popover.hidden;
                const previewStyle = getComputedStyle(popover);
                const previewBackground = previewStyle.backgroundColor;
                const previewBorderColor = previewStyle.borderTopColor;
                const previewBackdropFilter = previewStyle.backdropFilter
                  || previewStyle.webkitBackdropFilter
                  || 'none';
                window.dispatchEvent(new Event('scroll'));
                const previewHiddenAfterScroll = popover.hidden;

                reference.focus({preventScroll: true});
                const previewHiddenAfterFocus = popover.hidden;
                reference.dispatchEvent(new FocusEvent('focusout', {
                  bubbles: true,
                  relatedTarget: document.body
                }));
                await new Promise(resolve => setTimeout(resolve, 220));
                const previewHiddenAfterFocusExit = popover.hidden;

                reference.dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true}));
                const definitionFocused = document.activeElement === definition;
                back.dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true}));

                return {
                  previewTitle,
                  originID: origin.id,
                  previewHiddenAfterHover,
                  previewHiddenAfterScroll,
                  previewHiddenAfterFocus,
                  previewHiddenAfterFocusExit,
                  previewBackground,
                  previewBorderColor,
                  previewBackdropFilter,
                  navigatedToDefinition,
                  definitionFocused,
                  returnedToReference,
                  referenceFocused: document.activeElement === reference
                };
                """,
                arguments: [:]
            )
            guard JSONSerialization.isValidJSONObject(rawResult as Any),
                  let data = try? JSONSerialization.data(withJSONObject: rawResult as Any) else {
                throw ReadHarnessError.invalidSnapshot
            }
            return try JSONDecoder().decode(FootnoteInteractionSnapshot.self, from: data)
        }

        func selectVisibleText(_ requestedText: String) async throws -> MarkdownReviewSelection {
            guard let rootView = window.contentViewController?.view,
                  let webView = findWebView(in: rootView) else {
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
                  ) else {
                throw ReadHarnessError.invalidSnapshot
            }
            return snapshot
        }

        func scrollRegistrySnapshot() async throws -> (
            count: Int,
            visualOrderIsMonotonic: Bool
        ) {
            guard let rootView = window.contentViewController?.view,
                  let webView = findWebView(in: rootView) else {
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
                  let visualOrderIsMonotonic = payload["visualOrderIsMonotonic"] as? Bool else {
                throw ReadHarnessError.invalidSnapshot
            }
            return (count, visualOrderIsMonotonic)
        }

        func presentationSnapshot() async throws -> MarkdownEditorSession.TestingPresentationSnapshot {
            guard let rootView = window.contentViewController?.view,
                  let webView = findWebView(in: rootView) else {
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
                    calloutRoleColor: calloutRoleStyle?.color || '',
                    calloutRolePosition: calloutRoleStyle?.position || '',
                    calloutRoleWidth: width('.scholium-document > .scholium-callout-state .scholium-callout-role'),
                    calloutRoleHeight: document.querySelector('.scholium-document > .scholium-callout-state .scholium-callout-role')?.getBoundingClientRect().height || 0,
                    calloutRoleFontFamily: calloutRoleStyle?.fontFamily || '',
                    calloutRoleFontSize: calloutRoleStyle?.fontSize || '',
                    calloutRoleFontWeight: calloutRoleStyle?.fontWeight || '',
                    calloutRoleLineHeight: calloutRoleStyle?.lineHeight || '',
                    calloutRoleLetterSpacing: calloutRoleStyle?.letterSpacing || '',
                    calloutRoleTextTransform: calloutRoleStyle?.textTransform || '',
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
                  ) else {
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
                       snapshot.documentWidth > 0 {
                        try await Task.sleep(for: .milliseconds(100))
                        let stableSnapshot = try await presentationSnapshot()
                        guard stableSnapshot.rootTextScale == scenario.expectedTextScale,
                              stableSnapshot.documentWidth > 0 else { continue }
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
        let userCSS: String
        @ObservedObject var sourceBox: SourceBox

        var body: some View {
            var surface = SafeMarkdownReadWebView(
                documentID: "ReadFixture.md",
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
                targetSourceLine: sourceBox.targetSourceLine,
                onSourceLineReached: {
                    let reached = sourceBox.targetSourceLine
                    sourceBox.reachedSourceLine = reached
                    sourceBox.targetSourceLine = nil
                }
            )
            #if DEBUG
            surface.testingForcesFinalizationFailure = sourceBox.testingForcesFinalizationFailure
            surface.testingScrollRestoreDelayMilliseconds = sourceBox.testingScrollRestoreDelayMilliseconds
            #endif
            return surface.id(sourceBox.surfaceIdentity)
        }
    }
}
