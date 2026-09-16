import AppKit
import Foundation
import ScholiumContracts
import SwiftUI

struct AgentChatMarkdown: View {
    let text: String
    var expandsToFillWidth = true
    var quoteSelection: ((AgentChatReplySelection) -> Void)? = nil
    @Environment(\.openURL) private var openURL

    var body: some View {
        AgentChatReadReply(
            source: text, quote: quoteSelection, openLink: { openURL($0) },
            fitsContent: !expandsToFillWidth
        )
        .font(ScholiumChatAppearance.messageFont)
        .foregroundStyle(ScholiumChatAppearance.messageForeground)
        .frame(maxWidth: expandsToFillWidth ? .infinity : nil, alignment: .leading)
    }

}

struct AgentChatTimelineItem: Identifiable {
    let messages: [AgentChatMessage]
    var id: String { messages[0].id }
    var isProcess: Bool { Self.isProcess(messages[0]) }
    static func activeActivityID(in history: [AgentChatMessage], turnID: String?) -> String? {
        guard let turnID else { return nil }
        return history.last { $0.turnID == turnID && $0.activity?.status == .running }?.id
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
                let previous = items.removeLast()
                items.append(.init(messages: previous.messages + [message]))
            } else {
                items.append(
                    .init(messages: [message]))
            }
        }
        return items
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
