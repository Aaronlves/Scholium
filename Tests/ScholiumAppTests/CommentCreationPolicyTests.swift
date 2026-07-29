import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Research Action passage-selection policy")
struct CommentCreationPolicyTests {
    @Test("A passage parameter cannot be created without a selection")
    func missingSelectionHasNoAnchor() {
        let note = WindowDocumentLocation.syntheticPreview(
            relativePath: "Analysis.md",
            rawContent: "# Analysis\n\nA bounded claim.\n"
        )

        #expect(ResearchFunctionSelectionCapture.anchor(
            for: nil,
            in: note.document.rawContent,
            relativePath: note.relativePath
        ) == nil)
    }

    @Test("An exact editor selection creates a fingerprint-bound Action anchor")
    func exactSelectionCreatesAnchor() throws {
        let source = "# Analysis\n\nA bounded claim.\n"
        let selectedText = "bounded claim"
        let selectedRange = (source as NSString).range(of: selectedText)
        let note = WindowDocumentLocation.syntheticPreview(
            relativePath: "Analysis.md",
            rawContent: source
        )
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

    @Test("An ambiguous rendered selection does not create an Action anchor")
    func ambiguousRenderedSelectionHasNoAnchor() {
        let note = WindowDocumentLocation.syntheticPreview(
            relativePath: "Topic.md",
            rawContent: "# Topic\n\nA claim.\n\nA claim.\n"
        )
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

    @Test("A rendered selection resolves its actual Markdown source line")
    func renderedSelectionResolvesSourceLine() throws {
        let source = "# Topic\n\nFirst part of one paragraph\nsecond distinct line.\n"
        let selection = MarkdownReviewSelection(
            startLine: 3,
            endLine: 3,
            excerpt: "second distinct line.",
            contextBefore: "paragraph ",
            contextAfter: ""
        )

        let anchor = try #require(ResearchFunctionSelectionCapture.anchor(
            for: selection,
            in: source,
            relativePath: "Topic.md"
        ))
        #expect(anchor.line == 4)
        #expect(anchor.endLine == 4)
    }
}
