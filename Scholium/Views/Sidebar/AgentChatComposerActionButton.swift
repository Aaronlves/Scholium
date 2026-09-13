import SwiftUI

/// Presentation only; admission and interruption remain controller-owned.
enum AgentChatComposerAction: Equatable {
    case send, sendNow, queue, stop, stopping

    init(state: AgentChatController.State, canSend: Bool, queuesInput: Bool) {
        switch state {
        case .stopping: self = .stopping
        case .compacting: self = .stop
        case .working: self = canSend ? (queuesInput ? .queue : .sendNow) : .stop
        default: self = .send
        }
    }

    var isInterruption: Bool { self == .stop || self == .stopping }
    var symbol: String {
        switch self {
        case .send, .sendNow: "arrow.up"
        case .queue: "text.badge.plus"
        case .stop: "stop.fill"
        case .stopping: "ellipsis"
        }
    }
    var label: String {
        switch self {
        case .send: String(localized: "Send", bundle: .module)
        case .sendNow: String(localized: "Send Now", bundle: .module)
        case .queue: String(localized: "Queue for Next Turn", bundle: .module)
        case .stop: String(localized: "Stop", bundle: .module)
        case .stopping: String(localized: "Stopping…", bundle: .module)
        }
    }
}

struct AgentChatComposerActionButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: AgentChatController.State
    let canSend: Bool
    let queuesInput: Bool
    let submit: () -> Void
    let stop: () -> Void

    var body: some View {
        let action = AgentChatComposerAction(state: state, canSend: canSend, queuesInput: queuesInput)
        Button {
            if action == .stop { stop() }
            else if !action.isInterruption { submit() }
        } label: {
            Image(systemName: action.symbol)
                .contentTransition(ScholiumMotion.symbolReplacementContentTransition(reduceMotion: reduceMotion))
        }
        .animation(ScholiumMotion.symbolReplacement(reduceMotion: reduceMotion), value: action)
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .controlSize(.regular)
        // Command-Return always means delivery, never interruption.
        .keyboardShortcut(action.isInterruption ? nil : KeyboardShortcut(.return, modifiers: .command))
        .disabled(action == .stopping || (!action.isInterruption && !canSend))
        .help(state == .disconnected ? String(localized: "Connect an agent before sending.", bundle: .module) : action.label)
        .accessibilityLabel(action.label)
        .accessibilityIdentifier("scholium.chat.primaryAction")
    }
}
