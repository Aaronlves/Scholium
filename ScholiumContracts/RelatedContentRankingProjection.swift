import Foundation

/// Retrieval-only field attribution. Search grammar and source offsets remain
/// owned by SearchTextSegment; these strings never become writable source.
public enum RelatedContentRankingField: String, Codable, CaseIterable, Sendable {
    case annotation, link, keyword, title, summary, heading, body
}

extension SearchTextSegment {
    func attributingRelatedContent(in semantic: MarkdownSemanticDocument) -> SearchTextSegment {
        let base: RelatedContentRankingField
        switch field {
        case .linkAnnotation: base = .annotation
        case .title, .alias: base = .title
        case .tag: base = .keyword
        case .summary: base = .summary
        case .heading: base = .heading
        case .body, .footnote, .callout: base = .body
        default: return self
        }
        let links = semantic.links.filter { $0.syntax == .wikilink }
        let annotations = semantic.links.compactMap(\.annotation)
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
            if let mapping, mapping.normalizedUTF16LowerBound < end {
                let source = mapping.sourceUTF16LowerBound..<mapping.sourceUTF16UpperBound
                // Annotation already has its own segment. Never count the same
                // occurrence again through a containing callout or footnote.
                if base != .annotation && annotations.contains(where: { $0.span.utf16Range.overlaps(source) }) {
                    attributed = nil
                } else if base == .body && links.contains(where: { $0.linkSpan.utf16Range.overlaps(source) }) {
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
