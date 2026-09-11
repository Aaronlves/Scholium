import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Research method selection", .serialized)
@MainActor
struct AgentChatMethodsTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Method fixture did not reach expected state")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("Selections persist with drafts, send explicit method input, and refuse missing or disabled methods")
    func methodLifecycle() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/method-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(triptychID: UUID(), root: root) { request in
            try! .init(requestID: request.requestID, result: .object(["status": .string("ok")]))
        }
        try await wait { controller.isLoaded }
        let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        controller.connect(executable: fixture, home: controller.runtimeHome, cli: fixture)
        try await wait { controller.state == .ready && controller.capabilities.hasMethods && !controller.capabilities.isRefreshing }
        let method = try #require(controller.capabilities.methods.first)
        #expect(controller.capabilities.tools.first?.connectionStatus == nil)
        #expect(AgentChatToolLabels.state(controller.capabilities.tools[0]) == String(localized: "Connection Status Unavailable", bundle: .module))
        controller.toggleMethod(method.selection)
        controller.editDraft("Read the passage")
        try await controller.flushPersistence()
        let storage = AgentChatStorage(root: root.appendingPathComponent(controller.triptychID.uuidString))
        #expect(try await storage.load().first?.selectedMethods == [method.selection])
        controller.capabilities.setEnabled(method, enabled: false, threadID: nil)
        #expect(!controller.canSend)
        try await wait { !controller.capabilities.isRefreshing && !controller.capabilities.isChanging }
        #expect(!controller.canSend && controller.selected?.draft == "Read the passage")
        let disabled = try #require(controller.capabilities.methods.first)
        controller.capabilities.setEnabled(disabled, enabled: true, threadID: nil)
        try await wait { controller.canSend }
        controller.send()
        try await wait { !controller.isBusy && controller.selected?.pendingMessageID == nil }
        #expect(controller.selected?.selectedMethods == nil)
        #expect(controller.selected?.messages.first?.methods == [method.selection])
        let turn = try JSONDecoder().decode(
            MCPJSONValue.self,
            from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("last-turn.json")))
        #expect(
            turn.objectValue?["input"]?.arrayValue?.contains(where: {
                $0.objectValue?["type"]?.stringValue == "skill" && $0.objectValue?["path"]?.stringValue == method.selection.path
            }) == true)
        controller.toggleMethod(method.selection)
        controller.editDraft("Preserve this draft")
        try Data().write(to: controller.runtimeHome.appendingPathComponent("method-missing"))
        controller.capabilities.refresh(threadID: controller.selected?.threadID)
        try await wait { !controller.capabilities.isRefreshing }
        #expect(!controller.canSend && controller.selected?.draft == "Preserve this draft")
        #expect(controller.capabilities.tools.first?.connectionStatus == "connected")
        controller.toggleMethod(method.selection)
        #expect(controller.canSend)
        controller.editDraft("hold work")
        controller.send()
        try await wait { controller.state == .working && controller.selected?.pendingMessageID == nil }
        #expect(!controller.capabilities.mayChange())
        await controller.disconnect()
        #expect(!controller.capabilities.hasMethods && controller.capabilities.methods.isEmpty)
    }
}
