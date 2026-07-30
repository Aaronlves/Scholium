import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Recommended Bibliography controller")
@MainActor
struct RecommendedBibliographyControllerTests {
    @Test("The controller constructs a canonical Triptych request")
    func requestConstruction() async throws {
        let controller = RecommendedBibliographyController()
        var captured: RecommendedBibliographyRequest?
        controller.bind(RecommendedBibliographyClient(
            overview: { RecommendedBibliographyOverview() },
            prepare: { request in
                captured = request
                return preparation(request: request)
            },
            cancel: { _ in },
            dismiss: { _, _ in }
        ))
        let scope = scope(title: "Analysis")
        await controller.refresh(for: scope)
        controller.selectedGoals = [.classicWorks, .objections]
        controller.purpose = "  map the strongest objection  "
        controller.prepare()
        await waitUntil { controller.phase == .awaitingAgent }

        #expect(captured?.scope == scope)
        #expect(captured?.goals == [.objections, .classicWorks])
        #expect(captured?.purpose == "map the strongest objection")
        #expect(controller.preparation?.request == captured)
    }

    @Test("A stale asynchronous projection cannot cross a Triptych switch")
    func staleProjectionIsRejected() async {
        let controller = RecommendedBibliographyController()
        let gate = BibliographyLoadGate()
        let first = scope(title: "First")
        let second = scope(title: "Second")
        var invocation = 0
        controller.bind(RecommendedBibliographyClient(
            overview: {
                invocation += 1
                if invocation == 1 {
                    await gate.wait()
                    return overview(scope: first)
                }
                return overview(scope: second)
            },
            prepare: { preparation(request: $0) },
            cancel: { _ in },
            dismiss: { _, _ in }
        ))
        let task = Task { await controller.refresh(for: first) }
        await gate.waitUntilArrived()
        await controller.refresh(for: second)
        await gate.release()
        await task.value

        #expect(controller.scope == second)
        #expect(controller.projection?.request.scope == second)
    }

    @Test("Changing the focal Note retains the Triptych result and draft")
    func selectedNoteChangeRetainsTriptychState() async {
        let controller = RecommendedBibliographyController()
        let triptychID = UUID()
        let first = scope(title: "First", triptychID: triptychID)
        let second = scope(title: "Second", triptychID: triptychID)
        var loadCount = 0
        controller.bind(RecommendedBibliographyClient(
            overview: {
                loadCount += 1
                return overview(scope: first)
            },
            prepare: { preparation(request: $0) },
            cancel: { _ in },
            dismiss: { _, _ in }
        ))

        await controller.refresh(for: first)
        let retained = controller.projection
        controller.purpose = "Retain this draft"
        await controller.refresh(for: second)

        #expect(loadCount == 1)
        #expect(controller.scope == second)
        #expect(controller.projection == retained)
        #expect(controller.purpose == "Retain this draft")
    }

    @Test("Same-Triptych refresh failures preserve the previous result list")
    func refreshFailurePreservesProjection() async {
        enum FixtureFailure: Error { case unavailable }
        let controller = RecommendedBibliographyController()
        let failureSwitch = BibliographyFailureSwitch()
        let scope = scope(title: "Analysis")
        controller.bind(RecommendedBibliographyClient(
            overview: {
                if await failureSwitch.isEnabled { throw FixtureFailure.unavailable }
                return overview(scope: scope)
            },
            prepare: { preparation(request: $0) },
            cancel: { _ in },
            dismiss: { _, _ in }
        ))
        await controller.refresh(for: scope)
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
            overview: { RecommendedBibliographyOverview() },
            prepare: { _ in throw RecommendedBibliographyError.methodRequiresRepair },
            cancel: { _ in },
            dismiss: { _, _ in }
        ))
        await controller.refresh(for: scope(title: "Analysis"))
        controller.prepare()
        await waitUntil { controller.phase == .failed }

        #expect(controller.needsMethodRepair)
        #expect(controller.errorMessage?.contains("Research Guidance") == true)
    }

    @Test("Unbinding resets the per-window draft and presentation state")
    func reset() async {
        let controller = RecommendedBibliographyController()
        let scope = scope(title: "Analysis")
        controller.bind(RecommendedBibliographyClient(
            overview: { overview(scope: scope) },
            prepare: { preparation(request: $0) },
            cancel: { _ in },
            dismiss: { _, _ in }
        ))
        await controller.refresh(for: scope)
        controller.selectedGoals = [.backgroundReading]
        controller.purpose = "A purpose"
        controller.unbind()

        #expect(controller.scope == nil)
        #expect(controller.projection == nil)
        #expect(controller.selectedGoals.isEmpty)
        #expect(controller.purpose.isEmpty)
        #expect(controller.phase == .idle)
    }

    @Test("A persisted pending request is restored and cannot be prepared twice")
    func pendingRequestRestoration() async {
        let controller = RecommendedBibliographyController()
        let scope = scope(title: "Pending")
        let request = RecommendedBibliographyRequest(scope: scope)
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
            overview: {
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

        await controller.refresh(for: scope)
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
        let scope = scope(title: "Stale")
        let request = RecommendedBibliographyRequest(scope: scope)
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
            overview: { RecommendedBibliographyOverview(result: stale, latestRun: stale) },
            prepare: { preparation(request: $0) },
            cancel: { _ in },
            dismiss: { _, _ in }
        ))

        await controller.refresh(for: scope)
        #expect(controller.phase == .stale)
        #expect(controller.projection == stale)
        #expect(controller.canPrepare)
    }

    @Test("Dismissal is scoped to the visible Triptych request")
    func scopedDismissal() async {
        let controller = RecommendedBibliographyController()
        let scope = scope(title: "Dismiss")
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
        let request = RecommendedBibliographyRequest(scope: scope)
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
            overview: { RecommendedBibliographyOverview(result: result, latestRun: result) },
            prepare: { preparation(request: $0) },
            cancel: { _ in },
            dismiss: { dismissed = ($0, $1) }
        ))

        await controller.refresh(for: scope)
        controller.dismiss(candidateID: candidateID)
        await waitUntil { dismissed != nil }
        #expect(dismissed?.0 == result.id)
        #expect(dismissed?.1 == candidateID)
    }

    private func scope(
        title: String,
        triptychID: UUID = UUID()
    ) -> RecommendedBibliographyScope {
        RecommendedBibliographyScope(
            triptychID: triptychID,
            selectedNotes: [RecommendedBibliographySourceNote(
                noteID: UUID(),
                note: VaultQualifiedNoteID(
                    vaultID: UUID(),
                    relativePath: "Analyses/\(title).md"
                ),
                role: .sourceCorpus,
                fingerprint: DocumentFingerprint(content: title),
                title: title
            )]
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

    private func overview(
        scope: RecommendedBibliographyScope
    ) -> RecommendedBibliographyOverview {
        let request = RecommendedBibliographyRequest(scope: scope)
        let result = RecommendedBibliographyProjection(
            id: UUID(),
            request: request,
            method: method(),
            state: .complete,
            sourceScope: "Complete source",
            preparedAt: Date(timeIntervalSince1970: 1_700_000_000),
            completedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
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
