import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Related-content role calibration")
struct RelatedContentRoleRankingTests {
    private func document(_ fields: [String: String]) -> RelatedContentBM25F.Document {
        .init(segments: [
            .init(field: .body, ordinal: 0, text: "", normalizedText: "", sourceRange: nil, offsetMap: [], relatedRankingText: fields)
        ])
    }

    @Test("Authored role changes the preferred structural clue, without changing the query")
    func roleContrasts() throws {
        // Equal lexical coverage and one occurrence per field isolate the
        // intended calibration: source summary, topic section, own prose.
        // These are structural expectations, not human usefulness judgments.
        let documents = [
            document(["summary": "agency reasons"]),
            document(["heading": "agency reasons"]),
            document(["body": "agency reasons"]),
        ]
        let analyses = try RelatedContentBM25F.scores(
            documents: documents, terms: ["agency", "reasons"], roles: Array(repeating: .sourceCorpus, count: 3))
        let topics = try RelatedContentBM25F.scores(
            documents: documents, terms: ["agency", "reasons"], roles: Array(repeating: .topicKnowledge, count: 3))
        let works = try RelatedContentBM25F.scores(
            documents: documents, terms: ["agency", "reasons"], roles: Array(repeating: .draftProject, count: 3))
        #expect(analyses[0] > analyses[1] && analyses[1] > analyses[2])
        #expect(topics[1] > topics[0] && topics[0] > topics[2])
        #expect(works[1] > works[2] && works[2] > works[0])
    }

    @Test("Role does not confer a universal priority or create matches")
    func noWholeRoleBoost() throws {
        let sameAnnotation = document(["annotation": "自由 agency"])
        let documents = [sameAnnotation, sameAnnotation, sameAnnotation, document(["body": "unrelated prose"])]
        let scores = try RelatedContentBM25F.scores(
            documents: documents, terms: ["自由", "agency"], roles: [.sourceCorpus, .topicKnowledge, .draftProject, .draftProject])
        #expect(scores[0] == scores[1])
        #expect(scores[1] == scores[2])
        #expect(scores[0] > 0)
        #expect(scores[3] == 0)
    }

    @Test("Role-aware comparison keeps one full corpus and follows documents through permutation")
    func sharedStatistics() throws {
        let documents = [
            document(["summary": "needle freedom", "body": "ordinary"]),
            document(["heading": "needle freedom", "body": "ordinary ordinary"]),
            document(["body": "needle freedom ordinary"]),
            document(["body": "unrelated"]),
        ]
        let roles: [VaultRole] = [.sourceCorpus, .topicKnowledge, .draftProject, .sourceCorpus]
        let scores = try RelatedContentBM25F.scores(documents: documents, terms: ["needle", "freedom"], roles: roles)
        let reversed = try RelatedContentBM25F.scores(
            documents: documents.reversed(), terms: ["freedom", "needle", "needle"], roles: roles.reversed())
        for (actual, expected) in zip(reversed, scores.reversed()) {
            #expect(abs(actual - expected) < 1e-12)
        }
        // An unmatched eligible document contributes to N and field averages.
        // It must not disappear merely because a role-aware profile is used.
        let reduced = try RelatedContentBM25F.scores(
            documents: Array(documents.prefix(3)), terms: ["needle", "freedom"], roles: Array(roles.prefix(3)))
        #expect(scores[0] > reduced[0])
        #expect(scores[3] == 0)
    }

    @Test("Generic scoring remains exact and rejects misaligned role context")
    func genericAndInvalidContext() throws {
        let documents = [document(["body": "needle freedom"]), document(["annotation": "needle", "body": "freedom"])]
        let generic = try RelatedContentBM25F.scores(documents: documents, terms: ["needle", "freedom"])
        let unclassified = try RelatedContentBM25F.scores(
            documents: documents, terms: ["needle", "freedom"], roles: [.other, .other])
        #expect(generic == unclassified)
        #expect(throws: SearchIndexError.self) {
            try RelatedContentBM25F.scores(documents: documents, terms: ["needle"], roles: [.sourceCorpus])
        }
    }
}
