import Combine
import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Chat stream mutations", .serialized)
@MainActor
struct AgentChatStreamMutationTests {
    @Test("Visible transcripts avoid unread writes; independent readers and hidden replies retain their meaning")
    func transcriptReadersAndPersistence() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/chat-stream-tests/\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let triptych = UUID()
        let storage = AgentChatStorage(root: root.appendingPathComponent(triptych.uuidString))
        var saves = 0
        let controller = AgentChatController(
            triptychID: triptych, root: root, workspaceDirectory: { root },
            saveHistory: { values in
                saves += 1
                try await storage.save(values)
            },
            toolHandler: { _, _ in try! .init(requestID: UUID(), result: .object([:])) })
        #expect(await controller.waitUntilLoaded())
        let first = try #require(controller.selectedID)
        controller.update(in: first) { $0.threadID = "thread" }
        controller.newConversation()
        let second = try #require(controller.selectedID)
        controller.update(in: second) { $0.threadID = "second-thread" }
        controller.setUnread(first, unread: true)
        let firstReader = UUID()
        let secondReader = UUID()
        let orderDate = controller.conversation(first)?.updatedAt
        controller.displayTranscript(first, readerID: firstReader)
        controller.displayTranscript(first, readerID: secondReader)
        #expect(controller.conversation(first)?.unreadAt == nil)
        #expect(controller.conversation(first)?.updatedAt == orderDate)
        try await controller.flushPersistence()
        saves = 0

        for _ in 0..<200 { await controller.receive(Self.delta("Visible 中文 😀\n")) }
        #expect(controller.conversation(first)?.unreadAt == nil)
        #expect(controller.scheduledPersistenceTask == nil && !controller.persistenceDirty)
        #expect(saves == 0)
        controller.displayTranscript(nil, readerID: firstReader)
        await controller.receive(Self.delta("Still visible\n"))
        #expect(controller.conversation(first)?.unreadAt == nil)
        controller.displayTranscript(second, readerID: secondReader)
        await controller.receive(Self.delta("Now hidden\n"))
        #expect(controller.conversation(first)?.unreadAt != nil)
        controller.displayTranscript(first, readerID: firstReader)
        await controller.receive(Self.delta("Other visible reply", thread: "second-thread"))
        #expect(controller.conversation(first)?.unreadAt == nil && controller.conversation(second)?.unreadAt == nil)
        controller.displayTranscript(nil, readerID: firstReader)
        await controller.receive(Self.delta("Hidden again\n"))
        #expect(controller.conversation(first)?.unreadAt != nil)
        let exactText = String(repeating: "Visible 中文 😀\n", count: 200) + "Still visible\nNow hidden\nHidden again\n"
        #expect(controller.conversation(first)?.messages.last?.text == exactText)

        // Final aggregates also respect visible readers; completion and disconnect
        // retain the durable barrier even though ordinary deltas do not write.
        await controller.receive([
            "method": .string("item/completed"),
            "params": .object([
                "threadId": .string("second-thread"), "turnId": .string("turn"),
                "item": .object([
                    "type": .string("agentMessage"), "id": .string("reply"),
                    "text": .string("Other visible reply — final"), "phase": .string("final_answer"),
                ]),
            ]),
        ])
        #expect(controller.conversation(second)?.unreadAt == nil)
        controller.displayTranscript(nil, readerID: secondReader)
        #expect(!controller.isTranscriptVisible(in: first) && !controller.isTranscriptVisible(in: second))
        await controller.disconnect()
        let restored = try await storage.load()
        #expect(restored.first { $0.id == first }?.messages.last?.text == exactText)
        #expect(restored.first { $0.id == first }?.unreadAt != nil)
        #expect(restored.first { $0.id == second }?.messages.last?.text == "Other visible reply — final")
        #expect(restored.first { $0.id == second }?.unreadAt == nil)
        #expect(saves > 0)
    }

    @Test("Each streamed delta publishes one complete mutation without changing its text")
    func deltaPublications() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/chat-stream-tests/\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AgentChatController(
            triptychID: UUID(), root: root, workspaceDirectory: { root }, saveHistory: { _ in },
            toolHandler: { _, _ in try! .init(requestID: UUID(), result: .object([:])) })
        #expect(await controller.waitUntilLoaded())
        let id = try #require(controller.selectedID)
        controller.update(in: id) { conversation in
            conversation.threadID = "thread"
            conversation.messages = (0..<3_999).map { .init(id: "retained-\($0)", role: .operation, text: "Retained operation") }
            conversation.messages.append(.init(id: "reply", role: .assistant, text: ""))
        }
        try await controller.flushPersistence()
        var publications = 0
        let observation = controller.$conversations.dropFirst().sink { _ in publications += 1 }
        defer { observation.cancel() }
        let deltas = (0..<200).map { "中文 😀 \($0)\n" }
        let start = ContinuousClock.now
        for delta in deltas { await controller.receive(Self.delta(delta)) }
        let duration = start.duration(to: .now)
        let milliseconds = Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
        #expect(controller.selected?.messages.last?.text == deltas.joined())
        #expect(controller.selected?.unreadAt != nil)
        print("CHAT_STREAM_MUTATION deltas=200 messages=4000 publications=\(publications) elapsed_ms=\(milliseconds)")
        #expect(publications == deltas.count)
        await controller.disconnect()
    }

    private static func delta(_ text: String, item: String = "reply", thread: String = "thread") -> [String: MCPJSONValue] {
        [
            "method": .string("item/agentMessage/delta"),
            "params": .object([
                "threadId": .string(thread), "turnId": .string("turn"),
                "itemId": .string(item), "delta": .string(text),
            ]),
        ]
    }
}
