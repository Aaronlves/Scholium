import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApplication

@Suite("Scholium stdio MCP")
struct ScholiumMCPServerTests {
    @Test("Initialization and discovery publish exactly the fixed local tool surface")
    func discoveryIsDataFreeAndClosed() async throws {
        let recorder = MCPRequestRecorder()
        let server = ScholiumMCPServer { request in
            await recorder.record(request)
            return .object(["schema_version": .integer(2), "status": .string("ok")])
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
        #expect(tools.count == 10)
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
        #expect(await recorder.requests().isEmpty)
    }

    @Test("Tool calls carry only the named tool and argument object to the App bridge")
    func toolCallDelegatesToAppBridge() async throws {
        let recorder = MCPRequestRecorder()
        let server = ScholiumMCPServer { request in
            await recorder.record(request)
            return .object([
                "schema_version": .integer(2),
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
        #expect(structured["schema_version"] as? Int == 2)
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
