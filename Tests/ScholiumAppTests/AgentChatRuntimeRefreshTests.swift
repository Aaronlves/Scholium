import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Chat runtime refresh", .serialized)
@MainActor
struct AgentChatRuntimeRefreshTests {
    @Test("Explicit refresh renews sign-in, discovers recovered models and preserves unavailable saved choices")
    func recoveredSubscriptionModels() async throws {
        try await withController { controller in
            controller.setModel("fixture-model")
            controller.setEffort("high")
            controller.editDraft("Unsent research question")
            let connection = controller.connectionID
            let selected = controller.selectedID
            let catalog = controller.runtimeHome.appendingPathComponent("recovered-runtime-model-catalog.json")
            try writeCatalog(["fixture-model", "recovered-model"], to: catalog)

            controller.refreshRuntime()
            #expect(controller.isRefreshingRuntime && !controller.canRefreshRuntime)
            await controller.runtimeRefreshTask?.value
            #expect(!controller.isRefreshingRuntime && controller.runtimeRefreshError == nil)
            #expect(controller.runtimeRefreshedAt != nil && controller.canRefreshRuntime)
            #expect(controller.models.map(\.model) == ["fixture-model", "recovered-model"])
            #expect(controller.selectedID == selected && controller.connectionID == connection)
            #expect(controller.selected?.draft == "Unsent research question")
            #expect(controller.selected?.preferences.model == "fixture-model")
            #expect(controller.selected?.preferences.effort == "high")
            let params = try JSONDecoder().decode(
                MCPJSONValue.self, from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("last-account-read.json")))
            #expect(params.objectValue?["refreshToken"] == .bool(true))

            controller.setModel("recovered-model")
            try writeCatalog(["fixture-model"], to: catalog)
            controller.refreshRuntime()
            await controller.runtimeRefreshTask?.value
            #expect(controller.selected?.preferences.model == "recovered-model")
            #expect(controller.selectedModel == nil && !controller.selectionIsAvailable && !controller.canSend)
            #expect(controller.selected?.draft == "Unsent research question" && controller.selected?.messages.isEmpty == true)
            #expect(try launches(controller) == "1")
        }
    }

    @Test("A failed refresh keeps the previous catalog and remains retryable without replay")
    func failureRetainsObservations() async throws {
        try await withController { controller in
            controller.editDraft("Retained draft")
            let models = controller.models
            let defaults = controller.runtimeDefaults
            let connection = controller.connectionID
            let failure = controller.runtimeHome.appendingPathComponent("fail-runtime-model-list")
            try Data().write(to: failure)
            controller.refreshRuntime()
            await controller.runtimeRefreshTask?.value
            #expect(controller.runtimeRefreshError != nil && controller.runtimeRefreshedAt == nil)
            #expect(controller.models == models && controller.runtimeDefaults == defaults)
            #expect(controller.connectionID == connection && controller.connectionState == .ready)
            #expect(controller.selected?.draft == "Retained draft" && controller.selected?.messages.isEmpty == true)
            #expect(controller.canRefreshRuntime)
            try FileManager.default.removeItem(at: failure)
            controller.refreshRuntime()
            await controller.runtimeRefreshTask?.value
            #expect(controller.runtimeRefreshError == nil && controller.runtimeRefreshedAt != nil)
            #expect(try launches(controller) == "1")
        }
    }

    @Test("Refreshing a busy runtime preserves its exact turn, admission and newer draft")
    func activeTurnSurvives() async throws {
        try await withController { controller in
            controller.editDraft("hold activity")
            controller.send()
            try await wait { controller.state == .working && controller.selected?.pendingMessageID == nil }
            controller.editDraft("Newer unsent draft")
            let turn = controller.currentTurnID
            let admission = controller.token
            let messages = controller.selected?.messages
            let lastTurn = try Data(contentsOf: controller.runtimeHome.appendingPathComponent("last-turn.json"))
            controller.refreshRuntime()
            await controller.runtimeRefreshTask?.value
            #expect(controller.runtimeRefreshError == nil && controller.state == .working)
            #expect(controller.currentTurnID == turn && controller.token == admission)
            #expect(controller.selected?.messages == messages && controller.selected?.draft == "Newer unsent draft")
            #expect(try Data(contentsOf: controller.runtimeHome.appendingPathComponent("last-turn.json")) == lastTurn)
            #expect(try launches(controller) == "1")
        }
    }

    @Test("Account changes refresh model observations without forcing another token renewal")
    func accountNotificationUpdatesCatalog() async throws {
        try await withController { controller in
            controller.editDraft("Preserved during account change")
            try writeCatalog(["fixture-model", "account-model"], to: controller.runtimeHome.appendingPathComponent("runtime-model-catalog.json"))
            await controller.receive(["method": .string("account/updated")])
            await controller.runtimeRefreshTask?.value
            #expect(controller.models.map(\.model) == ["fixture-model", "account-model"])
            let params = try JSONDecoder().decode(
                MCPJSONValue.self, from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("last-account-read.json")))
            #expect(params.objectValue?["refreshToken"] == .bool(false))
            try Data().write(to: controller.runtimeHome.appendingPathComponent("runtime-signed-out"))
            await controller.receive(["method": .string("account/updated")])
            await controller.runtimeRefreshTask?.value
            #expect(controller.account == nil && controller.quotas.isEmpty && !controller.canSend)
            #expect(controller.selected?.draft == "Preserved during account change" && controller.selected?.messages.isEmpty == true)
        }
    }

    @Test("Disconnect cancels an in-flight refresh and a later connection owns its own catalog")
    func disconnectInvalidatesRefresh() async throws {
        try await withController { controller in
            controller.editDraft("Retained while disconnected")
            let hold = controller.runtimeHome.appendingPathComponent("hold-runtime-model-list")
            try Data().write(to: hold)
            controller.refreshRuntime()
            try await wait { FileManager.default.fileExists(atPath: controller.runtimeHome.appendingPathComponent("pending-runtime-model-list").path) }
            let refreshTask = controller.runtimeRefreshTask
            await controller.disconnectByUser()
            await refreshTask?.value
            #expect(controller.connectionState == .disconnected && !controller.isRefreshingRuntime)
            #expect(controller.runtimeRefreshTask == nil && controller.runtimeRefreshError == nil)
            #expect(controller.models.isEmpty && controller.runtimeRefreshedAt == nil)
            try FileManager.default.removeItem(at: hold)
            controller.connect(executable: executable, home: controller.runtimeHome, helper: executable)
            #expect(await controller.waitUntilReady())
            #expect(controller.models.map(\.model) == ["fixture-model"])
            #expect(controller.selected?.draft == "Retained while disconnected")
            #expect(controller.runtimeRefreshedAt == nil)
        }
    }

    @Test("An account change during model discovery invalidates the snapshot without another token renewal")
    func accountChangeDuringRefresh() async throws {
        try await withController { controller in
            controller.editDraft("Preserved during sign-out")
            let catalog = controller.runtimeHome.appendingPathComponent("runtime-model-catalog.json")
            let hold = controller.runtimeHome.appendingPathComponent("hold-runtime-model-list")
            try Data().write(to: hold)
            controller.refreshRuntime()
            try await wait { FileManager.default.fileExists(atPath: controller.runtimeHome.appendingPathComponent("pending-runtime-model-list").path) }
            try Data().write(to: controller.runtimeHome.appendingPathComponent("runtime-signed-out"))
            try writeCatalog(["signed-out-catalog"], to: catalog)
            await controller.receive(["method": .string("account/updated")])
            #expect(controller.isRefreshingRuntime && controller.runtimeRefreshedAt == nil)
            try FileManager.default.removeItem(at: hold)
            await controller.runtimeRefreshTask?.value
            #expect(controller.account == nil && controller.quotas.isEmpty && !controller.canSend)
            #expect(controller.models.map(\.model) == ["signed-out-catalog"])
            #expect(controller.runtimeRefreshedAt != nil && controller.runtimeRefreshError == nil)
            let reads = try JSONDecoder().decode(
                [MCPJSONValue].self, from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("runtime-account-reads.json")))
            #expect(reads.compactMap { $0.objectValue?["refreshToken"]?.boolValue } == [true, false])
            #expect(controller.selected?.draft == "Preserved during sign-out" && controller.selected?.messages.isEmpty == true)
            #expect(try launches(controller) == "1")
        }
    }

    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private var executable: URL { repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py") }

    private func withController(_ body: (AgentChatController) async throws -> Void) async throws {
        let root = repository.appendingPathComponent(".build/runtime-refresh-tests/\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = fixtureChatController(triptychID: UUID(), root: root) { request in
            try! .init(requestID: request.requestID, result: .object(["status": .string("ok")]))
        }
        do {
            #expect(await controller.waitUntilLoaded())
            controller.connect(executable: executable, home: controller.runtimeHome, helper: executable)
            #expect(await controller.waitUntilReady())
            try await body(controller)
            await controller.disconnect()
        } catch {
            await controller.disconnect()
            throw error
        }
    }

    private func writeCatalog(_ names: [String], to url: URL) throws {
        let entries: [MCPJSONValue] = names.enumerated().map { index, name in
            .object([
                "id": .string(name + "-picker"), "model": .string(name), "displayName": .string(name),
                "isDefault": .bool(index == 0), "hidden": .bool(false), "defaultReasoningEffort": .string("medium"),
                "inputModalities": .array([.string("text"), .string("image")]),
                "supportedReasoningEfforts": .array(
                    ["low", "medium", "high"].map {
                        .object(["reasoningEffort": .string($0), "description": .string($0)])
                    }),
            ])
        }
        try JSONEncoder().encode(MCPJSONValue.object(["data": .array(entries), "nextCursor": .null])).write(to: url)
    }

    private func launches(_ controller: AgentChatController) throws -> String {
        try String(contentsOf: controller.runtimeHome.appendingPathComponent("runtime-launches"), encoding: .utf8)
    }

    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !predicate() {
            if ContinuousClock.now >= deadline { throw RefreshTestError.timeout }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    private enum RefreshTestError: Error { case timeout }
}
