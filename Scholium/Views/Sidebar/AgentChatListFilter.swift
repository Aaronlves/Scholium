import Foundation
import ScholiumContracts

/// A local list projection; it never changes conversation or execution state.
enum AgentChatListFilter: String, CaseIterable {
    case all, needsInput, inProgress, drafts, unread, important

    var title: String {
        switch self {
        case .all: "All Conversations"
        case .needsInput: "Needs Input"
        case .inProgress: "In Progress"
        case .drafts: "Has Draft"
        case .unread: "Unread"
        case .important: "Important"
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
        case .unread: conversation.unreadAt != nil
        case .important: conversation.importantAt != nil
        }
    }
}

/// Keep existing click and keyboard targets stationary during one list visit.
struct AgentChatListOrder {
    private(set) var ids: [UUID] = []

    mutating func reset(_ newestFirst: [UUID]) { ids = newestFirst }

    mutating func reconcile(_ newestFirst: [UUID]) {
        let existing = Set(ids)
        let visible = Set(newestFirst)
        ids = newestFirst.filter { !existing.contains($0) } + ids.filter { visible.contains($0) }
    }

    func arrange(_ conversations: [AgentChatConversation]) -> [AgentChatConversation] {
        let ranks = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        return conversations.sorted {
            let left = ranks[$0.id] ?? -1
            let right = ranks[$1.id] ?? -1
            return left == right ? $0.updatedAt > $1.updatedAt : left < right
        }
    }
}
