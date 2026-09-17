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
            Set(fields.keys).isSubset(of: Set(RelatedContentRankingField.allCases.map(\.rawValue)))
                && Set(fields.keys) == Set(fieldLengths.keys)
                && Set(textIndexes.keys) == Set(fields.keys)
                && fieldLengths.values.allSatisfy { $0.isFinite && $0 >= 0 }
                && textIndexes.values.allSatisfy(\.isValid)
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
        var lengths = [[Double]]()
        var frequencies = [[[Double]]]()
        var average = Array(repeating: 0.0, count: fields.count)
        var nonempty = Array(repeating: 0.0, count: fields.count)
        var documentFrequency = Array(repeating: 0.0, count: terms.count)
        for document in documents {
            try Task.checkCancellation()
            var fieldLengths = [Double]()
            var fieldFrequencies = [[Double]]()
            var present = Set<Int>()
            for (f, field) in fields.enumerated() {
                let text = document.fields[field.rawValue] ?? ""
                let length = document.fieldLengths[field.rawValue] ?? 0
                fieldLengths.append(length)
                if length > 0 {
                    average[f] += length
                    nonempty[f] += 1
                }
                let counts =
                    document.textIndexes[field.rawValue].map { matcher.counts(in: text, index: $0) }
                    ?? Array(repeating: 0, count: terms.count)
                for (t, count) in counts.enumerated() where count > 0 { present.insert(t) }
                fieldFrequencies.append(counts.map(Double.init))
            }
            for t in present { documentFrequency[t] += 1 }
            lengths.append(fieldLengths)
            frequencies.append(fieldFrequencies)
        }
        for f in fields.indices { average[f] = nonempty[f] > 0 ? average[f] / nonempty[f] : 1 }
        let k1 = 1.2
        let information = documentFrequency.map { log(1 + (Double(documents.count) - $0 + 0.5) / ($0 + 0.5)) }
        // Absent vocabulary cannot supply comparison information. In particular,
        // an unmatched script must not drown out the authored bilingual anchors.
        let totalInformation = information.indices.reduce(0.0) { $0 + (documentFrequency[$1] > 0 ? information[$1] : 0) }
        var coverage = Array(repeating: 0.0, count: documents.count)
        var distinctive = Array(repeating: false, count: documents.count)
        let scores = try documents.indices.map { d in
            try Task.checkCancellation()
            let fieldParameters = fields.map { parameters($0, role: roles?[d]) }
            return terms.indices.reduce(0.0) { score, t in
                var frequency = 0.0
                for f in fields.indices {
                    let p = fieldParameters[f]
                    let normalization = 1 - p.length + p.length * lengths[d][f] / average[f]
                    frequency += p.weight * frequencies[d][f][t] / normalization
                }
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
