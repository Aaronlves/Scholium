import Foundation
import Testing

@testable import ScholiumContracts

@Suite("Search source projection context")
struct SearchSourceProjectionContextTests {
    @Test("Nested ranges preserve original candidate order, ties and distinct empty-range predicates")
    func adversarialQueries() throws {
        let links = [
            link(28..<32, annotation: 180..<220, number: 0),
            link(8..<40, annotation: 24..<48, number: 1),
            link(12..<16, annotation: 16..<24, number: 2),
            link(12..<16, syntax: .embed, annotation: 16..<24, number: 3),
            link(20..<20, annotation: 20..<20, number: 4),
            link(16..<20, syntax: .markdown, annotation: 4..<8, number: 5),
            link(0..<128, annotation: 0..<128, number: 6),
        ]
        let anchors = [48..<52, 18..<20, 18..<20, 20..<20, 0..<4, 10..<64]
        let value = semantic(
            blocks: [block(8..<12, kind: .heading), block(8..<40), block(8..<20), block(4..<8)],
            links: links, headings: [20..<20, 64..<68], footnotes: [16..<16, 80..<96],
            math: [32..<32, 100..<120], callouts: [0..<4, 12..<16]
        )
        let context = makeContext(value, anchors: anchors)
        #expect(context.paragraph(startingAt: 8) == value.blocks[1])
        #expect(context.paragraph(startingAt: 4) == value.blocks[3])
        #expect(context.paragraph(startingAt: 9) == nil)
        #expect(context.containedVisibleLinks(in: 16..<20).map(\.target) == ["Target 4 e\u{301}😀"])
        #expect(context.firstAnchorSuffix(in: 0..<64) == 48..<52)
        #expect(context.annotationsForLinks(startingIn: 28..<32) == [links[0].annotation!])
        #expect(context.overlapsExcludedRange(19..<21))
        #expect(!context.overlapsProtectedRange(15..<17))
        #expect(context.overlapsExcludedRange(10..<10))
        #expect(context.clippedExcludedRanges(in: 10..<10).isEmpty)
        for lower in [0, 4, 8, 12, 16, 18, 20, 24, 28, 32, 40, 48, 52, 64, 80, 96, 128, 180, 220, 256] {
            for length in [0, 1, 4, 16, 64, 256] {
                try expectLinearQueries(context, semantic: value, anchors: anchors, range: lower..<(lower + length))
            }
        }
    }

    @Test("Deterministic randomized range queries equal the former independent linear filters")
    func randomizedLinearEquivalence() throws {
        var generator = Generator()
        for _ in 0..<96 {
            var links: [LinkOccurrence] = []
            for number in 0..<generator.number(48) {
                let annotation = generator.number(3) == 0 ? nil : generator.range()
                let item = link(generator.range(), syntax: [.wikilink, .markdown, .embed][generator.number(3)], annotation: annotation, number: number)
                links.append(item)
                if generator.number(4) == 0 { links.append(item) }
            }
            let anchors = (0..<generator.number(24)).map { _ in generator.range() }
            let blocks = (0..<generator.number(24)).map { _ in block(generator.range(), kind: generator.number(3) == 0 ? .heading : .paragraph) }
            let value = semantic(
                blocks: blocks, links: links,
                headings: (0..<generator.number(12)).map { _ in generator.range() },
                footnotes: (0..<generator.number(12)).map { _ in generator.range() },
                math: (0..<generator.number(12)).map { _ in generator.range() },
                callouts: (0..<generator.number(12)).map { _ in generator.range() }
            )
            let context = makeContext(value, anchors: anchors)
            try expectBytes(context.annotations, value.links.compactMap(\.annotation))
            for item in blocks {
                #expect(
                    context.paragraph(startingAt: item.span.utf16LowerBound)
                        == blocks.first { $0.kind == .paragraph && $0.span.utf16LowerBound == item.span.utf16LowerBound })
            }
            for _ in 0..<32 {
                try expectLinearQueries(context, semantic: value, anchors: anchors, range: generator.range())
            }
        }
    }

    @Test("Real Unicode, source boundaries, callouts, footnotes and malformed input retain query contracts")
    func parsedSourceQueries() throws {
        for newline in ["\n", "\r\n"] {
            for frontmatter in ["---\ntitle: e\u{301}😀\nkeywords: [one, two]\n---\n", "---\ntitle: [malformed\n---\n", ""] {
                let raw =
                    ("\u{FEFF}" + frontmatter + """
                        # Heading 中

                        Before &amp; [[Target|é😀]]{{A **reason** with [[Other|中文]].}} after. ^anchor1

                        > [!state] Claim
                        > Body with [[Third|visible]]{{annotation}}
                        >
                        > > [!quote] Nested
                        > > é 👩‍🔬

                        - list [[Item]]
                          - nested `code`

                        Next ![[Image.png|label]] and [web](https://example.invalid).

                        [^one]: footnote [[Reference|visible]]

                        $$
                        x = y
                        $$

                        [[Broken{{unclosed
                        """).replacingOccurrences(of: "\n", with: newline)
                let document = NoteDocument(relativePath: "Unicode.md", rawContent: raw)
                let value = MarkdownSemanticDocument(parsing: document)
                let anchors = ParagraphAnchorPlanner.anchors(in: document, semantic: value).map(\.markerSpan.utf16Range)
                let context = SearchSourceProjectionContext(
                    source: document.body, fullSourceUTF16Offset: raw.utf16.count - document.body.utf16.count,
                    semantic: value, anchorRanges: anchors)
                #expect(Data((context.source as String).utf8) == Data(document.body.utf8))
                for item in value.blocks {
                    try expectLinearQueries(context, semantic: value, anchors: anchors, range: item.span.utf16Range)
                }
                for item in value.links {
                    try expectLinearQueries(context, semantic: value, anchors: anchors, range: item.linkSpan.utf16Range)
                }
                for point in 0...raw.utf16.count {
                    #expect(context.annotationContains(point) == value.links.compactMap(\.annotation).contains { $0.span.utf16Range.contains(point) })
                }
            }
        }
    }

    @Test("Paragraph annotation segment lookup retains duplicate content starts and segment order")
    func duplicateAnnotationSegments() throws {
        let document = NoteDocument(relativePath: "Annotations.md", rawContent: "Before [[Target|label]]{{one}} after.\n\nSecond paragraph.\n")
        let parsed = MarkdownSemanticDocument(parsing: document)
        let first = try #require(parsed.links.first)
        let annotation = try #require(first.annotation)
        let second = LinkOccurrence(
            syntax: .wikilink, target: "Other", alias: nil, fragment: nil,
            annotation: .init(markdown: annotation.markdown, text: "e\u{301}😀", span: annotation.span, contentSpan: annotation.contentSpan),
            isExternal: false, span: first.span, linkSpan: first.linkSpan)
        let value = MarkdownSemanticDocument(
            fingerprint: parsed.fingerprint, blocks: parsed.blocks, inlines: parsed.inlines, headings: parsed.headings,
            callouts: parsed.callouts, footnoteDefinitions: parsed.footnoteDefinitions, footnoteReferences: parsed.footnoteReferences,
            mathExpressions: parsed.mathExpressions, links: [first, second], diagnostics: parsed.diagnostics)
        let projection = SearchDocumentProjection(document: document, semantic: value)
        let paragraph = try #require(projection.paragraphs.first)
        let expected = value.links.filter {
            paragraph.range.utf16LowerBound <= $0.linkSpan.utf16LowerBound && $0.linkSpan.utf16LowerBound < parsed.blocks[0].span.utf16UpperBound
        }
        .compactMap(\.annotation).flatMap { annotation in
            projection.segments.filter { $0.field == .linkAnnotation && $0.sourceRange?.utf16LowerBound == annotation.contentSpan.utf16LowerBound }
        }
        let actual = paragraph.segments.filter { $0.field == .linkAnnotation }
        #expect(actual.count == 4)
        try expectBytes(actual, expected)
    }
}

private extension SearchSourceProjectionContextTests {
    struct Generator {
        private var state: UInt64 = 0x1BE9_7A20_D0F3_4C68

        mutating func number(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 32) % UInt64(bound))
        }

        mutating func range() -> Range<Int> {
            let lower = number(256)
            return lower..<(lower + number(96))
        }
    }

    func makeContext(_ semantic: MarkdownSemanticDocument, anchors: [Range<Int>]) -> SearchSourceProjectionContext {
        .init(source: String(repeating: "x", count: 512), fullSourceUTF16Offset: 37, semantic: semantic, anchorRanges: anchors)
    }

    func expectLinearQueries(_ context: SearchSourceProjectionContext, semantic: MarkdownSemanticDocument, anchors: [Range<Int>], range: Range<Int>) throws {
        // These are the previous callers' independent filters, including their
        // deliberately different endpoint / empty-range rules and source order.
        let annotations = semantic.links.compactMap(\.annotation)
        let excluded =
            semantic.headings.map(\.span.utf16Range) + semantic.callouts.map(\.span.utf16Range)
            + semantic.footnoteDefinitions.map(\.span.utf16Range) + annotations.map(\.span.utf16Range) + anchors
        let protected =
            semantic.footnoteDefinitions.map(\.span.utf16Range)
            + semantic.mathExpressions.filter { $0.kind == .display }.map(\.span.utf16Range)
        let clipped = excluded.compactMap { item -> Range<Int>? in
            let lower = max(item.lowerBound, range.lowerBound)
            let upper = min(item.upperBound, range.upperBound)
            return lower < upper ? lower..<upper : nil
        }
        #expect(context.clippedExcludedRanges(in: range) == clipped)
        #expect(context.overlapsExcludedRange(range) == excluded.contains { $0.lowerBound < range.upperBound && $0.upperBound > range.lowerBound })
        #expect(context.overlapsProtectedRange(range) == protected.contains { $0.overlaps(range) })
        #expect(context.annotationContains(range.lowerBound) == annotations.contains { $0.span.utf16Range.contains(range.lowerBound) })
        #expect(context.firstAnchorSuffix(in: range) == anchors.first { range.lowerBound < $0.lowerBound && $0.upperBound <= range.upperBound })
        let visible = semantic.links.filter {
            ($0.syntax == .wikilink || $0.syntax == .embed)
                && range.lowerBound <= $0.linkSpan.utf16LowerBound && $0.linkSpan.utf16UpperBound <= range.upperBound
        }
        try expectBytes(context.containedVisibleLinks(in: range), visible)
        let owned = semantic.links.filter { range.contains($0.linkSpan.utf16LowerBound) }.compactMap(\.annotation)
        try expectBytes(context.annotationsForLinks(startingIn: range), owned)
    }

    func expectBytes<T: Encodable & Equatable>(_ actual: T, _ expected: T) throws {
        #expect(actual == expected)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(actual) == encoder.encode(expected))
    }

    func span(_ range: Range<Int>) -> SourceSpan {
        .init(
            utf8LowerBound: range.lowerBound, utf8UpperBound: range.upperBound,
            utf16LowerBound: range.lowerBound, utf16UpperBound: range.upperBound,
            start: .init(line: 1, utf8Column: range.lowerBound + 1, utf16Column: range.lowerBound + 1),
            end: .init(line: 1, utf8Column: range.upperBound + 1, utf16Column: range.upperBound + 1))
    }

    func block(_ range: Range<Int>, kind: MarkdownBlockKind = .paragraph) -> MarkdownBlock {
        .init(kind: kind, span: span(range))
    }

    func link(_ range: Range<Int>, syntax: LinkSyntax = .wikilink, annotation: Range<Int>?, number: Int) -> LinkOccurrence {
        .init(
            syntax: syntax, target: "Target \(number) e\u{301}😀", alias: number.isMultiple(of: 2) ? "Alias \(number)" : nil, fragment: nil,
            annotation: annotation.map { .init(markdown: "Annotation \(number)", text: "Annotation \(number)", span: span($0), contentSpan: span($0)) },
            isExternal: false, span: span(range), linkSpan: span(range))
    }

    func semantic(
        blocks: [MarkdownBlock], links: [LinkOccurrence], headings: [Range<Int>] = [],
        footnotes: [Range<Int>] = [], math: [Range<Int>] = [], callouts: [Range<Int>] = []
    ) -> MarkdownSemanticDocument {
        .init(
            fingerprint: DocumentFingerprint(content: "fixture"), blocks: blocks,
            headings: headings.map { .init(level: 1, text: "Heading", span: span($0)) },
            callouts: callouts.map {
                .init(
                    rawKind: "state", kind: "state", role: .state, title: "Claim", bodySource: "Body", quoteDepth: 1, foldState: .fixed, span: span($0),
                    headerSpan: span($0))
            },
            footnoteDefinitions: footnotes.map { .init(identifier: "one", content: "Note", contentSlices: [], ordinal: nil, isInline: false, span: span($0)) },
            footnoteReferences: [],
            mathExpressions: math.map { .init(kind: .display, content: "x", delimiterLength: 2, span: span($0), contentSpan: span($0)) },
            links: links, diagnostics: [])
    }
}
