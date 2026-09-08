import AppKit
import Combine
import ScholiumContracts
import SwiftUI
import UserNotifications

@MainActor
protocol SystemNotificationTransport: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func deliver(_ route: SystemNotificationRoute) async throws
}

@MainActor
final class SystemNotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = SystemNotificationService()
    @Published private(set) var notificationWindowID: UUID?
    @Published private(set) var pendingRoute: SystemNotificationRoute?
    private var transport: (any SystemNotificationTransport)?
    private let isActive: @MainActor () -> Bool
    private let delay: Duration
    private var deliveries: [String: (id: UUID, task: Task<Void, Never>)] = [:]
    private var openingRoutes: [UUID: SystemNotificationRoute] = [:]
    private var windowRoutes: [UUID: @MainActor (SystemNotificationRoute) -> Bool] = [:]
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
        guard change.state == .confirmed else { return }
        schedule(.agentChange(AgentChangeNotificationRoute(change)), isCurrent: { true })
    }

    func receive(_ route: AgentChatNotificationRoute, isCurrent: @escaping @MainActor () -> Bool) {
        schedule(.chat(route), isCurrent: isCurrent)
    }

    private func schedule(_ route: SystemNotificationRoute, isCurrent: @escaping @MainActor () -> Bool) {
        guard transport != nil, !isActive(), isCurrent() else { return }
        deliveries[route.identifier]?.task.cancel()
        let deliveryID = UUID()
        let task = Task { [weak self, delay] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, !Task.isCancelled else { return }
            await self.deliver(route, isCurrent: isCurrent)
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

    private func deliver(_ route: SystemNotificationRoute, isCurrent: @escaping @MainActor () -> Bool) async {
        guard let transport, !isActive(), !Task.isCancelled, isCurrent() else { return }
        let status = await transport.authorizationStatus()
        guard !isActive(), !Task.isCancelled, isCurrent() else { return }
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
        guard authorized, !isActive(), !Task.isCancelled, isCurrent() else { return }
        // Notification failure cannot change the committed mutation's result.
        try? await transport.deliver(route)
    }

    func registerWindow(id: UUID, open: @escaping @MainActor (SystemNotificationRoute) -> Bool) {
        windowRoutes[id] = open
    }

    func unregisterWindow(id: UUID) {
        windowRoutes[id] = nil
        openingRoutes[id] = nil
        if notificationWindowID == id { notificationWindowID = nil }
    }

    func open(_ route: SystemNotificationRoute) {
        for handler in windowRoutes.values {
            if handler(route) { return }
        }
        pendingRoute = route
    }

    /// The one-shot click is memory-only; restored windows never replay it.
    func prepareWindow(for route: SystemNotificationRoute) -> TriptychWindowRoute {
        let window = TriptychWindowRoute(triptychID: route.triptychID)
        openingRoutes[window.windowID] = route
        notificationWindowID = window.windowID
        return window
    }

    func takeOpeningRoute(windowID: UUID) -> SystemNotificationRoute? {
        if notificationWindowID == windowID { notificationWindowID = nil }
        return openingRoutes.removeValue(forKey: windowID)
    }

    func takePendingRoute() -> SystemNotificationRoute? {
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
              let route = try? JSONDecoder().decode(SystemNotificationRoute.self, from: data),
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
    func deliver(_ route: SystemNotificationRoute) async throws {
        let content = UNMutableNotificationContent()
        content.title = route.title
        content.body = route.body
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
