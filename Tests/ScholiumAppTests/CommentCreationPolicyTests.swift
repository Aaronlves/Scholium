import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Passage Comment selection policy")
struct CommentCreationPolicyTests {
    @Test("A Comment cannot be created without a selected passage")
    func missingSelectionHasNoAnchor() {
        let note = WindowDocumentLocation.unclassified(NoteDocument(
            relativePath: "Analysis.md",
            rawContent: "# Analysis\n\nA bounded claim.\n"
        ))

        #expect(ResearchFunctionSelectionCapture.anchor(
            for: nil,
            in: note.document.rawContent,
            relativePath: note.relativePath
        ) == nil)
    }

    @Test("An exact editor selection creates a fingerprint-bound anchor")
    func exactSelectionCreatesAnchor() throws {
        let source = "# Analysis\n\nA bounded claim.\n"
        let selectedText = "bounded claim"
        let selectedRange = (source as NSString).range(of: selectedText)
        let note = WindowDocumentLocation.unclassified(NoteDocument(
            relativePath: "Analysis.md",
            rawContent: source
        ))
        let selection = MarkdownReviewSelection(
            startLine: 3,
            endLine: 3,
            excerpt: selectedText,
            utf16LowerBound: selectedRange.location,
            utf16UpperBound: NSMaxRange(selectedRange)
        )

        let anchor = try #require(
            ResearchFunctionSelectionCapture.anchor(
                for: selection,
                in: note.document.rawContent,
                relativePath: note.relativePath
            )
        )
        #expect(anchor.fingerprint == note.document.fingerprint)
        #expect(anchor.quotation == selectedText)
        #expect(anchor.utf16Range == selectedRange.location..<NSMaxRange(selectedRange))
    }

    @Test("An ambiguous rendered selection does not create a Comment anchor")
    func ambiguousRenderedSelectionHasNoAnchor() {
        let note = WindowDocumentLocation.unclassified(NoteDocument(
            relativePath: "Topic.md",
            rawContent: "# Topic\n\nA claim.\n\nA claim.\n"
        ))
        let selection = MarkdownReviewSelection(
            startLine: 3,
            endLine: 5,
            excerpt: "A claim."
        )

        #expect(ResearchFunctionSelectionCapture.anchor(
            for: selection,
            in: note.document.rawContent,
            relativePath: note.relativePath
        ) == nil)
    }
}
