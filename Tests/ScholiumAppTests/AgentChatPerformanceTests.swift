import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Chat performance", .serialized)
@MainActor
struct AgentChatPerformanceTests {
    @Test("Continuous draft edits coalesce durable writes")
    func continuousDraftEditsCoalesceDurableWrites() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/scholium-chat-performance-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let triptychID = UUID()
        let storage = AgentChatStorage(root: root.appendingPathComponent(triptychID.uuidString))
        var conversation = AgentChatConversation(triptychID: triptychID)
        conversation.title = "Synthetic performance conversation"
        conversation.messages = (0..<80).flatMap { index in
            [
                .init(
                    role: .user,
                    text: "Synthetic request \(index)",
                    phase: nil),
                .init(
                    role: .assistant,
                    text: String(repeating: "Synthetic retained reply. ", count: 32),
                    phase: .finalAnswer),
            ]
        }
        try await storage.save([conversation])

        let recorder = ChatPerformanceSaveRecorder()
        let controller = AgentChatController(
            triptychID: triptychID,
            root: root,
            workspaceDirectory: { root.appendingPathComponent("workspace", isDirectory: true) },
            saveHistory: { values in
                await recorder.record(values)
                try await storage.save(values)
            },
            toolHandler: { _ in
                try! .init(requestID: UUID(), result: .object([:]))
            })
        #expect(await controller.waitUntilLoaded())
        try await controller.flushPersistence()
        await recorder.reset()

        let editCount = 80
        let mutationStart = ContinuousClock.now
        for index in 0..<editCount {
            controller.editDraft("Synthetic draft edit \(index)")
        }
        let mutationDuration = mutationStart.duration(to: .now)
        let mutationMilliseconds = Double(mutationDuration.components.attoseconds) / 1e15
            + Double(mutationDuration.components.seconds) * 1_000

        let flushStart = ContinuousClock.now
        try await controller.flushPersistence()
        let flushDuration = flushStart.duration(to: .now)
        let saves = await recorder.count
        let flushMilliseconds = Double(flushDuration.components.attoseconds) / 1e15
            + Double(flushDuration.components.seconds) * 1_000

        #expect(saves == 1)
        print(
            "CHAT_PERF draft_edits=\(editCount) durable_saves=\(saves) "
                + "mutation_ms=\(mutationMilliseconds) flush_ms=\(flushMilliseconds)"
        )
    }

    @Test("Timeline grouping stays linear for long process runs")
    func timelineGroupingStaysLinearForLongProcessRuns() {
        var messages: [AgentChatMessage] = []
        messages.reserveCapacity(4_000)
        for index in 0..<4_000 {
            var message = AgentChatMessage(
                id: "operation-\(index)", role: .operation, text: "Synthetic operation")
            message.turnID = "synthetic-turn"
            messages.append(message)
        }

        let start = ContinuousClock.now
        let projection = AgentChatTimelineProjection(messages)
        let grouped = projection.items
        let duration = start.duration(to: .now)
        let milliseconds = Double(duration.components.attoseconds) / 1e15
            + Double(duration.components.seconds) * 1_000

        #expect(grouped.count == 1)
        #expect(grouped[0].messages.count == messages.count)
        print("CHAT_PERF timeline_messages=\(messages.count) grouped_items=\(grouped.count) elapsed_ms=\(milliseconds)")
    }

    @Test("Streaming deltas use a bounded tail lookup")
    func streamingDeltasUseBoundedTailLookup() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/scholium-chat-stream-performance-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let triptychID = UUID()
        let storage = AgentChatStorage(root: root.appendingPathComponent(triptychID.uuidString))
        var conversation = AgentChatConversation(triptychID: triptychID)
        conversation.title = "Synthetic streaming conversation"
        conversation.threadID = "synthetic-thread"
        conversation.messages = (0..<3_999).map { index in
            var message = AgentChatMessage(id: "retained-\(index)", role: .operation, text: "Retained operation")
            message.turnID = "retained-turn-\(index)"
            return message
        }
        var streaming = AgentChatMessage(id: "streaming", role: .assistant, text: "")
        streaming.turnID = "streaming-turn"
        conversation.messages.append(streaming)
        try await storage.save([conversation])

        let controller = AgentChatController(
            triptychID: triptychID,
            root: root,
            workspaceDirectory: { root.appendingPathComponent("workspace", isDirectory: true) },
            saveHistory: { _ in },
            toolHandler: { _ in try! .init(requestID: UUID(), result: .object([:])) })
        #expect(await controller.waitUntilLoaded())

        let start = ContinuousClock.now
        for index in 0..<200 {
            await controller.receive([
                "method": .string("item/agentMessage/delta"),
                "params": .object([
                    "threadId": .string("synthetic-thread"),
                    "turnId": .string("streaming-turn"),
                    "itemId": .string("streaming"),
                    "delta": .string("x\(index)")
                ])
            ])
        }
        let duration = start.duration(to: .now)
        let milliseconds = Double(duration.components.attoseconds) / 1e15
            + Double(duration.components.seconds) * 1_000

        #expect(controller.selected?.messages.last?.text.count == 690)
        print("CHAT_PERF streaming_deltas=200 retained_messages=4000 elapsed_ms=\(milliseconds)")
    }
}

private actor ChatPerformanceSaveRecorder {
    private(set) var count = 0

    func record(_ values: [AgentChatConversation]) {
        count += 1
        _ = values.count
    }

    func reset() { count = 0 }
}
