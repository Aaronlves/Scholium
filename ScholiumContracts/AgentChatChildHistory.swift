import Foundation

/// Public child observations, with no runtime transport or authority.
public enum AgentChatChildHistory {
  public struct Metadata: Equatable, Sendable {
    public enum Status: String, Sendable { case notLoaded, idle, systemError, active }
    public let id: String
    public let parentID: String
    public let name: String?
    public let role: String?
    public let status: Status
    public let activeFlags: [String]
    public let isPaginated: Bool
    public init(
      id: String, parentID: String, name: String?, role: String?, status: Status, activeFlags: [String],
      isPaginated: Bool
    ) {
      self.id = id
      self.parentID = parentID
      self.name = name
      self.role = role
      self.status = status
      self.activeFlags = activeFlags
      self.isPaginated = isPaginated
    }
  }
  public struct Page: Equatable, Sendable {
    public let turns: [AgentChatTranscript.Turn]
    public let nextCursor: String?
    public init(turns: [AgentChatTranscript.Turn], nextCursor: String?) {
      self.turns = turns
      self.nextCursor = nextCursor
    }
  }
  public struct Snapshot: Equatable, Sendable {
    public let metadata: Metadata
    public var page: Page
    public init(metadata: Metadata, page: Page) {
      self.metadata = metadata
      self.page = page
    }
    public var activeTurnID: String? {
      let active = page.turns.filter { $0.status == .inProgress }
      return metadata.status == .active && active.count == 1 ? active[0].id : nil
    }
    public func confirmsEnd(of turnID: String) -> Bool {
      page.turns.contains { $0.id == turnID && $0.status != .inProgress }
    }

  }

}
