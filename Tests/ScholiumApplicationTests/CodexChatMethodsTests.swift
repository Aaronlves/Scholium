import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@Suite("Runtime method and tool inventory")
struct CodexChatMethodsTests {
    @Test("Authorization destinations are secure browser URLs without embedded credentials")
    func authorizationDestinations() throws {
        let valid: MCPJSONValue = .object(["authorizationUrl": .string("https://auth.example.test/start?state=opaque")])
        #expect(try CodexChatMethods.authorizationURL(valid).host == "auth.example.test")
        for value in ["javascript:alert(1)", "file:///fixture", "http://auth.example.test", "https://user:secret@auth.example.test", "https:///", "/relative"] {
            #expect(throws: CodexConnectionError.self) {
                try CodexChatMethods.authorizationURL(.object(["authorizationUrl": .string(value)]))
            }
        }
    }
    @Test("Discovery preserves disabled methods, declared dependencies and scan errors")
    func methods() throws {
        let skill: MCPJSONValue = .object([
            "name": .string("analysis"), "path": .string("/fixture/analysis/SKILL.md"),
            "description": .string("Read narrowly"), "enabled": .bool(false), "scope": .string("user"),
            "interface": .object(["displayName": .string("Source Analysis")]),
            "dependencies": .object(["tools": .array([.object(["value": .string("citations")])])]),
        ])
        let result: MCPJSONValue = .object([
            "data": .array([
                .object([
                    "cwd": .string("/fixture"), "skills": .array([skill]),
                    "errors": .array([.object(["path": .string("/fixture/broken"), "message": .string("Missing description")])]),
                ])
            ])
        ])
        let inventory = try CodexChatMethods.methods(result, cwd: "/fixture")
        #expect(inventory.methods.count == 1 && !inventory.methods[0].enabled)
        #expect(inventory.methods[0].selection.title == "Source Analysis")
        #expect(inventory.methods[0].dependencies == ["citations"] && inventory.errors.count == 1)
        #expect(throws: CodexConnectionError.self) { try CodexChatMethods.methods(result, cwd: "/another") }
        #expect(throws: CodexConnectionError.self) { try CodexChatMethods.methods(.object([:]), cwd: "/fixture") }
    }

    @Test("Authentication metadata and known tool names do not manufacture a connected runtime")
    func tools() throws {
        let result: MCPJSONValue = .object([
            "data": .array([
                .object([
                    "name": .string("citations"), "authStatus": .string("oAuth"), "runtimeStatus": .null,
                    "tools": .object(["lookup": .object([:])]),
                ])
            ])
        ])
        let tool = try #require(CodexChatMethods.tools(result).first)
        #expect(tool.connectionStatus == nil && tool.authStatus == "oAuth" && tool.tools == ["lookup"])
        #expect(throws: CodexConnectionError.self) { try CodexChatMethods.tools(.object([:])) }
    }

    @Test(
        "Installed Codex discovers and toggles an isolated local method without inference",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_CODEX_SMOKE_EXECUTABLE"] != nil))
    func officialMethods() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-chat-evolution/official-method-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let skill = root.appendingPathComponent("skills/scholium-fixture-method/SKILL.md")
        try FileManager.default.createDirectory(at: skill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "---\nname: scholium-fixture-method\ndescription: Read synthetic fixture passages without inventing claims.\n---\nUse only the synthetic fixture.\n"
            .write(to: skill, atomically: true, encoding: .utf8)
        let runtime = CodexAppServer()
        do {
            let executable = try #require(ProcessInfo.processInfo.environment["SCHOLIUM_CODEX_SMOKE_EXECUTABLE"])
            try await runtime.start(executable: URL(fileURLWithPath: executable), home: root)
            _ = try await runtime.request(
                "initialize",
                params: [
                    "clientInfo": .object([
                        "name": .string("scholium-method-test"), "version": .string("1"),
                    ])
                ])
            try await runtime.notify("initialized")
            let inventory = try await runtime.chatMethods(cwd: root)
            let method = try #require(inventory.methods.first { $0.selection.path == skill.path })
            #expect(method.enabled)
            #expect(try await runtime.setChatMethod(method, enabled: false) == false)
            #expect(try await runtime.chatMethods(cwd: root).methods.first { $0.id == method.id }?.enabled == false)
            #expect(try await runtime.setChatMethod(method, enabled: true))
            #expect(try await runtime.chatMethods(cwd: root).methods.first { $0.id == method.id }?.enabled == true)
            _ = try await runtime.chatConnectedTools(threadID: nil)
            let extra = root.appendingPathComponent("associated-fixture")
            let extraSkill = extra.appendingPathComponent("SKILL.md")
            try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
            let source = "---\nname: scholium-associated-fixture\ndescription: Inspect only synthetic material.\n---\nKeep exact fixture text.\n"
            try source.write(to: extraSkill, atomically: true, encoding: .utf8)
            #expect(try await runtime.chatMethods(cwd: root).methods.allSatisfy { $0.selection.path != extraSkill.path })
            try await runtime.setChatMethodFolders([extra.path])
            #expect(try await runtime.chatMethods(cwd: root).methods.contains { $0.selection.path == extraSkill.path })
            let collection = root.appendingPathComponent("associated-collection")
            let nestedSkill = collection.appendingPathComponent("nested-method/SKILL.md")
            try FileManager.default.createDirectory(at: nestedSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
            let nestedSource = "---\nname: scholium-nested-fixture\ndescription: Inspect synthetic nested material.\n---\nPreserve exact source.\n"
            try nestedSource.write(to: nestedSkill, atomically: true, encoding: .utf8)
            try await runtime.setChatMethodFolders([extra.path, collection.path])
            #expect(try await runtime.chatMethods(cwd: root).methods.contains { $0.selection.path == nestedSkill.path })
            try await runtime.setChatMethodFolders([])
            #expect(try await runtime.chatMethods(cwd: root).methods.allSatisfy { $0.selection.path != extraSkill.path })
            #expect(try await runtime.chatMethods(cwd: root).methods.allSatisfy { $0.selection.path != nestedSkill.path })
            #expect(try String(contentsOf: extraSkill, encoding: .utf8) == source)
            #expect(try String(contentsOf: nestedSkill, encoding: .utf8) == nestedSource)
            await runtime.close()
        } catch {
            await runtime.close()
            throw error
        }
    }
}
