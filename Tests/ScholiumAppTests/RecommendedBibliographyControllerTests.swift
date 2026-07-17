import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Recommended Bibliography controller")
@MainActor
struct RecommendedBibliographyControllerTests {
    @Test("The controller constructs a canonical request and preserves explicit goals")
    func requestConstruction() async throws {
        let controller = RecommendedBibliographyController()
        var captured: RecommendedBibliographyRequest?
        controller.bind(RecommendedBibliographyClient(
            overview: { _ in RecommendedBibliographyOverview() },
            prepare: { request in
                captured = request
                return preparation(request: request)
            },
            cancel: { _ in },
            dismiss: { _, _ in }
        ))
        let target = target(title: "Analysis")
        await controller.refresh(for: target)
        controller.selectedGoals = [.classicWorks, .objections]
        controller.purpose = "  map the strongest objection  "
        controller.prepare()
        await waitUntil { controller.phase == .awaitingAgent }

        #expect(captured?.target == target)
        #expect(captured?.goals == [.objections, .classicWorks])
        #expect(captured?.purpose == "map the strongest objection")
        #expect(controller.preparation?.request == captured)
    }

    @Test("A stale asynchronous projection cannot replace the current Analysis")
    func staleProjectionIsRejected() async {
        let controller = RecommendedBibliographyController()
        let gate = BibliographyLoadGate()
        controller.bind(RecommendedBibliographyClient(
            overview: { target in
                if target.title == "First" { await gate.wait() }
                return overview(target: target)
            },
            prepare: { preparation(request: $0) },
            cancel: { _ in },
            dismiss: { _, _ in }
        ))
        let first = target(title: "First")
        let second = target(title: "Second")
        let task = Task { await controller.refresh(for: first) }
        await gate.waitUntilArrived()
        await controller.refresh(for: second)
        await gate.release()
        await task.value

        #expect(controller.target == second)
        #expect(controller.projection?.request.target == second)
    }

    @Test("Same-Analysis refresh failures preserve the previous result list")
    func refreshFailurePreservesProjection() async {
        enum FixtureFailure: Error { case unavailable }
        let controller = RecommendedBibliographyController()
        let failureSwitch = BibliographyFailureSwitch()
        controller.bind(RecommendedBibliographyClient(
            overview: { target in
                if await failureSwitch.isEnabled { throw FixtureFailure.unavailable }
                return overview(target: target)
            },
            prepare: { preparation(request: $0) },
            cancel: { _ in },
            dismiss: { _, _ in }
        ))
        let analysis = target(title: "Analysis")
        await controller.refresh(for: analysis)
        let retained = controller.projection
        await failureSwitch.enable()
        await controller.retry()

        #expect(controller.phase == .failed)
        #expect(controller.projection == retained)
        #expect(controller.errorMessage != nil)
    }

    @Test("A broken explicit method exposes a Research Guidance repair state")
    func methodRepairState() async {
        let controller = RecommendedBibliographyController()
        controller.bind(RecommendedBibliographyClient(
            overview: { _ in RecommendedBibliographyOverview() },
            prepare: { _ in throw RecommendedBibliographyError.methodRequiresRepair },
            cancel: { _ in },
            dismiss: { _, _ in }
        ))
        await controller.refresh(for: target(title: "Analysis"))
        controller.prepare()
        await waitUntil { controller.phase == .failed }

        #expect(controller.needsMethodRepair)
        #expect(controller.errorMessage?.contains("Research Guidance") == true)
    }

    @Test("Unbinding resets the per-window draft and cancels presentation state")
    func reset() async {
        let controller = RecommendedBibliographyController()
        controller.bind(RecommendedBibliographyClient(
            overview: { overview(target: $0) },
            prepare: { preparation(request: $0) },
            cancel: { _ in },
            dismiss: { _, _ in }
        ))
        await controller.refresh(for: target(title: "Analysis"))
        controller.selectedGoals = [.backgroundReading]
        controller.purpose = "A purpose"
        controller.unbind()

        #expect(controller.target == nil)
        #expect(controller.projection == nil)
        #expect(controller.selectedGoals.isEmpty)
        #expect(controller.purpose.isEmpty)
        #expect(controller.phase == .idle)
    }

    @Test("A persisted pending request is restored and cannot be prepared twice")
    func pendingRequestRestoration() async {
        let controller = RecommendedBibliographyController()
        let analysis = target(title: "Pending")
        let request = RecommendedBibliographyRequest(target: analysis)
        let active = preparation(request: request)
        let activeProjection = RecommendedBibliographyProjection(
            id: active.id,
            request: request,
            method: active.method,
            state: .prepared,
            preparedAt: active.preparedAt
        )
        var prepareCount = 0
        controller.bind(RecommendedBibliographyClient(
            overview: { _ in
                RecommendedBibliographyOverview(
                    activePreparation: active,
                    latestRun: activeProjection
                )
            },
            prepare: { request in
                prepareCount += 1
                return preparation(request: request)
            },
            cancel: { _ in },
            dismiss: { _, _ in }
        ))

        await controller.refresh(for: analysis)
        #expect(controller.phase == .awaitingAgent)
        #expect(controller.preparation?.id == active.id)
        #expect(!controller.canPrepare)
        controller.prepare()
        #expect(prepareCount == 0)

        await controller.retry()
        #expect(controller.preparation?.instructions == active.instructions)
        #expect(controller.phase == .awaitingAgent)
    }

    @Test("Stale results remain visible with an explicit stale phase")
    func staleResultPresentation() async {
        let controller = RecommendedBibliographyController()
        let analysis = target(title: "Stale")
        let request = RecommendedBibliographyRequest(target: analysis)
        let stale = RecommendedBibliographyProjection(
            id: UUID(),
            request: request,
            method: method(),
            state: .stale,
            sourceScope: "Earlier source unit",
            preparedAt: Date(timeIntervalSince1970: 1_700_000_000),
            completedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        controller.bind(RecommendedBibliographyClient(
            overview: { _ in RecommendedBibliographyOverview(result: stale, latestRun: stale) },
            prepare: { preparation(request: $0) },
            cancel: { _ in },
            dismiss: { _, _ in }
        ))

        await controller.refresh(for: analysis)
        #expect(controller.phase == .stale)
        #expect(controller.projection == stale)
        #expect(controller.canPrepare)
    }

    @Test("Dismissal is scoped to the visible recommendation request")
    func scopedDismissal() async {
        let controller = RecommendedBibliographyController()
        let analysis = target(title: "Dismiss")
        let candidateID = UUID()
        let candidate = RecommendedBibliographyCandidate(
            id: candidateID,
            identity: BibliographyCandidateIdentity(rawCitation: "Author, Work"),
            reason: "The source discusses it.",
            evidence: BibliographyRecommendationEvidence(
                discussionStatus: .substantivelyDiscussed
            ),
            requiredNextCheck: "Inspect the work."
        )
        let request = RecommendedBibliographyRequest(target: analysis)
        let result = RecommendedBibliographyProjection(
            id: UUID(),
            request: request,
            method: method(),
            state: .complete,
            sourceScope: "Complete source",
            candidates: [candidate],
            preparedAt: Date(timeIntervalSince1970: 1_700_000_000),
            completedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        var dismissed: (UUID, UUID)?
        controller.bind(RecommendedBibliographyClient(
            overview: { _ in RecommendedBibliographyOverview(result: result, latestRun: result) },
            prepare: { preparation(request: $0) },
            cancel: { _ in },
            dismiss: { dismissed = ($0, $1) }
        ))

        await controller.refresh(for: analysis)
        controller.dismiss(candidateID: candidateID)
        await waitUntil { dismissed != nil }
        #expect(dismissed?.0 == result.id)
        #expect(dismissed?.1 == candidateID)
    }

    private func target(title: String) -> RecommendedBibliographyTarget {
        RecommendedBibliographyTarget(
            noteID: UUID(),
            note: VaultQualifiedNoteID(
                vaultID: UUID(),
                relativePath: "Analyses/\(title).md"
            ),
            fingerprint: DocumentFingerprint(content: title),
            title: title
        )
    }

    private func method() -> RecommendedBibliographyMethodSnapshot {
        RecommendedBibliographyMethodSnapshot(
            packageID: "scholium-source-analyzer",
            origin: .bundled,
            version: "1.1.0-template",
            packageRevision: DocumentFingerprint(content: "method"),
            loadedResources: []
        )
    }

    private func preparation(
        request: RecommendedBibliographyRequest
    ) -> RecommendedBibliographyPreparation {
        RecommendedBibliographyPreparation(
            request: request,
            method: method(),
            instructions: "Instructions"
        )
    }

    private func projection(
        target: RecommendedBibliographyTarget
    ) -> RecommendedBibliographyProjection {
        let request = RecommendedBibliographyRequest(target: target)
        return RecommendedBibliographyProjection(
            id: UUID(),
            request: request,
            method: method(),
            state: .complete,
            sourceScope: "Complete source",
            preparedAt: Date(timeIntervalSince1970: 1_700_000_000),
            completedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
    }

    private func overview(
        target: RecommendedBibliographyTarget
    ) -> RecommendedBibliographyOverview {
        let result = projection(target: target)
        return RecommendedBibliographyOverview(result: result, latestRun: result)
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<100 {
            if condition() { return }
            await Task.yield()
        }
    }
}

private actor BibliographyLoadGate {
    private var arrived = false
    private var released = false

    func wait() async {
        arrived = true
        while !released { await Task.yield() }
    }

    func waitUntilArrived() async {
        while !arrived { await Task.yield() }
    }

    func release() { released = true }
}

private actor BibliographyFailureSwitch {
    private var enabled = false

    var isEnabled: Bool { enabled }

    func enable() { enabled = true }
}
