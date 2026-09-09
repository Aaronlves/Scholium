import SwiftUI

/// A decorative text treatment. Execution identity and state stay with the caller.
struct AgentChatActivityText: View {
  let text: String
  let isCurrent: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.controlActiveState) private var windowState
  @State private var began: Date?

  private var animates: Bool { isCurrent && !reduceMotion && contrast != .increased && windowState != .inactive }

  var body: some View {
    Text(verbatim: text)
      .foregroundStyle(contrast == .increased ? .primary : .secondary)
      .overlay {
        if animates, let began {
          TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let elapsed = context.date.timeIntervalSince(began) - 0.6
            let phase = elapsed.truncatingRemainder(dividingBy: 4)
            GeometryReader { geometry in
              // Both endpoints remain semantic label colors; the base text never disappears.
              LinearGradient(colors: [.clear, Color.primary, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: max(32, geometry.size.width * 0.45))
                .offset(x: -geometry.size.width * 0.45 + geometry.size.width * 1.45 * min(1, max(0, phase)))
                .opacity(elapsed >= 0 && phase <= 1 ? 1 : 0)
            }
            .mask(Text(verbatim: text).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
          }
          .allowsHitTesting(false).accessibilityHidden(true)
        }
      }
      .onChange(of: animates, initial: true) { _, active in began = active ? Date() : nil }
  }
}
