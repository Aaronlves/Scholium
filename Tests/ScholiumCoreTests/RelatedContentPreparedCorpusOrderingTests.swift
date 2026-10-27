import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Related compact corpus ordering")
struct RelatedContentPreparedCorpusOrderingTests {
    @Test("Reordering compact rows preserves canonical floating-point statistics and role pairing")
    func fractionalLengthsKeepCanonicalScores() throws {
        let large = 10_000_000_000_000_000.0
        let small = 0.75
        // This is an accepted finite corpus whose sum depends on input order.
        // It must use the general scoring path without a new integer-only rule.
        #expect((large + small) + small != large + (small + small))
        let lengths = [large, small, small]
        let roles: [VaultRole] = [.sourceCorpus, .topicKnowledge, .draftProject]
        let original = RelatedContentBM25F.Document(rankingText: [["body": "needle needle"]])
        let documents = try lengths.map { length in
            let stored = RelatedContentBM25F.Document.Stored(
                fields: original.fields, fieldLengths: ["body": length],
                textIndexes: original.textIndexes.mapValues(\.stored))
            try stored.validate()
            return try RelatedContentBM25F.Document(stored: stored)
        }
        // The pre-existing direct scorer consumes the explicitly canonical
        // document array; it does not call the new compact-row permutation.
        let expected = try RelatedContentBM25F.evaluate(documents: documents, terms: ["needle"], roles: roles)
        for publicationOrder in [[0, 1, 2], [1, 2, 0], [2, 0, 1]] {
            var prepared = RelatedContentBM25F.PreparedCorpus(terms: ["needle"])
            for index in publicationOrder { try prepared.append(documents[index]) }
            let order = prepared.sortRows { publicationOrder[$0] < publicationOrder[$1] }
            #expect(order.map { publicationOrder[$0] } == [0, 1, 2])
            let reorderedRoles = order.map { roles[publicationOrder[$0]] }
            let actual = try RelatedContentBM25F.evaluate(prepared: prepared, roles: reorderedRoles)
            #expect(actual.scores.map(\.bitPattern) == expected.scores.map(\.bitPattern))
            #expect(actual.coverage.map(\.bitPattern) == expected.coverage.map(\.bitPattern))
            #expect(actual.hasDistinctiveMatch == expected.hasDistinctiveMatch)
        }
    }
}
