import Foundation
import ScholiumContracts
@testable import ScholiumApp
import Testing

@Suite("Research Action activity notifications")
@MainActor
struct ResearchActivityNotificationCoordinatorTests {
    @Test("Only researcher-decision states enter the Document notification stack")
    func documentStackEligibility() {
        #expect(!ResearchActivityNotificationState.waitingForAgent.requiresResearcherAttention)
        #expect(!ResearchActivityNotificationState.running.requiresResearcherAttention)
        #expect(ResearchActivityNotificationState.needsAttention.requiresResearcherAttention)
        #expect(ResearchActivityNotificationState.resultReady.requiresResearcherAttention)
        #expect(ResearchActivityNotificationState.recoveryRequired.requiresResearcherAttention)
    }

    @Test("One Action item evolves to Result Ready and survives window replacement until Dismiss")
    func persistentActionItem() throws {
        let system = ActivityNotificationSystem()
        let coordinator = ResearchResultNotificationCoordinator(
            systemNotifications: system,
            userDefaults: UserDefaults(suiteName: UUID().uuidString)!,
            applicationIsActive: { true }
        )
        let triptychID = UUID()
        let windowID = UUID()
        let runID = UUID()
        var snapshots: [[ResearchActivityNotification]] = []
        let token = coordinator.registerWindow(
            windowID: windowID,
            triptychID: triptychID,
            receiveActivities: { snapshots.append($0) },
            presentPermission: { _ in },
            dismissPermission: {},
            openReview: { _ in }
        )

        coordinator.receive(activities: [], arrivals: [], triptychID: triptychID)
        let activity = WorkspaceResearchActivity(
            runID: runID,
            actionID: .synthesize,
            targetNoteID: UUID(),
            targetTitle: "Normative Reasons",
            state: .running,
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        coordinator.receive(
            activities: [activity],
            arrivals: [],
            triptychID: triptychID
        )
        #expect(snapshots.last?.count == 1)
        #expect(snapshots.last?.first?.state == .running)

        let arrival = WorkspaceResearchResultArrival(
            runID: runID,
            recordID: runID,
            actionID: .synthesize,
            originNoteID: activity.targetNoteID,
            targetTitle: activity.targetTitle,
            affectedNotes: [
                WorkspaceResearchAffectedNote(
                    noteID: activity.targetNoteID,
                    title: "Normative Reasons"
                ),
                WorkspaceResearchAffectedNote(
                    noteID: UUID(),
                    title: "Practical Options"
                ),
            ],
            recordFingerprint: DocumentFingerprint(content: "result"),
            finishedAt: Date(timeIntervalSince1970: 20)
        )
        coordinator.receive(
            activities: [],
            arrivals: [arrival],
            triptychID: triptychID
        )
        let ready = snapshots.last?.first
        #expect(snapshots.last?.count == 1)
        #expect(ready?.state == .resultReady)
        #expect(ready?.affectedNotes.count == 2)

        coordinator.unregisterWindow(windowID: windowID, token: token)
        var replayed: [ResearchActivityNotification] = []
        _ = coordinator.registerWindow(
            windowID: windowID,
            triptychID: triptychID,
            receiveActivities: { replayed = $0 },
            presentPermission: { _ in },
            dismissPermission: {},
            openReview: { _ in }
        )
        #expect(replayed.count == 1)
        let destination = try #require(replayed.first?.result)
        coordinator.dismiss(destination, from: windowID)
        #expect(replayed.isEmpty)
    }
}

@MainActor
private final class ActivityNotificationSystem:
    ResearchResultSystemNotificationServing {
    var responseHandler: (@MainActor (ResearchResultReviewDestination) -> Void)?

    func authorizationState() async -> ResearchResultNotificationAuthorizationState {
        .authorized
    }

    func requestAuthorization() async throws -> Bool { true }
    func deliver(_ request: ResearchResultSystemNotificationRequest) async throws {}
    func removeNotification(identifier: String) {}
    func openNotificationSettings() {}
}
