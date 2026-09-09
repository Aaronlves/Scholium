import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApplication

@Suite("Scholium stdio MCP")
struct ScholiumMCPServerTests {
    @Test("Attachment images reach MCP as native image content while text describes their scope")
    func attachmentImageDelivery() async throws {
        let image: MCPJSONValue = .object(["mime_type": .string("image/png"), "data": .string("cG5n"), "pixel_width": .integer(1), "pixel_height": .integer(1)])
        let server = ScholiumMCPServer { _ in .object(["kind": .string("pdf_page_image"), "page": .integer(2), "image": image]) }
        let response = try await rpc(server, id: 1, method: "tools/call", params: ["name": "scholium_read_attachment", "arguments": [:]])
        let result = try object(response["result"])
        let content = try #require(result["content"] as? [[String: Any]])
        #expect(content.count == 2 && content[1]["type"] as? String == "image" && content[1]["mimeType"] as? String == "image/png")
        #expect(content[1]["data"] as? String == "cG5n")
        #expect(content[0]["text"] as? String != nil && (content[0]["text"] as? String)?.contains("cG5n") == false)
        #expect(try object(object(result["structuredContent"])["image"])["data"] as? String == "cG5n")
    }

    @Test("Partial move recovery returns bounded per-file outcomes without claiming successful mutation")
    func moveRecoveryIsStructured() async throws {
        let before = DocumentFingerprint(content: "Before"), intended = DocumentFingerprint(content: "After")
        let record = TriptychMutationRecoveryRecord(triptychID: UUID(), operation: .noteMove, failure: "Synthetic rollback interruption",
            files: (0..<101).map { index in .init(vaultID: UUID(), path: "Note\(index).md", alternatePath: index == 0 ? "Moved.md" : nil,
                role: index == 0 ? .movedNote : .incomingLinkRewrite, beforeRevision: before, intendedRevision: intended,
                observedRevision: index == 0 ? intended : before, state: index == 0 ? .intendedBytesRemain : .restored, detail: "Synthetic readback") })
        let failure = ScholiumMCPFailure(code: .operationUncertain, message: record.failure,
            recovery: "Inspect the retained Recovery record before another mutation.", recoveryDetails: .init(record: record))
        let transported = try JSONDecoder().decode(ScholiumMCPFailure.self, from: JSONEncoder().encode(failure))
        let server = ScholiumMCPServer { _ in throw transported }
        let response = try await rpc(server, id: 1, method: "tools/call", params: ["name": "scholium_move_note", "arguments": [:]])
        let result = try object(response["result"])
        #expect(result["isError"] as? Bool == true)
        let structured = try object(result["structuredContent"])
        #expect(structured["code"] as? String == "operation_uncertain" && structured["readback_verified"] == nil)
        let recovery = try object(structured["recovery_details"])
        #expect(recovery["recovery_id"] as? String == record.id.uuidString.lowercased())
        #expect(recovery["total"] as? Int == 101 && recovery["has_more"] as? Bool == true)
        let files = try #require(recovery["files"] as? [[String: Any]])
        #expect(files.count == 100 && files[0]["state"] as? String == "intendedBytesRemain")
        #expect(files[1]["state"] as? String == "restored")
        #expect(try object(files[0]["observed_fingerprint"])["sha256"] as? String == intended.sha256)
        #expect(try object(files[1]["observed_fingerprint"])["sha256"] as? String == before.sha256)
    }

    @Test("Initialization and discovery publish exactly the fixed local tool surface")
    func discoveryIsDataFreeAndClosed() async throws {
        let recorder = MCPRequestRecorder()
        let server = ScholiumMCPServer { request in
            await recorder.record(request)
            return .object(["schema_version": .integer(5), "status": .string("ok")])
        }

        let initialized = try await rpc(
            server,
            id: 1,
            method: "initialize",
            params: ["protocolVersion": "2025-11-25"]
        )
        let result = try object(initialized["result"])
        #expect(result["protocolVersion"] as? String == "2025-11-25")
        #expect(try object(result["serverInfo"])["name"] as? String == "scholium")
        #expect((result["instructions"] as? String)?.contains("workspace_status") == true)

        let listed = try await rpc(server, id: 2, method: "tools/list", params: [:])
        let listResult = try object(listed["result"])
        let tools = try #require(listResult["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String } ==
            ScholiumMCPToolName.allCases.map(\.rawValue))
        #expect(tools.count == 16)
        for tool in tools {
            let schema = try object(tool["inputSchema"])
            #expect(schema["additionalProperties"] as? Bool == false)
            let outputSchema = try object(tool["outputSchema"])
            let variants = try #require(
                outputSchema["oneOf"] as? [[String: Any]]
            )
            #expect(!variants.isEmpty)
            #expect(variants.allSatisfy {
                $0["additionalProperties"] as? Bool == false
            })
            let annotations = try object(tool["annotations"])
            #expect(annotations["openWorldHint"] as? Bool == false)
        }
        let update = try #require(tools.first { $0["name"] as? String == "scholium_update_note" })
        let input = try object(update["inputSchema"])
        let alternatives = try #require(input["oneOf"] as? [[String: Any]])
        #expect(alternatives.count == 2)
        let properties = try object(input["properties"])
        let edits = try object(properties["edits"])
        #expect(edits["maxItems"] as? Int == 100)
        let edit = try object(edits["items"])
        #expect(edit["additionalProperties"] as? Bool == false)
        #expect(Set(try #require(edit["required"] as? [String])) == Set(["start_utf8", "end_utf8", "expected_text", "replacement"]))
        let show = try #require(tools.first { $0["name"] as? String == "scholium_show_note" })
        #expect(try object(show["inputSchema"])["oneOf"] as? [[String: Any]] != nil)
        #expect(try object(show["annotations"])["readOnlyHint"] as? Bool == false)
        #expect(try object(show["annotations"])["idempotentHint"] as? Bool == false)
        #expect(await recorder.requests().isEmpty)
    }

    @Test("Tool calls carry only the named tool and argument object to the App bridge")
    func toolCallDelegatesToAppBridge() async throws {
        let recorder = MCPRequestRecorder()
        let server = ScholiumMCPServer { request in
            await recorder.record(request)
            return .object([
                "schema_version": .integer(5),
                "status": .string("ok"),
                "current": .bool(false),
            ])
        }
        let response = try await rpc(
            server,
            id: 1,
            method: "tools/call",
            params: [
                "name": ScholiumMCPToolName.workspaceStatus.rawValue,
                "arguments": [:],
            ]
        )
        let result = try object(response["result"])
        #expect(result["isError"] as? Bool == false)
        let structured = try object(result["structuredContent"])
        #expect(structured["status"] as? String == "ok")
        let requests = await recorder.requests()
        #expect(requests.count == 1)
        #expect(requests[0].tool == .workspaceStatus)
        #expect(requests[0].arguments.isEmpty)
    }

    @Test("Runtime turn metadata stays separate from tool arguments across the bridge")
    func runtimeContextIsTransportMetadata() async throws {
        let recorder = MCPRequestRecorder()
        let server = ScholiumMCPServer { request in
            await recorder.record(request)
            return .object(["status": .string("ok")])
        }
        _ = try await rpc(server, id: 1, method: "tools/call", params: [
            "name": ScholiumMCPToolName.workspaceStatus.rawValue,
            "arguments": [:],
            "_meta": ["x-codex-turn-metadata": ["thread_id": "thread-1", "turn_id": "turn-1"]],
        ])
        _ = try await rpc(server, id: 2, method: "tools/call", params: [
            "name": ScholiumMCPToolName.workspaceStatus.rawValue,
            "arguments": [:],
            "_meta": ["x-codex-turn-metadata": ["thread_id": "thread-1", "turn_id": ""]],
        ])
        let requests = await recorder.requests()
        #expect(requests[0].runtimeContext == .init(threadID: "thread-1", turnID: "turn-1"))
        #expect(requests.allSatisfy { $0.arguments.isEmpty && $0.conversationToken == nil })
        #expect(requests[1].runtimeContext == nil)
        let decoded = try JSONDecoder().decode(ScholiumMCPBridgeRequest.self, from: JSONEncoder().encode(requests[0]))
        #expect(decoded == requests[0] && decoded.schemaVersion == 3)
    }

    @Test("Expected App failures remain structured MCP tool failures")
    func domainFailureIsStructured() async throws {
        let server = ScholiumMCPServer { _ in
            throw ScholiumMCPFailure(
                code: .workspaceNotReady,
                message: "No open Triptych.",
                recovery: "Open one Triptych."
            )
        }
        let response = try await rpc(
            server,
            id: 1,
            method: "tools/call",
            params: [
                "name": ScholiumMCPToolName.workspaceStatus.rawValue,
                "arguments": [:],
            ]
        )
        let result = try object(response["result"])
        #expect(result["isError"] as? Bool == true)
        let structured = try object(result["structuredContent"])
        #expect(structured["schema_version"] as? Int == 5)
        #expect(structured["status"] as? String == "failed")
        #expect(structured["code"] as? String == "workspace_not_ready")
        #expect(structured["recovery"] as? String == "Open one Triptych.")
    }

    private func rpc(
        _ server: ScholiumMCPServer,
        id: Int,
        method: String,
        params: [String: Any]
    ) async throws -> [String: Any] {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ]
        let data = try JSONSerialization.data(withJSONObject: request)
        let responseData = try #require(await server.handle(requestData: data))
        return try #require(
            JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        )
    }

    private func object(_ value: Any?) throws -> [String: Any] {
        try #require(value as? [String: Any])
    }
}

private actor MCPRequestRecorder {
    private var values: [ScholiumMCPBridgeRequest] = []

    func record(_ request: ScholiumMCPBridgeRequest) {
        values.append(request)
    }

    func requests() -> [ScholiumMCPBridgeRequest] { values }
}
