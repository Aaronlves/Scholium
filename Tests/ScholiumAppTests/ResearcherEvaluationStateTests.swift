import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Researcher Evaluation state")
@MainActor
struct ResearcherEvaluationStateTests {
    @Test("Out-of-date drafts stay blocked while the researcher edits")
    func outOfDateDraftStaysBlocked() {
        let status = ResearchFormSaveStatus.outOfDate

        #expect(
            status.afterEvaluationDraftChange(
                isDirty: true,
                hasSavedEvaluation: true
            ) == .outOfDate
        )
        #expect(!status.permitsEvaluationMutation)
    }

    @Test("Saving locks mutation until the submitted revision resolves")
    func savingLocksMutation() {
        let status = ResearchFormSaveStatus.saving

        #expect(
            status.afterEvaluationDraftChange(
                isDirty: true,
                hasSavedEvaluation: true
            ) == .saving
        )
        #expect(!status.permitsEvaluationMutation)
    }

    @Test("Ordinary edits recover the correct local and saved states")
    func ordinaryDraftTransitions() {
        #expect(
            ResearchFormSaveStatus.saveFailed.afterEvaluationDraftChange(
                isDirty: true,
                hasSavedEvaluation: true
            ) == .unsavedDraft
        )
        #expect(
            ResearchFormSaveStatus.unsavedDraft.afterEvaluationDraftChange(
                isDirty: false,
                hasSavedEvaluation: true
            ) == .saved
        )
        #expect(
            ResearchFormSaveStatus.unsavedDraft.afterEvaluationDraftChange(
                isDirty: false,
                hasSavedEvaluation: false
            ) == .clean
        )
        #expect(ResearchFormSaveStatus.unsavedDraft.permitsEvaluationMutation)

        let committed = ScholiumApplicationError.operationCommittedButRefreshFailed(
            operation: "Evaluation save",
            reason: "Injected projection failure"
        )
        let uncertain = ScholiumApplicationError.operationCommitUncertain(
            operation: "Evaluation save",
            reason: "Injected post-rename uncertainty"
        )
        #expect(committed.durableMutationWasCommitted)
        #expect(!uncertain.durableMutationWasCommitted)
        #expect(committed.mustNotRetryMutation)
        #expect(uncertain.mustNotRetryMutation)
        #expect(
            ResearchFormSaveStatus.afterEvaluationMutationFailure(committed)
                == .outOfDate
        )
        #expect(
            ResearchFormSaveStatus.afterEvaluationMutationFailure(uncertain)
                == .outOfDate
        )
        #expect(
            ResearchFormSaveStatus.afterEvaluationMutationFailure(
                PortableResearcherResponseMutationError.recordUnavailable
            ) == .outOfDate
        )
        #expect(
            ResearchFormSaveStatus.afterEvaluationMutationFailure(
                EvaluationTestFailure.provenNotCommitted
            ) == .saveFailed
        )
    }

    private enum EvaluationTestFailure: Error {
        case provenNotCommitted
    }
}
