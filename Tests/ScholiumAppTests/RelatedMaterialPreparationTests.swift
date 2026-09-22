import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Silent related-material preparation") @MainActor
struct RelatedMaterialPreparationTests {
    private let vault = UUID()
    private let runtime = TriptychRuntimeIdentity(triptychID: UUID(), activationID: UUID())
    private let sessionID = UUID()

    private func key(editor: Int = 0, index: Int = 1, path: String = "Draft.md") -> RelatedMaterialsSession.BackgroundKey {
        .init(
            runtime: runtime, note: .init(vaultID: vault, relativePath: path),
            sessionID: sessionID, documentID: path, startingFingerprint: "initial",
            editorGeneration: editor,
            searchGeneration: .init(triptychID: runtime.triptychID, sequence: index, sourceManifestHash: "fixture-\(index)"))
    }

    @Test("Preparation is invisible, coalesces caret-only repeats and retries failures")
    func silentAndCoalesced() async throws {
        let model = RelatedMaterialsSession()
        var calls = 0
        let first = try #require(model.prepareBackground(key: key(), pause: {}) { calls += 1 })
        await first.value
        #expect(model.prepareBackground(key: key(), pause: {}) { calls += 1 } == nil)
        #expect(calls == 1)
        #expect(model.cards.isEmpty && model.seed == nil && !model.didSearch && !model.isLoading && model.issue == nil)
        let failed = try #require(model.prepareBackground(key: key(editor: 1), pause: {}) { throw CocoaError(.fileReadNoSuchFile) })
        await failed.value
        #expect(model.issue == nil && model.presentation == .waiting)
        let retry = try #require(model.prepareBackground(key: key(editor: 1), pause: {}) { calls += 1 })
        await retry.value
        #expect(calls == 2)
        let newIndex = try #require(model.prepareBackground(key: key(editor: 1, index: 2), pause: {}) { calls += 1 })
        await newIndex.value
        #expect(calls == 3)
    }

    @Test("Late preparation after Note departure cannot suppress the new Note or a return visit")
    func departureAndLateCompletion() async throws {
        let model = RelatedMaterialsSession()
        let gate = Gate()
        let departed = try #require(model.prepareBackground(key: key(), pause: {}) { await gate.wait() })
        await gate.entered()
        model.reset()
        let newNote = try #require(model.prepareBackground(key: key(path: "Other.md"), pause: {}) {})
        await newNote.value
        gate.release()
        await departed.value
        #expect(model.prepareBackground(key: key(path: "Other.md"), pause: {}) {} == nil)
        let returned = try #require(model.prepareBackground(key: key(), pause: {}) {})
        await returned.value
        #expect(model.cards.isEmpty && model.issue == nil && !model.didSearch)
    }

    @Test("Cancellation before capture prevents work and permits a subsequent preparation")
    func cancelDuringDelay() async throws {
        let model = RelatedMaterialsSession()
        let gate = Gate()
        var calls = 0
        let pending = try #require(model.prepareBackground(key: key(), pause: { await gate.wait() }) { calls += 1 })
        await gate.entered()
        model.stopBackgroundPreparation()
        gate.release()
        await pending.value
        #expect(calls == 0)
        let next = try #require(model.prepareBackground(key: key(), pause: {}) { calls += 1 })
        await next.value
        #expect(calls == 1)
    }

    @Test("Index events cannot restart preparation while foreground retrieval is waiting")
    func foregroundPriority() async throws {
        let model = RelatedMaterialsSession()
        let gate = Gate()
        let source = RelatedContentSeedSnapshot(noteID: key().note, source: "focus words")
        let request = RelatedContentRequest(seed: source)
        let seed = RelatedMaterialsSeed(
            request: request,
            attachment: .init(
                noteID: UUID(), vaultID: vault, relativePath: "Draft.md", text: source.source,
                fingerprint: source.fingerprint, sourceLine: 1))
        let foreground = model.find(
            capture: { seed },
            retrieve: { request in
                await gate.wait()
                return .init(
                    requestID: request.id, seedFingerprint: request.seed.fingerprint,
                    freshnessToken: .init("fixture"), availability: .unavailable, state: .empty,
                    identityCandidates: [], lexicalCandidates: [], identityHasMore: false, lexicalHasMore: false)
            }, references: [])
        await gate.entered()
        #expect(model.isLoading)
        #expect(model.prepareBackground(key: key(index: 2), pause: {}) {} == nil)
        gate.release()
        await foreground.value
        #expect(!model.isLoading && model.presentation == .empty)
        let retry = try #require(model.prepareBackground(key: key(index: 2), pause: {}) {})
        await retry.value
    }

    @MainActor private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var arrival: CheckedContinuation<Void, Never>?
        func wait() async {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                arrival?.resume()
                arrival = nil
            }
        }
        func entered() async {
            if continuation != nil { return }
            await withCheckedContinuation { arrival = $0 }
        }
        func release() {
            continuation?.resume()
            continuation = nil
        }
    }
}
