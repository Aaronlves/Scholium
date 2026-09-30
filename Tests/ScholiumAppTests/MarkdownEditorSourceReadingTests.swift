import Foundation
import Testing

@testable import ScholiumApp

@Suite("Editor source and reading projection", .serialized)
@MainActor
struct MarkdownEditorSourceReadingTests {
    @Test(
        "Focus and mode changes preserve exact source independently of DOM reading text",
        arguments: [
            "# Boundary\n\n中文 cafe\u{301} 👩🏽‍🔬\n",
            "\u{FEFF}# Boundary\r\n\r\n中文 cafe\u{301} 👩🏽‍🔬",
        ])
    func readingProjectionDoesNotReplaceSource(source: String) async throws {
        let harness = MarkdownEditorWebViewIntegrationTests.EditorHarness(
            source: source, initialMode: .source, laysOutForPointerTesting: true
        )
        defer { harness.close() }
        try await harness.waitUntilReady()
        let readingText = try #require(
            try await harness.callPageJavaScript("return document.querySelector('.cm-content')?.innerText;") as? String
        )
        #expect(readingText.contains("Boundary"))
        #expect(Data(try await harness.session.currentText(for: harness.documentID).utf8) == Data(source.utf8))
        #expect(!harness.session.isDirty)

        try await harness.session.focusAndWait()
        harness.session.setMode(.livePreview)
        _ = try await harness.waitUntilPresentation(stage: "reading projection in Edit") {
            $0.label == "Markdown editor, Edit mode"
        }
        harness.session.setMode(.source)
        _ = try await harness.waitUntilPresentation(stage: "exact Source return") {
            $0.label == "Markdown source editor"
        }
        #expect(Data(try await harness.session.currentText(for: harness.documentID).utf8) == Data(source.utf8))
        #expect(!harness.session.isDirty)
        await harness.closeAndDrain()
    }
}
