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

    public static func canonicalIdentifier(for raw: String) -> String {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":")))
            .lowercased()
        return switch normalized {
        case "mini": "orient"
        case "bibli", "bibliography", "cited": "cite"
        case "project": "connect"
        case "definition", "principle", "theorem", "argument", "objection", "reply": "state"
        case "example", "case", "dialogue": "illustrate"
        case "quotation", "author", "long-quote": "quote"
        case "warning", "caution", "source-warning", "torn", "question": "flag"
        default: normalized
        }
    }

    public static func role(for raw: String) -> CalloutSemanticRole {
        CalloutSemanticRole(rawValue: canonicalIdentifier(for: raw)) ?? .neutral
    }
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

public enum LinkSyntax: String, Codable, Hashable, Sendable {
    case wikilink
    case vectorWikilink
    case markdown
    case embed
    /// Retired typed-arrow syntax retained only for source-preserving diagnostics
    /// and compatibility with previously decoded semantic data.
    case relationArrow
}

/// Scholium's compact, workspace-wide relation language. The marker describes
/// the relationship relative to the note containing the wikilink.
public enum VectorLinkKind: String, Codable, Hashable, CaseIterable, Sendable {
    case neutral
    /// Plus-prefixed B in A means A supports B.
    case supportsTarget = "supports_target"
    /// Minus-prefixed B in A means B supports A.
    case supportedByTarget = "supported_by_target"
    /// Question-prefixed B means A and B cannot both be true.
    case incompatible
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
    public let relationship: RelationshipPredicate?
    public let vectorKind: VectorLinkKind?
    public let isExternal: Bool
    public let span: SourceSpan
    public var resolution: LinkOccurrenceResolution

    public init(
        syntax: LinkSyntax,
        target: String,
        alias: String?,
        fragment: String?,
        relationship: RelationshipPredicate?,
        vectorKind: VectorLinkKind? = nil,
        isExternal: Bool,
        span: SourceSpan,
        resolution: LinkOccurrenceResolution = .unresolved
    ) {
        self.syntax = syntax
        self.target = target
        self.alias = alias
        self.fragment = fragment
        self.relationship = relationship
        self.vectorKind = vectorKind
        self.isExternal = isExternal
        self.span = span
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
    case malformedFootnote
    case unknownRelationshipPredicate
    case noncanonicalRelationshipSyntax
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
    public let headings: [HeadingNode]
    public let callouts: [CalloutBlock]
    public let footnoteDefinitions: [FootnoteDefinition]
    public let footnoteReferences: [FootnoteReference]
    public let links: [LinkOccurrence]
    public let diagnostics: [MarkdownDiagnostic]

    public init(parsing document: NoteDocument) {
        self = MarkdownSemanticParser.parse(document)
    }

    public init(
        fingerprint: DocumentFingerprint,
        blocks: [MarkdownBlock],
        headings: [HeadingNode],
        callouts: [CalloutBlock],
        footnoteDefinitions: [FootnoteDefinition],
        footnoteReferences: [FootnoteReference],
        links: [LinkOccurrence],
        diagnostics: [MarkdownDiagnostic]
    ) {
        self.fingerprint = fingerprint
        self.blocks = blocks
        self.headings = headings
        self.callouts = callouts
        self.footnoteDefinitions = footnoteDefinitions
        self.footnoteReferences = footnoteReferences
        self.links = links
        self.diagnostics = diagnostics
    }
}

public enum MarkdownSemanticParser {
    public static func parse(_ document: NoteDocument) -> MarkdownSemanticDocument {
        let diagnosesLegacyRelationArrows = document.parsedFrontmatter["project_role"]?.displayScalar != "template"
        let sourceMapper = SemanticSourceMapper(document.rawContent)
        let bodyOffset = sourceMapper.utf16Offset(forUTF8Offset: document.bodyByteRange.lowerBound) ?? 0
        let bodyMapper = SemanticSourceMapper(document.body)
        let parsed = Document(parsing: document.body, options: [.parseBlockDirectives])

        var blocks: [MarkdownBlock] = []
        var headings: [HeadingNode] = []
        var literalRanges: [NSRange] = []
        collectMarkup(
            parsed,
            bodyMapper: bodyMapper,
            sourceMapper: sourceMapper,
            bodyUTF16Offset: bodyOffset,
            blocks: &blocks,
            headings: &headings,
            literalRanges: &literalRanges
        )

        literalRanges.append(contentsOf: commentRanges(in: document.body))
        literalRanges.append(contentsOf: inlineCodeRanges(in: document.body))

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
        let linkResult = parseLinks(
            body: document.body,
            bodyUTF16Offset: bodyOffset,
            sourceMapper: sourceMapper,
            excluded: literalRanges,
            diagnosesLegacyRelationArrows: diagnosesLegacyRelationArrows
        )
        return MarkdownSemanticDocument(
            fingerprint: document.fingerprint,
            blocks: blocks.sorted { $0.span.utf16LowerBound < $1.span.utf16LowerBound },
            headings: headings.sorted { $0.span.utf16LowerBound < $1.span.utf16LowerBound },
            callouts: calloutResult.callouts,
            footnoteDefinitions: footnoteResult.definitions,
            footnoteReferences: footnoteResult.references,
            links: linkResult.links,
            diagnostics: (calloutResult.diagnostics + footnoteResult.diagnostics + linkResult.diagnostics).sorted {
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
        headings: inout [HeadingNode],
        literalRanges: inout [NSRange]
    ) {
        if let range = markup.range,
           let relativeRange = bodyMapper.nsRange(for: range),
           let span = sourceMapper.span(for: NSRange(
               location: bodyUTF16Offset + relativeRange.location,
               length: relativeRange.length
           )) {
            if let heading = markup as? Heading {
                headings.append(HeadingNode(level: heading.level, text: heading.plainText, span: span))
            }
            if let kind = blockKind(for: markup) {
                blocks.append(MarkdownBlock(kind: kind, span: span))
            }
            if markup is CodeBlock || markup is InlineCode || markup is HTMLBlock || markup is InlineHTML {
                literalRanges.append(relativeRange)
            }
        }

        for child in markup.children {
            collectMarkup(
                child,
                bodyMapper: bodyMapper,
                sourceMapper: sourceMapper,
                bodyUTF16Offset: bodyUTF16Offset,
                blocks: &blocks,
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
                    of: #"^(?: {2,}|\t)"#,
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

    private static func parseLinks(
        body: String,
        bodyUTF16Offset: Int,
        sourceMapper: SemanticSourceMapper,
        excluded: [NSRange],
        diagnosesLegacyRelationArrows: Bool
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
                let vectorKind = vectorKind(
                    for: prefix,
                    at: prefixLocation,
                    in: body,
                    nsBody: nsBody
                )
                let sourceRange = (isEmbed || vectorKind != nil)
                    ? NSRange(location: prefixLocation, length: match.range.length + 1)
                    : match.range
                guard !intersectsExcluded(sourceRange, excluded),
                      !isEscaped(at: sourceRange.location, in: nsBody) else { continue }
                let inner = nsBody.substring(with: match.range(at: 1))
                let parsed = parseWikilinkInner(inner)
                guard let span = sourceMapper.span(for: shifted(sourceRange, by: bodyUTF16Offset)) else { continue }
                if parsed.relationship != nil {
                    diagnostics.append(MarkdownDiagnostic(
                        code: .noncanonicalRelationshipSyntax,
                        severity: .information,
                        message: "The legacy typed annotation is ignored. Use +[[Target]], -[[Target]], or ?[[Target]] for an explicit relation.",
                        span: span
                    ))
                }
                links.append(LinkOccurrence(
                    syntax: isEmbed ? .embed : (vectorKind == nil ? .wikilink : .vectorWikilink),
                    target: parsed.target,
                    alias: parsed.alias,
                    fragment: parsed.fragment,
                    relationship: nil,
                    vectorKind: isEmbed ? nil : (vectorKind ?? .neutral),
                    isExternal: false,
                    span: span
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
                    relationship: nil,
                    isExternal: isExternalDestination(rawDestination),
                    span: span
                ))
            }
        }

        // Retired relation arrows remain source-located neutral links. Keeping
        // the syntax classification lets diagnostics and rename rewriting point
        // to the original bytes without allowing the predicate into the graph.
        if diagnosesLegacyRelationArrows, let relationRegex = try? NSRegularExpression(
            pattern: #"(?m)^\s*-\s*`([a-z][a-z0-9_]*)`\s*->\s*\[\[([^\]\r\n]+)\]\]\s*$"#
        ) {
            for match in relationRegex.matches(in: body, range: fullRange) {
                guard !intersectsExcludedExceptInlinePredicate(match.range, predicate: match.range(at: 1), excluded: excluded),
                      !isEscaped(at: match.range.location, in: nsBody),
                      isInsideLevelTwoSection(named: "Relations", at: match.range.location, in: body) else { continue }
                let rawPredicate = nsBody.substring(with: match.range(at: 1))
                guard let span = sourceMapper.span(for: shifted(match.range, by: bodyUTF16Offset)) else { continue }
                guard relationshipPredicate(rawPredicate) != nil else {
                    diagnostics.append(MarkdownDiagnostic(
                        code: .unknownRelationshipPredicate,
                        severity: .warning,
                        message: "Unknown relationship predicate '\(rawPredicate)'.",
                        span: span
                    ))
                    continue
                }
                let parsed = parseWikilinkInner(nsBody.substring(with: match.range(at: 2)))
                links.removeAll { existing in
                    existing.syntax == .wikilink && NSIntersectionRange(existing.span.nsRange, span.nsRange).length > 0
                }
                diagnostics.append(MarkdownDiagnostic(
                    code: .noncanonicalRelationshipSyntax,
                    severity: .information,
                    message: "Legacy relation arrows are neutral connections. Use +[[Target]], -[[Target]], or ?[[Target]] for an explicit relation.",
                    span: span
                ))
                links.append(LinkOccurrence(
                    syntax: .relationArrow,
                    target: parsed.target,
                    alias: parsed.alias,
                    fragment: parsed.fragment,
                    relationship: nil,
                    vectorKind: .neutral,
                    isExternal: false,
                    span: span
                ))
            }
        }

        return LinkParseResult(
            links: links.sorted { $0.span.utf16LowerBound < $1.span.utf16LowerBound },
            diagnostics: diagnostics
        )
    }

    private static func vectorKind(
        for prefix: String?,
        at location: Int,
        in body: String,
        nsBody: NSString
    ) -> VectorLinkKind? {
        guard location >= 0, let prefix else { return nil }
        let kind: VectorLinkKind
        switch prefix {
        case "+": kind = .supportsTarget
        case "-": kind = .supportedByTarget
        case "?": kind = .incompatible
        default: return nil
        }
        guard !isEscaped(at: location, in: nsBody), isVectorTokenBoundary(before: location, in: body) else {
            return nil
        }
        return kind
    }

    private static func isVectorTokenBoundary(before markerUTF16Offset: Int, in source: String) -> Bool {
        guard markerUTF16Offset > 0 else { return true }
        let utf16 = source.utf16
        guard let markerIndex = utf16.index(utf16.startIndex, offsetBy: markerUTF16Offset, limitedBy: utf16.endIndex),
              let stringIndex = String.Index(markerIndex, within: source),
              let previous = source[..<stringIndex].last else { return true }
        if previous.isLetter || previous.isNumber || previous.isWhitespace == false
            && ["_", "\\", "!", "+", "-", "?"].contains(String(previous)) {
            return false
        }
        return true
    }

    private static func parseWikilinkInner(
        _ inner: String
    ) -> (target: String, alias: String?, fragment: String?, relationship: RelationshipPredicate?) {
        let pipe = inner.firstIndex(of: "|")
        let targetPart = pipe.map { String(inner[..<$0]) } ?? inner
        let annotation = pipe.map { String(inner[inner.index(after: $0)...]) }
        let destination = splitTargetAndFragment(targetPart.trimmingCharacters(in: .whitespaces))
        let relationAndAlias = parseRelationshipAnnotation(annotation)
        return (
            target: destination.target,
            alias: relationAndAlias.alias,
            fragment: destination.fragment,
            relationship: relationAndAlias.relationship
        )
    }

    private static func isInsideLevelTwoSection(named name: String, at offset: Int, in source: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"(?m)^(#{1,2})\s+([^\r\n#]+?)\s*#*\s*$"#) else { return false }
        let nsSource = source as NSString
        var activeSection: String?
        for match in regex.matches(in: source, range: NSRange(location: 0, length: nsSource.length)) {
            if match.range.location >= offset { break }
            let level = match.range(at: 1).length
            if level == 1 { activeSection = nil }
            if level == 2 {
                activeSection = nsSource.substring(with: match.range(at: 2))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return activeSection?.caseInsensitiveCompare(name) == .orderedSame
    }

    private static func intersectsExcludedExceptInlinePredicate(
        _ range: NSRange, predicate: NSRange, excluded: [NSRange]
    ) -> Bool {
        let allowed = NSRange(location: max(0, predicate.location - 1), length: predicate.length + 2)
        return excluded.contains { candidate in
            NSIntersectionRange(candidate, range).length > 0
                && !(candidate.location >= allowed.location && NSMaxRange(candidate) <= NSMaxRange(allowed))
        }
    }

    private static func parseRelationshipAnnotation(
        _ annotation: String?
    ) -> (alias: String?, relationship: RelationshipPredicate?) {
        guard let annotation = optionalTrimmed(annotation ?? "") else { return (nil, nil) }
        if annotation.hasPrefix(":"), let predicate = relationshipPredicate(String(annotation.dropFirst())) {
            return (nil, predicate)
        }
        guard let colon = annotation.lastIndex(of: ":") else { return (annotation, nil) }
        let suffix = String(annotation[annotation.index(after: colon)...])
        guard let predicate = relationshipPredicate(suffix) else { return (annotation, nil) }
        return (optionalTrimmed(String(annotation[..<colon])), predicate)
    }

    private static func relationshipPredicate(_ raw: String) -> RelationshipPredicate? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        if let exact = RelationshipPredicate.allCases.first(where: {
            $0.rawValue.lowercased().replacingOccurrences(of: "-", with: "_") == normalized
        }) {
            return exact
        }
        return switch normalized {
        case "see_also", "seealso": .seeAlso
        case "objectsto": .objectsTo
        case "repliesto": .repliesTo
        case "dependson": .dependsOn
        case "iscasefor": .isCaseFor
        case "issourcefor": .isSourceFor
        case "isbackgroundfor": .isBackgroundFor
        case "isnotevidencefor": .isNotEvidenceFor
        default: nil
        }
    }

    private static func splitTargetAndFragment(_ raw: String) -> (target: String, fragment: String?) {
        guard let hash = raw.firstIndex(of: "#") else { return (raw, nil) }
        return (
            String(raw[..<hash]),
            optionalTrimmed(String(raw[raw.index(after: hash)...]))
        )
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

    private static func commentRanges(in body: String) -> [NSRange] {
        let patterns = [#"%%[\s\S]*?%%"#, #"<!--[\s\S]*?-->"#]
        let fullRange = NSRange(location: 0, length: (body as NSString).length)
        return patterns.reduce(into: [NSRange]()) { ranges, pattern in
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
            ranges.append(contentsOf: expression.matches(in: body, range: fullRange).map(\.range))
        }
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
