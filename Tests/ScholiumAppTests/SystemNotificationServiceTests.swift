import Foundation
import ScholiumContracts
import Testing
import UserNotifications
@testable import ScholiumApp

@Suite("System notification delivery")
@MainActor
struct SystemNotificationServiceTests {
    @Test("Foreground and unconfirmed changes neither prompt nor deliver")
    func foregroundAndUnconfirmed() async throws {
        let transport = FakeNotificationTransport()
        let foreground = SystemNotificationService(transport: transport, delay: .zero, isActive: { true })
        foreground.receive(change())
        let background = SystemNotificationService(transport: transport, delay: .zero, isActive: { false })
        background.receive(change(state: .outcomeUncertain))
        try await Task.sleep(for: .milliseconds(20))
        #expect(transport.statusReads == 0)
        #expect(transport.authorizationRequests == 0)
        #expect(transport.delivered.isEmpty)
    }

    @Test("First eligible event requests once; a same-Note burst retains the latest exact receipt")
    func firstEventAndCoalescing() async throws {
        let transport = FakeNotificationTransport()
        let service = SystemNotificationService(transport: transport, delay: .milliseconds(10), isActive: { false })
        let first = change()
        let latest = change(noteID: first.noteID, triptychID: first.triptychID)
        service.receive(first)
        service.receive(latest)
        try await eventually { transport.delivered.count == 1 }
        #expect(transport.authorizationRequests == 1)
        #expect(transport.delivered.first == AgentChangeNotificationRoute(latest))
        service.receive(change())
        try await eventually { transport.delivered.count == 2 }
        #expect(transport.authorizationRequests == 1)
    }

    @Test("Denied permission remains quiet and does not prompt again")
    func denied() async throws {
        let transport = FakeNotificationTransport(status: .denied)
        let service = SystemNotificationService(transport: transport, delay: .zero, isActive: { false })
        service.receive(change())
        try await eventually { transport.statusReads == 1 }
        service.receive(change())
        try await eventually { transport.statusReads == 2 }
        #expect(transport.authorizationRequests == 0)
        #expect(transport.delivered.isEmpty)
    }

    @Test("Concurrent first events share one system authorization request")
    func concurrentAuthorization() async throws {
        let transport = FakeNotificationTransport()
        transport.authorizationDelay = .milliseconds(30)
        let service = SystemNotificationService(transport: transport, delay: .zero, isActive: { false })
        service.receive(change())
        try await eventually { transport.authorizationRequests == 1 }
        service.receive(change())
        try await eventually { transport.delivered.count == 2 }
        #expect(transport.authorizationRequests == 1)
    }

    @Test("A first refusal is respected by later events")
    func firstRefusal() async throws {
        let transport = FakeNotificationTransport()
        transport.grantAuthorization = false
        let service = SystemNotificationService(transport: transport, delay: .zero, isActive: { false })
        service.receive(change())
        try await eventually { transport.status == .denied }
        service.receive(change())
        try await eventually { transport.statusReads == 2 }
        #expect(transport.authorizationRequests == 1)
        #expect(transport.delivered.isEmpty)
    }

    @Test("Activation while the system prompt is pending prevents later delivery")
    func activationDuringAuthorization() async throws {
        let transport = FakeNotificationTransport()
        transport.authorizationDelay = .milliseconds(30)
        var active = false
        let service = SystemNotificationService(transport: transport, delay: .zero, isActive: { active })
        service.receive(change())
        try await eventually { transport.authorizationRequests == 1 }
        active = true
        service.applicationBecameActive()
        try await eventually { transport.status == .authorized }
        #expect(transport.delivered.isEmpty)
    }

    @Test("Returning to the App cancels pending background delivery")
    func cancellation() async throws {
        let transport = FakeNotificationTransport(status: .authorized)
        let service = SystemNotificationService(transport: transport, delay: .milliseconds(10), isActive: { false })
        service.receive(change())
        service.applicationBecameActive()
        try await Task.sleep(for: .milliseconds(30))
        #expect(transport.delivered.isEmpty)
        #expect(transport.statusReads == 0)
    }

    @Test("Click routes reuse a matching window and otherwise wait for a scene")
    func exactRoutingAndPrivacy() throws {
        let service = SystemNotificationService()
        let receipt = change()
        let route = AgentChangeNotificationRoute(receipt)
        let data = try JSONEncoder().encode(route)
        let payload = String(decoding: data, as: UTF8.self)
        #expect(!payload.contains("private-note.md"))
        #expect(!payload.contains("relativePath"))
        #expect(route.matches(receipt))
        #expect(!route.matches(change(noteID: receipt.noteID, triptychID: receipt.triptychID)))
        var opened: [AgentChangeNotificationRoute] = []
        let windowID = UUID()
        service.registerWindow(id: windowID) { opened.append($0); return true }
        service.open(route)
        #expect(opened == [route])
        #expect(service.pendingRoute == nil)
        service.unregisterWindow(id: windowID)
        service.open(route)
        #expect(service.takePendingRoute() == route)
        #expect(service.takePendingRoute() == nil)
    }

    @Test("Cold-window click handoff is consumed once and never enters window restoration")
    func coldWindowHandoff() throws {
        let service = SystemNotificationService()
        let route = AgentChangeNotificationRoute(change())
        let window = service.prepareWindow(for: route)
        let restored = try JSONDecoder().decode(TriptychWindowRoute.self, from: JSONEncoder().encode(window))
        #expect(restored.triptychID == route.triptychID)
        #expect(service.takeOpeningRoute(windowID: UUID()) == nil)
        #expect(service.takeOpeningRoute(windowID: window.windowID) == route)
        #expect(service.takeOpeningRoute(windowID: restored.windowID) == nil)
        #expect(service.notificationWindowID == nil)
    }

    @Test("Operation issues retain distinct failures until dismissed; duplicates keep identity")
    func localIssues() throws {
        let shell = WindowShellState()
        shell.reportOperationIssue("Refresh failed", kind: .warning, offersRefresh: true)
        let first = try #require(shell.operationIssues.first)
        shell.reportOperationIssue("Refresh failed", kind: .warning, offersRefresh: true)
        shell.reportOperationIssue("Save failed", kind: .error)
        #expect(shell.operationIssues.count == 2)
        #expect(shell.operationIssues.first?.id == first.id)
        shell.dismissOperationIssue(id: first.id)
        #expect(shell.operationIssues.map(\.message) == ["Save failed"])
    }

    private func change(noteID: UUID = UUID(), triptychID: UUID = UUID(),
                        state: AgentChangeRecoveryState = .confirmed) -> AgentChange {
        AgentChange(id: UUID(), triptychID: triptychID, operation: .update,
                    noteID: noteID, role: .topicKnowledge,
                    originalRelativePath: "private-note.md", finalRelativePath: "private-note.md",
                    beforeFingerprint: nil, afterFingerprint: nil, state: state,
                    createdAt: .now, confirmedAt: .now, undoneAt: nil)
    }

    private func eventually(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !predicate(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(predicate())
    }
}

@MainActor
private final class FakeNotificationTransport: SystemNotificationTransport {
    var status: UNAuthorizationStatus
    var grantAuthorization = true
    var authorizationDelay: Duration = .zero
    var authorizationRequests = 0
    var statusReads = 0
    var delivered: [AgentChangeNotificationRoute] = []
    init(status: UNAuthorizationStatus = .notDetermined) { self.status = status }
    func authorizationStatus() async -> UNAuthorizationStatus {
        statusReads += 1
        return status
    }
    func requestAuthorization() async throws -> Bool {
        authorizationRequests += 1
        try await Task.sleep(for: authorizationDelay)
        status = grantAuthorization ? .authorized : .denied
        return grantAuthorization
    }
    func deliver(_ route: AgentChangeNotificationRoute) async throws { delivered.append(route) }
}
