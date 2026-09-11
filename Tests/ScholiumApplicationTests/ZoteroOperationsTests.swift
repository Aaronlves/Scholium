import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

private actor MaterialFixtureClient {
    private(set) var requests: [URLRequest] = []
    private let originalURL: URL?
    init(originalURL: URL? = nil) { self.originalURL = originalURL }
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil) else {
            throw URLError(.badURL)
        }
        requests.append(request)
        let json: String
        switch request.url?.path {
        case "/api/users/0/items/ATTACH01":
            if let originalURL {
                return (
                    try JSONSerialization.data(withJSONObject: [
                        "key": "ATTACH01",
                        "data": [
                            "key": "ATTACH01",
                            "itemType": "attachment", "contentType": "text/plain", "linkMode": "imported_file", "filename": originalURL.lastPathComponent,
                        ],
                    ]), response
                )
            }
            json = #"{"key":"ATTACH01","data":{"key":"ATTACH01","itemType":"attachment","contentType":"application/pdf","linkMode":"imported_file"}}"#
        case "/api/users/0/items/ATTACH01/file/view/url":
            guard let originalURL else { throw URLError(.badURL) }
            return (Data(originalURL.absoluteString.utf8), response)
        case "/api/users/0/items/ANNO0001":
            json =
                #"{"key":"ANNO0001","data":{"key":"ANNO0001","itemType":"annotation","parentItem":"ATTACH01","annotationText":"Exact selected text","annotationComment":"Separate comment","annotationPosition":"{\"pageIndex\":1}"}}"#
        default:
            throw URLError(.badURL)
        }
        return (Data(json.utf8), response)
    }
}

@Suite("Runtime-owned Zotero operations")
struct ZoteroOperationsTests {
    @Test("Original selection uses the same runtime capability and returns exact bounded material")
    func originalReadThroughApplication() async throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let file = fixture.rootURL.appendingPathComponent("Selected.txt")
        let bytes = Data("Exact original\r\nExcluded tail".utf8)
        try bytes.write(to: file)
        let client = MaterialFixtureClient(originalURL: file)
        let operations = ZoteroOperations(requestLoader: { try await client.send($0) })
        let request = Data(
            #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"zotero_read_original","arguments":{"library":"user","attachment_key":"ATTACH01","mode":"text","maximum_utf8":14}}}"#
                .utf8)
        let data = try #require(await operations.handle(requestData: request, access: .readOnly))
        let rpc = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try #require(rpc["result"] as? [String: Any])
        let content = try #require(result["structuredContent"] as? [String: Any])
        try #require(result["isError"] as? Bool == false, "\(content)")
        #expect(content["text"] as? String == "Exact original")
        #expect(content["original_fingerprint"] as? String == DocumentFingerprint(data: bytes).sha256)
        #expect(content["next_start_utf8"] as? Int == 14)
        #expect(await client.requests.count == 4)
        #expect(try Data(contentsOf: file) == bytes)
        let observed = try reportedRead(response: data, request: request)
        #expect(observed.representation == .text && observed.range?.end == 14)
        #expect(observed.excerpt == "Exact original" && observed.fingerprint == DocumentFingerprint(data: bytes).sha256)
    }

    @Test("Selected annotation content passes through the runtime-owned read-only service")
    func annotationReadThroughApplication() async throws {
        let client = MaterialFixtureClient()
        let operations = ZoteroOperations(requestLoader: { try await client.send($0) })
        let request = Data(
            #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"zotero_read_annotation","arguments":{"library":"user","attachment_key":"ATTACH01","annotation_key":"ANNO0001"}}}"#
                .utf8)
        let data = try #require(await operations.handle(requestData: request, access: .readOnly))
        let rpc = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try #require(rpc["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == false)
        let content = try #require(result["structuredContent"] as? [String: Any])
        #expect(content["selected_text"] as? String == "Exact selected text")
        #expect(content["comment"] as? String == "Separate comment")
        #expect(content["original_file_read"] as? Bool == false)
        let reference = try #require(content["reference"] as? [String: Any])
        #expect(reference["url"] as? String == "zotero://open-pdf/library/items/ATTACH01?page=2&annotation=ANNO0001")
        let requests = await client.requests
        #expect(requests.map { $0.url?.path } == ["/api/users/0/items/ATTACH01", "/api/users/0/items/ANNO0001", "/api/users/0/items/ATTACH01"])
        #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
        let observed = try reportedRead(response: data, request: request)
        #expect(observed.representation == .annotation && observed.reference.page == 2)
        #expect(observed.excerpt == "Exact selected text" && observed.comment == "Separate comment")
    }

    private func reportedRead(response: Data, request: Data) throws -> ZoteroReadReport {
        let rpc = try JSONDecoder().decode(MCPJSONValue.self, from: response)
        let call = try JSONDecoder().decode(MCPJSONValue.self, from: request)
        let params = try #require(call.objectValue?["params"]?.objectValue)
        var result = try #require(rpc.objectValue?["result"]?.objectValue)
        // Codex 0.153.4 retains content/structuredContent; it has no result.isError field.
        result["isError"] = nil
        let item: [String: MCPJSONValue] = [
            "id": .string("call"), "type": .string("mcpToolCall"), "server": .string("scholium-zotero"),
            "tool": try #require(params["name"]), "arguments": try #require(params["arguments"]), "status": .string("completed"), "result": .object(result),
        ]
        let activity = try #require(CodexChatActivity.parse(item, completed: true))
        guard case .zoteroReadReport(let report) = activity.sourceObservation else {
            Issue.record("Missing public tool report")
            throw URLError(.cannotParseResponse)
        }
        #expect(activity.source == .runtime && report.isValid)
        return report
    }

    @Test("Snapshot runtime owns one delivery-neutral Zotero capability")
    func runtimeOwnershipAndTransportReports() async throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let first = runtime.zotero
        let second = runtime.zotero

        #expect(first === second)
        #expect(first.descriptor == .supportedLocal)

        let environment = ["PATH": ""]
        let report = first.report(environment: environment)
        #expect(report.descriptorID == first.descriptor.identifier)
        #expect(report.state == .notConfigured)
        #expect(!report.liveHandshakePerformed)
        #expect(report.commandPath == nil)

        let probed = await first.probe(environment: environment, timeout: 0.01)
        #expect(probed == report)
        await runtime.shutdown()
    }

    @Test("Application request handling preserves the MCP delivery contract")
    func requestHandling() async throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let operations = runtime.zotero
        let request = Data(
            #"{"jsonrpc":"2.0","id":7,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#
                .utf8
        )
        let response = try #require(await operations.handle(requestData: request, access: .guardedImports))
        let object = try #require(
            JSONSerialization.jsonObject(with: response) as? [String: Any]
        )
        #expect(object["jsonrpc"] as? String == "2.0")
        #expect(object["id"] as? Int == 7)
        let result = try #require(object["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2024-11-05")
        let server = try #require(result["serverInfo"] as? [String: Any])
        #expect(server["name"] as? String == "scholium-zotero")
        #expect(
            server["version"] as? String
                == ScholiumProductIdentity.marketingVersion
        )

        let notification = Data(
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8
        )
        #expect(await operations.handle(requestData: notification, access: .guardedImports) == nil)
        await runtime.shutdown()
    }

    @Test("Binding search keeps exact user and group library identities")
    func bindingSearchAcrossLibraries() async throws {
        let groups = Data(
            """
            [{"id":42,"name":"Shared Ethics"}]
            """.utf8)
        let userItems = Data(
            """
            [{
              "key": "USER0001",
              "data": {
                "key": "USER0001",
                "itemType": "journalArticle",
                "title": "Agency in Practice",
                "creators": []
              }
            }]
            """.utf8)
        let groupItems = Data(
            """
            [{
              "key": "GROUP001",
              "data": {
                "key": "GROUP001",
                "itemType": "book",
                "title": "Reasons and Agency",
                "creators": []
              }
            }]
            """.utf8)
        let script = AttachmentRequestScript(responses: [
            (200, groups),
            (200, userItems),
            (200, groupItems),
        ])
        let operations = ZoteroOperations(requestLoader: { request in
            try await script.load(request)
        })

        let hits = try await operations.searchLibrary(query: "agency")

        #expect(hits.map(\.library.identity) == [.user, .group(42)])
        #expect(hits.map(\.item.key) == ["USER0001", "GROUP001"])
        #expect(
            await script.paths() == [
                "/api/users/0/groups",
                "/api/users/0/items",
                "/api/groups/42/items",
            ])
    }

    @Test("An exact item key present in user and group libraries requires library selection")
    func exactKeyAcrossLibraries() async throws {
        let groups = Data(
            """
            [{"id":42,"name":"Shared Ethics"}]
            """.utf8)
        let item = Data(
            """
            {
              "key": "SHARED01",
              "data": {
                "key": "SHARED01",
                "itemType": "journalArticle",
                "title": "Library-specific item",
                "creators": []
              }
            }
            """.utf8)
        let script = AttachmentRequestScript(responses: [
            (200, groups),
            (200, item),
            (200, item),
        ])
        let operations = ZoteroOperations(requestLoader: { request in
            try await script.load(request)
        })

        let hits = try await operations.searchLibrary(query: "shared01")

        #expect(hits.map(\.item.key) == ["SHARED01", "SHARED01"])
        #expect(Set(hits.map(\.library.identity)) == [.user, .group(42)])
        #expect(
            await script.paths() == [
                "/api/users/0/groups",
                "/api/users/0/items/SHARED01",
                "/api/groups/42/items/SHARED01",
            ])
    }

    @Test("A missing exact key never falls through to an item-collection search")
    func missingExactKeyDoesNotSearchCollections() async throws {
        let groups = Data(
            """
            [{"id":42,"name":"Shared Ethics"}]
            """.utf8)
        let script = AttachmentRequestScript(responses: [
            (200, groups),
            (404, Data()),
            (404, Data()),
        ])
        let operations = ZoteroOperations(requestLoader: { request in
            try await script.load(request)
        })

        let hits = try await operations.searchLibrary(query: "missing1")

        #expect(hits.isEmpty)
        #expect(
            await script.paths() == [
                "/api/users/0/groups",
                "/api/users/0/items/MISSING1",
                "/api/groups/42/items/MISSING1",
            ])
    }

    @Test("A response from any URL other than the exact loopback request is rejected")
    func redirectedResponseFailsClosed() async throws {
        let remoteURL = try #require(URL(string: "https://example.invalid/items"))
        let operations = ZoteroOperations(requestLoader: { _ in
            let response = try #require(
                HTTPURLResponse(
                    url: remoteURL,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                ))
            return (Data("[]".utf8), response)
        })

        do {
            _ = try await operations.refreshLibraryInfo()
            Issue.record("A redirected Zotero response must fail closed.")
        } catch let error as ZoteroUseCaseError {
            guard case .invalidResponse = error else {
                Issue.record("Unexpected Zotero error: \(error)")
                return
            }
        }
    }

}

private actor AttachmentRequestScript {
    private var responses: [(Int, Data)]
    private var requestedPaths: [String] = []

    init(responses: [(Int, Data)]) {
        self.responses = responses
    }

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        guard let url = request.url, !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }
        requestedPaths.append(url.path)
        let next = responses.removeFirst()
        guard
            let response = HTTPURLResponse(
                url: url,
                statusCode: next.0,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )
        else {
            throw URLError(.badServerResponse)
        }
        return (next.1, response)
    }

    func paths() -> [String] { requestedPaths }
}

private struct Fixture {
    let rootURL: URL
    let supportURL: URL
    let registryURL: URL

    static func make() throws -> Self {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/agent-knowledge-tools/zotero-application-fixtures/\(UUID().uuidString)", isDirectory: true)
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        let registry = root.appendingPathComponent("Registry", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return Self(rootURL: root, supportURL: support, registryURL: registry)
    }

    func runtime() -> WorkspaceRuntime {
        WorkspaceRuntime(
            configuration: .snapshot(
                .init(
                    applicationSupportURL: supportURL,
                    workspaceRegistryStorageURL: registryURL,
                    assignments: []
                )))
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
