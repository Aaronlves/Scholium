import SwiftUI

/// A one-shot presentation on an inserted message. It never animates row
/// geometry or keys its lifetime to streamed text or execution status.
struct AgentChatMessageArrival: ViewModifier {
    let enabled: Bool
    var waitsForContent = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.controlActiveState) private var windowState
    @State private var appeared = false

    private var animates: Bool {
        enabled && !reduceMotion && contrast != .increased && windowState != .inactive
    }

    func body(content: Content) -> some View {
        content
            .animation(ScholiumMotion.chatMessageArrival(reduceMotion: !animates)) { view in
                view.opacity(animates && !appeared ? 0 : 1)
            }
            .onAppear { if !waitsForContent { appeared = true } }
            .onPreferenceChange(AgentChatReplyReadyPreference.self) { ready in
                // Later streaming revisions never reset the one-shot reveal.
                if ready { appeared = true }
            }
    }
}

/// Readiness is projected from the existing reader, never timed or guessed.
struct AgentChatReplyReadyPreference: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
