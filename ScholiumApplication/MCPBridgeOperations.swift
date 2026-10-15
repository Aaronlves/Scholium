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

    public func callZotero(_ request: ScholiumZoteroBridgeRequest) throws -> MCPJSONValue {
        let response = try client.send(.init(zoteroRequest: request))
        guard response.mcpResponse == nil,
            let result = response.zoteroResponse, let fields = result.objectValue,
            Set(fields.keys).isSubset(of: ["jsonrpc", "id", "result", "error"]),
            fields["jsonrpc"] == .string("2.0"), fields["id"] == request.request.objectValue?["id"],
            (fields["result"] == nil) != (fields["error"] == nil),
            Self.validZoteroOutcome(fields)
        else { throw ScholiumAppBridgeError.outcomeUnknown }
        return result
    }

    private static func validZoteroOutcome(_ fields: [String: MCPJSONValue]) -> Bool {
        if let error = fields["error"] {
            guard let object = error.objectValue else { return false }
            return object["code"]?.intValue != nil && object["message"]?.stringValue != nil
        }
        guard let result = fields["result"]?.objectValue, let content = result["content"]?.arrayValue,
            // Every managed Zotero operation retains public tool output. An
            // empty confirmation cannot establish its operation's outcome.
            !content.isEmpty, content.allSatisfy(validContentBlock),
            result["isError"] == nil || result["isError"]?.boolValue != nil,
            result["structuredContent"] == nil || result["structuredContent"]?.objectValue != nil,
            validOptionalObject(result, key: "_meta")
        else { return false }
        return true
    }

    private static func validContentBlock(_ value: MCPJSONValue) -> Bool {
        guard let block = value.objectValue, let type = block["type"]?.stringValue,
            validOptionalObject(block, key: "annotations"), validOptionalObject(block, key: "_meta")
        else { return false }
        switch type {
        case "text": return block["text"]?.stringValue != nil
        case "image", "audio": return block["data"]?.stringValue != nil && block["mimeType"]?.stringValue != nil
        case "resource_link": return block["uri"]?.stringValue != nil && block["name"]?.stringValue != nil
        case "resource":
            guard let resource = block["resource"]?.objectValue, resource["uri"]?.stringValue != nil,
                resource["mimeType"] == nil || resource["mimeType"]?.stringValue != nil,
                validOptionalObject(resource, key: "_meta")
            else { return false }
            let text = resource["text"]?.stringValue
            let blob = resource["blob"]?.stringValue
            return (text != nil && resource["blob"] == nil) || (blob != nil && resource["text"] == nil)
        default: return false
        }
    }

    private static func validOptionalObject(_ fields: [String: MCPJSONValue], key: String) -> Bool {
        fields[key] == nil || fields[key]?.objectValue != nil
    }
}

enum ZoteroMCPBridgeReply {
    static func failure(request: MCPJSONValue, code: String, message: String, uncertain: Bool = false) -> MCPJSONValue {
        let details: MCPJSONValue = .object([
            "status": .string(uncertain ? "outcome_uncertain" : "failed"),
            "error_code": .string(code), "error": .string(message),
        ])
        let text = (try? JSONEncoder().encode(details)).map { String(decoding: $0, as: UTF8.self) } ?? message
        return .object([
            "jsonrpc": .string("2.0"), "id": request.objectValue?["id"] ?? .null,
            "result": .object([
                "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
                "structuredContent": details, "isError": .bool(true),
            ]),
        ])
    }
}
