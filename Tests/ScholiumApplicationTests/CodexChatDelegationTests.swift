import ScholiumApplication
import ScholiumContracts
import Testing

@Suite("Public delegation reports")
struct CodexChatDelegationTests {
    @Test("Coordination completion preserves independently reported target states and exact results")
    func projection() throws {
        var item: [String: MCPJSONValue] = [
            "type": .string("collabAgentToolCall"),
            "senderThreadId": .string("parent"), "tool": .string("wait"), "status": .string("completed"),
            "receiverThreadIds": .array([.string("still-running"), .string("missing-state")]),
            "prompt": .string("Compare only the supplied passages."),
            "agentsStates": .object([
                "still-running": .object(["status": .string("running")]),
                "reported-result": .object(["status": .string("completed"), "message": .string("Exact report\r\nwith *literal* text")]),
            ]),
        ]
        let report = try CodexChatDelegation.parse(item, senderThreadID: "parent")
        #expect(report.targets.map(\.id) == ["still-running", "missing-state", "reported-result"])
        #expect(report.targets.map(\.state) == [.running, nil, .completed])
        #expect(report.targets.last?.message == "Exact report\r\nwith *literal* text")
        // Forked history retains the original sender instead of attributing old work to the branch.
        #expect(try CodexChatDelegation.parse(item, senderThreadID: "branch").senderThreadID == "parent")
        item["receiverThreadIds"] = .array([.string("same"), .string("same")])
        #expect(throws: CodexConnectionError.self) { try CodexChatDelegation.parse(item, senderThreadID: "parent") }
        item["receiverThreadIds"] = .array([])
        item["tool"] = .string("listAgents")
        item["agentsStates"] = .object(["parent": .object(["status": .string("running")])])
        #expect(try CodexChatDelegation.parse(item, senderThreadID: "parent").targets.first?.id == "parent")
        item["agentsStates"] = .object(["target": .object(["status": .string("unrecognized")])])
        #expect(throws: CodexConnectionError.self) { try CodexChatDelegation.parse(item, senderThreadID: "parent") }
    }

    @Test("Lifecycle reports retain runtime path without inferring an unreported run state")
    func lifecycle() throws {
        var item: [String: MCPJSONValue] = [
            "type": .string("subAgentActivity"),
            "kind": .string("interacted"), "agentThreadId": .string("child"), "agentPath": .string("/root/source-check"),
        ]
        let report = try CodexChatDelegation.parse(item, senderThreadID: "parent")
        #expect(report.targets.first?.path == "/root/source-check" && report.targets.first?.state == nil)
        item["kind"] = .string("completed")
        #expect(try CodexChatDelegation.parse(item, senderThreadID: "parent").targets.first?.state == .completed)
        item["agentThreadId"] = .string("parent")
        #expect(throws: CodexConnectionError.self) { try CodexChatDelegation.parse(item, senderThreadID: "parent") }
    }
}
