import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Research result processing state")
@MainActor
struct ResearcherEvaluationStateTests {
    @Test("Out-of-date drafts stay blocked while the researcher edits")
    func outOfDateDraftStaysBlocked() {
        let status = ResearcherResponseEditorStatus.outOfDate

        #expect(
            status.afterDraftChange(isDirty: true) == .outOfDate
        )
        #expect(!status.permitsMutation)
    }

    @Test("Saving locks mutation until the submitted revision resolves")
    func savingLocksMutation() {
        let status = ResearcherResponseEditorStatus.saving

        #expect(
            status.afterDraftChange(isDirty: true) == .saving
        )
        #expect(!status.permitsMutation)
    }

    @Test("Ordinary edits recover the correct local and saved states")
    func ordinaryDraftTransitions() {
        #expect(
            ResearcherResponseEditorStatus.saveFailed.afterDraftChange(
                isDirty: true
            ) == .unsaved
        )
        #expect(
            ResearcherResponseEditorStatus.unsaved.afterDraftChange(
                isDirty: false
            ) == .clean
        )
        #expect(ResearcherResponseEditorStatus.unsaved.permitsMutation)

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
            ResearcherResponseEditorStatus.afterMutationFailure(committed)
                == .outOfDate
        )
        #expect(
            ResearcherResponseEditorStatus.afterMutationFailure(uncertain)
                == .outOfDate
        )
        #expect(
            ResearcherResponseEditorStatus.afterMutationFailure(
                PortableResearcherResponseMutationError.recordUnavailable
            ) == .outOfDate
        )
        #expect(
            ResearcherResponseEditorStatus.afterMutationFailure(
                EvaluationTestFailure.provenNotCommitted
            ) == .saveFailed
        )
    }

    @Test("Direct Undo never adopts a different finalized-result fingerprint")
    func directUndoGrantCannotUpgrade() {
        let granted = DocumentFingerprint(content: "granted finalized result")
        var state = ResearchRecordDirectUndoGrantState(
            finalizedResultFingerprint: granted,
            isValid: true
        )

        let initialMatch = state.reconcile(
            observedFinalizedResultFingerprint: granted
        )
        #expect(initialMatch)
        let replacementMatch = state.reconcile(
            observedFinalizedResultFingerprint: DocumentFingerprint(
                content: "replacement finalized result"
            )
        )
        #expect(!replacementMatch)
        #expect(!state.isValid)
        #expect(state.finalizedResultFingerprint == granted)
        let cannotRegainValidity = state.reconcile(
            observedFinalizedResultFingerprint: granted
        )
        #expect(!cannotRegainValidity)
    }

    private enum EvaluationTestFailure: Error {
        case provenNotCommitted
    }
}
