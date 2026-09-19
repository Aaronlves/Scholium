import Foundation
import ScholiumContracts

// Pure Core-internal matching and result construction helpers. SearchIndex
// remains the sole authority for generation, eligibility, and read transactions.

struct StoredSearchDocument {
    let rowID: Int
    let vaultID: UUID
    let vaultName: String
    let vaultRole: VaultRole
    let relativePath: String
    let stableNoteID: String?
    let title: String
    let normalizedTitle: String
    let filenameKey: String
    let pathKey: String
    let aliases: [String]
    let calloutRoles: Set<String>
    let hasBrokenLink: Bool
    let fingerprint: DocumentFingerprint
    let evidentialLayer: EvidentialLayer
    let roleOrder: Int
    let sourceLineStarts: [Int]
    var segments: [SearchTextSegment]
    let paragraphs: [SearchParagraphProjection]
    let paragraphsAreComplete: Bool
    let properties: [SearchPropertyProjection.Entry]
    let propertyIssues: [SearchPropertyProjection.Issue]
    var relatedLexical: RelatedContentLexicalProjection? = nil

    var noteID: VaultQualifiedNoteID {
        VaultQualifiedNoteID(vaultID: vaultID, relativePath: relativePath)
    }
}

struct SearchCandidate {
    let document: StoredSearchDocument
    let identityPriority: Int
    let lexicalRank: Double

    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.identityPriority != rhs.identityPriority {
            return lhs.identityPriority < rhs.identityPriority
        }
        if lhs.lexicalRank != rhs.lexicalRank { return lhs.lexicalRank < rhs.lexicalRank }
        if lhs.document.normalizedTitle != rhs.document.normalizedTitle {
            return lhs.document.normalizedTitle < rhs.document.normalizedTitle
        }
        if lhs.document.roleOrder != rhs.document.roleOrder {
            return lhs.document.roleOrder < rhs.document.roleOrder
        }
        if lhs.document.pathKey != rhs.document.pathKey {
            return lhs.document.pathKey < rhs.document.pathKey
        }
        return lhs.document.relativePath < rhs.document.relativePath
    }
}

struct RelatedIdentityCandidate {
    let document: StoredSearchDocument
    let reason: RelatedContentIdentityMentionReason

    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        let left = minimumMentionOrder(lhs.reason.mentions)
        let right = minimumMentionOrder(rhs.reason.mentions)
        if left.0 != right.0 { return left.0 < right.0 }
        if left.1 != right.1 { return left.1 < right.1 }
        return documentPrecedes(lhs.document, rhs.document)
    }

    static func minimumMentionOrder(
        _ mentions: [RelatedContentIdentityMention]
    ) -> (Int, Int) {
        mentions.map(mentionOrder).reduce((Int.max, Int.max)) { current, next in
            if next.0 != current.0 { return next.0 < current.0 ? next : current }
            return next.1 < current.1 ? next : current
        }
    }

    static func mentionOrder(
        _ mention: RelatedContentIdentityMention
    ) -> (Int, Int) {
        (
            RelatedContentSeedKind.rankingOrder.firstIndex(
                of: mention.seedKind
            ) ?? Int.max,
            mention.identityKind == .title ? 0 : 1
        )
    }

    static func documentPrecedes(
        _ lhs: StoredSearchDocument,
        _ rhs: StoredSearchDocument
    ) -> Bool {
        if lhs.normalizedTitle != rhs.normalizedTitle {
            return lhs.normalizedTitle < rhs.normalizedTitle
        }
        if lhs.roleOrder != rhs.roleOrder { return lhs.roleOrder < rhs.roleOrder }
        if lhs.pathKey != rhs.pathKey { return lhs.pathKey < rhs.pathKey }
        return lhs.relativePath < rhs.relativePath
    }
}

struct RelatedLexicalCandidate {
    let candidate: SearchCandidate
    let reason: RelatedContentLexicalReason
    let score: Double

    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        return SearchCandidate.precedes(lhs.candidate, rhs.candidate)
    }
}

private struct RelatedContentSeedSegment {
    let kind: RelatedContentSeedKind
    let field: SearchMatchedField?
    let normalizedText: String
}

struct RelatedContentSeedTermGroup {
    let kind: RelatedContentSeedKind
    let terms: [String]
}

struct RelatedContentSeedMaterial {
    private let segments: [RelatedContentSeedSegment]
    let termGroups: [RelatedContentSeedTermGroup]
    let combinedTerms: [String]
    let termMatcher: RelatedContentTermMatcher

    init(
        projection: SearchDocumentProjection,
        focuses: [RelatedContentSeedFocus]
    ) {
        let sourceFields: Set<SearchMatchedField> = [
            .title, .heading, .summary, .body, .callout, .footnote, .linkAnnotation, .tag,
        ]
        var segments = focuses.map {
            RelatedContentSeedSegment(
                kind: $0.kind,
                field: nil,
                normalizedText: SearchTextNormalization.normalize($0.text)
            )
        }
        segments.append(
            contentsOf: projection.segments.compactMap { segment in
                guard sourceFields.contains(segment.field) else { return nil }
                return RelatedContentSeedSegment(
                    kind: .sourceNote,
                    field: segment.field,
                    normalizedText: segment.normalizedText
                )
            })
        self.segments = segments

        var groups: [RelatedContentSeedTermGroup] = focuses.map {
            RelatedContentSeedTermGroup(
                kind: $0.kind,
                terms: RelatedContentSeedTermExtractor.terms(
                    in: $0.text,
                    limit: RelatedContentContract.maximumFocusSeedTerms
                )
            )
        }
        groups.append(
            RelatedContentSeedTermGroup(
                kind: .sourceNote,
                terms: RelatedContentSeedTermExtractor.terms(
                    in: projection,
                    limit: RelatedContentContract.maximumSourceSeedTerms
                )
            ))
        termGroups = groups
        termMatcher = RelatedContentTermMatcher(terms: Array(Set(groups.flatMap(\.terms))).sorted())

        var terms: [String] = []
        var seen = Set<String>()
        for kind in RelatedContentSeedKind.rankingOrder {
            for term in groups.first(where: { $0.kind == kind })?.terms ?? []
            where terms.count
                < RelatedContentContract.maximumCombinedSeedTerms
            {
                if seen.insert(term).inserted { terms.append(term) }
            }
        }
        combinedTerms = terms
    }

    func identityMentionReason(
        for document: StoredSearchDocument
    ) -> RelatedContentIdentityMentionReason? {
        var identities: [(RelatedContentIdentityKind, String)] = []
        identities.append((.title, document.title))
        identities.append(contentsOf: document.aliases.map { (.alias, $0) })
        var mentions: [RelatedContentIdentityMention] = []
        var seen = Set<RelatedContentIdentityMention>()
        for (identityKind, identity) in identities {
            let value = SearchLexicalValue.phrase(identity)
            let needle = SearchTextNormalization.lexicalNormalize(identity)
            for segment in segments
            where SearchMatcher.containsOccurrence(
                of: value,
                in: segment.normalizedText, normalizedNeedle: needle
            ) {
                let mention = RelatedContentIdentityMention(
                    seedKind: segment.kind,
                    identityKind: identityKind,
                    matchedIdentity: identity,
                    seedField: segment.field
                )
                if seen.insert(mention).inserted { mentions.append(mention) }
            }
        }
        mentions.sort { lhs, rhs in
            let leftKind =
                RelatedContentSeedKind.rankingOrder.firstIndex(
                    of: lhs.seedKind
                ) ?? Int.max
            let rightKind =
                RelatedContentSeedKind.rankingOrder.firstIndex(
                    of: rhs.seedKind
                ) ?? Int.max
            if leftKind != rightKind { return leftKind < rightKind }
            if lhs.identityKind != rhs.identityKind {
                return lhs.identityKind == .title
            }
            return (lhs.seedField?.rawValue ?? "", lhs.matchedIdentity)
                < (rhs.seedField?.rawValue ?? "", rhs.matchedIdentity)
        }
        return mentions.isEmpty
            ? nil
            : RelatedContentIdentityMentionReason(mentions: mentions)
    }

    func lexicalReason(
        for candidate: SearchCandidate
    ) -> RelatedContentLexicalReason {
        var fields: [SearchMatchedField] = []
        var seedMatches: [RelatedContentSeedTermMatch] = []
        var matchingFieldsByTerm: [String: [SearchMatchedField]] = [:]
        for segment in candidate.document.relatedLexical?.segments ?? [] {
            for term in termMatcher.matchingTerms(in: segment.text, index: segment.index) {
                if !matchingFieldsByTerm[term, default: []].contains(segment.field) {
                    matchingFieldsByTerm[term, default: []].append(segment.field)
                }
            }
        }
        for group in termGroups {
            var matches: [String] = []
            for term in group.terms {
                let matchingFields = matchingFieldsByTerm[term] ?? []
                guard !matchingFields.isEmpty else { continue }
                if matches.count < 8 { matches.append(term) }
                for field in matchingFields where !fields.contains(field) {
                    fields.append(field)
                }
            }
            if !matches.isEmpty {
                seedMatches.append(
                    RelatedContentSeedTermMatch(
                        seedKind: group.kind,
                        terms: matches
                    ))
            }
        }
        return RelatedContentLexicalReason(
            matchedFields: fields,
            seedMatches: seedMatches
        )
    }
}

private enum RelatedContentSeedTermExtractor {
    private static let ignoredLatinTerms: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "been", "being", "but",
        "by", "for", "from", "had", "has", "have", "if", "in", "is", "it",
        "its", "not", "of", "on", "or", "that", "the", "these", "this",
        "those", "to", "was", "we", "were", "with",
    ]

    static func terms(
        in projection: SearchDocumentProjection,
        limit: Int
    ) -> [String] {
        guard limit > 0 else { return [] }
        var result: [String] = []
        var seen = Set<String>()

        func appendDistinct(_ values: [String], maximum: Int) {
            var inserted = 0
            for value in values where result.count < limit && inserted < maximum {
                guard seen.insert(value).inserted else { continue }
                result.append(value)
                inserted += 1
            }
        }

        appendDistinct(tokens(in: projection.title), maximum: 12)
        appendDistinct(tokens(in: projection.summary ?? ""), maximum: 16)
        appendDistinct(
            projection.tags.flatMap(tokens(in:)),
            maximum: 12
        )
        appendDistinct(
            projection.headings.flatMap(tokens(in:)),
            maximum: 16
        )

        var bodyCounts: [String: (count: Int, first: Int)] = [:]
        for (index, token) in tokens(in: projection.body).enumerated() {
            let existing = bodyCounts[token]
            bodyCounts[token] = (
                count: min(8, (existing?.count ?? 0) + 1),
                first: existing?.first ?? index
            )
        }
        let orderedBody = bodyCounts.sorted { left, right in
            if left.value.count != right.value.count {
                return left.value.count > right.value.count
            }
            if left.value.first != right.value.first {
                return left.value.first < right.value.first
            }
            return left.key < right.key
        }.map(\.key)
        appendDistinct(orderedBody, maximum: limit)
        return result
    }

    static func terms(in value: String, limit: Int) -> [String] {
        RelatedContentQueryTerms.terms(in: value, limit: limit)
    }

    static func tokens(in value: String) -> [String] {
        let normalized = SearchTextNormalization.normalize(value)
        var result: [String] = []
        var current = ""
        var currentIsCJK: Bool?

        func finish() {
            guard !current.isEmpty else { return }
            let candidates =
                currentIsCJK == true
                ? SearchTokenization.queryTokens(for: current)
                : [current]
            for candidate in candidates {
                let token = SearchTextNormalization.normalize(candidate)
                let containsCJK = SearchTokenization.containsCJK(token)
                guard !token.isEmpty,
                    token.utf8.count <= 128,
                    containsCJK || token.count > 1,
                    containsCJK || !ignoredLatinTerms.contains(token)
                else {
                    continue
                }
                result.append(token)
            }
            current = ""
            currentIsCJK = nil
        }

        for scalar in normalized.unicodeScalars {
            let isCJK = SearchTokenization.isCJK(scalar)
            let isToken = CharacterSet.alphanumerics.contains(scalar)
            guard isCJK || isToken else {
                finish()
                continue
            }
            if let currentIsCJK, currentIsCJK != isCJK { finish() }
            currentIsCJK = isCJK
            current.unicodeScalars.append(scalar)
        }
        finish()
        return result
    }
}

enum SearchMatcher {
    /// Normalization belongs to the query, not each candidate segment. Include
    /// excluded and paragraph predicates so every branch uses the same policy.
    static func normalizedNeedles(for expression: SearchExpression) -> [SearchLexicalValue: String] {
        var result: [SearchLexicalValue: String] = [:]
        func collect(_ expression: SearchExpression) {
            for predicate in expression.predicates {
                switch predicate.clause {
                case .lexical(let clause):
                    if result[clause.value] == nil {
                        result[clause.value] = SearchTextNormalization.lexicalNormalize(clause.value.text)
                    }
                case .paragraph(let query): collect(query.expression)
                case .structured, .property, .link: break
                }
            }
        }
        collect(expression)
        return result
    }

    static func evaluate(
        _ ast: SearchQueryAST, document: StoredSearchDocument,
        linkMatches: [SearchLinkQuery: SearchLinkResolution],
        normalizedNeedles preparedNeedles: [SearchLexicalValue: String]? = nil
    ) -> SearchEvaluation {
        let needles = preparedNeedles ?? normalizedNeedles(for: ast.expression)
        return ast.expression.evaluate { clause in
            switch clause {
            case .lexical(let lexical):
                return matchingSegments(for: lexical, in: document).contains {
                    !occurrences(
                        of: lexical.value, in: $0.normalizedText,
                        normalizedNeedle: needles[lexical.value], firstOnly: true
                    ).isEmpty
                } ? .yes : .no
            case .structured(let structured):
                switch structured.field {
                case .callout: return document.calloutRoles.contains(structured.value) ? .yes : .no
                case .has: return structured.value == "broken-link" && document.hasBrokenLink ? .yes : .no
                }
            case .property(let property):
                let ambiguous = document.propertyIssues.contains { issue in
                    switch issue {
                    case .invalidYAML, .nonMappingRoot, .unboundedKey: true
                    case .duplicateKey(let key): key == property.key
                    case .unboundedScalarValue: false
                    }
                }
                if ambiguous { return .unknown }
                if propertyMatch(property, in: document) != nil { return .yes }
                if property.value != nil, document.propertyIssues.contains(.unboundedScalarValue(property.key)) { return .unknown }
                return .no
            case .paragraph(let query):
                if !paragraphWitnesses(query, document: document, normalizedNeedles: needles).isEmpty { return .yes }
                return document.paragraphsAreComplete ? .no : .unknown
            case .link(let query):
                guard let resolved = linkMatches[query] else { return .unknown }
                if resolved.matches[document.noteID] != nil { return .yes }
                return resolved.indeterminateNotes.contains(document.noteID) ? .unknown : .no
            }
        }
    }

    struct ParagraphWitness {
        let range: SearchSourceRange
        let document: StoredSearchDocument
        let ast: SearchQueryAST
    }
    static func paragraphWitnesses(_ ast: SearchQueryAST, document: StoredSearchDocument) -> [ParagraphWitness] {
        ast.positiveParagraphQueries.flatMap { paragraphWitnesses($0, document: document) }
    }
    static func paragraphWitnesses(
        _ query: SearchParagraphQuery, document: StoredSearchDocument,
        normalizedNeedles preparedNeedles: [SearchLexicalValue: String]? = nil
    ) -> [ParagraphWitness] {
        let needles = preparedNeedles ?? normalizedNeedles(for: query.expression)
        return document.paragraphs.compactMap { paragraph in
            let evaluation = query.expression.evaluate { clause in
                guard case .lexical(let value) = clause else { return .unknown }
                return paragraph.segments.contains {
                    !occurrences(
                        of: value.value, in: $0.normalizedText,
                        normalizedNeedle: needles[value.value], firstOnly: true
                    ).isEmpty
                } ? .yes : .no
            }
            guard evaluation.truth == .yes else { return nil }
            var local = document
            local.segments = paragraph.segments
            let ast = SearchQueryAST(provider: .note, providerWasExplicit: false, expression: query.expression, identityNeedle: nil).matched(by: evaluation)
            return ParagraphWitness(range: paragraph.range, document: local, ast: ast)
        }
    }

    static func propertyMatch(
        _ clause: SearchPropertyClause,
        in document: StoredSearchDocument
    ) -> SearchPropertyMatch? {
        guard
            let entry = document.properties.first(where: {
                $0.key == clause.key
                    && (clause.value == nil
                        || $0.stringMembers.contains {
                            $0.normalizedValue == clause.value
                        })
            })
        else { return nil }
        guard let value = clause.value else {
            return SearchPropertyMatch(
                key: entry.key,
                mode: .presence,
                normalizedValue: nil,
                valueKind: entry.valueKind,
                isEmpty: entry.isEmpty,
                keySourceRange: entry.keySourceRange
            )
        }
        let matchingMembers = entry.stringMembers.filter {
            $0.normalizedValue == value
        }
        guard !matchingMembers.isEmpty else { return nil }
        let ranges = matchingMembers.compactMap(\.sourceRange)
        return SearchPropertyMatch(
            key: entry.key,
            mode: .exactStringValue,
            normalizedValue: value,
            valueKind: entry.valueKind,
            isEmpty: entry.isEmpty,
            keySourceRange: entry.keySourceRange,
            valueSourceRanges: ranges
        )
    }

    static func identityPriority(
        identityNeedle: String?,
        document: StoredSearchDocument
    ) -> Int {
        guard let identityNeedle else { return 10 }
        if document.normalizedTitle == identityNeedle { return 0 }
        if document.aliases.contains(where: {
            SearchTextNormalization.normalize($0) == identityNeedle
        }) {
            return 1
        }
        if document.filenameKey == identityNeedle { return 2 }
        if document.pathKey == identityNeedle { return 3 }
        return 10
    }

    static func matchedFields(
        ast: SearchQueryAST,
        document: StoredSearchDocument
    ) -> [SearchMatchedField] {
        var fields: [SearchMatchedField] = []
        for clause in ast.positiveLexicalClauses {
            for segment in matchingSegments(for: clause, in: document)
            where !occurrences(of: clause.value, in: segment.normalizedText).isEmpty {
                if !fields.contains(segment.field) { fields.append(segment.field) }
            }
        }
        for paragraph in paragraphWitnesses(ast, document: document) {
            for field in matchedFields(ast: paragraph.ast, document: paragraph.document) where !fields.contains(field) {
                fields.append(field)
            }
        }
        if fields.isEmpty, ast.isFilterOnly {
            for clause in ast.clauses {
                let field: SearchMatchedField?
                switch clause {
                case .structured(let structured):
                    field =
                        switch structured.field {
                        case .callout: .callout
                        case .has: .brokenLink
                        }
                case .property, .link:
                    field = .title
                case .paragraph:
                    field = .title
                case .lexical:
                    field = nil
                }
                if let field, !fields.contains(field) { fields.append(field) }
            }
        }
        return fields
    }

    static func matchingSegments(
        for clause: SearchLexicalClause,
        in document: StoredSearchDocument
    ) -> [SearchTextSegment] {
        guard let field = clause.field else {
            return document.segments
        }
        let matched: SearchMatchedField =
            switch field {
            case .title: .title
            case .alias: .alias
            case .heading: .heading
            case .summary: .summary
            case .body: .body
            case .author: .author
            case .publicationDate: .publicationDate
            case .tag: .tag
            case .footnote: .footnote
            case .linkAnnotation: .linkAnnotation
            case .path: .path
            }
        return document.segments.filter { $0.field == matched }
    }

    static func occurrences(
        of value: SearchLexicalValue,
        in normalizedText: String,
        normalizedNeedle: String? = nil,
        firstOnly: Bool = false
    ) -> [Range<Int>] {
        var result: [Range<Int>] = []
        scanOccurrences(of: value, in: normalizedText, normalizedNeedle: normalizedNeedle) { range in
            let lowerBound = range.lowerBound.utf16Offset(in: normalizedText)
            let upperBound = range.upperBound.utf16Offset(in: normalizedText)
            result.append(lowerBound..<upperBound)
            return !firstOnly
        }
        return result
    }

    static func occurrenceCount(
        of value: SearchLexicalValue, in normalizedText: String, normalizedNeedle: String? = nil
    ) -> Int {
        var count = 0
        scanOccurrences(of: value, in: normalizedText, normalizedNeedle: normalizedNeedle) { _ in
            count += 1
            return true
        }
        return count
    }

    static func containsOccurrence(
        of value: SearchLexicalValue, in normalizedText: String, normalizedNeedle: String
    ) -> Bool {
        var found = false
        scanOccurrences(of: value, in: normalizedText, normalizedNeedle: normalizedNeedle) { _ in
            found = true
            return false
        }
        return found
    }

    static func scanOccurrences(
        of value: SearchLexicalValue, in normalizedText: String, normalizedNeedle: String?,
        visit: (Range<String.Index>) -> Bool
    ) {
        let needle = normalizedNeedle ?? SearchTextNormalization.lexicalNormalize(value.text)
        guard !needle.isEmpty, !normalizedText.isEmpty else { return }
        let hasCJKStart = beginsWithCJK(value.text)
        let hasCJKEnd = endsWithCJK(value.text)
        // Both comparison forms are NFC-normalized before matching. Literal
        // search avoids repeating Unicode equivalence work for every term and
        // segment; exact source locations still come from the checked maps.
        var cursor = normalizedText.startIndex
        while cursor < normalizedText.endIndex {
            guard var range = normalizedText.range(of: needle, options: .literal, range: cursor..<normalizedText.endIndex) else { return }
            // Literal lookup can stop inside an extended grapheme such as a
            // letter plus enclosing mark. Preserve canonical search semantics
            // for that exceptional case instead of publishing a partial match.
            if range.lowerBound.samePosition(in: normalizedText) == nil || range.upperBound.samePosition(in: normalizedText) == nil {
                guard let canonical = normalizedText.range(of: needle, range: cursor..<normalizedText.endIndex) else { return }
                range = canonical
            }
            let leadingBoundary =
                hasCJKStart
                || isTokenBoundary(before: range.lowerBound, in: normalizedText)
            let trailingBoundary: Bool
            switch value {
            case .prefix: trailingBoundary = true
            case .phrase, .term:
                trailingBoundary =
                    hasCJKEnd
                    || isTokenBoundary(after: range.upperBound, in: normalizedText)
            }
            if leadingBoundary && trailingBoundary && !visit(range) { return }
            cursor = range.upperBound
        }
    }

    static func ftsExpression(for clauses: [SearchLexicalClause]) -> String {
        clauses.map { clause in
            let tokens = SearchTokenization.queryTokens(for: clause.value.text)
            let terms: [String]
            if tokens.isEmpty {
                terms = [clause.value.text]
            } else {
                terms = tokens
            }
            let expression = terms.map { token in
                let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\"" + (clause.value.isPrefix ? "*" : "")
            }.joined(separator: " AND ")
            let grouped = terms.count > 1 ? "(\(expression))" : expression
            guard let field = clause.field else { return grouped }
            let column: String =
                switch field {
                case .title: "title"
                case .alias: "aliases"
                case .heading: "headings"
                case .summary: "summary"
                case .body: "body"
                case .author: "authors"
                case .publicationDate: "publication_date"
                case .tag: "tags"
                case .footnote: "footnotes"
                case .linkAnnotation: "link_annotations"
                case .path: "path"
                }
            return "\(column):\(grouped)"
        }.joined(separator: " AND ")
    }

    static func isTokenBoundary(before index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else { return true }
        return !isTokenCharacter(text[text.index(before: index)])
    }

    static func beginsWithCJK(_ value: String) -> Bool {
        value.unicodeScalars.first.map(SearchTokenization.isCJK) ?? false
    }

    static func endsWithCJK(_ value: String) -> Bool {
        value.unicodeScalars.last.map(SearchTokenization.isCJK) ?? false
    }

    static func isTokenBoundary(after index: String.Index, in text: String) -> Bool {
        guard index < text.endIndex else { return true }
        return !isTokenCharacter(text[index])
    }

    static func isTokenCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_"
        }
    }
}

enum NoteSearchResultBuilder {
    static func hit(
        candidate: SearchCandidate,
        ast: SearchQueryAST,
        freshness: SearchFreshnessToken,
        linkMatches: [SearchLinkQuery: SearchLinkResolution]
    ) -> NoteSearchResult {
        let document = candidate.document
        let matchedFields = SearchMatcher.matchedFields(ast: ast, document: document)
        let primary = matchedFields.first ?? .title
        let paragraphs = SearchMatcher.paragraphWitnesses(ast, document: document)
        let paragraphLead = paragraphs.first
        let snippetAST = ast.positiveLexicalClauses.isEmpty ? (paragraphLead?.ast ?? ast) : ast
        let snippetDocument = ast.positiveLexicalClauses.isEmpty ? (paragraphLead?.document ?? document) : document
        let matched = firstMatch(ast: snippetAST, document: snippetDocument, preferredField: primary)
        let reasons = matchReasons(
            ast: ast,
            document: document,
            linkMatches: linkMatches
        )
        let property = reasons.compactMap { reason -> SearchPropertyMatch? in
            guard case .property(let value) = reason else { return nil }
            return value
        }.first
        let presentation: (text: String, highlights: [SearchHighlight])
        if let matched {
            presentation = snippet(
                segment: matched.segment,
                normalizedRange: matched.range,
                positiveClauses: snippetAST.positiveLexicalClauses
            )
        } else if let property,
            let entry = document.properties.first(where: {
                $0.key == property.key && $0.keySourceRange == property.keySourceRange
            })
        {
            let value = entry.stringMembers.first(where: {
                $0.normalizedValue == property.normalizedValue
            })?.value
            presentation = (value.map { "\(entry.key): \($0)" } ?? entry.key, [])
        } else {
            presentation = snippet(
                segment: document.segments.first { $0.field == .title },
                normalizedRange: nil,
                positiveClauses: ast.positiveLexicalClauses
            )
        }
        let lexicalSourceRange = matched.flatMap {
            sourceRange(for: $0.range, segment: $0.segment, lineStarts: document.sourceLineStarts)
        }
        // Named apart from sourceRange(for:segment:lineStarts:) above: a local
        // constant sharing that name is in scope inside the closure that calls
        // the method, and older compilers than this file was written against
        // read the pair as a circular reference rather than a shadow.
        let matchSourceRange =
            lexicalSourceRange
            ?? property?.valueSourceRanges.first
            ?? property?.keySourceRange
        let reason = rankReason(candidate.identityPriority, filterOnly: ast.isFilterOnly)
        return NoteSearchResult(
            resultID: "\(document.vaultID.uuidString.lowercased()):\(document.relativePath):\(matchSourceRange?.utf16LowerBound ?? -1)",
            vaultID: document.vaultID,
            vaultName: document.vaultName,
            vaultRole: document.vaultRole,
            relativePath: document.relativePath,
            stableNoteID: document.stableNoteID,
            title: document.title,
            matchedField: primary,
            context: context(for: primary),
            sourceLine: matchSourceRange?.line ?? 1,
            snippet: presentation.text,
            highlights: presentation.highlights,
            matchedFields: matchedFields,
            rankReason: reason,
            primaryMatchReason: reasons.first ?? .lexical,
            additionalMatchReasons: Array(reasons.dropFirst()),
            paragraphRanges: Array(Set(paragraphs.map(\.range))).sorted { $0.utf16LowerBound < $1.utf16LowerBound },
            sourceRange: matchSourceRange,
            freshnessToken: freshness,
            fingerprint: document.fingerprint,
            evidentialLayer: document.evidentialLayer,
            classification: .retrievalLead
        )
    }

    static func occurrenceHits(
        candidate: SearchCandidate,
        ast: SearchQueryAST,
        freshness: SearchFreshnessToken,
        limit: Int,
        linkMatches: [SearchLinkQuery: SearchLinkResolution]
    ) -> [NoteSearchResult] {
        let document = candidate.document
        let matchedFields = SearchMatcher.matchedFields(ast: ast, document: document)
        let reasons = matchReasons(
            ast: ast,
            document: document,
            linkMatches: linkMatches
        )
        var hits: [NoteSearchResult] = []
        for lead in ast.positiveLexicalClauses {
            for segment in SearchMatcher.matchingSegments(for: lead, in: document) {
                for range in SearchMatcher.occurrences(of: lead.value, in: segment.normalizedText) {
                    let sourceRange = sourceRange(
                        for: range,
                        segment: segment,
                        lineStarts: document.sourceLineStarts
                    )
                    let presentation = snippet(
                        segment: segment,
                        normalizedRange: range,
                        positiveClauses: ast.positiveLexicalClauses
                    )
                    hits.append(
                        NoteSearchResult(
                            resultID:
                                "\(document.vaultID.uuidString.lowercased()):\(document.relativePath):\(sourceRange?.utf16LowerBound ?? segment.ordinal):\(sourceRange?.utf16UpperBound ?? segment.ordinal)",
                            vaultID: document.vaultID,
                            vaultName: document.vaultName,
                            vaultRole: document.vaultRole,
                            relativePath: document.relativePath,
                            stableNoteID: document.stableNoteID,
                            title: document.title,
                            matchedField: segment.field,
                            context: context(for: segment.field),
                            sourceLine: sourceRange?.line ?? 1,
                            snippet: presentation.text,
                            highlights: presentation.highlights,
                            matchedFields: matchedFields,
                            rankReason: rankReason(candidate.identityPriority, filterOnly: ast.isFilterOnly),
                            primaryMatchReason: reasons.first ?? .lexical,
                            additionalMatchReasons: Array(reasons.dropFirst()),
                            sourceRange: sourceRange,
                            freshnessToken: freshness,
                            fingerprint: document.fingerprint,
                            evidentialLayer: document.evidentialLayer,
                            classification: .retrievalLead
                        ))
                }
            }
        }
        for paragraph in SearchMatcher.paragraphWitnesses(ast, document: document) {
            let local = SearchCandidate(document: paragraph.document, identityPriority: 0, lexicalRank: candidate.lexicalRank)
            hits.append(contentsOf: occurrenceHits(candidate: local, ast: paragraph.ast, freshness: freshness, limit: limit, linkMatches: linkMatches))
        }
        var seen: Set<String> = []
        return Array(
            hits.sorted {
                ($0.sourceRange?.utf16LowerBound ?? 0, $0.sourceRange?.utf16UpperBound ?? 0) < (
                    $1.sourceRange?.utf16LowerBound ?? 0, $1.sourceRange?.utf16UpperBound ?? 0
                )
            }.filter { seen.insert($0.resultID).inserted }.prefix(limit))
    }

    static func matchReasons(
        ast: SearchQueryAST,
        document: StoredSearchDocument,
        linkMatches: [SearchLinkQuery: SearchLinkResolution]
    ) -> [NoteSearchMatchReason] {
        var reasons: [NoteSearchMatchReason] = []
        if !ast.positiveLexicalClauses.isEmpty { reasons.append(.lexical) }
        for predicate in ast.expression.predicates {
            let clause = predicate.clause
            if predicate.excluded {
                if case .structured(let value) = clause {
                    reasons.append(.structured(SearchStructuredMatch(field: value.field, value: value.value, excluded: true)))
                } else {
                    reasons.append(.excluded(clause))
                }
                continue
            }
            switch clause {
            case .paragraph(let value): reasons.append(.paragraph(value))
            case .structured(let value):
                reasons.append(
                    .structured(
                        SearchStructuredMatch(
                            field: value.field,
                            value: value.value,
                            excluded: false
                        )))
            case .property(let value):
                if let match = SearchMatcher.propertyMatch(value, in: document) {
                    reasons.append(.property(match))
                }
            case .link(let query):
                if let linkMatch = linkMatches[query]?.matches[document.noteID] {
                    reasons.append(.link(linkMatch))
                }
            case .lexical:
                continue
            }
        }
        if reasons.isEmpty { reasons.append(.lexical) }
        return reasons
    }

    static func firstMatch(
        ast: SearchQueryAST,
        document: StoredSearchDocument,
        preferredField: SearchMatchedField
    ) -> (segment: SearchTextSegment, range: Range<Int>)? {
        for clause in ast.positiveLexicalClauses {
            let segments = SearchMatcher.matchingSegments(for: clause, in: document)
                .sorted { ($0.field == preferredField ? 0 : 1) < ($1.field == preferredField ? 0 : 1) }
            for segment in segments {
                if let range = SearchMatcher.occurrences(
                    of: clause.value,
                    in: segment.normalizedText
                ).first {
                    return (segment, range)
                }
            }
        }
        return nil
    }

    static func sourceRange(
        for normalizedRange: Range<Int>,
        segment: SearchTextSegment,
        lineStarts: [Int]
    ) -> SearchSourceRange? {
        guard let range = segment.sourceUTF16Range(forNormalizedUTF16Range: normalizedRange) else {
            return segment.sourceRange
        }
        let start = position(range.lowerBound, lineStarts: lineStarts)
        let end = position(range.upperBound, lineStarts: lineStarts)
        return SearchSourceRange(
            utf16LowerBound: range.lowerBound,
            utf16UpperBound: range.upperBound,
            line: start.line,
            column: start.column,
            endLine: end.line,
            endColumn: end.column
        )
    }

    static func position(
        _ offset: Int,
        lineStarts: [Int]
    ) -> (line: Int, column: Int) {
        guard !lineStarts.isEmpty else { return (1, offset + 1) }
        var low = 0
        var high = lineStarts.count
        while low + 1 < high {
            let middle = (low + high) / 2
            if lineStarts[middle] <= offset { low = middle } else { high = middle }
        }
        return (low + 1, offset - lineStarts[low] + 1)
    }

    static func snippet(
        segment: SearchTextSegment?,
        normalizedRange: Range<Int>?,
        positiveClauses: [SearchLexicalClause]
    ) -> (text: String, highlights: [SearchHighlight]) {
        guard let segment else { return ("", []) }
        let source = segment.text
        let targetUTF16 =
            normalizedRange.flatMap {
                SearchTextNormalization.originalUTF16RangeForLexicalNormalization(
                    in: source,
                    requestedRange: $0
                )
            } ?? 0..<0
        let boundedLower = min(max(0, targetUTF16.lowerBound), source.utf16.count)
        let boundedUpper = min(max(boundedLower, targetUTF16.upperBound), source.utf16.count)
        let boundedTarget = boundedLower..<boundedUpper
        let targetLower = String.Index(utf16Offset: boundedTarget.lowerBound, in: source)
        let targetUpper = String.Index(utf16Offset: boundedTarget.upperBound, in: source)
        let totalCharacters = source.count
        let targetStart = source.distance(from: source.startIndex, to: targetLower)
        let targetEnd = source.distance(from: source.startIndex, to: targetUpper)
        var lowerPosition = max(0, targetStart - 80)
        var upperPosition = min(totalCharacters, max(targetEnd, targetStart) + 160)
        for _ in 0..<3 {
            let decorations =
                (lowerPosition > 0 ? 1 : 0)
                + (upperPosition < totalCharacters ? 1 : 0)
            let allowed = max(1, 240 - decorations)
            guard upperPosition - lowerPosition > allowed else { break }
            upperPosition = lowerPosition + allowed
            if upperPosition < targetEnd {
                upperPosition = min(totalCharacters, targetEnd)
                lowerPosition = max(0, upperPosition - allowed)
            }
        }
        let lower = source.index(source.startIndex, offsetBy: lowerPosition)
        let upper = source.index(source.startIndex, offsetBy: upperPosition)
        let prefix = lowerPosition == 0 ? "" : "…"
        let suffix = upperPosition == totalCharacters ? "" : "…"
        let coreSource = String(source[lower..<upper])

        var core = ""
        var displayOffsets: [(original: Range<Int>, displayed: Range<Int>)] = []
        var originalCursor = 0
        for character in coreSource {
            let originalLength = String(character).utf16.count
            let displayed = character.isWhitespace ? " " : String(character)
            let displayedLower = core.utf16.count
            core += displayed
            displayOffsets.append(
                (
                    originalCursor..<(originalCursor + originalLength),
                    displayedLower..<core.utf16.count
                ))
            originalCursor += originalLength
        }
        let text = prefix + core + suffix
        let contextLowerUTF16 = lower.utf16Offset(in: source)
        let contextUpperUTF16 = upper.utf16Offset(in: source)
        let prefixUTF16 = prefix.utf16.count
        var highlights: [SearchHighlight] = []
        for (clauseIndex, clause) in positiveClauses.enumerated() {
            let occurrences =
                clauseIndex == 0 && normalizedRange != nil
                ? [normalizedRange!]
                : SearchMatcher.occurrences(
                    of: clause.value,
                    in: segment.normalizedText
                )
            for normalizedOccurrence in occurrences {
                guard
                    let original = SearchTextNormalization.originalUTF16RangeForLexicalNormalization(
                        in: source,
                        requestedRange: normalizedOccurrence
                    ), original.lowerBound >= contextLowerUTF16,
                    original.upperBound <= contextUpperUTF16
                else { continue }
                let relativeLower = original.lowerBound - contextLowerUTF16
                let relativeUpper = original.upperBound - contextLowerUTF16
                let relative = relativeLower..<relativeUpper
                let overlapping = displayOffsets.filter {
                    $0.original.lowerBound < relative.upperBound
                        && $0.original.upperBound > relative.lowerBound
                }
                guard let first = overlapping.first, let last = overlapping.last else { continue }
                highlights.append(
                    SearchHighlight(
                        utf16LowerBound: prefixUTF16 + first.displayed.lowerBound,
                        utf16UpperBound: prefixUTF16 + last.displayed.upperBound
                    ))
            }
        }
        let uniqueHighlights = Array(Set(highlights)).sorted {
            if $0.utf16LowerBound != $1.utf16LowerBound {
                return $0.utf16LowerBound < $1.utf16LowerBound
            }
            return $0.utf16UpperBound < $1.utf16UpperBound
        }
        return (text, uniqueHighlights)
    }

    static func rankReason(
        _ identityPriority: Int,
        filterOnly: Bool
    ) -> SearchRankReason {
        switch identityPriority {
        case 0: .exactTitle
        case 1: .exactAlias
        case 2: .exactFilename
        case 3: .exactPath
        default: filterOnly ? .structuredFilter : .lexicalRelevance
        }
    }

    static func context(for field: SearchMatchedField) -> String {
        switch field {
        case .title: "Title"
        case .alias: "Alias"
        case .heading: "Heading"
        case .summary: "Summary"
        case .author: "Author"
        case .publicationDate: "Publication Date"
        case .tag: "Keyword"
        case .body: "Body"
        case .callout: "Callout"
        case .footnote: "Footnote"
        case .linkAnnotation: "Link Annotation"
        case .brokenLink: "Broken link"
        case .path: "Path"
        }
    }
}
