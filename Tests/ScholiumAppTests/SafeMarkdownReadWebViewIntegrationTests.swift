import AppKit
import ScholiumContracts
import SwiftUI
import Testing
import WebKit
@testable import ScholiumApp

extension MarkdownEditorWebViewIntegrationTests {
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

    struct TestingPresentationScenario {
        let name: String
        let width: CGFloat
        let configuration: ScholiumDocumentPresentationConfiguration
        let appearanceName: NSAppearance.Name
        let readUserCSS: String
        let liveUserCSS: String

        init(
            name: String,
            width: CGFloat,
            configuration: ScholiumDocumentPresentationConfiguration,
            appearanceName: NSAppearance.Name,
            readUserCSS: String = "",
            liveUserCSS: String = ""
        ) {
            self.name = name
            self.width = width
            self.configuration = configuration
            self.appearanceName = appearanceName
            self.readUserCSS = readUserCSS
            self.liveUserCSS = liveUserCSS
        }

        var expectedTextScale: String {
            String(format: "%.6fem", locale: Locale(identifier: "en_US_POSIX"), configuration.textScale)
        }

        func expectedInlineInset(viewportWidth: Double) -> String {
            let compactBoundary = Double(configuration.compactThresholdRootEms) * 16
            let value = viewportWidth <= compactBoundary
                ? configuration.compactInlineInsetCSSPixels
                : configuration.regularInlineInsetCSSPixels
            return "\(Int(value))px"
        }

        var expectedParagraphGap: String {
            String(
                format: "%.6fpx",
                locale: Locale(identifier: "en_US_POSIX"),
                Double(ScholiumDocumentRhythm.paragraphGapCSSPixels) * configuration.textScale
            )
        }
    }

    static let testingPresentationScenarios: [TestingPresentationScenario] = [
        .init(name: "narrow", width: 520, configuration: .init(textScale: 1), appearanceName: .aqua),
        .init(name: "compact-boundary", width: 704, configuration: .init(textScale: 1), appearanceName: .aqua),
        .init(name: "two-hundred-percent", width: 900, configuration: .init(textScale: 2), appearanceName: .aqua),
        .init(name: "dark", width: 720, configuration: .init(textScale: 1), appearanceName: .darkAqua),
        .init(
            name: "increased-contrast-dark",
            width: 720,
            configuration: .init(textScale: 1),
            appearanceName: .accessibilityHighContrastDarkAqua
        ),
        .init(name: "workspace-900", width: 900, configuration: .init(textScale: 1), appearanceName: .aqua),
        .init(name: "wide", width: 1_080, configuration: .init(textScale: 1), appearanceName: .aqua),
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
        for (scenario, readSnapshot) in readScenarios {
            let liveSnapshot = try #require(liveScenarios.first { $0.0.name == scenario.name }?.1)
            expectSharedPresentationParity(read: readSnapshot, live: liveSnapshot)
            #expect(readSnapshot.rootTextScale == scenario.expectedTextScale)
            #expect(readSnapshot.rootContentTopInset == "32.000000px")
            #expect(readSnapshot.rootInlineRegular == "32.000000px")
            #expect(readSnapshot.rootInlineSource == "40.000000px")
            #expect(readSnapshot.rootInlineNarrow == "20.000000px")
            #expect(readSnapshot.rootParagraphGap == scenario.expectedParagraphGap)
            #expect(readSnapshot.documentPaddingInlineStart == scenario.expectedInlineInset(
                viewportWidth: readSnapshot.viewportWidth
            ))
            if scenario.readUserCSS.isEmpty {
                #expect(abs(readSnapshot.documentWidth - readSnapshot.viewportWidth) <= 1)
            }
            #expect(readSnapshot.pageHorizontalOverflow <= 1)
        }
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
        x^2 + y^2
        $$

        Claim[^parity].

        [^parity]: **Shared** footnote.

        """
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
        #expect(live.titleTextDecorationLine == read.titleTextDecorationLine)
        #expect(live.titleTextDecorationLine == "none")
        #expect(live.titleBorderBottomWidth == read.titleBorderBottomWidth)
        #expect(live.titleBorderBottomWidth == "1px")
        #expect(abs(live.titleWidth - read.titleWidth) <= 1)

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

        #expect(live.footnoteFontFamily == read.footnoteFontFamily)
        #expect(live.footnoteColor == read.footnoteColor)
        #expect(live.footnoteFontSize == read.footnoteFontSize)
        #expect(live.footnoteLineHeight == read.footnoteLineHeight)
        #expect(live.footnoteMarginBlockStart == read.footnoteMarginBlockStart)
        #expect(live.footnoteListPaddingInlineStart == read.footnoteListPaddingInlineStart)
        #expect(abs(live.footnoteWidth - read.footnoteWidth) <= 1)

        #expect(live.mathOverflowX == read.mathOverflowX)
        #expect(live.mathColor == read.mathColor)
        #expect(live.mathFontSize == read.mathFontSize)
        #expect(live.mathLineHeight == read.mathLineHeight)
        #expect(live.mathMarginBlockStart == read.mathMarginBlockStart)
        #expect(live.mathPaddingBlockStart == read.mathPaddingBlockStart)
        #expect(abs(live.mathWidth - read.mathWidth) <= 1)
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
    }

    @MainActor
    private final class ReadHarness {
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
                contentWorld: .page
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
                contentWorld: .page
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
                const titleBlockStyle = style('.scholium-document > h1:first-child');
                const titleStyle = textStyle('.scholium-document > h1:first-child');
                const calloutStyle = style('.scholium-document > .scholium-callout-state');
                const calloutRoleStyle = style('.scholium-document > .scholium-callout-state .scholium-callout-role');
                const calloutTitleStyle = style('.scholium-document > .scholium-callout-state .scholium-callout-title');
                const orientationStyle = style('.scholium-document > .scholium-callout-orient .scholium-callout-body');
                const tableStyle = style('.scholium-document > .scholium-table-scroll');
                const tableCellStyle = style('.scholium-document > .scholium-table-scroll th');
                const footnoteStyle = style('.scholium-document > .footnotes');
                const footnoteListStyle = style('.scholium-document > .footnotes > ol');
                const mathStyle = style('.scholium-document > .scholium-math-display');
                return {
                    rootContentTopInset: rootStyle.getPropertyValue('--scholium-document-content-top-inset').trim(),
                    rootTextScale: rootStyle.getPropertyValue('--scholium-document-text-scale').trim(),
                    rootProseLineHeight: rootStyle.getPropertyValue('--scholium-rhythm-prose-line-height').trim(),
                    rootParagraphGap: rootStyle.getPropertyValue('--scholium-rhythm-paragraph-gap').trim(),
                    rootHeadingLineHeight: rootStyle.getPropertyValue('--scholium-rhythm-heading-line-height').trim(),
                    rootInlineRegular: rootStyle.getPropertyValue('--scholium-rhythm-inline-regular').trim(),
                    rootInlineSource: rootStyle.getPropertyValue('--scholium-rhythm-inline-source').trim(),
                    rootInlineNarrow: rootStyle.getPropertyValue('--scholium-rhythm-inline-narrow').trim(),
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
                    titleTextDecorationLine: titleStyle?.textDecorationLine || '',
                    titleBorderBottomWidth: titleBlockStyle?.borderBottomWidth || '',
                    titleWidth: width('.scholium-document > h1:first-child'),
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
                    footnoteFontFamily: footnoteStyle?.fontFamily || '',
                    footnoteColor: footnoteStyle?.color || '',
                    footnoteFontSize: footnoteStyle?.fontSize || '',
                    footnoteLineHeight: footnoteStyle?.lineHeight || '',
                    footnoteMarginBlockStart: footnoteStyle?.marginBlockStart || '',
                    footnoteListPaddingInlineStart: footnoteListStyle?.paddingInlineStart || '',
                    footnoteWidth: width('.scholium-document > .footnotes'),
                    mathOverflowX: mathStyle?.overflowX || '',
                    mathColor: mathStyle?.color || '',
                    mathFontSize: mathStyle?.fontSize || '',
                    mathLineHeight: mathStyle?.lineHeight || '',
                    mathMarginBlockStart: mathStyle?.marginBlockStart || '',
                    mathPaddingBlockStart: mathStyle?.paddingBlockStart || '',
                    mathWidth: width('.scholium-document > .scholium-math-display')
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
                let nextCSS = scenario.configuration.css
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
        @ObservedObject var sourceBox: SourceBox

        var body: some View {
            var surface = SafeMarkdownReadWebView(
                documentID: "ReadFixture.md",
                fingerprint: fingerprint,
                source: source,
                htmlBody: htmlBody,
                presentationCSS: sourceBox.presentationCSS,
                userCSS: sourceBox.userCSS,
                researcherComments: [],
                onLinkClick: { _ in },
                onOpenExternalURL: { _ in },
                onCommentSelection: nil,
                onCommentActivation: nil,
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
