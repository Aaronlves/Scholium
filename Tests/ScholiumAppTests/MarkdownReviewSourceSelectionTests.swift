import Foundation
import Testing
@testable import ScholiumApp

@Suite("Chat selection source fidelity")
struct MarkdownReviewSourceSelectionTests {
  @Test("Review maps repeated Unicode by its exact block position, preserving CRLF")
  func exactSource() throws {
    let source = "\u{FEFF}# 原文\r\n\r\nsame 😀 same\r\n"
    let block = (source as NSString).range(of: "same 😀 same\r\n")
    let offsets = try #require(MarkdownReviewSourceSelection.exactReviewRange(blockLower: block.location,
      blockUpper: NSMaxRange(block), blockText: "same 😀 same", selectionLower: 8, selectionUpper: 12,
      excerpt: "same", source: source))
    let capture = try #require(MarkdownReviewSourceSelection.review(
      .init(startLine: 3, endLine: 3, excerpt: "same", utf16LowerBound: offsets.lowerBound,
        utf16UpperBound: offsets.upperBound), source: source))
    #expect(capture.source == source && capture.excerpt == "same")
    #expect(capture.sourceRange.line == 3 && capture.sourceRange.column == 9)
  }
  @Test("Rendered-only text cannot find itself in hidden Markdown destinations or another source revision")
  func rejectedSelections() {
    #expect(MarkdownReviewSourceSelection.exactReviewRange(blockLower: 0, blockUpper: 2,
      blockText: "é", selectionLower: 0, selectionUpper: 1, excerpt: "é", source: "e\u{301}") == nil)
    let raw = "[some **thing**](some thing)"
    #expect(MarkdownReviewSourceSelection.exactReviewRange(blockLower: 0, blockUpper: raw.utf16.count,
      blockText: "some thing", selectionLower: 0, selectionUpper: 10, excerpt: "some thing", source: raw) == nil)
    #expect(MarkdownReviewSourceSelection.review(.init(startLine: 1, endLine: 1, excerpt: "same"), source: "same same") == nil)
    #expect(MarkdownReviewSourceSelection.review(.init(startLine: 1, endLine: 1, excerpt: "old", utf16LowerBound: 0,
      utf16UpperBound: 3), source: "new") == nil)
  }
}
