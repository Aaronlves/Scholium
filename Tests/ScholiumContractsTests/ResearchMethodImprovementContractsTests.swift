import Foundation
import ScholiumContracts
import Testing

@Suite("Method improvement contracts")
struct ResearchMethodImprovementContractsTests {
    @Test("Draft and submission shapes are closed, bounded, and strict")
    func strictShapes() throws {
        let replacement = try ResearchMethodImprovementDraft(
            targetID: "primary-method",
            disposition: .replace,
            replacementSource: "# Revised Method\n",
            diagnosis: "The researcher comment warrants one exact clarification."
        )
        #expect(replacement.disposition == .replace)
        #expect(throws: ResearchMethodImprovementError.self) {
            _ = try ResearchMethodImprovementDraft(
                targetID: "primary-method",
                disposition: .diagnosedNoChange,
                replacementSource: "unexpected",
                diagnosis: "No change."
            )
        }

        let submission = try ResearchMethodImprovementSubmission(
            requestID: UUID(),
            feedbackRevision: UUID(),
            expectedResultFingerprint: DocumentFingerprint(content: "result"),
            targetID: "primary-method",
            expectedTargetRevision: DocumentFingerprint(content: "before"),
            disposition: .replace,
            replacementSource: "after",
            diagnosis: "One bounded edit."
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(submission)
        #expect(try JSONDecoder().decode(
            ResearchMethodImprovementSubmission.self,
            from: data
        ) == submission)
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["hidden_authority"] = true
        let unknown = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: ResearchMethodImprovementError.self) {
            _ = try JSONDecoder().decode(
                ResearchMethodImprovementSubmission.self,
                from: unknown
            )
        }
    }

    @Test("The Run freezes one current Method and exact Practice targets without a package or history")
    func frozenRunAndContext() throws {
        let registration = try ResearchSkillRegistration(
            actionID: .synthesize,
            displayName: "Synthesis Method",
            primaryMarkdown: .machineLocal()
        )
        let practice = try ResearchPracticeSnapshot(
            title: "Dialectical Partner",
            relativePath: "Dialectical Partner.md",
            source: "# Dialectical Partner\n"
        )
        let method = try ResearchMethodSnapshot(
            registration: registration,
            primaryMarkdownSource: "# Synthesis Method\n",
            practices: [practice]
        )
        let run = try ResearchMethodImprovementRun(
            id: UUID(),
            parentRecordID: UUID(),
            triptychID: UUID(),
            registrationKey: registration.key,
            actionID: .synthesize,
            method: method,
            feedbackRevision: UUID(),
            feedbackText: "Preserve the alternative.",
            expectedResultFingerprint: DocumentFingerprint(content: "result")
        )
        let locator = try #require(ResearchRunLocator(
            rawValue: "abcdefghijklmnopqrstuvwx"
        ))
        let context = try ResearchMethodImprovementContext(
            run: locator,
            improvement: run
        )
        #expect(context.targets.map(\.id) == [
            "primary-method", "practice:Dialectical Partner.md",
        ])
        #expect(context.targets.allSatisfy {
            $0.revision == DocumentFingerprint(content: $0.source)
        })

        let encoder = JSONEncoder()
        let data = try encoder.encode(context)
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["provider_id"] = "forbidden"
        #expect(throws: ResearchMethodImprovementError.self) {
            _ = try JSONDecoder().decode(
                ResearchMethodImprovementContext.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
    }

    @Test("Writing evidence is retryable and only one terminal receipt is retained")
    func writingAndCompletion() throws {
        let registration = try ResearchSkillRegistration(
            actionID: .write,
            displayName: "Write Method",
            primaryMarkdown: .machineLocal()
        )
        let method = try ResearchMethodSnapshot(
            registration: registration,
            primaryMarkdownSource: "# Write Method\n",
            practices: []
        )
        let run = try ResearchMethodImprovementRun(
            id: UUID(),
            parentRecordID: UUID(),
            triptychID: UUID(),
            registrationKey: registration.key,
            actionID: .write,
            method: method,
            feedbackRevision: UUID(),
            feedbackText: "Clarify the preservation rule.",
            expectedResultFingerprint: DocumentFingerprint(content: "result")
        )
        let submission = try ResearchMethodImprovementSubmission(
            requestID: UUID(),
            feedbackRevision: run.feedbackRevision,
            expectedResultFingerprint: run.expectedResultFingerprint,
            targetID: "primary-method",
            expectedTargetRevision: method.primaryMarkdownRevision,
            disposition: .replace,
            replacementSource: "# Revised Write Method\n",
            diagnosis: "The primary Method needs one clarification."
        )
        let fingerprint = try submission.contentFingerprint()
        let writing = try run.beginning(
            submission: submission,
            submissionFingerprint: fingerprint
        )
        #expect(writing.state == .writing)
        #expect(writing.pendingSubmission == submission)
        let receipt = try ResearchMethodImprovementReceipt(
            runID: run.id,
            requestID: submission.requestID,
            disposition: .replace,
            targetID: submission.targetID,
            startingRevision: submission.expectedTargetRevision,
            endingRevision: DocumentFingerprint(content: "# Revised Write Method\n"),
            feedbackCleared: true,
            diagnosis: submission.diagnosis
        )
        let completed = try writing.completing(
            submissionFingerprint: fingerprint,
            receipt: receipt
        )
        #expect(completed.state == .completed)
        #expect(completed.pendingSubmission == nil)
        #expect(completed.receipt == receipt)
    }
}
