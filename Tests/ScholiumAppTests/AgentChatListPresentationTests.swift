import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Chat list presentation")
struct AgentChatListPresentationTests {
    @Test("Previews remove Markdown and distinguish unsent material from previous answers")
    func previews() {
        var conversation = AgentChatConversation(triptychID: UUID())
        conversation.messages = [.init(role: .assistant, text: "## 初步分析\n**理由**与[价值](https://example.invalid)不同。")]
        #expect(AgentChatListPresentation.preview(conversation, query: "") == "初步分析 理由与价值不同。")
        conversation.draft = "**未发送**的补充。"
        #expect(AgentChatListPresentation.preview(conversation, query: "") == "未发送的补充。")
        #expect(AgentChatListFilter.hasDraft(conversation))
        conversation.draft = ""
        conversation.childDrafts = ["child": "An unsent instruction"]
        #expect(AgentChatListPresentation.preview(conversation, query: "") != "初步分析 理由与价值不同。")
        let before = conversation
        #expect(AgentChatListPresentation.preview(conversation, query: "理由").contains("理由"))
        #expect(AgentChatListPresentation.preview(conversation, query: "example.invalid").contains("example.invalid"))
        #expect(conversation == before)
    }

    @Test("Only observed current execution or consequential outcomes occupy the status slot")
    func states() {
        var conversation = AgentChatConversation(triptychID: UUID())
        for previous in [AgentChatActivity.Status.completed, .running, .waitingForInput, .waitingForApproval] {
            conversation.lastRunStatus = previous
            #expect(AgentChatListPresentation.status(conversation, questions: 0, approvals: 0, busy: false) == nil)
        }
        conversation.lastRunStatus = .failed
        #expect(AgentChatListPresentation.status(conversation, questions: 0, approvals: 0, busy: false) == .failed)
        #expect(AgentChatListPresentation.status(conversation, questions: 0, approvals: 0, busy: true) == .running)
        #expect(AgentChatListPresentation.status(conversation, questions: 1, approvals: 0, busy: true) == .waitingForInput)
        #expect(AgentChatListPresentation.status(conversation, questions: 0, approvals: 1, busy: true) == .waitingForApproval)
    }

}
