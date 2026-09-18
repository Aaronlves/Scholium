import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

struct AgentMCPServiceTests {
    @Test func helperRejectsStandaloneAndImportEntrypoints() {
        for args in [
            ["update"], ["version"], ["zotero"], ["zotero", "mcp"], ["zotero", "mcp", "serve", "--unsupported"],
            ["mcp", "serve", "--conversation-token", "invalid"],
        ] {
            #expect(throws: (any Error).self) { try AgentMCPService.helperHandler(arguments: args, environment: [:]) }
        }
    }

    @Test func independentZoteroHelperExposesReadWriteSurface() async throws {
        let full = try AgentMCPService.helperHandler(arguments: ["zotero", "mcp", "serve"], environment: [:])
        let readOnly = try AgentMCPService.helperHandler(arguments: ["zotero", "mcp", "serve", "--read-only"], environment: [:])
        for (handler, expectsWrites) in [(full, true), (readOnly, false)] {
            let data = try #require(await handler(Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#.utf8)))
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let result = try #require(object["result"] as? [String: Any])
            let tools = try #require(result["tools"] as? [[String: Any]])
            let names = Set(tools.compactMap { $0["name"] as? String })
            #expect(names.contains("zotero_search"))
            #expect(names.contains("zotero_fulltext"))
            #expect(names.contains("zotero_import_bibtex") == expectsWrites)
            #expect(names.contains("zotero_update_item") == expectsWrites)
            if expectsWrites {
                let update = try #require(tools.first { $0["name"] as? String == "zotero_update_item" })
                let annotations = try #require(update["annotations"] as? [String: Any])
                #expect(annotations["readOnlyHint"] as? Bool == false)
                #expect(annotations["destructiveHint"] as? Bool == true)
            }
        }
    }
    @Test func externalHelperExposesOnlyResearchToolsAndRefusesMissingApp() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = ["SCHOLIUM_APP_BRIDGE_CONTAINER": root.path]
        let external = try AgentMCPService.helperHandler(arguments: ["mcp", "serve"], environment: environment)
        let scoped = try AgentMCPService.helperHandler(
            arguments: ["mcp", "serve", "--conversation-token", UUID().uuidString], environment: environment)
        for (handler, expectedCount) in [(external, 16), (scoped, 20)] {
            let data = try #require(await handler(Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#.utf8)))
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let result = try #require(object["result"] as? [String: Any])
            let tools = try #require(result["tools"] as? [[String: Any]])
            #expect(tools.count == expectedCount)
        }
        let response = try #require(
            await external(
                Data(
                    #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"scholium_workspace_status","arguments":{}}}"#.utf8)))
        #expect(String(decoding: response, as: UTF8.self).contains("isError"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Workspace").path))
    }

    @Test func bundledDiscoveryUsesOnlyAppHelper() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("Contents/Helpers/ScholiumAgentHelper")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        #expect(ScholiumAgentIntegrationResources.chatHelperURL(bundleURL: root) == nil)
        try Data("fixture".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        #expect(ScholiumAgentIntegrationResources.chatHelperURL(bundleURL: root) == executable)
    }
}
