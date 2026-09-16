import SwiftUI

/// Owns bottom-area geometry; queue content, request disclosure and native input
/// keep their existing state owners. Only the queue's empty margin overlaps.
struct AgentChatInputArea<Queue: View, Input: View, Candidates: View>: View {
    let hasQueue: Bool
    @ViewBuilder let queue: () -> Queue
    @ViewBuilder let input: () -> Input
    @ViewBuilder let candidates: () -> Candidates

    private let queueOverlap: CGFloat = 16

    var body: some View {
        AgentChatInputAreaLayout(overlap: queueOverlap) {
            if hasQueue {
                queue()
                    .padding(.bottom, queueOverlap)
                    .scholiumFloatingSurface(in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 8)
            }
            input()
        }
        .padding(ScholiumSidebarLayout.edgeInset)
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
