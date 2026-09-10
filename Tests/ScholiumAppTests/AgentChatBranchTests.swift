import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Native conversation branches", .serialized)
@MainActor
struct AgentChatBranchTests {
  private var repository: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  }
  private func wait(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while !condition() {
      try #require(ContinuousClock.now < deadline, "Branch fixture did not reach expected state")
      try await Task.sleep(for: .milliseconds(10))
    }
  }
  private func controller(root: URL) async throws -> AgentChatController {
    let controller = AgentChatController(triptychID: UUID(), root: root) { request in
      try! .init(requestID: request.requestID, result: .object(["status": .string("ok")]))
    }
    try await wait { controller.isLoaded }
    let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
    controller.connect(executable: fixture, home: controller.runtimeHome, cli: fixture)
    try await wait { controller.state == .ready && controller.account != nil }
    return controller
  }
  private func send(_ text: String, through controller: AgentChatController) async throws {
    controller.editDraft(text)
    controller.send()
    try await wait { controller.state == .ready && controller.selected?.pendingMessageID == nil && !controller.isBusy }
  }

  @Test("Branching through an earlier turn preserves settings, materials and its original conversation")
  func branchHistory() async throws {
    let root = repository.appendingPathComponent(".build/agent-chat-tests/branch-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = try await controller(root: root)
    controller.setPermission(.fullAccess)
    controller.setEffort("high")
    controller.setWebSearch(.live)
    let material = AgentChatAttachment(noteID: UUID(), vaultID: UUID(), relativePath: "原文.md",
      text: "Exact\r\nsource", fingerprint: .init(content: "Exact\r\nsource"))
    controller.attach(material)
    try await send("First interpretation capabilities", through: controller)
    let firstTurn = try #require(controller.branchPoints.first?.turnID)
    let firstMessages = try #require(controller.selected?.messages)
    #expect(firstMessages.allSatisfy { $0.turnID == firstTurn })
    try await send("Second interpretation", through: controller)
    controller.editDraft("Keep this unsent draft")
    controller.attach(material)
    let original = try #require(controller.selected)
    controller.branch(through: firstTurn)
    try await wait { controller.selectedID != original.id && !controller.hasActiveExecutions }
    let branch = try #require(controller.selected)
    #expect(branch.messages == firstMessages)
    #expect(branch.preferences == original.preferences && branch.permission == original.permission)
    #expect(branch.branchOrigin == .init(conversationID: original.id, turnID: firstTurn))
    #expect(branch.draft.isEmpty && branch.attachments.isEmpty && branch.pendingMessageID == nil)
    #expect(controller.token == nil && controller.approvals.isEmpty)
    let retained = try #require(controller.conversations.first { $0.id == original.id })
    #expect(retained.messages == original.messages && retained.draft == original.draft && retained.attachments == original.attachments)
    let params = try JSONDecoder().decode(MCPJSONValue.self,
      from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("last-fork.json"))).objectValue
    #expect(params?["lastTurnId"]?.stringValue == firstTurn && params?["deferGoalContinuation"]?.boolValue == true)
    let args = params?["config"]?.objectValue?["mcp_servers"]?.objectValue?["scholium"]?.objectValue?["args"]?.arrayValue
    let dormantToken = try #require(args?.last?.stringValue.flatMap(UUID.init(uuidString:)))
    #expect(!controller.owns(token: dormantToken))
    try await send("Continue the first interpretation", through: controller)
    #expect(controller.selected?.threadID == branch.threadID)
    #expect(controller.conversations.first { $0.id == original.id }?.messages == original.messages)
    await controller.disconnect()
    let stored = try await AgentChatStorage(root: root.appendingPathComponent(controller.triptychID.uuidString)).load()
    #expect(stored.first { $0.id == branch.id }?.branchOrigin == branch.branchOrigin)
  }

  @Test("Editing a request forks before its turn, prepares exact materials and never resends automatically")
  func editRequest() async throws {
    let root = repository.appendingPathComponent(".build/agent-chat-tests/edit-branch-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = try await controller(root: root)
    try await send("First question", through: controller)
    let earlier = try #require(controller.selected?.messages)
    let firstRequest = try #require(earlier.first { $0.role == .user })
    let sourceID = try #require(controller.selectedID)
    let file = root.appendingPathComponent("paper.txt")
    try Data("\u{feff}Exact\r\nsource".utf8).write(to: file)
    await controller.addLocalFiles([file], to: sourceID)
    let attachment = AgentChatAttachment(noteID: UUID(), vaultID: UUID(), relativePath: "原文.md",
      text: "Supplied passage", fingerprint: .init(content: "Supplied passage"))
    controller.attach(attachment)
    try await wait { controller.capabilities.hasMethods && !controller.capabilities.isRefreshing }
    let method = try #require(controller.capabilities.methods.first)
    controller.toggleMethod(method.selection)
    controller.setEffort("high")
    try await send("Second question 中文\nExact draft", through: controller)
    let request = try #require(controller.selected?.messages.last { $0.role == .user })
    controller.editDraft("Unsent source draft")
    controller.attach(attachment)
    let original = try #require(controller.selected)
    let delivered = try Data(contentsOf: controller.runtimeHome.appendingPathComponent("last-turn.json"))
    controller.retryInNewBranch(turnID: try #require(request.turnID))
    try await wait { controller.selectedID != sourceID && !controller.hasActiveExecutions }
    let edited = try #require(controller.selected)
    #expect(edited.messages == earlier && edited.draft == request.text)
    #expect(edited.attachments == request.attachments && edited.localMaterials == request.localMaterials)
    #expect(edited.selectedMethods == request.methods && edited.preferences == original.preferences)
    #expect(edited.branchOrigin == .init(conversationID: sourceID, turnID: try #require(request.turnID), position: .before))
    #expect(edited.pendingMessageID == nil && controller.approvals.isEmpty && controller.token == nil)
    #expect(try Data(contentsOf: controller.runtimeHome.appendingPathComponent("last-turn.json")) == delivered)
    let params = try JSONDecoder().decode(MCPJSONValue.self,
      from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("last-fork.json"))).objectValue
    #expect(params?["beforeTurnId"]?.stringValue == request.turnID && params?["lastTurnId"] == nil)
    #expect(params?["deferGoalContinuation"]?.boolValue == true)
    let unchanged = try #require(controller.conversations.first { $0.id == sourceID })
    #expect(unchanged.messages == original.messages && unchanged.draft == original.draft && unchanged.attachments == original.attachments)
    try await send("Revised second question", through: controller)
    #expect(controller.selected?.messages.filter { $0.role == .user }.map(\.text) == ["First question", "Revised second question"])
    controller.select(sourceID)
    try await wait { controller.canBranch }
    controller.editInNewBranch(firstRequest.id)
    try await wait { controller.selectedID != sourceID && !controller.hasActiveExecutions }
    #expect(controller.selected?.messages.isEmpty == true && controller.selected?.draft == "First question")
    #expect(controller.selected?.branchOrigin?.position == .before && controller.canSend)
    try await controller.flushPersistence()
    let stored = try await AgentChatStorage(root: root.appendingPathComponent(controller.triptychID.uuidString)).load()
    #expect(stored.first { $0.id == edited.id }?.branchOrigin?.position == .before)
    await controller.disconnect()
  }

  @Test("A failed turn exposes an explicit branch retry without replaying the original")
  func retryFailedTurn() async throws {
    let root = repository.appendingPathComponent(".build/agent-chat-tests/retry-failed-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = try await controller(root: root)
    let sourceID = try #require(controller.selectedID)
    try await send("fail-turn", through: controller)
    let turnID = try #require(controller.editableRequests.first?.turnID)
    #expect(controller.selected?.turns[turnID]?.status == .failed)
    #expect(controller.canRetryInNewBranch(turnID: turnID))

    controller.retryInNewBranch(turnID: turnID)
    try await wait { controller.selectedID != sourceID && !controller.hasActiveExecutions }
    #expect(controller.selected?.draft == "fail-turn")
    #expect(controller.selected?.messages.isEmpty == true)
    #expect(controller.conversations.first { $0.id == sourceID }?.messages.contains { $0.text == "fail-turn" } == true)
    await controller.disconnect()
  }

  @Test("Additional input in the same turn has no independent edit boundary")
  func additionalInput() async throws {
    let root = repository.appendingPathComponent(".build/agent-chat-tests/edit-steer-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = try await controller(root: root)
    controller.editDraft("hold the opening request")
    controller.send()
    try await wait { controller.state == .working && controller.canSend == false && controller.selected?.pendingMessageID == nil }
    try await send("Additional instruction", through: controller)
    let requests = try #require(controller.selected?.messages.filter { $0.role == .user })
    #expect(requests.count == 2 && Set(requests.compactMap(\.turnID)).count == 1)
    #expect(controller.editableRequests.map(\.id) == [requests[0].id])
    controller.editInNewBranch(requests[1].id)
    #expect(controller.conversations.count == 1 && !controller.isBusy)
    await controller.disconnect()
  }

  @Test("An unconfirmed or cancelled branch preserves the source and does not grab another conversation")
  func branchFailureAndCancellation() async throws {
    let root = repository.appendingPathComponent(".build/agent-chat-tests/branch-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = try await controller(root: root)
    try await send("Source question omit-client-id", through: controller)
    let originalID = try #require(controller.selectedID)
    let turn = try #require(controller.branchPoints.first?.turnID)
    let requestID = try #require(controller.editableRequests.first?.id)
    let wrong = controller.runtimeHome.appendingPathComponent("wrong-fork-boundary")
    try Data().write(to: wrong)
    controller.editInNewBranch(requestID)
    try await wait { !controller.isBusy && controller.error != nil }
    #expect(controller.conversations.count == 1 && controller.selectedID == originalID)
    try FileManager.default.removeItem(at: wrong)
    let reject = controller.runtimeHome.appendingPathComponent("reject-fork")
    try Data().write(to: reject)
    controller.branch(through: turn)
    try await wait { !controller.isBusy && controller.error != nil }
    #expect(controller.conversations.count == 1 && controller.selectedID == originalID)
    try FileManager.default.removeItem(at: reject)
    controller.branch(through: turn)
    controller.newConversation()
    let visibleID = controller.selectedID
    try await wait { !controller.hasActiveExecutions && controller.conversations.count == 3 }
    #expect(controller.selectedID == visibleID)
    controller.select(originalID)
    try await wait { !controller.isBusy }
    controller.setArchived(originalID, archived: true)
    #expect(controller.canBranch)
    let hold = controller.runtimeHome.appendingPathComponent("hold-fork")
    try Data().write(to: hold)
    controller.branch(through: turn)
    #expect(controller.state == .branching && !controller.canSend)
    let counter = controller.runtimeHome.appendingPathComponent("fork-count")
    try await wait { (try? String(contentsOf: counter, encoding: .utf8)) == "4" }
    controller.stop()
    try await wait { !controller.isBusy }
    #expect(controller.conversations.count == 3 && controller.selectedID == originalID)
    #expect(controller.selected?.archivedAt != nil)
    controller.setArchived(originalID, archived: false)
    controller.editDraft("Continue after cancellation")
    #expect(controller.canSend)
    controller.editInNewBranch(requestID)
    try await wait { (try? String(contentsOf: counter, encoding: .utf8)) == "5" }
    await controller.disconnect()
    #expect(controller.conversations.count == 3 && controller.state == .disconnected)
  }
}
