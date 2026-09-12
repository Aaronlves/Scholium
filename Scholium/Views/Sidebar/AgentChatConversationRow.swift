import Foundation
import ScholiumContracts
import SwiftUI

/// Source-neutral list copy. Conversation storage and execution remain controller-owned.
enum AgentChatListPresentation {
    static func plainText(_ source: String) -> String {
        MarkdownVisibleText.render(source).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func preview(_ conversation: AgentChatConversation, query: String) -> String {
        if !query.isEmpty {
            guard
                let passage = conversation.messages.lazy.compactMap({ AgentChatSearch.passage(in: $0, query: query) }).first
                    ?? (AgentChatSearch.matches(conversation.title, query: query) ? conversation.title : nil)
            else { return "" }
            let readable = plainText(passage)
            // A query for literal syntax or a hidden destination still needs its exact match.
            return AgentChatSearch.matches(readable, query: query)
                ? readable
                : passage.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        let source: String
        if !conversation.draft.isEmpty {
            source = conversation.draft
        } else if let queued = conversation.queuedMessages.first {
            source = queued.text
        } else if AgentChatListFilter.hasDraft(conversation) {
            return String(localized: "Unsent materials or instructions")
        } else {
            source = conversation.messages.last(where: { $0.role != .operation && !$0.text.isEmpty })?.text ?? ""
        }
        return String(plainText(source).prefix(180))
    }

    static func status(_ conversation: AgentChatConversation, questions: Int, approvals: Int, busy: Bool) -> AgentChatActivity.Status? {
        if questions > 0 { return .waitingForInput }
        if approvals > 0 { return .waitingForApproval }
        if busy { return .running }
        switch conversation.lastRunStatus {
        case .failed, .uncertain, .interrupted, .declined: return conversation.lastRunStatus
        default: return nil  // A completed prior turn is ordinary history, not a current selection or pending task.
        }
    }
}

struct AgentChatConversationRow: View {
    let conversation: AgentChatConversation
    let query: String
    let status: AgentChatActivity.Status?

    private var title: String {
        conversation.title.isEmpty ? String(localized: "New Conversation") : conversation.title
    }
    private var context: String {
        var labels: [String] = []
        if conversation.unreadAt != nil { labels.append(String(localized: "Unread")) }
        if conversation.importantAt != nil { labels.append(String(localized: "Important")) }
        if !query.isEmpty {
            labels.append(String(localized: "Search Match"))
        } else if AgentChatListFilter.hasDraft(conversation) {
            labels.append(String(localized: "Draft"))
        }
        if let status { labels.append(status.label) }
        return labels.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: ScholiumSidebarLayout.itemSpacing) {
            Image(systemName: "circle.fill")
                .font(.caption2)
                .foregroundStyle(ScholiumNativeColorRole.controlAccent.color)
                .opacity(conversation.unreadAt == nil ? 0 : 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: ScholiumSidebarLayout.textSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.body.weight(conversation.unreadAt != nil ? .semibold : .medium))
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    Spacer(minLength: ScholiumSidebarLayout.textSpacing)
                    if conversation.importantAt != nil {
                        Image(systemName: "star.fill").foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                    if Calendar.current.isDateInToday(conversation.updatedAt) {
                        Text(conversation.updatedAt, format: .dateTime.hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(conversation.updatedAt, format: .dateTime.month(.twoDigits).day(.twoDigits))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                let preview = AgentChatListPresentation.preview(conversation, query: query)
                let summary = [context, preview].filter { !$0.isEmpty }.joined(separator: " · ")
                Text(summary).font(.callout).foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(title)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityValue(
            Text(
                [context, AgentChatListPresentation.preview(conversation, query: query)]
                    .filter { !$0.isEmpty }.joined(separator: " · ")))
    }
}
