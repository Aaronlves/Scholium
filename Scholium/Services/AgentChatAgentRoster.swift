import ScholiumContracts

/// Retained public observations of Agents that appeared in this conversation.
/// This projection neither establishes live status nor grants child control.
struct AgentChatAgentRoster: Equatable {
    struct Entry: Equatable, Identifiable {
        struct ObservationID: Hashable {
            let targetID: String
            let messageID: String
            let senderThreadID: String
        }

        let id: String
        var name: String
        var state: AgentChatDelegation.State?
        /// Keep the first qualifying report's scope when opening an inherited Agent.
        let messageID: String
        let senderThreadID: String
        var stateMessageID: String?
        var stateSenderThreadID: String?

        var observationID: ObservationID {
            .init(targetID: id, messageID: messageID, senderThreadID: senderThreadID)
        }
    }

    let entries: [Entry]

    init(messages: [AgentChatMessage], threadID: String?) {
        var entries: [Entry] = []
        var indices: [String: Int] = [:]

        // Establish membership separately from observations. Merely listing or
        // messaging an arbitrary runtime identity must never add it to the count.
        for message in messages {
            guard let report = message.activity?.delegation,
                Self.identifiesChildActivity(report.operation)
            else { continue }
            for target in report.targets where Self.isOtherAgent(target.id, in: report, threadID: threadID) {
                guard indices[target.id] == nil else { continue }
                indices[target.id] = entries.count
                entries.append(
                    .init(
                        id: target.id, name: target.id, state: nil,
                        messageID: message.id, senderThreadID: report.senderThreadID))
            }
        }

        // Transcript order is the observation order. An absent state never
        // turns a known outcome into unknown or assumes the Agent is running.
        for message in messages {
            guard let report = message.activity?.delegation else { continue }
            for target in report.targets where Self.isOtherAgent(target.id, in: report, threadID: threadID) {
                guard let index = indices[target.id] else { continue }
                if let path = target.path, !path.isEmpty { entries[index].name = path }
                if let state = target.state {
                    entries[index].state = state
                    entries[index].stateMessageID = message.id
                    entries[index].stateSenderThreadID = report.senderThreadID
                }
            }
        }
        self.entries = entries
    }

    private static func identifiesChildActivity(_ operation: AgentChatDelegation.Operation) -> Bool {
        switch operation {
        case .spawnAgent, .started, .interacted, .interrupted, .completed: true
        case .sendInput, .resumeAgent, .wait, .closeAgent, .sendMessage,
            .followupTask, .interruptAgent, .listAgents:
            false
        }
    }

    private static func isOtherAgent(
        _ id: String, in report: AgentChatDelegation, threadID: String?
    ) -> Bool {
        !id.isEmpty && id != threadID && id != report.senderThreadID
    }
}
