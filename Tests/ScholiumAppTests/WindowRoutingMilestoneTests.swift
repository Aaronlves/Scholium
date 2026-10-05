import Foundation
import Testing

@testable import ScholiumApp

@Suite("Window routing milestones", .serialized)
@MainActor
struct WindowRoutingMilestoneTests {
    @Test("Native attachment hands off launch while document content remains pending")
    func attachmentDoesNotRequireWorkspaceReadiness() async throws {
        var policy = ScholiumLifecyclePolicy()
        policy.routeReadiness = .milliseconds(30)
        let registry = ScholiumWindowLifecycleRegistry(policy: policy)
        let id = UUID()
        registry.register(id: id) {}
        defer { registry.unregister(id: id) }

        registry.markAttached(id: id)
        try await registry.waitUntilAttached(id: id)
        await #expect(throws: ScholiumWindowLifecycleError.timedOut(.routeReadiness)) {
            try await registry.waitUntilReady(id: id)
        }

        // A workspace may load or present Restore Access after launch has
        // handed off. Full-content callers retain their independent contract.
        registry.markReady(id: id)
        try await registry.waitUntilReady(id: id)
    }

    @Test("Workspace opening failure does not invalidate an attached native window")
    func openingFailureRetainsAttachedRecoveryWindow() async throws {
        let registry = ScholiumWindowLifecycleRegistry()
        let id = UUID()
        registry.register(id: id) {}
        defer { registry.unregister(id: id) }
        registry.markAttached(id: id)
        registry.markFailed(id: id, error: ScholiumWindowLifecycleError.failed("Fixture opening failure"))

        try await registry.waitUntilAttached(id: id)
        await #expect(throws: ScholiumWindowLifecycleError.self) {
            try await registry.waitUntilReady(id: id)
        }
    }

    @Test("Closed routes fail attachment and content, and explicit re-registration renews both")
    func unregisterEndsBothMilestones() async throws {
        let registry = ScholiumWindowLifecycleRegistry()
        let id = UUID()
        registry.register(id: id) {}
        registry.markAttached(id: id)
        registry.unregister(id: id)

        await #expect(throws: ScholiumWindowLifecycleError.unregisteredBeforeReady) {
            try await registry.waitUntilAttached(id: id)
        }
        await #expect(throws: ScholiumWindowLifecycleError.unregisteredBeforeReady) {
            try await registry.waitUntilReady(id: id)
        }

        registry.register(id: id) {}
        defer { registry.unregister(id: id) }
        registry.markAttached(id: id)
        registry.markReady(id: id)
        try await registry.waitUntilAttached(id: id)
        try await registry.waitUntilReady(id: id)
    }

    @Test("An attachment timeout retains the exact route for a later retry")
    func lateAttachmentCanBeRetried() async throws {
        var policy = ScholiumLifecyclePolicy()
        policy.routeReadiness = .milliseconds(30)
        let registry = ScholiumWindowLifecycleRegistry(policy: policy)
        let id = UUID()
        registry.register(id: id) {}
        defer { registry.unregister(id: id) }

        await #expect(throws: ScholiumWindowLifecycleError.timedOut(.routeReadiness)) {
            try await registry.waitUntilAttached(id: id)
        }
        registry.markAttached(id: id)
        try await registry.waitUntilAttached(id: id)
    }
}
