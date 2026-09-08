import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Local method associations", .serialized)
@MainActor
struct AgentChatAssociationTests {
  @Test("Search renewal restores associated methods before dependent input can be sent", arguments: [false, true])
  func searchRenewalRestoresMethods(rejectRoots: Bool) async throws {
    let root = repository.appendingPathComponent(".build/agent-chat-tests/renewal-roots-\(UUID())")
    let suite = "scholium.renewal-roots.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let controller = AgentChatController(triptychID: UUID(), root: root, methodDefaults: defaults) { request in
      try! .init(requestID: request.requestID, result: .object([:]))
    }
    try await connect(controller)
    let folder = root.appendingPathComponent("source-check")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("---\nname: source-check\n---\nCheck sources.\n".utf8).write(to: folder.appendingPathComponent("SKILL.md"))
    controller.capabilities.associate(folder, threadID: nil)
    try await wait { !controller.capabilities.isRefreshing }
    let method = try #require(controller.capabilities.methods.first { $0.selection.path == folder.appendingPathComponent("SKILL.md").path })
    controller.editDraft("establish thread"); controller.send()
    try await wait { !controller.isBusy && controller.selected?.threadID != nil }
    let thread = controller.selected?.threadID
    controller.toggleMethod(method.selection)
    controller.editDraft("retained method request")
    let rejection = controller.runtimeHome.appendingPathComponent("reject-roots")
    if rejectRoots { try Data().write(to: rejection) }
    controller.setWebSearch(.live)
    try await wait { !controller.isRenewingSettings && !controller.isBusy && !controller.capabilities.isRefreshing }
    #expect(controller.selected?.threadID == thread && controller.selected?.draft == "retained method request")
    #expect(controller.selected?.selectedMethods == [method.selection])
    let counter = controller.runtimeHome.appendingPathComponent("roots-request-count")
    #expect(try String(contentsOf: counter, encoding: .utf8) == "2")
    if rejectRoots {
      #expect(controller.capabilities.associationError != nil && !controller.canSend)
      try FileManager.default.removeItem(at: rejection)
      controller.capabilities.refresh(threadID: thread, applyAssociations: true)
      try await wait { !controller.capabilities.isRefreshing }
    }
    #expect(controller.capabilities.associationError == nil)
    #expect(controller.capabilities.contains(method.selection) && controller.canSend)
    await controller.disconnect()
  }

  private var repository: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  }

  @Test("Disconnect during renewed connection initialization cancels roots and never publishes stale readiness")
  func cancelRenewalInitialization() async throws {
    let root = repository.appendingPathComponent(".build/agent-chat-tests/cancel-renewal-roots-\(UUID())")
    let suite = "scholium.cancel-renewal-roots.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let controller = AgentChatController(triptychID: UUID(), root: root, methodDefaults: defaults) { request in
      try! .init(requestID: request.requestID, result: .object([:]))
    }
    try await connect(controller)
    let folder = root.appendingPathComponent("method")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    controller.capabilities.associate(folder, threadID: nil)
    try await wait { !controller.capabilities.isRefreshing }
    controller.editDraft("establish"); controller.send()
    try await wait { !controller.isBusy && controller.selected?.threadID != nil }
    controller.editDraft("preserved after cancel")
    let marker = controller.runtimeHome.appendingPathComponent("hold-roots")
    let counter = controller.runtimeHome.appendingPathComponent("roots-request-count")
    try Data().write(to: marker)
    controller.setWebSearch(.live)
    try await wait { (try? String(contentsOf: counter, encoding: .utf8)) == "2" }
    #expect(controller.connectionState == .connecting && controller.isRenewingSettings && !controller.canSend)
    await controller.disconnect()
    #expect(controller.connectionState == .disconnected && !controller.isRenewingSettings)
    #expect(!controller.capabilities.isConnected && !controller.capabilities.isRefreshing)
    #expect(controller.selected?.draft == "preserved after cancel")
    try FileManager.default.removeItem(at: marker)
    try await connect(controller)
    #expect(controller.canSend && controller.capabilities.associatedFolders == [folder.path])
    #expect(try String(contentsOf: counter, encoding: .utf8) == "3")
    await controller.disconnect()
  }
  private func wait(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while !condition() {
      try #require(ContinuousClock.now < deadline, "Association fixture did not reach expected state")
      try await Task.sleep(for: .milliseconds(10))
    }
  }
  private func connect(_ controller: AgentChatController, home: URL? = nil) async throws {
    try await wait { controller.isLoaded }
    let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
    controller.connect(executable: fixture, home: home ?? controller.runtimeHome, cli: fixture)
    try await wait { controller.connectionState == .ready && !controller.capabilities.isRefreshing }
  }

  @Test("Association survives reconnect, stays scoped to its settings folder, and removal preserves Skill bytes")
  func lifecycle() async throws {
    let root = repository.appendingPathComponent(".build/agent-chat-tests/roots-\(UUID())")
    let suite = "scholium.association-fixture.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let controller = AgentChatController(triptychID: UUID(), root: root, methodDefaults: defaults) { request in
      try! .init(requestID: request.requestID, result: .object(["status": .string("ok")]))
    }
    let folder = root.appendingPathComponent("exact-source-method")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let skill = folder.appendingPathComponent("SKILL.md")
    let original = Data("---\r\nname: exact-source-method\r\n---\r\nPreserve Unicode 😀\r\n".utf8)
    try original.write(to: skill)
    try await connect(controller)
    controller.capabilities.associate(folder, threadID: nil)
    try await wait { !controller.capabilities.isRefreshing }
    #expect(controller.capabilities.associatedFolders == [folder.path])
    #expect(controller.capabilities.methods.contains { $0.selection.path == skill.path })
    await controller.disconnect()
    try await connect(controller)
    #expect(controller.capabilities.associatedFolders == [folder.path])
    #expect(controller.capabilities.methods.contains { $0.selection.path == skill.path })
    await controller.disconnect()
    try await connect(controller, home: root.appendingPathComponent("another-configuration"))
    #expect(controller.capabilities.associatedFolders.isEmpty)
    #expect(controller.capabilities.methods.allSatisfy { $0.selection.path != skill.path })
    await controller.disconnect()
    try await connect(controller)
    controller.capabilities.removeAssociation(folder.path, threadID: nil)
    try await wait { !controller.capabilities.isRefreshing }
    #expect(controller.capabilities.methods.allSatisfy { $0.selection.path != skill.path })
    #expect(try Data(contentsOf: skill) == original)
    await controller.disconnect()
    try await connect(controller)
    #expect(controller.capabilities.associatedFolders.isEmpty)
    await controller.disconnect()
  }

  @Test("Failed application retains the chosen folder, never retries on background refresh, and can be repaired")
  func failureAndBusyScope() async throws {
    let root = repository.appendingPathComponent(".build/agent-chat-tests/roots-\(UUID())")
    let suite = "scholium.association-fixture.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let controller = AgentChatController(triptychID: UUID(), root: root, methodDefaults: defaults) { request in
      try! .init(requestID: request.requestID, result: .object(["status": .string("ok")]))
    }
    try await connect(controller)
    let folder = root.appendingPathComponent("associated-method")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let reject = controller.runtimeHome.appendingPathComponent("reject-roots")
    let counter = controller.runtimeHome.appendingPathComponent("roots-request-count")
    try Data().write(to: reject)
    controller.capabilities.associate(folder, threadID: nil)
    try await wait { !controller.capabilities.isRefreshing }
    #expect(controller.capabilities.associatedFolders == [folder.path])
    #expect(controller.capabilities.associationError != nil && !controller.capabilities.hasMethods)
    controller.capabilities.refresh(threadID: nil)
    try await wait { !controller.capabilities.isRefreshing }
    #expect(try String(contentsOf: counter, encoding: .utf8) == "1")
    try FileManager.default.removeItem(at: reject)
    controller.capabilities.refresh(threadID: nil, applyAssociations: true)
    try await wait { !controller.capabilities.isRefreshing }
    #expect(controller.capabilities.associationError == nil && controller.capabilities.hasMethods)
    #expect(try String(contentsOf: counter, encoding: .utf8) == "2")
    controller.editDraft("hold work")
    controller.send()
    try await wait { controller.state == .working && controller.selected?.pendingMessageID == nil }
    controller.capabilities.removeAssociation(folder.path, threadID: controller.selected?.threadID)
    #expect(controller.capabilities.associatedFolders == [folder.path])
    await controller.disconnect()
    try FileManager.default.removeItem(at: folder)
    try await connect(controller)
    #expect(controller.capabilities.associationError != nil && controller.capabilities.associatedFolders == [folder.path])
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    controller.capabilities.refresh(threadID: nil, applyAssociations: true)
    try await wait { !controller.capabilities.isRefreshing }
    #expect(controller.capabilities.associationError == nil)
    try FileManager.default.removeItem(at: folder)
    controller.capabilities.refresh(threadID: nil, applyAssociations: true)
    try await wait { !controller.capabilities.isRefreshing }
    #expect(controller.capabilities.associationError != nil && !controller.capabilities.hasMethods)
    controller.capabilities.removeAssociation(folder.path, threadID: nil)
    try await wait { !controller.capabilities.isRefreshing }
    #expect(controller.capabilities.associationError == nil && controller.capabilities.hasMethods)
    await controller.disconnect()
  }

  @Test("Two connections sharing launch preferences merge folder choices without silently changing another process")
  func sharedPreferences() async throws {
    let root = repository.appendingPathComponent(".build/agent-chat-tests/roots-\(UUID())")
    let suite = "scholium.association-fixture.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let first = AgentChatController(triptychID: UUID(), root: root, methodDefaults: defaults) { request in
      try! .init(requestID: request.requestID, result: .object([:]))
    }
    let second = AgentChatController(triptychID: UUID(), root: root, methodDefaults: defaults) { request in
      try! .init(requestID: request.requestID, result: .object([:]))
    }
    let folderA = root.appendingPathComponent("method-a"), folderB = root.appendingPathComponent("method-b")
    for folder in [folderA, folderB] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    try await connect(first)
    try await connect(second)
    first.capabilities.associate(folderA, threadID: nil)
    try await wait { !first.capabilities.isRefreshing }
    second.capabilities.associate(folderB, threadID: nil)
    try await wait { !second.capabilities.isRefreshing }
    #expect(second.capabilities.associatedFolders == [folderA.path, folderB.path])
    #expect(first.capabilities.associatedFolders == [folderA.path])
    first.capabilities.refresh(threadID: nil)
    try await wait { !first.capabilities.isRefreshing }
    #expect(first.capabilities.associatedFolders == [folderA.path, folderB.path])
    #expect(first.capabilities.associationError != nil && !first.capabilities.hasMethods)
    first.capabilities.refresh(threadID: nil, applyAssociations: true)
    try await wait { !first.capabilities.isRefreshing }
    #expect(first.capabilities.associationError == nil && first.capabilities.hasMethods)
    #expect(first.capabilities.methods.contains { $0.selection.path == folderB.appendingPathComponent("SKILL.md").path })
    await first.disconnect()
    await second.disconnect()
  }
}
