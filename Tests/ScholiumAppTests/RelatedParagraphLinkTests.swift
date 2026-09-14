import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Related paragraph links")
struct RelatedParagraphLinkTests {
    private func card(_ document: NoteDocument, paragraph index: Int = 0, span supplied: SourceSpan? = nil) -> RelatedMaterialCard {
        let span = supplied ?? MarkdownSemanticDocument(parsing: document).blocks.filter { $0.kind == .paragraph }[index].span
        let vault = UUID()
        let source = (document.rawContent as NSString).substring(with: span.nsRange)
        return .init(
            passage: .init(
                candidate: .init(
                    note: .init(vaultID: vault, relativePath: document.relativePath), vaultRole: .topicKnowledge,
                    title: "Source", fingerprint: document.fingerprint,
                    reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: []))),
                range: .init(
                    utf16LowerBound: span.utf16LowerBound, utf16UpperBound: span.utf16UpperBound,
                    line: span.start.line, column: span.start.utf16Column, endLine: span.end.line, endColumn: span.end.utf16Column),
                source: source, displayText: source, excerpt: "bounded excerpt", excerptMatches: [], matches: []),
            reference: .init(
                vaultID: vault, vaultName: "Topics", vaultRole: .topicKnowledge,
                relativePath: document.relativePath, stableNoteID: UUID().uuidString), linkTarget: "Source")
    }

    @Test("Repeated paragraphs use the exact retrieved position and preserve all surrounding bytes")
    func repeatedParagraphs() throws {
        let source = "\u{FEFF}---\r\ncustom: 'untouched'\r\n---\r\n自由与理由。\r\n\r\n自由与理由。\r\n"
        let document = NoteDocument(relativePath: "Source.md", rawContent: source)
        let result = try RelatedParagraphLink.plan(for: card(document, paragraph: 1), in: document)
        #expect(
            result.candidateSource
                == source.replacingOccurrences(
                    of: "自由与理由。\r\n", with: "自由与理由。 ^\(result.anchorID)\r\n", range: source.range(of: "自由与理由。\r\n", options: .backwards)!))
        try RelatedParagraphLink.verify(result, saved: .init(relativePath: "Source.md", rawContent: result.candidateSource))
    }

    @Test("Both inline and detached existing anchors are reused", arguments: ["Reasons matter. ^stable\n", "Reasons matter.\n\n^stable\n"])
    func existingAnchor(_ source: String) throws {
        let document = NoteDocument(relativePath: "Source.md", rawContent: source)
        let result = try RelatedParagraphLink.plan(for: card(document), in: document)
        #expect(result.anchorID == "stable" && result.edits.isEmpty)
        try RelatedParagraphLink.verify(result, saved: document)
    }

    @Test("Stale fingerprints and partial passage ranges cannot create an anchor")
    func staleAndPartial() throws {
        let document = NoteDocument(relativePath: "Source.md", rawContent: "Reasons matter.\n")
        let original = card(document)
        #expect(throws: RelatedMaterialsError.changedSource) {
            try RelatedParagraphLink.plan(for: original, in: .init(relativePath: "Source.md", rawContent: "Reasons matter.\n\nChanged."))
        }
        let passage = original.passage
        let partial = RelatedMaterialCard(
            passage: .init(
                candidate: passage.candidate,
                range: .init(utf16LowerBound: 0, utf16UpperBound: 7, line: 1, column: 1, endLine: 1, endColumn: 8),
                source: "Reasons", displayText: "Reasons", excerpt: "Reasons", excerptMatches: [], matches: []), reference: original.reference)
        #expect(throws: RelatedMaterialsError.changedSource) { try RelatedParagraphLink.plan(for: partial, in: document) }
    }

    @Test("Container passages remain readable but cannot authorize ordinary paragraph anchors", arguments: ["> Reasons matter.\n", "- Reasons matter.\n"])
    func protectedParagraph(_ source: String) throws {
        let document = NoteDocument(relativePath: "Source.md", rawContent: source)
        #expect(throws: ParagraphAnchorError.unsupportedParagraph) { try RelatedParagraphLink.plan(for: card(document), in: document) }
    }

    @Test("Saved verification refuses any intervening edit, even if the anchor survives")
    func changedAfterSave() throws {
        let document = NoteDocument(relativePath: "Source.md", rawContent: "Reasons matter.\n")
        let result = try RelatedParagraphLink.plan(for: card(document), in: document)
        #expect(throws: RelatedMaterialsError.changedSource) {
            try RelatedParagraphLink.verify(result, saved: .init(relativePath: "Source.md", rawContent: result.candidateSource + "\nAnother writer."))
        }
    }
}
