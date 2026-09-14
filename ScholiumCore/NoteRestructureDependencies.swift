import Foundation
import Markdown
import ScholiumContracts

/// Original-source ranges are the only write coordinates. Dependencies are copied as exact slices.
struct NoteRestructureDependencies {
    let ranges: [Range<Int>]
    let edits: [AgentSourceEdit]
    let sourceEdits: [AgentSourceEdit]
    let retainedDefinitions: String
    let separator: String

    static func prepare(source: NoteDocument, target: NoteDocument, selection: Range<Int>, operation: NoteRestructureOperation) throws -> Self {
        let semantic = MarkdownSemanticDocument(parsing: source)
        let definitions = semantic.footnoteDefinitions.filter { !$0.isInline }
        let definitionRanges = Dictionary(uniqueKeysWithValues: definitions.map { ($0.identifier, trimmed($0.span.utf8Range, source: source.rawContent)) })
        let references = try footnoteReferences(source, semantic: semantic, definitions: definitionRanges)
        var ids = Set(definitions.filter { selection.overlaps(definitionRanges[$0.identifier]!) }.map(\.identifier))
        for definition in definitions where ids.contains(definition.identifier) {
            guard contains(selection, definitionRanges[definition.identifier]!) else {
                throw failure("Select complete footnote definitions; a definition cannot be split.")
            }
        }
        ids.formUnion(references.filter { selection.overlaps($0.range) }.map(\.id))
        var previous: Set<String> = []
        while previous != ids {
            previous = ids
            for id in ids {
                guard let span = definitionRanges[id] else { throw failure("A selected footnote has no definition.") }
                ids.formUnion(references.filter { contains(span, $0.range) }.map(\.id))
            }
        }
        for diagnostic in semantic.diagnostics where diagnostic.code == .duplicateFootnote {
            if let span = diagnostic.span, let raw = try? slice(source.rawContent, span.utf8Range),
                ids.contains(where: { raw.hasPrefix("[^" + $0 + "]:") })
            {
                throw failure("Duplicate footnote definitions must be resolved before reorganizing their references.")
            }
        }
        let extra = ids.compactMap { definitionRanges[$0] }.filter { !contains(selection, $0) }.sorted { $0.lowerBound < $1.lowerBound }
        let ranges = [selection] + extra
        var edits: [AgentSourceEdit] = []
        let targetSemantic = MarkdownSemanticDocument(parsing: target)
        var occupied = Set(targetSemantic.footnoteDefinitions.filter { !$0.isInline }.map(\.identifier))
        occupied.formUnion(targetSemantic.footnoteReferences.filter { !$0.isInline }.map(\.identifier))
        occupied.formUnion(ids)
        let conflicts = Set(targetSemantic.footnoteDefinitions.filter { !$0.isInline }.map(\.identifier))
            .union(targetSemantic.footnoteReferences.filter { !$0.isInline }.map(\.identifier))
        for id in ids.sorted() where conflicts.contains(id) {
            var ordinal = 2
            while occupied.contains(id + "-" + String(ordinal)) { ordinal += 1 }
            let fresh = id + "-" + String(ordinal)
            occupied.insert(fresh)
            let definition = definitionRanges[id]!
            edits.append(try edit(source.rawContent, definition.lowerBound..<(definition.lowerBound + id.utf8.count + 3), "[^" + fresh + "]"))
            for reference in references where reference.id == id && ranges.contains(where: { contains($0, reference.range) }) {
                edits.append(try edit(source.rawContent, reference.range, "[^" + fresh + "]"))
            }
        }
        // A shared definition and its dependency closure must remain available to the source.
        var retained = Set(references.filter { reference in !ranges.contains(where: { contains($0, reference.range) }) }.map(\.id))
        previous = []
        while previous != retained {
            previous = retained
            for id in retained {
                if let span = definitionRanges[id] { retained.formUnion(references.filter { contains(span, $0.range) }.map(\.id)) }
            }
        }
        var sourceEdits: [AgentSourceEdit] = []
        var retainedSlices: [String] = []
        if operation == .move {
            for definition in definitions where ids.contains(definition.identifier) {
                let span = definitionRanges[definition.identifier]!
                if retained.contains(definition.identifier) {
                    if contains(selection, span) { retainedSlices.append(try slice(source.rawContent, span)) }
                } else if !contains(selection, span) {
                    sourceEdits.append(try edit(source.rawContent, span, ""))
                }
            }
        }
        let newline = source.rawContent.contains("\r\n") ? "\r\n" : "\n"
        return Self(
            ranges: ranges, edits: edits, sourceEdits: sourceEdits, retainedDefinitions: retainedSlices.joined(separator: newline + newline),
            separator: newline + newline)
    }

    func fragment(source: String) throws -> String { try ranges.map { try Self.slice(source, $0) }.joined(separator: separator) }

    func mapped(_ edit: AgentSourceEdit) throws -> AgentSourceEdit {
        var offset = 0
        for range in ranges {
            if Self.contains(range, edit.startUTF8..<edit.endUTF8) {
                return AgentSourceEdit(
                    startUTF8: offset + edit.startUTF8 - range.lowerBound, endUTF8: offset + edit.endUTF8 - range.lowerBound,
                    expectedText: edit.expectedText, replacement: edit.replacement)
            }
            offset += range.count + separator.utf8.count
        }
        throw Self.failure("A dependency edit falls outside its exact transferred source range.")
    }

    static func contains(_ outer: Range<Int>, _ inner: Range<Int>) -> Bool { outer.lowerBound <= inner.lowerBound && outer.upperBound >= inner.upperBound }
    static func slice(_ source: String, _ range: Range<Int>) throws -> String {
        let bytes = Array(source.utf8)
        guard range.lowerBound >= 0, range.upperBound <= bytes.count, let result = String(bytes: bytes[range], encoding: .utf8) else {
            throw failure("A source range no longer identifies complete UTF-8 text.")
        }
        return result
    }
    static func edit(_ source: String, _ range: Range<Int>, _ replacement: String) throws -> AgentSourceEdit {
        AgentSourceEdit(startUTF8: range.lowerBound, endUTF8: range.upperBound, expectedText: try slice(source, range), replacement: replacement)
    }
    private static func trimmed(_ range: Range<Int>, source: String) -> Range<Int> {
        let bytes = Array(source.utf8)
        var end = range.upperBound
        while end > range.lowerBound && [10, 13].contains(bytes[end - 1]) { end -= 1 }
        return range.lowerBound..<end
    }
    static func literalRanges(in source: NoteDocument, semantic: MarkdownSemanticDocument) -> [Range<Int>] {
        let text = source.rawContent as NSString
        let comments = MarkdownSemanticParser.commentRanges(in: source).map { range in
            text.substring(to: range.lowerBound).utf8.count..<text.substring(to: range.upperBound).utf8.count
        }
        return comments + semantic.mathExpressions.map(\.span.utf8Range)
            + semantic.blocks.filter { $0.kind == .code || $0.kind == .html }.map(\.span.utf8Range)
            + semantic.inlines.filter { $0.kind == .code }.map(\.span.utf8Range)
    }

    private static func footnoteReferences(_ source: NoteDocument, semantic: MarkdownSemanticDocument, definitions: [String: Range<Int>]) throws
        -> [(id: String, range: Range<Int>)]
    {
        let excluded = literalRanges(in: source, semantic: semantic)
        let pattern = try NSRegularExpression(pattern: #"\[\^([^\]\r\n]+)\]"#)
        let body = source.body as NSString
        let ordinary = semantic.footnoteReferences.filter { !$0.isInline }.map { (id: $0.identifier, range: $0.span.utf8Range) }
        let supplementary: [(id: String, range: Range<Int>)] = pattern.matches(in: source.body, range: NSRange(location: 0, length: body.length)).compactMap {
            match in
            let start = source.bodyByteRange.lowerBound + body.substring(to: match.range.location).utf8.count
            let end = start + body.substring(with: match.range).utf8.count
            let range = start..<end
            guard !ordinary.contains(where: { $0.range == range }),
                definitions.values.contains(where: { contains($0, range) && $0.lowerBound != start }),
                !excluded.contains(where: { $0.overlaps(range) })
            else { return nil }
            let bytes = Array(source.rawContent.utf8)
            var preceding = start
            while preceding > 0 && bytes[preceding - 1] == 92 { preceding -= 1 }
            guard (start - preceding).isMultiple(of: 2) else { return nil }
            return (body.substring(with: match.range(at: 1)), range)
        }
        return ordinary + supplementary
    }
    static func failure(_ message: String) -> NoteRestructureError { .unavailable(message) }
}

/// swift-markdown proves occurrence ranges and destinations, including reference syntax and titles.
struct NoteRestructureMarkdownLinks {
    struct Occurrence: Equatable {
        let range: Range<Int>
        let destination: String
        let title: String?
        let isImage: Bool
        let raw: String

        var isReference: Bool { !raw.contains("](") && !raw.hasPrefix("<") }
        func replacingDestination(_ destination: String) throws -> String {
            // Locate the label's closing delimiter using its actual bracket/escape nesting.
            let bytes = Array(raw.utf8)
            let start = isImage ? 1 : 0
            guard start < bytes.count, bytes[start] == 91 else {
                throw NoteRestructureDependencies.failure("This link syntax cannot be relocated without changing its authored label.")
            }
            var depth = 0
            var cursor = start
            var close: Int?
            while cursor < bytes.count {
                if bytes[cursor] == 92 {
                    cursor += 2
                    continue
                }
                if bytes[cursor] == 91 { depth += 1 }
                if bytes[cursor] == 93 {
                    depth -= 1
                    if depth == 0 {
                        close = cursor
                        break
                    }
                }
                cursor += 1
            }
            guard let close, let label = String(bytes: bytes[0...close], encoding: .utf8) else {
                throw NoteRestructureDependencies.failure("The link label has no complete source boundary.")
            }
            var allowed = CharacterSet.urlPathAllowed.union(.urlQueryAllowed)
            allowed.remove(charactersIn: " <>\"\\\r\n()")
            allowed.insert(charactersIn: "#%")
            let escaped = destination.addingPercentEncoding(withAllowedCharacters: allowed) ?? destination
            let titleSource = title.map { " \"" + $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" } ?? ""
            return label + "(" + escaped + titleSource + ")"
        }
    }
    let occurrences: [Occurrence]
    let definitions: [Range<Int>]
    let unsupportedDefinitions: [Range<Int>]

    init(_ source: NoteDocument) throws {
        let semantic = MarkdownSemanticDocument(parsing: source)
        let text = source.rawContent as NSString
        let comments = MarkdownSemanticParser.commentRanges(in: source).map {
            text.substring(to: $0.lowerBound).utf8.count..<text.substring(to: $0.upperBound).utf8.count
        }
        let wikiRanges = semantic.links.filter {
            guard let raw = try? NoteRestructureDependencies.slice(source.rawContent, $0.linkSpan.utf8Range) else { return false }
            return raw.hasPrefix("[[") || raw.hasPrefix("![[")
        }.map(\.linkSpan.utf8Range)
        let inlineProjections =
            wikiRanges + semantic.footnoteDefinitions.filter(\.isInline).map(\.span.utf8Range)
            + semantic.mathExpressions.filter { $0.kind == .inline }.map(\.span.utf8Range)
        let projections =
            semantic.footnoteDefinitions.map(\.span.utf8Range)
            + semantic.mathExpressions.map(\.span.utf8Range) + comments + wikiRanges
        let protected = NoteRestructureDependencies.literalRanges(in: source, semantic: semantic) + projections
        var bodyBytes = Array(source.body.utf8)
        // Definitions inside a footnote belong only to that footnote's rendering scope.
        // Mask before parsing, rather than letting their declarations capture outer prose.
        for range in projections {
            for offset in range {
                let index = offset - source.bodyByteRange.lowerBound
                if bodyBytes.indices.contains(index), ![10, 13].contains(bodyBytes[index]) { bodyBytes[index] = 32 }
            }
        }
        for range in inlineProjections
        where !semantic.footnoteDefinitions.contains(where: {
            !$0.isInline && NoteRestructureDependencies.contains($0.span.utf8Range, range)
        }) {
            for offset in range {
                let index = offset - source.bodyByteRange.lowerBound
                if bodyBytes.indices.contains(index), ![10, 13].contains(bodyBytes[index]) { bodyBytes[index] = 120 }
            }
        }
        var walker = Walker(source: source)
        walker.visit(Document(parsing: String(decoding: bodyBytes, as: UTF8.self), options: [.parseBlockDirectives]))
        var occurrences = walker.occurrences.filter { occurrence in !protected.contains { NoteRestructureDependencies.contains($0, occurrence.range) } }
        // The reader parses footnote content as its own Markdown scope. Use the same projection,
        // but map its nodes back through the parser-owned source slices before planning any edit.
        for definition in semantic.footnoteDefinitions
        where !semantic.footnoteDefinitions.contains(where: {
            $0.span != definition.span && NoteRestructureDependencies.contains($0.span.utf8Range, definition.span.utf8Range)
        }) {
            let fragment = NoteDocument(relativePath: source.relativePath, rawContent: definition.content)
            let links = try Self(fragment)
            for link in links.occurrences {
                guard let first = definition.contentSlices.first(where: { $0.contentUTF8Range.contains(link.range.lowerBound) }),
                    let last = definition.contentSlices.last(where: {
                        $0.contentUTF8Range.lowerBound < link.range.upperBound && $0.contentUTF8Range.upperBound >= link.range.upperBound
                    })
                else { throw NoteRestructureDependencies.failure("A footnote link has no exact source mapping.") }
                let lower = first.sourceSpan.utf8LowerBound + link.range.lowerBound - first.contentUTF8Range.lowerBound
                let upper = last.sourceSpan.utf8LowerBound + link.range.upperBound - last.contentUTF8Range.lowerBound
                let range = lower..<upper
                occurrences.append(
                    Occurrence(
                        range: range, destination: link.destination, title: link.title, isImage: link.isImage,
                        raw: try NoteRestructureDependencies.slice(source.rawContent, range)))
            }
        }
        self.occurrences = occurrences.sorted { $0.range.lowerBound < $1.range.lowerBound }
        let regex = try NSRegularExpression(pattern: #"(?m)^ {0,3}\[(?!\^)[^\]\r\n]+\]:[^\r\n]*(?:\r\n|\n|$)"#)
        let body = source.body as NSString
        var definitions: [Range<Int>] = []
        var unsupported: [Range<Int>] = []
        for match in regex.matches(in: source.body, range: NSRange(location: 0, length: body.length)) {
            let start = source.bodyByteRange.lowerBound + body.substring(to: match.range.location).utf8.count
            let raw = body.substring(with: match.range)
            let span = start..<(start + raw.utf8.count)
            if protected.contains(where: { $0.overlaps(span) }) { continue }
            // A complete standalone definition produces no visible block. Multi-line definitions fail closed below.
            guard Document(parsing: raw).childCount == 0 else {
                unsupported.append(span)
                continue
            }
            // A next-line title belongs to this definition, not to a new prose block.
            let end = NSMaxRange(match.range)
            if end < body.length {
                let next = body.lineRange(for: NSRange(location: end, length: 0))
                let nextRaw = body.substring(with: next)
                let titleLine = nextRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                if let first = titleLine.first, "\"'(".contains(first),
                    Document(parsing: raw + nextRaw).childCount == 0
                {
                    unsupported.append(span.lowerBound..<(span.upperBound + nextRaw.utf8.count))
                    continue
                }
            }
            definitions.append(span)
        }
        let nested = try NSRegularExpression(
            pattern: #"(?m)^(?:[ \t]*(?:>[ \t]*|(?:[-+*]|[0-9]{1,9}[.)])[ \t]+))+\[(?!\^)[^\]\r\n]+\]:[^\r\n]*|^[ \t]{4,}\[(?!\^)[^\]\r\n]+\]:[^\r\n]*"#)
        for match in nested.matches(in: source.body, range: NSRange(location: 0, length: body.length)) {
            let start = source.bodyByteRange.lowerBound + body.substring(to: match.range.location).utf8.count
            let span = start..<(start + body.substring(with: match.range).utf8.count)
            if !protected.contains(where: { $0.overlaps(span) }) { unsupported.append(span) }
        }
        self.definitions = definitions
        self.unsupportedDefinitions = unsupported
    }

    /// A reference table belongs to the complete Markdown scope. Escape only newly captured
    /// literal openers in the transferred text, then prove both sides retain their link meaning.
    static func isolatingReferences(in fragment: String, after prefix: String, path: String) throws -> String {
        func links(_ text: String) throws -> [Occurrence] {
            try Self(NoteDocument(relativePath: path, rawContent: text)).occurrences.filter { !$0.raw.hasPrefix("[^") }
        }
        let retained = try links(prefix)
        let boundary = prefix.utf8.count
        var candidate = fragment
        // Each iteration escapes at least one previously unescaped opener; there is no retry
        // against changing documents, and the original input bounds the work.
        for _ in 0...fragment.utf8.filter({ $0 == 91 }).count {
            let transferred = try links(candidate).map {
                Occurrence(
                    range: ($0.range.lowerBound + boundary)..<($0.range.upperBound + boundary),
                    destination: $0.destination, title: $0.title, isImage: $0.isImage, raw: $0.raw)
            }
            let expected = retained + transferred
            let combined = try links(prefix + candidate)
            if combined == expected { return candidate }
            guard expected.allSatisfy({ combined.contains($0) }) else {
                throw NoteRestructureDependencies.failure("Combining these notes would change an existing Markdown link's meaning.")
            }
            let captured = combined.filter { !expected.contains($0) }
            guard !captured.isEmpty,
                captured.allSatisfy({ link in
                    link.range.lowerBound >= boundary && link.isReference
                        && !expected.contains(where: { $0.range.overlaps(link.range) })
                })
            else {
                throw NoteRestructureDependencies.failure("A transferred reference definition would change the destination's existing text.")
            }
            let edits = captured.map { link in
                let offset = link.range.lowerBound - boundary + (link.isImage ? 1 : 0)
                return AgentSourceEdit(startUTF8: offset, endUTF8: offset, expectedText: "", replacement: "\\")
            }
            candidate = try AgentSourceEdit.applying(edits, to: Data(candidate.utf8))
        }
        throw NoteRestructureDependencies.failure("The transferred text could not retain its original reference meaning.")
    }

    private struct Walker: MarkupWalker {
        let source: NoteDocument
        var occurrences: [Occurrence] = []
        mutating func visitLink(_ link: Markdown.Link) {
            append(link, destination: link.destination, title: link.title, isImage: false)
            // The outer label owns nested image markup; overlapping edits must never be guessed.
        }
        mutating func visitImage(_ image: Markdown.Image) { append(image, destination: image.source, title: image.title, isImage: true) }
        mutating func append(_ node: Markup, destination: String?, title: String?, isImage: Bool) {
            guard let range = node.range, let destination else { return }
            let bytes = Array(source.body.utf8)
            var starts = [0]
            for index in bytes.indices where bytes[index] == 10 { starts.append(index + 1) }
            guard range.lowerBound.line > 0, range.upperBound.line <= starts.count else { return }
            let lower = starts[range.lowerBound.line - 1] + range.lowerBound.column - 1 + source.bodyByteRange.lowerBound
            let upper = starts[range.upperBound.line - 1] + range.upperBound.column - 1 + source.bodyByteRange.lowerBound
            guard let raw = try? NoteRestructureDependencies.slice(source.rawContent, lower..<upper) else { return }
            occurrences.append(Occurrence(range: lower..<upper, destination: destination, title: title, isImage: isImage, raw: raw))
        }
    }
}
