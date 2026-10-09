import Foundation

public struct SearchCompletion: Codable, Hashable, Identifiable, Sendable {
    public let replacementText: String
    public let displayText: String
    public let detail: String
    public let caretUTF16: Int?

    public var id: String { replacementText }

    public init(replacementText: String, displayText: String, detail: String, caretUTF16: Int? = nil) {
        self.replacementText = replacementText
        self.displayText = displayText
        self.detail = detail
        self.caretUTF16 = caretUTF16
    }
}

/// The lexical fragment currently being completed. It is deliberately smaller
/// than a Search query: the parser remains the authority for the full query,
/// while an index may answer only for this one visible token.
public struct SearchCompletionLookup: Codable, Hashable, Sendable {
    public let partial: String
    public let field: SearchLexicalField?

    public init(partial: String, field: SearchLexicalField? = nil) {
        self.partial = partial
        self.field = field
    }

    public var normalizedPartial: String {
        SearchTextNormalization.lexicalNormalize(partial)
    }
}

/// One authorized lexical value supplied by the active Search generation.
/// It is a disposable retrieval projection, not a second source or query
/// authority.
public struct SearchCompletionTerm: Codable, Hashable, Sendable, Identifiable {
    public let text: String
    public let fields: [SearchLexicalField]
    public let occurrenceCount: Int

    public var id: String { SearchTextNormalization.lexicalNormalize(text) }

    public init(
        text: String,
        fields: [SearchLexicalField] = [],
        occurrenceCount: Int = 1
    ) {
        self.text = text
        self.fields = fields.sorted { $0.rawValue < $1.rawValue }
        self.occurrenceCount = max(1, occurrenceCount)
    }
}

/// Optional scope-first candidates supplied by Application. The static
/// capability table remains the grammar authority; this context can only
/// provide values for fields already typed as Property or Note identity, plus
/// lexical terms returned by the authorized Search index.
public struct SearchCompletionContext: Codable, Hashable, Sendable {
    public let propertyKeys: [String]
    public let propertyValues: [String: [String]]
    public let noteIdentities: [String]
    public let lexicalTerms: [SearchCompletionTerm]

    public init(
        propertyKeys: [String] = [],
        propertyValues: [String: [String]] = [:],
        noteIdentities: [String] = [],
        lexicalTerms: [SearchCompletionTerm] = []
    ) {
        self.propertyKeys = propertyKeys
        self.propertyValues = propertyValues
        self.noteIdentities = noteIdentities
        self.lexicalTerms = lexicalTerms
    }

    public static let empty = SearchCompletionContext()
}

public extension SearchCapabilities {
    /// Returns the lexical lookup owned by the active token, if the token is
    /// eligible for corpus-backed completion. Operators, properties,
    /// structured fields and an already explicit prefix do not request a
    /// lexical vocabulary scan.
    func lexicalCompletionLookup(
        for rawQuery: String,
        scope: SearchPresentationScope,
        provider: SearchProvider = .note,
        caretUTF16: Int? = nil
    ) -> SearchCompletionLookup? {
        let caret = caretUTF16 ?? rawQuery.utf16.count
        guard !rawQuery.isEmpty, caret >= 0, caret <= rawQuery.utf16.count
        else { return nil }
        let tokens = SearchQueryParser.completionTokens(rawQuery)
        let active = tokens.first {
            $0.range.lowerBound < caret
                && $0.range.upperBound >= caret
                && !["(", ")", "-"].contains($0.raw)
        }
        let start = active?.range.lowerBound ?? caret
        let previous = tokens.filter { $0.range.upperBound <= start }
        var groups: [String?] = []
        for (index, item) in previous.enumerated() {
            if item.raw == "(" {
                let field =
                    index > 0 && previous[index - 1].raw.hasSuffix(":")
                    ? String(previous[index - 1].raw.dropLast()).lowercased()
                    : nil
                groups.append(field ?? groups.last.flatMap { $0 })
            } else if item.raw == ")", !groups.isEmpty {
                groups.removeLast()
            }
        }
        let inParagraph = groups.contains { $0 == "paragraph" }
        let inherited = inParagraph ? nil : groups.last.flatMap { $0 }
        if let inherited {
            guard let capability = fields(for: provider, scope: scope).first(where: { $0.name == inherited }),
                capability.valueKind == .lexical
            else { return nil }
        }

        guard let tokenPrefixRange = Range(NSRange(location: start, length: caret - start), in: rawQuery)
        else { return nil }
        let token = String(rawQuery[tokenPrefixRange])
        let partial: String
        let field: SearchLexicalField?
        if !token.hasPrefix("\""), let colon = token.firstIndex(of: ":") {
            guard !inParagraph else { return nil }
            let rawField = String(token[..<colon]).lowercased()
            guard let lexicalField = SearchLexicalField(rawValue: rawField),
                fields(for: provider, scope: scope).contains(where: {
                    $0.name == rawField && $0.valueKind == .lexical
                })
            else { return nil }
            partial = String(token[token.index(after: colon)...])
            field = lexicalField
        } else {
            partial = token
            field = inherited.flatMap(SearchLexicalField.init(rawValue:))
        }

        guard let value = Self.lexicalCompletionValue(partial) else { return nil }
        let normalized = SearchTextNormalization.lexicalNormalize(value.text)
        guard !normalized.isEmpty,
            value.quoted || (!partial.hasSuffix("*") && !["AND", "OR", "NOT"].contains(partial))
        else { return nil }
        let containsCJK = value.text.unicodeScalars.contains(where: SearchTokenization.isCJK)
        guard containsCJK || normalized.utf8.count >= 2 else { return nil }
        return SearchCompletionLookup(partial: value.text, field: field)
    }

    /// Completion shares the parser's lexer and replaces only the active token (or field/key),
    /// preserving all following query source and returning the resulting native caret position.
    func completions(
        for rawQuery: String, scope: SearchPresentationScope, provider: SearchProvider = .note,
        context: SearchCompletionContext = .empty, limit: Int = 8, caretUTF16: Int? = nil
    ) -> [SearchCompletion] {
        let caret = caretUTF16 ?? rawQuery.utf16.count
        guard !rawQuery.isEmpty, limit > 0, caret >= 0, caret <= rawQuery.utf16.count,
            let prefixRange = Range(NSRange(location: 0, length: caret), in: rawQuery)
        else { return [] }
        let beforeCaret = String(rawQuery[prefixRange])
        let tokens = SearchQueryParser.completionTokens(rawQuery)
        let active = tokens.first { $0.range.lowerBound < caret && $0.range.upperBound >= caret && !["(", ")", "-"].contains($0.raw) }
        let start = active?.range.lowerBound ?? caret
        var end = active?.range.upperBound ?? caret
        if let active, !active.raw.hasPrefix("\""), let colon = active.raw.firstIndex(of: ":"), start + colon.utf16Offset(in: active.raw) >= caret {
            end = start + colon.utf16Offset(in: active.raw) + 1
        } else if let active, active.raw.hasPrefix("property:"), let equal = SearchQueryParser.propertyEqualityIndex(in: active.raw),
            start + equal.utf16Offset(in: active.raw) >= caret
        {
            end = start + equal.utf16Offset(in: active.raw)
        }
        guard let tokenPrefixRange = Range(NSRange(location: start, length: caret - start), in: rawQuery),
            let replacementRange = Range(NSRange(location: start, length: end - start), in: rawQuery)
        else { return [] }
        let token = String(rawQuery[tokenPrefixRange])
        var groups: [String?] = []
        let previous = tokens.filter { $0.range.upperBound <= start }
        for (index, item) in previous.enumerated() {
            if item.raw == "(" {
                let field = index > 0 && previous[index - 1].raw.hasSuffix(":") ? String(previous[index - 1].raw.dropLast()).lowercased() : nil
                groups.append(field ?? groups.last.flatMap { $0 })
            } else if item.raw == ")", !groups.isEmpty {
                groups.removeLast()
            }
        }
        let inParagraph = groups.contains { $0 == "paragraph" }
        let inherited = inParagraph ? nil : groups.last.flatMap { $0 }
        if let inherited {
            guard let field = fields(for: provider, scope: scope).first(where: { $0.name == inherited }),
                field.name != "kind", field.valueKind == .lexical || field.valueKind == .canonical
            else { return [] }
        }
        let synthetic = inherited.map { $0 + ":" + token } ?? token
        let atomics = atomicCompletions(
            for: synthetic, scope: scope, provider: provider, context: context, limit: limit, lexicalOnly: inParagraph)
        var replacements = atomics.map { item -> (String, String) in
            let replacement = inherited.map { String(item.replacementText.dropFirst($0.count + 1)) } ?? item.replacementText
            return (replacement, item.detail)
        }
        if !token.contains(":"), !token.hasPrefix("\"") {
            for operation in ["AND", "OR", "NOT"] where operation.hasPrefix(token) && (inherited == nil || token == token.uppercased()) {
                let trial = String(rawQuery[..<replacementRange.lowerBound]) + operation + " placeholder"
                if SearchQueryParser.parse(trial + String(repeating: ")", count: groups.count)).isValid {
                    replacements.append((operation + " ", "Boolean operator"))
                }
            }
        }
        if token.isEmpty, !groups.isEmpty, SearchQueryParser.parse(beforeCaret + String(repeating: ")", count: groups.count)).isValid {
            replacements.append((")", "Close the current group"))
        }
        return replacements.prefix(limit).map { replacement, detail in
            let prefix = String(rawQuery[..<replacementRange.lowerBound])
            return SearchCompletion(
                replacementText: prefix + replacement + rawQuery[replacementRange.upperBound...],
                displayText: replacement, detail: detail, caretUTF16: prefix.utf16.count + replacement.utf16.count)
        }
    }

    /// Bounded completion derived only from the current static capability
    /// table. It edits plain query text and never creates hidden query state.
    private func atomicCompletions(
        for rawQuery: String,
        scope: SearchPresentationScope,
        provider: SearchProvider = .note,
        context: SearchCompletionContext = .empty,
        limit: Int = 8,
        lexicalOnly: Bool = false
    ) -> [SearchCompletion] {
        guard limit > 0,
            let tokenRange = Self.trailingTokenRange(in: rawQuery)
        else {
            return []
        }
        let token = String(rawQuery[tokenRange])
        guard !token.isEmpty else { return [] }
        let prefix = String(rawQuery[..<tokenRange.lowerBound])
        let fields = fields(for: provider, scope: scope)
        guard !fields.isEmpty else { return [] }

        var candidates: [(replacement: String, display: String, detail: String)]
        if lexicalOnly || token.hasPrefix("\"") {
            candidates = Self.lexicalTermCandidates(matching: token, field: nil, context: context)
        } else if let colon = token.firstIndex(of: ":") {
            let rawField = String(token[..<colon]).lowercased()
            let rawPartialValue = String(token[token.index(after: colon)...])
            let partialValue = rawPartialValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"")).lowercased()
            guard
                let field = fields.first(where: {
                    $0.name == rawField
                })
            else { return [] }
            if field.valueKind == .property,
                let separator = SearchQueryParser.propertyEqualityIndex(in: rawPartialValue)
            {
                let keyQuery = "property:" + String(rawPartialValue[..<separator])
                guard let ast = SearchQueryParser.parse(keyQuery).ast,
                    ast.clauses.count == 1, case .property(let clause) = ast.clauses[0]
                else { return [] }
                let key = clause.key
                let valuePrefix = String(rawPartialValue[rawPartialValue.index(after: separator)...]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    .lowercased()
                let matches = Self.uniqueSorted(context.propertyValues[key] ?? [])
                    .filter { $0.lowercased().hasPrefix(valuePrefix) }
                return matches.prefix(limit).map { value in
                    let replacement = "property:\(Self.propertyKey(key))=\(Self.queryValue(value))"
                    return SearchCompletion(
                        replacementText: prefix + replacement,
                        displayText: replacement,
                        detail: "Controlled value for \(key)"
                    )
                }
            }
            let allowedValues: [String]
            switch field.valueKind {
            case .property: allowedValues = context.propertyKeys
            case .noteIdentity: allowedValues = context.noteIdentities
            case .canonical, .lexical: allowedValues = field.allowedValues
            }
            candidates = Self.uniqueSorted(allowedValues).filter {
                $0.lowercased().hasPrefix(partialValue)
            }.map {
                let value = field.valueKind == .property ? Self.propertyKey($0) : Self.queryValue($0)
                let detail =
                    switch field.valueKind {
                    case .property: "Observed YAML key in the authorized scope"
                    case .noteIdentity: "Exact Note identity in the authorized scope"
                    case .canonical: "Canonical \(field.name) value"
                    case .lexical: "\(field.name) value"
                    }
                return ("\(field.name):\(value)", "\(field.name):\(value)", detail)
            }
            if field.valueKind == .lexical,
                let lexicalField = SearchLexicalField(rawValue: field.name)
            {
                candidates.append(
                    contentsOf: Self.lexicalTermCandidates(
                        matching: rawPartialValue,
                        field: lexicalField,
                        context: context
                    ))
            }
        } else {
            let partial = token.lowercased()
            candidates = fields.filter {
                $0.name.hasPrefix(partial)
            }.map {
                ("\($0.name):" + ($0.name == "paragraph" ? "(" : ""), "\($0.name):", Self.detail(for: $0))
            }
            candidates.append(
                contentsOf: Self.lexicalTermCandidates(
                    matching: token,
                    field: nil,
                    context: context
                ))
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
        case .property: "Find a top-level property or exact scalar/list-member text"
        case .noteIdentity: "Resolve one exact Note identity"
        }
    }

    private static func lexicalTermCandidates(
        matching partial: String,
        field: SearchLexicalField?,
        context: SearchCompletionContext
    ) -> [(replacement: String, display: String, detail: String)] {
        guard let value = lexicalCompletionValue(partial),
            value.quoted || (!partial.hasSuffix("*") && !["AND", "OR", "NOT"].contains(partial))
        else { return [] }
        let normalizedPartial = SearchTextNormalization.lexicalNormalize(value.text)
        guard !normalizedPartial.isEmpty else { return [] }
        return context.lexicalTerms
            .filter { term in
                let matchesField =
                    field.map {
                        term.fields.isEmpty || term.fields.contains($0)
                    } ?? true
                return matchesField
                    && SearchTextNormalization.lexicalNormalize(term.text).hasPrefix(normalizedPartial)
            }
            .sorted { lhs, rhs in
                let lhsNormalized = SearchTextNormalization.lexicalNormalize(lhs.text)
                let rhsNormalized = SearchTextNormalization.lexicalNormalize(rhs.text)
                let lhsExact = lhsNormalized == normalizedPartial
                let rhsExact = rhsNormalized == normalizedPartial
                if lhsExact != rhsExact { return lhsExact }
                if lhs.occurrenceCount != rhs.occurrenceCount {
                    return lhs.occurrenceCount > rhs.occurrenceCount
                }
                if lhsNormalized.utf16.count != rhsNormalized.utf16.count {
                    return lhsNormalized.utf16.count < rhsNormalized.utf16.count
                }
                return lhsNormalized < rhsNormalized
            }
            .map { term in
                let literal = queryValue(term.text, forceQuoted: value.quoted)
                let replacement = field.map { "\($0.rawValue):\(literal)" } ?? literal
                return (replacement, replacement, "Search term")
            }
    }

    /// Let the query parser decode escapes and reject malformed literals. The
    /// extra closing quote permits a still-open phrase while the researcher types.
    private static func lexicalCompletionValue(_ raw: String) -> (text: String, quoted: Bool)? {
        guard raw.hasPrefix("\"") else {
            guard !raw.contains("\"") else { return nil }
            return (raw, false)
        }
        let parsed = SearchQueryParser.parse(raw).ast ?? SearchQueryParser.parse(raw + "\"").ast
        guard let parsed, parsed.clauses.count == 1,
            case .lexical(let clause) = parsed.clauses[0], clause.field == nil,
            case .phrase(let value) = clause.value
        else { return nil }
        return (value, true)
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values)).sorted {
            let lhs = SearchTextNormalization.normalize($0)
            let rhs = SearchTextNormalization.normalize($1)
            if lhs != rhs { return lhs < rhs }
            return $0 < $1
        }
    }

    private static func propertyKey(_ key: String) -> String {
        let query = "property:" + key
        if let ast = SearchQueryParser.parse(query).ast, ast.clauses.count == 1,
            case .property(let clause) = ast.clauses[0], clause.key == key,
            clause.value == nil
        {
            return key
        }
        return "\""
            + key.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func queryValue(_ value: String, forceQuoted: Bool = false) -> String {
        guard
            forceQuoted || ["AND", "OR", "NOT", "NEAR"].contains(value) || value.hasPrefix("-")
                || value.contains(where: { $0.isWhitespace || "\"\\():".contains($0) })
        else { return value }
        let escaped =
            value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
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
                if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { quoted = false }
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
