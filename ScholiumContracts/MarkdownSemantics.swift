import Foundation

public struct MarkdownFootnoteReference: Hashable, Sendable {
    public let identifier: String
    public let range: NSRange
    public let labelRange: NSRange
    public let content: String
}

public struct MarkdownHighlight: Hashable, Sendable {
    public let range: NSRange
    public let contentRange: NSRange
}

public struct MarkdownCalloutBlock: Hashable, Sendable {
    public let kind: String
    public let foldState: CalloutFoldState
    public let foldMarkerRange: NSRange?
    public let blockRange: NSRange
    public let headerRange: NSRange
    public let kindRange: NSRange
    public let markerRanges: [NSRange]
}

/// Read-only UTF-16 ranges used by the native reader and Live Preview. These
/// projections never modify or normalize the Markdown string.
public enum MarkdownSemanticProjection {
    public static func highlights(in source: String) -> [MarkdownHighlight] {
        matches(#"==([^=\n]+)=="#, in: source).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return MarkdownHighlight(range: match.range, contentRange: match.range(at: 1))
        }
    }

    public static func footnoteReferences(in source: String) -> [MarkdownFootnoteReference] {
        let nsSource = source as NSString
        var definitions: [String: String] = [:]
        for match in matches(#"(?m)^\[\^([^\]\n]+)\]:[ \t]*(.*(?:\n(?: {2,}|\t).*)*)$"#, in: source) {
            let identifier = nsSource.substring(with: match.range(at: 1))
            let raw = nsSource.substring(with: match.range(at: 2))
            definitions[identifier] = raw
                .replacingOccurrences(of: #"\n(?: {2,}|\t)"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return matches(#"\[\^([^\]\n]+)\]"#, in: source).compactMap { match in
            let lineRange = nsSource.lineRange(for: NSRange(location: match.range.location, length: 0))
            let line = nsSource.substring(with: lineRange)
            let localLocation = match.range.location - lineRange.location
            let suffix = (line as NSString).substring(from: min((line as NSString).length, localLocation + match.range.length))
            if suffix.hasPrefix(":") { return nil }
            let identifier = nsSource.substring(with: match.range(at: 1))
            guard let content = definitions[identifier], !content.isEmpty else { return nil }
            return MarkdownFootnoteReference(
                identifier: identifier,
                range: match.range,
                labelRange: match.range(at: 1),
                content: content
            )
        }
    }

    public static func callouts(in source: String) -> [MarkdownCalloutBlock] {
        let nsSource = source as NSString
        let headers = matches(#"(?m)^(\s*>\s*)\[!([^\]\n]+)\]([+-])?[ \t]*(.*)$"#, in: source)
        return headers.map { header in
            var blockEnd = NSMaxRange(nsSource.lineRange(for: header.range))
            var cursor = blockEnd
            var markers = [header.range(at: 1)]

            while cursor < nsSource.length {
                let lineRange = nsSource.lineRange(for: NSRange(location: cursor, length: 0))
                let line = nsSource.substring(with: lineRange)
                guard let marker = firstMatch(#"^\s*>\s?"#, in: line) else { break }
                markers.append(NSRange(location: lineRange.location + marker.range.location, length: marker.range.length))
                blockEnd = NSMaxRange(lineRange)
                cursor = blockEnd
            }

            let foldMarkerRange = header.range(at: 3).length == 0 ? nil : header.range(at: 3)
            let foldState: CalloutFoldState = switch foldMarkerRange.map({ nsSource.substring(with: $0) }) {
            case "+": .expanded
            case "-": .collapsed
            case nil: .fixed
            default: .fixed
            }

            return MarkdownCalloutBlock(
                kind: nsSource.substring(with: header.range(at: 2)).lowercased(),
                foldState: foldState,
                foldMarkerRange: foldMarkerRange,
                blockRange: NSRange(location: header.range.location, length: blockEnd - header.range.location),
                headerRange: header.range,
                kindRange: header.range(at: 2),
                markerRanges: markers
            )
        }
    }

    private static func matches(_ pattern: String, in source: String) -> [NSTextCheckingResult] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return expression.matches(in: source, range: NSRange(location: 0, length: source.utf16.count))
    }

    private static func firstMatch(_ pattern: String, in source: String) -> NSTextCheckingResult? {
        matches(pattern, in: source).first
    }
}
