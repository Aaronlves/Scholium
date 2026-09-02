import Foundation
import Markdown

public struct SourcePosition: Codable, Hashable, Sendable {
    public let line: Int
    public let utf8Column: Int
    public let utf16Column: Int

    public init(line: Int, utf8Column: Int, utf16Column: Int) {
        self.line = line
        self.utf8Column = utf8Column
        self.utf16Column = utf16Column
    }
}

public struct SourceSpan: Codable, Hashable, Sendable {
    public let utf8LowerBound: Int
    public let utf8UpperBound: Int
    public let utf16LowerBound: Int
    public let utf16UpperBound: Int
    public let start: SourcePosition
    public let end: SourcePosition

    public init(
        utf8LowerBound: Int,
        utf8UpperBound: Int,
        utf16LowerBound: Int,
        utf16UpperBound: Int,
        start: SourcePosition,
        end: SourcePosition
    ) {
        self.utf8LowerBound = utf8LowerBound
        self.utf8UpperBound = utf8UpperBound
        self.utf16LowerBound = utf16LowerBound
        self.utf16UpperBound = utf16UpperBound
        self.start = start
        self.end = end
    }

    public var utf8Range: Range<Int> { utf8LowerBound..<utf8UpperBound }
    public var utf16Range: Range<Int> { utf16LowerBound..<utf16UpperBound }
    public var nsRange: NSRange {
        NSRange(location: utf16LowerBound, length: utf16UpperBound - utf16LowerBound)
    }
}

public enum MarkdownBlockKind: String, Codable, Hashable, Sendable {
    case paragraph
    case heading
    case blockQuote
    case code
    case unorderedList
    case orderedList
    case listItem
    case table
    case thematicBreak
    case html
    case other
}

public struct MarkdownBlock: Codable, Hashable, Sendable {
    public let kind: MarkdownBlockKind
    public let span: SourceSpan
}

public enum MarkdownInlineKind: String, Codable, Hashable, Sendable {
    case strong
    case emphasis
    case strikethrough
    case highlight
    case code
    case link
    case image
}

public struct MarkdownInline: Codable, Hashable, Sendable {
    public let kind: MarkdownInlineKind
    public let span: SourceSpan

    public init(kind: MarkdownInlineKind, span: SourceSpan) {
        self.kind = kind
        self.span = span
    }
}

public struct HeadingNode: Codable, Hashable, Sendable {
    public let level: Int
    public let text: String
    public let span: SourceSpan
}

public enum CalloutFoldState: String, Codable, Hashable, Sendable {
    case fixed
    case expanded
    case collapsed
}

public enum CalloutSemanticRole: String, Codable, Hashable, Sendable, CaseIterable {
    case orient
    case cite
    case connect
    case state
    case illustrate
    case quote
    case flag
    case neutral

    public var displayLabel: String {
        switch self {
        case .orient: "Orientation"
        case .cite: "Source"
        case .connect: "Connections"
        case .state: "Statement"
        case .illustrate: "Illustration"
        case .quote: "Quotation"
        case .flag: "Caution"
        case .neutral: "Note"
        }
    }

    public var purpose: String {
        switch self {
        case .orient: "Introduces the note's purpose, scope, and route."
        case .cite: "Records sources that anchor the note without implying that they support every claim."
        case .connect: "Routes the reader to a curated set of neighboring knowledge objects."
        case .state: "Isolates a claim, definition, principle, formula, distinction, or compact argument without endorsing it."
        case .illustrate: "Presents a scenario, example, thought experiment, or test case used in reasoning."
        case .quote: "Preserves source-specific wording with attribution."
        case .flag: "Marks a limitation, unresolved dependency, source restriction, or interpretive warning."
        case .neutral: "Preserves an unsupported callout without assigning it a research role."
        }
    }
}

public enum CalloutSemanticVocabulary {
    public static let preferredIdentifiers: Set<String> = [
        "orient", "cite", "connect", "state", "illustrate", "quote", "flag",
    ]

    public static let aliasesByCanonicalIdentifier: [String: [String]] = [
        "orient": ["mini"],
        "cite": ["bibli", "bibliography", "cited"],
        "connect": ["project"],
        "state": ["definition", "principle", "theorem", "argument", "objection", "reply"],
        "illustrate": ["example", "case", "dialogue"],
        "quote": ["quotation", "author", "long-quote"],
        "flag": ["warning", "caution", "source-warning", "torn", "question"],
    ]

    public static func canonicalIdentifier(for raw: String) -> String {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":")))
            .lowercased()
        return aliasesByCanonicalIdentifier.first(where: { $0.value.contains(normalized) })?.key
            ?? normalized
    }

    public static func role(for raw: String) -> CalloutSemanticRole {
        CalloutSemanticRole(rawValue: canonicalIdentifier(for: raw)) ?? .neutral
    }
}

/// The delivery-neutral Markdown vocabulary required by an editing surface.
///
/// This value is derived from Contracts authorities. It contains no cursor,
/// selection, JavaScript, repository, or mutable configuration state.
public struct MarkdownEditingDialect: Codable, Hashable, Sendable {
    public struct Callout: Codable, Hashable, Sendable {
        public let identifier: String
        public let aliases: [String]
        public let label: String
        public let meaning: String
    }

    public struct LinkAnnotationSyntax: Codable, Hashable, Sendable {
        public let openingDelimiter: String
        public let closingDelimiter: String
        public let escapeCharacter: String
        public let allowsMultiline: Bool
        public let allowsNesting: Bool
    }

    public struct Mathematics: Codable, Hashable, Sendable {
        public let inlineDelimiter: String
        public let displayDelimiter: String
        public let singleDollarInline: Bool
    }

    public struct Footnotes: Codable, Hashable, Sendable {
        public let namedReferenceOpening: String
        public let namedReferenceClosing: String
        public let definitionSeparator: String
        public let inlineOpening: String
        public let continuationIndentSpaces: Int
        public let allowsTabContinuation: Bool
        public let caseSensitiveIdentifiers: Bool
        public let ordinalByFirstReference: Bool
    }

    public let version: Int
    public let callouts: [Callout]
    public let linkAnnotation: LinkAnnotationSyntax
    public let footnotes: Footnotes
    public let mathematics: Mathematics

    public init(
        version: Int,
        callouts: [Callout],
        linkAnnotation: LinkAnnotationSyntax,
        footnotes: Footnotes,
        mathematics: Mathematics
    ) {
        self.version = version
        self.callouts = callouts
        self.linkAnnotation = linkAnnotation
        self.footnotes = footnotes
        self.mathematics = mathematics
    }

    public static let current = MarkdownEditingDialect(
        version: 5,
        callouts: CalloutSemanticRole.allCases.compactMap { role in
            guard role != .neutral else { return nil }
            return Callout(
                identifier: role.rawValue,
                aliases: CalloutSemanticVocabulary.aliasesByCanonicalIdentifier[role.rawValue] ?? [],
                label: role.displayLabel,
                meaning: role.purpose
            )
        },
        linkAnnotation: LinkAnnotationSyntax(
            openingDelimiter: "{{",
            closingDelimiter: "}}",
            escapeCharacter: "\\",
            allowsMultiline: true,
            allowsNesting: false
        ),
        footnotes: Footnotes(
            namedReferenceOpening: "[^",
            namedReferenceClosing: "]",
            definitionSeparator: ":",
            inlineOpening: "^[",
            continuationIndentSpaces: 2,
            allowsTabContinuation: true,
            caseSensitiveIdentifiers: true,
            ordinalByFirstReference: true
        ),
        mathematics: Mathematics(
            inlineDelimiter: "$",
            displayDelimiter: "$$",
            singleDollarInline: true
        )
    )
}

public struct CalloutBlock: Codable, Hashable, Sendable {
    public let rawKind: String
    public let kind: String
    public let role: CalloutSemanticRole
    public let title: String?
    public let bodySource: String
    public let quoteDepth: Int
    public let foldState: CalloutFoldState
    public let span: SourceSpan
    public let headerSpan: SourceSpan
}

public struct FootnoteDefinition: Codable, Hashable, Sendable {
    public let identifier: String
    public let content: String
    public let ordinal: Int?
    public let isInline: Bool
    public let span: SourceSpan
}

public struct FootnoteReference: Codable, Hashable, Sendable {
    public let identifier: String
    public let ordinal: Int
    public let occurrence: Int
    public let isInline: Bool
    public let span: SourceSpan
}

public enum MathExpressionKind: String, Codable, Hashable, Sendable {
    case inline
    case display
}

public struct MathExpression: Codable, Hashable, Sendable {
    public let kind: MathExpressionKind
    public let content: String
    public let delimiterLength: Int
    public let span: SourceSpan
    public let contentSpan: SourceSpan
}

public enum LinkSyntax: String, Codable, Hashable, Sendable {
    case wikilink
    case markdown
    case embed
}

public struct LinkAnnotation: Codable, Hashable, Sendable {
    /// Exact authored Markdown between the annotation delimiters.
    public let markdown: String
    /// Visible semantic text used by Search and compact projections.
    public let text: String
    /// Exact `{{...}}` source range.
    public let span: SourceSpan
    /// Exact authored Markdown range inside the delimiters.
    public let contentSpan: SourceSpan

    public init(markdown: String, text: String, span: SourceSpan, contentSpan: SourceSpan) {
        self.markdown = markdown
        self.text = text
        self.span = span
        self.contentSpan = contentSpan
    }
}

public enum LinkOccurrenceResolution: Codable, Hashable, Sendable {
    case unresolved
    case resolved(VaultQualifiedNoteID)
    case ambiguous([VaultQualifiedNoteID])
    case broken(String)
}

public struct VaultQualifiedNoteID: Codable, Hashable, Sendable, Comparable {
    public let vaultID: UUID
    public let relativePath: String

    public init(vaultID: UUID, relativePath: String) {
        self.vaultID = vaultID
        self.relativePath = relativePath
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.vaultID != rhs.vaultID {
            return lhs.vaultID.uuidString < rhs.vaultID.uuidString
        }
        return lhs.relativePath < rhs.relativePath
    }
}

public struct LinkOccurrence: Codable, Hashable, Sendable {
    public let syntax: LinkSyntax
    public let target: String
    public let alias: String?
    public let fragment: String?
    public let annotation: LinkAnnotation?
    public let localContext: String
    public let isExternal: Bool
    /// Whole valid occurrence, including an adjacent annotation when present.
    public let span: SourceSpan
    /// The exact link source, excluding an adjacent annotation.
    public let linkSpan: SourceSpan
    public var resolution: LinkOccurrenceResolution

    public init(
        syntax: LinkSyntax,
        target: String,
        alias: String?,
        fragment: String?,
        annotation: LinkAnnotation? = nil,
        localContext: String = "",
        isExternal: Bool,
        span: SourceSpan,
        linkSpan: SourceSpan? = nil,
        resolution: LinkOccurrenceResolution = .unresolved
    ) {
        self.syntax = syntax
        self.target = target
        self.alias = alias
        self.fragment = fragment
        self.annotation = annotation
        self.localContext = localContext
        self.isExternal = isExternal
        self.span = span
        self.linkSpan = linkSpan ?? span
        self.resolution = resolution
    }
}

public enum MarkdownDiagnosticSeverity: String, Codable, Hashable, Sendable {
    case information
    case warning
    case error
}

public enum MarkdownDiagnosticCode: String, Codable, Hashable, Sendable {
    case unknownCallout
    case duplicateFootnote
    case undefinedFootnote
    case unreferencedFootnote
    case malformedMath
    case malformedComment
    case malformedLinkAnnotation
}

public struct MarkdownDiagnostic: Codable, Hashable, Sendable {
    public let code: MarkdownDiagnosticCode
    public let severity: MarkdownDiagnosticSeverity
    public let message: String
    public let span: SourceSpan?
}

public struct MarkdownSemanticDocument: Codable, Hashable, Sendable {
    public let fingerprint: DocumentFingerprint
    public let blocks: [MarkdownBlock]
    public let inlines: [MarkdownInline]
    public let headings: [HeadingNode]
    public let callouts: [CalloutBlock]
    public let footnoteDefinitions: [FootnoteDefinition]
    public let footnoteReferences: [FootnoteReference]
    public let mathExpressions: [MathExpression]
    public let links: [LinkOccurrence]
    public let diagnostics: [MarkdownDiagnostic]

    public init(parsing document: NoteDocument) {
        self = MarkdownSemanticParser.parse(document)
    }

    public init(
        fingerprint: DocumentFingerprint,
        blocks: [MarkdownBlock],
        inlines: [MarkdownInline] = [],
        headings: [HeadingNode],
        callouts: [CalloutBlock],
        footnoteDefinitions: [FootnoteDefinition],
        footnoteReferences: [FootnoteReference],
        mathExpressions: [MathExpression],
        links: [LinkOccurrence],
        diagnostics: [MarkdownDiagnostic]
    ) {
        self.fingerprint = fingerprint
        self.blocks = blocks
        self.inlines = inlines
        self.headings = headings
        self.callouts = callouts
        self.footnoteDefinitions = footnoteDefinitions
        self.footnoteReferences = footnoteReferences
        self.mathExpressions = mathExpressions
        self.links = links
        self.diagnostics = diagnostics
    }
}

public enum MarkdownSemanticParser {
    /// Parses links in a standalone prose fragment without allowing a leading
    /// `---` sequence to be reinterpreted as Note frontmatter. Returned spans
    /// are relative to the exact fragment supplied by the caller.
    package static func links(inFragment source: String) -> [LinkOccurrence] {
        let prefix = "\n"
        let document = NoteDocument(
            relativePath: "research-record-fragment.md",
            rawContent: prefix + source
        )
        func removingPrefix(from span: SourceSpan) -> SourceSpan {
            SourceSpan(
                utf8LowerBound: span.utf8LowerBound - prefix.utf8.count,
                utf8UpperBound: span.utf8UpperBound - prefix.utf8.count,
                utf16LowerBound: span.utf16LowerBound - prefix.utf16.count,
                utf16UpperBound: span.utf16UpperBound - prefix.utf16.count,
                start: SourcePosition(
                    line: span.start.line - 1,
                    utf8Column: span.start.utf8Column,
                    utf16Column: span.start.utf16Column
                ),
                end: SourcePosition(
                    line: span.end.line - 1,
                    utf8Column: span.end.utf8Column,
                    utf16Column: span.end.utf16Column
                )
            )
        }
        return parse(document).links.compactMap { occurrence in
            guard occurrence.span.utf8LowerBound >= prefix.utf8.count,
                occurrence.span.utf16LowerBound >= prefix.utf16.count
            else { return nil }
            return LinkOccurrence(
                syntax: occurrence.syntax,
                target: occurrence.target,
                alias: occurrence.alias,
                fragment: occurrence.fragment,
                annotation: occurrence.annotation.map { annotation in
                    LinkAnnotation(
                        markdown: annotation.markdown,
                        text: annotation.text,
                        span: removingPrefix(from: annotation.span),
                        contentSpan: removingPrefix(from: annotation.contentSpan)
                    )
                },
                localContext: occurrence.localContext,
                isExternal: occurrence.isExternal,
                span: removingPrefix(from: occurrence.span),
                linkSpan: removingPrefix(from: occurrence.linkSpan)
            )
        }
    }

    public static func parse(_ document: NoteDocument) -> MarkdownSemanticDocument {
        let sourceMapper = SemanticSourceMapper(document.rawContent)
        let bodyOffset = sourceMapper.utf16Offset(forUTF8Offset: document.bodyByteRange.lowerBound) ?? 0
        let bodyMapper = SemanticSourceMapper(document.body)
        let parsed = Document(parsing: document.body, options: [.parseBlockDirectives])

        var blocks: [MarkdownBlock] = []
        var inlines: [MarkdownInline] = []
        var headings: [HeadingNode] = []
        var literalRanges: [NSRange] = []
        collectMarkup(
            parsed,
            bodyMapper: bodyMapper,
            sourceMapper: sourceMapper,
            bodyUTF16Offset: bodyOffset,
            blocks: &blocks,
            inlines: &inlines,
            headings: &headings,
            literalRanges: &literalRanges
        )

        let commentResult = parseComments(
            body: document.body,
            bodyUTF16Offset: bodyOffset,
            sourceMapper: sourceMapper
        )
        literalRanges.append(contentsOf: commentResult.ranges)
        literalRanges.append(contentsOf: inlineCodeRanges(in: document.body))
        inlines.append(contentsOf: parseHighlights(
            body: document.body,
            bodyUTF16Offset: bodyOffset,
            sourceMapper: sourceMapper,
            excluded: literalRanges
        ))

        let calloutResult = parseCallouts(
            body: document.body,
            bodyUTF16Offset: bodyOffset,
            sourceMapper: sourceMapper,
            excluded: literalRanges
        )
        let footnoteResult = parseFootnotes(
            body: document.body,
            bodyUTF16Offset: bodyOffset,
            sourceMapper: sourceMapper,
            excluded: literalRanges
        )
        let mathResult = parseMath(
            body: document.body,
            bodyUTF16Offset: bodyOffset,
            sourceMapper: sourceMapper,
            excluded: literalRanges
        )
        let linkResult = parseLinks(
            body: document.body,
            bodyUTF16Offset: bodyOffset,
            sourceMapper: sourceMapper,
            excluded: literalRanges
        )
        return MarkdownSemanticDocument(
            fingerprint: document.fingerprint,
            blocks: blocks.sorted { $0.span.utf16LowerBound < $1.span.utf16LowerBound },
            inlines: inlines.sorted { left, right in
                if left.span.utf16LowerBound != right.span.utf16LowerBound {
                    return left.span.utf16LowerBound < right.span.utf16LowerBound
                }
                return left.span.utf16UpperBound > right.span.utf16UpperBound
            },
            headings: headings.sorted { $0.span.utf16LowerBound < $1.span.utf16LowerBound },
            callouts: calloutResult.callouts,
            footnoteDefinitions: footnoteResult.definitions,
            footnoteReferences: footnoteResult.references,
            mathExpressions: mathResult.expressions,
            links: linkResult.links,
            diagnostics: (commentResult.diagnostics + calloutResult.diagnostics + footnoteResult.diagnostics + mathResult.diagnostics + linkResult.diagnostics).sorted {
                ($0.span?.utf16LowerBound ?? Int.max) < ($1.span?.utf16LowerBound ?? Int.max)
            }
        )
    }

    private static func collectMarkup(
        _ markup: Markup,
        bodyMapper: SemanticSourceMapper,
        sourceMapper: SemanticSourceMapper,
        bodyUTF16Offset: Int,
        blocks: inout [MarkdownBlock],
        inlines: inout [MarkdownInline],
        headings: inout [HeadingNode],
        literalRanges: inout [NSRange]
    ) {
        if let range = markup.range,
           let relativeRange = bodyMapper.nsRange(for: range) {
            let fullRange = NSRange(
                location: bodyUTF16Offset + relativeRange.location,
                length: relativeRange.length
            )
            if let span = sourceMapper.span(for: fullRange) {
                if let heading = markup as? Heading {
                    headings.append(HeadingNode(level: heading.level, text: heading.plainText, span: span))
                }
                if let kind = blockKind(for: markup) {
                    let normalizedRange = rangeWithoutTerminalLineEnding(fullRange, in: sourceMapper.nsSource)
                    if let normalizedSpan = sourceMapper.span(for: normalizedRange) {
                        blocks.append(MarkdownBlock(kind: kind, span: normalizedSpan))
                    }
                }
                if let kind = inlineKind(for: markup) {
                    inlines.append(MarkdownInline(kind: kind, span: span))
                }
                if markup is CodeBlock || markup is InlineCode || markup is HTMLBlock || markup is InlineHTML {
                    literalRanges.append(relativeRange)
                }
            }
        }

        for child in markup.children {
            collectMarkup(
                child,
                bodyMapper: bodyMapper,
                sourceMapper: sourceMapper,
                bodyUTF16Offset: bodyUTF16Offset,
                blocks: &blocks,
                inlines: &inlines,
                headings: &headings,
                literalRanges: &literalRanges
            )
        }
    }

    private static func blockKind(for markup: Markup) -> MarkdownBlockKind? {
        switch markup {
        case is Paragraph: .paragraph
        case is Heading: .heading
        case is BlockQuote: .blockQuote
        case is CodeBlock: .code
        case is UnorderedList: .unorderedList
        case is OrderedList: .orderedList
        case is ListItem: .listItem
        case is Table: .table
        case is ThematicBreak: .thematicBreak
        case is HTMLBlock: .html
        default: nil
        }
    }

    private static func inlineKind(for markup: Markup) -> MarkdownInlineKind? {
        switch markup {
        case is Strong: .strong
        case is Emphasis: .emphasis
        case is Strikethrough: .strikethrough
        case is InlineCode: .code
        case is Link: .link
        case is Image: .image
        default: nil
        }
    }

    private static func parseHighlights(
        body: String,
        bodyUTF16Offset: Int,
        sourceMapper: SemanticSourceMapper,
        excluded: [NSRange]
    ) -> [MarkdownInline] {
        guard let expression = try? NSRegularExpression(pattern: #"(?<!\\)==([^=\r\n]+)=="#) else {
            return []
        }
        let bodyLength = (body as NSString).length
        return expression.matches(
            in: body,
            range: NSRange(location: 0, length: bodyLength)
        ).compactMap { match in
            guard match.numberOfRanges > 1,
                  match.range.length > 4,
                  !intersectsExcluded(match.range, excluded),
                  let span = sourceMapper.span(for: shifted(match.range, by: bodyUTF16Offset)) else {
                return nil
            }
            return MarkdownInline(kind: .highlight, span: span)
        }
    }

    private static func rangeWithoutTerminalLineEnding(
        _ range: NSRange,
        in source: NSString
    ) -> NSRange {
        var length = range.length
        guard length > 0 else { return range }
        let last = source.character(at: range.location + length - 1)
        if last == 0x0A {
            length -= 1
            if length > 0, source.character(at: range.location + length - 1) == 0x0D {
                length -= 1
            }
        } else if last == 0x0D {
            length -= 1
        }
        return NSRange(location: range.location, length: length)
    }

    private struct CalloutParseResult {
        var callouts: [CalloutBlock]
        var diagnostics: [MarkdownDiagnostic]
    }

    private static func parseCallouts(
        body: String,
        bodyUTF16Offset: Int,
        sourceMapper: SemanticSourceMapper,
        excluded: [NSRange]
    ) -> CalloutParseResult {
        let nsBody = body as NSString
        guard let headerRegex = try? NSRegularExpression(
            pattern: #"^(\s*(?:>\s*)+)\[!([^\]\r\n]+)\]([+-])?[ \t]*(.*)$"#
        ) else { return CalloutParseResult(callouts: [], diagnostics: []) }

        var callouts: [CalloutBlock] = []
        var diagnostics: [MarkdownDiagnostic] = []
        var cursor = 0
        while cursor < nsBody.length {
            let lineRange = nsBody.lineRange(for: NSRange(location: cursor, length: 0))
            let contentRange = lineContentRange(lineRange, in: nsBody)
            defer { cursor = max(NSMaxRange(lineRange), cursor + 1) }
            guard !intersectsExcluded(contentRange, excluded),
                  let match = headerRegex.firstMatch(
                    in: body,
                    range: contentRange
                  ) else { continue }

            let prefix = nsBody.substring(with: match.range(at: 1))
            let depth = prefix.reduce(into: 0) { if $1 == ">" { $0 += 1 } }
            guard depth > 0 else { continue }

            var blockEnd = NSMaxRange(lineRange)
            var next = blockEnd
            while next < nsBody.length {
                let candidateLine = nsBody.lineRange(for: NSRange(location: next, length: 0))
                let candidateContent = lineContentRange(candidateLine, in: nsBody)
                let line = nsBody.substring(with: candidateContent)
                guard quoteDepth(of: line) >= depth else { break }
                blockEnd = NSMaxRange(candidateLine)
                next = blockEnd
            }

            let rawKind = nsBody.substring(with: match.range(at: 2))
            let normalizedKind = CalloutSemanticVocabulary.canonicalIdentifier(for: rawKind)
            let title = optionalTrimmed(nsBody.substring(with: match.range(at: 4)))
            let foldState: CalloutFoldState = switch match.range(at: 3).location == NSNotFound
                ? nil
                : nsBody.substring(with: match.range(at: 3)) {
            case "+": .expanded
            case "-": .collapsed
            default: .fixed
            }
            let relativeBlockRange = NSRange(
                location: lineRange.location,
                length: blockEnd - lineRange.location
            )
            guard let span = sourceMapper.span(for: shifted(relativeBlockRange, by: bodyUTF16Offset)),
                  let headerSpan = sourceMapper.span(for: shifted(contentRange, by: bodyUTF16Offset)) else {
                continue
            }

            callouts.append(CalloutBlock(
                rawKind: rawKind,
                kind: normalizedKind,
                role: CalloutSemanticVocabulary.role(for: normalizedKind),
                title: title,
                bodySource: dequotedCalloutBody(
                    nsBody: nsBody,
                    blockRange: relativeBlockRange,
                    headerLineRange: lineRange,
                    depth: depth
                ),
                quoteDepth: depth,
                foldState: foldState,
                span: span,
                headerSpan: headerSpan
            ))

            if !CalloutSemanticVocabulary.preferredIdentifiers.contains(normalizedKind) {
                diagnostics.append(MarkdownDiagnostic(
                    code: .unknownCallout,
                    severity: .information,
                    message: "Unknown callout type '\(rawKind)' is rendered as a neutral note.",
                    span: headerSpan
                ))
            }
        }

        return CalloutParseResult(
            callouts: callouts.sorted { $0.span.utf16LowerBound < $1.span.utf16LowerBound },
            diagnostics: diagnostics
        )
    }

    private struct FootnoteParseResult {
        var definitions: [FootnoteDefinition]
        var references: [FootnoteReference]
        var diagnostics: [MarkdownDiagnostic]
    }

    private struct RawFootnoteDefinition {
        let identifier: String
        let content: String
        let relativeRange: NSRange
        let isInline: Bool
    }

    private struct RawFootnoteReference {
        let identifier: String
        let relativeRange: NSRange
        let isInline: Bool
        let inlineContent: String?
    }

    private static func parseFootnotes(
        body: String,
        bodyUTF16Offset: Int,
        sourceMapper: SemanticSourceMapper,
        excluded: [NSRange]
    ) -> FootnoteParseResult {
        let nsBody = body as NSString
        let definitionRegex = try? NSRegularExpression(
            pattern: #"^\[\^([^\]\r\n]+)\]:[ \t]*(.*)$"#
        )
        let referenceRegex = try? NSRegularExpression(pattern: #"\[\^([^\]\r\n]+)\]"#)
        let inlineRegex = try? NSRegularExpression(pattern: #"\^\[([^\]\r\n]+)\]"#)
        guard let definitionRegex, let referenceRegex, let inlineRegex else {
            return FootnoteParseResult(definitions: [], references: [], diagnostics: [])
        }

        var rawDefinitions: [RawFootnoteDefinition] = []
        var definitionMarkerRanges: [NSRange] = []
        var diagnostics: [MarkdownDiagnostic] = []
        var cursor = 0
        while cursor < nsBody.length {
            let lineRange = nsBody.lineRange(for: NSRange(location: cursor, length: 0))
            let contentRange = lineContentRange(lineRange, in: nsBody)
            defer { cursor = max(NSMaxRange(lineRange), cursor + 1) }
            guard !intersectsExcluded(contentRange, excluded),
                  let match = definitionRegex.firstMatch(in: body, range: contentRange) else { continue }

            let identifier = nsBody.substring(with: match.range(at: 1))
            var definitionEnd = NSMaxRange(lineRange)
            var contentParts = [nsBody.substring(with: match.range(at: 2))]
            var next = definitionEnd
            while next < nsBody.length {
                let candidateLine = nsBody.lineRange(for: NSRange(location: next, length: 0))
                let candidateContent = lineContentRange(candidateLine, in: nsBody)
                let candidate = nsBody.substring(with: candidateContent)
                guard candidate.hasPrefix("  ") || candidate.hasPrefix("\t") || candidate.isEmpty else { break }
                contentParts.append(candidate.replacingOccurrences(
                    // Remove exactly one Scholium continuation indent. Any
                    // additional indentation is semantic Markdown belonging
                    // to a nested list, quote, or code block.
                    of: #"^(?: {2}|\t)"#,
                    with: "",
                    options: .regularExpression
                ))
                definitionEnd = NSMaxRange(candidateLine)
                next = definitionEnd
            }
            let wholeRange = NSRange(location: lineRange.location, length: definitionEnd - lineRange.location)
            definitionMarkerRanges.append(match.range)
            rawDefinitions.append(RawFootnoteDefinition(
                identifier: identifier,
                content: contentParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                relativeRange: wholeRange,
                isInline: false
            ))
        }

        var rawReferences: [RawFootnoteReference] = []
        for match in referenceRegex.matches(in: body, range: NSRange(location: 0, length: nsBody.length)) {
            guard !intersectsExcluded(match.range, excluded),
                  !definitionMarkerRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                  !isEscaped(at: match.range.location, in: nsBody) else { continue }
            rawReferences.append(RawFootnoteReference(
                identifier: nsBody.substring(with: match.range(at: 1)),
                relativeRange: match.range,
                isInline: false,
                inlineContent: nil
            ))
        }
        var inlineCounter = 0
        for match in inlineRegex.matches(in: body, range: NSRange(location: 0, length: nsBody.length)) {
            guard !intersectsExcluded(match.range, excluded), !isEscaped(at: match.range.location, in: nsBody) else { continue }
            inlineCounter += 1
            let identifier = "inline-\(inlineCounter)"
            let content = nsBody.substring(with: match.range(at: 1))
            rawReferences.append(RawFootnoteReference(
                identifier: identifier,
                relativeRange: match.range,
                isInline: true,
                inlineContent: content
            ))
            rawDefinitions.append(RawFootnoteDefinition(
                identifier: identifier,
                content: content,
                relativeRange: match.range,
                isInline: true
            ))
        }
        rawReferences.sort { $0.relativeRange.location < $1.relativeRange.location }

        var ordinalByIdentifier: [String: Int] = [:]
        var occurrenceByIdentifier: [String: Int] = [:]
        var references: [FootnoteReference] = []
        for raw in rawReferences {
            let ordinal = ordinalByIdentifier[raw.identifier] ?? (ordinalByIdentifier.count + 1)
            ordinalByIdentifier[raw.identifier] = ordinal
            let occurrence = (occurrenceByIdentifier[raw.identifier] ?? 0) + 1
            occurrenceByIdentifier[raw.identifier] = occurrence
            guard let span = sourceMapper.span(for: shifted(raw.relativeRange, by: bodyUTF16Offset)) else { continue }
            references.append(FootnoteReference(
                identifier: raw.identifier,
                ordinal: ordinal,
                occurrence: occurrence,
                isInline: raw.isInline,
                span: span
            ))
        }

        var firstDefinitionByIdentifier: [String: RawFootnoteDefinition] = [:]
        for raw in rawDefinitions {
            if firstDefinitionByIdentifier[raw.identifier] != nil {
                let span = sourceMapper.span(for: shifted(raw.relativeRange, by: bodyUTF16Offset))
                diagnostics.append(MarkdownDiagnostic(
                    code: .duplicateFootnote,
                    severity: .warning,
                    message: "Footnote '\(raw.identifier)' is defined more than once.",
                    span: span
                ))
            } else {
                firstDefinitionByIdentifier[raw.identifier] = raw
            }
        }

        for reference in references where firstDefinitionByIdentifier[reference.identifier] == nil {
            diagnostics.append(MarkdownDiagnostic(
                code: .undefinedFootnote,
                severity: .warning,
                message: "Footnote '\(reference.identifier)' has no definition.",
                span: reference.span
            ))
        }

        var definitions: [FootnoteDefinition] = []
        for raw in firstDefinitionByIdentifier.values {
            guard let span = sourceMapper.span(for: shifted(raw.relativeRange, by: bodyUTF16Offset)) else { continue }
            let ordinal = ordinalByIdentifier[raw.identifier]
            definitions.append(FootnoteDefinition(
                identifier: raw.identifier,
                content: raw.content,
                ordinal: ordinal,
                isInline: raw.isInline,
                span: span
            ))
            if ordinal == nil {
                diagnostics.append(MarkdownDiagnostic(
                    code: .unreferencedFootnote,
                    severity: .information,
                    message: "Footnote '\(raw.identifier)' is never referenced.",
                    span: span
                ))
            }
        }
        definitions.sort {
            let left = $0.ordinal ?? Int.max
            let right = $1.ordinal ?? Int.max
            return left == right ? $0.span.utf16LowerBound < $1.span.utf16LowerBound : left < right
        }

        return FootnoteParseResult(
            definitions: definitions,
            references: references,
            diagnostics: diagnostics
        )
    }

    private struct LinkParseResult {
        let links: [LinkOccurrence]
        let diagnostics: [MarkdownDiagnostic]
    }

    private struct MathParseResult {
        let expressions: [MathExpression]
        let diagnostics: [MarkdownDiagnostic]
    }

    /// Implements the published dollar-sequence model used by the mature
    /// micromark/remark math ecosystem: inline closing runs equal the opener,
    /// runs are greedy, escapes remain literal, and display fences are
    /// standalone runs of at least two dollars. This scanner produces only a
    /// source-located projection and never rewrites the document.
    private static func parseMath(
        body: String,
        bodyUTF16Offset: Int,
        sourceMapper: SemanticSourceMapper,
        excluded: [NSRange]
    ) -> MathParseResult {
        let source = body as NSString
        var expressions: [MathExpression] = []
        var diagnostics: [MarkdownDiagnostic] = []
        var displayRanges: [NSRange] = []
        var cursor = 0

        while cursor < source.length {
            let lineRange = source.lineRange(for: NSRange(location: cursor, length: 0))
            let contentRange = lineContentRange(lineRange, in: source)
            defer { cursor = max(NSMaxRange(lineRange), cursor + 1) }
            guard !intersectsExcluded(contentRange, excluded),
                  let opener = displayFence(in: contentRange, source: source) else { continue }

            var search = NSMaxRange(lineRange)
            var closingLineRange: NSRange?
            var closingFenceRange: NSRange?
            while search < source.length {
                let candidateLine = source.lineRange(for: NSRange(location: search, length: 0))
                let candidateContent = lineContentRange(candidateLine, in: source)
                if !intersectsExcluded(candidateContent, excluded),
                   let candidate = displayFence(in: candidateContent, source: source),
                   candidate.length >= opener.length {
                    closingLineRange = candidateLine
                    closingFenceRange = candidate
                    break
                }
                search = max(NSMaxRange(candidateLine), search + 1)
            }

            guard let closingLineRange, let closingFenceRange else {
                let span = sourceMapper.span(for: shifted(opener, by: bodyUTF16Offset))
                diagnostics.append(MarkdownDiagnostic(
                    code: .malformedMath,
                    severity: .warning,
                    message: "Display mathematics has no closing dollar fence.",
                    span: span
                ))
                continue
            }

            let wholeRange = NSRange(
                location: opener.location,
                length: NSMaxRange(closingFenceRange) - opener.location
            )
            let rawContentRange = NSRange(
                location: NSMaxRange(lineRange),
                length: closingLineRange.location - NSMaxRange(lineRange)
            )
            guard let span = sourceMapper.span(for: shifted(wholeRange, by: bodyUTF16Offset)),
                  let contentSpan = sourceMapper.span(for: shifted(rawContentRange, by: bodyUTF16Offset)) else {
                continue
            }
            displayRanges.append(wholeRange)
            expressions.append(MathExpression(
                kind: .display,
                content: source.substring(with: rawContentRange).trimmingCharacters(in: .newlines),
                delimiterLength: opener.length,
                span: span,
                contentSpan: contentSpan
            ))
            cursor = NSMaxRange(closingLineRange)
        }

        let inlineExcluded = excluded + displayRanges
        cursor = 0
        while cursor < source.length {
            guard source.character(at: cursor) == 0x24 else {
                cursor += 1
                continue
            }
            let openingStart = cursor
            while cursor < source.length, source.character(at: cursor) == 0x24 { cursor += 1 }
            let delimiterLength = cursor - openingStart
            let openingRange = NSRange(location: openingStart, length: delimiterLength)
            guard !isEscaped(at: openingStart, in: source),
                  !intersectsExcluded(openingRange, inlineExcluded),
                  (openingStart == 0 || source.character(at: openingStart - 1) != 0x24),
                  (cursor == source.length || source.character(at: cursor) != 0x24) else { continue }

            var search = cursor
            var closingStart: Int?
            while search < source.length {
                guard source.character(at: search) == 0x24 else {
                    search += 1
                    continue
                }
                let runStart = search
                while search < source.length, source.character(at: search) == 0x24 { search += 1 }
                guard search - runStart == delimiterLength,
                      !isEscaped(at: runStart, in: source),
                      (runStart == 0 || source.character(at: runStart - 1) != 0x24),
                      (search == source.length || source.character(at: search) != 0x24) else { continue }
                closingStart = runStart
                break
            }
            guard let closingStart, closingStart > cursor else { continue }

            let wholeRange = NSRange(
                location: openingStart,
                length: closingStart + delimiterLength - openingStart
            )
            let contentRange = NSRange(location: cursor, length: closingStart - cursor)
            guard !intersectsExcluded(wholeRange, inlineExcluded),
                  let span = sourceMapper.span(for: shifted(wholeRange, by: bodyUTF16Offset)),
                  let contentSpan = sourceMapper.span(for: shifted(contentRange, by: bodyUTF16Offset)) else {
                continue
            }
            let rawContent = source.substring(with: contentRange)
            let content = normalizedInlineMathContent(rawContent)
            expressions.append(MathExpression(
                kind: .inline,
                content: content,
                delimiterLength: delimiterLength,
                span: span,
                contentSpan: contentSpan
            ))
            cursor = NSMaxRange(wholeRange)
        }

        return MathParseResult(
            expressions: expressions.sorted { $0.span.utf16LowerBound < $1.span.utf16LowerBound },
            diagnostics: diagnostics
        )
    }

    private static func displayFence(in line: NSRange, source: NSString) -> NSRange? {
        var position = line.location
        var indentation = 0
        while position < NSMaxRange(line), source.character(at: position) == 0x20, indentation < 4 {
            position += 1
            indentation += 1
        }
        guard indentation <= 3, position < NSMaxRange(line), source.character(at: position) == 0x24,
              !isEscaped(at: position, in: source) else { return nil }
        let start = position
        while position < NSMaxRange(line), source.character(at: position) == 0x24 { position += 1 }
        let delimiterEnd = position
        guard delimiterEnd - start >= 2 else { return nil }
        while position < NSMaxRange(line),
              source.character(at: position) == 0x20 || source.character(at: position) == 0x09 {
            position += 1
        }
        guard position == NSMaxRange(line) else { return nil }
        return NSRange(location: start, length: delimiterEnd - start)
    }

    private static func normalizedInlineMathContent(_ raw: String) -> String {
        guard raw.count > 2,
              raw.first?.isWhitespace == true,
              raw.last?.isWhitespace == true,
              raw.contains(where: { !$0.isWhitespace }) else { return raw }
        return String(raw.dropFirst().dropLast())
    }

    private static func parseLinks(
        body: String,
        bodyUTF16Offset: Int,
        sourceMapper: SemanticSourceMapper,
        excluded: [NSRange]
    ) -> LinkParseResult {
        let nsBody = body as NSString
        let fullRange = NSRange(location: 0, length: nsBody.length)
        let wikiRegex = try? NSRegularExpression(pattern: #"\[\[([^\]\r\n]+)\]\]"#)
        let markdownRegex = try? NSRegularExpression(pattern: #"(!)?\[([^\]\r\n]*)\]\(([^)\r\n]+)\)"#)
        var links: [LinkOccurrence] = []
        var diagnostics: [MarkdownDiagnostic] = []

        if let wikiRegex {
            for match in wikiRegex.matches(in: body, range: fullRange) {
                guard !intersectsExcluded(match.range, excluded), !isEscaped(at: match.range.location, in: nsBody) else { continue }
                let prefixLocation = match.range.location - 1
                let prefix = prefixLocation >= 0
                    ? nsBody.substring(with: NSRange(location: prefixLocation, length: 1))
                    : nil
                let isEmbed = prefix == "!" && !isEscaped(at: prefixLocation, in: nsBody)
                let linkRange = isEmbed
                    ? NSRange(location: prefixLocation, length: match.range.length + 1)
                    : match.range
                guard !intersectsExcluded(linkRange, excluded),
                      !isEscaped(at: linkRange.location, in: nsBody) else { continue }
                let inner = nsBody.substring(with: match.range(at: 1))
                let parsed = parseWikilinkInner(inner)
                guard let linkSpan = sourceMapper.span(for: shifted(linkRange, by: bodyUTF16Offset)) else { continue }
                var occurrenceRange = linkRange
                var annotation: LinkAnnotation?
                if !isEmbed {
                    switch parseLinkAnnotation(after: linkRange, in: body, sourceMapper: sourceMapper, bodyUTF16Offset: bodyUTF16Offset) {
                    case .absent:
                        break
                    case .valid(let value, let range):
                        annotation = value
                        occurrenceRange = NSUnionRange(linkRange, range)
                    case .malformed(let range, let message):
                        diagnostics.append(MarkdownDiagnostic(
                            code: .malformedLinkAnnotation,
                            severity: .warning,
                            message: message,
                            span: sourceMapper.span(for: shifted(range, by: bodyUTF16Offset))
                        ))
                    }
                }
                guard let span = sourceMapper.span(for: shifted(occurrenceRange, by: bodyUTF16Offset)) else { continue }
                links.append(LinkOccurrence(
                    syntax: isEmbed ? .embed : .wikilink,
                    target: parsed.target,
                    alias: parsed.alias,
                    fragment: parsed.fragment,
                    annotation: annotation,
                    localContext: localContext(in: nsBody, containing: occurrenceRange),
                    isExternal: false,
                    span: span,
                    linkSpan: linkSpan
                ))
            }
        }

        if let markdownRegex {
            for match in markdownRegex.matches(in: body, range: fullRange) {
                guard !intersectsExcluded(match.range, excluded), !isEscaped(at: match.range.location, in: nsBody) else { continue }
                let isEmbed = match.range(at: 1).location != NSNotFound
                let alias = optionalTrimmed(nsBody.substring(with: match.range(at: 2)))
                let rawDestination = nsBody.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
                let destination = splitTargetAndFragment(rawDestination)
                guard let span = sourceMapper.span(for: shifted(match.range, by: bodyUTF16Offset)) else { continue }
                links.append(LinkOccurrence(
                    syntax: isEmbed ? .embed : .markdown,
                    target: destination.target.removingPercentEncoding ?? destination.target,
                    alias: alias,
                    fragment: destination.fragment,
                    localContext: localContext(in: nsBody, containing: match.range),
                    isExternal: isExternalDestination(rawDestination),
                    span: span
                ))
            }
        }

        return LinkParseResult(
            links: links.sorted { $0.span.utf16LowerBound < $1.span.utf16LowerBound },
            diagnostics: diagnostics
        )
    }

    private enum LinkAnnotationParseResult {
        case absent
        case valid(LinkAnnotation, NSRange)
        case malformed(NSRange, String)
    }

    private static func parseLinkAnnotation(
        after linkRange: NSRange,
        in source: String,
        sourceMapper: SemanticSourceMapper,
        bodyUTF16Offset: Int
    ) -> LinkAnnotationParseResult {
        let nsSource = source as NSString
        let opening = NSMaxRange(linkRange)
        guard opening + 1 < nsSource.length,
              nsSource.character(at: opening) == 0x7B,
              nsSource.character(at: opening + 1) == 0x7B else { return .absent }

        var cursor = opening + 2
        while cursor + 1 < nsSource.length {
            let isDelimiter = nsSource.character(at: cursor) == 0x7B
                && nsSource.character(at: cursor + 1) == 0x7B
            if isDelimiter, !isEscaped(at: cursor, in: nsSource) {
                return .malformed(
                    NSRange(location: opening, length: cursor + 2 - opening),
                    "Link annotations cannot nest; escape literal '{{' as '\\{{'."
                )
            }

            let isClosing = nsSource.character(at: cursor) == 0x7D
                && nsSource.character(at: cursor + 1) == 0x7D
            if isClosing, !isEscaped(at: cursor, in: nsSource) {
                let annotationRange = NSRange(location: opening, length: cursor + 2 - opening)
                let contentRange = NSRange(location: opening + 2, length: cursor - opening - 2)
                let markdown = nsSource.substring(with: contentRange)
                let text = visibleLinkAnnotationText(markdown)
                guard !text.isEmpty else {
                    return .malformed(annotationRange, "Link annotations must contain visible text.")
                }
                guard let span = sourceMapper.span(for: shifted(annotationRange, by: bodyUTF16Offset)),
                      let contentSpan = sourceMapper.span(for: shifted(contentRange, by: bodyUTF16Offset)) else {
                    return .malformed(annotationRange, "The link annotation source range is invalid.")
                }
                return .valid(
                    LinkAnnotation(markdown: markdown, text: text, span: span, contentSpan: contentSpan),
                    annotationRange
                )
            }
            cursor += 1
        }

        return .malformed(
            NSRange(location: opening, length: nsSource.length - opening),
            "Link annotation is missing its closing '}}' delimiter."
        )
    }

    /// Link annotations are Markdown, but ordinary Wikilinks inside that
    /// Markdown are Scholium syntax rather than CommonMark. Project their
    /// reader-visible label before asking the shared Markdown renderer for
    /// plain text so Search and MCP never expose raw link delimiters or a
    /// hidden destination as annotation prose.
    private static func visibleLinkAnnotationText(_ markdown: String) -> String {
        let fragment = NoteDocument(relativePath: "Link Annotation.md", rawContent: markdown)
        let semantic = MarkdownSemanticDocument(parsing: fragment)
        let nsMarkdown = markdown as NSString
        var projected = markdown
        for link in semantic.links.reversed()
            where link.syntax == .wikilink || link.syntax == .embed {
            let range = link.linkSpan.nsRange
            guard NSMaxRange(range) <= nsMarkdown.length else { continue }
            let visible = markdownEscapedText(link.alias ?? link.target)
            guard let swiftRange = Range(range, in: projected) else { continue }
            projected.replaceSubrange(swiftRange, with: visible)
        }
        return MarkdownVisibleText.render(projected)
    }

    private static func markdownEscapedText(_ text: String) -> String {
        let special = CharacterSet(charactersIn: #"\`*_{}[]<>()#+-.!|"#)
        return text.unicodeScalars.reduce(into: "") { result, scalar in
            if special.contains(scalar) { result.append("\\") }
            result.unicodeScalars.append(scalar)
        }
    }

    private static func parseWikilinkInner(
        _ inner: String
    ) -> (target: String, alias: String?, fragment: String?) {
        let pipe = inner.firstIndex(of: "|")
        let targetPart = pipe.map { String(inner[..<$0]) } ?? inner
        let alias = pipe.map { optionalTrimmed(String(inner[inner.index(after: $0)...])) } ?? nil
        let destination = splitTargetAndFragment(targetPart.trimmingCharacters(in: .whitespaces))
        return (target: destination.target, alias: alias, fragment: destination.fragment)
    }

    private static func splitTargetAndFragment(_ raw: String) -> (target: String, fragment: String?) {
        guard let hash = raw.firstIndex(of: "#") else { return (raw, nil) }
        return (
            String(raw[..<hash]),
            optionalTrimmed(String(raw[raw.index(after: hash)...]))
        )
    }

    private static func localContext(in source: NSString, containing range: NSRange) -> String {
        let start = min(max(0, range.location), source.length)
        let upper = min(max(start, NSMaxRange(range)), source.length)
        let firstLine = source.lineRange(for: NSRange(location: start, length: 0))
        let lastLocation = upper > start ? upper - 1 : upper
        let lastLine = source.lineRange(for: NSRange(location: lastLocation, length: 0))
        return source.substring(with: NSRange(
            location: firstLine.location,
            length: NSMaxRange(lastLine) - firstLine.location
        )).trimmingCharacters(in: .newlines)
    }

    private static func isExternalDestination(_ raw: String) -> Bool {
        guard let schemeRange = raw.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) else {
            return false
        }
        let scheme = raw[schemeRange].dropLast().lowercased()
        return scheme != "scholium-note"
    }

    private static func dequotedCalloutBody(
        nsBody: NSString,
        blockRange: NSRange,
        headerLineRange: NSRange,
        depth: Int
    ) -> String {
        var lines: [String] = []
        var cursor = NSMaxRange(headerLineRange)
        while cursor < NSMaxRange(blockRange) {
            let lineRange = nsBody.lineRange(for: NSRange(location: cursor, length: 0))
            let contentRange = lineContentRange(lineRange, in: nsBody)
            var line = nsBody.substring(with: contentRange)
            var remainingDepth = depth
            while remainingDepth > 0 {
                line = line.replacingOccurrences(
                    of: #"^\s*>\s?"#,
                    with: "",
                    options: .regularExpression
                )
                remainingDepth -= 1
            }
            lines.append(line)
            cursor = max(NSMaxRange(lineRange), cursor + 1)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    private static func quoteDepth(of line: String) -> Int {
        guard let expression = try? NSRegularExpression(pattern: #"^\s*((?:>\s*)+)"#),
              let match = expression.firstMatch(
                in: line,
                range: NSRange(location: 0, length: (line as NSString).length)
              ) else { return 0 }
        return (line as NSString).substring(with: match.range(at: 1)).reduce(into: 0) {
            if $1 == ">" { $0 += 1 }
        }
    }

    private struct CommentParseResult {
        let ranges: [NSRange]
        let diagnostics: [MarkdownDiagnostic]
    }

    private static func parseComments(
        body: String,
        bodyUTF16Offset: Int,
        sourceMapper: SemanticSourceMapper
    ) -> CommentParseResult {
        let source = body as NSString
        var ranges: [NSRange] = []
        var diagnostics: [MarkdownDiagnostic] = []
        let delimiters = [
            (opening: "%%", closing: "%%", name: "Obsidian comment"),
            (opening: "<!--", closing: "-->", name: "HTML comment"),
        ]

        for delimiter in delimiters {
            var cursor = 0
            while cursor < source.length {
                let searchRange = NSRange(location: cursor, length: source.length - cursor)
                let opening = source.range(of: delimiter.opening, options: [], range: searchRange)
                guard opening.location != NSNotFound else { break }

                let closingSearchStart = NSMaxRange(opening)
                let closingSearchRange = NSRange(
                    location: closingSearchStart,
                    length: source.length - closingSearchStart
                )
                let closing = source.range(
                    of: delimiter.closing,
                    options: [],
                    range: closingSearchRange
                )
                guard closing.location != NSNotFound else {
                    ranges.append(NSRange(
                        location: opening.location,
                        length: source.length - opening.location
                    ))
                    diagnostics.append(MarkdownDiagnostic(
                        code: .malformedComment,
                        severity: .warning,
                        message: "\(delimiter.name) has no closing \(delimiter.closing) delimiter.",
                        span: sourceMapper.span(for: shifted(opening, by: bodyUTF16Offset))
                    ))
                    break
                }

                ranges.append(NSRange(
                    location: opening.location,
                    length: NSMaxRange(closing) - opening.location
                ))
                cursor = NSMaxRange(closing)
            }
        }

        return CommentParseResult(
            ranges: ranges.sorted { $0.location < $1.location },
            diagnostics: diagnostics
        )
    }

    private static func inlineCodeRanges(in body: String) -> [NSRange] {
        let source = body as NSString
        var ranges: [NSRange] = []
        var cursor = 0

        while cursor < source.length {
            guard source.character(at: cursor) == 0x60 else {
                cursor += 1
                continue
            }
            let openingStart = cursor
            while cursor < source.length, source.character(at: cursor) == 0x60 { cursor += 1 }
            let delimiterLength = cursor - openingStart
            guard !isEscaped(at: openingStart, in: source) else { continue }

            var search = cursor
            var closingEnd: Int?
            while search < source.length {
                guard source.character(at: search) == 0x60 else {
                    search += 1
                    continue
                }
                let runStart = search
                while search < source.length, source.character(at: search) == 0x60 { search += 1 }
                if search - runStart == delimiterLength {
                    closingEnd = search
                    break
                }
            }
            if let closingEnd {
                ranges.append(NSRange(location: openingStart, length: closingEnd - openingStart))
                cursor = closingEnd
            }
        }
        return ranges
    }

    private static func lineContentRange(_ lineRange: NSRange, in source: NSString) -> NSRange {
        var length = lineRange.length
        while length > 0 {
            let value = source.character(at: lineRange.location + length - 1)
            guard value == 10 || value == 13 else { break }
            length -= 1
        }
        return NSRange(location: lineRange.location, length: length)
    }

    private static func intersectsExcluded(_ range: NSRange, _ excluded: [NSRange]) -> Bool {
        excluded.contains { NSIntersectionRange($0, range).length > 0 }
    }

    private static func shifted(_ range: NSRange, by offset: Int) -> NSRange {
        NSRange(location: range.location + offset, length: range.length)
    }

    private static func optionalTrimmed(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isEscaped(at location: Int, in source: NSString) -> Bool {
        guard location > 0 else { return false }
        var cursor = location - 1
        var count = 0
        while cursor >= 0, source.character(at: cursor) == 92 {
            count += 1
            if cursor == 0 { break }
            cursor -= 1
        }
        return count % 2 == 1
    }
}

private struct SemanticSourceMapper {
    let source: String
    let nsSource: NSString
    let lineStartsUTF16: [Int]

    init(_ source: String) {
        self.source = source
        self.nsSource = source as NSString
        var starts = [0]
        var index = 0
        while index < nsSource.length {
            let value = nsSource.character(at: index)
            if value == 13 {
                if index + 1 < nsSource.length, nsSource.character(at: index + 1) == 10 {
                    index += 1
                }
                starts.append(index + 1)
            } else if value == 10 {
                starts.append(index + 1)
            }
            index += 1
        }
        self.lineStartsUTF16 = starts
    }

    func span(for range: NSRange) -> SourceSpan? {
        guard range.location != NSNotFound,
              range.location >= 0,
              range.length >= 0,
              NSMaxRange(range) <= nsSource.length,
              let lowerByte = utf8Offset(forUTF16Offset: range.location),
              let upperByte = utf8Offset(forUTF16Offset: NSMaxRange(range)) else { return nil }
        return SourceSpan(
            utf8LowerBound: lowerByte,
            utf8UpperBound: upperByte,
            utf16LowerBound: range.location,
            utf16UpperBound: NSMaxRange(range),
            start: position(atUTF16Offset: range.location),
            end: position(atUTF16Offset: NSMaxRange(range))
        )
    }

    func nsRange(for sourceRange: Markdown.SourceRange) -> NSRange? {
        guard let lower = utf16Offset(line: sourceRange.lowerBound.line, utf8Column: sourceRange.lowerBound.column),
              let upper = utf16Offset(line: sourceRange.upperBound.line, utf8Column: sourceRange.upperBound.column),
              upper >= lower else { return nil }
        return NSRange(location: lower, length: upper - lower)
    }

    func utf16Offset(forUTF8Offset offset: Int) -> Int? {
        guard offset >= 0, offset <= source.utf8.count else { return nil }
        let utf8Index = source.utf8.index(source.utf8.startIndex, offsetBy: offset)
        guard let index = String.Index(utf8Index, within: source) else { return nil }
        return index.utf16Offset(in: source)
    }

    private func utf8Offset(forUTF16Offset offset: Int) -> Int? {
        guard offset >= 0, offset <= nsSource.length else { return nil }
        let index = String.Index(utf16Offset: offset, in: source)
        return source.utf8.distance(from: source.utf8.startIndex, to: index)
    }

    private func utf16Offset(line: Int, utf8Column: Int) -> Int? {
        guard line > 0, line <= lineStartsUTF16.count, utf8Column > 0 else { return nil }
        let lineStart = lineStartsUTF16[line - 1]
        let lineEnd = line < lineStartsUTF16.count ? lineStartsUTF16[line] : nsSource.length
        let startIndex = String.Index(utf16Offset: lineStart, in: source)
        let endIndex = String.Index(utf16Offset: lineEnd, in: source)
        let lineSlice = source[startIndex..<endIndex]
        let byteOffset = utf8Column - 1
        guard byteOffset <= lineSlice.utf8.count else { return nil }
        let utf8Index = lineSlice.utf8.index(lineSlice.utf8.startIndex, offsetBy: byteOffset)
        guard let target = String.Index(utf8Index, within: source) else { return nil }
        return target.utf16Offset(in: source)
    }

    private func position(atUTF16Offset offset: Int) -> SourcePosition {
        var low = 0
        var high = lineStartsUTF16.count
        while low + 1 < high {
            let middle = (low + high) / 2
            if lineStartsUTF16[middle] <= offset {
                low = middle
            } else {
                high = middle
            }
        }
        let lineStart = lineStartsUTF16[low]
        let safeOffset = min(max(offset, lineStart), nsSource.length)
        let startIndex = String.Index(utf16Offset: lineStart, in: source)
        let targetIndex = String.Index(utf16Offset: safeOffset, in: source)
        let utf8Column = source.utf8.distance(from: startIndex, to: targetIndex) + 1
        return SourcePosition(
            line: low + 1,
            utf8Column: utf8Column,
            utf16Column: safeOffset - lineStart + 1
        )
    }
}
