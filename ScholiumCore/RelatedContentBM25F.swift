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

    static func evaluate(documents: [Document], terms: [String], roles: [VaultRole]? = nil) throws -> Evaluation {
        guard roles == nil || roles?.count == documents.count else {
            throw SearchIndexError.invalidDocuments("Related-content roles must correspond to every scoring document.")
        }
        let terms = Array(Set(terms)).sorted()
        guard !documents.isEmpty, !terms.isEmpty else {
            let zero = Array(repeating: 0.0, count: documents.count)
            return Evaluation(scores: zero, coverage: zero, hasDistinctiveMatch: Array(repeating: false, count: documents.count))
        }
        let matcher = RelatedContentTermMatcher(terms: terms)
        let fields = RelatedContentRankingField.allCases
        var average = Array(repeating: 0.0, count: fields.count)
        var nonempty = Array(repeating: 0.0, count: fields.count)
        for document in documents {
            try Task.checkCancellation()
            for (f, field) in fields.enumerated() {
                let length = document.fieldLengths[field.rawValue] ?? 0
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
        frequencies.reserveCapacity(documents.count)
        var documentFrequency = Array(repeating: 0.0, count: terms.count)
        for (d, document) in documents.enumerated() {
            try Task.checkCancellation()
            let fieldParameters = parametersByRole[roles?[d] ?? .other]!
            var frequency = Array(repeating: 0.0, count: terms.count)
            // Absent fields contribute zero. Normalize each present field once,
            // and retain only the per-term sum, in the original field order.
            // This avoids a document x field x term matrix and repeated field
            // normalization without changing corpus statistics or arithmetic.
            for (f, field) in fields.enumerated() {
                guard let text = document.fields[field.rawValue] else { continue }
                let p = fieldParameters[f]
                let normalization = 1 - p.length + p.length * (document.fieldLengths[field.rawValue] ?? 0) / average[f]
                let counts =
                    document.textIndexes[field.rawValue].map { matcher.counts(in: text, index: $0) }
                    ?? Array(repeating: 0, count: terms.count)
                for t in terms.indices {
                    frequency[t] += p.weight * Double(counts[t]) / normalization
                }
            }
            for t in terms.indices where frequency[t] > 0 { documentFrequency[t] += 1 }
            frequencies.append(frequency)
        }
        let k1 = 1.2
        let information = documentFrequency.map { log(1 + (Double(documents.count) - $0 + 0.5) / ($0 + 0.5)) }
        // Absent vocabulary cannot supply comparison information. In particular,
        // an unmatched script must not drown out the authored bilingual anchors.
        let totalInformation = information.indices.reduce(0.0) { $0 + (documentFrequency[$1] > 0 ? information[$1] : 0) }
        var coverage = Array(repeating: 0.0, count: documents.count)
        var distinctive = Array(repeating: false, count: documents.count)
        let scores = try documents.indices.map { d in
            try Task.checkCancellation()
            return terms.indices.reduce(0.0) { score, t in
                let frequency = frequencies[d][t]
                let idf = information[t]
                if frequency > 0 {
                    coverage[d] += idf / totalInformation
                    if documentFrequency[t] <= max(1, Double(documents.count) * 0.2) { distinctive[d] = true }
                }
                return score + idf * (k1 + 1) * frequency / (k1 + frequency)
            }
        }
        return Evaluation(scores: scores, coverage: coverage, hasDistinctiveMatch: distinctive)
    }
}
