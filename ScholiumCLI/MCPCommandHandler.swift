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
        var parser = ZoteroMCPFrameParser()
        for try await byte in FileHandle.standardInput.bytes {
            for frame in try parser.append(byte) {
                guard let response = await server.handle(requestData: frame.body) else {
                    continue
                }
                writeMCPResponse(response, mode: frame.mode)
            }
        }
        for frame in try parser.finish() {
            guard let response = await server.handle(requestData: frame.body) else {
                continue
            }
            writeMCPResponse(response, mode: frame.mode)
        }
    }

    private static func writeMCPResponse(
        _ body: Data,
        mode: ZoteroMCPFrame.Mode
    ) {
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
