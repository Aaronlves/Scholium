import Foundation
import ScholiumContracts
import Testing

@Suite("Research Record prose projection")
struct ResearchRecordProseProjectionTests {
    @Test("Supported scholarly emphasis and headings project without changing source")
    func supportedInlineMarkup() throws {
        let source = "# Argument\n\nThe **strong** and *qualified* claim uses `P -> Q`."
        let projection = ResearchRecordProseProjection(source: source)

        #expect(projection.source == source)
        #expect(projection.blocks.count == 2)
        #expect(projection.blocks[0].kind == .heading)
        #expect(projection.blocks[0].inlines == [
            ResearchRecordProseInline(text: "Argument", traits: .strong),
        ])
        #expect(projection.blocks[1].inlines.contains {
            $0.text == "strong" && $0.traits == .strong
        })
        #expect(projection.blocks[1].inlines.contains {
            $0.text == "qualified" && $0.traits == .emphasis
        })
        #expect(projection.blocks[1].inlines.contains {
            $0.text == "P -> Q" && $0.traits == .code
        })
    }

    @Test("Unicode and CRLF source offsets preserve exact linked and literal syntax")
    func unicodeSourceOffsets() throws {
        let source = "前提 😀 **强调**\r\n\r\n参见 [[论文#论证|这篇论文]] 与 [不安全](javascript:alert(1))。"
        let projection = ResearchRecordProseProjection(source: source)
        let inlines = projection.blocks.flatMap(\.inlines)

        #expect(projection.source == source)
        #expect(inlines.contains { $0.text == "强调" && $0.traits == .strong })
        #expect(inlines.contains {
            $0.text == "这篇论文" && $0.link == .internalReference(
                target: "论文",
                fragment: "论证",
                fallbackText: "[[论文#论证|这篇论文]]",
                syntax: .wikilink
            )
        })
        #expect(inlines.map(\.text).joined().contains("[不安全](javascript:alert(1))"))
    }

    @Test("Ordinary lists and quotations retain their modest structural roles")
    func listsAndQuotations() throws {
        let source = "- First\n  - Nested\n\n3. Third\n\n> A limited quotation."
        let blocks = ResearchRecordProseProjection(source: source).blocks

        #expect(blocks.map(\.kind) == [
            .unorderedListItem(depth: 0),
            .unorderedListItem(depth: 1),
            .orderedListItem(index: 3, depth: 0),
            .paragraph,
        ])
        #expect(blocks.last?.quoteDepth == 1)
        #expect(blocks.last?.inlines.map(\.text).joined() == "A limited quotation.")
    }

    @Test("Full Wikilinks retain exact fallback syntax and neutralize vector meaning")
    func fullWikilinks() throws {
        let source = "See [[Paper]], [[Paper#Objection|the objection]], [[Paper#^p3]], and +[[Support]]."
        let projection = ResearchRecordProseProjection(source: source)
        let links = projection.blocks.flatMap(\.inlines).compactMap(\.link)

        #expect(projection.source == source)
        #expect(links.count == 4)
        #expect(links[0] == .internalReference(
            target: "Paper",
            fragment: nil,
            fallbackText: "[[Paper]]",
            syntax: .wikilink
        ))
        #expect(links[1] == .internalReference(
            target: "Paper",
            fragment: "Objection",
            fallbackText: "[[Paper#Objection|the objection]]",
            syntax: .wikilink
        ))
        #expect(links[2] == .internalReference(
            target: "Paper",
            fragment: "^p3",
            fallbackText: "[[Paper#^p3]]",
            syntax: .wikilink
        ))
        #expect(links[3] == .internalReference(
            target: "Support",
            fragment: nil,
            fallbackText: "[[Support]]",
            syntax: .wikilink
        ))
        #expect(projection.blocks.flatMap(\.inlines).map(\.text).joined().contains("+Support"))
    }

    @Test("Safe web and internal Markdown links project while unsafe schemes remain literal")
    func markdownLinks() throws {
        let source = "[Web](https://example.org), [Note](Paper.md#Claim), [local](#Claim), [unsafe](javascript:alert(1))."
        let projection = ResearchRecordProseProjection(source: source)
        let inlines = projection.blocks.flatMap(\.inlines)

        #expect(inlines.contains {
            $0.text == "Web" && $0.link == .external(URL(string: "https://example.org")!)
        })
        #expect(inlines.contains {
            $0.text == "Note" && $0.link == .internalReference(
                target: "Paper.md",
                fragment: "Claim",
                fallbackText: "[Note](Paper.md#Claim)",
                syntax: .markdown
            )
        })
        #expect(inlines.contains {
            $0.text == "local" && $0.link == .internalReference(
                target: "",
                fragment: "Claim",
                fallbackText: "[local](#Claim)",
                syntax: .markdown
            )
        })
        #expect(inlines.map(\.text).joined().contains("[unsafe](javascript:alert(1))"))
        #expect(!inlines.contains { inline in
            guard case .external? = inline.link else { return false }
            return inline.text == "unsafe"
        })
    }

    @Test("Unsupported structures remain literal and never activate nested Wikilinks")
    func unsupportedStructuresRemainLiteral() throws {
        let source = """
        ```swift
        [[Code]]
        ```

        > [!NOTE]
        > [[Callout]]

        ![[Embed]]

        - [x] [[Task]]
        """
        let projection = ResearchRecordProseProjection(source: source)

        #expect(projection.source == source)
        #expect(projection.blocks.flatMap(\.inlines).compactMap(\.link).isEmpty)
        let literal = projection.blocks.flatMap(\.inlines).map(\.text).joined(separator: "\n")
        #expect(literal.contains("[[Code]]"))
        #expect(literal.contains("[[Callout]]"))
        #expect(literal.contains("![[Embed]]"))
        #expect(literal.contains("[[Task]]"))
    }

    @Test("Navigation resolves exact notes, headings, blocks, aliases, and fragment-only links")
    func navigationResolution() throws {
        let vaultID = UUID()
        let sourceID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Notes/Source.md")
        let target = NoteDocument(
            relativePath: "Notes/Target.md",
            rawContent: "# Claim\n\nBody ^support\n"
        )
        let targetID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: target.relativePath)
        let targetSemantic = MarkdownSemanticDocument(parsing: target)
        let source = NoteDocument(
            relativePath: sourceID.relativePath,
            rawContent: "# Local\n"
        )
        let catalog = LinkResolutionCatalog(catalog: [
            LinkCatalogNote(vaultID: vaultID, document: source),
            LinkCatalogNote(
                id: targetID,
                title: "Declared Target",
                aliases: ["Alias"],
                headings: targetSemantic.headings,
                blockAnchors: LinkCatalogNote(
                    vaultID: vaultID,
                    document: target,
                    semantic: targetSemantic
                ).blockAnchors
            ),
        ])

        #expect(catalog.resolveNavigation(
            target: "Alias",
            fragment: nil,
            from: sourceID
        ) == .resolved(LinkDestination(
            note: targetID,
            kind: .note,
            fragment: nil,
            span: nil
        )))
        let heading = catalog.resolveNavigation(
            target: "Target",
            fragment: "Claim",
            from: sourceID
        )
        guard case .resolved(let headingDestination) = heading else {
            Issue.record("Expected heading navigation to resolve")
            return
        }
        #expect(headingDestination.kind == .heading)
        #expect(headingDestination.span?.start.line == 1)

        let block = catalog.resolveNavigation(
            target: "Target",
            fragment: "^support",
            from: sourceID
        )
        guard case .resolved(let blockDestination) = block else {
            Issue.record("Expected block navigation to resolve")
            return
        }
        #expect(blockDestination.kind == .block)
        #expect(blockDestination.span?.start.line == 3)

        #expect(catalog.resolveNavigation(
            target: "",
            fragment: "Local",
            from: sourceID
        ) == .resolved(LinkDestination(
            note: sourceID,
            kind: .heading,
            fragment: "Local",
            span: try #require(
                MarkdownSemanticDocument(parsing: source).headings.first?.span
            )
        )))
    }

    @Test("Navigation fails closed for ambiguity and missing fragments")
    func failClosedNavigation() {
        let vaultID = UUID()
        let sourceID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Source.md")
        let first = VaultQualifiedNoteID(vaultID: vaultID, relativePath: "A/Paper.md")
        let second = VaultQualifiedNoteID(vaultID: vaultID, relativePath: "B/Paper.md")
        let catalog = LinkResolutionCatalog(catalog: [
            LinkCatalogNote(id: sourceID, headings: [], blockAnchors: [:]),
            LinkCatalogNote(id: first, headings: [], blockAnchors: [:]),
            LinkCatalogNote(id: second, headings: [], blockAnchors: [:]),
        ])

        guard case .ambiguous(let candidates) = catalog.resolveNavigation(
            target: "Paper",
            fragment: nil,
            from: sourceID
        ) else {
            Issue.record("Expected colliding stems to remain ambiguous")
            return
        }
        #expect(candidates == [first, second].sorted())
        #expect(catalog.resolveNavigation(
            target: "A/Paper",
            fragment: "Missing",
            from: sourceID
        ) == .missingHeading)
        #expect(catalog.resolveNavigation(
            target: "A/Paper",
            fragment: "^missing",
            from: sourceID
        ) == .missingBlock)
        #expect(catalog.resolveNavigation(
            target: "Absent",
            fragment: nil,
            from: sourceID
        ) == .missingNote)
    }
}
