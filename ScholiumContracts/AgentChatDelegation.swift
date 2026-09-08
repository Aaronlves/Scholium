import Foundation

/// A public runtime observation at one point in history, never child admission.
public struct AgentChatDelegation: Codable, Equatable, Sendable {
  public enum Operation: String, Codable, Sendable {
    case spawnAgent, sendInput, resumeAgent, wait, closeAgent, sendMessage
    case followupTask, interruptAgent, listAgents
    case started, interacted, interrupted, completed
  }
  public enum State: String, Codable, Sendable {
    case pendingInit, running, interrupted, completed, errored, shutdown, notFound
  }
  public struct Target: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let path: String?
    public let state: State?
    public let message: String?
    public init(id: String, path: String? = nil, state: State?, message: String? = nil) {
      self.id = id; self.path = path; self.state = state; self.message = message
    }
  }
  public let operation: Operation
  public let senderThreadID: String
  public let prompt: String?
  public let targets: [Target]
  public init(operation: Operation, senderThreadID: String, prompt: String?, targets: [Target]) {
    self.operation = operation; self.senderThreadID = senderThreadID
    self.prompt = prompt; self.targets = targets
  }
}
