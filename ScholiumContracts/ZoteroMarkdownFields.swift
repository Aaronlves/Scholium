import CoreFoundation
import Foundation
import Markdown

/// Source-owned host metadata. Zotero's document data and field strings remain opaque.
public struct ZoteroMarkdownBibliographyStyle: Codable, Hashable, Sendable {
    public let firstLineIndent: Double
    public let indent: Double
    public let lineSpacing: Double
    public let entrySpacing: Double
    public let tabStops: [Double]

    public init(firstLineIndent: Double, indent: Double, lineSpacing: Double, entrySpacing: Double, tabStops: [Double]) {
        self.firstLineIndent = firstLineIndent
        self.indent = indent
        self.lineSpacing = lineSpacing
        self.entrySpacing = entrySpacing
        self.tabStops = tabStops
    }

    public var bodyIndentPoints: Double { indent / 20 }
    public var firstLineOffsetPoints: Double { firstLineIndent / 20 }
    public var firstLineIndentPoints: Double { (indent + firstLineIndent) / 20 }
    public var lineHeightMultiple: Double { lineSpacing / 240 }
    public var entrySpacingPoints: Double { entrySpacing / 20 }
    public var tabStopPoints: [Double] { tabStops.map { $0 / 20 } }

    var isValid: Bool {
        let values = [firstLineIndent, indent, lineSpacing, entrySpacing] + tabStops
        return tabStops.count <= 64 && lineSpacing > 0 && entrySpacing >= 0
            && values.allSatisfy { $0.isFinite && abs($0) <= 100_000 }
    }
}

public struct ZoteroMarkdownAcceptedField: Codable, Hashable, Sendable {
    public let id: String
    public let code: String
    public init(id: String, code: String) {
        self.id = id
        self.code = code
    }
}

public struct ZoteroMarkdownDocumentState: Codable, Hashable, Sendable {
    public let data: String
    public let bibliographyStyle: ZoteroMarkdownBibliographyStyle?
    public let acceptedFields: [ZoteroMarkdownAcceptedField]?
    public let span: SourceSpan
}

public struct ZoteroMarkdownField: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable { case citation, bibliography }
    public let id: String
    public let kind: Kind
    public let code: String
    /// Exact last vendor HTML; never a display or current-text authority.
    public let text: String
    public let span: SourceSpan
    public let fallbackSpan: SourceSpan
    public let markerSpans: [SourceSpan]
    public let fallbackMarkdown: String
    /// Actual rendered fallback text, including manual edits.
    public let plainText: String

    public var isCompleted: Bool {
        let prefix = kind == .citation ? "ITEM CSL_CITATION " : "BIBL "
        guard code.hasPrefix(prefix) else { return false }
        var json = String(code.dropFirst(prefix.count))
        if kind == .bibliography {
            let suffix = " CSL_BIBLIOGRAPHY"
            guard json.hasSuffix(suffix) else { return false }
            json.removeLast(suffix.count)
        }
        guard let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        if kind == .bibliography { return true }
        guard let items = object["citationItems"] as? [[String: Any]], !items.isEmpty else { return false }
        return items.allSatisfy { item in
            if let id = item["id"] as? String { return !id.isEmpty }
            if let id = item["id"] as? NSNumber {
                let value = id.doubleValue
                return CFGetTypeID(id) != CFBooleanGetTypeID() && value > 0
                    && value <= 9_007_199_254_740_991 && value.rounded(.towardZero) == value
            }
            return false
        }
    }
}

public struct ZoteroMarkdownDiagnostic: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case malformedEnvelope, unsupportedEnvelope, duplicateID, duplicateDocument, unsupportedText, unsupportedContext
    }
    public let kind: Kind
    public let span: SourceSpan
    public let message: String
}

/// A deletion-only, read-only projection. Every retained UTF-16 unit maps to the
/// same exact unit in source. No consumer may serialize this projection as source.
public struct ZoteroMarkdownReadingProjection: Hashable, Sendable {
    public struct Segment: Hashable, Sendable {
        public let projectedRange: Range<Int>
        public let sourceRange: Range<Int>
    }
    public let source: String
    public let segments: [Segment]

    public func sourceRange(for range: Range<Int>) -> Range<Int>? {
        guard range.lowerBound >= 0, range.upperBound <= source.utf16.count, range.lowerBound < range.upperBound,
            let first = segments.first(where: { $0.projectedRange.contains(range.lowerBound) }),
            let last = segments.first(where: { $0.projectedRange.contains(range.upperBound - 1) })
        else { return nil }
        let lower = first.sourceRange.lowerBound + range.lowerBound - first.projectedRange.lowerBound
        let upper = last.sourceRange.lowerBound + range.upperBound - last.projectedRange.lowerBound
        return lower..<upper
    }

    public func sourceFragments(for range: Range<Int>) -> [(projectedRange: Range<Int>, sourceRange: Range<Int>)] {
        segments.compactMap { segment in
            let lower = max(range.lowerBound, segment.projectedRange.lowerBound)
            let upper = min(range.upperBound, segment.projectedRange.upperBound)
            guard lower < upper else { return nil }
            let delta = segment.sourceRange.lowerBound - segment.projectedRange.lowerBound
            return (lower..<upper, (lower + delta)..<(upper + delta))
        }
    }
}

/// One bounded parser-owned catalog for committed source, presentation and native
/// citation admission. Malformed source remains unchanged and nonauthorizing.
public struct ZoteroMarkdownFields: Codable, Hashable, Sendable {
    public static let citationScheme = "scholium-zotero:"
    public static let maximumEnvelopeUTF16Count = 256 * 1_024
    public static let maximumFallbackUTF16Count = 64 * 1_024
    public static let maximumFieldCount = 1_024

    public let fingerprint: DocumentFingerprint
    public let fields: [ZoteroMarkdownField]
    public let documentState: ZoteroMarkdownDocumentState?
    public let diagnostics: [ZoteroMarkdownDiagnostic]
    public var canMutate: Bool { diagnostics.isEmpty }
    public var citationStateStale: Bool {
        guard let accepted = documentState?.acceptedFields else { return !fields.isEmpty }
        return accepted != fields.map { .init(id: $0.id, code: $0.code) }
    }
    public var metadataSpans: [SourceSpan] {
        guard canMutate else { return [] }
        return fields.flatMap(\.markerSpans) + (documentState.map { [$0.span] } ?? [])
    }

    public init(parsing document: NoteDocument) { self = MarkdownSemanticDocument(parsing: document).zoteroFields }

    init(fingerprint: DocumentFingerprint, fields: [ZoteroMarkdownField], documentState: ZoteroMarkdownDocumentState?, diagnostics: [ZoteroMarkdownDiagnostic])
    {
        self.fingerprint = fingerprint
        self.fields = fields
        self.documentState = documentState
        self.diagnostics = diagnostics
    }

    static func empty(fingerprint: DocumentFingerprint) -> Self {
        .init(fingerprint: fingerprint, fields: [], documentState: nil, diagnostics: [])
    }

    public func readingProjection(source: String) -> ZoteroMarkdownReadingProjection? {
        guard DocumentFingerprint(content: source) == fingerprint else { return nil }
        let removals = metadataSpans.map(\.utf16Range).sorted { $0.lowerBound < $1.lowerBound }
        let nsSource = source as NSString
        var cursor = 0
        var projected = ""
        var segments: [ZoteroMarkdownReadingProjection.Segment] = []
        func append(_ range: Range<Int>) {
            guard !range.isEmpty else { return }
            let start = projected.utf16.count
            projected += nsSource.substring(with: NSRange(location: range.lowerBound, length: range.count))
            segments.append(.init(projectedRange: start..<projected.utf16.count, sourceRange: range))
        }
        for removal in removals {
            guard removal.lowerBound >= cursor, removal.upperBound <= nsSource.length else { return nil }
            append(cursor..<removal.lowerBound)
            cursor = removal.upperBound
        }
        append(cursor..<nsSource.length)
        return .init(source: projected, segments: segments)
    }

    static func parse(_ document: NoteDocument, semantic: MarkdownSemanticDocument, inlineHTMLSpans: [SourceSpan]) -> Self {
        guard document.frontmatterState != .malformed else { return .empty(fingerprint: document.fingerprint) }
        guard
            document.rawContent.range(of: citationScheme, options: .caseInsensitive) != nil
                || document.rawContent.contains(ZoteroMarkdownFieldParser.fieldPrefix)
                || document.rawContent.contains(ZoteroMarkdownFieldParser.documentPrefix)
                || document.rawContent.contains(ZoteroMarkdownFieldParser.fieldClose)
        else { return .empty(fingerprint: document.fingerprint) }
        return ZoteroMarkdownFieldParser(document: document, semantic: semantic, inlineHTMLSpans: inlineHTMLSpans).parse()
    }

    static func plainFallbackText(_ markdown: String) throws -> String {
        let parsed = Document(parsing: markdown)
        var visitor = ZoteroFallbackText()
        visitor.visit(parsed)
        guard !visitor.unsupported else { throw ZoteroFallbackFailure.unsupported }
        return visitor.text
    }
}

private enum ZoteroFallbackFailure: Error { case unsupported }

private struct ZoteroFieldPayload: Decodable {
    let id: String
    let kind: ZoteroMarkdownField.Kind
    let code: String
    let text: String
}
private struct ZoteroDocumentPayload: Decodable {
    let data: String
    let bibliographyStyle: ZoteroMarkdownBibliographyStyle?
    let acceptedFields: [ZoteroMarkdownAcceptedField]?
}

private struct ZoteroMarkdownFieldParser {
    let document: NoteDocument
    let semantic: MarkdownSemanticDocument
    let source: NSString
    let mapper: SemanticSourceMapper
    let comments: [Range<Int>]
    let ignoredInlineHTML: [Range<Int>]
    let sourceHTMLSpans: [SourceSpan]
    static let fieldPrefix = "<!--scholium-zotero-field:"
    static let documentPrefix = "<!--scholium-zotero-document:"
    static let fieldClose = "<!--/scholium-zotero-field-->"

    init(document: NoteDocument, semantic: MarkdownSemanticDocument, inlineHTMLSpans: [SourceSpan]) {
        self.document = document
        self.semantic = semantic
        let exactSource = document.rawContent as NSString
        source = exactSource
        mapper = SemanticSourceMapper(document.rawContent)
        comments = MarkdownSemanticParser.commentRanges(in: document)
        ignoredInlineHTML = Self.inlineHTMLContainers(in: exactSource, spans: inlineHTMLSpans)
        sourceHTMLSpans = Array(
            Set(
                semantic.blocks.filter { $0.kind == .html }.map(\.span)
                    + inlineHTMLSpans.filter { span in
                        let raw = exactSource.substring(with: span.nsRange)
                        return raw.hasPrefix(Self.documentPrefix) || raw.hasPrefix(Self.fieldPrefix) || raw.hasPrefix(Self.fieldClose)
                    })
        ).sorted { $0.utf16LowerBound < $1.utf16LowerBound }
    }

    func parse() -> ZoteroMarkdownFields {
        var fields: [ZoteroMarkdownField] = []
        var states: [ZoteroMarkdownDocumentState] = []
        var identities: [(String, SourceSpan)] = []
        var diagnostics: [ZoteroMarkdownDiagnostic] = []
        func diagnose(_ kind: ZoteroMarkdownDiagnostic.Kind, _ range: NSRange, _ message: String) {
            guard let span = mapper.span(for: range) else { return }
            diagnostics.append(.init(kind: kind, span: span, message: message))
        }
        for inline in semantic.inlines where inline.kind == .link {
            let range = inline.span.nsRange
            let raw = source.substring(with: range)
            guard
                semantic.links.contains(where: {
                    $0.linkSpan == inline.span && $0.target.lowercased().hasPrefix(ZoteroMarkdownFields.citationScheme)
                })
            else { continue }
            guard !ignoredInlineHTML.contains(where: { $0.overlaps(inline.span.utf16Range) }) else { continue }
            guard ordinaryContext(range, allowing: inline.span) else {
                diagnose(.unsupportedContext, range, "Citations require an ordinary body paragraph.")
                continue
            }
            guard let expression = try? NSRegularExpression(pattern: #"^\[([\s\S]*)\]\(scholium-zotero:1:([A-Za-z0-9+/=]*)\)$"#),
                let match = expression.firstMatch(in: raw, range: NSRange(location: 0, length: (raw as NSString).length))
            else {
                diagnose(.unsupportedEnvelope, range, "Invalid or unsupported citation source envelope.")
                continue
            }
            let fallback = NSRange(location: range.location + match.range(at: 1).location, length: match.range(at: 1).length)
            do {
                let payload: ZoteroFieldPayload = try decode((raw as NSString).substring(with: match.range(at: 2)), keys: ["id", "kind", "code", "text"])
                guard payload.kind == .citation else { throw ParseFailure.invalid }
                if validID(payload.id) { identities.append((payload.id, inline.span)) }
                fields.append(try field(payload, range: range, fallback: fallback))
            } catch { diagnose(.malformedEnvelope, range, "Invalid citation payload or unsupported fallback text.") }
        }

        for marker in sourceHTMLSpans {
            let range = marker.nsRange
            let raw = source.substring(with: range)
            let candidate = raw.trimmingCharacters(in: .whitespaces)
            guard candidate.hasPrefix(Self.documentPrefix) || candidate.hasPrefix(Self.fieldPrefix) else { continue }
            guard !ignoredInlineHTML.contains(where: { $0.overlaps(marker.utf16Range) }) else { continue }
            guard markerOnly(range), raw.hasPrefix(Self.documentPrefix) || raw.hasPrefix(Self.fieldPrefix) else {
                diagnose(.malformedEnvelope, range, "Zotero markers require an exact marker-only source line.")
                continue
            }
            let isDocument = raw.hasPrefix(Self.documentPrefix)
            let prefix = isDocument ? Self.documentPrefix : Self.fieldPrefix
            guard raw.hasSuffix("-->"), raw.utf16.count <= ZoteroMarkdownFields.maximumEnvelopeUTF16Count + 64,
                !raw.contains("\n"), !raw.contains("\r")
            else {
                diagnose(.malformedEnvelope, range, "Invalid Zotero source marker.")
                continue
            }
            guard ordinaryContext(range, allowing: marker) else {
                diagnose(.unsupportedContext, range, "Zotero markers require an ordinary body context.")
                continue
            }
            guard raw.dropFirst(prefix.count).hasPrefix("1:")
            else {
                diagnose(.unsupportedEnvelope, range, "Invalid or unsupported Zotero source marker.")
                continue
            }
            let encoded = String(raw.dropFirst(prefix.count + 2).dropLast(3))
            do {
                if isDocument {
                    let payload: ZoteroDocumentPayload = try decode(encoded, keys: ["data", "bibliographyStyle", "acceptedFields"])
                    guard payload.bibliographyStyle?.isValid != false,
                        payload.acceptedFields?.count ?? 0 <= ZoteroMarkdownFields.maximumFieldCount,
                        payload.acceptedFields?.allSatisfy({ validID($0.id) }) != false,
                        Set(payload.acceptedFields?.map(\.id) ?? []).count == (payload.acceptedFields?.count ?? 0)
                    else { throw ParseFailure.invalid }
                    states.append(
                        .init(
                            data: payload.data, bibliographyStyle: payload.bibliographyStyle,
                            acceptedFields: payload.acceptedFields, span: marker))
                } else {
                    let payload: ZoteroFieldPayload = try decode(encoded, keys: ["id", "kind", "code", "text"])
                    if validID(payload.id) { identities.append((payload.id, marker)) }
                    guard payload.kind == .bibliography,
                        let close = sourceHTMLSpans.first(where: { candidate in
                            candidate.utf16LowerBound >= NSMaxRange(range)
                                && source.substring(with: candidate.nsRange) == Self.fieldClose
                        }), markerOnly(close.nsRange)
                    else { throw ParseFailure.invalid }
                    let full = NSRange(location: range.location, length: close.utf16UpperBound - range.location)
                    guard ordinaryContext(full, allowing: marker, extraAllowed: close),
                        let fallback = bibliographyFallbackRange(NSMaxRange(range)..<close.utf16LowerBound)
                    else { throw ParseFailure.invalid }
                    fields.append(try field(payload, range: full, fallback: fallback))
                }
            } catch { diagnose(.malformedEnvelope, range, "Invalid Zotero payload, paired markers or fallback.") }
        }

        fields.sort { $0.span.utf16LowerBound < $1.span.utf16LowerBound }
        for marker in sourceHTMLSpans
        where source.substring(with: marker.nsRange).trimmingCharacters(in: .whitespaces) == Self.fieldClose
            && !ignoredInlineHTML.contains(where: { $0.overlaps(marker.utf16Range) })
            && !fields.contains(where: { $0.kind == .bibliography && $0.span.utf16Range.contains(marker.utf16LowerBound) })
        {
            diagnose(.malformedEnvelope, marker.nsRange, "A bibliography closing marker has no valid paired field.")
        }
        // Diagnostics may recognize an unowned reserved token, but only the
        // parser-proved Link and HTMLBlock paths above can confer field authority.
        let owned =
            semantic.inlines.filter { $0.kind == .link }.map(\.span.utf16Range)
            + semantic.links.filter { !$0.target.lowercased().hasPrefix(ZoteroMarkdownFields.citationScheme) }.map(\.span.utf16Range)
        let ignored =
            semantic.blocks.filter { $0.kind == .code || $0.kind == .html }.map(\.span.utf16Range)
            + semantic.inlines.filter { $0.kind == .code }.map(\.span.utf16Range)
            + ignoredInlineHTML + comments
        let unsupported =
            semantic.blocks.filter { ![MarkdownBlockKind.paragraph, .html, .code].contains($0.kind) }.map(\.span.utf16Range)
            + semantic.callouts.map(\.span.utf16Range) + semantic.footnoteDefinitions.map(\.span.utf16Range)
            + semantic.footnoteReferences.map(\.span.utf16Range) + semantic.mathExpressions.map(\.span.utf16Range)
        if let expression = try? NSRegularExpression(pattern: #"scholium-zotero:|<!--scholium-zotero-(?:field|document):"#, options: .caseInsensitive) {
            for match in expression.matches(
                in: source as String, range: NSRange(location: document.bodyUTF16Offset, length: source.length - document.bodyUTF16Offset))
            {
                let offset = match.range.location
                guard !(owned + ignored).contains(where: { $0.contains(offset) }) else { continue }
                if offset > 0, source.character(at: offset) == 60 {
                    var cursor = offset
                    while cursor > 0, source.character(at: cursor - 1) == 92 { cursor -= 1 }
                    if (offset - cursor) % 2 == 1 { continue }
                }
                let kind: ZoteroMarkdownDiagnostic.Kind = unsupported.contains(where: { $0.contains(offset) }) ? .unsupportedContext : .malformedEnvelope
                diagnose(kind, match.range, "Citation metadata is not in a supported parser-owned carrier.")
            }
        }
        let duplicates = Set(Dictionary(grouping: identities, by: { $0.0 }).filter { $0.value.count > 1 }.keys)
        for (id, span) in identities where duplicates.contains(id) {
            diagnose(.duplicateID, span.nsRange, "Copied or duplicate field identity; reinsert the citation.")
        }
        fields.removeAll { duplicates.contains($0.id) }
        if fields.count > ZoteroMarkdownFields.maximumFieldCount {
            for field in fields { diagnose(.malformedEnvelope, field.span.nsRange, "Too many Zotero fields.") }
            fields.removeAll()
        }
        if states.count > 1 {
            for state in states { diagnose(.duplicateDocument, state.span.nsRange, "More than one document state is present.") }
        }
        return .init(
            fingerprint: document.fingerprint, fields: fields,
            documentState: states.count == 1 ? states.first : nil,
            diagnostics: diagnostics.sorted { $0.span.utf16LowerBound < $1.span.utf16LowerBound })
    }

    private func field(_ payload: ZoteroFieldPayload, range: NSRange, fallback: NSRange) throws -> ZoteroMarkdownField {
        guard validID(payload.id), fallback.length <= ZoteroMarkdownFields.maximumFallbackUTF16Count,
            let span = mapper.span(for: range), let fallbackSpan = mapper.span(for: fallback)
        else { throw ParseFailure.invalid }
        let markdown = source.substring(with: fallback)
        guard payload.kind != .citation || !markdown.contains(where: { $0.isNewline }) else { throw ParseFailure.invalid }
        guard payload.text.utf16.count <= ZoteroMarkdownFields.maximumFallbackUTF16Count else { throw ParseFailure.invalid }
        let actual = try ZoteroMarkdownFields.plainFallbackText(markdown)
        let markers: [SourceSpan]
        if payload.kind == .citation {
            markers = [
                mapper.span(for: NSRange(location: range.location, length: fallback.location - range.location)),
                mapper.span(for: NSRange(location: NSMaxRange(fallback), length: NSMaxRange(range) - NSMaxRange(fallback))),
            ].compactMap { $0 }
        } else {
            markers = sourceHTMLSpans.filter { range.location <= $0.utf16LowerBound && $0.utf16UpperBound <= NSMaxRange(range) }
        }
        return .init(
            id: payload.id, kind: payload.kind, code: payload.code, text: payload.text, span: span,
            fallbackSpan: fallbackSpan, markerSpans: markers, fallbackMarkdown: markdown, plainText: actual)
    }

    private func ordinaryContext(_ range: NSRange, allowing: SourceSpan, extraAllowed: SourceSpan? = nil) -> Bool {
        let protected =
            semantic.blocks.filter {
                ![MarkdownBlockKind.paragraph, .html].contains($0.kind)
                    || ($0.kind == .html && $0.span != allowing && $0.span != extraAllowed)
            }.map(\.span)
            + semantic.inlines.filter {
                $0.kind == .code || $0.kind == .image || ($0.kind == .link && $0.span != allowing)
            }.map(\.span) + semantic.callouts.map(\.span) + semantic.footnoteDefinitions.map(\.span)
            + semantic.footnoteReferences.map(\.span) + semantic.mathExpressions.map(\.span)
            + semantic.links.filter { $0.syntax != .markdown }.map(\.span)
        guard !protected.contains(where: { NSIntersectionRange($0.nsRange, range).length > 0 }) else { return false }
        return !comments.contains { comment in
            let allowed = comment == allowing.utf16Range || comment == extraAllowed?.utf16Range
            return !allowed && comment.lowerBound < NSMaxRange(range) && comment.upperBound > range.location
        }
    }

    private func markerOnly(_ range: NSRange) -> Bool {
        let previous = source.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: range.location))
        let lineStart = previous.location == NSNotFound ? 0 : NSMaxRange(previous)
        let following = source.range(of: "\n", range: NSRange(location: NSMaxRange(range), length: source.length - NSMaxRange(range)))
        let lineEnd = following.location == NSNotFound ? source.length : following.location
        let prefix = source.substring(with: NSRange(location: lineStart, length: range.location - lineStart))
        let suffix = source.substring(with: NSRange(location: NSMaxRange(range), length: lineEnd - NSMaxRange(range)))
        return (prefix.isEmpty || (lineStart == 0 && prefix == "\u{FEFF}"))
            && (suffix.isEmpty || (following.location != NSNotFound && suffix == "\r"))
    }
    private func bibliographyFallbackRange(_ range: Range<Int>) -> NSRange? {
        let middle = source.substring(with: NSRange(location: range.lowerBound, length: range.count)) as NSString
        guard let startExpression = try? NSRegularExpression(pattern: #"^(?:\r\n|\n){2}"#),
            let endExpression = try? NSRegularExpression(pattern: #"(?:\r\n|\n){2}$"#),
            let start = startExpression.firstMatch(in: middle as String, range: NSRange(location: 0, length: middle.length)),
            let end = endExpression.firstMatch(in: middle as String, range: NSRange(location: 0, length: middle.length)),
            start.range.length + end.range.length <= middle.length
        else { return nil }
        return NSRange(location: range.lowerBound + start.range.length, length: middle.length - start.range.length - end.range.length)
    }
    private func validID(_ id: String) -> Bool { id.range(of: #"^[A-Za-z][A-Za-z0-9_-]{0,127}$"#, options: .regularExpression) != nil }
    /// Only tags already classified by the shared Markdown parser may open a raw
    /// HTML context. Source resembling HTML in code, escapes or text has no role.
    private static func inlineHTMLContainers(in source: NSString, spans: [SourceSpan]) -> [Range<Int>] {
        let tagExpression = try? NSRegularExpression(pattern: #"^<(\/?)([A-Za-z][A-Za-z0-9-]*)\b"#)
        let voidTags: Set<String> = ["br", "hr", "img", "input", "meta", "link", "wbr"]
        var stack: [(name: String, from: Int)] = []
        var ranges: [Range<Int>] = []
        for span in spans.sorted(by: { $0.utf16LowerBound < $1.utf16LowerBound }) {
            let raw = source.substring(with: span.nsRange) as NSString
            if (raw as String).hasPrefix(documentPrefix) || (raw as String).hasPrefix(fieldPrefix) || (raw as String).hasPrefix(fieldClose) { continue }
            ranges.append(span.utf16Range)
            guard let match = tagExpression?.firstMatch(in: raw as String, range: NSRange(location: 0, length: raw.length)) else { continue }
            let name = raw.substring(with: match.range(at: 2)).lowercased()
            if match.range(at: 1).length > 0 {
                if let opening = stack.popLast() {
                    ranges.append(opening.from..<span.utf16UpperBound)
                    if opening.name != name { ranges.append(span.utf16LowerBound..<source.length) }
                }
            } else if !voidTags.contains(name), (raw as String).range(of: #"/\s*>$"#, options: .regularExpression) == nil {
                stack.append((name, span.utf16LowerBound))
            }
        }
        ranges.append(contentsOf: stack.map { $0.from..<source.length })
        return ranges
    }
    private func decode<T: Decodable>(_ encoded: String, keys: Set<String>) throws -> T {
        guard !encoded.isEmpty, encoded.utf16.count <= ZoteroMarkdownFields.maximumEnvelopeUTF16Count,
            let data = Data(base64Encoded: encoded), data.base64EncodedString() == encoded,
            String(data: data, encoding: .utf8) != nil,
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], Set(object.keys).isSubset(of: keys)
        else { throw ParseFailure.invalid }
        if let style = object["bibliographyStyle"] as? [String: Any],
            Set(style.keys) != ["firstLineIndent", "indent", "lineSpacing", "entrySpacing", "tabStops"]
        {
            throw ParseFailure.invalid
        }
        if let accepted = object["acceptedFields"] as? [[String: Any]],
            !accepted.allSatisfy({ Set($0.keys) == ["id", "code"] })
        {
            throw ParseFailure.invalid
        }
        if object["bibliographyStyle"] is NSNull || object["acceptedFields"] is NSNull { throw ParseFailure.invalid }
        return try JSONDecoder().decode(T.self, from: data)
    }
    private enum ParseFailure: Error { case invalid }
}

private struct ZoteroFallbackText: MarkupWalker {
    var text = "", unsupported = false
    mutating func visitDocument(_ document: Document) { descendInto(document) }
    mutating func visitParagraph(_ paragraph: Paragraph) { descendInto(paragraph) }
    mutating func visitEmphasis(_ emphasis: Emphasis) { descendInto(emphasis) }
    mutating func visitStrong(_ strong: Strong) { descendInto(strong) }
    mutating func visitText(_ node: Markdown.Text) { text += node.string }
    mutating func visitSoftBreak(_ node: SoftBreak) { text += "\n" }
    mutating func defaultVisit(_ markup: Markup) { unsupported = true }
}
