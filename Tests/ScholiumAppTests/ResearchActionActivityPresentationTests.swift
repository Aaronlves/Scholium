import Foundation
import ScholiumContracts
@testable import ScholiumApp
import Testing

@Suite("Research Action activity presentation")
struct ResearchActionActivityPresentationTests {
    @Test("Action state priority preserves actionable recovery")
    func statePriority() throws {
        let targetNoteID = UUID()
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
                activities: [running, attention]
            )
        )

        #expect(presentation.primary == attention)
        #expect(presentation.stateTitle == "Needs Attention")
        #expect(presentation.detail?.contains("source conflict") == true)
        #expect(!presentation.showsProgress)
        #expect(!presentation.showsDirectEnd)
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

    @Test("An active status remains reachable while Action availability is unavailable")
    func activeStatusSurvivesAvailabilityFailure() throws {
        let targetNoteID = UUID()
        let target = ResearchActionNoteSnapshot(
            noteID: targetNoteID,
            note: VaultQualifiedNoteID(
                vaultID: UUID(),
                relativePath: "Analyses/Result.md"
            ),
            role: .analysis,
            fingerprint: DocumentFingerprint(content: "target"),
            title: "Result"
        )
        let running = activity(
            targetNoteID: targetNoteID,
            state: .running,
            updatedAt: 20
        )

        let presentation = ResearchActionsPresentation.make(
            target: target,
            availability: [],
            availabilityError: "Profile unavailable",
            activities: [running]
        )
        let row = try #require(presentation.items.first)

        #expect(row.id == .analyze)
        #expect(row.title == "Analyze")
        #expect(row.canPresent)
        #expect(row.activity?.primary == running)
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
