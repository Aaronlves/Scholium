import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Shared Markdown semantic document")
struct MarkdownSemanticDocumentTests {
    @Test("Concurrent semantic parses retain independent Unicode matches and source revisions")
    func concurrentSemanticSourceIsolation() async {
        let documents = (0..<24).map { number in
            let newline = number.isMultiple(of: 2) ? "\n" : "\r\n"
            let source = [
                "# Note \(number)", "", "> [!note] Context \(number)", "> Quoted wording.", "",
                "==highlight-\(number)== [[Target-\(number)|Café 😀 依据]]{{annotation \(number)}} [^n\(number)].", "",
                "[^n\(number)]: Definition \(number).", "", "`[[literal-\(number)]]`",
            ].joined(separator: newline)
            return NoteDocument(relativePath: "Concurrent-\(number).md", rawContent: source)
        }
        let expected = documents.map { MarkdownSemanticDocument(parsing: $0) }
        await withTaskGroup(of: (Int, MarkdownSemanticDocument).self) { group in
            for iteration in 0..<192 {
                let index = iteration % documents.count
                group.addTask { (index, MarkdownSemanticDocument(parsing: documents[index])) }
            }
            for await (index, actual) in group {
                #expect(actual == expected[index])
                #expect(actual.fingerprint == documents[index].fingerprint)
                #expect(actual.links.count == 1)
                #expect(actual.links.first?.target == "Target-\(index)")
            }
        }
    }

    @Test("Adjacent link annotations own exact multiline Markdown and distinct source spans")
    func annotatedLinkSourceOwnership() throws {
        let source = """
            # Claim

            [[Inference A#Step|the inference]]{{First **reason**.

            - escaped \\}} text
            - second reason}}
            """
        let semantic = MarkdownSemanticDocument(parsing: NoteDocument(relativePath: "claim.md", rawContent: source))
        let occurrence = try #require(semantic.links.first)
        let annotation = try #require(occurrence.annotation)

        #expect(semantic.links.count == 1)
        #expect(occurrence.target == "Inference A")
        #expect(occurrence.fragment == "Step")
        #expect(occurrence.alias == "the inference")
        #expect(annotation.markdown.contains("First **reason**."))
        #expect(annotation.markdown.contains("\\}} text"))
        #expect(annotation.text.contains("First reason."))
        #expect(
            (source as NSString).substring(with: occurrence.linkSpan.nsRange)
                == "[[Inference A#Step|the inference]]")
        #expect(
            (source as NSString).substring(with: occurrence.span.nsRange)
                == "[[Inference A#Step|the inference]]{{\(annotation.markdown)}}")
        #expect(
            (source as NSString).substring(with: annotation.contentSpan.nsRange)
                == annotation.markdown)
        #expect(semantic.diagnostics.isEmpty)
    }

    @Test("Malformed annotation markup preserves the ordinary Wikilink and reports its source")
    func malformedLinkAnnotations() {
        for source in [
            "[[Empty]]{{ }}",
            "[[Empty Code]]{{` `}}",
            "[[Rule Only]]{{---}}",
            "[[Nested]]{{outer {{inner}} tail}}",
            "[[Unclosed]]{{reason",
        ] {
            let semantic = MarkdownSemanticDocument(
                parsing: NoteDocument(
                    relativePath: "Malformed.md",
                    rawContent: source
                ))
            #expect(semantic.links.count == 1)
            #expect(semantic.links[0].annotation == nil)
            #expect(
                (source as NSString).substring(with: semantic.links[0].span.nsRange)
                    == (source as NSString).substring(with: semantic.links[0].linkSpan.nsRange))
            #expect(semantic.diagnostics.contains { $0.code == .malformedLinkAnnotation })
        }
    }

    @Test("Detached and escaped annotation openers remain ordinary source")
    func nonAnnotationOpeners() {
        for source in ["[[Detached]] {{reason}}", "[[Escaped]]\\{{reason}}"] {
            let semantic = MarkdownSemanticDocument(
                parsing: NoteDocument(
                    relativePath: "Ordinary.md",
                    rawContent: source
                ))
            #expect(semantic.links.first?.annotation == nil)
            #expect(semantic.diagnostics.isEmpty)
        }
    }

    @Test("Annotated links parse everywhere ordinary Wikilinks are valid")
    func annotatedLinks() {
        let source = """
            ---
            title: Annotation Fixture
            hidden: "[[YAML Literal]]{{Hidden}}"
            ---
            A [[First]]{{A reason.}} and [[Second]]{{Another **reason**.}}.
            ![[Embedded]]
            `[[Inline Code]]{{Hidden}}`
            ``[[Long Inline Code]]{{Hidden}}``
            ```md
            [[Fenced Code]]{{Hidden}}
            ```
            %% [[Commented]]{{Hidden}} %%
            <!-- [[HTML Commented]]{{Hidden}} -->
            """
        let semantic = MarkdownSemanticDocument(parsing: NoteDocument(relativePath: "Annotations.md", rawContent: source))
        let byTarget = Dictionary(uniqueKeysWithValues: semantic.links.map { ($0.target, $0) })

        #expect(byTarget["First"]?.annotation?.markdown == "A reason.")
        #expect(byTarget["Second"]?.annotation?.text == "Another reason.")
        #expect(byTarget["Embedded"]?.syntax == .embed)
        #expect(byTarget["Embedded"]?.annotation == nil)
        #expect(byTarget["Inline Code"] == nil)
        #expect(byTarget["Long Inline Code"] == nil)
        #expect(byTarget["Fenced Code"] == nil)
        #expect(byTarget["Commented"] == nil)
        #expect(byTarget["HTML Commented"] == nil)
        #expect(byTarget["YAML Literal"] == nil)
    }

    @Test("Unclosed comments fail closed and diagnose their exact opener")
    func unclosedComments() throws {
        for fixture in [
            (source: "Visible.\n%%\n[[Hidden]]{{Hidden annotation.}} $x$ [^hidden]", opener: "%%"),
            (source: "Visible.\n<!--\n[[Hidden]]{{Hidden annotation.}} $x$ [^hidden]", opener: "<!--"),
        ] {
            let semantic = MarkdownSemanticDocument(
                parsing: NoteDocument(
                    relativePath: "comment.md",
                    rawContent: fixture.source
                ))
            #expect(semantic.links.isEmpty)
            #expect(semantic.mathExpressions.isEmpty)
            #expect(semantic.footnoteReferences.isEmpty)
            let diagnostic = try #require(
                semantic.diagnostics.first {
                    $0.code == .malformedComment
                })
            let span = try #require(diagnostic.span)
            #expect((fixture.source as NSString).substring(with: span.nsRange) == fixture.opener)
        }
    }

    @Test("Incomplete inline extension markers remain exact ordinary source")
    func incompleteInlineExtensionMarkers() {
        let source = """
            [^unclosed
            [^]: empty identifier
            ^[unclosed
            ^[]
            [[unclosed
            ==unclosed
            $unclosed
            > [!unclosed
            """
        let semantic = MarkdownSemanticDocument(
            parsing: NoteDocument(
                relativePath: "Incomplete.md",
                rawContent: source
            ))

        #expect(semantic.callouts.isEmpty)
        #expect(semantic.links.isEmpty)
        #expect(semantic.footnoteDefinitions.isEmpty)
        #expect(semantic.footnoteReferences.isEmpty)
        #expect(semantic.mathExpressions.isEmpty)
        #expect(semantic.diagnostics.isEmpty)
    }

    @Test("Literal unions preserve real syntax touching code and overlapping comment boundaries")
    func touchingLiteralBoundaries() throws {
        let source =
            "\u{FEFF}---\r\ntitle: Literal boundaries\r\n---\r\n\r\n"
            + "`[[CodeHidden]] ==CodeHidden== $codeHidden$`[[AfterCode]]==afterCode==$afterCode$\r\n\r\n"
            + "[[BeforeCode]]==beforeCode==$beforeCode$`literal`\r\n\r\n"
            + "%% `[[CommentHidden]] ==CommentHidden== $commentHidden$` %%[[AfterComment]]==afterComment==$afterComment$\r\n\r\n"
            + "Text <!-- `[[HtmlHidden]] ==HtmlHidden== $htmlHidden$` -->[[AfterHTML]]==afterHTML==$afterHTML$\r\n\r\n"
            + "$$\r\n$insideDisplay$\r\n$$\r\n\r\n$afterDisplay$\r\n"
        let document = NoteDocument(relativePath: "literal-boundaries.md", rawContent: source)
        let semantic = MarkdownSemanticDocument(parsing: document)
        #expect(semantic.links.map(\.target) == ["AfterCode", "BeforeCode", "AfterComment", "AfterHTML"])
        let highlights = semantic.inlines.filter { $0.kind == .highlight }
        #expect(
            highlights.map { (source as NSString).substring(with: $0.span.nsRange) } == [
                "==afterCode==", "==beforeCode==", "==afterComment==", "==afterHTML==",
            ])
        #expect(semantic.mathExpressions.map(\.kind) == [.inline, .inline, .inline, .inline, .display, .inline])
        #expect(
            semantic.mathExpressions.map(\.content) == [
                "afterCode", "beforeCode", "afterComment", "afterHTML", "$insideDisplay$", "afterDisplay",
            ])
        for link in semantic.links {
            #expect((source as NSString).substring(with: link.span.nsRange) == "[[" + link.target + "]]")
        }
        for span in semantic.links.map(\.span) + highlights.map(\.span) + semantic.mathExpressions.map(\.span) {
            let exact = (source as NSString).substring(with: span.nsRange)
            #expect(Data(source.utf8)[span.utf8Range] == Data(exact.utf8))
        }
        #expect(document.sourceBytes == Data(source.utf8))
    }

    @Test("Mismatched backtick runs do not suppress valid annotated links")
    func mismatchedBackticks() {
        let source = "` unmatched [[Visible]]{{Reason}} ``\nText ``` [[Hidden]]{{Hidden}} ```"
        let semantic = MarkdownSemanticDocument(parsing: NoteDocument(relativePath: "ticks.md", rawContent: source))
        #expect(semantic.links.contains { $0.target == "Visible" && $0.annotation != nil })
        #expect(!semantic.links.contains { $0.target == "Hidden" })
    }
    @Test("Source spans remain exact across BOM, CRLF, and Unicode")
    func sourceSpans() throws {
        let source = "\u{FEFF}---\r\ntitle: 范围\r\n---\r\n\r\n# 哲学 🧭\r\n\r\nBody."
        let document = NoteDocument(relativePath: "unicode.md", rawContent: source)
        let semantic = MarkdownSemanticDocument(parsing: document)
        let heading = try #require(semantic.headings.first)

        #expect(heading.text == "哲学 🧭")
        #expect(heading.span.start.line == 5)
        #expect((source as NSString).substring(with: heading.span.nsRange) == "# 哲学 🧭")
        #expect(Data(source.utf8)[heading.span.utf8Range] == Data("# 哲学 🧭".utf8))
    }

    @Test("Unrecorded containers retain nested inline spans and InlineHTML literal exclusions")
    func nestedInlineSourceOwnership() throws {
        let source =
            "\u{FEFF}---\r\ntitle: Mapper\r\n---\r\n\r\n# 范围 e\u{301} 🧭\r\n\r\n"
            + "| Cell | Meaning |\r\n| --- | --- |\r\n| **证据 e\u{301} 🧭** | [Visible](Target.md) |\r\n\r\n"
            + "Paragraph <span title=\"[[Hidden]]\">visible</span> and [[Real]].\r\n"
        let document = NoteDocument(relativePath: "nested-inline.md", rawContent: source)
        let semantic = MarkdownSemanticDocument(parsing: document)
        let strong = try #require(semantic.inlines.first { $0.kind == .strong })
        let link = try #require(semantic.inlines.first { $0.kind == .link })
        let table = try #require(semantic.blocks.first { $0.kind == .table })
        let expectedStrong = "**证据 e\u{301} 🧭**"
        let expectedLink = "[Visible](Target.md)"
        #expect((source as NSString).substring(with: strong.span.nsRange).utf8.elementsEqual(expectedStrong.utf8))
        #expect((source as NSString).substring(with: link.span.nsRange).utf8.elementsEqual(expectedLink.utf8))
        #expect(strong.span.start.line == 9 && strong.span.start.utf16Column == 3)
        #expect(semantic.links.map(\.target) == ["Target.md", "Real"])
        #expect(!semantic.links.contains { $0.target == "Hidden" })
        for span in [table.span, strong.span, link.span] + semantic.links.map(\.span) {
            let exact = (source as NSString).substring(with: span.nsRange)
            #expect(Data(source.utf8)[span.utf8Range] == Data(exact.utf8))
        }
        #expect(document.sourceBytes == Data(source.utf8))
    }

    @Test("Obsidian callouts are typed without parsing literal regions")
    func callouts() {
        let source = """
            ```md
            > [!flag] Not a callout
            ```

            > [!orient] Scope
            > This note maps the issue.

            > [!cite]- Sources
            > Checked source.

            > [!connect] Neighboring notes
            > [[Related Note]]

            > [!state] Normative reason
            > A reason that counts in favour.

            > [!illustrate] Evil Demon
            > A concrete test case.

            > [!quote] Author (2026, p. 1)
            > “Exact wording.”

            > [!flag]+ Source-status limit
            > Verification remains incomplete.

            > [!mini] Legacy orientation
            > Preserved legacy source.

            > [!bibli:] Legacy sources
            > Preserved legacy source.

            > [!project:] Legacy connections
            > Preserved legacy source.

            > [!theorem] Legacy statement
            > Preserved legacy source.

            > [!dialogue] Legacy illustration
            > Preserved legacy source.

            > [!author] Legacy quotation
            > Preserved legacy source.

            > [!torn] Legacy caution
            > Preserved legacy source.

            > [!bespoke] Preserved
            > Unknown kinds remain readable.
            """
        let semantic = MarkdownSemanticDocument(parsing: NoteDocument(relativePath: "callouts.md", rawContent: source))

        #expect(semantic.callouts.count == 15)
        #expect(
            Array(semantic.callouts.prefix(7).map(\.kind)) == [
                "orient", "cite", "connect", "state", "illustrate", "quote", "flag",
            ])
        #expect(
            Array(semantic.callouts.prefix(7).map(\.role)) == [
                .orient, .cite, .connect, .state, .illustrate, .quote, .flag,
            ])
        #expect(
            Array(semantic.callouts.dropFirst(7).map(\.kind)) == [
                "mini", "bibli", "project", "theorem", "dialogue", "author", "torn", "bespoke",
            ])
        #expect(semantic.callouts[7].rawKind == "mini")
        #expect(semantic.callouts[7].role == .neutral)
        #expect(semantic.callouts[8].role == .neutral)
        #expect(semantic.callouts[9].role == .neutral)
        #expect(semantic.callouts[10].role == .neutral)
        #expect(semantic.callouts[11].role == .neutral)
        #expect(semantic.callouts[12].role == .neutral)
        #expect(semantic.callouts[13].role == .neutral)
        #expect(semantic.callouts[1].foldState == .collapsed)
        #expect(semantic.callouts[6].foldState == .expanded)
        #expect(semantic.callouts[3].bodySource == "A reason that counts in favour.")
        #expect(semantic.callouts[14].kind == "bespoke")
        #expect(semantic.callouts[14].role == .neutral)
        #expect(semantic.diagnostics.contains { $0.code == .unknownCallout })
    }

    @Test("Named, repeated, inline, missing, and unused footnotes stay distinct")
    func footnotes() {
        let source = """
            First[^reason], repeated[^reason], missing[^missing], inline^[Inline *content*].

            [^reason]: First line
              second line
            [^unused]: Not cited.
            """
        let semantic = MarkdownSemanticDocument(parsing: NoteDocument(relativePath: "footnotes.md", rawContent: source))
        let named = semantic.footnoteReferences.filter { $0.identifier == "reason" }
        let inline = semantic.footnoteReferences.first { $0.isInline }

        #expect(named.map(\.occurrence) == [1, 2])
        #expect(named.allSatisfy { $0.ordinal == 1 })
        #expect(inline?.ordinal == 3)
        #expect(semantic.footnoteDefinitions.first { $0.identifier == "reason" }?.content == "First line\nsecond line")
        #expect(semantic.diagnostics.contains { $0.code == .undefinedFootnote })
        #expect(semantic.diagnostics.contains { $0.code == .unreferencedFootnote })
    }

    @Test("Footnote continuations preserve nested block indentation and exact ownership")
    func nestedBlockFootnote() throws {
        let source = """
            Claim[^blocks].

            [^blocks]: First paragraph.

              - Outer item
                - Nested item

              ```swift
              let value = 1
              ```
            Following paragraph.
            """
        let semantic = MarkdownSemanticDocument(
            parsing: NoteDocument(relativePath: "nested-footnote.md", rawContent: source)
        )
        let definition = try #require(semantic.footnoteDefinitions.first)

        #expect(
            definition.content == """
                First paragraph.

                - Outer item
                  - Nested item

                ```swift
                let value = 1
                ```
                """)
        let exactSource = (source as NSString).substring(with: definition.span.nsRange)
        #expect(exactSource.hasPrefix("[^blocks]: First paragraph."))
        #expect(exactSource.hasSuffix("  ```\n"))
        #expect(!exactSource.contains("Following paragraph."))
    }

    @Test("Links share one syntax-aware source-location contract")
    func links() {
        let source = """
            前置 🧭 [[Paper#Claim|visible alias]]{{Why **this** matters.}} and [Topic](topics/Topic%20Name.md#Scope).
            `[[Ignored]]`
            %% [[Commented]] %%
            ![[figure.png|320]]
            """
        let semantic = MarkdownSemanticDocument(parsing: NoteDocument(relativePath: "links.md", rawContent: source))

        #expect(semantic.links.count == 3)
        let annotated = semantic.links[0]
        #expect(annotated.target == "Paper")
        #expect(annotated.fragment == "Claim")
        #expect(annotated.alias == "visible alias")
        #expect(annotated.annotation?.markdown == "Why **this** matters.")
        #expect(annotated.span.start.line == 1)
        #expect(
            (source as NSString).substring(with: annotated.span.nsRange)
                == "[[Paper#Claim|visible alias]]{{Why **this** matters.}}")
        #expect(
            (source as NSString).substring(with: annotated.linkSpan.nsRange)
                == "[[Paper#Claim|visible alias]]")
        #expect(semantic.diagnostics.isEmpty)

        #expect(semantic.links[1].target == "topics/Topic Name.md")
        #expect(semantic.links[1].fragment == "Scope")
        #expect(semantic.links[2].syntax == .embed)
        #expect(semantic.links[2].target == "figure.png")
    }

    @Test("Duplicate footnote definitions are visible diagnostics")
    func duplicateFootnotes() {
        let source = "Claim[^x].\n\n[^x]: First.\n[^x]: Second.\n"
        let semantic = MarkdownSemanticDocument(parsing: NoteDocument(relativePath: "duplicate.md", rawContent: source))
        #expect(semantic.footnoteDefinitions.count == 1)
        #expect(semantic.diagnostics.contains { $0.code == .duplicateFootnote })
    }

    @Test("Dollar mathematics is source-located and excludes literal regions")
    func mathematics() throws {
        let source = """
            ---
            title: "$YAML$"
            ---
            Inline $x + 范围$ and double-inline $$C_L$$.

            $$
            \\int_0^1 x^2 \\, dx
            $$

            Escaped \\$literal$ and `code $ignored$`.
            %% $commented$ %%
            <!-- $hidden$ -->

            <div>
            $raw$
            </div>
            """
        let semantic = MarkdownSemanticDocument(
            parsing: NoteDocument(
                relativePath: "Math.md",
                rawContent: source
            ))

        #expect(semantic.mathExpressions.map(\.kind) == [.inline, .inline, .display])
        #expect(
            semantic.mathExpressions.map(\.content) == [
                "x + 范围", "C_L", "\\int_0^1 x^2 \\, dx",
            ])
        #expect(semantic.mathExpressions.map(\.delimiterLength) == [1, 2, 2])
        for expression in semantic.mathExpressions {
            let exact = (source as NSString).substring(with: expression.span.nsRange)
            #expect(exact.contains(expression.content))
        }
        #expect(!semantic.mathExpressions.contains { $0.content.contains("YAML") })
        #expect(!semantic.mathExpressions.contains { $0.content.contains("ignored") })
        #expect(!semantic.mathExpressions.contains { $0.content.contains("commented") })
        #expect(!semantic.mathExpressions.contains { $0.content.contains("hidden") })
        #expect(!semantic.mathExpressions.contains { $0.content.contains("raw") })
    }

    @Test("Unclosed display mathematics remains exact source with a diagnostic")
    func malformedDisplayMathematics() {
        let source = "Before\n\n$$\nx + y\n"
        let semantic = MarkdownSemanticDocument(
            parsing: NoteDocument(
                relativePath: "Malformed Math.md",
                rawContent: source
            ))

        #expect(semantic.mathExpressions.isEmpty)
        #expect(
            semantic.diagnostics.contains { diagnostic in
                diagnostic.code == .malformedMath
                    && diagnostic.span.map { (source as NSString).substring(with: $0.nsRange) } == "$$"
            })
    }
}
