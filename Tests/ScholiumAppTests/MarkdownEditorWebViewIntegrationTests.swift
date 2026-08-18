import AppKit
import Combine
import ScholiumContracts
import SwiftUI
import Testing
import WebKit
@testable import ScholiumApp

@Suite("Markdown editor WKWebView integration", .serialized)
@MainActor
struct MarkdownEditorWebViewIntegrationTests {
    @Test("A bare ATX marker and space immediately use heading presentation")
    func bareATXMarkerImmediatelyUsesHeadingPresentation() async throws {
        let source = ""
        let harness = EditorHarness(
            source: source,
            initialSourceRange: 0..<0
        )
        defer { harness.close() }
        try await harness.waitUntilReady()

        try await harness.session.perform(.pastePlain, argument: "#")
        try await harness.waitUntilSelection(head: 1, stage: "ATX marker")
        #expect(try await harness.session.testingAccessibilitySnapshot().liveH1Count == 0)

        try await harness.session.perform(.pastePlain, argument: " ")
        try await harness.waitUntilSelection(head: 2, stage: "ATX marker separator")

        let presentation = try await harness.session.testingAccessibilitySnapshot()
        #expect(presentation.liveH1Count == 1)
        #expect(!presentation.h1FontSize.isEmpty)
        #expect(try await harness.session.currentText(for: harness.documentID) == "# ")
        await harness.closeAndDrain()
    }

    @Test("Initial body selection is acknowledged before editor readiness")
    func initialBodySelectionGatesReadiness() async throws {
        let source = "---\r\ncustom: |+\r\n  before\r\n  ---\r\n  after\r\n---\r\nBody\r\n"
        let bodyStart = NoteDocument(
            relativePath: "Untitled.md",
            rawContent: source
        ).bodyUTF16Offset
        let sourceBodyUTF16Index = source.utf16.index(
            source.utf16.startIndex,
            offsetBy: bodyStart
        )
        let sourceBodyIndex = try #require(
            String.Index(sourceBodyUTF16Index, within: source)
        )
        let editorBodyStart = String(source[..<sourceBodyIndex])
            .replacingOccurrences(of: "\r\n", with: "\n")
            .utf16.count
        let dispatcher = SuspendingInitialSelectionBridgeDispatcher()
        let harness = EditorHarness(
            source: source,
            bridgeDispatcher: dispatcher,
            initialSourceRange: bodyStart..<bodyStart
        )
        defer { harness.close() }

        try await dispatcher.waitUntilSuspended()
        #expect(!harness.session.isLoaded)
        #expect(harness.session.presentedMode == nil)
        #expect(!(try await harness.session.testingAccessibilitySnapshot().isFocused))

        dispatcher.resume()
        try await harness.waitUntilReady()
        try await harness.waitUntilSelection(
            head: editorBodyStart,
            stage: "acknowledged managed body boundary"
        )
        #expect(harness.session.presentedMode == .livePreview)
        #expect(try await harness.session.testingAccessibilitySnapshot().isFocused)
    }

    @Test("Review handoff revokes focus from a pending editor initialization")
    func reviewHandoffRevokesPendingInitialFocus() async throws {
        let source = "---\ntags: [draft]\n---\nBody\n"
        let bodyStart = NoteDocument(
            relativePath: "Untitled.md",
            rawContent: source
        ).bodyUTF16Offset
        let dispatcher = SuspendingInitialSelectionBridgeDispatcher()
        let harness = EditorHarness(
            source: source,
            bridgeDispatcher: dispatcher,
            initialSourceRange: bodyStart..<bodyStart
        )
        defer { harness.close() }

        try await dispatcher.waitUntilSuspended()
        let handoff = Task { @MainActor in
            await harness.session.resignFocusAndWait()
        }
        await Task.yield()
        dispatcher.resume()
        await handoff.value
        try await harness.waitUntilReady()

        #expect(!(try await harness.session.testingAccessibilitySnapshot().isFocused))
    }

    @Test("A newer Source request supersedes a pending Review handoff")
    func sourceRequestSupersedesPendingReviewHandoff() async throws {
        let source = "---\ntags: [draft]\n---\nBody\n"
        let bodyStart = NoteDocument(
            relativePath: "Untitled.md",
            rawContent: source
        ).bodyUTF16Offset
        let dispatcher = SuspendingInitialSelectionBridgeDispatcher()
        let harness = EditorHarness(
            source: source,
            bridgeDispatcher: dispatcher,
            initialSourceRange: bodyStart..<bodyStart
        )
        defer { harness.close() }

        try await dispatcher.waitUntilSuspended()
        let obsoleteReviewHandoff = Task { @MainActor in
            await harness.session.resignFocusAndWait()
        }
        await Task.yield()
        harness.session.authorizeAutomaticFocus()
        harness.session.setMode(.source)
        dispatcher.resume()
        await obsoleteReviewHandoff.value
        try await harness.waitUntilReady()
        try await harness.waitUntilPresentedMode(.source)
        try await harness.waitUntilSelection(
            head: bodyStart,
            stage: "newest Source request body boundary"
        )

        #expect(harness.session.presentedMode == .source)
        #expect(try await harness.session.testingAccessibilitySnapshot().isFocused)
    }

    @Test("A failed bridge blur cannot block the native Review handoff")
    func failedBlurDoesNotBlockReviewHandoff() async throws {
        let dispatcher = FailingBlurBridgeDispatcher()
        let harness = EditorHarness(
            source: "Body\n",
            bridgeDispatcher: dispatcher
        )
        defer { harness.close() }
        try await harness.waitUntilReady()

        await harness.session.resignFocusAndWait()

        #expect(dispatcher.didAttemptBlur)
        #expect(harness.session.isLoaded)
    }

    @Test("Rejected editor recovery report resets only after teardown returns")
    func rejectedEditorRecoveryReportDefersTeardownReset() async throws {
        let dispatcher = FailingQueryTextBridgeDispatcher()
        let harness = EditorHarness(
            source: "Body\n",
            bridgeDispatcher: dispatcher
        )
        defer { harness.close() }
        try await harness.waitUntilReady()

        let webView = try #require(harness.session.webView)
        dispatcher.shouldFailQueryText = true
        harness.session.reconcileAfterRejectedEditorChanges(
            resultingGeneration: harness.session.generation + 1,
            in: webView
        )

        let clock = ContinuousClock()
        let reportDeadline = clock.now.advanced(by: .seconds(3))
        while harness.session.errorMessage == nil,
              clock.now < reportDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(dispatcher.didFailQueryText)
        #expect(harness.session.errorMessage != nil)

        var invalidationCount = 0
        let observation = harness.session.objectWillChange.sink {
            invalidationCount += 1
        }
        invalidationCount = 0

        harness.session.detach(webView)

        #expect(!harness.session.hasAttachedWebView)
        #expect(harness.session.errorMessage != nil)
        #expect(invalidationCount == 0)

        let resetDeadline = clock.now.advanced(by: .seconds(3))
        while harness.session.errorMessage != nil,
              clock.now < resetDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(harness.session.errorMessage == nil)
        #expect(invalidationCount == 1)
        _ = observation
    }

    @Test("A false initial selection acknowledgement fails editor readiness")
    func falseInitialSelectionAcknowledgementFailsClosed() async throws {
        let source = "---\ntags: [draft]\n---\nBody\n"
        let bodyStart = NoteDocument(
            relativePath: "Untitled.md",
            rawContent: source
        ).bodyUTF16Offset
        let harness = EditorHarness(
            source: source,
            bridgeDispatcher: WrongInitialSelectionBridgeDispatcher(),
            initialSourceRange: bodyStart..<bodyStart
        )
        defer { harness.close() }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while harness.session.errorMessage == nil, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(harness.session.errorMessage != nil)
        #expect(!harness.session.isLoaded)
        #expect(harness.session.presentedMode == nil)
    }

    @Test("Post-initialize failure leaves the hidden editor unfocused")
    func postInitializeFailureLeavesEditorUnfocused() async throws {
        let source = "---\ntags: [draft]\n---\nBody\n"
        let bodyStart = NoteDocument(
            relativePath: "Untitled.md",
            rawContent: source
        ).bodyUTF16Offset
        let harness = EditorHarness(
            source: source,
            bridgeDispatcher: FailingPostInitializeBridgeDispatcher(),
            initialSourceRange: bodyStart..<bodyStart
        )
        defer { harness.close() }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while harness.session.errorMessage == nil, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(harness.session.errorMessage != nil)
        #expect(!harness.session.isLoaded)
        #expect(!(try await harness.session.testingAccessibilitySnapshot().isFocused))
    }

    @Test("Edit renders Mermaid only after the caret leaves its exact fenced source")
    func mermaidRendersAtFencedBlockExit() async throws {
        let source = """
        # Diagram

        ```mermaid
        flowchart LR
        accTitle: Argument structure
        accDescr: A reason supports a conclusion.
        A --> B
        ```

        After diagram.
        """
        let harness = EditorHarness(source: source)
        defer { harness.close() }
        try await harness.waitUntilReady()

        func snapshot() async throws -> [String: Any] {
            try #require(try await harness.callPageJavaScript(
                """
                return {
                  runtime: window.scholiumMermaid?.version || 0,
                  widgets: document.querySelectorAll('.cm-live-mermaid-widget').length,
                  rendered: [...document.querySelectorAll('.cm-live-mermaid-widget .scholium-mermaid-output')]
                    .filter(output => output.shadowRoot?.querySelector('svg')).length,
                  sourceLines: [...document.querySelectorAll('.cm-line')]
                    .filter(line => (line.textContent || '').includes('flowchart LR')).length,
                  openingFenceVisible: [...document.querySelectorAll('.cm-line')]
                    .some(line => (line.textContent || '').trim() === '```mermaid'
                      && line.getBoundingClientRect().height > 0.5),
                  closingFenceVisible: [...document.querySelectorAll('.cm-line')]
                    .some(line => (line.textContent || '').trim() === '```'
                      && line.getBoundingClientRect().height > 0.5),
                  collapsedFenceLines: document.querySelectorAll('.cm-live-code-fence-line').length
                };
                """
            ) as? [String: Any])
        }

        let clock = ContinuousClock()
        var deadline = clock.now.advanced(by: .seconds(8))
        var inactive = try await snapshot()
        while inactive["rendered"] as? Int != 1 {
            if clock.now >= deadline {
                Issue.record("Inactive Mermaid did not render: \(inactive)")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(25))
            inactive = try await snapshot()
        }
        #expect(inactive["runtime"] as? Int == 2)
        #expect(inactive["widgets"] as? Int == 1)
        #expect(inactive["sourceLines"] as? Int == 0)

        let closingFence = try #require(source.range(of: "```\n\nAfter diagram.")?.lowerBound)
            .utf16Offset(in: source)
        let blockTo = closingFence + 3
        harness.session.revealSourceRange(fromUTF16: blockTo, toUTF16: blockTo)
        try await harness.waitUntilSelection(head: blockTo, stage: "Mermaid closing boundary")
        try await harness.session.testingPressArrow("ArrowLeft")
        try await harness.waitUntilSelection(head: blockTo - 1, stage: "left-arrow Mermaid source entry")
        deadline = clock.now.advanced(by: .seconds(4))
        var arrowActive = try await snapshot()
        while arrowActive["widgets"] as? Int != 0
            || arrowActive["sourceLines"] as? Int != 1
            || arrowActive["openingFenceVisible"] as? Bool != true
            || arrowActive["closingFenceVisible"] as? Bool != true
        {
            if clock.now >= deadline {
                Issue.record("Mermaid source did not expose both fences after arrow entry: \(arrowActive)")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(20))
            arrowActive = try await snapshot()
        }
        #expect(arrowActive["collapsedFenceLines"] as? Int == 0)
        #expect(try await harness.session.currentText(for: harness.documentID) == source)

        harness.session.goToLine(10)
        deadline = clock.now.advanced(by: .seconds(8))
        var arrowExited = try await snapshot()
        while arrowExited["rendered"] as? Int != 1 {
            if clock.now >= deadline {
                Issue.record("Mermaid did not rerender after arrow exit: \(arrowExited)")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(25))
            arrowExited = try await snapshot()
        }

        harness.session.goToLine(4)
        deadline = clock.now.advanced(by: .seconds(4))
        var active = try await snapshot()
        while active["widgets"] as? Int != 0
            || active["sourceLines"] as? Int != 1
            || active["openingFenceVisible"] as? Bool != true
            || active["closingFenceVisible"] as? Bool != true
        {
            if clock.now >= deadline {
                Issue.record("Mermaid source did not expose both fences after direct entry: \(active)")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(20))
            active = try await snapshot()
        }
        #expect(active["rendered"] as? Int == 0)
        #expect(active["collapsedFenceLines"] as? Int == 0)
        #expect(try await harness.session.currentText(for: harness.documentID) == source)

        let selectedBody = try #require(source.range(of: "A --> B"))
        let selectedBodyFrom = selectedBody.lowerBound.utf16Offset(in: source)
        let selectedBodyTo = selectedBody.upperBound.utf16Offset(in: source)
        harness.session.revealSourceRange(fromUTF16: selectedBodyFrom, toUTF16: selectedBodyTo)
        try await harness.waitUntilSelection(head: selectedBodyTo, stage: "exact Mermaid source selection")
        let exactSelection = try #require(try await harness.session.currentSelection(
            for: harness.documentID,
            in: source
        ))
        #expect(exactSelection.excerpt == "A --> B")
        let selectedActive = try await snapshot()
        #expect(selectedActive["widgets"] as? Int == 0)
        #expect(selectedActive["openingFenceVisible"] as? Bool == true)
        #expect(selectedActive["closingFenceVisible"] as? Bool == true)
        #expect(try await harness.session.currentText(for: harness.documentID) == source)

        harness.session.goToLine(10)
        deadline = clock.now.advanced(by: .seconds(8))
        var exited = try await snapshot()
        while exited["rendered"] as? Int != 1 {
            if clock.now >= deadline {
                Issue.record("Mermaid did not rerender after direct exit: \(exited)")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(25))
            exited = try await snapshot()
        }
        #expect(exited["widgets"] as? Int == 1)
        #expect(exited["sourceLines"] as? Int == 0)
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
    }

    @Test("Active fenced code has one block surface and no visual blank after its closing fence")
    func activeFencedCodeUsesOneSurface() async throws {
        let source = "Before `inline`.\n\n```swift\nstruct Fixture {}\n```\n\nAfter.\n"
        let codeCaret = try #require(source.range(of: "struct Fixture")?.lowerBound)
            .utf16Offset(in: source) + 3
        let harness = EditorHarness(source: source)
        defer { harness.close() }
        try await harness.waitUntilReady()

        harness.session.revealSourceRange(fromUTF16: codeCaret, toUTF16: codeCaret)
        try await harness.waitUntilSelection(head: codeCaret, stage: "active fenced code")
        let snapshot = try #require(try await harness.callPageJavaScript(
            """
            const allLines = Array.from(document.querySelectorAll('.cm-line'));
            const blockLines = allLines.filter(line => line.classList.contains('cm-live-codeblock'));
            const closingFence = blockLines.find(
                line => (line.textContent || '').trim() === '```'
            );
            const closingIndex = closingFence ? allLines.indexOf(closingFence) : -1;
            const authoredBlank = closingIndex >= 0 ? allLines[closingIndex + 1] : null;
            return {
              blockLineCount: blockLines.length,
              activeBlockLineCount: blockLines.filter(
                line => line.classList.contains('cm-live-codeblock-active')
              ).length,
              fencedInlineCodeCount: blockLines.reduce(
                (count, line) => count + line.querySelectorAll('.cm-live-code').length,
                0
              ),
              totalInlineCodeCount: document.querySelectorAll('.cm-live-code').length,
              closingPaddingBottom: closingFence
                ? Number.parseFloat(getComputedStyle(closingFence).paddingBottom) || 0
                : -1,
              authoredBlankIsSourceLine: Boolean(
                authoredBlank?.classList.contains('cm-live-blank-line')
              ),
              authoredBlankUsesCodeSurface: Boolean(
                authoredBlank?.classList.contains('cm-live-codeblock')
              ),
              closingBackground: closingFence
                ? getComputedStyle(closingFence).backgroundColor
                : '',
              authoredBlankBackground: authoredBlank
                ? getComputedStyle(authoredBlank).backgroundColor
                : ''
            };
            """
        ) as? [String: Any])
        #expect(snapshot["blockLineCount"] as? Int == 3)
        #expect(snapshot["activeBlockLineCount"] as? Int == 3)
        #expect(snapshot["fencedInlineCodeCount"] as? Int == 0)
        #expect(snapshot["totalInlineCodeCount"] as? Int == 1)
        #expect(snapshot["closingPaddingBottom"] as? Double == 0)
        #expect(snapshot["authoredBlankIsSourceLine"] as? Bool == true)
        #expect(snapshot["authoredBlankUsesCodeSurface"] as? Bool == false)
        #expect((snapshot["authoredBlankBackground"] as? String)
            != (snapshot["closingBackground"] as? String))
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("The published editor mode changes only after the Web bridge acknowledges it")
    func presentedModeWaitsForBridgeAcknowledgement() async throws {
        let dispatcher = SuspendingModeBridgeDispatcher()
        let harness = EditorHarness(
            source: "# Mode handoff\n",
            bridgeDispatcher: dispatcher
        )
        defer { harness.close() }
        try await harness.waitUntilReady()
        let mermaidRuntime = try await harness.callPageJavaScript(
            "return window.scholiumMermaid?.version || 0"
        ) as? Int
        #expect(mermaidRuntime == 0)
        #expect(harness.session.presentedMode == .livePreview)
        var presentationPublications: [MarkdownEditorPresentationState] = []
        let observation = harness.session.$presentation.dropFirst().sink {
            presentationPublications.append($0)
        }

        harness.session.setMode(.source)
        try await dispatcher.waitUntilSuspended()
        #expect(harness.session.presentedMode == .livePreview)
        #expect(presentationPublications.isEmpty)

        dispatcher.resume()
        try await harness.waitUntilPresentedMode(.source)
        #expect(harness.session.presentedMode == .source)
        #expect(presentationPublications.map(\.documentPhase) == [.ready(.source)])
        _ = observation
        await harness.closeAndDrain()
    }

    @Test("A newer editor-mode request converges after an in-flight acknowledgement")
    func newerModeRequestConvergesAfterInflightAcknowledgement() async throws {
        let dispatcher = SuspendingModeBridgeDispatcher()
        let harness = EditorHarness(
            source: "# Mode convergence\n\nExact **Markdown**.\n",
            bridgeDispatcher: dispatcher
        )
        defer { harness.close() }
        try await harness.waitUntilReady()

        harness.session.setMode(.source)
        try await dispatcher.waitUntilSuspended()
        harness.session.setMode(.livePreview)
        dispatcher.resume()

        try await dispatcher.waitUntilModeRequestCount(2)
        try await harness.waitUntilPresentedMode(.livePreview)
        let final = try await harness.waitUntilPresentation(stage: "latest retained editor mode") {
            $0.liveModeClassCount == 1
                && $0.sourceModeClassCount == 0
                && $0.gutterCount == 0
        }
        #expect(final.label == "Markdown editor, Edit mode")
        #expect(dispatcher.requestedModes == [.source, .livePreview])
        await harness.closeAndDrain()
    }

    @Test("A transient mode transport failure retries idempotently before publication")
    func transientModeFailureRetriesBeforePublication() async throws {
        let dispatcher = FailingOnceModeBridgeDispatcher()
        let harness = EditorHarness(
            source: "# Retried mode\n\nExact **Markdown**.\n",
            bridgeDispatcher: dispatcher
        )
        defer { harness.close() }
        try await harness.waitUntilReady()
        var presentationPublications: [MarkdownEditorPresentationState] = []
        let observation = harness.session.$presentation.dropFirst().sink {
            presentationPublications.append($0)
        }

        harness.session.setMode(.source)
        try await harness.waitUntilPresentedMode(.source)
        let source = try await harness.waitUntilPresentation(stage: "retried Source mode") {
            $0.sourceModeClassCount == 1
                && $0.liveProjectionDOMCount == 0
        }

        #expect(source.label == "Markdown source editor")
        #expect(dispatcher.requestedModes == [.source, .source])
        #expect(presentationPublications.map(\.documentPhase) == [.ready(.source)])
        _ = observation
        await harness.closeAndDrain()
    }

    @Test("A mode request waits for marked-text composition before changing presentation")
    func modeChangeDefersUntilCompositionEnds() async throws {
        let source = "# Composition boundary\r\n\r\n研究输入 remains exact.\r\n"
        let harness = EditorHarness(source: source)
        defer { harness.close() }
        try await harness.waitUntilReady()

        try await harness.session.testingDispatchCompositionEvent("compositionstart")
        harness.session.setMode(.source)
        try await Task.sleep(for: .milliseconds(120))
        #expect(harness.session.presentedMode == .livePreview)
        let composing = try await harness.session.testingAccessibilitySnapshot()
        #expect(composing.label == "Markdown editor, Edit mode")
        #expect(composing.sourceModeClassCount == 0)

        try await harness.session.testingDispatchCompositionEvent("compositionend")
        try await harness.waitUntilPresentedMode(.source)
        let sourceMode = try await harness.waitUntilPresentation(stage: "post-composition Source") {
            $0.label == "Markdown source editor"
                && $0.sourceModeClassCount == 1
                && $0.liveProjectionDOMCount == 0
        }
        #expect(sourceMode.liveModeClassCount == 0)
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("Source mode preserves exact Markdown without semantic typography")
    func sourceModeUsesExactSourceTypography() async throws {
        let source = """
        # Exact heading

        **Bold source** and *italic source* and ~~struck source~~ and [linked source](https://example.test).
        """
        let harness = EditorHarness(source: source, initialMode: .source)
        defer { harness.close() }
        try await harness.waitUntilReady()

        harness.session.setMode(.source)
        let snapshot = try await harness.waitUntilPresentation(stage: "plain exact Source typography") {
            $0.sourceModeClassCount == 1
                && $0.liveModeClassCount == 0
                && $0.gutterCount > 0
                && $0.lineNumberCount > 0
        }
        #expect(snapshot.liveTitleCount == 0)
        #expect(snapshot.liveH1Count == 0)
        #expect(snapshot.sourceSemanticTypographyCount == 0)
        #expect(snapshot.liveProjectionDOMCount == 0)
        #expect(snapshot.selectionActionsCount == 0)
        #expect(snapshot.previewPopoverCount == 0)
        #expect(snapshot.visibleLineClassSummary.contains("**Bold source**"))
        #expect(snapshot.visibleLineClassSummary.contains("*italic source*"))
        #expect(snapshot.visibleLineClassSummary.contains("~~struck source~~"))
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("Edit and Source derive bidi direction without executing raw HTML")
    func bidiDirectionUsesTheVisibleLineAndKeepsRawHTMLInert() async throws {
        let source = """
        # Direction boundary

        هذا نص عربي مع **دليل عربي** و[مرجع عربي](https://example.test) والعدد 2026.

        זהו טקסט עברי עם Scholium והמספר 2026.

        <section dir="rtl">يبقى HTML الخام نصًا حرفيًا.</section>
        """
        let harness = EditorHarness(source: source)
        defer { harness.close() }
        try await harness.waitUntilReady()

        let edit = try #require(try await harness.callPageJavaScript(
            """
            const lines = [...document.querySelectorAll('.cm-line')];
            const find = token => lines.find(line => (line.textContent || '').includes(token));
            const arabic = find('هذا نص عربي');
            const hebrew = find('זהו טקסט עברי');
            const raw = document.querySelector('.cm-live-raw-html-widget');
            return {
              arabicAttribute: arabic?.getAttribute('dir') || '',
              arabicDirection: arabic ? getComputedStyle(arabic).direction : '',
              hebrewAttribute: hebrew?.getAttribute('dir') || '',
              hebrewDirection: hebrew ? getComputedStyle(hebrew).direction : '',
              rawDirection: raw ? getComputedStyle(raw).direction : '',
              executableSectionCount: document.querySelectorAll('section[dir="rtl"]').length,
            };
            """
        ) as? [String: Any])
        #expect(edit["arabicAttribute"] as? String == "auto")
        #expect(edit["arabicDirection"] as? String == "rtl")
        #expect(edit["hebrewAttribute"] as? String == "auto")
        #expect(edit["hebrewDirection"] as? String == "rtl")
        #expect(edit["rawDirection"] as? String == "ltr")
        #expect(edit["executableSectionCount"] as? Int == 0)

        harness.session.setMode(.source)
        try await harness.waitUntilPresentedMode(.source)
        let sourceMode = try #require(try await harness.callPageJavaScript(
            """
            const lines = [...document.querySelectorAll('.cm-line')];
            const find = token => lines.find(line => (line.textContent || '').includes(token));
            const isolates = [...document.querySelectorAll('.cm-iso')];
            const result = token => {
              const line = find(token);
              return {
                attribute: line?.getAttribute('dir') || '',
                direction: line ? getComputedStyle(line).direction : '',
              };
            };
            return {
              arabic: result('هذا نص عربي'),
              hebrew: result('זהו טקסט עברי'),
              raw: result('<section dir="rtl">'),
              autoMarkdownIsolate: isolates.some(element =>
                element.getAttribute('dir') === 'auto'
                  && (element.textContent || '').includes('**دليل عربي**')),
              ltrMarkdownIsolate: isolates.some(element =>
                element.getAttribute('dir') === 'ltr'
                  && (element.textContent || '').includes('[مرجع عربي](https://example.test)')),
              liveProjectionCount: document.querySelectorAll('[class*="cm-live-"]').length,
            };
            """
        ) as? [String: Any])
        let sourceArabic = try #require(sourceMode["arabic"] as? [String: Any])
        let sourceHebrew = try #require(sourceMode["hebrew"] as? [String: Any])
        let sourceRaw = try #require(sourceMode["raw"] as? [String: Any])
        #expect(sourceArabic["attribute"] as? String == "auto")
        #expect(sourceArabic["direction"] as? String == "rtl")
        #expect(sourceHebrew["attribute"] as? String == "auto")
        #expect(sourceHebrew["direction"] as? String == "rtl")
        #expect(sourceRaw["attribute"] as? String == "auto")
        #expect(sourceRaw["direction"] as? String == "ltr")
        #expect(sourceMode["autoMarkdownIsolate"] as? Bool == true)
        #expect(sourceMode["ltrMarkdownIsolate"] as? Bool == true)
        #expect(sourceMode["liveProjectionCount"] as? Int == 0)
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("RTL pointer placement and exact insertion remain writable in Source and Edit")
    func rtlTextRemainsWritableAcrossEditorModes() async throws {
        let source = """
        هذا نص عربي للاختبار.

        זהו טקסט עברי לבדיקה.
        """
        let harness = EditorHarness(source: source, initialMode: .source, laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()
        harness.session.focus()
        try await harness.waitUntilFocused()

        let arabicRange = try #require(source.range(of: "نص عربي"))
        let arabicFrom = arabicRange.lowerBound.utf16Offset(in: source)
        let arabicTo = arabicRange.upperBound.utf16Offset(in: source)
        try await harness.session.testingClickVisibleText("نص عربي")
        _ = try await harness.waitUntilSelection(in: arabicFrom..<arabicTo)
        let sourceSelection = try #require(harness.session.context?.selections.first)
        #expect(sourceSelection.anchor == sourceSelection.head)
        try await harness.session.perform(.pastePlain, argument: "س")
        let afterSourceInput = try await harness.session.currentText(for: harness.documentID)
        #expect(afterSourceInput.utf16.count == source.utf16.count + 1)
        #expect(afterSourceInput.hasPrefix("هذا "))

        harness.session.setMode(.livePreview)
        try await harness.waitUntilPresentedMode(.livePreview)
        let hebrewRange = try #require(afterSourceInput.range(of: "טקסט עברי"))
        let hebrewFrom = hebrewRange.lowerBound.utf16Offset(in: afterSourceInput)
        let hebrewTo = hebrewRange.upperBound.utf16Offset(in: afterSourceInput)
        try await harness.session.testingClickVisibleText("טקסט עברי")
        _ = try await harness.waitUntilSelection(in: hebrewFrom..<hebrewTo)
        let editSelection = try #require(harness.session.context?.selections.first)
        #expect(editSelection.anchor == editSelection.head)
        try await harness.session.perform(.pastePlain, argument: "א")
        let afterEditInput = try await harness.session.currentText(for: harness.documentID)
        #expect(afterEditInput.utf16.count == source.utf16.count + 2)
        #expect(afterEditInput.contains("זהו "))
        #expect(harness.latestSource == afterEditInput)
        #expect(harness.lifecycleSource == source)

        harness.setPresentationCSS(".cm-editor { --qa-unrelated-update: 1; }")
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await harness.session.currentText(for: harness.documentID) == afterEditInput)
        #expect(harness.lifecycleSource == source)
        await harness.closeAndDrain()
    }

    @Test("Selecting text does not highlight matching text elsewhere")
    func selectionDoesNotHighlightDocumentMatches() async throws {
        let source = "Repeated z appears beside z and another z.\n"
        let harness = EditorHarness(source: source)
        defer { harness.close() }
        try await harness.waitUntilReady()
        let selected = try #require(source.range(of: "z"))
        let from = selected.lowerBound.utf16Offset(in: source)
        let to = selected.upperBound.utf16Offset(in: source)

        harness.session.revealSourceRange(fromUTF16: from, toUTF16: to)
        _ = try await harness.waitUntilSelection(in: from..<(to + 1))
        let snapshot = try await harness.session.testingAccessibilitySnapshot()
        #expect(snapshot.selectionMatchCount == 0)
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("A delayed bridge success cannot mutate or block a replacement document")
    func delayedBridgeSuccessIsRejectedAfterReplacement() async throws {
        let dispatcher = SuspendingBridgeDispatcher(targetDocumentID: "Argument.md")
        let harness = EditorHarness(
            source: "Original A\n",
            bridgeDispatcher: dispatcher
        )
        defer { harness.close() }
        try await harness.waitUntilReady()

        let delayed = Task {
            try await harness.session.currentText(for: harness.documentID)
        }
        try await dispatcher.waitUntilSuspended()

        harness.session.loadDocument(
            "Replacement B\n",
            documentID: "Replacement.md",
            mode: .livePreview
        )
        try await harness.waitUntilLoaded(documentID: "Replacement.md")
        #expect(try await harness.session.currentText(for: "Replacement.md") == "Replacement B\n")

        dispatcher.resumeSuccessfully()
        do {
            _ = try await delayed.value
            Issue.record("The stale A request unexpectedly succeeded after B loaded.")
        } catch MarkdownEditorSession.SessionError.staleRequest {
            // Expected: identity validation owns the result, not transport order.
        } catch {
            Issue.record("The stale A request returned the wrong error: \(error).")
        }

        #expect(harness.session.documentID == "Replacement.md")
        #expect(harness.session.errorMessage == nil)
        #expect(try await harness.session.currentText(for: "Replacement.md") == "Replacement B\n")
        await harness.closeAndDrain()
    }

    @Test("A text snapshot remains valid when the same document advances")
    func textSnapshotToleratesSameDocumentInput() async throws {
        let dispatcher = SuspendingBridgeDispatcher(targetDocumentID: "Argument.md")
        let harness = EditorHarness(
            source: "Original A\n",
            bridgeDispatcher: dispatcher
        )
        defer { harness.close() }
        try await harness.waitUntilReady()

        let snapshot = Task {
            try await harness.session.currentTextSnapshot(for: harness.documentID)
        }
        try await dispatcher.waitUntilSuspended()

        // The snapshot read must not own the source-mutation lane. CodeMirror
        // may accept a later transaction while the read is in transport.
        try await harness.session.perform(.pastePlain, argument: "x")
        dispatcher.resumeSuccessfully()

        let captured = try await snapshot.value
        #expect(captured.text == "xOriginal A\n")
        #expect(captured.generation == 1)
        #expect(harness.session.checkedSource == captured.text)
        #expect(harness.session.errorMessage == nil)
        await harness.closeAndDrain()
    }

    @Test("A committed autosave snapshot never replaces newer input")
    func committedSnapshotKeepsNewerInputDirty() async throws {
        let source = "Original A\n"
        let harness = EditorHarness(source: source)
        defer { harness.close() }
        try await harness.waitUntilReady()
        let savedSnapshot = try await harness.session.currentTextSnapshot(
            for: harness.documentID
        )

        try await harness.session.perform(.pastePlain, argument: "x")
        let newerSource = "xOriginal A\n"
        #expect(harness.session.checkedSource == newerSource)

        let committedFingerprint = DocumentFingerprint(content: source)
        let acknowledgement = try await harness.session.acknowledgeCommittedSnapshot(
            expectedText: savedSnapshot.text,
            committedText: source,
            fingerprint: committedFingerprint,
            documentID: harness.documentID
        )

        #expect(acknowledgement == .superseded)
        #expect(harness.session.checkedSource == newerSource)
        #expect(harness.session.isDirty)
        #expect(harness.session.startingFingerprint == committedFingerprint.sha256)
        #expect(try await harness.session.currentText(for: harness.documentID) == newerSource)
        await harness.closeAndDrain()
    }

    @Test("A delayed bridge transport error is hidden from a replacement document")
    func delayedBridgeErrorIsRejectedAfterReplacement() async throws {
        let dispatcher = SuspendingBridgeDispatcher(targetDocumentID: "Argument.md")
        let harness = EditorHarness(
            source: "Original A\n",
            bridgeDispatcher: dispatcher
        )
        defer { harness.close() }
        try await harness.waitUntilReady()

        let delayed = Task {
            try await harness.session.currentText(for: harness.documentID)
        }
        try await dispatcher.waitUntilSuspended()

        harness.session.loadDocument(
            "Replacement B\n",
            documentID: "Replacement.md",
            mode: .livePreview
        )
        try await harness.waitUntilLoaded(documentID: "Replacement.md")
        #expect(try await harness.session.currentText(for: "Replacement.md") == "Replacement B\n")

        dispatcher.resumeWithTransportError()
        do {
            _ = try await delayed.value
            Issue.record("The stale A transport failure unexpectedly succeeded.")
        } catch MarkdownEditorSession.SessionError.staleRequest {
            // Expected: B must not inherit A's transport failure.
        } catch {
            Issue.record("The stale A transport failure escaped identity validation: \(error).")
        }

        #expect(harness.session.documentID == "Replacement.md")
        #expect(harness.session.errorMessage == nil)
        #expect(try await harness.session.currentText(for: "Replacement.md") == "Replacement B\n")
        await harness.closeAndDrain()
    }

    @Test("A hanging bridge request times out without poisoning the editor")
    func hangingBridgeRequestIsBoundedAndRetryable() async throws {
        let dispatcher = SuspendingBridgeDispatcher(targetDocumentID: "Argument.md")
        var policy = ScholiumLifecyclePolicy()
        policy.bridgeRequest = .milliseconds(30)
        let harness = EditorHarness(
            source: "Retryable\n",
            bridgeDispatcher: dispatcher,
            lifecyclePolicy: policy
        )
        defer { harness.close() }
        try await harness.waitUntilReady()

        let request = Task {
            try await harness.session.currentText(for: harness.documentID)
        }
        try await dispatcher.waitUntilSuspended()
        do {
            _ = try await request.value
            Issue.record("A hanging editor bridge request incorrectly succeeded")
        } catch let error as ScholiumWindowLifecycleError {
            #expect(error == .timedOut(.bridgeRequest))
        } catch {
            Issue.record("Unexpected editor bridge deadline error: \(error)")
        }

        dispatcher.resumeSuccessfully()
        #expect(try await harness.session.currentText(for: harness.documentID) == "Retryable\n")
        #expect(harness.session.errorMessage == nil)
        await harness.closeAndDrain()
    }

    @Test("One hundred thousand CJK characters preserve an exact CRLF edit across modes")
    func largeCJKExactRoundTrip() async throws {
        let seed = "研究性能边界输入选择撤销渲染滚动保存恢复"
        let cjkCharacters = String(
            String(repeating: seed, count: 100_000 / seed.count + 1).prefix(100_000)
        )
        let normalizedSource = "---\ntitle: WK 100k CJK\n---\n# CJK Stress\n\n\(cjkCharacters)\n"
        let source = normalizedSource.replacingOccurrences(of: "\n", with: "\r\n")
        let token = "QA-CJK-END-\(UUID().uuidString)"
        let harness = EditorHarness(source: source, laysOutForPointerTesting: true)
        defer { harness.close() }

        try await harness.waitUntilReady()
        harness.session.goToLine(
            normalizedSource.split(separator: "\n", omittingEmptySubsequences: false).count
        )
        try await harness.waitUntilSelection(head: normalizedSource.utf16.count)
        try await harness.session.perform(.pastePlain, argument: token)

        let edited = try await harness.session.currentText(for: harness.documentID)
        #expect(Data(edited.utf8) == Data((source + token).utf8))
        #expect(harness.latestSource == source + token)
        #expect(harness.session.isDirty)
        let exactUpdate = try #require(
            try await harness.session.queryPerformanceSamples().last {
                $0.name == "exact-source-update"
            }
        )
        #expect(exactUpdate.observed["changeCount"] == 1)
        #expect((exactUpdate.observed["documentLength"] ?? 0) >= 100_000)

        harness.session.setMode(.source)
        _ = try await harness.waitUntilPresentation(stage: "100k Source mode") {
            $0.label == "Markdown source editor" && $0.gutterCount > 0
        }
        harness.session.setMode(.livePreview)
        _ = try await harness.waitUntilPresentation(stage: "100k Live Preview") {
            $0.label == "Markdown editor, Edit mode" && $0.gutterCount == 0
        }
        #expect(try await harness.session.currentText(for: harness.documentID) == source + token)
        await harness.closeAndDrain()
    }

    @Test("A plain Editor loads mathematics only after the first authored expression")
    func plainEditorLoadsMathRuntimeOnDemand() async throws {
        let plainSource = "Other paragraph.\n\nInline "
        #expect(!MarkdownEditorWebView.requiresMathRuntime(
            source: plainSource,
            linkPreviews: []
        ))
        let end = plainSource.utf16.count
        let harness = EditorHarness(
            source: plainSource,
            initialSourceRange: end..<end
        )
        defer { harness.close() }

        try await harness.waitUntilReady()
        try await harness.session.perform(.pastePlain, argument: "$x$.\n")
        harness.synchronizeLifecycleSourceFromSession()
        harness.session.revealSourceRange(fromUTF16: 0, toUTF16: 0)
        try await harness.waitUntilSelection(head: 0)
        harness.session.setMode(.source)
        try await harness.waitUntilPresentedMode(.source)
        harness.session.setMode(.livePreview)
        try await harness.waitUntilPresentedMode(.livePreview)
        let presentation = try await harness.waitUntilPresentation(
            stage: "on-demand mathematics runtime"
        ) {
            $0.renderedMathCount == 1 && $0.mathErrorCount == 0
        }
        #expect(presentation.renderedMathCount == 1)
        #expect(
            try await harness.session.currentText(for: harness.documentID)
                == "Other paragraph.\n\nInline $x$.\n"
        )
    }

    @Test("Exact UTF-16 reveal selects source without changing bytes, generation, or undo")
    func exactSourceRangeRevealIsNonmutating() async throws {
        let source = "# Search\n\nBefore 🧭 autonomy after.\n"
        let nsSource = source as NSString
        let range = nsSource.range(of: "autonomy")
        let harness = EditorHarness(source: source)
        defer { harness.close() }
        try await harness.waitUntilReady()

        let generation = harness.session.generation
        let undoLabel = harness.session.context?.undoLabel
        harness.session.revealSourceRange(
            fromUTF16: range.location,
            toUTF16: NSMaxRange(range)
        )
        try await harness.waitUntilSelection(head: NSMaxRange(range))

        let selection = try #require(try await harness.session.currentSelection(
            for: harness.documentID,
            in: source
        ))
        #expect(selection.excerpt == "autonomy")
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        #expect(harness.session.generation == generation)
        #expect(harness.session.context?.undoLabel == undoLabel)
        #expect(!harness.session.isDirty)
        await harness.closeAndDrain()
    }

    @Test("Edit reveals only the selected inline construct and preserves its semantic style")
    func editInlineSyntaxActivationIsConstructScoped() async throws {
        let probe = "INLINE_SYNTAX_PROBE"
        let source = """
        # Inline projection

        \(probe) before **First** between **Second**, *Third* or *Fourth*, ~~Fifth~~, ==Sixth==, `Seventh`, and [Eighth](https://example.test).
        """
        let harness = EditorHarness(source: source)
        defer { harness.close() }
        try await harness.waitUntilReady()

        let generation = harness.session.generation
        let undoLabel = harness.session.context?.undoLabel
        let caret = { (sourceToken: String, leadingMarkerLength: Int) throws -> Int in
            let range = try #require(source.range(of: sourceToken))
            return range.lowerBound.utf16Offset(in: source) + leadingMarkerLength + 1
        }
        let moveCaret = { (offset: Int) async throws in
            harness.session.revealSourceRange(fromUTF16: offset, toUTF16: offset)
            try await harness.waitUntilSelection(head: offset)
        }

        try await moveCaret(try caret("before", 0))
        let inactive = try await harness.session.testingInlineProjectionSnapshot(containing: probe)
        #expect(inactive.lineText == "\(probe) before First between Second, Third or Fourth, Fifth, Sixth, Seventh, and Eighth.")
        #expect(inactive.strongTexts == ["First", "Second"])
        #expect(inactive.emphasisTexts == ["Third", "Fourth"])
        #expect(inactive.strikethroughTexts == ["Fifth"])
        #expect(inactive.highlightTexts == ["Sixth"])
        #expect(inactive.highlightBackgrounds == ["rgb(255, 154, 0)"])
        #expect(inactive.highlightColors == ["rgb(40, 36, 29)"])
        #expect(inactive.codeTexts == ["Seventh"])
        #expect(inactive.linkTexts == ["Eighth"])

        let firstCaret = try caret("**First**", 2)
        try await moveCaret(firstCaret)
        let activeStrong = try await harness.session.testingInlineProjectionSnapshot(containing: probe)
        #expect(activeStrong.lineText == "\(probe) before **First** between Second, Third or Fourth, Fifth, Sixth, Seventh, and Eighth.")
        #expect(activeStrong.strongTexts == ["**First**", "Second"])
        #expect(activeStrong.strongWeights.allSatisfy { $0 == "700" })

        let scopedProjectionCount = try await harness.session.queryPerformanceSamples().filter {
            $0.name == "projection" && $0.observed["selectionScoped"] == 1
        }.count
        try await moveCaret(firstCaret + 1)
        let sameConstructProjectionCount = try await harness.session.queryPerformanceSamples().filter {
            $0.name == "projection" && $0.observed["selectionScoped"] == 1
        }.count
        #expect(sameConstructProjectionCount == scopedProjectionCount)

        try await moveCaret(try caret("*Third*", 1))
        let activeEmphasis = try await harness.session.testingInlineProjectionSnapshot(containing: probe)
        #expect(activeEmphasis.lineText == "\(probe) before First between Second, *Third* or Fourth, Fifth, Sixth, Seventh, and Eighth.")
        #expect(activeEmphasis.emphasisTexts == ["*Third*", "Fourth"])
        #expect(activeEmphasis.emphasisStyles.allSatisfy { $0 == "italic" })

        try await moveCaret(try caret("~~Fifth~~", 2))
        let activeStrike = try await harness.session.testingInlineProjectionSnapshot(containing: probe)
        #expect(activeStrike.strikethroughTexts == ["~~Fifth~~"])
        #expect(!activeStrike.lineText.contains("*Third*"))

        try await moveCaret(try caret("==Sixth==", 2))
        let activeHighlight = try await harness.session.testingInlineProjectionSnapshot(containing: probe)
        #expect(activeHighlight.highlightTexts == ["==Sixth=="])
        #expect(!activeHighlight.lineText.contains("~~Fifth~~"))

        try await moveCaret(try caret("`Seventh`", 1))
        let activeCode = try await harness.session.testingInlineProjectionSnapshot(containing: probe)
        #expect(activeCode.codeTexts == ["`Seventh`"])
        #expect(!activeCode.lineText.contains("==Sixth=="))

        try await moveCaret(try caret("[Eighth](https://example.test)", 1))
        let activeLink = try await harness.session.testingInlineProjectionSnapshot(containing: probe)
        #expect(activeLink.linkTexts == ["[Eighth](https://example.test)"])
        #expect(!activeLink.lineText.contains("`Seventh`"))

        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        #expect(harness.session.generation == generation)
        #expect(harness.session.context?.undoLabel == undoLabel)
        #expect(!harness.session.isDirty)
        await harness.closeAndDrain()
    }

    @Test("Pointer selection defers syntax reveal until mouse-up")
    func pointerSelectionDefersSyntaxRevealUntilMouseUp() async throws {
        let source = "Lead **bold syntax** between *italic syntax* tail.\n\nFollowing paragraph.\n"
        let harness = EditorHarness(source: source, laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()
        harness.session.focus()
        try await harness.waitUntilFocused()

        let result = try await harness.session.testingDragSelectionProjection(
            from: "Lead",
            to: "italic syntax",
            lineContaining: "Lead"
        )
        let selection = try #require(try await harness.session.currentSelection(
            for: harness.documentID,
            in: source
        ))
        #expect(!selection.excerpt.isEmpty)
        #expect(selection.excerpt.contains("bold syntax"))
        #expect(selection.excerpt.contains("italic s"))
        #expect(result.duringDragLineText == "Lead bold syntax between italic syntax tail.")
        #expect(result.afterMouseUpLineText.contains("**bold syntax**"))
        #expect(result.afterMouseUpLineText.contains("*italic syntax*"))
        #expect(result.toolbarHiddenDuringDrag)
        #expect(result.toolbarVisibleAfterMouseUp)
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("A plain click on projected inline syntax inserts one caret")
    func projectedInlineClickInsertsOneCaret() async throws {
        let source = "Before **Obsidian** after.\n"
        let construct = try #require(source.range(of: "**Obsidian**"))
        let from = construct.lowerBound.utf16Offset(in: source)
        let to = construct.upperBound.utf16Offset(in: source)
        let harness = EditorHarness(source: source, laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()

        try await harness.session.testingClickVisibleText("Obsidian")
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while true {
            if let selection = harness.session.context?.selections.first,
               selection.anchor == selection.head,
               selection.head >= from,
               selection.head < to {
                break
            }
            if clock.now >= deadline {
                Issue.record("A plain projected-syntax click did not publish one caret inside the construct.")
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let selection = try #require(harness.session.context?.selections.first)
        #expect(selection.anchor == selection.head)
        #expect(selection.head >= from && selection.head < to)
        let active = try await harness.session.testingInlineProjectionSnapshot(containing: "Obsidian")
        #expect(active.lineText == "Before **Obsidian** after.")
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("Edit selection paints source characters without blank-line rectangles")
    func editSelectionPaintsOnlySourceCharacters() async throws {
        let source = "First paragraph text.\n\nSecond paragraph text.\n"
        let firstFrom = try #require(source.range(of: "paragraph text"))
            .lowerBound.utf16Offset(in: source)
        let secondTo = try #require(source.range(of: "Second paragraph"))
            .upperBound.utf16Offset(in: source)
        let harness = EditorHarness(source: source)
        defer { harness.close() }
        try await harness.waitUntilReady()

        harness.session.revealSourceRange(fromUTF16: firstFrom, toUTF16: secondTo)
        try await harness.waitUntilSelection(head: secondTo, stage: "cross-paragraph selection")
        let snapshot = try await harness.session.testingEditorSelectionPresentationSnapshot()
        #expect(snapshot.selectedTexts == ["paragraph text.", "Second paragraph"])
        #expect(snapshot.selectedRunCount == 2)
        #expect(snapshot.selectedBlankLineRunCount == 0)
        #expect(snapshot.visibleStockRectangleCount == 0)
        #expect(snapshot.nativeSelectionBackground == "rgba(0, 0, 0, 0)")
        #expect(snapshot.selectedBackgroundsMatchAccent)
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("Deleting a block-safe date retains one cursor owner across Edit and Source")
    func deletingDateRetainsOneCursorOwner() async throws {
        let date = "2026-08-03"
        let source = "Before.\n\n\(date)\n\nAfter.\n"
        let dateEnd = try #require(source.range(of: date)?.upperBound.utf16Offset(in: source))
        let expected = source.replacingOccurrences(of: date, with: "")
        let harness = EditorHarness(source: source, laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()

        harness.session.focus()
        try await harness.waitUntilFocused()
        harness.session.revealSourceRange(fromUTF16: dateEnd, toUTF16: dateEnd)
        try await harness.waitUntilSelection(head: dateEnd, stage: "date insertion point")
        for _ in date {
            try await harness.session.testingPressBackspace()
        }
        #expect(try await harness.session.currentText(for: harness.documentID) == expected)

        let snapshot = try await harness.session.testingEditorSelectionPresentationSnapshot()
        #expect(snapshot.nativeCaretIsTransparent)
        #expect(snapshot.drawnCursorCount == 1)
        #expect(snapshot.visibleStockRectangleCount == 0)

        harness.session.setMode(.source)
        try await harness.waitUntilPresentedMode(.source)
        let sourceSnapshot = try await harness.session.testingEditorSelectionPresentationSnapshot()
        #expect(sourceSnapshot.nativeCaretIsTransparent)
        #expect(sourceSnapshot.drawnCursorCount == 1)
        #expect(sourceSnapshot.visibleStockRectangleCount == 0)
        #expect(try await harness.session.currentText(for: harness.documentID) == expected)
        await harness.closeAndDrain()
    }

    @Test("Triple-click selects one paragraph and reveals syntax immediately")
    func tripleClickSelectsOneParagraphWithoutLayoutSpace() async throws {
        let source = "First **bold** paragraph.\n\nSecond paragraph.\n"
        let firstLineTo = source.firstIndex(of: "\n")?.utf16Offset(in: source) ?? 0
        let harness = EditorHarness(source: source, laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()

        try await harness.session.testingTripleClickVisibleText("bold")
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while harness.session.context?.selections.first?.anchor
            == harness.session.context?.selections.first?.head
        {
            if clock.now >= deadline {
                Issue.record("Triple-click did not publish a paragraph selection.")
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let selection = try #require(harness.session.context?.selections.first)
        #expect(selection.anchor != selection.head)
        #expect(min(selection.anchor, selection.head) >= 0)
        #expect(max(selection.anchor, selection.head) <= firstLineTo + 1)
        let active = try await harness.session.testingInlineProjectionSnapshot(containing: "bold")
        #expect(active.lineText == "First **bold** paragraph.")
        let presentation = try await harness.session.testingEditorSelectionPresentationSnapshot()
        #expect(presentation.selectedBlankLineRunCount == 0)
        #expect(presentation.visibleStockRectangleCount == 0)
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("Source triple-click does not paint the next logical line as active")
    func sourceTripleClickDoesNotActivateFollowingLine() async throws {
        let source = """
        This is deterministic, disposable, nonprivate test material. It contains no real
        source claims and makes no philosophical attribution.
        > [!orient] Reading route
        """
        let harness = EditorHarness(
            source: source,
            initialMode: .source,
            laysOutForPointerTesting: true
        )
        defer { harness.close() }
        try await harness.waitUntilReady()
        harness.session.focus()
        try await harness.waitUntilFocused()

        try await harness.session.testingTripleClickVisibleText("nonprivate")
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while harness.session.context?.selections.first?.anchor
            == harness.session.context?.selections.first?.head
        {
            if clock.now >= deadline {
                Issue.record("Source triple-click did not publish a logical-line selection.")
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let selected = try await harness.session.testingEditorSelectionPresentationSnapshot()
        #expect(selected.selectedTexts.joined() == String(source.split(separator: "\n")[0]))
        #expect(selected.activeLineTexts.isEmpty)
        #expect(selected.activeLineGutterCount == 0)

        let secondLineStart = try #require(source.range(of: "source claims"))
            .lowerBound.utf16Offset(in: source)
        harness.session.revealSourceRange(fromUTF16: secondLineStart, toUTF16: secondLineStart)
        let collapseDeadline = clock.now.advanced(by: .seconds(3))
        while harness.session.context?.selections.first.map({ selection in
            selection.anchor == secondLineStart && selection.head == secondLineStart
        }) != true {
            if clock.now >= collapseDeadline {
                Issue.record("Source selection did not collapse after triple-click.")
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let collapsed = try await harness.session.testingEditorSelectionPresentationSnapshot()
        #expect(collapsed.activeLineTexts == ["source claims and makes no philosophical attribution."])
        #expect(collapsed.activeLineGutterCount > 0)
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("Callout content boundaries, nested links, and arrows share one source projection")
    func calloutContentBoundaryAndNestedLinksShareOneProjection() async throws {
        let calloutSource = """
        > [!cite]- Synthetic source boundary
        > +[[analysis-001|support]]; body ends with [[work-031|linked note]].
        """
        let source = "Lead.\n\n\(calloutSource)\n\nAfter.\n"
        let range = try #require(source.range(of: calloutSource))
        let calloutFrom = range.lowerBound.utf16Offset(in: source)
        let calloutTo = range.upperBound.utf16Offset(in: source)
        let linkRange = try #require(source.range(of: "[[work-031|linked note]]"))
        let linkFrom = linkRange.lowerBound.utf16Offset(in: source)
        let linkTo = linkRange.upperBound.utf16Offset(in: source)
        let vectorLinkRange = try #require(source.range(of: "+[[analysis-001|support]]"))
        let vectorLinkTo = vectorLinkRange.upperBound.utf16Offset(in: source)
        let harness = EditorHarness(source: source, laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()
        do {
            _ = try await harness.waitUntilPresentation(stage: "inactive nested-link Callout") {
                $0.liveCalloutWidgetCount == 1 && $0.activeLiveBlockKind.isEmpty
            }
        } catch {
            Issue.record("Inactive nested-link Callout presentation failed: \(error)")
            throw error
        }
        let inactive: MarkdownEditorSession.TestingCalloutProjectionSnapshot
        do {
            inactive = try await harness.session.testingCalloutProjectionSnapshot(
                containing: "Synthetic source boundary"
            )
        } catch {
            Issue.record("Inactive Callout link projection snapshot failed: \(error)")
            throw error
        }
        #expect(inactive.renderedLinkTexts == ["support", "linked note"])
        #expect(inactive.renderedLinkTargets == ["analysis-001", "work-031"])
        #expect(inactive.renderedLinkCaretOffsets == [vectorLinkTo, linkTo])
        #expect(inactive.renderedLinkIconNames == ["plus", "link"])
        #expect(inactive.renderedLinkIconMaskCount == 2)

        do {
            try await harness.session.testingClickFirstCalloutText("linked note")
        } catch {
            Issue.record("Projected Callout Wikilink click failed: \(error)")
            throw error
        }
        try await harness.waitUntilSelection(head: linkTo, stage: "Wikilink projected end boundary")
        let projectedLink = try await harness.session.testingInlineProjectionSnapshot(
            containing: "linked note"
        )
        #expect(projectedLink.wikiLinkTexts.contains("linked note"))
        #expect(!projectedLink.lineText.contains("[[work-031|linked note]]"))

        try await harness.session.testingPressArrow("ArrowLeft")
        try await harness.waitUntilSelection(
            head: linkTo - 1,
            stage: "Wikilink exact closing syntax entry"
        )
        let activeLink = try await harness.session.testingInlineProjectionSnapshot(
            containing: "linked note"
        )
        #expect(activeLink.lineText.contains("[[work-031|linked note]]"))

        harness.session.revealSourceRange(fromUTF16: linkFrom, toUTF16: linkFrom)
        try await harness.waitUntilSelection(head: linkFrom, stage: "Wikilink keyboard start boundary")
        try await harness.session.testingPressArrow("ArrowRight")
        try await harness.waitUntilSelection(head: linkTo, stage: "Wikilink keyboard end boundary")
        let keyboardProjectedLink = try await harness.session.testingInlineProjectionSnapshot(
            containing: "linked note"
        )
        #expect(keyboardProjectedLink.wikiLinkTexts.contains("linked note"))

        harness.session.goToLine(1)
        _ = try await harness.waitUntilPresentation(stage: "Callout restored before modified link") {
            $0.liveCalloutWidgetCount == 1 && $0.activeLiveBlockKind.isEmpty
        }
        try await harness.session.testingModifiedClickVisibleText(
            "linked note",
            modifierFlags: .control
        )
        let activationDeadline = ContinuousClock().now.advanced(by: .seconds(3))
        while harness.activatedLinks != ["work-031"] {
            if ContinuousClock().now >= activationDeadline {
                Issue.record("Control-click did not activate the projected Callout link.")
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(harness.activatedLinks == ["work-031"])

        try await harness.session.testingClickFirstCalloutText("body ends")
        try await harness.waitUntilSelection(head: calloutTo)
        let projectedHeader = try await harness.session.testingInlineProjectionSnapshot(
            containing: "Synthetic source boundary"
        )
        #expect(projectedHeader.lineText.contains("Synthetic source boundary"))
        #expect(!projectedHeader.lineText.contains("> [!cite]"))
        let activeBody = try await harness.session.testingInlineProjectionSnapshot(
            containing: "body ends"
        )
        #expect(activeBody.lineText.contains("> support; body ends"))
        #expect(!activeBody.lineText.contains("+[[analysis-001|support]]"))
        try await harness.session.perform(.pastePlain, argument: "继续")
        let editedTo = calloutTo + 2
        try await harness.waitUntilSelection(head: editedTo)
        let edited = try await harness.session.currentText(for: harness.documentID)
        #expect(edited.contains("> +[[analysis-001|support]]; body ends with [[work-031|linked note]].继续"))
        try await harness.session.testingPressArrow("ArrowRight")
        try await harness.waitUntilSelection(head: editedTo + 1, stage: "real separator after Callout")
        _ = try await harness.waitUntilPresentation(stage: "Callout restored after separator entry") {
            $0.liveCalloutWidgetCount == 1 && $0.activeLiveBlockKind.isEmpty
        }

        harness.session.goToLine(2)
        let blankBefore = calloutFrom - 1
        try await harness.waitUntilSelection(head: blankBefore, stage: "real separator before Callout")
        try await harness.session.testingPressArrow("ArrowRight")
        try await harness.waitUntilSelection(head: calloutFrom, stage: "right-arrow Callout entry")
        try await harness.session.testingPressArrow("ArrowRight")
        try await harness.waitUntilSelection(head: calloutFrom + 1, stage: "right-arrow inside Callout")
        await harness.closeAndDrain()
    }

    @Test("Callout Return continues one visible block and a second Return exits")
    func calloutReturnContinuesOneVisibleBlockThenExits() async throws {
        let calloutHeader = "> [!orient] Reading **route**"
        let source = "Lead.\n\n" + calloutHeader
        let headerEnd = source.utf16.count
        let harness = EditorHarness(source: source)
        defer { harness.close() }
        try await harness.waitUntilReady()
        harness.session.focus()
        try await harness.waitUntilFocused()

        _ = try await harness.waitUntilPresentation(stage: "title-only Orient projection") {
            $0.liveCalloutWidgetCount == 1 && $0.activeLiveBlockKind.isEmpty
        }
        let titleOnly = try await harness.session.testingCalloutProjectionSnapshot(
            containing: "Reading route"
        )
        #expect(titleOnly.renderedTitleText.isEmpty)
        #expect(titleOnly.renderedBodyText.contains("Reading route"))

        harness.session.revealSourceRange(fromUTF16: headerEnd, toUTF16: headerEnd)
        try await harness.waitUntilSelection(head: headerEnd, stage: "active Orient header")
        try await harness.session.testingPressEnter()
        let continuedSource = source + "\n> "
        try await harness.waitUntilSelection(
            head: continuedSource.utf16.count,
            stage: "continued Callout line"
        )
        let continueDeadline = ContinuousClock().now.advanced(by: .seconds(3))
        while try await harness.session.currentText(for: harness.documentID) != continuedSource {
            if ContinuousClock().now >= continueDeadline {
                Issue.record("Return did not continue the Callout with one quote prefix.")
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(harness.session.context?.undoLabel == "Continue Callout")

        let active = try await harness.waitUntilPresentation(stage: "line-scoped Callout source") {
            $0.activeLiveBlockKind == "callout" && $0.liveCalloutSourceLineCount == 2
        }
        #expect(active.exactCalloutSourceCount == 0)
        let activeProjection = try await harness.session.testingCalloutProjectionSnapshot(
            containing: "Reading route"
        )
        #expect(activeProjection.activeSourceLineTexts.count == 2)
        #expect(activeProjection.activeSourceLineClassNames[0]
            .contains("cm-live-callout-projected-line"))
        #expect(activeProjection.activeSourceLineClassNames[1]
            .contains("cm-live-callout-active-line"))
        #expect(activeProjection.activeSourceLineTexts[0]
            .trimmingCharacters(in: .whitespaces) == "Reading route")
        #expect(activeProjection.activeSourceLineTexts[1].trimmingCharacters(in: .whitespaces) == ">")
        #expect(Set(activeProjection.activeSourceLineBackgrounds).count == 1)
        #expect(activeProjection.activeSourceLineBackgrounds.allSatisfy {
            $0 != "transparent" && $0 != "rgba(0, 0, 0, 0)"
        })
        try await harness.session.testingPressEnter()
        let exitedSource = source + "\n"
        try await harness.waitUntilSelection(
            head: exitedSource.utf16.count,
            stage: "Callout exit line"
        )
        let exitDeadline = ContinuousClock().now.advanced(by: .seconds(3))
        while try await harness.session.currentText(for: harness.documentID) != exitedSource {
            if ContinuousClock().now >= exitDeadline {
                Issue.record("A second Return retained an empty Callout quote prefix.")
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(harness.session.context?.undoLabel == "Exit Callout")
        _ = try await harness.waitUntilPresentation(stage: "title-only Orient restored") {
            $0.activeLiveBlockKind.isEmpty && $0.liveCalloutWidgetCount == 1
        }
        let restored = try await harness.session.testingCalloutProjectionSnapshot(
            containing: "Reading route"
        )
        #expect(restored.renderedBodyText.contains("Reading route"))
        #expect(try await harness.session.currentText(for: harness.documentID) == exitedSource)
        await harness.closeAndDrain()
    }

    @Test("Callout Return continues its current list level")
    func calloutReturnContinuesCurrentListLevel() async throws {
        let source = "> [!state] Claims\n> - First claim"
        let expected = source + "\n> - "
        let harness = EditorHarness(source: source, laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()
        harness.session.focus()
        try await harness.waitUntilFocused()

        harness.session.revealSourceRange(
            fromUTF16: source.utf16.count,
            toUTF16: source.utf16.count
        )
        try await harness.waitUntilSelection(head: source.utf16.count)
        let bodyActive = try await harness.session.testingCalloutProjectionSnapshot(
            containing: "Claims"
        )
        #expect(bodyActive.activeSourceLineClassNames[0]
            .contains("cm-live-callout-projected-line"))
        #expect(bodyActive.activeSourceLineClassNames[1]
            .contains("cm-live-callout-active-line"))
        try await harness.session.testingPressEnter()

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while try await harness.session.currentText(for: harness.documentID) != expected {
            if clock.now >= deadline {
                let actual = try await harness.session.currentText(for: harness.documentID)
                Issue.record("Return did not retain the Callout quote and list prefixes. Actual source: \(String(reflecting: actual)); selections: \(String(describing: harness.session.context?.selections)); undo label: \(harness.session.context?.undoLabel ?? "nil")")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        try await harness.waitUntilSelection(head: expected.utf16.count)
        #expect(harness.session.context?.undoLabel == "Continue List")
        let active = try await harness.waitUntilPresentation(stage: "continued Callout list") {
            $0.activeLiveBlockKind == "callout" && $0.liveCalloutSourceLineCount == 3
        }
        #expect(active.liveCalloutWidgetCount == 0)

        try await harness.session.perform(.pastePlain, argument: "Second claim")
        let completed = expected + "Second claim"
        #expect(try await harness.session.currentText(for: harness.documentID) == completed)
        let continued = try await harness.session.testingCalloutProjectionSnapshot(
            containing: "Claims"
        )
        #expect(continued.activeSourceLineTexts.contains { $0.contains("First claim") })
        #expect(continued.activeSourceLineTexts.contains { $0.contains("Second claim") })
        await harness.closeAndDrain()
    }

    @Test("Active Callout title retains its role typography")
    func activeCalloutTitleRetainsRoleTypography() async throws {
        let source = "Before.\n\n> [!connect] Curated connections\n> - First claim\n\nAfter.\n"
        let harness = EditorHarness(source: source)
        defer { harness.close() }
        try await harness.waitUntilReady()

        harness.session.goToLine(1)
        _ = try await harness.waitUntilPresentation(stage: "inactive Connect Callout") {
            $0.liveCalloutWidgetCount == 1 && $0.activeLiveBlockKind.isEmpty
        }
        let inactive = try await harness.session.testingCalloutProjectionSnapshot(
            containing: "Curated connections"
        )
        #expect(inactive.renderedTitleFontWeight == "550")
        #expect(inactive.renderedTitleFontStyle == "italic")

        let bodyCaret = try #require(source.range(of: "First claim")?.lowerBound)
            .utf16Offset(in: source) + 2
        harness.session.revealSourceRange(fromUTF16: bodyCaret, toUTF16: bodyCaret)
        try await harness.waitUntilSelection(head: bodyCaret)
        let bodyActive = try await harness.session.testingCalloutProjectionSnapshot(
            containing: "Curated connections"
        )
        #expect(bodyActive.activeSourceLineClassNames[0]
            .contains("cm-live-callout-projected-line"))
        #expect(bodyActive.activeSourceLineClassNames[0]
            .contains("cm-live-callout-role-connect"))
        #expect(bodyActive.activeSourceTitleFontFamilies[0]
            == inactive.renderedTitleFontFamily)
        #expect(bodyActive.activeSourceTitleFontSizes[0]
            == inactive.renderedTitleFontSize)
        #expect(bodyActive.activeSourceTitleFontWeights[0]
            == inactive.renderedTitleFontWeight)
        #expect(bodyActive.activeSourceTitleFontStyles[0]
            == inactive.renderedTitleFontStyle)

        let titleCaret = try #require(source.range(of: "Curated connections")?.lowerBound)
            .utf16Offset(in: source) + 2
        harness.session.revealSourceRange(fromUTF16: titleCaret, toUTF16: titleCaret)
        try await harness.waitUntilSelection(head: titleCaret)
        let titleActive = try await harness.session.testingCalloutProjectionSnapshot(
            containing: "Curated connections"
        )
        #expect(titleActive.activeSourceLineClassNames[0]
            .contains("cm-live-callout-active-line"))
        #expect(titleActive.activeSourceLineFontWeights[0]
            == bodyActive.activeSourceLineFontWeights[1])
        #expect(titleActive.activeSourceTitleFontWeights[0]
            == inactive.renderedTitleFontWeight)
        #expect(titleActive.activeSourceTitleFontStyles[0]
            == inactive.renderedTitleFontStyle)
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("Edit footnote locators move the one CodeMirror caret to the exact definition")
    func editFootnoteReferenceLocatesExactDefinition() async throws {
        let source = "Claim[^note].\n\n[^note]: Basis.\n"
        let definitionContentFrom = try #require(source.range(of: "Basis"))
            .lowerBound.utf16Offset(in: source)
        let harness = EditorHarness(source: source, laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()
        harness.session.focus()
        try await harness.waitUntilFocused()

        _ = try await harness.waitUntilPresentation(
            stage: "Edit footnote locator and direct definition"
        ) {
            $0.footnoteReferenceCount == 1 && $0.footnoteDefinitionSourceCount == 1
        }

        try await harness.session.testingClickFirstFootnoteReference()
        try await harness.waitUntilSelection(head: definitionContentFrom)
        let sourcePresentation = try await harness.session.testingAccessibilitySnapshot()
        #expect(sourcePresentation.footnoteReferenceCount == 1)
        #expect(sourcePresentation.footnoteDefinitionSourceCount == 1)
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("Edit footnote definitions remain direct exact Markdown after preceding edits")
    func editFootnoteDefinitionRemainsDirectEditableSource() async throws {
        let source = "Claim[^note].\n\n[^note]: Basis for revision.\n"
        let prefix = "Preface added before projected content.\n\n"
        let harness = EditorHarness(source: source)
        defer { harness.close() }
        harness.resize(width: 700)
        try await harness.waitUntilReady()
        harness.setPresentationCSS(ScholiumDocumentPresentationConfiguration(textScale: 2).css)
        _ = try await harness.waitUntilPresentation(stage: "two-hundred-percent footnote") {
            $0.presentation.rootTextScale == "2.000000em"
                && $0.footnoteDefinitionSourceCount == 1
        }

        harness.session.goToLine(1)
        try await harness.waitUntilSelection(head: 0)
        try await harness.session.perform(.pastePlain, argument: prefix)
        let shiftedSource = prefix + source
        let contentFrom = try #require(shiftedSource.range(of: "Basis"))
            .lowerBound.utf16Offset(in: shiftedSource)
        _ = try await harness.waitUntilPresentation(stage: "shifted direct footnote") {
            $0.footnoteDefinitionSourceCount == 1
        }

        harness.session.revealSourceRange(fromUTF16: contentFrom, toUTF16: contentFrom)
        try await harness.waitUntilSelection(head: contentFrom)
        let direct = try await harness.session.testingAccessibilitySnapshot()
        #expect(direct.footnoteDefinitionSourceCount == 1)

        try await harness.session.perform(.pastePlain, argument: "Revised ")
        let expected = shiftedSource.replacingOccurrences(
            of: "Basis for revision.",
            with: "Revised Basis for revision."
        )
        #expect(try await harness.session.currentText(for: harness.documentID) == expected)
        #expect(harness.latestSource == expected)
        await harness.closeAndDrain()
    }

    @Test("A Live Preview click places one caret before exposing only that inline construct")
    func inlineProjectionClickPlacesSingleCaret() async throws {
        let source = "Before **bold evidence** and [a standard link](https://example.test).\n"
        let linkRange = try #require(source.range(of: "a standard link"))
        let linkFrom = linkRange.lowerBound.utf16Offset(in: source)
        let linkTo = linkRange.upperBound.utf16Offset(in: source)
        let harness = EditorHarness(source: source, laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()

        try await harness.session.testingClickVisibleText("a standard link")
        _ = try await harness.waitUntilSelection(in: linkFrom..<linkTo)
        let selection = try #require(harness.session.context?.selections.first)
        #expect(selection.anchor == selection.head)
        let active = try await harness.session.testingInlineProjectionSnapshot(
            containing: "a standard link"
        )
        #expect(active.linkTexts == ["[a standard link](https://example.test)"])
        #expect(!active.lineText.contains("**bold evidence**"))
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("A caret beside Wiki syntax has no synthetic bracket selection")
    func wikiSyntaxCaretRemainsAPlainInsertionPoint() async throws {
        let source = "Before [[work-034]] after.\n"
        let construct = try #require(source.range(of: "[[work-034]]"))
        let closingMarker = construct.upperBound.utf16Offset(in: source) - 1
        let harness = EditorHarness(source: source, laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()

        harness.session.revealSourceRange(fromUTF16: closingMarker, toUTF16: closingMarker)
        try await harness.waitUntilSelection(head: closingMarker)
        let selection = try #require(harness.session.context?.selections.first)
        #expect(selection.anchor == selection.head)
        let presentation = try await harness.session.testingAccessibilitySnapshot()
        #expect(presentation.matchingBracketCount == 0)

        try await harness.session.perform(.pastePlain, argument: "中文")
        let expected = (source as NSString).replacingCharacters(
            in: NSRange(location: closingMarker, length: 0),
            with: "中文"
        )
        #expect(try await harness.session.currentText(for: harness.documentID) == expected)
        await harness.closeAndDrain()
    }

    @Test("Edit keeps an empty auto-closed Wikilink placeholder exact")
    func emptyWikilinkPlaceholderRemainsExact() async throws {
        let source = "Before [[]] after.\n"
        let harness = EditorHarness(source: source, laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()

        let projection = try await harness.session.testingInlineProjectionSnapshot(
            containing: "Before"
        )
        #expect(projection.lineText == "Before [[]] after.")
        #expect(projection.wikiLinkTexts.isEmpty)
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        #expect(harness.session.generation == 0)
        #expect(!harness.session.isDirty)
        await harness.closeAndDrain()
    }

    @Test("Footnote definition content uses ordinary Live Preview at its sole source position")
    func footnoteDefinitionContentUsesOrdinaryLiveProjection() async throws {
        let source = "Claim[^note].\n\n[^note]: **Grounded** reason.\n\n  - Nested footnote item.\n"
        let harness = EditorHarness(source: source)
        defer { harness.close() }
        try await harness.waitUntilReady()

        let definition = try await harness.session.testingInlineProjectionSnapshot(
            containing: "Grounded"
        )
        #expect(definition.strongTexts == ["Grounded"])
        #expect(definition.lineText.contains("[^note]:"))
        let presentation = try await harness.session.testingAccessibilitySnapshot()
        #expect(presentation.footnoteDefinitionSourceCount == 1)
        #expect(presentation.liveListMarkerCount == 1)
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("Two-hundred-percent Edit projections remain measured and pointer-addressable")
    func enlargedEditProjectionRemainsStableAcrossFocusAndBlockActivation() async throws {
        let source = """
        ---
        title: Projection stability
        ---
        # Centered document title

        ## Stable second-level heading

        > Ordinary quotation keeps the Review inset.

        ```swift
        let deliberatelyLongLine = "code remains one semantic block"
        ```

        | Claim | Status |
        |:---|:---:|
        | Fittingness | Open |

        AFTER_TABLE_TARGET remains pointer-addressable.

        1. First ordered item.
        2. SECOND_LIST_TARGET remains pointer-addressable.
        """
        let targetRange = try #require(source.range(of: "AFTER_TABLE_TARGET"))
        let targetFrom = targetRange.lowerBound.utf16Offset(in: source)
        let targetTo = targetRange.upperBound.utf16Offset(in: source)
        let listMarkerRange = try #require(source.range(of: "2. SECOND_LIST_TARGET"))
        let listMarkerFrom = listMarkerRange.lowerBound.utf16Offset(in: source)
        let harness = EditorHarness(source: source)
        defer { harness.close() }
        harness.resize(width: 700)
        try await harness.waitUntilReady()
        let profile = DocumentAppearanceProfile(name: "Default")
        harness.setPresentationCSS(
            ScholiumDocumentPresentationConfiguration(textScale: 2).css
                + "\n"
                + DocumentAppearanceStyles.css(for: profile)
        )

        let initial = try await harness.waitUntilPresentation(stage: "stable enlarged Edit projection") {
            $0.presentation.rootTextScale == "2.000000em"
                && $0.liveTitleCount == 1
                && $0.liveH1Count == 1
                && $0.liveH2Count == 1
                && $0.collapsedCodeFenceLineCount == 2
                && $0.liveListMarkerCount == 2
                && $0.semanticTableCount == 1
        }
        #expect(initial.titleTextAlign == "center")
        #expect(initial.h2TextAlign == "start")
        #expect(initial.h1FontSize == "64px")
        #expect(initial.h2FontSize == "48px")
        #expect(initial.collapsedCodeFenceVisibleHeight <= 0.5)

        // At 200% the quotation may be outside CodeMirror's mounted viewport
        // even though the surrounding semantic catalog is complete. Move the
        // caret to the following blank line so the quotation is both mounted
        // and inactive; an active quotation intentionally exposes exact
        // source rather than retaining its projected inset.
        harness.session.goToLine(9)
        let inactiveQuote = try await harness.waitUntilPresentation(stage: "mounted inactive quotation") {
            !$0.quotePaddingInlineStart.isEmpty
        }
        let quoteInset = Double(
            inactiveQuote.quotePaddingInlineStart.replacingOccurrences(of: "px", with: "")
        )
        #expect(quoteInset == Double(ScholiumDocumentRhythm.quoteInlineInset))
        #expect(inactiveQuote.quoteMarginInlineStart == "0px")

        harness.session.goToLine(4)
        let titleFrom = try #require(source.range(of: "# Centered document title"))
            .lowerBound.utf16Offset(in: source)
        try await harness.waitUntilSelection(head: titleFrom)
        let activeTitle = try await harness.waitUntilPresentation(stage: "active document title") {
            $0.liveTitleCount == 1 && $0.liveH1Count == 1
        }
        #expect(activeTitle.titleTextAlign == "center")

        harness.session.resignFocus()
        try await Task.sleep(for: .milliseconds(150))
        #expect(!(try await harness.session.testingAccessibilitySnapshot()).isFocused)
        harness.session.focus()
        try await harness.waitUntilFocused()
        let refocused = try await harness.waitUntilPresentation(stage: "refocused heading projection") {
            $0.liveTitleCount == 1 && $0.liveH1Count == 1 && $0.liveH2Count == 1
        }
        #expect(refocused.titleTextAlign == "center")

        try await harness.session.testingClickFirstTableCell()
        _ = try await harness.waitUntilPresentation(stage: "pointer-activated table source") {
            $0.semanticTableCount == 0 && $0.liveTableSourceLineCount > 0
        }
        try await harness.session.testingClickVisibleText("AFTER_TABLE_TARGET")
        _ = try await harness.waitUntilSelection(in: targetFrom..<(targetTo + 1))
        _ = try await harness.waitUntilPresentation(stage: "remeasured table projection") {
            $0.semanticTableCount == 1 && $0.liveTableSourceLineCount == 0
        }

        try await harness.session.testingClickVisibleText("2.")
        _ = try await harness.waitUntilSelection(in: listMarkerFrom..<(listMarkerFrom + 3))
        let final = try await harness.waitUntilPresentation(stage: "ordered-list pointer placement") {
            $0.liveListMarkerCount == 1
        }
        #expect(final.liveTitleCount == 1)
        #expect(final.liveH2Count == 1)
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("Fresh Edit and Source-to-Edit publish the same semantic projection before acknowledgement")
    func freshAndRetainedEditEntryHaveProjectionParity() async throws {
        let source = """
        # QA Autosave A

        ## Fixture boundary

        First paragraph remains independently editable.

        > [!orient] Reading route
        > This synthetic note exercises the complete Scholium editing dialect.

        > [!cite]- Synthetic source boundary
        > No real publication or quotation is represented here.
        """
        let presentationCSS = ScholiumDocumentPresentationConfiguration(textScale: 1).css
            + "\n"
            + DocumentAppearanceStyles.css(for: DocumentAppearanceProfile(name: "Default"))
        let harness = EditorHarness(
            source: source,
            initialPresentationCSS: presentationCSS,
            laysOutForPointerTesting: true
        )
        defer { harness.close() }
        try await harness.waitUntilReady()

        // `isLoaded` is the product visibility boundary. It must never expose
        // the partial projection that previously appeared after Review -> Edit.
        let fresh = try await harness.session.testingAccessibilitySnapshot()
        #expect(fresh.liveTitleCount == 1)
        #expect(fresh.liveH1Count == 1)
        #expect(fresh.liveH2Count == 1)
        #expect(fresh.liveCalloutWidgetCount == 2)
        #expect(fresh.h1FontSize == "32px")
        #expect(fresh.h2FontSize == "24px")
        #expect(fresh.titleTextAlign == "center")
        #expect(fresh.h2TextAlign == "start")
        #expect(fresh.editBlankLineCount > 0)
        #expect(fresh.editBlankLineMinimumHeight == 16)

        harness.session.setMode(.source)
        try await harness.waitUntilPresentedMode(.source)
        _ = try await harness.waitUntilPresentation(stage: "parity Source mode") {
            $0.gutterCount > 0 && $0.lineNumberCount > 0
        }
        harness.session.setMode(.livePreview)
        try await harness.waitUntilPresentedMode(.livePreview)
        let retained = try await harness.session.testingAccessibilitySnapshot()

        #expect(retained.liveTitleCount == fresh.liveTitleCount)
        #expect(retained.liveH1Count == fresh.liveH1Count)
        #expect(retained.liveH2Count == fresh.liveH2Count)
        #expect(retained.liveCalloutWidgetCount == fresh.liveCalloutWidgetCount)
        #expect(retained.h1FontSize == fresh.h1FontSize)
        #expect(retained.h2FontSize == fresh.h2FontSize)
        #expect(retained.titleTextAlign == fresh.titleTextAlign)
        #expect(retained.h2TextAlign == fresh.h2TextAlign)
        #expect(retained.editBlankLineCount == fresh.editBlankLineCount)
        #expect(retained.editBlankLineMinimumHeight == fresh.editBlankLineMinimumHeight)
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("Losing editor focus preserves the complete heading projection")
    func focusLossPreservesHeadingProjection() async throws {
        let source = """
        # Focus-stable document title

        ## Focus-stable section heading

        Ordinary paragraph.
        """
        let presentationCSS = ScholiumDocumentPresentationConfiguration(textScale: 2).css
            + "\n"
            + DocumentAppearanceStyles.css(for: DocumentAppearanceProfile(name: "Default"))
        let harness = EditorHarness(
            source: source,
            initialPresentationCSS: presentationCSS
        )
        defer { harness.close() }
        try await harness.waitUntilReady()
        _ = try await harness.waitUntilPresentation(stage: "focused heading projection") {
            $0.isFocused
                && $0.liveTitleCount == 1
                && $0.liveH1Count == 1
                && $0.liveH2Count == 1
        }

        await harness.session.resignFocusAndWait()
        let blurred = try await harness.waitUntilPresentation(stage: "unfocused heading projection") {
            !$0.isFocused
                && $0.liveTitleCount == 1
                && $0.liveH1Count == 1
                && $0.liveH2Count == 1
        }
        #expect(blurred.h1FontSize == "64px")
        #expect(blurred.h2FontSize == "48px")
        #expect(blurred.titleTextAlign == "center")
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("Inactive Edit lists mirror Review rhythm, markers, and task projection")
    func inactiveEditListsMirrorReviewPresentation() async throws {
        let source = """
        # List parity

        - Unordered item one
        - Unordered item two
          - Nested unordered item

        1. Ordered item one
        2. Ordered item two
           1. Nested ordered item

        - [ ] Open task fixture
        - [x] Completed task fixture

        Following paragraph.
        """
        let harness = EditorHarness(source: source, laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()

        let inactive = try await harness.waitUntilPresentation(stage: "inactive Review-parity lists") {
            $0.liveListMarkerCount == 8
                && $0.liveTaskCheckboxCount == 2
                && $0.liveTaskCheckedCheckboxCount == 1
                && $0.liveTaskSourceTokenCount == 0
        }
        #expect(inactive.liveListMarkerUsesPrimaryText)
        #expect(inactive.liveListMarkerText == "•|•|◦|1.|2.|1.")
        #expect(inactive.liveListMarkerTextGap > 0)
        #expect(inactive.liveListMarkerTextGap < 8)
        let rhythm = try #require(try await harness.callPageJavaScript(
            """
            const lines = [...document.querySelectorAll('.cm-line.cm-live-list')].slice(0, 3);
            return {
              count: lines.length,
              paddingEnds: lines.map(line => getComputedStyle(line).paddingBlockEnd),
              gaps: lines.slice(1).map((line, index) =>
                line.getBoundingClientRect().top - lines[index].getBoundingClientRect().bottom),
            };
            """
        ) as? [String: Any])
        #expect(rhythm["count"] as? Int == 3)
        #expect((rhythm["paddingEnds"] as? [String]) == ["0px", "0px", "0px"])
        let internalGaps = try #require(rhythm["gaps"] as? [Double])
        #expect(internalGaps.allSatisfy { abs($0) <= 1 })

        let taskSourceFrom = try #require(source.range(of: "- [ ] Open task fixture"))
            .lowerBound.utf16Offset(in: source)
        harness.session.goToLine(11)
        try await harness.waitUntilSelection(head: taskSourceFrom)
        let active = try await harness.waitUntilPresentation(stage: "active exact task source") {
            $0.liveListMarkerCount == 7
                && $0.liveTaskCheckboxCount == 1
                && $0.liveTaskSourceTokenCount == 1
        }
        #expect(active.liveListMarkerUsesPrimaryText)
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("Projected task checkbox toggles only its exact marker bytes")
    func projectedTaskCheckboxTogglesExactMarkerBytes() async throws {
        let source = """
        Before the tasks.

        - [ ] OPEN_TASK_BODY
        - [x] COMPLETED_TASK_BODY
        * [ ] ALTERNATE_TASK_BODY
          ALTERNATE_CONTINUATION

        After the tasks.
        """
        let expected = source.replacingOccurrences(
            of: "- [ ] OPEN_TASK_BODY",
            with: "- [x] OPEN_TASK_BODY"
        )
        let expectedAfterUncheck = expected.replacingOccurrences(
            of: "- [x] COMPLETED_TASK_BODY",
            with: "- [ ] COMPLETED_TASK_BODY"
        )
        let expectedAfterCommand = expectedAfterUncheck.replacingOccurrences(
            of: "* [ ] ALTERNATE_TASK_BODY",
            with: "* [x] ALTERNATE_TASK_BODY"
        )
        let harness = EditorHarness(source: source, laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()

        let inactive = try await harness.waitUntilPresentation(stage: "projected task checkboxes") {
            $0.liveTaskCheckboxCount == 3
                && $0.liveTaskCheckedCheckboxCount == 1
                && $0.liveTaskSourceTokenCount == 0
        }
        #expect(inactive.isFocused)
        let controls = try #require(try await harness.callPageJavaScript(
            """
            return Array.from(document.querySelectorAll('.cm-live-task-checkbox')).map(checkbox => ({
              tag: checkbox.tagName,
              type: checkbox.type,
              label: checkbox.getAttribute('aria-label'),
              tabIndex: checkbox.tabIndex,
              checked: checkbox.checked,
              width: checkbox.getBoundingClientRect().width,
              height: checkbox.getBoundingClientRect().height
            }));
            """
        ) as? [[String: Any]])
        #expect(controls.count == 3)
        #expect(controls.allSatisfy { $0["tag"] as? String == "INPUT" })
        #expect(controls.allSatisfy { $0["type"] as? String == "checkbox" })
        #expect(controls.allSatisfy { $0["label"] as? String == "Task item" })
        #expect(controls.allSatisfy { $0["tabIndex"] as? Int == -1 })
        #expect(controls.compactMap { $0["checked"] as? Bool } == [false, true, false])
        #expect(controls.allSatisfy { ($0["width"] as? Double ?? 0) >= 20 })
        #expect(controls.allSatisfy { ($0["height"] as? Double ?? 0) >= 20 })

        func taskBodyLeadingX(_ body: String) async throws -> Double {
            let value = try #require(try await harness.callPageJavaScript(
                """
                const target = '\(body)';
                for (const line of document.querySelectorAll('.cm-line.cm-live-task-list')) {
                  const walker = document.createTreeWalker(line, NodeFilter.SHOW_TEXT);
                  let node;
                  while ((node = walker.nextNode())) {
                    const offset = (node.textContent || '').indexOf(target);
                    if (offset < 0) continue;
                    const range = document.createRange();
                    range.setStart(node, offset);
                    range.setEnd(node, offset + 1);
                    return range.getBoundingClientRect().left;
                  }
                }
                return null;
                """
            ) as? NSNumber)
            return value.doubleValue
        }
        let initialOpenTaskX = try await taskBodyLeadingX("OPEN_TASK_BODY")
        let initialCompletedTaskX = try await taskBodyLeadingX("COMPLETED_TASK_BODY")
        #expect(abs(initialOpenTaskX - initialCompletedTaskX) <= 0.5)

        let selectionBeforeClick = harness.session.context?.selections
        try await harness.session.testingClickTaskCheckbox()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(4))
        while try await harness.session.currentText(for: harness.documentID) != expected {
            guard clock.now < deadline else {
                Issue.record("Task checkbox did not update its exact source marker.")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let checked = try await harness.waitUntilPresentation(stage: "checked task projection") {
            $0.liveTaskCheckboxCount == 3
                && $0.liveTaskCheckedCheckboxCount == 2
                && $0.liveTaskSourceTokenCount == 0
        }
        #expect(checked.isFocused)
        #expect(harness.session.context?.selections == selectionBeforeClick)
        #expect(harness.session.context?.undoLabel == "Toggle Task")
        #expect(try await harness.session.currentText(for: harness.documentID) == expected)
        #expect(abs(try await taskBodyLeadingX("OPEN_TASK_BODY") - initialOpenTaskX) <= 0.5)
        #expect(
            abs(try await taskBodyLeadingX("COMPLETED_TASK_BODY") - initialCompletedTaskX)
                <= 0.5
        )

        try await harness.session.testingClickTaskCheckbox(at: 1)
        let uncheckDeadline = clock.now.advanced(by: .seconds(4))
        while try await harness.session.currentText(for: harness.documentID) != expectedAfterUncheck {
            guard clock.now < uncheckDeadline else {
                Issue.record("Checked task checkbox did not clear its exact source marker.")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let unchecked = try await harness.waitUntilPresentation(stage: "unchecked task projection") {
            $0.liveTaskCheckboxCount == 3
                && $0.liveTaskCheckedCheckboxCount == 1
                && $0.liveTaskSourceTokenCount == 0
        }
        #expect(unchecked.isFocused)
        #expect(harness.session.context?.selections == selectionBeforeClick)
        #expect(harness.session.context?.undoLabel == "Toggle Task")
        #expect(try await harness.session.currentText(for: harness.documentID) == expectedAfterUncheck)
        #expect(abs(try await taskBodyLeadingX("OPEN_TASK_BODY") - initialOpenTaskX) <= 0.5)
        #expect(
            abs(try await taskBodyLeadingX("COMPLETED_TASK_BODY") - initialCompletedTaskX)
                <= 0.5
        )

        let commandCaret = try #require(expectedAfterUncheck.range(of: "ALTERNATE_CONTINUATION"))
            .lowerBound.utf16Offset(in: expectedAfterUncheck) + 2
        harness.session.revealSourceRange(fromUTF16: commandCaret, toUTF16: commandCaret)
        try await harness.waitUntilSelection(head: commandCaret)
        let availabilityDeadline = clock.now.advanced(by: .seconds(4))
        while harness.session.context?.availableCommands.contains(.toggleTask) != true {
            guard clock.now < availabilityDeadline else {
                Issue.record("The alternate task continuation did not expose Toggle Task.")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(harness.session.context?.availableCommands.contains(.toggleTask) == true)
        try await harness.session.perform(.toggleTask)
        let commandDeadline = clock.now.advanced(by: .seconds(4))
        while try await harness.session.currentText(for: harness.documentID) != expectedAfterCommand {
            guard clock.now < commandDeadline else {
                Issue.record("The keyboard/menu task command did not update its exact marker.")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(harness.session.context?.undoLabel == "Toggle Task")
        #expect(try await harness.session.currentText(for: harness.documentID) == expectedAfterCommand)
        await harness.closeAndDrain()
    }

    @Test("Left Arrow enters every projected list prefix at its trailing edge")
    func leftArrowEntersProjectedListPrefixAtTrailingEdge() async throws {
        let source = """
        Before the lists.

        - BULLET_LIST_BODY
          - NESTED_LIST_BODY
        10. ORDERED_LIST_BODY
        - [ ] TASK_LIST_BODY

        After the lists.
        """
        let cases = [
            (prefix: "- ", body: "BULLET_LIST_BODY"),
            (prefix: "  - ", body: "NESTED_LIST_BODY"),
            (prefix: "10. ", body: "ORDERED_LIST_BODY"),
            (prefix: "- [ ] ", body: "TASK_LIST_BODY"),
        ]
        let harness = EditorHarness(source: source, laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()

        for testCase in cases {
            let bodyFrom = try #require(source.range(of: testCase.body))
                .lowerBound.utf16Offset(in: source)
            harness.session.revealSourceRange(fromUTF16: bodyFrom, toUTF16: bodyFrom)
            try await harness.waitUntilSelection(head: bodyFrom)

            try await harness.session.testingPressArrow("ArrowLeft")
            try await harness.waitUntilSelection(
                head: bodyFrom - 1,
                stage: "trailing-edge source entry for \(testCase.body)"
            )
            let lineText = try #require(try await harness.callPageJavaScript(
                """
                return Array.from(document.querySelectorAll('.cm-line'))
                  .find(line => (line.textContent || '').includes('\(testCase.body)'))
                  ?.textContent || '';
                """
            ) as? String)
            #expect(lineText.contains(testCase.prefix + testCase.body))
        }
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("List source reveal is marker scoped and preserves content geometry")
    func listSourceRevealIsMarkerScopedAndPreservesContentGeometry() async throws {
        let source = """
        Before the list.

        - ROOT_LIST_BODY
          - NESTED_LIST_BODY

        10. ORDERED_LIST_BODY

        - [ ] TASK_LIST_BODY

        After the list.
        """
        let afterFrom = try #require(source.range(of: "After the list."))
            .lowerBound.utf16Offset(in: source)
        let cases = [
            (marker: "- ROOT_LIST_BODY", body: "ROOT_LIST_BODY", task: false),
            (marker: "- NESTED_LIST_BODY", body: "NESTED_LIST_BODY", task: false),
            (marker: "10. ORDERED_LIST_BODY", body: "ORDERED_LIST_BODY", task: false),
            (marker: "- [ ] TASK_LIST_BODY", body: "TASK_LIST_BODY", task: true),
        ]
        let harness = EditorHarness(source: source, laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()

        func bodyLeadingX(_ target: String) async throws -> Double {
            let value = try #require(try await harness.callPageJavaScript(
                """
                const target = '\(target)';
                for (const line of document.querySelectorAll('.cm-line')) {
                  const walker = document.createTreeWalker(line, NodeFilter.SHOW_TEXT);
                  let node;
                  while ((node = walker.nextNode())) {
                    const text = node.textContent || '';
                    const offset = text.indexOf(target);
                    if (offset < 0) continue;
                    const range = document.createRange();
                    range.setStart(node, offset);
                    range.setEnd(node, offset + 1);
                    return range.getBoundingClientRect().left;
                  }
                }
                return null;
                """
            ) as? NSNumber)
            return value.doubleValue
        }

        harness.session.revealSourceRange(fromUTF16: afterFrom, toUTF16: afterFrom)
        try await harness.waitUntilSelection(head: afterFrom)
        let inactive = try await harness.session.testingAccessibilitySnapshot()
        #expect(inactive.liveListMarkerCount == cases.count)

        for testCase in cases {
            let markerFrom = try #require(source.range(of: testCase.marker))
                .lowerBound.utf16Offset(in: source)
            let bodyFrom = try #require(source.range(of: testCase.body))
                .lowerBound.utf16Offset(in: source)
            let inactiveX = try await bodyLeadingX(testCase.body)

            let bodyCaret = bodyFrom + testCase.body.utf16.count / 2
            harness.session.revealSourceRange(fromUTF16: bodyCaret, toUTF16: bodyCaret)
            try await harness.waitUntilSelection(head: bodyCaret)
            let bodyActive = try await harness.session.testingAccessibilitySnapshot()
            #expect(bodyActive.liveListMarkerCount == cases.count)
            #expect(bodyActive.liveTaskSourceTokenCount == 0)
            let bodyActiveX = try await bodyLeadingX(testCase.body)

            harness.session.revealSourceRange(fromUTF16: markerFrom, toUTF16: markerFrom)
            try await harness.waitUntilSelection(head: markerFrom)
            let markerActive = try await harness.session.testingAccessibilitySnapshot()
            #expect(markerActive.liveListMarkerCount == cases.count - 1)
            #expect(markerActive.liveTaskSourceTokenCount == (testCase.task ? 1 : 0))
            let markerActiveX = try await bodyLeadingX(testCase.body)

            harness.session.revealSourceRange(fromUTF16: afterFrom, toUTF16: afterFrom)
            try await harness.waitUntilSelection(head: afterFrom)
            let restored = try await harness.session.testingAccessibilitySnapshot()
            #expect(restored.liveListMarkerCount == cases.count)
            let restoredX = try await bodyLeadingX(testCase.body)

            for candidate in [bodyActiveX, markerActiveX, restoredX] {
                #expect(abs(candidate - inactiveX) <= 0.5)
            }
        }
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("A nested list prefix never consumes its active Callout marker")
    func nestedListPrefixPreservesActiveCalloutMarker() async throws {
        let source = """
        > [!state] Callout list
        > - CALLOUT_LIST_BODY
        """
        let bodyFrom = try #require(source.range(of: "CALLOUT_LIST_BODY"))
            .lowerBound.utf16Offset(in: source)
        let markerFrom = try #require(source.range(of: "- CALLOUT_LIST_BODY"))
            .lowerBound.utf16Offset(in: source)
        let harness = EditorHarness(source: source, laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()

        func listLinePresentation() async throws -> [String: Any] {
            try #require(try await harness.callPageJavaScript(
                """
                const line = Array.from(document.querySelectorAll('.cm-line'))
                  .find(candidate => (candidate.textContent || '').includes('CALLOUT_LIST_BODY'));
                if (!line) return null;
                return {
                  text: line.textContent || '',
                  projected: line.querySelectorAll('.cm-live-list-marker').length,
                  exactPrefix: line.querySelectorAll('.cm-live-list-source-prefix').length
                };
                """
            ) as? [String: Any])
        }

        let bodyCaret = bodyFrom + 4
        harness.session.revealSourceRange(fromUTF16: bodyCaret, toUTF16: bodyCaret)
        try await harness.waitUntilSelection(head: bodyCaret)
        _ = try await harness.waitUntilPresentation(stage: "Callout list body projection") {
            $0.activeLiveBlockKind == "callout" && $0.liveListMarkerCount == 1
        }
        let projected = try await listLinePresentation()
        #expect((projected["text"] as? String)?.hasPrefix(">") == true)
        #expect(projected["projected"] as? Int == 1)
        #expect(projected["exactPrefix"] as? Int == 0)

        harness.session.revealSourceRange(fromUTF16: markerFrom, toUTF16: markerFrom)
        try await harness.waitUntilSelection(head: markerFrom)
        _ = try await harness.waitUntilPresentation(stage: "exact nested list prefix") {
            $0.activeLiveBlockKind == "callout" && $0.liveListMarkerCount == 0
        }
        let exact = try await listLinePresentation()
        #expect((exact["text"] as? String)?.contains("> - CALLOUT_LIST_BODY") == true)
        #expect(exact["projected"] as? Int == 0)
        #expect(exact["exactPrefix"] as? Int == 1)
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("Edit paragraph separators remain real symmetric source lines with Review-sized rhythm")
    func editParagraphSeparatorsRemainEditableSourceLines() async throws {
        let source = "First paragraph.\n\nSecond paragraph.\n"
        let blankOffset = try #require(source.range(of: "\n\n"))
            .lowerBound.utf16Offset(in: source) + 1
        let secondFrom = try #require(source.range(of: "Second paragraph."))
            .lowerBound.utf16Offset(in: source)
        let harness = EditorHarness(source: source, laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()

        let presentation = try await harness.session.testingAccessibilitySnapshot()
        #expect(presentation.editBlankLineCount >= 1)
        #expect(
            presentation.editBlankLineMinimumHeight
                == DocumentAppearanceSettings.defaultSettings.body.paragraphSpacingEm
                * DocumentAppearanceSettings.defaultSettings.body.fontSizePoints
                * (96 / 72)
        )

        harness.session.revealSourceRange(fromUTF16: secondFrom, toUTF16: secondFrom)
        try await harness.waitUntilSelection(head: secondFrom)
        try await harness.session.testingPressArrow("ArrowLeft")
        try await harness.waitUntilSelection(head: blankOffset)
        let expectedActiveLineHeight = DocumentAppearanceSettings.defaultSettings
            .body.lineHeight
            * DocumentAppearanceSettings.defaultSettings.body.fontSizePoints
            * (96 / 72)
        let activeBlankGeometry = try #require(
            try await harness.callPageJavaScript(
                """
                const line = document.querySelector('.cm-live-blank-line-active');
                const style = line ? getComputedStyle(line) : null;
                return {
                  className: line?.className || '',
                  height: line?.getBoundingClientRect().height || 0,
                  blockSize: style?.blockSize || '',
                  minBlockSize: style?.minBlockSize || '',
                  lineHeight: style?.lineHeight || ''
                };
                """
            ) as? [String: Any]
        )
        let activeBlankHeight = try #require(
            activeBlankGeometry["height"] as? NSNumber
        ).doubleValue
        #expect(
            (activeBlankGeometry["className"] as? String)?
                .contains("cm-live-blank-line-active") == true
        )
        #expect(abs(activeBlankHeight - expectedActiveLineHeight) < 0.5)

        func transitionGeometry(lineIndex: Int) async throws -> [String: Double] {
            let value = try #require(try await harness.callPageJavaScript(
                """
                const lines = Array.from(document.querySelectorAll('.cm-line'));
                const line = lines[lineIndex] || null;
                const following = lines[lineIndex + 1] || null;
                return line && following ? {
                  lineTop: line.getBoundingClientRect().top,
                  followingTop: following.getBoundingClientRect().top,
                  lineHeight: Number.parseFloat(getComputedStyle(line).lineHeight)
                } : null;
                """,
                arguments: ["lineIndex": lineIndex]
            ) as? [String: Any])
            return [
                "lineTop": try #require(value["lineTop"] as? NSNumber).doubleValue,
                "followingTop": try #require(value["followingTop"] as? NSNumber).doubleValue,
                "lineHeight": try #require(value["lineHeight"] as? NSNumber).doubleValue,
            ]
        }

        let beforeInput = try await transitionGeometry(lineIndex: 1)
        try await harness.session.perform(.pastePlain, argument: "a")
        try await harness.waitUntilSelection(
            head: blankOffset + 1,
            stage: "first character on separator line"
        )
        let afterInput = try await transitionGeometry(lineIndex: 1)
        for key in ["lineTop", "followingTop", "lineHeight"] {
            let before = try #require(beforeInput[key])
            let after = try #require(afterInput[key])
            #expect(abs(before - after) < 0.5)
        }

        try await harness.session.testingPressArrow("ArrowRight")
        try await harness.waitUntilSelection(head: secondFrom + 1)
        #expect(
            try await harness.session.currentText(for: harness.documentID)
                == "First paragraph.\na\nSecond paragraph.\n"
        )
        await harness.closeAndDrain()
    }

    @Test("An authored separator line owns semantic block spacing and pointer entry")
    func authoredSeparatorLineOwnsSemanticBlockGap() async throws {
        let source = "Lead paragraph.\n\n> Quoted paragraph.\n> Continued quotation.\n\nFollowing paragraph.\n"
        let blankOffset = try #require(source.range(of: "\n\n"))
            .lowerBound.utf16Offset(in: source) + 1
        let harness = EditorHarness(source: source, laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()

        let presentation = try await harness.session.testingAccessibilitySnapshot()
        #expect(presentation.semanticGapCount == 0)
        try await harness.session.testingClickBlankLine(
            between: "Lead paragraph.",
            and: "Quoted paragraph."
        )
        try await harness.waitUntilSelection(head: blankOffset, stage: "authored separator click")
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("Raw HTML switches between an inert projection and exact editable source")
    func rawHTMLProjectionRevealsExactSourceOnlyWhileActive() async throws {
        let source = """
        # Raw HTML boundary

        <section data-fixture="raw-html">Literal source.</section>

        Following paragraph.
        """
        let htmlFrom = try #require(source.range(of: "<section"))
            .lowerBound.utf16Offset(in: source)
        let harness = EditorHarness(source: source)
        defer { harness.close() }
        try await harness.waitUntilReady()

        _ = try await harness.waitUntilPresentation(stage: "inactive raw HTML projection") {
            $0.liveRawHTMLWidgetCount == 1 && $0.liveRawHTMLSourceLineCount == 0
        }
        harness.session.goToLine(3)
        try await harness.waitUntilSelection(head: htmlFrom)
        _ = try await harness.waitUntilPresentation(stage: "active exact raw HTML source") {
            $0.liveRawHTMLWidgetCount == 0 && $0.liveRawHTMLSourceLineCount == 1
        }
        #expect(try await harness.session.currentText(for: harness.documentID) == source)

        harness.session.goToLine(5)
        _ = try await harness.waitUntilPresentation(stage: "restored raw HTML projection") {
            $0.liveRawHTMLWidgetCount == 1 && $0.liveRawHTMLSourceLineCount == 0
        }
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("A projected Callout enters its editable content-end boundary before Backspace")
    func calloutPointerBackspaceCannotDeleteThePrecedingBlock() async throws {
        let source = """
        # Interaction boundary

        > [!orient] Reading route
        > This synthetic note exercises the complete Scholium editing dialect.

        > [!cite]- Synthetic source boundary
        > No real publication or quotation is represented here.
        """
        let firstCalloutSource = """
        > [!orient] Reading route
        > This synthetic note exercises the complete Scholium editing dialect.
        """
        let calloutRange = try #require(source.range(of: firstCalloutSource))
        let calloutTo = calloutRange.upperBound.utf16Offset(in: source)
        let harness = EditorHarness(source: source)
        defer { harness.close() }
        try await harness.waitUntilReady()
        _ = try await harness.waitUntilPresentation(stage: "passive Callout before Backspace") {
            $0.liveCalloutWidgetCount == 2 && $0.editBlankLineMinimumHeight > 0
        }

        try await harness.session.testingClickFirstCalloutText("synthetic note")
        _ = try await harness.waitUntilSelection(head: calloutTo)
        try await harness.session.testingPressBackspace()

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        var edited = source
        while clock.now < deadline {
            edited = try await harness.session.currentText(for: harness.documentID)
            if edited != source { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(edited.utf16.count == source.utf16.count - 1)
        #expect(edited.contains("> [!orient] Reading route"))
        #expect(edited.contains("> [!cite]- Synthetic source boundary"))
        await harness.closeAndDrain()
    }

    @Test("Source soft-wraps exact logical lines without changing their text or numbering")
    func sourceSoftWrapPreservesExactLogicalLines() async throws {
        let longLine = "SOFT_WRAP_PROBE "
            + Array(repeating: "exact-source-token", count: 80).joined(separator: " ")
        let source = "---\r\ntitle: Soft Wrap\r\n---\r\n\(longLine)\r\nFinal logical line.\r\n"
        let normalizedSource = source.replacingOccurrences(of: "\r\n", with: "\n")
        let finalLineOffset = try #require(
            normalizedSource.range(of: "Final logical line.")?.lowerBound
        ).utf16Offset(in: normalizedSource)
        let harness = EditorHarness(source: source)
        defer { harness.close() }

        try await harness.waitUntilReady()
        let generation = harness.session.generation
        let undoLabel = harness.session.context?.undoLabel
        harness.session.setMode(.source)
        let sourceMode = try await harness.waitUntilPresentation(stage: "soft-wrapped Source") {
            $0.label == "Markdown source editor"
                && $0.lineWrappingEnabled
                && $0.softWrapProbeHeight > 0
        }
        let sourceLineHeight = Double(
            sourceMode.presentation.documentLineHeight.replacingOccurrences(of: "px", with: "")
        ) ?? 0
        #expect(sourceLineHeight > 0)
        #expect(sourceMode.softWrapProbeHeight > sourceLineHeight * 2)

        harness.session.goToLine(5)
        try await harness.waitUntilSelection(head: finalLineOffset)
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        #expect(harness.session.generation == generation)
        #expect(harness.session.context?.undoLabel == undoLabel)
        #expect(!harness.session.isDirty)
        await harness.closeAndDrain()
    }

    @Test("The WebKit symbol catalog resolves every direct SF Symbol")
    func webSymbolCatalogResolvesDirectSystemSymbols() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogSource = try String(
            contentsOf: repository.appendingPathComponent("WebEditor/system-symbols.ts"),
            encoding: .utf8
        )
        let catalogStart = try #require(
            catalogSource.range(of: "export const webSystemSymbolKeys = [")
        )
        let catalogEnd = try #require(
            catalogSource.range(of: "] as const;", range: catalogStart.upperBound..<catalogSource.endIndex)
        )
        let catalogBody = String(catalogSource[catalogStart.upperBound..<catalogEnd.lowerBound])
        let catalogExpression = try NSRegularExpression(pattern: #""([^"]+)""#)
        let catalogNSString = catalogBody as NSString
        let webTokens = Set<String>(catalogExpression.matches(
            in: catalogBody,
            range: NSRange(location: 0, length: catalogNSString.length)
        ).compactMap { match in
            guard match.numberOfRanges == 2 else { return nil }
            return catalogNSString.substring(with: match.range(at: 1))
        })
        #expect(webTokens == Set(ScholiumSystemSymbol.allCases.map(\.webToken)))

        let css = ScholiumWebSymbolAssets.cssVariables
        for symbol in ScholiumSystemSymbol.allCases {
            let image = try #require(NSImage(
                systemSymbolName: symbol.systemName,
                accessibilityDescription: nil
            )?.withSymbolConfiguration(.init(pointSize: 16, weight: .regular)))
            let prefix = "data:image/png;base64,"
            let dataURI = ScholiumWebSymbolAssets.dataURI(for: symbol)
            #expect(dataURI.hasPrefix(prefix))
            let data = try #require(Data(base64Encoded: String(dataURI.dropFirst(prefix.count))))
            let bitmap = try #require(NSBitmapImageRep(data: data))
            #expect(CGFloat(bitmap.pixelsWide) >= image.size.width * 4 - 1)
            #expect(CGFloat(bitmap.pixelsHigh) >= image.size.height * 4 - 1)
            #expect(css.contains("--scholium-system-symbol-\(symbol.webToken):"))
        }
    }

    @Test("Edit Vector Links use only the shared SF Symbol masks")
    func editVectorLinksUseSystemSymbols() async throws {
        let source = "Intro.\n\n+[[Support]] -[[Oppose]] ?[[Conflict]] [[Related]] [External](https://example.com)\n"
        let harness = EditorHarness(source: source, laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        var snapshot: [String: Any] = [:]
        while true {
            snapshot = try #require(try await harness.callPageJavaScript(
                """
                const icons = [...document.querySelectorAll('.cm-live-vector-icon')];
                return {
                  names: icons.map(icon => icon.dataset.scholiumSystemSymbol || ''),
                  maskCount: icons.filter(icon => {
                    const style = getComputedStyle(icon);
                    return [style.webkitMaskImage, style.maskImage].some(
                      value => Boolean(value) && value !== 'none'
                    );
                  }).length,
                  svgCount: icons.reduce((count, icon) => count + icon.querySelectorAll('svg').length, 0),
                  visibleText: icons.map(icon => icon.textContent || '').join(''),
                  sizes: icons.map(icon => {
                    const rect = icon.getBoundingClientRect();
                    return `${rect.width.toFixed(2)}x${rect.height.toFixed(2)}`;
                  }),
                  wikiColor: getComputedStyle(document.querySelector('.cm-live-vector-neutral')).color,
                  externalColor: getComputedStyle(document.querySelector('.cm-live-link')).color,
                  wikiDecoration: getComputedStyle(document.querySelector('.cm-live-vector-neutral')).textDecorationLine,
                  externalDecoration: getComputedStyle(document.querySelector('.cm-live-link')).textDecorationLine
                };
                """
            ) as? [String: Any])
            if (snapshot["names"] as? [String])?.count == 4 { break }
            if clock.now >= deadline {
                Issue.record("Edit did not project all Vector Link symbols: \(snapshot).")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(snapshot["names"] as? [String] == [
            "plus",
            "minus",
            "xmark",
            "link",
        ])
        #expect(snapshot["maskCount"] as? Int == 4)
        #expect(snapshot["svgCount"] as? Int == 0)
        #expect(snapshot["visibleText"] as? String == "")
        #expect(Set(snapshot["sizes"] as? [String] ?? []).count == 1)
        #expect((snapshot["wikiColor"] as? String) == (snapshot["externalColor"] as? String))
        #expect(snapshot["wikiDecoration"] as? String == "none")
        #expect((snapshot["externalDecoration"] as? String)?.contains("underline") == true)
        await harness.closeAndDrain()
    }

    @Test("Edit renders an inactive embed as one complete bounded Note")
    func editEmbeddedNotePresentation() async throws {
        let source = "Intro.\n\n![[Embedded]]\n\nAfter embedded note.\n"
        let embedOffset = try #require(source.range(of: "![[Embedded]]")?.lowerBound)
            .utf16Offset(in: source)
        let embedLength = "![[Embedded]]".utf16.count
        let preview = DocumentLinkPreview(
            sourceSpan: SourceSpan(
                utf8LowerBound: embedOffset,
                utf8UpperBound: embedOffset + embedLength,
                utf16LowerBound: embedOffset,
                utf16UpperBound: embedOffset + embedLength,
                start: SourcePosition(line: 3, utf8Column: 1, utf16Column: 1),
                end: SourcePosition(
                    line: 3,
                    utf8Column: embedLength + 1,
                    utf16Column: embedLength + 1
                )
            ),
            target: VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Embedded.md"),
            targetFingerprint: DocumentFingerprint(content: "Embedded target"),
            title: "Embedded note",
            syntax: .embed,
            relationship: nil,
            fragment: nil,
            htmlBody: "<h1>Embedded note</h1>" + String(
                repeating: "<p>Complete projected paragraph.</p>",
                count: 90
            ) + "<p>Complete editor embedded tail</p>"
        )
        let harness = EditorHarness(
            source: source,
            linkPreviews: [preview],
            laysOutForPointerTesting: true
        )
        defer { harness.close() }
        try await harness.waitUntilReady()

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        var snapshot: [String: Any] = [:]
        while true {
            snapshot = try #require(try await harness.callPageJavaScript(
                """
                const shell = document.querySelector('.cm-live-embedded-note-widget');
                const viewport = shell?.querySelector('.scholium-embedded-note-viewport');
                const body = shell?.querySelector('.scholium-embedded-note-body');
                const open = shell?.querySelector('.scholium-embedded-note-open');
                if (!shell || !viewport || !body || !open) {
                  return {
                    ready: false,
                    contentText: document.querySelector('.cm-content')?.textContent || '',
                    embedFallbacks: document.querySelectorAll('.cm-live-embed').length,
                    replacementWidgets: document.querySelectorAll('.cm-widgetBuffer').length
                  };
                }
                viewport.scrollTop = 160;
                return {
                  ready: true,
                  bodyOwnsDocumentStyle: body.classList.contains('scholium-document'),
                  duplicateTitleCount: [...body.querySelectorAll('h1')]
                    .filter(heading => (heading.textContent || '').trim() === 'Embedded note').length,
                  hasTail: (body.textContent || '').includes('Complete editor embedded tail'),
                  scrolls: viewport.scrollHeight > viewport.clientHeight && viewport.scrollTop > 0,
                  openBadgeCount: open.querySelectorAll('.cm-live-vector-icon').length,
                  viewportTabIndex: viewport.tabIndex,
                  sourceLocatorCount: body.querySelectorAll('[data-source-utf16-start]').length
                };
                """
            ) as? [String: Any])
            if snapshot["ready"] as? Bool == true { break }
            if clock.now >= deadline {
                Issue.record("Edit did not install the finite embedded Note widget: \(snapshot).")
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(snapshot["bodyOwnsDocumentStyle"] as? Bool == true)
        #expect(snapshot["duplicateTitleCount"] as? Int == 0)
        #expect(snapshot["hasTail"] as? Bool == true)
        #expect(snapshot["scrolls"] as? Bool == true)
        #expect(snapshot["openBadgeCount"] as? Int == 0)
        #expect(snapshot["viewportTabIndex"] as? Int == 0)
        #expect(snapshot["sourceLocatorCount"] as? Int == 0)
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("Edit selection toolbar exposes the approved hierarchy and exact Markdown comment action")
    func editSelectionToolbarHierarchy() async throws {
        let source = "Toolbar claim remains exact.\n"
        let selectedText = "Toolbar claim"
        let selectedRange = try #require(source.range(of: selectedText))
        let from = selectedRange.lowerBound.utf16Offset(in: source)
        let to = selectedRange.upperBound.utf16Offset(in: source)
        let harness = EditorHarness(source: source, laysOutForPointerTesting: true)
        defer { harness.close() }

        try await harness.waitUntilReady()
        harness.session.revealSourceRange(fromUTF16: from, toUTF16: to)
        try await harness.waitUntilSelection(head: to, stage: "formatting toolbar selection")
        harness.session.focus()
        try await harness.waitUntilFocused()
        let accessibility = try await harness.session.testingAccessibilitySnapshot()
        #expect(harness.session.errorMessage == nil)
        #expect(accessibility.liveModeClassCount == 1)
        #expect(accessibility.selectionActionsCount == 1)

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        var toolbar = try await harness.session.testingSelectionToolbarSnapshot()
        while toolbar.hidden {
            if clock.now >= deadline {
                Issue.record("The Edit formatting toolbar did not become visible: \(toolbar).")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(20))
            toolbar = try await harness.session.testingSelectionToolbarSnapshot()
        }

        #expect(toolbar.toolbarRole == "toolbar")
        #expect(toolbar.toolbarLabel == "Formatting actions")
        #expect(toolbar.visibleControlLabels == [
            "Text Style",
            "Bold",
            "Italic",
            "Strikethrough",
            "Highlight",
            "Link",
            "Wiki",
            "Vector Link Options",
            "More Formatting",
        ])
        #expect(toolbar.wikiSeparatorCount == 0)
        #expect(!toolbar.containsMarkdownSyntax)
        #expect(toolbar.rootWidth > 0 && toolbar.rootWidth < 360)
        #expect(toolbar.rootHeight >= 37 && toolbar.rootHeight <= 40)
        let selectionCenter = (toolbar.selectionLeft + toolbar.selectionRight) / 2
        let expectedToolbarLeft = max(
            8,
            min(
                selectionCenter - toolbar.rootWidth / 2,
                toolbar.viewportWidth - toolbar.rootWidth - 8
            )
        )
        #expect(abs(toolbar.rootLeft - expectedToolbarLeft) <= 1)
        #expect(toolbar.rootTop >= toolbar.selectionBottom + 5)
        #expect(toolbar.minimumControlHeight >= 28)
        #expect(toolbar.interfaceLabelFontSize == "12px")
        #expect(toolbar.rootBorderColor == toolbar.separatorColor)
        #expect(toolbar.menuBorderColor == toolbar.separatorColor)
        #expect(toolbar.rootBorderColor != toolbar.accentColor)
        #expect(toolbar.toolbarSystemSymbolNames == [
            "textformat",
            "chevron-down",
            "bold",
            "italic",
            "strikethrough",
            "highlighter",
            "link",
            "chevron-down",
            "ellipsis",
        ])
        #expect(toolbar.toolbarSystemSymbolMaskCount == toolbar.toolbarSystemSymbolNames.count)
        #expect(toolbar.toolbarSystemSymbolWidths.allSatisfy { $0 >= 10 && $0 <= 18 })
        #expect(toolbar.toolbarSystemSymbolHeights.allSatisfy { $0 >= 10 && $0 <= 16 })
        #expect(toolbar.inlineSVGCount == 0)
        let labelSize = Double(toolbar.interfaceLabelFontSize.dropLast(2)) ?? 0
        let documentSize = Double(toolbar.documentFontSize.dropLast(2)) ?? 0
        #expect(labelSize > 0 && labelSize < documentSize)

        let textStyle = try await harness.session.testingSelectionToolbarSnapshot(
            opening: "Text Style"
        )
        #expect(textStyle.openMenuCount == 1)
        #expect(textStyle.visibleMenuLabels == [
            "Paragraph",
            "Heading 1",
            "Heading 2",
            "Heading 3",
            "Heading 4",
            "Heading 5",
            "Heading 6",
        ])
        #expect(textStyle.visibleMenuSystemSymbolNames == Array(
            repeating: "checkmark",
            count: 7
        ))
        #expect(textStyle.minimumMenuRowHeight >= 28)

        let vector = try await harness.session.testingSelectionToolbarSnapshot(
            opening: "Vector Link Options"
        )
        #expect(vector.visibleMenuLabels == ["Supports", "Opposes", "Incompatible"])
        #expect(vector.visibleMenuSystemSymbolNames == [
            "plus-circle",
            "minus-circle",
            "xmark-circle",
        ])

        let more = try await harness.session.testingSelectionToolbarSnapshot(
            opening: "More Formatting"
        )
        #expect(more.visibleMenuLabels == [
            "Inline Code",
            "Code Block",
            "Lists",
            "Blockquote",
            "Comment",
            "Import Image…",
            "Index Image…",
        ])
        #expect(more.visibleMenuCommands == [
            "inlineCode",
            "fencedCode",
            "",
            "blockQuotation",
            "markdownComment",
            "",
            "",
        ])
        #expect(more.visibleMenuSystemSymbolNames == [
            "curlybraces",
            "curlybraces-square",
            "list-bullet",
            "chevron-down",
            "text-quote",
            "eye-slash",
        ])
        #expect(more.rootBackground != more.raisedSurfaceBackground)
        #expect(more.focusedClassName.contains("scholium-selection-menu-item"))
        #expect(more.focusedMatchesFeedbackSelector)
        #expect(more.focusedBackground == more.keyboardFocusSurfaceBackground)
        #expect(more.focusedBackground != more.raisedSurfaceBackground)
        let lists = try await harness.session.testingSelectionToolbarSnapshot(
            opening: "More Formatting",
            submenu: "Lists"
        )
        #expect(lists.openMenuCount == 2)
        #expect(lists.visibleMenuLabels == ["Bullet List", "Numbered List", "Checkbox List"])
        #expect(lists.visibleMenuSystemSymbolNames == [
            "list-bullet",
            "list-number",
            "checklist",
        ])
        #expect(lists.focusedClassName.contains("scholium-selection-menu-item"))
        #expect(lists.focusedMatchesFeedbackSelector)
        #expect(lists.focusedBackground == lists.keyboardFocusSurfaceBackground)
        #expect(lists.focusedBackground != lists.raisedSurfaceBackground)

        harness.session.focus()
        try await harness.waitUntilFocused()
        #expect(try await harness.session.testingFocusSelectionToolbar() == "Text Style")
        try await Task.sleep(for: .milliseconds(30))
        let keyboardFocused = try await harness.session.testingSelectionToolbarSnapshot()
        #expect(!keyboardFocused.hidden)
        #expect(keyboardFocused.focusedLabel == "Text Style")
        #expect(keyboardFocused.focusedClassName.contains("scholium-selection-control"))
        #expect(keyboardFocused.focusedMatchesFeedbackSelector)
        #expect(
            keyboardFocused.focusedBackground
                == keyboardFocused.keyboardFocusSurfaceBackground
        )
        #expect(keyboardFocused.focusedBackground != keyboardFocused.raisedSurfaceBackground)

        harness.session.focus()
        try await harness.waitUntilFocused()
        try await harness.session.perform(.markdownComment)
        let expected = "%% Toolbar claim %% remains exact.\n"
        let mutationDeadline = clock.now.advanced(by: .seconds(3))
        while try await harness.session.currentText(for: harness.documentID) != expected {
            if clock.now >= mutationDeadline {
                Issue.record("The toolbar Markdown Comment action did not apply its exact transform.")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(harness.latestSource == expected)
        #expect(harness.session.context?.undoLabel == "Markdown Comment")
        #expect(harness.session.generation == 1)
        await harness.closeAndDrain()
    }

    @Test("Edit selection toolbar centers above the complete visual selection")
    func editSelectionToolbarCentersAboveCompleteVisualSelection() async throws {
        let longSelectionLine = "This selected line deliberately reaches across most of the editor width so its visible center differs from its endpoints."
        let shortSelectionLine = "Short selected tail."
        let source = [
            "First prelude establishes space above the selection.",
            "Second prelude keeps the fixture deterministic.",
            "Third prelude keeps the target away from the top edge.",
            longSelectionLine,
            shortSelectionLine,
            "Following text remains outside the selection.",
        ].joined(separator: "\n") + "\n"
        let from = try #require(source.range(of: longSelectionLine)?.lowerBound)
            .utf16Offset(in: source)
        let to = try #require(source.range(of: shortSelectionLine)?.upperBound)
            .utf16Offset(in: source)
        let harness = EditorHarness(source: source, laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()

        harness.session.revealSourceRange(fromUTF16: from, toUTF16: to)
        try await harness.waitUntilSelection(head: to, stage: "visual toolbar anchor")
        harness.session.focus()
        try await harness.waitUntilFocused()

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        var toolbar = try await harness.session.testingSelectionToolbarSnapshot()
        while toolbar.hidden {
            if clock.now >= deadline {
                Issue.record("The Edit toolbar did not appear for its visual-anchor regression.")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(20))
            toolbar = try await harness.session.testingSelectionToolbarSnapshot()
        }

        let selectionCenter = (toolbar.selectionLeft + toolbar.selectionRight) / 2
        let expectedLeft = max(
            8,
            min(
                selectionCenter - toolbar.rootWidth / 2,
                toolbar.viewportWidth - toolbar.rootWidth - 8
            )
        )
        #expect(abs(toolbar.rootLeft - expectedLeft) <= 1)
        #expect(toolbar.rootBottom <= toolbar.selectionTop - 5)
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("Edit selection toolbar skips equivalent repeated updates")
    func editSelectionToolbarRepeatedUpdateWork() async throws {
        let source = "Repeated toolbar update remains exact.\n"
        let selectedRange = try #require(source.range(of: "Repeated toolbar update"))
        let from = selectedRange.lowerBound.utf16Offset(in: source)
        let to = selectedRange.upperBound.utf16Offset(in: source)
        let harness = EditorHarness(source: source, laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()
        harness.session.revealSourceRange(fromUTF16: from, toUTF16: to)
        try await harness.waitUntilSelection(head: to, stage: "toolbar performance selection")
        harness.session.focus()
        try await harness.waitUntilFocused()

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while try await harness.session.testingSelectionToolbarSnapshot().hidden {
            if clock.now >= deadline {
                Issue.record("The Edit toolbar did not appear for its performance diagnostic.")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let snapshot = try await harness.session.testingSelectionToolbarRepeatedUpdateSnapshot(
            iterations: 24
        )
        #expect(snapshot.iterationCount == 24)
        #expect(snapshot.attributeMutationCount == 0)
        #expect(snapshot.measureReadCount <= 1)
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        print("Edit toolbar bounded-work result: \(snapshot)")
        await harness.closeAndDrain()
    }

    @Test("Edit selection toolbar follows its selection through scroll and resize")
    func editSelectionToolbarTracksGeometryChanges() async throws {
        let target = "Anchored toolbar selection"
        let source = (1 ... 48).map { index in
            index == 24
                ? "\(target) remains exact."
                : "Synthetic editor paragraph \(index) provides disposable scrolling space."
        }.joined(separator: "\n\n")
        let range = try #require(source.range(of: target))
        let from = range.lowerBound.utf16Offset(in: source)
        let to = range.upperBound.utf16Offset(in: source)
        let harness = EditorHarness(source: source)
        defer { harness.close() }
        try await harness.waitUntilReady()
        harness.session.revealSourceRange(fromUTF16: from, toUTF16: to)
        try await harness.waitUntilSelection(head: to, stage: "scroll-anchored toolbar selection")
        harness.session.focus()
        try await harness.waitUntilFocused()

        let clock = ContinuousClock()
        let visibleDeadline = clock.now.advanced(by: .seconds(3))
        var before = try await harness.session.testingSelectionToolbarSnapshot()
        while before.hidden {
            if clock.now >= visibleDeadline {
                Issue.record("The Edit toolbar did not appear for its geometry regression.")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
            before = try await harness.session.testingSelectionToolbarSnapshot()
        }

        let scrollDelta = try await harness.session.testingScrollEditor(by: 56)
        #expect(scrollDelta >= 40)
        let afterScroll = try await harness.session.testingSelectionToolbarSnapshot()
        #expect(!afterScroll.hidden)
        #expect(abs(
            (afterScroll.rootTop - before.rootTop)
                - (afterScroll.selectionTop - before.selectionTop)
        ) <= 1.5)
        #expect(abs(
            (afterScroll.rootTop - afterScroll.selectionTop)
                - (before.rootTop - before.selectionTop)
        ) <= 1.5)

        harness.resize(width: 900)
        let resizeDeadline = clock.now.advanced(by: .seconds(3))
        var resized = try await harness.session.testingSelectionToolbarSnapshot()
        var resizedSelectionCenter = (resized.selectionLeft + resized.selectionRight) / 2
        var resizedExpectedLeft = max(
            8,
            min(
                resizedSelectionCenter - resized.rootWidth / 2,
                resized.viewportWidth - resized.rootWidth - 8
            )
        )
        while resized.viewportWidth <= afterScroll.viewportWidth
                || abs(resized.rootLeft - resizedExpectedLeft) > 1 {
            if clock.now >= resizeDeadline {
                Issue.record("The Edit toolbar did not converge after the viewport resize.")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
            resized = try await harness.session.testingSelectionToolbarSnapshot()
            resizedSelectionCenter = (resized.selectionLeft + resized.selectionRight) / 2
            resizedExpectedLeft = max(
                8,
                min(
                    resizedSelectionCenter - resized.rootWidth / 2,
                    resized.viewportWidth - resized.rootWidth - 8
                )
            )
        }
        #expect(abs(resized.rootLeft - resizedExpectedLeft) <= 1)
        #expect(resized.rootLeft >= 8)
        #expect(resized.rootLeft + resized.rootWidth <= resized.viewportWidth - 8 + 1)
        await harness.closeAndDrain()
    }

    @Test("Editor context menu starts with standard editing and adds only clicked-construct actions")
    func editorContextMenuOwnsOneCompactCommandProjection() {
        let webView = WindowAttachedWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            configuration: WKWebViewConfiguration()
        )
        func context(
            selection: MarkdownEditorSelectionRange,
            available: [MarkdownEditorCommand]
        ) -> MarkdownEditorContext {
            MarkdownEditorContext(
                selections: [selection],
                activeInlineConstructs: [],
                activeBlockConstructs: [],
                tablePosition: nil,
                composing: false,
                availableCommands: available,
                undoLabel: nil,
                redoLabel: nil
            )
        }

        let selectedMenu = webView.makeEditorContextMenu(
            context: context(
                selection: MarkdownEditorSelectionRange(anchor: 2, head: 8),
                available: [.bold, .toggleTask, .tableInsertRowAfter]
            ),
            mode: .livePreview,
            canPaste: true
        )
        #expect(Array(selectedMenu.items.prefix(5)).map(\.identifier?.rawValue) == [
            "scholium.editor.cut",
            "scholium.editor.copy",
            "scholium.editor.paste",
            nil,
            "scholium.editor.selectAll",
        ])
        #expect(selectedMenu.item(withTitle: ScholiumL10n.string("Cut"))?.isEnabled == true)
        #expect(selectedMenu.item(withTitle: ScholiumL10n.string("Copy"))?.isEnabled == true)
        #expect(selectedMenu.item(withTitle: ScholiumL10n.string("Paste"))?.isEnabled == true)
        let spelling = selectedMenu.item(
            withTitle: ScholiumL10n.string("Spelling and Grammar")
        )?.submenu
        #expect(spelling?.item(withTitle: ScholiumL10n.string("Show Spelling and Grammar"))?.action == NSSelectorFromString("showGuessPanel:"))
        #expect(spelling?.item(withTitle: ScholiumL10n.string("Check Spelling While Typing"))?.action == NSSelectorFromString("toggleContinuousSpellChecking:"))
        #expect(selectedMenu.item(withTitle: "Autofill") == nil)
        #expect(selectedMenu.item(withTitle: "Services") == nil)
        #expect(selectedMenu.item(withTitle: ScholiumL10n.string("Bold")) == nil)
        #expect(selectedMenu.item(withTitle: ScholiumL10n.string("Toggle Task")) == nil)

        let constructMenu = webView.makeEditorContextMenu(
            context: context(
                selection: MarkdownEditorSelectionRange(anchor: 4, head: 4),
                available: [.toggleTask, .tableInsertRowAfter]
            ),
            mode: .livePreview,
            canPaste: false
        )
        #expect(constructMenu.item(withTitle: ScholiumL10n.string("Cut"))?.isEnabled == false)
        #expect(constructMenu.item(withTitle: ScholiumL10n.string("Copy"))?.isEnabled == false)
        #expect(constructMenu.item(withTitle: ScholiumL10n.string("Paste"))?.isEnabled == false)
        #expect(constructMenu.item(withTitle: ScholiumL10n.string("Toggle Task")) != nil)
        #expect(constructMenu.item(withTitle: ScholiumL10n.string("Table"))?.submenu != nil)

        let sourceMenu = webView.makeEditorContextMenu(
            context: context(
                selection: MarkdownEditorSelectionRange(anchor: 4, head: 4),
                available: [.toggleTask, .tableInsertRowAfter]
            ),
            mode: .source,
            canPaste: true
        )
        #expect(sourceMenu.item(withTitle: ScholiumL10n.string("Toggle Task")) == nil)
        #expect(sourceMenu.item(withTitle: ScholiumL10n.string("Table")) == nil)
    }

    @Test("Native pasteboard image bytes route to attachment import")
    func nativeImagePasteboardRouting() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("scholium-image-paste-\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        let png = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        #expect(pasteboard.setData(png, forType: .init("public.png")))

        guard case .data(let data, let preferredFilename) =
                WindowAttachedWebView.pastedImageSource(in: pasteboard) else {
            Issue.record("Expected native PNG pasteboard bytes.")
            return
        }
        #expect(data == png)
        #expect(preferredFilename == "Pasted Image.png")
        pasteboard.clearContents()
    }

    @Test("Bridge v10 preserves exact commands, diagnostics, mode chrome, and reconstruction state")
    func bridgeCommandRoundTrip() async throws {
        // Swift Testing can schedule unrelated AppKit suites concurrently.
        // Let their short native-window journeys finish before this suite owns
        // the shared WebKit process; this is test-process isolation only.
        try await Task.sleep(for: .seconds(2))
        let frontmatter = "---\r\ntitle: Fixture\r\n---\r\n"
        let longTail = (1...40).map { "Research paragraph \($0)." }.joined(separator: "\r\n") + "\r\n"
        let original = frontmatter + "[[Target]]\r\nThesis\r\nSecond\r\n\r\n| **Claim** | Status | Count |\r\n|:---|:---:|---:|\r\n| Fittingness | Open | 2 |\r\n\r\nInline $x^2 + y^2$.\r\n\r\n$$\r\n\\int_0^1 x\\,dx\r\n$$\r\nClaim[^note] and inline ^[Inline note].\r\n\r\n[^note]: **Named** note\r\n  continued\r\n\r\n  - Outer item\r\n    - Nested item\r\n\r\n  > Quoted reason.\r\n\r\n  > [!state] Nested claim\r\n  > Body with $z$.\r\n\r\n  | Term | Value |\r\n  |:---|---:|\r\n  | $z$ | 3 |\r\n\r\n  $$\r\n  z^2\r\n  $$\r\n\r\n  ```swift\r\n  let value = 1\r\n  ```\r\n" + longTail + "\r\n## Shared heading\r\n\r\nA shared paragraph establishes the editorial measure.\r\n\r\n> [!state] Shared claim\r\n> The same callout must retain its typographic hierarchy.\r\n\r\nAfter shared callout.\r\n"
        let linkOffset = frontmatter.utf16.count
        let harness = EditorHarness(
            source: original,
            linkPreviews: [Self.linkPreview(atUTF16: linkOffset)]
        )
        defer { harness.close() }

        try await harness.waitUntilReady()
        #expect(harness.session.isReady)
        #expect(harness.session.isLoaded)
        #expect(harness.session.documentID == harness.documentID)
        #expect(harness.session.hasAttachedWebView)
        let initial: String
        do {
            initial = try await harness.session.currentText(for: harness.documentID)
        } catch {
            Issue.record(Comment(rawValue: "Initial bridge query failed: \(error.localizedDescription)"))
            return
        }
        #expect(initial == original)

        harness.session.resignFocus()
        try await Task.sleep(for: .milliseconds(150))
        do {
            #expect(!(try await harness.session.testingAccessibilitySnapshot()).isFocused)
        } catch {
            Issue.record("The resigned-focus accessibility snapshot failed: \(error).")
            throw error
        }
        harness.session.focus()
        try await harness.waitUntilFocused()

        let accessibility: MarkdownEditorSession.TestingAccessibilitySnapshot
        do {
            accessibility = try await harness.session.testingAccessibilitySnapshot()
        } catch {
            Issue.record("The initial accessibility snapshot failed: \(error).")
            throw error
        }
        #expect(accessibility.contentEditableCount == 1)
        #expect(accessibility.textboxCount == 1)
        #expect(accessibility.label == "Markdown editor, Edit mode")
        #expect(accessibility.multiline == "true")
        #expect(!accessibility.hasValueText)
        #expect(accessibility.spellcheck == "true")
        #expect(accessibility.mathRuntimeVersion == 1)
        #expect(accessibility.renderedMathCount == 4)
        #expect(accessibility.mathErrorCount == 0)
        #expect(accessibility.displayMathOverflowX == "auto")
        #expect(accessibility.frontmatterLineCount == 0)
        #expect(accessibility.frontmatterVisibleHeight == 0)
        #expect(accessibility.unclosedFrontmatterNoticeCount == 0)
        #expect(accessibility.semanticTableCount == 1)
        #expect(accessibility.liveTableSourceLineCount == 0)
        #expect(accessibility.tableHeaderCount == 3)
        #expect(accessibility.tableBodyCellCount == 3)
        #expect(accessibility.tableStrongCount == 1)
        #expect(accessibility.tableFirstHeaderText == "Claim")
        #expect(accessibility.tableOverflowX == "auto")
        #expect(accessibility.footnoteReferenceCount == 2)
        #expect(accessibility.footnoteDefinitionSourceCount == 1)
        #expect(accessibility.liveCalloutWidgetCount == 2)
        #expect(accessibility.liveCalloutSourceLineCount == 0)
        #expect(accessibility.exactWikilinkSourceCount == 1)
        #expect(accessibility.incompleteWikilinkSourceCount == 0)
        let normalizedOriginal = original.replacingOccurrences(of: "\r\n", with: "\n")
        let normalizedLines = normalizedOriginal.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        let displayMathLine = try #require(
            normalizedLines.firstIndex(where: { $0 == "$$" }).map { $0 + 1 }
        )
        harness.session.goToLine(displayMathLine)
        let activeMath = try await harness.waitUntilPresentation(stage: "active mathematics source") {
            $0.renderedMathCount == 3
        }
        #expect(activeMath.mathErrorCount == 0)
        #expect(try await harness.session.currentText(for: harness.documentID) == initial)

        let sharedCalloutLine = try #require(
            normalizedLines.firstIndex(where: { $0 == "> [!state] Shared claim" }).map { $0 + 1 }
        )
        let calloutFrom = try #require(normalizedOriginal.range(of: "> [!state] Shared claim")?.lowerBound)
            .utf16Offset(in: normalizedOriginal)
        let calloutSource = "> [!state] Shared claim\n> The same callout must retain its typographic hierarchy."
        let calloutTo = try #require(normalizedOriginal.range(of: calloutSource)?.upperBound)
            .utf16Offset(in: normalizedOriginal)
        try await harness.session.testingClickFirstCalloutText("same callout")
        let pointerDeadline = ContinuousClock().now.advanced(by: .seconds(3))
        while harness.session.context?.selections.first?.head != calloutTo {
            if ContinuousClock().now >= pointerDeadline {
                Issue.record("The projected Callout click did not enter its editable content-end boundary; head=\(harness.session.context?.selections.first?.head ?? -1), expected=\(calloutTo).")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let activeCallout = try await harness.waitUntilPresentation(stage: "active callout source") {
            $0.activeLiveBlockKind == "callout"
        }
        #expect(activeCallout.semanticTableCount == 1)
        #expect(activeCallout.liveCalloutSourceLineCount == 2)
        #expect(activeCallout.exactCalloutSourceCount == 0)
        #expect(try await harness.session.currentText(for: harness.documentID) == initial)

        harness.session.goToLine(sharedCalloutLine - 1)
        _ = try await harness.waitUntilPresentation(stage: "callout restored before arrow navigation") {
            $0.activeLiveBlockKind.isEmpty && $0.liveCalloutWidgetCount == 2
        }
        try await harness.session.testingPressArrow("ArrowDown")
        try await harness.waitUntilSelection(head: calloutFrom, stage: "down-arrow callout entry")
        _ = try await harness.waitUntilPresentation(stage: "arrow-revealed callout source") {
            $0.activeLiveBlockKind == "callout"
        }
        harness.session.goToLine(sharedCalloutLine + 3)
        _ = try await harness.waitUntilPresentation(stage: "callout restored below") {
            $0.activeLiveBlockKind.isEmpty && $0.liveCalloutWidgetCount == 2
        }
        try await harness.session.testingPressArrow("ArrowUp")
        try await harness.waitUntilSelection(
            head: calloutTo + 1,
            stage: "up-arrow real separator line"
        )
        try await harness.session.testingPressArrow("ArrowUp")
        try await harness.waitUntilSelection(head: calloutTo, stage: "up-arrow callout entry")
        _ = try await harness.waitUntilPresentation(stage: "up-arrow-revealed callout source") {
            $0.activeLiveBlockKind == "callout"
        }
        try await harness.session.testingPressArrow("ArrowUp")
        _ = try await harness.waitUntilSelection(in: calloutFrom..<calloutTo)

        let tableLine = try #require(
            normalizedLines.firstIndex(where: { $0 == "| **Claim** | Status | Count |" }).map { $0 + 1 }
        )
        harness.session.goToLine(tableLine)
        _ = try await harness.waitUntilPresentation(stage: "active table source") {
            $0.semanticTableCount == 0
                && $0.liveTableSourceLineCount > 0
        }
        let namedDefinitionLine = try #require(
            normalizedLines.firstIndex(where: { $0.hasPrefix("[^note]:") }).map { $0 + 1 }
        )
        harness.session.goToLine(namedDefinitionLine)
        let namedDefinitionOffset = try #require(normalizedOriginal.range(of: "[^note]:")?.lowerBound)
            .utf16Offset(in: normalizedOriginal)
        try await harness.waitUntilSelection(
            head: namedDefinitionOffset,
            stage: "named footnote definition"
        )
        let directFootnote = try await harness.waitUntilPresentation(stage: "direct footnote source") {
            $0.footnoteDefinitionSourceCount == 1
        }
        #expect(directFootnote.footnoteReferenceCount == 2)
        harness.session.goToLine(4)
        try await harness.waitUntilPreviewIsAvailable()
        #expect(harness.session.canShowPreviewAtSelection)
        harness.session.showPreview()
        let preview = try await harness.waitUntilPresentation(stage: "link preview") {
            !$0.previewPopoverHidden && $0.previewTitle == "Target note"
        }
        #expect(preview.previewTitle == "Target note")
        try await Task.sleep(for: .milliseconds(200))
        let presentationPerformance = try await harness.session.queryPerformanceSamples()
        #expect(presentationPerformance.contains { $0.name == "mode-toggle-work" })
        #expect(presentationPerformance.contains { $0.name == "cached-preview-work" })

        let initialSelection = try #require(harness.session.context?.selections)
        let configuredTopInset: CGFloat = 36
        let expectedPadding = "\(Int(configuredTopInset))px"
        harness.setPresentationCSS(ScholiumDocumentPresentationConfiguration(
            textScale: ScholiumMetrics.Document.defaultTextScale,
            contentTopInsetCSSPixels: configuredTopInset
        ).css)

        let live = try await harness.waitUntilPresentation(stage: "configured Live Preview") {
            $0.label == "Markdown editor, Edit mode"
                && $0.contentPaddingTop == expectedPadding
                && $0.contentPaddingInlineStart == "20px"
        }
        #expect(live.gutterCount == 0)
        #expect(live.lineNumberCount == 0)
        #expect(live.activeLineCount == 0)
        #expect(live.liveProjectionDOMCount > 0)
        #expect(live.selectionActionsCount == 1)
        #expect(live.previewPopoverCount == 1)
        #expect(live.contentPaddingInlineStart == "20px")
        #expect(live.isFocused)

        harness.session.setMode(.source)
        let sourceMode = try await harness.waitUntilPresentation(stage: "Source mode") {
            $0.label == "Markdown source editor"
                && $0.gutterCount > 0
                && $0.lineNumberCount > 0
                && $0.liveProjectionDOMCount == 0
                && $0.selectionActionsCount == 0
                && $0.previewPopoverCount == 0
        }
        #expect(sourceMode.activeLineCount > 0)
        #expect(sourceMode.renderedMathCount == 0)
        #expect(sourceMode.semanticTableCount == 0)
        #expect(sourceMode.footnoteReferenceCount == 0)
        #expect(sourceMode.previewPopoverHidden)
        #expect(sourceMode.contentPaddingTop == expectedPadding)
        #expect(sourceMode.contentPaddingInlineStart == "20px")
        #expect(sourceMode.isFocused)
        #expect(harness.session.context?.selections == initialSelection)
        let bodyStartEditorOffset = frontmatter.replacingOccurrences(of: "\r\n", with: "\n").utf16.count
        harness.session.goToLine(2)
        try await harness.waitUntilSelection(head: 4, stage: "Source frontmatter line")
        harness.session.setMode(.livePreview)
        _ = try await harness.waitUntilPresentation(stage: "frontmatter-clamped Live Preview") {
            $0.label == "Markdown editor, Edit mode" && $0.frontmatterLineCount == 0
        }
        try await harness.waitUntilSelection(
            head: bodyStartEditorOffset,
            stage: "Edit body clamp"
        )
        harness.session.setMode(.source)
        _ = try await harness.waitUntilPresentation(stage: "frontmatter selection restored Source") {
            $0.label == "Markdown source editor" && $0.lineNumberCount > 0
        }
        try await harness.waitUntilSelection(head: 4, stage: "restored Source frontmatter")
        let bodyEditorOffset = (frontmatter.replacingOccurrences(of: "\r\n", with: "\n") + "[[Target]]\n").utf16.count
        let bodySourceOffset = (frontmatter + "[[Target]]\r\n").utf16.count
        harness.session.goToLine(5)
        try await harness.waitUntilSelection(head: bodyEditorOffset, stage: "Source body line")

        harness.session.setMode(.livePreview)
        let restoredLive = try await harness.waitUntilPresentation(stage: "restored Live Preview") {
            $0.label == "Markdown editor, Edit mode"
                && $0.gutterCount == 0
                && $0.renderedMathCount == 4
                && $0.semanticTableCount == 1
                && $0.footnoteReferenceCount == 2
        }
        #expect(restoredLive.lineNumberCount == 0)
        #expect(restoredLive.activeLineCount == 0)
        #expect(restoredLive.contentPaddingTop == expectedPadding)
        #expect(restoredLive.isFocused)
        #expect(restoredLive.renderedMathCount == 4)
        #expect(restoredLive.semanticTableCount == 1)
        #expect(restoredLive.footnoteReferenceCount == 2)
        #expect(try await harness.session.currentText(for: harness.documentID) == initial)
        #expect(harness.session.context?.selections.first?.head == bodyEditorOffset)

        do {
            try await harness.session.perform(.bold)
        } catch {
            Issue.record(Comment(rawValue: "Formatting command failed: \(error.localizedDescription)"))
            return
        }

        let updated = try await harness.session.currentText(for: harness.documentID)
        let expectedUpdated = try inserting("****", atUTF16: bodySourceOffset, in: original)
        #expect(updated == expectedUpdated)
        #expect(harness.latestSource == expectedUpdated)
        #expect(harness.session.generation == 1)
        #expect(harness.session.isDirty)

        for _ in 0..<25 {
            harness.session.setMode(.source)
            _ = try await harness.waitUntilPresentation(stage: "stress Source mode") {
                $0.label == "Markdown source editor"
                    && $0.gutterCount > 0
                    && $0.lineNumberCount > 0
                    && $0.liveProjectionDOMCount == 0
                    && $0.selectionActionsCount == 0
                    && $0.previewPopoverCount == 0
            }
            harness.session.setMode(.livePreview)
            _ = try await harness.waitUntilPresentation(stage: "stress Live Preview") {
                $0.label == "Markdown editor, Edit mode"
                    && $0.gutterCount == 0
                    && $0.lineNumberCount == 0
            }
        }
        #expect(try await harness.session.currentText(for: harness.documentID) == expectedUpdated)
        #expect(harness.session.isDirty)
        #expect(harness.session.hasAttachedWebView)
        let modeStressSamples = try await harness.session.queryPerformanceSamples()
        let latestModeTransition = try #require(
            modeStressSamples.last { $0.name == "mode-toggle-work" }
        )
        #expect((latestModeTransition.observed["transitionSequence"] ?? 0) >= 50)

        let pastePayload = #"{"plainText":"Reason","html":"<strong>Reason</strong>"}"#
        try await harness.session.perform(.pasteMarkdown, argument: pastePayload)
        let pasted = try await harness.session.currentText(for: harness.documentID)
        let expectedPasted = try inserting("****Reason****", atUTF16: bodySourceOffset, in: original)
        #expect(pasted == expectedPasted)
        #expect(harness.session.generation == 2)

        let unicode = "e\u{301} | é | 👩🏽‍💻️ | العربية، Markdown | עברית (LTR)"
        let unicodeInsertionOffset = try #require(harness.session.context?.selections.first?.head)
        try await harness.session.perform(.pastePlain, argument: unicode)
        let beforeTermination = try await harness.session.currentText(for: harness.documentID)
        let expectedBeforeTermination = try insertingAtEditorOffset(
            unicode,
            editorUTF16: unicodeInsertionOffset,
            in: pasted
        )
        #expect(Data(beforeTermination.utf8) == Data(expectedBeforeTermination.utf8))
        #expect(Array(beforeTermination.utf16) == Array(expectedBeforeTermination.utf16))
        #expect(harness.session.isDirty)
        let insertionOffset = try #require(harness.session.context?.selections.first?.head)

        // Terminate before the bounded EditorState capture can replace the
        // delta-checked mirror fallback. Recovery must retain the last context
        // selection so the next insertion remains at the end of the source.
        #expect(harness.session.testingSimulateWebContentProcessTermination())
        try await harness.waitUntilReady()
        let recovered = try await harness.session.currentText(for: harness.documentID)
        #expect(Data(recovered.utf8) == Data(beforeTermination.utf8))
        #expect(Array(recovered.utf16) == Array(beforeTermination.utf16))
        #expect(harness.session.isDirty)

        try await harness.session.perform(.pastePlain, argument: "!")
        let afterSelectionRestore = try await harness.session.currentText(for: harness.documentID)
        let expectedAfterSelectionRestore = try insertingAtEditorOffset(
            "!",
            editorUTF16: insertionOffset,
            in: recovered
        )
        #expect(Data(afterSelectionRestore.utf8) == Data(expectedAfterSelectionRestore.utf8))
        #expect(Array(afterSelectionRestore.utf16) == Array(expectedAfterSelectionRestore.utf16))

        // Collapse/reopen uses the same explicit recovery capture before
        // SwiftUI dismantles the WKWebView. The retained session must restore
        // exact bytes, selection, bounded undo history, focus, and scroll.
        let selectionBeforeReconstruction = try #require(harness.session.context?.selections.first)
        _ = try #require(harness.session.context?.undoLabel)
        let beforeScroll = try await harness.session.testingAccessibilitySnapshot()
        #expect(beforeScroll.scrollExtent > 0)
        try await harness.session.testingApplyScrollFraction(0.65)
        let fractionScrollAnchor = try await harness.waitUntilScrollAnchor()
        #expect(fractionScrollAnchor.fallbackFraction > 0.2)
        let anchorText = "Research paragraph 30."
        let anchorRange = try #require(afterSelectionRestore.range(of: anchorText))
        let anchorLowerBound = anchorRange.lowerBound.utf16Offset(in: afterSelectionRestore)
        let requestedAnchor = EditorScrollAnchor(
            sourceFingerprint: DocumentFingerprint(content: afterSelectionRestore).sha256,
            sourceUTF16Offset: anchorLowerBound,
            blockUTF16LowerBound: anchorLowerBound,
            blockUTF16UpperBound: anchorLowerBound + anchorText.utf16.count,
            relativeBlockPosition: 0,
            fallbackFraction: 0.65
        )
        try await harness.session.testingApplyScrollAnchor(requestedAnchor)
        let semanticScrollAnchor = try await harness.waitUntilScrollAnchor()
        #expect(semanticScrollAnchor.fallbackFraction > 0.2)
        #expect(abs(semanticScrollAnchor.sourceUTF16Offset - anchorLowerBound) < 4)
        #expect(semanticScrollAnchor.sourceUTF16Offset >= semanticScrollAnchor.blockUTF16LowerBound)
        #expect(semanticScrollAnchor.sourceUTF16Offset <= semanticScrollAnchor.blockUTF16UpperBound)

        #expect(harness.session.testingRetainedScrollAnchor?.blockUTF16LowerBound == semanticScrollAnchor.blockUTF16LowerBound)
        try await harness.session.captureStateForViewReconstruction()
        #expect(harness.session.testingRetainedScrollAnchor?.blockUTF16LowerBound == semanticScrollAnchor.blockUTF16LowerBound)
        try await harness.reconstructEditorView()
        try await harness.waitUntilReady()
        #expect(harness.session.testingRetainedScrollAnchor?.blockUTF16LowerBound == semanticScrollAnchor.blockUTF16LowerBound)

        let afterReopen = try await harness.session.currentText(for: harness.documentID)
        #expect(Data(afterReopen.utf8) == Data(afterSelectionRestore.utf8))
        #expect(harness.session.context?.selections.first == selectionBeforeReconstruction)
        #expect(harness.session.context?.undoLabel != nil)
        try await harness.waitUntilFocused()
        let restoredScrollAnchor = try await harness.waitUntilCurrentScrollAnchor {
            $0.sourceFingerprint == semanticScrollAnchor.sourceFingerprint
                && $0.blockUTF16LowerBound == semanticScrollAnchor.blockUTF16LowerBound
                && $0.blockUTF16UpperBound == semanticScrollAnchor.blockUTF16UpperBound
        }
        #expect(restoredScrollAnchor?.sourceFingerprint == semanticScrollAnchor.sourceFingerprint)
        #expect(restoredScrollAnchor?.sourceUTF16Offset == semanticScrollAnchor.sourceUTF16Offset)
        #expect(restoredScrollAnchor?.blockUTF16LowerBound == semanticScrollAnchor.blockUTF16LowerBound)
        #expect(restoredScrollAnchor?.blockUTF16UpperBound == semanticScrollAnchor.blockUTF16UpperBound)
        #expect((harness.session.testingRetainedScrollFraction ?? 0) > 0.2)
        let restoredAccessibility = try await harness.session.testingAccessibilitySnapshot()
        #expect(restoredAccessibility.isFocused)

        try await harness.session.perform(.pastePlain, argument: "?")
        let afterInsertion = try await harness.session.currentText(for: harness.documentID)
        let expectedAfterInsertion = try insertingAtEditorOffset(
            "?",
            editorUTF16: selectionBeforeReconstruction.head,
            in: afterSelectionRestore
        )
        #expect(afterInsertion == expectedAfterInsertion)
        let performanceSamples = try await harness.session.queryPerformanceSamples()
        #expect(!performanceSamples.isEmpty)
        #expect(performanceSamples.count <= 256)
        #expect(performanceSamples.contains { $0.name == "startup" })
        #expect(performanceSamples.contains { $0.name == "document-load" })
        #expect(performanceSamples.contains { $0.name == "projection" })
        #expect(performanceSamples.contains { $0.name == "bridge-request" })
        #expect(performanceSamples.allSatisfy {
            $0.durationMilliseconds.isFinite && $0.durationMilliseconds >= 0
                && $0.observed.values.allSatisfy { $0.isFinite && $0 >= 0 }
        })
        harness.resize(width: 1_080)
        harness.session.setMode(.source)
        let regularSourceGrid = try await harness.waitUntilPresentation(
            stage: "regular-width Source grid"
        ) {
            $0.label == "Markdown source editor"
                && $0.presentation.viewportWidth > 704
                && $0.presentation.rootLineWidth == "72ch"
                && (Double($0.contentPaddingInlineStart.dropLast(2)) ?? 0) > 40
        }
        #expect(regularSourceGrid.presentation.rootInlineSource == "40.000000px")
        #expect(regularSourceGrid.presentation.documentFontFamily.contains("Victor Mono"))
        #expect(try await harness.session.currentText(for: harness.documentID) == afterInsertion)

        let regularSourceInset = try #require(
            Double(regularSourceGrid.contentPaddingInlineStart.dropLast(2))
        )
        let selectionBeforeLineWidthChange = harness.session.context?.selections
        let undoBeforeLineWidthChange = harness.session.context?.undoLabel
        let scrollAnchorBeforeLineWidthChange = try await harness.session.currentScrollAnchor()
        let narrowMeasureProfile = DocumentAppearanceProfile(
            name: "Narrow Measure",
            settings: .init(lineWidthCharacterUnits: 48)
        )
        harness.setPresentationCSS(
            ScholiumDocumentPresentationConfiguration(
                textScale: ScholiumMetrics.Document.defaultTextScale,
                contentTopInsetCSSPixels: configuredTopInset
            ).css
                + "\n"
                + DocumentAppearanceStyles.css(for: narrowMeasureProfile)
        )
        let customSourceGrid = try await harness.waitUntilPresentation(
            stage: "custom Source line width"
        ) {
            $0.label == "Markdown source editor"
                && $0.presentation.rootLineWidth == "48ch"
                && (Double($0.contentPaddingInlineStart.dropLast(2)) ?? 0) > regularSourceInset
        }
        #expect(customSourceGrid.presentation.documentFontFamily.contains("Victor Mono"))
        #expect(customSourceGrid.isFocused)
        #expect(harness.session.context?.selections == selectionBeforeLineWidthChange)
        #expect(harness.session.context?.undoLabel == undoBeforeLineWidthChange)
        #expect(try await harness.session.currentText(for: harness.documentID) == afterInsertion)
        let scrollAnchorAfterLineWidthChange = try await harness.session.currentScrollAnchor()
        let anchorBefore = try #require(scrollAnchorBeforeLineWidthChange)
        let anchorAfter = try #require(scrollAnchorAfterLineWidthChange)
        #expect(anchorAfter.sourceFingerprint == anchorBefore.sourceFingerprint)
        // Soft wrapping changes visual block heights. Preserve the same
        // nearby semantic source location while allowing the viewport probe
        // to cross at most one neighboring logical line at a line boundary.
        let sourceDistance = abs(
            anchorAfter.sourceUTF16Offset - anchorBefore.sourceUTF16Offset
        )
        let neighboringLineBound = max(
            anchorBefore.blockUTF16UpperBound - anchorBefore.blockUTF16LowerBound,
            anchorAfter.blockUTF16UpperBound - anchorAfter.blockUTF16LowerBound
        ) + 2
        #expect(sourceDistance <= neighboringLineBound)
        harness.close()
        try await Task.sleep(for: .milliseconds(500))

        let unclosedSource = "\u{FEFF}---\ntitle: Unclosed\n[[Not a body link]]\n\n| A | B |\n|---|---|\n| $x$ | [^n] |\n\n[^n]: Note\n"
        let unclosedHarness = EditorHarness(source: unclosedSource)
        defer { unclosedHarness.close() }
        try await unclosedHarness.waitUntilReady()
        let unavailableLive = try await unclosedHarness.waitUntilPresentation(stage: "unclosed frontmatter") {
            $0.unclosedFrontmatterNoticeCount == 1
        }
        #expect(unavailableLive.gutterCount == 0)
        #expect(unavailableLive.lineNumberCount == 0)
        #expect(unavailableLive.frontmatterLineCount == 0)
        #expect(unavailableLive.semanticTableCount == 0)
        #expect(unavailableLive.renderedMathCount == 0)
        #expect(unavailableLive.previewAnchorCount == 0)
        let unavailableLiveSource = try await unclosedHarness.session.currentText(
            for: unclosedHarness.documentID
        )
        #expect(Data(unavailableLiveSource.utf8) == Data(unclosedSource.utf8))
        #expect(Array(unavailableLiveSource.utf16) == Array(unclosedSource.utf16))
        unclosedHarness.session.setMode(.source)
        let unclosedSourceMode = try await unclosedHarness.waitUntilPresentation(stage: "unclosed frontmatter Source") {
            $0.gutterCount > 0 && $0.lineNumberCount > 0
        }
        #expect(unclosedSourceMode.unclosedFrontmatterNoticeCount == 0)
        let unavailableSourceModeSource = try await unclosedHarness.session.currentText(
            for: unclosedHarness.documentID
        )
        #expect(Data(unavailableSourceModeSource.utf8) == Data(unclosedSource.utf8))
        #expect(Array(unavailableSourceModeSource.utf16) == Array(unclosedSource.utf16))
        unclosedHarness.close()
        try await Task.sleep(for: .milliseconds(300))

        let matrixHarness = EditorHarness(source: Self.testingPresentationFixtureSource())
        defer { matrixHarness.close() }
        try await matrixHarness.waitUntilReady()
        let livePresentationScenarios = try await matrixHarness.presentationSnapshots(
            for: Self.testingPresentationScenarios
        )
        matrixHarness.close()
        try await Task.sleep(for: .milliseconds(300))
        try await verifyReadSemanticScrollRestoration(liveScenarios: livePresentationScenarios)
    }

    private func inserting(_ insertion: String, atUTF16 offset: Int, in source: String) throws -> String {
        let units = source.utf16
        let position = try #require(units.index(units.startIndex, offsetBy: offset, limitedBy: units.endIndex))
        let index = try #require(String.Index(position, within: source))
        return String(source[..<index]) + insertion + source[index...]
    }

    private func insertingAtEditorOffset(
        _ insertion: String,
        editorUTF16 requestedOffset: Int,
        in source: String
    ) throws -> String {
        let units = Array(source.utf16)
        var sourceOffset = 0
        var editorOffset = 0
        while sourceOffset < units.count, editorOffset < requestedOffset {
            if units[sourceOffset] == 13,
               sourceOffset + 1 < units.count,
               units[sourceOffset + 1] == 10 {
                sourceOffset += 2
            } else {
                sourceOffset += 1
            }
            editorOffset += 1
        }
        #expect(editorOffset == requestedOffset)
        return try inserting(insertion, atUTF16: sourceOffset, in: source)
    }

    private static func linkPreview(atUTF16 offset: Int) -> DocumentLinkPreview {
        DocumentLinkPreview(
            sourceSpan: SourceSpan(
                utf8LowerBound: offset,
                utf8UpperBound: offset + 10,
                utf16LowerBound: offset,
                utf16UpperBound: offset + 10,
                start: SourcePosition(line: 4, utf8Column: 1, utf16Column: 1),
                end: SourcePosition(line: 4, utf8Column: 11, utf16Column: 11)
            ),
            target: VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Target.md"),
            targetFingerprint: DocumentFingerprint(content: "Target body"),
            title: "Target note",
            syntax: .wikilink,
            relationship: .neutral,
            fragment: nil,
            htmlBody: "<p>Target body</p>"
        )
    }

    @MainActor
    final class EditorHarness {
        let session: MarkdownEditorSession
        let documentID: String
        private let sourceBox: SourceBox
        var latestSource: String { session.checkedSource }
        var lifecycleSource: String { sourceBox.source }
        var latestScrollAnchor: EditorScrollAnchor? { sourceBox.scrollAnchor }
        var activatedLinks: [String] { sourceBox.activatedLinks }
        private let window: NSWindow
        private var hostingController: NSViewController?
        private var isClosed = false

        func synchronizeLifecycleSourceFromSession() {
            sourceBox.source = session.checkedSource
        }

        init(
            documentID: String = "Argument.md",
            source: String,
            linkPreviews: [DocumentLinkPreview] = [],
            bridgeDispatcher: (any MarkdownEditorBridgeDispatching)? = nil,
            lifecyclePolicy: ScholiumLifecyclePolicy = ScholiumLifecyclePolicy(),
            initialMode: MarkdownEditorMode = .livePreview,
            initialPresentationCSS: String = "",
            initialSourceRange: Range<Int>? = nil,
            initialWindowSize: NSSize = NSSize(width: 720, height: 520),
            fixedLayoutSize: NSSize? = nil,
            laysOutForPointerTesting: Bool = false
        ) {
            _ = NSApplication.shared
            session = bridgeDispatcher.map {
                MarkdownEditorSession(
                    bridgeDispatcher: $0,
                    lifecyclePolicy: lifecyclePolicy
                )
            } ?? MarkdownEditorSession()
            session.authorizeAutomaticFocus()
            if let initialSourceRange {
                session.revealSourceRange(
                    fromUTF16: initialSourceRange.lowerBound,
                    toUTF16: initialSourceRange.upperBound
                )
            }
            self.documentID = documentID
            sourceBox = SourceBox(source, mode: initialMode)
            sourceBox.presentationCSS = initialPresentationCSS
            window = NSWindow(
                contentRect: NSRect(
                    origin: .zero,
                    size: initialWindowSize
                ),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            // The harness is the sole window owner. AppKit's historical
            // close-release behavior must not invalidate this strong Swift
            // property before EditorHarness.deinit releases it.
            window.isReleasedWhenClosed = false
            let editor = EditorHarnessRoot(
                session: session,
                documentID: documentID,
                sourceBox: sourceBox,
                linkPreviews: linkPreviews,
                laysOutForPointerTesting: laysOutForPointerTesting,
                fixedLayoutSize: fixedLayoutSize
            )
            let hostingController = NSHostingController(rootView: editor)
            self.hostingController = hostingController
            window.contentViewController = hostingController
            window.orderFrontRegardless()
        }

        func waitUntilReady() async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(10))
            while !session.isReady || !session.isLoaded {
                if clock.now >= deadline {
                    Issue.record(Comment(rawValue: session.errorMessage ?? "The WKWebView editor did not become ready."))
                    throw MarkdownEditorSession.SessionError.unavailable
                }
                try await Task.sleep(for: .milliseconds(25))
            }
        }

        func waitUntilLoaded(documentID: String) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(5))
            while session.documentID != documentID || !session.isLoaded {
                if clock.now >= deadline {
                    Issue.record("The replacement editor document did not finish loading.")
                    throw MarkdownEditorSession.SessionError.unavailable
                }
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        func waitUntilPresentedMode(_ mode: MarkdownEditorMode) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(5))
            while session.presentedMode != mode {
                if clock.now >= deadline {
                    Issue.record("The editor did not publish the acknowledged \(mode.rawValue) mode.")
                    throw MarkdownEditorSession.SessionError.unavailable
                }
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        func resize(width: CGFloat) {
            window.setContentSize(NSSize(width: width, height: 520))
        }

        func resize(width: CGFloat, height: CGFloat) {
            window.setContentSize(NSSize(width: width, height: height))
        }

        func callPageJavaScript(
            _ body: String,
            arguments: [String: Any] = [:]
        ) async throws -> Any? {
            guard let webView = session.webView else {
                throw MarkdownEditorSession.SessionError.unavailable
            }
            return try await webView.callAsyncJavaScript(
                body,
                arguments: arguments,
                in: nil,
                contentWorld: .page
            )
        }

        func reconstructEditorView() async throws {
            sourceBox.showsEditor = false
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(3))
            while session.hasAttachedWebView {
                if clock.now >= deadline {
                    Issue.record("SwiftUI did not dismantle the editor view during reconstruction.")
                    throw MarkdownEditorSession.SessionError.unavailable
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            sourceBox.showsEditor = true
        }

        func waitUntilFocused() async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(3))
            while true {
                do {
                    if try await session.testingAccessibilitySnapshot().isFocused { return }
                } catch {
                    Issue.record("The focus polling snapshot failed: \(error).")
                    throw error
                }
                if clock.now >= deadline {
                    Issue.record("The reconstructed editor did not regain focus.")
                    throw MarkdownEditorSession.SessionError.unavailable
                }
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        func waitUntilPreviewIsAvailable() async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(3))
            while !session.canShowPreviewAtSelection {
                if clock.now >= deadline {
                    Issue.record("The editor did not move the insertion point to a previewable construct.")
                    throw MarkdownEditorSession.SessionError.unavailable
                }
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        func waitUntilSelection(head: Int, stage: String = "requested selection") async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(3))
            while session.context?.selections.first?.head != head {
                if clock.now >= deadline {
                    Issue.record(
                        "The editor did not publish \(stage); expected \(head), latest \(String(describing: session.context?.selections.first?.head))."
                    )
                    throw MarkdownEditorSession.SessionError.unavailable
                }
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        func waitUntilSelection(in expectedRange: Range<Int>) async throws -> Int {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(3))
            while true {
                if let head = session.context?.selections.first?.head,
                   expectedRange.contains(head) {
                    return head
                }
                if clock.now >= deadline {
                    Issue.record(
                        "The editor did not publish an insertion point inside \(expectedRange.lowerBound)..<\(expectedRange.upperBound); head=\(session.context?.selections.first?.head ?? -1)."
                    )
                    throw MarkdownEditorSession.SessionError.unavailable
                }
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        func waitUntilScrollAnchor() async throws -> EditorScrollAnchor {
            try await Task.sleep(for: .milliseconds(250))
            let anchor = try #require(try await session.currentScrollAnchor())
            sourceBox.scrollAnchor = anchor
            return anchor
        }

        func waitUntilCurrentScrollAnchor(
            matching predicate: (EditorScrollAnchor) -> Bool
        ) async throws -> EditorScrollAnchor? {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(3))
            while true {
                let anchor = try await session.currentScrollAnchor()
                if anchor.map(predicate) == true { return anchor }
                if clock.now >= deadline {
                    Issue.record("The editor did not stabilize the requested semantic scroll anchor; latest: \(String(describing: anchor)).")
                    throw MarkdownEditorSession.SessionError.unavailable
                }
                try await Task.sleep(for: .milliseconds(25))
            }
        }

        func waitUntilPresentation(
            stage: String,
            _ predicate: (MarkdownEditorSession.TestingAccessibilitySnapshot) -> Bool
        ) async throws -> MarkdownEditorSession.TestingAccessibilitySnapshot {
            let clock = ContinuousClock()
            // Keep the predicate semantic rather than accepting an incomplete
            // projection while WebKit finishes its layout work.
            let deadline = clock.now.advanced(by: .seconds(8))
            while true {
                let snapshot = try await session.testingAccessibilitySnapshot()
                if predicate(snapshot) { return snapshot }
                if clock.now >= deadline {
                    Issue.record("The editor did not apply \(stage); label=\(snapshot.label), top=\(snapshot.contentPaddingTop), inline=\(snapshot.contentPaddingInlineStart), rootRegular=\(snapshot.presentation.rootInlineRegular), rootNarrow=\(snapshot.presentation.rootInlineNarrow), rootLineWidth=\(snapshot.presentation.rootLineWidth), preview=\(snapshot.previewTitle), previewHidden=\(snapshot.previewPopoverHidden), tables=\(snapshot.semanticTableCount), footnoteReferences=\(snapshot.footnoteReferenceCount), footnoteDefinitions=\(snapshot.footnoteDefinitionSourceCount), callouts=\(snapshot.liveCalloutWidgetCount), title=\(snapshot.liveTitleCount), h1=\(snapshot.liveH1Count), h2=\(snapshot.liveH2Count), fences=\(snapshot.collapsedCodeFenceLineCount), fenceHeight=\(snapshot.collapsedCodeFenceVisibleHeight), listMarkers=\(snapshot.liveListMarkerCount), lines=\(snapshot.visibleLineClassSummary).")
                    throw MarkdownEditorSession.SessionError.unavailable
                }
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        func presentationSnapshots(
            for scenarios: [TestingPresentationScenario]
        ) async throws -> [(TestingPresentationScenario, MarkdownEditorSession.TestingPresentationSnapshot)] {
            var snapshots: [(TestingPresentationScenario, MarkdownEditorSession.TestingPresentationSnapshot)] = []
            for scenario in scenarios {
                window.appearance = NSAppearance(named: scenario.appearanceName)
                window.setContentSize(NSSize(width: scenario.width, height: 520))
                sourceBox.userCSS = scenario.liveUserCSS
                sourceBox.presentationCSS = scenario.presentationCSS
                _ = try await waitUntilPresentation(stage: scenario.name) {
                    $0.label == "Markdown editor, Edit mode"
                        && $0.presentation.rootTextScale == scenario.expectedTextScale
                        && $0.presentation.documentWidth > 0
                }
                try await Task.sleep(for: .milliseconds(100))
                let snapshot = try await waitUntilPresentation(stage: "stable \(scenario.name)") {
                    $0.label == "Markdown editor, Edit mode"
                        && $0.presentation.rootTextScale == scenario.expectedTextScale
                        && $0.presentation.documentWidth > 0
                }
                snapshots.append((scenario, snapshot.presentation))
            }
            return snapshots
        }

        func setPresentationCSS(_ css: String) {
            sourceBox.presentationCSS = css
        }

        func close() {
            guard !isClosed else { return }
            isClosed = true
            window.orderOut(nil)
            window.contentViewController = nil
            hostingController = nil
            window.close()
        }

        /// SwiftUI dismantles the representable synchronously, but WebKit and
        /// AppKit finish releasing window-owned objects on subsequent main-run
        /// loop turns. Crossing a Swift Testing autorelease-pool boundary
        /// immediately after `close()` can therefore race those releases on
        /// the selected Xcode beta. Product code never relies on this helper;
        /// the integration harness waits for its real detach boundary and then
        /// gives framework-owned cleanup a bounded drain interval.
        func closeAndDrain() async {
            close()
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(2))
            while session.hasAttachedWebView, clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
            #expect(!session.hasAttachedWebView)
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    @MainActor
    private final class SuspendingInitialSelectionBridgeDispatcher:
        MarkdownEditorBridgeDispatching
    {
        private let production = WKWebViewMarkdownEditorBridgeDispatcher()
        private var continuation: CheckedContinuation<Void, Never>?
        private var didSuspend = false

        func dispatch(
            requestJSON: String,
            in webView: WKWebView
        ) async throws -> Any? {
            let request = try JSONDecoder().decode(
                MarkdownEditorRequest.self,
                from: Data(requestJSON.utf8)
            )
            let result = try await production.dispatch(
                requestJSON: requestJSON,
                in: webView
            )
            if !didSuspend,
               case .initialize(_, _, _, .some) = request.operation {
                didSuspend = true
                await withCheckedContinuation { continuation = $0 }
            }
            return result
        }

        func waitUntilSuspended() async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(3))
            while continuation == nil {
                if clock.now >= deadline {
                    Issue.record("The initial selection did not reach its acknowledgement boundary.")
                    throw MarkdownEditorSession.SessionError.unavailable
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        func resume() {
            continuation?.resume()
            continuation = nil
        }
    }

    @MainActor
    private final class WrongInitialSelectionBridgeDispatcher:
        MarkdownEditorBridgeDispatching
    {
        private let production = WKWebViewMarkdownEditorBridgeDispatcher()

        func dispatch(
            requestJSON: String,
            in webView: WKWebView
        ) async throws -> Any? {
            let request = try JSONDecoder().decode(
                MarkdownEditorRequest.self,
                from: Data(requestJSON.utf8)
            )
            let result = try await production.dispatch(
                requestJSON: requestJSON,
                in: webView
            )
            guard case .initialize(_, _, _, .some) = request.operation,
                  var object = result as? [String: Any] else {
                return result
            }
            object["selections"] = [["anchor": 0, "head": 0]]
            if var context = object["context"] as? [String: Any] {
                context["selections"] = object["selections"]
                object["context"] = context
            }
            return object
        }
    }

    @MainActor
    private final class FailingPostInitializeBridgeDispatcher:
        MarkdownEditorBridgeDispatching
    {
        private enum ProbeError: Error { case postInitializeFailure }
        private let production = WKWebViewMarkdownEditorBridgeDispatcher()
        private var initialized = false

        func dispatch(
            requestJSON: String,
            in webView: WKWebView
        ) async throws -> Any? {
            let request = try JSONDecoder().decode(
                MarkdownEditorRequest.self,
                from: Data(requestJSON.utf8)
            )
            if initialized, case .setScrollFraction = request.operation {
                throw ProbeError.postInitializeFailure
            }
            let result = try await production.dispatch(
                requestJSON: requestJSON,
                in: webView
            )
            if case .initialize = request.operation { initialized = true }
            return result
        }
    }

    @MainActor
    private final class FailingBlurBridgeDispatcher:
        MarkdownEditorBridgeDispatching
    {
        private enum ProbeError: Error { case blurFailure }
        private let production = WKWebViewMarkdownEditorBridgeDispatcher()
        private(set) var didAttemptBlur = false

        func dispatch(
            requestJSON: String,
            in webView: WKWebView
        ) async throws -> Any? {
            let request = try JSONDecoder().decode(
                MarkdownEditorRequest.self,
                from: Data(requestJSON.utf8)
            )
            if case .blur = request.operation {
                didAttemptBlur = true
                throw ProbeError.blurFailure
            }
            return try await production.dispatch(
                requestJSON: requestJSON,
                in: webView
            )
        }
    }

    @MainActor
    private final class FailingQueryTextBridgeDispatcher:
        MarkdownEditorBridgeDispatching
    {
        private enum ProbeError: Error { case queryTextFailure }
        private let production = WKWebViewMarkdownEditorBridgeDispatcher()
        var shouldFailQueryText = false
        private(set) var didFailQueryText = false

        func dispatch(
            requestJSON: String,
            in webView: WKWebView
        ) async throws -> Any? {
            let request = try JSONDecoder().decode(
                MarkdownEditorRequest.self,
                from: Data(requestJSON.utf8)
            )
            if shouldFailQueryText,
               case .queryText = request.operation {
                didFailQueryText = true
                throw ProbeError.queryTextFailure
            }
            return try await production.dispatch(
                requestJSON: requestJSON,
                in: webView
            )
        }
    }

    @MainActor
    private final class SuspendingBridgeDispatcher: MarkdownEditorBridgeDispatching {
        private enum ProbeError: Error {
            case transportFailure
        }

        private enum ResumeOutcome: Equatable {
            case success
            case failure
        }

        private let targetDocumentID: String
        private let production = WKWebViewMarkdownEditorBridgeDispatcher()
        private var didSuspend = false
        private var continuation: CheckedContinuation<Void, Never>?
        private var outcome: ResumeOutcome = .success

        init(targetDocumentID: String) {
            self.targetDocumentID = targetDocumentID
        }

        func dispatch(
            requestJSON: String,
            in webView: WKWebView
        ) async throws -> Any? {
            let request = try JSONDecoder().decode(
                MarkdownEditorRequest.self,
                from: Data(requestJSON.utf8)
            )
            if !didSuspend,
               request.documentID == targetDocumentID,
               case .queryText = request.operation {
                didSuspend = true
                await withCheckedContinuation { continuation = $0 }
                if outcome == .failure {
                    throw ProbeError.transportFailure
                }
                return try await production.dispatch(requestJSON: requestJSON, in: webView)
            }
            return try await production.dispatch(requestJSON: requestJSON, in: webView)
        }

        func waitUntilSuspended() async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(3))
            while continuation == nil {
                if clock.now >= deadline {
                    Issue.record("The bridge request did not reach the deterministic suspension point.")
                    throw MarkdownEditorSession.SessionError.unavailable
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        func resumeSuccessfully() {
            outcome = .success
            continuation?.resume()
            continuation = nil
        }

        func resumeWithTransportError() {
            outcome = .failure
            continuation?.resume()
            continuation = nil
        }
    }

    @MainActor
    private final class SuspendingModeBridgeDispatcher: MarkdownEditorBridgeDispatching {
        private let production = WKWebViewMarkdownEditorBridgeDispatcher()
        private var didSuspend = false
        private var continuation: CheckedContinuation<Void, Never>?
        private(set) var requestedModes: [MarkdownEditorMode] = []

        func dispatch(
            requestJSON: String,
            in webView: WKWebView
        ) async throws -> Any? {
            let request = try JSONDecoder().decode(
                MarkdownEditorRequest.self,
                from: Data(requestJSON.utf8)
            )
            if case .setMode(let mode) = request.operation {
                requestedModes.append(mode)
                if !didSuspend {
                    didSuspend = true
                    await withCheckedContinuation { continuation = $0 }
                }
            }
            return try await production.dispatch(requestJSON: requestJSON, in: webView)
        }

        func waitUntilSuspended() async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(3))
            while continuation == nil {
                if clock.now >= deadline {
                    Issue.record("The mode bridge request did not reach its acknowledgement boundary.")
                    throw MarkdownEditorSession.SessionError.unavailable
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        func resume() {
            continuation?.resume()
            continuation = nil
        }

        func waitUntilModeRequestCount(_ expectedCount: Int) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(3))
            while requestedModes.count < expectedCount {
                if clock.now >= deadline {
                    Issue.record("The editor did not converge the latest requested mode.")
                    throw MarkdownEditorSession.SessionError.unavailable
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    @MainActor
    private final class FailingOnceModeBridgeDispatcher: MarkdownEditorBridgeDispatching {
        private enum ProbeError: Error {
            case transientTransportFailure
        }

        private let production = WKWebViewMarkdownEditorBridgeDispatcher()
        private var hasFailed = false
        private(set) var requestedModes: [MarkdownEditorMode] = []

        func dispatch(
            requestJSON: String,
            in webView: WKWebView
        ) async throws -> Any? {
            let request = try JSONDecoder().decode(
                MarkdownEditorRequest.self,
                from: Data(requestJSON.utf8)
            )
            if case .setMode(let mode) = request.operation {
                requestedModes.append(mode)
                if !hasFailed {
                    hasFailed = true
                    throw ProbeError.transientTransportFailure
                }
            }
            return try await production.dispatch(requestJSON: requestJSON, in: webView)
        }
    }

    @MainActor
    private final class SourceBox: ObservableObject {
        @Published var source: String
        @Published var showsEditor = true
        @Published var scrollAnchor: EditorScrollAnchor?
        @Published var presentationCSS = ""
        @Published var userCSS = ""
        var activatedLinks: [String] = []
        let mode: MarkdownEditorMode
        init(_ source: String, mode: MarkdownEditorMode) {
            self.source = source
            self.mode = mode
        }
    }

    private struct EditorHarnessRoot: View {
        @ObservedObject var sourceBox: SourceBox
        let session: MarkdownEditorSession
        let documentID: String
        let linkPreviews: [DocumentLinkPreview]
        let laysOutForPointerTesting: Bool
        let fixedLayoutSize: NSSize?

        init(
            session: MarkdownEditorSession,
            documentID: String,
            sourceBox: SourceBox,
            linkPreviews: [DocumentLinkPreview],
            laysOutForPointerTesting: Bool,
            fixedLayoutSize: NSSize?
        ) {
            self.session = session
            self.documentID = documentID
            self.sourceBox = sourceBox
            self.linkPreviews = linkPreviews
            self.laysOutForPointerTesting = laysOutForPointerTesting
            self.fixedLayoutSize = fixedLayoutSize
        }

        var body: some View {
            if sourceBox.showsEditor {
                if let fixedLayoutSize {
                    editorSurface
                        .frame(width: fixedLayoutSize.width, height: fixedLayoutSize.height)
                } else if laysOutForPointerTesting {
                    editorSurface
                        .frame(width: 720, height: 520)
                } else {
                    editorSurface
                }
            }
        }

        private var editorSurface: some View {
            MarkdownEditorWebView(
                    session: session,
                    documentID: documentID,
                    performanceDocumentID: documentID,
                    source: sourceBox.source,
                    mode: sourceBox.mode,
                    presentationCSS: sourceBox.presentationCSS,
                    userCSS: sourceBox.userCSS,
                    requiresMathRuntime: MarkdownEditorWebView.requiresMathRuntime(
                        source: sourceBox.source,
                        linkPreviews: linkPreviews
                    ),
                    linkCompletionQuery: { _, _ in [] },
                    linkPreviews: linkPreviews,
                    initialScrollFraction: 0,
                    initialScrollAnchor: sourceBox.scrollAnchor,
                    onDocumentActivity: {},
                    onRequestSave: {},
                    onRequestFind: { _ in },
                    onRequestImportImage: {},
                    onRequestIndexImage: {},
                    onPasteImage: { _ in false },
                    onLinkActivation: { sourceBox.activatedLinks.append($0) },
                    onScrollFractionChange: { _ in },
                    onScrollAnchorChange: { sourceBox.scrollAnchor = $0 }
            )
        }
    }

}
