import Combine
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
    private func wait(
        for changes: ObservableObjectPublisher,
        sourceLocation: SourceLocation = #_sourceLocation,
        until condition: () -> Bool
    ) async throws {
        let events = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let observation = changes.sink { events.continuation.yield(()) }
        let deadline = Task {
            do {
                try await Task.sleep(for: .seconds(8))
                events.continuation.finish()
            } catch {}
        }
        defer {
            observation.cancel()
            deadline.cancel()
            events.continuation.finish()
        }
        try Task.checkCancellation()
        if condition() { return }
        // objectWillChange precedes mutation. Read only after resuming on the
        // main actor, once the synchronous publication and mutation finish.
        for await _ in events.stream {
            try Task.checkCancellation()
            if condition() { return }
        }
        try Task.checkCancellation()
        try #require(condition(), "Tool authentication fixture did not reach expected state", sourceLocation: sourceLocation)
    }
    private func connect(_ controller: AgentChatController) async throws {
        try #require(await controller.waitUntilLoaded(), "Chat history did not finish loading")
        try FileManager.default.createDirectory(at: controller.runtimeHome, withIntermediateDirectories: true)
        try Data().write(to: controller.runtimeHome.appendingPathComponent("oauth-fixture"))
        let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        controller.connect(executable: fixture, home: controller.runtimeHome, helper: fixture)
        try #require(await controller.waitUntilConnectionReady(), "Chat runtime did not finish capability initialization")
    }

    @Test("Agent tool sign-in accepts only completion from its exact runtime thread")
    func agentAuthenticationRequiresExactThread() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/agent-auth-thread-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = fixtureChatController(triptychID: UUID(), root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        do {
            try await connect(controller)
            controller.editDraft("hold while authorizing agent tools")
            controller.send()
            try await wait(for: controller.objectWillChange) { controller.state == .working && controller.selected?.pendingMessageID == nil }
            let token = try #require(controller.token)
            let context = try #require(controller.runtimeContext(for: token))
            let caps = controller.capabilities
            let request = ScholiumMCPBridgeRequest(
                tool: .configureTool,
                arguments: ["action": .string("sign_in"), "name": .string("fixture-library")],
                conversationToken: token, runtimeContext: context)
            let started = await controller.handle(request)
            try #require(started.error == nil && started.result?.objectValue?["authorization_url"]?.stringValue != nil)

            caps.authenticationCompleted(
                ["name": .string("fixture-library"), "threadId": .string("another-thread"), "success": .bool(true)],
                visibleThreadID: context.threadID)
            #expect(caps.authenticationNotice == nil && caps.authenticationError == nil)
            #expect(caps.authenticationFeedbackTool == nil)
            let repeated = await controller.handle(request)
            #expect(repeated.error?.code == .conflict)

            caps.authenticationCompleted(
                [
                    "name": .string("fixture-library"), "threadId": .string(context.threadID), "success": .bool(false),
                    "error": .string("Fixture authorization declined"),
                ],
                visibleThreadID: context.threadID)
            try await wait(for: caps.objectWillChange) { caps.hasTools && !caps.isRefreshing }
            #expect(caps.authenticationNotice == nil && caps.authenticationError == "Fixture authorization declined")
            let server = try #require(caps.tools.first { $0.name == "fixture-library" })
            #expect(caps.canSignIn(server))
            #expect(controller.runtimeContext(for: token) == context)
        } catch {
            await controller.disconnect()
            throw error
        }
        await controller.disconnect()
    }

    @Test("Native tool sign-in waits for an existing Agent authorization flow")
    func nativeSignInWaitsForAgentAuthorization() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/agent-auth-overlap-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = fixtureChatController(triptychID: UUID(), root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        do {
            try await connect(controller)
            controller.editDraft("hold while authorizing agent tools")
            controller.send()
            try await wait(for: controller.objectWillChange) { controller.state == .working && controller.selected?.pendingMessageID == nil }
            let token = try #require(controller.token)
            let context = try #require(controller.runtimeContext(for: token))
            let caps = controller.capabilities
            let server = try #require(caps.tools.first { $0.name == "fixture-library" })
            let started = await controller.handle(
                .init(
                    tool: .configureTool,
                    arguments: ["action": .string("sign_in"), "name": .string(server.name)],
                    conversationToken: token, runtimeContext: context))
            try #require(started.error == nil)
            #expect(!caps.canSignIn(server))
            var opened = 0
            caps.signIn(server, threadID: context.threadID) { _ in opened += 1 }
            try await wait(for: caps.objectWillChange) { caps.authenticationError != nil || caps.authorizationURL != nil }
            #expect(opened == 0 && caps.authorizationURL == nil && caps.authenticatingTool == nil)
            caps.authenticationCompleted(
                ["name": .string(server.name), "threadId": .string(context.threadID), "success": .bool(false)],
                visibleThreadID: context.threadID)
            try await wait(for: caps.objectWillChange) { caps.hasTools && !caps.isRefreshing }
            #expect(caps.canSignIn(server) && caps.authenticatingTool == nil)
        } catch {
            await controller.disconnect()
            throw error
        }
        await controller.disconnect()
    }

    @Test("Opening a page does not confirm sign-in; only the matching runtime event does")
    func authentication() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/auth-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = fixtureChatController(triptychID: UUID(), root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        do {
            try await connect(controller)
            let capabilities = controller.capabilities
            let server = try #require(capabilities.tools.first { $0.name == "fixture-library" })
            controller.editDraft("hold while signing in")
            controller.send()
            try await wait(for: controller.objectWillChange) { controller.state == .working && controller.selected?.pendingMessageID == nil }
            let authThread = try #require(controller.selected?.threadID)
            #expect(capabilities.canSignIn(server))
            var opened: [URL] = []
            capabilities.signIn(server, threadID: authThread) { opened.append($0) }
            try await wait(for: capabilities.objectWillChange) { capabilities.authorizationURL != nil }
            #expect(opened.count == 1 && capabilities.authenticationNotice == nil)
            #expect(capabilities.authenticatingTool == server.name && !capabilities.canSignIn(server))
            #expect(capabilities.authenticationFeedbackTool == server.name)
            capabilities.authenticationCompleted(["name": .string(server.name), "threadId": .string("another"), "success": .bool(true)], visibleThreadID: nil)
            #expect(capabilities.authenticatingTool == server.name)
            try "failure".write(to: controller.runtimeHome.appendingPathComponent("finish-tool-auth"), atomically: true, encoding: .utf8)
            capabilities.refresh(threadID: nil)
            try await wait(for: capabilities.objectWillChange) { capabilities.authenticatingTool == nil && capabilities.hasTools && !capabilities.isRefreshing }
            #expect(capabilities.authenticationError != nil && capabilities.authenticationNotice == nil && capabilities.authorizationURL == nil)
            #expect(capabilities.authenticationFeedbackTool == server.name)
            capabilities.signIn(server, threadID: authThread) { opened.append($0) }
            try await wait(for: capabilities.objectWillChange) { capabilities.authorizationURL != nil }
            #expect(opened.count == 2)
            try "success".write(to: controller.runtimeHome.appendingPathComponent("finish-tool-auth"), atomically: true, encoding: .utf8)
            capabilities.refresh(threadID: nil)
            try await wait(for: capabilities.objectWillChange) { capabilities.authenticatingTool == nil && capabilities.hasTools && !capabilities.isRefreshing }
            #expect(capabilities.authenticationNotice?.contains(server.name) == true)
            #expect(capabilities.authorizationURL == nil && capabilities.authenticationError == nil)
            #expect(capabilities.tools.first { $0.name == server.name }?.connectionStatus == "notStarted")
            try await controller.flushPersistence()
            let archive = root.appendingPathComponent(controller.triptychID.uuidString).appendingPathComponent("conversations.json")
            #expect(try !String(contentsOf: archive, encoding: .utf8).contains("auth.example.test"))
        } catch {
            await controller.disconnect()
            throw error
        }
        await controller.disconnect()
    }

    @Test("Unsafe authorization pages and late disconnected requests cannot open the browser")
    func unsafeAndDisconnect() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/auth-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = fixtureChatController(triptychID: UUID(), root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        do {
            try await connect(controller)
            var opened = 0
            let unsafe = controller.runtimeHome.appendingPathComponent("unsafe-auth-url")
            try Data().write(to: unsafe)
            let server = try #require(controller.capabilities.tools.first { $0.name == "fixture-library" })
            controller.capabilities.signIn(server, threadID: nil) { _ in opened += 1 }
            try await wait(for: controller.capabilities.objectWillChange) { controller.capabilities.authenticationError != nil }
            #expect(opened == 0 && controller.capabilities.authorizationURL == nil)
            try FileManager.default.removeItem(at: unsafe)
            try Data().write(to: controller.runtimeHome.appendingPathComponent("hold-tool-auth"))
            controller.capabilities.signIn(server, threadID: nil) { _ in opened += 1 }
            #expect(controller.capabilities.authenticatingTool == server.name)
            await controller.disconnect()
            #expect(opened == 0 && controller.capabilities.authenticatingTool == nil)
            #expect(controller.capabilities.authenticationFeedbackTool == nil)
            controller.capabilities.authenticationCompleted(["name": .string(server.name), "success": .bool(true)], visibleThreadID: nil)
            #expect(controller.capabilities.authenticationNotice == nil)
        } catch {
            await controller.disconnect()
            throw error
        }
    }
}
