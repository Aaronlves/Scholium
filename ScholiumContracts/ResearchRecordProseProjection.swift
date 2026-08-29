import Foundation
import Markdown

public struct ResearchRecordProseTraits: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let strong = Self(rawValue: 1 << 0)
    public static let emphasis = Self(rawValue: 1 << 1)
    public static let code = Self(rawValue: 1 << 2)
}

public enum ResearchRecordProseInternalLinkSyntax: Hashable, Sendable {
    case markdown
    case wikilink
}

public enum ResearchRecordProseLink: Hashable, Sendable {
    case external(URL)
    case internalReference(
        target: String,
        fragment: String?,
        fallbackText: String,
        syntax: ResearchRecordProseInternalLinkSyntax
    )
}

public struct ResearchRecordProseInline: Hashable, Sendable {
    public let text: String
    public let traits: ResearchRecordProseTraits
    public let link: ResearchRecordProseLink?

    public init(
        text: String,
        traits: ResearchRecordProseTraits = [],
        link: ResearchRecordProseLink? = nil
    ) {
        self.text = text
        self.traits = traits
        self.link = link
    }
}

public enum ResearchRecordProseBlockKind: Hashable, Sendable {
    case paragraph
    /// Every authored ATX or Setext heading becomes the same Record-local
    /// section lead. The source level is deliberately not presentation state.
    case heading
    case unorderedListItem(depth: Int)
    case orderedListItem(index: Int, depth: Int)
    case listContinuation(depth: Int)
    /// Unsupported structures remain visible source instead of disappearing
    /// or becoming a second full Markdown renderer.
    case literal
}

public struct ResearchRecordProseBlock: Hashable, Sendable {
    public let kind: ResearchRecordProseBlockKind
    public let quoteDepth: Int
    public let inlines: [ResearchRecordProseInline]

    public init(
        kind: ResearchRecordProseBlockKind,
        quoteDepth: Int = 0,
        inlines: [ResearchRecordProseInline]
    ) {
        self.kind = kind
        self.quoteDepth = quoteDepth
        self.inlines = inlines
    }
}

/// A disposable, presentation-only projection over an exact Research Record
/// prose string. The source string remains the sole value stored in the strict
/// portable Record.
public struct ResearchRecordProseProjection: Hashable, Sendable {
    public let source: String
    public let blocks: [ResearchRecordProseBlock]

    public init(source: String) {
        self.source = source
        let tokenized = ResearchRecordWikilinkTokenizer.tokenize(source)
        let parsed = Document(parsing: tokenized.source)
        var projector = ResearchRecordProseProjector(
            source: tokenized.source,
            wikilinks: tokenized.links
        )
        blocks = projector.project(parsed)
    }
}

private struct ResearchRecordWikilinkToken {
    let link: ResearchRecordProseLink
}

private struct ResearchRecordWikilinkTokenization {
    let source: String
    let links: [String: ResearchRecordWikilinkToken]
}

private enum ResearchRecordWikilinkTokenizer {
    static func tokenize(_ source: String) -> ResearchRecordWikilinkTokenization {
        let parsed = Document(parsing: source)
        let sourceMap = ResearchRecordSourceMap(source)
        let excluded = unsupportedBlockRanges(in: parsed, sourceMap: sourceMap)
        let candidates = MarkdownSemanticParser.links(inFragment: source)
            .filter { $0.syntax == .wikilink || $0.syntax == .vectorWikilink }
            .filter { link in
                !excluded.contains { range in
                    range.overlaps(link.span.utf8Range)
                }
            }

        guard !candidates.isEmpty else {
            return ResearchRecordWikilinkTokenization(source: source, links: [:])
        }

        let transformed = NSMutableString(string: source)
        let original = source as NSString
        var tokens: [String: ResearchRecordWikilinkToken] = [:]
        for (index, link) in candidates.enumerated().reversed() {
            let token = "scholium-record-wikilink://\(index)"
            let raw = original.substring(with: link.span.nsRange)
            let prefix: String
            let fallback: String
            if link.syntax == .vectorWikilink, let first = raw.first,
                ["+", "-", "?"].contains(String(first))
            {
                prefix = String(first)
                fallback = String(raw.dropFirst())
            } else {
                prefix = ""
                fallback = raw
            }
            let display = link.alias
                ?? (link.target.isEmpty ? link.fragment ?? "Link" : link.target)
            let escapedDisplay = display
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "[", with: "\\[")
                .replacingOccurrences(of: "]", with: "\\]")
            transformed.replaceCharacters(
                in: link.span.nsRange,
                with: "\(prefix)[\(escapedDisplay)](\(token))"
            )
            tokens[token] = ResearchRecordWikilinkToken(
                link: .internalReference(
                    target: link.target,
                    fragment: link.fragment,
                    fallbackText: fallback,
                    syntax: .wikilink
                )
            )
        }
        return ResearchRecordWikilinkTokenization(
            source: transformed as String,
            links: tokens
        )
    }

    private static func unsupportedBlockRanges(
        in markup: Markup,
        sourceMap: ResearchRecordSourceMap
    ) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        func visit(_ node: Markup) {
            if node is CodeBlock || node is HTMLBlock || node is Table
                || node is ThematicBreak || node is CustomBlock
            {
                if let range = sourceMap.utf8Range(node.range) { ranges.append(range) }
                return
            }
            if let item = node as? ListItem, item.checkbox != nil {
                if let range = sourceMap.utf8Range(node.range) { ranges.append(range) }
                return
            }
            if node is BlockQuote,
                let source = sourceMap.substring(node.range),
                source.range(
                    of: #"(?m)^\s*>\s*\[![^\]]+\]"#,
                    options: .regularExpression
                ) != nil
            {
                if let range = sourceMap.utf8Range(node.range) { ranges.append(range) }
                return
            }
            for child in node.children { visit(child) }
        }
        visit(markup)
        return ranges
    }
}

private struct ResearchRecordProseProjector {
    let wikilinks: [String: ResearchRecordWikilinkToken]
    let sourceMap: ResearchRecordSourceMap
    var blocks: [ResearchRecordProseBlock] = []

    init(source: String, wikilinks: [String: ResearchRecordWikilinkToken]) {
        self.wikilinks = wikilinks
        sourceMap = ResearchRecordSourceMap(source)
    }

    mutating func project(_ document: Document) -> [ResearchRecordProseBlock] {
        for child in document.children {
            append(child, quoteDepth: 0)
        }
        return blocks
    }

    private mutating func append(_ markup: Markup, quoteDepth: Int) {
        switch markup {
        case let paragraph as Paragraph:
            appendInlineBlock(
                kind: .paragraph,
                markup: paragraph,
                quoteDepth: quoteDepth
            )
        case let heading as Heading:
            appendInlineBlock(
                kind: .heading,
                markup: heading,
                quoteDepth: quoteDepth,
                additionalTraits: .strong
            )
        case let quote as BlockQuote:
            if let raw = sourceMap.substring(quote.range),
                raw.range(
                    of: #"(?m)^\s*>\s*\[![^\]]+\]"#,
                    options: .regularExpression
                ) != nil
            {
                appendLiteral(quote, quoteDepth: quoteDepth)
            } else {
                for child in quote.children {
                    append(child, quoteDepth: quoteDepth + 1)
                }
            }
        case let list as UnorderedList:
            appendUnorderedList(list, depth: 0, quoteDepth: quoteDepth)
        case let list as OrderedList:
            appendOrderedList(list, depth: 0, quoteDepth: quoteDepth)
        case is CodeBlock, is HTMLBlock, is Table, is ThematicBreak, is CustomBlock:
            appendLiteral(markup, quoteDepth: quoteDepth)
        default:
            appendLiteral(markup, quoteDepth: quoteDepth)
        }
    }

    private mutating func appendUnorderedList(
        _ list: UnorderedList,
        depth: Int,
        quoteDepth: Int
    ) {
        for child in list.children {
            guard let item = child as? ListItem else {
                appendLiteral(child, quoteDepth: quoteDepth)
                continue
            }
            appendListItem(
                item,
                primaryKind: .unorderedListItem(depth: depth),
                depth: depth,
                quoteDepth: quoteDepth
            )
        }
    }

    private mutating func appendOrderedList(
        _ list: OrderedList,
        depth: Int,
        quoteDepth: Int
    ) {
        for (offset, child) in list.children.enumerated() {
            guard let item = child as? ListItem else {
                appendLiteral(child, quoteDepth: quoteDepth)
                continue
            }
            appendListItem(
                item,
                primaryKind: .orderedListItem(
                    index: Int(list.startIndex) + offset,
                    depth: depth
                ),
                depth: depth,
                quoteDepth: quoteDepth
            )
        }
    }

    private mutating func appendListItem(
        _ item: ListItem,
        primaryKind: ResearchRecordProseBlockKind,
        depth: Int,
        quoteDepth: Int
    ) {
        guard item.checkbox == nil else {
            appendLiteral(item, quoteDepth: quoteDepth)
            return
        }
        var emittedPrimary = false
        for child in item.children {
            switch child {
            case let paragraph as Paragraph:
                appendInlineBlock(
                    kind: emittedPrimary ? .listContinuation(depth: depth) : primaryKind,
                    markup: paragraph,
                    quoteDepth: quoteDepth
                )
                emittedPrimary = true
            case let nested as UnorderedList:
                appendUnorderedList(nested, depth: depth + 1, quoteDepth: quoteDepth)
            case let nested as OrderedList:
                appendOrderedList(nested, depth: depth + 1, quoteDepth: quoteDepth)
            default:
                appendLiteral(child, quoteDepth: quoteDepth)
            }
        }
    }

    private mutating func appendInlineBlock(
        kind: ResearchRecordProseBlockKind,
        markup: Markup,
        quoteDepth: Int,
        additionalTraits: ResearchRecordProseTraits = []
    ) {
        var inlines: [ResearchRecordProseInline] = []
        for child in markup.children {
            appendInline(
                child,
                traits: additionalTraits,
                link: nil,
                to: &inlines
            )
        }
        blocks.append(
            ResearchRecordProseBlock(
                kind: kind,
                quoteDepth: quoteDepth,
                inlines: merged(inlines)
            )
        )
    }

    private func appendInline(
        _ markup: Markup,
        traits: ResearchRecordProseTraits,
        link: ResearchRecordProseLink?,
        to output: inout [ResearchRecordProseInline]
    ) {
        switch markup {
        case let text as Markdown.Text:
            output.append(.init(text: text.string, traits: traits, link: link))
        case is SoftBreak:
            output.append(.init(text: " ", traits: traits, link: link))
        case is LineBreak:
            output.append(.init(text: "\n", traits: traits, link: link))
        case let code as InlineCode:
            output.append(.init(text: code.code, traits: traits.union(.code), link: link))
        case let strong as Strong:
            for child in strong.children {
                appendInline(child, traits: traits.union(.strong), link: link, to: &output)
            }
        case let emphasis as Emphasis:
            for child in emphasis.children {
                appendInline(child, traits: traits.union(.emphasis), link: link, to: &output)
            }
        case let markdownLink as Markdown.Link:
            appendLink(markdownLink, traits: traits, to: &output)
        case let html as InlineHTML:
            output.append(.init(text: html.rawHTML, traits: traits, link: link))
        case let deleted as Strikethrough:
            output.append(.init(text: "~~", traits: traits, link: link))
            for child in deleted.children {
                appendInline(child, traits: traits, link: link, to: &output)
            }
            output.append(.init(text: "~~", traits: traits, link: link))
        case is Image, is SymbolLink, is InlineAttributes, is CustomInline:
            appendLiteralInline(markup, traits: traits, link: link, to: &output)
        default:
            if markup.childCount > 0 {
                for child in markup.children {
                    appendInline(child, traits: traits, link: link, to: &output)
                }
            } else {
                appendLiteralInline(markup, traits: traits, link: link, to: &output)
            }
        }
    }

    private func appendLink(
        _ markdownLink: Markdown.Link,
        traits: ResearchRecordProseTraits,
        to output: inout [ResearchRecordProseInline]
    ) {
        guard let destination = markdownLink.destination else {
            appendLiteralInline(markdownLink, traits: traits, link: nil, to: &output)
            return
        }
        let resolvedLink: ResearchRecordProseLink?
        if let token = wikilinks[destination] {
            resolvedLink = token.link
        } else if let url = URL(string: destination),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        {
            resolvedLink = .external(url)
        } else if URL(string: destination)?.scheme == nil {
            let targetAndFragment = splitTargetAndFragment(destination)
            resolvedLink = .internalReference(
                target: targetAndFragment.target,
                fragment: targetAndFragment.fragment,
                fallbackText: sourceMap.substring(markdownLink.range)
                    ?? "[\(plainText(markdownLink))](\(destination))",
                syntax: .markdown
            )
        } else {
            resolvedLink = nil
        }

        guard let resolvedLink else {
            appendLiteralInline(markdownLink, traits: traits, link: nil, to: &output)
            return
        }
        for child in markdownLink.children {
            appendInline(child, traits: traits, link: resolvedLink, to: &output)
        }
    }

    private func appendLiteralInline(
        _ markup: Markup,
        traits: ResearchRecordProseTraits,
        link: ResearchRecordProseLink?,
        to output: inout [ResearchRecordProseInline]
    ) {
        guard let literal = sourceMap.substring(markup.range), !literal.isEmpty else { return }
        output.append(.init(text: literal, traits: traits, link: link))
    }

    private mutating func appendLiteral(_ markup: Markup, quoteDepth: Int) {
        guard let literal = sourceMap.substring(markup.range), !literal.isEmpty else { return }
        blocks.append(
            ResearchRecordProseBlock(
                kind: .literal,
                quoteDepth: quoteDepth,
                inlines: [.init(text: literal, traits: .code)]
            )
        )
    }

    private func merged(
        _ inlines: [ResearchRecordProseInline]
    ) -> [ResearchRecordProseInline] {
        var result: [ResearchRecordProseInline] = []
        for inline in inlines where !inline.text.isEmpty {
            if let last = result.last,
                last.traits == inline.traits,
                last.link == inline.link
            {
                result[result.count - 1] = ResearchRecordProseInline(
                    text: last.text + inline.text,
                    traits: inline.traits,
                    link: inline.link
                )
            } else {
                result.append(inline)
            }
        }
        return result
    }

    private func plainText(_ markup: Markup) -> String {
        markup.children.map { child in
            if let text = child as? Markdown.Text { return text.string }
            return plainText(child)
        }.joined()
    }

    private func splitTargetAndFragment(
        _ destination: String
    ) -> (target: String, fragment: String?) {
        guard let hash = destination.firstIndex(of: "#") else {
            return (destination.removingPercentEncoding ?? destination, nil)
        }
        let target = String(destination[..<hash])
        let fragment = String(destination[destination.index(after: hash)...])
        return (
            target.removingPercentEncoding ?? target,
            fragment.removingPercentEncoding ?? fragment
        )
    }
}

private struct ResearchRecordSourceMap {
    private let bytes: [UInt8]
    private let lineStarts: [Int]

    init(_ source: String) {
        bytes = Array(source.utf8)
        var starts = [0]
        for (offset, byte) in bytes.enumerated() where byte == 0x0A {
            starts.append(offset + 1)
        }
        lineStarts = starts
    }

    func utf8Range(_ range: Markdown.SourceRange?) -> Range<Int>? {
        guard let range,
            let lower = offset(range.lowerBound),
            let upper = offset(range.upperBound),
            lower <= upper,
            upper <= bytes.count
        else { return nil }
        return lower..<upper
    }

    func substring(_ range: Markdown.SourceRange?) -> String? {
        guard let range = utf8Range(range) else { return nil }
        return String(decoding: bytes[range], as: UTF8.self)
    }

    private func offset(_ location: Markdown.SourceLocation) -> Int? {
        let lineIndex = location.line - 1
        guard lineStarts.indices.contains(lineIndex), location.column >= 1 else { return nil }
        let value = lineStarts[lineIndex] + location.column - 1
        return value <= bytes.count ? value : nil
    }
}
