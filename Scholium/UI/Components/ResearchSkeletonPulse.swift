import SwiftUI

/// Shared loading treatment for initial placeholders and retained result rows.
struct ResearchSkeletonPulse: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.phaseAnimator(isActive && !reduceMotion ? [false, true] : [false]) { content, phase in
            content.opacity(isActive ? (phase ? 0.45 : 0.9) : 1)
        } animation: { _ in
            isActive && !reduceMotion ? .easeInOut(duration: 1.1) : nil
        }
    }
}
