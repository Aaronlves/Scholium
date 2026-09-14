import Foundation
import ScholiumContracts

/// Retrieval locators are checked against complete current source before they
/// may authorize an authored identity. Readable excerpts never locate a paragraph.
enum RelatedParagraphLink {
    static func plan(for card: RelatedMaterialCard, in document: NoteDocument) throws -> ParagraphAnchorPlan {
        let passage = card.passage
        guard document.fingerprint == card.candidate.fingerprint,
            document.relativePath == card.candidate.note.relativePath,
            card.reference.vaultID == card.candidate.note.vaultID,
            card.reference.relativePath == document.relativePath,
            let block = MarkdownSemanticDocument(parsing: document).blocks.first(where: {
                $0.kind == .paragraph && $0.span.utf16LowerBound == passage.range.utf16LowerBound
                    && $0.span.utf16UpperBound == passage.range.utf16UpperBound
                    && $0.span.start.line == passage.range.line && $0.span.start.utf16Column == passage.range.column
                    && $0.span.end.line == passage.range.endLine && $0.span.end.utf16Column == passage.range.endColumn
            }),
            let range = Range(block.span.nsRange, in: document.rawContent),
            document.rawContent[range].utf8.elementsEqual(passage.source.utf8)
        else { throw RelatedMaterialsError.changedSource }
        return try ParagraphAnchorPlanner.ensureAnchor(in: document, atUTF16: block.span.utf16LowerBound)
    }

    static func verify(_ plan: ParagraphAnchorPlan, saved: NoteDocument) throws {
        let anchors = ParagraphAnchorPlanner.anchors(in: saved).filter { $0.id == plan.anchorID }
        guard saved.rawContent.utf8.elementsEqual(plan.candidateSource.utf8),
            anchors.count == 1, anchors.first?.paragraphSpan == plan.paragraphSpan
        else { throw RelatedMaterialsError.changedSource }
    }
}
