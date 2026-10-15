import ScholiumContracts
import SwiftUI

struct AgentChatOutlineRequest: Identifiable {
    let id: String
    let text: String
    let responseID: String?
    let responseText: String?
}

/// A mounted Outline retains its current source associations, raw-query
/// matches and only the labels requested by its lazy rows. Neither query nor
/// selection changes need to parse the same Markdown again.
@MainActor
final class AgentChatOutlineProjection {
    private struct Preview {
        let source: String
        let limit: Int
        let text: String
    }

    private var retained: [AgentChatOutlineRequest] = []
    private var query: String?
    private var queryLocale: Locale?
    private var matches: [AgentChatOutlineRequest] = []
    private var previews: [String: Preview] = [:]
    private let plainText: (String) -> String

    init(plainText: @escaping (String) -> String = AgentChatListPresentation.plainText) {
        self.plainText = plainText
    }

    func requests(in messages: [AgentChatMessage], query: String) -> [AgentChatOutlineRequest] {
        var firstResponses: [String: AgentChatMessage] = [:]
        for message in messages where message.role == .assistant && message.phase != .commentary && !message.text.isEmpty {
            if let turnID = message.turnID, firstResponses[turnID] == nil { firstResponses[turnID] = message }
        }
        let requests = messages.filter { $0.role == .user }.map { message in
            let response = message.turnID.flatMap { firstResponses[$0] }
            return AgentChatOutlineRequest(
                id: message.id, text: message.text, responseID: response?.id, responseText: response?.text)
        }
        let changed = !Self.hasSameSources(retained, requests)
        if changed {
            retained = requests
            let validIDs = Set(requests.flatMap { [$0.id] + ($0.responseID.map { [$0] } ?? []) })
            previews = previews.filter { validIDs.contains($0.key) }
        }
        let queryChanged = self.query.map { !ScholiumExactUTF8.equal($0, query) } ?? true
        let locale = Locale.current
        if changed || queryChanged || queryLocale != locale {
            // Keep the existing question predicate on exact captured source,
            // including syntax and destinations absent from visible labels.
            matches = retained.filter { query.isEmpty || $0.text.localizedStandardContains(query) }
            self.query = query
            queryLocale = locale
        }
        return matches
    }

    func question(for request: AgentChatOutlineRequest) -> String {
        request.text.isEmpty
            ? String(localized: "Materials", bundle: .module)
            : preview(id: request.id, source: request.text, limit: 240)
    }

    func response(for request: AgentChatOutlineRequest) -> String? {
        guard let id = request.responseID, let text = request.responseText else { return nil }
        return preview(id: id, source: text, limit: 180)
    }

    private func preview(id: String, source: String, limit: Int) -> String {
        if let retained = previews[id], retained.limit == limit, ScholiumExactUTF8.equal(retained.source, source) {
            return retained.text
        }
        let text = String(plainText(source).prefix(limit))
        previews[id] = .init(source: source, limit: limit, text: text)
        return text
    }

    private static func hasSameSources(_ lhs: [AgentChatOutlineRequest], _ rhs: [AgentChatOutlineRequest]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { pair in
            let (left, right) = pair
            guard left.id == right.id && left.responseID == right.responseID && ScholiumExactUTF8.equal(left.text, right.text) else {
                return false
            }
            switch (left.responseText, right.responseText) {
            case (nil, nil): return true
            case (.some(let left), .some(let right)): return ScholiumExactUTF8.equal(left, right)
            default: return false
            }
        }
    }
}

struct AgentChatConversationOutline: View {
    let messages: [AgentChatMessage]
    let currentMessageID: String?
    let navigate: (String) -> Void
    @State private var projection = AgentChatOutlineProjection()
    @State private var query = ""

    var body: some View {
        let requests = projection.requests(in: messages, query: query)
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text("Conversation Outline").font(.headline)
            TextField("Find a question", text: $query)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    ForEach(requests) { message in
                        Button {
                            navigate(message.id)
                        } label: {
                            HStack(alignment: .top, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                                Image(systemName: currentMessageID == message.id ? "arrow.right" : "text.bubble")
                                    .frame(width: ScholiumGrid.Dimension.iconTrackWidth)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                                    Text(verbatim: projection.question(for: message))
                                        .lineLimit(3).foregroundStyle(.primary)
                                    if let response = projection.response(for: message) {
                                        Text(verbatim: response).font(.caption).foregroundStyle(
                                            .secondary
                                        ).lineLimit(2)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, minHeight: ScholiumGrid.Dimension.preferredCustomTarget, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(ScholiumContentActionButtonStyle(restingRole: .primaryText))
                        .accessibilityIdentifier("scholium.chat.outline.\(message.id)")
                        Divider()
                    }
                    if requests.isEmpty { Text("No Matches").foregroundStyle(.secondary) }
                }
            }
            .frame(maxHeight: 280)
            .fixedSize(horizontal: false, vertical: true)
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(ScholiumSidebarLayout.textInset)
        .frame(width: 300)
        .accessibilityIdentifier("scholium.chat.outline")
    }
}
