import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Runtime-owned Zotero operations")
struct ZoteroOperationsTests {
    @Test("Snapshot runtime owns one native Zotero connection")
    func runtimeOwnership() async throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let first = runtime.zotero
        let second = runtime.zotero

        #expect(first === second)
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
