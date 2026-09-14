import Foundation
import ScholiumContracts

/// A rendered block must match its exact source projection before DOM offsets map.
/// Only parser-owned trailing identities and boundary whitespace are omitted;
/// formatted or synthesized text never locates itself by searching authored prose.
enum MarkdownReviewSourceSelection {
    static func exactReviewRange(
        blockLower: Int, blockUpper: Int, blockText: String,
        selectionLower: Int, selectionUpper: Int, excerpt: String, source: String
    ) -> Range<Int>? {
        guard blockLower >= 0, blockUpper >= blockLower, blockUpper <= source.utf16.count,
            blockText.utf16.count <= 64_000, selectionLower >= 0, selectionUpper > selectionLower,
            selectionUpper <= blockText.utf16.count,
            let block = Range(NSRange(location: blockLower, length: blockUpper - blockLower), in: source)
        else { return nil }
        guard !source[block].hasPrefix("\n"), !source[block].hasPrefix("\r") else { return nil }
        var raw = String(source[block]).trimmingCharacters(in: .newlines)
        let note = NoteDocument(relativePath: "Review.md", rawContent: source)
        let anchors = ParagraphAnchorPlanner.anchors(in: note).filter {
            $0.markerSpan.utf16LowerBound >= blockLower && $0.markerSpan.utf16UpperBound <= blockUpper
        }
        if let anchor = anchors.first {
            guard anchors.count == 1 else { return nil }
            let offset = anchor.markerSpan.utf16LowerBound - blockLower
            let markerEnd = anchor.markerSpan.utf16UpperBound - blockLower
            guard markerEnd <= raw.utf16.count,
                (raw as NSString).substring(from: markerEnd).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            raw = (raw as NSString).substring(to: offset)
        }
        // CommonMark omits trailing paragraph whitespace. Either exact DOM form
        // retains the same prefix coordinates; no interior transformation is accepted.
        guard
            raw.utf8.elementsEqual(blockText.utf8)
                || trimmingTrailingWhitespace(raw).utf8.elementsEqual(blockText.utf8),
            let selected = Range(NSRange(location: selectionLower, length: selectionUpper - selectionLower), in: blockText)
        else { return nil }
        let selectedText = String(blockText[selected])
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.elementsEqual(excerpt.utf8) else { return nil }
        // The reader bounds and trims its excerpt. Adjust only those known edge
        // characters, then verify the resulting source bytes independently.
        let leading = selectedText.prefix { $0.isWhitespace }.utf16.count
        let lower = blockLower + selectionLower + leading
        let upper = lower + trimmed.utf16.count
        guard let exact = Range(NSRange(location: lower, length: upper - lower), in: source),
            source[exact].utf8.elementsEqual(excerpt.utf8)
        else { return nil }
        return lower..<upper
    }

    /// Selecting all visible paragraph prose includes its hidden identity in a
    /// paragraph operation. A partial selection retains its exact original range.
    static func passage(
        _ selection: MarkdownReviewSelection,
        source: String,
        paragraphSpan: SourceSpan
    ) -> MarkdownSourceSelectionSnapshot? {
        guard let captured = review(selection, source: source) else { return nil }
        return DocumentPassageSnapshot.includingParagraphIdentity(captured, paragraphSpan: paragraphSpan)
    }

    private static func trimmingTrailingWhitespace(_ source: String) -> String {
        String(source.reversed().drop(while: { $0.isWhitespace }).reversed())
    }

    static func review(_ selection: MarkdownReviewSelection, source: String) -> MarkdownSourceSelectionSnapshot? {
        guard let offsets = selection.exactUTF16Range, offsets.lowerBound >= 0,
            offsets.upperBound <= source.utf16.count, offsets.count <= 32_000,
            let range = Range(NSRange(location: offsets.lowerBound, length: offsets.count), in: source),
            source[range].utf8.elementsEqual(selection.excerpt.utf8)
        else { return nil }
        let native = source as NSString
        let sourceRange = SearchSourceRange(
            utf16LowerBound: offsets.lowerBound, utf16UpperBound: offsets.upperBound,
            line: 1 + source[..<range.lowerBound].utf8.filter { $0 == 10 }.count,
            column: offsets.lowerBound - native.lineRange(for: NSRange(location: offsets.lowerBound, length: 0)).location + 1,
            endLine: 1 + source[..<range.upperBound].utf8.filter { $0 == 10 }.count,
            endColumn: offsets.upperBound - native.lineRange(for: NSRange(location: offsets.upperBound, length: 0)).location + 1)
        return .init(source: source, excerpt: String(source[range]), sourceRange: sourceRange)
    }
}
