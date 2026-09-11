import SwiftUI

/// Keeps native activation, roles, shortcuts, sizing, and container behavior.
/// Only command tint is owned here; document selection retains its own Accent.
private struct ScholiumNeutralButtonStyle<NativeStyle: PrimitiveButtonStyle>: PrimitiveButtonStyle {
    let nativeStyle: NativeStyle

    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .buttonStyle(nativeStyle)
            .tint(
                (configuration.role == .destructive
                    ? ScholiumColorRole.destructive : .primaryText).color)
    }
}

/// Menu triggers use MenuStyle rather than PrimitiveButtonStyle on macOS.
private struct ScholiumNeutralMenuStyle<NativeStyle: MenuStyle>: MenuStyle {
    let nativeStyle: NativeStyle

    func makeBody(configuration: Configuration) -> some View {
        Menu(configuration)
            .menuStyle(nativeStyle)
            .tint(ScholiumColorRole.primaryText.color)
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
    func scholiumButtonStyle<S: PrimitiveButtonStyle>(_ nativeStyle: S) -> some View {
        buttonStyle(ScholiumNeutralButtonStyle(nativeStyle: nativeStyle))
            .menuStyle(ScholiumNeutralMenuStyle(nativeStyle: .automatic))
    }

    func scholiumMenuStyle<S: MenuStyle>(_ nativeStyle: S) -> some View {
        menuStyle(ScholiumNeutralMenuStyle(nativeStyle: nativeStyle))
    }

    func scholiumIconControl() -> some View {
        modifier(ScholiumIconControlModifier())
    }
}
