import Foundation
import ScholiumContracts
import ScholiumCore

/// App-bundled MCP framing for external hosts and token-scoped Chat.
public enum AgentMCPService {
    public typealias Handler = @Sendable (Data) async -> Data?

    public static func serve(_ handler: Handler) async throws {
        var parser = MCPFrameParser()
        func write(_ frame: MCPFrame) async throws {
            guard let data = await handler(frame.body) else { return }
            let output =
                frame.mode == .line
                ? data + Data([10])
                : Data("Content-Length: \(data.count)\r\n\r\n".utf8) + data
            try FileHandle.standardOutput.write(contentsOf: output)
        }
        for try await byte in FileHandle.standardInput.bytes {
            for frame in try parser.append(byte) { try await write(frame) }
        }
        for frame in try parser.finish() { try await write(frame) }
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
        let bridge = try MCPBridgeOperations(applicationSupportURL: ScholiumPaths.appBridgeContainerURL(environment: environment))
        if let zoteroAccess {
            let discovery = ZoteroMCPServer()
            return { data in
                guard data.count <= ScholiumMCPContract.maximumEncodedMessageByteCount else {
                    return await discovery.handle(requestData: data, access: zoteroAccess)
                }
                let request = try? JSONDecoder().decode(MCPJSONValue.self, from: data)
                guard request?.objectValue?["method"] == .string("tools/call") else {
                    return await discovery.handle(requestData: data, access: zoteroAccess)
                }
                guard let request, request.objectValue?["id"] != nil else { return nil }
                guard let identity = request.objectValue?["id"],
                    let identityData = try? JSONEncoder().encode(identity),
                    identityData.count <= ScholiumMCPContract.maximumEncodedResponseIdentityByteCount
                else {
                    return try? JSONEncoder().encode(
                        ZoteroMCPBridgeReply.failure(
                            request: .object(["id": .null]), code: "invalid_request", message: "The Zotero MCP response identity exceeds its bounded limit."))
                }
                let envelope: ScholiumZoteroBridgeRequest
                do {
                    guard data.count <= ScholiumMCPContract.maximumEncodedMessageByteCount else {
                        throw ScholiumAppBridgeError.requestTooLarge
                    }
                    envelope = try .init(access: zoteroAccess, request: request)
                } catch {
                    return try? JSONEncoder().encode(
                        ZoteroMCPBridgeReply.failure(
                            request: request, code: "invalid_request", message: "The Zotero MCP call is invalid or exceeds its bounded request limit."))
                }
                let response: MCPJSONValue
                do {
                    response = try await bridge.callZotero(envelope)
                } catch {
                    let uncertain = envelope.mayMutate && Self.deliveryMayHaveStarted(error)
                    response = ZoteroMCPBridgeReply.failure(
                        request: request, code: uncertain ? "write_outcome_uncertain" : Self.zoteroBridgeFailureCode(error),
                        message: uncertain
                            ? "Scholium could not confirm delivery of the Zotero item update. Do not replay the update. Inspect the current Zotero item and version before another update."
                            : "The running Scholium App could not complete this Zotero call. Open Scholium and check its Zotero connection and original-file access before retrying this call.",
                        uncertain: uncertain)
                }
                return try? JSONEncoder().encode(response)
            }
        }
        let server = ScholiumMCPServer(conversationToken: token) { request in
            try await bridge.call(
                .init(
                    requestID: request.requestID, tool: request.tool,
                    arguments: request.arguments, conversationToken: token, runtimeContext: request.runtimeContext))
        }
        return { await server.handle(requestData: $0) }
    }

    private static func deliveryMayHaveStarted(_ error: Error) -> Bool {
        guard let error = error as? ScholiumAppBridgeError else { return true }
        switch error {
        case .outcomeUnknown, .invalidResponse: return true
        case .remote(let code, _): return code == "operation_uncertain"
        default: return false
        }
    }

    private static func zoteroBridgeFailureCode(_ error: Error) -> String {
        guard let error = error as? ScholiumAppBridgeError else { return "app_bridge_failure" }
        switch error {
        case .unavailable: return "app_unavailable"
        case .requestTooLarge: return "request_too_large"
        case .permissionDenied: return "app_bridge_permission_denied"
        default: return "app_bridge_failure"
        }
    }

    private enum HelperFailure: LocalizedError {
        case unsupportedCommand
        var errorDescription: String? { "The Scholium connection helper accepts only App-mediated Scholium or Zotero MCP service requests." }
    }
}
