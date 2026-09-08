import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Delegated work observations", .serialized) @MainActor
struct AgentChatDelegationTests {
  private var repository: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  }
  private func wait(_ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while !predicate() {
      try #require(ContinuousClock.now < deadline, "Delegation fixture did not reach its expected state")
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  @Test("Delegation stays attributed through concurrent navigation, Stop, storage and branching")
  func continuity() async throws {
    let root = repository.appendingPathComponent(".build/agent-chat-tests/delegation-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = AgentChatController(triptychID: UUID(), root: root) { request in
      try! .init(requestID: request.requestID, result: .object([:]))
    }
    try await wait { controller.isLoaded }
    let executable = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
    controller.connect(executable: executable, home: controller.runtimeHome, cli: executable)
    try await wait { controller.account != nil && controller.state == .ready }
    controller.editDraft("hold delegation"); controller.send()
    try await wait { controller.selected?.messages.filter { $0.activity?.delegation != nil }.count == 2 }
    let source = try #require(controller.selectedID)
    let record = try #require(controller.selected?.messages.first { $0.activity?.delegation?.operation == .spawnAgent })
    let report = try #require(record.activity?.delegation)
    #expect(record.activity?.status == .completed && report.targets.first?.state == .running)
    #expect(report.senderThreadID == controller.selected?.threadID && record.changeID == nil)
    #expect(controller.approvals.isEmpty)
    #expect(AgentChatSearch.passage(in: record, query: "第二处")?.contains("尚无直接支持") == true)
    controller.newConversation()
    controller.editDraft("capabilities"); controller.send()
    try await wait { !controller.isBusy && controller.selected?.pendingMessageID == nil }
    #expect(controller.selected?.messages.contains { $0.activity?.delegation != nil } == false)
    controller.select(source); controller.stop()
    try await wait { !controller.isBusy }
    #expect(controller.selected?.messages.first { $0.id == record.id }?.activity?.delegation == report)
    let turn = try #require(controller.branchPoints.first?.turnID)
    controller.branch(through: turn)
    try await wait { !controller.isBusy && controller.selectedID != source }
    #expect(controller.selected?.messages.first { $0.id == record.id }?.activity?.delegation == report)
    try await controller.flushPersistence()
    let selected = controller.selectedID
    await controller.disconnect()
    let reopened = AgentChatController(triptychID: controller.triptychID, root: root) { request in
      try! .init(requestID: request.requestID, result: .object([:]))
    }
    try await wait { reopened.isLoaded }
    reopened.select(try #require(selected))
    #expect(reopened.selected?.messages.first { $0.id == record.id }?.activity?.delegation == report)
    #expect(reopened.approvals.isEmpty && !reopened.isBusy)
    reopened.connect(executable: executable, home: reopened.runtimeHome, cli: executable)
    try await wait { reopened.account != nil && reopened.state == .ready }
    reopened.editDraft("continue branch"); reopened.send()
    try await wait { !reopened.isBusy && reopened.selected?.pendingMessageID == nil }
    #expect(reopened.selected?.messages.first { $0.id == record.id }?.activity?.delegation == report)
    #expect(reopened.selected?.messages.first { $0.activity?.delegation?.operation == .interacted }?
      .activity?.delegation?.senderThreadID == report.senderThreadID)
    await reopened.disconnect()
  }

  @Test("Unreadable delegation is visible without inventing a result or file receipt")
  func unreadable() throws {
    let activity = try #require(AgentChatActivityProjection.withLocalizedFailure(CodexChatActivity.parse([
      "type": .string("collabAgentToolCall"), "status": .string("completed")], completed: true, threadID: "parent")))
    #expect(activity.status == .uncertain && activity.delegation == nil && !activity.detail.isEmpty)
    #expect(activity.files.isEmpty && !activity.kind.isMutation)
  }
}
