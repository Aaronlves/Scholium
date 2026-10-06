import Foundation

public enum SearchProvider: String, Codable, CaseIterable, Hashable, Sendable {
    case note
}

public enum SearchLexicalField: String, Codable, CaseIterable, Hashable, Sendable {
    case title
    case alias
    case heading
    case summary
    case body
    case author
    case publicationDate = "publication_date"
    case tag = "keyword"
    case footnote
    case linkAnnotation = "link_annotation"
    case path
}

public enum SearchStructuredField: String, Codable, CaseIterable, Hashable, Sendable {
    case callout
    case has
}

public enum SearchLinkDirection: String, Codable, CaseIterable, Hashable, Sendable {
    case fromNote = "from-note"
    case toNote = "to-note"
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

    public var matchKind: SearchLexicalMatchKind {
        switch self {
        case .term: .term
        case .phrase: .phrase
        case .prefix: .prefix
        }
    }
}

public enum SearchLexicalMatchKind: String, Codable, Hashable, Sendable {
    case term
    case phrase
    case prefix
}

public struct SearchLexicalClause: Codable, Hashable, Sendable {
    public let field: SearchLexicalField?
    public let value: SearchLexicalValue
    public let sourceRange: Range<Int>

    public init(
        field: SearchLexicalField?,
        value: SearchLexicalValue,
        sourceRange: Range<Int>
    ) {
        self.field = field
        self.value = value
        self.sourceRange = sourceRange
    }
}

public struct SearchStructuredClause: Codable, Hashable, Sendable {
    public let field: SearchStructuredField
    public let value: String
    public let sourceRange: Range<Int>

    public init(
        field: SearchStructuredField,
        value: String,
        sourceRange: Range<Int>
    ) {
        self.field = field
        self.value = value
        self.sourceRange = sourceRange
    }
}

public struct SearchPropertyClause: Codable, Hashable, Sendable {
    /// Exact, case-sensitive top-level YAML key.
    public let key: String
    /// Normalized string equality value. `nil` means property presence.
    public let value: String?
    public let valueWasQuoted: Bool
    public let sourceRange: Range<Int>

    public init(
        key: String,
        value: String?,
        valueWasQuoted: Bool,
        sourceRange: Range<Int>
    ) {
        self.key = key
        self.value = value
        self.valueWasQuoted = valueWasQuoted
        self.sourceRange = sourceRange
    }
}

public struct SearchLinkQuery: Codable, Hashable, Sendable {
    public let direction: SearchLinkDirection
    public let noteIdentity: String
    public let sourceRange: Range<Int>

    public init(
        direction: SearchLinkDirection,
        noteIdentity: String,
        sourceRange: Range<Int>
    ) {
        self.direction = direction
        self.noteIdentity = noteIdentity
        self.sourceRange = sourceRange
    }
}

public indirect enum SearchClause: Codable, Hashable, Sendable {
    case lexical(SearchLexicalClause)
    case structured(SearchStructuredClause)
    case property(SearchPropertyClause)
    case link(SearchLinkQuery)
    case paragraph(SearchParagraphQuery)
}

public struct SearchParagraphQuery: Codable, Hashable, Sendable {
    public let expression: SearchExpression
    public let sourceRange: Range<Int>
    public init(expression: SearchExpression, sourceRange: Range<Int>) {
        self.expression = expression
        self.sourceRange = sourceRange
    }
}

public enum SearchExplanationNormalization: String, Codable, Hashable, Sendable {
    case canonicalUnicodeCaseWhitespace = "canonical_unicode_case_whitespace"
    case lexicalUnicodeCaseDiacriticWhitespace = "lexical_unicode_case_diacritic_whitespace"
    case cjkCharacterAndOverlappingBigramProjection = "cjk_character_and_overlapping_bigram_projection"
    case caseSensitiveTopLevelPropertyKey = "case_sensitive_top_level_property_key"
}

public enum SearchExplanationOrdering: String, Codable, Hashable, Sendable {
    case noteExactIdentityThenBM25ThenTitleRolePath = "note_exact_identity_then_bm25_then_title_role_path"
}

public enum SearchExplanationLimitation: String, Codable, Hashable, Sendable {
    case authorizedScopeOnly = "authorized_scope_only"
    case retrievalLeadNotEvidence = "retrieval_lead_not_evidence"
    case noteLinksDirectOnly = "note_links_direct_only"
}

public enum SearchExplanationClauseKind: Codable, Hashable, Sendable {
    case lexical(SearchLexicalField?, String, SearchLexicalMatchKind, Bool)
    case structured(SearchStructuredField, String, Bool)
    case property(String, String?)
    case link(SearchLinkDirection, String)
    case paragraph(SearchExpression)
}

public struct SearchExplanationClause: Codable, Hashable, Sendable {
    public let kind: SearchExplanationClauseKind
    public let sourceRange: Range<Int>

    public init(kind: SearchExplanationClauseKind, sourceRange: Range<Int>) {
        self.kind = kind
        self.sourceRange = sourceRange
    }
}

public struct SearchExplanation: Codable, Hashable, Sendable {
    public let provider: SearchProvider
    public let providerWasExplicit: Bool
    public let scope: SearchPresentationScope
    public let expression: SearchExpression
    public var clauses: [SearchExplanationClause] { expression.predicates.map(\.explanation) }
    public let normalization: [SearchExplanationNormalization]
    public let ordering: SearchExplanationOrdering
    public let limitations: [SearchExplanationLimitation]

    public init(
        provider: SearchProvider,
        providerWasExplicit: Bool,
        scope: SearchPresentationScope,
        expression: SearchExpression
    ) {
        self.provider = provider
        self.providerWasExplicit = providerWasExplicit
        self.scope = scope
        self.expression = expression
        self.normalization = Self.normalization(for: provider)
        self.ordering = .noteExactIdentityThenBM25ThenTitleRolePath
        self.limitations = [.authorizedScopeOnly, .retrievalLeadNotEvidence, .noteLinksDirectOnly]
    }

    private static func normalization(
        for provider: SearchProvider
    ) -> [SearchExplanationNormalization] {
        [
            .canonicalUnicodeCaseWhitespace,
            .lexicalUnicodeCaseDiacriticWhitespace,
            .cjkCharacterAndOverlappingBigramProjection,
            .caseSensitiveTopLevelPropertyKey,
        ]
    }
}

public struct SearchQueryAST: Codable, Hashable, Sendable {
    public let provider: SearchProvider
    public let providerWasExplicit: Bool
    public let expression: SearchExpression
    public let identityNeedle: String?

    public init(provider: SearchProvider, providerWasExplicit: Bool, expression: SearchExpression, identityNeedle: String?) {
        self.provider = provider
        self.providerWasExplicit = providerWasExplicit
        self.expression = expression
        self.identityNeedle = identityNeedle
    }

    public var clauses: [SearchClause] { expression.predicates.map(\.clause) }
    public var positiveLexicalClauses: [SearchLexicalClause] {
        expression.predicates.compactMap {
            guard !$0.excluded, case .lexical(let clause) = $0.clause else { return nil }
            return clause
        }
    }
    public var linkQueries: [SearchLinkQuery] {
        clauses.compactMap { if case .link(let query) = $0 { query } else { nil } }
    }
    public var hasPropertyClause: Bool { clauses.contains { if case .property = $0 { true } else { false } } }
    public var positiveParagraphQueries: [SearchParagraphQuery] {
        expression.predicates.compactMap { if !$0.excluded, case .paragraph(let value) = $0.clause { value } else { nil } }
    }
    public var rankingLexicalClauses: [SearchLexicalClause] {
        positiveLexicalClauses
            + positiveParagraphQueries.flatMap {
                $0.expression.predicates.compactMap {
                    if !$0.excluded, case .lexical(let clause) = $0.clause { clause } else { nil }
                }
            }
    }
    public var isFilterOnly: Bool { positiveLexicalClauses.isEmpty && positiveParagraphQueries.isEmpty }

    public func scopeDiagnostic(scope: SearchPresentationScope, queryUTF16Count: Int) -> SearchQueryDiagnostic? {
        guard scope == .thisNote else { return nil }
        let hasNonLexical = clauses.contains {
            switch $0 {
            case .lexical, .paragraph: false
            default: true
            }
        }
        guard !hasNonLexical, expression.guaranteesPositiveLexicalMatch else {
            return SearchQueryDiagnostic(
                reason: .currentNoteRequiresPositiveText,
                message: "This Note requires a positive text condition in every alternative and does not use property, structural, or link filters.",
                utf16LowerBound: 0, utf16UpperBound: queryUTF16Count)
        }
        return nil
    }

    public func explanation(scope: SearchPresentationScope) -> SearchExplanation {
        SearchExplanation(
            provider: provider, providerWasExplicit: providerWasExplicit, scope: scope,
            expression: expression)
    }

    /// A result projection contains only conditions that actually establish this match.
    public func matched(by evaluation: SearchEvaluation) -> Self {
        Self(
            provider: provider, providerWasExplicit: providerWasExplicit,
            expression: .and(evaluation.matches.map { $0.excluded ? .not(.clause($0.clause)) : .clause($0.clause) }),
            identityNeedle: identityNeedle)
    }
}

public struct SearchQueryParseResult: Codable, Hashable, Sendable {
    public let provider: SearchProvider
    public let providerWasExplicit: Bool
    public let ast: SearchQueryAST?
    public let diagnostics: [SearchQueryDiagnostic]

    public init(
        provider: SearchProvider? = nil,
        providerWasExplicit: Bool? = nil,
        ast: SearchQueryAST?,
        diagnostics: [SearchQueryDiagnostic]
    ) {
        self.provider = provider ?? ast?.provider ?? .note
        self.providerWasExplicit =
            providerWasExplicit
            ?? ast?.providerWasExplicit
            ?? false
        self.ast = ast
        self.diagnostics = diagnostics
    }

    public var isValid: Bool { ast != nil && diagnostics.isEmpty }

    public func explanation(scope: SearchPresentationScope) -> SearchExplanation {
        ast?.explanation(scope: scope)
            ?? SearchExplanation(
                provider: provider,
                providerWasExplicit: providerWasExplicit,
                scope: scope,
                expression: .and([])
            )
    }
}

public enum SearchQueryParser {
    private struct Token {
        let raw: String
        let range: Range<Int>
    }

    private struct LinkAnchor {
        let direction: SearchLinkDirection
        let identity: String
        let sourceRange: Range<Int>
    }

    private static let calloutValues = Set(CalloutSemanticRole.allCases.map(\.rawValue))
    private static let scopeSelectors: Set<String> = ["scope", "vault", "role"]
    private static let knownUnsupportedFields: Set<String> = ["status", "review"]

    public static func parse(_ raw: String) -> SearchQueryParseResult {
        guard raw.utf16.count <= SearchContract.maximumQueryUTF16Count else {
            return SearchQueryParseResult(
                ast: nil,
                diagnostics: [
                    SearchQueryDiagnostic(
                        reason: .queryTooLong(limit: SearchContract.maximumQueryUTF16Count),
                        message: "Search queries are limited to \(SearchContract.maximumQueryUTF16Count) UTF-16 code units.",
                        utf16LowerBound: 0,
                        utf16UpperBound: SearchContract.maximumQueryUTF16Count
                    )
                ]
            )
        }
        let tokenized = tokenize(raw)
        guard tokenized.diagnostics.isEmpty else {
            return SearchQueryParseResult(ast: nil, diagnostics: tokenized.diagnostics)
        }
        guard !tokenized.tokens.isEmpty else {
            return SearchQueryParseResult(
                ast: SearchQueryAST(
                    provider: .note,
                    providerWasExplicit: false,
                    expression: .and([]),
                    identityNeedle: nil
                ),
                diagnostics: []
            )
        }
        guard tokenized.tokens.count <= SearchContract.maximumQueryTokenCount else {
            let overflow = tokenized.tokens[SearchContract.maximumQueryTokenCount]
            return SearchQueryParseResult(
                ast: nil,
                diagnostics: [
                    SearchQueryDiagnostic(
                        reason: .tooManyTokens(limit: SearchContract.maximumQueryTokenCount),
                        message: "Search queries are limited to \(SearchContract.maximumQueryTokenCount) tokens.",
                        utf16LowerBound: overflow.range.lowerBound,
                        utf16UpperBound: overflow.range.upperBound
                    )
                ]
            )
        }

        let providerResolution = resolveProvider(in: tokenized.tokens)
        guard providerResolution.diagnostics.isEmpty else {
            return SearchQueryParseResult(
                provider: providerResolution.provider,
                providerWasExplicit: providerResolution.explicit,
                ast: nil,
                diagnostics: providerResolution.diagnostics
            )
        }

        if let misplaced = tokenized.tokens.dropFirst().first(where: isKindToken) {
            return SearchQueryParseResult(ast: nil, diagnostics: [diagnostic(.misplacedProvider, "Put kind:note once at the start of the query.", misplaced)])
        }
        let tokens = tokenized.tokens.first.map(isKindToken) == true ? Array(tokenized.tokens.dropFirst()) : tokenized.tokens
        do {
            var reader = ExpressionReader(tokens: tokens)
            let expression = try reader.read()
            let clauses = expression.predicates.filter { !$0.excluded }.map(\.clause)
            return SearchQueryParseResult(
                ast: SearchQueryAST(
                    provider: providerResolution.provider, providerWasExplicit: providerResolution.explicit,
                    expression: expression, identityNeedle: expression.containsDisjunction ? nil : identityNeedle(for: clauses)), diagnostics: [])
        } catch {
            return SearchQueryParseResult(
                provider: providerResolution.provider, providerWasExplicit: providerResolution.explicit,
                ast: nil, diagnostics: [error])
        }
    }

    private struct ExpressionReader {
        let tokens: [Token]
        var index = 0
        mutating func read() throws(SearchQueryDiagnostic) -> SearchExpression {
            guard !tokens.isEmpty else { return .and([]) }
            let result = try disjunction(field: nil, depth: 0)
            guard index == tokens.count else { throw error(.unexpectedOperator, "Unexpected closing parenthesis or operator.") }
            return result
        }
        func error(_ reason: SearchQueryDiagnosticReason, _ message: String) -> SearchQueryDiagnostic {
            let token = index < tokens.count ? tokens[index] : tokens.last ?? Token(raw: "", range: 0..<0)
            return diagnostic(reason, message, token)
        }
        mutating func disjunction(field: String?, depth: Int) throws(SearchQueryDiagnostic) -> SearchExpression {
            var values = [try conjunction(field: field, depth: depth)]
            while index < tokens.count, tokens[index].raw == "OR" {
                index += 1
                values.append(try conjunction(field: field, depth: depth))
            }
            return values.count == 1 ? values[0] : .or(values)
        }
        mutating func conjunction(field: String?, depth: Int) throws(SearchQueryDiagnostic) -> SearchExpression {
            var values = [try unary(field: field, depth: depth)]
            while index < tokens.count, tokens[index].raw != ")", tokens[index].raw != "OR" {
                if tokens[index].raw == "AND" {
                    index += 1
                } else if tokens[index - 1].range.upperBound == tokens[index].range.lowerBound {
                    throw error(.conditionSeparatorRequired, "Separate conditions with whitespace or an operator.")
                }
                values.append(try unary(field: field, depth: depth))
            }
            return values.count == 1 ? values[0] : .and(values)
        }
        mutating func unary(field: String?, depth: Int) throws(SearchQueryDiagnostic) -> SearchExpression {
            var negated = false
            while index < tokens.count, ["NOT", "-"].contains(tokens[index].raw) {
                negated.toggle()
                index += 1
            }
            guard index < tokens.count, !["AND", "OR", ")"].contains(tokens[index].raw) else {
                throw error(.conditionRequired, "An operator or group requires a condition.")
            }
            let token = tokens[index]
            index += 1
            let result: SearchExpression
            if token.raw == "(" {
                result = try group(field: field, depth: depth, opening: token)
            } else if token.raw.hasSuffix(":"), index < tokens.count, tokens[index].raw == "(" {
                let name = String(token.raw.dropLast()).lowercased()
                if name == "paragraph", field == nil {
                    index += 1
                    let inner = try group(field: nil, depth: depth, opening: tokens[index - 1])
                    guard inner.predicates.allSatisfy({ if case .lexical(let clause) = $0.clause { clause.field == nil } else { false } }),
                        inner.guaranteesPositiveLexicalMatch
                    else {
                        throw diagnostic(
                            .paragraphRequiresPositiveText, "Paragraph groups require unfielded text and a positive condition in every alternative.", token)
                    }
                    let paragraph = SearchExpression.clause(
                        .paragraph(
                            .init(
                                expression: inner,
                                sourceRange: token.range.lowerBound..<tokens[index - 1].range.upperBound)))
                    return negated ? .not(paragraph) : paragraph
                }
                guard field == nil, SearchLexicalField(rawValue: name) != nil || SearchStructuredField(rawValue: name) != nil else {
                    throw diagnostic(.fieldGroupUnsupported, "This field cannot contain a field group. Combine complete conditions instead.", token)
                }
                index += 1
                result = try group(field: name, depth: depth, opening: tokens[index - 1])
            } else {
                if field != nil, splitField(token.raw).field != nil {
                    throw diagnostic(.inheritedFieldOverride, "A field group cannot override its inherited field.", token)
                }
                let inherited = Token(raw: field.map { $0 + ":" + token.raw } ?? token.raw, range: token.range)
                switch parseNote(inherited) {
                case .clause(let clause): result = .clause(clause)
                case .anchor(let anchor):
                    result = .clause(.link(SearchLinkQuery(direction: anchor.direction, noteIdentity: anchor.identity, sourceRange: anchor.sourceRange)))
                case .diagnostic(let issue): throw issue
                }
            }
            return negated ? .not(result) : result
        }
        mutating func group(field: String?, depth: Int, opening: Token) throws(SearchQueryDiagnostic) -> SearchExpression {
            guard depth < SearchContract.maximumQueryGroupDepth else {
                throw diagnostic(.groupDepthExceeded(limit: SearchContract.maximumQueryGroupDepth), "Search groups are limited to 8 levels.", opening)
            }
            let value = try disjunction(field: field, depth: depth + 1)
            guard index < tokens.count, tokens[index].raw == ")" else {
                throw diagnostic(.unclosedGroup, "The group is not closed.", opening)
            }
            index += 1
            return value
        }
    }

    private static func resolveProvider(
        in tokens: [Token]
    ) -> (provider: SearchProvider, explicit: Bool, diagnostics: [SearchQueryDiagnostic]) {
        let kindTokens = tokens.filter(isKindToken)
        guard kindTokens.count <= 1 else {
            return (
                .note, true,
                [
                    diagnostic(
                        .duplicateProvider,
                        "kind: may appear only once.",
                        kindTokens[1]
                    )
                ]
            )
        }
        guard let token = kindTokens.first else { return (.note, false, []) }
        let raw = token.raw
        let split = splitField(raw)
        guard !split.value.isEmpty else {
            return (
                .note, true,
                [
                    diagnostic(
                        .providerValueRequired,
                        "The kind field requires note.",
                        token
                    )
                ]
            )
        }
        let decoded: DecodedValue
        switch decodeValue(split.value, token: token) {
        case .success(let value): decoded = value
        case .failure(let error): return (.note, true, [error])
        }
        guard !decoded.quoted, !decoded.hadTrailingAsterisk,
            let provider = SearchProvider(rawValue: decoded.text.lowercased())
        else {
            return (
                .note, true,
                [
                    diagnostic(
                        .unknownProvider,
                        "kind: accepts only note.",
                        token
                    )
                ]
            )
        }
        return (provider, true, [])
    }

    private enum NoteParseResult {
        case clause(SearchClause)
        case anchor(LinkAnchor)
        case diagnostic(SearchQueryDiagnostic)
    }

    private static func parseNote(_ token: Token) -> NoteParseResult {
        let raw = token.raw
        if let syntaxDiagnostic = unsupportedSyntaxDiagnostic(raw: raw, token: token) {
            return .diagnostic(syntaxDiagnostic)
        }
        let split = splitField(raw)
        guard let fieldName = split.field else {
            switch lexicalClause(field: nil, rawValue: raw, token: token) {
            case .success(let value): return .clause(.lexical(value))
            case .failure(let error): return .diagnostic(error)
            }
        }
        let field = fieldName.lowercased()
        guard !split.value.isEmpty else {
            return .diagnostic(
                diagnostic(
                    .missingFieldValue(field: field),
                    "The \(field) field requires a value.",
                    token
                ))
        }
        if scopeSelectors.contains(field) {
            return .diagnostic(scopeSelectorDiagnostic(token))
        }
        if knownUnsupportedFields.contains(field) {
            return .diagnostic(
                diagnostic(
                    .unsupportedField(field: field),
                    "The \(field): field is known but is not supported by the current Search contract.",
                    token
                ))
        }
        if let lexicalField = SearchLexicalField(rawValue: field) {
            switch lexicalClause(
                field: lexicalField,
                rawValue: split.value,
                token: token
            ) {
            case .success(let value): return .clause(.lexical(value))
            case .failure(let error): return .diagnostic(error)
            }
        }
        if let structuredField = SearchStructuredField(rawValue: field) {
            switch structuredClause(
                field: structuredField,
                rawValue: split.value,
                token: token
            ) {
            case .success(let value): return .clause(.structured(value))
            case .failure(let error): return .diagnostic(error)
            }
        }
        switch field {
        case "property":
            switch propertyClause(rawValue: split.value, token: token) {
            case .success(let value): return .clause(.property(value))
            case .failure(let error): return .diagnostic(error)
            }
        case SearchLinkDirection.fromNote.rawValue, SearchLinkDirection.toNote.rawValue:
            switch linkAnchor(
                direction: SearchLinkDirection(rawValue: field)!,
                rawValue: split.value,
                token: token
            ) {
            case .success(let value): return .anchor(value)
            case .failure(let error): return .diagnostic(error)
            }
        default:
            return .diagnostic(diagnostic(.unknownField(field: field), "Unknown Search field \(field):.", token))
        }
    }

    private static func lexicalClause(
        field: SearchLexicalField?,
        rawValue: String,
        token: Token
    ) -> Result<SearchLexicalClause, SearchQueryDiagnostic> {
        lexicalValue(rawValue, token: token, permitsPrefix: true).map {
            SearchLexicalClause(
                field: field,
                value: $0,
                sourceRange: token.range
            )
        }
    }

    private static func lexicalValue(
        _ rawValue: String,
        token: Token,
        permitsPrefix: Bool
    ) -> Result<SearchLexicalValue, SearchQueryDiagnostic> {
        let value: DecodedValue
        switch decodeValue(rawValue, token: token) {
        case .success(let decoded): value = decoded
        case .failure(let error): return .failure(error)
        }
        let normalized = SearchTextNormalization.normalize(value.text)
        guard !normalized.isEmpty else {
            return .failure(diagnostic(.emptyClause, "A Search clause cannot be empty.", token))
        }
        if value.quoted {
            return .success(.phrase(normalized))
        }
        if value.hadTrailingAsterisk {
            guard permitsPrefix else {
                return .failure(
                    diagnostic(
                        .prefixUnsupported,
                        "This field does not support prefix values.",
                        token
                    ))
            }
            if SearchTokenization.containsCJK(normalized) {
                return .failure(
                    diagnostic(
                        .cjkPrefixUnsupported,
                        "CJK clauses do not use *. Continuous character and bigram matching is automatic.",
                        token
                    ))
            }
            guard normalized.unicodeScalars.count >= 2 else {
                return .failure(
                    diagnostic(
                        .prefixTooShort,
                        "A prefix requires at least two non-CJK Unicode scalars before *.",
                        token
                    ))
            }
            return .success(.prefix(normalized))
        }
        return .success(.term(normalized))
    }

    private static func structuredClause(
        field: SearchStructuredField,
        rawValue: String,
        token: Token
    ) -> Result<SearchStructuredClause, SearchQueryDiagnostic> {
        let value: DecodedValue
        switch decodeValue(rawValue, token: token) {
        case .success(let decoded): value = decoded
        case .failure(let error): return .failure(error)
        }
        guard !value.quoted, !value.hadTrailingAsterisk else {
            return .failure(
                diagnostic(
                    .structuredValueSyntax,
                    "Structured Search values are canonical identifiers, not phrases or prefixes.",
                    token
                ))
        }
        let normalized = value.text.lowercased()
        let allowed: Set<String> =
            switch field {
            case .callout: calloutValues
            case .has: ["broken-link"]
            }
        guard allowed.contains(normalized) else {
            return .failure(
                diagnostic(
                    .unknownStructuredValue(field: field, value: value.text),
                    "Unknown canonical \(field.rawValue) value \(value.text).",
                    token
                ))
        }
        return .success(
            SearchStructuredClause(
                field: field,
                value: normalized,
                sourceRange: token.range
            ))
    }

    static func propertyEqualityIndex(in rawValue: String) -> String.Index? {
        var quoted = false
        var escaped = false
        return rawValue.indices.first { index in
            let character = rawValue[index]
            if escaped {
                escaped = false
                return false
            }
            if character == "\\", quoted {
                escaped = true
                return false
            }
            if character == "\"" {
                quoted.toggle()
                return false
            }
            return character == "=" && !quoted
        }
    }

    private static func propertyClause(
        rawValue: String,
        token: Token
    ) -> Result<SearchPropertyClause, SearchQueryDiagnostic> {

        let equality = propertyEqualityIndex(in: rawValue)
        let rawKey = equality.map { String(rawValue[..<$0]) } ?? rawValue
        let decodedKey: DecodedValue
        switch decodeValue(rawKey, token: token) {
        case .success(let value): decodedKey = value
        case .failure(let error): return .failure(error)
        }
        guard !decodedKey.text.isEmpty, !decodedKey.hadTrailingAsterisk,
            !decodedKey.text.contains(where: { $0.isNewline }),
            decodedKey.quoted || isUnambiguousPropertyKey(decodedKey.text)
        else {
            return .failure(
                diagnostic(
                    .invalidPropertyKey,
                    "Property keys use an identifier or a double-quoted top-level key.",
                    token
                ))
        }
        let key = decodedKey.text.precomposedStringWithCanonicalMapping
        guard let equality else {
            return .success(
                SearchPropertyClause(
                    key: key,
                    value: nil,
                    valueWasQuoted: false,
                    sourceRange: token.range
                ))
        }
        let rawEqualityValue = String(rawValue[rawValue.index(after: equality)...])
        guard !rawEqualityValue.isEmpty else {
            return .failure(
                diagnostic(
                    .propertyValueRequired,
                    "Property equality requires a scalar text value.",
                    token
                ))
        }
        let decoded: DecodedValue
        switch decodeValue(rawEqualityValue, token: token) {
        case .success(let value): decoded = value
        case .failure(let error): return .failure(error)
        }
        guard !decoded.hadTrailingAsterisk else {
            return .failure(
                diagnostic(
                    .propertyPrefixUnsupported,
                    "Property equality is exact and does not support prefixes.",
                    token
                ))
        }
        let normalized = SearchTextNormalization.normalize(decoded.text)
        guard !normalized.isEmpty else {
            return .failure(diagnostic(.emptyPropertyValue, "A Property value cannot be empty.", token))
        }
        return .success(
            SearchPropertyClause(
                key: key,
                value: normalized,
                valueWasQuoted: decoded.quoted,
                sourceRange: token.range
            ))
    }

    private static func linkAnchor(
        direction: SearchLinkDirection,
        rawValue: String,
        token: Token
    ) -> Result<LinkAnchor, SearchQueryDiagnostic> {

        let value: DecodedValue
        switch decodeValue(rawValue, token: token) {
        case .success(let decoded): value = decoded
        case .failure(let error): return .failure(error)
        }
        guard !value.hadTrailingAsterisk else {
            return .failure(
                diagnostic(
                    .linkPrefixUnsupported,
                    "Link identities do not support prefixes.",
                    token
                ))
        }
        let identity = SearchTextNormalization.normalize(value.text)
        guard !identity.isEmpty else {
            return .failure(diagnostic(.emptyLinkIdentity, "A link identity cannot be empty.", token))
        }
        return .success(
            LinkAnchor(
                direction: direction,
                identity: identity,
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
                return .failure(
                    diagnostic(
                        .phrasePrefixUnsupported,
                        "A quoted phrase cannot also be a prefix query.",
                        token
                    ))
            }
            guard raw.count >= 2, raw.hasSuffix("\"") else {
                return .failure(diagnostic(.unclosedPhrase, "The quoted phrase is not closed.", token))
            }
            var result = ""
            var escaped = false
            for character in raw.dropFirst().dropLast() {
                if escaped {
                    guard character == "\"" || character == "\\" else {
                        return .failure(
                            diagnostic(
                                .invalidPhraseEscape,
                                "Only \\\" and \\\\ are valid Search phrase escapes.",
                                token
                            ))
                    }
                    result.append(character)
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    return .failure(
                        diagnostic(
                            .partialQuotedValue,
                            "A quote must enclose the complete value of one Search clause.",
                            token
                        ))
                } else {
                    result.append(character)
                }
            }
            if escaped {
                return .failure(
                    diagnostic(
                        .trailingPhraseEscape,
                        "A phrase cannot end with an escape marker.",
                        token
                    ))
            }
            return .success(
                DecodedValue(
                    text: result,
                    quoted: true,
                    hadTrailingAsterisk: false
                ))
        }
        if raw.contains("\"") {
            return .failure(
                diagnostic(
                    .partialQuotedValue,
                    "A quote must enclose the complete value of one Search clause.",
                    token
                ))
        }
        let stars = raw.filter { $0 == "*" }.count
        guard stars == 0 || (stars == 1 && raw.hasSuffix("*")) else {
            return .failure(
                diagnostic(
                    .invalidPrefixPlacement,
                    "* is supported only once at the end of an unquoted term.",
                    token
                ))
        }
        let value = raw.hasSuffix("*") ? String(raw.dropLast()) : raw
        return .success(
            DecodedValue(
                text: value,
                quoted: false,
                hadTrailingAsterisk: raw.hasSuffix("*")
            ))
    }

    private static func unsupportedSyntaxDiagnostic(
        raw: String,
        token: Token
    ) -> SearchQueryDiagnostic? {
        let syntax = syntaxOutsideQuotedValue(raw)
        if ["AND", "OR", "NOT", "NEAR"].contains(syntax)
            || syntax.contains("(") || syntax.contains(")") || syntax.contains("|")
        {
            return diagnostic(
                .operatorTextRequiresQuotes,
                "Quote operator words to search them as text. NEAR and alternate-expression syntax are not supported.",
                token
            )
        }
        let candidate = splitField(syntax).value
        if syntax.hasSuffix("~")
            || syntax.contains("..")
            || (candidate.count > 1
                && candidate.hasPrefix("/")
                && candidate.hasSuffix("/"))
        {
            return diagnostic(
                .unsupportedPatternSyntax,
                "Regular-expression, fuzzy, and range syntax are not supported.",
                token
            )
        }
        return nil
    }

    private static func syntaxOutsideQuotedValue(_ raw: String) -> String {
        var result = ""
        var quoted = false
        var escaped = false
        for character in raw {
            if quoted {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    quoted = false
                }
                result.append(" ")
            } else if character == "\"" {
                quoted = true
                result.append(" ")
            } else {
                result.append(character)
            }
        }
        return result
    }

    private static func isKindToken(_ token: Token) -> Bool {
        var raw = token.raw
        if raw.hasPrefix("-") { raw.removeFirst() }
        return splitField(raw).field?.lowercased() == "kind"
    }

    private static func splitField(_ raw: String) -> (field: String?, value: String) {
        guard let colon = raw.firstIndex(of: ":") else { return (nil, raw) }
        let field = String(raw[..<colon])
        guard !field.isEmpty else { return (nil, raw) }
        return (field, String(raw[raw.index(after: colon)...]))
    }

    private static func isUnambiguousPropertyKey(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
            CharacterSet.letters.contains(first) || first == "_"
        else { return false }
        return value.unicodeScalars.dropFirst().allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
        }
    }

    private static func identityNeedle(for clauses: [SearchClause]) -> String? {
        var unfieldedValues: [String] = []
        var fieldedIdentityValues: [String] = []
        for clause in clauses {
            guard case .lexical(let lexical) = clause,
                !lexical.value.isPrefix
            else { continue }
            switch lexical.field {
            case nil:
                unfieldedValues.append(lexical.value.text)
            case .title, .alias, .path:
                fieldedIdentityValues.append(lexical.value.text)
            case .heading, .summary, .body, .author, .publicationDate, .tag, .footnote, .linkAnnotation:
                continue
            }
        }
        if !unfieldedValues.isEmpty {
            return SearchTextNormalization.normalize(unfieldedValues.joined(separator: " "))
        }
        guard fieldedIdentityValues.count == 1 else { return nil }
        return SearchTextNormalization.normalize(fieldedIdentityValues[0])
    }

    private static func scopeSelectorDiagnostic(_ token: Token) -> SearchQueryDiagnostic {
        diagnostic(
            .scopeSelectorInQuery,
            "Choose This Note, This Vault, or Triptych outside the query.",
            token
        )
    }

    private static func diagnostic(
        _ reason: SearchQueryDiagnosticReason,
        _ message: String,
        _ token: Token
    ) -> SearchQueryDiagnostic {
        SearchQueryDiagnostic(
            reason: reason,
            message: message,
            utf16LowerBound: token.range.lowerBound,
            utf16UpperBound: token.range.upperBound
        )
    }

    static func completionTokens(_ raw: String) -> [(raw: String, range: Range<Int>)] {
        tokenize(raw, allowsIncompletePhrase: true).tokens.map { ($0.raw, $0.range) }
    }

    private static func tokenize(_ raw: String, allowsIncompletePhrase: Bool = false) -> (
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
            if ["(", ")", "-"].contains(raw[index]) {
                index = raw.index(after: index)
                tokens.append(Token(raw: String(raw[start..<index]), range: start.utf16Offset(in: raw)..<index.utf16Offset(in: raw)))
                continue
            }
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
                } else if character.isWhitespace || character == "(" || character == ")" {
                    break
                }
                index = raw.index(after: index)
            }
            let end = index
            let range = start.utf16Offset(in: raw)..<end.utf16Offset(in: raw)
            if quoted && !allowsIncompletePhrase {
                return (
                    [],
                    [
                        SearchQueryDiagnostic(
                            reason: .unclosedPhrase,
                            message: "The quoted phrase is not closed.",
                            utf16LowerBound: range.lowerBound,
                            utf16UpperBound: range.upperBound
                        )
                    ]
                )
            }
            tokens.append(Token(raw: String(raw[start..<end]), range: range))
        }
        return (tokens, [])
    }
}

public enum SearchTextNormalization {
    public static func normalize(_ value: String) -> String {
        normalize(value, options: [.caseInsensitive])
    }

    /// Deterministic comparison form shared by lexical projections, index input
    /// and queries. FTS5 `unicode61` has narrower diacritic folding, so it receives
    /// this comparison form rather than defining it. Exact identity keys keep
    /// using `normalize(_:)`, which preserves diacritics and punctuation.
    public static func lexicalNormalize(_ value: String) -> String {
        normalize(value, options: [.caseInsensitive, .diacriticInsensitive])
    }

    public static func originalUTF16RangeForLexicalNormalization(
        in value: String,
        requestedRange: Range<Int>
    ) -> Range<Int>? {
        originalUTF16RangesForLexicalNormalization(
            in: value,
            requestedRanges: [requestedRange]
        )[0]
    }

    /// Maps normalized UTF-16 ranges to complete source graphemes in request
    /// order. Empty or out-of-bounds requests return nil. One source mapping is
    /// built for the batch; each request uses binary searches over that mapping.
    public static func originalUTF16RangesForLexicalNormalization(
        in value: String,
        requestedRanges: [Range<Int>]
    ) -> [Range<Int>?] {
        mappedOriginalUTF16Ranges(
            in: value,
            requestedRanges: requestedRanges,
            normalizer: lexicalNormalize
        )
    }

    private static func normalize(
        _ value: String,
        options: String.CompareOptions
    ) -> String {
        let folded = value.precomposedStringWithCanonicalMapping.folding(
            options: options,
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

    private static func mappedOriginalUTF16Ranges(
        in value: String,
        requestedRanges: [Range<Int>],
        normalizer: (String) -> String
    ) -> [Range<Int>?] {
        guard !requestedRanges.isEmpty else { return [] }
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
                offsets.append(
                    Offset(
                        normalized: lower..<(lower + 1),
                        original: pendingWhitespace
                    ))
            }
            pendingWhitespace = nil
            let folded = normalizer(String(character))
            let lower = normalizedUTF16Count
            normalized += folded
            normalizedUTF16Count += folded.utf16.count
            offsets.append(
                Offset(
                    normalized: lower..<normalizedUTF16Count,
                    original: originalRange
                ))
        }

        guard normalized == normalizer(value) else {
            return Array(repeating: nil, count: requestedRanges.count)
        }
        return requestedRanges.map { requestedRange in
            guard !requestedRange.isEmpty,
                requestedRange.lowerBound >= 0,
                requestedRange.upperBound <= normalizedUTF16Count
            else { return nil }

            var lower = 0
            var upper = offsets.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if offsets[middle].normalized.upperBound <= requestedRange.lowerBound {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            let first = lower
            upper = offsets.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if offsets[middle].normalized.lowerBound < requestedRange.upperBound {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            guard first < lower else { return nil }
            return offsets[first].original.lowerBound..<offsets[lower - 1].original.upperBound
        }
    }
}

public enum SearchTokenization {
    public static func isTokenCharacter(_ character: Character) -> Bool {
        if let ascii = character.asciiValue {
            return (48...57).contains(ascii) || (65...90).contains(ascii)
                || (97...122).contains(ascii) || ascii == 95
        }
        return character.unicodeScalars.allSatisfy(isTokenScalar)
    }

    private static func isTokenScalar(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
    }

    /// Candidate text only. Exact matching retains the authored symbols. The
    /// native Unicode table must not attach a symbol to a canonical word run.
    private static func candidateText(_ normalized: String) -> String {
        var result = ""
        var separator = false
        func append(_ value: String, token: Bool) {
            guard token else {
                separator = !result.isEmpty
                return
            }
            if separator {
                result.append(" ")
                separator = false
            }
            result.append(value)
        }
        for character in normalized { append(String(character), token: isTokenCharacter(character)) }
        return result
    }

    public static func indexText(_ value: String) -> String {
        let normalized = candidateText(SearchTextNormalization.lexicalNormalize(value))
        guard containsCJK(normalized) else { return normalized }
        let additions = indexScriptTokens(in: normalized)
        return additions.isEmpty ? normalized : normalized + " " + additions.joined(separator: " ")
    }

    public static func queryTokens(for value: String) -> [String] {
        let normalized = candidateText(SearchTextNormalization.lexicalNormalize(value))
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

    /// Returns the bounded word units represented by the active Search
    /// tokenizer. This is used only for disposable completion vocabulary; it
    /// carries no source locations and never reconstructs authored Markdown.
    public static func vocabularyTerms(in value: String) -> [String] {
        let normalized = SearchTextNormalization.normalize(value)
        var result: [String] = []
        var nonCJK = ""
        var cjk = ""

        func finishNonCJK() {
            guard !nonCJK.isEmpty else { return }
            result.append(nonCJK)
            nonCJK = ""
        }

        func finishCJK() {
            guard !cjk.isEmpty else { return }
            result.append(contentsOf: indexTokens(forCJKRun: cjk))
            cjk = ""
        }

        for scalar in normalized.unicodeScalars {
            if isCJK(scalar) {
                finishNonCJK()
                cjk.unicodeScalars.append(scalar)
            } else {
                finishCJK()
                if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                    nonCJK.unicodeScalars.append(scalar)
                } else {
                    finishNonCJK()
                }
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
            0x20000...0x2FA1F:
            true
        default: false
        }
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
        return scalars
            + (0..<(scalars.count - 1)).map {
                scalars[$0] + scalars[$0 + 1]
            }
    }
}
