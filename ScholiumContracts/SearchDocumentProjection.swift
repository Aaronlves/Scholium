import CryptoKit
import Foundation
import Markdown

public struct SearchSegmentOffset: Codable, Hashable, Sendable {
    public let normalizedUTF16LowerBound: Int
    public let normalizedUTF16UpperBound: Int
    public let sourceUTF16LowerBound: Int
    public let sourceUTF16UpperBound: Int

    public init(
        normalizedUTF16LowerBound: Int,
        normalizedUTF16UpperBound: Int,
        sourceUTF16LowerBound: Int,
        sourceUTF16UpperBound: Int
    ) {
        self.normalizedUTF16LowerBound = normalizedUTF16LowerBound
        self.normalizedUTF16UpperBound = normalizedUTF16UpperBound
        self.sourceUTF16LowerBound = sourceUTF16LowerBound
        self.sourceUTF16UpperBound = sourceUTF16UpperBound
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

    public init(
        field: SearchMatchedField,
        ordinal: Int,
        text: String,
        normalizedText: String,
        sourceRange: SearchSourceRange?,
        offsetMap: [SearchSegmentOffset]
    ) {
        self.field = field
        self.ordinal = ordinal
        self.text = text
        self.normalizedText = normalizedText
        self.sourceRange = sourceRange
        self.offsetMap = offsetMap
    }

    public func sourceUTF16Range(
        forNormalizedUTF16Range range: Range<Int>
    ) -> Range<Int>? {
        let overlapping = offsetMap.filter {
            $0.normalizedUTF16LowerBound < range.upperBound
                && $0.normalizedUTF16UpperBound > range.lowerBound
        }
        guard let first = overlapping.first, let last = overlapping.last else {
            return sourceRange.map { $0.utf16LowerBound..<$0.utf16UpperBound }
        }
        return first.sourceUTF16LowerBound..<last.sourceUTF16UpperBound
    }
}

/// Disposable semantic text derived from exact Markdown. It deliberately has
/// no raw-source field and is never a writable representation of a note.
public struct SearchDocumentProjection: Codable, Hashable, Sendable {
    public let title: String
    public let titleUsesFilenameFallback: Bool
    public let aliases: [String]
    public let headings: [String]
    public let authors: [String]
    public let year: String?
    public let tags: [String]
    public let body: String
    public let callouts: String
    public let calloutRoles: Set<String>
    public let footnotes: String
    public let path: String
    public private(set) var review: String?
    public private(set) var hasBrokenLink: Bool
    public let sourceLineStartsUTF16: [Int]
    public let segments: [SearchTextSegment]
    public private(set) var projectionHash: String

    public init(
        document: NoteDocument,
        profile: SchemaProfileID = .genericMarkdown,
        semantic: MarkdownSemanticDocument? = nil,
        review: String? = nil,
        hasBrokenLink: Bool = false
    ) {
        let semantic = semantic ?? MarkdownSemanticDocument(parsing: document)
        let titleResolution = ResearchNoteTitleResolver.resolve(
            document: document,
            profile: profile,
            semantic: semantic
        )
        let titleValue = titleResolution.title
        title = titleValue
        titleUsesFilenameFallback = titleResolution.source == .filename
        aliases = document.parsedFrontmatter["aliases"]?.searchStrings
            ?? document.parsedFrontmatter["alias"]?.searchStrings
            ?? []
        headings = semantic.headings.map(\.text)
        authors = document.parsedFrontmatter["authors"]?.searchStrings
            ?? document.parsedFrontmatter["author"]?.searchStrings
            ?? []
        year = document.parsedFrontmatter["year"]?.displayScalar
        tags = document.parsedFrontmatter["tags"]?.searchStrings ?? []
        path = document.relativePath
        self.review = review?.lowercased()
        self.hasBrokenLink = hasBrokenLink
        calloutRoles = Set(semantic.callouts.map { $0.role.rawValue })

        let sourceLocator = SearchSourceLocator(source: document.rawContent)
        sourceLineStartsUTF16 = sourceLocator.lineStartsUTF16
        var builtSegments: [SearchTextSegment] = []
        func appendMetadata(
            _ values: [String],
            field: SearchMatchedField,
            preferredRange: Range<Int>?
        ) {
            for value in values where !value.isEmpty {
                let exact = sourceLocator.uniqueRange(of: value, within: preferredRange)
                builtSegments.append(SearchProjectionBuilder.segment(
                    field: field,
                    ordinal: builtSegments.count,
                    text: value,
                    sourceRange: exact,
                    source: document.rawContent,
                    sourceLocator: sourceLocator
                ))
            }
        }

        let frontmatterRange = document.frontmatterByteRange.flatMap {
            sourceLocator.utf16Range(forUTF8Range: $0)
        }
        if titleResolution.source == .analysisProperty {
            appendMetadata([title], field: .title, preferredRange: frontmatterRange)
        } else if titleResolution.source == .firstLevelOneHeading,
                  let heading = semantic.headings.first(where: { $0.level == 1 }) {
            let range = heading.span.utf16Range
            builtSegments.append(SearchProjectionBuilder.segment(
                field: .title,
                ordinal: builtSegments.count,
                text: title,
                sourceRange: range,
                source: document.rawContent,
                sourceLocator: sourceLocator,
                explicitMap: SearchProjectionBuilder.alignedFragments(
                    text: title,
                    sourceRange: range,
                    source: document.rawContent
                )
            ))
        } else {
            builtSegments.append(SearchProjectionBuilder.segment(
                field: .title,
                ordinal: builtSegments.count,
                text: title,
                sourceRange: nil,
                source: document.rawContent,
                sourceLocator: sourceLocator
            ))
        }
        appendMetadata(aliases, field: .alias, preferredRange: frontmatterRange)
        appendMetadata(authors, field: .author, preferredRange: frontmatterRange)
        if let year { appendMetadata([year], field: .year, preferredRange: frontmatterRange) }
        appendMetadata(tags, field: .tag, preferredRange: frontmatterRange)
        builtSegments.append(SearchProjectionBuilder.segment(
            field: .path,
            ordinal: builtSegments.count,
            text: document.relativePath,
            sourceRange: nil,
            source: document.rawContent,
            sourceLocator: sourceLocator
        ))

        for heading in semantic.headings {
            let range = heading.span.utf16Range
            builtSegments.append(SearchProjectionBuilder.segment(
                field: .heading,
                ordinal: builtSegments.count,
                text: heading.text,
                sourceRange: range,
                source: document.rawContent,
                sourceLocator: sourceLocator,
                explicitMap: SearchProjectionBuilder.alignedFragments(
                    text: heading.text,
                    sourceRange: range,
                    source: document.rawContent
                )
            ))
        }
        for callout in semantic.callouts {
            let visible = [callout.title, MarkdownVisibleText.render(callout.bodySource)]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !visible.isEmpty else { continue }
            let range = callout.span.utf16Range
            builtSegments.append(SearchProjectionBuilder.segment(
                field: .callout,
                ordinal: builtSegments.count,
                text: visible,
                sourceRange: range,
                source: document.rawContent,
                sourceLocator: sourceLocator,
                explicitMap: SearchProjectionBuilder.alignedFragments(
                    text: visible,
                    sourceRange: range,
                    source: document.rawContent
                )
            ))
        }
        for footnote in semantic.footnoteDefinitions where !footnote.content.isEmpty {
            let visible = MarkdownVisibleText.render(footnote.content)
            guard !visible.isEmpty else { continue }
            let range = footnote.span.utf16Range
            builtSegments.append(SearchProjectionBuilder.segment(
                field: .footnote,
                ordinal: builtSegments.count,
                text: visible,
                sourceRange: range,
                source: document.rawContent,
                sourceLocator: sourceLocator,
                explicitMap: SearchProjectionBuilder.alignedFragments(
                    text: visible,
                    sourceRange: range,
                    source: document.rawContent
                )
            ))
        }

        let excluded = semantic.headings.map(\.span.utf16Range)
            + semantic.callouts.map(\.span.utf16Range)
            + semantic.footnoteDefinitions.map(\.span.utf16Range)
        let bodyStart = document.rawContent.utf16.count - document.body.utf16.count
        var collector = SearchVisibleTextCollector(
            source: document.body,
            fullSourceUTF16Offset: bodyStart,
            excludedFullSourceRanges: excluded
        )
        collector.visit(Document(parsing: document.body))
        if !collector.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            builtSegments.append(SearchProjectionBuilder.segment(
                field: .body,
                ordinal: builtSegments.count,
                text: collector.text,
                sourceRange: collector.coveringSourceRange,
                source: document.rawContent,
                sourceLocator: sourceLocator,
                explicitMap: collector.fragments
            ))
        }

        segments = builtSegments
        body = builtSegments.filter { $0.field == .body }.map(\.text).joined(separator: "\n")
        callouts = builtSegments.filter { $0.field == .callout }.map(\.text).joined(separator: "\n")
        footnotes = builtSegments.filter { $0.field == .footnote }.map(\.text).joined(separator: "\n")

        projectionHash = Self.hash(
            segments: builtSegments,
            review: self.review,
            hasBrokenLink: hasBrokenLink
        )
    }

    /// Reuses the source-derived visible-text and exact-offset projection when
    /// only graph or legacy-review state changed. Source catalog versions bind
    /// the cached projection to the exact `NoteDocument`; this copy operation
    /// updates only the dynamic Search fields and their projection hash.
    func applyingDynamicState(
        review: String?,
        hasBrokenLink: Bool
    ) -> SearchDocumentProjection {
        var updated = self
        updated.review = review?.lowercased()
        updated.hasBrokenLink = hasBrokenLink
        updated.projectionHash = Self.hash(
            segments: updated.segments,
            review: updated.review,
            hasBrokenLink: hasBrokenLink
        )
        return updated
    }

    private static func hash(
        segments: [SearchTextSegment],
        review: String?,
        hasBrokenLink: Bool
    ) -> String {
        let stableMaterial = segments.map {
            "\($0.field.rawValue)\u{1F}\($0.ordinal)\u{1F}\($0.normalizedText)"
        }.joined(separator: "\u{1E}")
            + "\u{1D}\(review ?? "")\u{1D}\(hasBrokenLink)"
        return SHA256.hash(data: Data(stableMaterial.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    public func text(for field: SearchMatchedField) -> String {
        switch field {
        case .title: title
        case .alias: aliases.joined(separator: "\n")
        case .heading: headings.joined(separator: "\n")
        case .author: authors.joined(separator: "\n")
        case .year: year ?? ""
        case .tag: tags.joined(separator: "\n")
        case .body: body
        case .callout: callouts
        case .footnote: footnotes
        case .path: path
        case .review: review ?? ""
        case .brokenLink: ""
        }
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
        let nsSource = source as NSString
        guard sourceRange.lowerBound >= 0,
              sourceRange.upperBound <= nsSource.length else { return [] }
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
            if match.location != NSNotFound {
                fragments.append(SearchVisibleFragment(
                    textRange: textCursor..<(textCursor + textLength),
                    sourceRange: match.location..<NSMaxRange(match),
                    exact: true
                ))
                sourceCursor = NSMaxRange(match)
            }
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

    private static func normalizedTextAndMap(
        text: String,
        sourceRange: Range<Int>?,
        explicitMap: [SearchVisibleFragment]?
    ) -> (text: String, map: [SearchSegmentOffset]) {
        var normalized = ""
        var normalizedUTF16Count = 0
        var map: [SearchSegmentOffset] = []
        var hasPendingWhitespace = false
        var pendingWhitespaceSource: Range<Int>?
        let fragments = explicitMap ?? [SearchVisibleFragment(
            textRange: 0..<text.utf16.count,
            sourceRange: sourceRange,
            exact: sourceRange?.count == text.utf16.count
        )]

        for fragment in fragments {
            let nsText = text as NSString
            guard fragment.textRange.lowerBound >= 0,
                  fragment.textRange.upperBound <= nsText.length else { continue }
            let fragmentText = nsText.substring(with: NSRange(
                location: fragment.textRange.lowerBound,
                length: fragment.textRange.count
            ))
            var localUTF16 = 0
            for character in fragmentText {
                let characterLength = String(character).utf16.count
                let originalLower = localUTF16
                let originalUpper = localUTF16 + characterLength
                localUTF16 = originalUpper
                let mappedSource: Range<Int>? = fragment.sourceRange.map { range in
                    guard fragment.exact else { return range }
                    return (range.lowerBound + originalLower)..<(range.lowerBound + originalUpper)
                }
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
                        map.append(SearchSegmentOffset(
                            normalizedUTF16LowerBound: lower,
                            normalizedUTF16UpperBound: lower + 1,
                            sourceUTF16LowerBound: pendingWhitespaceSource.lowerBound,
                            sourceUTF16UpperBound: pendingWhitespaceSource.upperBound
                        ))
                    }
                    hasPendingWhitespace = false
                    pendingWhitespaceSource = nil
                }
                let folded = SearchTextNormalization.lexicalNormalize(String(character))
                let lower = normalizedUTF16Count
                normalized += folded
                normalizedUTF16Count += folded.utf16.count
                let upper = normalizedUTF16Count
                if let mappedSource {
                    map.append(SearchSegmentOffset(
                        normalizedUTF16LowerBound: lower,
                        normalizedUTF16UpperBound: upper,
                        sourceUTF16LowerBound: mappedSource.lowerBound,
                        sourceUTF16UpperBound: mappedSource.upperBound
                    ))
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

    func uniqueRange(of value: String, within preferred: Range<Int>?) -> Range<Int>? {
        guard !value.isEmpty else { return nil }
        let searchRange = preferred.map {
            NSRange(location: $0.lowerBound, length: $0.count)
        } ?? NSRange(location: 0, length: nsSource.length)
        let first = nsSource.range(of: value, options: [], range: searchRange)
        guard first.location != NSNotFound else { return nil }
        let tailStart = NSMaxRange(first)
        let tail = NSRange(
            location: tailStart,
            length: max(0, NSMaxRange(searchRange) - tailStart)
        )
        guard nsSource.range(of: value, options: [], range: tail).location == NSNotFound else {
            return nil
        }
        return first.location..<NSMaxRange(first)
    }

    func utf16Range(forUTF8Range range: Range<Int>) -> Range<Int>? {
        guard let lowerUTF8 = source.utf8.index(
            source.utf8.startIndex,
            offsetBy: range.lowerBound,
            limitedBy: source.utf8.endIndex
        ), let upperUTF8 = source.utf8.index(
            source.utf8.startIndex,
            offsetBy: range.upperBound,
            limitedBy: source.utf8.endIndex
        ), let lower = lowerUTF8.samePosition(in: source),
           let upper = upperUTF8.samePosition(in: source) else { return nil }
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

private struct SearchVisibleTextCollector: MarkupWalker {
    private let source: String
    private let mapper: SearchMarkdownSourceMapper
    private let fullSourceUTF16Offset: Int
    private let excludedFullSourceRanges: [Range<Int>]
    private(set) var text = ""
    private(set) var fragments: [SearchVisibleFragment] = []
    private var textUTF16Count = 0

    init(
        source: String,
        fullSourceUTF16Offset: Int,
        excludedFullSourceRanges: [Range<Int>]
    ) {
        self.source = source
        mapper = SearchMarkdownSourceMapper(source)
        self.fullSourceUTF16Offset = fullSourceUTF16Offset
        self.excludedFullSourceRanges = excludedFullSourceRanges
    }

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
    mutating func visitCodeBlock(_ node: CodeBlock) { append(node.code, range: node.range); appendSeparator("\n") }
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
        let relative = range.flatMap(mapper.utf16Range)
        let fullRange = relative.map {
            ($0.lowerBound + fullSourceUTF16Offset)..<($0.upperBound + fullSourceUTF16Offset)
        }
        if let fullRange, excludedFullSourceRanges.contains(where: { overlaps($0, fullRange) }) {
            return
        }
        let start = textUTF16Count
        text += value
        textUTF16Count += value.utf16.count
        let end = textUTF16Count
        let exact = relative.map { range in
            (source as NSString).substring(with: NSRange(
                location: range.lowerBound,
                length: range.count
            )) == value
        } ?? false
        fragments.append(SearchVisibleFragment(
            textRange: start..<end,
            sourceRange: fullRange,
            exact: exact
        ))
    }

    private mutating func appendSeparator(_ value: String) {
        guard !text.isEmpty, !text.hasSuffix(value) else { return }
        let start = textUTF16Count
        text += value
        textUTF16Count += value.utf16.count
        fragments.append(SearchVisibleFragment(
            textRange: start..<textUTF16Count,
            sourceRange: nil,
            exact: false
        ))
    }

    private func overlaps(_ lhs: Range<Int>, _ rhs: Range<Int>) -> Bool {
        lhs.lowerBound < rhs.upperBound && lhs.upperBound > rhs.lowerBound
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
              upper >= lower else { return nil }
        return lower..<upper
    }

    private func utf16Offset(line: Int, utf8Column: Int) -> Int? {
        guard line > 0, line <= lineStarts.count, utf8Column > 0 else { return nil }
        let lineStart = lineStarts[line - 1]
        let lineEnd = line < lineStarts.count ? lineStarts[line] : nsSource.length
        let lineString = nsSource.substring(with: NSRange(
            location: lineStart,
            length: lineEnd - lineStart
        ))
        let byteOffset = utf8Column - 1
        guard let utf8 = lineString.utf8.index(
            lineString.utf8.startIndex,
            offsetBy: byteOffset,
            limitedBy: lineString.utf8.endIndex
        ), let stringIndex = utf8.samePosition(in: lineString) else { return nil }
        return lineStart + stringIndex.utf16Offset(in: lineString)
    }
}
