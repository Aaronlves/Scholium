import Foundation
import Testing

@testable import ScholiumCore

@Suite("Zotero library directory hints")
struct ZoteroLibraryDirectoryTests {
    @Test("Exact stored attachments locate custom Unicode folders without reading original bytes", arguments: ["imported_file", "imported_url"])
    func storedDirectory(mode: String) async throws {
        let directory = URL(fileURLWithPath: "/Nonprivate custom location/文献库", isDirectory: true)
        let url = directory.appendingPathComponent("storage/ATTACH01/Source 原文.pdf")
        let item = try metadata(filename: url.lastPathComponent, mode: mode)
        let client = HintClient([
            .json(try list([item])), .text(url.absoluteString), .json(item), .text(url.absoluteString),
        ])
        let server = server(client)
        #expect(try await server.suggestedOriginalLibraryDirectory() == directory)
        let requests = await client.requests
        #expect(
            requests.map { $0.url?.path } == [
                "/api/users/0/items", "/api/users/0/items/ATTACH01/file/view/url",
                "/api/users/0/items/ATTACH01", "/api/users/0/items/ATTACH01/file/view/url",
            ])
        #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.url?.host == "127.0.0.1" })
        #expect(
            URLComponents(url: try #require(requests.first?.url), resolvingAgainstBaseURL: false)?.queryItems?.contains(.init(name: "limit", value: "100"))
                == true)
    }

    @Test("Group-only libraries and missing local files retain exact scope")
    func groupAndMissingOriginal() async throws {
        let first = try metadata(key: "MISSING1")
        let second = try metadata()
        let url = "file:///Nonprivate/Group%20Library/storage/ATTACH01/Source.pdf"
        let client = HintClient([
            .json(Data("[]".utf8)), .json(Data("[{\"id\":42,\"name\":\"Shared Library\",\"type\":\"group\"}]".utf8)),
            .json(try list([first, second])), .init(statusCode: 404, body: Data()),
            .text(url), .json(second), .text(url),
        ])
        #expect(try await server(client).suggestedOriginalLibraryDirectory()?.path == "/Nonprivate/Group Library")
        #expect(await client.requests.dropFirst(2).allSatisfy { $0.url?.path.hasPrefix("/api/groups/42/") == true })
    }

    @Test(
        "Linked files, unrelated storage layouts and unsafe URLs never identify a library",
        arguments: [
            "file:///Nonprivate/storage/OTHER001/Source.pdf",
            "file:///Nonprivate/storage/ATTACH01/Other.pdf",
            "file:///Nonprivate/attachments/ATTACH01/Source.pdf",
            "file:///storage/ATTACH01/Source.pdf",
            "file://remote.invalid/Nonprivate/storage/ATTACH01/Source.pdf",
            "file:///Nonprivate/../storage/ATTACH01/Source.pdf",
        ])
    func rejectedLayout(url: String) async throws {
        let client = HintClient([.json(try list([metadata()])), .text(url), .json(Data("[]".utf8))])
        #expect(try await server(client).suggestedOriginalLibraryDirectory() == nil)
    }

    @Test("A linked attachment never promotes its containing folder into a library")
    func linkedAttachment() async throws {
        let client = HintClient([.json(try list([metadata(mode: "linked_file")])), .json(Data("[]".utf8))])
        #expect(try await server(client).suggestedOriginalLibraryDirectory() == nil)
        #expect(await client.requests.count == 2)
    }

    @Test("Server, metadata and URL changes invalidate a candidate", arguments: [0, 1, 2])
    func changedObservation(change: Int) async throws {
        let item = try metadata()
        let url = "file:///Nonprivate/Library/storage/ATTACH01/Source.pdf"
        var replies: [HintReply] = [.json(try list([item])), .text(url), .json(item), .text(url)]
        if change == 0 { replies[1].serverID = "other-instance" }
        if change == 1 { replies[2] = .json(try metadata(filename: "Changed.pdf")) }
        if change == 2 { replies[3] = .text("file:///Nonprivate/Other/storage/ATTACH01/Source.pdf") }
        let client = HintClient(replies)
        do {
            _ = try await server(client).suggestedOriginalLibraryDirectory()
            Issue.record("A changed observation must not locate a library")
        } catch ZoteroMCPServiceError.materialChanged {}
    }

    @Test("Discovery bounds local file candidates and does not scan the library")
    func candidateBound() async throws {
        let items = try (1...20).map { try metadata(key: String(format: "ATT%05d", $0)) }
        let client = HintClient([.json(try list(items))] + Array(repeating: .init(statusCode: 404, body: Data()), count: 8))
        #expect(try await server(client).suggestedOriginalLibraryDirectory() == nil)
        #expect(await client.requests.count == 9)
    }

    private func server(_ client: HintClient) -> ZoteroMCPServer {
        ZoteroMCPServer(
            client: client,
            originalContentReader: { _, _ in
                Issue.record("Directory discovery must never read original bytes")
                throw CocoaError(.fileReadNoPermission)
            })
    }

    private func metadata(key: String = "ATTACH01", filename: String = "Source.pdf", mode: String = "imported_file") throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "key": key, "version": 1,
            "data": ["key": key, "itemType": "attachment", "linkMode": mode, "filename": filename],
        ])
    }

    private func list(_ items: [Data]) throws -> Data {
        try JSONSerialization.data(withJSONObject: items.map { try JSONSerialization.jsonObject(with: $0) })
    }
}

private struct HintReply: Sendable {
    var statusCode = 200
    var body: Data
    var serverID = "fixture-instance"
    static func json(_ data: Data) -> Self { .init(body: data) }
    static func text(_ value: String) -> Self { .init(body: Data(value.utf8)) }
}

private actor HintClient: ZoteroMCPHTTPClient {
    private var replies: [HintReply]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [HintReply]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> ZoteroMCPHTTPResponse {
        requests.append(request)
        let reply = try #require(replies.first, "Unexpected discovery request")
        replies.removeFirst()
        return .init(statusCode: reply.statusCode, headers: ["Zotero-Server-ID": reply.serverID], body: reply.body)
    }
}
