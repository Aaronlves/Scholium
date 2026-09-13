import SwiftUI

/// A quiet activity row. Disclosure owns local visibility, never a transcript animation.
struct AgentChatDisclosureStyle: DisclosureGroupStyle {
    var animates = true
    var symbol: String? = nil

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, animates: animates, symbol: symbol)
    }

    private struct Content: View {
        let configuration: DisclosureGroupStyleConfiguration
        let animates: Bool
        let symbol: String?
        @State private var isHovered = false
        @State private var hasOpened = false
        @FocusState private var isFocused: Bool

        private var showsChevron: Bool { symbol == nil || configuration.isExpanded || isHovered || isFocused }
        private var indicatorWidth: CGFloat { ScholiumGrid.Dimension.iconTrackWidth }
        private var contentInset: CGFloat { indicatorWidth + ScholiumGrid.Spacing.labelAccessoryGap }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    // A withAnimation here also animates the following WKWebView's
                    // frame and the composer's inset. Only the indicator owns motion.
                    withTransaction(Transaction(animation: nil)) {
                        configuration.isExpanded.toggle()
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                        ZStack {
                            if let symbol {
                                Image(systemName: symbol).opacity(showsChevron ? 0 : 1)
                            }
                            ScholiumSidebarDisclosureIndicator(isExpanded: configuration.isExpanded, animates: animates)
                                .opacity(showsChevron ? 1 : 0)
                        }
                        .font(.caption)
                        .foregroundStyle(isHovered || isFocused ? .primary : .secondary)
                        .frame(width: indicatorWidth)
                        .accessibilityHidden(true)
                        configuration.label
                    }
                    .frame(maxWidth: .infinity, minHeight: ScholiumGrid.Dimension.preferredCustomTarget, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .tint(.primary)
                .scholiumActivationPointer()
                .focused($isFocused)
                .scholiumHoverState { isHovered = $0 }
                .accessibilityValue(configuration.isExpanded ? String(localized: "Expanded") : String(localized: "Collapsed"))

                // Mount lazily, then retain the already measured content and its
                // native readers. Collapsing must not destroy/reload WebKit pages.
                if hasOpened || configuration.isExpanded {
                    configuration.content
                        .padding(.top, ScholiumGrid.Spacing.labelAccessoryGap)
                        .padding(.leading, contentInset)
                        .overlay(alignment: .leading) {
                            HStack(spacing: 0) {
                                Divider()
                                Spacer(minLength: 0)
                            }
                            .padding(.leading, indicatorWidth / 2)
                            .allowsHitTesting(false).accessibilityHidden(true)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(height: configuration.isExpanded ? nil : 0, alignment: .top)
                        .clipped()
                        .opacity(configuration.isExpanded ? 1 : 0)
                        .disabled(!configuration.isExpanded)
                        .allowsHitTesting(configuration.isExpanded)
                        .accessibilityHidden(!configuration.isExpanded)
                }
            }
            .onChange(of: configuration.isExpanded, initial: true) { _, expanded in
                if expanded { hasOpened = true }
            }
        }
    }
}
