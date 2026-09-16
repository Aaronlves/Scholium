import Foundation
import Testing

@testable import ScholiumContracts

@Suite("Current paragraph identities")
struct ParagraphAnchorPlannerTests {
    @Test("Cached anchors cannot outlive their authored marker or replace current source spans")
    func staleSuppliedAnchorProjection() throws {
        let previous = NoteDocument(relativePath: "A.md", rawContent: "Old. ^old")
        let stale = MarkdownSemanticDocument(parsing: previous)
        for raw in [
            "\u{FEFF}---\r\nunknown: 'unchanged' # comment\r\n---\r\n当前 🦉 e\u{301}.",
            "\u{FEFF}---\r\nunknown: 'unchanged' # comment\r\n---\r\n当前 🦉 e\u{301}. ^current",
        ] {
            let current = NoteDocument(relativePath: "A.md", rawContent: raw)
            let before = current.sourceBytes
            let anchors = ParagraphAnchorPlanner.anchors(in: current, semantic: stale)
            #expect(anchors == ParagraphAnchorPlanner.anchors(in: current))
            #expect(!anchors.contains { $0.id == "old" })
            if let markerRange = raw.range(of: "^current") {
                let anchor = try #require(anchors.first)
                #expect(anchor.id == "current")
                let lowerByte = raw.utf8.distance(from: raw.utf8.startIndex, to: markerRange.lowerBound)
                let upperByte = raw.utf8.distance(from: raw.utf8.startIndex, to: markerRange.upperBound)
                #expect(anchor.markerSpan.utf8Range == lowerByte..<upperByte)
                #expect((raw as NSString).substring(with: anchor.paragraphSpan.nsRange) == "当前 🦉 e\u{301}. ^current")
            } else {
                #expect(anchors.isEmpty)
            }
            #expect(current.sourceBytes == before)
        }
    }

    @Test("A matching fingerprint cannot authorize malformed cached source coordinates")
    func malformedSuppliedProjection() throws {
        let document = NoteDocument(relativePath: "A.md", rawContent: "😀 Current. ^one\r\n\r\nTail.")
        let parsed = MarkdownSemanticDocument(parsing: document)
        let first = try #require(parsed.blocks.first)
        let tooLong = MarkdownSemanticDocument(
            parsing: .init(
                relativePath: "Other.md",
                rawContent: "# A much longer unrelated cached document heading\n\nWrong paragraph. ^wrong"))
        let splitSurrogate = SourceSpan(
            utf8LowerBound: first.span.utf8LowerBound, utf8UpperBound: first.span.utf8UpperBound,
            utf16LowerBound: 1, utf16UpperBound: first.span.utf16UpperBound,
            start: first.span.start, end: first.span.end)
        let wrongBytes = SourceSpan(
            utf8LowerBound: 1, utf8UpperBound: first.span.utf8UpperBound,
            utf16LowerBound: first.span.utf16LowerBound, utf16UpperBound: first.span.utf16UpperBound,
            start: first.span.start, end: first.span.end)
        let splitNewline = SourceSpan(
            utf8LowerBound: first.span.utf8LowerBound, utf8UpperBound: first.span.utf8UpperBound,
            utf16LowerBound: first.span.utf16LowerBound, utf16UpperBound: first.span.utf16UpperBound + 1,
            start: first.span.start, end: first.span.end)
        for blocks in [
            tooLong.blocks, [MarkdownBlock(kind: .paragraph, span: splitSurrogate)],
            [MarkdownBlock(kind: .paragraph, span: wrongBytes)], [MarkdownBlock(kind: .paragraph, span: splitNewline)],
        ] {
            let forged = MarkdownSemanticDocument(
                fingerprint: document.fingerprint, blocks: blocks, headings: [], callouts: [],
                footnoteDefinitions: [], footnoteReferences: [], mathExpressions: [], links: [], diagnostics: [])
            #expect(
                ParagraphAnchorPlanner.anchors(in: document, semantic: forged)
                    == ParagraphAnchorPlanner.anchors(in: document))
        }
    }

    @Test("Adding an identity preserves BOM, CRLF, Unicode, frontmatter, and final-newline state")
    func exactSourceInsertion() throws {
        let raw = "\u{FEFF}---\r\nx: 'untouched' # comment\r\n---\r\nA 🧭 e\u{301}.\r\n\r\nLast"
        let note = NoteDocument(relativePath: "A.md", rawContent: raw)
        let position = (raw as NSString).range(of: "🧭").location
        let result = try ParagraphAnchorPlanner.ensureAnchor(in: note, atUTF16: position, id: "first")
        #expect(result.candidateSource == raw.replacingOccurrences(of: "A 🧭 e\u{301}.", with: "A 🧭 e\u{301}. ^first"))
        #expect(result.edits.count == 1)
        let changed = NoteDocument(relativePath: "A.md", rawContent: result.candidateSource)
        let again = try ParagraphAnchorPlanner.ensureAnchor(in: changed, atUTF16: position, id: "unused")
        #expect(again.anchorID == "first")
        #expect(again.edits.isEmpty)
        #expect(again.candidateSource.utf8.elementsEqual(result.candidateSource.utf8))
    }

    @Test("Edited prose retains identity; duplicate identities remain ambiguous")
    func navigationUsesCurrentContent() throws {
        let vault = UUID()
        let note = NoteDocument(relativePath: "A.md", rawContent: "Revised paragraph. ^same\n\nOther.")
        let noteID = VaultQualifiedNoteID(vaultID: vault, relativePath: "A.md")
        let catalog = LinkResolutionCatalog(catalog: [LinkCatalogNote(vaultID: vault, document: note)])
        guard case .resolved(let target) = catalog.resolveNavigation(target: "A", fragment: "^same", from: noteID) else {
            Issue.record("Expected current paragraph target")
            return
        }
        let span = try #require(target.span)
        #expect((note.rawContent as NSString).substring(with: span.nsRange) == "Revised paragraph. ^same")
        let duplicate = NoteDocument(relativePath: "A.md", rawContent: "One. ^same\n\nTwo. ^same")
        let ambiguous = LinkResolutionCatalog(catalog: [LinkCatalogNote(vaultID: vault, document: duplicate)])
        #expect(ambiguous.resolveNavigation(target: "A", fragment: "^same", from: noteID) == .ambiguousBlock)
        #expect(throws: ParagraphAnchorError.duplicateIdentifier("same")) {
            try ParagraphAnchorPlanner.ensureAnchor(in: duplicate, atUTF16: 1)
        }
    }

    @Test("Protected syntax never creates paragraph targets")
    func protectedSource() {
        for raw in [
            "- Listed ^no", "> Quoted ^no", "```\nCode ^no\n```", "    Code ^no", "`code ^no`", "%% Hidden ^no", "%%\n\nHidden ^no\n\n%%", "$$\nx ^no\n$$",
            "[^1]: Definition ^no",
        ] {
            let note = NoteDocument(relativePath: "A.md", rawContent: raw)
            #expect(ParagraphAnchorPlanner.anchors(in: note).isEmpty, "Unexpected target in \(raw)")
        }
        for raw in ["- Listed paragraph", "> Quoted paragraph", "# Heading", "```\nCode\n```"] {
            let note = NoteDocument(relativePath: "A.md", rawContent: raw)
            #expect(throws: ParagraphAnchorError.unsupportedParagraph) {
                try ParagraphAnchorPlanner.ensureAnchor(in: note, atUTF16: raw.utf16.count - 1)
            }
        }
    }

    @Test("A standalone identifier moves with its paragraph and is concealed in Review")
    func standaloneAnchor() throws {
        let note = NoteDocument(relativePath: "A.md", rawContent: "Paragraph.\r\n\r\n^one\r\n\r\nFollowing.")
        let span = try ParagraphAnchorPlanner.paragraph(in: note, atUTF16: 1)
        #expect((note.rawContent as NSString).substring(with: span.nsRange) == "Paragraph.\r\n\r\n^one")
        let rendered = SafeMarkdownRenderer.render(note).htmlBody
        #expect(!rendered.contains("^one"))
        #expect(rendered.contains("Following."))
        let followingOffset = (note.rawContent as NSString).range(of: "Following.").location
        #expect(rendered.contains("data-source-utf16-start=\"\(followingOffset)\""))
    }

    @Test("Copying remints selected identities and their local references in one exact plan")
    func copyIdentity() throws {
        let raw = "Original. ^one\n\n[[#^one|local]]\n\nOutside."
        let note = NoteDocument(relativePath: "A.md", rawContent: raw)
        let range = 0..<((raw as NSString).range(of: "Outside.").location - 2)
        let edits = try ParagraphAnchorPlanner.remintAnchors(in: note, within: range, idProvider: { _ in "copy-one" })
        let result = try AgentSourceEdit.applying(edits, to: note.sourceBytes)
        #expect(result == "Original. ^copy-one\n\n[[#^copy-one|local]]\n\nOutside.")
        #expect(throws: ParagraphAnchorError.partialAnchor) {
            try ParagraphAnchorPlanner.remintAnchors(in: note, within: 0..<4)
        }
    }

    @Test("Search keeps decoded prose and exact current locators while excluding identity syntax")
    func searchExcludesIdentity() {
        let note = NoteDocument(relativePath: "A.md", rawContent: "A &amp; B claim. ^one\n\nNext.")
        let projection = SearchDocumentProjection(document: note)
        #expect(projection.body.contains("A & B claim."))
        #expect(projection.body.contains("Next."))
        #expect(!projection.body.contains("^one"))
        let body = projection.segments.first { $0.field == .body }
        #expect(body?.sourceRange?.utf16LowerBound == 0)
    }

    @Test("Block previews and embeds include only the current referenced paragraph")
    func boundedPreview() throws {
        let vault = UUID()
        let source = NoteDocument(relativePath: "A.md", rawContent: "![[B#^one]] [[B#^one]]")
        let target = NoteDocument(relativePath: "B.md", rawContent: "Before.\n\nCurrent **claim**. ^one\n\nAfter.")
        let sourceID = VaultQualifiedNoteID(vaultID: vault, relativePath: "A.md")
        let targetID = VaultQualifiedNoteID(vaultID: vault, relativePath: "B.md")
        let graph = LinkGraphBuilder.build(
            generation: 1,
            catalog: [
                LinkCatalogNote(vaultID: vault, document: source), LinkCatalogNote(vaultID: vault, document: target),
            ], documents: [sourceID: MarkdownSemanticDocument(parsing: source), targetID: MarkdownSemanticDocument(parsing: target)])
        let previews = DocumentPreviewCatalogBuilder.build(
            source: sourceID, sourceFingerprint: source.fingerprint, graph: graph, documents: [sourceID: source, targetID: target])
        #expect(previews.links.count == 2)
        for preview in previews.links {
            #expect(preview.htmlBody.contains("Current <strong>claim</strong>."))
            #expect(!preview.htmlBody.contains("Before."))
            #expect(!preview.htmlBody.contains("After."))
            #expect(!preview.htmlBody.contains("^one"))
        }
    }
}
