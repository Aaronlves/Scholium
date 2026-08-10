import Foundation
import ScholiumContracts
@testable import ScholiumApp
import Testing

@Suite("Research Action activity presentation")
struct ResearchActionActivityPresentationTests {
    @Test("Action state priority preserves recovery while retaining the newest ready result")
    func statePriorityAndOutstandingResults() throws {
        let targetNoteID = UUID()
        let olderReady = activity(
            targetNoteID: targetNoteID,
            state: .resultReady,
            recordID: UUID(),
            fingerprint: DocumentFingerprint(content: "older"),
            updatedAt: 10
        )
        let newestReady = activity(
            targetNoteID: targetNoteID,
            state: .resultReady,
            recordID: UUID(),
            fingerprint: DocumentFingerprint(content: "newer"),
            updatedAt: 20
        )
        let running = activity(
            targetNoteID: targetNoteID,
            state: .running,
            updatedAt: 30
        )
        let attention = activity(
            targetNoteID: targetNoteID,
            state: .needsAttention,
            repairReason: .sourceConflict,
            updatedAt: 5
        )

        let presentation = try #require(
            ResearchActionActivityPresentation.make(
                activities: [olderReady, newestReady, running, attention]
            )
        )

        #expect(presentation.primary == attention)
        #expect(presentation.newestResult == newestReady)
        #expect(presentation.resultReadyCount == 2)
        #expect(presentation.stateTitle == "Needs Attention")
        #expect(presentation.detail?.contains("source conflict") == true)
        #expect(presentation.detail?.contains("2 results") == true)
        #expect(!presentation.showsProgress)
        #expect(!presentation.showsDirectEnd)
    }

    @Test("Multiple ready results choose the newest and expose their count")
    func newestResultAndCount() throws {
        let targetNoteID = UUID()
        let older = activity(
            targetNoteID: targetNoteID,
            state: .resultReady,
            recordID: UUID(),
            fingerprint: DocumentFingerprint(content: "older"),
            updatedAt: 10
        )
        let newer = activity(
            targetNoteID: targetNoteID,
            state: .resultReady,
            recordID: UUID(),
            fingerprint: DocumentFingerprint(content: "newer"),
            updatedAt: 20
        )

        let presentation = try #require(
            ResearchActionActivityPresentation.make(activities: [older, newer])
        )

        #expect(presentation.primary == newer)
        #expect(presentation.newestResult == newer)
        #expect(presentation.resultReadyCount == 2)
        #expect(presentation.stateTitle == "2 Results Ready")
    }

    @Test("Running and waiting states preserve direct End access")
    func activeRunStates() throws {
        let targetNoteID = UUID()
        let waiting = try #require(ResearchActionActivityPresentation.make(
            activities: [activity(
                targetNoteID: targetNoteID,
                state: .waitingForAgent,
                updatedAt: 10
            )]
        ))
        let running = try #require(ResearchActionActivityPresentation.make(
            activities: [activity(
                targetNoteID: targetNoteID,
                state: .running,
                updatedAt: 10
            )]
        ))

        #expect(waiting.stateTitle == "Waiting for Agent")
        #expect(waiting.showsDirectEnd)
        #expect(!waiting.showsProgress)
        #expect(running.stateTitle == "Running")
        #expect(running.showsDirectEnd)
        #expect(running.showsProgress)
    }

    @Test("A durable result remains reachable while Action availability is unavailable")
    func resultSurvivesAvailabilityFailure() throws {
        let targetNoteID = UUID()
        let target = ResearchActionNoteSnapshot(
            noteID: targetNoteID,
            note: VaultQualifiedNoteID(
                vaultID: UUID(),
                relativePath: "Analyses/Result.md"
            ),
            role: .analysis,
            lifecycle: .active,
            fingerprint: DocumentFingerprint(content: "target"),
            title: "Result"
        )
        let ready = activity(
            targetNoteID: targetNoteID,
            state: .resultReady,
            recordID: UUID(),
            fingerprint: DocumentFingerprint(content: "result"),
            updatedAt: 20
        )

        let presentation = ResearchActionsPresentation.make(
            target: target,
            availability: [],
            availabilityError: "Profile unavailable",
            activities: [ready]
        )
        let row = try #require(presentation.items.first)

        #expect(row.id == .analyze)
        #expect(row.title == "Analyze")
        #expect(row.canPresent)
        #expect(row.activity?.primary == ready)
    }

    private func activity(
        targetNoteID: UUID,
        state: WorkspaceResearchActivityState,
        recordID: UUID? = nil,
        fingerprint: DocumentFingerprint? = nil,
        repairReason: WorkspaceResearchActivityRepairReason? = nil,
        updatedAt: TimeInterval
    ) -> WorkspaceResearchActivity {
        WorkspaceResearchActivity(
            runID: UUID(),
            actionID: .analyze,
            targetNoteID: targetNoteID,
            state: state,
            recordID: recordID,
            recordFingerprint: fingerprint,
            repairReason: repairReason,
            updatedAt: Date(timeIntervalSinceReferenceDate: updatedAt)
        )
    }
}
