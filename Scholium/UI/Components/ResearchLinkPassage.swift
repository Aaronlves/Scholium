import Foundation
import ScholiumContracts

/// A read-only projection that keeps an authored occurrence's focus separate from label highlighting.
struct ResearchLinkPassage {
    let text: String
    let authoredFocus: [Range<Int>]
    let focus: [Range<Int>]
    let highlights: [Range<Int>]

    init(occurrence: LinkOccurrence, query: String = "") {
        text = ResearchExcerptPresentation.readableText(
            occurrence.localContext.isEmpty ? occurrence.target : occurrence.localContext)
        let anchor = Self.anchor(for: occurrence, readableText: text)
        authoredFocus = anchor.map { [$0.range] } ?? []
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryMatches = Self.queryMatches(in: text, query: needle)
        focus = queryMatches.isEmpty ? authoredFocus : queryMatches
        if !needle.isEmpty {
            // A title, path, hidden target or annotation can admit this row
            // without matching its readable body. Never invent a body witness.
            highlights = queryMatches
            return
        }
        // Even with an exact source anchor, repeated visible labels stay unhighlighted.
        if let anchor, let first = text.range(of: anchor.label),
            text.range(
                of: anchor.label,
                range: text.index(after: first.lowerBound)..<text.endIndex) == nil
        {
            highlights = [anchor.range]
        } else {
            highlights = []
        }
    }

    /// The existing Links filter is one localized substring, not a Search query.
    /// Foundation supplies the same matching semantics and original-text ranges.
    static func queryMatches(in text: String, query: String) -> [Range<Int>] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var lower = text.startIndex
        var ranges: [Range<Int>] = []
        while lower < text.endIndex,
            let match = text[lower...].localizedStandardRange(of: needle), !match.isEmpty
        {
            // Localized matching may end before a decomposed combining mark.
            // Keep its complete source grapheme for display and subsequent search.
            let range = (text as NSString).rangeOfComposedCharacterSequences(for: NSRange(match, in: text))
            guard let complete = Range(range, in: text) else { break }
            ranges.append(range.location..<NSMaxRange(range))
            lower = complete.upperBound
        }
        return ranges
    }

    private static func anchor(
        for occurrence: LinkOccurrence, readableText: String
    ) -> (range: Range<Int>, label: String)? {
        let source = occurrence.localContext
        guard !source.isEmpty, occurrence.linkSpan.start.utf16Column > 0,
            occurrence.linkSpan.utf16LowerBound >= 0,
            occurrence.linkSpan.utf16UpperBound >= occurrence.linkSpan.utf16LowerBound,
            occurrence.span.utf16LowerBound >= 0,
            occurrence.span.utf16UpperBound >= occurrence.span.utf16LowerBound
        else { return nil }
        // localContext starts at the beginning of the occurrence's first source line.
        let offset = occurrence.linkSpan.start.utf16Column - 1
        let document = MarkdownSemanticDocument(parsing: NoteDocument(relativePath: "snippet.md", rawContent: source))
        guard
            let link = document.links.first(where: {
                $0.linkSpan.utf16LowerBound == offset && $0.syntax == occurrence.syntax
                    && $0.target == occurrence.target && $0.alias == occurrence.alias
                    && $0.fragment == occurrence.fragment && $0.isExternal == occurrence.isExternal
                    && $0.linkSpan.utf16Range.count == occurrence.linkSpan.utf16Range.count
                    && $0.span.utf16Range.count == occurrence.span.utf16Range.count
                    && $0.annotation?.markdown == occurrence.annotation?.markdown
            }), let sourceRange = Range(link.span.nsRange, in: source)
        else { return nil }

        let label = ResearchExcerptPresentation.readableText(String(source[sourceRange]))
        guard !label.isEmpty else { return nil }
        var marker = "ScholiumLinkPassageAnchor"
        while source.contains(marker) || readableText.contains(marker) { marker += "Q" }
        var markedSource = source
        // Replacing the whole parsed span also removes the separately presented annotation.
        markedSource.replaceSubrange(sourceRange, with: marker)
        var markedText = ResearchExcerptPresentation.readableText(markedSource)
        guard let markerRange = markedText.range(of: marker),
            markedText.range(of: marker, range: markerRange.upperBound..<markedText.endIndex) == nil
        else { return nil }
        let lower = NSRange(markerRange, in: markedText).location
        markedText.replaceSubrange(markerRange, with: label)
        // The marker is merely a presentation probe. Accept its offset only when replacing
        // it reconstructs exactly the ordinary readable projection, including Unicode bytes.
        guard markedText.utf8.elementsEqual(readableText.utf8) else { return nil }
        return (lower..<(lower + label.utf16.count), label)
    }
}
