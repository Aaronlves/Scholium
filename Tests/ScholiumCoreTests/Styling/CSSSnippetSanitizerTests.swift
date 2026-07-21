import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Protected CSS snippets")
struct CSSSnippetSanitizerTests {
    @Test("Supported document selectors are scoped and projected")
    func scopesSelectors() throws {
        let result = try CSSSnippetSanitizer.sanitize("""
        h1, h2 { color: #7257d9; font-family: Alegreya; }
        body { font-size: 1em; }
        p { line-height: 1.7; }
        code { font-family: 'Victor Mono'; background-color: #eee; }
        """)

        #expect(result.readCSS.contains(".scholium-document h1"))
        #expect(result.readCSS.contains(".scholium-document p"))
        #expect(result.livePreviewCSS.contains(".cm-live-h1"))
        #expect(result.livePreviewCSS.contains(".cm-live-paragraph"))
        #expect(!result.livePreviewCSS.contains(".scholium-live-mode .cm-line"))
        #expect(result.livePreviewCSS.contains(".cm-live-code"))
        #expect(result.livePreviewCSS.contains(".cm-editor.scholium-live-mode .cm-content"))
    }

    @Test("Network, cascade escape, and HTML injection are rejected", arguments: [
        "p { background: url(https://example.com/x); }",
        "p { color: red !important; }",
        "@import 'other.css';",
        "p { color: red; } </style><script>alert(1)</script>"
    ])
    func rejectsUnsafeCSS(source: String) {
        #expect(throws: CSSSnippetSanitizationError.self) {
            try CSSSnippetSanitizer.sanitize(source)
        }
    }

    @Test("Research signals cannot be restyled", arguments: [
        ".scholium-callout { color: transparent; }",
        ".footnote-reference { display: none; }",
        "[data-scholium-protected] { opacity: 0; }",
        ".review-annotation { color: white; }",
        ".provenance-warning { color: green; }",
        ".scholium-vector { opacity: 0; }",
        ".cm-live-vector { color: transparent; }"
    ])
    func protectsResearchSignals(source: String) {
        #expect(throws: CSSSnippetSanitizationError.self) {
            try CSSSnippetSanitizer.sanitize(source)
        }
    }

    @Test("Layout and executable properties are not part of the contract", arguments: [
        "p { position: fixed; }",
        "p { display: none; }",
        "p { content: 'replacement'; }"
    ])
    func rejectsUnsupportedProperties(source: String) {
        #expect(throws: CSSSnippetSanitizationError.self) {
            try CSSSnippetSanitizer.sanitize(source)
        }
    }

    @Test("Broad selectors cannot hide protected descendants through opacity", arguments: [
        "a { opacity: 0; }",
        ".scholium-document { opacity: 0; }",
        "p { opacity: 0.5; }"
    ])
    func rejectsOpacity(source: String) {
        #expect(throws: CSSSnippetSanitizationError.self) {
            try CSSSnippetSanitizer.sanitize(source)
        }
    }

    @Test("Zero font sizes cannot hide document links", arguments: [
        "a { font-size: 0; }",
        ".scholium-document { font-size: 0px; }",
        "p { font-size: .0rem; }"
    ])
    func rejectsZeroFontSize(source: String) {
        #expect(throws: CSSSnippetSanitizationError.self) {
            try CSSSnippetSanitizer.sanitize(source)
        }
    }

    @Test("Nonzero typography remains available to ordinary content")
    func preservesDocumentTypography() throws {
        let result = try CSSSnippetSanitizer.sanitize("p { font-size: 1.1em; color: #444; }")

        #expect(result.readCSS.contains("font-size: 1.1em"))
        #expect(result.readCSS.contains("color: #444"))
    }
}
