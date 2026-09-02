import Foundation
import ScholiumApplication
import ScholiumContracts

extension ScholiumCLI {
    static func runMCP(_ arguments: [String]) async throws {
        guard arguments == ["serve"] else {
            throw commandUsageError("mcp serve")
        }
        let server = ScholiumMCPServer(bridge: try CLIContext.makeMCPBridge())
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
