import Foundation
import ScholiumContracts

/// Standalone-CLI client for the current-user-only App bridge. The adapter
/// owns no workspace, source, Search index, permission, or task state.
public actor MCPBridgeOperations {
    private let client: ScholiumAppBridgeClient

    public init(applicationSupportURL: URL) throws {
        client = try ScholiumAppBridgeClient(
            applicationSupportURL: applicationSupportURL
        )
    }

    public func call(_ request: ScholiumMCPBridgeRequest) throws -> MCPJSONValue {
        let response = try client.send(ScholiumAppBridgeRequest(
            mcpRequest: request
        ))
        guard let bridgeResponse = response.mcpResponse,
              bridgeResponse.requestID == request.requestID else {
            throw ScholiumMCPFailure(
                code: .internalError,
                message: "The running App returned an invalid MCP response.",
                recovery: "Restart Scholium and begin again with workspace status."
            )
        }
        if let error = bridgeResponse.error { throw error }
        guard let result = bridgeResponse.result else {
            throw ScholiumMCPFailure(
                code: .internalError,
                message: "The running App returned no MCP result.",
                recovery: "Restart Scholium and begin again with workspace status."
            )
        }
        return result
    }
}
