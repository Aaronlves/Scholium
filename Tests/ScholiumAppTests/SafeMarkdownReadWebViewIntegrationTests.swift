import AppKit
import ScholiumContracts
import SwiftUI
import Testing
import WebKit
@testable import ScholiumApp

extension MarkdownEditorWebViewIntegrationTests {
    struct TestingPresentationScenario {
        let name: String
        let width: CGFloat
        let configuration: ScholiumDocumentPresentationConfiguration
        let appearanceName: NSAppearance.Name

        var expectedTextScale: String {
            String(format: "%.6fem", locale: Locale(identifier: "en_US_POSIX"), configuration.textScale)
        }

        var expectedReadableMeasure: String {
            String(format: "%.6fpx", locale: Locale(identifier: "en_US_POSIX"), Double(configuration.readableMeasure))
        }
    }

    static let testingPresentationScenarios: [TestingPresentationScenario] = [
        .init(name: "narrow", width: 520, configuration: .init(textScale: 1), appearanceName: .aqua),
        .init(name: "two-hundred-percent", width: 720, configuration: .init(textScale: 2), appearanceName: .aqua),
        .init(name: "dark", width: 720, configuration: .init(textScale: 1), appearanceName: .darkAqua),
        .init(
            name: "increased-contrast-dark",
            width: 720,
            configuration: .init(textScale: 1),
            appearanceName: .accessibilityHighContrastDarkAqua
        ),
        .init(name: "ordinary-restored", width: 720, configuration: .init(textScale: 1), appearanceName: .aqua),
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
        let readScenarios = try await harness.presentationSnapshots(for: Self.testingPresentationScenarios)
        #expect(readScenarios.count == liveScenarios.count)
        for (scenario, readSnapshot) in readScenarios {
            let liveSnapshot = try #require(liveScenarios.first { $0.0.name == scenario.name }?.1)
            expectSharedPresentationParity(read: readSnapshot, live: liveSnapshot)
            #expect(readSnapshot.rootTextScale == scenario.expectedTextScale)
            #expect(readSnapshot.rootReadableMeasure == scenario.expectedReadableMeasure)
        }
        let captured = try await harness.waitUntilCapturedAnchor(stage: "initial") {
            $0.blockUTF16LowerBound == fixture.anchorLowerBound
                && $0.blockUTF16UpperBound == fixture.anchorUpperBound
        }
        #expect(captured.sourceFingerprint == fingerprint)
        #expect(captured.blockUTF16LowerBound == fixture.anchorLowerBound)
        #expect(captured.blockUTF16UpperBound == fixture.anchorUpperBound)
        #expect(captured.fallbackFraction > 0.2)

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
        Cursor anchor.

        ## Shared heading

        A shared paragraph establishes the editorial measure.

        > [!state] Shared claim
        > The same callout must retain its typographic hierarchy.

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
        #expect(live.rootReadableMeasure == read.rootReadableMeasure)
        #expect(live.rootContentTopInset == read.rootContentTopInset)
        #expect(live.rootTextScale == read.rootTextScale)
        #expect(live.rootProseLineHeight == read.rootProseLineHeight)
        #expect(live.rootParagraphGap == read.rootParagraphGap)
        #expect(live.rootHeadingLineHeight == read.rootHeadingLineHeight)
        #expect(live.rootInlineRegular == read.rootInlineRegular)
        #expect(live.rootInlineNarrow == read.rootInlineNarrow)
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

        #expect(live.headingFontFamily == read.headingFontFamily)
        #expect(live.headingFontSize == read.headingFontSize)
        #expect(live.headingFontWeight == read.headingFontWeight)
        #expect(live.headingLineHeight == read.headingLineHeight)
        #expect(abs(live.headingBlockBefore - read.headingBlockBefore) <= 1)
        #expect(abs(live.headingBlockAfter - read.headingBlockAfter) <= 1)
        #expect(abs(live.headingWidth - read.headingWidth) <= 1)

        #expect(live.calloutAccent == read.calloutAccent)
        #expect(live.calloutBorderColor == read.calloutBorderColor)
        #expect(live.calloutFontSize == read.calloutFontSize)
        #expect(live.calloutLineHeight == read.calloutLineHeight)
        #expect(abs(live.calloutWidth - read.calloutWidth) <= 1)
        #expect(live.calloutRoleFontFamily == read.calloutRoleFontFamily)
        #expect(live.calloutRoleFontSize == read.calloutRoleFontSize)
        #expect(live.calloutRoleFontWeight == read.calloutRoleFontWeight)
        #expect(live.calloutRoleLineHeight == read.calloutRoleLineHeight)
        #expect(live.calloutRoleLetterSpacing == read.calloutRoleLetterSpacing)
        #expect(live.calloutTitleFontFamily == read.calloutTitleFontFamily)
        #expect(live.calloutTitleFontSize == read.calloutTitleFontSize)
        #expect(live.calloutTitleFontWeight == read.calloutTitleFontWeight)
        #expect(live.calloutTitleLineHeight == read.calloutTitleLineHeight)

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
            var anchor: EditorScrollAnchor?
            var fraction: Double
        }

        @Published var isReady = false
        @Published var restoration: Restoration
        @Published var capturedAnchor: EditorScrollAnchor?
        @Published var failure: String?
        @Published var userCSS = ""

        init(initialAnchor: EditorScrollAnchor?, initialScrollFraction: Double) {
            restoration = Restoration(anchor: initialAnchor, fraction: initialScrollFraction)
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
            initialScrollFraction: Double
        ) {
            _ = NSApplication.shared
            self.source = source
            self.htmlBody = htmlBody
            self.fingerprint = fingerprint
            sourceBox = SourceBox(
                initialAnchor: initialAnchor,
                initialScrollFraction: initialScrollFraction
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
            sourceBox.restoration = .init(anchor: initialAnchor, fraction: fallbackFraction)
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
                const documentStyle = style('.scholium-document');
                const headingStyle = style('.scholium-document > h2');
                const calloutStyle = style('.scholium-document > .scholium-callout-state');
                const calloutRoleStyle = style('.scholium-document > .scholium-callout-state .scholium-callout-role');
                const calloutTitleStyle = style('.scholium-document > .scholium-callout-state .scholium-callout-title');
                const tableStyle = style('.scholium-document > .scholium-table-scroll');
                const tableCellStyle = style('.scholium-document > .scholium-table-scroll th');
                const footnoteStyle = style('.scholium-document > .footnotes');
                const footnoteListStyle = style('.scholium-document > .footnotes > ol');
                const mathStyle = style('.scholium-document > .scholium-math-display');
                return {
                    rootReadableMeasure: rootStyle.getPropertyValue('--scholium-document-readable-measure').trim(),
                    rootContentTopInset: rootStyle.getPropertyValue('--scholium-document-content-top-inset').trim(),
                    rootTextScale: rootStyle.getPropertyValue('--scholium-document-text-scale').trim(),
                    rootProseLineHeight: rootStyle.getPropertyValue('--scholium-rhythm-prose-line-height').trim(),
                    rootParagraphGap: rootStyle.getPropertyValue('--scholium-rhythm-paragraph-gap').trim(),
                    rootHeadingLineHeight: rootStyle.getPropertyValue('--scholium-rhythm-heading-line-height').trim(),
                    rootInlineRegular: rootStyle.getPropertyValue('--scholium-rhythm-inline-regular').trim(),
                    rootInlineNarrow: rootStyle.getPropertyValue('--scholium-rhythm-inline-narrow').trim(),
                    pageColor: documentStyle?.color || '',
                    pageBackgroundColor: style('body')?.backgroundColor || '',
                    documentFontFamily: style('body')?.fontFamily || '',
                    documentFontSize: style('body')?.fontSize || '',
                    documentLineHeight: style('body')?.lineHeight || '',
                    documentMaxWidth: documentStyle?.maxWidth || '',
                    documentPaddingTop: documentStyle?.paddingTop || '',
                    documentPaddingInlineStart: documentStyle?.paddingInlineStart || '',
                    documentWidth: width('.scholium-document'),
                    headingFontFamily: headingStyle?.fontFamily || '',
                    headingFontSize: headingStyle?.fontSize || '',
                    headingFontWeight: headingStyle?.fontWeight || '',
                    headingLineHeight: headingStyle?.lineHeight || '',
                    headingBlockBefore: px(headingStyle?.marginTop) + px(headingStyle?.paddingTop),
                    headingBlockAfter: px(headingStyle?.marginBottom) + px(headingStyle?.paddingBottom),
                    headingWidth: width('.scholium-document > h2'),
                    calloutAccent: calloutStyle?.getPropertyValue('--callout-accent').trim() || '',
                    calloutBorderColor: calloutStyle?.borderInlineStartColor || '',
                    calloutFontSize: calloutStyle?.fontSize || '',
                    calloutLineHeight: calloutStyle?.lineHeight || '',
                    calloutWidth: width('.scholium-document > .scholium-callout-state'),
                    calloutRoleFontFamily: calloutRoleStyle?.fontFamily || '',
                    calloutRoleFontSize: calloutRoleStyle?.fontSize || '',
                    calloutRoleFontWeight: calloutRoleStyle?.fontWeight || '',
                    calloutRoleLineHeight: calloutRoleStyle?.lineHeight || '',
                    calloutRoleLetterSpacing: calloutRoleStyle?.letterSpacing || '',
                    calloutTitleFontFamily: calloutTitleStyle?.fontFamily || '',
                    calloutTitleFontSize: calloutTitleStyle?.fontSize || '',
                    calloutTitleFontWeight: calloutTitleStyle?.fontWeight || '',
                    calloutTitleLineHeight: calloutTitleStyle?.lineHeight || '',
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
                let nextCSS = scenario.configuration.css
                if sourceBox.userCSS != nextCSS {
                    sourceBox.isReady = false
                    sourceBox.userCSS = nextCSS
                    try await waitUntilReady()
                }

                let clock = ContinuousClock()
                let deadline = clock.now.advanced(by: .seconds(5))
                while true {
                    let snapshot = try await presentationSnapshot()
                    if snapshot.rootTextScale == scenario.expectedTextScale,
                       snapshot.rootReadableMeasure == scenario.expectedReadableMeasure,
                       snapshot.documentWidth > 0 {
                        try await Task.sleep(for: .milliseconds(100))
                        let stableSnapshot = try await presentationSnapshot()
                        guard stableSnapshot.rootTextScale == scenario.expectedTextScale,
                              stableSnapshot.rootReadableMeasure == scenario.expectedReadableMeasure,
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
            SafeMarkdownReadWebView(
                documentID: "ReadFixture.md",
                fingerprint: fingerprint,
                source: source,
                htmlBody: htmlBody,
                userCSS: sourceBox.userCSS,
                researcherComments: [],
                onLinkClick: { _ in },
                onOpenExternalURL: { _ in },
                onCommentSelection: nil,
                onCommentActivation: nil,
                onRenderingFailure: { sourceBox.failure = $0 },
                onRenderingReady: { sourceBox.isReady = true },
                initialScrollFraction: sourceBox.restoration.fraction,
                initialScrollAnchor: sourceBox.restoration.anchor,
                onScrollFractionChange: { _ in },
                onScrollAnchorChange: { sourceBox.capturedAnchor = $0 }
            )
        }
    }
}
