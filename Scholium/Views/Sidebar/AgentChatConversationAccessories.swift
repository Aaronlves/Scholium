import SwiftUI

/// Accessory geometry constrains only the input area. Its measured height must
/// not invalidate the transcript's projection or its already mounted readers.
struct AgentChatConversationBottomArea<Accessories: View, Input: View>: View {
    let viewportHeight: CGFloat
    @ViewBuilder let accessories: () -> Accessories
    @ViewBuilder let input: (CGFloat) -> Input
    @State private var accessoryHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            accessories()
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    accessoryHeight = $0
                }
            input(max(0, viewportHeight - accessoryHeight))
        }
    }
}

/// Distance changes belong to this small floating surface. Keep native controls
/// mounted across that threshold rather than rebuilding the transcript or dock.
struct AgentChatConversationAccessories<Activity: View>: View {
    let readingSession: AgentChatReadingSession
    let hasActivity: Bool
    let latest: () -> Void
    @ViewBuilder let activity: () -> Activity

    private var showsLatest: Bool { readingSession.isAwayFromLatest || readingSession.history.last != nil }
    private var reservesNavigation: Bool { readingSession.history.last != nil }

    var body: some View {
        AgentChatConversationAccessoryLayout(hasActivity: hasActivity, showsLatest: showsLatest, reservesNavigation: reservesNavigation) {
            activity()
            navigation(shown: showsLatest)
        }
        .padding(.bottom, hasActivity || reservesNavigation ? ScholiumSidebarLayout.itemSpacing : 0)
    }

    private func navigation(shown: Bool) -> some View {
        Button(action: latest) {
            ScholiumSidebarIcon(systemImage: ScholiumSidebarAction.later.symbol, placement: .action)
        }
        .scholiumIconControl()
        .help("Latest Reply").accessibilityLabel("Latest Reply")
        .accessibilityIdentifier("scholium.chat.latest")
        .opacity(shown ? 1 : 0)
        .disabled(!shown)
        .allowsHitTesting(shown)
        .accessibilityHidden(!shown)
    }
}

/// Reserve only persistent activity controls. Latest is a floating navigation
/// affordance: its visibility changes placement, never transcript geometry.
/// One layout also retains each native control when a narrow row wraps.
private struct AgentChatConversationAccessoryLayout: Layout {
    let hasActivity: Bool
    let showsLatest: Bool
    let reservesNavigation: Bool
    private let gap = ScholiumSidebarLayout.itemSpacing

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        guard sizes.count == 2 else { return .zero }
        let naturalWidth = sizes[0].width + gap + sizes[1].width
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? naturalWidth
        let height: CGFloat
        if hasActivity && reservesNavigation && naturalWidth > width {
            height = sizes[0].height + gap + sizes[1].height
        } else {
            height = hasActivity || reservesNavigation ? max(sizes[0].height, sizes[1].height) : 0
        }
        return CGSize(
            width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let activity = subviews[0].sizeThatFits(.unspecified)
        let navigation = subviews[1].sizeThatFits(.unspecified)
        let fits = activity.width + gap + navigation.width <= bounds.width
        let inline = hasActivity && showsLatest && fits
        let navigationY =
            hasActivity || reservesNavigation
            ? (hasActivity && reservesNavigation && !fits ? bounds.maxY - navigation.height / 2 : bounds.midY)
            : bounds.minY - gap - navigation.height / 2
        let activityX = inline ? bounds.midX - (activity.width + gap + navigation.width) / 2 : bounds.midX - activity.width / 2
        let activityY =
            hasActivity && showsLatest && !fits
            ? navigationY - navigation.height / 2 - gap - activity.height / 2
            : bounds.midY
        subviews[0].place(at: CGPoint(x: activityX, y: activityY), anchor: .leading, proposal: .unspecified)
        let navigationX = inline ? activityX + activity.width + gap : bounds.midX - navigation.width / 2
        subviews[1].place(at: CGPoint(x: navigationX, y: navigationY), anchor: .leading, proposal: .unspecified)
    }
}
