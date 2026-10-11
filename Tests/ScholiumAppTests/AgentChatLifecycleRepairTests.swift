import Foundation
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Chat lifecycle repairs", .serialized) @MainActor
struct AgentChatLifecycleRepairTests {
    @Test("Repeated Sign In joins one pending request without replacing connection setup")
    func loginIsDeduplicated() async throws {
        try await withController(signedOut: true) { controller in
            let runtime = try #require(controller.runtime)
            let generation = controller.connectionID
            var opened: [URL] = []
            controller.openAuthenticationURL = { opened.append($0) }
            controller.editDraft("Keep this unsent research question")
            controller.login()
            let login = try #require(controller.loginTask)
            controller.login()
            controller.login()
            try await wait { self.loginCount(controller) == "1" }
            #expect(controller.isStartingLogin && !controller.canStartLogin)
            #expect(controller.connectionTask != nil)
            let status = AgentChatConnectionStatus(controller: controller, diagnosticsPresentation: .constant(nil)).statuses
            #expect(status.first?.isProgress == true && status.first?.actions.isEmpty == true)
            _ = try await runtime.request("test/completeLogin")
            await login.value
            #expect(opened == [URL(string: "https://auth.openai.com/fixture")!])
            #expect(!controller.isStartingLogin && controller.loginTask == nil && controller.loginID == nil)
            #expect(controller.canStartLogin && controller.connectionID == generation)
            #expect(controller.selected?.draft == "Keep this unsent research question")
        }
    }

    @Test("Disconnect revokes pending login, and its cancellation cannot publish an error into a later connection")
    func disconnectOwnsLoginCancellation() async throws {
        try await withController(signedOut: true) { controller in
            var opened: [URL] = []
            controller.openAuthenticationURL = { opened.append($0) }
            controller.editDraft("Retained through disconnect")
            controller.login()
            let oldLogin = try #require(controller.loginTask)
            try await wait { self.loginCount(controller) == "1" }
            await controller.disconnect()
            await oldLogin.value
            #expect(controller.connectionState == .disconnected && controller.connectionError == nil)
            #expect(!controller.isStartingLogin && controller.loginTask == nil && controller.loginID == nil)
            #expect(opened.isEmpty && controller.selected?.draft == "Retained through disconnect")
            controller.connect(executable: executable, home: controller.runtimeHome, helper: executable)
            #expect(await controller.waitUntilReady())
            controller.login()
            let nextLogin = try #require(controller.loginTask)
            try await wait { self.loginCount(controller) == "2" }
            let runtime = try #require(controller.runtime)
            _ = try await runtime.request("test/completeLogin", params: ["error": .string("Fixture sign-in declined")])
            await nextLogin.value
            #expect(controller.connectionError == "Fixture sign-in declined" && controller.canStartLogin)
            #expect(opened.isEmpty && controller.selected?.draft == "Retained through disconnect")
            controller.login()
            let retry = try #require(controller.loginTask)
            try await wait { self.loginCount(controller) == "3" }
            _ = try await runtime.request("test/completeLogin")
            await retry.value
            #expect(controller.connectionError == nil && opened.count == 1)
        }
    }

    @Test("An obsolete connection's login result cannot open a URL or publish failure", arguments: [false, true])
    func obsoleteLoginResults(fails: Bool) async throws {
        try await withController(signedOut: true) { controller in
            let runtime = try #require(controller.runtime)
            let originalGeneration = try #require(controller.connectionID)
            var opened: [URL] = []
            controller.openAuthenticationURL = { opened.append($0) }
            controller.login()
            let oldLogin = try #require(controller.loginTask)
            try await wait { self.loginCount(controller) == "1" }
            // Keep the deterministic transport alive to deliver either late
            // outcome after its owning connection generation has been revoked.
            controller.connectionID = UUID()
            controller.connectionError = "Current connection explanation"
            _ = try await runtime.request(
                "test/completeLogin", params: fails ? ["error": .string("Obsolete login failed")] : [:])
            await oldLogin.value
            #expect(opened.isEmpty && controller.connectionError == "Current connection explanation")
            controller.cancelLogin()
            controller.connectionID = originalGeneration
        }
    }

    @Test("Unavailable saved reasoning remains repairable when the model loses efforts", arguments: [[], ["low"]])
    func unavailableReasoningCanBeCleared(efforts: [String]) async throws {
        try await withController { controller in
            controller.setModel("fixture-model")
            controller.setEffort("high")
            controller.editDraft("Preserve this question exactly")
            try await controller.flushPersistence()
            let selected = controller.selectedID
            let model: MCPJSONValue = .object([
                "id": .string("fixture-picker"), "model": .string("fixture-model"),
                "displayName": .string("Fixture Model"), "isDefault": .bool(true),
                "defaultReasoningEffort": .string("low"), "inputModalities": .array([.string("text")]),
                "supportedReasoningEfforts": .array(efforts.map { .object(["reasoningEffort": .string($0)]) }),
            ])
            try JSONEncoder().encode(MCPJSONValue.object(["data": .array([model])]))
                .write(to: controller.runtimeHome.appendingPathComponent("runtime-model-catalog.json"))
            controller.refreshRuntime()
            await controller.runtimeRefreshTask?.value
            #expect(controller.selected?.preferences.effort == "high" && !controller.canSend)
            let preferences = try #require(controller.selected?.preferences)
            let menu = AgentChatConfigurationMenu(
                models: controller.models, preferences: preferences, selectedModel: controller.selectedModel,
                isEnabled: true, canSelectModel: true,
                selectModel: controller.setModel, selectEffort: controller.setEffort, selectWebSearch: controller.setWebSearch)
            #expect(menu.showsReasoningMenu && menu.unavailableEffort == "high")
            menu.selectEffort(nil)  // The retained menu's explicit Runtime Default action.
            #expect(controller.selected?.preferences.effort == nil && controller.canSend)
            #expect(controller.selectedID == selected && controller.selected?.draft == "Preserve this question exactly")
            #expect(controller.selected?.messages.isEmpty == true)
            try await controller.flushPersistence()
            #expect(controller.historySaveError == nil)
        }
    }

    @Test("Unsupported requests remain rejected and visible on the actual owning conversation")
    func unsupportedInteractionIsScoped() async throws {
        try await withController { controller in
            let owner = try #require(controller.selectedID)
            controller.editDraft("hold unsupported-interaction")
            controller.send()
            try await wait { controller.state == .working && controller.selected?.pendingMessageID == nil }
            let thread = try #require(controller.selected?.threadID)
            let turn = try #require(controller.currentTurnID)
            let messages = controller.selected?.messages
            controller.newConversation()
            let visible = try #require(controller.selectedID)
            controller.editDraft("Unrelated unsent draft")
            await controller.receive([
                "id": .integer(881), "method": .string("fixture/unsupportedInteraction"),
                "params": .object(["threadId": .string(thread), "turnId": .string(turn)]),
            ])
            try await wait { self.rejectedID(controller) == .integer(881) }
            let explanation = ScholiumL10n.string("Codex requested an interaction this client does not support.")
            #expect(controller.executions[owner]?.error == explanation && controller.connectionError == nil)
            #expect(controller.selectedID == visible && controller.error == nil)
            #expect(controller.selected?.draft == "Unrelated unsent draft")
            #expect(controller.conversation(owner)?.messages == messages && controller.approvals.isEmpty)
            controller.select(owner)
            let status = AgentChatConnectionStatus(controller: controller, diagnosticsPresentation: .constant(nil)).statuses
            #expect(status.contains { $0.id == "execution" && $0.error == explanation })
            controller.executions[owner]?.error = nil
            controller.select(visible)
            await controller.receive([
                "id": .integer(882), "method": .string("fixture/unsupportedInteraction"),
                "params": .object(["threadId": .string(thread), "turnId": .string("obsolete-turn")]),
            ])
            try await wait { self.rejectedID(controller) == .integer(882) }
            #expect(controller.executions[owner]?.error == nil && controller.executions[visible]?.error == nil)
            #expect(controller.connectionError == explanation && controller.selectedID == visible)
            let fallback = AgentChatConnectionStatus(controller: controller, diagnosticsPresentation: .constant(nil)).statuses
            #expect(fallback.contains { $0.id == "connection" && $0.error == explanation })
            #expect(controller.selected?.draft == "Unrelated unsent draft" && controller.approvals.isEmpty)
        }
    }

    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private var executable: URL { repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py") }
    private func loginCount(_ controller: AgentChatController) -> String? {
        try? String(contentsOf: controller.runtimeHome.appendingPathComponent("login-start-count"), encoding: .utf8)
    }
    private func rejectedID(_ controller: AgentChatController) -> MCPJSONValue? {
        guard let data = try? Data(contentsOf: controller.runtimeHome.appendingPathComponent("approval-response.json")),
            let reply = try? JSONDecoder().decode(MCPJSONValue.self, from: data),
            reply.objectValue?["error"] != nil
        else { return nil }
        return reply.objectValue?["id"]
    }
    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !predicate() {
            try #require(ContinuousClock.now < deadline, "Chat lifecycle fixture did not reach its expected state")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    private func withController(signedOut: Bool = false, _ body: (AgentChatController) async throws -> Void) async throws {
        let root = repository.appendingPathComponent(".build/chat-lifecycle-repair-tests/\(UUID())")
        let suite = "scholium.qa.chatLifecycleRepair.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let controller = fixtureChatController(triptychID: UUID(), root: root, methodDefaults: defaults) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        controller.openAuthenticationURL = { _ in Issue.record("A fixture must never open live authentication") }
        do {
            #expect(await controller.waitUntilLoaded())
            try FileManager.default.createDirectory(at: controller.runtimeHome, withIntermediateDirectories: true)
            if signedOut { try Data().write(to: controller.runtimeHome.appendingPathComponent("runtime-signed-out")) }
            controller.connect(executable: executable, home: controller.runtimeHome, helper: executable)
            #expect(await controller.waitUntilReady())
            try await body(controller)
            await controller.disconnect()
        } catch {
            await controller.disconnect()
            throw error
        }
    }
}
