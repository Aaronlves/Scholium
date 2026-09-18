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
            try await wait { controller.isLoaded }
            controller.connect(executable: executable, home: controller.runtimeHome, helper: executable)
            try await wait { controller.capabilities.canConfigureTools }
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
        #expect(caps.zoteroConnectionAvailable)
        await first.disconnect()
    }
}
