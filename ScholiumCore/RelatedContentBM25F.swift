import Foundation
import ScholiumContracts

/// One scoring rule for candidate Notes and current-source passages. Statistics
/// are local to each eligible comparison set; scores from stages are never added.
struct RelatedContentBM25F {
    struct Document {
        let fields: [String: String]
        init(segments: [SearchTextSegment]) {
            var result: [String: String] = [:]
            for segment in segments {
                for (field, text) in segment.relatedRankingText {
                    result[field, default: ""] += "\n" + text
                }
            }
            fields = result
        }
    }

    static func parameters(_ field: RelatedContentRankingField) -> (weight: Double, length: Double) {
        switch field {
        case .annotation: (8, 0.30)
        case .link: (5, 0.20)
        case .keyword, .title: (4, 0)
        case .summary: (3, 0.50)
        case .heading: (2, 0.30)
        case .body: (1, 0.75)
        }
    }

    static func scores(documents: [Document], terms: [String]) throws -> [Double] {
        let terms = Array(Set(terms)).sorted()
        guard !documents.isEmpty, !terms.isEmpty else { return Array(repeating: 0, count: documents.count) }
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
                let text = SearchTextNormalization.lexicalNormalize(document.fields[field.rawValue] ?? "")
                // Analyze the source projection once, without FTS's appended CJK
                // expansion string. Query tokens are also used for CJK lengths.
                let words = text.split { !$0.isLetter && !$0.isNumber }
                let length = Double(words.reduce(0) { $0 + SearchTokenization.queryTokens(for: String($1)).count })
                fieldLengths.append(length)
                if length > 0 {
                    average[f] += length
                    nonempty[f] += 1
                }
                var tf = [Double]()
                for (t, term) in terms.enumerated() {
                    let count = relatedContentOccurrenceCount(term: term, text: text)
                    tf.append(Double(count))
                    if count > 0 { present.insert(t) }
                }
                fieldFrequencies.append(tf)
            }
            for t in present { documentFrequency[t] += 1 }
            lengths.append(fieldLengths)
            frequencies.append(fieldFrequencies)
        }
        for f in fields.indices { average[f] = nonempty[f] > 0 ? average[f] / nonempty[f] : 1 }
        let k1 = 1.2
        return try documents.indices.map { d in
            try Task.checkCancellation()
            return terms.indices.reduce(0.0) { score, t in
                var frequency = 0.0
                for (f, field) in fields.enumerated() {
                    let p = parameters(field)
                    let normalization = 1 - p.length + p.length * lengths[d][f] / average[f]
                    frequency += p.weight * frequencies[d][f][t] / normalization
                }
                let idf = log(1 + (Double(documents.count) - documentFrequency[t] + 0.5) / (documentFrequency[t] + 0.5))
                return score + idf * (k1 + 1) * frequency / (k1 + frequency)
            }
        }
    }
}
