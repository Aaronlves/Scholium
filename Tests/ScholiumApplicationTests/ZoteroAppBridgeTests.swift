import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("App-owned Zotero delivery", .serialized)
struct ZoteroAppBridgeTests {
    @Test("Authenticated Zotero calls preserve original-page output and the helper's access profile", arguments: [ZoteroMCPAccess.full, .readOnly])
    func exactReplyRoundTrip(access: ZoteroMCPAccess) async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let counter = ZoteroBridgeCallCounter()
        let call = request(
            tool: "zotero_read_original_page",
            arguments: [
                "library": .string("group:42"), "attachment_key": .string("ATTACH01"),
                "page": .integer(2), "mode": .string("image"),
            ])
        let expected: MCPJSONValue = .object([
            "jsonrpc": .string("2.0"), "id": .integer(41),
            "result": .object([
                "content": .array([
                    .object(["type": .string("text"), "text": .string("\u{FEFF}α研究\r\nExact physical page 2\r\n")]),
                    .object(["type": .string("image"), "mimeType": .string("image/png"), "data": .string("Zml4dHVyZS1wbmc=")]),
                ]),
                "structuredContent": .object([
                    "source_kind": .string("zotero_original"), "original_file_read": .bool(true),
                    "original_fingerprint": .string(String(repeating: "a", count: 64)),
                    "page": .integer(2), "total_pages": .integer(3),
                ]), "isError": .bool(false),
            ]),
        ])
        let server = try ScholiumAppBridgeServer(
            applicationSupportURL: root,
            zoteroHandler: { envelope in
                await counter.increment()
                #expect(envelope.access == access && envelope.request == call)
                return expected
            }
        ) { _ in
            Issue.record("A Zotero call must not enter the research-operation router.")
            throw ScholiumAppBridgeError.invalidRequest
        }
        defer { server.stop() }
        let handler = try helper(root: root, access: access)
        let reply = try #require(await handler(JSONEncoder().encode(call)))
        #expect(try JSONDecoder().decode(MCPJSONValue.self, from: reply) == expected)
        #expect(await counter.count == 1)
        #expect(await server.stopAndWait(timeout: 1))
    }

    @Test("Discovery stays local while missing App calls fail without executing Zotero", arguments: [ZoteroMCPAccess.full, .readOnly])
    func missingApp(access: ZoteroMCPAccess) async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let handler = try helper(root: root, access: access)
        for method in ["initialize", "ping", "tools/list"] {
            let reply = try #require(
                await handler(
                    JSONEncoder().encode(
                        MCPJSONValue.object([
                            "jsonrpc": .string("2.0"), "id": .integer(1), "method": .string(method),
                        ]))))
            #expect(try JSONDecoder().decode(MCPJSONValue.self, from: reply).objectValue?["result"] != nil)
        }
        for tool in ["zotero_read_original_page", "zotero_fulltext", "zotero_update_item"] {
            let failure = try await failure(handler, call: request(tool: tool))
            #expect(failure["status"] == .string("failed"))
            #expect(failure["error_code"] == .string("app_unavailable"))
        }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test("A read-only connection cannot gain item-update authority through the App bridge")
    func readOnlyAdmission() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let zotero = ZoteroOperations()
        let server = try ScholiumAppBridgeServer(
            applicationSupportURL: root,
            zoteroHandler: { envelope in
                let data = try #require(await zotero.handle(requestData: JSONEncoder().encode(envelope.request), access: envelope.access))
                return try JSONDecoder().decode(MCPJSONValue.self, from: data)
            }
        ) { _ in throw ScholiumAppBridgeError.invalidRequest }
        defer { server.stop() }
        let handler = try helper(root: root, access: .readOnly)
        let failure = try await failure(handler, call: request(tool: "zotero_update_item"))
        #expect(failure["status"] == .string("failed") && failure["error_code"] == .string("unknown_tool"))
        #expect(await server.stopAndWait(timeout: 1))
    }

    @Test("Lost or mismatched update confirmations stay uncertain without replay", arguments: [false, true])
    func uncertainUpdate(throwAfterAdmission: Bool) async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let counter = ZoteroBridgeCallCounter()
        let server = try ScholiumAppBridgeServer(
            applicationSupportURL: root,
            zoteroHandler: { _ in
                await counter.increment()
                if throwAfterAdmission { throw ScholiumAppBridgeError.invalidResponse }
                return .object(["jsonrpc": .string("2.0"), "id": .integer(999), "result": .object([:])])
            }
        ) { _ in throw ScholiumAppBridgeError.invalidRequest }
        defer { server.stop() }
        let handler = try helper(root: root, access: .full)
        let failure = try await failure(handler, call: request(tool: "zotero_update_item"))
        #expect(failure["status"] == .string("outcome_uncertain"))
        #expect(failure["error_code"] == .string("write_outcome_uncertain"))
        #expect(failure["error"]?.stringValue?.contains("Do not replay") == true)
        #expect(await counter.count == 1)
        #expect(await server.stopAndWait(timeout: 1))
    }

    @Test("Matching identities cannot turn malformed update replies into confirmation", arguments: MalformedZoteroConfirmation.allCases)
    func malformedMatchingUpdate(scenario: MalformedZoteroConfirmation) async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let counter = ZoteroBridgeCallCounter()
        let server = try ScholiumAppBridgeServer(
            applicationSupportURL: root,
            zoteroHandler: { _ in
                await counter.increment()
                return .object(["jsonrpc": .string("2.0"), "id": .integer(41)].merging(scenario.fields) { _, value in value })
            }
        ) { _ in throw ScholiumAppBridgeError.invalidRequest }
        defer { server.stop() }
        let handler = try helper(root: root, access: .full)
        let failure = try await failure(handler, call: request(tool: "zotero_update_item"))
        #expect(failure["status"] == .string("outcome_uncertain"))
        #expect(failure["error_code"] == .string("write_outcome_uncertain"))
        #expect(failure["error"]?.stringValue?.contains("Do not replay") == true)
        #expect(await counter.count == 1)
        #expect(await server.stopAndWait(timeout: 1))
    }

    @Test("Typed RPC refusals and tool results with an omitted error flag retain their exact payload", arguments: [false, true])
    func validConfirmationPayload(rpcRefusal: Bool) async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let outcome: MCPJSONValue =
            rpcRefusal
            ? .object(["code": .integer(-32601), "message": .string("Unavailable tool"), "data": .object(["exact": .string("α\r\n")])])
            : .object(["content": .array([.object(["type": .string("text"), "text": .string("α\r\n")])])])
        let expected = MCPJSONValue.object(["jsonrpc": .string("2.0"), "id": .integer(41), (rpcRefusal ? "error" : "result"): outcome])
        let server = try ScholiumAppBridgeServer(applicationSupportURL: root, zoteroHandler: { _ in expected }) {
            _ in throw ScholiumAppBridgeError.invalidRequest
        }
        defer { server.stop() }
        let handler = try helper(root: root, access: .full)
        let reply = try #require(await handler(JSONEncoder().encode(request(tool: "zotero_update_item"))))
        #expect(try JSONDecoder().decode(MCPJSONValue.self, from: reply) == expected)
        #expect(await server.stopAndWait(timeout: 1))
    }

    @Test("Bridge envelopes reject mixed targets, missing outcomes, old versions and path-bearing Zotero envelopes")
    func closedEnvelope() throws {
        let research = ScholiumAppBridgeRequest(mcpRequest: .init(tool: .search))
        let zotero = try ScholiumZoteroBridgeRequest(access: .readOnly, request: request(tool: "zotero_item"))
        let encoded = try JSONEncoder().encode(ScholiumAppBridgeRequest(zoteroRequest: zotero))
        #expect(try JSONDecoder().decode(ScholiumAppBridgeRequest.self, from: encoded).zoteroRequest == zotero)
        let researchJSON = try JSONDecoder().decode(MCPJSONValue.self, from: JSONEncoder().encode(research))
        let zoteroJSON = try JSONDecoder().decode(MCPJSONValue.self, from: JSONEncoder().encode(zotero))
        var mixed = try #require(researchJSON.objectValue)
        mixed["zotero_request"] = zoteroJSON
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ScholiumAppBridgeRequest.self, from: JSONEncoder().encode(MCPJSONValue.object(mixed))) }
        mixed["mcp_request"] = nil
        mixed["zotero_request"] = nil
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ScholiumAppBridgeRequest.self, from: JSONEncoder().encode(MCPJSONValue.object(mixed))) }
        mixed["zotero_request"] = zoteroJSON
        mixed["schema_version"] = .integer(1)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ScholiumAppBridgeRequest.self, from: JSONEncoder().encode(MCPJSONValue.object(mixed))) }
        var pathBearing = try #require(zoteroJSON.objectValue)
        pathBearing["path"] = .string("/private/fixture.pdf")
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ScholiumZoteroBridgeRequest.self, from: JSONEncoder().encode(MCPJSONValue.object(pathBearing)))
        }
        #expect(throws: ScholiumAppBridgeError.invalidResponse) { try ScholiumAppBridgeResponse(correlationID: UUID()) }
        #expect(throws: ScholiumAppBridgeError.invalidResponse) {
            try ScholiumAppBridgeResponse(correlationID: UUID(), zoteroResponse: .object([:]), error: .init(code: "failed", message: "simultaneous"))
        }
    }

    private func makeRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/zotero-app-bridge-tests/\(UUID())")
    }
    private func helper(root: URL, access: ZoteroMCPAccess) throws -> AgentMCPService.Handler {
        try AgentMCPService.helperHandler(
            arguments: ["zotero", "mcp", "serve"] + (access == .readOnly ? ["--read-only"] : []),
            environment: ["SCHOLIUM_APP_BRIDGE_CONTAINER": root.path])
    }
    private func request(tool: String, arguments: [String: MCPJSONValue] = [:]) -> MCPJSONValue {
        .object([
            "jsonrpc": .string("2.0"), "id": .integer(41), "method": .string("tools/call"),
            "params": .object(["name": .string(tool), "arguments": .object(arguments)]),
        ])
    }
    private func failure(_ handler: AgentMCPService.Handler, call: MCPJSONValue) async throws -> [String: MCPJSONValue] {
        let reply = try #require(await handler(JSONEncoder().encode(call)))
        let result = try #require(try JSONDecoder().decode(MCPJSONValue.self, from: reply).objectValue?["result"]?.objectValue)
        #expect(result["isError"] == .bool(true))
        return try #require(result["structuredContent"]?.objectValue)
    }
}

enum MalformedZoteroConfirmation: String, CaseIterable, Sendable {
    case nullResult, emptyResult, missingContent, nonArrayContent, emptyContent, missingText, wrongImageData
    case wrongErrorFlag, nonObjectStructuredContent, nullRPCError, wrongRPCErrorCode, missingRPCErrorMessage

    var fields: [String: MCPJSONValue] {
        var result: [String: MCPJSONValue] = ["content": .array([.object(["type": .string("text"), "text": .string("Update output")])])]
        switch self {
        case .nullResult: return ["result": .null]
        case .emptyResult: return ["result": .object([:])]
        case .missingContent: result = ["isError": .bool(false)]
        case .nonArrayContent: result["content"] = .object([:])
        case .emptyContent: result["content"] = .array([])
        case .missingText: result["content"] = .array([.object(["type": .string("text")])])
        case .wrongImageData: result["content"] = .array([.object(["type": .string("image"), "mimeType": .string("image/png"), "data": .integer(1)])])
        case .wrongErrorFlag: result["isError"] = .string("false")
        case .nonObjectStructuredContent: result["structuredContent"] = .null
        case .nullRPCError: return ["error": .null]
        case .wrongRPCErrorCode: return ["error": .object(["code": .string("-32601"), "message": .string("Malformed refusal")])]
        case .missingRPCErrorMessage: return ["error": .object(["code": .integer(-32601)])]
        }
        return ["result": .object(result)]
    }
}

private actor ZoteroBridgeCallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}
