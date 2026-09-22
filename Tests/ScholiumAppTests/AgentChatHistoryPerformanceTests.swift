import Combine
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Chat history reconciliation", .serialized)
@MainActor
struct AgentChatHistoryPerformanceTests {
    @Test("History insertion preserves local messages, pending delivery and streamed command output")
    func historyInsertionPreservesLocalState() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/chat-history-tests/\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(
            triptychID: UUID(), root: root, workspaceDirectory: { root }, saveHistory: { _ in },
            toolHandler: { _ in try! .init(requestID: UUID(), result: .object([:])) })
        #expect(await controller.waitUntilLoaded())
        let id = try #require(controller.selectedID)
        controller.update(in: id) { conversation in
            conversation.threadID = "thread"
            conversation.pendingMessageID = "local-user"
            conversation.messages = [
                .init(id: "local-user", role: .user, text: "Preserve my exact input"),
                .init(
                    id: "runtime:command", role: .operation, text: "",
                    activity: .init(
                        kind: .command, status: .running, source: .runtime, detail: "first\nlast\n")),
                .init(id: "later-local", role: .user, text: "Keep this local message"),
            ]
        }
        let items: [MCPJSONValue] = [
            .object(["id": .string("runtime-user"), "type": .string("userMessage"), "clientId": .string("local-user"), "content": .array([])]),
            .object(["id": .string("first-reply"), "type": .string("agentMessage"), "text": .string("Recovered reply")]),
            .object([
                "id": .string("command"), "type": .string("commandExecution"), "command": .string("synthetic"), "status": .string("completed"),
                "aggregatedOutput": .string("last\n"),
            ]),
            .object(["id": .string("last-reply"), "type": .string("agentMessage"), "text": .string("Recovered final reply")]),
        ]
        let history: MCPJSONValue = .object([
            "thread": .object([
                "id": .string("thread"),
                "turns": .array([
                    .object([
                        "id": .string("turn"), "status": .string("completed"), "items": .array(items),
                    ])
                ]),
            ])
        ])
        try controller.hydrate(history, in: id)
        let result = try #require(controller.selected)
        #expect(result.messages.map(\.id) == ["local-user", "first-reply", "runtime:command", "last-reply", "later-local"])
        #expect(result.messages[0].text == "Preserve my exact input")
        #expect(result.messages[2].activity?.detail == "first\nlast\n")
        #expect(result.messages[2].activity?.status == .completed)
        #expect(result.messages.prefix(4).allSatisfy { $0.turnID == "turn" })
        #expect(result.messages.last?.turnID == nil)
        #expect(result.pendingMessageID == nil)
        try controller.hydrate(history, in: id)
        #expect(controller.selected == result)
        try await controller.flushPersistence()
    }

    @Test("Retained history refresh publishes one complete reconciliation", arguments: [1_000, 4_000])
    func retainedHistoryRefresh(messageCount: Int) async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/chat-history-tests/\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(
            triptychID: UUID(), root: root, workspaceDirectory: { root },
            saveHistory: { _ in },
            toolHandler: { _ in try! .init(requestID: UUID(), result: .object([:])) })
        #expect(await controller.waitUntilLoaded())
        let id = try #require(controller.selectedID)
        controller.update(in: id) { conversation in
            conversation.threadID = "synthetic-thread"
            conversation.draft = "Preserve the researcher's draft."
            conversation.messages = (0..<messageCount).map { index in
                .init(id: "reply-\(index)", role: .assistant, text: "Retained reply \(index)", phase: .finalAnswer)
            }
        }
        let turns: [MCPJSONValue] = (0..<messageCount).map { index in
            .object([
                "id": .string("turn-\(index)"), "status": .string("completed"),
                "items": .array([
                    .object([
                        "id": .string("reply-\(index)"), "type": .string("agentMessage"),
                        "text": .string("Refreshed reply \(index)"), "phase": .string("final_answer"),
                    ])
                ]),
            ])
        }
        let history: MCPJSONValue = .object([
            "thread": .object(["id": .string("synthetic-thread"), "turns": .array(turns)])
        ])
        var publications = 0
        let observation = controller.$conversations.dropFirst().sink { _ in publications += 1 }
        defer { observation.cancel() }
        let start = ContinuousClock.now
        try controller.hydrate(history, in: id)
        let duration = start.duration(to: .now)
        let milliseconds =
            Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1e15
        let result = try #require(controller.selected)
        #expect(result.messages.count == messageCount)
        #expect(
            result.messages.enumerated().allSatisfy { index, message in
                message.id == "reply-\(index)" && message.text == "Refreshed reply \(index)"
                    && message.turnID == "turn-\(index)"
            })
        #expect(result.turns.count == messageCount)
        #expect(result.draft == "Preserve the researcher's draft.")
        print("CHAT_PERF hydration_messages=\(messageCount) publications=\(publications) elapsed_ms=\(milliseconds)")
        #expect(publications == 1)
        try await controller.flushPersistence()
    }
}
