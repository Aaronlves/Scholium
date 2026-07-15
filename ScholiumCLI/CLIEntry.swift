import ScholiumContracts
import Darwin
import Foundation

@main
struct ScholiumCLI {
    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            writeError("scholium: \(error.localizedDescription)\n")
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) async throws {
        guard let command = arguments.first else {
            printHelp()
            return
        }

        switch command {
        case "help", "--help", "-h":
            printHelp()
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
                case "skills":
                    try await runSkills(Array(arguments.dropFirst()), context: context)
                case "workflow":
                    try await runWorkflow(Array(arguments.dropFirst()), context: context)
                case "read":
                    try await runRead(Array(arguments.dropFirst()), context: context)
                case "note":
                    try await runNote(Array(arguments.dropFirst()), context: context)
                case "dialogue":
                    try await runDialogue(Array(arguments.dropFirst()), context: context)
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
