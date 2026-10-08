import SwiftUI

/// Presentation only; admission and interruption remain controller-owned.
enum AgentChatComposerAction: Equatable {
    case send, steer, queue, stop, stopping

    init(state: AgentChatController.State, hasInput: Bool, queuesInput: Bool) {
        switch state {
        case .stopping: self = .stopping
        case .compacting: self = .stop
        case .working: self = hasInput ? (queuesInput ? .queue : .steer) : .stop
        default: self = .send
        }
    }

    var isDelivery: Bool { self == .send || self == .steer || self == .queue }

    var symbol: String {
        switch self {
        case .send, .steer: "arrow.up.circle.fill"
        case .queue: "plus.circle.fill"
        case .stop: "stop.circle.fill"
        case .stopping: "ellipsis.circle.fill"
        }
    }
    var label: String {
        switch self {
        case .send: String(localized: "Send", bundle: .module)
        case .steer: String(localized: "Add to Current Turn", bundle: .module)
        case .queue: String(localized: "Queue for Next Turn", bundle: .module)
        case .stop: String(localized: "Stop", bundle: .module)
        case .stopping: String(localized: "Stopping…", bundle: .module)
        }
    }

    func isEnabled(canSend: Bool) -> Bool {
        switch self {
        case .send, .steer, .queue: canSend
        case .stop: true
        case .stopping: false
        }
    }
}

struct AgentChatComposerActionButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: AgentChatController.State
    let hasInput: Bool
    let canSend: Bool
    let queuesInput: Bool
    let submit: () -> Void
    let stop: () -> Void

    var body: some View {
        let action = AgentChatComposerAction(state: state, hasInput: hasInput, queuesInput: queuesInput)
        if action.isDelivery {
            primaryButton(for: action)
                .keyboardShortcut(.return, modifiers: .command)
        } else {
            primaryButton(for: action)
        }
    }

    private func primaryButton(for action: AgentChatComposerAction) -> some View {
        Button(action: { perform(action) }) {
            AgentChatComposerIcon(content: .action(action.symbol))
                .contentTransition(ScholiumMotion.symbolReplacementContentTransition(reduceMotion: reduceMotion))
                .agentChatComposerControl()
        }
        .buttonStyle(ScholiumContentActionButtonStyle())
        .agentChatComposerControl()
        .disabled(!action.isEnabled(canSend: canSend))
        .help(help(for: action))
        .accessibilityLabel(action.label)
        .accessibilityIdentifier("scholium.chat.primaryAction")
    }

    private func perform(_ action: AgentChatComposerAction) {
        switch action {
        case .send, .steer, .queue: submit()
        case .stop: stop()
        case .stopping: break
        }
    }

    private func help(for action: AgentChatComposerAction) -> String {
        if action == .send, state == .disconnected {
            return String(localized: "Connect an agent before sending.", bundle: .module)
        }
        return action.label
    }
}

/// The window's native command owns interruption even while a question or
/// permission form replaces the composer. Both routes call the same controller.
struct AgentChatStopCommand: View {
    @ObservedObject var controller: AgentChatController

    var body: some View {
        Button("Stop Agent", action: controller.stop)
            .keyboardShortcut(".", modifiers: .command)
            .disabled(controller.state != .working && controller.state != .compacting && !controller.canRetryStop)
    }
}
