import Foundation
import ScholiumContracts
import Testing

/// Literal-boundary regressions run by default; high-density diagnostics remain
/// opt-in and do not establish a performance gate or release acceptance.
@Suite("Mixed Markdown density and literal boundaries")
struct MixedSyntaxStressTests {
    private static let stressEnabled =
        ProcessInfo.processInfo.environment["SCHOLIUM_MIXED_SYNTAX_STRESS"] == "1"

    @Test(
        "Authored mixed-syntax counts and exact source coordinates survive density",
        .enabled(if: MixedSyntaxStressTests.stressEnabled), arguments: [1, 32, 256])
    func mixedSemanticDensity(groups: Int) throws {
        let fixture = Fixture(groups: groups, newline: "\r\n")
        let document = NoteDocument(relativePath: "Synthetic Mixed.md", rawContent: fixture.source)
        let semantic = MarkdownSemanticDocument(parsing: document)

        // Expectations come from the authored groups, never another parser or
        // a reduced rendering of the same source.
        #expect(semantic.headings.count == groups + 1)
        #expect(semantic.links.map(\.target) == fixture.linkTargets)
        #expect(semantic.links.map { fixture.slice($0.span) } == fixture.linkSources)
        #expect(semantic.callouts.count == groups * 2)
        #expect(semantic.callouts.map(\.kind) == (0..<groups).flatMap { _ in ["state", "flag"] })
        #expect(semantic.callouts.map(\.quoteDepth) == (0..<groups).flatMap { _ in [1, 2] })
        #expect(semantic.footnoteDefinitions.count == groups * 2)
        #expect(semantic.footnoteReferences.count == groups * 3)
        #expect(semantic.mathExpressions.count == groups)
        #expect(semantic.mathExpressions.allSatisfy { $0.kind == .inline })
        #expect(semantic.blocks.filter { $0.kind == .code }.count == groups * 2)
        #expect(semantic.blocks.filter { $0.kind == .table }.count == groups)
        #expect(semantic.diagnostics.isEmpty)
        #expect(
            ParagraphAnchorPlanner.anchors(in: document, semantic: semantic).map(\.id)
                == fixture.anchorIDs)

        try Self.requireExactSpans(semantic, source: fixture.source)
        #expect(document.sourceBytes == fixture.bytes)
        #expect(document.fingerprint == DocumentFingerprint(data: fixture.bytes))
        #expect(fixture.source.hasPrefix("\u{FEFF}---\r\n"))
        #expect(!fixture.source.hasSuffix("\n"))
    }

    @Test(
        "Dense tables, code, Mermaid and inert raw HTML keep independent exact action payloads",
        .enabled(if: MixedSyntaxStressTests.stressEnabled))
    func mixedRenderedObjects() throws {
        let groups = 96
        let fixture = Fixture(groups: groups, newline: "\r\n")
        let document = NoteDocument(relativePath: "Synthetic Mixed.md", rawContent: fixture.source)
        let semantic = MarkdownSemanticDocument(parsing: document)
        let rendered = SafeMarkdownRenderer.render(document, semantic: semantic)

        // Authored HTML blocks are exposed as inert, copyable source examples.
        // Each group therefore owns a table, two code objects and a diagram.
        #expect(rendered.objects.count == groups * 4)
        #expect(
            rendered.objects.filter { $0.kind == .table }.map(\.copyText).sorted()
                == fixture.tables.sorted())
        #expect(
            rendered.objects.filter { $0.kind == .code }.map(\.copyText).sorted() == fixture.code.sorted()
        )
        #expect(
            rendered.objects.filter { $0.kind == .diagram }.map(\.copyText).sorted()
                == fixture.diagrams.sorted())
        #expect(Set(rendered.objects.map(\.id)).count == groups * 4)
        for object in rendered.objects {
            let marker = "data-scholium-object=\"" + object.id + "\""
            #expect(rendered.htmlBody.components(separatedBy: marker).count == 2)
            #expect(!object.html.contains("data-scholium-object"))
        }
        #expect(!rendered.htmlBody.contains("<script"))
        #expect(!rendered.htmlBody.contains("SCHOLIUMINLINETOKEN"))
        #expect(!rendered.htmlBody.contains("Nested rendering limit reached"))
        #expect(rendered.htmlBody.contains("Final visible boundary 🧭 e\u{301}"))
        #expect(SafeMarkdownRenderer.render(document) == rendered)
        #expect(document.sourceBytes == fixture.bytes)
        try Self.requireExactSpans(rendered.semanticDocument, source: fixture.source)
    }

    @Test(
        "A comment opener inside code cannot consume the following authored structures",
        arguments: ["%%", "<!--"])
    func codeCommentOpenersRemainLiteral(opener: String) throws {
        let containers = [
            "`\(opener)`",
            "``literal ` \(opener)``",
            "```text\n\(opener)\n```",
            "~~~text\n\(opener)\n~~~",
            "    \(opener)",
            "> ```text\n> \(opener)\n> ```",
        ]
        for (index, literal) in containers.enumerated() {
            let source =
                "# Literal \(index)\n\n" + literal
                + "\n\n[[Visible-\(index)]]{{Visible reason.}} $x$ [^visible]\n\n"
                + "> [!state] Visible Callout\n> Visible body.\n\n"
                + "[^visible]: Visible definition.\n\nVisible paragraph. ^visible-anchor"
            let document = NoteDocument(relativePath: "Literal.md", rawContent: source)
            let semantic = MarkdownSemanticDocument(parsing: document)
            #expect(
                semantic.links.map(\.target) == ["Visible-\(index)"],
                "Container: \(literal.debugDescription)")
            #expect(semantic.callouts.count == 1, "Container: \(literal.debugDescription)")
            #expect(semantic.mathExpressions.count == 1, "Container: \(literal.debugDescription)")
            #expect(semantic.footnoteDefinitions.count == 1, "Container: \(literal.debugDescription)")
            #expect(semantic.footnoteReferences.count == 1, "Container: \(literal.debugDescription)")
            #expect(
                !semantic.diagnostics.contains { $0.code == .malformedComment },
                "Container: \(literal.debugDescription)")
            #expect(
                ParagraphAnchorPlanner.anchors(in: document, semantic: semantic).map(\.id) == [
                    "visible-anchor"
                ])
            #expect(MarkdownSemanticParser.commentRanges(in: document).isEmpty)
            #expect(MarkdownSemanticParser.commentRanges(in: document, semantic: semantic).isEmpty)
            let rendered = SafeMarkdownRenderer.render(document, semantic: semantic)
            #expect(
                rendered.htmlBody.contains("Visible body."),
                "Review must retain prose after the code literal.")
            #expect(document.sourceBytes == Data(source.utf8))
            try Self.requireExactSpans(semantic, source: source)
        }
    }

    @Test(
        "Literal closers cannot end adjacent real comments or create trailing comments",
        arguments: ["%%", "<!--"])
    func codeCommentClosersRemainLiteral(opener: String) throws {
        let closer = opener == "%%" ? "%%" : "-->"
        let literal = "```text\r\n\(opener)\r\n\(closer)\r\n```"
        let comment = opener + " [[Hidden]] $hidden$ [^hidden] " + closer
        let source =
            "\u{FEFF}---\r\nunknown: '中文 e\u{301} 🧭' # preserve\r\n---\r\n\r\n"
            + literal + "\r\n\r\n" + comment + "\r\n\r\n"
            + "`\(closer)` [[Visible]] $x$ [^visible]\r\n\r\n"
            + "> [!state] Visible\r\n> Visible body.\r\n\r\n"
            + "[^visible]: Visible definition.\r\n\r\nVisible paragraph. ^visible-anchor"
        let document = NoteDocument(relativePath: "Closers.md", rawContent: source)
        let semantic = MarkdownSemanticDocument(parsing: document)
        #expect(semantic.links.map(\.target) == ["Visible"])
        #expect(semantic.mathExpressions.count == 1)
        #expect(semantic.footnoteDefinitions.count == 1)
        #expect(semantic.footnoteReferences.count == 1)
        #expect(semantic.callouts.count == 1)
        #expect(semantic.diagnostics.isEmpty)
        #expect(
            ParagraphAnchorPlanner.anchors(in: document, semantic: semantic).map(\.id) == [
                "visible-anchor"
            ])
        let expectedRange = (source as NSString).range(of: comment)
        let comments = MarkdownSemanticParser.commentRanges(in: document)
        #expect(comments == [expectedRange.location..<NSMaxRange(expectedRange)])
        #expect(MarkdownSemanticParser.commentRanges(in: document, semantic: semantic) == comments)
        #expect(document.sourceBytes == Data(source.utf8))
        try Self.requireExactSpans(semantic, source: source)
    }

    @Test("The comment range scan ignores interior code markers and other comment delimiters")
    func realCommentsOwnTheirInterior() throws {
        let comments = [
            "%% <!-- ` [[Hidden-A]] %%",
            "<!-- %% ` [[Hidden-B]] -->",
            "%% ```text\n<!-- [[Hidden-C]]\n%%",
        ]
        let source = comments.joined(separator: "\n\n[[Visible]]\n\n") + "\n\n[[Visible]]"
        let document = NoteDocument(relativePath: "Real comments.md", rawContent: source)
        let semantic = MarkdownSemanticDocument(parsing: document)
        #expect(semantic.diagnostics.isEmpty)
        let actual = MarkdownSemanticParser.commentRanges(in: document)
        #expect(
            actual.map {
                (source as NSString).substring(with: NSRange(location: $0.lowerBound, length: $0.count))
            } == comments)
        #expect(MarkdownSemanticParser.commentRanges(in: document, semantic: semantic) == actual)
        let stale = MarkdownSemanticDocument(parsing: NoteDocument(relativePath: document.relativePath, rawContent: "```\nold\n```"))
        #expect(MarkdownSemanticParser.commentRanges(in: document, semantic: stale) == actual)
        #expect(document.sourceBytes == Data(source.utf8))
        try Self.requireExactSpans(semantic, source: source)
    }

    @Test(
        "An unclosed real comment after code still fails closed at its exact source opener",
        arguments: ["%%", "<!--"])
    func realUnclosedCommentAfterCode(opener: String) throws {
        let source =
            "\u{FEFF}# 范围 e\u{301} 🧭\r\n\r\n`\(opener)`\r\n\r\n[[Visible]]\r\n\r\n"
            + opener + "\r\n[[Hidden]] $hidden$ [^hidden]\r\n\r\n> [!state] Hidden\r\n> Hidden body."
        let document = NoteDocument(relativePath: "Unclosed.md", rawContent: source)
        let semantic = MarkdownSemanticDocument(parsing: document)
        #expect(semantic.links.map(\.target) == ["Visible"])
        #expect(semantic.mathExpressions.isEmpty)
        #expect(semantic.footnoteReferences.isEmpty)
        #expect(semantic.callouts.isEmpty)
        let diagnostic = try #require(semantic.diagnostics.first { $0.code == .malformedComment })
        let span = try #require(diagnostic.span)
        let opening = (source as NSString).range(of: opener, options: .backwards)
        #expect(span.nsRange == opening)
        let comments = MarkdownSemanticParser.commentRanges(in: document)
        #expect(comments == [opening.location..<(source as NSString).length])
        #expect(MarkdownSemanticParser.commentRanges(in: document, semantic: semantic) == comments)
        #expect(document.sourceBytes == Data(source.utf8))
        try Self.requireExactSpans(semantic, source: source)
    }

    @Test(
        "Dense malformed extensions diagnose their owned sources and fail closed at a real comment",
        .enabled(if: MixedSyntaxStressTests.stressEnabled), arguments: ["%%", "<!--"])
    func malformedMixedDensity(opener: String) throws {
        let groups = 48
        var sections = ["# Synthetic malformed density"]
        var expectedTargets: [String] = []
        for index in 0..<groups {
            expectedTargets.append("Malformed-\(index)")
            sections.append(
                """
                [[Malformed-\(index)]]{{ }} [^missing-\(index)] [^duplicate-\(index)]

                > [!synthetic-unknown-\(index)] Preserved neutral Callout
                > Unknown identifiers do not invent a semantic role.

                [^duplicate-\(index)]: First definition.
                [^duplicate-\(index)]: Second definition.

                ```mermaid
                flowchart ??? invalid-\(index)
                [[literal-\(index)]] $not-math$ [^not-a-footnote]
                ```
                """)
        }
        sections.append(opener + "\n[[Hidden]] $hidden$ [^hidden]\n\n> [!state] Hidden\n> Hidden body.")
        let source = sections.joined(separator: "\n\n")
        let document = NoteDocument(relativePath: "Malformed Mixed.md", rawContent: source)
        let semantic = MarkdownSemanticDocument(parsing: document)
        #expect(semantic.links.map(\.target) == expectedTargets)
        #expect(semantic.links.allSatisfy { $0.annotation == nil && $0.span == $0.linkSpan })
        #expect(semantic.callouts.count == groups)
        #expect(semantic.callouts.allSatisfy { $0.role == .neutral })
        #expect(semantic.footnoteDefinitions.count == groups)
        #expect(semantic.footnoteReferences.count == groups * 2)
        #expect(semantic.mathExpressions.isEmpty)
        for code in [
            MarkdownDiagnosticCode.malformedLinkAnnotation, .unknownCallout, .duplicateFootnote,
            .undefinedFootnote,
        ] {
            #expect(semantic.diagnostics.filter { $0.code == code }.count == groups)
        }
        let comment = try #require(semantic.diagnostics.first { $0.code == .malformedComment })
        let span = try #require(comment.span)
        #expect((source as NSString).substring(with: span.nsRange) == opener)
        #expect(semantic.diagnostics.filter { $0.code == .malformedComment }.count == 1)
        let rendered = SafeMarkdownRenderer.render(document, semantic: semantic)
        #expect(rendered.objects.filter { $0.kind == .diagram }.count == groups)
        // The safe renderer may preserve unrecognized/commented source as an
        // inert example. That text must not acquire links or Callout behavior.
        #expect(!rendered.htmlBody.contains("href=\"scholium-note:Hidden\""))
        #expect(!rendered.htmlBody.contains("data-callout=\"state\""))
        #expect(document.sourceBytes == Data(source.utf8))
        try Self.requireExactSpans(semantic, source: source)
    }

    private static func requireExactSpans(_ semantic: MarkdownSemanticDocument, source: String) throws {
        let nsSource = source as NSString
        let bytes = Data(source.utf8)
        var spans = semantic.blocks.map(\.span) + semantic.inlines.map(\.span)
        spans += semantic.headings.map(\.span) + semantic.links.flatMap { [$0.span, $0.linkSpan] }
        spans += semantic.callouts.flatMap { [$0.span, $0.headerSpan] }
        spans += semantic.footnoteDefinitions.map(\.span) + semantic.footnoteReferences.map(\.span)
        spans += semantic.mathExpressions.flatMap { [$0.span, $0.contentSpan] }
        spans += semantic.diagnostics.compactMap(\.span)
        for span in spans {
            try #require(
                span.utf8LowerBound >= 0 && span.utf8LowerBound <= span.utf8UpperBound
                    && span.utf8UpperBound <= bytes.count)
            try #require(
                span.utf16LowerBound >= 0 && span.utf16LowerBound <= span.utf16UpperBound
                    && span.utf16UpperBound <= nsSource.length)
            let exact = nsSource.substring(with: span.nsRange)
            #expect(bytes[span.utf8Range] == Data(exact.utf8))
        }
    }

    private struct Fixture {
        let source: String
        let bytes: Data
        let linkTargets: [String]
        let linkSources: [String]
        let anchorIDs: [String]
        let tables: [String]
        let code: [String]
        let diagrams: [String]

        init(groups: Int, newline: String) {
            var sections = [
                "\u{FEFF}---\nunknown: 'preserve' # original metadata\nfixture_only: true\nhidden: '[[YAML Literal]] $hidden$'\n---\n\n# Synthetic Mixed Syntax"
            ]
            var targets: [String] = []
            var links: [String] = []
            var anchors: [String] = []
            var authoredTables: [String] = []
            var authoredCode: [String] = []
            var authoredDiagrams: [String] = []
            for index in 0..<groups {
                let annotated = "[[Target-\(index)#Part|中文 e\u{301} 🧭]]{{Reason **\(index)**.}}"
                let external = "[External \(index)](https://example.invalid/\(index))"
                let callout = "[[Callout-\(index)]]"
                let tableLink = "[[Table-\(index)]]"
                let table = "| Key | Value |\n| :--- | ---: |\n| escaped \\| pipe \(index) | \(tableLink) |"
                let code =
                    "let symbols = \"[[Code-\(index)]] $literal$ [^literal]\"\n> [!state] Literal Callout\n<script>literal-\(index)</script>\n"
                let diagram =
                    "flowchart LR\n  A\(index)[\"[[DiagramLiteral-\(index)]]\"] --> B\(index)[\"节点 🧭\"]\n"
                let anchor = "paragraph-\(index)"
                sections.append(
                    """
                    ## Segment \(index) · 中文 e\u{301} 🧭

                    **bold-\(index)** *emphasis* ~~strike~~ ==highlight== $x_{\(index)}$ \(annotated) \(external).
                    Named[^named-\(index)] repeated[^named-\(index)] inline^[inline-\(index)].

                    - [ ] Task \(index)
                    - [x] Completed \(index)
                      - Nested bullet

                    1. Ordered item
                    2. Second item

                    > [!state]+ Outer \(index)
                    > Body \(callout).
                    >
                    > > [!flag]- Inner \(index)
                    > > Preserved nested body **\(index)**.

                    \(table)

                    ```swift
                    \(code)```

                    ```mermaid
                    \(diagram)```

                    `[[InlineLiteral-\(index)]] $literal$ [^literal]` and \\[[EscapedLiteral-\(index)]].

                    %% [[CommentLiteral-\(index)]] $literal$ [^literal] %%

                    <!-- [[HTMLCommentLiteral-\(index)]] $literal$ [^literal] -->

                    [^named-\(index)]: Definition \(index).

                    Paragraph \(index). ^\(anchor)
                    """)
                targets += [
                    "Target-\(index)", "https://example.invalid/\(index)", "Callout-\(index)",
                    "Table-\(index)",
                ]
                links += [annotated, external, callout, tableLink]
                anchors.append(anchor)
                authoredTables.append(table.replacingOccurrences(of: "\n", with: newline))
                authoredCode.append(code.replacingOccurrences(of: "\n", with: newline))
                authoredCode.append(
                    "<!-- [[HTMLCommentLiteral-\(index)]] $literal$ [^literal] -->" + newline)
                authoredDiagrams.append(diagram.replacingOccurrences(of: "\n", with: newline))
            }
            sections.append("Final visible boundary 🧭 e\u{301}")
            let authoredSource = sections.joined(separator: "\n\n").replacingOccurrences(
                of: "\n", with: newline)
            self.source = authoredSource
            self.bytes = Data(authoredSource.utf8)
            self.linkTargets = targets
            self.linkSources = links
            self.anchorIDs = anchors
            self.tables = authoredTables
            self.code = authoredCode
            self.diagrams = authoredDiagrams
        }

        func slice(_ span: SourceSpan) -> String {
            (source as NSString).substring(with: span.nsRange)
        }
    }
}
