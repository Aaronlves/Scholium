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
            #expect(!names.contains("zotero_import_bibtex"))
            #expect(!names.contains("zotero_import_ris"))
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
        let chatControls: [ScholiumMCPToolName] = [
            .capabilities, .configureSkill, .configureTool, .configureChat, .observeCurrentState,
        ]
        let researchTools = ScholiumMCPToolName.allCases.filter { !chatControls.contains($0) }
        #expect(researchTools.count == 19)
        #expect(ScholiumMCPToolName.allCases.filter(\.isChatControl) == chatControls)
        for (handler, expectedTools) in [(external, researchTools), (scoped, researchTools + chatControls)] {
            let data = try #require(await handler(Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#.utf8)))
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let result = try #require(object["result"] as? [String: Any])
            let tools = try #require(result["tools"] as? [[String: Any]])
            #expect(tools.compactMap { $0["name"] as? String } == expectedTools.map(\.rawValue))
            #expect(tools.count == expectedTools.count)
        }
        for (index, tool) in chatControls.enumerated() {
            let request: [String: Any] = [
                "jsonrpc": "2.0", "id": index + 3, "method": "tools/call",
                "params": ["name": tool.rawValue, "arguments": [:]],
            ]
            let data = try #require(await external(JSONSerialization.data(withJSONObject: request)))
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let result = try #require(object["result"] as? [String: Any])
            let failure = try #require(result["structuredContent"] as? [String: Any])
            #expect(result["isError"] as? Bool == true)
            #expect(failure["code"] as? String == "invalid_request")
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

    @Test func discoversCodexInCurrentChatGPTBundleLayout() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let chatGPT = root.appendingPathComponent("Custom Location/ChatGPT.app", isDirectory: true)
        let info = chatGPT.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.createDirectory(at: info.deletingLastPathComponent(), withIntermediateDirectories: true)
        #expect(((["CFBundleIdentifier": "com.openai.codex"] as NSDictionary).write(to: info, atomically: true)))
        let executable = chatGPT.appendingPathComponent(
            "Contents/Resources/codex-cli/Runtime Bundle.app/Contents/MacOS/codex")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture runtime".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        let discoveredRuntime = try #require(
            ScholiumAgentIntegrationResources.codexRuntimeURL(
                registeredApplicationBundles: [chatGPT],
                trustedApplication: { $0 == chatGPT },
                trustedNestedRuntime: { $0.lastPathComponent == "Runtime Bundle.app" }))
        #expect(discoveredRuntime.standardizedFileURL.path == executable.standardizedFileURL.path)
        #expect(
            ScholiumAgentIntegrationResources.codexRuntimeURL(
                registeredApplicationBundles: [chatGPT], trustedApplication: { _ in true },
                trustedNestedRuntime: { _ in false }) == nil)
        // A copied bundle ID without OpenAI's signature cannot authorize automatic execution.
        #expect(
            ScholiumAgentIntegrationResources.codexRuntimeURL(
                registeredApplicationBundles: [chatGPT]) == nil)
    }

    @Test func rejectsRuntimeEscapingSignedApplicationLayout() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let application = root.appendingPathComponent("ChatGPT.app", isDirectory: true)
        let info = application.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.createDirectory(at: info.deletingLastPathComponent(), withIntermediateDirectories: true)
        #expect(((["CFBundleIdentifier": "com.openai.codex"] as NSDictionary).write(to: info, atomically: true)))
        let outside = root.appendingPathComponent("Outside.app/Contents/MacOS/codex")
        try FileManager.default.createDirectory(at: outside.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("foreign runtime".utf8).write(to: outside)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: outside.path)
        let cli = application.appendingPathComponent("Contents/Resources/codex-cli")
        try FileManager.default.createDirectory(at: cli, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: cli.appendingPathComponent("Outside.app"),
            withDestinationURL: outside.deletingLastPathComponent().deletingLastPathComponent())
        #expect(
            ScholiumAgentIntegrationResources.codexRuntimeURL(
                registeredApplicationBundles: [application], trustedApplication: { _ in true },
                trustedNestedRuntime: { _ in true }) == nil)
    }

    @Test func doesNotSearchConventionalOrStandalonePathsWithoutRegisteredApplications() {
        #expect(ScholiumAgentIntegrationResources.codexRuntimeURL(registeredApplicationBundles: []) == nil)
    }

    @Test func ignoresLegacyDirectResourcesRuntime() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let application = root.appendingPathComponent("Legacy.app", isDirectory: true)
        let executable = application.appendingPathComponent("Contents/Resources/codex")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("legacy runtime".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        #expect(ScholiumAgentIntegrationResources.codexRuntimeURL(registeredApplicationBundles: [application]) == nil)
    }
}
