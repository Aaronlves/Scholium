import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Chat list presentation")
struct AgentChatListPresentationTests {
    @Test("Alternating live updates preserve list targets until the next visit")
    func stableLiveOrder() {
        var first = AgentChatConversation(triptychID: UUID())
        var second = AgentChatConversation(triptychID: first.triptychID)
        var order = AgentChatListOrder()
        order.reset([first.id, second.id])
        for index in 0..<8 {
            if index.isMultiple(of: 2) {
                second.updatedAt = Date().addingTimeInterval(Double(index))
            } else {
                first.updatedAt = Date().addingTimeInterval(Double(index))
            }
            let newest = [first, second].sorted { $0.updatedAt > $1.updatedAt }
            order.reconcile(newest.map(\.id))
            #expect(order.arrange(newest).map(\.id) == [first.id, second.id])
        }
        let incoming = AgentChatConversation(triptychID: first.triptychID)
        order.reconcile([incoming.id, second.id, first.id])
        #expect(order.ids == [incoming.id, first.id, second.id])
        order.reconcile([incoming.id, second.id])
        #expect(order.ids == [incoming.id, second.id])
        order.reset([second.id, incoming.id])
        #expect(order.ids == [second.id, incoming.id])
    }

    @Test("Previews remove Markdown and distinguish unsent material from previous answers")
    func previews() {
        var conversation = AgentChatConversation(triptychID: UUID())
        conversation.messages = [
            .init(role: .assistant, text: "## 初步分析\n**理由**与[价值](https://example.invalid)不同。")
        ]
        #expect(AgentChatListPresentation.preview(conversation, query: "") == "初步分析 理由与价值不同。")
        conversation.draft = "**未发送**的补充。"
        #expect(AgentChatListPresentation.preview(conversation, query: "") == "未发送的补充。")
        #expect(AgentChatListFilter.hasDraft(conversation))
        conversation.draft = ""
        conversation.childDrafts = ["child": "An unsent instruction"]
        #expect(AgentChatListPresentation.preview(conversation, query: "") != "初步分析 理由与价值不同。")
        let before = conversation
        #expect(AgentChatListPresentation.preview(conversation, query: "理由").contains("理由"))
        #expect(
            AgentChatListPresentation.preview(conversation, query: "example.invalid").contains(
                "example.invalid"))
        #expect(conversation == before)
    }

    @Test("Only observed current execution or consequential outcomes occupy the status slot")
    func states() {
        var conversation = AgentChatConversation(triptychID: UUID())
        for previous in [
            AgentChatActivity.Status.completed, .running, .waitingForInput, .waitingForApproval,
        ] {
            conversation.lastRunStatus = previous
            #expect(
                AgentChatListPresentation.status(conversation, questions: 0, approvals: 0, busy: false)
                    == nil)
        }
        conversation.lastRunStatus = .failed
        #expect(
            AgentChatListPresentation.status(conversation, questions: 0, approvals: 0, busy: false)
                == .failed)
        #expect(
            AgentChatListPresentation.status(conversation, questions: 0, approvals: 0, busy: true)
                == .running)
        #expect(
            AgentChatListPresentation.status(conversation, questions: 1, approvals: 0, busy: true)
                == .waitingForInput)
        #expect(
            AgentChatListPresentation.status(conversation, questions: 0, approvals: 1, busy: true)
                == .waitingForApproval)
    }

}
