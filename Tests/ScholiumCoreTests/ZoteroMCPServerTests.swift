import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("First-party Zotero MCP transport")
struct ZoteroMCPServerTests {
    @Test("Initialize and tool discovery do not contact Zotero")
    func protocolDiscoveryIsDataFree() async throws {
        let client = MockZoteroMCPHTTPClient()
        let server = ZoteroMCPServer(client: client)

        let initialize = try await rpc(
            server,
            id: 1,
            method: "initialize",
            params: ["protocolVersion": "2024-11-05"]
        )
        let initializeResult = try object(initialize["result"])
        #expect(initializeResult["protocolVersion"] as? String == "2024-11-05")
        let serverInfo = try object(initializeResult["serverInfo"])
        #expect(serverInfo["name"] as? String == "scholium-zotero")

        let list = try await rpc(server, id: 2, method: "tools/list", params: [:])
        let listResult = try object(list["result"])
        let tools = try #require(listResult["tools"] as? [[String: Any]])
        #expect(Set(tools.compactMap { $0["name"] as? String }) == [
            "zotero_status", "zotero_search", "zotero_item",
            "zotero_selected_target", "zotero_import_bibtex", "zotero_import_ris",
        ])
        #expect(await client.recordedRequests().isEmpty)
    }

    @Test("Status distinguishes a disabled local API from an available Connector")
    func statusNamesExactBoundary() async throws {
        let client = MockZoteroMCPHTTPClient()
        await client.enqueue(
            method: "GET",
            path: "/api/users/0/items",
            response: .init(statusCode: 403)
        )
        await client.enqueue(
            method: "GET",
            path: "/connector/ping",
            response: .init(statusCode: 200)
        )
        let server = ZoteroMCPServer(client: client)

        let response = try await toolCall(server, id: 1, name: "zotero_status")
        let payload = try structuredContent(response)
        #expect(payload["local_api"] as? String == "disabled")
        #expect(payload["connector"] as? String == "available")
        #expect(payload["direct_database_access"] as? Bool == false)
        #expect(try toolIsError(response) == false)

        let requests = await client.recordedRequests()
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.url?.host == "127.0.0.1" && $0.url?.port == 23119 })
        #expect(requests.allSatisfy { !($0.url?.path.lowercased().contains("sqlite") ?? true) })
    }

    @Test("Search uses only bounded local API routes and retains library identity")
    func searchUsesLocalAPIAcrossLibraries() async throws {
        let client = MockZoteroMCPHTTPClient()
        await client.enqueueJSON(
            method: "GET",
            path: "/api/users/0/groups",
            json: #"[{"id":42,"data":{"id":42,"name":"Test Group","version":7},"links":{},"meta":{},"version":7}]"#
        )
        await client.enqueueJSON(
            method: "GET",
            path: "/api/users/0/items",
            json: #"[{"key":"USER0001","data":{"key":"USER0001","itemType":"book","title":"Alpha","creators":[{"creatorType":"author","firstName":"A","lastName":"Author"}]}}]"#
        )
        await client.enqueueJSON(
            method: "GET",
            path: "/api/groups/42/items",
            json: #"[{"key":"GROUP001","data":{"key":"GROUP001","itemType":"journalArticle","title":"Beta","creators":[{"creatorType":"author","name":"B Author"}]}}]"#
        )
        let server = ZoteroMCPServer(client: client)

        let response = try await toolCall(
            server,
            id: 1,
            name: "zotero_search",
            arguments: ["query": "sample", "limit": 10]
        )
        let payload = try structuredContent(response)
        #expect(payload["count"] as? Int == 2)
        let results = try #require(payload["results"] as? [[String: Any]])
        #expect(results.map { $0["item_key"] as? String } == ["USER0001", "GROUP001"])
        let groupLibrary = try object(results[1]["library"])
        #expect(groupLibrary["type"] as? String == "group")
        #expect(groupLibrary["id"] as? Int == 42)

        let requests = await client.recordedRequests()
        #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
        #expect(requests.filter { $0.url?.path.hasSuffix("/items") == true }.allSatisfy {
            URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.contains(URLQueryItem(name: "limit", value: "10")) == true
        })
    }

    @Test("Attachment pointers require the explicit inspection flag")
    func attachmentPointersAreExplicitAndBounded() async throws {
        let client = MockZoteroMCPHTTPClient()
        await client.enqueueJSON(method: "GET", path: "/api/users/0/groups", json: "[]")
        await client.enqueueJSON(
            method: "GET",
            path: "/api/users/0/items/ITEM0001",
            json: #"{"key":"ITEM0001","data":{"key":"ITEM0001","itemType":"book","title":"Item","creators":[]}}"#
        )
        await client.enqueueJSON(
            method: "GET",
            path: "/api/users/0/items/ITEM0001/children",
            json: #"[{"key":"ATTACH01","data":{"key":"ATTACH01","itemType":"attachment","title":"Local PDF","contentType":"application/pdf","linkMode":"linked_file","path":"/tmp/test-source.pdf","parentItem":"ITEM0001"}},{"key":"NOTE0001","data":{"key":"NOTE0001","itemType":"note","note":"private text"}}]"#
        )
        let server = ZoteroMCPServer(client: client)

        let response = try await toolCall(
            server,
            id: 1,
            name: "zotero_item",
            arguments: ["item_key": "item0001", "include_attachments": true]
        )
        let payload = try structuredContent(response)
        let attachments = try #require(payload["attachments"] as? [[String: Any]])
        #expect(attachments.count == 1)
        #expect(attachments[0]["item_key"] as? String == "ATTACH01")
        #expect(attachments[0]["path"] as? String == "/tmp/test-source.pdf")
        #expect(!String(describing: payload).contains("private text"))
    }

    @Test("A dry-run token is bound to the selected destination")
    func targetChangeBlocksImport() async throws {
        let client = MockZoteroMCPHTTPClient()
        await client.enqueueJSON(
            method: "POST",
            path: "/connector/getSelectedCollection",
            json: Self.targetJSON(libraryName: "My Library", selectedName: "My Library")
        )
        await client.enqueueJSON(method: "GET", path: "/api/users/0/groups", json: "[]")
        let server = ZoteroMCPServer(client: client)
        let source = "@book{sample,\n title={Sample}\n}"

        let preview = try await toolCall(
            server,
            id: 1,
            name: "zotero_import_bibtex",
            arguments: ["bibtex": source, "dry_run": true]
        )
        let previewPayload = try structuredContent(preview)
        let token = try #require(previewPayload["authorization_token"] as? String)
        #expect(previewPayload["status"] as? String == "preview-only")

        await client.enqueueJSON(
            method: "POST",
            path: "/connector/getSelectedCollection",
            json: Self.targetJSON(libraryName: "Another Library", selectedName: "Another Library", libraryID: 2)
        )
        let importResponse = try await toolCall(
            server,
            id: 2,
            name: "zotero_import_bibtex",
            arguments: [
                "bibtex": source,
                "dry_run": false,
                "confirm": true,
                "authorization_token": token,
            ]
        )
        #expect(try toolIsError(importResponse))
        #expect(try structuredContent(importResponse)["error"] as? String ==
            "The selected Zotero destination changed after the dry run.")
        #expect(await client.recordedRequests().allSatisfy { $0.url?.path != "/connector/import" })
    }

    @Test("Dry run recognizes a same-named collection and multiple single-line BibTeX records")
    func previewResolvesCollectionAndCountsRecords() async throws {
        let client = MockZoteroMCPHTTPClient()
        await client.enqueueJSON(
            method: "POST",
            path: "/connector/getSelectedCollection",
            json: #"{"libraryID":1,"libraryName":"My Library","libraryEditable":true,"filesEditable":true,"editable":true,"id":17,"name":"My Library","targets":[],"tags":{}}"#
        )
        await client.enqueueJSON(method: "GET", path: "/api/users/0/groups", json: "[]")
        await client.enqueueJSON(
            method: "GET",
            path: "/api/users/0/collections",
            json: #"[{"key":"COLL0001","data":{"key":"COLL0001","name":"My Library"}}]"#
        )
        let server = ZoteroMCPServer(client: client)

        let preview = try await toolCall(
            server,
            id: 1,
            name: "zotero_import_bibtex",
            arguments: [
                "bibtex": "@book{one,title={One}} @article{two,title={Two}}",
                "dry_run": true,
            ]
        )
        let payload = try structuredContent(preview)
        #expect(payload["record_count"] as? Int == 2)
        let selectedTarget = try object(payload["selected_target"])
        #expect(selectedTarget["kind"] as? String == "collection")
        let destination = try object(payload["resolved_destination"])
        #expect(destination["collection_key"] as? String == "COLL0001")
    }

    @Test("Confirmed import is one-shot and succeeds only after local API read-back")
    func importRequiresReadBackAndCannotReplay() async throws {
        let client = MockZoteroMCPHTTPClient()
        for _ in 0..<2 {
            await client.enqueueJSON(
                method: "POST",
                path: "/connector/getSelectedCollection",
                json: Self.targetJSON(libraryName: "My Library", selectedName: "My Library")
            )
            await client.enqueueJSON(method: "GET", path: "/api/users/0/groups", json: "[]")
        }
        await client.enqueueJSON(
            method: "POST",
            path: "/connector/import",
            statusCode: 201,
            json: #"[{"key":"NEW00001","itemType":"book","title":"Sample"}]"#
        )
        await client.enqueueJSON(
            method: "GET",
            path: "/api/users/0/items/NEW00001",
            json: #"{"key":"NEW00001","library":{"type":"user","id":0,"name":"My Library"},"data":{"key":"NEW00001","itemType":"book","title":"Sample","creators":[{"creatorType":"author","name":"Test Author"}],"collections":[]}}"#
        )
        let server = ZoteroMCPServer(client: client)
        let source = "@book{sample,\n title={Sample},\n author={Test Author}\n}"

        let preview = try await toolCall(
            server,
            id: 1,
            name: "zotero_import_bibtex",
            arguments: ["bibtex": source, "dry_run": true]
        )
        let token = try #require(try structuredContent(preview)["authorization_token"] as? String)
        let confirmed = try await toolCall(
            server,
            id: 2,
            name: "zotero_import_bibtex",
            arguments: [
                "bibtex": source,
                "dry_run": false,
                "confirm": true,
                "authorization_token": token,
            ]
        )
        let confirmedPayload = try structuredContent(confirmed)
        #expect(try toolIsError(confirmed) == false)
        #expect(confirmedPayload["status"] as? String == "imported-and-verified")
        #expect(confirmedPayload["item_count_verified"] as? Bool == true)
        #expect(confirmedPayload["destination_verified"] as? Bool == true)

        let replay = try await toolCall(
            server,
            id: 3,
            name: "zotero_import_bibtex",
            arguments: [
                "bibtex": source,
                "dry_run": false,
                "confirm": true,
                "authorization_token": token,
            ]
        )
        #expect(try toolIsError(replay))
        #expect(await client.recordedRequests().filter { $0.url?.path == "/connector/import" }.count == 1)
    }

    @Test("The frame parser accepts line and Content-Length messages")
    func frameParserSupportsBothModes() throws {
        let lineBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.utf8)
        let headerBody = Data(#"{"jsonrpc":"2.0","id":2,"method":"ping"}"#.utf8)
        let bytes = lineBody + Data([0x0A])
            + Data("Content-Length: \(headerBody.count)\r\n\r\n".utf8)
            + headerBody
        var parser = ZoteroMCPFrameParser()
        var frames: [ZoteroMCPFrame] = []
        for byte in bytes { frames.append(contentsOf: try parser.append(byte)) }
        frames.append(contentsOf: try parser.finish())

        #expect(frames == [
            ZoteroMCPFrame(body: lineBody, mode: .line),
            ZoteroMCPFrame(body: headerBody, mode: .contentLength),
        ])
    }

    @Test("The frame parser rejects a truncated Content-Length message")
    func frameParserRejectsTruncatedBody() throws {
        var parser = ZoteroMCPFrameParser()
        for byte in Data("Content-Length: 20\r\n\r\n{}".utf8) {
            _ = try parser.append(byte)
        }
        do {
            _ = try parser.finish()
            Issue.record("Expected the incomplete Content-Length frame to fail closed.")
        } catch let error as ZoteroMCPFrameError {
            #expect(error.errorDescription?.contains("frame header") == true)
        }
    }

    private static func targetJSON(
        libraryName: String,
        selectedName: String,
        libraryID: Int = 1
    ) -> String {
        """
        {"libraryID":\(libraryID),"libraryName":"\(libraryName)","libraryEditable":true,"filesEditable":true,"editable":true,"id":null,"name":"\(selectedName)","targets":[],"tags":{}}
        """
    }

    private func toolCall(
        _ server: ZoteroMCPServer,
        id: Int,
        name: String,
        arguments: [String: Any] = [:]
    ) async throws -> [String: Any] {
        try await rpc(server, id: id, method: "tools/call", params: [
            "name": name,
            "arguments": arguments,
        ])
    }

    private func rpc(
        _ server: ZoteroMCPServer,
        id: Int,
        method: String,
        params: [String: Any]
    ) async throws -> [String: Any] {
        let request = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": id, "method": method, "params": params,
        ], options: [.sortedKeys])
        let responseData = try #require(await server.handle(requestData: request))
        return try object(JSONSerialization.jsonObject(with: responseData))
    }

    private func structuredContent(_ response: [String: Any]) throws -> [String: Any] {
        let result = try object(response["result"])
        return try object(result["structuredContent"])
    }

    private func toolIsError(_ response: [String: Any]) throws -> Bool {
        let result = try object(response["result"])
        return try #require(result["isError"] as? Bool)
    }

    private func object(_ value: Any?) throws -> [String: Any] {
        try #require(value as? [String: Any])
    }
}

private actor MockZoteroMCPHTTPClient: ZoteroMCPHTTPClient {
    private struct Route: Hashable {
        let method: String
        let path: String
    }

    private var responses: [Route: [ZoteroMCPHTTPResponse]] = [:]
    private var requests: [URLRequest] = []

    func enqueue(method: String, path: String, response: ZoteroMCPHTTPResponse) {
        responses[Route(method: method, path: path), default: []].append(response)
    }

    func enqueueJSON(
        method: String,
        path: String,
        statusCode: Int = 200,
        json: String
    ) {
        enqueue(
            method: method,
            path: path,
            response: ZoteroMCPHTTPResponse(
                statusCode: statusCode,
                headers: ["Content-Type": "application/json"],
                body: Data(json.utf8)
            )
        )
    }

    func send(_ request: URLRequest) async throws -> ZoteroMCPHTTPResponse {
        requests.append(request)
        let route = Route(method: request.httpMethod ?? "GET", path: request.url?.path ?? "")
        guard var queued = responses[route], !queued.isEmpty else {
            throw MockZoteroMCPError.unexpectedRequest
        }
        let response = queued.removeFirst()
        responses[route] = queued
        return response
    }

    func recordedRequests() -> [URLRequest] { requests }
}

private enum MockZoteroMCPError: Error {
    case unexpectedRequest
}
