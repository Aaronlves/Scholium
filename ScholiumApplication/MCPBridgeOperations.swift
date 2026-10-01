import Foundation
import ScholiumContracts

/// Bundled-helper client for the current-user-only App bridge. The adapter
/// owns no workspace, source, Search index, permission, or task state.
public actor MCPBridgeOperations {
    private let client: ScholiumAppBridgeClient

    public init(applicationSupportURL: URL) throws {
        client = try ScholiumAppBridgeClient(
            applicationSupportURL: applicationSupportURL
        )
    }

    public func call(_ request: ScholiumMCPBridgeRequest) throws -> MCPJSONValue {
        let response = try client.send(
            ScholiumAppBridgeRequest(
                mcpRequest: request
            ))
        guard let bridgeResponse = response.mcpResponse,
            bridgeResponse.schemaVersion == ScholiumMCPBridgeResponse.currentSchemaVersion,
            bridgeResponse.requestID == request.requestID,
            (bridgeResponse.result == nil) != (bridgeResponse.error == nil)
        else {
            throw ScholiumAppBridgeError.outcomeUnknown
        }
        if let error = bridgeResponse.error { throw error }
        guard let result = bridgeResponse.result else {
            throw ScholiumAppBridgeError.outcomeUnknown
        }
        return result
    }
}
