import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Triptych Chat workspace", .serialized)
@MainActor
struct AgentChatWorkspaceTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Workspace fixture did not reach expected state")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    private func connect(_ controller: AgentChatController) async throws {
        try await wait { controller.isLoaded }
        let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        controller.connect(executable: fixture, home: controller.runtimeHome, helper: fixture)
        try await wait { controller.connectionState == .ready && !controller.capabilities.isRefreshing }
    }
    private func controller(_ root: URL, id: UUID = UUID()) -> AgentChatController {
        fixtureChatController(triptychID: id, root: root) { try! .init(requestID: $0.requestID, result: .object([:])) }
    }
    private func addSkill(_ name: String, workspace: URL) throws -> URL {
        let path = workspace.appendingPathComponent("skills/\(name)/SKILL.md")
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("---\nname: \(name)\ndescription: Synthetic fixture.\n---\nUse supplied fixture text.\n".utf8).write(to: path)
        return path
    }

    @Test("Shared login home keeps two Triptych workspaces and Skill inventories separate")
    func isolatedWorkspaces() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/workspace-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = controller(root)
        let second = controller(root)
        let a = try agentChatFixtureWorkspace(root: root, triptychID: first.triptychID)
        let b = try agentChatFixtureWorkspace(root: root, triptychID: second.triptychID)
        let skillA = try addSkill("first-only", workspace: a)
        let skillB = try addSkill("second-only", workspace: b)
        let guide = Data("# Instructions\r\nKeep exact text 😀\r\n".utf8)
        try guide.write(to: a.appendingPathComponent("AGENTS.md"))
        try await connect(first)
        try await connect(second)
        #expect(first.runtimeHome == second.runtimeHome)
        #expect(first.workingDirectory?.path == a.path && second.workingDirectory?.path == b.path)
        #expect(first.capabilities.skillRoots == [a.appendingPathComponent("skills").path])
        #expect(second.capabilities.skillRoots == [b.appendingPathComponent("skills").path])
        #expect(first.capabilities.methods.contains { $0.selection.path == skillA.path })
        #expect(!first.capabilities.methods.contains { $0.selection.path == skillB.path })
        #expect(second.capabilities.methods.contains { $0.selection.path == skillB.path })
        #expect(!second.capabilities.methods.contains { $0.selection.path == skillA.path })
        first.editDraft("read fixture")
        first.send()
        try await wait { !first.isBusy && first.selected?.threadID != nil }
        let params = try JSONDecoder().decode(MCPJSONValue.self, from: Data(contentsOf: first.runtimeHome.appendingPathComponent("configuration.json")))
        #expect(params.objectValue?["cwd"]?.stringValue == a.path)
        #expect(params.objectValue?["config"]?.objectValue?["project_doc_max_bytes"]?.intValue == 32768)
        #expect(params.objectValue?["config"]?.objectValue?["project_root_markers"]?.arrayValue == [])
        #expect(try Data(contentsOf: a.appendingPathComponent("AGENTS.md")) == guide)
        #expect(!FileManager.default.fileExists(atPath: a.appendingPathComponent("config.toml").path))
        await first.disconnect()
        await second.disconnect()
    }

    @Test("New Skill files are discovered without registration and reconnect retains their workspace")
    func discoveryAndRenewal() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/workspace-refresh-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let chat = controller(root)
        try await connect(chat)
        let workspace = try #require(chat.workingDirectory)
        let skill = try addSkill("new-method", workspace: workspace)
        chat.capabilities.refresh(threadID: nil)
        try await wait { !chat.capabilities.isRefreshing }
        let method = try #require(chat.capabilities.methods.first { $0.selection.path == skill.path })
        chat.editDraft("establish thread")
        chat.send()
        try await wait { !chat.isBusy && chat.selected?.threadID != nil }
        let thread = chat.selected?.threadID
        chat.toggleMethod(method.selection)
        chat.editDraft("retained request")
        chat.setWebSearch(.live)
        try await wait { !chat.isRenewingSettings && !chat.capabilities.isRefreshing }
        #expect(chat.workingDirectory?.path == workspace.path && chat.selected?.threadID == thread)
        #expect(chat.selected?.draft == "retained request" && chat.capabilities.contains(method.selection))
        #expect(chat.canSend)
        await chat.disconnect()
        try await connect(chat)
        #expect(chat.workingDirectory?.path == workspace.path && chat.capabilities.contains(method.selection))
        await chat.disconnect()
    }

    @Test("Workspace discovery failures stay visible and explicit refresh repairs them")
    func discoveryFailure() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/workspace-failure-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let chat = controller(root)
        try FileManager.default.createDirectory(at: chat.runtimeHome, withIntermediateDirectories: true)
        let rejection = chat.runtimeHome.appendingPathComponent("reject-roots")
        try Data().write(to: rejection)
        try await connect(chat)
        #expect(chat.capabilities.workspaceError != nil && !chat.capabilities.hasMethods)
        chat.editDraft("preserve draft")
        #expect(!chat.canSend)
        try FileManager.default.removeItem(at: rejection)
        chat.capabilities.refresh(threadID: nil, reloadWorkspace: true)
        try await wait { !chat.capabilities.isRefreshing }
        #expect(chat.capabilities.workspaceError == nil && chat.capabilities.hasMethods)
        #expect(chat.selected?.draft == "preserve draft" && chat.canSend)
        await chat.disconnect()
    }

    @Test("Portable workspace rejects runtime state and a symlinked Skills root")
    func directoryBoundaries() throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/workspace-boundaries-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try agentChatFixtureWorkspace(root: root, triptychID: UUID())
        #expect(throws: (any Error).self) { try AgentChatWorkspace.prepare(workspace, runtimeHome: workspace.appendingPathComponent("Codex")) }
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: workspace.appendingPathComponent("skills"), withDestinationURL: outside)
        #expect(throws: (any Error).self) { try AgentChatWorkspace.prepare(workspace, runtimeHome: root.appendingPathComponent("Codex")) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test("Disconnect during workspace initialization cannot restore a stale connection")
    func cancelledInitialization() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/workspace-cancel-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let chat = controller(root)
        try await connect(chat)
        chat.editDraft("establish thread")
        chat.send()
        try await wait { !chat.isBusy && chat.selected?.threadID != nil }
        chat.editDraft("preserve after cancellation")
        let marker = chat.runtimeHome.appendingPathComponent("hold-roots")
        let counter = chat.runtimeHome.appendingPathComponent("roots-request-count")
        try Data().write(to: marker)
        chat.setWebSearch(.live)
        try await wait { (try? String(contentsOf: counter, encoding: .utf8)) == "2" }
        #expect(chat.connectionState == .connecting && !chat.canSend)
        await chat.disconnect()
        #expect(chat.connectionState == .disconnected && !chat.capabilities.workspaceReady)
        #expect(chat.selected?.draft == "preserve after cancellation")
        try FileManager.default.removeItem(at: marker)
        try await connect(chat)
        #expect(chat.capabilities.workspaceReady && chat.canSend)
        await chat.disconnect()
    }
}
