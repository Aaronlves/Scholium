import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("First-party Zotero MCP transport")
struct ZoteroMCPServerTests {
    @Test("Read-only mode publishes only read tools and refuses forged imports before contacting Zotero")
    func readOnlyAdmission() async throws {
        let client = MockZoteroMCPHTTPClient()
        let server = ZoteroMCPServer(client: client)
        let list = try await rpc(server, id: 1, method: "tools/list", params: [:], access: .readOnly)
        let tools = try #require(object(list["result"])["tools"] as? [[String: Any]])
        #expect(Set(tools.compactMap { $0["name"] as? String }) == ["zotero_status", "zotero_search", "zotero_item", "zotero_selected_target", "zotero_list_annotations", "zotero_read_annotation", "zotero_read_original"])
        for name in ["zotero_import_bibtex", "zotero_import_ris"] {
            let response = try await rpc(server, id: 2, method: "tools/call", params: ["name": name,
                "arguments": ["dry_run": false, "confirm": true, "authorization_token": "forged"]], access: .readOnly)
            #expect(try toolIsError(response))
        }
        #expect(await client.recordedRequests().isEmpty)
        await client.enqueue(method: "GET", path: "/api/users/0/items", response: .init(statusCode: 200, body: Data("[]".utf8)))
        await client.enqueue(method: "GET", path: "/connector/ping", response: .init(statusCode: 200))
        let status = try structuredContent(await rpc(server, id: 3, method: "tools/call", params: ["name": "zotero_status", "arguments": [:]], access: .readOnly))
        #expect(status["access_mode"] as? String == "read-only" && status["guarded_imports"] as? Bool == false)
        #expect(await client.recordedRequests().count == 2)
    }

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
            "zotero_list_annotations", "zotero_read_annotation",
            "zotero_read_original",
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
        #expect(try object(attachments[0]["reference"])["url"] as? String == "zotero://open-pdf/library/items/ATTACH01")
        #expect(try object(payload["reference"])["url"] as? String == "zotero://select/library/items/ITEM0001")
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

    @Test("Collection resolution uses the stable Connector library identity")
    func previewResolvesGroupByStableLibraryID() async throws {
        let client = MockZoteroMCPHTTPClient()
        await client.enqueueJSON(
            method: "POST",
            path: "/connector/getSelectedCollection",
            json: #"{"libraryID":42,"libraryName":"Renamed Group","libraryEditable":true,"filesEditable":true,"editable":true,"id":17,"name":"Selected Collection","targets":[],"tags":{}}"#
        )
        await client.enqueueJSON(
            method: "GET",
            path: "/api/users/0/groups",
            json: #"[{"id":42,"data":{"id":42,"name":"Renamed Group","version":7},"links":{},"meta":{},"version":7}]"#
        )
        await client.enqueueJSON(
            method: "GET",
            path: "/api/groups/42/collections",
            json: #"[{"key":"GROUPCOLL1","data":{"key":"GROUPCOLL1","name":"Selected Collection"}}]"#
        )
        let server = ZoteroMCPServer(client: client)

        let preview = try await toolCall(
            server,
            id: 1,
            name: "zotero_import_bibtex",
            arguments: ["bibtex": "@book{one,title={One}}", "dry_run": true]
        )
        let destination = try object(try structuredContent(preview)["resolved_destination"])
        #expect(destination["type"] as? String == "group")
        #expect(destination["id"] as? Int == 42)
        #expect(destination["connector_target_id"] as? String == "17")
    }

    @Test("A collection target ID is part of the dry-run binding even when names stay the same")
    func collectionTargetIDChangeBlocksImport() async throws {
        let client = MockZoteroMCPHTTPClient()
        await client.enqueueJSON(
            method: "POST",
            path: "/connector/getSelectedCollection",
            json: Self.targetJSON(libraryName: "My Library", selectedName: "My Library", selectedID: 17)
        )
        await client.enqueueJSON(method: "GET", path: "/api/users/0/groups", json: "[]")
        await client.enqueueJSON(
            method: "GET",
            path: "/api/users/0/collections",
            json: #"[{"key":"COLL0001","data":{"key":"COLL0001","name":"My Library"}}]"#
        )
        let server = ZoteroMCPServer(client: client)
        let source = "@book{sample,title={Sample}}"
        let preview = try await toolCall(
            server,
            id: 1,
            name: "zotero_import_bibtex",
            arguments: ["bibtex": source, "dry_run": true]
        )
        let token = try #require(try structuredContent(preview)["authorization_token"] as? String)
        await client.enqueueJSON(
            method: "POST",
            path: "/connector/getSelectedCollection",
            json: Self.targetJSON(libraryName: "My Library", selectedName: "My Library", selectedID: 18)
        )
        let result = try await toolCall(
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
        #expect(try toolIsError(result))
        #expect(try structuredContent(result)["error"] as? String ==
            "The selected Zotero destination changed after the dry run.")
        #expect(await client.recordedRequests().allSatisfy { $0.url?.path != "/connector/import" })
    }

    @Test("Confirmed import is one-shot and succeeds only after local API read-back")
    func importRequiresReadBackAndCannotReplay() async throws {
        let client = MockZoteroMCPHTTPClient()
        for _ in 0..<4 {
            await client.enqueueJSON(
                method: "POST",
                path: "/connector/getSelectedCollection",
                json: Self.targetJSON(libraryName: "My Library", selectedName: "My Library")
            )
        }
        for _ in 0..<3 {
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

    @Test("A destination change after Connector response remains uncertain and skips read-back")
    func importDestinationChangeAfterWriteIsUncertain() async throws {
        let client = MockZoteroMCPHTTPClient()
        for _ in 0..<3 {
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
            method: "POST",
            path: "/connector/getSelectedCollection",
            json: Self.targetJSON(libraryName: "Another Library", selectedName: "Another Library", libraryID: 2)
        )
        let server = ZoteroMCPServer(client: client)
        let source = "@book{sample,title={Sample}}"
        let preview = try await toolCall(
            server,
            id: 1,
            name: "zotero_import_bibtex",
            arguments: ["bibtex": source, "dry_run": true]
        )
        let token = try #require(try structuredContent(preview)["authorization_token"] as? String)
        let result = try await toolCall(
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
        let payload = try structuredContent(result)
        #expect(try toolIsError(result))
        #expect(payload["status"] as? String == "import-outcome-uncertain")
        #expect(payload["write_may_have_completed"] as? Bool == true)
        #expect(await client.recordedRequests().filter { $0.url?.path == "/api/users/0/items/NEW00001" }.isEmpty)
    }

    @Test("A lost Connector import response is reported as uncertain and is not replayed")
    func importTransportFailureIsUncertain() async throws {
        let client = MockZoteroMCPHTTPClient()
        for _ in 0..<3 {
            await client.enqueueJSON(
                method: "POST",
                path: "/connector/getSelectedCollection",
                json: Self.targetJSON(libraryName: "My Library", selectedName: "My Library")
            )
            await client.enqueueJSON(method: "GET", path: "/api/users/0/groups", json: "[]")
        }
        let server = ZoteroMCPServer(client: client)
        let source = "@book{sample,title={Sample}}"
        let preview = try await toolCall(
            server,
            id: 1,
            name: "zotero_import_bibtex",
            arguments: ["bibtex": source, "dry_run": true]
        )
        let token = try #require(try structuredContent(preview)["authorization_token"] as? String)
        let result = try await toolCall(
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
        let payload = try structuredContent(result)
        #expect(try toolIsError(result))
        #expect(payload["status"] as? String == "import-outcome-uncertain")
        #expect(payload["write_may_have_completed"] as? Bool == true)
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
        libraryID: Int = 1,
        selectedID: Int? = nil
    ) -> String {
        let selectedIDValue = selectedID.map(String.init) ?? "null"
        return """
        {"libraryID":\(libraryID),"libraryName":"\(libraryName)","libraryEditable":true,"filesEditable":true,"editable":true,"id":\(selectedIDValue),"name":"\(selectedName)","targets":[],"tags":{}}
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
        params: [String: Any], access: ZoteroMCPAccess = .guardedImports
    ) async throws -> [String: Any] {
        let request = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": id, "method": method, "params": params,
        ], options: [.sortedKeys])
        let responseData = try #require(await server.handle(requestData: request, access: access))
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

extension ZoteroMCPServerTests {
    @Test("Annotation selection pages only pointers and reads one exact record with its provenance")
    func exactAnnotationSelection() async throws {
        let client = MockZoteroMCPHTTPClient()
        let server = ZoteroMCPServer(client: client)
        let first = try Self.annotationJSON(key: "ANNO0001", text: "  引文\r\nsource  ", comment: "My evaluation", position: "{\"pageIndex\":2}", label: "xii")
        let second = try Self.annotationJSON(key: "ANNO0002", text: "Not selected", position: "{\"pageIndex\":3}")
        let records = "[\(second),\(first)]"
        await queueAnnotationListing(client, json: records)
        let page1 = try structuredContent(await annotationCall(server, name: "zotero_list_annotations", arguments: ["limit": 1]))
        let pointers = try #require(page1["annotations"] as? [[String: Any]])
        #expect(pointers.count == 1 && pointers[0]["annotation_key"] as? String == "ANNO0001")
        #expect(pointers[0]["selected_text"] == nil && pointers[0]["comment"] == nil)
        #expect(!String(describing: page1).contains("My evaluation"))
        #expect(page1["next_offset"] as? Int == 1 && page1["total_count"] as? Int == 2)
        let listingFingerprint = try #require(page1["listing_fingerprint"] as? String)
        let recordFingerprint = try #require(pointers[0]["annotation_fingerprint"] as? String)
        await queueAnnotationListing(client, json: records)
        let page2 = try structuredContent(await annotationCall(server, name: "zotero_list_annotations", arguments: ["offset": 1, "expected_listing_fingerprint": listingFingerprint]))
        #expect((page2["annotations"] as? [[String: Any]])?.first?["annotation_key"] as? String == "ANNO0002")
        await queueAnnotationRead(client, json: first)
        let selected = try structuredContent(await annotationCall(server, name: "zotero_read_annotation", arguments: ["annotation_key": "ANNO0001", "expected_fingerprint": recordFingerprint]))
        #expect(selected["selected_text"] as? String == "  引文\r\nsource  ")
        #expect(selected["comment"] as? String == "My evaluation")
        #expect(selected["page_label"] as? String == "xii" && selected["original_file_read"] as? Bool == false)
        #expect(selected["source_kind"] as? String == "zotero_annotation")
        #expect(selected["annotation_fingerprint"] as? String == recordFingerprint)
        let locator = try object(selected["reference"])
        #expect(locator["page"] as? Int == 3)
        let locatorURL = try #require(locator["url"] as? String)
        let url = try #require(URL(string: locatorURL))
        #expect(try ZoteroReference(url: url) == ZoteroReference(library: .group(42), kind: .pdf, itemKey: "ATTACH01", page: 3, annotationKey: "ANNO0001"))
        let requests = await client.recordedRequests()
        #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.url?.host == "127.0.0.1" && $0.url?.path.hasPrefix("/api/groups/42/items/") == true })
        #expect(!requests.contains { $0.url?.path.contains("file") == true || $0.url?.path.contains("fulltext") == true })
        let listRequest = try #require(requests.first { $0.url?.path.hasSuffix("children") == true })
        let query = URLComponents(url: try #require(listRequest.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.contains(URLQueryItem(name: "limit", value: "1001")) == true)
        #expect(query?.contains(URLQueryItem(name: "itemType", value: "annotation")) == true)
    }

    @Test("Changed selections, crossed parents and changed attachment observations cannot return content")
    func annotationSelectionRefusals() async throws {
        let client = MockZoteroMCPHTTPClient()
        let server = ZoteroMCPServer(client: client)
        let original = try Self.annotationJSON(key: "ANNO0001", text: "Original")
        await queueAnnotationListing(client, json: "[\(original)]")
        let listed = try structuredContent(await annotationCall(server, name: "zotero_list_annotations"))
        let pointer = try #require((listed["annotations"] as? [[String: Any]])?.first)
        let changed = try Self.annotationJSON(key: "ANNO0001", text: "Changed")
        await queueAnnotationRead(client, json: changed, revalidate: false)
        let stale = try await annotationCall(server, name: "zotero_read_annotation", arguments: ["annotation_key": "ANNO0001", "expected_fingerprint": try #require(pointer["annotation_fingerprint"] as? String)])
        #expect(try toolIsError(stale))
        #expect(!(try structuredContent(stale)).keys.contains("selected_text"))
        await queueAnnotationListing(client, json: "[\(changed)]", revalidate: false)
        #expect(try toolIsError(await annotationCall(server, name: "zotero_list_annotations", arguments: ["offset": 1, "expected_listing_fingerprint": try #require(listed["listing_fingerprint"] as? String)])))
        let crossed = try Self.annotationJSON(key: "ANNO0001", text: "Wrong paper", parent: "OTHER001")
        await queueAnnotationRead(client, json: crossed, revalidate: false)
        #expect(try toolIsError(await annotationCall(server, name: "zotero_read_annotation", arguments: ["annotation_key": "ANNO0001"])))
        await queueAnnotationRead(client, json: original, revalidate: false)
        await client.enqueueJSON(method: "GET", path: "/api/groups/42/items/ATTACH01", json: Self.pdfJSON.replacingOccurrences(of: "\"version\":1", with: "\"version\":2"))
        #expect(try toolIsError(await annotationCall(server, name: "zotero_read_annotation", arguments: ["annotation_key": "ANNO0001"])))
        let before = await client.recordedRequests().count
        for arguments: [String: Any] in [["offset": 1], ["offset": -1], ["limit": 51], ["limit": 1e100], ["library": "group:-1"], ["attachment_key": "../escape"], ["expected_listing_fingerprint": "wrong"], ["guess": "title"]] {
            #expect(try toolIsError(await annotationCall(server, name: "zotero_list_annotations", arguments: arguments)))
        }
        #expect(await client.recordedRequests().count == before)
        await client.enqueue(method: "GET", path: "/api/groups/42/items/ATTACH01", response: .init(statusCode: 200, headers: ["Zotero-Server-ID": "instance-A"], body: Data(Self.pdfJSON.utf8)))
        await client.enqueue(method: "GET", path: "/api/groups/42/items/ANNO0001", response: .init(statusCode: 200, headers: ["Zotero-Server-ID": "instance-B"], body: Data(original.utf8)))
        #expect(try toolIsError(await annotationCall(server, name: "zotero_read_annotation", arguments: ["annotation_key": "ANNO0001"])))
        await client.enqueueJSON(method: "GET", path: "/api/groups/42/items/ATTACH01", json: Self.pdfJSON.replacingOccurrences(of: "application/pdf", with: "text/html"))
        let count = await client.recordedRequests().count
        #expect(try toolIsError(await annotationCall(server, name: "zotero_read_annotation", arguments: ["annotation_key": "ANNO0001"])))
        #expect(await client.recordedRequests().count == count + 1)
    }

    @Test("Invalid physical positions stay unlocated and annotation lists reject incomplete or oversized snapshots")
    func annotationBoundsAndPositions() async throws {
        let client = MockZoteroMCPHTTPClient()
        let server = ZoteroMCPServer(client: client)
        for position in ["invalid", "{\"pageIndex\":-1}", "{\"pageIndex\":1e100}", "{\"pageIndex\":1.5}", "{\"pageIndex\":true}"] {
            let annotation = try Self.annotationJSON(key: "ANNO0001", text: "Selected", position: position, label: "42")
            await queueAnnotationRead(client, json: annotation)
            let result = try structuredContent(await annotationCall(server, name: "zotero_read_annotation", arguments: ["annotation_key": "ANNO0001"]))
            #expect(result["page_label"] as? String == "42")
            #expect((try object(result["reference"])["page"]) is NSNull)
            #expect((try object(result["reference"])["url"]) as? String == "zotero://open-pdf/groups/42/items/ATTACH01?annotation=ANNO0001")
        }
        let one = try Self.annotationJSON(key: "ANNO0001", text: "text")
        await queueAnnotationListing(client, json: "[" + Array(repeating: one, count: 1_001).joined(separator: ",") + "]", revalidate: false)
        #expect(try toolIsError(await annotationCall(server, name: "zotero_list_annotations")))
        await client.enqueueJSON(method: "GET", path: "/api/groups/42/items/ATTACH01", json: Self.pdfJSON)
        await client.enqueue(method: "GET", path: "/api/groups/42/items/ATTACH01/children", response: .init(statusCode: 200, headers: ["Total-Results": "2"], body: Data("[\(one)]".utf8)))
        #expect(try toolIsError(await annotationCall(server, name: "zotero_list_annotations")))
        await client.enqueueJSON(method: "GET", path: "/api/groups/42/items/ATTACH01", json: Self.pdfJSON)
        await client.enqueue(method: "GET", path: "/api/groups/42/items/ATTACH01/children", response: .init(statusCode: 200, body: Data(repeating: 32, count: 4 * 1_024 * 1_024 + 1)))
        #expect(try toolIsError(await annotationCall(server, name: "zotero_list_annotations")))
    }

    private static let pdfJSON = #"{"key":"ATTACH01","version":1,"data":{"key":"ATTACH01","itemType":"attachment","parentItem":"PARENT01","contentType":"application/pdf","linkMode":"imported_file"}}"#

    private static func annotationJSON(key: String, text: String, comment: String = "", parent: String = "ATTACH01",
                                       position: String = "{}", label: String = "") throws -> String {
        let record: [String: Any] = ["key": key, "version": 1, "data": ["key": key, "itemType": "annotation", "parentItem": parent,
            "annotationType": "highlight", "annotationText": text, "annotationComment": comment, "annotationPosition": position, "annotationPageLabel": label]]
        return String(decoding: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), as: UTF8.self)
    }

    private func queueAnnotationListing(_ client: MockZoteroMCPHTTPClient, json: String, revalidate: Bool = true) async {
        await client.enqueueJSON(method: "GET", path: "/api/groups/42/items/ATTACH01", json: Self.pdfJSON)
        await client.enqueueJSON(method: "GET", path: "/api/groups/42/items/ATTACH01/children", json: json)
        if revalidate { await client.enqueueJSON(method: "GET", path: "/api/groups/42/items/ATTACH01", json: Self.pdfJSON) }
    }

    private func queueAnnotationRead(_ client: MockZoteroMCPHTTPClient, json: String, revalidate: Bool = true) async {
        await client.enqueueJSON(method: "GET", path: "/api/groups/42/items/ATTACH01", json: Self.pdfJSON)
        await client.enqueueJSON(method: "GET", path: "/api/groups/42/items/ANNO0001", json: json)
        if revalidate { await client.enqueueJSON(method: "GET", path: "/api/groups/42/items/ATTACH01", json: Self.pdfJSON) }
    }

    private func annotationCall(_ server: ZoteroMCPServer, name: String, arguments: [String: Any] = [:]) async throws -> [String: Any] {
        let base: [String: Any] = ["library": "group:42", "attachment_key": "ATTACH01"]
        return try await rpc(server, id: 1, method: "tools/call", params: ["name": name,
            "arguments": base.merging(arguments, uniquingKeysWith: { _, new in new })], access: .readOnly)
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
