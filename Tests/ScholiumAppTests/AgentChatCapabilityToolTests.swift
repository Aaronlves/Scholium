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

    private func wait(_ condition: () -> Bool, reason: String = "expected state") async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Agent capability fixture did not reach \(reason)")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test(
        "Successful Agent capability writes refresh retained inventory and native configuration",
        arguments: ["skill", "tool"])
    func successfulWriteRefreshesRetainedCapabilities(_ operation: String) async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/capability-refresh-\(UUID())")
        let suite = "scholium.agent-capability-refresh.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let controller = fixtureChatController(triptychID: UUID(), root: root, methodDefaults: defaults) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        do {
            try #require(await controller.waitUntilLoaded())
            let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
            controller.connect(executable: fixture, home: controller.runtimeHome, helper: fixture)
            try #require(await controller.waitUntilConnectionReady())
            controller.editDraft("hold capability configuration")
            controller.send()
            try await wait({ controller.state == .working && controller.selected?.pendingMessageID == nil }, reason: "working turn")
            let token = try #require(controller.token)
            let context = try #require(controller.runtimeContext(for: token))
            let caps = controller.capabilities
            let method = try #require(caps.methods.first { !$0.isProtected })
            let inspected = await controller.handle(.init(tool: .capabilities, conversationToken: token, runtimeContext: context))
            let initialVersion = try #require(inspected.result?.objectValue?["tool_configuration"]?.objectValue?["version"]?.stringValue)
            let request: ScholiumMCPBridgeRequest
            if operation == "skill" {
                request = .init(
                    tool: .configureSkill,
                    arguments: ["action": .string("disable"), "path": .string(method.selection.path)],
                    conversationToken: token, runtimeContext: context)
            } else {
                request = .init(
                    tool: .configureTool,
                    arguments: [
                        "action": .string("add"), "expected_version": .string(initialVersion),
                        "name": .string("retained-parser"), "kind": .string("remote"),
                        "address": .string("https://parser.example.invalid/mcp"), "enabled": .bool(false),
                    ], conversationToken: token, runtimeContext: context)
            }
            let response = await controller.handle(request)
            try #require(response.error == nil)
            try await wait({ !caps.isRefreshing && !caps.isChanging }, reason: "settled capability refresh")
            #expect(caps.hasMethods && caps.hasTools && caps.workspaceReady)
            #expect(caps.methodError == nil && caps.toolError == nil && caps.toolConfigurationError == nil)
            #expect(caps.tools.contains { $0.name == "scholium" })
            #expect(controller.state == .working && controller.runtimeContext(for: token) == context)

            let expectedVersion: String
            if operation == "skill" {
                #expect(FileManager.default.fileExists(atPath: controller.runtimeHome.appendingPathComponent("method-disabled").path))
                #expect(caps.methods.first { $0.selection.path == method.selection.path }?.enabled == false)
                #expect(!caps.contains(method.selection))
                expectedVersion = initialVersion
            } else {
                expectedVersion = try #require(response.result?.objectValue?["configuration"]?.objectValue?["version"]?.stringValue)
                let saved = try Data(contentsOf: controller.runtimeHome.appendingPathComponent("fixture-tool-config.json"))
                let configuration = try JSONDecoder().decode(MCPJSONValue.self, from: saved).objectValue
                #expect(configuration?["servers"]?.objectValue?["retained-parser"]?.objectValue?["enabled"]?.boolValue == false)
                #expect(caps.toolConnections.first { $0.name == "retained-parser" }?.enabled == false)
                #expect(caps.tools.first { $0.name == "retained-parser" }?.connectionStatus == "disabled")
                #expect(expectedVersion != initialVersion)
            }

            controller.stop()
            try await wait({ controller.state == .ready && !controller.isBusy }, reason: "idle conversation")
            #expect(!caps.isChanging && !caps.isRefreshing && caps.canConfigureTools)
            #expect(await controller.waitUntilConnectionReady())
            #expect(caps.editTool()?.revision == expectedVersion)
            if operation == "tool" {
                #expect(caps.editTool(named: "retained-parser")?.revision == expectedVersion)
            }
        } catch {
            await controller.disconnect()
            throw error
        }
        await controller.disconnect()
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
        let controller = fixtureChatController(triptychID: UUID(), root: root, methodDefaults: defaults) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try await wait({ controller.isLoaded }, reason: "loaded")
        let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        controller.connect(executable: fixture, home: controller.runtimeHome, helper: fixture)
        try await wait(
            { controller.state == .ready && controller.capabilities.hasMethods && !controller.capabilities.isRefreshing }, reason: "ready capabilities")

        controller.editDraft("hold capability configuration")
        controller.send()
        try await wait({ controller.state == .working && controller.selected?.pendingMessageID == nil }, reason: "working turn")
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

        let associated = try #require(controller.workingDirectory).appendingPathComponent("skills/agent-managed-skill")
        try FileManager.default.createDirectory(at: associated, withIntermediateDirectories: true)
        try "---\nname: agent-managed-skill\ndescription: Synthetic capability fixture.\n---\nKeep the exact fixture.\n"
            .write(to: associated.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let refreshed = await controller.handle(.init(tool: .capabilities, conversationToken: token, runtimeContext: context))
        #expect(refreshed.error == nil)
        #expect(
            refreshed.result?.objectValue?["skills"]?.arrayValue?.contains {
                $0.objectValue?["path"]?.stringValue == associated.appendingPathComponent("SKILL.md").path
            } == true)

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

    @Test(
        "Stop during capability discovery prevents later configuration writes",
        arguments: [
            "selected_skills", "skill_enable", "tool_write", "sign_in",
        ])
    func stoppedDiscoveryDoesNotWrite(_ operation: String) async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/capability-stop-\(UUID())")
        let suite = "scholium.agent-capability-stop.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let controller = fixtureChatController(triptychID: UUID(), root: root, methodDefaults: defaults) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try await wait { controller.isLoaded }
        if operation == "sign_in" {
            FileManager.default.createFile(atPath: controller.runtimeHome.appendingPathComponent("oauth-fixture").path, contents: Data())
        }
        let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        controller.connect(executable: fixture, home: controller.runtimeHome, helper: fixture)
        try await wait { controller.state == .ready && controller.capabilities.hasMethods && !controller.capabilities.isRefreshing }
        controller.editDraft("hold capability configuration")
        controller.send()
        try await wait { controller.state == .working && controller.selected?.pendingMessageID == nil }
        let token = try #require(controller.token)
        let context = try #require(controller.runtimeContext(for: token))
        let method = try #require(controller.capabilities.methods.first { !$0.isProtected })
        let inventory = await controller.handle(.init(tool: .capabilities, conversationToken: token, runtimeContext: context))
        let version = try #require(inventory.result?.objectValue?["tool_configuration"]?.objectValue?["version"]?.stringValue)
        let hold = operation == "sign_in" ? "tools-list" : "skills-list"
        let home = controller.runtimeHome
        FileManager.default.createFile(atPath: home.appendingPathComponent("hold-capability-\(hold)").path, contents: Data())
        let request: ScholiumMCPBridgeRequest
        switch operation {
        case "selected_skills":
            request = .init(
                tool: .configureChat,
                arguments: [
                    "action": .string("set_selected_skills"), "skill_paths": .array([.string(method.selection.path)]),
                ], conversationToken: token, runtimeContext: context)
        case "skill_enable":
            request = .init(
                tool: .configureSkill,
                arguments: [
                    "action": .string("disable"), "path": .string(method.selection.path),
                ], conversationToken: token, runtimeContext: context)
        case "tool_write":
            request = .init(
                tool: .configureTool,
                arguments: [
                    "action": .string("add"), "expected_version": .string(version),
                    "name": .string("stopped-parser"), "kind": .string("remote"),
                    "address": .string("https://parser.example.invalid/mcp"),
                ], conversationToken: token, runtimeContext: context)
        default:
            request = .init(
                tool: .configureTool,
                arguments: [
                    "action": .string("sign_in"), "name": .string("fixture-library"),
                ], conversationToken: token, runtimeContext: context)
        }
        let call = Task { @MainActor in await controller.handle(request) }
        try await wait { FileManager.default.fileExists(atPath: home.appendingPathComponent("pending-capability-\(hold)").path) }
        controller.stop()
        let response = await call.value
        #expect(response.error?.code == .invalidRequest)
        #expect(controller.selected?.selectedMethods == nil)
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("method-disabled").path))
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("fixture-tool-config.json").path))
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("capability-sign-in-requested").path))
        try await wait { controller.state == .ready && !controller.isBusy }
        await controller.disconnect()
    }

    @Test("A saved tool configuration with failed readback reports an uncertain outcome")
    func savedToolWithLostReadbackIsUncertain() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/capability-readback-\(UUID())")
        let suite = "scholium.agent-capability-readback.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let controller = fixtureChatController(triptychID: UUID(), root: root, methodDefaults: defaults) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try await wait({ controller.isLoaded }, reason: "readback fixture loaded")
        let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        controller.connect(executable: fixture, home: controller.runtimeHome, helper: fixture)
        try await wait(
            { controller.state == .ready && controller.capabilities.hasMethods && !controller.capabilities.isRefreshing }, reason: "readback fixture ready")
        controller.editDraft("hold capability configuration")
        controller.send()
        try await wait({ controller.state == .working && controller.selected?.pendingMessageID == nil }, reason: "readback working turn")
        let token = try #require(controller.token)
        let context = try #require(controller.runtimeContext(for: token))
        let inspected = await controller.handle(.init(tool: .capabilities, conversationToken: token, runtimeContext: context))
        let version = try #require(inspected.result?.objectValue?["tool_configuration"]?.objectValue?["version"]?.stringValue)
        FileManager.default.createFile(
            atPath: controller.runtimeHome.appendingPathComponent("fail-config-read-after-write").path, contents: Data())
        let result = await controller.handle(
            .init(
                tool: .configureTool,
                arguments: [
                    "action": .string("add"), "expected_version": .string(version),
                    "name": .string("saved-parser"), "kind": .string("remote"),
                    "address": .string("https://parser.example.invalid/mcp"),
                ], conversationToken: token, runtimeContext: context))
        #expect(result.error?.code == .operationUncertain)
        let saved = try String(contentsOf: controller.runtimeHome.appendingPathComponent("fixture-tool-config.json"), encoding: .utf8)
        #expect(saved.contains("saved-parser"))
        controller.stop()
        await controller.disconnect()
    }

    @Test("Stop after a Skill write begins reports an uncertain outcome")
    func stoppedSkillWriteIsUncertain() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/capability-skill-ack-\(UUID())")
        let suite = "scholium.agent-capability-skill-ack.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let controller = fixtureChatController(triptychID: UUID(), root: root, methodDefaults: defaults) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try await wait({ controller.isLoaded }, reason: "Skill fixture loaded")
        let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        controller.connect(executable: fixture, home: controller.runtimeHome, helper: fixture)
        try await wait(
            { controller.state == .ready && controller.capabilities.hasMethods && !controller.capabilities.isRefreshing }, reason: "Skill fixture ready")
        controller.editDraft("hold capability configuration")
        controller.send()
        try await wait({ controller.state == .working && controller.selected?.pendingMessageID == nil }, reason: "Skill working turn")
        let token = try #require(controller.token)
        let context = try #require(controller.runtimeContext(for: token))
        let method = try #require(controller.capabilities.methods.first { !$0.isProtected })
        let home = controller.runtimeHome
        FileManager.default.createFile(atPath: home.appendingPathComponent("hold-capability-skill-ack").path, contents: Data())
        let call = Task { @MainActor in
            await controller.handle(
                .init(
                    tool: .configureSkill,
                    arguments: ["action": .string("disable"), "path": .string(method.selection.path)],
                    conversationToken: token, runtimeContext: context))
        }
        try await wait({ FileManager.default.fileExists(atPath: home.appendingPathComponent("pending-capability-skill-ack").path) }, reason: "Skill write sent")
        controller.stop()
        let result = await call.value
        #expect(result.error?.code == .operationUncertain)
        #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("method-disabled").path))
        await controller.disconnect()
    }
}

private extension AgentChatController {
    func conversationPermissionForTests(conversationID: UUID) -> AgentChatPermission? {
        selected?.id == conversationID ? selected?.permission : nil
    }
}
