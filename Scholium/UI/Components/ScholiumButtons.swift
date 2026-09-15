import SwiftUI

/// Quiet actions embedded in content (message footers, composer accessories,
/// and attachment actions). Native Button retains activation, keyboard focus,
/// disabled presentation and accessibility; the shared content feedback owns
/// only the pointer treatment.
struct ScholiumContentActionButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .frame(
                    minWidth: ScholiumGrid.Dimension.preferredCustomTarget,
                    minHeight: ScholiumGrid.Dimension.preferredCustomTarget
                )
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .modifier(ScholiumContentActionFeedback())
    }
}

private struct ScholiumContentActionFeedback: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scholiumContentControlInk()
            .scholiumActivationPointer()
            .scholiumContentControlPointerFeedback(
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialControlCornerRadius,
                    style: .continuous
                )
            )
    }
}

/// Shared native chrome for icon Buttons and Menus. Labels and action/state
/// ownership remain with the calling component.
private struct ScholiumIconControlModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .menuStyle(.button)
            .buttonStyle(.glass)
            .tint(nil as Color?)
            .buttonBorderShape(.circle)
            .controlSize(.regular)
            .menuIndicator(.hidden)
            .frame(
                width: ScholiumMetrics.Accessibility.preferredCustomTarget,
                height: ScholiumMetrics.Accessibility.preferredCustomTarget
            )
    }
}

extension View {
    /// Native menus retain their menu host; their label supplies the same
    /// target geometry as a compact action. Do not style individual menu items.
    func scholiumContentActionMenu() -> some View {
        menuStyle(.borderlessButton)
            .buttonStyle(.borderless)
            .modifier(ScholiumContentActionFeedback())
    }

    func scholiumIconControl() -> some View {
        modifier(ScholiumIconControlModifier())
    }
}
