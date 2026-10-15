import CoreGraphics
import CoreText
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp
@testable import ScholiumApplication

@Suite("Zotero original to saved Analysis workflow", .serialized)
@MainActor
struct ZoteroAnalysisWorkflowTests {
    @Test("An unusable index can be checked against a granted original, saved and reread through the App tools")
    func originalToAnalysis() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/zotero-analysis-workflow/\(UUID())")
        let originals = root.appendingPathComponent("Originals")
        let vaults = ["Analyses", "Topics", "Works"].map { root.appendingPathComponent($0) }
        for directory in [originals] + vaults {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let file = originals.appendingPathComponent("Article.pdf")
        let bytes = try pdf()
        try bytes.write(to: file)
        let api = WorkflowZoteroAPI(original: file)
        let support = root.appendingPathComponent("Support")
        let zotero = ZoteroOperations(applicationSupportURL: support, mcpRequestLoader: { try await api.send($0) })
        let runtime = WorkspaceRuntime(
            configuration: .live(
                .init(
                    applicationSupportURL: support, workspaceRegistryStorageURL: root.appendingPathComponent("Registry"))), zotero: zotero)
        let handle = try await runtime.configureTriptych(
            paperAnalysisURL: vaults[0], topicKnowledgeURL: vaults[1], outputURL: vaults[2],
            portableContainerURL: root, triptychName: "Original Analysis Fixture")
        let assignment = try #require(try await runtime.availableWorkspaces().first)
        let router = ScholiumAppBridgeRequestRouter(
            runtime: runtime, flushEditors: { _ in }, openTriptychs: { [assignment] })
        let bridgeRoot = root.appendingPathComponent("Bridge")
        let server = try ScholiumAppBridgeServer(
            applicationSupportURL: bridgeRoot,
            zoteroHandler: { request in
                let response = try #require(
                    await zotero.handle(
                        requestData: JSONEncoder().encode(request.request), access: request.access))
                return try JSONDecoder().decode(MCPJSONValue.self, from: response)
            }
        ) { request in await router.handle(request) }
        defer { server.stop() }
        do {
            let environment = ["SCHOLIUM_APP_BRIDGE_CONTAINER": bridgeRoot.path]
            let zoteroTool = try AgentMCPService.helperHandler(arguments: ["zotero", "mcp", "serve", "--read-only"], environment: environment)
            let noteTool = try AgentMCPService.helperHandler(arguments: ["mcp", "serve"], environment: environment)
            let selection: [String: MCPJSONValue] = ["library": .string("user"), "attachment_key": .string("ATTACH01")]
            let index = try await call(zoteroTool, "zotero_fulltext", selection)
            #expect(index["text"] == .string("Unrelated indexed chapter"))
            #expect(index["original_file_read"] == .bool(false))
            let page = selection.merging(["page": .integer(1), "mode": .string("text")], uniquingKeysWith: { _, new in new })
            let denied = try await call(zoteroTool, "zotero_read_original_page", page, failed: true)
            #expect(denied["error_code"] == .string("original_permission_denied"))
            #expect(try await handle.agentCollaboration.agentChanges().isEmpty)

            try await zotero.authorizeOriginalAccess(selectedURL: originals, replacing: nil)
            let original = try await call(zoteroTool, "zotero_read_original_page", page)
            let text = try #require(original["text"]?.stringValue)
            let reference = try #require(original["reference"]?.objectValue?["url"]?.stringValue)
            let fingerprint = try #require(original["original_fingerprint"]?.stringValue)
            #expect(text.contains("Exact Fixture Article") && !text.contains("Unrelated indexed chapter"))
            #expect(original["original_file_read"] == .bool(true) && original["page"] == .integer(1))
            #expect(fingerprint == DocumentFingerprint(data: bytes).sha256)
            let blankPage = page.merging(["page": .integer(2), "expected_fingerprint": .string(fingerprint)], uniquingKeysWith: { _, new in new })
            #expect(try await call(zoteroTool, "zotero_read_original_page", blankPage)["text_available"] == .bool(false))
            let image = try await call(
                zoteroTool, "zotero_read_original_page", blankPage.merging(["mode": .string("image")], uniquingKeysWith: { _, new in new }))
            #expect(image["kind"] == .string("pdf_page_image") && image["page"] == .integer(2))

            let source =
                "# Fixture Analysis\r\n\r\n[Original page 1](\(reference))\r\n\r\nRead physical page 1 as text and page 2 as an image.\r\n\r\n\(text)\r\n"
            let created = try await call(
                noteTool, "scholium_create_note",
                [
                    "triptych_id": .string(handle.id.uuidString), "role": .string("analyses"),
                    "relative_path": .string("Fixture Analysis.md"), "content": .string(source),
                ])
            let noteID = try #require(created["note_id"]?.stringValue)
            let saved = try await call(
                noteTool, "scholium_read_note",
                [
                    "triptych_id": .string(handle.id.uuidString), "note_id": .string(noteID),
                ])
            #expect(saved["source"] == .string(source) && saved["complete"] == .bool(true))
            #expect(saved["fingerprint"] == created["fingerprint"])
            #expect(try Data(contentsOf: vaults[0].appendingPathComponent("Fixture Analysis.md")) == Data(source.utf8))
            #expect(try await handle.agentCollaboration.agentChanges().count == 1)

            let grant = try #require(try await zotero.originalAccessGrants().first)
            try await zotero.removeOriginalAccess(grantID: grant.id)
            let revoked = try await call(zoteroTool, "zotero_read_original_page", page, failed: true)
            #expect(revoked["error_code"] == .string("original_permission_denied"))
            #expect(try Data(contentsOf: file) == bytes)
            #expect(await api.requests.allSatisfy { $0.httpMethod == "GET" && $0.url?.host == "127.0.0.1" })
            #expect(await server.stopAndWait(timeout: 2))
            await runtime.shutdown()
        } catch {
            _ = await server.stopAndWait(timeout: 2)
            await runtime.shutdown()
            throw error
        }
    }

    private func call(_ handler: AgentMCPService.Handler, _ tool: String, _ arguments: [String: MCPJSONValue], failed: Bool = false) async throws -> [String:
        MCPJSONValue]
    {
        let request = MCPJSONValue.object([
            "jsonrpc": .string("2.0"), "id": .integer(1), "method": .string("tools/call"),
            "params": .object(["name": .string(tool), "arguments": .object(arguments)]),
        ])
        let response = try #require(await handler(JSONEncoder().encode(request)))
        let result = try #require(try JSONDecoder().decode(MCPJSONValue.self, from: response).objectValue?["result"]?.objectValue)
        #expect(result["isError"] == .bool(failed))
        return try #require(result["structuredContent"]?.objectValue)
    }

    private func pdf() throws -> Data {
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data))
        let context = try #require(CGContext(consumer: consumer, mediaBox: nil, nil))
        for text in ["Exact Fixture Article", ""] {
            context.beginPDFPage(nil)
            context.textPosition = CGPoint(x: 40, y: 500)
            CTLineDraw(
                CTLineCreateWithAttributedString(
                    NSAttributedString(
                        string: text,
                        attributes: [
                            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 14, nil)
                        ])), context)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}

private actor WorkflowZoteroAPI {
    let original: URL
    private(set) var requests: [URLRequest] = []
    init(original: URL) { self.original = original }
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let path = request.url?.path ?? ""
        let body: Data
        if path.hasSuffix("/file/view/url") {
            body = Data(original.absoluteString.utf8)
        } else if path.hasSuffix("/fulltext") {
            body = Data(#"{"content":"Unrelated indexed chapter","indexedPages":1,"totalPages":2}"#.utf8)
        } else if path == "/api/users/0/items/ATTACH01" {
            body = Data(
                #"{"key":"ATTACH01","version":1,"data":{"key":"ATTACH01","itemType":"attachment","parentItem":"PARENT01","linkMode":"imported_file","contentType":"application/pdf","filename":"Article.pdf"}}"#
                    .utf8)
        } else {
            throw URLError(.badURL)
        }
        let url = try #require(request.url)
        let response = try #require(
            HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Zotero-Server-ID": "fixture-server", "Last-Modified-Version": "1"]))
        return (body, response)
    }
}
