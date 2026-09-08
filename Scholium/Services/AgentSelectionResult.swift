import Foundation
import ScholiumContracts

typealias AgentSelectionValidation = @MainActor () async -> Bool
typealias AgentSelectionInquiryHandler = @MainActor (AgentChatSelectionInquiry, AgentSelectionValidation) async -> AgentSelectionResult?

/// A disposable reference to a Chat-owned execution, never a second transcript or task.
@MainActor
struct AgentSelectionResult {
    let chat: AgentChatController
    let conversationID: UUID
    let title: String
    let original: String
    let adopt: ((String) async throws -> Void)?
    let openReference: (URL) -> Bool
    let continueInChat: () -> Void

    var conversation: AgentChatConversation? { chat.conversations.first { $0.id == conversationID } }
    var finalReply: String? {
        guard conversation?.lastRunStatus == .completed, !chat.isBusy(in: conversationID) else { return nil }
        let messages = conversation?.messages.filter { $0.role == .assistant && $0.phase == .finalAnswer } ?? []
        guard messages.count == 1, let reply = messages.first?.text, !reply.isEmpty else { return nil }
        return reply
    }
}
