import ScholiumContracts
import Foundation
import Testing
@testable import ScholiumApplication

@Suite("Runtime-owned Zotero operations")
struct ZoteroOperationsTests {
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
            #"{"jsonrpc":"2.0","id":7,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#.utf8
        )
        let response = try #require(await operations.handle(requestData: request))
        let object = try #require(
            JSONSerialization.jsonObject(with: response) as? [String: Any]
        )
        #expect(object["jsonrpc"] as? String == "2.0")
        #expect(object["id"] as? Int == 7)
        let result = try #require(object["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2024-11-05")
        let server = try #require(result["serverInfo"] as? [String: Any])
        #expect(server["name"] as? String == "scholium-zotero")
        #expect(server["version"] as? String == "0.1.0")

        let notification = Data(
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8
        )
        #expect(await operations.handle(requestData: notification) == nil)
        await runtime.shutdown()
    }

    @Test("An exact Zotero attachment resolves only its parent identity and local file URL")
    func exactAttachmentResolution() async throws {
        let sourceURL = URL(fileURLWithPath: "/private/source/Article.pdf")
        let envelope = """
        {
          "key": "ATTACH02",
          "data": {
            "key": "ATTACH02",
            "itemType": "attachment",
            "parentItem": "PARENT01",
            "title": "Article",
            "filename": "Article.pdf"
          }
        }
        """
        let script = AttachmentRequestScript(responses: [
            (200, Data(envelope.utf8)),
            (200, Data(sourceURL.absoluteString.utf8)),
        ])
        let operations = ZoteroOperations(requestLoader: { request in
            try await script.load(request)
        })
        let resolved = try await operations.resolveAttachment(
            itemKey: "parent01",
            attachmentKey: "attach02"
        )
        #expect(resolved.itemKey == "PARENT01")
        #expect(resolved.attachmentKey == "ATTACH02")
        #expect(resolved.displayName == "Article.pdf")
        #expect(resolved.fileURL == sourceURL)
        #expect(await script.paths() == [
            "/api/users/0/items/ATTACH02",
            "/api/users/0/items/ATTACH02/file/view/url",
        ])
    }

    @Test("The same item key resolves through the exact portable user or group library")
    func exactBindingLibraryRoute() async throws {
        let item = Data("""
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
        let script = AttachmentRequestScript(responses: [(200, item), (200, item)])
        let operations = ZoteroOperations(requestLoader: { request in
            try await script.load(request)
        })
        _ = try await operations.resolve(binding: AnalysisZoteroBinding(
            noteID: UUID(),
            library: .user,
            itemKey: "SHARED01"
        ))
        _ = try await operations.resolve(binding: AnalysisZoteroBinding(
            noteID: UUID(),
            library: .group(42),
            itemKey: "SHARED01"
        ))
        #expect(await script.paths() == [
            "/api/users/0/items/SHARED01",
            "/api/groups/42/items/SHARED01",
        ])
    }

    @Test("A Zotero attachment from another parent fails before file lookup")
    func attachmentParentMismatch() async throws {
        let envelope = """
        {
          "key": "ATTACH02",
          "data": {
            "key": "ATTACH02",
            "itemType": "attachment",
            "parentItem": "OTHER001",
            "title": "Article",
            "filename": "Article.pdf"
          }
        }
        """
        let script = AttachmentRequestScript(responses: [
            (200, Data(envelope.utf8)),
        ])
        let operations = ZoteroOperations(requestLoader: { request in
            try await script.load(request)
        })
        await #expect(throws: ZoteroUseCaseError.self) {
            _ = try await operations.resolveAttachment(
                itemKey: "PARENT01",
                attachmentKey: "ATTACH02"
            )
        }
        #expect(await script.paths().count == 1)
    }

    @Test("A relative file URL cannot become a process-relative attachment path")
    func relativeAttachmentURLFailsClosed() async throws {
        let envelope = """
        {
          "key": "ATTACH02",
          "data": {
            "key": "ATTACH02",
            "itemType": "attachment",
            "parentItem": "PARENT01",
            "title": "Article",
            "filename": "Article.pdf"
          }
        }
        """
        let script = AttachmentRequestScript(responses: [
            (200, Data(envelope.utf8)),
            (200, Data("file:relative.pdf".utf8)),
        ])
        let operations = ZoteroOperations(requestLoader: { request in
            try await script.load(request)
        })

        do {
            _ = try await operations.resolveAttachment(
                itemKey: "PARENT01",
                attachmentKey: "ATTACH02"
            )
            Issue.record("A relative attachment URL must fail closed.")
        } catch let error as ZoteroUseCaseError {
            guard case .invalidAttachmentURL = error else {
                Issue.record("Unexpected Zotero error: \(error)")
                return
            }
        }
        #expect(await script.paths().count == 2)
    }

    @Test("A response from any URL other than the exact loopback request is rejected")
    func redirectedResponseFailsClosed() async throws {
        let remoteURL = try #require(URL(string: "https://example.invalid/items"))
        let operations = ZoteroOperations(requestLoader: { _ in
            let response = try #require(HTTPURLResponse(
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

    @Test("The default Zotero transport declines redirects before following them")
    func redirectDelegateDeclinesRedirect() async throws {
        let original = try #require(URL(string: "http://127.0.0.1:23119/api/users/0/items"))
        let remote = try #require(URL(string: "https://example.invalid/items"))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: original)
        let response = try #require(HTTPURLResponse(
            url: original,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": remote.absoluteString]
        ))
        let decision: URLRequest? = await withCheckedContinuation { continuation in
            ZoteroNoRedirectDelegate().urlSession(
                session,
                task: task,
                willPerformHTTPRedirection: response,
                newRequest: URLRequest(url: remote),
                completionHandler: { continuation.resume(returning: $0) }
            )
        }
        #expect(decision == nil)
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
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: next.0,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        ) else {
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
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Scholium-ZoteroOperations-\(UUID().uuidString)",
            isDirectory: true
        )
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        let registry = root.appendingPathComponent("Registry", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return Self(rootURL: root, supportURL: support, registryURL: registry)
    }

    func runtime() -> WorkspaceRuntime {
        WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: supportURL,
            workspaceRegistryStorageURL: registryURL,
            assignments: []
        )))
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
