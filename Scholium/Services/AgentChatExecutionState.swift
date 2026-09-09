import Foundation
import ScholiumApplication
import ScholiumContracts

/// Ephemeral state of one conversation on one connection. No UI selection or source ownership.
@MainActor
struct AgentChatExecutionState {
  var state: AgentChatController.State = .ready
  var sendingMessageID: String?
  var isSending: Bool { sendingMessageID != nil }
  var isRefreshingHistory = false
  var error: String?
  var turnID: String?
  var routeToken: UUID?
  var admissionID: UUID?
  var displayScope: AgentChatDisplayScope?
  var completedTurns: Set<String> = []
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
