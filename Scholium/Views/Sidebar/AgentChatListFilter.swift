import Foundation
import ScholiumContracts

/// A local list projection; it never changes conversation or execution state.
enum AgentChatListFilter: String, CaseIterable {
    case all, needsInput, inProgress, drafts

    var title: String {
        switch self {
        case .all: "All Conversations"
        case .needsInput: "Needs Input"
        case .inProgress: "In Progress"
        case .drafts: "Has Draft"
        }
    }

    static func hasDraft(_ conversation: AgentChatConversation) -> Bool {
        !conversation.draft.isEmpty || !conversation.attachments.isEmpty
            || !conversation.localMaterials.isEmpty || conversation.draftReplyQuotes?.isEmpty == false
            || conversation.selectedMethods?.isEmpty == false || !conversation.queuedMessages.isEmpty
            || conversation.childDrafts.values.contains { !$0.isEmpty }
            || conversation.draftCoordinationTarget != nil
    }

    func includes(_ conversation: AgentChatConversation, needsInput: Bool, inProgress: Bool) -> Bool {
        switch self {
        case .all: true
        case .needsInput: needsInput
        case .inProgress: inProgress
        case .drafts: Self.hasDraft(conversation)
        }
    }
}
