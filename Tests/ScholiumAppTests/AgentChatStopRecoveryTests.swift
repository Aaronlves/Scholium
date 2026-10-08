import Foundation
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Chat Stop recovery", .serialized)
@MainActor
struct AgentChatStopRecoveryTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test("Failed Stop retries deliberately, deduplicates requests and never re-admits retained input")
    func retryPreservesAuthorityAndQueue() async throws {
        try await withController { controller in
            try await startTurn(controller, text: "hold-queue original")
            let owner = try #require(controller.selectedID)
            let turn = try #require(controller.currentTurnID)
            let thread = try #require(controller.selected?.threadID)
            let token = try #require(controller.token)
            controller.editDraft("Retained queued request")
            #expect(controller.queue())
            let queued = controller.queuedMessages
            controller.editDraft("Keep this separate draft")
            try mark("fail-interrupt", in: controller)
            controller.stop()
            let first = try #require(controller.executions[owner]?.interruptTask)
            controller.stop()
            await first.value
            #expect(interruptCount(controller) == 1)
            #expect(controller.state == .stopping && controller.currentTurnID == turn)
            #expect(controller.canRetryStop && controller.executions[owner]?.recovery == .stopUnconfirmed)
            #expect(!controller.owns(token: token) && controller.token == nil)
            #expect(!controller.canSend && !controller.canQueue)
            #expect(controller.executions[owner]?.automaticallyAdvancesQueue == false)
            #expect(controller.selected?.lastRunStatus == .running)
            let statuses = AgentChatConnectionStatus(controller: controller, diagnosticsPresentation: .constant(nil)).statuses
            #expect(statuses.first { $0.id == "execution" }?.actions == [.retryStop])

            // Replayed start notifications must not turn a failure into an automatic retry.
            await controller.receive(turnEvent("turn/started", thread: thread, turn: turn, status: "inProgress"))
            _ = try await controller.runtime?.request("test/echo")
            #expect(interruptCount(controller) == 1 && controller.canRetryStop)

            try unmark("fail-interrupt", in: controller)
            try mark("hold-interrupt-reply", in: controller)
            controller.stop()
            let retry = try #require(controller.executions[owner]?.interruptTask)
            controller.stop()
            try await wait { interruptCount(controller) == 2 }
            #expect(!controller.canRetryStop && controller.error == nil)
            #expect(controller.state == .stopping && !controller.owns(token: token))
            try await releaseInterrupt(in: controller)
            await retry.value
            #expect(interruptCount(controller) == 2 && controller.canRetryStop)

            // Successful RPC acknowledgement still cannot finish the turn or drain the queue.
            try unmark("hold-interrupt-reply", in: controller)
            try mark("acknowledge-interrupt-only", in: controller)
            controller.stop()
            let acknowledged = try #require(controller.executions[owner]?.interruptTask)
            await acknowledged.value
            controller.stop()
            _ = try await controller.runtime?.request("test/echo")
            #expect(interruptCount(controller) == 3)
            #expect(controller.state == .stopping && !controller.canRetryStop && controller.error == nil)
            #expect(controller.queuedMessages == queued && controller.selected?.draft == "Keep this separate draft")
            try mark("release-queued-turn", in: controller)
            _ = try await controller.runtime?.request("account/rateLimits/read")
            try await wait { controller.state == .ready }
            #expect(controller.currentTurnID == nil && controller.error == nil && !controller.canRetryStop)
            #expect(controller.token == nil && controller.queuedMessages == queued)
            #expect(controller.selected?.draft == "Keep this separate draft")
            #expect(controller.selected?.messages.filter { $0.role == .user }.count == 1)
            #expect(controller.executions[owner]?.interruptRequestedTurnID == nil)
        }
    }

    @Test("A late uncertain input diagnostic retains the independent Retry Stop action")
    func lateInputFailureRetainsStopRecovery() async throws {
        try await withController { controller in
            try await startTurn(controller, text: "hold original turn")
            let owner = try #require(controller.selectedID)
            let turn = try #require(controller.currentTurnID)
            controller.editDraft("hold mismatched-steer-ack defer-input-ack")
            controller.send()
            let input = try #require(controller.executions[owner]?.operationTask)
            let lastInput = controller.runtimeHome.appendingPathComponent("last-turn.json")
            try await wait {
                (try? String(contentsOf: lastInput, encoding: .utf8))?.contains("mismatched-steer-ack") == true
            }
            _ = try await controller.runtime?.request("test/echo")
            let pendingMessage = try #require(controller.selected?.pendingMessageID)
            try mark("fail-interrupt", in: controller)
            controller.stop()
            let interrupt = try #require(controller.executions[owner]?.interruptTask)
            await interrupt.value
            #expect(controller.canRetryStop && controller.executions[owner]?.recovery == .stopUnconfirmed)

            try mark("release-input-ack", in: controller)
            _ = try await controller.runtime?.request("account/rateLimits/read")
            await input.value
            let deliveryError = try #require(controller.error)
            #expect(controller.executions[owner]?.recovery == .deliveryUnconfirmed)
            #expect(controller.canRetryStop && controller.state == .stopping && controller.currentTurnID == turn)
            #expect(controller.token == nil && controller.selected?.pendingMessageID == pendingMessage)
            let status = try #require(
                AgentChatConnectionStatus(controller: controller, diagnosticsPresentation: .constant(nil))
                    .statuses.first { $0.id == "execution" })
            #expect(status.title == AgentChatExecutionRecovery.deliveryUnconfirmed.title)
            #expect(status.error == deliveryError && status.actions == [.retryStop])

            try unmark("fail-interrupt", in: controller)
            controller.stop()
            try await wait { controller.state == .ready }
            #expect(interruptCount(controller) == 2 && !controller.canRetryStop)
            #expect(controller.error == deliveryError && controller.executions[owner]?.recovery == .deliveryUnconfirmed)
            #expect(controller.selected?.pendingMessageID == pendingMessage)
            #expect(controller.selected?.messages.filter { $0.role == .user }.count == 2)
        }
    }

    @Test("Stop recovery follows its conversation while another selected conversation keeps running")
    func switchConversationDuringStop() async throws {
        try await withController { controller in
            try await startTurn(controller, text: "hold first conversation")
            let firstID = try #require(controller.selectedID)
            let firstThread = try #require(controller.selected?.threadID)
            try mark("hold-interrupt-reply", in: controller)
            controller.stop()
            let pending = try #require(controller.executions[firstID]?.interruptTask)
            try await wait { interruptCount(controller) == 1 }
            controller.newConversation()
            try await startTurn(controller, text: "hold second conversation")
            let secondID = try #require(controller.selectedID)
            let secondTurn = controller.currentTurnID
            let secondToken = try #require(controller.token)
            try await releaseInterrupt(in: controller)
            await pending.value
            #expect(controller.selectedID == secondID && controller.state == .working)
            #expect(controller.currentTurnID == secondTurn && controller.owns(token: secondToken))
            #expect(controller.error == nil && !controller.canRetryStop)
            #expect(controller.executions[firstID]?.recovery == .stopUnconfirmed)
            controller.select(firstID)
            #expect(controller.canRetryStop)
            try unmark("hold-interrupt-reply", in: controller)
            controller.stop()
            try await wait { controller.state(for: firstID) == .ready }
            let request = try JSONDecoder().decode(
                [String: MCPJSONValue].self,
                from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("last-interrupt.json")))
            #expect(request["threadId"]?.stringValue == firstThread)
            #expect(controller.state(for: secondID) == .working && controller.owns(token: secondToken))
            controller.select(secondID)
            controller.stop()
            try await wait { controller.state == .ready }
        }
    }

    @Test("A rendered Retry Stop target cannot act on another conversation, attempt or turn")
    func staleRenderedRetryTarget() async throws {
        try await withController { controller in
            try await startTurn(controller, text: "hold first target")
            let firstID = try #require(controller.selectedID)
            try mark("fail-interrupt", in: controller)
            controller.stop()
            let failure = try #require(controller.executions[firstID]?.interruptTask)
            await failure.value
            let original = try #require(controller.stopRetryTarget)

            controller.newConversation()
            try await startTurn(controller, text: "hold second target")
            let secondID = try #require(controller.selectedID)
            let secondTurn = controller.currentTurnID
            let secondToken = try #require(controller.token)
            controller.retryStop(original)
            #expect(controller.state == .working && controller.currentTurnID == secondTurn)
            #expect(controller.owns(token: secondToken) && controller.stopRetryTarget == nil)
            _ = try await controller.runtime?.request("test/echo")
            #expect(interruptCount(controller) == 1)

            controller.select(firstID)
            controller.retryStop(original)
            let replacementFailure = try #require(controller.executions[firstID]?.interruptTask)
            controller.retryStop(original)
            await replacementFailure.value
            let current = try #require(controller.stopRetryTarget)
            #expect(current != original && current.turnID == original.turnID)
            #expect(interruptCount(controller) == 2)
            let currentError = controller.error
            controller.retryStop(original)
            #expect(controller.stopRetryTarget == current && controller.error == currentError)
            _ = try await controller.runtime?.request("test/echo")
            #expect(interruptCount(controller) == 2)

            try unmark("fail-interrupt", in: controller)
            controller.retryStop(current)
            controller.retryStop(current)
            try await wait { controller.state == .ready }
            #expect(interruptCount(controller) == 3 && controller.stopRetryTarget == nil)
            try await startTurn(controller, text: "hold replacement turn")
            let replacementTurn = controller.currentTurnID
            let replacementToken = try #require(controller.token)
            controller.retryStop(original)
            controller.retryStop(current)
            #expect(controller.state == .working && controller.currentTurnID == replacementTurn)
            #expect(controller.owns(token: replacementToken))
            _ = try await controller.runtime?.request("test/echo")
            #expect(interruptCount(controller) == 3)
            #expect(controller.state(for: secondID) == .working && controller.owns(token: secondToken))
            controller.stop()
            try await wait { controller.state == .ready }
            controller.select(secondID)
            controller.stop()
            try await wait { controller.state == .ready }
        }
    }

    @Test(
        "Late Stop replies cannot change a replaced connection, thread, turn or attempt",
        arguments: ["connection", "thread", "turn", "attempt", "acknowledgement"])
    func staleInterruptReply(replacement: String) async throws {
        try await withController { controller in
            try await startTurn(controller, text: "hold replacement test")
            let owner = try #require(controller.selectedID)
            let originalConnection = controller.connectionID
            let originalThread = controller.selected?.threadID
            try mark("hold-interrupt-reply", in: controller)
            controller.stop()
            let obsolete = try #require(controller.executions[owner]?.interruptTask)
            try await wait { interruptCount(controller) == 1 }
            switch replacement {
            case "connection": controller.connectionID = UUID()
            case "thread": controller.update { $0.threadID = "replacement-thread" }
            case "turn": controller.executions[owner]?.turnID = "replacement-turn"
            default: controller.executions[owner]?.interruptRequestID = UUID()
            }
            controller.executions[owner]?.error = "Replacement operation diagnostic"
            let requestID = controller.executions[owner]?.interruptRequestID
            let turnID = controller.currentTurnID
            let admission = UUID()
            controller.executions[owner]?.admissionID = admission
            try await releaseInterrupt(in: controller, succeeds: replacement == "acknowledgement")
            await obsolete.value
            #expect(controller.error == "Replacement operation diagnostic")
            #expect(controller.executions[owner]?.recovery == nil && !controller.canRetryStop)
            #expect(controller.executions[owner]?.interruptFailedTurnID == nil)
            #expect(controller.executions[owner]?.interruptRequestID == requestID)
            #expect(controller.currentTurnID == turnID && controller.executions[owner]?.admissionID == admission)
            if replacement != "turn" { #expect(controller.executions[owner]?.interruptTask != nil) }
            controller.connectionID = originalConnection
            controller.update { $0.threadID = originalThread }
        }
    }

    @Test("Transport loss during Stop preserves input and cannot leak recovery into a new connection")
    func disconnectedStop() async throws {
        try await withController { controller in
            try await startTurn(controller, text: "hold lost transport")
            let owner = try #require(controller.selectedID)
            controller.editDraft("Retain across disconnection")
            let oldConnection = controller.connectionID
            try mark("disconnect-on-interrupt", in: controller)
            controller.stop()
            try await wait { controller.connectionState == .disconnected && controller.connectionError != nil }
            #expect(!controller.canRetryStop && controller.executions[owner]?.recovery == nil)
            #expect(controller.executions[owner]?.admissionID == nil && controller.selected?.draft == "Retain across disconnection")
            try unmark("disconnect-on-interrupt", in: controller)
            controller.newConversation()
            try await connect(controller)
            #expect(controller.connectionID != oldConnection)
            try await startTurn(controller, text: "hold newly connected turn")
            #expect(controller.error == nil && !controller.canRetryStop)
            #expect(controller.conversation(owner)?.draft == "Retain across disconnection")
            #expect(controller.conversation(owner)?.messages.filter { $0.role == .user }.count == 1)
            controller.stop()
            try await wait { controller.state == .ready }
            #expect(controller.error == nil)
        }
    }

    @Test("Turn completion clears only its Stop failure, preserving independent later diagnostics")
    func terminalRecoveryOwnership() {
        var execution = AgentChatExecutionState()
        execution.turnID = "stopped-turn"
        execution.report(.stopUnconfirmed, detail: "Stop failed")
        execution.turnID = nil
        #expect(execution.error == nil && execution.recovery == nil)
        execution.turnID = "another-turn"
        execution.report(.stopUnconfirmed, detail: "Stop failed")
        execution.report(.historyRefreshFailed, detail: "Independent failure")
        execution.turnID = nil
        #expect(execution.error == "Independent failure" && execution.recovery == .historyRefreshFailed)
    }

    private func withController(_ operation: @MainActor (AgentChatController) async throws -> Void) async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/stop-recovery-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = fixtureChatController(triptychID: UUID(), root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        do {
            try await connect(controller)
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
        try #require(await controller.waitUntilReady())
        try #require(controller.account != nil && controller.capabilities.workspaceReady)
    }

    private func startTurn(_ controller: AgentChatController, text: String) async throws {
        let owner = try #require(controller.selectedID)
        controller.editDraft(text)
        controller.send()
        try await wait {
            controller.currentTurnID != nil && controller.selected?.pendingMessageID == nil && controller.executions[owner]?.isSending == false
        }
    }

    private func mark(_ name: String, in controller: AgentChatController, value: String = "") throws {
        try Data(value.utf8).write(to: controller.runtimeHome.appendingPathComponent(name))
    }

    private func unmark(_ name: String, in controller: AgentChatController) throws {
        try FileManager.default.removeItem(at: controller.runtimeHome.appendingPathComponent(name))
    }

    private func interruptCount(_ controller: AgentChatController) -> Int {
        let data = try? String(contentsOf: controller.runtimeHome.appendingPathComponent("interrupt-count"), encoding: .utf8)
        return data.flatMap(Int.init) ?? 0
    }

    private func releaseInterrupt(in controller: AgentChatController, succeeds: Bool = false) async throws {
        try mark("release-interrupt-reply", in: controller, value: succeeds ? "success" : "error")
        _ = try await controller.runtime?.request("account/rateLimits/read")
    }

    private func turnEvent(_ method: String, thread: String, turn: String, status: String) -> [String: MCPJSONValue] {
        [
            "method": .string(method),
            "params": .object([
                "threadId": .string(thread),
                "turn": .object([
                    "id": .string(turn), "status": .string(status), "items": .array([]), "itemsView": .string("notLoaded"),
                ]),
            ]),
        ]
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Chat Stop fixture did not reach the expected state")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
