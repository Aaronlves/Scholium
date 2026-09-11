import SwiftUI

/// Native disclosure semantics with a trailing, progressively revealed accessory.
struct AgentChatDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration)
    }

    private struct Content: View {
        let configuration: DisclosureGroupStyleConfiguration
        @State private var isHovered = false
        @FocusState private var isFocused: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    configuration.isExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        configuration.label
                        Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                            .chatAccessory()
                            .opacity(isHovered || isFocused ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focused($isFocused)
                .accessibilityValue(configuration.isExpanded ? String(localized: "Expanded") : String(localized: "Collapsed"))
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
