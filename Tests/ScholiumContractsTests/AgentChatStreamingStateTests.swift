import Foundation
import ScholiumContracts
import Testing

struct AgentChatStreamingStateTests {
    @Test("Streaming is transient while exact prose and retained message metadata round-trip")
    func persistence() throws {
        var message = AgentChatMessage(
            id: "reply", role: .assistant, text: "**未完成 😀\r\n", phase: .commentary, isStreaming: true)
        message.turnID = "turn"
        message.coordinationTarget = .init(parentThreadID: "parent", childThreadID: "child", name: "Reader")
        message.replyQuotes = [.init(conversationID: UUID(), messageID: "earlier", text: "Exact quotation")]
        let data = try JSONEncoder().encode(message)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["isStreaming"] == nil)
        let restored = try JSONDecoder().decode(AgentChatMessage.self, from: data)
        #expect(!restored.isStreaming)
        message.isStreaming = false
        #expect(restored == message)
    }
}
