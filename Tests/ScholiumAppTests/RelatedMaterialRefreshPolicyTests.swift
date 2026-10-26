import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Related material refresh policy")
struct RelatedMaterialRefreshPolicyTests {
    @Test("Automatic stale queries never request a workspace refresh", arguments: [false, true])
    func automaticNeverRefreshes(refreshIndex: Bool) async throws {
        let probe = Probe()
        let response = try await WindowModel.retrieveRelatedMaterialContent(
            Self.request(), automatic: true, refreshIndex: refreshIndex,
            retrieve: { await probe.retrieve($0) }, refresh: { await probe.refresh() })
        let calls = await probe.counts()
        #expect(calls.queries == 1 && calls.refreshes == 0)
        #expect(response.state == .stale)
    }

    @Test("Manual stale and explicit refresh retain one bounded refresh", arguments: [false, true])
    func manualRefresh(refreshIndex: Bool) async throws {
        let probe = Probe()
        let response = try await WindowModel.retrieveRelatedMaterialContent(
            Self.request(), automatic: false, refreshIndex: refreshIndex,
            retrieve: { await probe.retrieve($0) }, refresh: { await probe.refresh() })
        let calls = await probe.counts()
        #expect(calls.refreshes == 1 && calls.queries == (refreshIndex ? 1 : 2))
        #expect(response.state == .empty)
    }

    @Test("Cancellation after a stale query prevents its refresh")
    func cancelledQuery() async {
        let probe = Probe()
        let operation = Task {
            try await WindowModel.retrieveRelatedMaterialContent(
                Self.request(), automatic: false, refreshIndex: false,
                retrieve: { request in
                    let response = await probe.retrieve(request)
                    withUnsafeCurrentTask { $0?.cancel() }
                    return response
                }, refresh: { await probe.refresh() })
        }
        do {
            _ = try await operation.value
            Issue.record("Cancelled query unexpectedly completed")
        } catch { #expect(error is CancellationError) }
        let calls = await probe.counts()
        #expect(calls.queries == 1 && calls.refreshes == 0)
    }

    private static func request() -> RelatedContentRequest {
        .init(seed: .init(noteID: .init(vaultID: UUID(), relativePath: "Draft.md"), source: "Unsaved freedom 自由"))
    }

    private actor Probe {
        private var queries = 0
        private var refreshes = 0
        private let generation = SearchGenerationID(triptychID: UUID(), sequence: 1, sourceManifestHash: "fixture")
        func retrieve(_ request: RelatedContentRequest) -> RelatedContentResponse {
            queries += 1
            return .init(
                requestID: request.id, seedFingerprint: request.seed.fingerprint, freshnessToken: .triptych(generation),
                availability: .refreshing(lastGood: generation), state: refreshes == 0 ? .stale : .empty,
                identityCandidates: [], lexicalCandidates: [], identityHasMore: false, lexicalHasMore: false)
        }
        func refresh() { refreshes += 1 }
        func counts() -> (queries: Int, refreshes: Int) { (queries, refreshes) }
    }
}
