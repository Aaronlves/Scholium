import ScholiumContracts
import SwiftUI

/// One visual and activation grid for the composer's quiet accessory controls.
/// Callers retain action, state, color and accessibility ownership.
struct AgentChatComposerAccessoryLabel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(width: ScholiumGrid.Dimension.iconTrackWidth, height: ScholiumGrid.Dimension.iconTrackWidth)
            .frame(width: ScholiumGrid.Dimension.preferredCustomTarget, height: ScholiumGrid.Dimension.preferredCustomTarget)
            .contentShape(Rectangle())
    }
}

/// Reported occupancy only; cumulative token consumption is a different value.
struct AgentChatContextMeter: View {
    let usage: AgentChatContextUsage?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            AgentChatComposerAccessoryLabel {
                AgentChatContextRing(fraction: AgentChatContextPresentation.fraction(usage))
            }
            .accessibilityHidden(true)
        }
        .buttonStyle(ScholiumContentActionButtonStyle())
        .help(AgentChatContextPresentation.summary(usage))
        .accessibilityLabel("Context Window")
        .accessibilityValue(AgentChatContextPresentation.summary(usage))
        .accessibilityIdentifier("scholium.chat.contextMeter")
    }
}

/// One quiet geometry for both observed occupancy and unavailable capacity.
/// The dashed ring is a state distinction, not a guessed zero reading.
private struct AgentChatContextRing: View {
    let fraction: Double?

    var body: some View {
        ZStack {
            Circle()
                .stroke(.tertiary, lineWidth: ScholiumMetrics.AgentChat.contextRingStrokeWidth)
            if let fraction {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        .secondary,
                        style: StrokeStyle(
                            lineWidth: ScholiumMetrics.AgentChat.contextRingStrokeWidth,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(-90))
            } else {
                Circle()
                    .stroke(
                        .secondary,
                        style: StrokeStyle(
                            lineWidth: ScholiumMetrics.AgentChat.contextRingStrokeWidth,
                            lineCap: .round,
                            dash: [
                                ScholiumMetrics.AgentChat.contextRingStrokeWidth,
                                ScholiumMetrics.AgentChat.contextRingStrokeWidth * 2,
                            ]
                        )
                    )
            }
        }
    }
}
