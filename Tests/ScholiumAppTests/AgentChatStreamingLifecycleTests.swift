import Combine
import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Chat streaming lifecycle", .serialized) @MainActor
struct AgentChatStreamingLifecycleTests {
    private func fixture(_ action: (AgentChatController, UUID) async throws -> Void) async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/chat-streaming-lifecycle/\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = fixtureChatControllerWithAdmission(
            triptychID: UUID(), root: root, workspaceDirectory: { root }, saveHistory: { _ in },
            toolHandler: { _, _ in try! .init(requestID: UUID(), result: .object([:])) })
        #expect(await controller.waitUntilLoaded())
        let id = try #require(controller.selectedID)
        controller.update(in: id) { $0.threadID = "thread" }
        try await action(controller, id)
        await controller.disconnect()
    }

    @Test("Deltas activate unknown retained prose; item completion cannot be reopened by late started or delta events")
    func itemBoundaries() async throws {
        try await fixture { controller, id in
            controller.update(in: id) { $0.messages = [.init(id: "reply", role: .assistant, text: "Known ")] }
            await controller.receive(delta("中文 **"))
            #expect(controller.selected?.messages.last?.isStreaming == true)
            await controller.receive(item(completed: true, text: "Known 中文 **final**"))
            let settled = controller.selected?.messages.last
            #expect(settled?.isStreaming == false && settled?.text == "Known 中文 **final**")
            await controller.receive(delta("late"))
            await controller.receive(item(completed: false, text: "obsolete"))
            #expect(controller.selected?.messages.last == settled)
            await controller.receive(delta("Next public commentary", item: "next"))
            #expect(controller.selected?.messages.last?.isStreaming == true)
            #expect(controller.selected?.messages.last?.id == "next")
        }
    }

    @Test(
        "Stop keeps received prose streaming until a terminal turn; terminal turns reject late deltas",
        arguments: ["completed", "interrupted", "failed"])
    func turnBoundaries(status: String) async throws {
        try await fixture { controller, id in
            controller.executions[id]?.state = .working
            controller.executions[id]?.turnID = "turn"
            await controller.receive(item(completed: false, text: "**Partial 中文"))
            controller.stop()
            #expect(controller.executions[id]?.state == .stopping)
            #expect(controller.selected?.messages.last?.isStreaming == true)
            await controller.receive([
                "method": .string("turn/completed"),
                "params": .object([
                    "threadId": .string("thread"),
                    "turn": .object(["id": .string("turn"), "status": .string(status), "items": .array([])]),
                ]),
            ])
            #expect(controller.selected?.messages.last?.isStreaming == false)
            #expect(controller.selected?.messages.last?.text == "**Partial 中文")
            let count = controller.selected?.messages.count
            await controller.receive(delta("late", item: "unseen-late-item"))
            #expect(controller.selected?.messages.count == count)
        }
    }

    @Test("Unversioned history cannot overwrite live observations received after its request", arguments: [false, true])
    func staleHistoryAfterLiveText(completed: Bool) async throws {
        try await fixture { controller, id in
            await controller.receive(item(completed: false, text: "Prefix 中文"))
            let read = try controller.beginHistoryRead(in: id)
            if completed {
                await controller.receive(item(completed: true, text: "Complete **revised** answer 😀"))
            } else {
                await controller.receive(delta(" and newly received words 😀"))
            }
            let latest = controller.selected?.messages.last
            try controller.hydrate(snapshot(text: "Prefix 中文"), in: id, after: read)
            #expect(controller.selected?.messages.last == latest)
            // A response without a request boundary also cannot replace known
            // live or completed prose with an unversioned partial snapshot.
            try controller.hydrate(snapshot(text: "Prefix"), in: id)
            #expect(controller.selected?.messages.last == latest)
            if completed {
                let freshRead = try controller.beginHistoryRead(in: id)
                try controller.hydrate(snapshot(text: "Obsolete partial"), in: id, after: freshRead)
                #expect(controller.selected?.messages.last == latest)
            }
        }
    }

    @Test("A fresh history read can authoritatively replace prose with a shorter non-prefix completed revision")
    func completeHistoryRevision() async throws {
        try await fixture { controller, id in
            await controller.receive(item(completed: false, text: "A long provisional answer with **unfinished markup"))
            let read = try controller.beginHistoryRead(in: id)
            try controller.hydrate(snapshot(text: "Revised. 😀", status: "completed"), in: id, after: read)
            #expect(controller.selected?.messages.last?.text == "Revised. 😀")
            #expect(controller.selected?.messages.last?.isStreaming == false)
            #expect(controller.selected?.turns["turn"]?.status == .completed)
            let secondRead = try controller.beginHistoryRead(in: id)
            try controller.hydrate(snapshot(text: "终稿", status: "completed"), in: id, after: secondRead)
            #expect(controller.selected?.messages.last?.text == "终稿")
            let unicodeRead = try controller.beginHistoryRead(in: id)
            try controller.hydrate(snapshot(text: "e\u{301}", status: "completed"), in: id, after: unicodeRead)
            let composedRead = try controller.beginHistoryRead(in: id)
            try controller.hydrate(snapshot(text: "é", status: "completed"), in: id, after: composedRead)
            #expect(controller.selected?.messages.last?.text.utf8.elementsEqual("é".utf8) == true)
        }
    }

    @Test("Delayed active history preserves terminal turn status, message phase and exact received text")
    func staleHistoryAfterTerminalTurn() async throws {
        try await fixture { controller, id in
            controller.executions[id]?.state = .working
            controller.executions[id]?.turnID = "turn"
            await controller.receive(item(completed: false, text: "**Partial 😀\r\n"))
            let read = try controller.beginHistoryRead(in: id)
            await controller.receive([
                "method": .string("turn/completed"),
                "params": .object([
                    "threadId": .string("thread"),
                    "turn": .object(["id": .string("turn"), "status": .string("interrupted"), "items": .array([])]),
                ]),
            ])
            try controller.hydrate(snapshot(text: "**Partial"), in: id, after: read)
            #expect(controller.selected?.messages.last?.text == "**Partial 😀\r\n")
            #expect(controller.selected?.messages.last?.isStreaming == false)
            #expect(controller.selected?.turns["turn"]?.status == .interrupted)
            #expect(controller.selected?.lastRunStatus == .interrupted)
            let unseen = "**Historical e\u{301} 😀\r\n"
            try controller.hydrate(snapshot(text: unseen, itemID: "unseen-history-item"), in: id, after: read)
            let restored = try #require(controller.selected?.messages.first { $0.id == "unseen-history-item" })
            #expect(restored.text.utf8.elementsEqual(unseen.utf8))
            #expect(!restored.isStreaming && restored.turnID == "turn")
            #expect(controller.selected?.turns["turn"]?.status == .interrupted)
            #expect(controller.selected?.lastRunStatus == .interrupted)
            await controller.receive(delta("late", item: "unseen-history-item"))
            #expect(controller.selected?.messages.first { $0.id == "unseen-history-item" } == restored)
        }
    }

    @Test("History and child snapshots preserve active prose; disconnect settles local presentation without changing text")
    func historyAndDisconnect() async throws {
        let history: MCPJSONValue = .object([
            "thread": .object([
                "id": .string("thread"), "parentThreadId": .string("parent"), "historyMode": .string("legacy"),
                "status": .object(["type": .string("active"), "activeFlags": .array([])]),
                "turns": .array([
                    .object([
                        "id": .string("turn"), "status": .string("inProgress"),
                        "items": .array([
                            .object(["id": .string("reply"), "type": .string("agentMessage"), "text": .string("**Partial 中文")]),
                            .object([
                                "id": .string("commentary"), "type": .string("agentMessage"), "text": .string("Done"),
                                "status": .string("completed"), "phase": .string("commentary"),
                            ]),
                        ]),
                    ])
                ]),
            ])
        ])
        try await fixture { controller, id in
            try controller.hydrate(history, in: id)
            #expect(controller.selected?.messages.first?.isStreaming == true)
            #expect(controller.selected?.messages.last?.isStreaming == false)
            controller.invalidateExecutions()
            #expect(controller.selected?.messages.allSatisfy { !$0.isStreaming } == true)
            #expect(controller.selected?.messages.first?.text == "**Partial 中文")
        }
        let connected = CurrentValueSubject<Bool, Never>(true)
        let child = AgentChatChildController(
            childID: "thread", parentID: "parent", parentTitle: "Synthetic parent",
            connection: connected.eraseToAnyPublisher(), request: { _, _ in history })
        child.refresh()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while child.isWorking {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(child.messages.first?.value.isStreaming == true)
        #expect(child.messages.last?.value.isStreaming == false)
        connected.send(false)
        #expect(child.messages.allSatisfy { !$0.value.isStreaming })
        #expect(child.messages.first?.value.text == "**Partial 中文")
        child.cancel()
    }

    private func item(completed: Bool, text: String) -> [String: MCPJSONValue] {
        [
            "method": .string(completed ? "item/completed" : "item/started"),
            "params": .object([
                "threadId": .string("thread"), "turnId": .string("turn"),
                "item": .object(["id": .string("reply"), "type": .string("agentMessage"), "text": .string(text)]),
            ]),
        ]
    }

    private func delta(_ text: String, item: String = "reply") -> [String: MCPJSONValue] {
        [
            "method": .string("item/agentMessage/delta"),
            "params": .object([
                "threadId": .string("thread"), "turnId": .string("turn"), "itemId": .string(item), "delta": .string(text),
            ]),
        ]
    }

    private func snapshot(text: String, status: String = "inProgress", itemID: String = "reply") -> MCPJSONValue {
        .object([
            "thread": .object([
                "id": .string("thread"),
                "turns": .array([
                    .object([
                        "id": .string("turn"), "status": .string(status),
                        "items": .array([
                            .object([
                                "id": .string(itemID), "type": .string("agentMessage"), "text": .string(text),
                            ])
                        ]),
                    ])
                ]),
            ])
        ])
    }
}
