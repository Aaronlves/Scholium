import Foundation
import ScholiumContracts

/// App-bundled MCP framing for external hosts and token-scoped Chat.
public enum AgentMCPService {
    public typealias Handler = @Sendable (Data) async -> Data?

    public static func serve(_ handler: Handler) async throws {
        var parser = MCPFrameParser()
        func write(_ frame: MCPFrame) async {
            guard let data = await handler(frame.body) else { return }
            let output =
                frame.mode == .line
                ? data + Data([10])
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
        let token: UUID?
        let zoteroAccess: ZoteroMCPAccess?
        if arguments == ["mcp", "serve"] {
            token = nil
            zoteroAccess = nil
        } else if arguments.count == 4, Array(arguments.prefix(3)) == ["mcp", "serve", "--conversation-token"],
            let identifier = UUID(uuidString: arguments[3])
        {
            token = identifier
            zoteroAccess = nil
        } else if arguments == ["zotero", "mcp", "serve"] {
            token = nil
            zoteroAccess = .full
        } else if arguments == ["zotero", "mcp", "serve", "--read-only"] {
            token = nil
            zoteroAccess = .readOnly
        } else {
            throw HelperFailure.unsupportedCommand
        }
        if let zoteroAccess {
            let zotero = ZoteroOperations()
            return { await zotero.handle(requestData: $0, access: zoteroAccess) }
        }
        let bridge = try MCPBridgeOperations(applicationSupportURL: ScholiumPaths.appBridgeContainerURL(environment: environment))
        let server = ScholiumMCPServer(conversationToken: token) { request in
            try await bridge.call(
                .init(
                    requestID: request.requestID, tool: request.tool,
                    arguments: request.arguments, conversationToken: token, runtimeContext: request.runtimeContext))
        }
        return { await server.handle(requestData: $0) }
    }

    private enum HelperFailure: LocalizedError {
        case unsupportedCommand
        var errorDescription: String? { "The Scholium connection helper accepts only App-mediated Scholium MCP or independent Zotero MCP service requests." }
    }
}
