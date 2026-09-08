import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Tool authentication lifecycle", .serialized)
@MainActor
struct AgentChatToolAuthenticationTests {
  private var repository: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  }
  private func wait(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while !condition() {
      try #require(ContinuousClock.now < deadline, "Tool authentication fixture did not reach expected state")
      try await Task.sleep(for: .milliseconds(10))
    }
  }
  private func connect(_ controller: AgentChatController) async throws {
    try await wait { controller.isLoaded }
    try FileManager.default.createDirectory(at: controller.runtimeHome, withIntermediateDirectories: true)
    try Data().write(to: controller.runtimeHome.appendingPathComponent("oauth-fixture"))
    let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
    controller.connect(executable: fixture, home: controller.runtimeHome, cli: fixture)
    try await wait { controller.capabilities.hasTools && !controller.capabilities.isRefreshing }
  }

  @Test("Opening a page does not confirm sign-in; only the matching runtime event does")
  func authentication() async throws {
    let root = repository.appendingPathComponent(".build/agent-chat-tests/auth-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = AgentChatController(triptychID: UUID(), root: root) { request in
      try! .init(requestID: request.requestID, result: .object([:]))
    }
    try await connect(controller)
    let capabilities = controller.capabilities
    let server = try #require(capabilities.tools.first { $0.name == "fixture-library" })
    controller.editDraft("hold while signing in")
    controller.send()
    try await wait { controller.state == .working && controller.selected?.pendingMessageID == nil }
    let authThread = try #require(controller.selected?.threadID)
    #expect(capabilities.canSignIn(server))
    var opened: [URL] = []
    capabilities.signIn(server, threadID: authThread) { opened.append($0) }
    try await wait { capabilities.authorizationURL != nil }
    #expect(opened.count == 1 && capabilities.authenticationNotice == nil)
    #expect(capabilities.authenticatingTool == server.name && !capabilities.canSignIn(server))
    capabilities.authenticationCompleted(["name": .string(server.name), "threadId": .string("another"), "success": .bool(true)], visibleThreadID: nil)
    #expect(capabilities.authenticatingTool == server.name)
    try "failure".write(to: controller.runtimeHome.appendingPathComponent("finish-tool-auth"), atomically: true, encoding: .utf8)
    capabilities.refresh(threadID: nil)
    try await wait { capabilities.authenticatingTool == nil && capabilities.hasTools && !capabilities.isRefreshing }
    #expect(capabilities.authenticationError != nil && capabilities.authenticationNotice == nil && capabilities.authorizationURL == nil)
    capabilities.signIn(server, threadID: authThread) { opened.append($0) }
    try await wait { capabilities.authorizationURL != nil }
    #expect(opened.count == 2)
    try "success".write(to: controller.runtimeHome.appendingPathComponent("finish-tool-auth"), atomically: true, encoding: .utf8)
    capabilities.refresh(threadID: nil)
    try await wait { capabilities.authenticatingTool == nil && capabilities.hasTools && !capabilities.isRefreshing }
    #expect(capabilities.authenticationNotice?.contains(server.name) == true)
    #expect(capabilities.authorizationURL == nil && capabilities.authenticationError == nil)
    #expect(capabilities.tools.first { $0.name == server.name }?.connectionStatus == "notStarted")
    try await controller.flushPersistence()
    let archive = root.appendingPathComponent(controller.triptychID.uuidString).appendingPathComponent("conversations.json")
    #expect(try !String(contentsOf: archive, encoding: .utf8).contains("auth.example.test"))
    await controller.disconnect()
  }

  @Test("Unsafe authorization pages and late disconnected requests cannot open the browser")
  func unsafeAndDisconnect() async throws {
    let root = repository.appendingPathComponent(".build/agent-chat-tests/auth-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let controller = AgentChatController(triptychID: UUID(), root: root) { request in
      try! .init(requestID: request.requestID, result: .object([:]))
    }
    try await connect(controller)
    var opened = 0
    let unsafe = controller.runtimeHome.appendingPathComponent("unsafe-auth-url")
    try Data().write(to: unsafe)
    let server = try #require(controller.capabilities.tools.first { $0.name == "fixture-library" })
    controller.capabilities.signIn(server, threadID: nil) { _ in opened += 1 }
    try await wait { controller.capabilities.authenticationError != nil }
    #expect(opened == 0 && controller.capabilities.authorizationURL == nil)
    try FileManager.default.removeItem(at: unsafe)
    try Data().write(to: controller.runtimeHome.appendingPathComponent("hold-tool-auth"))
    controller.capabilities.signIn(server, threadID: nil) { _ in opened += 1 }
    #expect(controller.capabilities.authenticatingTool == server.name)
    await controller.disconnect()
    #expect(opened == 0 && controller.capabilities.authenticatingTool == nil)
    controller.capabilities.authenticationCompleted(["name": .string(server.name), "success": .bool(true)], visibleThreadID: nil)
    #expect(controller.capabilities.authenticationNotice == nil)
  }
}
