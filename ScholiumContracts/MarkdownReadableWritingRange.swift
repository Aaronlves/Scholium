import Foundation
import Markdown

/// A caret-owned, exact source slice of readable Markdown body text. The caller
/// supplies a bounded body capture, never a complete remote-writing document.
public struct MarkdownReadableWritingRange: Equatable, Sendable {
    public static let maximumFragmentUTF16Count = 32_000

    public let sourceUTF16Range: Range<Int>
    public let isProse: Bool

    public init?(bodyFragment: String, caretUTF16: Int) {
        guard !bodyFragment.isEmpty,
            bodyFragment.utf16.count <= Self.maximumFragmentUTF16Count,
            caretUTF16 >= 0, caretUTF16 <= bodyFragment.utf16.count,
            let caretRange = Range(NSRange(location: caretUTF16, length: 0), in: bodyFragment),
            caretRange.lowerBound == bodyFragment.endIndex || bodyFragment.indices.contains(caretRange.lowerBound)
        else { return nil }

        // A body-local thematic break must not become a YAML envelope. Every
        // range below is mapped back by removing this one synthetic LF.
        let source = "\n" + bodyFragment
        let native = source as NSString
        let caret = caretUTF16 + 1
        let document = NoteDocument(relativePath: "WritingContext.md", rawContent: source)
        let semantic = MarkdownSemanticDocument(parsing: document)
        let sourceMapper = SemanticSourceMapper(source)
        var protected = semantic.mathExpressions.map(\.span.utf16Range)
        protected += MarkdownSemanticParser.commentRanges(in: document)
        var anchorMarkers = ParagraphAnchorPlanner.anchors(in: document, semantic: semantic).map(\.markerSpan.utf16Range)
        if anchorMarkers.isEmpty, bodyFragment.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("^") {
            // A capture containing only a standalone marker omits its preceding
            // paragraph. Use the existing planner with a local probe paragraph
            // solely to exclude that identifier, never to authorize a target.
            let prefix = "Writing context.\n\n"
            let probe = NoteDocument(relativePath: "WritingContext.md", rawContent: prefix + source)
            anchorMarkers = ParagraphAnchorPlanner.anchors(in: probe).compactMap {
                let lower = $0.markerSpan.utf16LowerBound - prefix.utf16.count
                let upper = $0.markerSpan.utf16UpperBound - prefix.utf16.count
                return lower >= 1 && upper <= native.length ? lower..<upper : nil
            }
        }
        protected += anchorMarkers
        for diagnostic in semantic.diagnostics where diagnostic.code == .malformedMath {
            if let span = diagnostic.span { protected.append(span.utf16LowerBound..<native.length) }
        }
        var omitted: [Range<Int>] = []
        var partialMathRanges: [Range<Int>] = []
        var readableOverrides: [Range<Int>] = []
        var completeReferenceRanges: [Range<Int>] = []
        var candidates: [Candidate] = []
        var owner = 0
        for inline in semantic.inlines where inline.kind == .highlight {
            let span = inline.span.utf16Range
            guard span.count > 4 else { continue }
            let content = (span.lowerBound + 2)..<(span.upperBound - 2)
            omitted += [span.lowerBound..<content.lowerBound, content.upperBound..<span.upperBound]
            readableOverrides.append(content)
        }
        for link in semantic.links {
            guard let annotation = link.annotation else { continue }
            let content = annotation.contentSpan.utf16Range
            omitted += Self.subtract(annotation.span.utf16Range, excluding: [content])
            readableOverrides.append(content)
        }
        // A paragraph capture can omit a reference definition elsewhere in the
        // Note. Its complete authored label remains readable, but neither the
        // brackets nor the reference identifier become provider context. Parse
        // only the exact label with the existing Markdown parser below.
        if let references = try? NSRegularExpression(
            pattern: #"(?<![\\\[\^])!?\[((?:\\[^\r\n]|[^\[\]\\\r\n])+)\]\[([^\[\]\\\r\n]+)\]"#)
        {
            for match in references.matches(in: source, range: NSRange(location: 0, length: native.length)) {
                let label = match.range(at: 1).location..<NSMaxRange(match.range(at: 1))
                let whole = match.range.location..<NSMaxRange(match.range)
                omitted += Self.subtract(whole, excluding: [label])
                readableOverrides.append(label)
                completeReferenceRanges.append(whole)
            }
        }

        func walk(_ markup: Markup, mapper: SemanticSourceMapper, offset: Int, prose: Bool, ownerID: Int) {
            guard let parsedRange = markup.range, let range = mapper.nsRange(for: parsedRange) else {
                for child in markup.children { walk(child, mapper: mapper, offset: offset, prose: prose, ownerID: ownerID) }
                return
            }
            let bounds = (range.location + offset)..<(NSMaxRange(range) + offset)
            if markup is CodeBlock || markup is InlineCode || markup is HTMLBlock || markup is InlineHTML {
                protected.append(bounds)
                return
            }
            if markup is Link || markup is Image {
                let marker = markup is Image ? bounds.lowerBound + 1 : bounds.lowerBound
                guard bounds.lowerBound >= 0, bounds.upperBound <= native.length,
                    marker < bounds.upperBound, native.character(at: marker) == 0x5B
                else {
                    protected.append(bounds)
                    return
                }
                owner += 1
                let linkOwner = owner
                completeReferenceRanges.append(bounds)
                for child in markup.children { walk(child, mapper: mapper, offset: offset, prose: false, ownerID: linkOwner) }
                return
            }
            if markup is Table.Cell, bounds.lowerBound >= 0, bounds.upperBound <= native.length {
                var lower = bounds.lowerBound
                var upper = bounds.upperBound
                while lower < upper, native.character(at: lower) == 0x20 || native.character(at: lower) == 0x09 { lower += 1 }
                while upper > lower, native.character(at: upper - 1) == 0x20 || native.character(at: upper - 1) == 0x09 { upper -= 1 }
                let cell = native.substring(with: NSRange(location: lower, length: upper - lower))
                if cell.contains("\\|") {
                    // GFM removes escaped-pipe backslashes before parsing cell
                    // inlines, shortening their child ranges. The Cell range
                    // still owns exact source. Reparse that slice with the same
                    // parser in a forced paragraph, then clip away the local
                    // prefix; neither displayed text nor shortened coordinates
                    // authorize provider context.
                    let prefix = "\nWriting context. "
                    let local = prefix + cell
                    let parsed = Document(parsing: local, options: [.parseBlockDirectives])
                    let start = candidates.count
                    owner += 1
                    walk(parsed, mapper: SemanticSourceMapper(local), offset: lower - prefix.utf16.count, prose: false, ownerID: owner)
                    for index in start..<candidates.count {
                        let candidate = candidates[index].range
                        candidates[index].range = min(upper, max(lower, candidate.lowerBound))..<max(lower, min(upper, candidate.upperBound))
                    }
                    return
                }
            }
            if markup is Paragraph || markup is Heading || markup is Table.Cell {
                owner += 1
                let blockOwner = owner
                let ordinary = markup is Paragraph && prose
                for child in markup.children { walk(child, mapper: mapper, offset: offset, prose: ordinary, ownerID: blockOwner) }
                return
            }
            if markup is BlockQuote,
                let paragraph = markup.children.first(where: { $0 is Paragraph }),
                let paragraphRange = paragraph.range,
                let header = mapper.nsRange(for: paragraphRange),
                header.location + offset >= 0, NSMaxRange(header) + offset <= native.length,
                let marker = try? NSRegularExpression(pattern: #"^\[![^\]\r\n]+\][+-]?[ \t]*"#),
                let match = marker.firstMatch(
                    in: native.substring(
                        with: NSRange(
                            location: header.location + offset, length: header.length)), range: NSRange(location: 0, length: header.length))
            {
                // The AST owns this quote's content start even inside a list;
                // a line-prefix regex cannot establish that nested boundary.
                let lower = header.location + offset + match.range.location
                omitted.append(lower..<(lower + match.range.length))
            }
            if markup is Text {
                candidates.append(Candidate(range: bounds, isProse: prose, owner: ownerID))
                return
            }
            let ordinary = prose && !(markup is BlockQuote || markup is ListItem || markup is Table)
            for child in markup.children { walk(child, mapper: mapper, offset: offset, prose: ordinary, ownerID: ownerID) }
        }

        let parsed = Document(parsing: source, options: [.parseBlockDirectives])
        walk(parsed, mapper: SemanticSourceMapper(source), offset: 0, prose: true, ownerID: 0)

        // A complex label that neither the bounded reference projection nor
        // the existing AST proved cannot fall back to a Text node containing
        // its identifier. Keep that source line unavailable instead.
        if let suffixes = try? NSRegularExpression(pattern: #"(?<!\\)\]\[[^\]\r\n]+\]"#) {
            for match in suffixes.matches(in: source, range: NSRange(location: 0, length: native.length)) {
                guard
                    !completeReferenceRanges.contains(where: {
                        $0.lowerBound <= match.range.location && NSMaxRange(match.range) <= $0.upperBound
                    })
                else { continue }
                let line = native.lineRange(for: match.range)
                omitted.append(line.location..<NSMaxRange(line))
            }
        }

        for link in semantic.links where link.syntax == .wikilink || link.syntax == .embed {
            let span = link.linkSpan.utf16Range
            guard span.upperBound <= native.length else { continue }
            let openingCount = link.syntax == .embed ? 3 : 2
            if link.syntax == .embed,
                !native.substring(with: link.linkSpan.nsRange).hasPrefix("![[")
            {
                continue
            }
            guard link.alias != nil, span.count >= openingCount + 2
            else {
                omitted.append(span)
                continue
            }
            let inner = NSRange(location: span.lowerBound + openingCount, length: span.count - openingCount - 2)
            let separator = native.range(of: "|", range: inner)
            guard separator.location != NSNotFound else {
                omitted.append(span)
                continue
            }
            let label = NSMaxRange(separator)..<(span.upperBound - 2)
            omitted += [span.lowerBound..<label.lowerBound, label.upperBound..<span.upperBound]
            readableOverrides.append(label)
        }
        for reference in semantic.footnoteReferences where !reference.isInline {
            omitted.append(reference.span.utf16Range)
        }
        for definition in semantic.footnoteDefinitions {
            omitted.append(definition.span.utf16Range)
        }
        // An inline literal in a definition/header can suppress its semantic
        // projection, but never makes that source-owned identifier readable.
        for pattern in [
            #"^[ \t]*\[\^[^\]\r\n]+\]:[ \t]*"#,
            #"^[ \t]*(?:>[ \t]*)+\[![^\]\r\n]+\][+-]?[ \t]*"#,
        ] {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
            for match in expression.matches(in: source, range: NSRange(location: 0, length: native.length)) {
                omitted.append(match.range.location..<NSMaxRange(match.range))
            }
        }
        // A bounded capture may end before an inline-math closer on a later
        // line. Complete pairs already have semantic source spans; an otherwise
        // readable, unescaped dollar run leaves the remaining capture unproved.
        if let dollars = try? NSRegularExpression(pattern: #"\$+"#) {
            for match in dollars.matches(in: source, range: NSRange(location: 0, length: native.length)) {
                let start = match.range.location
                guard candidates.contains(where: { $0.range.contains(start) }),
                    !(protected + omitted).contains(where: { $0.contains(start) })
                else { continue }
                var previous = start
                while previous > 0, native.character(at: previous - 1) == 0x5C { previous -= 1 }
                guard (start - previous) % 2 == 0 else { continue }
                let unproved = start..<native.length
                partialMathRanges.append(unproved)
                omitted.append(unproved)
            }
        }
        // Incomplete destination/code syntax has no proven readable projection.
        // Complete AST-owned spans take precedence over these partial openers.
        for pattern in [
            #"(?<!\\)\[\[(?:(?!\]\])[^\r\n])*$"#,
            #"\]\([^\)\r\n]*$"#,
            #"(?<!\\)`+[^`\r\n]*$"#,
            #"(?<!\\)<[A-Za-z!/][^>\r\n]*$"#,
        ] {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
            for match in expression.matches(in: source, range: NSRange(location: 0, length: native.length)) {
                guard !protected.contains(where: { $0.contains(match.range.location) }) else { continue }
                omitted.append(match.range.location..<NSMaxRange(match.range))
            }
        }

        // Wikilink aliases are authored body text even
        // when the standard parser treats their enclosing syntax as a reference.
        let overrideCandidatesStart = candidates.count
        for bounds in readableOverrides where !bounds.isEmpty {
            let text = native.substring(with: NSRange(location: bounds.lowerBound, length: bounds.count))
            let local = "\n" + text
            let parsed = Document(parsing: local, options: [.parseBlockDirectives])
            owner += 1
            walk(parsed, mapper: SemanticSourceMapper(local), offset: bounds.lowerBound - 1, prose: false, ownerID: owner)
        }
        let outerProtection = protected + partialMathRanges
        guard !outerProtection.contains(where: { $0.contains(caret) }) else { return nil }
        // Footnote content is a nested Markdown projection, not an escape from
        // the enclosing source's math/comment/code protection. Only after that
        // proof may its existing de-indented source map admit an exact slice.
        for definition in semantic.footnoteDefinitions {
            guard
                let slice = definition.contentSlices.first(where: {
                    $0.sourceSpan.utf16LowerBound <= caret && caret <= $0.sourceSpan.utf16UpperBound
                })
                    ?? definition.contentSlices.last.flatMap({ last -> FootnoteContentSlice? in
                        // The footnote projection intentionally trims display text.
                        // Prove its final authored horizontal tail independently;
                        // source coordinates and the actual caret stay unchanged.
                        let end = last.sourceSpan.utf16UpperBound
                        guard !definition.isInline, end < caret, caret <= definition.span.utf16UpperBound,
                            (end..<caret).allSatisfy({ native.character(at: $0) == 0x20 || native.character(at: $0) == 0x09 })
                        else { return nil }
                        return last
                    })
            else { continue }
            let contentMapper = SemanticSourceMapper(definition.content)
            let proofCaret = min(caret, slice.sourceSpan.utf16UpperBound)
            guard let caretSpan = sourceMapper.span(for: NSRange(location: proofCaret, length: 0)),
                let contentCaret = contentMapper.utf16Offset(
                    forUTF8Offset: slice.contentUTF8Range.lowerBound + caretSpan.utf8LowerBound - slice.sourceSpan.utf8LowerBound),
                let readable = Self(bodyFragment: definition.content, caretUTF16: contentCaret),
                let contentSpan = contentMapper.span(
                    for: NSRange(
                        location: readable.sourceUTF16Range.lowerBound, length: readable.sourceUTF16Range.count))
            else { return nil }
            let firstByte = max(contentSpan.utf8LowerBound, slice.contentUTF8Range.lowerBound)
            let lastByte = min(contentSpan.utf8UpperBound, slice.contentUTF8Range.upperBound)
            guard firstByte < lastByte,
                let lower = sourceMapper.utf16Offset(
                    forUTF8Offset: slice.sourceSpan.utf8LowerBound + firstByte - slice.contentUTF8Range.lowerBound),
                let mappedUpper = sourceMapper.utf16Offset(
                    forUTF8Offset: slice.sourceSpan.utf8LowerBound + lastByte - slice.contentUTF8Range.lowerBound)
            else { return nil }
            let upper = caret > mappedUpper && mappedUpper == slice.sourceSpan.utf16UpperBound ? caret : mappedUpper
            guard
                let admitted = Self.subtract(lower..<upper, excluding: outerProtection).first(where: {
                    $0.lowerBound <= caret && caret <= $0.upperBound
                })
            else { return nil }
            sourceUTF16Range = (admitted.lowerBound - 1)..<(admitted.upperBound - 1)
            isProse = false
            return
        }
        let exclusions = protected + omitted
        var pieces: [Candidate] = []
        for (index, candidate) in candidates.enumerated() {
            let candidateExclusions = index < overrideCandidatesStart ? exclusions + readableOverrides : exclusions
            for range in Self.subtract(candidate.range, excluding: candidateExclusions) where !range.isEmpty {
                let ordinary = candidate.isProse && !readableOverrides.contains(where: { $0.overlaps(range) })
                pieces.append(Candidate(range: range, isProse: ordinary, owner: candidate.owner))
            }
        }
        pieces.sort {
            $0.owner == $1.owner ? $0.range.lowerBound < $1.range.lowerBound : $0.owner < $1.owner
        }
        var merged: [Candidate] = []
        for piece in pieces {
            if let previous = merged.last, previous.owner == piece.owner,
                previous.isProse == piece.isProse, previous.range.upperBound <= piece.range.lowerBound,
                let gap = Range(NSRange(location: previous.range.upperBound, length: piece.range.lowerBound - previous.range.upperBound), in: source),
                source[gap].allSatisfy(\.isWhitespace),
                !exclusions.contains(where: { $0.overlaps(previous.range.upperBound..<piece.range.lowerBound) })
            {
                merged[merged.count - 1] = Candidate(
                    range: previous.range.lowerBound..<piece.range.upperBound, isProse: piece.isProse, owner: piece.owner)
            } else {
                merged.append(piece)
            }
        }
        var admitted: [Candidate] = []
        for var candidate in merged {
            let originalEnd = candidate.range.upperBound
            var end = originalEnd
            // Markdown trims spaces/Tabs from Text ranges. A paused caret in
            // that authored tail still belongs to the same readable source
            // span; never jump a marker, protected range or physical line.
            if caret > originalEnd {
                while end < native.length,
                    native.character(at: end) == 0x20 || native.character(at: end) == 0x09
                {
                    end += 1
                }
            }
            if candidate.isProse {
                if end < native.length, native.character(at: end) == 13,
                    end + 1 < native.length, native.character(at: end + 1) == 10
                {
                    end += 2
                } else if end < native.length, native.character(at: end) == 10 {
                    end += 1
                }
            }
            if !exclusions.contains(where: { $0.overlaps(originalEnd..<end) }) {
                candidate.range = candidate.range.lowerBound..<end
            }
            if candidate.range.lowerBound <= caret, caret <= candidate.range.upperBound { admitted.append(candidate) }
        }
        guard let result = admitted.min(by: { $0.range.count < $1.range.count }),
            result.range.lowerBound > 0,
            Range(NSRange(location: result.range.lowerBound, length: result.range.count), in: source) != nil
        else { return nil }
        sourceUTF16Range = (result.range.lowerBound - 1)..<(result.range.upperBound - 1)
        isProse = result.isProse
    }

    private struct Candidate {
        var range: Range<Int>
        let isProse: Bool
        let owner: Int
    }

    private static func subtract(_ range: Range<Int>, excluding exclusions: [Range<Int>]) -> [Range<Int>] {
        var pieces = [range]
        for exclusion in exclusions where exclusion.overlaps(range) {
            pieces = pieces.flatMap { piece in
                guard piece.overlaps(exclusion) else { return [piece] }
                var retained: [Range<Int>] = []
                if piece.lowerBound < exclusion.lowerBound { retained.append(piece.lowerBound..<min(piece.upperBound, exclusion.lowerBound)) }
                if piece.upperBound > exclusion.upperBound { retained.append(max(piece.lowerBound, exclusion.upperBound)..<piece.upperBound) }
                return retained
            }
        }
        return pieces
    }
}
