import SwiftUI

/// Native disclosure semantics with a trailing, progressively revealed accessory.
struct AgentChatDisclosureStyle: DisclosureGroupStyle {
    var animates = true

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, animates: animates)
    }

    private struct Content: View {
        let configuration: DisclosureGroupStyleConfiguration
        let animates: Bool
        @Environment(\.controlActiveState) private var windowState
        @State private var isHovered = false
        @FocusState private var isFocused: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(
                        ScholiumMotion.disclosure(
                            reduceMotion: reduceMotion || !animates || windowState == .inactive)
                    ) {
                        configuration.isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        configuration.label
                        Image(systemName: "chevron.right")
                            .chatAccessory()
                            .animation(
                                ScholiumMotion.disclosure(
                                    reduceMotion: reduceMotion || !animates || windowState == .inactive)
                            ) { image in
                                image.rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                            }
                            .opacity(isHovered || isFocused ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .scholiumContentControlInk(
                        resting: .secondaryText,
                        emphasized: .accent
                    )
                }
                .buttonStyle(
                    ScholiumContentControlButtonStyle(
                        isFocused: isFocused,
                        isHovering: isHovered,
                        in: RoundedRectangle(
                            cornerRadius: ScholiumShape.editorialControlCornerRadius,
                            style: .continuous
                        )
                    )
                )
                .scholiumActivationPointer()
                .focused($isFocused)
                .accessibilityValue(
                    configuration.isExpanded ? String(localized: "Expanded") : String(localized: "Collapsed"))
                if configuration.isExpanded { configuration.content }
            }
            .scholiumHoverState { isHovered = $0 }
        }
    }
}

extension Image {
    func chatAccessory() -> some View {
        imageScale(.small).foregroundStyle(.secondary).frame(width: 20, height: 20)
    }
}
