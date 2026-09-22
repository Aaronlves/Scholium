import ScholiumContracts
import SwiftUI
import ThinkingOrbs

/// A small visual vocabulary for observed public Agent activity. It is a
/// presentation mapping, not an execution state or an inference about private
/// reasoning.
enum AgentChatActivityOrbStyle: Equatable, Sendable {
    case breathing
    case working
    case searching
    case connecting
    case weaving
    case composing

    var design: OrbDesign {
        switch self {
        case .breathing: .breathing
        case .working: .working
        case .searching: .searching
        case .connecting: .connecting
        case .weaving: .weaving
        case .composing: .composing
        }
    }

    /// Only a confirmed running activity receives a moving design. Waiting,
    /// terminal and uncertain outcomes remain represented by their native text
    /// and symbols.
    static func style(for activity: AgentChatActivity) -> Self? {
        guard activity.status == .running else { return nil }

        if let action = activity.commandAction {
            switch action.kind {
            case .read: return .working
            case .search, .listFiles: return .searching
            }
        }

        switch activity.kind {
        case .search, .webSearch:
            return .searching
        case .tool:
            return .connecting
        case .delegation:
            return .weaving
        case .create, .update:
            return .composing
        case .compaction:
            return .breathing
        case .read, .readAttachment, .trash, .command, .files:
            return .working
        }
    }
}

struct AgentChatActivityOrb: View {
    let style: AgentChatActivityOrbStyle
    let animates: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.controlActiveState) private var activeState

    private var isPaused: Bool {
        !animates || !isEnabled || reduceMotion || contrast == .increased || activeState == .inactive
    }

    var body: some View {
        ThinkingOrb(
            style.design,
            size: .small,
            diameter: ScholiumGrid.Dimension.iconTrackWidth,
            isPaused: isPaused
        )
        .id(style)
        .transition(shouldAnimateStyle ? .opacity : .identity)
        .animation(shouldAnimateStyle ? .easeInOut(duration: 0.18) : nil, value: style)
        .accessibilityHidden(true)
    }

    private var shouldAnimateStyle: Bool {
        animates && !reduceMotion && contrast != .increased && activeState != .inactive
    }
}
