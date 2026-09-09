import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumApplication

struct AgentMCPServiceTests {
    @Test func helperRejectsStandaloneAndImportEntrypoints() {
        for args in [["update"], ["mcp", "serve"], ["zotero", "mcp", "serve"],
                     ["mcp", "serve", "--conversation-token", "invalid"]] {
            #expect(throws: (any Error).self) { try AgentMCPService.helperHandler(arguments: args, environment: [:]) }
        }
    }
    @Test func bundledDiscoveryDoesNotRequireUserCLI() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("Contents/Helpers/ScholiumAgentHelper")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        #expect(ScholiumAgentIntegrationResources.chatHelperURL(bundleURL: root) == nil)
        try Data("fixture".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        #expect(ScholiumAgentIntegrationResources.chatHelperURL(bundleURL: root) == executable)
    }
    @Test func readOnlyHelperPublishesReadToolsAndRejectsImports() async throws {
        let handler = try AgentMCPService.helperHandler(arguments: ["zotero", "mcp", "serve", "--read-only"], environment: [:])
        let response = try #require(await handler(Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#.utf8)))
        let object = try JSONSerialization.jsonObject(with: response) as! [String: Any]
        let result = object["result"] as! [String: Any]
        let tools = result["tools"] as! [[String: Any]]
        #expect(tools.count == 7)
        #expect(!tools.contains { ($0["name"] as? String)?.contains("import") == true })
        let denied = try #require(await handler(Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"zotero_import_bibtex","arguments":{}}}"#.utf8)))
        #expect(String(decoding: denied, as: UTF8.self).contains("error"))
    }
}
