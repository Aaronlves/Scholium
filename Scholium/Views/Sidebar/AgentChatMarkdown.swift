import AppKit
import Foundation
import ScholiumContracts
import SwiftUI

struct AgentChatMarkdown: View {
    let text: String
    var readerID: String? = nil
    var expandsToFillWidth = true
    var quoteSelection: ((AgentChatReplySelection) -> Void)? = nil
    @Environment(\.openURL) private var openURL

    var body: some View {
        AgentChatReadReply(
            source: text, readerID: readerID, quote: quoteSelection, openLink: { openURL($0) },
            fitsContent: !expandsToFillWidth
        )
        .font(ScholiumChatAppearance.messageFont)
        .foregroundStyle(ScholiumChatAppearance.messageForeground)
        .frame(maxWidth: expandsToFillWidth ? .infinity : nil, alignment: .leading)
    }

}

struct AgentChatTimelineItem: Identifiable {
    var messages: [AgentChatMessage]
    var id: String { messages[0].id }
    var isProcess: Bool { Self.isProcess(messages[0]) }
    static func activeActivityID(in history: [AgentChatMessage], turnID: String?) -> String? {
        guard let turnID else { return nil }
        return history.last { $0.turnID == turnID && $0.activity?.status.isActive == true }?.id
    }
    func carriesTurnStatus(in history: [AgentChatMessage]) -> Bool {
        guard let turn = messages.first?.turnID else { return false }
        // A turn can stop before producing any Agent item; retain its status below the request.
        let anchor =
            history.first { $0.turnID == turn && $0.role != .user }
            ?? history.last { $0.turnID == turn && $0.role == .user }
        return anchor?.id == id
    }
    static func isProcess(_ message: AgentChatMessage) -> Bool {
        message.role == .operation || message.phase == .commentary || message.plan != nil
    }

    static func group(_ messages: [AgentChatMessage]) -> [Self] {
        var items: [Self] = []
        for message in messages {
            if Self.isProcess(message), items.last?.isProcess == true,
                items.last?.messages.last?.turnID == message.turnID
            {
                items[items.count - 1].messages.append(message)
            } else {
                items.append(
                    .init(messages: [message]))
            }
        }
        return items
    }
}

/// A single-pass view projection for the mounted transcript. It keeps the
/// detail view from rescanning the complete retained history for every
/// process row or turn-status label.
struct AgentChatTimelineProjection {
    let messages: [AgentChatMessage]
    let items: [AgentChatTimelineItem]
    let ids: [String]
    private let messagesByTurn: [String: [AgentChatMessage]]
    private let statusOwnerIDs: Set<String>
    private let activeActivityIDs: [String: String]

    init(_ messages: [AgentChatMessage]) {
        self.messages = messages
        self.items = AgentChatTimelineItem.group(messages)
        self.ids = self.items.map(\.id)

        var messagesByTurn: [String: [AgentChatMessage]] = [:]
        var firstNonUserIDs: [String: String] = [:]
        var lastUserIDs: [String: String] = [:]
        var activeActivityIDs: [String: String] = [:]
        for message in messages {
            guard let turnID = message.turnID else { continue }
            messagesByTurn[turnID, default: []].append(message)
            if message.role != .user, firstNonUserIDs[turnID] == nil {
                firstNonUserIDs[turnID] = message.id
            }
            if message.role == .user { lastUserIDs[turnID] = message.id }
            if message.activity?.status.isActive == true { activeActivityIDs[turnID] = message.id }
        }
        self.messagesByTurn = messagesByTurn
        self.activeActivityIDs = activeActivityIDs

        var statusOwnerIDs: Set<String> = []
        for item in items {
            guard let turnID = item.messages.first?.turnID else { continue }
            let owner = firstNonUserIDs[turnID] ?? lastUserIDs[turnID]
            if owner == item.id { statusOwnerIDs.insert(item.id) }
        }
        self.statusOwnerIDs = statusOwnerIDs
    }

    func messages(for turnID: String?) -> [AgentChatMessage] {
        guard let turnID else { return [] }
        return messagesByTurn[turnID] ?? []
    }

    func carriesTurnStatus(_ item: AgentChatTimelineItem) -> Bool {
        statusOwnerIDs.contains(item.id)
    }

    func activeActivityID(for turnID: String?) -> String? {
        turnID.flatMap { activeActivityIDs[$0] }
    }
}

private struct ChatReadingInteractionKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    var chatReadingInteraction: @MainActor () -> Void {
        get { self[ChatReadingInteractionKey.self] }
        set { self[ChatReadingInteractionKey.self] = newValue }
    }
}
