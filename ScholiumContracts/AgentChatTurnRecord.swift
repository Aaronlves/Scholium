import Foundation

/// Runtime-reported wall time, including waits. Never model thinking time.
public struct AgentChatTurnTiming: Codable, Equatable, Sendable {
  public let startedAt: Date?
  public let completedAt: Date?
  public let durationMilliseconds: Int?

  public init(startedAt: Date? = nil, completedAt: Date? = nil, durationMilliseconds: Int? = nil) {
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.durationMilliseconds = durationMilliseconds
  }

  public var completedSeconds: Int? {
    if let durationMilliseconds, durationMilliseconds >= 0 { return durationMilliseconds / 1_000 }
    guard let startedAt, let completedAt, completedAt >= startedAt else { return nil }
    return Int(exactly: completedAt.timeIntervalSince(startedAt).rounded(.down))
  }
}

/// Retained public lifecycle, shared by live delivery and history restoration.
public struct AgentChatTurnRecord: Codable, Equatable, Sendable {
  public let status: AgentChatTranscript.Turn.Status
  public let timing: AgentChatTurnTiming

  public init(status: AgentChatTranscript.Turn.Status, timing: AgentChatTurnTiming = .init()) {
    self.status = status; self.timing = timing
  }

  public func merging(_ incoming: Self) -> Self {
    // A delayed start acknowledgement cannot revive a completed turn.
    guard status == .inProgress || incoming.status != .inProgress else { return self }
    return .init(status: incoming.status, timing: .init(
      startedAt: incoming.timing.startedAt ?? timing.startedAt,
      completedAt: incoming.timing.completedAt ?? timing.completedAt,
      durationMilliseconds: incoming.timing.durationMilliseconds ?? timing.durationMilliseconds))
  }
}
