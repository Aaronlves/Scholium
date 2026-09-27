import Foundation
import ScholiumContracts

/// One scoring rule for candidate Notes and current-source passages. Statistics
/// are local to each eligible comparison set; scores from stages are never added.
struct RelatedContentBM25F {
    struct Document: Codable, Sendable {
        /// Query-independent comparison text and tokenizer lengths.
        let fields: [String: String]
        let fieldLengths: [String: Double]
        let textIndexes: [String: RelatedContentTextIndex]
        init(segments: [SearchTextSegment]) {
            var result: [String: String] = [:]
            for segment in segments {
                for (field, text) in segment.relatedRankingText {
                    result[field, default: ""] += "\n" + text
                }
            }
            fields = result.mapValues(SearchTextNormalization.lexicalNormalize)
            textIndexes = fields.mapValues(RelatedContentTextIndex.init)
            fieldLengths = fields.mapValues { text in
                Double(
                    text.split { !$0.isLetter && !$0.isNumber }.reduce(0) { total, word in
                        let asciiWord = word.utf8.allSatisfy {
                            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                        }
                        return total + (asciiWord ? 1 : SearchTokenization.queryTokens(for: String(word)).count)
                    })
            }
        }

        var estimatedByteCount: Int {
            128 + fields.reduce(0) { $0 + 64 + $1.key.utf8.count + $1.value.utf8.count }
                + fieldLengths.count * 64
                + textIndexes.values.reduce(0) { $0 + $1.estimatedByteCount }
        }

        var isValid: Bool {
            // RelatedContentTextIndex validates its immutable packed words
            // while constructing or decoding them.
            Set(fields.keys).isSubset(of: Set(RelatedContentRankingField.allCases.map(\.rawValue)))
                && Set(fields.keys) == Set(fieldLengths.keys)
                && Set(textIndexes.keys) == Set(fields.keys)
                && fieldLengths.values.allSatisfy { $0.isFinite && $0 >= 0 }
        }

        /// Matching and scoring often retain the same normalized prose and word
        /// counts. Share immutable Swift storage only after exact value checks;
        /// independently decoded dictionaries do not share through COW alone.
        func sharingPreparedText(
            _ text: String, index: RelatedContentTextIndex
        ) -> (text: String, index: RelatedContentTextIndex) {
            guard let field = matchingPreparedField(text, index: index) else { return (text, index) }
            return (fields[field]!, textIndexes[field]!)
        }

        /// Private persisted references avoid decoding duplicate normalized
        /// strings and frequency dictionaries only to discard them afterward.
        enum StoredText: Codable {
            case scoringField(String)
            case independent(text: String, index: RelatedContentTextIndex)

            func resolve(in document: Document) throws -> (text: String, index: RelatedContentTextIndex) {
                switch self {
                case .scoringField(let field):
                    guard let text = document.fields[field], let index = document.textIndexes[field] else {
                        throw SearchIndexError.corruptDatabase
                    }
                    return (text, index)
                case .independent(let text, let index):
                    return (text, index)
                }
            }
        }

        func storedText(_ text: String, index: RelatedContentTextIndex) -> StoredText {
            if let field = matchingPreparedField(text, index: index) { return .scoringField(field) }
            return .independent(text: text, index: index)
        }

        private func matchingPreparedField(_ text: String, index: RelatedContentTextIndex) -> String? {
            for (field, candidate) in fields {
                guard candidate.utf8.elementsEqual(text.utf8),
                    let candidateIndex = textIndexes[field],
                    candidateIndex.containsCJK == index.containsCJK,
                    candidateIndex.hasSameWordCounts(as: index)
                else { continue }
                return field
            }
            return nil
        }
    }

    static func parameters(_ field: RelatedContentRankingField, role: VaultRole? = nil) -> (weight: Double, length: Double) {
        let baseline: (weight: Double, length: Double) =
            switch field {
            case .annotation: (8, 0.30)
            case .link: (5, 0.20)
            case .keyword, .title: (4, 0)
            case .summary: (3, 0.50)
            case .heading: (2, 0.30)
            case .body: (1, 0.75)
            }
        // Registered roles supply authored-structure priors, never a claim
        // that a Note supports an argument or is more authoritative. Preserve
        // shared statistics and normalization; there is no whole-role boost.
        let weight: Double =
            switch (role ?? .other, field) {
            case (.sourceCorpus, .title): 5
            case (.sourceCorpus, .summary): 4
            case (.topicKnowledge, .title), (.topicKnowledge, .keyword): 5
            case (.topicKnowledge, .heading): 4
            case (.draftProject, .keyword): 3
            case (.draftProject, .summary): 2
            case (.draftProject, .heading): 4
            case (.draftProject, .body): 3
            default: baseline.weight
            }
        return (weight, baseline.length)
    }

    static func scores(documents: [Document], terms: [String], roles: [VaultRole]? = nil) throws -> [Double] {
        try evaluate(documents: documents, terms: terms, roles: roles).scores
    }

    struct Evaluation {
        let scores: [Double]
        /// Fraction of query information occurring locally, independent of
        /// repeated occurrences and field weights. Not semantic confidence.
        let coverage: [Double]
        let hasDistinctiveMatch: [Bool]
    }

    /// Query-bound scalar material for an FTS candidate. The complete lexical
    /// projection may be released after this is prepared; it owns no field text
    /// or word index. Passage scoring continues to read its full Documents.
    struct PreparedCorpus {
        struct Row {
            let fieldLengths: [String: Double]
            let countsByField: [String: [Int]]
        }

        let terms: [String]
        fileprivate let matcher: RelatedContentTermMatcher
        private(set) var rows: [Row] = []

        init(terms: [String]) {
            self.terms = Array(Set(terms)).sorted()
            matcher = RelatedContentTermMatcher(terms: self.terms)
        }

        mutating func append(_ document: Document) throws {
            var countsByField: [String: [Int]] = [:]
            for field in RelatedContentRankingField.allCases {
                try Task.checkCancellation()
                guard let text = document.fields[field.rawValue] else { continue }
                countsByField[field.rawValue] =
                    document.textIndexes[field.rawValue].map { matcher.counts(in: text, index: $0) }
                    ?? Array(repeating: 0, count: terms.count)
            }
            rows.append(.init(fieldLengths: document.fieldLengths, countsByField: countsByField))
        }
    }

    static func evaluate(documents: [Document], terms: [String], roles: [VaultRole]? = nil) throws -> Evaluation {
        let terms = Array(Set(terms)).sorted()
        return try evaluate(
            rows: documents, terms: terms, matcher: .init(terms: terms), roles: roles,
            fieldLength: { $0.fieldLengths[$1] ?? 0 },
            fieldCounts: { document, field, matcher in
                guard let text = document.fields[field] else { return nil }
                return document.textIndexes[field].map { matcher.counts(in: text, index: $0) }
                    ?? Array(repeating: 0, count: terms.count)
            })
    }

    static func evaluate(prepared corpus: PreparedCorpus, roles: [VaultRole]? = nil) throws -> Evaluation {
        try evaluate(
            rows: corpus.rows, terms: corpus.terms, matcher: corpus.matcher, roles: roles,
            fieldLength: { $0.fieldLengths[$1] ?? 0 },
            fieldCounts: { row, field, _ in row.countsByField[field] })
    }

    private static func evaluate<Row>(
        rows: [Row], terms: [String], matcher: RelatedContentTermMatcher,
        roles: [VaultRole]?, fieldLength: (Row, String) -> Double,
        fieldCounts: (Row, String, RelatedContentTermMatcher) -> [Int]?
    ) throws -> Evaluation {
        guard roles == nil || roles?.count == rows.count else {
            throw SearchIndexError.invalidDocuments("Related-content roles must correspond to every scoring document.")
        }
        guard !rows.isEmpty, !terms.isEmpty else {
            let zero = Array(repeating: 0.0, count: rows.count)
            return Evaluation(scores: zero, coverage: zero, hasDistinctiveMatch: Array(repeating: false, count: rows.count))
        }
        let fields = RelatedContentRankingField.allCases
        var average = Array(repeating: 0.0, count: fields.count)
        var nonempty = Array(repeating: 0.0, count: fields.count)
        for row in rows {
            try Task.checkCancellation()
            for (f, field) in fields.enumerated() {
                let length = fieldLength(row, field.rawValue)
                if length > 0 {
                    average[f] += length
                    nonempty[f] += 1
                }
            }
        }
        for f in fields.indices { average[f] = nonempty[f] > 0 ? average[f] / nonempty[f] : 1 }
        let parametersByRole = Dictionary(
            uniqueKeysWithValues: Set(roles ?? [.other]).map { role in
                (role, fields.map { parameters($0, role: role) })
            })
        var frequencies = [[Double]]()
        frequencies.reserveCapacity(rows.count)
        var documentFrequency = Array(repeating: 0.0, count: terms.count)
        for (d, row) in rows.enumerated() {
            try Task.checkCancellation()
            let fieldParameters = parametersByRole[roles?[d] ?? .other]!
            var frequency = Array(repeating: 0.0, count: terms.count)
            // Absent fields contribute zero. Fold each present field once in
            // the original order. Full passage Documents compute term counts
            // transiently; compact candidates already carry those counts.
            for (f, field) in fields.enumerated() {
                guard let counts = fieldCounts(row, field.rawValue, matcher) else { continue }
                let p = fieldParameters[f]
                let normalization = 1 - p.length + p.length * fieldLength(row, field.rawValue) / average[f]
                for t in terms.indices {
                    frequency[t] += p.weight * Double(counts[t]) / normalization
                }
            }
            for t in terms.indices where frequency[t] > 0 { documentFrequency[t] += 1 }
            frequencies.append(frequency)
        }
        let k1 = 1.2
        let information = documentFrequency.map { log(1 + (Double(rows.count) - $0 + 0.5) / ($0 + 0.5)) }
        // Absent vocabulary cannot supply comparison information. In particular,
        // an unmatched script must not drown out the authored bilingual anchors.
        let totalInformation = information.indices.reduce(0.0) { $0 + (documentFrequency[$1] > 0 ? information[$1] : 0) }
        var coverage = Array(repeating: 0.0, count: rows.count)
        var distinctive = Array(repeating: false, count: rows.count)
        let scores = try rows.indices.map { d in
            try Task.checkCancellation()
            return terms.indices.reduce(0.0) { score, t in
                let frequency = frequencies[d][t]
                let idf = information[t]
                if frequency > 0 {
                    coverage[d] += idf / totalInformation
                    if documentFrequency[t] <= max(1, Double(rows.count) * 0.2) { distinctive[d] = true }
                }
                return score + idf * (k1 + 1) * frequency / (k1 + frequency)
            }
        }
        return Evaluation(scores: scores, coverage: coverage, hasDistinctiveMatch: distinctive)
    }
}
