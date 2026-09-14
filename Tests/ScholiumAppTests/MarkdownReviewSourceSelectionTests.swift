import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Chat selection source fidelity")
struct MarkdownReviewSourceSelectionTests {
    @Test("Review maps repeated Unicode by its exact block position, preserving CRLF")
    func exactSource() throws {
        let source = "\u{FEFF}# 原文\r\n\r\nsame 😀 same\r\n"
        let block = (source as NSString).range(of: "same 😀 same\r\n")
        let offsets = try #require(
            MarkdownReviewSourceSelection.exactReviewRange(
                blockLower: block.location,
                blockUpper: NSMaxRange(block), blockText: "same 😀 same", selectionLower: 8, selectionUpper: 12,
                excerpt: "same", source: source))
        let capture = try #require(
            MarkdownReviewSourceSelection.review(
                .init(
                    startLine: 3, endLine: 3, excerpt: "same", utf16LowerBound: offsets.lowerBound,
                    utf16UpperBound: offsets.upperBound), source: source))
        #expect(capture.source == source && capture.excerpt == "same")
        #expect(capture.sourceRange.line == 3 && capture.sourceRange.column == 9)
    }
    @Test("Review locates selected prose before a hidden identity and carries it only with the whole paragraph")
    func anchoredParagraphSelection() throws {
        let text = "Alpha passage for reorganization."
        let source = text + " ^2a97d9c8-ab7e-4af2-9b29-bb745cf8dd0b\n"
        let span = try ParagraphAnchorPlanner.paragraph(in: .init(relativePath: "QA.md", rawContent: source), atUTF16: 0)
        for rendered in [text, text + " "] {
            let offsets = try #require(
                MarkdownReviewSourceSelection.exactReviewRange(
                    blockLower: 0, blockUpper: span.utf16UpperBound,
                    blockText: rendered, selectionLower: 0, selectionUpper: rendered.utf16.count,
                    excerpt: text, source: source))
            #expect(offsets == 0..<text.utf16.count)
            let selection = MarkdownReviewSelection(
                startLine: 1, endLine: 1, excerpt: text,
                utf16LowerBound: offsets.lowerBound, utf16UpperBound: offsets.upperBound)
            let snapshot = try #require(MarkdownReviewSourceSelection.passage(selection, source: source, paragraphSpan: span))
            #expect(snapshot.sourceRange.utf16UpperBound == span.utf16UpperBound)
            #expect(snapshot.excerpt == text + " ^2a97d9c8-ab7e-4af2-9b29-bb745cf8dd0b")
        }
        let partial = MarkdownReviewSelection(startLine: 1, endLine: 1, excerpt: "Alpha", utf16LowerBound: 0, utf16UpperBound: 5)
        let partialSnapshot = try #require(MarkdownReviewSourceSelection.passage(partial, source: source, paragraphSpan: span))
        #expect(partialSnapshot.excerpt == "Alpha")
        #expect(partialSnapshot.sourceRange.utf16UpperBound == 5)
    }

    @Test("Hidden identity mapping keeps repeated paragraphs separate and rejects forged rendered text")
    func anchoredRepeatedText() throws {
        let source = "Same 😀. ^first\r\n\r\nSame 😀. ^second\r\n"
        let lower = (source as NSString).range(of: "Same 😀.", options: .backwards).location
        let span = try ParagraphAnchorPlanner.paragraph(in: .init(relativePath: "QA.md", rawContent: source), atUTF16: lower)
        let offsets = try #require(
            MarkdownReviewSourceSelection.exactReviewRange(
                blockLower: lower, blockUpper: span.utf16UpperBound,
                blockText: "Same 😀.", selectionLower: 0, selectionUpper: "Same 😀.".utf16.count,
                excerpt: "Same 😀.", source: source))
        #expect(offsets.lowerBound == lower)
        #expect(
            MarkdownReviewSourceSelection.exactReviewRange(
                blockLower: lower, blockUpper: span.utf16UpperBound,
                blockText: "Forged", selectionLower: 0, selectionUpper: 6, excerpt: "Forged", source: source) == nil)
        let code = "`Same ^id`"
        #expect(
            MarkdownReviewSourceSelection.exactReviewRange(
                blockLower: 0, blockUpper: code.utf16.count, blockText: "Same", selectionLower: 0,
                selectionUpper: 4, excerpt: "Same", source: code) == nil)
    }

    @Test("Rendered-only text cannot find itself in hidden Markdown destinations or another source revision")
    func rejectedSelections() {
        #expect(
            MarkdownReviewSourceSelection.exactReviewRange(
                blockLower: 0, blockUpper: 2,
                blockText: "é", selectionLower: 0, selectionUpper: 1, excerpt: "é", source: "e\u{301}") == nil)
        let raw = "[some **thing**](some thing)"
        #expect(
            MarkdownReviewSourceSelection.exactReviewRange(
                blockLower: 0, blockUpper: raw.utf16.count,
                blockText: "some thing", selectionLower: 0, selectionUpper: 10, excerpt: "some thing", source: raw) == nil)
        #expect(MarkdownReviewSourceSelection.review(.init(startLine: 1, endLine: 1, excerpt: "same"), source: "same same") == nil)
        #expect(
            MarkdownReviewSourceSelection.review(
                .init(
                    startLine: 1, endLine: 1, excerpt: "old", utf16LowerBound: 0,
                    utf16UpperBound: 3), source: "new") == nil)
    }
}
