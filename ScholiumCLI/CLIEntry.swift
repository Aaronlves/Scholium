import ScholiumContracts
import ScholiumCLIUpdate
import Darwin
import Foundation

@main
struct ScholiumCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        do {
            try await run(arguments)
        } catch {
            writeCLIError(error, arguments: arguments)
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) async throws {
        guard let command = arguments.first else {
            try printHelp()
            return
        }

        if try renderMetaCommandIfPresent(arguments) { return }
        try validateCLIArguments(arguments)

        if command == "mcp" {
            try await runMCP(Array(arguments.dropFirst()))
            return
        }

        switch command {
        case "doctor":
            let context = try await CLIContext.make()
            do {
                try await runDoctor(Array(arguments.dropFirst()), context: context)
            } catch {
                await context.shutdown()
                throw error
            }
            await context.shutdown()
        case "update":
            try await runUpdate(Array(arguments.dropFirst()))
        default:
            let context = try await CLIContext.make()
            do {
                switch command {
                case "zotero":
                    try await runZotero(
                        Array(arguments.dropFirst()),
                        context: context
                    )
                case "vault":
                    try await runVault(Array(arguments.dropFirst()), context: context)
                case "search":
                    try await runSearch(Array(arguments.dropFirst()), context: context)
                case "links":
                    try await runLinks(Array(arguments.dropFirst()), context: context)
                case "graph":
                    try await runGraph(Array(arguments.dropFirst()), context: context)
                case "workspace":
                    try await runWorkspace(Array(arguments.dropFirst()), context: context)
                case "read":
                    try await runRead(Array(arguments.dropFirst()), context: context)
                case "note":
                    try await runNote(Array(arguments.dropFirst()), context: context)
                default:
                    throw CLIError.usage("Unknown command '\(command)'. Run 'scholium help'.")
                }
            } catch {
                await context.shutdown()
                throw error
            }
            await context.shutdown()
        }
    }

}
