import Foundation
import ScholiumContracts
@testable import ScholiumApplication
import Testing

@Suite("Authenticated Method improvement Run", .serialized)
struct ResearchMethodImprovementOperationsTests {
    @Test("One explicit Run replaces the exact primary Method, clears only its comment, and replays idempotently")
    func primaryMethodImprovement() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let record = try await completedSynthesis(handle: handle, fixture: fixture)
        let original = try await handle.research.researchMethod(for: .synthesize)
        let commented = try await addFeedback(
            "Preserve the rival formulation more explicitly.",
            to: record,
            handle: handle
        )

        let handoff = try await handle.research.issueMethodImprovementHandoff(
            recordID: record.id
        )
        let credential = try await handle.research.pairAgent(
            run: handoff.run,
            pairingCode: handoff.pairingCode
        )
        let context = try await handle.research.methodImprovementContext(
            credential: credential,
            run: handoff.run
        )
        #expect(context.feedbackText == commented.methodFeedbackComment?.text)
        #expect(context.targets.first?.id == "primary-method")
        #expect(context.targets.allSatisfy { target in
            target.revision == DocumentFingerprint(content: target.source)
        })

        let replacement = original.primaryMarkdownSource
            + "\n<!-- bounded method improvement -->\n"
        let submission = try ResearchMethodImprovementSubmission(
            requestID: UUID(),
            feedbackRevision: try #require(
                commented.methodFeedbackComment?.revision
            ),
            expectedResultFingerprint: try commented.finalizedResultFingerprint(),
            targetID: "primary-method",
            expectedTargetRevision: original.primaryMarkdownRevision,
            disposition: .replace,
            replacementSource: replacement,
            diagnosis: "The comment concerns the primary Method and warrants one bounded clarification."
        )
        let receipt = try await handle.research.submitMethodImprovement(
            credential: credential,
            run: handoff.run,
            submission: submission
        )
        let replay = try await handle.research.submitMethodImprovement(
            credential: credential,
            run: handoff.run,
            submission: submission
        )
        #expect(receipt == replay)
        #expect(receipt.disposition == .replace)
        #expect(receipt.feedbackCleared)
        #expect(receipt.startingRevision == original.primaryMarkdownRevision)
        #expect(receipt.endingRevision == DocumentFingerprint(content: replacement))
        #expect(try await handle.research.researchMethod(
            for: .synthesize
        ).primaryMarkdownSource == replacement)
        #expect(try await handle.services.portableResearchRecordStore.record(
            id: record.id
        ).methodFeedbackComment == nil)

        let parent = try await handle.services.localResearchExecutionStore.record(
            id: record.id
        )
        #expect(parent.methodImprovementRun?.state == .completed)
        #expect(parent.methodImprovementRun?.receipt == receipt)

        let different = try ResearchMethodImprovementSubmission(
            requestID: UUID(),
            feedbackRevision: submission.feedbackRevision,
            expectedResultFingerprint: submission.expectedResultFingerprint,
            targetID: submission.targetID,
            expectedTargetRevision: submission.expectedTargetRevision,
            disposition: .replace,
            replacementSource: replacement + "different",
            diagnosis: "A different final submission must not replace the first."
        )
        await #expect(throws: ResearchMethodImprovementError.self) {
            _ = try await handle.research.submitMethodImprovement(
                credential: credential,
                run: handoff.run,
                submission: different
            )
        }

        let restored = try await handle.research.restorePreviousResearchMethod(
            registrationKey: original.registration.key,
            expectedRevision: receipt.endingRevision
        )
        #expect(restored.primaryMarkdownSource == original.primaryMarkdownSource)
        _ = try await runtime.endResearchAgentRun(
            credential: credential,
            run: handoff.run
        )
        await runtime.shutdown()
    }

    @Test("A changed researcher comment blocks an unstarted edit and a no-change diagnosis clears only an unchanged comment")
    func commentCASAndDiagnosis() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let record = try await completedSynthesis(handle: handle, fixture: fixture)
        let first = try await addFeedback(
            "Check whether the Method overstates convergence.",
            to: record,
            handle: handle
        )
        let original = try await handle.research.researchMethod(for: .synthesize)
        let firstHandoff = try await handle.research.issueMethodImprovementHandoff(
            recordID: record.id
        )
        let firstCredential = try await handle.research.pairAgent(
            run: firstHandoff.run,
            pairingCode: firstHandoff.pairingCode
        )
        let firstContext = try await handle.research.methodImprovementContext(
            credential: firstCredential,
            run: firstHandoff.run
        )
        let revised = try await handle.research.saveMethodFeedbackComment(
            recordID: record.id,
            draft: try ResearchMethodFeedbackDraft(
                text: "The revised comment asks only for a diagnosis."
            ),
            expectedCommentRevision: first.methodFeedbackComment?.revision,
            expectedResultFingerprint: try first.finalizedResultFingerprint()
        )
        let staleSubmission = try ResearchMethodImprovementSubmission(
            requestID: UUID(),
            feedbackRevision: firstContext.feedbackRevision,
            expectedResultFingerprint: firstContext.expectedResultFingerprint,
            targetID: "primary-method",
            expectedTargetRevision: original.primaryMarkdownRevision,
            disposition: .replace,
            replacementSource: original.primaryMarkdownSource + "\nstale edit\n",
            diagnosis: "This now-stale comment must not authorize a Method edit."
        )
        await #expect(throws: ResearchMethodImprovementError.self) {
            _ = try await handle.research.submitMethodImprovement(
                credential: firstCredential,
                run: firstHandoff.run,
                submission: staleSubmission
            )
        }
        #expect(try await handle.research.researchMethod(
            for: .synthesize
        ).primaryMarkdownRevision == original.primaryMarkdownRevision)

        let secondHandoff = try await handle.research.issueMethodImprovementHandoff(
            recordID: record.id
        )
        let secondCredential = try await handle.research.pairAgent(
            run: secondHandoff.run,
            pairingCode: secondHandoff.pairingCode
        )
        let secondContext = try await handle.research.methodImprovementContext(
            credential: secondCredential,
            run: secondHandoff.run
        )
        let diagnosis = try ResearchMethodImprovementSubmission(
            requestID: UUID(),
            feedbackRevision: try #require(
                revised.methodFeedbackComment?.revision
            ),
            expectedResultFingerprint: try revised.finalizedResultFingerprint(),
            targetID: "primary-method",
            expectedTargetRevision: original.primaryMarkdownRevision,
            disposition: .diagnosedNoChange,
            diagnosis: "The issue concerns this particular execution, not the current Method text."
        )
        #expect(secondContext.feedbackRevision == diagnosis.feedbackRevision)
        let receipt = try await handle.research.submitMethodImprovement(
            credential: secondCredential,
            run: secondHandoff.run,
            submission: diagnosis
        )
        #expect(receipt.disposition == .diagnosedNoChange)
        #expect(receipt.feedbackCleared)
        #expect(receipt.startingRevision == receipt.endingRevision)
        #expect(try await handle.research.researchMethod(
            for: .synthesize
        ).primaryMarkdownRevision == original.primaryMarkdownRevision)
        await runtime.shutdown()
    }

    @Test("A committed Method write with an interrupted receipt resumes without writing twice")
    func committedWriteReconciliation() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let record = try await completedSynthesis(handle: handle, fixture: fixture)
        let commented = try await addFeedback(
            "Add one recovery-focused sentence.",
            to: record,
            handle: handle
        )
        let original = try await handle.research.researchMethod(for: .synthesize)
        let handoff = try await handle.research.issueMethodImprovementHandoff(
            recordID: record.id
        )
        let credential = try await handle.research.pairAgent(
            run: handoff.run,
            pairingCode: handoff.pairingCode
        )
        let context = try await handle.research.methodImprovementContext(
            credential: credential,
            run: handoff.run
        )
        let replacement = original.primaryMarkdownSource + "\nRecovery remains explicit.\n"
        let submission = try ResearchMethodImprovementSubmission(
            requestID: UUID(),
            feedbackRevision: try #require(
                commented.methodFeedbackComment?.revision
            ),
            expectedResultFingerprint: try commented.finalizedResultFingerprint(),
            targetID: "primary-method",
            expectedTargetRevision: original.primaryMarkdownRevision,
            disposition: .replace,
            replacementSource: replacement,
            diagnosis: "The exact primary Method needs this bounded recovery clarification."
        )
        let fingerprint = try submission.contentFingerprint()
        let improvement = try await handle.services.localResearchExecutionStore
            .methodImprovement(id: try await runID(context, handle: handle))
        _ = try await handle.services.localResearchExecutionStore
            .beginMethodImprovement(
                runID: improvement.id,
                submission: submission,
                submissionFingerprint: fingerprint
            )
        _ = try await handle.saveCurrentResearchMethod(
            registrationKey: original.registration.key,
            source: replacement,
            expectedRevision: original.primaryMarkdownRevision
        )

        let receipt = try await handle.research.submitMethodImprovement(
            credential: credential,
            run: handoff.run,
            submission: submission
        )
        #expect(receipt.endingRevision == DocumentFingerprint(content: replacement))
        #expect(receipt.feedbackCleared)
        #expect(try await handle.services.portableResearchRecordStore.record(
            id: record.id
        ).methodFeedbackComment == nil)
        await runtime.shutdown()
    }

    @Test("The same explicit boundary can replace one linked Practice and preserve its previous-edit recovery point")
    func linkedPracticeImprovement() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let method = try await handle.research.researchMethod(for: .synthesize)
        let practice = try #require(
            try await handle.research.philosophicalPractices().first
        )
        _ = try await handle.research.saveResearchMethod(
            registrationKey: method.registration.key,
            source: method.primaryMarkdownSource + "\n[[\(practice.title)]]\n",
            expectedRevision: method.primaryMarkdownRevision
        )
        let record = try await completedSynthesis(handle: handle, fixture: fixture)
        let commented = try await addFeedback(
            "Clarify one linked Practice without changing the primary Method.",
            to: record,
            handle: handle
        )
        let handoff = try await handle.research.issueMethodImprovementHandoff(
            recordID: record.id
        )
        let credential = try await handle.research.pairAgent(
            run: handoff.run,
            pairingCode: handoff.pairingCode
        )
        let context = try await handle.research.methodImprovementContext(
            credential: credential,
            run: handoff.run
        )
        let target = try #require(context.targets.first(where: {
            $0.kind == .practice && $0.relativePath == practice.relativePath
        }))
        let replacement = practice.source + "\nPractice recovery remains explicit.\n"
        let submission = try ResearchMethodImprovementSubmission(
            requestID: UUID(),
            feedbackRevision: try #require(
                commented.methodFeedbackComment?.revision
            ),
            expectedResultFingerprint: try commented.finalizedResultFingerprint(),
            targetID: target.id,
            expectedTargetRevision: target.revision,
            disposition: .replace,
            replacementSource: replacement,
            diagnosis: "The bounded feedback concerns this linked Practice only."
        )
        let receipt = try await handle.research.submitMethodImprovement(
            credential: credential,
            run: handoff.run,
            submission: submission
        )
        #expect(receipt.feedbackCleared)
        let updated = try #require(
            try await handle.research.philosophicalPractices().first(where: {
                $0.relativePath == practice.relativePath
            })
        )
        #expect(updated.source == replacement)
        let restored = try await handle.research
            .restorePreviousPhilosophicalPractice(
                relativePath: practice.relativePath,
                expectedRevision: updated.revision
            )
        #expect(restored.source == practice.source)
        await runtime.shutdown()
    }

    private func completedSynthesis(
        handle: WorkspaceHandle,
        fixture: ResearchFixture
    ) async throws -> PortableResearchRecord {
        let target = try await researchFunctionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let helpers = ResearchFunctionOperationsTests()
        let preparation = try await handle.research.prepareAction(
            try await helpers.actionRequest(
                handle: handle,
                actionID: .synthesize,
                target: helpers.actionNote(target)
            )
        )
        let handoff = try await handle.research.issueAgentHandoff(
            runID: preparation.runID
        )
        let credential = try await handle.research.pairAgent(
            run: handoff.run,
            pairingCode: handoff.pairingCode
        )
        _ = try await handle.research.submitAgentResult(
            credential: credential,
            run: handoff.run,
            submission: try ResearchAgentResultSubmission(
                academicResults: ResearchAcademicFieldValues(
                    rawValues: [
                        "synthesis-outcome": .freeText(
                            "A bounded synthesis for Method feedback."
                        ),
                        "contribution": .multipleChoice(["qualifies"]),
                    ],
                    definitions: preparation.snapshot.resultContract.academicFields
                )
            )
        )
        return try await handle.services.portableResearchRecordStore.record(
            id: preparation.runID
        )
    }

    private func addFeedback(
        _ text: String,
        to record: PortableResearchRecord,
        handle: WorkspaceHandle
    ) async throws -> PortableResearchRecord {
        try await handle.research.saveMethodFeedbackComment(
            recordID: record.id,
            draft: try ResearchMethodFeedbackDraft(text: text),
            expectedCommentRevision: record.methodFeedbackComment?.revision,
            expectedResultFingerprint: try record.finalizedResultFingerprint()
        )
    }

    private func runID(
        _ context: ResearchMethodImprovementContext,
        handle: WorkspaceHandle
    ) async throws -> UUID {
        let listing = try await handle.services.localResearchExecutionStore.listing()
        return try #require(listing.records.first(where: {
            $0.id == context.parentRecordID
        })?.methodImprovementRun?.id)
    }
}
