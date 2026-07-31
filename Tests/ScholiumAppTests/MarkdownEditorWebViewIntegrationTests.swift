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
    @Test("The published editor mode changes only after the Web bridge acknowledges it")
    func presentedModeWaitsForBridgeAcknowledgement() async throws {
        let dispatcher = SuspendingModeBridgeDispatcher()
        let harness = EditorHarness(
            source: "# Mode handoff\n",
            bridgeDispatcher: dispatcher
        )
        defer { harness.close() }
        try await harness.waitUntilReady()
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

    @Test("Edit footnote markers hand pointer placement back to CodeMirror")
    func editFootnoteReferenceUsesOrdinaryPointerPlacement() async throws {
        let source = "Claim[^note].\n\n[^note]: Basis.\n"
        let referenceRange = try #require(source.range(of: "[^note]"))
        let referenceFrom = referenceRange.lowerBound.utf16Offset(in: source)
        let referenceTo = referenceRange.upperBound.utf16Offset(in: source)
        let harness = EditorHarness(source: source, laysOutForPointerTesting: true)
        defer { harness.close() }
        try await harness.waitUntilReady()
        harness.session.focus()
        try await harness.waitUntilFocused()

        let initialPresentation = try await harness.waitUntilPresentation(
            stage: "passive Edit footnote marker"
        ) {
            $0.footnoteReferenceCount == 1 && $0.footnoteDefinitionSourceCount == 0
        }
        #expect(initialPresentation.footnoteItemCount == 1)

        try await harness.session.testingClickFirstFootnoteReference()
        _ = try await harness.waitUntilSelection(in: referenceFrom..<(referenceTo + 1))
        let sourcePresentation = try await harness.waitUntilPresentation(
            stage: "pointer-revealed Edit footnote source"
        ) {
            $0.footnoteReferenceCount == 0 && $0.footnoteDefinitionSourceCount == 0
        }
        #expect(sourcePresentation.footnoteItemCount == 1)
        #expect(try await harness.session.currentText(for: harness.documentID) == source)
        await harness.closeAndDrain()
    }

    @Test("Edit footnote definitions reveal their exact Markdown content for editing")
    func editFootnoteDefinitionActivatesEditableSource() async throws {
        let source = "Claim[^note].\n\n[^note]: Basis for revision.\n"
        let prefix = "Preface added before projected content.\n\n"
        let harness = EditorHarness(source: source)
        defer { harness.close() }
        harness.resize(width: 700)
        try await harness.waitUntilReady()
        harness.setPresentationCSS(ScholiumDocumentPresentationConfiguration(textScale: 2).css)
        _ = try await harness.waitUntilPresentation(stage: "two-hundred-percent footnote") {
            $0.presentation.rootTextScale == "2.000000em"
                && $0.footnoteItemCount == 1
                && $0.footnoteDefinitionSourceCount == 0
        }

        harness.session.goToLine(1)
        try await harness.waitUntilSelection(head: 0)
        try await harness.session.perform(.pastePlain, argument: prefix)
        let shiftedSource = prefix + source
        let contentFrom = try #require(shiftedSource.range(of: "Basis"))
            .lowerBound.utf16Offset(in: shiftedSource)
        _ = try await harness.waitUntilPresentation(stage: "shifted projected footnote") {
            $0.footnoteItemCount == 1 && $0.footnoteDefinitionSourceCount == 0
        }

        try await harness.session.testingClickFirstFootnoteDefinition()
        try await harness.waitUntilSelection(head: contentFrom)
        let revealed = try await harness.waitUntilPresentation(
            stage: "pointer-revealed footnote definition source"
        ) {
            $0.footnoteDefinitionSourceCount > 0 && $0.footnoteItemCount == 0
        }
        #expect(revealed.footnoteSectionCount == 0)

        try await harness.session.perform(.pastePlain, argument: "Revised ")
        let expected = shiftedSource.replacingOccurrences(
            of: "Basis for revision.",
            with: "Revised Basis for revision."
        )
        #expect(try await harness.session.currentText(for: harness.documentID) == expected)
        #expect(harness.latestSource == expected)
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
        #expect(fresh.collapsedBlankLineCount > 0)
        #expect(fresh.collapsedBlankLineVisibleHeight <= 0.5)

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
        #expect(retained.collapsedBlankLineCount == fresh.collapsedBlankLineCount)
        #expect(retained.collapsedBlankLineVisibleHeight <= 0.5)
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

        try await harness.session.resignFocusAndWait()
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
                && $0.liveTaskSourceTokenCount == 0
        }
        #expect(inactive.liveListMarkerUsesPrimaryText)
        #expect(inactive.liveListMarkerText == "•|•|◦|1.|2.|1.|•|•")

        let taskSourceFrom = try #require(source.range(of: "- [ ] Open task fixture"))
            .lowerBound.utf16Offset(in: source)
        harness.session.goToLine(11)
        try await harness.waitUntilSelection(head: taskSourceFrom)
        let active = try await harness.waitUntilPresentation(stage: "active exact task source") {
            $0.liveListMarkerCount == 7 && $0.liveTaskSourceTokenCount == 1
        }
        #expect(active.liveListMarkerUsesPrimaryText)
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

    @Test("A projected Callout enters its half-open source range before Backspace")
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
        let calloutFrom = calloutRange.lowerBound.utf16Offset(in: source)
        let calloutTo = calloutRange.upperBound.utf16Offset(in: source)
        let harness = EditorHarness(source: source)
        defer { harness.close() }
        try await harness.waitUntilReady()
        _ = try await harness.waitUntilPresentation(stage: "passive Callout before Backspace") {
            $0.liveCalloutWidgetCount == 2 && $0.collapsedBlankLineVisibleHeight <= 0.5
        }

        try await harness.session.testingClickFirstCalloutText("synthetic note")
        _ = try await harness.waitUntilSelection(in: calloutFrom..<calloutTo)
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

    @Test("Bridge v7 preserves exact commands, diagnostics, mode chrome, and reconstruction state")
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
        #expect(accessibility.renderedMathCount == 2)
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
        #expect(accessibility.footnoteSectionCount == 1)
        #expect(accessibility.footnoteItemCount == 2)
        #expect(accessibility.footnoteStrongCount == 1)
        #expect(accessibility.footnoteNestedListCount == 1)
        #expect(accessibility.footnoteBlockquoteCount == 1)
        #expect(accessibility.footnoteCodeBlockCount == 1)
        #expect(accessibility.footnoteCalloutCount == 1)
        #expect(accessibility.footnoteTableCount == 1)
        #expect(accessibility.footnoteRenderedMathCount == 3)
        #expect(accessibility.footnoteDefinitionSourceCount == 0)
        #expect(accessibility.liveCalloutWidgetCount == 1)
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
            $0.renderedMathCount == 1
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
        while harness.session.context?.selections.first?.head != calloutTo - 1 {
            if ContinuousClock().now >= pointerDeadline {
                Issue.record("The projected Callout click did not enter its half-open source range; head=\(harness.session.context?.selections.first?.head ?? -1), expected=\(calloutTo - 1).")
                throw MarkdownEditorSession.SessionError.unavailable
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let activeCallout = try await harness.waitUntilPresentation(stage: "active callout source") {
            $0.activeLiveBlockKind == "callout"
        }
        #expect(activeCallout.semanticTableCount == 1)
        #expect(try await harness.session.currentText(for: harness.documentID) == initial)

        harness.session.goToLine(sharedCalloutLine - 1)
        _ = try await harness.waitUntilPresentation(stage: "callout restored before arrow navigation") {
            $0.activeLiveBlockKind.isEmpty && $0.liveCalloutWidgetCount == 1
        }
        try await harness.session.testingPressArrow("ArrowDown")
        try await harness.waitUntilSelection(head: calloutFrom, stage: "down-arrow callout entry")
        _ = try await harness.waitUntilPresentation(stage: "arrow-revealed callout source") {
            $0.activeLiveBlockKind == "callout"
        }
        harness.session.goToLine(sharedCalloutLine + 3)
        _ = try await harness.waitUntilPresentation(stage: "callout restored below") {
            $0.activeLiveBlockKind.isEmpty && $0.liveCalloutWidgetCount == 1
        }
        try await harness.session.testingPressArrow("ArrowUp")
        try await harness.waitUntilSelection(head: calloutTo - 1, stage: "up-arrow callout entry")
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
                && $0.footnoteItemCount == 2
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
        let revealedFootnote = try await harness.waitUntilPresentation(stage: "revealed footnote source") {
            $0.footnoteItemCount == 1 && $0.footnoteDefinitionSourceCount > 0
        }
        #expect(revealedFootnote.footnoteReferenceCount == 2)
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
        #expect(sourceMode.footnoteSectionCount == 0)
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
                && $0.renderedMathCount == 2
                && $0.semanticTableCount == 1
                && $0.footnoteItemCount == 2
                && $0.footnoteReferenceCount == 2
        }
        #expect(restoredLive.lineNumberCount == 0)
        #expect(restoredLive.activeLineCount == 0)
        #expect(restoredLive.contentPaddingTop == expectedPadding)
        #expect(restoredLive.isFocused)
        #expect(restoredLive.renderedMathCount == 2)
        #expect(restoredLive.semanticTableCount == 1)
        #expect(restoredLive.footnoteItemCount == 2)
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
        #expect(unavailableLive.footnoteSectionCount == 0)
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
        var latestSource: String { sourceBox.source }
        var latestScrollAnchor: EditorScrollAnchor? { sourceBox.scrollAnchor }
        private let window: NSWindow
        private var hostingController: NSViewController?
        private var isClosed = false

        init(
            documentID: String = "Argument.md",
            source: String,
            linkPreviews: [DocumentLinkPreview] = [],
            bridgeDispatcher: (any MarkdownEditorBridgeDispatching)? = nil,
            lifecyclePolicy: ScholiumLifecyclePolicy = ScholiumLifecyclePolicy(),
            initialMode: MarkdownEditorMode = .livePreview,
            initialPresentationCSS: String = "",
            laysOutForPointerTesting: Bool = false
        ) {
            _ = NSApplication.shared
            session = bridgeDispatcher.map {
                MarkdownEditorSession(
                    bridgeDispatcher: $0,
                    lifecyclePolicy: lifecyclePolicy
                )
            } ?? MarkdownEditorSession()
            self.documentID = documentID
            sourceBox = SourceBox(source, mode: initialMode)
            sourceBox.presentationCSS = initialPresentationCSS
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
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
                laysOutForPointerTesting: laysOutForPointerTesting
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
                    Issue.record("The editor did not apply \(stage); label=\(snapshot.label), top=\(snapshot.contentPaddingTop), inline=\(snapshot.contentPaddingInlineStart), rootRegular=\(snapshot.presentation.rootInlineRegular), rootNarrow=\(snapshot.presentation.rootInlineNarrow), rootLineWidth=\(snapshot.presentation.rootLineWidth), preview=\(snapshot.previewTitle), previewHidden=\(snapshot.previewPopoverHidden), tables=\(snapshot.semanticTableCount), footnotes=\(snapshot.footnoteItemCount), callouts=\(snapshot.footnoteCalloutCount), title=\(snapshot.liveTitleCount), h1=\(snapshot.liveH1Count), h2=\(snapshot.liveH2Count), fences=\(snapshot.collapsedCodeFenceLineCount), fenceHeight=\(snapshot.collapsedCodeFenceVisibleHeight), listMarkers=\(snapshot.liveListMarkerCount), lines=\(snapshot.visibleLineClassSummary).")
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
                let result = MarkdownEditorCommandResult(
                    requestID: request.requestID,
                    resultingGeneration: request.expectedGeneration,
                    sourceChanged: false,
                    selections: [MarkdownEditorSelectionRange(anchor: 0, head: 0)],
                    undoLabel: nil,
                    text: "Stale A\n",
                    context: nil,
                    selection: nil,
                    recovery: nil,
                    scrollAnchor: nil,
                    performanceSamples: nil,
                    accepted: true,
                    error: nil
                )
                return try JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(result)
                )
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

        init(
            session: MarkdownEditorSession,
            documentID: String,
            sourceBox: SourceBox,
            linkPreviews: [DocumentLinkPreview],
            laysOutForPointerTesting: Bool
        ) {
            self.session = session
            self.documentID = documentID
            self.sourceBox = sourceBox
            self.linkPreviews = linkPreviews
            self.laysOutForPointerTesting = laysOutForPointerTesting
        }

        var body: some View {
            if sourceBox.showsEditor {
                if laysOutForPointerTesting {
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
                    source: sourceBox.source,
                    mode: sourceBox.mode,
                    presentationCSS: sourceBox.presentationCSS,
                    userCSS: sourceBox.userCSS,
                    linkCompletionQuery: { _ in [] },
                    linkPreviews: linkPreviews,
                    initialScrollFraction: 0,
                    initialScrollAnchor: sourceBox.scrollAnchor,
                    onDocumentChange: { sourceBox.source = $0 },
                    onRequestSave: {},
                    onRequestSearch: {},
                    onLinkActivation: { _ in },
                    onScrollFractionChange: { _ in },
                    onScrollAnchorChange: { sourceBox.scrollAnchor = $0 }
            )
        }
    }

}
