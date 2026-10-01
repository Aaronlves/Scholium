import Foundation
import ScholiumApplication
import ScholiumContracts

/// Current operation consequences, separate from the retained technical error.
enum AgentChatExecutionRecovery: Equatable {
    case turnEnded, messageNotSent, deliveryUnconfirmed, historyRefreshFailed, queuedInputBlocked

    var title: String {
        switch self {
        case .turnEnded: ScholiumL10n.string("Input Preserved")
        case .messageNotSent: ScholiumL10n.string("Message Not Sent")
        case .deliveryUnconfirmed: ScholiumL10n.string("Delivery Not Confirmed")
        case .historyRefreshFailed: ScholiumL10n.string("History Could Not Be Updated")
        case .queuedInputBlocked: ScholiumL10n.string("Queued Message Needs Attention")
        }
    }

    var explanation: String {
        switch self {
        case .turnEnded: ScholiumL10n.string("The previous turn ended. Your input is preserved; send it as a new request.")
        case .messageNotSent: ScholiumL10n.string("Your input is preserved. Review it before sending again.")
        case .deliveryUnconfirmed: ScholiumL10n.string("Review the conversation before continuing. The unconfirmed message will not be sent again.")
        case .historyRefreshFailed: ScholiumL10n.string("The saved conversation and draft remain available. Retry updating its runtime history.")
        case .queuedInputBlocked: ScholiumL10n.string("The next queued message is retained. Resolve its sending issue or remove it from the queue.")
        }
    }
}

/// Ephemeral state of one conversation on one connection. No UI selection or source ownership.
@MainActor
struct AgentChatExecutionState {
    var state: AgentChatController.State = .ready
    var sendingMessageID: String?
    var isSending: Bool { sendingMessageID != nil }
    var isRefreshingHistory = false
    var historyUnavailable = false
    var error: String? {
        didSet { recovery = nil }
    }
    var recovery: AgentChatExecutionRecovery?

    mutating func report(_ recovery: AgentChatExecutionRecovery, detail: String) {
        error = detail
        self.recovery = recovery
    }
    var turnID: String?
    var routeToken: UUID?
    var admissionID: UUID?
    var displayScope: AgentChatDisplayScope?
    /// Permission captured when the current turn is admitted. Conversation
    /// settings may be changed by an in-turn capability call, but those changes
    /// apply to the next turn only.
    var permission: AgentChatPermission = .ask
    var completedTurns: Set<String> = []
    /// A matching normal completion may advance the queue once delivery settles.
    /// Stop and connection replacement revoke this permission.
    var pendingQueueAdvanceTurnID: String?
    var automaticallyAdvancesQueue = false
    /// Notification validity only; public run state retains its existing owner.
    var notificationTurnID: String?
    var runtimeItems: [String: CodexChatOperationContext] = [:]
    var configuration: [String: MCPJSONValue] = [:]
    var interruptRequestedTurnID: String?
    var approvals: [AgentChatApproval] = []
    var questionAnswers: [UUID: [String: AgentChatQuestionAnswer]] = [:]
    var replies: [UUID: (AgentChatInteractionReply) -> Void] = [:]
    var operationTask: Task<Void, Never>?
    var historyTask: Task<Void, Never>?
    var interruptTask: Task<Void, Never>?

    var isBusy: Bool {
        state != .ready || isSending || isRefreshingHistory
    }
}
