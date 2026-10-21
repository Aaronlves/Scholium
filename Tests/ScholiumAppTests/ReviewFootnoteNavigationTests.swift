import Foundation
import ScholiumContracts
import Testing
import WebKit

@testable import ScholiumApp

extension MarkdownEditorWebViewIntegrationTests {
    @Test("Review reveals the beginning of a long footnote above the toolbar and returns to its reference")
    func reviewLongFootnoteStartsAtReadableTop() async throws {
        let source =
            "Reference[^long].\n\n"
            + (0..<24).map { "Body paragraph \($0).\n\n" }.joined()
            + "[^long]: Footnote beginning.\n"
            + (0..<64).map { "\n    Footnote paragraph \($0).\n" }.joined()
        let document = NoteDocument(relativePath: "LongFootnote.md", rawContent: source)
        let css = ":root { --scholium-document-toolbar-inset: 48px; --scholium-document-content-top-inset: 20px; }"
        let harness = EditorHarness(source: source, initialMode: .review, initialPresentationCSS: css)
        defer { harness.close() }
        harness.configureReview(
            SafeMarkdownReadWebView(
                documentID: harness.documentID, document: document,
                htmlBody: SafeMarkdownRenderer.render(document).htmlBody,
                presentationCSS: css, userCSS: "",
                configurationRevision: document.fingerprint.sha256,
                onLinkClick: { _ in }, onOpenExternalURL: { _ in },
                onRenderingFailure: { Issue.record(Comment(rawValue: $0)) }))
        try await harness.waitUntilReady()
        try await harness.waitUntilPresentedMode(.review)
        let webView = try #require(harness.session.webView)
        let navigation = try #require(
            try await harness.callPageJavaScript(
                """
                const match = window.matchMedia.bind(window);
                window.matchMedia = query => query.includes('prefers-reduced-motion') ? {matches: true} : match(query);
                const reference = document.querySelector('.footnote-reference');
                const definition = document.getElementById(reference.dataset.target);
                const scrollDOM = document.querySelector('.cm-scroller');
                reference.click();
                await new Promise(resolve => {
                    setTimeout(resolve, 200);
                    requestAnimationFrame(() => requestAnimationFrame(resolve));
                });
                const bounds = definition.getBoundingClientRect();
                const viewport = scrollDOM.getBoundingClientRect();
                const result = {top: bounds.top - viewport.top, height: bounds.height,
                    viewportHeight: scrollDOM.clientHeight,
                    focused: document.activeElement === definition};
                definition.querySelector('.footnote-return').click();
                result.returned = document.activeElement === reference;
                return result;
                """) as? [String: Any])
        let top = try #require(navigation["top"] as? Double)
        let height = try #require(navigation["height"] as? Double)
        let viewport = try #require(navigation["viewportHeight"] as? Double)
        #expect(height > viewport * 2, "The fixture must exercise a definition taller than the reading viewport.")
        #expect(abs(top - 68) <= 2, "The beginning must remain below the 48px toolbar and 20px content inset; actual \(top).")
        #expect(navigation["focused"] as? Bool == true)
        #expect(navigation["returned"] as? Bool == true)
        #expect(harness.session.webView === webView)
        #expect(!harness.session.isDirty)
        #expect(Data(try await harness.session.currentText().utf8) == Data(source.utf8))
        await harness.closeAndDrain()
    }
}
