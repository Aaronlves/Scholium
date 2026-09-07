import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Related materials") @MainActor
struct RelatedMaterialsTests {
    private let vault = UUID()
    private func seed(_ text: String = "unsaved freedom 自由") -> RelatedMaterialsSeed {
        let snapshot = RelatedContentSeedSnapshot(noteID: .init(vaultID: vault, relativePath: "Draft.md"),
            source: "# Draft\n\n" + text, focuses: [.init(kind: .selectedPassage, text: text)])
        return .init(request: .init(seed: snapshot), attachment: .init(noteID: UUID(), vaultID: vault,
            relativePath: "Draft.md", text: text, fingerprint: snapshot.fingerprint, sourceLine: 3))
    }
    private func candidate(_ source: String) -> RelatedContentCandidate {
        .init(note: .init(vaultID: vault, relativePath: "Source.md"), vaultRole: .sourceCorpus,
            title: "Source", fingerprint: .init(content: source),
            reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: [.init(seedKind: .selectedPassage, terms: ["自由"])])))
    }
    private func reference() -> VaultNoteReference {
        .init(vaultID: vault, vaultName: "Analyses", vaultRole: .sourceCorpus, relativePath: "Source.md", stableNoteID: UUID().uuidString)
    }
    private func response(_ request: RelatedContentRequest, candidates: [RelatedContentCandidate] = []) -> RelatedContentResponse {
        .init(requestID: request.id, seedFingerprint: request.seed.fingerprint, freshnessToken: .init("fixture"),
            availability: .current(.init(triptychID: UUID(), sequence: 1, sourceManifestHash: "fixture")),
            state: candidates.isEmpty ? .empty : .current,
            identityCandidates: candidates, lexicalCandidates: candidates, identityHasMore: false, lexicalHasMore: false)
    }

    @Test("Paragraphs from the same Note stay separate and handoff preserves exact source ranges")
    func selectionAndParagraphs() async {
        let model = RelatedMaterialsSession(), seed = seed(), candidate = candidate("whole source")
        let first = RelatedContentPassage(candidate: candidate, range: .init(utf16LowerBound: 12, utf16UpperBound: 18,
            line: 3, column: 1, endLine: 3, endColumn: 7), source: "**自由**", displayText: "自由",
            matches: [.init(seedKind: .selectedPassage, terms: ["自由"])])
        let second = RelatedContentPassage(candidate: candidate, range: .init(utf16LowerBound: 20, utf16UpperBound: 26,
            line: 5, column: 1, endLine: 5, endColumn: 7), source: "另一段自由。", displayText: "另一段自由。", matches: first.matches)
        let response = RelatedContentResponse(requestID: seed.request.id, seedFingerprint: seed.request.seed.fingerprint,
            freshnessToken: .init("fixture"), availability: .unavailable, state: .current, identityCandidates: [],
            lexicalCandidates: [candidate], identityHasMore: false, lexicalHasMore: false, passages: [first, second])
        await model.find(capture: { seed }, retrieve: { request in
            #expect(request.seed.source.contains("unsaved"))
            #expect(request.seed.focuses.first?.text == seed.attachment.text)
            return response
        }, references: [reference()]).value
        #expect(model.cards.count == 2)
        #expect(model.cards.map(\.id) == [first.id, second.id])
        #expect(model.seed?.attachment.text == seed.attachment.text)
        #expect(model.didSearch && !model.isLoading)
        #expect(model.cards.first?.attachment?.sourceRange == first.range)
        #expect(model.cards.first?.attachment?.text == "**自由**")
    }

    @Test("A reset invalidates an uncooperative late response and leaves no cross-workspace material")
    func cancelledPublication() async {
        let model = RelatedMaterialsSession(), seed = seed()
        var release: CheckedContinuation<Void, Never>?
        var started: CheckedContinuation<Void, Never>?
        let latch = Task { await withCheckedContinuation { started = $0 } }
        await Task.yield()
        let response = response(seed.request)
        let operation = model.find(capture: {
            await withCheckedContinuation { continuation in
                release = continuation; started?.resume()
            }
            return seed
        }, retrieve: { _ in response }, references: [])
        await latch.value
        model.reset()
        release?.resume()
        await operation.value
        #expect(model.seed == nil && model.cards.isEmpty && !model.isLoading && !model.didSearch)
    }

    @Test("Stale retrieval offers refresh while an invalid selection asks for different wording", arguments: [RelatedContentResultState.stale, .invalidSeed, .unavailable])
    func retrievalStates(_ state: RelatedContentResultState) async {
        let model = RelatedMaterialsSession(), seed = seed()
        let response = RelatedContentResponse(requestID: seed.request.id,
            seedFingerprint: seed.request.seed.fingerprint, freshnessToken: .init("fixture"), availability: .unavailable,
            state: state, identityCandidates: [], lexicalCandidates: [], identityHasMore: false, lexicalHasMore: false)
        await model.find(capture: { seed }, retrieve: { _ in response },
            references: []).value
        #expect(model.issue != nil && !model.isLoading)
        #expect(model.needsRefresh == (state != .invalidSeed))
        #expect(model.cards.isEmpty && !model.didSearch)
    }

    @Test("Omitted sources are visible and no-selection preserves a recoverable error")
    func failures() async {
        let model = RelatedMaterialsSession(), seed = seed()
        let response = RelatedContentResponse(requestID: seed.request.id, seedFingerprint: seed.request.seed.fingerprint,
            freshnessToken: .init("fixture"), availability: .unavailable, state: .partial, identityCandidates: [],
            lexicalCandidates: [], identityHasMore: false, lexicalHasMore: false, omittedSourceCount: 1)
        await model.find(capture: { seed }, retrieve: { _ in response }, references: [reference()]).value
        #expect(model.omittedCount == 1 && model.cards.isEmpty && model.didSearch)
        await model.find(capture: { throw RelatedMaterialsError.selectionRequired }, retrieve: { _ in response }, references: []).value
        #expect(model.issue != nil && !model.isLoading)
    }
}
