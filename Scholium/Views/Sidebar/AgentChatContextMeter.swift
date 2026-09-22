import ScholiumContracts
import SwiftUI

/// Reported occupancy only; cumulative token consumption is a different value.
struct AgentChatContextMeter: View {
    let usage: AgentChatContextUsage?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            AgentChatComposerIcon(content: .context(AgentChatContextPresentation.fraction(usage)))
        }
        .buttonStyle(ScholiumContentActionButtonStyle())
        .agentChatComposerControl()
        .help(AgentChatContextPresentation.summary(usage))
        .accessibilityLabel("Context Window")
        .accessibilityValue(AgentChatContextPresentation.summary(usage))
        .accessibilityIdentifier("scholium.chat.contextMeter")
    }
}
