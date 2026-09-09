import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Quiet activity and context presentation")
struct AgentChatActivityRefinementTests {
  @Test("Compact tool groups preserve every item and public commentary boundary")
  func toolGrouping() {
    let first = AgentChatMessage(id: "a", role: .operation, text: "", activity: .init(kind: .search, source: .runtime))
    let second = AgentChatMessage(id: "b", role: .operation, text: "", activity: .init(kind: .read, source: .runtime))
    let commentary = AgentChatMessage(id: "c", role: .assistant, text: "已找到原文，继续核对。", phase: .commentary)
    let third = AgentChatMessage(id: "d", role: .operation, text: "", activity: .init(kind: .read, source: .runtime))
    let groups = AgentChatProcessSlice.collect([first, second, commentary, third])
    #expect(groups.map { $0.messages.map(\.id) } == [["a", "b"], ["c"], ["d"]])
    #expect(groups.map(\.isTools) == [true, false, true])
    #expect(AgentChatProcessSlice.collect([first, second]).first?.id == "a")
  }
  @Test("A completed operation keeps its object without a repeated Completed label")
  func summary() {
    let locale = Locale(identifier: "zh-Hans")
    var activity = AgentChatActivity(kind: .read, source: .scholium,
      files: [.init(path: "Topics/行动理由.md")])
    #expect(AgentChatActivityProjection.summary(activity, locale: locale) == "正在研读笔记 · 行动理由.md")
    activity.status = .completed
    #expect(AgentChatActivityProjection.summary(activity, locale: locale) == "已读取笔记 · 行动理由.md")
    let search = AgentChatActivity(kind: .search, source: .scholium, subject: "实践理性")
    #expect(AgentChatActivityProjection.subject(search) == "实践理性")
    var command = AgentChatActivity(kind: .command, source: .runtime, subject: "cat /private/raw")
    #expect(AgentChatActivityProjection.subject(command) == nil)
    command.commandAction = .init(kind: .read, target: "/guidance/SKILL.md")
    #expect(AgentChatActivityProjection.subject(command) == "SKILL.md")
  }

  @Test("Context occupancy uses the latest observation, never cumulative usage or guessed capacity")
  func context() {
    #expect(AgentChatContextPresentation.fraction(nil) == nil)
    #expect(AgentChatContextPresentation.fraction(.init(lastTurnTokens: 12, totalTokens: 9999, capacity: nil)) == nil)
    #expect(AgentChatContextPresentation.fraction(.init(lastTurnTokens: 12, totalTokens: 9999, capacity: 0)) == nil)
    #expect(AgentChatContextPresentation.fraction(.init(lastTurnTokens: 25, totalTokens: 9999, capacity: 100)) == 0.25)
    #expect(AgentChatContextPresentation.fraction(.init(lastTurnTokens: 101, totalTokens: 9999, capacity: 100)) == 1)
    #expect(AgentChatContextPresentation.fraction(.init(lastTurnTokens: 0, totalTokens: 0, capacity: 100)) == 0)
  }
}
