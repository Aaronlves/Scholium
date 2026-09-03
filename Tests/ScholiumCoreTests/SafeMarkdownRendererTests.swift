import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Safe Markdown Read renderer")
struct SafeMarkdownRendererTests {
    @Test("A matching workspace semantic projection produces identical safe HTML")
    func matchingSemanticProjectionIsReusable() {
        let document = NoteDocument(
            relativePath: "reused.md",
            rawContent: "# Exact\n\nA [[Target]] with *emphasis* and $x$.\n"
        )
        let semantic = MarkdownSemanticDocument(parsing: document)

        let ordinary = SafeMarkdownRenderer.render(document)
        let reused = SafeMarkdownRenderer.render(document, semantic: semantic)

        #expect(reused == ordinary)
        #expect(reused.semanticDocument.fingerprint == document.fingerprint)
    }

    @Test("A stale semantic projection cannot render newer source")
    func staleSemanticProjectionFailsClosed() {
        let original = NoteDocument(relativePath: "note.md", rawContent: "Original.\n")
        let current = NoteDocument(relativePath: "note.md", rawContent: "Current **claim**.\n")
        let stale = MarkdownSemanticDocument(parsing: original)

        let rendered = SafeMarkdownRenderer.render(current, semantic: stale)

        #expect(rendered == SafeMarkdownRenderer.render(current))
        #expect(rendered.semanticDocument.fingerprint == current.fingerprint)
    }

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

    @Test("Mermaid remains escaped source-located fenced code before projection")
    func mermaidIsAnInertSourceProjectionInput() {
        let source = """
        ```mermaid
        flowchart LR
        A[<script>attack()</script>] --> B
        ```
        """
        let rendered = SafeMarkdownRenderer.render(
            NoteDocument(relativePath: "diagram.md", rawContent: source)
        ).htmlBody

        #expect(rendered.contains("class=\"language-mermaid\""))
        #expect(rendered.contains("data-source-utf16-start="))
        #expect(rendered.contains("&lt;script&gt;attack()&lt;/script&gt;"))
        #expect(!rendered.contains("<script>attack()</script>"))
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

    @Test("Semantic text owns automatic direction while technical source stays isolated")
    func semanticWritingDirection() {
        let source = """
        # عنوان عربي

        هذه فقرة عربية مع Scholium والعدد 2026.

        > اقتباس عربي.

        - عنصر عربي.

        | حقل | قيمة |
        |:---|---:|
        | عربي | 2 |

        `exact_code()`

        <section dir="rtl">يبقى HTML الخام نصًا حرفيًا.</section>
        """
        let rendered = SafeMarkdownRenderer.render(
            NoteDocument(relativePath: "direction.md", rawContent: source)
        ).htmlBody

        #expect(rendered.contains("<h1 dir=\"auto\""))
        #expect(rendered.contains("<p dir=\"auto\""))
        #expect(rendered.contains("<blockquote dir=\"auto\""))
        #expect(rendered.contains("<li dir=\"auto\""))
        #expect(rendered.contains("<th dir=\"auto\""))
        #expect(rendered.contains("<td dir=\"auto\""))
        #expect(rendered.contains("<code dir=\"ltr\">exact_code()</code>"))
        #expect(rendered.contains("class=\"raw-html\" dir=\"ltr\""))
        #expect(rendered.contains("&lt;section dir=&quot;rtl&quot;&gt;"))
        #expect(!rendered.contains("<section dir=\"rtl\">"))
    }

    @Test("Task list items retain their read-only checkbox state in Review")
    func taskListCheckboxes() {
        let source = "- [ ] Open task.\n- [x] Completed task.\n* [x] Alternate task."
        let rendered = SafeMarkdownRenderer.render(
            NoteDocument(relativePath: "tasks.md", rawContent: source)
        ).htmlBody

        #expect(
            rendered.components(separatedBy: "class=\"scholium-task-list-item\"")
                .count - 1 == 3
        )
        #expect(
            rendered.components(separatedBy: "class=\"scholium-task-checkbox\"")
                .count - 1 == 3
        )
        #expect(rendered.contains("aria-label=\"Incomplete task\""))
        #expect(rendered.contains("aria-label=\"Completed task\""))
        #expect(rendered.contains("checked=\"\""))
        #expect(!rendered.contains("[ ]"))
        #expect(!rendered.contains("[x]"))
    }

    @Test("Obsidian embeds remain navigable links without transclusion")
    func obsidianEmbedLink() {
        let source = "![[Notes/Claim#Ground|Claim ground]]"
        let rendered = SafeMarkdownRenderer.render(
            NoteDocument(relativePath: "embed.md", rawContent: source)
        ).htmlBody

        #expect(rendered.contains("class=\"wiki-link scholium-embed\""))
        #expect(rendered.contains("href=\"scholium-note:Notes/Claim%23Ground\""))
        #expect(rendered.contains("data-scholium-protected=\"embed\""))
        #expect(rendered.contains(">Claim ground</a>"))
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
        #expect(rendered.contains("class=\"scholium-callout-title\" dir=\"auto\"><em>Fittingness</em></span>"))
        #expect(rendered.contains("class=\"scholium-callout-signature\" aria-hidden=\"true\""))
        #expect(rendered.contains("without endorsing it"))
        #expect(rendered.contains("<strong>correct</strong>"))
        #expect(!rendered.contains("scholium-callout-fold-mark"))
        #expect(!rendered.contains("[!state]"))
    }

    @Test("Links inside callouts retain document-level source locations")
    func calloutLinkSourceLocations() {
        let source = """
        Prelude.

        > [!connect] Curated connections
        > - [[Target]]
        > - [[Support]]{{Why this source links to Support.}}
        """
        let document = NoteDocument(relativePath: "callout-links.md", rawContent: source)
        let result = SafeMarkdownRenderer.render(document)

        #expect(result.semanticDocument.links.count == 2)
        for link in result.semanticDocument.links {
            #expect(result.htmlBody.contains(
                "data-source-utf16-start=\"\(link.linkSpan.utf16LowerBound)\" "
                    + "data-source-utf16-end=\"\(link.linkSpan.utf16UpperBound)\""
            ))
        }
        #expect(result.htmlBody.contains("href=\"scholium-note:Target\""))
        #expect(result.htmlBody.contains("href=\"scholium-note:Support\""))
        #expect(result.htmlBody.contains("class=\"scholium-link-annotation-button\""))
        #expect(result.htmlBody.contains("Why this source links to Support."))
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
        #expect(rendered.contains("<blockquote class=\"scholium-callout-quotation\" dir=\"auto\">"))
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
        #expect(rendered.contains("class=\"scholium-callout-title\" dir=\"auto\">Reading route</span>"))
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
        #expect(rendered.contains("id=\"fnref-2-1\""))
        #expect(rendered.contains("id=\"fn-2\""))
        #expect(rendered.contains("class=\"footnote-reference-cluster\""))
        #expect(rendered.contains("</sup>,</span> repeated"))
        #expect(rendered.contains("</sup>.</span>"))
        #expect(rendered.contains("Inline note"))
        #expect(rendered.contains("class=\"footnote-return\""))
        #expect(rendered.contains("<strong>footnote</strong>"))
        #expect(!rendered.contains("[^a]:"))
        #expect(!rendered.contains("^[Inline note]"))
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

        #expect(rendered.contains("<div class=\"footnote-content\"><p dir=\"auto\">First paragraph.</p>"))
        #expect(rendered.contains("<ul><li dir=\"auto\"><p dir=\"auto\">Outer item</p>"))
        #expect(rendered.contains("<ul><li dir=\"auto\"><p dir=\"auto\">Nested item</p>"))
        #expect(rendered.contains("<blockquote dir=\"auto\"><p dir=\"auto\">Quoted reason.</p>"))
        #expect(rendered.contains("class=\"scholium-callout scholium-callout-state\""))
        #expect(rendered.contains("<table class=\"scholium-table\""))
        #expect(rendered.contains("class=\"scholium-math scholium-math-inline\""))
        #expect(rendered.contains("class=\"scholium-math scholium-math-display\""))
        #expect(rendered.contains("<pre dir=\"ltr\"><code dir=\"ltr\" class=\"language-swift\">let value = 1"))
        #expect(rendered.contains(">Following paragraph.</p>"))
        #expect(!rendered.contains("<div class=\"footnote-content\"><p dir=\"auto\">Following paragraph."))
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
        #expect(rendered.htmlBody.contains("<code class=\"scholium-math-source\" dir=\"ltr\">$x^2 + y^2$</code>"))
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
        #expect(rendered.contains("<th dir=\"auto\" scope=\"col\" class=\"scholium-table-align-left\">Claim</th>"))
        #expect(rendered.contains("<th dir=\"auto\" scope=\"col\" class=\"scholium-table-align-center\">Status</th>"))
        #expect(rendered.contains("<th dir=\"auto\" scope=\"col\" class=\"scholium-table-align-right\">Count</th>"))
        #expect(rendered.contains("<tbody><tr>"))
        #expect(rendered.contains("<td dir=\"auto\" class=\"scholium-table-align-right\">2</td>"))
        #expect(!rendered.contains("<thead><td>"))
    }

    @Test("Wikilinks render as ordinary navigation without invented relation metadata")
    func wikilinks() {
        let rendered = SafeMarkdownRenderer.render(
            NoteDocument(
                relativePath: "links.md",
                rawContent: "See [[Paper#Claim|Source]]."
            )
        ).htmlBody

        #expect(rendered.contains("href=\"scholium-note:Paper%23Claim\""))
        #expect(rendered.contains(">Source</a>"))
    }

    @Test("Annotated Wikilinks expose one protected Markdown disclosure")
    func annotatedLinks() {
        let rendered = SafeMarkdownRenderer.render(
            NoteDocument(
                relativePath: "links.md",
                rawContent: "[[B]]{{First **reason**.\n\n- Second reason.}} [[C]]"
            )
        ).htmlBody

        #expect(rendered.contains("class=\"scholium-annotated-link\""))
        #expect(rendered.contains("<sup class=\"scholium-link-annotation-marker\">"))
        #expect(rendered.contains("class=\"scholium-link-annotation-button\""))
        #expect(rendered.contains("aria-controls=\"scholium-preview-popover\""))
        #expect(rendered.contains("<template id="))
        #expect(rendered.contains("<strong>reason</strong>"))
        #expect(rendered.contains("Second reason."))
        #expect(!rendered.contains("{{"))
        #expect(!rendered.contains("scholium-link-annotation-panel"))
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
