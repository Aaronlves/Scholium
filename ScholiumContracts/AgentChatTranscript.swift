import Foundation

/// Public runtime observations. These values grant no execution or source authority.
public enum AgentChatTranscript {
  public struct Item: Equatable, Sendable {
    public enum Content: Equatable, Sendable {
      case assistant(text: String, phase: AgentChatMessage.Phase?)
      case user(text: String, hasAdditionalMaterial: Bool)
      case activity(AgentChatActivity)
    }
    public let id: String
    public let content: Content
    public let clientMessageID: String?
    public let isManagedTool: Bool
    public init(id: String, content: Content, clientMessageID: String? = nil, isManagedTool: Bool = false) {
      self.id = id; self.content = content
      self.clientMessageID = clientMessageID; self.isManagedTool = isManagedTool
    }
  }

  public struct Turn: Equatable, Sendable {
    public enum Status: String, Sendable {
      case inProgress, completed, interrupted, failed
      public var runStatus: AgentChatActivity.Status {
        switch self {
        case .inProgress: .running
        case .completed: .completed
        case .interrupted: .interrupted
        case .failed: .failed
        }
      }
    }
    public let id: String
    public let status: Status
    public enum Items: Equatable, Sendable {
      case full([Item])
      case references(Set<String>)
      case notLoaded
    }
    public let itemContent: Items
    public let error: String?
    public var items: [Item] {
      if case .full(let items) = itemContent { return items }
      return []
    }
    public init(id: String, status: Status, items: Items, error: String? = nil) {
      self.id = id; self.status = status; self.itemContent = items; self.error = error
    }
    public var messageIDs: Set<String> {
      let ids: Set<String>
      switch itemContent {
      case .full(let items):
        ids = Set(items.flatMap { [$0.id, "runtime:\($0.id)"] + ($0.clientMessageID.map { [$0] } ?? []) })
      case .references(let references): ids = references
      case .notLoaded: ids = []
      }
      return ids.union(["plan:\(id)"])
    }
  }
}
