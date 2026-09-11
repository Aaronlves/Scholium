import Foundation
import ScholiumApplication
import ScholiumContracts

extension ScholiumCLI {
    static func runZotero(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard arguments.first == "mcp" else {
            throw commandUsageError("zotero mcp")
        }
        let subcommand = arguments.dropFirst().first ?? "status"
        if subcommand == "serve" {
            guard arguments.count == 2 || (arguments.count == 3 && arguments.last == "--read-only") else {
                throw commandUsageError("zotero mcp serve")
            }
            try await serveZoteroMCP(using: context.runtime.zotero, access: arguments.contains("--read-only") ? .readOnly : .guardedImports)
            return
        }
        let format = option("--format", in: arguments) ?? "text"
        guard format == "text" || format == "json" else {
            throw CLIError.usage("--format must be text or json.")
        }
        let operations = context.runtime.zotero
        let descriptor = operations.descriptor
        switch subcommand {
        case "config":
            if format == "json" {
                let configuration: [String: Any] = [
                    "mcpServers": [
                        "zotero": [
                            "command": descriptor.clientConfiguration.command,
                            "args": descriptor.clientConfiguration.arguments,
                        ]
                    ]
                ]
                let data = try JSONSerialization.data(
                    withJSONObject: configuration,
                    options: [.prettyPrinted, .sortedKeys]
                )
                write(String(decoding: data, as: UTF8.self) + "\n")
            } else {
                write(
                    """
                    First-party Zotero MCP transport: \(descriptor.displayName)
                    Build: \(descriptor.installationCommand)
                    Optional PATH install: \(descriptor.setupCommand)
                    Command: \(descriptor.command)
                    Arguments: \(descriptor.clientConfiguration.arguments.joined(separator: " "))
                    Retrieval: Zotero localhost API (read-only)
                    Guarded imports: localhost Connector with target-bound dry run and read-back
                    The Skill file is not a live connection.
                    Configuration:
                      {
                        \"mcpServers\": {
                          \"zotero\": {
                            \"command\": \"\(descriptor.clientConfiguration.command)\",
                            \"args\": [\"zotero\", \"mcp\", \"serve\"]
                          }
                        }
                      }
                    """)
                write("\n")
            }
        case "status":
            let report =
                arguments.contains("--probe")
                ? await operations.probe()
                : operations.report()
            if format == "json" {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                write(String(decoding: try encoder.encode(report), as: UTF8.self) + "\n")
            } else {
                write("Zotero MCP transport: \(report.state.rawValue)\n")
                if let path = report.commandPath {
                    write("Command: \(path)\n")
                }
                if let serverName = report.serverName {
                    write("Server: \(serverName)\n")
                }
                if let protocolVersion = report.serverProtocolVersion {
                    write("Protocol: \(protocolVersion)\n")
                }
                write("\(report.note)\n")
            }
        default:
            throw CLIError.usage("Unknown Zotero MCP command '\(subcommand)'.")
        }
    }

    private static func serveZoteroMCP(using operations: any ZoteroUseCases, access: ZoteroMCPAccess) async throws {
        try await AgentMCPService.serve { await operations.handle(requestData: $0, access: access) }
    }
}
