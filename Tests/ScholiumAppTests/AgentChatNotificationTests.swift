import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Chat notification events", .serialized) @MainActor
struct AgentChatNotificationTests {
  private var repository: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  }
  private func wait(_ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while !predicate() {
      try #require(ContinuousClock.now < deadline, "Chat notification fixture did not reach its expected state")
      try await Task.sleep(for: .milliseconds(10))
    }
  }
  private func makeController(_ root: URL, recorder: ChatNotificationRecorder) async throws -> AgentChatController {
    let controller = AgentChatController(triptychID: UUID(), root: root,
      notificationSink: { route, current in recorder.events.append((route, current)) }) { request in
        try! .init(requestID: request.requestID, result: .object([:]))
      }
    try await wait { controller.isLoaded }
    let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
    controller.connect(executable: fixture, home: controller.runtimeHome, cli: fixture)
    try await wait { controller.account != nil && controller.state == .ready }
    return controller
  }

  @Test("Live results notify once per turn and keep independent destinations; history and Stop stay quiet")
  func outcomes() async throws {
    let root = repository.appendingPathComponent(".build/agent-chat-tests/notifications-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = ChatNotificationRecorder(), controller = try await makeController(root, recorder: recorder)
    let first = try #require(controller.selectedID)
    controller.editDraft("duplicate-completion private-title"); controller.send()
    try await wait { !controller.isBusy && recorder.events.count == 1 }
    #expect(recorder.events[0].route.event == .completed && recorder.events[0].route.conversationID == first)
    #expect(recorder.events[0].current())
    controller.newConversation()
    let second = try #require(controller.selectedID)
    controller.editDraft("fail-turn"); controller.send()
    try await wait { !controller.isBusy && recorder.events.count == 2 }
    #expect(recorder.events[1].route.event == .failed && recorder.events[1].route.conversationID == second)
    #expect(recorder.events.allSatisfy { $0.current() })
    let payload = String(decoding: try JSONEncoder().encode(recorder.events[0].route), as: UTF8.self)
    #expect(!payload.contains("private-title") && !payload.contains("turnID"))
    controller.select(first)
    try await wait { !controller.isRefreshingHistory }
    #expect(recorder.events.count == 2)
    controller.editDraft("hold activity"); controller.send()
    try await wait { controller.state == .working && controller.selected?.pendingMessageID == nil }
    #expect(!recorder.events[0].current() && recorder.events[1].current())
    controller.stop()
    try await wait { !controller.isBusy }
    #expect(recorder.events.count == 2)
    await controller.disconnect()
    #expect(recorder.events.allSatisfy { !$0.current() })
  }

  @Test("Input alerts become invalid on submission or Stop without changing conversation ownership")
  func pendingInput() async throws {
    let root = repository.appendingPathComponent(".build/agent-chat-tests/input-notifications-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = ChatNotificationRecorder(), controller = try await makeController(root, recorder: recorder)
    controller.editDraft("hold questions"); controller.send()
    try await wait { controller.approvals.count == 1 && recorder.events.count == 1 }
    let owner = try #require(controller.selectedID), question = try #require(controller.approvals.first)
    controller.newConversation()
    #expect(recorder.events[0].current() && recorder.events[0].route.conversationID == owner)
    controller.answer(question.id, allow: false)
    #expect(!recorder.events[0].current())
    controller.stop(in: owner)
    controller.editDraft("hold approval"); controller.send()
    try await wait { controller.approvals.count == 1 && recorder.events.count == 2 }
    #expect(recorder.events[1].route.event == .inputRequired && recorder.events[1].current())
    controller.stop()
    #expect(!recorder.events[1].current())
    try await wait { !controller.hasActiveExecutions }
    #expect(recorder.events.count == 2)
    controller.editDraft("hold note-operation"); controller.send()
    try await wait { controller.state == .working && controller.selected?.pendingMessageID == nil }
    let token = try #require(controller.token)
    let proposed = Task { await controller.handle(.init(tool: .createNote,
      arguments: ["relative_path": .string("Private proposed Note.md"), "content": .string("Private proposed source")],
      conversationToken: token, runtimeContext: controller.runtimeContext(for: token))) }
    try await wait { controller.approvals.count == 1 && recorder.events.count == 3 }
    #expect(recorder.events[2].route.event == .inputRequired && recorder.events[2].current())
    let payload = String(decoding: try JSONEncoder().encode(recorder.events[2].route), as: UTF8.self)
    #expect(!payload.contains("Private") && !payload.contains("content"))
    controller.answer(try #require(controller.approvals.first?.id), allow: false)
    #expect(await proposed.value.error != nil && !recorder.events[2].current())
    controller.stop()
    try await wait { !controller.isBusy }
    await controller.disconnect()
  }

  @Test("A cold notification opens exact archived history without connecting, sending or substituting a target")
  func opening() async throws {
    let root = repository.appendingPathComponent(".build/agent-chat-tests/notification-opening-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = ChatNotificationRecorder(), controller = try await makeController(root, recorder: recorder)
    controller.editDraft("retained unsent draft")
    let archived = try #require(controller.selectedID), triptych = controller.triptychID
    controller.setArchived(archived, archived: true)
    try await controller.flushPersistence()
    await controller.disconnect()
    let reopened = AgentChatController(triptychID: triptych, root: root,
      notificationSink: { route, current in recorder.events.append((route, current)) }) { request in
        try! .init(requestID: request.requestID, result: .object([:]))
      }
    #expect(await reopened.selectNotification(.init(triptychID: triptych, conversationID: archived, event: .completed)))
    #expect(reopened.selectedID == archived && reopened.selected?.archivedAt != nil)
    #expect(reopened.selected?.draft == "retained unsent draft" && reopened.selected?.messages.isEmpty == true)
    #expect(reopened.connectionState == .disconnected && !reopened.canSend && recorder.events.isEmpty)
    #expect(await !reopened.selectNotification(.init(triptychID: UUID(), conversationID: archived, event: .completed)))
    #expect(await !reopened.selectNotification(.init(triptychID: triptych, conversationID: UUID(), event: .completed)))
    #expect(reopened.selectedID == archived)
  }

  @Test("Window notification routing preserves the open Note and its unsaved source")
  func windowRouting() async throws {
    let root = repository.appendingPathComponent(".build/agent-chat-tests/notification-window-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let vaults = ["Analyses", "Topics", "Works"].map { root.appendingPathComponent("Triptych/" + $0) }
    for directory in vaults { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    let source = "# Synthetic source\n\nKeep this Note open.\n"
    let file = vaults[0].appendingPathComponent("Source.md")
    try Data(source.utf8).write(to: file)
    let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
    do {
      let configured = try await store.configureTriptychCapabilities(paperAnalysisURL: vaults[0], topicKnowledgeURL: vaults[1],
        outputURL: vaults[2], portableContainerURL: root.appendingPathComponent("Triptych"), triptychName: "Notification fixture")
      let window = WindowModel(workspaceStore: store, requestedTriptychID: configured.id)
      await window.refreshWorkspaceAssignment(preferredTriptychID: configured.id)
      try await window.openWorkspaceVault(.paperAnalysis)
      let note = try #require(window.workspaceCatalog?.notes.first { $0.reference.relativePath == "Source.md" })
      let snapshot = try #require(try await window.documentController.noteSnapshot(
        .init(vaultID: note.reference.vaultID, relativePath: note.reference.relativePath)))
      window.documentController.installOpenedDocument(snapshot, vaultName: note.reference.vaultName, vaultRole: note.reference.vaultRole)
      let document = try #require(window.documentController.selectedDocument)
      let editor = window.documentController.session(for: document.editingTarget)
      editor.suppressAutosave = true; editor.editingSource = "Unsaved researcher argument"
      let chat = try #require(window.chatController)
      try await wait { chat.isLoaded }
      let target = try #require(chat.selectedID)
      chat.newConversation(); chat.editDraft("Other conversation draft")
      let current = chat.selectedID
      let route = SystemNotificationRoute.chat(.init(triptychID: configured.id, conversationID: target, event: .inputRequired))
      #expect(await window.openSystemNotification(route) == .chat)
      #expect(chat.selectedID == target && chat.connectionState == .disconnected)
      #expect(window.documentController.selectedDocument?.editingTarget == document.editingTarget)
      #expect(editor.editingSource == "Unsaved researcher argument")
      #expect(try Data(contentsOf: file) == Data(source.utf8))
      #expect(chat.conversations.first { $0.id == current }?.draft == "Other conversation draft")
      #expect(await window.openSystemNotification(.chat(.init(triptychID: configured.id, conversationID: UUID(), event: .completed))) == nil)
      #expect(chat.selectedID == target && !window.shellState.operationIssues.isEmpty)
      await store.shutdownApplicationRuntime()
    } catch { await store.shutdownApplicationRuntime(); throw error }
  }
}

@MainActor
private final class ChatNotificationRecorder {
  var events: [(route: AgentChatNotificationRoute, current: @MainActor () -> Bool)] = []
}
