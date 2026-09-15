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
    let submitAlternate: () -> Void
    let stop: () -> Void

    var body: some View {
        let action = AgentChatComposerAction(state: state, canSend: canSend, queuesInput: queuesInput)
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            if !action.isInterruption {
                Button(action: submit) { Image(systemName: action.symbol) }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.circle)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canSend)
                    .help(state == .disconnected ? String(localized: "Connect an agent before sending.", bundle: .module) : action.label)
                    .accessibilityLabel(action.label)
                    .accessibilityIdentifier("scholium.chat.primaryAction")
                if state == .working {
                    Menu {
                        Button(action.label, action: submit)
                        Button((queuesInput ? AgentChatComposerAction.sendNow : .queue).label, action: submitAlternate)
                    } label: {
                        Image(systemName: "chevron.down")
                            .accessibilityLabel("Send Options")
                            .frame(minWidth: ScholiumGrid.Dimension.preferredCustomTarget, minHeight: ScholiumGrid.Dimension.preferredCustomTarget)
                    }
                    .scholiumContentActionMenu().menuIndicator(.hidden)
                    .disabled(!canSend)
                    .help("Send Options").accessibilityLabel("Send Options")
                    .accessibilityIdentifier("scholium.chat.sendOptions")
                }
            }
            if state == .working || action.isInterruption {
                let interruption: AgentChatComposerAction = state == .stopping ? .stopping : .stop
                Button(action: stop) {
                    Image(systemName: interruption.symbol)
                        .contentTransition(ScholiumMotion.symbolReplacementContentTransition(reduceMotion: reduceMotion))
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.circle)
                .disabled(state == .stopping)
                .help(interruption.label).accessibilityLabel(interruption.label)
                .accessibilityIdentifier("scholium.chat.stop")
            }
        }
        .controlSize(.regular)
    }
}

/// The window's native command owns interruption even while a question or
/// permission form replaces the composer. Both routes call the same controller.
struct AgentChatStopCommand: View {
    @ObservedObject var controller: AgentChatController

    var body: some View {
        Button("Stop Agent", action: controller.stop)
            .keyboardShortcut(".", modifiers: .command)
            .disabled(controller.state != .working && controller.state != .compacting)
    }
}
