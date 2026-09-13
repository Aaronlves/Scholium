import ScholiumContracts
import SwiftUI

struct AgentChatConversationOutline: View {
    let messages: [AgentChatMessage]
    let currentMessageID: String?
    let navigate: (String) -> Void
    @State private var query = ""

    private var requests: [AgentChatMessage] {
        messages.filter { $0.role == .user && (query.isEmpty || $0.text.localizedStandardContains(query)) }
    }
    var body: some View {
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
                                    Text(
                                        verbatim: message.text.isEmpty
                                            ? String(localized: "Materials", bundle: .module)
                                            : String(AgentChatListPresentation.plainText(message.text).prefix(240))
                                    )
                                    .lineLimit(3).foregroundStyle(.primary)
                                    if let response = messages.first(where: {
                                        $0.turnID != nil && $0.turnID == message.turnID && $0.role == .assistant && $0.phase != .commentary && !$0.text.isEmpty
                                    }) {
                                        Text(verbatim: String(AgentChatListPresentation.plainText(response.text).prefix(180))).font(.caption).foregroundStyle(
                                            .secondary
                                        ).lineLimit(2)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, minHeight: ScholiumGrid.Dimension.preferredCustomTarget, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("scholium.chat.outline.\(message.id)")
                        Divider()
                    }
                    if requests.isEmpty { Text("No Matches").foregroundStyle(.secondary) }
                }
            }
        }
        .padding(ScholiumSidebarLayout.textInset)
        .frame(width: 300, height: 360)
        .accessibilityIdentifier("scholium.chat.outline")
    }
}
