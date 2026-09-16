import SwiftUI

struct AgentChatHeader<Actions: View>: View {
    let title: String
    let back: (() -> Void)?
    let canCreate: Bool
    let newConversation: () -> Void
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        ScholiumSidebarHeader {
            if let back {
                Button(action: back) {
                    ScholiumSidebarHeaderIcon(systemImage: ScholiumSidebarAction.back.symbol)
                }
                .scholiumSidebarHeaderControl()
                .help("Conversations").accessibilityLabel("Conversations")
                .accessibilityIdentifier("scholium.chat.back")
            }
            Text(title).font(.headline).lineLimit(1)
                .padding(.leading, back == nil ? ScholiumSidebarLayout.rowInset : 0)
            Spacer(minLength: 0)
            ScholiumSidebarHeaderActions {
                Button(action: newConversation) {
                    ScholiumSidebarHeaderIcon(systemImage: ScholiumSidebarAction.newConversation.symbol)
                }
                .scholiumSidebarHeaderControl()
                .disabled(!canCreate)
                .help("New Conversation").accessibilityLabel("New Conversation")
                .accessibilityIdentifier("scholium.chat.newConversation")
                actions()
            }
        }
    }
}
