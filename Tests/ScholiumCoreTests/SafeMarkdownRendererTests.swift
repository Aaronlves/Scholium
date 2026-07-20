import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Safe Markdown Read renderer")
struct SafeMarkdownRendererTests {
    @Test("Obsidian highlights render outside literal regions only")
    func highlights() {
        let document = NoteDocument(
            relativePath: "highlight.md",
            rawContent: "A ==central claim== and `==literal==`.\n\n```\n==also literal==\n```"
        )
        let html = SafeMarkdownRenderer.render(document).htmlBody
        #expect(html.contains("<mark class=\"scholium-highlight\">central claim</mark>"))
        #expect(html.contains("==literal=="))
        #expect(html.contains("==also literal=="))
    }

    @Test("Raw HTML and remote media remain inert")
    func hostileHTMLIsInert() {
        let source = """
        <script>alert('research')</script>

        <img src="https://example.com/private.png" onerror="alert(1)">

        ![Remote](https://example.com/image.png)
        """
        let rendered = SafeMarkdownRenderer.render(
            NoteDocument(relativePath: "hostile.md", rawContent: source)
        ).htmlBody

        #expect(!rendered.contains("<script>"))
        #expect(!rendered.contains("<img"))
        #expect(!rendered.contains(" onerror=\""))
        #expect(rendered.contains("&lt;script&gt;"))
        #expect(rendered.contains("data-scholium-protected=\"embed\""))
    }

    @Test("Callouts render as protected semantic components")
    func callouts() {
        let source = """
        > [!state] *Fittingness*
        > A response is fitting when **correct**.
        """
        let rendered = SafeMarkdownRenderer.render(
            NoteDocument(relativePath: "callout.md", rawContent: source)
        ).htmlBody

        #expect(rendered.contains("scholium-callout-state"))
        #expect(rendered.contains("data-callout=\"state\""))
        #expect(rendered.contains("data-callout-fold=\"fixed\""))
        #expect(rendered.contains("data-callout-source=\"state\""))
        #expect(rendered.contains("data-scholium-protected=\"callout\""))
        #expect(rendered.contains("class=\"scholium-callout-heading\" role=\"heading\" aria-level=\"2\""))
        #expect(rendered.contains("class=\"scholium-callout-role\""))
        #expect(rendered.contains(">Statement</span>"))
        #expect(rendered.contains("class=\"scholium-callout-title\"><em>Fittingness</em></span>"))
        #expect(rendered.contains("class=\"scholium-callout-signature\" aria-hidden=\"true\""))
        #expect(rendered.contains("without endorsing it"))
        #expect(rendered.contains("<strong>correct</strong>"))
        #expect(!rendered.contains("scholium-callout-fold-mark"))
        #expect(!rendered.contains("[!state]"))
    }

    @Test("Callout fold markers select expanded or collapsed Read state")
    func calloutFolding() {
        let expanded = SafeMarkdownRenderer.render(
            NoteDocument(
                relativePath: "source.md",
                rawContent: "> [!cite]+\n> **2026-07-13** Paper entry [[Paper Analysis]]\n"
            )
        ).htmlBody
        let collapsed = SafeMarkdownRenderer.render(
            NoteDocument(
                relativePath: "source.md",
                rawContent: "> [!cite]-\n> **2026-07-13** Paper entry [[Paper Analysis]]\n"
            )
        ).htmlBody

        #expect(expanded.contains("<details"))
        #expect(expanded.contains("data-callout-fold=\"expanded\""))
        #expect(expanded.contains(" open>"))
        #expect(expanded.contains(">Source</span>"))
        #expect(expanded.contains("class=\"scholium-callout-fold-mark\" aria-hidden=\"true\""))
        #expect(expanded.contains("<strong>2026-07-13</strong>"))
        #expect(expanded.contains("Paper Analysis"))
        #expect(collapsed.contains("data-callout-fold=\"collapsed\""))
        #expect(collapsed.contains("class=\"scholium-callout-fold-mark\" aria-hidden=\"true\""))
        #expect(!collapsed.contains(" open>"))
    }

    @Test("Quotation callouts expose semantic quotation markup without forcing italics")
    func quotationSemantics() {
        let rendered = SafeMarkdownRenderer.render(
            NoteDocument(
                relativePath: "quotation.md",
                rawContent: "> [!quote]+ Exact wording\n> The wording itself does argumentative work.\n"
            )
        ).htmlBody

        #expect(rendered.contains("scholium-callout-quote"))
        #expect(rendered.contains("<blockquote class=\"scholium-callout-quotation\">"))
        #expect(rendered.contains("The wording itself does argumentative work."))
        #expect(rendered.contains("class=\"scholium-callout-signature\" aria-hidden=\"true\""))
    }

    @Test("Orientation preserves semantic metadata for its label-free visual treatment")
    func orientationPreservesMetadata() {
        let rendered = SafeMarkdownRenderer.render(
            NoteDocument(
                relativePath: "orientation.md",
                rawContent: "> [!orient] Reading route\n> Follow the distinctions first.\n"
            )
        ).htmlBody

        #expect(rendered.contains("scholium-callout-orient"))
        #expect(rendered.contains("data-callout=\"orient\""))
        #expect(rendered.contains("class=\"scholium-callout-role\""))
        #expect(rendered.contains(">Orientation</span>"))
        #expect(rendered.contains("class=\"scholium-callout-title\">Reading route</span>"))
        #expect(rendered.contains("data-scholium-protected=\"callout\""))
    }

    @Test("Legacy callout identifiers preserve source identity while using the new semantic role")
    func legacyCallout() {
        let rendered = SafeMarkdownRenderer.render(
            NoteDocument(relativePath: "legacy-callout.md", rawContent: "> [!torn]- Limit\n> Check the source.\n")
        ).htmlBody

        #expect(rendered.contains("scholium-callout-flag"))
        #expect(rendered.contains("data-callout=\"flag\""))
        #expect(rendered.contains("data-callout-source=\"torn\""))
        #expect(rendered.contains("<details"))
        #expect(!rendered.contains("<details open"))
    }

    @Test("Footnotes render previews, definitions, and origin-aware controls")
    func footnotes() {
        let source = "Claim[^a], repeated[^a], inline^[Inline note].\n\n[^a]: Rich **footnote**.\n"
        let rendered = SafeMarkdownRenderer.render(
            NoteDocument(relativePath: "footnote.md", rawContent: source)
        ).htmlBody

        #expect(rendered.contains("id=\"fnref-1-1\""))
        #expect(rendered.contains("id=\"fnref-1-2\""))
        #expect(rendered.contains("id=\"fn-1\""))
        #expect(rendered.contains("class=\"footnote-return\""))
        #expect(rendered.contains("<strong>footnote</strong>"))
        #expect(!rendered.contains("[^a]:"))
    }

    @Test("Footnote definitions render owned nested blocks without absorbing following prose")
    func nestedBlockFootnotes() {
        let source = """
        Claim[^blocks].

        [^blocks]: First paragraph.

          - Outer item
            - Nested item

          > Quoted reason.

          > [!state] Nested claim
          > Body with $z$.

          | Term | Value |
          |:---|---:|
          | $z$ | 3 |

          $$
          z^2
          $$

          ```swift
          let value = 1
          ```
        Following paragraph.
        """
        let rendered = SafeMarkdownRenderer.render(
            NoteDocument(relativePath: "nested-footnote.md", rawContent: source)
        ).htmlBody

        #expect(rendered.contains("<div class=\"footnote-content\"><p>First paragraph.</p>"))
        #expect(rendered.contains("<ul><li><p>Outer item</p>"))
        #expect(rendered.contains("<ul><li><p>Nested item</p>"))
        #expect(rendered.contains("<blockquote><p>Quoted reason.</p>"))
        #expect(rendered.contains("class=\"scholium-callout scholium-callout-state\""))
        #expect(rendered.contains("<table class=\"scholium-table\""))
        #expect(rendered.contains("class=\"scholium-math scholium-math-inline\""))
        #expect(rendered.contains("class=\"scholium-math scholium-math-display\""))
        #expect(rendered.contains("<pre><code class=\"language-swift\">let value = 1"))
        #expect(rendered.contains(">Following paragraph.</p>"))
        #expect(!rendered.contains("<div class=\"footnote-content\"><p>Following paragraph."))
    }

    @Test("Mathematics renders inert shared-runtime placeholders with exact source fallback")
    func mathematics() {
        let source = "Inline $x^2 + y^2$.\n\n$$\n\\int_0^1 x\\,dx\n$$\n\n`$literal$`"
        let rendered = SafeMarkdownRenderer.render(
            NoteDocument(relativePath: "mathematics.md", rawContent: source)
        )

        #expect(rendered.semanticDocument.mathExpressions.count == 2)
        #expect(rendered.htmlBody.contains("class=\"scholium-math scholium-math-inline\""))
        #expect(rendered.htmlBody.contains("class=\"scholium-math scholium-math-display\""))
        #expect(rendered.htmlBody.contains("data-math-kind=\"inline\""))
        #expect(rendered.htmlBody.contains("data-math-source=\""))
        #expect(rendered.htmlBody.contains("<code class=\"scholium-math-source\">$x^2 + y^2$</code>"))
        #expect(rendered.htmlBody.contains("$literal$"))
        #expect(!rendered.htmlBody.contains("<script"))
    }

    @Test("Tables expose column headers, alignment, and a bounded shared scroll container")
    func tableSemantics() {
        let source = """
        | Claim | Status | Count |
        |:---|:---:|---:|
        | Fittingness | Open | 2 |
        """
        let rendered = SafeMarkdownRenderer.render(
            NoteDocument(relativePath: "table.md", rawContent: source)
        ).htmlBody

        #expect(rendered.contains("class=\"scholium-table-scroll\""))
        #expect(rendered.contains("data-scholium-protected=\"table\""))
        #expect(rendered.contains("<table class=\"scholium-table\""))
        #expect(rendered.contains("<thead><tr>"))
        #expect(rendered.contains("<th scope=\"col\" class=\"scholium-table-align-left\">Claim</th>"))
        #expect(rendered.contains("<th scope=\"col\" class=\"scholium-table-align-center\">Status</th>"))
        #expect(rendered.contains("<th scope=\"col\" class=\"scholium-table-align-right\">Count</th>"))
        #expect(rendered.contains("<tbody><tr>"))
        #expect(rendered.contains("<td class=\"scholium-table-align-right\">2</td>"))
        #expect(!rendered.contains("<thead><td>"))
    }

    @Test("Legacy typed wikilinks render as inert neutral navigation")
    func wikilinks() {
        let rendered = SafeMarkdownRenderer.render(
            NoteDocument(
                relativePath: "links.md",
                rawContent: "See [[Paper#Claim|Source:supports]]."
            )
        ).htmlBody

        #expect(rendered.contains("href=\"scholium-note:Paper%23Claim\""))
        #expect(rendered.contains("data-vector-kind=\"neutral\""))
        #expect(!rendered.contains("data-relationship="))
        #expect(rendered.contains(">Source</a>"))
    }

    @Test("Vector links expose protected semantic rendering metadata")
    func vectorLinks() {
        let rendered = SafeMarkdownRenderer.render(
            NoteDocument(relativePath: "vectors.md", rawContent: "+[[B]] -[[C]] ?[[D]] [[E]]")
        ).htmlBody

        #expect(rendered.contains("class=\"wiki-link scholium-vector\""))
        #expect(rendered.contains("data-vector-kind=\"supports_target\""))
        #expect(rendered.contains("data-vector-kind=\"supported_by_target\""))
        #expect(rendered.contains("data-vector-kind=\"incompatible\""))
        #expect(rendered.contains("data-vector-kind=\"neutral\""))
        #expect(!rendered.contains("+[[B]]"))
    }

    @Test("Relative Markdown links use internal navigation while approved schemes remain external")
    func standardMarkdownLinks() {
        let rendered = SafeMarkdownRenderer.render(
            NoteDocument(
                relativePath: "links.md",
                rawContent: "[Topic](Topics/Topic%20Name.md#Main%20Claim) [Here](#Section) [Web](https://example.com)"
            )
        ).htmlBody

        #expect(rendered.contains("href=\"scholium-note:Topics/Topic%20Name.md%23Main%20Claim\""))
        #expect(rendered.contains("href=\"scholium-note:%23Section\""))
        #expect(rendered.contains("href=\"https://example.com\""))
    }

    @Test("Headings, callouts, and footnotes expose exact read-mode source anchors")
    func sourceAnchors() {
        let source = """
        ---
        title: Anchors
        ---
        # First heading

        > [!state] Claim
        > Body.

        Text[^one].

        [^one]: Note.
        """
        let document = NoteDocument(relativePath: "anchors.md", rawContent: source)
        let semantic = MarkdownSemanticDocument(parsing: document)
        let rendered = SafeMarkdownRenderer.render(document).htmlBody

        let heading = semantic.headings[0].span
        let callout = semantic.callouts[0].span
        let footnote = semantic.footnoteDefinitions[0].span
        #expect(rendered.contains("id=\"scholium-line-\(heading.start.line)\""))
        #expect(rendered.contains("data-source-utf16-start=\"\(heading.utf16LowerBound)\""))
        #expect(rendered.contains("data-source-utf16-end=\"\(heading.utf16UpperBound)\""))
        #expect(rendered.contains("data-source-utf16-start=\"\(callout.utf16LowerBound)\""))
        #expect(rendered.contains("data-source-utf16-end=\"\(callout.utf16UpperBound)\""))
        #expect(rendered.contains("data-source-utf16-start=\"\(footnote.utf16LowerBound)\""))
        #expect(rendered.contains("data-source-utf16-end=\"\(footnote.utf16UpperBound)\""))
    }

    @Test("Repeated visible text retains distinct exact source containers")
    func repeatedTextSourceContainers() {
        let document = NoteDocument(
            relativePath: "repeated.md",
            rawContent: "Repeated claim.\n\nRepeated claim.\n"
        )
        let paragraphs = MarkdownSemanticDocument(parsing: document).blocks.filter {
            $0.kind == .paragraph
        }
        let rendered = SafeMarkdownRenderer.render(document).htmlBody

        #expect(paragraphs.count == 2)
        #expect(paragraphs[0].span.utf16Range != paragraphs[1].span.utf16Range)
        for paragraph in paragraphs {
            #expect(rendered.contains(
                "data-source-utf16-start=\"\(paragraph.span.utf16LowerBound)\" data-source-utf16-end=\"\(paragraph.span.utf16UpperBound)\""
            ))
        }
    }
}
