import SwiftUI

/// One-way size proposals from the input-area owner. These limits change local
/// scrolling, never the identity or retained state of a draft or request.
struct AgentChatInputAreaLimits: Equatable {
    var maximumHeight: CGFloat?
    var reservedTranscriptHeight: CGFloat?
    var queueMaximumHeight: CGFloat?
    var requestMaximumHeight: CGFloat?
    var preparationMaximumHeight: CGFloat?
    var editorMaximumHeight: CGFloat?

    static let unconstrained = AgentChatInputAreaLimits()

    static func fitting(
        viewportHeight: CGFloat?, hasQueue: Bool, hasPreparedContent: Bool,
        hasFooterStatus: Bool, lineHeight: CGFloat
    ) -> Self {
        guard let viewportHeight, viewportHeight.isFinite else { return .unconstrained }
        let availableHeight = max(0, viewportHeight)
        let lineHeight = max(1, lineHeight)
        let target = ScholiumGrid.Dimension.preferredCustomTarget
        let gap = ScholiumSidebarLayout.itemSpacing
        let minimumEditor = max(40, lineHeight + 12)
        let scrollPadding = 2 * ScholiumSidebarLayout.textSpacing
        let minimumPreparation = hasPreparedContent ? max(target, lineHeight) + scrollPadding : 0
        // The measured safe-area inset still owns the actual result. Reserve
        // the existing padding and control rows before proposing scroll sizes.
        let chrome = 2 * ScholiumSidebarLayout.edgeInset + 2 * ScholiumSidebarLayout.rowInset
            + target + 2 * gap + (hasFooterStatus ? lineHeight + gap : 0)
        let queueChrome = hasQueue ? target + 12 + gap : 0
        let minimumQueue = hasQueue ? target + scrollPadding : 0
        let minimumHeight = chrome + queueChrome + minimumQueue + minimumEditor + minimumPreparation
        let readingHeight = max(6 * lineHeight, availableHeight * 0.4)
        let maximumHeight = max(minimumHeight, availableHeight - readingHeight)
        let contentHeight = max(0, maximumHeight - chrome - queueChrome)
        let extraHeight = max(0, contentHeight - minimumQueue - minimumEditor - minimumPreparation)
        let queueHeight = hasQueue ? min(144, minimumQueue + extraHeight * 0.25) : 0
        let inputHeight = max(minimumEditor + minimumPreparation, contentHeight - queueHeight)
        let editorHeight = min(
            7 * lineHeight + 12,
            hasPreparedContent ? max(minimumEditor, inputHeight * 0.55) : inputHeight)
        return Self(
            maximumHeight: maximumHeight,
            reservedTranscriptHeight: max(0, availableHeight - maximumHeight),
            queueMaximumHeight: hasQueue ? queueHeight : nil,
            // Approvals may reflow their action row. Keep that extra native
            // control row outside the scrolling request body.
            requestMaximumHeight: max(target, min(240, contentHeight - queueHeight - target)),
            preparationMaximumHeight: hasPreparedContent ? max(minimumPreparation, inputHeight - editorHeight) : nil,
            editorMaximumHeight: editorHeight)
    }
}

private struct AgentChatInputAreaLimitsKey: EnvironmentKey {
    static let defaultValue = AgentChatInputAreaLimits.unconstrained
}

private struct AgentChatContentMaximumHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var agentChatInputAreaLimits: AgentChatInputAreaLimits {
        get { self[AgentChatInputAreaLimitsKey.self] }
        set { self[AgentChatInputAreaLimitsKey.self] = newValue }
    }

    var agentChatContentMaximumHeight: CGFloat? {
        get { self[AgentChatContentMaximumHeightKey.self] }
        set { self[AgentChatContentMaximumHeightKey.self] = newValue }
    }
}

/// Owns bottom-area geometry; queue content, request disclosure and native input
/// keep their existing state owners. Only the queue's empty margin overlaps.
struct AgentChatInputArea<Queue: View, Input: View, Candidates: View>: View {
    let hasQueue: Bool
    var viewportHeight: CGFloat? = nil
    var hasPreparedContent = false
    var hasFooterStatus = false
    @ViewBuilder let queue: () -> Queue
    @ViewBuilder let input: () -> Input
    @ViewBuilder let candidates: () -> Candidates

    private let queueOverlap: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var lineHeight = ScholiumChatAppearance.messageLoadingHeight

    private var limits: AgentChatInputAreaLimits {
        .fitting(
            viewportHeight: viewportHeight, hasQueue: hasQueue,
            hasPreparedContent: hasPreparedContent, hasFooterStatus: hasFooterStatus,
            lineHeight: lineHeight)
    }

    var body: some View {
        AgentChatInputAreaLayout(overlap: queueOverlap) {
            if hasQueue {
                queue()
                    .environment(\.agentChatContentMaximumHeight, limits.queueMaximumHeight)
                    .padding(.bottom, queueOverlap)
                    .scholiumFloatingSurface(in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 8)
            }
            input()
                .environment(\.agentChatContentMaximumHeight, limits.requestMaximumHeight)
        }
        .padding(ScholiumSidebarLayout.edgeInset)
        .environment(\.agentChatInputAreaLimits, limits)
        .overlay(alignment: .top) {
            candidates()
                .padding(.horizontal, ScholiumSidebarLayout.edgeInset)
                .alignmentGuide(.top) { $0[.bottom] }
        }
    }
}

/// Measures the complete input area for its transcript safe-area inset. The
/// optional back surface and front surface share one overlap calculation.
private struct AgentChatInputAreaLayout: Layout {
    let overlap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.init(width: proposal.width, height: nil)) }
        return CGSize(
            width: sizes.map(\.width).max() ?? 0,
            height: sizes.reduce(0) { $0 + $1.height } - (sizes.count > 1 ? overlap : 0)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let childProposal = ProposedViewSize(width: bounds.width, height: nil)
        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            if index > 0 { y -= overlap }
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: childProposal)
            y += subview.sizeThatFits(childProposal).height
        }
    }
}
