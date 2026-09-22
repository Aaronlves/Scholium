import SwiftUI

/// A quiet activity row. Disclosure owns local visibility, never a transcript animation.
struct AgentChatDisclosureStyle: DisclosureGroupStyle {
    var animates = true
    var symbol: String? = nil
    var orbStyle: AgentChatActivityOrbStyle? = nil
    var allowsLabelInteraction = false

    func makeBody(configuration: Configuration) -> some View {
        Content(
            configuration: configuration,
            animates: animates,
            symbol: symbol,
            orbStyle: orbStyle,
            allowsLabelInteraction: allowsLabelInteraction)
    }

    private struct Content: View {
        let configuration: DisclosureGroupStyleConfiguration
        let animates: Bool
        let symbol: String?
        let orbStyle: AgentChatActivityOrbStyle?
        let allowsLabelInteraction: Bool
        @State private var isHovered = false
        @State private var hasOpened = false
        @FocusState private var isFocused: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var effectiveAnimates: Bool { animates && !reduceMotion }

        private var showsChevron: Bool {
            (symbol == nil && orbStyle == nil) || configuration.isExpanded || isHovered || isFocused
        }
        private var indicatorWidth: CGFloat { ScholiumGrid.Dimension.iconTrackWidth }
        private var contentInset: CGFloat { indicatorWidth + ScholiumGrid.Spacing.labelAccessoryGap }

        private var indicator: some View {
            ZStack {
                if let orbStyle {
                    AgentChatActivityOrb(style: orbStyle, animates: effectiveAnimates)
                        .opacity(showsChevron ? 0 : 1)
                } else if let symbol {
                    Image(systemName: symbol).opacity(showsChevron ? 0 : 1)
                }
                ScholiumSidebarDisclosureIndicator(isExpanded: configuration.isExpanded, animates: effectiveAnimates)
                    .opacity(showsChevron ? 1 : 0)
            }
            .font(.caption)
            .foregroundStyle(isHovered || isFocused ? .primary : .secondary)
            .frame(width: indicatorWidth)
            .accessibilityHidden(true)
        }

        private var disclosureButton: some View {
            Button {
                // A withAnimation here also animates the following WKWebView's
                // frame and the composer's inset. Only the indicator owns motion.
                withTransaction(Transaction(animation: nil)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                indicator
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .tint(.primary)
            .scholiumActivationPointer()
            .focused($isFocused)
            .frame(width: indicatorWidth)
            .frame(minHeight: ScholiumGrid.Dimension.preferredCustomTarget)
            .accessibilityLabel(Text("Details", bundle: .module))
            .accessibilityValue(configuration.isExpanded ? String(localized: "Expanded") : String(localized: "Collapsed"))
        }

        @ViewBuilder
        private var header: some View {
            if allowsLabelInteraction {
                HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    disclosureButton
                    configuration.label
                }
                .frame(maxWidth: .infinity, minHeight: ScholiumGrid.Dimension.preferredCustomTarget, alignment: .leading)
                .scholiumHoverState { isHovered = $0 }
            } else {
                Button {
                    // A withAnimation here also animates the following WKWebView's
                    // frame and the composer's inset. Only the indicator owns motion.
                    withTransaction(Transaction(animation: nil)) {
                        configuration.isExpanded.toggle()
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                        indicator
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
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                header

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
                        // DisclosureGroup does not provide a reliable vertical
                        // proposal for nested retained readers. Give the mounted
                        // process its intrinsic height so the outer transcript
                        // owns one stable scroll geometry.
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
