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

    @Test("Successful Agent Skill writes refresh retained inventory and native configuration")
    func successfulWriteRefreshesRetainedCapabilities() async throws {
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
        let response = await controller.handle(
            .init(
                tool: .configureSkill,
                arguments: ["action": .string("disable"), "path": .string(method.selection.path)],
                conversationToken: token, runtimeContext: context))
        try #require(response.error == nil)
        try await wait({ !caps.isRefreshing && !caps.isChanging }, reason: "settled capability refresh")
        #expect(caps.hasMethods && caps.hasTools && caps.workspaceReady)
        #expect(caps.methodError == nil && caps.toolError == nil && caps.toolConfigurationError == nil)
        #expect(FileManager.default.fileExists(atPath: controller.runtimeHome.appendingPathComponent("method-disabled").path))
        #expect(caps.methods.first { $0.selection.path == method.selection.path }?.enabled == false)
        #expect(!caps.contains(method.selection))
        controller.stop()
        try await wait({ controller.state == .ready && !controller.isBusy }, reason: "idle conversation")
        #expect(caps.canConfigureTools)
        await controller.disconnect()
    }

    @Test("An active Agent turn can inspect and configure Skills but cannot grant itself authority")
    func activeTurnCanConfigureCapabilities() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/capabilities-\(UUID())")
        let suite = "scholium.agent-capabilities.\(UUID())"
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
        #expect(added.error?.code == .invalidRequest)
        #expect(!FileManager.default.fileExists(atPath: controller.runtimeHome.appendingPathComponent("fixture-tool-config.json").path))
        let settings = await controller.handle(
            .init(
                tool: .configureChat,
                arguments: ["action": .string("set_permission"), "permission": .string("fullAccess")],
                conversationToken: token, runtimeContext: context))
        #expect(settings.error?.code == .invalidRequest && controller.selected?.permission == .ask)
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
            "selected_skills", "skill_enable", "sign_in",
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
        #expect(inventory.error == nil)
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

    @Test("Agent connection changes are denied regardless of supplied revision or execution fields")
    func modelConnectionWritesRequireNativeSettings() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/capability-authority-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = fixtureChatController(triptychID: UUID(), root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try #require(await controller.waitUntilLoaded())
        let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        controller.connect(executable: fixture, home: controller.runtimeHome, helper: fixture)
        try #require(await controller.waitUntilConnectionReady())
        let caps = controller.capabilities
        // Native configuration remains usable and gives the Agent a real revision
        // to replay. The runtime fixture records writes; it never launches servers.
        var native = try #require(caps.editTool())
        native.connection = .init(
            name: "fixture-server", kind: .local,
            address: "/fixture/researcher-selected-program", enabled: false)
        try #require(await caps.saveTool(native))
        try await wait { caps.canConfigureTools }
        let configURL = controller.runtimeHome.appendingPathComponent("fixture-tool-config.json")
        let originalBytes = try Data(contentsOf: configURL)
        let originalConnections = caps.toolConnections
        let version = try #require(caps.editTool(named: "fixture-server")?.revision)
        controller.editDraft("hold capability authority")
        controller.send()
        try await wait { controller.state == .working && controller.selected?.pendingMessageID == nil }
        let token = try #require(controller.token)
        let context = try #require(controller.runtimeContext(for: token))
        for action in ["add", "update", "set_enabled", "remove"] {
            for revision in [version, "stale-fixture-version"] {
                for kind in ["local", "remote"] {
                    let request = ScholiumMCPBridgeRequest(
                        tool: .configureTool,
                        arguments: [
                            "action": .string(action), "expected_version": .string(revision),
                            "name": .string("fixture-server"), "kind": .string(kind),
                            "address": .string(kind == "local" ? "/fixture/changed-program" : "https://fixture.invalid/mcp"),
                            "args": .array([.string("changed-argument")]), "env_vars": .array([.string("FIXTURE_ONLY")]),
                            "enabled": .bool(true), "reuse_access_settings": .bool(true),
                        ], conversationToken: token, runtimeContext: context)
                    let result = await controller.handle(request)
                    #expect(result.error?.code == .invalidRequest)
                    #expect(try Data(contentsOf: configURL) == originalBytes)
                    #expect(caps.toolConnections == originalConnections && !caps.isChanging)
                }
            }
        }
        for tool in [ScholiumMCPToolName.configureTool, .configureChat] {
            let arguments: [String: MCPJSONValue] =
                tool == .configureTool
                ? ["action": .string("add"), "name": .string("unapproved-fixture")]
                : ["action": .string("set_permission"), "permission": .string("fullAccess")]
            let foreign = await controller.handle(
                .init(
                    tool: tool, arguments: arguments,
                    conversationToken: UUID(), runtimeContext: context))
            #expect(foreign.error?.code == .invalidRequest)
            let changedContext = await controller.handle(
                .init(
                    tool: tool, arguments: arguments,
                    conversationToken: token, runtimeContext: .init(threadID: "foreign-fixture-thread", turnID: context.turnID)))
            #expect(changedContext.error?.code == .invalidRequest)
            let cancelled = await Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                return await controller.handle(
                    .init(
                        tool: tool, arguments: arguments,
                        conversationToken: token, runtimeContext: context))
            }.value
            #expect(cancelled.error?.code == .invalidRequest)
            #expect(try Data(contentsOf: configURL) == originalBytes)
            #expect(controller.selected?.permission == .ask && caps.toolConnections == originalConnections)
        }
        #expect(controller.approvals.isEmpty)
        controller.stop()
        try await wait { !controller.isBusy }
        let stale = await controller.handle(
            .init(
                tool: .configureTool,
                arguments: ["action": .string("set_enabled"), "enabled": .bool(true)],
                conversationToken: token, runtimeContext: context))
        #expect(stale.error?.code == .invalidRequest)
        #expect(try Data(contentsOf: configURL) == originalBytes)
        await controller.disconnect()
    }

    @Test("Agent elevation cannot alter queued turns, native idle control still grants and Agent can reduce permission")
    func permissionAuthorityAndQueuedTurns() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/permission-authority-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = fixtureChatController(triptychID: UUID(), root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try #require(await controller.waitUntilLoaded())
        let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        controller.connect(executable: fixture, home: controller.runtimeHome, helper: fixture)
        try #require(await controller.waitUntilConnectionReady())
        controller.editDraft("hold-queue authority turn")
        controller.send()
        try await wait { controller.state == .working && controller.selected?.pendingMessageID == nil }
        let token = try #require(controller.token)
        let context = try #require(controller.runtimeContext(for: token))
        controller.editDraft("queued ordinary request")
        try #require(controller.queue())
        controller.setPermission(.fullAccess)
        #expect(controller.selected?.permission == .ask)
        let elevated = await controller.handle(
            .init(
                tool: .configureChat,
                arguments: ["action": .string("set_permission"), "permission": .string("fullAccess")],
                conversationToken: token, runtimeContext: context))
        #expect(elevated.error?.code == .invalidRequest && controller.selected?.permission == .ask)
        #expect(controller.approvals.isEmpty && controller.queuedMessages.count == 1)
        try Data().write(to: controller.runtimeHome.appendingPathComponent("release-queued-turn"))
        controller.refreshQuota()
        try await wait { controller.queuedMessages.isEmpty && controller.selected?.lastRunStatus == .completed }
        let inputs = try JSONDecoder().decode(
            MCPJSONValue.self,
            from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("turn-inputs.json")))
        let turns = try #require(inputs.arrayValue)
        #expect(turns.count == 2)
        for turn in turns {
            #expect(turn.objectValue?["approvalPolicy"]?.stringValue == AgentChatPermission.ask.approvalPolicy)
            #expect(turn.objectValue?["approvalPolicy"]?.stringValue != "never")
        }
        let runtimeConfiguration = try JSONDecoder().decode(
            MCPJSONValue.self,
            from: Data(contentsOf: controller.runtimeHome.appendingPathComponent("configuration.json")))
        #expect(runtimeConfiguration.objectValue?["sandbox"]?.stringValue == AgentChatPermission.ask.sandbox)
        let stale = await controller.handle(
            .init(
                tool: .configureChat,
                arguments: ["action": .string("set_permission"), "permission": .string("fullAccess")],
                conversationToken: token, runtimeContext: context))
        #expect(stale.error?.code == .invalidRequest && controller.selected?.permission == .ask)
        controller.setPermission(.fullAccess)
        #expect(controller.selected?.permission == .fullAccess)
        controller.editDraft("hold authority reduction")
        controller.send()
        try await wait { controller.state == .working && controller.selected?.pendingMessageID == nil }
        let fullToken = try #require(controller.token)
        let fullContext = try #require(controller.runtimeContext(for: fullToken))
        let reduced = await controller.handle(
            .init(
                tool: .configureChat,
                arguments: ["action": .string("set_permission"), "permission": .string("ask")],
                conversationToken: fullToken, runtimeContext: fullContext))
        #expect(reduced.error == nil && controller.selected?.permission == .ask)
        controller.stop()
        try await wait { !controller.isBusy }
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
