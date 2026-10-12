import Foundation
import Markdown
import NaturalLanguage

/// Source-faithful comparison shared by the local corpus and editor boundary.
public enum WritingCompletionPrefix {
    public static func suffixes(in query: String) -> [String] {
        guard query.count >= 2 else { return [] }
        return (2...min(48, query.count)).reversed().compactMap { count in
            let suffix = String(query.suffix(count))
            let previous = query.dropLast(count).last
            guard previous == nil || previous?.isWhitespace == true || SearchTokenization.containsCJK(suffix)
            else { return nil }
            return suffix
        }
    }

    public static func canAppend(_ word: String, after prefix: String) -> Bool {
        let count = prefix.utf16.count
        guard count < word.utf16.count else { return false }
        let units = Array(word.utf16.prefix(count))
        let value = String(decoding: units, as: UTF16.self)
        return value.utf16.elementsEqual(units)
            && value.lowercased().utf16.elementsEqual(prefix.lowercased().utf16)
    }

    public static func matchingCount(_ word: String, query: String) -> Int {
        suffixes(in: query).first { canAppend(word, after: $0) }?.utf16.count ?? 0
    }
}

/// Query-independent readable prose and word boundaries. This derived value
/// retains neither authoritative Markdown nor provider state; callers validate
/// the current source fingerprint before reuse.
public struct WritingCompletionVocabulary: Sendable {
    private struct Fragment: Sendable {
        let text: String
        let words: [Range<String.Index>]
    }
    private let fragments: [Fragment]

    /// Bounded-cache accounting, not an allocator or process-memory claim.
    public var estimatedByteCount: Int {
        128 + fragments.reduce(0) { $0 + 64 + $1.text.utf8.count + $1.words.count * MemoryLayout<Range<String.Index>>.stride }
    }

    public init(document: NoteDocument) throws {
        guard document.hasProvableBodyBoundary else {
            fragments = []
            return
        }
        try Task.checkCancellation()
        let semantic = MarkdownSemanticDocument(parsing: document)
        let bodyStart = document.rawContent.utf16.count - document.body.utf16.count
        let body = NSMutableString(string: document.body)
        var exclusions = semantic.mathExpressions.map { (range: $0.span.nsRange, replacement: "\n\n") }
        for callout in semantic.callouts {
            try Task.checkCancellation()
            guard let range = Range(callout.headerSpan.nsRange, in: document.rawContent) else { continue }
            let header = String(document.rawContent[range])
            if let marker = header.range(of: #"\[![^\]]+\][+-]?"#, options: .regularExpression) {
                let local = NSRange(marker, in: header)
                exclusions.append((NSRange(location: callout.headerSpan.utf16LowerBound + local.location, length: local.length), ""))
            }
        }
        // Embed destinations are resources, not authored vocabulary. Retain an
        // explicit visible label, separated from neighbouring prose.
        for embed in semantic.links where embed.syntax == .embed {
            try Task.checkCancellation()
            let label = embed.alias ?? ""
            let labelDocument = NoteDocument(relativePath: "embed-label.md", rawContent: label)
            let labelText = NSMutableString(string: labelDocument.body)
            let labelStart = labelDocument.rawContent.utf16.count - labelDocument.body.utf16.count
            for math in MarkdownSemanticDocument(parsing: labelDocument).mathExpressions.reversed() {
                let range = NSRange(location: math.span.utf16LowerBound - labelStart, length: math.span.nsRange.length)
                if range.location >= 0, NSMaxRange(range) <= labelText.length {
                    labelText.replaceCharacters(in: range, with: "\n\n")
                }
            }
            exclusions.append((embed.span.nsRange, "\n\n" + (labelText as String) + "\n\n"))
        }
        // Apply original-source coordinates once. An outer exclusion consumes
        // nested spans; partially overlapping exclusions fail closed as a gap.
        var disjoint: [(range: NSRange, replacement: String)] = []
        for exclusion in exclusions.sorted(by: {
            if $0.range.location != $1.range.location { return $0.range.location < $1.range.location }
            return $0.range.length > $1.range.length
        }) {
            if let previous = disjoint.last, NSMaxRange(previous.range) > exclusion.range.location {
                if NSMaxRange(previous.range) < NSMaxRange(exclusion.range) {
                    disjoint[disjoint.count - 1] = (NSUnionRange(previous.range, exclusion.range), "\n\n")
                }
            } else {
                disjoint.append(exclusion)
            }
        }
        for exclusion in disjoint.reversed() {
            let range = NSRange(location: exclusion.range.location - bodyStart, length: exclusion.range.length)
            if range.location >= 0, NSMaxRange(range) <= body.length {
                body.replaceCharacters(in: range, with: exclusion.replacement)
            }
        }
        try Task.checkCancellation()
        var collector = WritingProseCollector()
        collector.visit(Document(parsing: body as String, options: [.parseBlockDirectives]))
        collector.finish()
        var prepared: [Fragment] = []
        for fragment in collector.fragments {
            try Task.checkCancellation()
            // The existing dialect formatter exposes ordinary link labels.
            let text = ResearchExcerptPresentation.readableText(fragment, includingAnnotations: true)
            let tokenizer = NLTokenizer(unit: .word)
            tokenizer.string = text
            let words = tokenizer.tokens(for: text.startIndex..<text.endIndex)
            if !words.isEmpty { prepared.append(.init(text: text, words: words)) }
        }
        fragments = prepared
    }

    public func terms(matching query: String) throws -> [String] {
        let prefixes = WritingCompletionPrefix.suffixes(in: query)
        guard !prefixes.isEmpty else { return [] }
        var terms: [String: (text: String, count: Int)] = [:]
        for fragment in fragments {
            try Task.checkCancellation()
            let text = fragment.text
            let words = fragment.words
            for start in words.indices {
                try Task.checkCancellation()
                for end in start..<min(words.count, start + 8) {
                    if end > start {
                        let gap = text[words[end - 1].upperBound..<words[end].lowerBound]
                        guard gap.allSatisfy({ $0 == " " || $0 == "\t" || $0 == "-" }) else { break }
                    }
                    let phrase = String(text[words[start].lowerBound..<words[end].upperBound])
                    guard phrase.utf16.count <= 96 else { break }
                    guard let prefix = prefixes.first(where: { WritingCompletionPrefix.canAppend(phrase, after: $0) })
                    else { continue }
                    let suffix = String(decoding: phrase.utf16.dropFirst(prefix.utf16.count), as: UTF16.self)
                    guard !suffix.contains(where: { "\\`*_{}[]<>!|#+.\n\r".contains($0) }) else { continue }
                    let key = phrase.lowercased()
                    terms[key] = (phrase, prefix.utf16.count)
                }
            }
        }
        return terms.values.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            if $0.text.utf16.count != $1.text.utf16.count { return $0.text.utf16.count < $1.text.utf16.count }
            return $0.text < $1.text
        }.prefix(32).map(\.text)
    }
}

private struct WritingProseCollector: MarkupWalker {
    var fragments: [String] = []
    private var current = ""
    mutating func finish() {
        if !current.isEmpty {
            fragments.append(current)
            current = ""
        }
    }
    mutating func visitText(_ text: Markdown.Text) { current.append(text.string) }
    mutating func visitParagraph(_ paragraph: Paragraph) {
        descendInto(paragraph)
        finish()
    }
    mutating func visitHeading(_ heading: Heading) {
        descendInto(heading)
        finish()
    }
    mutating func visitTableCell(_ cell: Table.Cell) {
        descendInto(cell)
        finish()
    }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) { finish() }
    mutating func visitLineBreak(_ lineBreak: LineBreak) { finish() }
    mutating func visitInlineCode(_ code: InlineCode) { finish() }
    mutating func visitCodeBlock(_ code: CodeBlock) { finish() }
    mutating func visitHTMLBlock(_ html: HTMLBlock) { finish() }
    mutating func visitInlineHTML(_ html: InlineHTML) { finish() }
}
