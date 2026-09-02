import Foundation

public enum SearchProvider: String, Codable, CaseIterable, Hashable, Sendable {
    case note
    case record
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

public enum SearchClause: Codable, Hashable, Sendable {
    case lexical(SearchLexicalClause)
    case structured(SearchStructuredClause)
    case property(SearchPropertyClause)
    case link(SearchLinkQuery)
}

public enum SearchExplanationOperator: String, Codable, Hashable, Sendable {
    case and
}

public enum SearchExplanationNormalization: String, Codable, Hashable, Sendable {
    case canonicalUnicodeCaseWhitespace = "canonical_unicode_case_whitespace"
    case lexicalUnicodeCaseDiacriticWhitespace = "lexical_unicode_case_diacritic_whitespace"
    case cjkCharacterAndOverlappingBigramProjection = "cjk_character_and_overlapping_bigram_projection"
    case caseSensitiveTopLevelPropertyKey = "case_sensitive_top_level_property_key"
}

public enum SearchExplanationOrdering: String, Codable, Hashable, Sendable {
    case noteExactIdentityThenBM25ThenTitleRolePath = "note_exact_identity_then_bm25_then_title_role_path"
    case recordQuestionThenStepThenTimeQuestionID = "record_question_then_step_then_time_question_id"
}

public enum SearchExplanationLimitation: String, Codable, Hashable, Sendable {
    case authorizedScopeOnly = "authorized_scope_only"
    case retrievalLeadNotEvidence = "retrieval_lead_not_evidence"
    case noCrossProviderRanking = "no_cross_provider_ranking"
    case noteLinksDirectOnly = "note_links_direct_only"
}

public enum SearchExplanationClauseKind: Codable, Hashable, Sendable {
    case lexical(SearchLexicalField?, String, SearchLexicalMatchKind, Bool)
    case structured(SearchStructuredField, String, Bool)
    case property(String, String?)
    case link(SearchLinkDirection, String)
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
    public let `operator`: SearchExplanationOperator
    public let clauses: [SearchExplanationClause]
    public let normalization: [SearchExplanationNormalization]
    public let ordering: SearchExplanationOrdering
    public let limitations: [SearchExplanationLimitation]

    public init(
        provider: SearchProvider,
        providerWasExplicit: Bool,
        scope: SearchPresentationScope,
        operator: SearchExplanationOperator = .and,
        clauses: [SearchExplanationClause]
    ) {
        self.provider = provider
        self.providerWasExplicit = providerWasExplicit
        self.scope = scope
        self.operator = `operator`
        self.clauses = clauses
        self.normalization = Self.normalization(for: provider)
        self.ordering = provider == .note
            ? .noteExactIdentityThenBM25ThenTitleRolePath
            : .recordQuestionThenStepThenTimeQuestionID
        self.limitations = provider == .note
            ? [.authorizedScopeOnly, .retrievalLeadNotEvidence,
               .noCrossProviderRanking, .noteLinksDirectOnly]
            : [.authorizedScopeOnly, .retrievalLeadNotEvidence,
               .noCrossProviderRanking]
    }

    private static func normalization(
        for provider: SearchProvider
    ) -> [SearchExplanationNormalization] {
        if provider == .note {
            return [.canonicalUnicodeCaseWhitespace,
                    .lexicalUnicodeCaseDiacriticWhitespace,
                    .cjkCharacterAndOverlappingBigramProjection,
                    .caseSensitiveTopLevelPropertyKey]
        }
        return [.canonicalUnicodeCaseWhitespace,
                .lexicalUnicodeCaseDiacriticWhitespace,
                .cjkCharacterAndOverlappingBigramProjection]
    }
}

public struct SearchQueryAST: Codable, Hashable, Sendable {
    public let provider: SearchProvider
    public let providerWasExplicit: Bool
    public let clauses: [SearchClause]
    public let identityNeedle: String?

    public init(
        provider: SearchProvider,
        providerWasExplicit: Bool,
        clauses: [SearchClause],
        identityNeedle: String?
    ) {
        self.provider = provider
        self.providerWasExplicit = providerWasExplicit
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

    public var linkQuery: SearchLinkQuery? {
        clauses.compactMap {
            guard case .link(let query) = $0 else { return nil }
            return query
        }.first
    }

    public var hasPropertyClause: Bool {
        clauses.contains {
            if case .property = $0 { return true }
            return false
        }
    }

    public var isFilterOnly: Bool {
        guard !clauses.isEmpty else { return providerWasExplicit }
        return clauses.allSatisfy { clause in
            switch clause {
            case .structured, .property, .link: true
            case .lexical: false
            }
        }
    }

    public func explanation(scope: SearchPresentationScope) -> SearchExplanation {
        SearchExplanation(
            provider: provider,
            providerWasExplicit: providerWasExplicit,
            scope: scope,
            clauses: clauses.map { clause in
                switch clause {
                case .lexical(let value):
                    SearchExplanationClause(
                        kind: .lexical(
                            value.field,
                            value.value.text,
                            value.value.matchKind,
                            value.excluded
                        ),
                        sourceRange: value.sourceRange
                    )
                case .structured(let value):
                    SearchExplanationClause(
                        kind: .structured(value.field, value.value, value.excluded),
                        sourceRange: value.sourceRange
                    )
                case .property(let value):
                    SearchExplanationClause(
                        kind: .property(value.key, value.value),
                        sourceRange: value.sourceRange
                    )
                case .link(let value):
                    SearchExplanationClause(
                        kind: .link(value.direction, value.noteIdentity),
                        sourceRange: value.sourceRange
                    )
                }
            }
        )
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
        self.providerWasExplicit = providerWasExplicit
            ?? ast?.providerWasExplicit
            ?? false
        self.ast = ast
        self.diagnostics = diagnostics
    }

    public var isValid: Bool { ast != nil && diagnostics.isEmpty }

    public func explanation(scope: SearchPresentationScope) -> SearchExplanation {
        ast?.explanation(scope: scope) ?? SearchExplanation(
            provider: provider,
            providerWasExplicit: providerWasExplicit,
            scope: scope,
            clauses: []
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
                diagnostics: [SearchQueryDiagnostic(
                    code: .unsupportedSyntax,
                    message: "Search queries are limited to \(SearchContract.maximumQueryUTF16Count) UTF-16 code units.",
                    utf16LowerBound: 0,
                    utf16UpperBound: SearchContract.maximumQueryUTF16Count
                )]
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
                    clauses: [],
                    identityNeedle: nil
                ),
                diagnostics: []
            )
        }
        guard tokenized.tokens.count <= SearchContract.maximumQueryTokenCount else {
            let overflow = tokenized.tokens[SearchContract.maximumQueryTokenCount]
            return SearchQueryParseResult(
                ast: nil,
                diagnostics: [SearchQueryDiagnostic(
                    code: .unsupportedSyntax,
                    message: "Search queries are limited to \(SearchContract.maximumQueryTokenCount) tokens.",
                    utf16LowerBound: overflow.range.lowerBound,
                    utf16UpperBound: overflow.range.upperBound
                )]
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

        var clauses: [SearchClause] = []
        var diagnostics: [SearchQueryDiagnostic] = []
        var linkAnchors: [LinkAnchor] = []
        for token in tokenized.tokens where !isKindToken(token) {
            switch parseNote(token) {
            case .clause(let clause): clauses.append(clause)
            case .anchor(let anchor): linkAnchors.append(anchor)
            case .diagnostic(let diagnostic): diagnostics.append(diagnostic)
            }
        }

        diagnostics.append(contentsOf: linkDiagnostics(anchors: linkAnchors))
        if diagnostics.isEmpty, let anchor = linkAnchors.first {
            clauses.append(.link(SearchLinkQuery(
                direction: anchor.direction,
                noteIdentity: anchor.identity,
                sourceRange: anchor.sourceRange
            )))
        }
        guard diagnostics.isEmpty else {
            return SearchQueryParseResult(
                provider: providerResolution.provider,
                providerWasExplicit: providerResolution.explicit,
                ast: nil,
                diagnostics: diagnostics
            )
        }

        let hasPositiveUnfielded = clauses.contains { clause in
            switch clause {
            case .lexical(let value): !value.excluded
            case .structured, .property, .link: false
            }
        }
        let hasFilter = clauses.contains { clause in
            switch clause {
            case .structured, .property, .link: true
            case .lexical: false
            }
        }
        if !clauses.isEmpty, !hasPositiveUnfielded, !hasFilter,
           clauses.allSatisfy({ clause in
               switch clause {
               case .lexical(let value): value.excluded
               case .structured, .property, .link: false
               }
           }) {
            let range = tokenized.tokens.first?.range ?? 0..<max(0, raw.utf16.count)
            return SearchQueryParseResult(
                provider: providerResolution.provider,
                providerWasExplicit: providerResolution.explicit,
                ast: nil,
                diagnostics: [SearchQueryDiagnostic(
                    code: .onlyExcludedFreeText,
                    message: "Add a positive term or a provider filter.",
                    utf16LowerBound: range.lowerBound,
                    utf16UpperBound: range.upperBound
                )]
            )
        }

        return SearchQueryParseResult(
            ast: SearchQueryAST(
                provider: providerResolution.provider,
                providerWasExplicit: providerResolution.explicit,
                clauses: clauses,
                identityNeedle: identityNeedle(for: clauses)
            ),
            diagnostics: []
        )
    }

    /// Parses the Record provider with the same tokenizer, normalization,
    /// bounded grammar, and `kind:` resolution used by Note Search.
    public static func parseRecord(_ raw: String) -> RecordSearchQueryParseResult {
        guard raw.utf16.count <= SearchContract.maximumQueryUTF16Count else {
            return RecordSearchQueryParseResult(
                providerWasExplicit: false,
                ast: nil,
                diagnostics: [SearchQueryDiagnostic(
                    code: .unsupportedSyntax,
                    message: "Search queries are limited to \(SearchContract.maximumQueryUTF16Count) UTF-16 code units.",
                    utf16LowerBound: 0,
                    utf16UpperBound: SearchContract.maximumQueryUTF16Count
                )]
            )
        }
        let tokenized = tokenize(raw)
        guard tokenized.diagnostics.isEmpty else {
            return RecordSearchQueryParseResult(
                providerWasExplicit: false,
                ast: nil,
                diagnostics: tokenized.diagnostics
            )
        }
        guard tokenized.tokens.count <= SearchContract.maximumQueryTokenCount else {
            let overflow = tokenized.tokens[SearchContract.maximumQueryTokenCount]
            return RecordSearchQueryParseResult(
                providerWasExplicit: false,
                ast: nil,
                diagnostics: [SearchQueryDiagnostic(
                    code: .unsupportedSyntax,
                    message: "Search queries are limited to \(SearchContract.maximumQueryTokenCount) tokens.",
                    utf16LowerBound: overflow.range.lowerBound,
                    utf16UpperBound: overflow.range.upperBound
                )]
            )
        }
        let providerResolution = resolveProvider(in: tokenized.tokens)
        guard providerResolution.diagnostics.isEmpty else {
            return RecordSearchQueryParseResult(
                providerWasExplicit: providerResolution.explicit,
                ast: nil,
                diagnostics: providerResolution.diagnostics
            )
        }
        if providerResolution.explicit, providerResolution.provider != .record {
            return RecordSearchQueryParseResult(
                providerWasExplicit: true,
                ast: nil,
                diagnostics: [SearchQueryDiagnostic(
                    code: .providerMismatch,
                    message: "The Record provider cannot execute kind:note.",
                    utf16LowerBound: 0,
                    utf16UpperBound: raw.utf16.count
                )]
            )
        }

        var clauses: [RecordSearchClause] = []
        var diagnostics: [SearchQueryDiagnostic] = []
        for token in tokenized.tokens where !isKindToken(token) {
            var tokenRaw = token.raw
            let excluded = tokenRaw.hasPrefix("-")
            if excluded { tokenRaw.removeFirst() }
            if let syntaxDiagnostic = unsupportedSyntaxDiagnostic(
                raw: tokenRaw,
                token: token
            ) {
                diagnostics.append(syntaxDiagnostic)
                continue
            }
            let split = splitField(tokenRaw)
            let field: RecordSearchField?
            if let fieldName = split.field {
                let normalizedField = fieldName.lowercased()
                guard !split.value.isEmpty else {
                    diagnostics.append(diagnostic(
                        .missingFieldValue,
                        "The \(normalizedField) field requires a value.",
                        token
                    ))
                    continue
                }
                guard let resolved = RecordSearchField(rawValue: normalizedField) else {
                    diagnostics.append(diagnostic(
                        .unknownField,
                        "Unknown Record Search field \(normalizedField):.",
                        token
                    ))
                    continue
                }
                field = resolved
            } else {
                field = nil
            }
            switch lexicalValue(split.value, token: token, permitsPrefix: true) {
            case .success(let value):
                clauses.append(RecordSearchClause(
                    field: field,
                    value: value,
                    excluded: excluded,
                    sourceRange: token.range
                ))
            case .failure(let error):
                diagnostics.append(error)
            }
        }
        if diagnostics.isEmpty,
           !clauses.isEmpty,
           clauses.allSatisfy(\.excluded) {
            let range = tokenized.tokens.first?.range ?? 0..<max(0, raw.utf16.count)
            diagnostics.append(SearchQueryDiagnostic(
                code: .onlyExcludedFreeText,
                message: "Add a positive term to Record Search.",
                utf16LowerBound: range.lowerBound,
                utf16UpperBound: range.upperBound
            ))
        }
        guard diagnostics.isEmpty else {
            return RecordSearchQueryParseResult(
                providerWasExplicit: providerResolution.explicit,
                ast: nil,
                diagnostics: diagnostics
            )
        }
        return RecordSearchQueryParseResult(
            providerWasExplicit: providerResolution.explicit,
            ast: RecordSearchQueryAST(
                providerWasExplicit: providerResolution.explicit,
                clauses: clauses
            ),
            diagnostics: []
        )
    }

    private static func resolveProvider(
        in tokens: [Token]
    ) -> (provider: SearchProvider, explicit: Bool, diagnostics: [SearchQueryDiagnostic]) {
        let kindTokens = tokens.filter(isKindToken)
        guard kindTokens.count <= 1 else {
            return (.note, true, [diagnostic(
                .duplicateClause,
                "kind: may appear only once.",
                kindTokens[1]
            )])
        }
        guard let token = kindTokens.first else { return (.note, false, []) }
        var raw = token.raw
        let excluded = raw.hasPrefix("-")
        if excluded { raw.removeFirst() }
        let split = splitField(raw)
        guard !excluded else {
            return (.note, true, [diagnostic(
                .unsupportedSyntax,
                "kind: cannot be excluded.",
                token
            )])
        }
        guard !split.value.isEmpty else {
            return (.note, true, [diagnostic(
                .missingFieldValue,
                "The kind field requires note or record.",
                token
            )])
        }
        let decoded: DecodedValue
        switch decodeValue(split.value, token: token) {
        case .success(let value): decoded = value
        case .failure(let error): return (.note, true, [error])
        }
        guard !decoded.quoted, !decoded.hadTrailingAsterisk,
              let provider = SearchProvider(rawValue: decoded.text.lowercased()) else {
            return (.note, true, [diagnostic(
                .unknownStructuredValue,
                "kind: accepts only note or record.",
                token
            )])
        }
        return (provider, true, [])
    }

    private enum NoteParseResult {
        case clause(SearchClause)
        case anchor(LinkAnchor)
        case diagnostic(SearchQueryDiagnostic)
    }

    private static func parseNote(_ token: Token) -> NoteParseResult {
        var raw = token.raw
        let excluded = raw.hasPrefix("-")
        if excluded { raw.removeFirst() }
        if let syntaxDiagnostic = unsupportedSyntaxDiagnostic(raw: raw, token: token) {
            return .diagnostic(syntaxDiagnostic)
        }
        let split = splitField(raw)
        guard let fieldName = split.field else {
            switch lexicalClause(field: nil, rawValue: raw, excluded: excluded, token: token) {
            case .success(let value): return .clause(.lexical(value))
            case .failure(let error): return .diagnostic(error)
            }
        }
        let field = fieldName.lowercased()
        guard !split.value.isEmpty else {
            return .diagnostic(diagnostic(
                .missingFieldValue,
                "The \(field) field requires a value.",
                token
            ))
        }
        if scopeSelectors.contains(field) {
            return .diagnostic(scopeSelectorDiagnostic(token))
        }
        if knownUnsupportedFields.contains(field) {
            return .diagnostic(diagnostic(
                .unsupportedField,
                "The \(field): field is known but is not supported by the current Search contract.",
                token
            ))
        }
        if let lexicalField = SearchLexicalField(rawValue: field) {
            switch lexicalClause(
                field: lexicalField,
                rawValue: split.value,
                excluded: excluded,
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
                excluded: excluded,
                token: token
            ) {
            case .success(let value): return .clause(.structured(value))
            case .failure(let error): return .diagnostic(error)
            }
        }
        switch field {
        case "property":
            switch propertyClause(rawValue: split.value, excluded: excluded, token: token) {
            case .success(let value): return .clause(.property(value))
            case .failure(let error): return .diagnostic(error)
            }
        case SearchLinkDirection.fromNote.rawValue, SearchLinkDirection.toNote.rawValue:
            switch linkAnchor(
                direction: SearchLinkDirection(rawValue: field)!,
                rawValue: split.value,
                excluded: excluded,
                token: token
            ) {
            case .success(let value): return .anchor(value)
            case .failure(let error): return .diagnostic(error)
            }
        default:
            return .diagnostic(diagnostic(.unknownField, "Unknown Search field \(field):.", token))
        }
    }

    private static func lexicalClause(
        field: SearchLexicalField?,
        rawValue: String,
        excluded: Bool,
        token: Token
    ) -> Result<SearchLexicalClause, SearchQueryDiagnostic> {
        lexicalValue(rawValue, token: token, permitsPrefix: true).map {
            SearchLexicalClause(
                field: field,
                value: $0,
                excluded: excluded,
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
                return .failure(diagnostic(
                    .unsupportedSyntax,
                    "This field does not support prefix values.",
                    token
                ))
            }
            if SearchTokenization.containsCJK(normalized) {
                return .failure(diagnostic(
                    .cjkPrefixUnsupported,
                    "CJK clauses do not use *. Continuous character and bigram matching is automatic.",
                    token
                ))
            }
            guard normalized.unicodeScalars.count >= 2 else {
                return .failure(diagnostic(
                    .invalidPrefix,
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
        excluded: Bool,
        token: Token
    ) -> Result<SearchStructuredClause, SearchQueryDiagnostic> {
        let value: DecodedValue
        switch decodeValue(rawValue, token: token) {
        case .success(let decoded): value = decoded
        case .failure(let error): return .failure(error)
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

    private static func propertyClause(
        rawValue: String,
        excluded: Bool,
        token: Token
    ) -> Result<SearchPropertyClause, SearchQueryDiagnostic> {
        guard !excluded else {
            return .failure(diagnostic(
                .unsupportedSyntax,
                "Structured Metadata clauses cannot be excluded.",
                token
            ))
        }
        let equality = rawValue.firstIndex(of: "=")
        let rawKey = equality.map { String(rawValue[..<$0]) } ?? rawValue
        guard isUnambiguousPropertyKey(rawKey) else {
            return .failure(diagnostic(
                .unsupportedSyntax,
                "Metadata keys use an unquoted identifier containing letters, numbers, _ or -.",
                token
            ))
        }
        let key = rawKey.precomposedStringWithCanonicalMapping
        guard let equality else {
            return .success(SearchPropertyClause(
                key: key,
                value: nil,
                valueWasQuoted: false,
                sourceRange: token.range
            ))
        }
        let rawEqualityValue = String(rawValue[rawValue.index(after: equality)...])
        guard !rawEqualityValue.isEmpty else {
            return .failure(diagnostic(
                .missingFieldValue,
                "Metadata equality requires a string value.",
                token
            ))
        }
        let decoded: DecodedValue
        switch decodeValue(rawEqualityValue, token: token) {
        case .success(let value): decoded = value
        case .failure(let error): return .failure(error)
        }
        guard !decoded.hadTrailingAsterisk else {
            return .failure(diagnostic(
                .unsupportedSyntax,
                "Metadata equality is exact and does not support prefixes.",
                token
            ))
        }
        let normalized = SearchTextNormalization.normalize(decoded.text)
        guard !normalized.isEmpty else {
            return .failure(diagnostic(.emptyClause, "A Metadata value cannot be empty.", token))
        }
        return .success(SearchPropertyClause(
            key: key,
            value: normalized,
            valueWasQuoted: decoded.quoted,
            sourceRange: token.range
        ))
    }

    private static func linkAnchor(
        direction: SearchLinkDirection,
        rawValue: String,
        excluded: Bool,
        token: Token
    ) -> Result<LinkAnchor, SearchQueryDiagnostic> {
        guard !excluded else {
            return .failure(diagnostic(
                .unsupportedSyntax,
                "Link anchors cannot be excluded.",
                token
            ))
        }
        let value: DecodedValue
        switch decodeValue(rawValue, token: token) {
        case .success(let decoded): value = decoded
        case .failure(let error): return .failure(error)
        }
        guard !value.hadTrailingAsterisk else {
            return .failure(diagnostic(
                .unsupportedSyntax,
                "Link identities do not support prefixes.",
                token
            ))
        }
        let identity = SearchTextNormalization.normalize(value.text)
        guard !identity.isEmpty else {
            return .failure(diagnostic(.emptyClause, "A link identity cannot be empty.", token))
        }
        return .success(LinkAnchor(
            direction: direction,
            identity: identity,
            sourceRange: token.range
        ))
    }

    private static func linkDiagnostics(
        anchors: [LinkAnchor]
    ) -> [SearchQueryDiagnostic] {
        if anchors.count > 1 {
            return [SearchQueryDiagnostic(
                code: .duplicateClause,
                message: "Use exactly one from-note: or to-note: anchor.",
                utf16LowerBound: anchors[1].sourceRange.lowerBound,
                utf16UpperBound: anchors[1].sourceRange.upperBound
            )]
        }
        return []
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
            for character in raw.dropFirst().dropLast() {
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
                return .failure(diagnostic(
                    .invalidEscape,
                    "A phrase cannot end with an escape marker.",
                    token
                ))
            }
            return .success(DecodedValue(
                text: result,
                quoted: true,
                hadTrailingAsterisk: false
            ))
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

    private static func unsupportedSyntaxDiagnostic(
        raw: String,
        token: Token
    ) -> SearchQueryDiagnostic? {
        let syntax = syntaxOutsideQuotedValue(raw)
        if syntax.caseInsensitiveCompare("OR") == .orderedSame
            || syntax.caseInsensitiveCompare("NEAR") == .orderedSame
            || syntax.contains("(") || syntax.contains(")") || syntax.contains("|") {
            return diagnostic(
                .unsupportedSyntax,
                "OR, NEAR, grouping, and alternate-expression syntax are not supported.",
                token
            )
        }
        let candidate = splitField(syntax).value
        if syntax.hasSuffix("~")
            || syntax.contains("..")
            || (candidate.count > 1
                && candidate.hasPrefix("/")
                && candidate.hasSuffix("/")) {
            return diagnostic(
                .unsupportedSyntax,
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
              CharacterSet.letters.contains(first) || first == "_" else { return false }
        return value.unicodeScalars.dropFirst().allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
        }
    }

    private static func identityNeedle(for clauses: [SearchClause]) -> String? {
        var unfieldedValues: [String] = []
        var fieldedIdentityValues: [String] = []
        for clause in clauses {
            guard case .lexical(let lexical) = clause,
                  !lexical.excluded,
                  !lexical.value.isPrefix else { continue }
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
            .unsupportedScopeSelector,
            "Choose This Note, This Vault, or Triptych outside the query.",
            token
        )
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
        normalize(value, options: [.caseInsensitive])
    }

    /// Deterministic comparison form corresponding to FTS5
    /// `unicode61 remove_diacritics 2`. Exact identity keys deliberately keep
    /// using `normalize(_:)`, which preserves diacritics and punctuation.
    public static func lexicalNormalize(_ value: String) -> String {
        normalize(value, options: [.caseInsensitive, .diacriticInsensitive])
    }

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
