import Foundation
import ScholiumContracts

/// A rendered block must equal its exact source span before DOM offsets can map.
/// Formatted or synthesized text never locates itself by searching authored prose.
enum MarkdownReviewSourceSelection {
  static func exactReviewRange(blockLower: Int, blockUpper: Int, blockText: String,
    selectionLower: Int, selectionUpper: Int, excerpt: String, source: String) -> Range<Int>? {
    guard blockLower >= 0, blockUpper >= blockLower, blockUpper <= source.utf16.count,
      blockText.utf16.count <= 64_000, selectionLower >= 0, selectionUpper > selectionLower,
      selectionUpper <= blockText.utf16.count,
      let block = Range(NSRange(location: blockLower, length: blockUpper - blockLower), in: source)
    else { return nil }
    // The Markdown block span can include its terminating newline. It is not
    // part of the rendered paragraph; all internal bytes must still match.
    let raw = String(source[block]).trimmingCharacters(in: .newlines)
    guard raw.utf8.elementsEqual(blockText.utf8), !source[block].hasPrefix("\n"), !source[block].hasPrefix("\r"),
      let selected = Range(NSRange(location: selectionLower, length: selectionUpper - selectionLower), in: blockText),
      blockText[selected].utf8.elementsEqual(excerpt.utf8) else { return nil }
    return (blockLower + selectionLower)..<(blockLower + selectionUpper)
  }

  static func review(_ selection: MarkdownReviewSelection, source: String) -> MarkdownSourceSelectionSnapshot? {
    guard let offsets = selection.exactUTF16Range, offsets.lowerBound >= 0,
      offsets.upperBound <= source.utf16.count, offsets.count <= 32_000,
      let range = Range(NSRange(location: offsets.lowerBound, length: offsets.count), in: source),
      source[range].utf8.elementsEqual(selection.excerpt.utf8) else { return nil }
    let native = source as NSString
    let sourceRange = SearchSourceRange(utf16LowerBound: offsets.lowerBound, utf16UpperBound: offsets.upperBound,
      line: 1 + source[..<range.lowerBound].utf8.filter { $0 == 10 }.count,
      column: offsets.lowerBound - native.lineRange(for: NSRange(location: offsets.lowerBound, length: 0)).location + 1,
      endLine: 1 + source[..<range.upperBound].utf8.filter { $0 == 10 }.count,
      endColumn: offsets.upperBound - native.lineRange(for: NSRange(location: offsets.upperBound, length: 0)).location + 1)
    return .init(source: source, excerpt: String(source[range]), sourceRange: sourceRange)
  }
}
