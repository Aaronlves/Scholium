import Foundation

/// An authored, portable identity. Its locator is always derived from the current source.
public struct ParagraphAnchor: Hashable, Sendable {
    public let id: String
    public let markerSpan: SourceSpan
    public let paragraphSpan: SourceSpan
}

public struct ParagraphAnchorPlan: Sendable {
    public let anchorID: String
    public let paragraphSpan: SourceSpan
    public let edits: [AgentSourceEdit]
    public let candidateSource: String
}

public enum ParagraphAnchorError: Error, Equatable, LocalizedError {
    case unsupportedParagraph
    case invalidIdentifier
    case duplicateIdentifier(String)
    case partialAnchor

    public var errorDescription: String? {
        switch self {
        case .unsupportedParagraph: "Choose a complete ordinary paragraph outside lists, quotations, definitions, and protected source."
        case .invalidIdentifier: "A paragraph identifier must contain only ASCII letters, numbers, and hyphens."
        case .duplicateIdentifier(let id): "The paragraph identifier ^\(id) occurs more than once. Resolve the ambiguity first."
        case .partialAnchor: "The selection cuts through a paragraph identity. Select the complete paragraph."
        }
    }
}

/// Plans exact-source changes only. Persistence, revision checks, and multi-file recovery
/// belong to the caller. Moving source retains its IDs; copying explicitly remints them.
public enum ParagraphAnchorPlanner {
    public static func anchors(
        in document: NoteDocument,
        semantic supplied: MarkdownSemanticDocument? = nil
    ) -> [ParagraphAnchor] {
        let source = document.rawContent as NSString
        let mapper = SemanticSourceMapper(document.rawContent)
        let semantic =
            supplied.flatMap {
                $0.fingerprint == document.fingerprint && validSourceSpans(in: $0, source: source, mapper: mapper) ? $0 : nil
            } ?? MarkdownSemanticDocument(parsing: document)
        let comments = MarkdownSemanticParser.commentRanges(in: document)
        let pattern = #"(?:^|[ \t\r\n])\^([A-Za-z0-9-]+)[ \t]*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var anchors: [ParagraphAnchor] = []
        for block in semantic.blocks where block.kind == .paragraph {
            let text = source.substring(with: block.span.nsRange)
            guard !comments.contains(where: { $0.overlaps(block.span.utf16Range) }),
                !isProtected(block.span, semantic: semantic, text: text),
                let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
            else { continue }
            let identifierRange = match.range(at: 1)
            let markerRange = NSRange(
                location: block.span.utf16LowerBound + identifierRange.location - 1,
                length: identifierRange.length + 1
            )
            guard !semantic.inlines.contains(where: { $0.span.nsRange.intersection(markerRange) != nil }),
                let marker = mapper.span(for: markerRange)
            else { continue }
            // An ID on its own attaches to the immediately preceding ordinary paragraph.
            // Lists, code, tables and container blocks require a separate future contract.
            let preceding = semantic.blocks.last { candidate in
                candidate.span.utf16UpperBound < block.span.utf16LowerBound
            }
            let target: SourceSpan
            if text.trimmingCharacters(in: .whitespacesAndNewlines) == source.substring(with: markerRange) {
                guard let preceding, preceding.kind == .paragraph,
                    !isProtected(preceding.span, semantic: semantic, text: source.substring(with: preceding.span.nsRange)),
                    source.substring(
                        with: NSRange(
                            location: preceding.span.utf16UpperBound,
                            length: block.span.utf16LowerBound - preceding.span.utf16UpperBound
                        )
                    ).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    let combined = mapper.span(
                        for: NSRange(
                            location: preceding.span.utf16LowerBound,
                            length: block.span.utf16UpperBound - preceding.span.utf16LowerBound
                        ))
                else { continue }
                target = combined
            } else {
                target = block.span
            }
            anchors.append(
                ParagraphAnchor(
                    id: (text as NSString).substring(with: identifierRange),
                    markerSpan: marker,
                    paragraphSpan: target
                ))
        }
        return anchors
    }

    public static func paragraph(in document: NoteDocument, atUTF16 offset: Int) throws -> SourceSpan {
        let semantic = MarkdownSemanticDocument(parsing: document)
        let source = document.rawContent as NSString
        guard
            let block = semantic.blocks.first(where: {
                $0.kind == .paragraph && $0.span.utf16LowerBound <= offset && offset <= $0.span.utf16UpperBound
            }), !MarkdownSemanticParser.commentRanges(in: document).contains(where: { $0.overlaps(block.span.utf16Range) }),
            !isProtected(block.span, semantic: semantic, text: source.substring(with: block.span.nsRange))
        else { throw ParagraphAnchorError.unsupportedParagraph }
        let matching = anchors(in: document, semantic: semantic).filter {
            $0.paragraphSpan.utf16LowerBound <= offset && offset <= $0.paragraphSpan.utf16UpperBound
        }
        guard matching.count <= 1 else { throw ParagraphAnchorError.unsupportedParagraph }
        return matching.first?.paragraphSpan ?? block.span
    }

    public static func ensureAnchor(
        in document: NoteDocument,
        atUTF16 offset: Int,
        id: String = UUID().uuidString.lowercased()
    ) throws -> ParagraphAnchorPlan {
        let span = try paragraph(in: document, atUTF16: offset)
        let existing = anchors(in: document)
        if let anchor = existing.first(where: { $0.paragraphSpan == span }) {
            guard existing.filter({ $0.id == anchor.id }).count == 1 else {
                throw ParagraphAnchorError.duplicateIdentifier(anchor.id)
            }
            return ParagraphAnchorPlan(anchorID: anchor.id, paragraphSpan: span, edits: [], candidateSource: document.rawContent)
        }
        guard validIdentifier(id) else { throw ParagraphAnchorError.invalidIdentifier }
        guard !existing.contains(where: { $0.id == id }) else { throw ParagraphAnchorError.duplicateIdentifier(id) }
        let edit = AgentSourceEdit(startUTF8: span.utf8UpperBound, endUTF8: span.utf8UpperBound, expectedText: "", replacement: " ^\(id)")
        let candidate = try AgentSourceEdit.applying([edit], to: document.sourceBytes)
        let changed = NoteDocument(relativePath: document.relativePath, rawContent: candidate)
        guard let anchor = anchors(in: changed).first(where: { $0.id == id }) else {
            throw ParagraphAnchorError.unsupportedParagraph
        }
        return ParagraphAnchorPlan(anchorID: id, paragraphSpan: anchor.paragraphSpan, edits: [edit], candidateSource: candidate)
    }

    /// All edits use original-document UTF-8 coordinates, including fragment-only
    /// references inside the copied selection. References outside it keep their target.
    public static func remintAnchors(
        in document: NoteDocument,
        within range: Range<Int>,
        excludingIDs: Set<String> = [],
        idProvider: (String) -> String = { _ in UUID().uuidString.lowercased() }
    ) throws -> [AgentSourceEdit] {
        let semantic = MarkdownSemanticDocument(parsing: document)
        let all = anchors(in: document, semantic: semantic)
        var reserved = excludingIDs.union(all.map(\.id))
        var replacements: [String: String] = [:]
        var edits: [AgentSourceEdit] = []
        for anchor in all where anchor.paragraphSpan.utf8Range.overlaps(range) {
            guard range.lowerBound <= anchor.paragraphSpan.utf8LowerBound,
                range.upperBound >= anchor.paragraphSpan.utf8UpperBound
            else { throw ParagraphAnchorError.partialAnchor }
            guard all.filter({ $0.id == anchor.id }).count == 1 else {
                throw ParagraphAnchorError.duplicateIdentifier(anchor.id)
            }
            let id = idProvider(anchor.id)
            guard validIdentifier(id) else { throw ParagraphAnchorError.invalidIdentifier }
            guard !reserved.contains(id) else { throw ParagraphAnchorError.duplicateIdentifier(id) }
            reserved.insert(id)
            replacements[anchor.id] = id
            edits.append(
                AgentSourceEdit(
                    startUTF8: anchor.markerSpan.utf8LowerBound,
                    endUTF8: anchor.markerSpan.utf8UpperBound,
                    expectedText: "^\(anchor.id)", replacement: "^\(id)"
                ))
        }
        for link in semantic.links
        where link.target.isEmpty && range.lowerBound <= link.linkSpan.utf8LowerBound
            && range.upperBound >= link.linkSpan.utf8UpperBound
        {
            guard let fragment = link.fragment, fragment.hasPrefix("^"),
                let replacement = replacements[String(fragment.dropFirst())]
            else { continue }
            let original = String(decoding: document.sourceBytes[link.linkSpan.utf8Range], as: UTF8.self)
            // The semantic parser establishes the fragment role; replace only that
            // target occurrence before any alias, never matching prose elsewhere.
            guard let marker = original.range(of: "#\(fragment)") else { continue }
            let prefixCount = original[..<marker.lowerBound].utf8.count
            edits.append(
                AgentSourceEdit(
                    startUTF8: link.linkSpan.utf8LowerBound + prefixCount,
                    endUTF8: link.linkSpan.utf8LowerBound + prefixCount + original[marker].utf8.count,
                    expectedText: String(original[marker]), replacement: "#^\(replacement)"
                ))
        }
        return edits.sorted { $0.startUTF8 < $1.startUTF8 }
    }

    /// A fingerprint label alone cannot make an externally supplied projection's
    /// coordinates safe. Validate before constructing ranges or extracting text.
    private static func validSourceSpans(
        in semantic: MarkdownSemanticDocument,
        source: NSString,
        mapper: SemanticSourceMapper
    ) -> Bool {
        let spans =
            semantic.blocks.map(\.span) + semantic.inlines.map(\.span)
            + semantic.footnoteDefinitions.map(\.span) + semantic.mathExpressions.map(\.span)
        func boundary(_ offset: Int) -> Bool {
            guard offset > 0 && offset < source.length else { return true }
            let before = source.character(at: offset - 1)
            let after = source.character(at: offset)
            return !(before == 13 && after == 10)
                && !((0xD800...0xDBFF).contains(before) && (0xDC00...0xDFFF).contains(after))
        }
        return spans.allSatisfy { span in
            guard span.utf16LowerBound >= 0,
                span.utf16UpperBound >= span.utf16LowerBound,
                span.utf16UpperBound <= source.length,
                boundary(span.utf16LowerBound), boundary(span.utf16UpperBound)
            else { return false }
            return mapper.span(
                for: NSRange(
                    location: span.utf16LowerBound,
                    length: span.utf16UpperBound - span.utf16LowerBound
                )) == span
        }
    }

    private static func validIdentifier(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }
    }

    private static func isProtected(_ span: SourceSpan, semantic: MarkdownSemanticDocument, text: String) -> Bool {
        text.contains("%%") || text.contains("<!--")
            || semantic.blocks.contains {
                [.blockQuote, .listItem, .orderedList, .unorderedList, .table].contains($0.kind)
                    && $0.span.utf16LowerBound <= span.utf16LowerBound
                    && $0.span.utf16UpperBound >= span.utf16UpperBound
            }
            || (semantic.footnoteDefinitions.map(\.span) + semantic.mathExpressions.map(\.span)).contains {
                $0.utf16Range.overlaps(span.utf16Range)
            }
    }
}
