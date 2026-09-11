import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Native tool configuration", .serialized)
@MainActor
struct AgentChatToolConfigurationTests {
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Tool configuration fixture did not reach expected state")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    @Test("Add, edit, stale rejection, reload and removal preserve exact connection ownership")
    func lifecycle() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-chat-tests/config-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(triptychID: UUID(), root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try await wait { controller.isLoaded }
        let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        controller.connect(executable: fixture, home: controller.runtimeHome, cli: fixture)
        try await wait { controller.capabilities.canConfigureTools }
        let caps = controller.capabilities
        var add = try #require(caps.editTool())
        add.connection = .init(
            name: "research", address: "https://example.invalid/mcp", enabled: false,
            bearerTokenVariable: "RESEARCH_FIXTURE_TOKEN")
        #expect(await caps.saveTool(add))
        try await wait { caps.canConfigureTools }
        #expect(caps.toolConnections.first?.name == "research" && caps.tools.first(where: { $0.name == "research" })?.connectionStatus == "disabled")
        var edit = try #require(caps.editTool(named: "research"))
        #expect(edit.connection.bearerTokenVariable == "RESEARCH_FIXTURE_TOKEN")
        let stale = edit
        edit.connection.enabled = true
        edit.connection.bearerTokenVariable = ""
        #expect(await caps.saveTool(edit))
        try await wait { caps.canConfigureTools }
        #expect(!((await caps.saveTool(stale, removing: true))))
        #expect(caps.toolConfigurationError != nil && caps.toolConnections.count == 1)
        let fresh = try #require(await caps.reloadToolEdit(stale))
        #expect(fresh.connection.enabled)
        #expect(fresh.connection.bearerTokenVariable.isEmpty)
        controller.editDraft("hold while tools are configured")
        controller.send()
        try await wait { controller.state == .working && controller.selected?.pendingMessageID == nil }
        #expect(!(await caps.saveTool(fresh, removing: true)))
        controller.stop()
        try await wait { controller.state == .ready && !controller.isBusy }
        #expect(await caps.saveTool(fresh, removing: true))
        try await wait { caps.canConfigureTools }
        #expect(caps.toolConnections.isEmpty)
        await controller.disconnect()
        #expect(!(await caps.saveTool(fresh)))
    }
}
