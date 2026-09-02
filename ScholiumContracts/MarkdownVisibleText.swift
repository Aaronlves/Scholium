import Foundation
import Markdown

/// Produces the text a reader sees after Markdown syntax is removed. Search
/// uses this projection only for result presentation; source locations and
/// writes continue to use the exact Markdown bytes.
public enum MarkdownVisibleText {
    public static func render(_ source: String) -> String {
        let parsed = Document(parsing: source)
        var collector = MarkdownRenderedTextCollector(source: source)
        collector.visit(parsed)
        return collector.renderedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct MarkdownRenderedTextFragment {
    let renderedRange: Range<Int>
    let sourceRange: Range<Int>?
    let exact: Bool
}

private struct MarkdownRenderedTextCollector: MarkupWalker {
    private let source: String
    private let mapper: MarkdownRenderedSourceMapper
    private(set) var renderedText = ""
    private var fragments: [MarkdownRenderedTextFragment] = []

    init(source: String) {
        self.source = source
        mapper = MarkdownRenderedSourceMapper(source)
    }

    mutating func visitDocument(_ document: Document) { descendInto(document) }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        descendInto(paragraph)
        appendSeparator("\n")
    }

    mutating func visitHeading(_ heading: Heading) {
        descendInto(heading)
        appendSeparator("\n")
    }

    mutating func visitText(_ text: Markdown.Text) {
        append(text.string, sourceRange: text.range)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        append(inlineCode.code, sourceRange: inlineCode.range)
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) { appendSeparator("\n") }
    mutating func visitLineBreak(_ lineBreak: LineBreak) { appendSeparator("\n") }

    mutating func visitImage(_ image: Image) {
        if let title = image.title, !title.isEmpty {
            append(title, sourceRange: image.range)
        }
    }

    func sourceRange(for renderedRange: Range<String.Index>) -> Range<Int>? {
        let lower = renderedRange.lowerBound.utf16Offset(in: renderedText)
        let upper = renderedRange.upperBound.utf16Offset(in: renderedText)
        let overlapping = fragments.filter {
            $0.sourceRange != nil
                && $0.renderedRange.lowerBound < upper
                && $0.renderedRange.upperBound > lower
        }
        guard let first = overlapping.first,
              let last = overlapping.last,
              let firstSource = first.sourceRange,
              let lastSource = last.sourceRange else { return nil }

        let sourceLower: Int
        if first.exact {
            sourceLower = firstSource.lowerBound + max(0, lower - first.renderedRange.lowerBound)
        } else {
            sourceLower = firstSource.lowerBound
        }
        let sourceUpper: Int
        if last.exact {
            sourceUpper = lastSource.lowerBound
                + min(lastSource.count, upper - last.renderedRange.lowerBound)
        } else {
            sourceUpper = lastSource.upperBound
        }
        guard sourceUpper > sourceLower else { return nil }
        return sourceLower..<sourceUpper
    }

    func renderedText(forSourceRange sourceRange: Range<Int>) -> String? {
        let overlapping = fragments.filter {
            guard let fragmentSource = $0.sourceRange else { return false }
            return fragmentSource.lowerBound < sourceRange.upperBound
                && fragmentSource.upperBound > sourceRange.lowerBound
        }
        guard let first = overlapping.first,
              let last = overlapping.last,
              let firstSource = first.sourceRange,
              let lastSource = last.sourceRange else { return nil }

        let renderedLower = first.exact
            ? first.renderedRange.lowerBound
                + max(0, sourceRange.lowerBound - firstSource.lowerBound)
            : first.renderedRange.lowerBound
        let renderedUpper = last.exact
            ? last.renderedRange.lowerBound
                + min(last.renderedRange.count, sourceRange.upperBound - lastSource.lowerBound)
            : last.renderedRange.upperBound
        guard renderedUpper > renderedLower else { return nil }
        let nsRendered = renderedText as NSString
        let result = nsRendered.substring(with: NSRange(
            location: renderedLower,
            length: renderedUpper - renderedLower
        )).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private mutating func append(_ text: String, sourceRange: Markdown.SourceRange?) {
        guard !text.isEmpty else { return }
        let renderedStart = renderedText.utf16.count
        renderedText += text
        let renderedEnd = renderedText.utf16.count
        guard var range = sourceRange.flatMap(mapper.utf16Range) else {
            fragments.append(MarkdownRenderedTextFragment(
                renderedRange: renderedStart..<renderedEnd,
                sourceRange: nil,
                exact: false
            ))
            return
        }
        let nsSource = source as NSString
        let raw = nsSource.substring(with: NSRange(
            location: range.lowerBound,
            length: range.count
        ))
        if raw != text,
           let match = raw.range(of: text),
           raw.range(of: text, range: match.upperBound..<raw.endIndex) == nil {
            let lower = match.lowerBound.utf16Offset(in: raw)
            let upper = match.upperBound.utf16Offset(in: raw)
            range = (range.lowerBound + lower)..<(range.lowerBound + upper)
        }
        let exact = (source as NSString).substring(with: NSRange(
            location: range.lowerBound,
            length: range.count
        )) == text
        fragments.append(MarkdownRenderedTextFragment(
            renderedRange: renderedStart..<renderedEnd,
            sourceRange: range,
            exact: exact
        ))
    }

    private mutating func appendSeparator(_ separator: String) {
        guard !renderedText.hasSuffix(separator) else { return }
        let start = renderedText.utf16.count
        renderedText += separator
        fragments.append(MarkdownRenderedTextFragment(
            renderedRange: start..<renderedText.utf16.count,
            sourceRange: nil,
            exact: false
        ))
    }
}

private struct MarkdownRenderedSourceMapper {
    let source: String
    let lineStarts: [Int]

    init(_ source: String) {
        self.source = source
        let nsSource = source as NSString
        var starts = [0]
        var offset = 0
        while offset < nsSource.length {
            let value = nsSource.character(at: offset)
            if value == 13 {
                if offset + 1 < nsSource.length, nsSource.character(at: offset + 1) == 10 {
                    offset += 1
                }
                starts.append(offset + 1)
            } else if value == 10 {
                starts.append(offset + 1)
            }
            offset += 1
        }
        lineStarts = starts
    }

    func utf16Range(_ range: Markdown.SourceRange) -> Range<Int>? {
        guard let lower = utf16Offset(
            line: range.lowerBound.line,
            utf8Column: range.lowerBound.column
        ), let upper = utf16Offset(
            line: range.upperBound.line,
            utf8Column: range.upperBound.column
        ), upper >= lower else { return nil }
        return lower..<upper
    }

    private func utf16Offset(line: Int, utf8Column: Int) -> Int? {
        guard line > 0, line <= lineStarts.count else { return nil }
        let lineStart = lineStarts[line - 1]
        let nsSource = source as NSString
        let lineRange = nsSource.lineRange(for: NSRange(location: lineStart, length: 0))
        let lineText = nsSource.substring(with: lineRange)
        let byteOffset = max(0, utf8Column - 1)
        guard byteOffset <= lineText.utf8.count else { return nil }
        let byteIndex = lineText.utf8.index(lineText.utf8.startIndex, offsetBy: byteOffset)
        guard let index = String.Index(byteIndex, within: lineText) else { return nil }
        return lineStart + index.utf16Offset(in: lineText)
    }
}
