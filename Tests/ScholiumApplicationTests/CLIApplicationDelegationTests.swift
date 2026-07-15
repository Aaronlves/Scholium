import Foundation
import Testing

@Suite("CLI Application delegation")
struct CLIApplicationDelegationTests {
    @Test("CLI command families delegate to one snapshot runtime")
    func commandFamiliesUseApplicationCapabilities() throws {
        let sources = try CLISources.load()

        #expect(sources.context.contains("WorkspaceRuntime.snapshot("))
        #expect(sources.entry.contains("let context = try await CLIContext.make()"))
        #expect(sources.entry.contains("await context.shutdown()"))
        #expect(sources.workspace.contains("handle.discovery.search("))
        #expect(sources.workspace.contains("handle.discovery.snapshot().catalog"))
        #expect(sources.workspace.contains("let research = handle.research"))
        #expect(sources.workspace.contains("research.dialogueEntries()"))
        #expect(sources.document.contains("handle.documents.load("))
        #expect(sources.document.contains("handle.documents.create("))
        #expect(sources.document.contains("handle.documents.save("))
        #expect(sources.document.contains("handle.documents.move("))
        #expect(sources.document.contains("handle.documents.deletePermanently("))
        #expect(sources.entry.contains(#"case "zotero":"#))
        #expect(sources.entry.contains("context: context"))
        #expect(sources.zotero.contains("context.runtime.zotero"))
        #expect(sources.zotero.contains("operations.handle(requestData: frame.body)"))
        #expect(!sources.zotero.contains("ZoteroMCPServer("))
        #expect(!sources.zotero.contains("ZoteroMCPTransportLocator."))
    }

    @Test("Search, catalog, read, and lifecycle output schemas remain stable")
    func serializedOutputContractsRemainStable() throws {
        let sources = try CLISources.load()

        #expect(sources.workspace.contains(
            #"write("\(hit.vaultName):\(hit.relativePath):\(hit.sourceLine)  [retrieval_lead]\n  \(hit.snippet)\n")"#
        ))
        #expect(sources.workspace.contains(
            "String(decoding: try encoder.encode(hit), as: UTF8.self) + \"\\n\""
        ))
        #expect(sources.workspace.contains(
            "String(decoding: try encoder.encode(snapshot), as: UTF8.self) + \"\\n\""
        ))
        for key in ["vault_id", "vault_name", "relative_path", "sha256", "content"] {
            #expect(sources.document.contains("\"\(key)\""))
        }
        #expect(sources.document.contains("Created "))
        #expect(sources.document.contains("Replaced "))
        #expect(sources.document.contains("Moved "))
        #expect(sources.document.contains("Permanently deleted "))
        #expect(sources.zotero.contains(
            #"write("Zotero MCP transport: \(report.state.rawValue)\n")"#
        ))
        #expect(sources.zotero.contains(
            #"Data("Content-Length: \(body.count)\r\n\r\n".utf8) + body"#
        ))
        #expect(sources.zotero.contains(
            #"FileHandle.standardOutput.write(body + Data([0x0A]))"#
        ))
    }
}

private struct CLISources {
    let entry: String
    let context: String
    let workspace: String
    let document: String
    let zotero: String

    static func load() throws -> Self {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let cli = root.appendingPathComponent("ScholiumCLI", isDirectory: true)
        return try Self(
            entry: String(
                contentsOf: cli.appendingPathComponent("CLIEntry.swift"),
                encoding: .utf8
            ),
            context: String(
                contentsOf: cli.appendingPathComponent("CLIContext.swift"),
                encoding: .utf8
            ),
            workspace: String(
                contentsOf: cli.appendingPathComponent("WorkspaceCommandHandlers.swift"),
                encoding: .utf8
            ),
            document: String(
                contentsOf: cli.appendingPathComponent("DocumentCommandHandler.swift"),
                encoding: .utf8
            ),
            zotero: String(
                contentsOf: cli.appendingPathComponent("ZoteroCommandHandler.swift"),
                encoding: .utf8
            )
        )
    }
}
