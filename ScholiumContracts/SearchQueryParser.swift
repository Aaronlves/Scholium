import Foundation

public enum SearchLexicalField: String, Codable, CaseIterable, Hashable, Sendable {
    case title
    case alias
    case heading
    case body
    case author
    case year
    case tag
    case footnote
    case path
}

public enum SearchStructuredField: String, Codable, CaseIterable, Hashable, Sendable {
    case callout
    case has
}

public enum SearchLexicalValue: Codable, Hashable, Sendable {
    case term(String)
    case phrase(String)
    case prefix(String)

    public var text: String {
        switch self {
        case .term(let value), .phrase(let value), .prefix(let value): value
        }
    }

    public var isPrefix: Bool {
        if case .prefix = self { return true }
        return false
    }
}

public struct SearchLexicalClause: Codable, Hashable, Sendable {
    public let field: SearchLexicalField?
    public let value: SearchLexicalValue
    public let excluded: Bool
    public let sourceRange: Range<Int>

    public init(
        field: SearchLexicalField?,
        value: SearchLexicalValue,
        excluded: Bool,
        sourceRange: Range<Int>
    ) {
        self.field = field
        self.value = value
        self.excluded = excluded
        self.sourceRange = sourceRange
    }
}

public struct SearchStructuredClause: Codable, Hashable, Sendable {
    public let field: SearchStructuredField
    public let value: String
    public let excluded: Bool
    public let sourceRange: Range<Int>

    public init(
        field: SearchStructuredField,
        value: String,
        excluded: Bool,
        sourceRange: Range<Int>
    ) {
        self.field = field
        self.value = value
        self.excluded = excluded
        self.sourceRange = sourceRange
    }
}

public enum SearchClause: Codable, Hashable, Sendable {
    case lexical(SearchLexicalClause)
    case structured(SearchStructuredClause)
}

public struct SearchQueryAST: Codable, Hashable, Sendable {
    public let clauses: [SearchClause]
    public let identityNeedle: String?

    public init(clauses: [SearchClause], identityNeedle: String?) {
        self.clauses = clauses
        self.identityNeedle = identityNeedle
    }

    public var positiveLexicalClauses: [SearchLexicalClause] {
        clauses.compactMap {
            guard case .lexical(let clause) = $0, !clause.excluded else { return nil }
            return clause
        }
    }

    public var firstPositiveLexicalClause: SearchLexicalClause? {
        positiveLexicalClauses.first
    }

    public var isFilterOnly: Bool {
        !clauses.isEmpty && positiveLexicalClauses.isEmpty
            && clauses.allSatisfy {
                if case .structured = $0 { return true }
                return false
            }
    }

    /// The only query shape allowed to request direct graph neighbors.
    public var relatedIdentityNeedle: String? {
        guard clauses.count == 1,
              case .lexical(let clause) = clauses[0],
              clause.field == nil,
              !clause.excluded,
              !clause.value.isPrefix else { return nil }
        return clause.value.text
    }
}

public struct SearchQueryParseResult: Codable, Hashable, Sendable {
    public let ast: SearchQueryAST?
    public let diagnostics: [SearchQueryDiagnostic]

    public init(ast: SearchQueryAST?, diagnostics: [SearchQueryDiagnostic]) {
        self.ast = ast
        self.diagnostics = diagnostics
    }

    public var isValid: Bool { ast != nil && diagnostics.isEmpty }
}

public enum SearchQueryParser {
    private struct Token {
        let raw: String
        let range: Range<Int>
    }

    private static let removedFields: Set<String> = ["vault", "role", "metadata", "status"]
    private static let calloutValues = Set(CalloutSemanticRole.allCases.map(\.rawValue))

    public static func parse(_ raw: String) -> SearchQueryParseResult {
        let tokenized = tokenize(raw)
        guard tokenized.diagnostics.isEmpty else {
            return SearchQueryParseResult(ast: nil, diagnostics: tokenized.diagnostics)
        }
        guard !tokenized.tokens.isEmpty else {
            return SearchQueryParseResult(
                ast: SearchQueryAST(clauses: [], identityNeedle: nil),
                diagnostics: []
            )
        }

        var clauses: [SearchClause] = []
        var diagnostics: [SearchQueryDiagnostic] = []
        for token in tokenized.tokens {
            switch parse(token) {
            case .success(let clause): clauses.append(clause)
            case .failure(let diagnostic): diagnostics.append(diagnostic)
            }
        }
        if !diagnostics.isEmpty {
            return SearchQueryParseResult(ast: nil, diagnostics: diagnostics)
        }

        let hasPositiveLexical = clauses.contains {
            if case .lexical(let clause) = $0 { return !clause.excluded }
            return false
        }
        let hasStructured = clauses.contains {
            if case .structured = $0 { return true }
            return false
        }
        if !hasPositiveLexical && !hasStructured {
            let range = tokenized.tokens.first?.range ?? 0..<max(0, raw.utf16.count)
            return SearchQueryParseResult(ast: nil, diagnostics: [
                SearchQueryDiagnostic(
                    code: .onlyExcludedFreeText,
                    message: "Add a positive term or a structured callout or broken-link condition.",
                    utf16LowerBound: range.lowerBound,
                    utf16UpperBound: range.upperBound
                ),
            ])
        }

        return SearchQueryParseResult(
            ast: SearchQueryAST(
                clauses: clauses,
                identityNeedle: identityNeedle(for: clauses)
            ),
            diagnostics: []
        )
    }

    private static func parse(_ token: Token) -> Result<SearchClause, SearchQueryDiagnostic> {
        var raw = token.raw
        let excluded = raw.hasPrefix("-")
        if excluded { raw.removeFirst() }
        guard !raw.isEmpty else {
            return .failure(diagnostic(.emptyClause, "A minus sign must be followed by a clause.", token))
        }
        if raw.caseInsensitiveCompare("OR") == .orderedSame
            || raw.caseInsensitiveCompare("NEAR") == .orderedSame
            || raw.contains("(") || raw.contains(")") || raw.contains("|") {
            return .failure(diagnostic(
                .unsupportedSyntax,
                "OR, NEAR, grouping, and alternate-expression syntax are not supported.",
                token
            ))
        }
        if raw.hasSuffix("~")
            || raw.contains("..")
            || (raw.count > 1 && raw.hasPrefix("/") && raw.hasSuffix("/")) {
            return .failure(diagnostic(
                .unsupportedSyntax,
                "Regular-expression, fuzzy, and range syntax are not supported.",
                token
            ))
        }

        let split = splitField(raw)
        if let fieldName = split.field {
            let field = fieldName.lowercased()
            guard !split.value.isEmpty else {
                return .failure(diagnostic(
                    .missingFieldValue,
                    "The \(field) field requires a value.",
                    token
                ))
            }
            if removedFields.contains(field) {
                let message = field == "status"
                    ? "The status: field is unsupported because status is not a Scholium property."
                    : "The \(field): field was removed in Search v4. Choose scope in the visible interface or CLI option."
                return .failure(SearchQueryDiagnostic(
                    code: .removedField,
                    message: message,
                    utf16LowerBound: token.range.lowerBound,
                    utf16UpperBound: token.range.upperBound,
                    needsEditing: true
                ))
            }
            if let lexicalField = SearchLexicalField(rawValue: field) {
                return lexicalClause(
                    field: lexicalField,
                    rawValue: split.value,
                    excluded: excluded,
                    token: token
                ).map(SearchClause.lexical)
            }
            if let structuredField = SearchStructuredField(rawValue: field) {
                return structuredClause(
                    field: structuredField,
                    rawValue: split.value,
                    excluded: excluded,
                    token: token
                ).map(SearchClause.structured)
            }
            return .failure(diagnostic(.unknownField, "Unknown Search field \(field):.", token))
        }

        return lexicalClause(
            field: nil,
            rawValue: raw,
            excluded: excluded,
            token: token
        ).map(SearchClause.lexical)
    }

    private static func lexicalClause(
        field: SearchLexicalField?,
        rawValue: String,
        excluded: Bool,
        token: Token
    ) -> Result<SearchLexicalClause, SearchQueryDiagnostic> {
        let value: DecodedValue
        switch decodeValue(rawValue, token: token) {
        case .success(let decodedValue):
            value = decodedValue
        case .failure(let error):
            return .failure(error)
        }
        let normalized = SearchTextNormalization.normalize(value.text)
        guard !normalized.isEmpty else {
            return .failure(diagnostic(.emptyClause, "A Search clause cannot be empty.", token))
        }
        let lexicalValue: SearchLexicalValue
        if value.quoted {
            guard !value.hadTrailingAsterisk else {
                return .failure(diagnostic(
                    .invalidPrefix,
                    "A quoted phrase cannot also be a prefix query.",
                    token
                ))
            }
            lexicalValue = .phrase(normalized)
        } else if value.hadTrailingAsterisk {
            if SearchTokenization.containsCJK(normalized) {
                return .failure(diagnostic(
                    .cjkPrefixUnsupported,
                    "CJK clauses do not use *. Continuous character and bigram matching is automatic.",
                    token
                ))
            }
            let scalarCount = normalized.unicodeScalars.count
            guard scalarCount >= 2 else {
                return .failure(diagnostic(
                    .invalidPrefix,
                    "A prefix requires at least two non-CJK Unicode scalars before *.",
                    token
                ))
            }
            lexicalValue = .prefix(normalized)
        } else {
            lexicalValue = .term(normalized)
        }
        return .success(SearchLexicalClause(
            field: field,
            value: lexicalValue,
            excluded: excluded,
            sourceRange: token.range
        ))
    }

    private static func structuredClause(
        field: SearchStructuredField,
        rawValue: String,
        excluded: Bool,
        token: Token
    ) -> Result<SearchStructuredClause, SearchQueryDiagnostic> {
        let value: DecodedValue
        switch decodeValue(rawValue, token: token) {
        case .success(let decodedValue):
            value = decodedValue
        case .failure(let error):
            return .failure(error)
        }
        guard !value.quoted, !value.hadTrailingAsterisk else {
            return .failure(diagnostic(
                .unsupportedSyntax,
                "Structured Search values are canonical identifiers, not phrases or prefixes.",
                token
            ))
        }
        let normalized = value.text.lowercased()
        let allowed: Set<String> = switch field {
        case .callout: calloutValues
        case .has: ["broken-link"]
        }
        guard allowed.contains(normalized) else {
            return .failure(diagnostic(
                .unknownStructuredValue,
                "Unknown canonical \(field.rawValue) value \(value.text).",
                token
            ))
        }
        return .success(SearchStructuredClause(
            field: field,
            value: normalized,
            excluded: excluded,
            sourceRange: token.range
        ))
    }

    private struct DecodedValue {
        let text: String
        let quoted: Bool
        let hadTrailingAsterisk: Bool
    }

    private static func decodeValue(
        _ raw: String,
        token: Token
    ) -> Result<DecodedValue, SearchQueryDiagnostic> {
        if raw.hasPrefix("\"") {
            if raw.hasSuffix("\"*") {
                return .failure(diagnostic(
                    .invalidPrefix,
                    "A quoted phrase cannot also be a prefix query.",
                    token
                ))
            }
            guard raw.count >= 2, raw.hasSuffix("\"") else {
                return .failure(diagnostic(.unclosedPhrase, "The quoted phrase is not closed.", token))
            }
            var result = ""
            var escaped = false
            let inner = raw.dropFirst().dropLast()
            for character in inner {
                if escaped {
                    guard character == "\"" || character == "\\" else {
                        return .failure(diagnostic(
                            .invalidEscape,
                            "Only \\\" and \\\\ are valid Search phrase escapes.",
                            token
                        ))
                    }
                    result.append(character)
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else {
                    result.append(character)
                }
            }
            if escaped {
                return .failure(diagnostic(.invalidEscape, "A phrase cannot end with an escape marker.", token))
            }
            return .success(DecodedValue(text: result, quoted: true, hadTrailingAsterisk: false))
        }
        if raw.contains("\"") {
            return .failure(diagnostic(
                .unsupportedSyntax,
                "A quote must enclose the complete value of one Search clause.",
                token
            ))
        }
        let stars = raw.filter { $0 == "*" }.count
        guard stars == 0 || (stars == 1 && raw.hasSuffix("*")) else {
            return .failure(diagnostic(
                .invalidPrefix,
                "* is supported only once at the end of an unquoted term.",
                token
            ))
        }
        let value = raw.hasSuffix("*") ? String(raw.dropLast()) : raw
        return .success(DecodedValue(
            text: value,
            quoted: false,
            hadTrailingAsterisk: raw.hasSuffix("*")
        ))
    }

    private static func splitField(_ raw: String) -> (field: String?, value: String) {
        guard let colon = raw.firstIndex(of: ":") else { return (nil, raw) }
        let field = String(raw[..<colon])
        guard !field.isEmpty else { return (nil, raw) }
        return (field, String(raw[raw.index(after: colon)...]))
    }

    private static func identityNeedle(for clauses: [SearchClause]) -> String? {
        var unfieldedValues: [String] = []
        var fieldedIdentityValues: [String] = []
        for clause in clauses {
            guard case .lexical(let lexical) = clause else { continue }
            guard !lexical.excluded else { continue }
            guard !lexical.value.isPrefix else { return nil }
            switch lexical.field {
            case nil:
                unfieldedValues.append(lexical.value.text)
            case .title, .alias, .path:
                fieldedIdentityValues.append(lexical.value.text)
            case .heading, .body, .author, .year, .tag, .footnote:
                continue
            }
        }
        if !unfieldedValues.isEmpty {
            return SearchTextNormalization.normalize(unfieldedValues.joined(separator: " "))
        }
        guard fieldedIdentityValues.count == 1 else { return nil }
        return SearchTextNormalization.normalize(fieldedIdentityValues[0])
    }

    private static func diagnostic(
        _ code: SearchQueryDiagnosticCode,
        _ message: String,
        _ token: Token
    ) -> SearchQueryDiagnostic {
        SearchQueryDiagnostic(
            code: code,
            message: message,
            utf16LowerBound: token.range.lowerBound,
            utf16UpperBound: token.range.upperBound
        )
    }

    private static func tokenize(_ raw: String) -> (
        tokens: [Token],
        diagnostics: [SearchQueryDiagnostic]
    ) {
        var tokens: [Token] = []
        var index = raw.startIndex
        while index < raw.endIndex {
            while index < raw.endIndex, raw[index].isWhitespace {
                index = raw.index(after: index)
            }
            guard index < raw.endIndex else { break }
            let start = index
            var quoted = false
            var escaped = false
            while index < raw.endIndex {
                let character = raw[index]
                if quoted {
                    if escaped {
                        escaped = false
                    } else if character == "\\" {
                        escaped = true
                    } else if character == "\"" {
                        quoted = false
                    }
                } else if character == "\"" {
                    quoted = true
                } else if character.isWhitespace {
                    break
                }
                index = raw.index(after: index)
            }
            let end = index
            let range = start.utf16Offset(in: raw)..<end.utf16Offset(in: raw)
            if quoted {
                return ([], [SearchQueryDiagnostic(
                    code: .unclosedPhrase,
                    message: "The quoted phrase is not closed.",
                    utf16LowerBound: range.lowerBound,
                    utf16UpperBound: range.upperBound
                )])
            }
            tokens.append(Token(raw: String(raw[start..<end]), range: range))
        }
        return (tokens, [])
    }
}

public enum SearchTextNormalization {
    public static func normalize(_ value: String) -> String {
        let folded = value.precomposedStringWithCanonicalMapping.folding(
            options: [.caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        var result = ""
        var pendingSpace = false
        for character in folded {
            if character.isWhitespace {
                pendingSpace = !result.isEmpty
            } else {
                if pendingSpace { result.append(" ") }
                result.append(character)
                pendingSpace = false
            }
        }
        return result.precomposedStringWithCanonicalMapping
    }

    /// Deterministic comparison form corresponding to FTS5
    /// `unicode61 remove_diacritics 2`. Exact identity keys deliberately keep
    /// using `normalize(_:)`, which preserves diacritics and punctuation.
    public static func lexicalNormalize(_ value: String) -> String {
        let folded = value.precomposedStringWithCanonicalMapping.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        var result = ""
        var pendingSpace = false
        for character in folded {
            if character.isWhitespace {
                pendingSpace = !result.isEmpty
            } else {
                if pendingSpace { result.append(" ") }
                result.append(character)
                pendingSpace = false
            }
        }
        return result.precomposedStringWithCanonicalMapping
    }

    /// Maps a range in `normalize(_:)` output back to the corresponding range
    /// in the original UTF-16 string. This is used for presentation only; the
    /// authoritative Markdown mapping remains the projection segment map.
    public static func originalUTF16Range(
        in value: String,
        forNormalizedUTF16Range requestedRange: Range<Int>
    ) -> Range<Int>? {
        mappedOriginalUTF16Range(
            in: value,
            requestedRange: requestedRange,
            normalizer: normalize
        )
    }

    /// Maps a range in `lexicalNormalize(_:)` output back to the exact
    /// displayed UTF-16 range used to build a Search snippet.
    public static func originalUTF16RangeForLexicalNormalization(
        in value: String,
        requestedRange: Range<Int>
    ) -> Range<Int>? {
        mappedOriginalUTF16Range(
            in: value,
            requestedRange: requestedRange,
            normalizer: lexicalNormalize
        )
    }

    private static func mappedOriginalUTF16Range(
        in value: String,
        requestedRange: Range<Int>,
        normalizer: (String) -> String
    ) -> Range<Int>? {
        struct Offset {
            let normalized: Range<Int>
            let original: Range<Int>
        }

        var normalized = ""
        var normalizedUTF16Count = 0
        var offsets: [Offset] = []
        var originalCursor = 0
        var pendingWhitespace: Range<Int>?
        for character in value {
            let originalLength = String(character).utf16.count
            let originalRange = originalCursor..<(originalCursor + originalLength)
            originalCursor += originalLength
            if character.isWhitespace {
                guard !normalized.isEmpty else { continue }
                if let existing = pendingWhitespace {
                    // Keep all collapsed source whitespace in the one
                    // normalized-space mapping.
                    pendingWhitespace = existing.lowerBound..<originalRange.upperBound
                } else {
                    pendingWhitespace = originalRange
                }
                continue
            }
            if let pendingWhitespace {
                let lower = normalizedUTF16Count
                normalized.append(" ")
                normalizedUTF16Count += 1
                offsets.append(Offset(
                    normalized: lower..<(lower + 1),
                    original: pendingWhitespace
                ))
            }
            pendingWhitespace = nil
            let folded = normalizer(String(character))
            let lower = normalizedUTF16Count
            normalized += folded
            normalizedUTF16Count += folded.utf16.count
            offsets.append(Offset(
                normalized: lower..<normalizedUTF16Count,
                original: originalRange
            ))
        }

        guard normalized == normalizer(value) else { return nil }
        let overlapping = offsets.filter {
            $0.normalized.lowerBound < requestedRange.upperBound
                && $0.normalized.upperBound > requestedRange.lowerBound
        }
        guard let first = overlapping.first, let last = overlapping.last else { return nil }
        return first.original.lowerBound..<last.original.upperBound
    }
}

public enum SearchTokenization {
    public static func indexText(_ value: String) -> String {
        let normalized = SearchTextNormalization.normalize(value)
        guard containsCJK(normalized) else { return normalized }
        let additions = indexScriptTokens(in: normalized)
        guard !additions.isEmpty else { return normalized }
        return normalized + " " + additions.joined(separator: " ")
    }

    public static func queryTokens(for value: String) -> [String] {
        let normalized = SearchTextNormalization.normalize(value)
        var result: [String] = []
        var nonCJK = ""
        func finishNonCJK() {
            let value = nonCJK.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { result.append(value) }
            nonCJK = ""
        }
        var cjk = ""
        func finishCJK() {
            if !cjk.isEmpty { result.append(contentsOf: tokens(forCJKRun: cjk)) }
            cjk = ""
        }
        for scalar in normalized.unicodeScalars {
            if isCJK(scalar) {
                finishNonCJK()
                cjk.unicodeScalars.append(scalar)
            } else {
                finishCJK()
                nonCJK.unicodeScalars.append(scalar)
            }
        }
        finishCJK()
        finishNonCJK()
        return result
    }

    public static func containsCJK(_ value: String) -> Bool {
        value.unicodeScalars.contains(where: isCJK)
    }

    public static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x11FF,
             0x2E80...0x2FFF,
             0x3040...0x30FF,
             0x3100...0x312F,
             0x3130...0x318F,
             0x31A0...0x31BF,
             0x31F0...0x31FF,
             0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xA960...0xA97F,
             0xAC00...0xD7FF,
             0xF900...0xFAFF,
             0xFF65...0xFF9F,
             0x20000...0x2FA1F: true
        default: false
        }
    }

    private static func cjkRuns(in value: String) -> [String] {
        var runs: [String] = []
        var current = ""
        for scalar in value.unicodeScalars {
            if isCJK(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                runs.append(current)
                current = ""
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    private static func indexScriptTokens(in value: String) -> [String] {
        var result: [String] = []
        var current = ""
        var currentIsCJK: Bool?
        func finish() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                current = ""
                currentIsCJK = nil
                return
            }
            if currentIsCJK == true {
                result.append(contentsOf: indexTokens(forCJKRun: trimmed))
            } else {
                result.append(trimmed)
            }
            current = ""
            currentIsCJK = nil
        }
        for scalar in value.unicodeScalars {
            let scalarIsCJK = isCJK(scalar)
            if let currentIsCJK, currentIsCJK != scalarIsCJK {
                finish()
            }
            currentIsCJK = scalarIsCJK
            current.unicodeScalars.append(scalar)
        }
        finish()
        return result
    }

    private static func tokens(forCJKRun run: String) -> [String] {
        let scalars = run.unicodeScalars.map(String.init)
        guard scalars.count > 1 else { return scalars }
        return (0..<(scalars.count - 1)).map { scalars[$0] + scalars[$0 + 1] }
    }

    private static func indexTokens(forCJKRun run: String) -> [String] {
        let scalars = run.unicodeScalars.map(String.init)
        guard scalars.count > 1 else { return scalars }
        return scalars + (0..<(scalars.count - 1)).map {
            scalars[$0] + scalars[$0 + 1]
        }
    }
}
