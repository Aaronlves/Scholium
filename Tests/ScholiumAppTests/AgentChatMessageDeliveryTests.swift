import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Chat message delivery placement")
struct AgentChatMessageDeliveryTests {
    @Test("Preflight does not project a sent-message status; only the pending researcher message owns it")
    func pendingIdentity() {
        let request = AgentChatMessage(id: "request", role: .user, text: "Retained request")
        let earlier = AgentChatMessage(id: "earlier", role: .user, text: "Retained request")
        let reply = AgentChatMessage(id: "request", role: .assistant, text: "Reply")
        #expect(AgentChatMessageDelivery.status(for: request, pendingMessageID: nil, sendingMessageID: request.id) == nil)
        #expect(AgentChatMessageDelivery.status(for: request, pendingMessageID: request.id, sendingMessageID: request.id) == .sending)
        #expect(AgentChatMessageDelivery.status(for: earlier, pendingMessageID: request.id, sendingMessageID: request.id) == nil)
        #expect(AgentChatMessageDelivery.status(for: reply, pendingMessageID: request.id, sendingMessageID: request.id) == nil)
    }

    @Test("Connection loss retains uncertainty; matching history clears it even before the request finishes")
    func acknowledgementAndRecovery() {
        let request = AgentChatMessage(id: "request", role: .user, text: "Retained request")
        #expect(AgentChatMessageDelivery.status(for: request, pendingMessageID: request.id, sendingMessageID: nil) == .unconfirmed)
        #expect(AgentChatMessageDelivery.status(for: request, pendingMessageID: request.id, sendingMessageID: "different-request") == .unconfirmed)
        #expect(AgentChatMessageDelivery.status(for: request, pendingMessageID: nil, sendingMessageID: request.id) == nil)
        #expect(AgentChatMessageDelivery.status(for: request, pendingMessageID: nil, sendingMessageID: nil) == nil)
    }
}
