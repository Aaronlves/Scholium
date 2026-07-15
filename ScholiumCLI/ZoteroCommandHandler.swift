import ScholiumContracts
import Foundation

extension ScholiumCLI {
    static func runZotero(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard arguments.first == "mcp" else {
            throw CLIError.usage("Usage: scholium zotero mcp <config|status|serve> [--probe] [--format text|json]")
        }
        let subcommand = arguments.dropFirst().first ?? "status"
        if subcommand == "serve" {
            guard arguments.count == 2 else {
                throw CLIError.usage("Usage: scholium zotero mcp serve")
            }
            try await serveZoteroMCP(using: context.runtime.zotero)
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
                        ],
                    ],
                ]
                let data = try JSONSerialization.data(
                    withJSONObject: configuration,
                    options: [.prettyPrinted, .sortedKeys]
                )
                write(String(decoding: data, as: UTF8.self) + "\n")
            } else {
                write("""
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
            let report = arguments.contains("--probe")
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

    private static func serveZoteroMCP(using operations: any ZoteroUseCases) async throws {
        var parser = ZoteroMCPFrameParser()
        for try await byte in FileHandle.standardInput.bytes {
            for frame in try parser.append(byte) {
                guard let response = await operations.handle(requestData: frame.body) else {
                    continue
                }
                writeMCPFrame(response, mode: frame.mode)
            }
        }
        for frame in try parser.finish() {
            guard let response = await operations.handle(requestData: frame.body) else {
                continue
            }
            writeMCPFrame(response, mode: frame.mode)
        }
    }

    private static func writeMCPFrame(_ body: Data, mode: ZoteroMCPFrame.Mode) {
        switch mode {
        case .line:
            FileHandle.standardOutput.write(body + Data([0x0A]))
        case .contentLength:
            FileHandle.standardOutput.write(
                Data("Content-Length: \(body.count)\r\n\r\n".utf8) + body
            )
        }
    }
}
