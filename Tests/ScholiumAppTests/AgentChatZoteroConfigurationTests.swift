import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp
@testable import ScholiumApplication

@Suite("Zotero Chat configuration", .serialized) @MainActor
struct AgentChatZoteroConfigurationTests {
    @Test(
        "Both Chat helpers retain the App endpoint across deployment path policies",
        arguments: ["isolated-home", "explicit-container", "debug-fallback", "production"])
    func helpersUseResolvedAppEndpoint(_ policy: String) async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-chat-tests/bridge-namespace-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let loginHome = root.appendingPathComponent("Synthetic Account", isDirectory: true)
        let debugSupport = root.appendingPathComponent("Debug Support", isDirectory: true)
        let isolatedHome = root.appendingPathComponent("QA Home", isDirectory: true)
        let explicitContainer = root.appendingPathComponent("Custom Bridge", isDirectory: true)
        let environment: [String: String]
        let debugFallback: URL?
        let expected: URL
        switch policy {
        case "isolated-home":
            environment = ["SCHOLIUM_HOME": isolatedHome.path]
            debugFallback = debugSupport
            expected = isolatedHome.appendingPathComponent("ApplicationSupport/AppBridge", isDirectory: true)
        case "explicit-container":
            environment = ["SCHOLIUM_HOME": isolatedHome.path, "SCHOLIUM_APP_BRIDGE_CONTAINER": explicitContainer.path]
            debugFallback = debugSupport
            expected = explicitContainer
        case "debug-fallback":
            environment = [:]
            debugFallback = debugSupport
            #if DEBUG
                expected = debugSupport.appendingPathComponent("AppBridge", isDirectory: true)
            #else
                expected = loginHome.appendingPathComponent("Library/Application Support/Scholium/State-v1/AppBridge", isDirectory: true)
            #endif
        default:
            environment = [:]
            debugFallback = nil
            expected = loginHome.appendingPathComponent("Library/Application Support/Scholium/State-v1/AppBridge", isDirectory: true)
        }
        let resolved = try ScholiumPaths.appBridgeContainerURL(
            environment: environment, homeURL: loginHome, debugFallbackURL: debugFallback)
        #expect(resolved == expected)
        let ownedPreferences = AgentChatFixturePreferenceStore()
        let registry = AgentChatRegistry(
            root: root.appendingPathComponent("Chat"), appBridgeContainerURL: resolved,
            contextAccessPreferences: AgentContextAccessPreferences(defaults: ownedPreferences.defaults),
            workspaceDirectory: { _ in root },
            previewUpdate: { _ in throw ScholiumAppBridgeError.invalidRequest },
            handler: { request, _ in
                Issue.record("Endpoint configuration must not dispatch a research operation")
                return try! .init(requestID: request.requestID, result: .object([:]))
            })
        let controller = registry.controller(for: UUID())
        controller.connectionDefaults = ownedPreferences.defaults
        try #require(await controller.waitUntilLoaded())
        let helperURL = root.appendingPathComponent("Synthetic Helper")
        controller.helperURL = helperURL
        let scope = UUID()
        let configuration = try controller.toolConfiguration(token: scope)
        let servers = try #require(configuration["mcp_servers"]?.objectValue)
        for name in ["scholium", "scholium-zotero"] {
            let server = try #require(servers[name]?.objectValue)
            let helperEnvironment = try #require(server["env"]?.objectValue)
            #expect(helperEnvironment == ["SCHOLIUM_APP_BRIDGE_CONTAINER": .string(expected.path)])
            // A helper's distinct login home/Debug fallback must never retarget
            // the endpoint already selected by the App composition root.
            let explicit = try #require(helperEnvironment["SCHOLIUM_APP_BRIDGE_CONTAINER"]?.stringValue)
            let helperResolved = try ScholiumPaths.appBridgeContainerURL(
                environment: ["SCHOLIUM_APP_BRIDGE_CONTAINER": explicit],
                homeURL: root.appendingPathComponent("Other Account"),
                debugFallbackURL: root.appendingPathComponent("Other Debug"))
            #expect(helperResolved == expected)
            #expect(server["command"] == .string(helperURL.path))
            #expect(server["required"] == .bool(true))
        }
        #expect(
            servers["scholium"]?.objectValue?["args"]?.arrayValue?.compactMap(\.stringValue)
                == ["mcp", "serve", "--conversation-token", scope.uuidString])
        #expect(
            servers["scholium-zotero"]?.objectValue?["args"]?.arrayValue?.compactMap(\.stringValue)
                == ["zotero", "mcp", "serve"])
        await controller.disconnect()
    }

    @Test("An unavailable App endpoint cannot yield unbound helper configuration")
    func missingAppEndpointFailsClosed() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-chat-tests/missing-bridge-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let ownedPreferences = AgentChatFixturePreferenceStore()
        let controller = AgentChatController(
            triptychID: UUID(), root: root, appBridgeContainerURL: nil, workspaceDirectory: { root },
            methodDefaults: ownedPreferences.defaults,
            contextAccessPreferences: AgentContextAccessPreferences(defaults: ownedPreferences.defaults),
            toolHandler: { request, _ in
                Issue.record("Missing endpoint must not dispatch a research operation")
                return try! .init(requestID: request.requestID, result: .object([:]))
            })
        try #require(await controller.waitUntilLoaded())
        controller.helperURL = root.appendingPathComponent("Synthetic Helper")
        #expect(throws: ScholiumAppBridgeError.unavailable) { try controller.toolConfiguration(token: UUID()) }
        #expect(controller.executions.values.allSatisfy { $0.admissionID == nil })
        await controller.disconnect()
    }

    @Test("Configured research and Zotero helpers reach only the App's injected bridge")
    func helpersDoNotCrossNamespaces() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-chat-tests/bridge-routing-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let intendedContainer = root.appendingPathComponent("Intended Bridge", isDirectory: true)
        let otherHome = root.appendingPathComponent("Other Home", isDirectory: true)
        let otherContainer = otherHome.appendingPathComponent("ApplicationSupport/AppBridge", isDirectory: true)
        let intendedCalls = ChatBridgeNamespaceCalls()
        let otherCalls = ChatBridgeNamespaceCalls()
        func bridge(at container: URL, marker: String, calls: ChatBridgeNamespaceCalls) throws -> ScholiumAppBridgeServer {
            try ScholiumAppBridgeServer(
                applicationSupportURL: container,
                zoteroHandler: { request in
                    await calls.record()
                    return .object([
                        "jsonrpc": .string("2.0"), "id": request.request.objectValue?["id"] ?? .null,
                        "result": .object([
                            "content": .array([.object(["type": .string("text"), "text": .string(marker)])]),
                            "structuredContent": .object(["namespace": .string(marker)]), "isError": .bool(false),
                        ]),
                    ])
                }
            ) { request in
                await calls.record()
                return try .init(requestID: request.requestID, result: .object(["namespace": .string(marker)]))
            }
        }
        let intended = try bridge(at: intendedContainer, marker: "intended", calls: intendedCalls)
        defer { intended.stop() }
        let other = try bridge(at: otherContainer, marker: "other", calls: otherCalls)
        defer { other.stop() }
        do {
            let ownedPreferences = AgentChatFixturePreferenceStore()
            let controller = AgentChatController(
                triptychID: UUID(), root: root.appendingPathComponent("Chat"),
                appBridgeContainerURL: intendedContainer, workspaceDirectory: { root },
                methodDefaults: ownedPreferences.defaults,
                contextAccessPreferences: AgentContextAccessPreferences(defaults: ownedPreferences.defaults),
                toolHandler: { request, _ in try! .init(requestID: request.requestID, result: .object([:])) })
            try #require(await controller.waitUntilLoaded())
            controller.helperURL = root.appendingPathComponent("Synthetic Helper")
            let configuration = try controller.toolConfiguration(token: UUID())
            let servers = try #require(configuration["mcp_servers"]?.objectValue)
            for name in ["scholium", "scholium-zotero"] {
                let server = try #require(servers[name]?.objectValue)
                let container = try #require(server["env"]?.objectValue?["SCHOLIUM_APP_BRIDGE_CONTAINER"]?.stringValue)
                // Require the disposable destination before constructing any
                // helper: a regression must never fall through to user state.
                try #require(container == intendedContainer.path)
                let argumentValues = try #require(server["args"]?.arrayValue)
                let arguments = argumentValues.compactMap(\.stringValue)
                let handler = try AgentMCPService.helperHandler(
                    arguments: arguments,
                    environment: ["SCHOLIUM_APP_BRIDGE_CONTAINER": container, "SCHOLIUM_HOME": otherHome.path])
                let tool = name == "scholium" ? "scholium_workspace_status" : "zotero_search"
                let request: MCPJSONValue = .object([
                    "jsonrpc": .string("2.0"), "id": .integer(1), "method": .string("tools/call"),
                    "params": .object(["name": .string(tool), "arguments": .object([:])]),
                ])
                let reply = try #require(await handler(JSONEncoder().encode(request)))
                let value = try JSONDecoder().decode(MCPJSONValue.self, from: reply)
                #expect(value.objectValue?["result"]?.objectValue?["structuredContent"]?.objectValue?["namespace"] == .string("intended"))
            }
            #expect(await intendedCalls.count == 2)
            #expect(await otherCalls.count == 0)
            await controller.disconnect()
        } catch {
            _ = await intended.stopAndWait(timeout: 1)
            _ = await other.stopAndWait(timeout: 1)
            throw error
        }
        #expect(await intended.stopAndWait(timeout: 1))
        #expect(await other.stopAndWait(timeout: 1))
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Zotero configuration fixture did not reach its expected state")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("Chat injects Scholium's independent Zotero connection")
    func injectsIndependentZoteroConnection() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-chat-tests/zotero-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        let triptych = UUID()
        func make() async throws -> AgentChatController {
            let controller = fixtureChatController(triptychID: triptych, root: root) { request in
                try! .init(requestID: request.requestID, result: .object([:]))
            }
            try #require(await controller.waitUntilLoaded(), "Chat history did not finish loading")
            controller.connect(executable: executable, home: controller.runtimeHome, helper: executable)
            try #require(await controller.waitUntilConnectionReady(), "Chat runtime configuration did not finish loading")
            return controller
        }
        let first = try await make()
        let caps = first.capabilities
        first.editDraft("hello")
        first.send()
        let configurationFile = first.runtimeHome.appendingPathComponent("configuration.json")
        try await wait { FileManager.default.fileExists(atPath: configurationFile.path) && first.state == .ready }
        let defaults = try JSONDecoder().decode(MCPJSONValue.self, from: Data(contentsOf: configurationFile))
        let config = try #require(defaults.objectValue?["config"]?.objectValue)
        let builtIn = try #require(config["mcp_servers"]?.objectValue)
        #expect(builtIn["scholium"] != nil)
        let zotero = try #require(builtIn["scholium-zotero"]?.objectValue)
        #expect(zotero["args"]?.arrayValue?.compactMap(\.stringValue) == ["zotero", "mcp", "serve"])
        let bridgeEnvironment: MCPJSONValue = .object([
            "SCHOLIUM_APP_BRIDGE_CONTAINER": .string(root.appendingPathComponent("AppBridge", isDirectory: true).path)
        ])
        #expect(builtIn["scholium"]?.objectValue?["env"] == bridgeEnvironment)
        #expect(zotero["env"] == bridgeEnvironment)
        #expect(config["project_doc_max_bytes"] == .integer(32768))
        #expect(config["project_root_markers"] == .array([]))
        #expect(defaults.objectValue?["developerInstructions"]?.stringValue?.contains(triptych.uuidString) == true)
        #expect(caps.zoteroConnectionState == .available)
        await first.disconnect()
    }

    @Test("Zotero availability follows tool configuration independently of Skill discovery")
    func availabilitySurvivesSkillFailure() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-chat-tests/zotero-state-\(UUID())")
        let suite = "scholium.zotero-state.\(UUID())"
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
            let caps = controller.capabilities
            #expect(caps.zoteroConnectionState == .disconnected)
            try FileManager.default.createDirectory(at: controller.runtimeHome, withIntermediateDirectories: true)
            let rejectSkills = controller.runtimeHome.appendingPathComponent("reject-roots")
            try Data().write(to: rejectSkills)
            let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
            controller.connect(executable: fixture, home: controller.runtimeHome, helper: fixture)
            try #require(await controller.waitUntilConnectionReady())
            #expect(caps.workspaceError != nil && !caps.hasMethods)
            #expect(caps.zoteroConnectionState == .available)

            let rejectConfiguration = controller.runtimeHome.appendingPathComponent("fail-config-read-after-write")
            try Data(#"{"version":1,"servers":{}}"#.utf8).write(
                to: controller.runtimeHome.appendingPathComponent("fixture-tool-config.json"))
            try Data().write(to: rejectConfiguration)
            caps.refresh(threadID: nil)
            #expect(caps.zoteroConnectionState == .checking)
            try await wait { !caps.isRefreshing }
            #expect(caps.toolConfigurationError != nil)
            #expect(caps.zoteroConnectionState == .unavailable)

            try FileManager.default.removeItem(at: rejectConfiguration)
            try FileManager.default.removeItem(at: rejectSkills)
            caps.refresh(threadID: nil, reloadWorkspace: true)
            try await wait { !caps.isRefreshing }
            #expect(caps.workspaceError == nil && caps.hasMethods)
            #expect(caps.zoteroConnectionState == .available)
        } catch {
            await controller.disconnect()
            throw error
        }
        await controller.disconnect()
        #expect(controller.capabilities.zoteroConnectionState == .disconnected)
    }
}

private actor ChatBridgeNamespaceCalls {
    private(set) var count = 0
    func record() { count += 1 }
}
