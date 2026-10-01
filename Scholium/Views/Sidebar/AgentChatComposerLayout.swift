import SwiftUI

/// The input area supplies size limits. This composition keeps prepared
/// material scrollable and the native editor and delivery controls direct.
struct AgentChatComposerLayout<Prepared: View, Input: View, Controls: View>: View {
    @Environment(\.agentChatInputAreaLimits) private var limits
    let hasPreparedContent: Bool
    @ViewBuilder let prepared: () -> Prepared
    @ViewBuilder let input: (CGFloat?) -> Input
    @ViewBuilder let controls: () -> Controls

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumSidebarLayout.itemSpacing) {
            if hasPreparedContent {
                AgentChatContentScroll(maximumHeight: limits.preparationMaximumHeight ?? 240) {
                    prepared()
                }
                .environment(\.agentChatContentMaximumHeight, limits.preparationMaximumHeight)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("scholium.chat.preparedMaterials")
            }
            input(limits.editorMaximumHeight)
            controls()
        }
    }
}
