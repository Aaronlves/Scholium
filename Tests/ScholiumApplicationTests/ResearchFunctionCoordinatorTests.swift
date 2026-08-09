import ScholiumContracts
import Testing
@testable import ScholiumApplication

@Suite("Research Function coordinator ownership")
struct ResearchFunctionCoordinatorTests {
    @Test("Coordinator owns protected preparation and completion on the Workspace actor")
    func protectedPreparationAndCompletionOwnership() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let coordinator = await handle.researchFunctionCoordinator

        let snapshot = try await handle.snapshot()
        let note = try #require(snapshot.document(id: fixture.analysisNoteID))
        let noteID = try #require(note.stableIdentity.resolvedID)
        let target = ResearchFunctionTarget(
            noteID: noteID,
            note: fixture.analysisNoteID,
            role: .analysis,
            fingerprint: note.fingerprint,
            title: "Analysis"
        )
        let availability = try await coordinator.researchFunctionAvailability(
            for: target,
            checkingSourceAccess: false,
            host: handle
        )
        #expect(availability.first { $0.function == .fidelity }?.isEnabled == true)
        let preparation = try await coordinator.prepareResearchFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: target,
                checks: [.content]
            ),
            host: handle
        )
        let recovered = try await coordinator.researchFunctionRun(
            id: preparation.runID,
            host: handle
        )
        #expect(recovered.snapshot == preparation.snapshot)
        #expect(Set(try coordinator.attachingAgentActions(
            to: recovered
        ).nextActions?.map(\.kind) ?? []) == [.inspect, .cancel])
        let submission = ResearchFunctionCompletionSubmission(
            runID: preparation.runID,
            confirmationToken: preparation.snapshot.confirmationToken,
            recordTitle: try ResearchRecordTitle("Test research result"),
            finalTargetFingerprint: note.fingerprint,
            summary: "Checked the frozen Analysis revision.",
            didModifyTarget: false,
            fidelityOutcomes: [FidelityCheckOutcome(
                check: .content,
                state: .passed,
                summary: "The fixture found no unresolved content-fidelity issue."
            )]
        )
        let action = try #require(preparation.snapshot.actionSnapshot)
        _ = try await handle.services.localResearchExecutionStore.stageResultPayload(
            ResearchRunResultPayload(
                runID: preparation.runID,
                submissionFingerprint: DocumentFingerprint(
                    content: "coordinator-result"
                ),
                recordTitle: submission.recordTitle,
                disposition: .completed,
                academicResults: testAcademicResults(for: action),
                contextUseReport: nil,
                fidelityOutcomes: submission.fidelityOutcomes,
                literatureRecommendations: nil,
                submittedAt: submission.submittedAt
            )
        )

        let completed = try await coordinator.completeProtectedFunction(
            submission,
            host: handle
        )
        #expect(completed.state == .complete)
        #expect(completed.runID == preparation.runID)
        #expect(try await coordinator.record(
            runID: preparation.runID
        ).completion == completed)
        #expect(try await coordinator.completeProtectedFunction(
            submission,
            host: handle
        ) == completed)
        await runtime.shutdown()
        await #expect(throws: ScholiumApplicationError.self) {
            _ = try await coordinator.researchFunctionRun(
                id: preparation.runID,
                host: handle
            )
        }
        await #expect(throws: ScholiumApplicationError.self) {
            _ = try await coordinator.completeProtectedFunction(
                submission,
                host: handle
            )
        }
    }

    @Test("One Workspace coordinator owns terminal run persistence and lifetime")
    func terminalRunOwnership() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let coordinator = await handle.researchFunctionCoordinator
        let repeatedLookup = await handle.researchFunctionCoordinator
        #expect(coordinator === repeatedLookup)
        #expect(coordinator.workspaceID == handle.id)

        let snapshot = try await handle.snapshot()
        let note = try #require(snapshot.document(id: fixture.analysisNoteID))
        guard case .resolved(let noteID) = note.stableIdentity else {
            Issue.record("The fixture Analysis has no stable identity.")
            await runtime.shutdown()
            return
        }
        let target = ResearchFunctionTarget(
            noteID: noteID,
            note: fixture.analysisNoteID,
            role: .analysis,
            fingerprint: note.fingerprint,
            title: "Analysis"
        )
        let preparation = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: target,
                checks: [.content]
            )
        )

        try await handle.research.cancelProtectedFunction(runID: preparation.runID)
        try await handle.research.cancelProtectedFunction(runID: preparation.runID)
        #expect(try await coordinator.record(
            runID: preparation.runID
        ).completion?.state == .cancelled)

        await runtime.shutdown()
        await #expect(throws: ScholiumApplicationError.self) {
            try await coordinator.cancelProtectedFunction(
                runID: preparation.runID,
                host: handle
            )
        }
    }
}
