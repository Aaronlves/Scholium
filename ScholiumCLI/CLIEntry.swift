import ScholiumContracts
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
            printHelp()
            return
        }

        if try renderMetaCommandIfPresent(arguments) { return }
        try validateCLIArguments(arguments)

        if command == "agent" {
            let agentArguments = Array(arguments.dropFirst())
            let operations = try CLIContext.makeAgentBridge()
            let credentialStore = CLIContext.makeAgentCredentialStore()
            if agentArguments.first == "start" {
                if let selector = option("--triptych", in: agentArguments),
                   let triptychID = UUID(uuidString: selector) {
                    // A UUID is already the bridge's typed identity. Let the
                    // running App validate it instead of requiring the CLI's
                    // local registry merely to translate the same value.
                    try await runAgent(
                        agentArguments,
                        triptychID: triptychID,
                        operations: operations,
                        credentialStore: credentialStore
                    )
                    return
                }
                let context = try await CLIContext.make()
                do {
                    let assignment = try await context.selectedTriptych(
                        selector: option("--triptych", in: agentArguments)
                    )
                    try await runAgent(
                        agentArguments,
                        triptychID: assignment.id,
                        operations: operations,
                        credentialStore: credentialStore
                    )
                } catch {
                    await context.shutdown()
                    throw error
                }
                await context.shutdown()
            } else {
                try await runAgent(
                    agentArguments,
                    operations: operations,
                    credentialStore: credentialStore
                )
            }
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
                case "action":
                    try await runAction(Array(arguments.dropFirst()), context: context)
                case "read":
                    try await runRead(Array(arguments.dropFirst()), context: context)
                case "note":
                    try await runNote(Array(arguments.dropFirst()), context: context)
                case "discuss":
                    try await runDiscuss(Array(arguments.dropFirst()), context: context)
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
