import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@Suite("Official Codex Triptych workspace")
struct CodexChatWorkspaceTests {
    @Test(
        "Two workspaces share runtime home without sharing local Skills",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_CODEX_SMOKE_EXECUTABLE"] != nil))
    func isolatedDiscovery() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/chat-workspace/official-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("Codex")
        let a = root.appendingPathComponent("TriptychA/.scholium")
        let b = root.appendingPathComponent("TriptychB/.scholium")
        for workspace in [a, b] {
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            _ = try AgentChatWorkspace.prepare(workspace, runtimeHome: home)
        }
        func writeSkill(_ name: String, workspace: URL) throws -> URL {
            let file = workspace.appendingPathComponent("skills/\(name)/SKILL.md")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("---\nname: \(name)\ndescription: Inspect synthetic fixtures only.\n---\nUse supplied fixture text.\n".utf8).write(to: file)
            return file
        }
        let skillA = try writeSkill("triptych-a-method", workspace: a)
        let skillB = try writeSkill("triptych-b-method", workspace: b)
        let localInstruction = "Scholium synthetic workspace instruction 91d5e13a"
        try Data(localInstruction.utf8).write(to: a.appendingPathComponent("AGENTS.md"))
        try Data("Scholium synthetic parent instruction must not load 4bab3b".utf8)
            .write(to: a.deletingLastPathComponent().appendingPathComponent("AGENTS.md"))
        let first = CodexAppServer()
        let second = CodexAppServer()
        do {
            let executable = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["SCHOLIUM_CODEX_SMOKE_EXECUTABLE"]))
            for (runtime, workspace) in [(first, a), (second, b)] {
                try await runtime.start(executable: executable, home: home, workingDirectory: workspace)
                _ = try await runtime.request(
                    "initialize",
                    params: [
                        "clientInfo": .object(["name": .string("scholium-workspace-test"), "version": .string("1")]),
                        "capabilities": .object(["experimentalApi": .bool(true)]),
                    ])
                try await runtime.notify("initialized")
                try await runtime.setChatMethodFolders([AgentChatWorkspace.skillsDirectory(in: workspace).path])
            }
            let inventoryA = try await first.chatMethods(cwd: a)
            let inventoryB = try await second.chatMethods(cwd: b)
            #expect(inventoryA.methods.contains { $0.selection.path == skillA.path })
            #expect(!inventoryA.methods.contains { $0.selection.path == skillB.path })
            #expect(inventoryB.methods.contains { $0.selection.path == skillB.path })
            #expect(!inventoryB.methods.contains { $0.selection.path == skillA.path })
            let added = try writeSkill("added-after-connect", workspace: a)
            #expect(try await first.chatMethods(cwd: a).methods.contains { $0.selection.path == added.path })
            #expect(try await second.chatMethods(cwd: b).methods.allSatisfy { $0.selection.path != added.path })
            let started = try await first.request(
                "thread/start",
                params: [
                    "cwd": .string(a.path), "approvalPolicy": .string("on-request"),
                    "sandbox": .string("read-only"),
                ])
            let thread = try #require(started.objectValue?["thread"]?.objectValue)
            #expect(thread["cwd"]?.stringValue == a.path)
            // Thread archives are created lazily by Codex. Starting a thread proves cwd
            // binding without inference; model consumption of instructions is a live check.
            #expect(try String(contentsOf: a.appendingPathComponent("AGENTS.md"), encoding: .utf8) == localInstruction)
            #expect(!FileManager.default.fileExists(atPath: a.appendingPathComponent("config.toml").path))
            #expect(!FileManager.default.fileExists(atPath: b.appendingPathComponent("auth.json").path))
            await first.close()
            await second.close()
        } catch {
            await first.close()
            await second.close()
            throw error
        }
    }
}
