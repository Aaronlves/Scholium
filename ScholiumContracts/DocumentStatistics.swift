import Foundation
import Markdown
import NaturalLanguage

public enum DocumentStatisticsScope: String, Codable, Hashable, Sendable {
    case body
    case selection
}

public struct DocumentStatistics: Codable, Hashable, Sendable {
    public let words: Int
    public let charactersWithSpaces: Int
    public let charactersWithoutSpaces: Int
    public let hanCharacters: Int
    public let scope: DocumentStatisticsScope

    public init(
        words: Int,
        charactersWithSpaces: Int,
        charactersWithoutSpaces: Int,
        hanCharacters: Int,
        scope: DocumentStatisticsScope
    ) {
        self.words = max(0, words)
        self.charactersWithSpaces = max(0, charactersWithSpaces)
        self.charactersWithoutSpaces = max(0, charactersWithoutSpaces)
        self.hanCharacters = max(0, hanCharacters)
        self.scope = scope
    }

    public static let emptyBody = DocumentStatistics(
        words: 0,
        charactersWithSpaces: 0,
        charactersWithoutSpaces: 0,
        hanCharacters: 0,
        scope: .body
    )
}

public enum DocumentStatisticsCalculator {
    public static func calculate(
        markdownSource: String,
        selectedUTF16Ranges: [Range<Int>] = []
    ) -> DocumentStatistics {
        let nonemptySelections = selectedUTF16Ranges.filter { !$0.isEmpty }
        let scope: DocumentStatisticsScope = nonemptySelections.isEmpty ? .body : .selection
        let document = NoteDocument(relativePath: "Statistics.md", rawContent: markdownSource)
        let bodyStart = markdownSource.utf16.count - document.body.utf16.count
        let selectedMarkdown: String
        if nonemptySelections.isEmpty {
            selectedMarkdown = document.body
        } else {
            let bodyRange = bodyStart..<markdownSource.utf16.count
            selectedMarkdown = nonemptySelections.compactMap { range -> String? in
                let lower = max(bodyRange.lowerBound, range.lowerBound)
                let upper = min(bodyRange.upperBound, range.upperBound)
                guard upper > lower else { return nil }
                return (markdownSource as NSString).substring(
                    with: NSRange(location: lower, length: upper - lower)
                )
            }.joined(separator: "\n")
        }
        return calculateVisibleMarkdown(selectedMarkdown, scope: scope)
    }

    public static func calculateVisibleText(
        _ text: String,
        scope: DocumentStatisticsScope
    ) -> DocumentStatistics {
        counts(in: text, scope: scope)
    }

    private static func calculateVisibleMarkdown(
        _ source: String,
        scope: DocumentStatisticsScope
    ) -> DocumentStatistics {
        var collector = StatisticsVisibleTextCollector()
        collector.visit(Document(parsing: source))
        return counts(in: collector.text, scope: scope)
    }

    private static func counts(
        in rawText: String,
        scope: DocumentStatisticsScope
    ) -> DocumentStatistics {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(location: 0, length: (text as NSString).length)
        return DocumentStatistics(
            words: wordCount(in: text),
            charactersWithSpaces: text.count,
            charactersWithoutSpaces: text.filter { !$0.isWhitespace }.count,
            hanCharacters: hanPattern.numberOfMatches(in: text, range: range),
            scope: scope
        )
    }

    private static func wordCount(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            count += 1
            return true
        }
        return count
    }

    private static let hanPattern = try! NSRegularExpression(pattern: #"\p{Han}"#)
}

private struct StatisticsVisibleTextCollector: MarkupWalker {
    private(set) var text = ""
    private var isInsideComment = false

    mutating func visitDocument(_ document: Document) { descendInto(document) }
    mutating func visitParagraph(_ paragraph: Paragraph) {
        descendInto(paragraph)
        appendSeparator()
    }
    mutating func visitHeading(_ heading: Heading) {
        descendInto(heading)
        appendSeparator()
    }
    mutating func visitText(_ node: Markdown.Text) {
        text += StatisticsCustomSyntax.visibleText(
            node.string,
            isInsideComment: &isInsideComment
        )
    }
    mutating func visitInlineCode(_ node: InlineCode) {
        if !isInsideComment { text += node.code }
    }
    mutating func visitCodeBlock(_ node: CodeBlock) {
        text += node.code
        appendSeparator()
    }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) { appendSeparator() }
    mutating func visitLineBreak(_ lineBreak: LineBreak) { appendSeparator() }
    mutating func visitImage(_ image: Image) { descendInto(image) }
    mutating func visitHTMLBlock(_ html: HTMLBlock) {}
    mutating func visitInlineHTML(_ html: InlineHTML) {}
    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {}

    private mutating func appendSeparator() {
        guard !isInsideComment,
              !text.isEmpty,
              text.last?.isWhitespace != true else { return }
        text.append("\n")
    }
}

private enum StatisticsCustomSyntax {
    static func visibleText(
        _ source: String,
        isInsideComment: inout Bool
    ) -> String {
        var result = textOutsideComments(source, isInsideComment: &isInsideComment)
        result = replacing(wikilinkPattern, in: result) { match, string in
            guard let contentRange = Range(match.range(at: 1), in: string) else { return "" }
            let content = String(string[contentRange])
            let parts = content.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            let target = String(parts[0].split(separator: "#", maxSplits: 1).first ?? "")
            let visible = parts.count == 2 ? String(parts[1]) : target
            return visible.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        result = replacing(calloutRolePattern, in: result) { _, _ in "" }
        result = replacing(footnoteReferencePattern, in: result) { match, string in
            guard let range = Range(match.range(at: 1), in: string) else { return "" }
            return String(string[range])
        }
        result = replacing(highlightPattern, in: result) { match, string in
            guard let range = Range(match.range(at: 1), in: string) else { return "" }
            return String(string[range])
        }
        result = replacing(displayMathPattern, in: result) { match, string in
            guard let range = Range(match.range(at: 1), in: string) else { return "" }
            return String(string[range])
        }
        result = replacing(inlineMathPattern, in: result) { match, string in
            guard let range = Range(match.range(at: 1), in: string) else { return "" }
            return String(string[range])
        }
        return result
    }

    private static func textOutsideComments(
        _ source: String,
        isInsideComment: inout Bool
    ) -> String {
        var result = ""
        var cursor = source.startIndex
        while cursor < source.endIndex {
            guard let marker = source[cursor...].range(of: "%%") else {
                if !isInsideComment { result += source[cursor...] }
                break
            }
            if !isInsideComment { result += source[cursor..<marker.lowerBound] }
            isInsideComment.toggle()
            cursor = marker.upperBound
        }
        return result
    }

    private static func replacing(
        _ expression: NSRegularExpression,
        in source: String,
        transform: (NSTextCheckingResult, String) -> String
    ) -> String {
        var result = source
        let matches = expression.matches(
            in: source,
            range: NSRange(location: 0, length: (source as NSString).length)
        )
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: transform(match, source))
        }
        return result
    }

    private static let wikilinkPattern = try! NSRegularExpression(
        pattern: #"(?:[+\-?])?!?\[\[([^\]\r\n]+)\]\]"#
    )
    private static let calloutRolePattern = try! NSRegularExpression(
        pattern: #"^\[![^\]]+\][+\-]?[ \t]*"#
    )
    private static let footnoteReferencePattern = try! NSRegularExpression(
        pattern: #"\[\^([^\]\r\n]+)\]"#
    )
    private static let highlightPattern = try! NSRegularExpression(
        pattern: #"==([^=\r\n]+)=="#
    )
    private static let displayMathPattern = try! NSRegularExpression(
        pattern: #"\$\$([^$\r\n]+)\$\$"#
    )
    private static let inlineMathPattern = try! NSRegularExpression(
        pattern: #"\$([^$\r\n]+)\$"#
    )
}
