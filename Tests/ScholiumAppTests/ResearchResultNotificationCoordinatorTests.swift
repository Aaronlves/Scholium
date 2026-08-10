import Foundation
import ScholiumContracts
@testable import ScholiumApp
import Testing

@Suite("Research result notifications")
@MainActor
struct ResearchResultNotificationCoordinatorTests {
    @Test("Foreground completion stays in the source window until explicit review")
    func foregroundDeliveryIsSourceWindowBound() async throws {
        let system = TestResearchResultSystemNotifications(state: .authorized)
        let defaults = isolatedDefaults()
        let coordinator = ResearchResultNotificationCoordinator(
            systemNotifications: system,
            userDefaults: defaults,
            applicationIsActive: { true }
        )
        let triptychID = UUID()
        let sourceWindowID = UUID()
        let otherWindowID = UUID()
        let waiting = activity(state: .waitingForAgent)
        let ready = activity(
            runID: waiting.runID,
            targetNoteID: waiting.targetNoteID,
            state: .resultReady,
            recordID: UUID(),
            fingerprint: DocumentFingerprint(content: "result")
        )
        var sourceNotices: [ResearchResultReviewDestination] = []
        var otherNotices: [ResearchResultReviewDestination] = []
        var opened: [ResearchResultReviewDestination] = []
        var dismissed: [ResearchResultReviewDestination] = []

        _ = coordinator.registerWindow(
            windowID: sourceWindowID,
            triptychID: triptychID,
            presentResult: { sourceNotices.append($0) },
            dismissResult: { dismissed.append($0) },
            presentPermission: { _ in },
            dismissPermission: {},
            openReview: { opened.append($0) }
        )
        _ = coordinator.registerWindow(
            windowID: otherWindowID,
            triptychID: triptychID,
            presentResult: { otherNotices.append($0) },
            dismissResult: { _ in },
            presentPermission: { _ in },
            dismissPermission: {},
            openReview: { opened.append($0) }
        )
        coordinator.receive(activities: [waiting], triptychID: triptychID)
        coordinator.recordSuccessfulHandoff(
            runID: waiting.runID,
            triptychID: triptychID,
            sourceWindowID: sourceWindowID
        )
        coordinator.receive(activities: [ready], triptychID: triptychID)
        coordinator.receive(activities: [ready], triptychID: triptychID)

        #expect(sourceNotices.count == 1)
        #expect(otherNotices.isEmpty)
        #expect(opened.isEmpty)
        #expect(system.delivered.isEmpty)

        let destination = try #require(sourceNotices.first)
        coordinator.review(destination, from: sourceWindowID)
        #expect(opened == [destination])

        coordinator.receive(activities: [], triptychID: triptychID)
        #expect(dismissed == [destination])
        #expect(system.removed.count == 1)
    }

    @Test("Background delivery is private, deduplicated, and routes only a current exact result")
    func backgroundDeliveryIsPrivateAndExact() async throws {
        let system = TestResearchResultSystemNotifications(state: .authorized)
        let coordinator = ResearchResultNotificationCoordinator(
            systemNotifications: system,
            userDefaults: isolatedDefaults(),
            applicationIsActive: { false }
        )
        let triptychID = UUID()
        let windowID = UUID()
        let waiting = activity(state: .waitingForAgent)
        let ready = activity(
            runID: waiting.runID,
            targetNoteID: waiting.targetNoteID,
            state: .resultReady,
            recordID: UUID(),
            fingerprint: DocumentFingerprint(content: "exact result")
        )
        var opened: [ResearchResultReviewDestination] = []
        _ = coordinator.registerWindow(
            windowID: windowID,
            triptychID: triptychID,
            presentResult: { _ in },
            dismissResult: { _ in },
            presentPermission: { _ in },
            dismissPermission: {},
            openReview: { opened.append($0) }
        )
        coordinator.receive(activities: [waiting], triptychID: triptychID)
        coordinator.recordSuccessfulHandoff(
            runID: waiting.runID,
            triptychID: triptychID,
            sourceWindowID: windowID
        )
        coordinator.receive(activities: [ready], triptychID: triptychID)
        coordinator.receive(activities: [ready], triptychID: triptychID)
        await settleTasks()

        let request = try #require(system.delivered.first)
        #expect(system.delivered.count == 1)
        #expect(request.body == "An Agent result is ready to review.")
        #expect(!request.body.contains(ready.targetNoteID.uuidString))
        #expect(opened.isEmpty)

        system.activate(request.destination)
        await settleTasks()
        #expect(opened == [request.destination])

        coordinator.receive(activities: [], triptychID: triptychID)
        system.activate(request.destination)
        await settleTasks()
        #expect(opened == [request.destination])
        #expect(system.removed == [request.identifier])
    }

    @Test("Review completion wins over a suspended system delivery")
    func completionCancelsSuspendedDelivery() async throws {
        let system = TestResearchResultSystemNotifications(state: .authorized)
        system.suspendsDelivery = true
        let coordinator = ResearchResultNotificationCoordinator(
            systemNotifications: system,
            userDefaults: isolatedDefaults(),
            applicationIsActive: { false }
        )
        let triptychID = UUID()
        let waiting = activity(state: .waitingForAgent)
        let ready = activity(
            runID: waiting.runID,
            targetNoteID: waiting.targetNoteID,
            state: .resultReady,
            recordID: UUID(),
            fingerprint: DocumentFingerprint(content: "result")
        )
        coordinator.receive(activities: [waiting], triptychID: triptychID)
        coordinator.receive(activities: [ready], triptychID: triptychID)
        await waitUntil { system.deliveryContinuation != nil }

        coordinator.receive(activities: [], triptychID: triptychID)
        system.resumeDelivery()
        await settleTasks()

        let request = try #require(system.delivered.first)
        #expect(system.activeIdentifiers.isEmpty)
        #expect(system.removed.filter { $0 == request.identifier }.count == 2)
    }

    @Test("A closed source window does not redirect a foreground notice")
    func closedSourceWindowDoesNotRetargetForegroundDelivery() {
        let system = TestResearchResultSystemNotifications(state: .authorized)
        let coordinator = ResearchResultNotificationCoordinator(
            systemNotifications: system,
            userDefaults: isolatedDefaults(),
            applicationIsActive: { true }
        )
        let triptychID = UUID()
        let sourceWindowID = UUID()
        let fallbackWindowID = UUID()
        let waiting = activity(state: .waitingForAgent)
        let ready = activity(
            runID: waiting.runID,
            targetNoteID: waiting.targetNoteID,
            state: .resultReady,
            recordID: UUID(),
            fingerprint: DocumentFingerprint(content: "ready")
        )
        var fallbackNotices = 0
        let sourceToken = coordinator.registerWindow(
            windowID: sourceWindowID,
            triptychID: triptychID,
            presentResult: { _ in },
            dismissResult: { _ in },
            presentPermission: { _ in },
            dismissPermission: {},
            openReview: { _ in }
        )
        _ = coordinator.registerWindow(
            windowID: fallbackWindowID,
            triptychID: triptychID,
            presentResult: { _ in fallbackNotices += 1 },
            dismissResult: { _ in },
            presentPermission: { _ in },
            dismissPermission: {},
            openReview: { _ in }
        )
        coordinator.receive(activities: [waiting], triptychID: triptychID)
        coordinator.recordSuccessfulHandoff(
            runID: waiting.runID,
            triptychID: triptychID,
            sourceWindowID: sourceWindowID
        )
        coordinator.unregisterWindow(
            windowID: sourceWindowID,
            token: sourceToken
        )
        coordinator.receive(activities: [ready], triptychID: triptychID)

        #expect(fallbackNotices == 0)
        #expect(system.delivered.isEmpty)
    }

    @Test("A system notification can open the exact Records route with no main window")
    func systemClickUsesRetainedSceneRouterWithoutAWindow() async throws {
        let system = TestResearchResultSystemNotifications(state: .authorized)
        let coordinator = ResearchResultNotificationCoordinator(
            systemNotifications: system,
            userDefaults: isolatedDefaults(),
            applicationIsActive: { false }
        )
        let triptychID = UUID()
        let waiting = activity(state: .waitingForAgent)
        let ready = activity(
            runID: waiting.runID,
            targetNoteID: waiting.targetNoteID,
            state: .resultReady,
            recordID: UUID(),
            fingerprint: DocumentFingerprint(content: "exact result")
        )
        var opened: [ResearchResultReviewDestination] = []
        coordinator.registerReviewRouter(triptychID: triptychID) {
            opened.append($0)
        }
        coordinator.receive(activities: [waiting], triptychID: triptychID)
        coordinator.receive(activities: [ready], triptychID: triptychID)
        await settleTasks()

        let request = try #require(system.delivered.first)
        system.activate(request.destination)
        await settleTasks()

        #expect(opened == [request.destination])
    }

    @Test("The first copied handoff offers permission once and denial opens settings")
    func permissionOfferIsOneTime() async {
        let system = TestResearchResultSystemNotifications(state: .notDetermined)
        system.authorizationResult = false
        let coordinator = ResearchResultNotificationCoordinator(
            systemNotifications: system,
            userDefaults: isolatedDefaults(),
            applicationIsActive: { true }
        )
        let triptychID = UUID()
        let windowID = UUID()
        var notices: [ResearchNotificationPermissionNotice] = []
        _ = coordinator.registerWindow(
            windowID: windowID,
            triptychID: triptychID,
            presentResult: { _ in },
            dismissResult: { _ in },
            presentPermission: { notices.append($0) },
            dismissPermission: {},
            openReview: { _ in }
        )

        coordinator.recordSuccessfulHandoff(
            runID: UUID(),
            triptychID: triptychID,
            sourceWindowID: windowID
        )
        await settleTasks()
        #expect(notices == [.enable])

        coordinator.requestNotificationAuthorization(windowID: windowID)
        await settleTasks()
        #expect(system.authorizationRequests == 1)
        #expect(notices == [.enable, .openSettings])

        coordinator.recordSuccessfulHandoff(
            runID: UUID(),
            triptychID: triptychID,
            sourceWindowID: windowID
        )
        await settleTasks()
        #expect(notices == [.enable, .openSettings])

        coordinator.openNotificationSettings()
        #expect(system.settingsOpenCount == 1)
    }

    @Test("Notification authorization is single-flight and a grant dismisses its banner")
    func permissionGrantDismissesBanner() async {
        let system = TestResearchResultSystemNotifications(state: .notDetermined)
        system.suspendsAuthorization = true
        let coordinator = ResearchResultNotificationCoordinator(
            systemNotifications: system,
            userDefaults: isolatedDefaults(),
            applicationIsActive: { true }
        )
        let triptychID = UUID()
        let windowID = UUID()
        var notices: [ResearchNotificationPermissionNotice] = []
        var dismissCount = 0
        _ = coordinator.registerWindow(
            windowID: windowID,
            triptychID: triptychID,
            presentResult: { _ in },
            dismissResult: { _ in },
            presentPermission: { notices.append($0) },
            dismissPermission: { dismissCount += 1 },
            openReview: { _ in }
        )
        coordinator.recordSuccessfulHandoff(
            runID: UUID(),
            triptychID: triptychID,
            sourceWindowID: windowID
        )
        await settleTasks()
        #expect(notices == [.enable])

        coordinator.requestNotificationAuthorization(windowID: windowID)
        coordinator.requestNotificationAuthorization(windowID: windowID)
        await waitUntil { system.authorizationContinuation != nil }
        #expect(system.authorizationRequests == 1)
        system.resumeAuthorization(granted: true)
        await settleTasks()

        #expect(dismissCount == 1)
        #expect(notices == [.enable])
    }

    @Test("An externally authorized notification prompt is dismissed without requesting again")
    func alreadyAuthorizedDismissesBanner() async {
        let system = TestResearchResultSystemNotifications(state: .notDetermined)
        let coordinator = ResearchResultNotificationCoordinator(
            systemNotifications: system,
            userDefaults: isolatedDefaults(),
            applicationIsActive: { true }
        )
        let triptychID = UUID()
        let windowID = UUID()
        var notices: [ResearchNotificationPermissionNotice] = []
        var dismissCount = 0
        _ = coordinator.registerWindow(
            windowID: windowID,
            triptychID: triptychID,
            presentResult: { _ in },
            dismissResult: { _ in },
            presentPermission: { notices.append($0) },
            dismissPermission: { dismissCount += 1 },
            openReview: { _ in }
        )
        coordinator.recordSuccessfulHandoff(
            runID: UUID(),
            triptychID: triptychID,
            sourceWindowID: windowID
        )
        await settleTasks()
        #expect(notices == [.enable])

        system.state = .authorized
        coordinator.requestNotificationAuthorization(windowID: windowID)
        await settleTasks()

        #expect(system.authorizationRequests == 0)
        #expect(dismissCount == 1)
    }

    private func activity(
        runID: UUID = UUID(),
        targetNoteID: UUID = UUID(),
        state: WorkspaceResearchActivityState,
        recordID: UUID? = nil,
        fingerprint: DocumentFingerprint? = nil
    ) -> WorkspaceResearchActivity {
        WorkspaceResearchActivity(
            runID: runID,
            actionID: .analyze,
            targetNoteID: targetNoteID,
            state: state,
            recordID: recordID,
            recordFingerprint: fingerprint,
            updatedAt: Date(timeIntervalSinceReferenceDate: 10)
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "ResearchResultNotificationCoordinatorTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func settleTasks() async {
        for _ in 0..<8 { await Task.yield() }
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }
}

@MainActor
private final class TestResearchResultSystemNotifications:
    ResearchResultSystemNotificationServing
{
    var responseHandler: (@MainActor (ResearchResultReviewDestination) -> Void)?
    var state: ResearchResultNotificationAuthorizationState
    var authorizationResult = true
    var authorizationRequests = 0
    var suspendsAuthorization = false
    var authorizationContinuation: CheckedContinuation<Bool, Never>?
    var delivered: [ResearchResultSystemNotificationRequest] = []
    var removed: [String] = []
    var activeIdentifiers: Set<String> = []
    var suspendsDelivery = false
    var deliveryContinuation: CheckedContinuation<Void, Never>?
    var settingsOpenCount = 0

    init(state: ResearchResultNotificationAuthorizationState) {
        self.state = state
    }

    func authorizationState() async -> ResearchResultNotificationAuthorizationState {
        state
    }

    func requestAuthorization() async throws -> Bool {
        authorizationRequests += 1
        if suspendsAuthorization {
            return await withCheckedContinuation { continuation in
                authorizationContinuation = continuation
            }
        }
        state = authorizationResult ? .authorized : .denied
        return authorizationResult
    }

    func deliver(_ request: ResearchResultSystemNotificationRequest) async throws {
        if suspendsDelivery {
            await withCheckedContinuation { continuation in
                deliveryContinuation = continuation
            }
        }
        delivered.append(request)
        activeIdentifiers.insert(request.identifier)
    }

    func removeNotification(identifier: String) {
        removed.append(identifier)
        activeIdentifiers.remove(identifier)
    }

    func openNotificationSettings() {
        settingsOpenCount += 1
    }

    func activate(_ destination: ResearchResultReviewDestination) {
        responseHandler?(destination)
    }

    func resumeDelivery() {
        suspendsDelivery = false
        let continuation = deliveryContinuation
        deliveryContinuation = nil
        continuation?.resume()
    }

    func resumeAuthorization(granted: Bool) {
        suspendsAuthorization = false
        state = granted ? .authorized : .denied
        let continuation = authorizationContinuation
        authorizationContinuation = nil
        continuation?.resume(returning: granted)
    }
}
