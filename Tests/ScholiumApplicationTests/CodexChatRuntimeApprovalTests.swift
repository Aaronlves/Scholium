import ScholiumApplication
import ScholiumContracts
import Testing

@Suite("Runtime approval scope")
struct CodexChatRuntimeApprovalTests {
    private let commandMethod = "item/commandExecution/requestApproval"
    private let permissionsMethod = "item/permissions/requestApproval"

    @Test("MCP tool approval grants only the exact call and rejects unrelated forms")
    func mcpToolApproval() throws {
        let method = "mcpServer/elicitation/request"
        var params: [String: MCPJSONValue] = [
            "threadId": .string("thread"), "turnId": .string("turn"), "serverName": .string("scholium"),
            "mode": .string("form"), "message": .string("Allow the stated tool call?"),
            "_meta": .object([
                "codex_approval_kind": .string("mcp_tool_call"),
                "persist": .array([.string("session"), .string("always")]),
            ]),
            "requestedSchema": .object(["type": .string("object"), "properties": .object([:])]),
        ]
        let request = try CodexChatRuntimeApproval.parse(method: method, params: params, item: nil)
        #expect(request.presentation.kind == .tool && request.presentation.toolServer == "scholium")
        #expect(request.presentation.grants == [.once])
        #expect(try request.response(for: .once) == .object(["action": .string("accept"), "content": .object([:])]))
        #expect(try request.response(for: .decline).objectValue?["action"] == .string("decline"))
        #expect(throws: CodexConnectionError.self) { try request.response(for: .session) }
        params["mode"] = .string("url")
        #expect(throws: CodexConnectionError.self) { try CodexChatRuntimeApproval.parse(method: method, params: params, item: nil) }
        params["mode"] = .string("form")
        params["requestedSchema"] = .object(["type": .string("object"), "properties": .object(["secret": .object(["type": .string("string")])])])
        #expect(throws: CodexConnectionError.self) { try CodexChatRuntimeApproval.parse(method: method, params: params, item: nil) }
        params["requestedSchema"] = .object(["type": .string("object"), "properties": .object([:])])
        params["_meta"] = .object([:])
        #expect(throws: CodexConnectionError.self) { try CodexChatRuntimeApproval.parse(method: method, params: params, item: nil) }
    }

    @Test("Terminal input, session-only choices and policy amendments cannot silently become Allow Once")
    func decisions() throws {
        var params: [String: MCPJSONValue] = [
            "kind": .string("writeStdin"), "command": .string("exact 中文 input\n"),
            "cwd": .string("/fixture"), "availableDecisions": .array([.string("accept"), .string("decline")]),
        ]
        let input = try CodexChatRuntimeApproval.parse(method: commandMethod, params: params, item: nil)
        #expect(input.presentation.kind == .terminalInput && input.presentation.command == "exact 中文 input\n" && input.presentation.grants == [.once])
        #expect(try input.response(for: .once) == .object(["decision": .string("accept")]))
        var networkParams = params
        networkParams["networkApprovalContext"] = .object(["host": .string("sources.example.test:8443"), "protocol": .string("https")])
        let network = try CodexChatRuntimeApproval.parse(method: commandMethod, params: networkParams, item: nil)
        #expect(network.presentation.kind == .network && network.presentation.networkHost == "sources.example.test:8443")
        #expect(throws: CodexConnectionError.self) { try input.response(for: .session) }
        params["availableDecisions"] = .array([.string("acceptForSession"), .string("cancel")])
        let session = try CodexChatRuntimeApproval.parse(method: commandMethod, params: params, item: nil)
        #expect(session.presentation.grants == [.session] && session.presentation.rejection == .cancel)
        #expect(throws: CodexConnectionError.self) { try session.response(for: .once) }
        params["availableDecisions"] = .array([
            .object(["acceptWithExecpolicyAmendment": .object(["execpolicy_amendment": .array([.string("echo")])])]), .string("decline"),
        ])
        let policy = try CodexChatRuntimeApproval.parse(method: commandMethod, params: params, item: nil)
        #expect(policy.presentation.grants.isEmpty)
        #expect(try policy.response(for: .decline) == .object(["decision": .string("decline")]))
        params["availableDecisions"] = .array([.integer(3), .string("accept"), .string("decline")])
        #expect(throws: CodexConnectionError.self) { try CodexChatRuntimeApproval.parse(method: commandMethod, params: params, item: nil) }
    }

    @Test("Permission responses preserve the exact requested rules and reject unknown grant scope")
    func permissions() throws {
        let profile: MCPJSONValue = .object([
            "network": .object(["enabled": .bool(false)]),
            "fileSystem": .object([
                "read": .array([.string("/fixture/source")]),
                "entries": .array([
                    .object(["access": .string("write"), "path": .object(["type": .string("glob_pattern"), "pattern": .string("/fixture/**/*.md")])]),
                    .object([
                        "access": .string("deny"),
                        "path": .object(["type": .string("special"), "value": .object(["kind": .string("project_roots"), "subpath": .string("private")])]),
                    ]),
                ]),
                "globScanMaxDepth": .integer(4),
            ]),
        ])
        let params: [String: MCPJSONValue] = ["cwd": .string("/fixture"), "permissions": profile]
        let request = try CodexChatRuntimeApproval.parse(method: permissionsMethod, params: params, item: nil)
        #expect(
            request.presentation.permissions?.rules.count == 3 && request.presentation.permissions?.network == false
                && request.presentation.permissions?.globScanMaxDepth == 4)
        #expect(try request.response(for: .turn) == .object(["permissions": profile, "scope": .string("turn")]))
        #expect(try request.response(for: .session) == .object(["permissions": profile, "scope": .string("session")]))
        #expect(try request.response(for: .decline) == .object(["permissions": .object([:]), "scope": .string("turn")]))
        for unknown: MCPJSONValue in [
            .object(["allVolumes": .bool(true)]),
            .object(["network": .object(["enabled": .bool(true), "futureScope": .string("all")])]),
            .object(["fileSystem": .object(["entries": .array([.object(["access": .string("write"), "path": .object(["type": .string("unknown")])])])])]),
        ] {
            #expect(throws: CodexConnectionError.self) {
                try CodexChatRuntimeApproval.parse(method: permissionsMethod, params: ["cwd": .string("/fixture"), "permissions": unknown], item: nil)
            }
        }
    }

    @Test("File proposals retain moves and exact diffs; a requested session root is never a one-time grant")
    func files() throws {
        let item: MCPJSONValue = .object([
            "type": .string("fileChange"),
            "changes": .array([
                .object([
                    "path": .string("/fixture/old.md"), "diff": .string("-old\n+new\n"),
                    "kind": .object(["type": .string("update"), "move_path": .string("/fixture/new.md")]),
                ])
            ]),
        ])
        let request = try CodexChatRuntimeApproval.parse(method: "item/fileChange/requestApproval", params: [:], item: .init(item))
        #expect(request.presentation.files.first?.destination == "/fixture/new.md" && request.presentation.files.first?.diff == "-old\n+new\n")
        let root = try CodexChatRuntimeApproval.parse(
            method: "item/fileChange/requestApproval",
            params: ["grantRoot": .string("/fixture")], item: .init(item))
        #expect(root.presentation.grants == [.session])
        #expect(throws: CodexConnectionError.self) { try root.response(for: .once) }
        #expect(throws: CodexConnectionError.self) { try CodexChatRuntimeApproval.parse(method: "item/fileChange/requestApproval", params: [:], item: nil) }
    }
}
