import SwiftUI

struct AgentChatFindBar: View {
    @Binding var query: String
    let focusRequest: UUID?
    let position: Int?
    let count: Int
    let move: (Bool) -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            ContextSearchField(
                text: $query, prompt: "Find in Conversation",
                identifier: "scholium.chat.find.query", focusRequest: focusRequest,
                navigate: move, dismiss: dismiss)
            HStack(spacing: 8) {
                Group {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Find in Conversation")
                    } else if let position {
                        Text("Message \(position) of \(count)")
                    } else {
                        Text("No Matches")
                    }
                }.font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    move(true)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .help("Previous Matching Message").accessibilityLabel("Previous Matching Message")
                .disabled(count == 0)
                Button {
                    move(false)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .help("Next Matching Message").accessibilityLabel("Next Matching Message")
                .disabled(count == 0)
                Button("Done", action: dismiss)
            }.controlSize(.small)
        }
        .padding(.horizontal, ScholiumSidebarLayout.textInset)
        .padding(.vertical, 8)
    }
}
