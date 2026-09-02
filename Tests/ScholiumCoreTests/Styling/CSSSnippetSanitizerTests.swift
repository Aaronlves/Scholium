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

    @Test("Declared document class selectors are accepted and scoped")
    func acceptsDocumentClassSelectors() throws {
        let result = try CSSSnippetSanitizer.sanitize("""
        .scholium-document { max-width: 46ch; }
        .scholium-document h2 { color: #7a3b2e; }
        .scholium-highlight { background-color: #f6ecd8; }
        """)

        #expect(result.readCSS.contains(".scholium-document {"))
        #expect(result.readCSS.contains(".scholium-document h2 {"))
        #expect(result.readCSS.contains(".scholium-highlight {"))
        #expect(result.livePreviewCSS.contains(".cm-editor.scholium-live-mode .cm-content"))
        #expect(result.livePreviewCSS.contains(".scholium-live-mode .cm-live-h2"))
        #expect(!result.livePreviewCSS.contains(".scholium-document h2"))
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
        ".scholium-link-annotation-content { opacity: 0; }",
        ".scholium-link-annotation-button { color: transparent; }"
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

    @Test("Snippet names normalize to inert display labels")
    func normalizesSnippetNames() {
        #expect(
            CSSSnippetSanitizer.normalizedSnippetName(
                "</style><script id=\"scholium-proof\">0</script><style>",
                fallback: "Fallback"
            )
                == "/stylescript id=\"scholium-proof\"0/scriptstyle"
        )
        #expect(
            CSSSnippetSanitizer.normalizedSnippetName(
                "</STYLE><SCRIPT id=\"scholium-proof\">0</SCRIPT><STYLE>",
                fallback: "Fallback"
            )
                == "/STYLESCRIPT id=\"scholium-proof\"0/SCRIPTSTYLE"
        )
        #expect(
            CSSSnippetSanitizer.normalizedSnippetName("  My Notes  ", fallback: "Fallback")
                == "My Notes"
        )
        #expect(
            CSSSnippetSanitizer.normalizedSnippetName("plain-name", fallback: "Fallback")
                == "plain-name"
        )
        #expect(
            CSSSnippetSanitizer.normalizedSnippetName("", fallback: "Fallback") == "Fallback"
        )
        #expect(
            CSSSnippetSanitizer.normalizedSnippetName("   \n\t ", fallback: "Fallback")
                == "Fallback"
        )
        #expect(
            CSSSnippetSanitizer.normalizedSnippetName("a\u{0000}b", fallback: "Fallback") == "ab"
        )
        #expect(
            CSSSnippetSanitizer.normalizedSnippetName(
                "line\u{2028}separator",
                fallback: "Fallback"
            ) == "lineseparator"
        )
        #expect(
            CSSSnippetSanitizer.normalizedSnippetName(
                String(repeating: "x", count: 200),
                fallback: "Fallback"
            ).count
                == CSSSnippetSanitizer.maximumSnippetNameLength
        )
        // Invisible format characters such as ZWSP are removed with control
        // characters so a label cannot hide text or spoof another name.
        #expect(
            CSSSnippetSanitizer.normalizedSnippetName("a\u{200B}b", fallback: "Fallback")
                == "ab"
        )
    }
}
