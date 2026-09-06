import AppKit
import Combine
import ScholiumContracts
import SwiftUI
import UserNotifications

/// Only opaque identity and revision data cross into macOS Notification Center.
struct AgentChangeNotificationRoute: Codable, Hashable, Sendable {
    let triptychID: UUID
    let changeID: UUID
    let noteID: UUID
    let operation: AgentChangeOperation
    let afterFingerprint: DocumentFingerprint?

    init(_ change: AgentChange) {
        triptychID = change.triptychID
        changeID = change.id
        noteID = change.noteID
        operation = change.operation
        afterFingerprint = change.afterFingerprint
    }

    var identifier: String { "scholium.agent-change.\(triptychID).\(noteID)" }

    func matches(_ change: AgentChange) -> Bool {
        triptychID == change.triptychID && changeID == change.id
            && noteID == change.noteID && operation == change.operation
            && afterFingerprint == change.afterFingerprint
    }
}

@MainActor
protocol SystemNotificationTransport: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func deliver(_ route: AgentChangeNotificationRoute) async throws
}

@MainActor
final class SystemNotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = SystemNotificationService()
    @Published private(set) var notificationWindowID: UUID?
    @Published private(set) var pendingRoute: AgentChangeNotificationRoute?
    private var transport: (any SystemNotificationTransport)?
    private let isActive: @MainActor () -> Bool
    private let delay: Duration
    private var deliveries: [String: (id: UUID, task: Task<Void, Never>)] = [:]
    private var openingRoutes: [UUID: AgentChangeNotificationRoute] = [:]
    private var windowRoutes: [UUID: @MainActor (AgentChangeNotificationRoute) -> Bool] = [:]
    private var authorizationRequest: Task<Bool, Never>?
    private var requestedAuthorization = false

    init(transport: (any SystemNotificationTransport)? = nil,
         delay: Duration = .seconds(2),
         isActive: @escaping @MainActor () -> Bool = { NSApp?.isActive ?? true }) {
        self.transport = transport
        self.delay = delay
        self.isActive = isActive
        super.init()
    }

    /// Called at App launch, never by tests, previews, or runtime construction.
    func start() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        transport = MacSystemNotificationTransport(center: center)
    }

    /// Exactly one call after a successful MCP mutation, never from history reloads.
    func receive(_ change: AgentChange) {
        guard change.state == .confirmed, transport != nil, !isActive() else { return }
        let route = AgentChangeNotificationRoute(change)
        deliveries[route.identifier]?.task.cancel()
        let deliveryID = UUID()
        let task = Task { [weak self, delay] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, !Task.isCancelled else { return }
            await self.deliver(route)
            if self.deliveries[route.identifier]?.id == deliveryID {
                self.deliveries[route.identifier] = nil
            }
        }
        deliveries[route.identifier] = (deliveryID, task)
    }

    func applicationBecameActive() {
        for delivery in deliveries.values { delivery.task.cancel() }
        deliveries.removeAll()
    }

    private func deliver(_ route: AgentChangeNotificationRoute) async {
        guard let transport, !isActive(), !Task.isCancelled else { return }
        let status = await transport.authorizationStatus()
        let authorized: Bool
        switch status {
        case .authorized, .provisional: authorized = true
        case .notDetermined:
            if let authorizationRequest {
                authorized = await authorizationRequest.value
            } else if !requestedAuthorization {
                requestedAuthorization = true
                let request = Task { (try? await transport.requestAuthorization()) ?? false }
                authorizationRequest = request
                authorized = await request.value
                authorizationRequest = nil
            } else {
                authorized = false
            }
        default: authorized = false
        }
        guard authorized, !isActive(), !Task.isCancelled else { return }
        // Notification failure cannot change the committed mutation's result.
        try? await transport.deliver(route)
    }

    func registerWindow(id: UUID, open: @escaping @MainActor (AgentChangeNotificationRoute) -> Bool) {
        windowRoutes[id] = open
    }

    func unregisterWindow(id: UUID) {
        windowRoutes[id] = nil
        openingRoutes[id] = nil
        if notificationWindowID == id { notificationWindowID = nil }
    }

    func open(_ route: AgentChangeNotificationRoute) {
        for handler in windowRoutes.values {
            if handler(route) { return }
        }
        pendingRoute = route
    }

    /// The one-shot click is memory-only; restored windows never replay it.
    func prepareWindow(for route: AgentChangeNotificationRoute) -> TriptychWindowRoute {
        let window = TriptychWindowRoute(triptychID: route.triptychID)
        openingRoutes[window.windowID] = route
        notificationWindowID = window.windowID
        return window
    }

    func takeOpeningRoute(windowID: UUID) -> AgentChangeNotificationRoute? {
        if notificationWindowID == windowID { notificationWindowID = nil }
        return openingRoutes.removeValue(forKey: windowID)
    }

    func takePendingRoute() -> AgentChangeNotificationRoute? {
        defer { pendingRoute = nil }
        return pendingRoute
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions { [] }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let data = response.notification.request.content.userInfo["route"] as? Data,
              let route = try? JSONDecoder().decode(AgentChangeNotificationRoute.self, from: data),
              response.notification.request.identifier == route.identifier else { return }
        await MainActor.run { self.open(route) }
    }
}

@MainActor
private final class MacSystemNotificationTransport: SystemNotificationTransport {
    let center: UNUserNotificationCenter
    init(center: UNUserNotificationCenter) { self.center = center }
    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }
    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert])
    }
    func deliver(_ route: AgentChangeNotificationRoute) async throws {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Agent Changes", table: "Localizable", bundle: .module)
        content.body = String(localized: "An Agent changed a Note. Open Scholium to inspect the change.", table: "Localizable", bundle: .module)
        content.userInfo = ["route": try JSONEncoder().encode(route)]
        content.threadIdentifier = route.triptychID.uuidString
        try await center.add(UNNotificationRequest(identifier: route.identifier, content: content, trigger: nil))
    }
}

/// Every scene can receive a cold-launch click; taking the route is atomic.
struct SystemNotificationRouting: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var notifications = SystemNotificationService.shared
    func body(content: Content) -> some View {
        content.onChange(of: notifications.pendingRoute, initial: true) { _, route in
            guard route != nil,
                  let destination = notifications.takePendingRoute() else { return }
            let window = notifications.prepareWindow(for: destination)
            openWindow(id: "scholium-main", value: window)
        }
    }
}
