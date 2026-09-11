import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@Suite("Runtime tool configuration")
struct CodexChatToolConfigurationTests {
    private func snapshot(override: Bool = false) throws -> CodexChatToolConfiguration {
        let server: MCPJSONValue = .object([
            "url": .string("https://one.example/mcp"), "enabled": .bool(true),
            "http_headers": .object(["X-Fixture": .string("synthetic-value")]), "custom_option": .integer(17),
        ])
        return try snapshot(server: server, override: override)
    }

    private func snapshot(server: MCPJSONValue, override: Bool = false) throws -> CodexChatToolConfiguration {
        var effective = server.objectValue!
        if override { effective["enabled"] = .bool(false) }
        return try .init(
            .object([
                "config": .object(["mcp_servers": .object(["fixture.other": .object(effective)])]),
                "layers": .array([
                    .object([
                        "name": .object(["type": .string("user"), "file": .string("/fixture/config.toml")]),
                        "version": .string("revision"), "config": .object(["mcp_servers": .object(["fixture.other": server])]),
                    ])
                ]),
            ]),
            home: URL(fileURLWithPath: "/fixture"))
    }

    @Test("Environment references preserve unsupported settings and never accept pasted assignments")
    func environmentReferences() throws {
        let snapshot = try snapshot()
        for variable in ["TOKEN=synthetic", "two words", "TOKEN\n", "\u{0}"] {
            #expect(throws: CodexChatToolConfigurationError.self) {
                try snapshot.writeParameters(.init(name: "new", address: "https://example.invalid", bearerTokenVariable: variable), originalName: nil)
            }
        }
        let remote = try self.snapshot(
            server: .object([
                "url": .string("https://one.example/mcp"),
                "bearer_token_env_var": .string("RESEARCH_TOKEN"),
            ]))
        var connection = try #require(remote.connections.first)
        connection.address = "https://two.example/mcp"
        #expect(remote.requiresAccessConfirmation(connection, originalName: connection.name))
        connection.bearerTokenVariable = ""
        #expect(!remote.requiresAccessConfirmation(connection, originalName: connection.name))
        let edits = try #require(remote.writeParameters(connection, originalName: connection.name)["edits"]?.arrayValue)
        #expect(
            edits.contains {
                $0.objectValue?["keyPath"]?.stringValue?.hasSuffix(".bearer_token_env_var") == true
                    && $0.objectValue?["value"] == .null
            })
        let local = try self.snapshot(
            server: .object([
                "command": .string("/fixture/server"),
                "env_vars": .array([
                    .string("LOCAL_TOKEN"), .object(["name": .string("REMOTE_TOKEN"), "source": .string("remote")]),
                ]),
            ]))
        var localConnection = try #require(local.connections.first)
        #expect(localConnection.isEditable && !localConnection.canEditEnvironmentVariables)
        localConnection.enabled = false
        #expect(try local.writeParameters(localConnection, originalName: localConnection.name)["edits"]?.arrayValue?.count == 1)
        localConnection.environmentVariables = []
        #expect(throws: CodexChatToolConfigurationError.self) { try local.writeParameters(localConnection, originalName: localConnection.name) }
        let helper = try self.snapshot(
            server: .object([
                "url": .string("https://one.example/mcp"),
                "http_headers_helper": .object(["command": .string("/fixture/helper")]),
            ]))
        var destination = try #require(helper.connections.first)
        destination.address = "https://two.example/mcp"
        #expect(helper.requiresAccessConfirmation(destination, originalName: destination.name))
    }

    @Test("Edits target changed fields only and credential reuse requires an explicit choice")
    func boundedEdits() throws {
        let snapshot = try snapshot()
        var value = try #require(snapshot.connections.first)
        value.enabled = false
        let params = try snapshot.writeParameters(value, originalName: value.name)
        let edits = try #require(params["edits"]?.arrayValue)
        #expect(edits.count == 1 && edits[0].objectValue?["keyPath"]?.stringValue == "mcp_servers.\"fixture.other\".enabled")
        #expect(params["expectedVersion"]?.stringValue == "revision")
        #expect(!String(decoding: try JSONEncoder().encode(params), as: UTF8.self).contains("synthetic-value"))
        value.address = "https://two.example/mcp"
        #expect(snapshot.requiresAccessConfirmation(value, originalName: value.name))
        #expect(throws: CodexChatToolConfigurationError.self) { try snapshot.writeParameters(value, originalName: value.name) }
        #expect(try snapshot.writeParameters(value, originalName: value.name, reuseAccessSettings: true)["edits"]?.arrayValue?.count == 2)
        value.address = "HTTPS://ONE.EXAMPLE:443/new-path"
        #expect(!snapshot.requiresAccessConfirmation(value, originalName: value.name))
        #expect(try self.snapshot(override: true).connections.first?.isEditable == false)
    }

    @Test("New connections cannot replace an existing name or the application bridge")
    func namesAndAddresses() throws {
        let snapshot = try snapshot()
        for name in ["", "scholium", "Scholium", "fixture.other"] {
            #expect(throws: CodexChatToolConfigurationError.self) {
                try snapshot.writeParameters(.init(name: name, address: "https://example.invalid"), originalName: nil)
            }
        }
        #expect(throws: CodexChatToolConfigurationError.self) {
            try snapshot.writeParameters(.init(name: "new", address: "http://remote.example/mcp"), originalName: nil)
        }
        #expect(
            try snapshot.writeParameters(
                .init(
                    name: "local", kind: .local, address: "/fixture/program ",
                    arguments: ["literal $(value)", "two words"]), originalName: nil)["edits"]?.arrayValue?.first?.objectValue?["value"]?.objectValue?[
                    "command"]?.stringValue == "/fixture/program ")
    }
    @Test(
        "Installed runtime applies version-checked tool configuration and removes a connection",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_CODEX_SMOKE_EXECUTABLE"] != nil))
    func officialConfiguration() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-chat-evolution/tool-config-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = CodexAppServer()
        do {
            let path = try #require(ProcessInfo.processInfo.environment["SCHOLIUM_CODEX_SMOKE_EXECUTABLE"])
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data("SCHOLIUM_TOOL_FIXTURE_TOKEN=synthetic-local-fixture\n".utf8)
                .write(to: root.appendingPathComponent(".env"))
            try await runtime.start(executable: URL(fileURLWithPath: path), home: root)
            _ = try await runtime.request(
                "initialize", params: ["clientInfo": .object(["name": .string("scholium-tool-config-test"), "version": .string("1")])])
            try await runtime.notify("initialized")
            let initial = try await runtime.request("config/read", params: ["includeLayers": .bool(true)])
            let layer = try #require(
                initial.objectValue?["layers"]?.arrayValue?.first {
                    $0.objectValue?["name"]?.objectValue?["type"]?.stringValue == "user"
                        && $0.objectValue?["name"]?.objectValue?["profile"]?.stringValue == nil
                }?.objectValue)
            let version = try #require(layer["version"]?.stringValue)
            let file = try #require(layer["name"]?.objectValue?["file"]?.stringValue)
            #expect(file == root.appendingPathComponent("config.toml").path)
            let value: MCPJSONValue = .object(["url": .string("https://example.invalid/mcp"), "enabled": .bool(false)])
            let params: [String: MCPJSONValue] = [
                "filePath": .string(file), "expectedVersion": .string(version),
                "reloadUserConfig": .bool(true),
                "edits": .array([
                    .object([
                        "keyPath": .string("mcp_servers.fixture"), "mergeStrategy": .string("replace"), "value": value,
                    ])
                ]),
            ]
            let written = try await runtime.request("config/batchWrite", params: params)
            let nextVersion = try #require(written.objectValue?["version"]?.stringValue)
            #expect(written.objectValue?["status"]?.stringValue == "ok")
            let readback = try await runtime.request("config/read", params: ["includeLayers": .bool(true)])
            #expect(readback.objectValue?["config"]?.objectValue?["mcp_servers"]?.objectValue?["fixture"]?.objectValue?["url"] == value.objectValue?["url"])
            let raw = readback.objectValue?["layers"]?.arrayValue?.first {
                $0.objectValue?["name"]?.objectValue?["type"]?.stringValue == "user"
            }?.objectValue?["config"]?.objectValue?["mcp_servers"]?.objectValue?["fixture"]
            #expect(raw == value)
            await #expect(throws: CodexConnectionError.self) { try await runtime.request("config/batchWrite", params: params) }
            _ = try await runtime.request(
                "config/batchWrite",
                params: [
                    "filePath": .string(file), "expectedVersion": .string(nextVersion),
                    "reloadUserConfig": .bool(true),
                    "edits": .array([
                        .object([
                            "keyPath": .string("mcp_servers.fixture"), "mergeStrategy": .string("replace"), "value": .null,
                        ])
                    ]),
                ])
            let removed = try await runtime.request("config/read", params: ["includeLayers": .bool(true)])
            #expect(removed.objectValue?["config"]?.objectValue?["mcp_servers"]?.objectValue?["fixture"] == nil)
            let removedVersion = try #require(
                removed.objectValue?["layers"]?.arrayValue?.first {
                    $0.objectValue?["name"]?.objectValue?["type"]?.stringValue == "user"
                }?.objectValue?["version"]?.stringValue)
            _ = try await runtime.request(
                "config/batchWrite",
                params: [
                    "filePath": .string(file), "expectedVersion": .string(removedVersion),
                    "reloadUserConfig": .bool(true),
                    "edits": .array([
                        .object([
                            "keyPath": .string("mcp_servers.\"fixture.other\""), "mergeStrategy": .string("replace"), "value": value,
                        ])
                    ]),
                ])
            let quoted = try await runtime.request("config/read")
            #expect(quoted.objectValue?["config"]?.objectValue?["mcp_servers"]?.objectValue?["fixture.other"]?.objectValue?["url"] == value.objectValue?["url"])
            let snapshot = try await runtime.chatToolConfiguration(home: root)
            let server = AgentChatToolConnection(
                name: "local-fixture", kind: .local, address: "/usr/bin/python3",
                arguments: [repository.appendingPathComponent("Tests/Fixtures/chat-tool-server.py").path, "--require-fixture-environment"],
                environmentVariables: ["SCHOLIUM_TOOL_FIXTURE_TOKEN"])
            #expect(try await runtime.writeChatTool(server, originalName: nil, snapshot: snapshot) == false)
            // Match Scholium's per-turn server injection while retaining the saved optional server.
            let thread = try await runtime.request(
                "thread/start",
                params: [
                    "cwd": .string(root.path),
                    "config": .object([
                        "mcp_servers": .object([
                            "scholium": .object([
                                "command": .string("/usr/bin/python3"),
                                "args": .array([.string(repository.appendingPathComponent("Tests/Fixtures/chat-tool-server.py").path)]),
                                "required": .bool(true), "tool_timeout_sec": .integer(600),
                            ])
                        ])
                    ]),
                ])
            let threadID = try #require(thread.objectValue?["thread"]?.objectValue?["id"]?.stringValue)
            let deadline = ContinuousClock.now.advanced(by: .seconds(12))
            var connected = false
            repeat {
                let tools = try await runtime.chatConnectedTools(threadID: threadID)
                connected = ["local-fixture", "scholium"].allSatisfy { name in
                    tools.contains { $0.name == name && $0.tools.contains("fixture_echo") }
                }
                if !connected { try await Task.sleep(for: .milliseconds(100)) }
            } while !connected && ContinuousClock.now < deadline
            #expect(connected)
            var disabled = server
            disabled.enabled = false
            disabled.environmentVariables = []
            let latest = try await runtime.chatToolConfiguration(home: root)
            _ = try await runtime.writeChatTool(disabled, originalName: server.name, snapshot: latest)
            let afterDisable = try await runtime.chatConnectedTools(threadID: threadID)
            #expect(afterDisable.first(where: { $0.name == server.name })?.connectionStatus == "disabled")
            let afterRemoval = try await runtime.chatToolConfiguration(home: root)
            #expect(afterRemoval.connections.first(where: { $0.name == server.name })?.environmentVariables == [])
            let remote = AgentChatToolConnection(
                name: "remote-env-fixture", address: "https://example.invalid/mcp", enabled: false,
                bearerTokenVariable: "SCHOLIUM_TOOL_FIXTURE_TOKEN")
            _ = try await runtime.writeChatTool(remote, originalName: nil, snapshot: afterRemoval)
            let remoteSnapshot = try await runtime.chatToolConfiguration(home: root)
            var remoteEdit = try #require(remoteSnapshot.connections.first { $0.name == remote.name })
            #expect(remoteEdit.bearerTokenVariable == "SCHOLIUM_TOOL_FIXTURE_TOKEN" && remoteEdit.isEditable)
            remoteEdit.bearerTokenVariable = ""
            _ = try await runtime.writeChatTool(remoteEdit, originalName: remote.name, snapshot: remoteSnapshot)
            let remoteReadback = try await runtime.chatToolConfiguration(home: root)
            #expect(remoteReadback.connections.first(where: { $0.name == remote.name })?.bearerTokenVariable.isEmpty == true)
            #expect(try await runtime.writeChatTool(remoteEdit, originalName: remote.name, snapshot: remoteReadback) == false)
            await runtime.close()
        } catch {
            await runtime.close()
            throw error
        }
    }
}
