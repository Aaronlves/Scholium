import Foundation
import ScholiumApplication
import ScholiumContracts

extension ScholiumCLI {
    static func runMCP(_ arguments: [String]) async throws {
        let token: UUID?
        if arguments == ["serve"] {
            token = nil
        } else if arguments.count == 3, arguments[0] == "serve",
                  arguments[1] == "--conversation-token", let id = UUID(uuidString: arguments[2]) {
            token = id
        } else {
            throw commandUsageError("mcp serve")
        }
        let bridge = try CLIContext.makeMCPBridge()
        let server = ScholiumMCPServer { request in
            try await bridge.call(ScholiumMCPBridgeRequest(
                requestID: request.requestID, tool: request.tool,
                arguments: request.arguments, conversationToken: token,
                runtimeContext: request.runtimeContext
            ))
        }
        try await AgentMCPService.serve { await server.handle(requestData: $0) }
    }
}
