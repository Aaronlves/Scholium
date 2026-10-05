import SwiftUI

/// Quiet actions embedded in content (message footers, composer accessories,
/// and attachment actions). SwiftUI owns standard activation, focus and
/// accessibility; this style changes only label ink, never its geometry.
struct ScholiumContentActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var restingRole: ScholiumColorRole = .secondaryText

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(
                minWidth: ScholiumGrid.Dimension.preferredCustomTarget,
                minHeight: ScholiumGrid.Dimension.preferredCustomTarget
            )
            .contentShape(.rect)
            .foregroundStyle(configuration.role == .destructive ? .red : restingRole.color)
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.5)
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
    /// Native Menus retain their own activation and accessibility host. Labels
    /// include the complete target; never wrap a Menu in a primitive Button.
    /// Menu items keep their system-owned style.
    func scholiumContentActionMenu() -> some View {
        menuStyle(.button)
            .buttonStyle(ScholiumContentActionButtonStyle())
            .foregroundStyle(.secondary)
            .tint(nil as Color?)
            .frame(
                minWidth: ScholiumGrid.Dimension.preferredCustomTarget,
                minHeight: ScholiumGrid.Dimension.preferredCustomTarget
            )
    }

    func scholiumIconControl() -> some View {
        modifier(ScholiumIconControlModifier())
    }
}
