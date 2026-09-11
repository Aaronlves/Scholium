import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Runtime approval interaction", .serialized) @MainActor
struct AgentChatRuntimeApprovalTests {
  @Test("Readable access summaries keep exact scope inspectable and preserve unfamiliar patterns")
  func readableAccess() {
    let permissions = AgentChatRuntimeApproval.Permissions(network: true, rules: [
      .init(access: .read, path: .literal("/fixture/sources")),
      .init(access: .write, path: .pattern("/fixture/output/**/*.md")),
      .init(access: .write, path: .pattern("/fixture/[ab]/*.txt")),
      .init(access: .deny, path: .literal("/fixture/private"))], globScanMaxDepth: nil)
    let request = AgentChatRuntimeApproval(kind: .permissions, command: nil, cwd: "/fixture",
      environmentID: nil, reason: nil, networkHost: nil, networkProtocol: nil,
      permissions: permissions, files: [], grantRoot: nil, grants: [.turn], rejection: .decline)
    let locale = Locale(identifier: "en")
    let overview = request.accessOverview(locale: locale).joined(separator: "\n")
    #expect(overview.contains("Markdown files in /fixture/output and its subfolders"))
    #expect(overview.contains("/fixture/[ab]/*.txt"))
    #expect(overview.contains("Connect to the internet"))
    let exact = request.scopeLines(locale: locale).joined(separator: "\n")
    #expect(exact.contains("/fixture/output/**/*.md") && exact.contains("/fixture/private"))
    #expect(exact.contains("/fixture/sources"))
  }

  @Test("Expired approval clears its tool's waiting state without inventing a tool outcome", arguments: [false, true])
  func expiredToolWaitingState(submit: Bool) async throws {
    let root = repository.appendingPathComponent(".build/agent-chat-tests/expired-tool-approval-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = try await controller(root, action: "runtime-linked-approval background activity")
    let approval = try #require(controller.approvals.first)
    let itemID = try #require(approval.runtimeItemID)
    let messageID = "runtime:\(itemID)"
    #expect(controller.selected?.messages.first { $0.id == messageID }?.activity?.status == .waitingForApproval)
    // Keep the decision unconfirmed: a real declined acknowledgement is a different outcome.
    try Data().write(to: controller.runtimeHome.appendingPathComponent("hold-approval-resolution"))
    if submit {
      controller.answerRuntimeApproval(approval.id, decision: .once)
      try await wait { FileManager.default.fileExists(atPath: controller.runtimeHome.appendingPathComponent("runtime-approval-response.json").path) }
    }
    controller.stop()
    try await wait { !controller.isBusy }
    #expect(controller.approvals.isEmpty && !controller.needsInput)
    #expect(controller.selected?.messages.first { $0.id == messageID }?.activity?.status == .uncertain)
    #expect(!controller.isAwaitingDecision(approval.id))
    await controller.disconnect()
  }

  @Test("MCP tool approval appears natively and Allow Once never persists a runtime rule")
  func mcpToolApproval() async throws {
    let root = repository.appendingPathComponent(".build/agent-chat-tests/mcp-approval-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = try await controller(root, action: "runtime-mcp-approval")
    let approval = try #require(controller.approvals.first)
    #expect(approval.runtimeApproval?.kind == .tool)
    #expect(approval.runtimeApproval?.toolServer == "scholium")
    #expect(approval.runtimeApproval?.grants == [.once])
    controller.answerRuntimeApproval(approval.id, decision: .session)
    #expect(controller.isAwaitingDecision(approval.id))
    controller.answerRuntimeApproval(approval.id, decision: .once)
    try await wait { controller.approvals.isEmpty }
    let file = controller.runtimeHome.appendingPathComponent("runtime-approval-response.json")
    let response = try JSONDecoder().decode(MCPJSONValue.self, from: Data(contentsOf: file))
    #expect(response.objectValue?["result"] == .object(["action": .string("accept"), "content": .object([:])]))
    #expect(controller.selected?.messages.contains { $0.changeID != nil } == false)
    controller.stop(); try await wait { !controller.isBusy }
    await controller.disconnect()
  }

  private var repository: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  }
  private func wait(_ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while !predicate() {
      try #require(ContinuousClock.now < deadline, "Runtime approval fixture did not reach the expected state")
      try await Task.sleep(for: .milliseconds(10))
    }
  }
  private func controller(_ root: URL, action: String) async throws -> AgentChatController {
    let controller = AgentChatController(triptychID: UUID(), root: root) { request in
      try! .init(requestID: request.requestID, result: .object([:]))
    }
    try await wait { controller.isLoaded }
    let executable = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
    controller.connect(executable: executable, home: controller.runtimeHome, cli: executable)
    try await wait { controller.account != nil && controller.state == .ready }
    controller.editDraft("hold " + action); controller.send()
    try await wait { !controller.approvals.isEmpty || controller.error != nil }
    return controller
  }

  @Test("Session permission replies stay with their request, await confirmation and cannot be submitted twice")
  func scopedReply() async throws {
    let root = repository.appendingPathComponent(".build/agent-chat-tests/runtime-approval-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = try await controller(root, action: "runtime-permission-approval")
    let owner = try #require(controller.selectedID), approval = try #require(controller.approvals.first)
    let request = try #require(approval.runtimeApproval)
    #expect(request.kind == .permissions && request.permissions?.rules.count == 3)
    #expect(approval.detail.isEmpty && approval.toolInputDetails == nil)
    controller.editDraft("Keep this draft")
    try Data().write(to: controller.runtimeHome.appendingPathComponent("hold-approval-resolution"))
    controller.newConversation()
    let other = controller.selectedID
    controller.answerRuntimeApproval(approval.id, decision: .session)
    let file = controller.runtimeHome.appendingPathComponent("runtime-approval-response.json")
    try await wait { FileManager.default.fileExists(atPath: file.path) }
    #expect(controller.selectedID == other && !controller.needsInput)
    let response = try JSONDecoder().decode(MCPJSONValue.self, from: Data(contentsOf: file))
    #expect(response.objectValue?["result"]?.objectValue?["scope"]?.stringValue == "session")
    #expect(response.objectValue?["result"]?.objectValue?["permissions"]?.objectValue?["fileSystem"]?.objectValue?["entries"]?.arrayValue?.count == 3)
    controller.select(owner)
    #expect(controller.approvals.first?.runtimeDecision == .session && controller.approvals.first?.isSubmitting == true)
    #expect(controller.selected?.draft == "Keep this draft")
    controller.answerRuntimeApproval(approval.id, decision: .decline)
    #expect(try String(contentsOf: controller.runtimeHome.appendingPathComponent("runtime-approval-response-count"), encoding: .utf8) == "1")
    try Data().write(to: controller.runtimeHome.appendingPathComponent("resolve-approvals"))
    controller.refreshQuota()
    try await wait { controller.approvals.isEmpty }
    let record = try #require(controller.selected?.messages.first { $0.id == "approval:\(approval.id)" })
    #expect(record.activity?.status == .completed && controller.selected?.lastRunStatus == .running)
    #expect(record.activity?.detail.contains("/fixture/private") == true && record.changeID == nil)
    controller.stop(); try await wait { !controller.isBusy }
    await controller.disconnect()
  }

  @Test("Allow Once cannot become session or persistent policy approval")
  func noBroaderSubstitution() async throws {
    for policyOnly in [false, true] {
      let root = repository.appendingPathComponent(".build/agent-chat-tests/runtime-scope-\(UUID())")
      defer { try? FileManager.default.removeItem(at: root) }
      let controller = try await controller(root, action: policyOnly ? "runtime-policy-approval" : "runtime-session-approval")
      let approval = try #require(controller.approvals.first)
      #expect(approval.runtimeApproval?.grants == (policyOnly ? [] : [.session]))
      controller.answer(approval.id, allow: true)
      controller.answerRuntimeApproval(approval.id, decision: .once)
      #expect(controller.isAwaitingDecision(approval.id) && controller.approvals.first?.runtimeDecision == nil)
      let file = controller.runtimeHome.appendingPathComponent("runtime-approval-response.json")
      #expect(!FileManager.default.fileExists(atPath: file.path))
      controller.answerRuntimeApproval(approval.id, decision: policyOnly ? .decline : .session)
      try await wait { controller.approvals.isEmpty }
      let response = try JSONDecoder().decode(MCPJSONValue.self, from: Data(contentsOf: file))
      #expect(response.objectValue?["result"]?.objectValue?["decision"]?.stringValue == (policyOnly ? "decline" : "acceptForSession"))
      await controller.disconnect()
    }
  }

  @Test("A runtime Cancel decision stops its exact owner; stale-turn approvals are refused")
  func cancelAndStale() async throws {
    for stale in [false, true] {
      let root = repository.appendingPathComponent(".build/agent-chat-tests/runtime-cancel-\(UUID())")
      defer { try? FileManager.default.removeItem(at: root) }
      let controller = try await controller(root, action: stale ? "runtime-stale-approval" : "runtime-cancel-approval")
      if stale { #expect(controller.approvals.isEmpty && controller.error != nil) }
      else {
        let owner = try #require(controller.selectedID), approval = try #require(controller.approvals.first)
        controller.newConversation()
        let other = controller.selectedID
        controller.answerRuntimeApproval(approval.id, decision: .cancel)
        try await wait { !controller.isBusy(in: owner) }
        #expect(controller.selectedID == other && !controller.needsInput)
      }
      await controller.disconnect()
    }
  }

  @Test("The client requests complete per-command permission metadata without granting it")
  func completePermissionMetadata() async throws {
    let root = repository.appendingPathComponent(".build/agent-chat-tests/runtime-metadata-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = try await controller(root, action: "runtime-command-extra-approval")
    let approval = try #require(controller.approvals.first)
    #expect(approval.runtimeApproval?.permissions?.network == true)
    #expect(approval.runtimeApproval?.permissions?.rules.first?.access == .write)
    #expect(approval.runtimeDecision == nil && controller.needsInput)
    await controller.disconnect()
  }

  @Test("A reused pending runtime request identity cannot redirect approval to another conversation")
  func duplicateIdentity() async throws {
    let root = repository.appendingPathComponent(".build/agent-chat-tests/runtime-duplicate-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = try await controller(root, action: "approval")
    let first = try #require(controller.selectedID), token = try #require(controller.token)
    controller.newConversation()
    let second = controller.selectedID
    controller.editDraft("hold duplicate-approval"); controller.send()
    try await wait { controller.connectionState == .disconnected }
    #expect(controller.selectedID == second && controller.error != nil)
    #expect(!controller.owns(token: token) && !controller.needsInput && controller.approvals.isEmpty)
    #expect(controller.conversations.first { $0.id == first }?.messages.isEmpty == false)
    #expect(!FileManager.default.fileExists(atPath: controller.runtimeHome.appendingPathComponent("runtime-approval-response.json").path))
    await controller.disconnect()
  }
}
