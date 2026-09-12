import SwiftUI

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
    func scholiumIconControl() -> some View {
        modifier(ScholiumIconControlModifier())
    }
}
