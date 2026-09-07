import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Read-only Zotero metadata matching")
struct ZoteroMetadataTests {
    @Test("Zotero JSON decoding preserves compact and expanded bibliographic metadata")
    func metadataDecoding() throws {
        let json = #"""
        {
          "key": "META0001",
          "data": {
            "key": "META0001",
            "itemType": "journalArticle",
            "title": "Fittingness",
            "creators": [
              {"creatorType":"author","firstName":"Richard","lastName":"Chappell"},
              {"creatorType":"editor","firstName":"Ignored","lastName":"Editor"}
            ],
            "date": "2012",
            "language": "en",
            "publicationTitle": "The Philosophical Quarterly",
            "volume": "62",
            "issue": "249",
            "pages": "684-704",
            "series": "Values and Reasons",
            "DOI": "10.1111/example",
            "ISBN": "978-1-2345-6789-0",
            "ISSN": "0031-8094",
            "citationKey": "ChappellFittingness2012",
            "abstractNote": "A source abstract.",
            "publisher": "Example Press",
            "place": "Oxford",
            "edition": "2",
            "url": "https://example.test/item",
            "tags": [{"tag":"fittingness"},{"tag":"value"}],
            "collections": ["COLL0001"],
            "dateModified": "2026-07-12T10:30:00Z"
          }
        }
        """#
        let result = try #require(ZoteroMetadataDecoder.decodeItems(from: Data(json.utf8)).first)
        #expect(result.key == "META0001")
        #expect(result.itemType == "journalArticle")
        #expect(result.title == "Fittingness")
        #expect(result.creators == [
            ZoteroCreatorMetadata(
                role: "author",
                name: "Richard Chappell",
                givenName: "Richard",
                familyName: "Chappell"
            ),
            ZoteroCreatorMetadata(
                role: "editor",
                name: "Ignored Editor",
                givenName: "Ignored",
                familyName: "Editor"
            ),
        ])
        #expect(result.authors == ["Richard Chappell"])
        #expect(result.date == "2012")
        #expect(result.year == 2012)
        #expect(result.language == "en")
        #expect(result.containerTitle == "The Philosophical Quarterly")
        #expect(result.volume == "62")
        #expect(result.issue == "249")
        #expect(result.pages == "684-704")
        #expect(result.series == "Values and Reasons")
        #expect(result.doi == "10.1111/example")
        #expect(result.isbn == "978-1-2345-6789-0")
        #expect(result.issn == "0031-8094")
        #expect(result.citationKey == "ChappellFittingness2012")
        #expect(result.abstract == "A source abstract.")
        #expect(result.publisher == "Example Press")
        #expect(result.place == "Oxford")
        #expect(result.edition == "2")
        #expect(result.url == "https://example.test/item")
        #expect(result.tags == ["fittingness", "value"])
        #expect(result.collectionKeys == ["COLL0001"])
        #expect(result.dateModified != nil)
    }

    @Test("Citation key in Extra remains readable")
    func compatibilityMetadataDecoding() throws {
        let itemJSON = #"""
        {"data":{"key":"EXTRA001","itemType":"book","title":"Book","extra":"Citation Key: LegacyKey"}}
        """#
        #expect(try ZoteroMetadataDecoder.decodeItems(from: Data(itemJSON.utf8)).first?.citationKey == "LegacyKey")
    }

    @Test("The transport policy permits only bodyless loopback GET reads")
    func readOnlyRequestPolicy() throws {
        let request = try #require(ZoteroLocalRequestPolicy.makeReadRequest(
            path: "items",
            query: [
                URLQueryItem(name: "q", value: "10.1000/example"),
                URLQueryItem(name: "qmode", value: "everything"),
                URLQueryItem(name: "limit", value: "50"),
            ]
        ))
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(request.url?.scheme == "http")
        #expect(request.url?.host == "127.0.0.1")
        #expect(request.url?.port == 23119)
        #expect(request.url?.path == "/api/users/0/items")
        #expect(request.value(forHTTPHeaderField: "Zotero-API-Version") == "3")

        let itemRequest = try #require(
            ZoteroLocalRequestPolicy.makeReadRequest(path: "items/FXS00026")
        )
        #expect(itemRequest.url?.path == "/api/users/0/items/FXS00026")
        let groupRequest = try #require(ZoteroLocalRequestPolicy.makeReadRequest(
            library: .group(42),
            path: "items/FXS00026"
        ))
        #expect(groupRequest.url?.path == "/api/groups/42/items/FXS00026")
        let groupsRequest = try #require(ZoteroLocalRequestPolicy.makeReadRequest(
            path: "groups"
        ))
        #expect(groupsRequest.url?.path == "/api/users/0/groups")
        #expect(ZoteroLocalRequestPolicy.makeReadRequest(
            library: .group(42),
            path: "groups"
        ) == nil)
        #expect(ZoteroLocalRequestPolicy.makeReadRequest(
            library: .group(0),
            path: "items/FXS00026"
        ) == nil)
        #expect(ZoteroLocalRequestPolicy.makeReadRequest(path: "collections/COLL0001") == nil)
        #expect(ZoteroLocalRequestPolicy.makeReadRequest(path: "items/ATTACH02/file/view/url") == nil)
        #expect(ZoteroLocalRequestPolicy.makeReadRequest(path: "items/FXS00026/children") == nil)
        #expect(ZoteroLocalRequestPolicy.makeReadRequest(path: "attachments/FXS00026") == nil)
        #expect(ZoteroLocalRequestPolicy.makeReadRequest(
            path: "items/../file/view/url"
        ) == nil)
        #expect(ZoteroLocalRequestPolicy.makeReadRequest(path: "../items") == nil)
        #expect(ZoteroLocalRequestPolicy.makeReadRequest(
            path: "items",
            query: [URLQueryItem(name: "include", value: "bib")]
        ) == nil)
    }

    @Test("The external Zotero MCP descriptor remains separate from the built-in read-only UI")
    func externalMCPDescriptorIsExplicit() throws {
        let descriptor = ZoteroMCPTransportDescriptor.supportedLocal
        #expect(descriptor.clientConfiguration.command == "scholium")
        #expect(descriptor.clientConfiguration.arguments == ["zotero", "mcp", "serve"])
        #expect(descriptor.capabilities.contains(.status))
        #expect(descriptor.capabilities.contains(.selectedTarget))
        #expect(descriptor.supportsGuardedImports)
        #expect(descriptor.localReadOnlyByDefault)
        #expect(!descriptor.importsRequireWebAPICredentials)
        #expect(descriptor.importsUseLocalConnector)
        #expect(descriptor.importsRequireDryRunAndConfirmation)
        #expect(descriptor.importsRequireReadBackVerification)
        #expect(descriptor.sourceURL.contains("Scholium"))
    }

    @Test("Transport location reports installation without claiming a handshake")
    func transportLocationDoesNotClaimConnection() throws {
        let report = ZoteroMCPTransportLocator.report(
            descriptor: .supportedLocal,
            environment: ["PATH": "/definitely/not-a-real-zotero-bin"]
        )
        #expect(report.state == .notConfigured)
        #expect(!report.liveHandshakePerformed)
        #expect(report.commandPath == nil)
    }

    @Test("An explicit probe completes the stdio initialize lifecycle without reading Zotero")
    func explicitMCPProbeCompletesInitialize() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let command = root.appendingPathComponent("mock-zotero")
        try Self.writeExecutable(
            """
            #!/bin/zsh
            IFS= read -r request || exit 1
            for i in {1..10000}; do print -n 'diagnostic ' >&2; done
            print >&2
            print -r -- '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","capabilities":{"tools":{},"resources":{}},"serverInfo":{"name":"mock-zotero","version":"1.0"}}}'
            IFS= read -r notification || true
            """,
            to: command
        )

        let report = await ZoteroMCPTransportLocator.probe(
            descriptor: Self.testDescriptor(command: "mock-zotero"),
            environment: ["PATH": root.path],
            timeout: 5
        )

        #expect(report.state == .handshakeSucceeded)
        #expect(report.liveHandshakePerformed)
        #expect(report.serverProtocolVersion == "2025-11-25")
        #expect(report.serverName == "mock-zotero")
        #expect(report.serverVersion == "1.0")
        #expect(report.capabilities == ["resources", "tools"])
        #expect(report.note.contains("No Zotero data was read or written"))
    }

    @Test("A failed explicit probe is visible and does not claim a connection")
    func failedMCPProbeIsExplicit() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let command = root.appendingPathComponent("mock-zotero-failure")
        try Self.writeExecutable(
            """
            #!/bin/zsh
            IFS= read -r request || exit 1
            print -r -- '{"jsonrpc":"2.0","id":1,"error":{"code":-1,"message":"not ready"}}'
            """,
            to: command
        )

        let report = await ZoteroMCPTransportLocator.probe(
            descriptor: Self.testDescriptor(command: "mock-zotero-failure"),
            environment: ["PATH": root.path],
            timeout: 2
        )

        #expect(report.state == .handshakeFailed)
        #expect(report.liveHandshakePerformed)
        #expect(report.serverName == nil)
        #expect(report.note.contains("initialize"))
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScholiumZoteroMCP-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func testDescriptor(command: String) -> ZoteroMCPTransportDescriptor {
        ZoteroMCPTransportDescriptor(
            identifier: "test-zotero-mcp",
            displayName: "Test Zotero MCP",
            command: command,
            installationCommand: "test",
            setupCommand: "test",
            clientConfiguration: ZoteroMCPClientConfiguration(command: command),
            capabilities: [.status],
            localReadOnlyByDefault: true,
            importsRequireWebAPICredentials: true,
            importsRequireDryRunAndConfirmation: true,
            sourceURL: "https://example.invalid/zotero-mcp"
        )
    }

    private static func writeExecutable(_ source: String, to url: URL) throws {
        try Data(source.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.path
        )
    }
}
