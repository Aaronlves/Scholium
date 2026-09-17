import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Related content graph refinement")
struct RelatedContentGraphRankingTests {
    private let vault = UUID(uuidString: "A49EF2E2-5A37-4D86-8F27-1422F8B6C655")!

    private func id(_ path: String) -> VaultQualifiedNoteID {
        .init(vaultID: vault, relativePath: path)
    }

    private func context(_ path: String, proximity: Double) throws -> RelatedContentGraphContext {
        let semantic = MarkdownSemanticDocument(parsing: NoteDocument(relativePath: "Draft.md", rawContent: "[[\(path)]]"))
        let occurrence = try #require(semantic.links.first)
        return .init(
            paths: [.init(steps: [.init(source: id("Draft.md"), destination: id(path), occurrence: occurrence, traversal: .outgoing)])],
            proximity: proximity)
    }

    private func source(_ path: String, _ text: String, graph: RelatedContentGraphContext? = nil) -> RelatedContentSource {
        let document = NoteDocument(relativePath: path, rawContent: text)
        return .init(
            candidate: .init(
                note: id(path), vaultRole: .sourceCorpus, title: path, fingerprint: document.fingerprint,
                reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: [])), graphContext: graph),
            document: document)
    }

    private var request: RelatedContentRequest {
        .init(
            seed: .init(
                noteID: id("Draft.md"), source: "freedom autonomy",
                focuses: [.init(kind: .selectedPassage, text: "freedom autonomy")]))
    }

    @Test("Graph proximity refines equal lexical material without losing unconnected Notes")
    func connectedMaterialRefinement() throws {
        let plain = source("A Plain.md", "Freedom autonomy premise comparison.")
        let linkedText = "\u{FEFF}Freedom autonomy objection comparison.\r\n"
        let unconnected = source("Z Linked.md", linkedText)
        let baseline = try TriptychSearchIndex.relatedPassages(request, sources: [plain, unconnected])
        #expect(baseline.first?.candidate.note == plain.candidate.note)
        let linked = source("Z Linked.md", linkedText, graph: try context("Z Linked.md", proximity: 1))
        let ranked = try TriptychSearchIndex.relatedPassages(request, sources: [plain, linked])
        #expect(ranked.first?.candidate.note == linked.candidate.note)
        #expect(Set(ranked.map(\.candidate.note)) == [plain.candidate.note, linked.candidate.note])
        #expect(try TriptychSearchIndex.relatedPassages(request, sources: [linked, plain]) == ranked)
        let passage = try #require(ranked.first)
        let range = try #require(
            Range(
                NSRange(
                    location: passage.range.utf16LowerBound,
                    length: passage.range.utf16UpperBound - passage.range.utf16LowerBound), in: linkedText))
        #expect(String(linkedText[range]) == passage.source)
        #expect(passage.candidate.fingerprint == linked.document.fingerprint)
        #expect(passage.candidate.graphContext == linked.candidate.graphContext)
    }

    @Test("Even maximal connectivity cannot admit unrelated, metadata-only or weak-focus prose")
    func graphDoesNotManufactureRelevance() throws {
        let connected = try context("Irrelevant.md", proximity: 1)
        let sources = [
            source("Useful.md", "Freedom autonomy distinction comparison."),
            source("Irrelevant.md", "Green leaves grow near a river.", graph: connected),
            source("Metadata.md", "---\nsummary: freedom autonomy\n---\n\nGreen leaves grow near a river.", graph: connected),
            source("Weak.md", "Freedom names a flowering garden plant.", graph: connected),
        ]
        let passages = try TriptychSearchIndex.relatedPassages(request, sources: sources)
        #expect(passages.map(\.candidate.note.relativePath) == ["Useful.md"])
    }

    @Test("Unrelated graph-only candidates cannot alter the lexical comparison corpus")
    func unrelatedGraphCorpus() throws {
        let lexical = [
            source("A.md", "Freedom autonomy premise comparison."),
            source("Z.md", "Freedom autonomy objection comparison."),
        ]
        let document = NoteDocument(relativePath: "Garden.md", rawContent: "Green leaves grow near a river.")
        let graph = try context("Garden.md", proximity: 1)
        let unrelated = RelatedContentSource(
            candidate: .init(
                note: id("Garden.md"), vaultRole: .sourceCorpus, title: "Garden",
                fingerprint: document.fingerprint, reason: .graphConnection(graph), graphContext: graph),
            document: document)
        #expect(
            try TriptychSearchIndex.relatedPassages(request, sources: lexical + [unrelated])
                == TriptychSearchIndex.relatedPassages(request, sources: lexical))
    }

    @Test("Proximity is bounded, finite and never a relevance substitute")
    func graphFactorBounds() throws {
        #expect(RelatedContentRecommendationPolicy.graphFactor(nil) == 1)
        #expect(RelatedContentRecommendationPolicy.graphFactor(.init(paths: [], proximity: 1)) == 1)
        #expect(RelatedContentRecommendationPolicy.graphFactor(try context("Target.md", proximity: 10)) == 1.15)
        #expect(RelatedContentRecommendationPolicy.graphFactor(try context("Target.md", proximity: -1)) == 1)
        #expect(RelatedContentRecommendationPolicy.graphFactor(try context("Target.md", proximity: .nan)) == 1)
        #expect(RelatedContentRecommendationPolicy.graphFactor(try context("Target.md", proximity: 0.25)) == 1.0375)
        let decoded = try JSONDecoder().decode(
            RelatedContentGraphContext.self,
            from: Data(#"{"paths":[{"steps":[]}],"proximity":100}"#.utf8))
        #expect(RelatedContentRecommendationPolicy.graphFactor(decoded) == 1)
        let step = try #require(context("Target.md", proximity: 1).paths.first?.steps.first)
        #expect(!RelatedContentGraphPath(steps: [step, step, step]).isValid)
        #expect(!RelatedContentGraphPath(steps: [step, step]).isValid)
        let returning = RelatedContentGraphStep(
            source: step.source, destination: step.destination,
            occurrence: step.occurrence, traversal: .incoming)
        #expect(!RelatedContentGraphPath(steps: [step, returning]).isValid)
    }

    @Test("Typed connection reasons and exact occurrences survive current-format round trips")
    func graphContractRoundTrip() throws {
        let graph = try context("Target.md", proximity: 0.25)
        let document = NoteDocument(relativePath: "Target.md", rawContent: "Freedom autonomy comparison.")
        let candidate = RelatedContentCandidate(
            note: id("Target.md"), vaultRole: .topicKnowledge, title: "Target",
            fingerprint: document.fingerprint, reason: .graphConnection(graph), graphContext: graph)
        let encoded = try JSONEncoder().encode(candidate)
        #expect(try JSONDecoder().decode(RelatedContentCandidate.self, from: encoded) == candidate)
    }
}
