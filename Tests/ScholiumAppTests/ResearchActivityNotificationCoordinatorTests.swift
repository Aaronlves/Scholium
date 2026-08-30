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

    @Test("Settings can recover notification authorization after education is dismissed")
    func settingsAuthorizationRecovery() async {
        let system = ActivityNotificationSystem(
            authorizationState: .notDetermined,
            authorizationStateAfterRequest: .authorized
        )
        let coordinator = ResearchResultNotificationCoordinator(
            systemNotifications: system,
            userDefaults: UserDefaults(suiteName: UUID().uuidString)!,
            applicationIsActive: { true }
        )

        await coordinator.refreshSystemNotificationAuthorization()
        #expect(coordinator.systemNotificationAuthorizationState == .notDetermined)

        await coordinator.requestSystemNotificationAuthorizationFromSettings()
        #expect(coordinator.systemNotificationAuthorizationState == .authorized)
        #expect(system.authorizationRequestCount == 1)

        coordinator.openNotificationSettings()
        #expect(system.openSettingsCount == 1)
    }

    @Test("A cold-launch notification click waits for its authoritative Triptych snapshot")
    func coldLaunchNotificationClick() {
        let system = ActivityNotificationSystem()
        let coordinator = ResearchResultNotificationCoordinator(
            systemNotifications: system,
            userDefaults: UserDefaults(suiteName: UUID().uuidString)!,
            applicationIsActive: { true }
        )
        let triptychID = UUID()
        let arrival = WorkspaceResearchResultArrival(
            runID: UUID(),
            recordID: UUID(),
            actionID: .analyze,
            originNoteID: UUID(),
            targetTitle: "Reasons",
            affectedNotes: [],
            recordFingerprint: DocumentFingerprint(content: "result"),
            finishedAt: Date(timeIntervalSince1970: 40)
        )
        let destination = ResearchResultReviewDestination(
            triptychID: triptychID,
            arrival: arrival
        )
        var opened: [ResearchResultReviewDestination] = []

        system.responseHandler?(destination)
        coordinator.registerReviewRouter(triptychID: triptychID) {
            opened.append($0)
        }
        #expect(opened.isEmpty)

        coordinator.receive(
            activities: [],
            arrivals: [arrival],
            triptychID: triptychID
        )

        #expect(opened == [destination])
    }

    @Test("System notification payload preserves the exact cold-launch route identity")
    func systemNotificationPayloadRoundTrip() throws {
        let arrival = WorkspaceResearchResultArrival(
            runID: UUID(),
            recordID: UUID(),
            actionID: .checkFidelity,
            originNoteID: UUID(),
            targetTitle: "Fidelity Review",
            affectedNotes: [],
            recordFingerprint: DocumentFingerprint(content: "final result"),
            finishedAt: Date(timeIntervalSince1970: 50)
        )
        let expected = ResearchResultReviewDestination(
            triptychID: UUID(),
            arrival: arrival
        )

        let payload = ResearchResultUserNotificationAdapter.userInfo(
            for: expected
        )
        let decoded = try #require(
            ResearchResultUserNotificationAdapter.destination(from: payload)
        )

        #expect(decoded.triptychID == expected.triptychID)
        #expect(decoded.runID == expected.runID)
        #expect(decoded.actionID == expected.actionID)
        #expect(decoded.targetNoteID == expected.targetNoteID)
        #expect(decoded.recordID == expected.recordID)
        #expect(
            decoded.finalizedResultFingerprint
                == expected.finalizedResultFingerprint
        )

        var invalidPayload = payload
        invalidPayload["result_sha256"] = "not-a-fingerprint"
        #expect(
            ResearchResultUserNotificationAdapter.destination(
                from: invalidPayload
            ) == nil
        )
    }

    #if DEBUG
    @Test("QA Action proof reuses the two latest durable result routes")
    func qaActionNotificationProof() {
        let triptychID = UUID()
        let arrivals = (0..<3).map { offset in
            WorkspaceResearchResultArrival(
                runID: UUID(),
                recordID: UUID(),
                actionID: offset == 0 ? .analyze : .synthesize,
                originNoteID: UUID(),
                targetTitle: "Result \(offset)",
                affectedNotes: [],
                recordFingerprint: DocumentFingerprint(
                    content: "result \(offset)"
                ),
                finishedAt: Date(timeIntervalSince1970: TimeInterval(offset))
            )
        }

        let notifications = QAActionNotificationProof.notifications(
            triptychID: triptychID,
            arrivals: arrivals
        )

        #expect(notifications.count == 2)
        #expect(notifications.map(\.targetTitle) == ["Result 2", "Result 1"])
        #expect(notifications.allSatisfy { $0.triptychID == triptychID })
        #expect(notifications.allSatisfy { $0.state == .resultReady })
        #expect(
            notifications.map(\.result?.recordID)
                == [arrivals[2].recordID, arrivals[1].recordID]
        )

        let shell = WindowShellState()
        let production = ResearchActivityNotification(
            triptychID: triptychID,
            runID: UUID(),
            actionID: .write,
            targetNoteID: UUID(),
            targetTitle: "Production activity",
            state: .running,
            activity: nil,
            result: nil,
            affectedNotes: [],
            updatedAt: .distantPast
        )
        shell.receiveResearchActivityNotifications([production])
        shell.presentQAResearchActivityNotifications(notifications)
        #expect(
            shell.researchActivityNotifications.map(\.runID)
                == notifications.map(\.runID) + [production.runID]
        )

        shell.receiveResearchActivityNotifications([production])
        #expect(
            shell.researchActivityNotifications.map(\.runID)
                == notifications.map(\.runID) + [production.runID]
        )
        #expect(shell.dismissQAResearchActivityNotification(
            runID: notifications[0].runID
        ))
        #expect(
            shell.researchActivityNotifications.map(\.runID)
                == [notifications[1].runID, production.runID]
        )
    }
    #endif
}

@MainActor
private final class ActivityNotificationSystem:
    ResearchResultSystemNotificationServing {
    var responseHandler: (@MainActor (ResearchResultReviewDestination) -> Void)?
    var authorizationStateValue: ResearchResultNotificationAuthorizationState
    let authorizationStateAfterRequest: ResearchResultNotificationAuthorizationState
    private(set) var authorizationRequestCount = 0
    private(set) var openSettingsCount = 0

    init(
        authorizationState: ResearchResultNotificationAuthorizationState = .authorized,
        authorizationStateAfterRequest: ResearchResultNotificationAuthorizationState = .authorized
    ) {
        authorizationStateValue = authorizationState
        self.authorizationStateAfterRequest = authorizationStateAfterRequest
    }

    func authorizationState() async -> ResearchResultNotificationAuthorizationState {
        authorizationStateValue
    }

    func requestAuthorization() async throws -> Bool {
        authorizationRequestCount += 1
        authorizationStateValue = authorizationStateAfterRequest
        return authorizationStateAfterRequest == .authorized
    }
    func deliver(_ request: ResearchResultSystemNotificationRequest) async throws {}
    func removeNotification(identifier: String) {}
    func openNotificationSettings() { openSettingsCount += 1 }
}
