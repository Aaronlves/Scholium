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
        let html = renderBody(document: document, semantic: semantic, depth: 0)
        return RenderedMarkdownDocument(htmlBody: html, semanticDocument: semantic)
    }

    private struct Replacement {
        let range: NSRange
        let text: String
    }

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
        let blockSourceSpans: [MarkdownBlockKind: [SourceSpan]] = depth == 0
            ? Dictionary(grouping: semantic.blocks.filter { block in
                !(outerCallouts.map(\.span) + removedDefinitionSpans).contains {
                    $0.utf16LowerBound <= block.span.utf16LowerBound
                        && $0.utf16UpperBound >= block.span.utf16UpperBound
                }
            }, by: \.kind).mapValues { blocks in
                blocks.map(\.span).sorted { $0.utf16LowerBound < $1.utf16LowerBound }
            }
            : [:]
        for (index, callout) in outerCallouts.enumerated() {
            guard let relative = relativeRange(callout.span, bodyStart: bodyStart, bodyLength: bodyLength) else { continue }
            let key = "\(nonce)-block-\(index)"
            let nestedLinkSpans = semantic.links.enumerated().compactMap { linkIndex, link -> SourceSpan? in
                guard link.span.utf16LowerBound >= callout.headerSpan.utf16UpperBound,
                      link.span.utf16UpperBound <= callout.span.utf16UpperBound else { return nil }
                return locatedSpan(
                    at: linkIndex,
                    from: locatedLinkSpans,
                    fallback: link.span
                )
            }
            blockHTML[key] = renderCallout(
                callout,
                locatedLinkSpans: nestedLinkSpans,
                depth: depth + 1
            )
            replacements.append(Replacement(
                range: relative,
                text: "\n<div data-scholium-block-token=\"\(key)\"></div>\n"
            ))
        }

        for definition in semantic.footnoteDefinitions where !definition.isInline {
            guard let relative = relativeRange(definition.span, bodyStart: bodyStart, bodyLength: bodyLength),
                  !overlaps(relative, replacements.map(\.range)) else { continue }
            replacements.append(Replacement(range: relative, text: ""))
        }

        for (index, expression) in semantic.mathExpressions.enumerated() {
            guard let relative = relativeRange(
                expression.span,
                bodyStart: bodyStart,
                bodyLength: bodyLength
            ), !overlaps(relative, replacements.map(\.range)) else { continue }
            let rawSource = (document.body as NSString).substring(with: relative)
            switch expression.kind {
            case .inline:
                let key = "SCHOLIUMINLINETOKEN\(nonce)M\(index)"
                inlineHTML[key] = renderMath(expression, rawSource: rawSource)
                replacements.append(Replacement(range: relative, text: key))
            case .display:
                let key = "\(nonce)-math-\(index)"
                blockHTML[key] = renderMath(expression, rawSource: rawSource)
                replacements.append(Replacement(
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
                  !overlaps(relative, replacements.map(\.range)) else { continue }
            let key = "SCHOLIUMINLINETOKEN\(nonce)F\(reference.ordinal)R\(reference.occurrence)"
            let definitionExists = definitionsByIdentifier[reference.identifier] != nil
            inlineHTML[key] = renderFootnoteReference(reference, definitionExists: definitionExists)
            replacements.append(Replacement(range: relative, text: key))
        }

        for (index, link) in semantic.links.enumerated() where link.syntax != .markdown {
            guard let relative = relativeRange(link.span, bodyStart: bodyStart, bodyLength: bodyLength),
                  !overlaps(relative, replacements.map(\.range)) else { continue }
            let key = "SCHOLIUMINLINETOKEN\(nonce)L\(index)"
            inlineHTML[key] = renderWikilink(
                link,
                locatedSpan: locatedSpan(
                    at: index,
                    from: locatedLinkSpans,
                    fallback: link.span
                )
            )
            replacements.append(Replacement(range: relative, text: key))
        }

        let literalRanges = semantic.blocks.compactMap { block -> NSRange? in
            guard block.kind == .code || block.kind == .html else { return nil }
            return relativeRange(block.span, bodyStart: bodyStart, bodyLength: bodyLength)
        } + inlineLiteralRanges(in: document.body)
        let body = document.body as NSString
        for (index, highlight) in semantic.inlines
            .filter({ $0.kind == .highlight })
            .enumerated() {
            guard let relative = relativeRange(
                highlight.span,
                bodyStart: bodyStart,
                bodyLength: bodyLength
            ), relative.length > 4,
               !overlaps(relative, literalRanges),
               !overlaps(relative, replacements.map(\.range)) else { continue }
            let key = "SCHOLIUMINLINETOKEN\(nonce)H\(index)"
            let contentRange = NSRange(location: relative.location + 2, length: relative.length - 4)
            inlineHTML[key] = "<mark class=\"scholium-highlight\">\(escapeHTML(body.substring(with: contentRange)))</mark>"
            replacements.append(Replacement(range: relative, text: key))
        }

        let transformed = apply(replacements, to: document.body)
        let parsed = Document(parsing: transformed, options: [.parseBlockDirectives])
        var visitor = SafeHTMLVisitor(
            blockHTML: blockHTML,
            inlineHTML: inlineHTML,
            blockSourceSpans: blockSourceSpans
        )
        visitor.visit(parsed)

        let footnoteSection = renderFootnoteSection(
            semantic.footnoteDefinitions,
            depth: depth + 1
        )
        return visitor.result + footnoteSection
    }

    private static func renderCallout(
        _ callout: CalloutBlock,
        locatedLinkSpans: [SourceSpan],
        depth: Int
    ) -> String {
        let roleLabel = escapeHTML(callout.role.displayLabel)
        let purpose = escapeAttribute(callout.role.purpose)
        let accessibleRole = escapeAttribute("\(callout.role.displayLabel). \(callout.role.purpose)")
        let roleHTML = "<span class=\"scholium-callout-role\" dir=\"auto\" title=\"\(purpose)\" aria-label=\"\(accessibleRole)\">\(roleLabel)</span>"
        let titleHTML = callout.title.map {
            "<span class=\"scholium-callout-title\" dir=\"auto\">\(renderInlineMarkdown($0))</span>"
        } ?? ""
        let heading = "<span class=\"scholium-callout-heading\" role=\"heading\" aria-level=\"2\">\(roleHTML)\(titleHTML)</span>"
        let fragment = NoteDocument(relativePath: "callout.md", rawContent: callout.bodySource)
        let fragmentSemantic = MarkdownSemanticDocument(parsing: fragment)
        let renderedBody = renderBody(
            document: fragment,
            semantic: fragmentSemantic,
            depth: depth,
            locatedLinkSpans: fragmentSemantic.links.count == locatedLinkSpans.count
                ? locatedLinkSpans
                : nil
        )
        let semanticBody = callout.role == .quote
            ? "<blockquote class=\"scholium-callout-quotation\" dir=\"auto\">\(renderedBody)</blockquote>"
            : renderedBody
        let body = "<div class=\"scholium-callout-body\"><span class=\"scholium-callout-signature\" aria-hidden=\"true\"></span><div class=\"scholium-callout-content\">\(semanticBody)</div></div>"
        let attributes = "class=\"scholium-callout scholium-callout-\(callout.role.rawValue)\" data-callout=\"\(escapeAttribute(callout.kind))\" data-callout-source=\"\(escapeAttribute(callout.rawKind))\" data-callout-fold=\"\(callout.foldState.rawValue)\" \(sourceAttributes(callout.span)) data-scholium-protected=\"callout\""
        switch callout.foldState {
        case .fixed:
            return "<aside \(attributes)><header>\(heading)</header>\(body)</aside>"
        case .expanded, .collapsed:
            let open = callout.foldState == .expanded ? " open" : ""
            return "<details \(attributes)\(open)><summary>\(heading)<span class=\"scholium-callout-fold-mark\" aria-hidden=\"true\"></span></summary>\(body)</details>"
        }
    }

    private static func renderFootnoteReference(
        _ reference: FootnoteReference,
        definitionExists: Bool
    ) -> String {
        let referenceID = "fnref-\(reference.ordinal)-\(reference.occurrence)"
        let target = "fn-\(reference.ordinal)"
        let disabled = definitionExists ? "" : " disabled aria-disabled=\"true\""
        return "<sup id=\"\(referenceID)\" class=\"footnote-reference-wrap\" \(sourceAttributes(reference.span)) data-scholium-protected=\"footnote\"><button type=\"button\" class=\"footnote-reference\" data-footnote=\"\(reference.ordinal)\" data-target=\"\(target)\" aria-label=\"Footnote \(reference.ordinal)\"\(disabled)>\(reference.ordinal)</button></sup>"
    }

    private static func renderMath(_ expression: MathExpression, rawSource: String) -> String {
        let encoded = Data(expression.content.utf8).base64EncodedString()
        let kind = expression.kind.rawValue
        let tag = expression.kind == .display ? "div" : "span"
        return "<\(tag) class=\"scholium-math scholium-math-\(kind)\" dir=\"ltr\" data-math-kind=\"\(kind)\" data-math-source=\"\(encoded)\" \(sourceAttributes(expression.span)) data-scholium-protected=\"math\"><code class=\"scholium-math-source\" dir=\"ltr\">\(escapeHTML(rawSource))</code></\(tag)>"
    }

    private static func renderInlineMarkdown(_ source: String) -> String {
        let parsed = Document(parsing: source)
        var visitor = SafeHTMLVisitor(blockHTML: [:], inlineHTML: [:], blockSourceSpans: [:])
        visitor.visit(parsed)
        let rendered = visitor.result
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
            return "<li id=\"fn-\(ordinal)\" dir=\"auto\" data-footnote=\"\(ordinal)\" \(sourceAttributes(definition.span))><div class=\"footnote-content\">\(content)</div><button type=\"button\" class=\"footnote-return\" data-footnote=\"\(ordinal)\" aria-label=\"Return to footnote reference \(ordinal)\">↩</button></li>"
        }.joined()
        return "<div class=\"scholium-footnotes-slot\"><section class=\"footnotes\" data-scholium-protected=\"footnotes\" aria-label=\"Footnotes\"><hr><ol>\(items)</ol></section></div>"
    }

    private static func renderWikilink(
        _ link: LinkOccurrence,
        locatedSpan: SourceSpan
    ) -> String {
        let display = link.alias ?? (link.target.isEmpty ? link.fragment ?? "Link" : link.target)
        let destination = link.target + (link.fragment.map { "#\($0)" } ?? "")
        let decodedDestination = destination.removingPercentEncoding ?? destination
        let encoded = decodedDestination.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? decodedDestination
        if link.syntax == .embed {
            return "<a class=\"wiki-link scholium-embed\" dir=\"auto\" href=\"scholium-note:\(escapeAttribute(encoded))\" \(sourceAttributes(locatedSpan)) data-scholium-protected=\"embed\">\(escapeHTML(display))</a>"
        }
        let relation = link.relationship.map { " data-relationship=\"\(escapeAttribute($0.rawValue))\"" } ?? ""
        let vectorClass = link.vectorKind == nil ? "" : " scholium-vector"
        let vector = link.vectorKind.map { " data-vector-kind=\"\(escapeAttribute($0.rawValue))\"" } ?? ""
        return "<a class=\"wiki-link\(vectorClass)\" dir=\"auto\" href=\"scholium-note:\(escapeAttribute(encoded))\" \(sourceAttributes(locatedSpan))\(relation)\(vector)>\(escapeHTML(display))</a>"
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
                ranges.append(NSRange(
                    location: openingRange.location,
                    length: source.length - openingRange.location
                ))
                break
            }
            ranges.append(NSRange(
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

private struct SafeHTMLVisitor: MarkupWalker {
    var result = ""
    let blockHTML: [String: String]
    let inlineHTML: [String: String]
    let blockSourceSpans: [MarkdownBlockKind: [SourceSpan]]
    var blockSourceIndices: [MarkdownBlockKind: Int] = [:]
    var tableColumnAlignments: [Table.ColumnAlignment?] = []
    var currentTableColumn = 0
    var isInsideTableHead = false

    mutating func visitDocument(_ document: Document) { descendInto(document) }
    mutating func visitParagraph(_ paragraph: Paragraph) {
        result += "<p dir=\"auto\"\(sourceAttributes(for: .paragraph))>"; descendInto(paragraph); result += "</p>\n"
    }
    mutating func visitHeading(_ heading: Heading) {
        let span = nextSourceSpan(for: .heading)
        let anchor = span.map { " id=\"scholium-line-\($0.start.line)\" \(SafeMarkdownRenderer.sourceAttributes($0))" } ?? ""
        result += "<h\(heading.level) dir=\"auto\"\(anchor)>"; descendInto(heading); result += "</h\(heading.level)>\n"
    }
    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        result += "<blockquote dir=\"auto\"\(sourceAttributes(for: .blockQuote))>"; descendInto(blockQuote); result += "</blockquote>\n"
    }
    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let language = codeBlock.language.map { " class=\"language-\(SafeMarkdownRenderer.escapeAttribute($0))\"" } ?? ""
        result += "<pre dir=\"ltr\"\(sourceAttributes(for: .code))><code dir=\"ltr\"\(language)>\(SafeMarkdownRenderer.escapeHTML(codeBlock.code))</code></pre>\n"
    }
    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        result += "<code dir=\"ltr\">\(SafeMarkdownRenderer.escapeHTML(inlineCode.code))</code>"
    }
    mutating func visitEmphasis(_ emphasis: Emphasis) {
        result += "<em>"; descendInto(emphasis); result += "</em>"
    }
    mutating func visitStrong(_ strong: Strong) {
        result += "<strong>"; descendInto(strong); result += "</strong>"
    }
    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        result += "<del>"; descendInto(strikethrough); result += "</del>"
    }
    mutating func visitLineBreak(_ lineBreak: LineBreak) { result += "<br>\n" }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) { result += "\n" }
    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) { result += "<hr\(sourceAttributes(for: .thematicBreak))>\n" }
    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        result += "<ul\(sourceAttributes(for: .unorderedList))>"; descendInto(unorderedList); result += "</ul>\n"
    }
    mutating func visitOrderedList(_ orderedList: OrderedList) {
        let start = orderedList.startIndex == 1 ? "" : " start=\"\(orderedList.startIndex)\""
        result += "<ol\(start)\(sourceAttributes(for: .orderedList))>"; descendInto(orderedList); result += "</ol>\n"
    }
    mutating func visitListItem(_ listItem: ListItem) {
        let taskClass = listItem.checkbox == nil
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
            let encoded = decodedDestination.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
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
            result += "<pre class=\"raw-html\" dir=\"ltr\"\(sourceAttributes(for: .html))><code dir=\"ltr\">\(SafeMarkdownRenderer.escapeHTML(html.rawHTML))</code></pre>"
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
        result += "<thead><tr>"; descendInto(tableHead); result += "</tr></thead>"
        isInsideTableHead = previousHeadState
    }
    mutating func visitTableBody(_ tableBody: Table.Body) {
        result += "<tbody>"; descendInto(tableBody); result += "</tbody>"
    }
    mutating func visitTableRow(_ tableRow: Table.Row) {
        currentTableColumn = 0
        result += "<tr>"; descendInto(tableRow); result += "</tr>"
    }
    mutating func visitTableCell(_ tableCell: Table.Cell) {
        guard tableCell.colspan > 0, tableCell.rowspan > 0 else { return }
        let tag = isInsideTableHead ? "th" : "td"
        var attributes = isInsideTableHead ? " scope=\"col\"" : ""
        if currentTableColumn < tableColumnAlignments.count,
           let alignment = tableColumnAlignments[currentTableColumn] {
            let value = switch alignment {
            case .left: "left"
            case .center: "center"
            case .right: "right"
            }
            attributes += " class=\"scholium-table-align-\(value)\""
        }
        if tableCell.colspan > 1 { attributes += " colspan=\"\(tableCell.colspan)\"" }
        if tableCell.rowspan > 1 { attributes += " rowspan=\"\(tableCell.rowspan)\"" }
        currentTableColumn += Int(tableCell.colspan)
        result += "<\(tag) dir=\"auto\"\(attributes)>"; descendInto(tableCell); result += "</\(tag)>"
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
        guard let expression = try? NSRegularExpression(
            pattern: #"^\s*<div data-scholium-block-token=\"([^\"]+)\"></div>\s*$"#
        ), let match = expression.firstMatch(
            in: rawHTML,
            range: NSRange(location: 0, length: (rawHTML as NSString).length)
        ) else { return nil }
        return (rawHTML as NSString).substring(with: match.range(at: 1))
    }

    private func isApprovedExternal(_ destination: String) -> Bool {
        guard let scheme = URL(string: destination)?.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto", "zotero"].contains(scheme)
    }
}
