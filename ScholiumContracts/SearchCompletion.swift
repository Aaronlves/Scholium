import Foundation

public struct SearchCompletion: Codable, Hashable, Identifiable, Sendable {
    public let replacementText: String
    public let displayText: String
    public let detail: String

    public var id: String { replacementText }

    public init(replacementText: String, displayText: String, detail: String) {
        self.replacementText = replacementText
        self.displayText = displayText
        self.detail = detail
    }
}

/// Optional scope-first candidates supplied by Application. The static
/// capability table remains the grammar authority; this context can only
/// provide values for fields already typed as Property or Note identity.
public struct SearchCompletionContext: Codable, Hashable, Sendable {
    public let propertyKeys: [String]
    public let noteIdentities: [String]

    public init(
        propertyKeys: [String] = [],
        noteIdentities: [String] = []
    ) {
        self.propertyKeys = propertyKeys
        self.noteIdentities = noteIdentities
    }

    public static let empty = SearchCompletionContext()
}

public extension SearchCapabilities {
    /// Bounded completion derived only from the current static capability
    /// table. It edits plain query text and never creates hidden query state.
    func completions(
        for rawQuery: String,
        context: SearchCompletionContext = .empty,
        limit: Int = 8
    ) -> [SearchCompletion] {
        guard limit > 0,
              let tokenRange = Self.trailingTokenRange(in: rawQuery) else {
            return []
        }
        let token = String(rawQuery[tokenRange])
        guard !token.isEmpty else { return [] }
        let prefix = String(rawQuery[..<tokenRange.lowerBound])
        let provider: SearchProvider = Self.completedTokens(in: prefix).contains {
            $0.caseInsensitiveCompare("kind:record") == .orderedSame
        } ? .record : .note
        guard let capability = capability(for: provider) else { return [] }

        let candidates: [(replacement: String, display: String, detail: String)]
        if let colon = token.firstIndex(of: ":") {
            let rawField = String(token[..<colon]).lowercased()
            let partialValue = String(token[token.index(after: colon)...]).lowercased()
            guard let field = capability.fields.first(where: {
                $0.name == rawField
            }) else { return [] }
            let allowedValues: [String] = switch field.valueKind {
            case .property:
                partialValue.contains("=") ? [] : context.propertyKeys
            case .noteIdentity:
                context.noteIdentities
            case .canonical, .lexical:
                field.allowedValues
            }
            candidates = Self.uniqueSorted(allowedValues).filter {
                $0.lowercased().hasPrefix(partialValue)
            }.map {
                let value = Self.queryValue($0)
                let detail = switch field.valueKind {
                case .property: "Top-level Property key in the authorized scope"
                case .noteIdentity: "Exact Note identity in the authorized scope"
                case .canonical: "Canonical \(field.name) value"
                case .lexical: "\(field.name) value"
                }
                return ("\(field.name):\(value)", "\(field.name):\(value)", detail)
            }
        } else {
            let partial = token.lowercased()
            candidates = capability.fields.filter {
                $0.name.hasPrefix(partial)
            }.map {
                ("\($0.name):", "\($0.name):", Self.detail(for: $0))
            }
        }
        return candidates.prefix(limit).map { candidate in
            SearchCompletion(
                replacementText: prefix + candidate.replacement,
                displayText: candidate.display,
                detail: candidate.detail
            )
        }
    }

    private static func detail(for field: SearchFieldCapability) -> String {
        switch field.valueKind {
        case .lexical: "Search a specific text field"
        case .canonical: "Use a canonical contract value"
        case .property: "Find a top-level YAML key or exact string value"
        case .noteIdentity: "Resolve one exact Note identity"
        }
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values)).sorted {
            let lhs = SearchTextNormalization.normalize($0)
            let rhs = SearchTextNormalization.normalize($1)
            if lhs != rhs { return lhs < rhs }
            return $0 < $1
        }
    }

    private static func queryValue(_ value: String) -> String {
        guard value.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "\\" })
        else { return value }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func completedTokens(in value: String) -> [String] {
        value.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func trailingTokenRange(in value: String) -> Range<String.Index>? {
        guard !value.isEmpty else { return nil }
        var quoted = false
        var escaped = false
        var tokenStart = value.startIndex
        var cursor = value.startIndex
        while cursor < value.endIndex {
            let character = value[cursor]
            if quoted {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { quoted = false }
            } else if character == "\"" {
                quoted = true
            } else if character.isWhitespace {
                tokenStart = value.index(after: cursor)
            }
            cursor = value.index(after: cursor)
        }
        return tokenStart..<value.endIndex
    }
}
