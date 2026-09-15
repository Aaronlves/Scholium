import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Conversation Agent roster") @MainActor
struct AgentChatAgentRosterTests {
    @Test("Completed Agents remain counted once in first-appearance order")
    func deduplicatedHistory() {
        let messages = [
            report("spawn", .spawnAgent, targets: [.init(id: "a", state: .running)]),
            report("start", .started, targets: [.init(id: "b", path: "/root/review", state: nil)]),
            report("finish", .completed, targets: [.init(id: "a", path: "/root/build", state: .completed)]),
            report("wait", .wait, targets: [.init(id: "a", state: .completed), .init(id: "b", state: .shutdown)]),
        ]
        let roster = AgentChatAgentRoster(messages: messages, threadID: "parent")
        #expect(roster.entries.map(\.id) == ["a", "b"])
        #expect(roster.entries.map(\.name) == ["/root/build", "/root/review"])
        #expect(roster.entries.map(\.state) == [.completed, .shutdown])
        #expect(roster.entries.map(\.messageID) == ["spawn", "start"])
    }

    @Test("Messages and general runtime listings do not establish roster membership")
    func unrelatedTargets() {
        let observationOperations: [AgentChatDelegation.Operation] = [
            .sendInput, .resumeAgent, .wait, .closeAgent, .sendMessage,
            .followupTask, .interruptAgent, .listAgents,
        ]
        let messages =
            observationOperations.enumerated().map { index, operation in
                report("report-\(index)", operation, targets: [.init(id: "unrelated", state: .running)])
            } + [
                report(
                    "child", .spawnAgent,
                    targets: [
                        .init(id: "parent", state: .running), .init(id: "", state: .running),
                        .init(id: "child", state: nil),
                    ])
            ]
        let roster = AgentChatAgentRoster(messages: messages, threadID: "parent")
        #expect(roster.entries.map(\.id) == ["child"])
        #expect(roster.entries.first?.state == nil)
    }

    @Test("Explicit sub-Agent activity qualifies even when its creation report is unavailable")
    func retainedActivity() {
        let operations: [AgentChatDelegation.Operation] = [.started, .interacted, .interrupted, .completed]
        let messages = operations.enumerated().map { index, operation in
            report("report-\(index)", operation, targets: [.init(id: "child-\(index)", state: nil)])
        }
        let roster = AgentChatAgentRoster(messages: messages, threadID: nil)
        #expect(roster.entries.map(\.id) == ["child-0", "child-1", "child-2", "child-3"])
        #expect(roster.entries.allSatisfy { $0.state == nil && $0.stateMessageID == nil })
    }

    @Test("Missing state cannot erase the latest explicit observation or infer completion from the tool")
    func stateProvenance() throws {
        let messages = [
            report("prior-observation", .wait, targets: [.init(id: "child", state: .pendingInit)]),
            report("start", .started, targets: [.init(id: "child", path: "/root/task", state: nil)]),
            report("latest-state", .wait, targets: [.init(id: "child", state: .interrupted)]),
            report("later-message", .sendMessage, targets: [.init(id: "child", path: "", state: nil)]),
        ]
        let entry = try #require(AgentChatAgentRoster(messages: messages, threadID: "parent").entries.first)
        #expect(entry.state == .interrupted)
        #expect(entry.name == "/root/task")
        #expect(entry.messageID == "start")
        #expect(entry.stateMessageID == "latest-state")
        #expect(entry.stateSenderThreadID == "parent")
        let earlier = try #require(AgentChatAgentRoster(messages: Array(messages.prefix(2)), threadID: "parent").entries.first)
        #expect(earlier.state == .pendingInit)
        #expect(earlier.stateMessageID == "prior-observation")
    }

    @Test("Inherited child opening keeps the originating report rather than adopting the branch scope")
    func branchProvenance() throws {
        let messages = [
            report(
                "origin-spawn", .spawnAgent, sender: "origin",
                targets: [
                    .init(id: "child", state: .running), .init(id: "origin", state: .running),
                ]),
            report(
                "branch-observation", .interacted, sender: "branch",
                targets: [
                    .init(id: "child", path: "/root/child", state: .completed),
                    .init(id: "branch", state: .running),
                ]),
        ]
        let roster = AgentChatAgentRoster(messages: messages, threadID: "branch")
        #expect(roster.entries.count == 1)
        let entry = try #require(roster.entries.first)
        #expect(entry.id == "child")
        #expect(entry.messageID == "origin-spawn" && entry.senderThreadID == "origin")
        #expect(entry.stateMessageID == "branch-observation" && entry.stateSenderThreadID == "branch")
        #expect(messages.first { $0.id == entry.messageID }?.activity?.delegation?.senderThreadID == "origin")
    }

    private func report(
        _ id: String, _ operation: AgentChatDelegation.Operation,
        sender: String = "parent", targets: [AgentChatDelegation.Target]
    ) -> AgentChatMessage {
        var activity = AgentChatActivity(kind: .delegation, status: .completed, source: .runtime)
        activity.delegation = .init(operation: operation, senderThreadID: sender, prompt: nil, targets: targets)
        return .init(id: id, role: .operation, text: "", activity: activity)
    }
}
