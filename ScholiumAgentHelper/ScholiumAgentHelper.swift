import Foundation
import ScholiumApplication

@main
struct ScholiumAgentHelper {
    static func main() async {
        do {
            let handler = try AgentMCPService.helperHandler(arguments: Array(CommandLine.arguments.dropFirst()),
                environment: ProcessInfo.processInfo.environment)
            try await AgentMCPService.serve(handler)
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(64)
        }
    }
}
