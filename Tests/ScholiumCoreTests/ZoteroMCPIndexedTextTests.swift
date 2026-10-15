import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Bounded Zotero indexed attachment reading")
struct ZoteroMCPIndexedTextTests {
    @Test("Unicode continuation preserves exact indexed bytes and keeps index coverage distinct from original access")
    func exactIndexedSlices() async throws {
        let text = "\u{FEFF}α研究\r\n😀Tail\r\n"
        let client = try IndexedTextClient(text: text, metadata: ["indexedPages": .integer(3), "totalPages": .integer(8)])
        let server = ZoteroMCPServer(client: client)
        let first = try await call(server, ["maximum_utf8": .integer(5)])
        #expect(!first.failed && first.value["text"] == .string("\u{FEFF}α"))
        #expect(first.value["source_kind"] == .string("zotero_indexed_text"))
        #expect(first.value["original_file_read"] == .bool(false))
        #expect(first.value["coverage"] == .string("indexed_text_slice"))
        #expect(first.value["index_version"] == .string("7"))
        #expect(first.value["index_metadata"]?.objectValue == ["indexedPages": .integer(3), "totalPages": .integer(8)])
        #expect(first.value["reference"]?.objectValue?["url"] == .string("zotero://select/groups/42/items/ATTACH01"))
        #expect(first.value["reference"]?.objectValue?["page"] == .null)
        #expect(first.value["parent_reference"]?.objectValue?["url"] == .string("zotero://select/groups/42/items/PARENT01"))
        let fingerprint = try #require(first.value["indexed_fingerprint"]?.stringValue)
        let next = try await call(server, ["start_utf8": .integer(5), "expected_fingerprint": .string(fingerprint)])
        #expect(!next.failed && next.value["text"] == .string("研究\r\n😀Tail\r\n"))
        #expect(next.value["end_utf8"] == .integer(text.utf8.count) && next.value["total_utf8"] == .integer(text.utf8.count))
        #expect(next.value["next_start_utf8"] == .null && next.value["indexed_fingerprint"] == .string(fingerprint))
        #expect(first.value["fulltext"] == nil && next.value["original_fingerprint"] == nil)
        #expect(await client.requests.allSatisfy { $0.httpMethod == "GET" && $0.url?.host == "127.0.0.1" && !$0.url!.path.contains("file") })
    }

    @Test("Large indexed text is available in bounded slices instead of exceeding the complete MCP reply")
    func largeIndexedText() async throws {
        let text = String(repeating: "\"", count: 1_536 * 1_024)
        let client = try IndexedTextClient(text: text)
        let response = try await call(ZoteroMCPServer(client: client))
        #expect(!response.failed && response.wire.count <= ScholiumMCPContract.maximumEncodedMessageByteCount)
        #expect(response.value["text"]?.stringValue?.utf8.count == 16_384)
        #expect(response.value["total_utf8"] == .integer(text.utf8.count))
        #expect(response.value["next_start_utf8"] == .integer(16_384))
    }

    @Test("Continuation rejects changed indexed content, index versions and attachment identity before returning text")
    func staleContinuation() async throws {
        for change in ["content", "indexVersion", "attachment", "server"] {
            let client = try IndexedTextClient(text: "Exact source")
            let server = ZoteroMCPServer(client: client)
            let first = try await call(server, ["maximum_utf8": .integer(5)])
            let fingerprint = try #require(first.value["indexed_fingerprint"]?.stringValue)
            try await client.change(change)
            let next = try await call(server, ["start_utf8": .integer(5), "expected_fingerprint": .string(fingerprint)])
            #expect(next.failed && next.value["error_code"] == .string("material_changed"))
            #expect(next.value["text"] == nil)
        }
    }

    @Test("Changes across suspended index and attachment reads cannot publish a mixed result")
    func concurrentChanges() async throws {
        for change in ["content", "indexVersion", "attachment", "server"] {
            let client = try IndexedTextClient(text: "Initial text")
            await client.changeDuringRead(change)
            let response = try await call(ZoteroMCPServer(client: client))
            #expect(response.failed && response.value["error_code"] == .string("material_changed"))
            #expect(response.value["text"] == nil && response.value["reference"] == nil)
        }
    }

    @Test("Invalid continuation cannot split scalars, make no progress or bypass required scope")
    func invalidBounds() async throws {
        let client = try IndexedTextClient(text: "α研究")
        let server = ZoteroMCPServer(client: client)
        for arguments: [String: ZoteroMCPJSONValue] in [
            ["start_utf8": .integer(1)], ["maximum_utf8": .integer(0)], ["maximum_utf8": .integer(65_537)],
            ["start_utf8": .integer(-1)], ["library": .null], ["path": .string("/arbitrary")],
        ] {
            let response = try await call(server, arguments)
            #expect(response.failed && response.value["error_code"] == .string("invalid_arguments"))
        }
        #expect(await client.requests.isEmpty)
        let first = try await call(server)
        let fingerprint = try #require(first.value["indexed_fingerprint"]?.stringValue)
        for arguments: [String: ZoteroMCPJSONValue] in [
            ["start_utf8": .integer(1), "expected_fingerprint": .string(fingerprint)],
            ["start_utf8": .integer(100), "expected_fingerprint": .string(fingerprint)],
            ["maximum_utf8": .integer(1)],
        ] {
            let response = try await call(server, arguments)
            #expect(response.failed && response.value["error_code"] == .string("invalid_arguments"))
            #expect(response.value["text"] == nil)
        }
        let end = try await call(server, ["start_utf8": .integer(8), "expected_fingerprint": .string(fingerprint)])
        #expect(!end.failed && end.value["text"] == .string("") && end.value["next_start_utf8"] == .null)
    }

    @Test("Empty and invalid indexed responses stay explicit without original access or invented page locations")
    func responseCoverage() async throws {
        let empty = try IndexedTextClient(text: "", metadata: ["indexedChars": .integer(0), "totalChars": .integer(10)])
        let response = try await call(ZoteroMCPServer(client: empty))
        #expect(!response.failed && response.value["text_available"] == .bool(false))
        #expect(response.value["total_utf8"] == .integer(0))
        #expect(response.value["index_metadata"]?.objectValue?["totalChars"] == .integer(10))
        let invalid = try IndexedTextClient(text: "Text", metadata: ["indexedPages": .integer(-1)])
        let refusal = try await call(ZoteroMCPServer(client: invalid))
        #expect(refusal.failed && refusal.value["error_code"] == .string("invalid_response"))
        #expect(refusal.value["text"] == nil)
    }

    private struct Response {
        let wire: Data
        let result: [String: ZoteroMCPJSONValue]
        var value: [String: ZoteroMCPJSONValue] { result["structuredContent"]?.objectValue ?? [:] }
        var failed: Bool { result["isError"] == .bool(true) }
    }

    private func call(_ server: ZoteroMCPServer, _ extra: [String: ZoteroMCPJSONValue] = [:]) async throws -> Response {
        let arguments: [String: ZoteroMCPJSONValue] = ["library": .string("group:42"), "attachment_key": .string("ATTACH01")]
        let request = ZoteroMCPJSONValue.object([
            "jsonrpc": .string("2.0"), "id": .integer(1), "method": .string("tools/call"),
            "params": .object(["name": .string("zotero_fulltext"), "arguments": .object(arguments.merging(extra, uniquingKeysWith: { _, new in new }))]),
        ])
        let wire = try #require(await server.handle(requestData: JSONEncoder().encode(request), access: .readOnly))
        let result = try #require(JSONDecoder().decode(ZoteroMCPJSONValue.self, from: wire).objectValue?["result"]?.objectValue)
        return Response(wire: wire, result: result)
    }
}

private actor IndexedTextClient: ZoteroMCPHTTPClient {
    private var attachment: ZoteroMCPJSONValue
    private var index: ZoteroMCPJSONValue
    private var indexVersion = "7"
    private var serverID = "fixture-instance"
    private var duringRead: String?
    private(set) var requests: [URLRequest] = []

    init(text: String, metadata: [String: ZoteroMCPJSONValue] = [:]) throws {
        attachment = .object([
            "key": .string("ATTACH01"), "version": .integer(1),
            "data": .object([
                "key": .string("ATTACH01"), "itemType": .string("attachment"), "parentItem": .string("PARENT01"),
                "linkMode": .string("imported_file"), "contentType": .string("application/pdf"),
            ]),
        ])
        index = .object(metadata.merging(["content": .string(text)], uniquingKeysWith: { _, new in new }))
    }

    func changeDuringRead(_ change: String) { duringRead = change }

    func change(_ change: String) throws {
        switch change {
        case "content":
            var object = index.objectValue ?? [:]
            object["content"] = .string("Changed indexed source")
            index = .object(object)
        case "indexVersion": indexVersion = "8"
        case "attachment":
            var object = attachment.objectValue ?? [:]
            object["version"] = .integer(2)
            var data = object["data"]?.objectValue ?? [:]
            data["parentItem"] = .string("PARENT02")
            object["data"] = .object(data)
            attachment = .object(object)
        case "server": serverID = "replacement-instance"
        default: break
        }
    }

    func send(_ request: URLRequest) async throws -> ZoteroMCPHTTPResponse {
        requests.append(request)
        if requests.count == 3, let duringRead { try change(duringRead) }
        let path = request.url?.path ?? ""
        let value: ZoteroMCPJSONValue
        if path == "/api/groups/42/items/ATTACH01" {
            value = attachment
        } else if path == "/api/groups/42/items/ATTACH01/fulltext" {
            value = index
        } else {
            throw URLError(.badURL)
        }
        return .init(
            statusCode: 200,
            headers: ["Zotero-Server-ID": serverID, "Last-Modified-Version": indexVersion],
            body: try JSONEncoder().encode(value))
    }
}
