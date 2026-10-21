import Foundation

/// Retrieval-only field attribution. Search grammar and source offsets remain
/// owned by SearchTextSegment; these strings never become writable source.
public enum RelatedContentRankingField: String, Codable, CaseIterable, Sendable {
    case annotation, link, keyword, title, summary, heading, body

    init?(searchField: SearchMatchedField) {
        switch searchField {
        case .linkAnnotation: self = .annotation
        case .title, .alias: self = .title
        case .tag: self = .keyword
        case .summary: self = .summary
        case .heading: self = .heading
        case .body, .footnote, .callout: self = .body
        default: return nil
        }
    }
}

/// One immutable source-range lookup for a document's segment attribution.
/// Queries do not assume normalized text maps to increasing source positions.
struct RelatedContentSourceAttribution: Sendable {
    private let linkRanges: [Range<Int>]
    private let annotationRanges: [Range<Int>]

    init(in semantic: MarkdownSemanticDocument) {
        linkRanges = Self.merged(semantic.links.compactMap { $0.syntax == .wikilink ? $0.linkSpan.utf16Range : nil })
        annotationRanges = Self.merged(semantic.links.compactMap { $0.annotation?.span.utf16Range })
    }

    var hasLinks: Bool { !linkRanges.isEmpty }
    var hasAnnotations: Bool { !annotationRanges.isEmpty }

    func containsLink(overlapping source: Range<Int>) -> Bool {
        Self.overlaps(source, ranges: linkRanges)
    }

    func containsAnnotation(overlapping source: Range<Int>) -> Bool {
        Self.overlaps(source, ranges: annotationRanges)
    }

    private static func merged(_ ranges: [Range<Int>]) -> [Range<Int>] {
        let sorted = ranges.filter { !$0.isEmpty }.sorted {
            $0.lowerBound == $1.lowerBound ? $0.upperBound < $1.upperBound : $0.lowerBound < $1.lowerBound
        }
        var result: [Range<Int>] = []
        for range in sorted {
            if let previous = result.last, range.lowerBound <= previous.upperBound {
                result[result.count - 1] = previous.lowerBound..<max(previous.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }

    private static func overlaps(_ source: Range<Int>, ranges: [Range<Int>]) -> Bool {
        guard !source.isEmpty else { return false }
        var lower = 0
        var upper = ranges.count
        // Merged, nonempty intervals have strictly increasing upper bounds.
        // Find the first one that ends after this half-open source range starts.
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if ranges[middle].upperBound <= source.lowerBound {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower < ranges.count && ranges[lower].lowerBound < source.upperBound
    }
}

extension SearchTextSegment {
    func attributingRelatedContent(using sourceAttribution: RelatedContentSourceAttribution) -> SearchTextSegment {
        guard let base = RelatedContentRankingField(searchField: field) else { return self }
        let usesLinks = base == .body
        let excludesAnnotations = base != .annotation
        if normalizedText.isEmpty || offsetMap.isEmpty
            || ((!usesLinks || !sourceAttribution.hasLinks) && (!excludesAnnotations || !sourceAttribution.hasAnnotations))
        {
            return .init(
                field: field, ordinal: ordinal, text: text, normalizedText: normalizedText,
                sourceRange: sourceRange, offsetMap: offsetMap,
                relatedRankingText: normalizedText.isEmpty ? [:] : [base.rawValue: " " + normalizedText])
        }
        var fields: [String: String] = [:]
        var previous: RelatedContentRankingField?
        var offset = 0
        var mapIndex = 0
        for character in normalizedText {
            let end = offset + String(character).utf16.count
            while mapIndex < offsetMap.count && offsetMap[mapIndex].normalizedUTF16UpperBound <= offset {
                mapIndex += 1
            }
            let mapping = mapIndex < offsetMap.count ? offsetMap[mapIndex] : nil
            var attributed: RelatedContentRankingField? = base
            if let mapping,
                let source = mapping.sourceUTF16Range(forNormalizedUTF16Range: offset..<end)
            {
                // Annotation already has its own segment. Never count the same
                // occurrence again through a containing callout or footnote.
                if excludesAnnotations && sourceAttribution.containsAnnotation(overlapping: source) {
                    attributed = nil
                } else if usesLinks && sourceAttribution.containsLink(overlapping: source) {
                    attributed = .link
                }
            }
            if let attributed {
                if previous != attributed { fields[attributed.rawValue, default: ""] += " " }
                fields[attributed.rawValue, default: ""].append(character)
            }
            previous = attributed
            offset = end
        }
        return .init(
            field: field, ordinal: ordinal, text: text, normalizedText: normalizedText,
            sourceRange: sourceRange, offsetMap: offsetMap, relatedRankingText: fields)
    }
}
