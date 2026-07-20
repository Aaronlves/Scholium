import AppKit
import ScholiumContracts
import SwiftUI
import Testing
@testable import ScholiumApp

@Suite("Markdown editor WKWebView integration", .serialized)
@MainActor
struct MarkdownEditorWebViewIntegrationTests {
    @Test("One hundred thousand CJK characters preserve an exact appended edit across modes")
    func largeCJKExactRoundTrip() async throws {
        let seed = "研究性能边界输入选择撤销渲染滚动保存恢复"
        let cjkCharacters = String(
            String(repeating: seed, count: 100_000 / seed.count + 1).prefix(100_000)
        )
        let source = "---\ntitle: WK 100k CJK\n---\n# CJK Stress\n\n\(cjkCharacters)\n"
        let token = "QA-CJK-END-\(UUID().uuidString)"
        let harness = EditorHarness(source: source)
        defer { harness.close() }

        try await harness.waitUntilReady()
        harness.session.goToLine(source.split(separator: "\n", omittingEmptySubsequences: false).count)
        try await harness.waitUntilSelection(head: source.utf16.count)
        try await harness.session.perform(.pastePlain, argument: token)

        let edited = try await harness.session.currentText(for: harness.documentID)
        #expect(Data(edited.utf8) == Data((source + token).utf8))
        #expect(harness.latestSource == source + token)
        #expect(harness.session.isDirty)

        harness.session.setMode(.source)
        _ = try await harness.waitUntilPresentation(stage: "100k Source mode") {
            $0.label == "Markdown source editor" && $0.gutterCount > 0
        }
        harness.session.setMode(.livePreview)
        _ = try await harness.waitUntilPresentation(stage: "100k Live Preview") {
            $0.label == "Markdown live preview editor" && $0.gutterCount == 0
        }
        #expect(try await harness.session.currentText(for: harness.documentID) == source + token)
        await harness.closeAndDrain()
    }

    @Test("Bridge v3 preserves exact commands, diagnostics, mode chrome, and reconstruction state")
    func bridgeCommandRoundTrip() async throws {
        // Swift Testing can schedule unrelated AppKit suites concurrently.
        // Let their short native-window journeys finish before this suite owns
        // the shared WebKit process; this is test-process isolation only.
        try await Task.sleep(for: .seconds(2))
        let frontmatter = "---\r\ntitle: Fixture\r\n---\r\n"
        let longTail = (1...40).map { "Research paragraph \($0)." }.joined(separator: "\r\n") + "\r\n"
        let original = frontmatter + "[[Target]]\r\nThesis\r\nSecond\r\n\r\n| **Claim** | Status | Count |\r\n|:---|:---:|---:|\r\n| Fittingness | Open | 2 |\r\n\r\nInline $x^2 + y^2$.\r\n\r\n$$\r\n\\int_0^1 x\\,dx\r\n$$\r\nClaim[^note] and inline ^[Inline note].\r\n\r\n[^note]: **Named** note\r\n  continued\r\n\r\n  - Outer item\r\n    - Nested item\r\n\r\n  > Quoted reason.\r\n\r\n  > [!state] Nested claim\r\n  > Body with $z$.\r\n\r\n  | Term | Value |\r\n  |:---|---:|\r\n  | $z$ | 3 |\r\n\r\n  $$\r\n  z^2\r\n  $$\r\n\r\n  ```swift\r\n  let value = 1\r\n  ```\r\n" + longTail + "\r\n## Shared heading\r\n\r\nA shared paragraph establishes the editorial measure.\r\n\r\n> [!state] Shared claim\r\n> The same callout must retain its typographic hierarchy.\r\n"
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
        #expect(accessibility.label == "Markdown live preview editor")
        #expect(accessibility.multiline == "true")
        #expect(!accessibility.hasValueText)
        #expect(accessibility.spellcheck == "true")
        #expect(accessibility.mathRuntimeVersion == 1)
        #expect(accessibility.renderedMathCount == 2)
        #expect(accessibility.mathErrorCount == 0)
        #expect(accessibility.displayMathOverflowX == "auto")
        #expect(accessibility.frontmatterLineCount == 3)
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
        do {
            try await harness.session.testingPreviewFirstFootnote()
        } catch {
            Issue.record("The footnote preview request failed after the presentation matrix: \(error).")
            throw error
        }
        let footnotePreview = try await harness.waitUntilPresentation(stage: "footnote preview") {
            $0.previewTitle == "Footnote note" && !$0.previewPopoverHidden
        }
        #expect(footnotePreview.previewNestedListCount == 1)
        #expect(footnotePreview.previewBlockquoteCount == 1)
        #expect(footnotePreview.previewCodeBlockCount == 1)
        #expect(footnotePreview.previewCalloutCount == 1)
        #expect(footnotePreview.previewTableCount == 1)
        #expect(footnotePreview.previewRenderedMathCount == 3)
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
        harness.session.goToLine(sharedCalloutLine)
        let activeCallout = try await harness.waitUntilPresentation(stage: "active callout source") {
            $0.liveCalloutWidgetCount == 0 && $0.liveCalloutSourceLineCount > 0
        }
        #expect(activeCallout.semanticTableCount == 1)
        #expect(try await harness.session.currentText(for: harness.documentID) == initial)

        let tableLine = try #require(
            normalizedLines.firstIndex(where: { $0 == "| **Claim** | Status | Count |" }).map { $0 + 1 }
        )
        harness.session.goToLine(tableLine)
        _ = try await harness.waitUntilPresentation(stage: "active table source") {
            $0.semanticTableCount == 0
                && $0.liveTableSourceLineCount > 0
                && $0.footnoteItemCount == 2
        }
        try await harness.session.testingRevealFirstFootnoteDefinition()
        let namedDefinitionOffset = try #require(normalizedOriginal.range(of: "[^note]:")?.lowerBound)
            .utf16Offset(in: normalizedOriginal)
        try await harness.waitUntilSelection(head: namedDefinitionOffset)
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
        harness.setUserCSS(ScholiumDocumentPresentationConfiguration(
            textScale: ScholiumMetrics.Document.defaultTextScale,
            contentTopInset: configuredTopInset
        ).css)

        let live = try await harness.waitUntilPresentation(stage: "configured Live Preview") {
            $0.label == "Markdown live preview editor"
                && $0.contentPaddingTop == expectedPadding
                && ["0px", "24px"].contains($0.contentPaddingInlineStart)
        }
        #expect(live.gutterCount == 0)
        #expect(live.lineNumberCount == 0)
        #expect(live.activeLineCount == 0)
        #expect(["0px", "24px"].contains(live.contentPaddingInlineStart))
        #expect(live.isFocused)

        harness.session.setMode(.source)
        let sourceMode = try await harness.waitUntilPresentation(stage: "Source mode") {
            $0.label == "Markdown source editor"
                && $0.gutterCount > 0
                && $0.lineNumberCount > 0
        }
        #expect(sourceMode.activeLineCount > 0)
        #expect(sourceMode.renderedMathCount == 0)
        #expect(sourceMode.semanticTableCount == 0)
        #expect(sourceMode.footnoteSectionCount == 0)
        #expect(sourceMode.footnoteReferenceCount == 0)
        #expect(sourceMode.previewPopoverHidden)
        #expect(sourceMode.contentPaddingTop == expectedPadding)
        #expect(sourceMode.isFocused)
        #expect(harness.session.context?.selections == initialSelection)
        let bodyEditorOffset = (frontmatter.replacingOccurrences(of: "\r\n", with: "\n") + "[[Target]]\n").utf16.count
        let bodySourceOffset = (frontmatter + "[[Target]]\r\n").utf16.count
        harness.session.goToLine(5)
        try await harness.waitUntilSelection(head: bodyEditorOffset)

        harness.session.setMode(.livePreview)
        let restoredLive = try await harness.waitUntilPresentation(stage: "restored Live Preview") {
            $0.label == "Markdown live preview editor"
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
            }
            harness.session.setMode(.livePreview)
            _ = try await harness.waitUntilPresentation(stage: "stress Live Preview") {
                $0.label == "Markdown live preview editor"
                    && $0.gutterCount == 0
                    && $0.lineNumberCount == 0
            }
        }
        #expect(try await harness.session.currentText(for: harness.documentID) == expectedUpdated)
        #expect(harness.session.isDirty)
        #expect(harness.session.hasAttachedWebView)
        let modeStressSamples = try await harness.session.queryPerformanceSamples()
        #expect(modeStressSamples.filter { $0.name == "mode-toggle-work" }.count >= 50)

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
    private final class EditorHarness {
        let session = MarkdownEditorSession()
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
            linkPreviews: [DocumentLinkPreview] = []
        ) {
            _ = NSApplication.shared
            self.documentID = documentID
            sourceBox = SourceBox(source)
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
                linkPreviews: linkPreviews
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

        func waitUntilSelection(head: Int) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(3))
            while session.context?.selections.first?.head != head {
                if clock.now >= deadline {
                    Issue.record("The editor did not publish the requested insertion point.")
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
                    Issue.record("The editor did not apply \(stage); label=\(snapshot.label), preview=\(snapshot.previewTitle), previewHidden=\(snapshot.previewPopoverHidden), tables=\(snapshot.semanticTableCount), footnotes=\(snapshot.footnoteItemCount), callouts=\(snapshot.footnoteCalloutCount).")
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
                sourceBox.userCSS = scenario.configuration.css
                _ = try await waitUntilPresentation(stage: scenario.name) {
                    $0.label == "Markdown live preview editor"
                        && $0.presentation.rootTextScale == scenario.expectedTextScale
                        && $0.presentation.rootReadableMeasure == scenario.expectedReadableMeasure
                        && $0.presentation.documentWidth > 0
                }
                try await Task.sleep(for: .milliseconds(100))
                let snapshot = try await waitUntilPresentation(stage: "stable \(scenario.name)") {
                    $0.label == "Markdown live preview editor"
                        && $0.presentation.rootTextScale == scenario.expectedTextScale
                        && $0.presentation.rootReadableMeasure == scenario.expectedReadableMeasure
                        && $0.presentation.documentWidth > 0
                }
                snapshots.append((scenario, snapshot.presentation))
            }
            return snapshots
        }

        func setUserCSS(_ css: String) {
            sourceBox.userCSS = css
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
    private final class SourceBox: ObservableObject {
        @Published var source: String
        @Published var showsEditor = true
        @Published var scrollAnchor: EditorScrollAnchor?
        @Published var userCSS = ""
        init(_ source: String) { self.source = source }
    }

    private struct EditorHarnessRoot: View {
        @ObservedObject var sourceBox: SourceBox
        let session: MarkdownEditorSession
        let documentID: String
        let linkPreviews: [DocumentLinkPreview]

        init(
            session: MarkdownEditorSession,
            documentID: String,
            sourceBox: SourceBox,
            linkPreviews: [DocumentLinkPreview]
        ) {
            self.session = session
            self.documentID = documentID
            self.sourceBox = sourceBox
            self.linkPreviews = linkPreviews
        }

        var body: some View {
            if sourceBox.showsEditor {
                editorSurface
            }
        }

        private var editorSurface: some View {
            MarkdownEditorWebView(
                    session: session,
                    documentID: documentID,
                    source: sourceBox.source,
                    mode: .livePreview,
                    userCSS: sourceBox.userCSS,
                    linkCompletions: [],
                    linkPreviews: linkPreviews,
                    researcherComments: [],
                    initialScrollFraction: 0,
                    initialScrollAnchor: sourceBox.scrollAnchor,
                    onDocumentChange: { sourceBox.source = $0 },
                    onRequestSave: {},
                    onRequestSearch: {},
                    onRequestComment: {},
                    onLinkActivation: { _ in },
                    onCommentActivation: nil,
                    onScrollFractionChange: { _ in },
                    onScrollAnchorChange: { sourceBox.scrollAnchor = $0 }
            )
        }
    }

}
