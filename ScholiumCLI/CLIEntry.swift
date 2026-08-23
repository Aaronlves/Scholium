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
            printHelp()
            return
        }

        if try renderMetaCommandIfPresent(arguments) { return }
        try validateCLIArguments(arguments)

        if command == "agent" {
            let agentArguments = Array(arguments.dropFirst())
            let operations = try CLIContext.makeAgentBridge()
            let credentialStore = CLIContext.makeAgentCredentialStore()
            if agentArguments.first == "start"
                || agentArguments.first == "preflight-analysis" {
                let triptychID = try await agentStartTriptychID(
                    selector: option("--triptych", in: agentArguments)
                )
                try await runAgent(
                    agentArguments,
                    triptychID: triptychID,
                    operations: operations,
                    credentialStore: credentialStore
                )
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
                case "record":
                    try await runRecord(Array(arguments.dropFirst()), context: context)
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

    /// Resolves the documented UUID-or-unique-name selector when the CLI has a
    /// healthy local registry projection. A UUID remains directly usable when
    /// that projection is absent or does not yet contain the App-owned
    /// registration; UUID-shaped names therefore retain ordinary name lookup.
    private static func agentStartTriptychID(selector: String?) async throws -> UUID {
        let directID = selector.flatMap(UUID.init(uuidString:))
        let context: CLIContext
        do {
            context = try await CLIContext.make()
        } catch {
            if let directID { return directID }
            throw error
        }
        do {
            let assignment = try await context.selectedTriptych(selector: selector)
            await context.shutdown()
            return assignment.id
        } catch let error as WorkspaceRegistryError {
            await context.shutdown()
            if case .triptychSelectorNotFound = error, let directID {
                return directID
            }
            throw error
        } catch {
            await context.shutdown()
            throw error
        }
    }
}
