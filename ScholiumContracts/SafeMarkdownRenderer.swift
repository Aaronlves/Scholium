import Foundation
import Markdown

public struct RenderedMarkdownDocument: Hashable, Sendable {
    public let htmlBody: String
    public let semanticDocument: MarkdownSemanticDocument

    public init(htmlBody: String, semanticDocument: MarkdownSemanticDocument) {
        self.htmlBody = htmlBody
        self.semanticDocument = semanticDocument
    }
}

/// Produces inert HTML from the shared semantic projection. The output contains
/// no scripts, event-handler attributes, remote media, or user-authored raw HTML.
public enum SafeMarkdownRenderer {
    public static func render(_ document: NoteDocument) -> RenderedMarkdownDocument {
        let semantic = MarkdownSemanticDocument(parsing: document)
        return render(document, semantic: semantic)
    }

    /// Reuses an immutable source-bound semantic projection when its exact
    /// fingerprint matches. A stale or unrelated projection is nonauthorizing
    /// and falls back to the ordinary parse path.
    public static func render(
        _ document: NoteDocument,
        semantic: MarkdownSemanticDocument
    ) -> RenderedMarkdownDocument {
        guard semantic.fingerprint == document.fingerprint else {
            return render(document)
        }
        let html = renderBody(document: document, semantic: semantic, depth: 0)
        return RenderedMarkdownDocument(htmlBody: html, semanticDocument: semantic)
    }

    private struct Replacement {
        let range: NSRange
        let text: String
    }

    private static let footnoteTrailingPunctuation = Set(
        ".,;:!?，。！？；：、…）》】」』’”\""
    )

    private static func renderBody(
        document: NoteDocument,
        semantic: MarkdownSemanticDocument,
        depth: Int,
        locatedLinkSpans: [SourceSpan]? = nil
    ) -> String {
        guard depth < 12 else {
            return "<p class=\"scholium-render-warning\" dir=\"auto\">Nested rendering limit reached.</p>"
        }

        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let bodyStart = bodyUTF16Offset(in: document)
        let bodyLength = (document.body as NSString).length
        var replacements: [Replacement] = []
        var blockHTML: [String: String] = [:]
        var inlineHTML: [String: String] = [:]

        let outerCallouts = semantic.callouts.filter { callout in
            !semantic.callouts.contains { candidate in
                candidate.span.utf16LowerBound < callout.span.utf16LowerBound
                    && candidate.span.utf16UpperBound >= callout.span.utf16UpperBound
            }
        }
        let removedDefinitionSpans = semantic.footnoteDefinitions
            .filter { !$0.isInline }
            .map(\.span)
        let blockSourceSpans: [MarkdownBlockKind: [SourceSpan]] =
            depth == 0
            ? Dictionary(
                grouping: semantic.blocks.filter { block in
                    !(outerCallouts.map(\.span) + removedDefinitionSpans).contains {
                        $0.utf16LowerBound <= block.span.utf16LowerBound
                            && $0.utf16UpperBound >= block.span.utf16UpperBound
                    }
                }, by: \.kind
            ).mapValues { blocks in
                blocks.map(\.span).sorted { $0.utf16LowerBound < $1.utf16LowerBound }
            }
            : [:]
        for (index, callout) in outerCallouts.enumerated() {
            guard let relative = relativeRange(callout.span, bodyStart: bodyStart, bodyLength: bodyLength) else { continue }
            let key = "\(nonce)-block-\(index)"
            let nestedLinkSpans = semantic.links.enumerated().compactMap { linkIndex, link -> SourceSpan? in
                guard link.span.utf16LowerBound >= callout.headerSpan.utf16UpperBound,
                    link.span.utf16UpperBound <= callout.span.utf16UpperBound
                else { return nil }
                return locatedSpan(
                    at: linkIndex,
                    from: locatedLinkSpans,
                    fallback: link.linkSpan
                )
            }
            blockHTML[key] = renderCallout(
                callout,
                locatedLinkSpans: nestedLinkSpans,
                depth: depth + 1
            )
            replacements.append(
                Replacement(
                    range: relative,
                    text: "\n<div data-scholium-block-token=\"\(key)\"></div>\n"
                ))
        }

        for definition in semantic.footnoteDefinitions where !definition.isInline {
            guard let relative = relativeRange(definition.span, bodyStart: bodyStart, bodyLength: bodyLength),
                !overlaps(relative, replacements.map(\.range))
            else { continue }
            replacements.append(Replacement(range: relative, text: ""))
        }

        for (index, expression) in semantic.mathExpressions.enumerated() {
            guard
                let relative = relativeRange(
                    expression.span,
                    bodyStart: bodyStart,
                    bodyLength: bodyLength
                ), !overlaps(relative, replacements.map(\.range))
            else { continue }
            let rawSource = (document.body as NSString).substring(with: relative)
            switch expression.kind {
            case .inline:
                let key = "SCHOLIUMINLINETOKEN\(nonce)M\(index)"
                inlineHTML[key] = renderMath(expression, rawSource: rawSource)
                replacements.append(Replacement(range: relative, text: key))
            case .display:
                let key = "\(nonce)-math-\(index)"
                blockHTML[key] = renderMath(expression, rawSource: rawSource)
                replacements.append(
                    Replacement(
                        range: relative,
                        text: "\n<div data-scholium-block-token=\"\(key)\"></div>\n"
                    ))
            }
        }

        let definitionsByIdentifier = Dictionary(
            uniqueKeysWithValues: semantic.footnoteDefinitions.map { ($0.identifier, $0) }
        )
        for reference in semantic.footnoteReferences {
            guard let relative = relativeRange(reference.span, bodyStart: bodyStart, bodyLength: bodyLength),
                !overlaps(relative, replacements.map(\.range))
            else { continue }
            let key = "SCHOLIUMINLINETOKEN\(nonce)F\(reference.ordinal)R\(reference.occurrence)"
            let definitionExists = definitionsByIdentifier[reference.identifier] != nil
            let punctuation = trailingPunctuation(in: document.body, after: relative)
            inlineHTML[key] = renderFootnoteReference(
                reference,
                definitionExists: definitionExists,
                trailingPunctuation: punctuation.text
            )
            replacements.append(
                Replacement(
                    range: NSRange(
                        location: relative.location,
                        length: relative.length + punctuation.utf16Length
                    ),
                    text: key
                ))
        }

        for (index, link) in semantic.links.enumerated() where link.syntax != .markdown {
            guard let relative = relativeRange(link.span, bodyStart: bodyStart, bodyLength: bodyLength),
                !overlaps(relative, replacements.map(\.range))
            else { continue }
            let key = "SCHOLIUMINLINETOKEN\(nonce)L\(index)"
            inlineHTML[key] = renderWikilink(
                link,
                locatedSpan: locatedSpan(
                    at: index,
                    from: locatedLinkSpans,
                    fallback: link.linkSpan
                ),
                depth: depth + 1
            )
            replacements.append(Replacement(range: relative, text: key))
        }

        let literalRanges =
            semantic.blocks.compactMap { block -> NSRange? in
                guard block.kind == .code || block.kind == .html else { return nil }
                return relativeRange(block.span, bodyStart: bodyStart, bodyLength: bodyLength)
            } + inlineLiteralRanges(in: document.body)
        let body = document.body as NSString
        for (index, highlight) in semantic.inlines
            .filter({ $0.kind == .highlight })
            .enumerated()
        {
            guard
                let relative = relativeRange(
                    highlight.span,
                    bodyStart: bodyStart,
                    bodyLength: bodyLength
                ), relative.length > 4,
                !overlaps(relative, literalRanges),
                !overlaps(relative, replacements.map(\.range))
            else { continue }
            let key = "SCHOLIUMINLINETOKEN\(nonce)H\(index)"
            let contentRange = NSRange(location: relative.location + 2, length: relative.length - 4)
            inlineHTML[key] = "<mark class=\"scholium-highlight\">\(escapeHTML(body.substring(with: contentRange)))</mark>"
            replacements.append(Replacement(range: relative, text: key))
        }

        let transformed = apply(replacements, to: document.body)
        let parsed = Document(parsing: transformed, options: [.parseBlockDirectives])
        let quoteDepths = Dictionary(
            uniqueKeysWithValues: semantic.blocks
                .filter { $0.kind == .blockQuote }
                .map { block in
                    (
                        block.span,
                        quoteDepth(
                            in: document.body,
                            span: block.span,
                            bodyUTF16Offset: bodyStart
                        )
                    )
                }
        )
        var visitor = SafeHTMLVisitor(
            blockHTML: blockHTML,
            inlineHTML: inlineHTML,
            blockSourceSpans: blockSourceSpans,
            quoteDepths: quoteDepths
        )
        visitor.visit(parsed)

        let footnoteSection = renderFootnoteSection(
            semantic.footnoteDefinitions,
            depth: depth + 1
        )
        return visitor.renderedHTML(
            source: document.body,
            bodyUTF16Offset: bodyStart
        ) + footnoteSection
    }

    private static func renderCallout(
        _ callout: CalloutBlock,
        locatedLinkSpans: [SourceSpan],
        depth: Int
    ) -> String {
        let roleLabel = escapeHTML(callout.role.displayLabel)
        let purpose = escapeAttribute(callout.role.purpose)
        let accessibleRole = escapeAttribute("\(callout.role.displayLabel). \(callout.role.purpose)")
        // Keep the role as accessible metadata, but render one visible Review
        // title: the authored title when present, otherwise the role's default
        // label. Live Preview retains only authored source text and never
        // materializes this fallback as editable prose.
        let roleHTML =
            "<span class=\"scholium-callout-role scholium-callout-role-context\" dir=\"auto\" "
            + "title=\"\(purpose)\" aria-label=\"\(accessibleRole)\">\(roleLabel)</span>"
        let orientationTitleBecomesBody =
            callout.role == .orient
            && callout.title != nil
            && callout.bodySource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let titleHTML =
            if let title = callout.title, !orientationTitleBecomesBody {
                "<span class=\"scholium-callout-title\" dir=\"auto\">\(renderInlineMarkdown(title))</span>"
            } else {
                "<span class=\"scholium-callout-title scholium-callout-default-title\" dir=\"auto\">\(roleLabel)</span>"
            }
        let heading = "<span class=\"scholium-callout-heading\" role=\"heading\" aria-level=\"2\">\(roleHTML)\(titleHTML)</span>"
        // Orient's title-only form is an authored reading route, not an empty
        // titled box. Live Preview moves that title into the body as prose;
        // Review must use the same projection.
        let bodySource = orientationTitleBecomesBody ? (callout.title ?? "") : callout.bodySource
        let fragment = NoteDocument(relativePath: "callout.md", rawContent: bodySource)
        let fragmentSemantic = MarkdownSemanticDocument(parsing: fragment)
        let renderedBody = renderBody(
            document: fragment,
            semantic: fragmentSemantic,
            depth: depth,
            locatedLinkSpans: fragmentSemantic.links.count == locatedLinkSpans.count
                ? locatedLinkSpans
                : nil
        )
        let semanticBody =
            callout.role == .quote
            ? "<blockquote class=\"scholium-callout-quotation\" dir=\"auto\">\(renderedBody)</blockquote>"
            : renderedBody
        let body =
            "<div class=\"scholium-callout-body\"><div class=\"scholium-callout-content\">\(semanticBody)</div></div>"
        let attributes =
            "class=\"scholium-callout scholium-callout-\(callout.role.rawValue)\" data-callout=\"\(escapeAttribute(callout.kind))\" data-callout-source=\"\(escapeAttribute(callout.rawKind))\" data-callout-fold=\"\(callout.foldState.rawValue)\" \(sourceAttributes(callout.span)) data-scholium-protected=\"callout\""
        switch callout.foldState {
        case .fixed:
            return "<aside \(attributes)><header>\(heading)</header>\(body)</aside>"
        case .expanded, .collapsed:
            let open = callout.foldState == .expanded ? " open" : ""
            return
                "<details \(attributes)\(open)><summary>\(heading)<span class=\"scholium-callout-fold-mark\" aria-hidden=\"true\"></span></summary>\(body)</details>"
        }
    }

    private static func renderFootnoteReference(
        _ reference: FootnoteReference,
        definitionExists: Bool,
        trailingPunctuation: String
    ) -> String {
        let referenceID = "fnref-\(reference.ordinal)-\(reference.occurrence)"
        let target = "fn-\(reference.ordinal)"
        let disabled = definitionExists ? "" : " disabled aria-disabled=\"true\""
        let locator =
            "<sup id=\"\(referenceID)\" class=\"footnote-reference-wrap\" \(sourceAttributes(reference.span)) data-scholium-protected=\"footnote\"><button type=\"button\" class=\"footnote-reference\" data-footnote=\"\(reference.ordinal)\" data-target=\"\(target)\" aria-label=\"Footnote \(reference.ordinal)\" aria-expanded=\"false\"\(disabled)>\(reference.ordinal)</button></sup>"
        guard !trailingPunctuation.isEmpty else { return locator }
        return "<span class=\"footnote-reference-cluster\">\(locator)\(escapeHTML(trailingPunctuation))</span>"
    }

    private static func trailingPunctuation(
        in body: String,
        after range: NSRange
    ) -> (text: String, utf16Length: Int) {
        let source = body as NSString
        var location = NSMaxRange(range)
        var value = ""
        while location < source.length {
            let characterRange = source.rangeOfComposedCharacterSequence(at: location)
            let character = source.substring(with: characterRange)
            guard character.count == 1,
                let valueCharacter = character.first,
                footnoteTrailingPunctuation.contains(valueCharacter)
            else { break }
            value += character
            location = NSMaxRange(characterRange)
        }
        return (value, location - NSMaxRange(range))
    }

    private static func renderMath(_ expression: MathExpression, rawSource: String) -> String {
        let encoded = Data(expression.content.utf8).base64EncodedString()
        let kind = expression.kind.rawValue
        let tag = expression.kind == .display ? "div" : "span"
        return
            "<\(tag) class=\"scholium-math scholium-math-\(kind)\" dir=\"ltr\" data-math-kind=\"\(kind)\" data-math-source=\"\(encoded)\" \(sourceAttributes(expression.span)) data-scholium-protected=\"math\"><code class=\"scholium-math-source\" dir=\"ltr\">\(escapeHTML(rawSource))</code></\(tag)>"
    }

    private static func renderInlineMarkdown(_ source: String) -> String {
        let parsed = Document(parsing: source)
        var visitor = SafeHTMLVisitor(
            blockHTML: [:],
            inlineHTML: [:],
            blockSourceSpans: [:],
            quoteDepths: [:]
        )
        visitor.visit(parsed)
        let rendered = visitor.renderedHTML(source: source, bodyUTF16Offset: 0)
        let paragraphPrefix = "<p dir=\"auto\">"
        guard rendered.hasPrefix(paragraphPrefix), rendered.hasSuffix("</p>\n") else {
            return escapeHTML(source)
        }
        return String(rendered.dropFirst(paragraphPrefix.count).dropLast(5))
    }

    private static func renderFootnoteSection(
        _ definitions: [FootnoteDefinition],
        depth: Int
    ) -> String {
        let referenced = definitions.filter { $0.ordinal != nil }
        guard !referenced.isEmpty else { return "" }
        let items = referenced.compactMap { definition -> String? in
            guard let ordinal = definition.ordinal else { return nil }
            let fragment = NoteDocument(relativePath: "footnote.md", rawContent: definition.content)
            let content = renderBody(
                document: fragment,
                semantic: MarkdownSemanticDocument(parsing: fragment),
                depth: depth
            )
            return
                "<li id=\"fn-\(ordinal)\" dir=\"auto\" data-footnote=\"\(ordinal)\" \(sourceAttributes(definition.span))><div class=\"footnote-content\">\(content)</div><button type=\"button\" class=\"footnote-return\" data-footnote=\"\(ordinal)\" aria-label=\"Return to footnote reference \(ordinal)\">↩</button></li>"
        }.joined()
        return
            "<div class=\"scholium-footnotes-slot\"><section class=\"footnotes\" data-scholium-protected=\"footnotes\" aria-label=\"Footnotes\"><hr><ol>\(items)</ol></section></div>"
    }

    private static func renderWikilink(
        _ link: LinkOccurrence,
        locatedSpan: SourceSpan,
        depth: Int
    ) -> String {
        let display = link.alias ?? (link.target.isEmpty ? link.fragment ?? "Link" : link.target)
        let destination = link.target + (link.fragment.map { "#\($0)" } ?? "")
        let decodedDestination = destination.removingPercentEncoding ?? destination
        let encoded =
            decodedDestination.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? decodedDestination
        if link.syntax == .embed {
            return
                "<a class=\"wiki-link scholium-embed\" dir=\"auto\" href=\"scholium-note:\(escapeAttribute(encoded))\" \(sourceAttributes(locatedSpan)) data-scholium-protected=\"embed\">\(escapeHTML(display))</a>"
        }
        let linkHTML =
            "<a class=\"wiki-link\" dir=\"auto\" href=\"scholium-note:\(escapeAttribute(encoded))\" \(sourceAttributes(locatedSpan))>\(escapeHTML(display))</a>"
        guard let annotation = link.annotation else { return linkHTML }
        let identifier = "link-annotation-\(link.span.utf16LowerBound)-\(link.span.utf16UpperBound)"
        let fragment = NoteDocument(relativePath: "link-annotation.md", rawContent: annotation.markdown)
        let annotationHTML = renderBody(
            document: fragment,
            semantic: MarkdownSemanticDocument(parsing: fragment),
            depth: depth
        )
        let label = escapeAttribute("Show link annotation for \(display)")
        let target = escapeAttribute(display)
        return
            "<span class=\"scholium-annotated-link\" data-scholium-protected=\"link-annotation\">\(linkHTML)<sup class=\"scholium-link-annotation-marker\"><button type=\"button\" class=\"scholium-link-annotation-button\" data-link-annotation=\"\(identifier)\" data-link-annotation-target=\"\(target)\" aria-expanded=\"false\" aria-label=\"\(label)\"><span aria-hidden=\"true\"></span></button><template id=\"\(identifier)-template\"><div class=\"scholium-link-annotation-content\" dir=\"auto\" role=\"note\" \(sourceAttributes(annotation.span))>\(annotationHTML)</div></template></sup></span>"
    }

    private static func bodyUTF16Offset(in document: NoteDocument) -> Int {
        let source = document.rawContent
        let byteOffset = document.bodyByteRange.lowerBound
        guard byteOffset <= source.utf8.count else { return 0 }
        let utf8Index = source.utf8.index(source.utf8.startIndex, offsetBy: byteOffset)
        guard let index = String.Index(utf8Index, within: source) else { return 0 }
        return index.utf16Offset(in: source)
    }

    private static func locatedSpan(
        at index: Int,
        from spans: [SourceSpan]?,
        fallback: SourceSpan
    ) -> SourceSpan {
        guard let spans, spans.indices.contains(index) else { return fallback }
        return spans[index]
    }

    private static func relativeRange(
        _ span: SourceSpan,
        bodyStart: Int,
        bodyLength: Int
    ) -> NSRange? {
        let location = span.utf16LowerBound - bodyStart
        let upper = span.utf16UpperBound - bodyStart
        guard location >= 0, upper >= location, upper <= bodyLength else { return nil }
        return NSRange(location: location, length: upper - location)
    }

    private static func quoteDepth(
        in body: String,
        span: SourceSpan,
        bodyUTF16Offset: Int
    ) -> Int {
        let source = body as NSString
        let location = span.utf16LowerBound - bodyUTF16Offset
        guard location >= 0, location < source.length else { return 1 }

        let line =
            source.substring(
                with: source.lineRange(
                    for: NSRange(location: location, length: 0)
                )
            ) as NSString
        var cursor = 0
        var depth = 0
        while cursor < line.length {
            var indentation = 0
            while cursor < line.length, indentation < 3, line.character(at: cursor) == 0x20 {
                cursor += 1
                indentation += 1
            }
            guard cursor < line.length, line.character(at: cursor) == 0x3E else { break }
            depth += 1
            cursor += 1
            if cursor < line.length, line.character(at: cursor) == 0x20 { cursor += 1 }
        }
        return max(1, min(depth, 3))
    }

    fileprivate static func normalizeQuoteParts(
        _ parts: [SafeHTMLPart],
        source: String,
        bodyUTF16Offset: Int
    ) -> [SafeHTMLPart] {
        let recursivelyNormalized = parts.map { part -> SafeHTMLPart in
            guard case .quote(var node) = part else { return part }
            node.children = normalizeQuoteParts(
                node.children,
                source: source,
                bodyUTF16Offset: bodyUTF16Offset
            )
            return .quote(node)
        }

        var output: [SafeHTMLPart] = []
        var pendingWhitespace = ""
        for part in recursivelyNormalized {
            if case .html(let html) = part,
                !html.isEmpty,
                html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                pendingWhitespace += html
                continue
            }

            if case .quote(let current) = part,
                let last = output.last,
                case .quote(let previous) = last,
                shouldJoinQuotes(
                    previous,
                    current,
                    source: source,
                    bodyUTF16Offset: bodyUTF16Offset
                )
            {
                output.removeLast()
                output.append(
                    .quote(
                        mergeQuotes(
                            previous,
                            current
                        )
                    )
                )
                pendingWhitespace = ""
                continue
            }

            if !pendingWhitespace.isEmpty {
                output.append(.html(pendingWhitespace))
                pendingWhitespace = ""
            }
            output.append(part)
        }
        if !pendingWhitespace.isEmpty {
            output.append(.html(pendingWhitespace))
        }
        return output
    }

    fileprivate static func renderQuoteParts(_ parts: [SafeHTMLPart]) -> String {
        parts.map { part in
            switch part {
            case .html(let html):
                return html
            case .quote(let node):
                let source = node.metadata.span.map { " \(sourceAttributes($0))" } ?? ""
                return
                    "<blockquote dir=\"auto\"\(source)>\(renderQuoteParts(node.children))</blockquote>\n"
            }
        }.joined()
    }

    private static func shouldJoinQuotes(
        _ left: SafeHTMLQuoteNode,
        _ right: SafeHTMLQuoteNode,
        source: String,
        bodyUTF16Offset: Int
    ) -> Bool {
        guard let leftSpan = left.metadata.span,
            let rightSpan = right.metadata.span,
            right.metadata.depth >= left.metadata.depth,
            rightSpan.utf16LowerBound >= leftSpan.utf16UpperBound
        else { return false }
        return quoteLinesBetween(
            leftSpan,
            rightSpan,
            minimumDepth: left.metadata.depth,
            source: source,
            bodyUTF16Offset: bodyUTF16Offset
        )
    }

    private static func quoteLinesBetween(
        _ left: SourceSpan,
        _ right: SourceSpan,
        minimumDepth: Int,
        source: String,
        bodyUTF16Offset: Int
    ) -> Bool {
        let body = source as NSString
        let leftOffset = max(0, min(body.length, left.utf16UpperBound - bodyUTF16Offset))
        let rightOffset = max(0, min(body.length, right.utf16LowerBound - bodyUTF16Offset))
        guard rightOffset >= leftOffset else { return false }

        let leftLine = lineIndex(in: body, at: leftOffset)
        let rightLine = lineIndex(in: body, at: rightOffset)
        guard rightLine >= leftLine else { return false }
        guard rightLine > leftLine + 1 else { return true }

        let lines = lineTexts(in: body)
        guard rightLine <= lines.count else { return false }
        for index in (leftLine + 1)..<rightLine {
            guard sourceQuoteDepth(of: lines[index]) >= minimumDepth else { return false }
        }
        return true
    }

    private static func lineIndex(in source: NSString, at offset: Int) -> Int {
        var index = 0
        var line = 0
        while index < min(offset, source.length) {
            if source.character(at: index) == 0x0A {
                line += 1
            }
            index += 1
        }
        return line
    }

    private static func lineTexts(in source: NSString) -> [String] {
        guard source.length > 0 else { return [""] }
        var lines: [String] = []
        var cursor = 0
        while cursor < source.length {
            let lineRange = source.lineRange(
                for: NSRange(location: cursor, length: 0)
            )
            let contentRange = lineContentRange(lineRange, in: source)
            lines.append(source.substring(with: contentRange))
            cursor = NSMaxRange(lineRange)
        }
        return lines
    }

    private static func sourceQuoteDepth(of line: String) -> Int {
        let source = line as NSString
        var cursor = 0
        var depth = 0
        while cursor < source.length {
            var indentation = 0
            while cursor < source.length,
                indentation < 3,
                source.character(at: cursor) == 0x20
            {
                cursor += 1
                indentation += 1
            }
            guard cursor < source.length, source.character(at: cursor) == 0x3E else {
                break
            }
            depth += 1
            cursor += 1
            if cursor < source.length,
                source.character(at: cursor) == 0x20
            {
                cursor += 1
            }
        }
        return min(depth, 3)
    }

    private static func lineContentRange(
        _ lineRange: NSRange,
        in source: NSString
    ) -> NSRange {
        var length = lineRange.length
        while length > 0 {
            let character = source.character(at: lineRange.location + length - 1)
            if character == 0x0A || character == 0x0D {
                length -= 1
            } else {
                break
            }
        }
        return NSRange(location: lineRange.location, length: length)
    }

    private static func mergeQuotes(
        _ left: SafeHTMLQuoteNode,
        _ right: SafeHTMLQuoteNode
    ) -> SafeHTMLQuoteNode {
        var merged = left
        let rightNode = nestedQuoteNode(
            right,
            under: left.metadata.depth
        )
        if right.metadata.depth == left.metadata.depth {
            merged.children.append(contentsOf: right.children)
        } else {
            merged.children.append(.quote(rightNode))
        }
        merged.metadata = SafeHTMLQuoteMetadata(
            span: combinedSpan(left.metadata.span, right.metadata.span),
            depth: left.metadata.depth
        )
        return merged
    }

    private static func nestedQuoteNode(
        _ node: SafeHTMLQuoteNode,
        under parentDepth: Int
    ) -> SafeHTMLQuoteNode {
        guard node.metadata.depth > parentDepth + 1 else { return node }
        var result = node
        for depth in stride(
            from: node.metadata.depth - 1,
            through: parentDepth + 1,
            by: -1
        ) {
            result = SafeHTMLQuoteNode(
                metadata: SafeHTMLQuoteMetadata(span: nil, depth: depth),
                children: [.quote(result)]
            )
        }
        return result
    }

    private static func combinedSpan(
        _ left: SourceSpan?,
        _ right: SourceSpan?
    ) -> SourceSpan? {
        guard let left, let right else { return left ?? right }
        let lower = left.utf16LowerBound <= right.utf16LowerBound ? left : right
        let upper = left.utf16UpperBound >= right.utf16UpperBound ? left : right
        return SourceSpan(
            utf8LowerBound: min(left.utf8LowerBound, right.utf8LowerBound),
            utf8UpperBound: max(left.utf8UpperBound, right.utf8UpperBound),
            utf16LowerBound: min(left.utf16LowerBound, right.utf16LowerBound),
            utf16UpperBound: max(left.utf16UpperBound, right.utf16UpperBound),
            start: lower.start,
            end: upper.end
        )
    }

    private static func overlaps(_ range: NSRange, _ existing: [NSRange]) -> Bool {
        existing.contains { NSIntersectionRange($0, range).length > 0 }
    }

    private static func inlineLiteralRanges(in source: String) -> [NSRange] {
        let length = (source as NSString).length
        let codeRanges = [#"`+[^`\n]*`+"#].flatMap { pattern in
            (try? NSRegularExpression(pattern: pattern))?.matches(
                in: source,
                range: NSRange(location: 0, length: length)
            ).map(\.range) ?? []
        }
        return codeRanges
            + literalCommentRanges(in: source, opening: "%%", closing: "%%")
            + literalCommentRanges(in: source, opening: "<!--", closing: "-->")
    }

    private static func literalCommentRanges(
        in value: String,
        opening: String,
        closing: String
    ) -> [NSRange] {
        let source = value as NSString
        var ranges: [NSRange] = []
        var cursor = 0
        while cursor < source.length {
            let openingRange = source.range(
                of: opening,
                options: [],
                range: NSRange(location: cursor, length: source.length - cursor)
            )
            guard openingRange.location != NSNotFound else { break }
            let closingStart = NSMaxRange(openingRange)
            let closingRange = source.range(
                of: closing,
                options: [],
                range: NSRange(location: closingStart, length: source.length - closingStart)
            )
            guard closingRange.location != NSNotFound else {
                ranges.append(
                    NSRange(
                        location: openingRange.location,
                        length: source.length - openingRange.location
                    ))
                break
            }
            ranges.append(
                NSRange(
                    location: openingRange.location,
                    length: NSMaxRange(closingRange) - openingRange.location
                ))
            cursor = NSMaxRange(closingRange)
        }
        return ranges
    }

    private static func apply(_ replacements: [Replacement], to source: String) -> String {
        let result = NSMutableString(string: source)
        for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            result.replaceCharacters(in: replacement.range, with: replacement.text)
        }
        return result as String
    }

    fileprivate static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    fileprivate static func escapeAttribute(_ value: String) -> String {
        escapeHTML(value).replacingOccurrences(of: "`", with: "&#96;")
    }

    fileprivate static func sourceAttributes(_ span: SourceSpan) -> String {
        "data-source-line=\"\(span.start.line)\" data-source-end-line=\"\(span.end.line)\" data-source-utf16-start=\"\(span.utf16LowerBound)\" data-source-utf16-end=\"\(span.utf16UpperBound)\" data-source-utf8-start=\"\(span.utf8LowerBound)\" data-source-utf8-end=\"\(span.utf8UpperBound)\""
    }
}

fileprivate struct SafeHTMLQuoteMetadata {
    let span: SourceSpan?
    let depth: Int
}

fileprivate struct SafeHTMLQuoteNode {
    var metadata: SafeHTMLQuoteMetadata
    var children: [SafeHTMLPart]
}

fileprivate indirect enum SafeHTMLPart {
    case html(String)
    case quote(SafeHTMLQuoteNode)
}

fileprivate struct SafeHTMLQuoteFrame {
    let identifier: String
    var node: SafeHTMLQuoteNode
}

private struct SafeHTMLVisitor: MarkupWalker {
    private static let quoteTokenStart = "\u{E000}scholium-quote-"
    private static let quoteTokenEnd = "\u{E001}"

    var result = ""
    let blockHTML: [String: String]
    let inlineHTML: [String: String]
    let blockSourceSpans: [MarkdownBlockKind: [SourceSpan]]
    let quoteDepths: [SourceSpan: Int]
    var blockSourceIndices: [MarkdownBlockKind: Int] = [:]
    var quoteMetadata: [String: SafeHTMLQuoteMetadata] = [:]
    var nextQuoteIdentifier = 0
    var tableColumnAlignments: [Table.ColumnAlignment?] = []
    var currentTableColumn = 0
    var isInsideTableHead = false

    mutating func visitDocument(_ document: Document) { descendInto(document) }
    mutating func visitParagraph(_ paragraph: Paragraph) {
        result += "<p dir=\"auto\"\(sourceAttributes(for: .paragraph))>"
        descendInto(paragraph)
        result += "</p>\n"
    }
    mutating func visitHeading(_ heading: Heading) {
        let span = nextSourceSpan(for: .heading)
        let anchor = span.map { " id=\"scholium-line-\($0.start.line)\" \(SafeMarkdownRenderer.sourceAttributes($0))" } ?? ""
        result += "<h\(heading.level) dir=\"auto\"\(anchor)>"
        descendInto(heading)
        result += "</h\(heading.level)>\n"
    }
    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        let span = nextSourceSpan(for: .blockQuote)
        let depth = span.flatMap { quoteDepths[$0] }.map { min(max($0, 1), 3) } ?? 1
        let identifier = String(nextQuoteIdentifier)
        nextQuoteIdentifier += 1
        quoteMetadata[identifier] = SafeHTMLQuoteMetadata(span: span, depth: depth)
        result += "\(Self.quoteTokenStart)open:\(identifier)\(Self.quoteTokenEnd)"
        descendInto(blockQuote)
        result += "\(Self.quoteTokenStart)close:\(identifier)\(Self.quoteTokenEnd)"
    }
    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let language = codeBlock.language.map { " class=\"language-\(SafeMarkdownRenderer.escapeAttribute($0))\"" } ?? ""
        result +=
            "<pre dir=\"ltr\"\(sourceAttributes(for: .code))><code dir=\"ltr\"\(language)>\(SafeMarkdownRenderer.escapeHTML(codeBlock.code))</code></pre>\n"
    }
    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        result += "<code dir=\"ltr\">\(SafeMarkdownRenderer.escapeHTML(inlineCode.code))</code>"
    }
    mutating func visitEmphasis(_ emphasis: Emphasis) {
        result += "<em>"
        descendInto(emphasis)
        result += "</em>"
    }
    mutating func visitStrong(_ strong: Strong) {
        result += "<strong>"
        descendInto(strong)
        result += "</strong>"
    }
    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        result += "<del>"
        descendInto(strikethrough)
        result += "</del>"
    }
    mutating func visitLineBreak(_ lineBreak: LineBreak) { result += "<br>\n" }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) { result += "\n" }
    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) { result += "<hr\(sourceAttributes(for: .thematicBreak))>\n" }
    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        result += "<ul\(sourceAttributes(for: .unorderedList))>"
        descendInto(unorderedList)
        result += "</ul>\n"
    }
    mutating func visitOrderedList(_ orderedList: OrderedList) {
        let start = orderedList.startIndex == 1 ? "" : " start=\"\(orderedList.startIndex)\""
        result += "<ol\(start)\(sourceAttributes(for: .orderedList))>"
        descendInto(orderedList)
        result += "</ol>\n"
    }
    mutating func visitListItem(_ listItem: ListItem) {
        let taskClass =
            listItem.checkbox == nil
            ? ""
            : " class=\"scholium-task-list-item\""
        result += "<li\(taskClass) dir=\"auto\"\(sourceAttributes(for: .listItem))>"
        if let checkbox = listItem.checkbox {
            let checked = checkbox == .checked
            let checkedAttribute = checked ? " checked=\"\"" : ""
            let label = checked ? "Completed task" : "Incomplete task"
            result += "<input class=\"scholium-task-checkbox\" type=\"checkbox\" disabled=\"\"\(checkedAttribute) aria-label=\"\(label)\">"
        }
        descendInto(listItem)
        result += "</li>\n"
    }
    mutating func visitLink(_ link: Link) {
        let destination = link.destination ?? ""
        let href: String
        if isApprovedExternal(destination) {
            href = destination
        } else {
            let decodedDestination = destination.removingPercentEncoding ?? destination
            let encoded =
                decodedDestination.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                ?? decodedDestination
            href = "scholium-note:\(encoded)"
        }
        result += "<a dir=\"auto\" href=\"\(SafeMarkdownRenderer.escapeAttribute(href))\">"
        descendInto(link)
        result += "</a>"
    }
    mutating func visitImage(_ image: Image) {
        result += "<span class=\"scholium-media-placeholder\">Image"
        if let title = image.title, !title.isEmpty {
            result += ": \(SafeMarkdownRenderer.escapeHTML(title))"
        }
        result += "</span>"
    }
    mutating func visitText(_ text: Text) { appendTextReplacingTokens(text.string) }
    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        if let key = blockToken(in: html.rawHTML), let replacement = blockHTML[key] {
            result += replacement
        } else {
            result +=
                "<pre class=\"raw-html\" dir=\"ltr\"\(sourceAttributes(for: .html))><code dir=\"ltr\">\(SafeMarkdownRenderer.escapeHTML(html.rawHTML))</code></pre>"
        }
    }
    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
        result += "<code class=\"raw-html-inline\" dir=\"ltr\">\(SafeMarkdownRenderer.escapeHTML(inlineHTML.rawHTML))</code>"
    }
    mutating func visitTable(_ table: Table) {
        let previousAlignments = tableColumnAlignments
        let previousColumn = currentTableColumn
        let previousHeadState = isInsideTableHead
        tableColumnAlignments = table.columnAlignments
        currentTableColumn = 0
        isInsideTableHead = false
        result += "<div class=\"scholium-table-scroll\" data-scholium-protected=\"table\"><table class=\"scholium-table\"\(sourceAttributes(for: .table))>"
        descendInto(table)
        result += "</table></div>"
        tableColumnAlignments = previousAlignments
        currentTableColumn = previousColumn
        isInsideTableHead = previousHeadState
    }
    mutating func visitTableHead(_ tableHead: Table.Head) {
        let previousHeadState = isInsideTableHead
        isInsideTableHead = true
        currentTableColumn = 0
        result += "<thead><tr>"
        descendInto(tableHead)
        result += "</tr></thead>"
        isInsideTableHead = previousHeadState
    }
    mutating func visitTableBody(_ tableBody: Table.Body) {
        result += "<tbody>"
        descendInto(tableBody)
        result += "</tbody>"
    }
    mutating func visitTableRow(_ tableRow: Table.Row) {
        currentTableColumn = 0
        result += "<tr>"
        descendInto(tableRow)
        result += "</tr>"
    }
    mutating func visitTableCell(_ tableCell: Table.Cell) {
        guard tableCell.colspan > 0, tableCell.rowspan > 0 else { return }
        let tag = isInsideTableHead ? "th" : "td"
        var attributes = isInsideTableHead ? " scope=\"col\"" : ""
        if currentTableColumn < tableColumnAlignments.count,
            let alignment = tableColumnAlignments[currentTableColumn]
        {
            let value =
                switch alignment {
                case .left: "left"
                case .center: "center"
                case .right: "right"
                }
            attributes += " class=\"scholium-table-align-\(value)\""
        }
        if tableCell.colspan > 1 { attributes += " colspan=\"\(tableCell.colspan)\"" }
        if tableCell.rowspan > 1 { attributes += " rowspan=\"\(tableCell.rowspan)\"" }
        currentTableColumn += Int(tableCell.colspan)
        result += "<\(tag) dir=\"auto\"\(attributes)>"
        descendInto(tableCell)
        result += "</\(tag)>"
    }

    private mutating func appendTextReplacingTokens(_ value: String) {
        var remaining = value[...]
        while !remaining.isEmpty {
            let candidate = inlineHTML.compactMap { key, html -> (String.Index, String, String)? in
                guard let range = remaining.range(of: key) else { return nil }
                return (range.lowerBound, key, html)
            }.min { $0.0 < $1.0 }
            guard let candidate, let range = remaining.range(of: candidate.1) else {
                result += SafeMarkdownRenderer.escapeHTML(String(remaining))
                break
            }
            result += SafeMarkdownRenderer.escapeHTML(String(remaining[..<range.lowerBound]))
            result += candidate.2
            remaining = remaining[range.upperBound...]
        }
    }

    private mutating func sourceAttributes(for kind: MarkdownBlockKind) -> String {
        guard let span = nextSourceSpan(for: kind) else { return "" }
        return " \(SafeMarkdownRenderer.sourceAttributes(span))"
    }

    private mutating func nextSourceSpan(for kind: MarkdownBlockKind) -> SourceSpan? {
        let index = blockSourceIndices[kind, default: 0]
        guard let spans = blockSourceSpans[kind], index < spans.count else { return nil }
        blockSourceIndices[kind] = index + 1
        return spans[index]
    }

    private func blockToken(in rawHTML: String) -> String? {
        guard
            let expression = try? NSRegularExpression(
                pattern: #"^\s*<div data-scholium-block-token=\"([^\"]+)\"></div>\s*$"#
            ),
            let match = expression.firstMatch(
                in: rawHTML,
                range: NSRange(location: 0, length: (rawHTML as NSString).length)
            )
        else { return nil }
        return (rawHTML as NSString).substring(with: match.range(at: 1))
    }

    private func isApprovedExternal(_ destination: String) -> Bool {
        guard let scheme = URL(string: destination)?.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto", "zotero"].contains(scheme)
    }

    func renderedHTML(source: String, bodyUTF16Offset: Int) -> String {
        guard !quoteMetadata.isEmpty else { return result }
        let parts = parsedQuoteParts()
        let normalized = SafeMarkdownRenderer.normalizeQuoteParts(
            parts,
            source: source,
            bodyUTF16Offset: bodyUTF16Offset
        )
        return SafeMarkdownRenderer.renderQuoteParts(normalized)
    }

    private func parsedQuoteParts() -> [SafeHTMLPart] {
        var roots: [SafeHTMLPart] = []
        var frames: [SafeHTMLQuoteFrame] = []

        func append(_ part: SafeHTMLPart) {
            if frames.isEmpty {
                roots.append(part)
            } else {
                frames[frames.count - 1].node.children.append(part)
            }
        }

        var cursor = result.startIndex
        while cursor < result.endIndex,
            let tokenStart = result.range(
                of: Self.quoteTokenStart,
                range: cursor..<result.endIndex
            )
        {
            if tokenStart.lowerBound > cursor {
                append(.html(String(result[cursor..<tokenStart.lowerBound])))
            }
            guard
                let tokenEnd = result.range(
                    of: Self.quoteTokenEnd,
                    range: tokenStart.upperBound..<result.endIndex
                )
            else {
                append(.html(String(result[tokenStart.lowerBound..<result.endIndex])))
                cursor = result.endIndex
                break
            }
            let payload = String(result[tokenStart.upperBound..<tokenEnd.lowerBound])
            if payload.hasPrefix("open:") {
                let identifier = String(payload.dropFirst("open:".count))
                let metadata =
                    quoteMetadata[identifier]
                    ?? SafeHTMLQuoteMetadata(span: nil, depth: 1)
                frames.append(
                    SafeHTMLQuoteFrame(
                        identifier: identifier,
                        node: SafeHTMLQuoteNode(metadata: metadata, children: [])
                    ))
            } else if payload.hasPrefix("close:"),
                let frame = frames.last,
                frame.identifier == String(payload.dropFirst("close:".count))
            {
                _ = frames.removeLast()
                append(.quote(frame.node))
            } else {
                append(.html(String(result[tokenStart.lowerBound..<tokenEnd.upperBound])))
            }
            cursor = tokenEnd.upperBound
        }
        if cursor < result.endIndex {
            append(.html(String(result[cursor..<result.endIndex])))
        }
        while let frame = frames.popLast() {
            append(.quote(frame.node))
        }
        return roots
    }
}
