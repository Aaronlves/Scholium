import ScholiumContracts
import SwiftUI

/// Reported occupancy only; cumulative token consumption is a different value.
struct AgentChatContextMeter: View {
    let usage: AgentChatContextUsage?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Group {
                if let fraction = AgentChatContextPresentation.fraction(usage) {
                    ProgressView(value: fraction)
                        .progressViewStyle(.circular).controlSize(.small)
                } else {
                    Image(systemName: "circle.dotted")
                }
            }
            .frame(width: ScholiumGrid.Dimension.iconTrackWidth, height: ScholiumGrid.Dimension.iconTrackWidth)
            .frame(width: ScholiumGrid.Dimension.preferredCustomTarget, height: ScholiumGrid.Dimension.preferredCustomTarget)
            .accessibilityHidden(true)
        }
        .buttonStyle(ScholiumContentActionButtonStyle())
        .help(AgentChatContextPresentation.summary(usage))
        .accessibilityLabel("Context Window")
        .accessibilityValue(AgentChatContextPresentation.summary(usage))
        .accessibilityIdentifier("scholium.chat.contextMeter")
    }
}
