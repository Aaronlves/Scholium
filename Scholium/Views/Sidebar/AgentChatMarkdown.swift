import ScholiumContracts
import SwiftUI

struct AgentChatMarkdown: View {
    private let sourceIdentity: ScholiumExactUTF8.SourceIdentity
    private var text: String { sourceIdentity.source }
    var readerID: String? = nil
    var isStreaming = false
    var expandsToFillWidth = true
    var allowsNativeParagraph = false
    var quoteSelection: ((AgentChatReplySelection) -> Void)? = nil
    @Environment(\.openURL) private var openURL

    init(
        text: String, readerID: String? = nil, isStreaming: Bool = false, expandsToFillWidth: Bool = true,
        quoteSelection: ((AgentChatReplySelection) -> Void)? = nil, allowsNativeParagraph: Bool = false
    ) {
        sourceIdentity = .init(text)
        self.readerID = readerID
        self.isStreaming = isStreaming
        self.expandsToFillWidth = expandsToFillWidth
        self.quoteSelection = quoteSelection
        self.allowsNativeParagraph = allowsNativeParagraph
    }

    var body: some View {
        AgentChatReadReply(
            source: text, readerID: readerID, isStreaming: isStreaming, quote: quoteSelection, openLink: { openURL($0) },
            fitsContent: !expandsToFillWidth, allowsNativeParagraph: allowsNativeParagraph
        )
        .font(ScholiumChatAppearance.messageFont)
        .foregroundStyle(ScholiumChatAppearance.messageForeground)
        .frame(maxWidth: expandsToFillWidth ? .infinity : nil, alignment: .leading)
    }

}

struct AgentChatTimelineItem: Identifiable {
    // Mounted items borrow one immutable transcript snapshot. Grouping must not
    // allocate another message-value buffer for every retained history item.
    let messages: ArraySlice<AgentChatMessage>
    var id: String { messages.first!.id }
    var isProcess: Bool { Self.isProcess(messages.first!) }
    static func isProcess(_ message: AgentChatMessage) -> Bool {
        message.role == .operation || message.phase == .commentary || message.plan != nil
    }

    static func group(_ messages: [AgentChatMessage]) -> [Self] {
        guard !messages.isEmpty else { return [] }
        var items: [Self] = []
        var start = messages.startIndex
        for index in messages.indices.dropFirst() {
            if Self.isProcess(messages[index]), Self.isProcess(messages[index - 1]),
                messages[index - 1].turnID == messages[index].turnID
            {
                continue
            }
            items.append(.init(messages: messages[start..<index]))
            start = index
        }
        items.append(.init(messages: messages[start..<messages.endIndex]))
        return items
    }
}

/// A single-pass view projection for the mounted transcript. It keeps the
/// detail view from rescanning the complete retained history for every
/// process row or turn-status label. Groups share the snapshot; the turn lookup
/// retains indices rather than a second full copy of every message value.
struct AgentChatTimelineProjection {
    let messages: [AgentChatMessage]
    let items: [AgentChatTimelineItem]
    let ids: [String]
    let replyReaderIDs: Set<String>
    private let messageIndicesByTurn: [String: [Int]]
    private let statusOwnerIDs: Set<String>
    private let activeActivityIDs: [String: String]

    init(_ messages: [AgentChatMessage]) {
        self.messages = messages
        self.items = AgentChatTimelineItem.group(messages)
        self.ids = self.items.map(\.id)

        var messageIndicesByTurn: [String: [Int]] = [:]
        var firstNonUserIDs: [String: String] = [:]
        var lastUserIDs: [String: String] = [:]
        var activeActivityIDs: [String: String] = [:]
        for (index, message) in messages.enumerated() {
            guard let turnID = message.turnID else { continue }
            messageIndicesByTurn[turnID, default: []].append(index)
            if message.role != .user, firstNonUserIDs[turnID] == nil {
                firstNonUserIDs[turnID] = message.id
            }
            if message.role == .user { lastUserIDs[turnID] = message.id }
            if message.activity?.status.isActive == true { activeActivityIDs[turnID] = message.id }
        }
        self.messageIndicesByTurn = messageIndicesByTurn
        self.activeActivityIDs = activeActivityIDs

        var statusOwnerIDs: Set<String> = []
        var replyReaderIDs: Set<String> = []
        for item in items {
            if !item.isProcess {
                for message in item.messages where message.asyncQuestion == nil && !message.text.isEmpty {
                    replyReaderIDs.insert(message.id)
                }
            }
            guard let turnID = item.messages.first?.turnID else { continue }
            let owner = firstNonUserIDs[turnID] ?? lastUserIDs[turnID]
            if owner == item.id { statusOwnerIDs.insert(item.id) }
        }
        self.statusOwnerIDs = statusOwnerIDs
        self.replyReaderIDs = replyReaderIDs
    }

    func messages(for turnID: String?) -> [AgentChatMessage] {
        guard let turnID else { return [] }
        return (messageIndicesByTurn[turnID] ?? []).map { messages[$0] }
    }

    func hasMessages(for turnID: String?) -> Bool {
        guard let turnID else { return false }
        return messageIndicesByTurn[turnID]?.isEmpty == false
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
