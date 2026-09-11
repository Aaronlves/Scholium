import SwiftUI

/// Speaker layout is independent of Markdown parsing and message lifecycle.
struct AgentChatMessageSurface<Content: View>: View {
    let isUser: Bool
    @ViewBuilder let content: () -> Content
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        content()
            .font(ScholiumChatAppearance.messageFont)
            .foregroundStyle(ScholiumChatAppearance.messageForeground)
            .padding(.horizontal, isUser ? ScholiumChatAppearance.bubbleHorizontalInset : 0)
            .padding(.vertical, isUser ? ScholiumChatAppearance.bubbleVerticalInset : 0)
            .background {
                if isUser {
                    RoundedRectangle(cornerRadius: ScholiumChatAppearance.bubbleRadius)
                        .fill(ScholiumChatAppearance.userMessageBackground)
                        .overlay {
                            if contrast == .increased {
                                RoundedRectangle(cornerRadius: ScholiumChatAppearance.bubbleRadius)
                                    .strokeBorder(.secondary, lineWidth: 1)
                            }
                        }
                }
            }
            .padding(.leading, isUser ? ScholiumChatAppearance.userLeadingInset : 0)
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}
