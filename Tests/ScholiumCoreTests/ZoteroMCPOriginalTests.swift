import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Exact Zotero original selection")
struct ZoteroMCPOriginalTests {
    @Test("A linked original preserves BOM, CRLF and Unicode across fingerprint-bound slices")
    func exactTextOriginal() async throws {
        let fixture = try OriginalFixture(filename: "Source.txt", mime: "text/plain", linked: true)
        defer { fixture.remove() }
        let bytes = Data([0xEF, 0xBB, 0xBF]) + Data("α研究\r\nTail\r\n".utf8)
        try bytes.write(to: fixture.file)
        let first = try await fixture.call(["maximum_utf8": 5])
        #expect(!first.failed)
        let decoded = try JSONDecoder().decode(ZoteroMCPJSONValue.self, from: first.wire)
        let firstText = try #require(decoded.objectValue?["result"]?.objectValue?["structuredContent"]?.objectValue?["text"]?.stringValue)
        #expect(Data(firstText.utf8) == Data([0xEF, 0xBB, 0xBF]) + Data("α".utf8))
        #expect(first.value["next_start_utf8"] as? Int == 5)
        let fingerprint = try #require(first.value["original_fingerprint"] as? String)
        #expect(fingerprint == DocumentFingerprint(data: bytes).sha256)
        let next = try await fixture.call(["start_utf8": 5, "expected_fingerprint": fingerprint])
        #expect(!next.failed && next.value["text"] as? String == "研究\r\nTail\r\n")
        #expect(next.value["source_kind"] as? String == "zotero_original" && next.value["original_file_read"] as? Bool == true)
        #expect(next.value["filename"] as? String == "Source.txt")
        #expect(next.value["end_utf8"] as? Int == bytes.count && next.value["total_utf8"] as? Int == bytes.count)
        #expect(next.value["next_start_utf8"] is NSNull)
        let reference = try #require(next.value["reference"] as? [String: Any])
        #expect(reference["url"] as? String == "zotero://select/groups/42/items/ATTACH01")
        #expect(!String(describing: next.value).contains(fixture.root.path))
        #expect(try Data(contentsOf: fixture.file) == bytes)
        let requests = await fixture.client.requests
        #expect(requests.count == 8)
        #expect(
            requests.allSatisfy {
                $0.httpMethod == "GET" && $0.httpBody == nil && $0.url?.host == "127.0.0.1" && $0.url?.path.hasPrefix("/api/groups/42/items/ATTACH01") == true
            })
        #expect(
            requests.filter { $0.url?.path.hasSuffix("/file/view/url") == true }.allSatisfy {
                $0.value(forHTTPHeaderField: "Accept") == "text/plain" && $0.value(forHTTPHeaderField: "Zotero-Server-ID") == "synthetic-instance"
            })
        for path in ["attachments:Source.txt", "attachments:folder/Source.txt"] {
            await fixture.client.reset()
            await fixture.client.setMetadata(try fixture.metadata(linkedPath: path))
            #expect(try await fixture.call([:]).failed == false)
        }
        let markdown = try OriginalFixture(filename: "Source.md", mime: "text/markdown")
        defer { markdown.remove() }
        try Data("# Exact Markdown\r\n".utf8).write(to: markdown.file)
        let read = try await markdown.call([:])
        #expect(!read.failed && read.value["text"] as? String == "# Exact Markdown\r\n")
    }

    @Test("PDF reads return only the selected text or bounded native page image")
    func selectedPDFRepresentations() async throws {
        let fixture = try OriginalFixture(filename: "Paper.pdf", mime: "application/pdf")
        defer { fixture.remove() }
        let bytes = try Self.pdf(["First page excluded", "Second page selected", ""])
        try bytes.write(to: fixture.file)
        let text = try await fixture.call(["page": 2])
        #expect(!text.failed)
        #expect((text.value["text"] as? String)?.contains("Second page selected") == true)
        #expect((text.value["text"] as? String)?.contains("First page excluded") == false)
        #expect(text.value["total_pages"] as? Int == 3 && text.value["page"] as? Int == 2)
        let reference = try #require(text.value["reference"] as? [String: Any])
        #expect(reference["url"] as? String == "zotero://open-pdf/groups/42/items/ATTACH01?page=2")
        let blank = try await fixture.call(["page": 3])
        #expect(!blank.failed && blank.value["text_available"] as? Bool == false)
        let image = try await fixture.call(["mode": "image", "page": 2])
        #expect(!image.failed && image.value["text"] == nil && image.value["kind"] as? String == "pdf_page_image")
        let blocks = try #require(image.result["content"] as? [[String: Any]])
        let native = try #require(blocks.first { $0["type"] as? String == "image" })
        #expect(native["mimeType"] as? String == "image/png")
        let base64 = try #require(native["data"] as? String)
        let png = try #require(Data(base64Encoded: base64))
        #expect(png.count <= 512 * 1_024)
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let raster = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(raster.width <= 1_024 && raster.height <= 1_024)
        let textBlock = try #require(blocks.first?["text"] as? String)
        #expect(textBlock.contains(base64) == false)
        #expect(image.value["original_fingerprint"] as? String == DocumentFingerprint(data: bytes).sha256)
        #expect(try await fixture.call(["page": 4]).failed)
        #expect(try await fixture.call([:]).failed)
        let document = try #require(PDFDocument(data: bytes))
        let locked = try #require(
            document.dataRepresentation(options: [
                PDFDocumentWriteOption.ownerPasswordOption: "fixture-owner",
                PDFDocumentWriteOption.userPasswordOption: "fixture-reader",
            ]))
        try locked.write(to: fixture.file)
        let refused = try await fixture.call(["page": 1])
        #expect(refused.failed && (refused.value["error"] as? String)?.contains("locked") == true)
        let standalone = try OriginalFixture(filename: "Figure.png", mime: "image/png")
        defer { standalone.remove() }
        try png.write(to: standalone.file)
        let imageFile = try await standalone.call(["mode": "image"])
        #expect(!imageFile.failed && imageFile.value["kind"] as? String == "image")
        #expect(imageFile.value["original_fingerprint"] as? String == DocumentFingerprint(data: png).sha256)
    }

    @Test("Changed bytes, attachment records and API-resolved paths reject selected originals")
    func changedOriginalRefusals() async throws {
        let fixture = try OriginalFixture(filename: "Source.txt", mime: "text/plain")
        defer { fixture.remove() }
        let original = Data("Original".utf8)
        try original.write(to: fixture.file)
        #expect(try await fixture.call(["expected_fingerprint": String(repeating: "0", count: 64)]).failed)
        let file = fixture.file
        await fixture.client.reset(hook: { count in
            if count == 3 { try Data("Externally replaced".utf8).write(to: file, options: .atomic) }
        })
        let changed = try await fixture.call([:])
        #expect(changed.failed && changed.value["text"] == nil)
        #expect(try Data(contentsOf: fixture.file) == Data("Externally replaced".utf8))
        await fixture.client.reset()
        await fixture.client.setMetadataAfterRead(try fixture.metadata(version: 2))
        #expect(try await fixture.call([:]).failed)
        await fixture.client.reset()
        let other = fixture.root.appendingPathComponent("Other.txt")
        try original.write(to: other)
        await fixture.client.setSecondURL(other.absoluteString)
        #expect(try await fixture.call([:]).failed)
    }

    @Test("Local URL resolution refuses redirects, remote hosts, filename/type mismatches and symlinks")
    func unsafeOriginalRefusals() async throws {
        let fixture = try OriginalFixture(filename: "Source.txt", mime: "text/plain")
        defer { fixture.remove() }
        try Data("Selected".utf8).write(to: fixture.file)
        for url in [
            "https://example.invalid/Source.txt", "file://remote.invalid/Source.txt", fixture.file.absoluteString + "?query=1",
            fixture.root.appendingPathComponent("Missing.txt").absoluteString, fixture.file.absoluteString + "#fragment",
        ] {
            await fixture.client.reset()
            await fixture.client.setURLResponse(.init(statusCode: 200, headers: ["Zotero-Server-ID": "synthetic-instance"], body: Data(url.utf8)))
            let result = try await fixture.call([:])
            #expect(result.failed && result.value["text"] == nil)
        }
        await fixture.client.reset()
        await fixture.client.setURLResponse(.init(statusCode: 302, headers: ["Location": fixture.file.absoluteString]))
        #expect(try await fixture.call([:]).failed)
        await fixture.client.reset()
        let target = fixture.root.appendingPathComponent("Target.txt")
        try Data("Symlink target".utf8).write(to: target)
        try FileManager.default.removeItem(at: fixture.file)
        try FileManager.default.createSymbolicLink(at: fixture.file, withDestinationURL: target)
        #expect(try await fixture.call([:]).failed)
        try FileManager.default.removeItem(at: fixture.file)
        try Data("Selected".utf8).write(to: fixture.file)
        let alias = fixture.root.appendingPathComponent("Alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.root)
        await fixture.client.reset()
        await fixture.client.setURLResponse(
            .init(
                statusCode: 200, headers: ["Zotero-Server-ID": "synthetic-instance"], body: Data(alias.appendingPathComponent("Source.txt").absoluteString.utf8)
            ))
        #expect(try await fixture.call([:]).failed)
        await fixture.client.reset()
        await fixture.client.setMetadata(try fixture.metadata(mime: "application/pdf"))
        #expect(try await fixture.call(["page": 1]).failed)
    }

    @Test("Original input and file bounds fail without falling back to indexed text")
    func originalBoundsAndUnavailable() async throws {
        let fixture = try OriginalFixture(filename: "Source.txt", mime: "text/plain")
        defer { fixture.remove() }
        for args: [String: Any] in [
            ["mode": "ocr"], ["page": 0], ["page": 1e100], ["maximum_utf8": 65_537],
            ["start_utf8": 1], ["mode": "image", "maximum_utf8": 100], ["path": fixture.file.path], ["url": fixture.file.absoluteString],
        ] {
            #expect(try await fixture.call(args).failed)
        }
        #expect(await fixture.client.requests.isEmpty)
        #expect(try await fixture.call([:]).failed)
        try Data([0xFF]).write(to: fixture.file)
        #expect(try await fixture.call([:]).failed)
        try Data("α研究".utf8).write(to: fixture.file)
        #expect(try await fixture.call(["maximum_utf8": 1]).failed)
        try Data(repeating: 65, count: 20 * 1_024 * 1_024 + 1).write(to: fixture.file)
        #expect(try await fixture.call([:]).failed)
        #expect(await fixture.client.requests.allSatisfy { $0.url?.path.contains("fulltext") == false })
    }

    @Test("Cancellation at the API boundary returns no original content")
    func cancelledOriginal() async throws {
        let fixture = try OriginalFixture(filename: "Source.txt", mime: "text/plain")
        defer { fixture.remove() }
        try Data("Do not return".utf8).write(to: fixture.file)
        await fixture.client.reset(hook: { _ in withUnsafeCurrentTask { $0?.cancel() } })
        let task = Task {
            let result = try await fixture.call([:])
            return result.failed && result.value["text"] == nil
        }
        #expect(try await task.value)
        #expect(await fixture.client.requests.count == 1)
    }

    private static func pdf(_ pages: [String]) throws -> Data {
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data))
        let context = try #require(CGContext(consumer: consumer, mediaBox: nil, nil))
        for text in pages {
            context.beginPDFPage(nil)
            context.textPosition = CGPoint(x: 40, y: 500)
            let attributed = NSAttributedString(
                string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 14, nil)])
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}

private struct OriginalFixture: Sendable {
    let root: URL
    let file: URL
    let client: OriginalFixtureClient
    let server: ZoteroMCPServer
    let mime: String
    let linked: Bool

    init(filename: String, mime: String, linked: Bool = false) throws {
        root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/agent-knowledge-tools/zotero-original-fixtures/\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        file = root.appendingPathComponent(filename)
        self.mime = mime
        self.linked = linked
        client = OriginalFixtureClient(metadata: try Self.metadata(file: file, mime: mime, linked: linked, version: 1), fileURL: file.absoluteString)
        server = ZoteroMCPServer(client: client)
    }

    func metadata(mime: String? = nil, version: Int = 1, linkedPath: String? = nil) throws -> Data {
        try Self.metadata(file: file, mime: mime ?? self.mime, linked: linked, version: version, linkedPath: linkedPath)
    }
    private static func metadata(file: URL, mime: String, linked: Bool, version: Int, linkedPath: String? = nil) throws -> Data {
        var data: [String: Any] = [
            "key": "ATTACH01", "itemType": "attachment", "contentType": mime,
            "linkMode": linked ? "linked_file" : "imported_file", "parentItem": "PARENT01",
        ]
        if linked { data["path"] = linkedPath ?? file.path } else { data["filename"] = file.lastPathComponent }
        return try JSONSerialization.data(withJSONObject: ["key": "ATTACH01", "version": version, "data": data], options: [.sortedKeys])
    }
    struct Response {
        let wire: Data
        let result: [String: Any]
        let value: [String: Any]
        var failed: Bool { result["isError"] as? Bool == true }
    }
    func call(_ extra: [String: Any]) async throws -> Response {
        let defaults: [String: Any] = ["library": "group:42", "attachment_key": "ATTACH01", "mode": "text"]
        let data = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": ["name": "zotero_read_original", "arguments": defaults.merging(extra, uniquingKeysWith: { _, new in new })],
        ])
        let response = try #require(await server.handle(requestData: data, access: .readOnly))
        let rpc = try #require(JSONSerialization.jsonObject(with: response) as? [String: Any])
        let result = try #require(rpc["result"] as? [String: Any])
        let value = try #require(result["structuredContent"] as? [String: Any])
        return Response(wire: response, result: result, value: value)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

private actor OriginalFixtureClient: ZoteroMCPHTTPClient {
    private let initialMetadata: Data
    private var metadata: Data
    private let fileURL: String
    private var metadataAfterRead: Data?
    private var secondURL: String?
    private var urlResponse: ZoteroMCPHTTPResponse?
    private var hook: (@Sendable (Int) throws -> Void)?
    private(set) var requests: [URLRequest] = []

    init(metadata: Data, fileURL: String) {
        self.initialMetadata = metadata
        self.metadata = metadata
        self.fileURL = fileURL
    }
    func reset(hook: (@Sendable (Int) throws -> Void)? = nil) {
        requests = []
        metadata = initialMetadata
        metadataAfterRead = nil
        secondURL = nil
        urlResponse = nil
        self.hook = hook
    }
    func setMetadataAfterRead(_ value: Data) { metadataAfterRead = value }
    func setMetadata(_ value: Data) { metadata = value }
    func setSecondURL(_ value: String) { secondURL = value }
    func setURLResponse(_ value: ZoteroMCPHTTPResponse) { urlResponse = value }

    func send(_ request: URLRequest) async throws -> ZoteroMCPHTTPResponse {
        requests.append(request)
        try hook?(requests.count)
        let headers = ["Zotero-Server-ID": "synthetic-instance"]
        switch request.url?.path {
        case "/api/groups/42/items/ATTACH01":
            return .init(statusCode: 200, headers: headers, body: requests.count >= 3 ? metadataAfterRead ?? metadata : metadata)
        case "/api/groups/42/items/ATTACH01/file/view/url":
            return urlResponse ?? .init(statusCode: 200, headers: headers, body: Data((requests.count >= 4 ? secondURL ?? fileURL : fileURL).utf8))
        default:
            throw URLError(.badURL)
        }
    }
}
