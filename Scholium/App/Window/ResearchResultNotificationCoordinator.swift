import AppKit
import Combine
import Foundation
import ScholiumContracts
@preconcurrency import UserNotifications

struct ResearchResultReviewDestination: Hashable, Sendable {
    let triptychID: UUID
    let runID: UUID
    let actionID: ResearchActionID
    let targetNoteID: UUID
    let recordID: UUID
    let finalizedResultFingerprint: DocumentFingerprint
    let targetTitle: String
    let affectedNotes: [WorkspaceResearchAffectedNote]
    let finishedAt: Date

    init(triptychID: UUID, arrival: WorkspaceResearchResultArrival) {
        self.triptychID = triptychID
        runID = arrival.runID
        actionID = arrival.actionID
        targetNoteID = arrival.originNoteID
        recordID = arrival.recordID
        finalizedResultFingerprint = arrival.recordFingerprint
        targetTitle = arrival.targetTitle
        affectedNotes = arrival.affectedNotes
        finishedAt = arrival.finishedAt
    }
}

enum ResearchActivityNotificationState: Hashable, Sendable {
    case waitingForAgent
    case running
    case needsAttention
    case resultReady
    case recoveryRequired
}

/// One process-local, Action-owned activity entry. It is a presentation and
/// operation route only; it owns no Record, Note review, Undo, or acceptance
/// state.
struct ResearchActivityNotification: Hashable, Identifiable, Sendable {
    let triptychID: UUID
    let runID: UUID
    let actionID: ResearchActionID
    let targetNoteID: UUID
    let targetTitle: String
    let state: ResearchActivityNotificationState
    let activity: WorkspaceResearchActivity?
    let result: ResearchResultReviewDestination?
    let affectedNotes: [WorkspaceResearchAffectedNote]
    let updatedAt: Date

    var id: UUID { runID }
}

enum ResearchNotificationPermissionNotice: Equatable {
    case enable
    case openSettings
}

enum ResearchResultNotificationAuthorizationState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

struct ResearchResultSystemNotificationRequest: Equatable, Sendable {
    let identifier: String
    let body: String
    let destination: ResearchResultReviewDestination
}

@MainActor
protocol ResearchResultSystemNotificationServing: AnyObject {
    var responseHandler: (@MainActor (ResearchResultReviewDestination) -> Void)? {
        get set
    }

    func authorizationState() async -> ResearchResultNotificationAuthorizationState
    func requestAuthorization() async throws -> Bool
    func deliver(_ request: ResearchResultSystemNotificationRequest) async throws
    func removeNotification(identifier: String)
    func openNotificationSettings()
}

@MainActor
final class ResearchResultUserNotificationAdapter: NSObject,
    ResearchResultSystemNotificationServing,
    UNUserNotificationCenterDelegate
{
    var responseHandler: (@MainActor (ResearchResultReviewDestination) -> Void)?

    private let center: UNUserNotificationCenter

    override init() {
        center = .current()
        super.init()
        center.delegate = self
    }

    func authorizationState() async -> ResearchResultNotificationAuthorizationState {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert])
    }

    func deliver(_ request: ResearchResultSystemNotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.body = request.body
        content.threadIdentifier = "scholium-research-results"
        content.userInfo = Self.userInfo(for: request.destination)
        try await center.add(UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: nil
        ))
    }

    func removeNotification(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func openNotificationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (
            UNNotificationPresentationOptions
        ) -> Void
    ) {
        // Foreground delivery is owned by the persistent in-app Action activity.
        completionHandler([])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let destination = Self.destination(
            from: response.notification.request.content.userInfo
        )
        completionHandler()
        guard let destination else { return }
        Task { @MainActor [weak self] in
            self?.responseHandler?(destination)
        }
    }

    private static func userInfo(
        for destination: ResearchResultReviewDestination
    ) -> [AnyHashable: Any] {
        [
            "triptych_id": destination.triptychID.uuidString,
            "run_id": destination.runID.uuidString,
            "action_id": destination.actionID.rawValue,
            "target_note_id": destination.targetNoteID.uuidString,
            "record_id": destination.recordID.uuidString,
            "result_sha256": destination.finalizedResultFingerprint.sha256,
            "result_byte_count": destination.finalizedResultFingerprint.byteCount,
        ]
    }

    private nonisolated static func destination(
        from userInfo: [AnyHashable: Any]
    ) -> ResearchResultReviewDestination? {
        guard let triptych = userInfo["triptych_id"] as? String,
              let triptychID = UUID(uuidString: triptych),
              let run = userInfo["run_id"] as? String,
              let runID = UUID(uuidString: run),
              let action = userInfo["action_id"] as? String,
              let actionID = ResearchActionID(rawValue: action),
              let target = userInfo["target_note_id"] as? String,
              let targetNoteID = UUID(uuidString: target),
              let record = userInfo["record_id"] as? String,
              let recordID = UUID(uuidString: record),
              let sha256 = userInfo["result_sha256"] as? String,
              let byteCount = userInfo["result_byte_count"] as? Int,
              sha256.range(
                  of: #"^[0-9a-f]{64}$"#,
                  options: .regularExpression
              ) != nil,
              byteCount >= 0 else { return nil }
        return ResearchResultReviewDestination(
            triptychID: triptychID,
            runID: runID,
            actionID: actionID,
            targetNoteID: targetNoteID,
            recordID: recordID,
            finalizedResultFingerprint: DocumentFingerprint(
                sha256: sha256,
                byteCount: byteCount
            ),
            targetTitle: "",
            affectedNotes: [],
            finishedAt: .distantPast
        )
    }
}

private extension ResearchResultReviewDestination {
    init(
        triptychID: UUID,
        runID: UUID,
        actionID: ResearchActionID,
        targetNoteID: UUID,
        recordID: UUID,
        finalizedResultFingerprint: DocumentFingerprint,
        targetTitle: String = "",
        affectedNotes: [WorkspaceResearchAffectedNote] = [],
        finishedAt: Date = .distantPast
    ) {
        self.triptychID = triptychID
        self.runID = runID
        self.actionID = actionID
        self.targetNoteID = targetNoteID
        self.recordID = recordID
        self.finalizedResultFingerprint = finalizedResultFingerprint
        self.targetTitle = targetTitle
        self.affectedNotes = affectedNotes
        self.finishedAt = finishedAt
    }
}

/// App-wide delivery coordinator. Execution and portable Records remain the
/// durable owners; this value owns only source-window affinity, transition
/// observation, notification delivery, and exact click routing.
@MainActor
final class ResearchResultNotificationCoordinator {
    private struct ResultKey: Hashable {
        let recordID: UUID
        let fingerprint: DocumentFingerprint
    }

    private struct WindowEndpoint {
        let token: UUID
        let windowID: UUID
        let triptychID: UUID
        var activationOrdinal: UInt64
        let receiveActivities: @MainActor ([ResearchActivityNotification]) -> Void
        let presentPermission: @MainActor (ResearchNotificationPermissionNotice) -> Void
        let dismissPermission: @MainActor () -> Void
        let openReview: @MainActor (ResearchResultReviewDestination) -> Void
    }

    private static let permissionPromptKey =
        "researchResultNotifications.didOfferPermission"

    private let systemNotifications: any ResearchResultSystemNotificationServing
    private let userDefaults: UserDefaults
    private let applicationIsActive: @MainActor () -> Bool
    private var boundStoreIdentity: ObjectIdentifier?
    private var storeCancellables: Set<AnyCancellable> = []
    private var initializedTriptychs: Set<UUID> = []
    private var readyByTriptych: [UUID: [ResultKey: ResearchResultReviewDestination]] = [:]
    private var activitiesByTriptych: [UUID: [UUID: WorkspaceResearchActivity]] = [:]
    private var presentedResultKeys: Set<ResultKey> = []
    private var deliveredKeys: Set<ResultKey> = []
    private var deliveryTasks: [ResultKey: Task<Void, Never>] = [:]
    private var deliveryTokens: [ResultKey: UUID] = [:]
    private var sourceWindowByRunID: [UUID: UUID] = [:]
    private var windowEndpoints: [UUID: WindowEndpoint] = [:]
    private var reviewRoutersByTriptych: [
        UUID: @MainActor (ResearchResultReviewDestination) -> Void
    ] = [:]
    private var pendingReviewDestination: ResearchResultReviewDestination?
    private var authorizationRequestWindowIDs: Set<UUID> = []
    private var nextActivationOrdinal: UInt64 = 0

    init(
        systemNotifications: any ResearchResultSystemNotificationServing =
            ResearchResultUserNotificationAdapter(),
        userDefaults: UserDefaults = .standard,
        applicationIsActive: @escaping @MainActor () -> Bool = { NSApp.isActive }
    ) {
        self.systemNotifications = systemNotifications
        self.userDefaults = userDefaults
        self.applicationIsActive = applicationIsActive
        systemNotifications.responseHandler = { [weak self] destination in
            self?.openReviewFromSystemNotification(destination)
        }
    }

    func bind(to workspaceStore: WorkspaceStore) {
        let identity = ObjectIdentifier(workspaceStore)
        guard boundStoreIdentity != identity else { return }
        boundStoreIdentity = identity
        storeCancellables.removeAll()

        workspaceStore.$workspaceActivations
            .sink { [weak self] activations in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    for (triptychID, activation) in activations {
                        receive(
                            activities: activation.snapshot.research.activities,
                            arrivals: activation.snapshot.research.resultArrivals,
                            triptychID: triptychID
                        )
                    }
                }
            }
            .store(in: &storeCancellables)

        workspaceStore.$workspaceEvents
            .sink { [weak self] events in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    for (triptychID, event) in events {
                        receive(
                            activities: event.snapshot.research.activities,
                            arrivals: event.snapshot.research.resultArrivals,
                            triptychID: triptychID
                        )
                    }
                }
            }
            .store(in: &storeCancellables)
    }

    @discardableResult
    func registerWindow(
        windowID: UUID,
        triptychID: UUID,
        receiveActivities: @escaping @MainActor (
            [ResearchActivityNotification]
        ) -> Void,
        presentPermission: @escaping @MainActor (
            ResearchNotificationPermissionNotice
        ) -> Void,
        dismissPermission: @escaping @MainActor () -> Void,
        openReview: @escaping @MainActor (
            ResearchResultReviewDestination
        ) -> Void
    ) -> UUID {
        let token = UUID()
        nextActivationOrdinal &+= 1
        windowEndpoints[windowID] = WindowEndpoint(
            token: token,
            windowID: windowID,
            triptychID: triptychID,
            activationOrdinal: nextActivationOrdinal,
            receiveActivities: receiveActivities,
            presentPermission: presentPermission,
            dismissPermission: dismissPermission,
            openReview: openReview
        )
        receiveActivities(currentActivities(for: triptychID))
        routePendingReviewIfPossible()
        return token
    }

    func unregisterWindow(windowID: UUID, token: UUID) {
        guard windowEndpoints[windowID]?.token == token else { return }
        windowEndpoints[windowID] = nil
        sourceWindowByRunID = sourceWindowByRunID.filter { $0.value != windowID }
    }

    func windowDidActivate(windowID: UUID, token: UUID) {
        guard var endpoint = windowEndpoints[windowID], endpoint.token == token else {
            return
        }
        nextActivationOrdinal &+= 1
        endpoint.activationOrdinal = nextActivationOrdinal
        windowEndpoints[windowID] = endpoint
    }

    /// Retains the SwiftUI scene-opening capability independently from a
    /// workspace window endpoint. This lets a delivered system notification
    /// open its exact Records window after all main windows have been closed,
    /// without treating another workspace window as the result's source.
    func registerReviewRouter(
        triptychID: UUID,
        openReview: @escaping @MainActor (
            ResearchResultReviewDestination
        ) -> Void
    ) {
        reviewRoutersByTriptych[triptychID] = openReview
        routePendingReviewIfPossible()
    }

    func recordSuccessfulHandoff(
        runID: UUID,
        triptychID: UUID,
        sourceWindowID: UUID
    ) {
        sourceWindowByRunID[runID] = sourceWindowID
        guard !userDefaults.bool(forKey: Self.permissionPromptKey),
              let endpoint = windowEndpoints[sourceWindowID],
              endpoint.triptychID == triptychID else { return }
        userDefaults.set(true, forKey: Self.permissionPromptKey)
        Task { @MainActor [weak self] in
            guard let self,
                  let currentEndpoint = windowEndpoints[sourceWindowID],
                  currentEndpoint.token == endpoint.token else { return }
            switch await systemNotifications.authorizationState() {
            case .notDetermined:
                currentEndpoint.presentPermission(.enable)
            case .denied:
                currentEndpoint.presentPermission(.openSettings)
            case .authorized:
                break
            }
        }
    }

    func requestNotificationAuthorization(windowID: UUID) {
        guard let endpoint = windowEndpoints[windowID],
              authorizationRequestWindowIDs.insert(windowID).inserted else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { authorizationRequestWindowIDs.remove(windowID) }
            @MainActor
            func currentEndpoint() -> WindowEndpoint? {
                guard let current = windowEndpoints[windowID],
                      current.token == endpoint.token else { return nil }
                return current
            }
            switch await systemNotifications.authorizationState() {
            case .authorized:
                currentEndpoint()?.dismissPermission()
            case .denied:
                currentEndpoint()?.presentPermission(.openSettings)
            case .notDetermined:
                do {
                    let granted = try await systemNotifications.requestAuthorization()
                    guard let current = currentEndpoint() else { return }
                    if granted {
                        current.dismissPermission()
                    } else if await systemNotifications.authorizationState()
                        == .denied {
                        current.presentPermission(.openSettings)
                    }
                } catch {
                    // The prompt remains available. Action and in-app result
                    // delivery do not depend on notification authorization.
                }
            }
        }
    }

    func openNotificationSettings() {
        systemNotifications.openNotificationSettings()
    }

    func review(
        _ destination: ResearchResultReviewDestination,
        from windowID: UUID
    ) {
        guard destinationIsCurrent(destination),
              let endpoint = windowEndpoints[windowID],
              endpoint.triptychID == destination.triptychID else { return }
        endpoint.openReview(destination)
    }

    /// Removes only the completed Action's process-local activity entry. It
    /// does not mutate its Record, Note review, Undo, or researcher judgment.
    func dismiss(
        _ destination: ResearchResultReviewDestination,
        from windowID: UUID
    ) {
        guard destinationIsCurrent(destination),
              let endpoint = windowEndpoints[windowID],
              endpoint.triptychID == destination.triptychID else { return }
        let key = ResultKey(
            recordID: destination.recordID,
            fingerprint: destination.finalizedResultFingerprint
        )
        presentedResultKeys.remove(key)
        systemNotifications.removeNotification(
            identifier: Self.notificationIdentifier(for: key)
        )
        publishActivities(triptychID: destination.triptychID)
    }

    func receive(
        activities: [WorkspaceResearchActivity],
        arrivals: [WorkspaceResearchResultArrival],
        triptychID: UUID
    ) {
        activitiesByTriptych[triptychID] = Dictionary(
            uniqueKeysWithValues: activities.map { ($0.runID, $0) }
        )
        let current = Dictionary(uniqueKeysWithValues: arrivals.map {
            arrival -> (ResultKey, ResearchResultReviewDestination) in
            let destination = ResearchResultReviewDestination(
                triptychID: triptychID,
                arrival: arrival
            )
            return (
                ResultKey(
                    recordID: destination.recordID,
                    fingerprint: destination.finalizedResultFingerprint
                ),
                destination
            )
        })
        let previous = readyByTriptych[triptychID] ?? [:]
        readyByTriptych[triptychID] = current

        for (key, destination) in previous where current[key] == nil {
            deliveredKeys.remove(key)
            deliveryTasks[key]?.cancel()
            deliveryTasks[key] = nil
            deliveryTokens[key] = nil
            systemNotifications.removeNotification(
                identifier: Self.notificationIdentifier(for: key)
            )
            presentedResultKeys.remove(key)
            if pendingReviewDestination == destination {
                pendingReviewDestination = nil
            }
        }

        guard initializedTriptychs.insert(triptychID).inserted == false else {
            publishActivities(triptychID: triptychID)
            return
        }
        for (key, destination) in current where previous[key] == nil {
            presentedResultKeys.insert(key)
            deliverIfNeeded(destination, key: key)
        }
        publishActivities(triptychID: triptychID)
    }

    private func publishActivities(triptychID: UUID) {
        let current = currentActivities(for: triptychID)
        for endpoint in windowEndpoints.values
            where endpoint.triptychID == triptychID {
            endpoint.receiveActivities(current)
        }
    }

    private func currentActivities(
        for triptychID: UUID
    ) -> [ResearchActivityNotification] {
        var byRunID: [UUID: ResearchActivityNotification] = [:]
        for activity in (activitiesByTriptych[triptychID] ?? [:]).values {
            let state: ResearchActivityNotificationState
            if activity.repairReason == .recoveryRequired {
                state = .recoveryRequired
            } else {
                state = switch activity.state {
                case .waitingForAgent: .waitingForAgent
                case .running: .running
                case .needsAttention: .needsAttention
                }
            }
            byRunID[activity.runID] = ResearchActivityNotification(
                triptychID: triptychID,
                runID: activity.runID,
                actionID: activity.actionID,
                targetNoteID: activity.targetNoteID,
                targetTitle: activity.targetTitle,
                state: state,
                activity: activity,
                result: nil,
                affectedNotes: [],
                updatedAt: activity.updatedAt
            )
        }
        for (key, result) in readyByTriptych[triptychID] ?? [:]
            where presentedResultKeys.contains(key) {
            byRunID[result.runID] = ResearchActivityNotification(
                triptychID: triptychID,
                runID: result.runID,
                actionID: result.actionID,
                targetNoteID: result.targetNoteID,
                targetTitle: result.targetTitle,
                state: .resultReady,
                activity: nil,
                result: result,
                affectedNotes: result.affectedNotes,
                updatedAt: result.finishedAt
            )
        }
        return byRunID.values.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.runID.uuidString < $1.runID.uuidString
        }
    }

    private func deliverIfNeeded(
        _ destination: ResearchResultReviewDestination,
        key: ResultKey
    ) {
        guard deliveredKeys.insert(key).inserted else { return }
        if applicationIsActive() {
            return
        }

        deliveryTasks[key]?.cancel()
        let deliveryToken = UUID()
        deliveryTokens[key] = deliveryToken
        deliveryTasks[key] = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled,
                  deliveryTokens[key] == deliveryToken,
                  destinationIsCurrent(destination) else {
                return
            }
            let authorization = await systemNotifications.authorizationState()
            guard !Task.isCancelled, authorization == .authorized,
                  deliveryTokens[key] == deliveryToken,
                  destinationIsCurrent(destination) else {
                finishDelivery(key: key, token: deliveryToken)
                return
            }
            let request = ResearchResultSystemNotificationRequest(
                identifier: Self.notificationIdentifier(for: key),
                body: String(
                    localized: "An Agent result is ready to review.",
                    table: "Localizable",
                    bundle: .module
                ),
                destination: destination
            )
            do {
                try await systemNotifications.deliver(request)
            } catch {
                finishDelivery(key: key, token: deliveryToken)
                return
            }
            guard !Task.isCancelled,
                  deliveryTokens[key] == deliveryToken,
                  destinationIsCurrent(destination) else {
                systemNotifications.removeNotification(
                    identifier: request.identifier
                )
                finishDelivery(key: key, token: deliveryToken)
                return
            }
            finishDelivery(key: key, token: deliveryToken)
        }
    }

    private func finishDelivery(key: ResultKey, token: UUID) {
        guard deliveryTokens[key] == token else { return }
        deliveryTasks[key] = nil
        deliveryTokens[key] = nil
    }

    private func openReviewFromSystemNotification(
        _ destination: ResearchResultReviewDestination
    ) {
        guard destinationIsCurrent(destination) else { return }
        if let endpoint = preferredEndpoint(for: destination) {
            endpoint.openReview(destination)
        } else if let route = reviewRoutersByTriptych[destination.triptychID] {
            route(destination)
        } else {
            pendingReviewDestination = destination
        }
    }

    private func routePendingReviewIfPossible() {
        guard let destination = pendingReviewDestination,
              destinationIsCurrent(destination) else { return }
        if let endpoint = preferredEndpoint(for: destination) {
            pendingReviewDestination = nil
            endpoint.openReview(destination)
            return
        }
        guard let route = reviewRoutersByTriptych[destination.triptychID] else {
            return
        }
        pendingReviewDestination = nil
        route(destination)
    }

    private func preferredEndpoint(
        for destination: ResearchResultReviewDestination
    ) -> WindowEndpoint? {
        if let sourceWindowID = sourceWindowByRunID[destination.runID],
           let source = windowEndpoints[sourceWindowID],
           source.triptychID == destination.triptychID {
            return source
        }
        return windowEndpoints.values
            .filter { $0.triptychID == destination.triptychID }
            .max {
                if $0.activationOrdinal != $1.activationOrdinal {
                    return $0.activationOrdinal < $1.activationOrdinal
                }
                return $0.windowID.uuidString > $1.windowID.uuidString
            }
    }

    private func destinationIsCurrent(
        _ destination: ResearchResultReviewDestination
    ) -> Bool {
        let key = ResultKey(
            recordID: destination.recordID,
            fingerprint: destination.finalizedResultFingerprint
        )
        guard let current = readyByTriptych[destination.triptychID]?[key] else {
            return false
        }
        return current.runID == destination.runID
            && current.actionID == destination.actionID
            && current.targetNoteID == destination.targetNoteID
    }

    private static func notificationIdentifier(for key: ResultKey) -> String {
        "scholium.research-result.\(key.recordID.uuidString.lowercased()).\(key.fingerprint.sha256)"
    }
}
