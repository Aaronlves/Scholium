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

        #expect(ResearchActionSelectionCapture.anchor(
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
            ResearchActionSelectionCapture.anchor(
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

        #expect(ResearchActionSelectionCapture.anchor(
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

        let anchor = try #require(ResearchActionSelectionCapture.anchor(
            for: selection,
            in: source,
            relativePath: "Topic.md"
        ))
        #expect(anchor.line == 4)
        #expect(anchor.endLine == 4)
    }

    @Test("An ambiguous Comment selection retains its safe rendered source block")
    func ambiguousCommentSelectionUsesSourceBlock() throws {
        let repeated = String(repeating: "same context ", count: 8) + "target"
        let source = "# Topic\n\n\(repeated)\n\n\(repeated)\n"
        let selection = MarkdownReviewSelection(
            startLine: 5,
            endLine: 5,
            excerpt: "target",
            contextBefore: String(repeating: "same context ", count: 6),
            contextAfter: ""
        )

        #expect(ResearchActionSelectionCapture.anchor(
            for: selection,
            in: source,
            relativePath: "Topic.md"
        ) == nil)
        #expect(ResearchActionSelectionCapture.commentLineRange(
            for: selection,
            in: source,
            relativePath: "Topic.md"
        ) == 5 ... 5)
    }

    @Test("A Comment source-block fallback cannot exceed the current document")
    func invalidCommentSourceBlockIsRejected() {
        let source = "# Topic\n\nA claim.\n"
        let selection = MarkdownReviewSelection(
            startLine: 99,
            endLine: 99,
            excerpt: "ambiguous"
        )

        #expect(ResearchActionSelectionCapture.commentLineRange(
            for: selection,
            in: source,
            relativePath: "Topic.md"
        ) == nil)
    }
}
