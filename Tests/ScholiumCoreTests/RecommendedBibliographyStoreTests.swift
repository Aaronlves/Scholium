import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumCore

@Suite("Recommended Bibliography portable store")
struct RecommendedBibliographyStoreTests {
    @Test("Preparation, zero completion, dismissal, and cancellation remain atomic")
    func lifecycle() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scholium-bibliography-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecommendedBibliographyStore(controlURL: root)
        let first = preparation(title: "First")

        let prepared = try await store.save(preparation: first)
        #expect(prepared.state == .prepared)
        #expect(try await store.preparation(id: first.id) == first)

        let zero = try await store.complete(
            requestID: first.id,
            sourceScope: "Reference list",
            candidates: []
        )
        #expect(zero.state == .complete)
        #expect(zero.candidates.isEmpty)
        #expect(try await store.latest(targetNoteID: first.request.target.noteID) == zero)

        let second = preparation(title: "Second", preparedAt: first.preparedAt.addingTimeInterval(1))
        _ = try await store.save(preparation: second)
        try await store.cancel(id: second.id)
        try await store.cancel(id: second.id)
        let cancelled = try await store.overview(targetNoteID: second.request.target.noteID)
        #expect(cancelled.result == nil)
        #expect(cancelled.latestRun?.state == .cancelled)
    }

    @Test("A candidate dismissal changes only app-owned projection state")
    func dismissal() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scholium-bibliography-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecommendedBibliographyStore(controlURL: root)
        let run = preparation(title: "Dismiss")
        _ = try await store.save(preparation: run)
        let candidate = RecommendedBibliographyCandidate(
            identity: BibliographyCandidateIdentity(rawCitation: "Author, Work"),
            reason: "The paper discusses this objection.",
            evidence: BibliographyRecommendationEvidence(
                discussionStatus: .substantivelyDiscussed
            ),
            requiredNextCheck: "Inspect the source."
        )
        _ = try await store.complete(
            requestID: run.id,
            sourceScope: "Complete paper",
            candidates: [candidate]
        )
        try await store.dismiss(requestID: run.id, candidateID: candidate.id)
        let projection = try #require(
            try await store.latest(targetNoteID: run.request.target.noteID)
        )
        #expect(projection.candidates.first?.isDismissed == true)
        #expect(projection.candidates.first?.identity == candidate.identity)
        #expect(projection.candidates.first?.evidence == candidate.evidence)
    }

    @Test("A pending update preserves the latest completed result")
    func pendingUpdatePreservesResult() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scholium-bibliography-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecommendedBibliographyStore(controlURL: root)
        let first = preparation(title: "Analysis")
        let completed = try await store.save(preparation: first)
        _ = completed
        let result = try await store.complete(
            requestID: first.id,
            sourceScope: "Complete source",
            candidates: []
        )
        let second = preparation(
            title: "Analysis update",
            target: first.request.target,
            preparedAt: first.preparedAt.addingTimeInterval(1)
        )
        _ = try await store.save(preparation: second)

        let overview = try await store.overview(targetNoteID: first.request.target.noteID)
        #expect(overview.result == result)
        #expect(overview.activePreparation == second)
        #expect(overview.latestRun?.id == second.id)
        #expect(overview.latestRun?.state == .prepared)

        await #expect(throws: RecommendedBibliographyError.self) {
            _ = try await store.save(preparation: preparation(
                title: "Duplicate active",
                target: first.request.target,
                preparedAt: second.preparedAt.addingTimeInterval(1)
            ))
        }

        try await store.markStale(id: second.id)
        let staleOverview = try await store.overview(
            targetNoteID: first.request.target.noteID
        )
        #expect(staleOverview.result == result)
        #expect(staleOverview.activePreparation == nil)
        #expect(staleOverview.latestRun?.state == .stale)
    }

    @Test("Independent App and CLI store instances cannot lose concurrent updates")
    func coordinatedConcurrentStores() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scholium-bibliography-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let appStore = RecommendedBibliographyStore(controlURL: root)
        let cliStore = RecommendedBibliographyStore(controlURL: root)
        let runs = (0..<32).map { index in
            preparation(
                title: "Concurrent \(index)",
                preparedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, run) in runs.enumerated() {
                group.addTask {
                    let store = index.isMultiple(of: 2) ? appStore : cliStore
                    _ = try await store.save(preparation: run)
                }
            }
            try await group.waitForAll()
        }

        for run in runs {
            let overview = try await appStore.overview(
                targetNoteID: run.request.target.noteID
            )
            #expect(overview.activePreparation?.id == run.id)
        }
    }

    @Test("Same-second runs use a deterministic identifier tie break")
    func deterministicSameSecondOrdering() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scholium-bibliography-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecommendedBibliographyStore(controlURL: root)
        let target = RecommendedBibliographyTarget(
            noteID: UUID(),
            note: VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Analysis.md"),
            fingerprint: DocumentFingerprint(content: "analysis"),
            title: "Analysis"
        )
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let first = preparation(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            title: "First",
            target: target,
            preparedAt: timestamp
        )
        _ = try await store.save(preparation: first)
        _ = try await store.complete(
            requestID: first.id,
            sourceScope: "Complete source",
            candidates: []
        )
        let second = preparation(
            id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
            title: "Second",
            target: target,
            preparedAt: timestamp
        )
        _ = try await store.save(preparation: second)
        try await store.cancel(id: second.id)

        let overview = try await store.overview(targetNoteID: target.noteID)
        #expect(overview.latestRun?.id == second.id)
        #expect(overview.latestRun?.state == .cancelled)
        #expect(overview.result?.id == first.id)
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
            _ = try await store.latest(targetNoteID: UUID())
        }
        #expect(try Data(contentsOf: outside) == Data("outside".utf8))
    }

    private func preparation(
        id: UUID = UUID(),
        title: String,
        target suppliedTarget: RecommendedBibliographyTarget? = nil,
        preparedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> RecommendedBibliographyPreparation {
        let target = suppliedTarget ?? RecommendedBibliographyTarget(
            noteID: UUID(),
            note: VaultQualifiedNoteID(vaultID: UUID(), relativePath: "\(title).md"),
            fingerprint: DocumentFingerprint(content: title),
            title: title
        )
        return RecommendedBibliographyPreparation(
            id: id,
            request: RecommendedBibliographyRequest(target: target),
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
}
