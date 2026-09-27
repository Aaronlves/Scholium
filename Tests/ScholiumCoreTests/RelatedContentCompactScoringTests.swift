import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Compact related-content scoring parity")
struct RelatedContentCompactScoringTests {
    @Test("Query-bound field counts preserve every full-document score and coverage value")
    func fullDocumentParity() throws {
        let rows: [(VaultRole, [String: String])] = [
            (
                .sourceCorpus,
                [
                    "title": "Compass and éthique", "body": "compass compass 自由 reason",
                    "annotation": "reasoned compass reading",
                ]
            ),
            (
                .topicKnowledge,
                ["title": "自由 and reasons", "keyword": "自由 compass", "body": "自由 remains a question"]
            ),
            (
                .draftProject,
                ["summary": "reason reason compass", "heading": "Éthique", "body": "a\u{200D}b compass"]
            ),
            (.sourceCorpus, ["body": "unrelated archive material"]),
            (.topicKnowledge, ["body": "compass", "annotation": ""]),
        ]
        let documents = rows.map { _, fields in
            RelatedContentBM25F.Document(segments: [
                .init(
                    field: .body, ordinal: 0, text: "", normalizedText: "", sourceRange: nil,
                    offsetMap: [], relatedRankingText: fields)
            ])
        }
        let roles = rows.map(\.0)
        #expect(documents.allSatisfy { $0.isValid })
        for terms in [
            ["compass", "reason", "自由", "éthique", "absent"],
            ["自由", "compass", "compass", "a", "archive"],
            ["absent", "alsoabsent"],
        ] {
            let full = try RelatedContentBM25F.evaluate(documents: documents, terms: terms, roles: roles)
            var compact = RelatedContentBM25F.PreparedCorpus(terms: terms)
            for document in documents { try compact.append(document) }
            #expect(compact.rows.count == documents.count)
            let prepared = try RelatedContentBM25F.evaluate(prepared: compact, roles: roles)
            let frozen = frozenEvaluation(documents: documents, terms: terms, roles: roles)
            for result in [full, prepared] {
                #expect(result.scores == frozen.scores)
                #expect(result.coverage == frozen.coverage)
                #expect(result.hasDistinctiveMatch == frozen.hasDistinctiveMatch)
            }
            #expect(prepared.scores.allSatisfy { $0.isFinite && $0 >= 0 })
            #expect(prepared.coverage.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 + 1e-12 })
        }
    }

    @Test("Full-projection multilingual oracle retains complete ordered candidates and reasons")
    func candidateParity() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build/related-compact-parity/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let analysis = RegisteredVault(
            name: "Analyses", role: .sourceCorpus, canonicalPath: root.appendingPathComponent("analyses").path)
        let topic = RegisteredVault(
            name: "Topics", role: .topicKnowledge, canonicalPath: root.appendingPathComponent("topics").path)
        let work = RegisteredVault(
            name: "Works", role: .draftProject, canonicalPath: root.appendingPathComponent("works").path)
        let candidateItems: [SearchIndexDocument] = [
            .init(
                vaultID: analysis.id, vaultName: analysis.name, vaultRole: analysis.role,
                document: .init(relativePath: "A.md", rawContent: "compass compass reason 自由 éthique")),
            .init(
                vaultID: topic.id, vaultName: topic.name, vaultRole: topic.role,
                document: .init(relativePath: "B.md", rawContent: "compass 自由 raises a question")),
            .init(
                vaultID: work.id, vaultName: work.name, vaultRole: work.role,
                document: .init(relativePath: "C.md", rawContent: "reason compass as a method")),
        ]
        let excluded = SearchIndexDocument(
            vaultID: analysis.id, vaultName: analysis.name, vaultRole: analysis.role,
            document: .init(relativePath: "D.md", rawContent: "unrelated archive material"))
        let seed = SearchIndexDocument(
            vaultID: work.id, vaultName: work.name, vaultRole: work.role,
            document: .init(relativePath: "Draft.md", rawContent: "Compass reason 自由. Éthique matters."))
        let index = try TriptychSearchIndex(
            databaseURL: root.appendingPathComponent("search.sqlite"), triptychID: UUID(),
            vaults: [analysis, topic, work])
        _ = try await index.synchronize(candidateItems + [excluded, seed])
        let request = RelatedContentRequest(
            seed: .init(
                noteID: .init(vaultID: work.id, relativePath: seed.relativePath),
                source: seed.document.rawContent),
            lexicalLimit: 1)
        let response = try await index.relatedMaterialSourceCandidates(request)
        #expect(response.lexicalHasMore)
        #expect(Set(response.lexicalCandidates.map(\.note.relativePath)) == Set(["A.md", "B.md", "C.md"]))

        let seedProjection = SearchDocumentProjection(
            document: seed.document, profile: WorkflowProfileResolver.resolve(vaultRole: seed.vaultRole))
        let material = RelatedContentSeedMaterial(projection: seedProjection, focuses: [])
        let projections = candidateItems.map { item in
            RelatedContentLexicalProjection(
                projection: .init(
                    document: item.document, profile: WorkflowProfileResolver.resolve(vaultRole: item.vaultRole)))
        }
        let evaluation = frozenEvaluation(
            documents: projections.map(\.scoringDocument), terms: material.combinedTerms,
            roles: candidateItems.map(\.vaultRole))
        let reference = zip(candidateItems.indices, evaluation.scores).compactMap {
            entry
                -> (item: SearchIndexDocument, reason: RelatedContentLexicalReason, score: Double)? in
            let (index, score) = entry
            guard score > 0 else { return nil }
            let reason = material.lexicalReason(for: projections[index])
            guard !reason.seedMatches.isEmpty else { return nil }
            return (candidateItems[index], reason, score)
        }.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.item.relativePath < rhs.item.relativePath
        }
        #expect(reference.count == 3)
        #expect(response.lexicalCandidates.map(\.note.relativePath) == reference.map { $0.item.relativePath })
        #expect(response.lexicalCandidates.map(\.reason) == reference.map { .lexicalOverlap($0.reason) })
        #expect(response.lexicalCandidates.map(\.fingerprint) == reference.map { $0.item.document.fingerprint })
    }

    /// Test-only copy of the pre-cutover two-pass BM25 arithmetic. It does not
    /// use the new generic evaluator or its compact field-count provider.
    private func frozenEvaluation(
        documents: [RelatedContentBM25F.Document], terms inputTerms: [String], roles: [VaultRole]
    ) -> RelatedContentBM25F.Evaluation {
        let terms = Array(Set(inputTerms)).sorted()
        guard !documents.isEmpty, !terms.isEmpty else {
            let zero = Array(repeating: 0.0, count: documents.count)
            return .init(scores: zero, coverage: zero, hasDistinctiveMatch: Array(repeating: false, count: documents.count))
        }
        let matcher = RelatedContentTermMatcher(terms: terms)
        let fields = RelatedContentRankingField.allCases
        var average = Array(repeating: 0.0, count: fields.count)
        var nonempty = Array(repeating: 0.0, count: fields.count)
        for document in documents {
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
            uniqueKeysWithValues: Set(roles).map { role in
                (role, fields.map { frozenParameters($0, role: role) })
            })
        var frequencies: [[Double]] = []
        var documentFrequency = Array(repeating: 0.0, count: terms.count)
        for (d, document) in documents.enumerated() {
            let parameters = parametersByRole[roles[d]]!
            var frequency = Array(repeating: 0.0, count: terms.count)
            for (f, field) in fields.enumerated() {
                guard let text = document.fields[field.rawValue] else { continue }
                let p = parameters[f]
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
        let totalInformation = information.indices.reduce(0.0) {
            $0 + (documentFrequency[$1] > 0 ? information[$1] : 0)
        }
        var coverage = Array(repeating: 0.0, count: documents.count)
        var distinctive = Array(repeating: false, count: documents.count)
        let scores = documents.indices.map { d in
            terms.indices.reduce(0.0) { score, t in
                let frequency = frequencies[d][t]
                let idf = information[t]
                if frequency > 0 {
                    coverage[d] += idf / totalInformation
                    if documentFrequency[t] <= max(1, Double(documents.count) * 0.2) { distinctive[d] = true }
                }
                return score + idf * (k1 + 1) * frequency / (k1 + frequency)
            }
        }
        return .init(scores: scores, coverage: coverage, hasDistinctiveMatch: distinctive)
    }

    private func frozenParameters(_ field: RelatedContentRankingField, role: VaultRole) -> (weight: Double, length: Double) {
        let baseline: (weight: Double, length: Double) =
            switch field {
            case .annotation: (8, 0.30)
            case .link: (5, 0.20)
            case .keyword, .title: (4, 0)
            case .summary: (3, 0.50)
            case .heading: (2, 0.30)
            case .body: (1, 0.75)
            }
        let weight: Double =
            switch (role, field) {
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
}
