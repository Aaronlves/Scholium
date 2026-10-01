import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Chat input and history recovery", .serialized)
@MainActor
struct AgentChatRecoveryTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test("Failed local history reads and repeated retries preserve the original bytes")
    func unreadableLocalHistory() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/local-recovery-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let triptychID = UUID()
        let historyRoot = root.appendingPathComponent(triptychID.uuidString)
        try FileManager.default.createDirectory(at: historyRoot, withIntermediateDirectories: true)
        let history = historyRoot.appendingPathComponent("conversations.json")
        let original = Data("{ unreadable retained history\n".utf8)
        try original.write(to: history)
        try await withController(root: root, triptychID: triptychID) { controller in
            #expect(!(await controller.waitUntilLoaded()))
            #expect(controller.localHistoryError != nil && controller.connectionError == nil)
            #expect(!controller.isLoadingLocalHistory && controller.conversations.isEmpty)
            controller.newConversation()
            controller.editDraft("Must not initialize over unreadable history")
            try await controller.flushPersistence()
            #expect(try Data(contentsOf: history) == original)
            controller.retryLocalHistory()
            controller.retryLocalHistory() // A second click cannot start another concurrent load.
            #expect(!(await controller.waitUntilLoaded()))
            #expect(controller.localHistoryError != nil && controller.conversations.isEmpty)
            #expect(try Data(contentsOf: history) == original)
        }
    }

    @Test("A foreign Triptych archive is never published; retry can load repaired history without rewriting it")
    func validatedLocalHistoryRetry() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/validated-recovery-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let triptychID = UUID()
        let historyRoot = root.appendingPathComponent(triptychID.uuidString)
        let storage = AgentChatStorage(root: historyRoot)
        let foreign = AgentChatConversation(triptychID: UUID())
        try await storage.save([foreign])
        let history = historyRoot.appendingPathComponent("conversations.json")
        let foreignBytes = try Data(contentsOf: history)
        try await withController(root: root, triptychID: triptychID) { controller in
            #expect(!(await controller.waitUntilLoaded()))
            #expect(controller.conversations.isEmpty && controller.selectedID == nil)
            #expect(try Data(contentsOf: history) == foreignBytes)
            var repaired = AgentChatConversation(triptychID: triptychID)
            repaired.draft = "恢复后的草稿 😀"
            repaired.queuedMessages = [.init(role: .user, text: "Retained queued request")]
            repaired.pendingMessageID = "retained-uncertain-input"
            try await storage.save([repaired]) // Test-owned external repair, never an app fallback.
            let repairedBytes = try Data(contentsOf: history)
            controller.retryLocalHistory()
            #expect(await controller.waitUntilLoaded())
            #expect(controller.localHistoryError == nil && !controller.isLoadingLocalHistory)
            #expect(controller.conversations == [repaired] && controller.selectedID == repaired.id)
            #expect(controller.selected?.pendingMessageID == repaired.pendingMessageID)
            #expect(try Data(contentsOf: history) == repairedBytes)
            controller.retryLocalHistory() // Already loaded state cannot discard the retained session.
            #expect(controller.conversations == [repaired])
        }
    }

    @Test("Idle queue blockers preserve Send Next semantics, retained context and queue order")
    func blockedIdleQueue() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/queue-recovery-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try await withController(root: root, triptychID: UUID()) { controller in
            try await connect(controller)
            controller.editDraft("Keep the unrelated composer draft")
            var blocked = AgentChatMessage(role: .user, text: "First queued request")
            blocked.methods = [.init(name: "missing", title: "Missing Skill", path: "/unavailable/skill/SKILL.md")]
            let later = AgentChatMessage(role: .user, text: "Second queued request")
            controller.update { $0.queuedMessages = [blocked, later] }
            let owner = try #require(controller.selected)
            #expect(!controller.canSendQueuedMessage(blocked.id))
            #expect(controller.queuedMessageBlockReason(blocked.id) == ScholiumL10n.string(
                "A requested Skill is unavailable. Refresh Skills or remove this queued message."))
            let action = AgentChatQueueAction(isWorking: controller.state == .working)
            #expect(action == .sendNext && !action.isEnabled(canSend: false, canSteer: false))
            #expect(!controller.sendQueuedMessage(blocked.id))
            #expect(controller.selected == owner)
            controller.update { $0.queuedMessages[0].methods = nil }
            #expect(controller.canSendQueuedMessage(blocked.id) && controller.queuedMessageBlockReason(blocked.id) == nil)
            #expect(!controller.canSendQueuedMessage(later.id))
            #expect(controller.queuedMessageBlockReason(later.id) == ScholiumL10n.string("Earlier queued messages will be sent first."))
            #expect(controller.selected?.draft == "Keep the unrelated composer draft")
            #expect(controller.queuedMessages.map(\.id) == [blocked.id, later.id])
            controller.executions[owner.id]?.report(.queuedInputBlocked, detail: "Fixture blocked queue head")
            controller.removeQueuedMessage(blocked.id)
            #expect(controller.error == nil && controller.executions[owner.id]?.recovery == nil)
            #expect(controller.queuedMessages == [later] && controller.selected?.draft == owner.draft)
        }
    }

    @Test("Failed runtime history refresh exposes its exact repair without replacing saved messages or draft")
    func runtimeHistoryRepair() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/runtime-history-recovery-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try await withController(root: root, triptychID: UUID()) { controller in
            try await connect(controller)
            controller.editDraft("phased activity")
            controller.send()
            try await wait { !controller.isBusy && controller.selected?.lastRunStatus == .completed }
            controller.editDraft("Keep this unsent research question")
            let owner = try #require(controller.selectedID)
            let messages = controller.selected?.messages
            let marker = controller.runtimeHome.appendingPathComponent("malformed-public-history")
            try Data().write(to: marker)
            controller.retryHistory()
            try await wait { !controller.isRefreshingHistory }
            #expect(controller.executions[owner]?.recovery == .historyRefreshFailed)
            #expect(controller.error != nil && !controller.historyUnavailable && controller.connectionState == .ready)
            #expect(controller.selected?.messages == messages && controller.selected?.draft == "Keep this unsent research question")
            try FileManager.default.removeItem(at: marker)
            controller.retryHistory()
            try await wait { !controller.isRefreshingHistory }
            #expect(controller.error == nil && controller.executions[owner]?.recovery == nil)
            #expect(controller.selected?.messages.filter { $0.role == .user } == messages?.filter { $0.role == .user })
            #expect(controller.selected?.messages.contains { $0.text.contains("Unconfirmed replacement") } == false)
            #expect(controller.selected?.draft == "Keep this unsent research question")
        }
    }

    @Test("A later error cannot inherit an earlier operation's recovery action")
    func recoveryBelongsToItsError() {
        var execution = AgentChatExecutionState()
        execution.report(.historyRefreshFailed, detail: "Fixture history failure")
        #expect(execution.recovery == .historyRefreshFailed)
        execution.error = "Different fixture error"
        #expect(execution.recovery == nil)
        execution.report(.deliveryUnconfirmed, detail: "Fixture delivery failure")
        execution.error = nil
        #expect(execution.recovery == nil)
    }

    private func withController(
        root: URL, triptychID: UUID,
        operation: @MainActor (AgentChatController) async throws -> Void
    ) async throws {
        let controller = fixtureChatController(triptychID: triptychID, root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        do {
            try await operation(controller)
            await controller.disconnect()
        } catch {
            await controller.disconnect()
            throw error
        }
    }

    private func connect(_ controller: AgentChatController) async throws {
        try #require(await controller.waitUntilLoaded())
        let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        controller.connect(executable: fixture, home: controller.runtimeHome, helper: fixture)
        try await wait { controller.state == .ready && controller.account != nil && controller.capabilities.workspaceReady }
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Chat recovery fixture did not reach the expected state")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
