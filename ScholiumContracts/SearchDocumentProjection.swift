import CryptoKit
import Foundation
import Markdown

public struct SearchSegmentOffset: Codable, Hashable, Sendable {
    public enum MappingKind: UInt8, Codable, Hashable, Sendable {
        /// Each normalized UTF-16 unit maps to the corresponding source unit.
        /// Runs are coalesced only across single-unit graphemes.
        case linear = 0
        /// Every overlapping normalized unit maps to the complete source span.
        /// This preserves grapheme, fold-expansion, collapsed-whitespace, and
        /// non-exact projection behavior.
        case sourceSpan = 1
    }

    public let normalizedUTF16LowerBound: Int
    public let normalizedUTF16UpperBound: Int
    public let sourceUTF16LowerBound: Int
    public let sourceUTF16UpperBound: Int
    public let mappingKind: MappingKind

    public init(
        normalizedUTF16LowerBound: Int,
        normalizedUTF16UpperBound: Int,
        sourceUTF16LowerBound: Int,
        sourceUTF16UpperBound: Int,
        mappingKind: MappingKind = .sourceSpan
    ) {
        self.normalizedUTF16LowerBound = normalizedUTF16LowerBound
        self.normalizedUTF16UpperBound = normalizedUTF16UpperBound
        self.sourceUTF16LowerBound = sourceUTF16LowerBound
        self.sourceUTF16UpperBound = sourceUTF16UpperBound
        self.mappingKind = mappingKind
    }

    public func sourceUTF16Range(
        forNormalizedUTF16Range range: Range<Int>
    ) -> Range<Int>? {
        let overlapLower = max(range.lowerBound, normalizedUTF16LowerBound)
        let overlapUpper = min(range.upperBound, normalizedUTF16UpperBound)
        guard overlapLower < overlapUpper else { return nil }
        guard mappingKind == .linear else {
            return sourceUTF16LowerBound..<sourceUTF16UpperBound
        }
        return (sourceUTF16LowerBound + overlapLower - normalizedUTF16LowerBound)..<(sourceUTF16LowerBound + overlapUpper - normalizedUTF16LowerBound)
    }
}

public struct SearchTextSegment: Codable, Hashable, Sendable {
    public let field: SearchMatchedField
    public let ordinal: Int
    public let text: String
    /// Tokenizer-policy comparison text (case/whitespace/diacritic folded),
    /// with `offsetMap` preserving exact UTF-16 source recovery.
    public let normalizedText: String
    public let sourceRange: SearchSourceRange?
    public let offsetMap: [SearchSegmentOffset]
    public let relatedRankingText: [String: String]

    public init(
        field: SearchMatchedField,
        ordinal: Int,
        text: String,
        normalizedText: String,
        sourceRange: SearchSourceRange?,
        offsetMap: [SearchSegmentOffset],
        relatedRankingText: [String: String] = [:]
    ) {
        self.field = field
        self.ordinal = ordinal
        self.text = text
        self.normalizedText = normalizedText
        self.sourceRange = sourceRange
        self.offsetMap = offsetMap
        self.relatedRankingText = relatedRankingText
    }

    public func sourceUTF16Range(
        forNormalizedUTF16Range range: Range<Int>
    ) -> Range<Int>? {
        var sourceLower: Int?
        var sourceUpper: Int?
        for mapping in offsetMap {
            guard let mapped = mapping.sourceUTF16Range(forNormalizedUTF16Range: range) else { continue }
            sourceLower = min(sourceLower ?? mapped.lowerBound, mapped.lowerBound)
            sourceUpper = max(sourceUpper ?? mapped.upperBound, mapped.upperBound)
        }
        guard let sourceLower, let sourceUpper else {
            return sourceRange.map { $0.utf16LowerBound..<$0.utf16UpperBound }
        }
        return sourceLower..<sourceUpper
    }
}

/// Disposable semantic text derived from exact Markdown. It deliberately has
/// no raw-source field and is never a writable representation of a note.
public struct SearchParagraphProjection: Codable, Hashable, Sendable {
    public let range: SearchSourceRange
    public let segments: [SearchTextSegment]

    package init(range: SearchSourceRange, segments: [SearchTextSegment]) {
        self.range = range
        self.segments = segments
    }
}

public struct SearchDocumentProjection: Codable, Hashable, Sendable {
    public private(set) var title: String
    public private(set) var aliases: [String]
    public let headings: [String]
    public let summary: String?
    public private(set) var authors: [String]
    public private(set) var publicationDate: String?
    public let tags: [String]
    public let body: String
    public let callouts: String
    public let calloutRoles: Set<String>
    public let footnotes: String
    public let linkAnnotations: String
    public let path: String
    public private(set) var hasBrokenLink: Bool
    public let sourceLineStartsUTF16: [Int]
    public private(set) var segments: [SearchTextSegment]
    public let paragraphs: [SearchParagraphProjection]
    public private(set) var projectionHash: String

    /// Restores a disposable projection through the package-owned cache codec.
    /// The cache owner must bind these values to the exact source fingerprint
    /// and validate stored coordinates before supplying them to Search.
    package init(
        title: String,
        aliases: [String],
        headings: [String],
        summary: String?,
        authors: [String],
        publicationDate: String?,
        tags: [String],
        body: String,
        callouts: String,
        calloutRoles: Set<String>,
        footnotes: String,
        linkAnnotations: String,
        path: String,
        hasBrokenLink: Bool,
        sourceLineStartsUTF16: [Int],
        segments: [SearchTextSegment],
        paragraphs: [SearchParagraphProjection],
        projectionHash: String
    ) {
        self.title = title
        self.aliases = aliases
        self.headings = headings
        self.summary = summary
        self.authors = authors
        self.publicationDate = publicationDate
        self.tags = tags
        self.body = body
        self.callouts = callouts
        self.calloutRoles = calloutRoles
        self.footnotes = footnotes
        self.linkAnnotations = linkAnnotations
        self.path = path
        self.hasBrokenLink = hasBrokenLink
        self.sourceLineStartsUTF16 = sourceLineStartsUTF16
        self.segments = segments
        self.paragraphs = paragraphs
        self.projectionHash = projectionHash
    }

    public init(
        document: NoteDocument,
        profile: SchemaProfileID = .genericMarkdown,
        semantic: MarkdownSemanticDocument? = nil,
        hasBrokenLink: Bool = false
    ) {
        let semantic = semantic ?? MarkdownSemanticDocument(parsing: document)
        let source = SearchSourceTextProjection(document: document, profile: profile, semantic: semantic)
        let locator = SearchSourceLocator(source: document.rawContent)
        title = source.title
        aliases = source.properties.textValues(forExactKey: "aliases")
        headings = semantic.headings.map(\.text)
        summary = source.summary
        authors = source.properties.textValues(forExactKey: "authors") + source.properties.textValues(forExactKey: "author")
        publicationDate = source.properties.textValues(forExactKey: "publication_date").first
        tags = source.properties.stringListMembers(forExactKey: "keywords").map(\.value)
        path = document.relativePath
        self.hasBrokenLink = hasBrokenLink
        calloutRoles = Set(semantic.callouts.map { $0.role.rawValue })
        sourceLineStartsUTF16 = locator.lineStartsUTF16
        segments = source.preparedSegments(in: document, sourceLocator: locator)
        paragraphs = source.paragraphs(in: document, segments: segments, sourceLocator: locator)
        body = segments.filter { $0.field == .body }.map(\.text).joined(separator: "\n")
        callouts = segments.filter { $0.field == .callout }.map(\.text).joined(separator: "\n")
        footnotes = segments.filter { $0.field == .footnote }.map(\.text).joined(separator: "\n")
        linkAnnotations = segments.filter { $0.field == .linkAnnotation }.map(\.text).joined(separator: "\n")
        projectionHash = Self.hash(segments: segments, hasBrokenLink: hasBrokenLink)
    }

    /// Source-bound segments are shared with passage scoring. That consumer
    /// has its own complete nested passage set and needs neither Search's
    /// top-level paragraph corpus nor its aggregate fields and projection hash.
    package static func sourceSegments(
        document: NoteDocument,
        semantic: MarkdownSemanticDocument,
        profile: SchemaProfileID = .genericMarkdown
    ) -> [SearchTextSegment] {
        SearchSourceTextProjection(document: document, profile: profile, semantic: semantic)
            .preparedSegments(in: document, sourceLocator: SearchSourceLocator(source: document.rawContent))
    }

    /// Prepare one exact source with a body tree shared only by its semantic
    /// and Search walks. The tree stays local; callers receive source-bound
    /// values rather than an AST that could be paired with another document.
    package static func prepareSourceSegments(
        document: NoteDocument,
        profile: SchemaProfileID = .genericMarkdown
    ) -> (semantic: MarkdownSemanticDocument, segments: [SearchTextSegment]) {
        let parsedBody = Document(parsing: document.body, options: [.parseBlockDirectives])
        let semantic = MarkdownSemanticParser.parse(document, parsedBody: parsedBody)
        let source = SearchSourceTextProjection(
            document: document, profile: profile, semantic: semantic, parsedBody: parsedBody)
        return (semantic, source.preparedSegments(in: document, sourceLocator: SearchSourceLocator(source: document.rawContent)))
    }

    /// Passage scoring consumes attributed field text, not Search coordinates.
    /// Keep the parsed tree local to the exact snippet's semantic and text walks.
    package static func preparePassageRanking(
        document: NoteDocument
    ) -> (semantic: MarkdownSemanticDocument, rankingText: [[String: String]]) {
        let parsedBody = Document(parsing: document.body, options: [.parseBlockDirectives])
        let semantic = MarkdownSemanticParser.parse(document, parsedBody: parsedBody)
        let source = SearchSourceTextProjection(
            document: document, profile: .genericMarkdown, semantic: semantic, parsedBody: parsedBody,
            purpose: .passageRanking)
        return (semantic, source.passageRankingText(in: document))
    }

    /// Reuses the source-derived visible-text and exact-offset projection when
    /// only graph state changed. Source catalog versions bind the cached
    /// projection to the exact `NoteDocument`; this copy operation updates
    /// only the dynamic Search field and its projection hash.
    package func applyingDynamicState(
        hasBrokenLink: Bool
    ) -> SearchDocumentProjection {
        var updated = self
        updated.hasBrokenLink = hasBrokenLink
        updated.projectionHash = Self.hash(
            segments: updated.segments,
            hasBrokenLink: hasBrokenLink
        )
        return updated
    }

    private static func hash(
        segments: [SearchTextSegment],
        hasBrokenLink: Bool
    ) -> String {
        var hasher = SHA256()
        let fieldSeparator = Data("\u{1F}".utf8)
        let segmentSeparator = Data("\u{1E}".utf8)
        let stateSeparator = Data("\u{1D}".utf8)

        func update(_ value: String) {
            hasher.update(data: Data(value.utf8))
        }

        for (index, segment) in segments.enumerated() {
            if index > 0 { hasher.update(data: segmentSeparator) }
            update(segment.field.rawValue)
            hasher.update(data: fieldSeparator)
            update(String(segment.ordinal))
            hasher.update(data: fieldSeparator)
            update(segment.normalizedText)
            for key in segment.relatedRankingText.keys.sorted() {
                hasher.update(data: fieldSeparator)
                update(key)
                hasher.update(data: fieldSeparator)
                update(segment.relatedRankingText[key] ?? "")
            }
        }
        hasher.update(data: stateSeparator)
        update(String(hasBrokenLink))
        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }

    public func text(for field: SearchMatchedField) -> String {
        switch field {
        case .title: title
        case .alias: aliases.joined(separator: "\n")
        case .heading: headings.joined(separator: "\n")
        case .summary: summary ?? ""
        case .author: authors.joined(separator: "\n")
        case .publicationDate: publicationDate ?? ""
        case .tag: tags.joined(separator: "\n")
        case .body: body
        case .callout: callouts
        case .footnote: footnotes
        case .linkAnnotation: linkAnnotations
        case .path: path
        case .brokenLink: ""
        }
    }
}

private struct SearchSourceSegmentInput {
    let field: SearchMatchedField
    let text: String
    let sourceRange: Range<Int>?
    var explicitMap: [SearchVisibleFragment]? = nil
}

/// One exact-source preparation shared by Note Search and Research scoring.
/// Only complete Note Search asks it for the separate top-level paragraph corpus.
private struct SearchSourceTextProjection {
    enum Purpose {
        case search, passageRanking
    }

    let title: String
    let summary: String?
    let properties: SearchPropertyProjection
    let sourceContext: SearchSourceProjectionContext
    let parsedBody: Document
    let segmentInputs: [SearchSourceSegmentInput]
    let sourceAttribution: RelatedContentSourceAttribution

    init(
        document: NoteDocument, profile: SchemaProfileID, semantic: MarkdownSemanticDocument,
        parsedBody: Document? = nil, purpose: Purpose = .search
    ) {
        // Passage scoring discards identity fields. In particular, deriving a
        // filename through a relative file URL repeats current-directory I/O
        // for every snippet, although that title never reaches its ranking.
        title = purpose == .search ? ResearchNoteTitleResolver.resolve(document: document) : ""
        properties = SearchPropertyProjection(document: document, profile: profile)
        let summaryMember =
            properties.entry(forExactKey: "summary")
            .flatMap { entry in
                entry.valueKind == .string && entry.stringMembers.count == 1
                    ? entry.stringMembers.first
                    : nil
            }
        summary = summaryMember?.value
        let keywordMembers = properties.stringListMembers(forExactKey: "keywords")
        sourceContext = SearchSourceProjectionContext(
            source: document.body,
            fullSourceUTF16Offset: document.rawContent.utf16.count - document.body.utf16.count,
            semantic: semantic,
            anchorRanges: ParagraphAnchorPlanner.anchors(in: document, semantic: semantic).map(\.markerSpan.utf16Range)
        )
        var builtSegments: [SearchSourceSegmentInput] = []
        if purpose == .search {
            builtSegments.append(
                SearchSourceSegmentInput(
                    field: .title,
                    text: title,
                    sourceRange: nil
                ))
        }
        for member in keywordMembers where !member.value.isEmpty {
            let range = member.sourceRange.map {
                $0.utf16LowerBound..<$0.utf16UpperBound
            }
            builtSegments.append(
                SearchSourceSegmentInput(
                    field: .tag,
                    text: member.value,
                    sourceRange: range,
                    explicitMap: range.map {
                        SearchProjectionBuilder.alignedFragments(
                            text: member.value,
                            sourceRange: $0,
                            source: document.rawContent
                        )
                    }
                ))
        }
        if purpose == .search {
            builtSegments.append(
                SearchSourceSegmentInput(
                    field: .path,
                    text: document.relativePath,
                    sourceRange: nil
                ))
        }

        for heading in semantic.headings {
            let range = heading.span.utf16Range
            builtSegments.append(
                SearchSourceSegmentInput(
                    field: .heading,
                    text: heading.text,
                    sourceRange: range,
                    explicitMap: SearchProjectionBuilder.alignedFragments(
                        text: heading.text,
                        sourceRange: range,
                        source: document.rawContent
                    )
                ))
        }
        if let summaryMember, let summarySourceRange = summaryMember.sourceRange {
            let range = Range(
                uncheckedBounds: (
                    summarySourceRange.utf16LowerBound,
                    summarySourceRange.utf16UpperBound
                )
            )
            builtSegments.append(
                SearchSourceSegmentInput(
                    field: .summary,
                    text: summaryMember.value,
                    sourceRange: range,
                    explicitMap: SearchProjectionBuilder.alignedFragments(
                        text: summaryMember.value,
                        sourceRange: range,
                        source: document.rawContent
                    )
                ))
        }
        for callout in semantic.callouts {
            let visible = [callout.title, ResearchExcerptPresentation.readableText(callout.bodySource)]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !visible.isEmpty else { continue }
            let range = callout.span.utf16Range
            builtSegments.append(
                SearchSourceSegmentInput(
                    field: .callout,
                    text: visible,
                    sourceRange: range,
                    explicitMap: SearchProjectionBuilder.alignedFragments(
                        text: visible,
                        sourceRange: range,
                        source: document.rawContent
                    )
                ))
        }
        for footnote in semantic.footnoteDefinitions where !footnote.content.isEmpty {
            let visible = ResearchExcerptPresentation.readableText(footnote.content)
            guard !visible.isEmpty else { continue }
            let range = footnote.span.utf16Range
            builtSegments.append(
                SearchSourceSegmentInput(
                    field: .footnote,
                    text: visible,
                    sourceRange: range,
                    explicitMap: SearchProjectionBuilder.alignedFragments(
                        text: visible,
                        sourceRange: range,
                        source: document.rawContent
                    )
                ))
        }
        for annotation in sourceContext.annotations {
            let range = annotation.contentSpan.utf16Range
            builtSegments.append(
                SearchSourceSegmentInput(
                    field: .linkAnnotation,
                    text: annotation.text,
                    sourceRange: range,
                    explicitMap: SearchProjectionBuilder.alignedFragments(
                        text: annotation.text,
                        sourceRange: range,
                        source: document.rawContent
                    )
                ))
        }

        var collector = SearchVisibleTextCollector(context: sourceContext)
        self.parsedBody = parsedBody ?? Document(parsing: document.body, options: [.parseBlockDirectives])
        collector.visit(self.parsedBody)
        if !collector.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            builtSegments.append(
                SearchSourceSegmentInput(
                    field: .body,
                    text: collector.text,
                    sourceRange: collector.coveringSourceRange,
                    explicitMap: collector.fragments
                ))
        }

        if purpose == .search {
            let fieldKeys: [(SearchMatchedField, [String])] = [
                (.title, ["title"]), (.alias, ["aliases"]),
                (.author, ["authors", "author"]), (.publicationDate, ["publication_date"]),
            ]
            for (field, keys) in fieldKeys {
                for key in keys {
                    for member in properties.entry(forExactKey: key)?.stringMembers ?? [] {
                        guard let span = member.sourceRange, !member.value.isEmpty else { continue }
                        let range = span.utf16LowerBound..<span.utf16UpperBound
                        builtSegments.append(
                            SearchSourceSegmentInput(
                                field: field, text: member.value, sourceRange: range,
                                explicitMap: SearchProjectionBuilder.alignedFragments(
                                    text: member.value, sourceRange: range, source: document.rawContent)))
                    }
                }
            }
        }
        sourceAttribution = RelatedContentSourceAttribution(in: semantic)
        segmentInputs = builtSegments
    }

    func preparedSegments(in document: NoteDocument, sourceLocator: SearchSourceLocator) -> [SearchTextSegment] {
        segmentInputs.enumerated().map { ordinal, input in
            SearchProjectionBuilder.segment(
                field: input.field, ordinal: ordinal, text: input.text,
                sourceRange: input.sourceRange, source: document.rawContent,
                sourceLocator: sourceLocator, explicitMap: input.explicitMap
            )
            .attributingRelatedContent(using: sourceAttribution)
        }
    }

    func passageRankingText(in document: NoteDocument) -> [[String: String]] {
        // Attribution of linked or annotated text requires complete normalized
        // offsets. Keep that established route rather than inventing coordinates.
        if sourceAttribution.hasLinks || sourceAttribution.hasAnnotations {
            return preparedSegments(in: document, sourceLocator: SearchSourceLocator(source: document.rawContent))
                .filter { $0.sourceRange != nil && $0.field != .title && $0.field != .alias }
                .map(\.relatedRankingText)
        }
        return segmentInputs.compactMap { input in
            guard input.sourceRange != nil, input.field != .title, input.field != .alias,
                let field = RelatedContentRankingField(searchField: input.field)
            else { return nil }
            // Preserve the same fragment boundaries and per-grapheme folding.
            // This internal tuple never becomes a SearchTextSegment without maps.
            let normalized = SearchProjectionBuilder.normalizedTextAndMap(
                text: input.text, sourceRange: input.sourceRange,
                explicitMap: input.explicitMap, recordsOffsets: false
            ).text
            return normalized.isEmpty ? [:] : [field.rawValue: " " + normalized]
        }
    }

    func paragraphs(
        in document: NoteDocument, segments: [SearchTextSegment], sourceLocator: SearchSourceLocator
    ) -> [SearchParagraphProjection] {
        let builtSegments = segments
        var annotationSegmentsByStart: [Int: [SearchTextSegment]] = [:]
        for segment in builtSegments where segment.field == .linkAnnotation {
            guard let start = segment.sourceRange?.utf16LowerBound else { continue }
            annotationSegmentsByStart[start, default: []].append(segment)
        }
        return
            document.hasProvableBodyBoundary
            ? parsedBody.children.compactMap { child -> SearchParagraphProjection? in
                guard child is Paragraph, let rawRange = child.range.flatMap(sourceContext.utf16Range),
                    let block = sourceContext.paragraph(startingAt: sourceContext.fullSourceUTF16Offset + rawRange.lowerBound)
                else { return nil }
                let range = block.span.utf16Range
                guard !sourceContext.overlapsProtectedRange(range),
                    !sourceContext.annotationContains(range.lowerBound)
                else { return nil }
                var local = SearchVisibleTextCollector(context: sourceContext)
                local.visit(child)
                var localSegments = [
                    SearchProjectionBuilder.segment(
                        field: .body, ordinal: 0, text: local.text,
                        sourceRange: range, source: document.rawContent, sourceLocator: sourceLocator, explicitMap: local.fragments)
                ]
                let annotations = sourceContext.annotationsForLinks(startingIn: range)
                for annotation in annotations {
                    localSegments.append(contentsOf: annotationSegmentsByStart[annotation.contentSpan.utf16LowerBound] ?? [])
                }
                let upper = max(range.upperBound, annotations.map(\.span.utf16UpperBound).max() ?? range.upperBound)
                return SearchParagraphProjection(range: sourceLocator.sourceRange(range.lowerBound..<upper), segments: localSegments)
            } : []
    }
}

private enum SearchProjectionBuilder {
    /// Aligns rendered semantic text to the exact source monotonically while
    /// allowing Markdown delimiters, quote markers, and footnote prefixes to
    /// remain between matched characters. A returned hit therefore selects
    /// the authoritative source interval, never a reconstructed string.
    static func alignedFragments(
        text: String,
        sourceRange: Range<Int>,
        source: String
    ) -> [SearchVisibleFragment] {
        let fallback = [
            SearchVisibleFragment(
                textRange: 0..<text.utf16.count,
                sourceRange: sourceRange,
                exact: false
            )
        ]
        let nsSource = source as NSString
        guard sourceRange.lowerBound >= 0,
            sourceRange.upperBound <= nsSource.length
        else { return fallback }
        var fragments: [SearchVisibleFragment] = []
        var sourceCursor = sourceRange.lowerBound
        var textCursor = 0
        for character in text {
            let value = String(character)
            let textLength = value.utf16.count
            let remaining = NSRange(
                location: sourceCursor,
                length: max(0, sourceRange.upperBound - sourceCursor)
            )
            let match = nsSource.range(of: value, options: [], range: remaining)
            guard match.location != NSNotFound else { return fallback }
            fragments.append(
                SearchVisibleFragment(
                    textRange: textCursor..<(textCursor + textLength),
                    sourceRange: match.location..<NSMaxRange(match),
                    exact: true
                ))
            sourceCursor = NSMaxRange(match)
            textCursor += textLength
        }
        return fragments
    }

    static func segment(
        field: SearchMatchedField,
        ordinal: Int,
        text: String,
        sourceRange: Range<Int>?,
        source: String,
        sourceLocator: SearchSourceLocator,
        explicitMap: [SearchVisibleFragment]? = nil
    ) -> SearchTextSegment {
        let normalized = normalizedTextAndMap(
            text: text,
            sourceRange: sourceRange,
            explicitMap: explicitMap
        )
        return SearchTextSegment(
            field: field,
            ordinal: ordinal,
            text: text,
            normalizedText: normalized.text,
            sourceRange: sourceRange.map(sourceLocator.sourceRange),
            offsetMap: normalized.map
        )
    }

    static func normalizedTextAndMap(
        text: String,
        sourceRange: Range<Int>?,
        explicitMap: [SearchVisibleFragment]?,
        recordsOffsets: Bool = true
    ) -> (text: String, map: [SearchSegmentOffset]) {
        var normalized = ""
        normalized.reserveCapacity(text.utf16.count)
        var normalizedUTF16Count = 0
        var map: [SearchSegmentOffset] = []
        // Grow with actual mapping runs. Reserving from source length retains
        // unused capacity for every cached segment after linear runs coalesce.

        func appendMapping(
            normalizedRange: Range<Int>,
            sourceRange: Range<Int>,
            kind: SearchSegmentOffset.MappingKind
        ) {
            guard recordsOffsets else { return }
            if let last = map.last,
                last.mappingKind == kind,
                last.normalizedUTF16UpperBound == normalizedRange.lowerBound
            {
                let canMerge: Bool
                switch kind {
                case .linear:
                    canMerge =
                        last.sourceUTF16UpperBound == sourceRange.lowerBound
                        && last.normalizedUTF16UpperBound - last.normalizedUTF16LowerBound
                            == last.sourceUTF16UpperBound - last.sourceUTF16LowerBound
                        && normalizedRange.count == sourceRange.count
                case .sourceSpan:
                    canMerge =
                        last.sourceUTF16LowerBound == sourceRange.lowerBound
                        && last.sourceUTF16UpperBound == sourceRange.upperBound
                }
                if canMerge {
                    map[map.count - 1] = SearchSegmentOffset(
                        normalizedUTF16LowerBound: last.normalizedUTF16LowerBound,
                        normalizedUTF16UpperBound: normalizedRange.upperBound,
                        sourceUTF16LowerBound: last.sourceUTF16LowerBound,
                        sourceUTF16UpperBound: kind == .linear ? sourceRange.upperBound : last.sourceUTF16UpperBound,
                        mappingKind: kind)
                    return
                }
            }
            map.append(
                SearchSegmentOffset(
                    normalizedUTF16LowerBound: normalizedRange.lowerBound,
                    normalizedUTF16UpperBound: normalizedRange.upperBound,
                    sourceUTF16LowerBound: sourceRange.lowerBound,
                    sourceUTF16UpperBound: sourceRange.upperBound,
                    mappingKind: kind))
        }
        var hasPendingWhitespace = false
        var pendingWhitespaceSource: Range<Int>?
        let fragments =
            explicitMap ?? [
                SearchVisibleFragment(
                    textRange: 0..<text.utf16.count,
                    sourceRange: sourceRange,
                    exact: sourceRange?.count == text.utf16.count
                )
            ]

        for fragment in fragments {
            let nsText = text as NSString
            guard fragment.textRange.lowerBound >= 0,
                fragment.textRange.upperBound <= nsText.length
            else { continue }
            let fragmentText = nsText.substring(
                with: NSRange(
                    location: fragment.textRange.lowerBound,
                    length: fragment.textRange.count
                ))

            // Most visible prose is already in the lexical comparison form.
            // Normalize that fragment once, then coalesce exact single-unit
            // graphemes into linear runs. Larger graphemes retain atomic spans.
            if !hasPendingWhitespace,
                !fragmentText.contains(where: { $0.isWhitespace }),
                SearchTextNormalization.lexicalNormalize(fragmentText) == fragmentText
            {
                let lower = normalizedUTF16Count
                normalized.append(contentsOf: fragmentText)
                normalizedUTF16Count += fragmentText.utf16.count
                if recordsOffsets, let sourceRange = fragment.sourceRange {
                    if !fragment.exact {
                        appendMapping(
                            normalizedRange: lower..<normalizedUTF16Count,
                            sourceRange: sourceRange,
                            kind: .sourceSpan)
                    } else {
                        var localUTF16 = 0
                        for character in fragmentText {
                            let characterLength = String(character).utf16.count
                            let originalLower = localUTF16
                            let originalUpper = localUTF16 + characterLength
                            localUTF16 = originalUpper
                            let mappedSource = (sourceRange.lowerBound + originalLower)..<(sourceRange.lowerBound + originalUpper)
                            appendMapping(
                                normalizedRange: (lower + originalLower)..<(lower + originalUpper),
                                sourceRange: mappedSource,
                                kind: characterLength == 1 ? .linear : .sourceSpan)
                        }
                    }
                }
                continue
            }

            var localUTF16 = 0
            for character in fragmentText {
                let characterLength = String(character).utf16.count
                let originalLower = localUTF16
                let originalUpper = localUTF16 + characterLength
                localUTF16 = originalUpper
                let mappedSource: Range<Int>? =
                    recordsOffsets
                    ? fragment.sourceRange.map { range in
                        guard fragment.exact else { return range }
                        return (range.lowerBound + originalLower)..<(range.lowerBound + originalUpper)
                    } : nil
                if character.isWhitespace {
                    if normalized.isEmpty { continue }
                    hasPendingWhitespace = true
                    if pendingWhitespaceSource == nil, let mappedSource {
                        pendingWhitespaceSource = mappedSource
                    }
                    continue
                }
                if hasPendingWhitespace {
                    let lower = normalizedUTF16Count
                    normalized.append(" ")
                    normalizedUTF16Count += 1
                    if let pendingWhitespaceSource {
                        appendMapping(
                            normalizedRange: lower..<(lower + 1),
                            sourceRange: pendingWhitespaceSource,
                            kind: pendingWhitespaceSource.count == 1 ? .linear : .sourceSpan)
                    }
                    hasPendingWhitespace = false
                    pendingWhitespaceSource = nil
                }
                // ASCII folding is a single case conversion; retain the lexical
                // policy's Foundation normalization for every other grapheme,
                // including composed accents and case-folding expansions.
                let folded: String
                if let ascii = character.asciiValue {
                    let scalar = ascii >= 65 && ascii <= 90 ? ascii + 32 : ascii
                    folded = String(UnicodeScalar(scalar))
                } else {
                    folded = SearchTextNormalization.lexicalNormalize(String(character))
                }
                let lower = normalizedUTF16Count
                normalized += folded
                normalizedUTF16Count += folded.utf16.count
                let upper = normalizedUTF16Count
                if let mappedSource {
                    let linear =
                        characterLength == 1 && folded.utf16.count == 1
                        && mappedSource.count == 1
                    appendMapping(
                        normalizedRange: lower..<upper,
                        sourceRange: mappedSource,
                        kind: linear ? .linear : .sourceSpan)
                }
            }
        }
        return (normalized, map)
    }
}

private struct SearchSourceLocator {
    let source: String
    private let nsSource: NSString
    private let lineStarts: [Int]

    var lineStartsUTF16: [Int] { lineStarts }

    init(source: String) {
        self.source = source
        nsSource = source as NSString
        var starts = [0]
        var index = 0
        while index < nsSource.length {
            let scalar = nsSource.character(at: index)
            if scalar == 13 {
                if index + 1 < nsSource.length, nsSource.character(at: index + 1) == 10 {
                    index += 1
                }
                starts.append(index + 1)
            } else if scalar == 10 {
                starts.append(index + 1)
            }
            index += 1
        }
        lineStarts = starts
    }

    func sourceRange(_ range: Range<Int>) -> SearchSourceRange {
        let start = position(range.lowerBound)
        let end = position(range.upperBound)
        return SearchSourceRange(
            utf16LowerBound: range.lowerBound,
            utf16UpperBound: range.upperBound,
            line: start.line,
            column: start.column,
            endLine: end.line,
            endColumn: end.column
        )
    }

    func utf16Range(forUTF8Range range: Range<Int>) -> Range<Int>? {
        guard
            let lowerUTF8 = source.utf8.index(
                source.utf8.startIndex,
                offsetBy: range.lowerBound,
                limitedBy: source.utf8.endIndex
            ),
            let upperUTF8 = source.utf8.index(
                source.utf8.startIndex,
                offsetBy: range.upperBound,
                limitedBy: source.utf8.endIndex
            ), let lower = lowerUTF8.samePosition(in: source),
            let upper = upperUTF8.samePosition(in: source)
        else { return nil }
        return lower.utf16Offset(in: source)..<upper.utf16Offset(in: source)
    }

    private func position(_ offset: Int) -> (line: Int, column: Int) {
        let bounded = min(max(0, offset), nsSource.length)
        var low = 0
        var high = lineStarts.count
        while low + 1 < high {
            let middle = (low + high) / 2
            if lineStarts[middle] <= bounded { low = middle } else { high = middle }
        }
        return (low + 1, bounded - lineStarts[low] + 1)
    }
}

private struct SearchVisibleFragment {
    let textRange: Range<Int>
    let sourceRange: Range<Int>?
    let exact: Bool
}

/// One note's immutable source topology. Queries restore semantic-array order
/// before the existing visible-text projection resolves overlaps and ties.
struct SearchSourceProjectionContext {
    let source: NSString
    let fullSourceUTF16Offset: Int
    let annotations: [LinkAnnotation]
    private let mapper: SearchMarkdownSourceMapper
    private let paragraphsByStart: [Int: MarkdownBlock]
    private let links: [LinkOccurrence]
    private let linkRanges: SearchSourceProjectionRanges
    private let excludedRanges: SearchSourceProjectionRanges
    private let anchorRanges: SearchSourceProjectionRanges
    private let annotationRanges: SearchSourceProjectionRanges
    private let protectedRanges: SearchSourceProjectionRanges

    init(
        source: String,
        fullSourceUTF16Offset: Int,
        semantic: MarkdownSemanticDocument,
        anchorRanges: [Range<Int>]
    ) {
        self.source = source as NSString
        self.fullSourceUTF16Offset = fullSourceUTF16Offset
        mapper = SearchMarkdownSourceMapper(source)
        var paragraphs: [Int: MarkdownBlock] = [:]
        for block in semantic.blocks where block.kind == .paragraph {
            let start = block.span.utf16LowerBound
            if paragraphs[start] == nil { paragraphs[start] = block }
        }
        paragraphsByStart = paragraphs
        links = semantic.links
        linkRanges = SearchSourceProjectionRanges(semantic.links.map(\.linkSpan.utf16Range))
        let annotations = semantic.links.compactMap(\.annotation)
        self.annotations = annotations
        annotationRanges = SearchSourceProjectionRanges(annotations.map(\.span.utf16Range))
        excludedRanges = SearchSourceProjectionRanges(
            semantic.headings.map(\.span.utf16Range)
                + semantic.callouts.map(\.span.utf16Range)
                + semantic.footnoteDefinitions.map(\.span.utf16Range)
                + annotations.map(\.span.utf16Range)
                + anchorRanges
        )
        self.anchorRanges = SearchSourceProjectionRanges(anchorRanges)
        protectedRanges = SearchSourceProjectionRanges(
            semantic.footnoteDefinitions.map(\.span.utf16Range)
                + semantic.mathExpressions.filter { $0.kind == .display }.map(\.span.utf16Range)
        )
    }

    func utf16Range(_ range: Markdown.SourceRange) -> Range<Int>? {
        mapper.utf16Range(range)
    }

    func paragraph(startingAt start: Int) -> MarkdownBlock? { paragraphsByStart[start] }

    func annotationContains(_ point: Int) -> Bool { annotationRanges.contains(point) }

    func overlapsProtectedRange(_ range: Range<Int>) -> Bool {
        // Swift Range.overlaps excludes empty operands. Collector exclusion
        // checks below intentionally retain their different endpoint predicate.
        !range.isEmpty && protectedRanges.hasStrictOverlap(range, excludingEmpty: true)
    }

    func overlapsExcludedRange(_ range: Range<Int>) -> Bool {
        excludedRanges.hasStrictOverlap(range, excludingEmpty: false)
    }

    func clippedExcludedRanges(in range: Range<Int>) -> [Range<Int>] {
        excludedRanges.strictOverlaps(range).compactMap { excluded in
            let lower = max(excluded.lowerBound, range.lowerBound)
            let upper = min(excluded.upperBound, range.upperBound)
            return lower < upper ? lower..<upper : nil
        }
    }

    func containedVisibleLinks(in range: Range<Int>) -> [LinkOccurrence] {
        linkRanges.containedOrdinals(in: range).compactMap { ordinal in
            let link = links[ordinal]
            return link.syntax == .wikilink || link.syntax == .embed ? link : nil
        }
    }

    func firstAnchorSuffix(in range: Range<Int>) -> Range<Int>? {
        // The original first(where:) uses semantic-array order, not the
        // earliest source position, and excludes an anchor at the node start.
        anchorRanges.containedOrdinals(in: range, strictlyAfterLowerBound: true).first.map {
            anchorRanges.range(at: $0)
        }
    }

    func annotationsForLinks(startingIn range: Range<Int>) -> [LinkAnnotation] {
        // A paragraph owns an annotation through the LINK's start. The
        // annotation itself can extend beyond that paragraph's source range.
        linkRanges.startingOrdinals(in: range).compactMap { links[$0].annotation }
    }
}

/// Source-local range lookup; original ordinals remain authoritative. A
/// max-upper tree prunes long/nested ranges without scanning every earlier
/// interval, while start windows answer containment and paragraph ownership.
private struct SearchSourceProjectionRanges {
    private let ranges: [Range<Int>]
    private let order: [Int]
    private let maximumUpper: [Int]

    init(_ ranges: [Range<Int>]) {
        self.ranges = ranges
        let order = ranges.indices.sorted {
            if ranges[$0].lowerBound != ranges[$1].lowerBound {
                return ranges[$0].lowerBound < ranges[$1].lowerBound
            }
            return $0 < $1
        }
        self.order = order
        var maximumUpper = [Int](repeating: Int.min, count: ranges.count)
        func populate(_ lower: Int, _ upper: Int) -> Int {
            guard lower < upper else { return Int.min }
            let middle = lower + (upper - lower) / 2
            let maximum = max(
                ranges[order[middle]].upperBound,
                max(populate(lower, middle), populate(middle + 1, upper))
            )
            maximumUpper[middle] = maximum
            return maximum
        }
        _ = populate(0, ranges.count)
        self.maximumUpper = maximumUpper
    }

    func range(at ordinal: Int) -> Range<Int> { ranges[ordinal] }

    func containedOrdinals(in range: Range<Int>, strictlyAfterLowerBound: Bool = false) -> [Int] {
        let lower = startBound(range.lowerBound, afterEqual: strictlyAfterLowerBound)
        // Empty links at the node's upper boundary were admitted by the
        // original fully-contained predicate and must remain candidates.
        let upper = startBound(range.upperBound, afterEqual: true)
        return order[lower..<upper].filter { ranges[$0].upperBound <= range.upperBound }.sorted()
    }

    func startingOrdinals(in range: Range<Int>) -> [Int] {
        let lower = startBound(range.lowerBound, afterEqual: false)
        let upper = startBound(range.upperBound, afterEqual: false)
        return order[lower..<upper].sorted()
    }

    func contains(_ point: Int) -> Bool {
        func visit(_ lower: Int, _ upper: Int) -> Bool {
            guard lower < upper else { return false }
            let middle = lower + (upper - lower) / 2
            guard ranges[order[lower]].lowerBound <= point, maximumUpper[middle] > point else { return false }
            return ranges[order[middle]].contains(point)
                || visit(lower, middle) || visit(middle + 1, upper)
        }
        return visit(0, order.count)
    }

    func hasStrictOverlap(_ range: Range<Int>, excludingEmpty: Bool) -> Bool {
        func visit(_ lower: Int, _ upper: Int) -> Bool {
            guard lower < upper else { return false }
            let middle = lower + (upper - lower) / 2
            guard ranges[order[lower]].lowerBound < range.upperBound,
                maximumUpper[middle] > range.lowerBound
            else { return false }
            let candidate = ranges[order[middle]]
            if !excludingEmpty || !candidate.isEmpty,
                candidate.lowerBound < range.upperBound, candidate.upperBound > range.lowerBound
            {
                return true
            }
            return visit(lower, middle) || visit(middle + 1, upper)
        }
        return visit(0, order.count)
    }

    func strictOverlaps(_ range: Range<Int>) -> [Range<Int>] {
        var ordinals: [Int] = []
        func visit(_ lower: Int, _ upper: Int) {
            guard lower < upper else { return }
            let middle = lower + (upper - lower) / 2
            guard ranges[order[lower]].lowerBound < range.upperBound,
                maximumUpper[middle] > range.lowerBound
            else { return }
            let ordinal = order[middle]
            let candidate = ranges[ordinal]
            if candidate.lowerBound < range.upperBound, candidate.upperBound > range.lowerBound {
                ordinals.append(ordinal)
            }
            visit(lower, middle)
            visit(middle + 1, upper)
        }
        visit(0, order.count)
        return ordinals.sorted().map { ranges[$0] }
    }

    private func startBound(_ value: Int, afterEqual: Bool) -> Int {
        var lower = 0
        var upper = order.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            let start = ranges[order[middle]].lowerBound
            if start < value || (afterEqual && start == value) {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }
}

private struct SearchVisibleTextCollector: MarkupWalker {
    private struct SourceProjection {
        let range: Range<Int>
        let replacement: String?
        let replacementSourceRange: Range<Int>?
    }

    private let context: SearchSourceProjectionContext
    private(set) var text = ""
    private(set) var fragments: [SearchVisibleFragment] = []
    private var textUTF16Count = 0

    init(context: SearchSourceProjectionContext) { self.context = context }

    var coveringSourceRange: Range<Int>? {
        let ranges = fragments.compactMap(\.sourceRange)
        guard let first = ranges.first, let last = ranges.last else { return nil }
        return first.lowerBound..<last.upperBound
    }

    mutating func visitDocument(_ document: Document) { descendInto(document) }
    mutating func visitParagraph(_ paragraph: Paragraph) {
        descendInto(paragraph)
        appendSeparator("\n")
    }
    mutating func visitHeading(_ heading: Heading) { descendInto(heading) }
    mutating func visitText(_ node: Markdown.Text) { append(node.string, range: node.range) }
    mutating func visitInlineCode(_ node: InlineCode) { append(node.code, range: node.range) }
    mutating func visitCodeBlock(_ node: CodeBlock) {
        append(node.code, range: node.range)
        appendSeparator("\n")
    }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) { appendSeparator("\n") }
    mutating func visitLineBreak(_ lineBreak: LineBreak) { appendSeparator("\n") }
    mutating func visitImage(_ image: Image) {
        // Image children are the author-visible alt text. The source URL and
        // optional Markdown title are destinations/presentation metadata, not
        // searchable note prose.
        descendInto(image)
    }
    mutating func visitHTMLBlock(_ html: HTMLBlock) {}
    mutating func visitInlineHTML(_ html: InlineHTML) {}

    private mutating func append(_ value: String, range: Markdown.SourceRange?) {
        guard !value.isEmpty else { return }
        let relative = range.flatMap(context.utf16Range)
        let fullRange = relative.map {
            ($0.lowerBound + context.fullSourceUTF16Offset)..<($0.upperBound + context.fullSourceUTF16Offset)
        }
        let exact =
            relative.map { range in
                context.source.substring(
                    with: NSRange(
                        location: range.lowerBound,
                        length: range.count
                    )) == value
            } ?? false
        if let fullRange, exact, appendProjectedSource(in: fullRange) { return }
        // Entity decoding can make a Text node nonexact. Remove the known literal
        // suffix from its visible text while retaining the decoded neighboring prose.
        if !exact, let fullRange,
            let anchor = context.firstAnchorSuffix(in: fullRange)
        {
            let suffixRange = NSRange(
                location: anchor.lowerBound - context.fullSourceUTF16Offset,
                length: fullRange.upperBound - anchor.lowerBound
            )
            let suffix = context.source.substring(with: suffixRange)
            let prefixRange = fullRange.lowerBound..<anchor.lowerBound
            if value.hasSuffix(suffix),
                !context.overlapsExcludedRange(prefixRange)
            {
                appendFragment(String(value.dropLast(suffix.count)), sourceRange: prefixRange, exact: false)
                return
            }
        }
        if let fullRange, context.overlapsExcludedRange(fullRange) {
            return
        }
        appendFragment(value, sourceRange: fullRange, exact: exact)
    }

    /// Removes non-body semantic ranges without dropping neighboring prose and
    /// replaces custom Wikilink markup with only its reader-visible label.
    /// Returning false means the original Markdown node needs no custom work.
    private mutating func appendProjectedSource(in fullRange: Range<Int>) -> Bool {
        var projections = context.clippedExcludedRanges(in: fullRange).map { excluded in
            SourceProjection(range: excluded, replacement: nil, replacementSourceRange: nil)
        }
        projections.append(
            contentsOf: context.containedVisibleLinks(in: fullRange).map { link in
                let linkRange = link.linkSpan.utf16Range
                return SourceProjection(
                    range: linkRange,
                    replacement: link.alias ?? link.target,
                    replacementSourceRange: visibleLabelRange(for: link)
                )
            })
        guard !projections.isEmpty else { return false }
        projections.sort {
            if $0.range.lowerBound != $1.range.lowerBound {
                return $0.range.lowerBound < $1.range.lowerBound
            }
            if ($0.replacement == nil) != ($1.replacement == nil) {
                return $0.replacement == nil
            }
            return $0.range.upperBound > $1.range.upperBound
        }

        var cursor = fullRange.lowerBound
        for projection in projections {
            guard projection.range.upperBound > cursor else { continue }
            if projection.range.lowerBound > cursor {
                appendExactSource(cursor..<projection.range.lowerBound)
            }
            if projection.range.lowerBound >= cursor,
                let replacement = projection.replacement,
                !replacement.isEmpty
            {
                let sourceRange = projection.replacementSourceRange ?? projection.range
                appendFragment(
                    replacement,
                    sourceRange: sourceRange,
                    exact: exactSource(replacement, in: sourceRange)
                )
            }
            cursor = max(cursor, projection.range.upperBound)
        }
        if cursor < fullRange.upperBound { appendExactSource(cursor..<fullRange.upperBound) }
        return true
    }

    private mutating func appendExactSource(_ fullRange: Range<Int>) {
        let relative = (fullRange.lowerBound - context.fullSourceUTF16Offset)..<(fullRange.upperBound - context.fullSourceUTF16Offset)
        guard relative.lowerBound >= 0,
            relative.upperBound <= context.source.length
        else { return }
        let value = context.source.substring(
            with: NSRange(
                location: relative.lowerBound,
                length: relative.count
            ))
        appendFragment(value, sourceRange: fullRange, exact: true)
    }

    private mutating func appendFragment(
        _ value: String,
        sourceRange: Range<Int>?,
        exact: Bool
    ) {
        guard !value.isEmpty else { return }
        let start = textUTF16Count
        text += value
        textUTF16Count += value.utf16.count
        fragments.append(
            SearchVisibleFragment(
                textRange: start..<textUTF16Count,
                sourceRange: sourceRange,
                exact: exact
            ))
    }

    private func visibleLabelRange(for link: LinkOccurrence) -> Range<Int>? {
        let linkRange = link.linkSpan.utf16Range
        let relative = (linkRange.lowerBound - context.fullSourceUTF16Offset)..<(linkRange.upperBound - context.fullSourceUTF16Offset)
        let nsSource = context.source
        guard relative.lowerBound >= 0, relative.upperBound <= nsSource.length else { return nil }
        let raw = nsSource.substring(with: NSRange(location: relative.lowerBound, length: relative.count))
        let visible = link.alias ?? link.target
        let options: NSString.CompareOptions = link.alias == nil ? [] : [.backwards]
        let match = (raw as NSString).range(of: visible, options: options)
        guard match.location != NSNotFound else { return nil }
        return (linkRange.lowerBound + match.location)..<(linkRange.lowerBound + NSMaxRange(match))
    }

    private func exactSource(_ value: String, in fullRange: Range<Int>) -> Bool {
        let relative = (fullRange.lowerBound - context.fullSourceUTF16Offset)..<(fullRange.upperBound - context.fullSourceUTF16Offset)
        let nsSource = context.source
        guard relative.lowerBound >= 0, relative.upperBound <= nsSource.length else { return false }
        return nsSource.substring(
            with: NSRange(
                location: relative.lowerBound,
                length: relative.count
            )) == value
    }

    private mutating func appendSeparator(_ value: String) {
        guard !text.isEmpty, !text.hasSuffix(value) else { return }
        let start = textUTF16Count
        text += value
        textUTF16Count += value.utf16.count
        fragments.append(
            SearchVisibleFragment(
                textRange: start..<textUTF16Count,
                sourceRange: nil,
                exact: false
            ))
    }

}

private struct SearchMarkdownSourceMapper {
    private let nsSource: NSString
    private let lineStarts: [Int]

    init(_ source: String) {
        nsSource = source as NSString
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
        lineStarts = starts
    }

    func utf16Range(_ range: Markdown.SourceRange) -> Range<Int>? {
        guard let lower = utf16Offset(line: range.lowerBound.line, utf8Column: range.lowerBound.column),
            let upper = utf16Offset(line: range.upperBound.line, utf8Column: range.upperBound.column),
            upper >= lower
        else { return nil }
        return lower..<upper
    }

    private func utf16Offset(line: Int, utf8Column: Int) -> Int? {
        guard line > 0, line <= lineStarts.count, utf8Column > 0 else { return nil }
        let lineStart = lineStarts[line - 1]
        let lineEnd = line < lineStarts.count ? lineStarts[line] : nsSource.length
        let lineString = nsSource.substring(
            with: NSRange(
                location: lineStart,
                length: lineEnd - lineStart
            ))
        let byteOffset = utf8Column - 1
        guard
            let utf8 = lineString.utf8.index(
                lineString.utf8.startIndex,
                offsetBy: byteOffset,
                limitedBy: lineString.utf8.endIndex
            ), let stringIndex = utf8.samePosition(in: lineString)
        else { return nil }
        return lineStart + stringIndex.utf16Offset(in: lineString)
    }
}
