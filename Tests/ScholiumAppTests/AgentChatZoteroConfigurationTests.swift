import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp
@testable import ScholiumApplication

@Suite("Zotero Chat configuration", .serialized) @MainActor
struct AgentChatZoteroConfigurationTests {
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
