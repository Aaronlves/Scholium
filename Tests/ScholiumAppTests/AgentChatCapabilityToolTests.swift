import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Agent capability controls", .serialized)
@MainActor
struct AgentChatCapabilityToolTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Agent capability fixture did not reach expected state")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("An active Agent turn can inspect and configure runtime Skills, Tools and Chat settings")
    func activeTurnCanConfigureCapabilities() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/capabilities-(UUID())")
        let suite = "scholium.agent-capabilities.(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let controller = AgentChatController(triptychID: UUID(), root: root, methodDefaults: defaults) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try await wait { controller.isLoaded }
        let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        controller.connect(executable: fixture, home: controller.runtimeHome, cli: fixture)
        try await wait { controller.state == .ready && controller.capabilities.hasMethods && !controller.capabilities.isRefreshing }

        controller.editDraft("hold capability configuration")
        controller.send()
        try await wait { controller.state == .working && controller.selected?.pendingMessageID == nil }
        let token = try #require(controller.token)
        let context = try #require(controller.runtimeContext(for: token))

        let inspected = await controller.handle(.init(tool: .capabilities, conversationToken: token, runtimeContext: context))
        let initial = try #require(inspected.result?.objectValue)
        #expect(inspected.error == nil)
        #expect(initial["schema_version"]?.intValue == ScholiumMCPContract.currentToolSchemaVersion)
        let configuration = try #require(initial["tool_configuration"]?.objectValue)
        let initialVersion = try #require(configuration["version"]?.stringValue)
        #expect(controller.capabilities.mayChange() == false)

        let method = try #require(controller.capabilities.methods.first { !$0.isProtected })
        let disabled = await controller.handle(
            .init(
                tool: .configureSkill,
                arguments: [
                    "action": .string("disable"), "path": .string(method.selection.path),
                ], conversationToken: token, runtimeContext: context))
        #expect(disabled.error == nil && disabled.result?.objectValue?["effective_enabled"]?.boolValue == false)
        let reenabled = await controller.handle(
            .init(
                tool: .configureSkill,
                arguments: [
                    "action": .string("enable"), "path": .string(method.selection.path),
                ], conversationToken: token, runtimeContext: context))
        #expect(reenabled.error == nil && reenabled.result?.objectValue?["effective_enabled"]?.boolValue == true)

        let associated = root.appendingPathComponent("agent-managed-skill")
        try FileManager.default.createDirectory(at: associated, withIntermediateDirectories: true)
        try "---\nname: agent-managed-skill\ndescription: Synthetic capability fixture.\n---\nKeep the exact fixture.\n"
            .write(to: associated.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let addedRoot = await controller.handle(
            .init(
                tool: .configureSkill,
                arguments: [
                    "action": .string("add_root"), "path": .string(associated.path),
                ], conversationToken: token, runtimeContext: context))
        #expect(addedRoot.error == nil && addedRoot.result?.objectValue?["skill_roots"]?.arrayValue?.contains(.string(associated.path)) == true)

        let added = await controller.handle(
            .init(
                tool: .configureTool,
                arguments: [
                    "action": .string("add"), "expected_version": .string(initialVersion),
                    "name": .string("agent-parser"), "kind": .string("remote"),
                    "address": .string("https://parser.example.invalid/mcp"), "enabled": .bool(false),
                ], conversationToken: token, runtimeContext: context))
        #expect(added.error == nil)
        let addedConfiguration = try #require(added.result?.objectValue?["configuration"]?.objectValue)
        let addedVersion = try #require(addedConfiguration["version"]?.stringValue)
        #expect(
            addedConfiguration["connections"]?.arrayValue?.contains {
                $0.objectValue?["name"]?.stringValue == "agent-parser"
            } == true)

        let enabled = await controller.handle(
            .init(
                tool: .configureTool,
                arguments: [
                    "action": .string("set_enabled"), "expected_version": .string(addedVersion),
                    "name": .string("agent-parser"), "enabled": .bool(true),
                ], conversationToken: token, runtimeContext: context))
        #expect(enabled.error == nil)

        let settings = await controller.handle(
            .init(
                tool: .configureChat,
                arguments: [
                    "action": .string("set_permission"), "permission": .string("fullAccess"),
                ], conversationToken: token, runtimeContext: context))
        #expect(settings.error == nil && controller.conversationPermissionForTests(conversationID: controller.selectedID!) == .fullAccess)
        #expect(controller.approvals.isEmpty)

        let mutation = Task { @MainActor in
            await controller.handle(.init(tool: .createNote, conversationToken: token, runtimeContext: context))
        }
        try await wait { controller.approvals.count == 1 }
        let approval = try #require(controller.approvals.first)
        controller.answer(approval.id, allow: false)
        let declined = await mutation.value
        #expect(declined.error?.code == .invalidRequest)
        #expect(controller.approvals.isEmpty)

        controller.stop()
        try await wait { controller.state == .ready && !controller.isBusy }
        await controller.disconnect()
    }
}

private extension AgentChatController {
    func conversationPermissionForTests(conversationID: UUID) -> AgentChatPermission? {
        selected?.id == conversationID ? selected?.permission : nil
    }
}
