import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("In-app Agent collaboration", .serialized)
@MainActor
struct AgentChatTests {
  private var repository: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
  }
  private var executable: URL {
    repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
  }
  private func root() throws -> URL {
    let root = repository.appendingPathComponent(".build/agent-chat-tests/\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }
  private func eventually(_ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while !predicate() {
      guard ContinuousClock.now < deadline else { throw TestFailure.timeout }
      try await Task.sleep(for: .milliseconds(10))
    }
  }
  private enum TestFailure: Error { case timeout }
  private func connect(_ controller: AgentChatController) async throws {
    try await eventually { controller.isLoaded }
    controller.connect(executable: executable, home: controller.runtimeHome, cli: executable)
    try await eventually { controller.state == .ready && controller.account != nil }
  }
  private func success(_ request: ScholiumMCPBridgeRequest) -> ScholiumMCPBridgeResponse {
    try! .init(requestID: request.requestID, result: .object(["status": .string("ok")]))
  }

  @Test("Ask waits, decline and cancellation cannot write; Full Access remains Triptych scoped")
  func permissionAdmission() async throws {
    let root = try root()
    defer { try? FileManager.default.removeItem(at: root) }
    var writes = 0
    let triptych = UUID()
    let controller = AgentChatController(triptychID: triptych, root: root) { request in
      #expect(request.arguments["triptych_id"] == .string(triptych.uuidString.lowercased()))
      if request.tool == .updateNote { writes += 1 }
      return success(request)
    }
    try await connect(controller)
    controller.editDraft("hold")
    controller.send()
    try await eventually {
      controller.state == .working && controller.selected?.pendingMessageID == nil
    }
    let token = try #require(controller.token)
    let request = ScholiumMCPBridgeRequest(tool: .updateNote, conversationToken: token)
    let declined = Task { await controller.handle(request) }
    try await eventually { controller.approvals.count == 1 }
    #expect(writes == 0)
    #expect(controller.selected?.messages.last?.activity?.status == .waitingForApproval)
    controller.answer(try #require(controller.approvals.first?.id), allow: false)
    #expect(await declined.value.error != nil)
    #expect(controller.selected?.messages.last?.activity?.status == .declined)
    #expect(writes == 0)
    let cancelled = Task { await controller.handle(request) }
    try await eventually { controller.approvals.count == 1 }
    cancelled.cancel()
    #expect(await cancelled.value.error != nil)
    #expect(controller.approvals.isEmpty && writes == 0)
    let approved = Task { await controller.handle(request) }
    try await eventually { controller.approvals.count == 1 }
    controller.answer(try #require(controller.approvals.first?.id), allow: true)
    #expect(await approved.value.error == nil)
    #expect(writes == 1)
    let stopped = Task { await controller.handle(request) }
    try await eventually { controller.approvals.count == 1 }
    controller.stop()
    #expect(await stopped.value.error != nil)
    try await eventually { controller.state == .ready }
    #expect(writes == 1)
    controller.setPermission(.fullAccess)
    controller.editDraft("hold again")
    controller.send()
    try await eventually {
      controller.state == .working && controller.selected?.pendingMessageID == nil
    }
    #expect(controller.token != token)
    #expect(await controller.handle(request).error != nil)
    let current = try #require(controller.token)
    let wrong = ScholiumMCPBridgeRequest(
      tool: .updateNote, arguments: ["triptych_id": .string(UUID().uuidString)],
      conversationToken: current)
    #expect(await controller.handle(wrong).error != nil)
    #expect(writes == 1)
    #expect(
      await controller.handle(.init(tool: .updateNote, conversationToken: current)).error == nil)
    #expect(writes == 2 && controller.approvals.isEmpty)
    await controller.disconnect()
    #expect(
      await controller.handle(.init(tool: .updateNote, conversationToken: current)).error != nil)
  }

  @Test("Live bridge activity distinguishes reads, no-op updates, confirmed edits and failed writes")
  func operationEvidence() async throws {
    let root = try root()
    defer { try? FileManager.default.removeItem(at: root) }
    let note = UUID(), change = UUID()
    let controller = AgentChatController(triptychID: UUID(), root: root) { request in
      await Task.yield()
      let mode = request.arguments["content"]?.stringValue ?? "read"
      if mode == "failed" {
        return try! .init(requestID: request.requestID, error: .init(
          code: .staleRevision, message: "The file changed.", recovery: "Read again."))
      }
      if mode == "noop" {
        return try! .init(requestID: request.requestID, error: .init(
          code: .noChanges, message: "Unchanged.", recovery: "Continue."))
      }
      var result: [String: MCPJSONValue] = ["note_id": .string(note.uuidString),
        "relative_path": .string("Ideas/理由.md")]
      if request.tool == .updateNote {
        result["change_id"] = .string(change.uuidString)
        result["before_fingerprint"] = .object(["sha256": .string("before")])
        result["after_fingerprint"] = .object(["sha256": .string("after")])
        result["readback_verified"] = .bool(true)
      }
      return try! .init(requestID: request.requestID, result: .object(result))
    }
    try await connect(controller)
    controller.setPermission(.fullAccess)
    controller.editDraft("hold activity")
    controller.send()
    try await eventually { controller.state == .working && controller.selected?.pendingMessageID == nil }
    let token = try #require(controller.token)
    let arguments: [String: MCPJSONValue] = ["note_id": .string(note.uuidString)]
    _ = await controller.handle(.init(tool: .readNote, arguments: arguments, conversationToken: token))
    #expect(controller.selected?.messages.last?.activity?.files.first?.effect == .read)
    var updateArguments = arguments
    updateArguments["content"] = .string("noop")
    _ = await controller.handle(.init(tool: .updateNote, arguments: updateArguments, conversationToken: token))
    #expect(controller.selected?.messages.last?.activity?.files.first?.effect == .unchanged)
    updateArguments["content"] = .string("edit")
    _ = await controller.handle(.init(tool: .updateNote, arguments: updateArguments, conversationToken: token))
    #expect(controller.selected?.messages.last?.activity?.files.first?.effect == .edited)
    #expect(controller.selected?.messages.last?.changeID == change)
    updateArguments["content"] = .string("failed")
    _ = await controller.handle(.init(tool: .updateNote, arguments: updateArguments, conversationToken: token))
    #expect(controller.selected?.messages.last?.activity?.status == .failed)
    #expect(controller.selected?.messages.last?.activity?.files.first?.effect == nil)
    let summaries = AgentChatFileSummary.collect(controller.selected?.messages ?? [])
    #expect(summaries.count == 1 && summaries.first?.file.effect == .edited)
    #expect(summaries.first?.file.path == "Ideas/理由.md")
    controller.stop()
    try await eventually { controller.state == .ready }
    #expect(controller.selected?.messages.contains { $0.activity?.status == .interrupted } == true)
    await controller.disconnect()
    let restored = AgentChatController(triptychID: controller.triptychID, root: root, toolHandler: success)
    try await eventually { restored.isLoaded }
    #expect(restored.selected?.messages.compactMap(\.activity).contains { $0.status.isActive } == false)
    #expect(AgentChatFileSummary.collect(restored.selected?.messages ?? []).first?.file.effect == .edited)
    try await connect(restored)
    #expect(restored.selected?.messages.compactMap(\.activity).first { $0.kind == .command }?.status == .interrupted)
    await restored.disconnect()
  }

  @Test("Early completion, conversation switching, history and drafts survive reconnect")
  func completionAndPersistence() async throws {
    let root = try root()
    defer { try? FileManager.default.removeItem(at: root) }
    let triptych = UUID()
    let controller = AgentChatController(triptychID: triptych, root: root, toolHandler: success)
    try await connect(controller)
    controller.setPermission(.fullAccess)
    controller.editDraft("first")
    controller.send()
    try await eventually {
      controller.state == .ready && controller.selected?.pendingMessageID == nil
        && controller.selected?.messages.count == 2
    }
    #expect(controller.selected?.messages.last?.text == "中文 😀 fixture reply")
    let first = try #require(controller.selectedID)
    let firstThread = controller.selected?.threadID
    let oldToken = controller.token
    controller.editDraft("unsent 中文 draft")
    controller.newConversation()
    #expect(controller.token == nil && controller.selected?.threadID == nil)
    controller.select(first)
    try await eventually { controller.state == .ready }
    #expect(controller.selected?.messages.count == 2)
    #expect(controller.selected?.draft == "unsent 中文 draft")
    controller.editDraft("hold approval")
    controller.send()
    try await eventually { controller.approvals.count == 1 }
    #expect(controller.token != oldToken && controller.selected?.threadID == firstThread)
    controller.stop()
    try await eventually { controller.state == .ready }
    await controller.disconnect()
    let restored = AgentChatController(triptychID: triptych, root: root, toolHandler: success)
    try await connect(restored)
    #expect(restored.selected?.permission == .fullAccess)
    #expect(restored.selected?.threadID == firstThread)
    #expect(restored.selected?.messages.filter { $0.role == .assistant }.count == 1)
    await restored.disconnect()
  }

  @Test("Lost acknowledgement is recovered by client message identity without resending")
  func uncertainDelivery() async throws {
    let root = try root()
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = AgentChatController(triptychID: UUID(), root: root, toolHandler: success)
    try await connect(controller)
    controller.editDraft("disconnect")
    controller.send()
    try await eventually { controller.state == .disconnected }
    #expect(controller.selected?.pendingMessageID != nil)
    try await connect(controller)
    #expect(controller.selected?.pendingMessageID == nil)
    #expect(controller.selected?.messages.filter { $0.role == .user }.count == 1)
    #expect(controller.selected?.messages.filter { $0.role == .assistant }.count == 1)
    await controller.disconnect()
  }

  @Test("Disconnect during initialization cannot revive a stale connection")
  func disconnectDuringConnect() async throws {
    let root = try root()
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = AgentChatController(triptychID: UUID(), root: root, toolHandler: success)
    try await eventually { controller.isLoaded }
    controller.connect(executable: executable, home: controller.runtimeHome, cli: executable)
    await controller.disconnect()
    try await Task.sleep(for: .milliseconds(100))
    #expect(controller.state == .disconnected && controller.token == nil)
    try await connect(controller)
    await controller.disconnect()
  }

  @Test("Stdio splits Unicode safely, correlates concurrent replies and cancels pending requests")
  func transport() async throws {
    let root = try root()
    defer { try? FileManager.default.removeItem(at: root) }
    let runtime = CodexAppServer()
    try await runtime.start(executable: executable, home: root)
    async let first = runtime.request("test/echo", params: ["text": .string("中文 😀")])
    async let second = runtime.request("test/echo", params: ["text": .string("second")])
    #expect(try await first.objectValue?["text"] == .string("中文 😀"))
    #expect(try await second.objectValue?["text"] == .string("second"))
    let cancelled = Task { try await runtime.request("test/hang") }
    cancelled.cancel()
    do {
      _ = try await cancelled.value
      Issue.record("Cancelled request succeeded")
    } catch {}
    let pending = Task { try await runtime.request("test/hang") }
    await runtime.close()
    do {
      _ = try await pending.value
      Issue.record("Closed request succeeded")
    } catch {}
  }

  @Test("Archiving preserves messages and drafts, blocks sending, and restores after reopening")
  func archiveConversation() async throws {
    let root = try root()
    defer { try? FileManager.default.removeItem(at: root) }
    let triptych = UUID()
    let controller = AgentChatController(triptychID: triptych, root: root, toolHandler: success)
    try await connect(controller)
    controller.editDraft("A question")
    controller.send()
    try await eventually { controller.state == .ready && controller.selected?.messages.count == 2 }
    controller.editDraft("A retained follow-up")
    let id = try #require(controller.selectedID)
    let messages = controller.selected!.messages
    let updated = controller.selected!.updatedAt
    controller.editDraft("A retained follow-up")
    #expect(controller.selected?.updatedAt == updated)
    controller.setArchived(id, archived: true)
    #expect(controller.selected?.archivedAt != nil && !controller.canSend)
    #expect(controller.selected?.messages == messages)
    try await controller.flushPersistence()
    await controller.disconnect()
    let reopened = AgentChatController(triptychID: triptych, root: root, toolHandler: success)
    try await eventually { reopened.isLoaded }
    let archived = try #require(reopened.conversations.first { $0.id == id })
    #expect(archived.archivedAt != nil && archived.draft == "A retained follow-up")
    #expect(archived.messages == messages && reopened.selectedID != id)
    reopened.setArchived(id, archived: false)
    reopened.select(id)
    #expect(reopened.selected?.archivedAt == nil && reopened.selected?.messages == messages)
    await reopened.disconnect()
  }

  @Test("Automatic connection uses explicit machine settings without rewriting them")
  func automaticConnection() async throws {
    let root = try root()
    defer { try? FileManager.default.removeItem(at: root) }
    let suite = "scholium-chat-test-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(executable.path, forKey: "agent.codex.executable")
    defaults.set(executable.path, forKey: "agent.scholium.cli")
    let controller = AgentChatController(triptychID: UUID(), root: root, toolHandler: success)
    try await eventually { controller.isLoaded }
    controller.connectConfigured(using: defaults)
    try await eventually { controller.state == .ready && controller.account != nil }
    #expect(defaults.string(forKey: "agent.codex.home") == nil)
    await controller.disconnect()
    defaults.set("/missing-test-runtime", forKey: "agent.codex.executable")
    controller.connectConfigured(using: defaults)
    #expect(controller.state == .disconnected && controller.error != nil)
  }

  @Test("Corrupt or linked history is preserved, never silently replaced")
  func storage() async throws {
    let root = try root()
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = AgentChatStorage(root: root)
    var conversation = AgentChatConversation(triptychID: UUID())
    conversation.draft = "\u{FEFF}中文 😀\r\n"
    conversation.permission = .fullAccess
    try await storage.save([conversation])
    #expect(try await storage.load() == [conversation])
    let file = root.appendingPathComponent("conversations.json")
    try Data("broken".utf8).write(to: file)
    do {
      _ = try await storage.load()
      Issue.record("Corrupt history accepted")
    } catch {}
    #expect(try String(contentsOf: file, encoding: .utf8) == "broken")
    try FileManager.default.removeItem(at: file)
    let target = root.appendingPathComponent("untouched")
    try Data("original".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
    do {
      try await storage.save([])
      Issue.record("Linked history overwritten")
    } catch {}
    #expect(try String(contentsOf: target, encoding: .utf8) == "original")
  }

  @Test(
    "Selected installed Codex runtime supports the stable client handshake",
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_CODEX_SMOKE_EXECUTABLE"] != nil))
  func officialRuntimeSmoke() async throws {
    let root = try root()
    defer { try? FileManager.default.removeItem(at: root) }
    let path = try #require(ProcessInfo.processInfo.environment["SCHOLIUM_CODEX_SMOKE_EXECUTABLE"])
    let runtime = CodexAppServer()
    try await runtime.start(executable: URL(fileURLWithPath: path), home: root)
    let initialized = try await runtime.request(
      "initialize",
      params: [
        "clientInfo": .object(["name": .string("scholium-test"), "version": .string("0.1")])
      ])
    #expect(initialized.objectValue != nil)
    try await runtime.notify("initialized")
    let account = try await runtime.request("account/read")
    #expect(account.objectValue != nil)
    let models = try await runtime.request("model/list")
    #expect(models.objectValue?["data"]?.arrayValue?.isEmpty == false)
    let thread = try await runtime.request(
      "thread/start",
      params: [
        "cwd": .string(root.path), "sandbox": .string("read-only"),
        "approvalPolicy": .string("on-request"),
      ])
    #expect(thread.objectValue?["thread"]?.objectValue?["id"]?.stringValue != nil)
    await runtime.close()
  }

  @Test("File references reject paths, duplicate locators, ports and missing identities")
  func references() throws {
    let id = UUID()
    #expect(AgentChatReference.parse(AgentChatReference.url(noteID: id, line: 7))?.noteID == id)
    #expect(AgentChatReference.parse(AgentChatReference.url(noteID: id, line: 7))?.line == 7)
    for suffix in ["/file.md", "?line=0", "?line=x", "?line=1&line=2", ":80", "#fragment"] {
      #expect(
        AgentChatReference.parse(try #require(URL(string: "scholium-note://\(id)\(suffix)"))) == nil
      )
    }
  }
}
