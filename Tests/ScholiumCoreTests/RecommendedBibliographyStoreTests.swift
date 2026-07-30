import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumCore

@Suite("Recommended Bibliography portable store")
struct RecommendedBibliographyStoreTests {
    @Test("Preparation, zero completion, dismissal, and cancellation remain atomic")
    func lifecycle() async throws {
        let fixture = makeStore()
        defer { fixture.remove() }
        let first = preparation(title: "First")

        let prepared = try await fixture.store.save(preparation: first)
        #expect(prepared.state == .prepared)
        #expect(try await fixture.store.preparation(id: first.id) == first)

        let zero = try await fixture.store.complete(
            requestID: first.id,
            sourceScope: "Reference list",
            candidates: []
        )
        #expect(zero.state == .complete)
        #expect(zero.candidates.isEmpty)
        #expect(try await fixture.store.latest() == zero)

        let second = preparation(
            title: "Second",
            preparedAt: first.preparedAt.addingTimeInterval(1)
        )
        _ = try await fixture.store.save(preparation: second)
        try await fixture.store.cancel(id: second.id)
        try await fixture.store.cancel(id: second.id)
        let cancelled = try await fixture.store.overview()
        #expect(cancelled.result == zero)
        #expect(cancelled.latestRun?.state == .cancelled)
    }

    @Test("A candidate dismissal changes only app-owned projection state")
    func dismissal() async throws {
        let fixture = makeStore()
        defer { fixture.remove() }
        let run = preparation(title: "Dismiss")
        _ = try await fixture.store.save(preparation: run)
        let candidate = RecommendedBibliographyCandidate(
            identity: BibliographyCandidateIdentity(rawCitation: "Author, Work"),
            reason: "The selected source discusses this objection.",
            evidence: BibliographyRecommendationEvidence(
                discussionStatus: .substantivelyDiscussed
            ),
            requiredNextCheck: "Inspect the source."
        )
        _ = try await fixture.store.complete(
            requestID: run.id,
            sourceScope: "Complete selected source",
            candidates: [candidate]
        )
        try await fixture.store.dismiss(requestID: run.id, candidateID: candidate.id)
        let projection = try #require(try await fixture.store.latest())
        #expect(projection.candidates.first?.isDismissed == true)
        #expect(projection.candidates.first?.identity == candidate.identity)
        #expect(projection.candidates.first?.evidence == candidate.evidence)
    }

    @Test("A pending update preserves the latest completed Triptych result")
    func pendingUpdatePreservesResult() async throws {
        let fixture = makeStore()
        defer { fixture.remove() }
        let first = preparation(title: "Analysis")
        _ = try await fixture.store.save(preparation: first)
        let result = try await fixture.store.complete(
            requestID: first.id,
            sourceScope: "Complete source",
            candidates: []
        )
        let second = preparation(
            title: "Topic update",
            preparedAt: first.preparedAt.addingTimeInterval(1)
        )
        _ = try await fixture.store.save(preparation: second)

        let overview = try await fixture.store.overview()
        #expect(overview.result == result)
        #expect(overview.activePreparation == second)
        #expect(overview.latestRun?.id == second.id)

        await #expect(throws: RecommendedBibliographyError.self) {
            _ = try await fixture.store.save(preparation: preparation(
                title: "Duplicate active",
                preparedAt: second.preparedAt.addingTimeInterval(1)
            ))
        }

        try await fixture.store.markStale(id: second.id)
        let staleOverview = try await fixture.store.overview()
        #expect(staleOverview.result == result)
        #expect(staleOverview.activePreparation == nil)
        #expect(staleOverview.latestRun?.state == .stale)
    }

    @Test("Independent App and CLI stores serialize one Triptych request")
    func coordinatedConcurrentStores() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scholium-bibliography-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let stores = [
            RecommendedBibliographyStore(controlURL: root),
            RecommendedBibliographyStore(controlURL: root),
        ]
        let runs = (0..<32).map { index in
            preparation(
                title: "Concurrent \(index)",
                preparedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        }

        let savedCount = await withTaskGroup(of: Bool.self) { group in
            for (index, run) in runs.enumerated() {
                group.addTask {
                    do {
                        _ = try await stores[index % stores.count].save(preparation: run)
                        return true
                    } catch {
                        return false
                    }
                }
            }
            var count = 0
            for await saved in group where saved { count += 1 }
            return count
        }

        #expect(savedCount == 1)
        #expect(try await stores[0].overview().activePreparation != nil)
    }

    @Test("Same-second runs use a deterministic identifier tie break")
    func deterministicSameSecondOrdering() async throws {
        let fixture = makeStore()
        defer { fixture.remove() }
        let scope = bibliographyScope(title: "Analysis")
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let first = preparation(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            title: "First",
            scope: scope,
            preparedAt: timestamp
        )
        _ = try await fixture.store.save(preparation: first)
        _ = try await fixture.store.complete(
            requestID: first.id,
            sourceScope: "Complete source",
            candidates: []
        )
        let second = preparation(
            id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
            title: "Second",
            scope: scope,
            preparedAt: timestamp
        )
        _ = try await fixture.store.save(preparation: second)
        try await fixture.store.cancel(id: second.id)

        let overview = try await fixture.store.overview()
        #expect(overview.latestRun?.id == second.id)
        #expect(overview.latestRun?.state == .cancelled)
        #expect(overview.result?.id == first.id)
    }

    @Test("Unsupported pre-Triptych schema is refused without rewriting bytes")
    func unsupportedSchemaIsPreserved() async throws {
        let fixture = makeStore()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.root,
            withIntermediateDirectories: true
        )
        let bytes = Data(#"{"schema_version":1,"records":[]}"#.utf8)
        let file = fixture.root.appendingPathComponent("recommended-bibliography.json")
        try bytes.write(to: file)

        await #expect(throws: RecommendedBibliographyError.self) {
            _ = try await fixture.store.latest()
        }
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test("Symlinked storage is refused without following it")
    func symlinkProtection() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("scholium-bibliography-\(UUID().uuidString)")
        let control = base.appendingPathComponent(".scholium", isDirectory: true)
        let outside = base.appendingPathComponent("outside.json")
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: control, withIntermediateDirectories: true)
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: control.appendingPathComponent("recommended-bibliography.json"),
            withDestinationURL: outside
        )
        let store = RecommendedBibliographyStore(controlURL: control)
        await #expect(throws: RecommendedBibliographyError.self) {
            _ = try await store.latest()
        }
        #expect(try Data(contentsOf: outside) == Data("outside".utf8))
    }

    private func makeStore() -> (root: URL, store: RecommendedBibliographyStore, remove: () -> Void) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scholium-bibliography-\(UUID().uuidString)")
        return (
            root,
            RecommendedBibliographyStore(controlURL: root),
            { _ = try? FileManager.default.removeItem(at: root) }
        )
    }

    private func preparation(
        id: UUID = UUID(),
        title: String,
        scope suppliedScope: RecommendedBibliographyScope? = nil,
        preparedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> RecommendedBibliographyPreparation {
        RecommendedBibliographyPreparation(
            id: id,
            request: RecommendedBibliographyRequest(
                scope: suppliedScope ?? bibliographyScope(title: title)
            ),
            method: RecommendedBibliographyMethodSnapshot(
                packageID: "scholium-source-analyzer",
                origin: .bundled,
                version: "1.1.0-template",
                packageRevision: DocumentFingerprint(content: "method"),
                loadedResources: []
            ),
            instructions: "Instructions",
            preparedAt: preparedAt
        )
    }

    private func bibliographyScope(title: String) -> RecommendedBibliographyScope {
        RecommendedBibliographyScope(
            triptychID: UUID(),
            selectedNotes: [RecommendedBibliographySourceNote(
                noteID: UUID(),
                note: VaultQualifiedNoteID(
                    vaultID: UUID(),
                    relativePath: "\(title).md"
                ),
                role: .sourceCorpus,
                fingerprint: DocumentFingerprint(content: title),
                title: title
            )]
        )
    }
}
