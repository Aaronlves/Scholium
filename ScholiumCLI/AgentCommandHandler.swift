import Foundation
import ScholiumContracts

extension ScholiumCLI {
    static func runAgent(
        _ arguments: [String],
        operations: any AgentBridgeUseCases
    ) async throws {
        guard arguments == ["mcp", "serve"] else {
            throw CLIError.usage("Usage: scholium agent mcp serve")
        }
        var parser = ZoteroMCPFrameParser()
        for try await byte in FileHandle.standardInput.bytes {
            for frame in try parser.append(byte) {
                guard let response = await operations.handle(
                    requestData: frame.body
                ) else { continue }
                writeAgentMCPFrame(response, mode: frame.mode)
            }
        }
        for frame in try parser.finish() {
            guard let response = await operations.handle(
                requestData: frame.body
            ) else { continue }
            writeAgentMCPFrame(response, mode: frame.mode)
        }
    }

    private static func writeAgentMCPFrame(
        _ data: Data,
        mode: ZoteroMCPFrame.Mode
    ) {
        switch mode {
        case .line:
            FileHandle.standardOutput.write(data + Data([0x0A]))
        case .contentLength:
            FileHandle.standardOutput.write(
                Data("Content-Length: \(data.count)\r\n\r\n".utf8) + data
            )
        }
    }
}
