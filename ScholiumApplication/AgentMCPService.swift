import Foundation
import ScholiumContracts

/// The same framing owner serves the standalone CLI and the app-owned helper.
public enum AgentMCPService {
    public typealias Handler = @Sendable (Data) async -> Data?

    public static func serve(_ handler: Handler) async throws {
        var parser = ZoteroMCPFrameParser()
        func write(_ frame: ZoteroMCPFrame) async {
            guard let data = await handler(frame.body) else { return }
            let output = frame.mode == .line ? data + Data([10])
                : Data("Content-Length: \(data.count)\r\n\r\n".utf8) + data
            FileHandle.standardOutput.write(output)
        }
        for try await byte in FileHandle.standardInput.bytes {
            for frame in try parser.append(byte) { await write(frame) }
        }
        for frame in try parser.finish() { await write(frame) }
    }

    /// Closed helper entry points: no workspace runtime, installer or CLI maintenance.
    public static func helperHandler(arguments: [String], environment: [String: String]) throws -> Handler {
        if arguments == ["zotero", "mcp", "serve", "--read-only"] {
            let zotero = ZoteroOperations()
            return { await zotero.handle(requestData: $0, access: .readOnly) }
        }
        guard arguments.count == 4, Array(arguments.prefix(3)) == ["mcp", "serve", "--conversation-token"],
              let token = UUID(uuidString: arguments[3]) else { throw HelperFailure.unsupportedCommand }
        let bridge = try MCPBridgeOperations(applicationSupportURL: ScholiumPaths.appBridgeContainerURL(environment: environment))
        let server = ScholiumMCPServer { request in
            try await bridge.call(.init(requestID: request.requestID, tool: request.tool,
                arguments: request.arguments, conversationToken: token, runtimeContext: request.runtimeContext))
        }
        return { await server.handle(requestData: $0) }
    }

    private enum HelperFailure: LocalizedError {
        case unsupportedCommand
        var errorDescription: String? { "The Scholium connection helper accepts only app-scoped MCP or read-only Zotero service requests." }
    }
}
