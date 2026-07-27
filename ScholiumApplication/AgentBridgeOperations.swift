import Foundation
import ScholiumContracts

public actor AgentBridgeOperations: AgentBridgeUseCases {
    private let client: LocalAgentBridgeClient

    public init(applicationSupportURL: URL) throws {
        client = try LocalAgentBridgeClient(
            applicationSupportURL: applicationSupportURL
        )
    }

    public func handle(requestData: Data) -> Data? {
        let decoded: Any
        do {
            decoded = try JSONSerialization.jsonObject(
                with: requestData,
                options: [.fragmentsAllowed]
            )
        } catch {
            return response(
                id: NSNull(),
                errorCode: -32700,
                message: "Invalid JSON-RPC payload."
            )
        }
        guard let object = decoded as? [String: Any] else {
            return response(
                id: NSNull(),
                errorCode: -32600,
                message: "Invalid JSON-RPC request."
            )
        }
        guard object["jsonrpc"] as? String == "2.0",
              let method = object["method"] as? String else {
            return response(
                id: object["id"] ?? NSNull(),
                errorCode: -32600,
                message: "Invalid JSON-RPC request."
            )
        }
        guard let id = object["id"] else { return nil }
        switch method {
        case "initialize":
            return response(id: id, result: [
                "protocolVersion": "2025-06-18",
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "scholium-agent", "version": "1"],
            ])
        case "ping":
            return response(id: id, result: [:])
        case "tools/list":
            return response(id: id, result: ["tools": tools])
        case "tools/call":
            return response(id: id, result: callTool(object["params"]))
        default:
            return response(
                id: id,
                errorCode: -32601,
                message: "Unsupported MCP method."
            )
        }
    }

    private func callTool(_ rawParameters: Any?) -> [String: Any] {
        do {
            guard let parameters = rawParameters as? [String: Any],
                  Set(parameters.keys).isSubset(of: ["name", "arguments"]),
                  let name = parameters["name"] as? String else {
                throw AgentMCPError.invalidArguments
            }
            let arguments = parameters["arguments"] as? [String: Any] ?? [:]
            let request = try bridgeRequest(tool: name, arguments: arguments)
            let record = try client.send(request).record
            guard let record else { throw AgentMCPError.invalidResponse }
            let recordData = try encode(record)
            guard let structured = try JSONSerialization.jsonObject(
                with: recordData
            ) as? [String: Any] else {
                throw AgentMCPError.invalidResponse
            }
            return [
                "content": [[
                    "type": "text",
                    "text": String(decoding: recordData, as: UTF8.self),
                ]],
                "structuredContent": structured,
                "isError": false,
            ]
        } catch {
            let payload: LocalAgentBridgeErrorPayload
            if let bridgeError = error as? LocalAgentBridgeError,
               case .remote(let remote) = bridgeError {
                payload = remote
            } else if error is AgentMCPError {
                payload = LocalAgentBridgeErrorPayload(
                    code: .invalidRequest,
                    message: "The Scholium Agent request was invalid."
                )
            } else {
                payload = LocalAgentBridgeWireCoding.errorPayload(error)
            }
            return [
                "content": [["type": "text", "text": payload.message]],
                "structuredContent": [
                    "error": [
                        "code": payload.code.rawValue,
                        "message": payload.message,
                    ],
                ],
                "isError": true,
            ]
        }
    }

    private func bridgeRequest(
        tool: String,
        arguments: [String: Any]
    ) throws -> LocalAgentBridgeRequest {
        guard let triptychValue = arguments["triptych_id"] as? String,
              let triptychID = UUID(uuidString: triptychValue),
              let key = arguments["coordination_key"] as? String else {
            throw AgentMCPError.invalidArguments
        }
        switch tool {
        case "request_note_changes":
            guard Set(arguments.keys) == [
                "triptych_id", "coordination_key", "request",
            ], let requestObject = arguments["request"] as? [String: Any] else {
                throw AgentMCPError.invalidArguments
            }
            let requestData = try JSONSerialization.data(
                withJSONObject: requestObject,
                options: [.sortedKeys]
            )
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .deferredToDate
            let request = try decoder.decode(
                AgentNoteChangeRequest.self,
                from: requestData
            )
            return try LocalAgentBridgeRequest(
                operation: .submit,
                triptychID: triptychID,
                coordinationKey: key,
                changeRequest: request
            )
        case "show_note_change_request", "cancel_note_change_request":
            guard Set(arguments.keys) == [
                "triptych_id", "coordination_key", "request_id",
            ], let requestValue = arguments["request_id"] as? String,
            let requestID = UUID(uuidString: requestValue) else {
                throw AgentMCPError.invalidArguments
            }
            return try LocalAgentBridgeRequest(
                operation: tool == "show_note_change_request" ? .status : .cancel,
                triptychID: triptychID,
                coordinationKey: key,
                changeRequestID: requestID
            )
        default:
            throw AgentMCPError.unknownTool
        }
    }

    private func encode(_ record: AgentNoteChangeRequestRecord) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(record)
    }

    private func response(
        id: Any,
        result: Any? = nil,
        errorCode: Int? = nil,
        message: String? = nil
    ) -> Data? {
        var object: [String: Any] = ["jsonrpc": "2.0", "id": id]
        if let errorCode {
            object["error"] = [
                "code": errorCode,
                "message": message ?? "MCP request failed.",
            ]
        } else {
            object["result"] = result ?? [:]
        }
        return try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
    }

    private var tools: [[String: Any]] { [
        tool(
            name: "request_note_changes",
            description: "Submit one bounded request for Scholium to consider additional Note changes.",
            properties: [
                "triptych_id": ["type": "string", "format": "uuid"],
                "coordination_key": ["type": "string"],
                "request": ["type": "object"],
            ]
        ),
        tool(
            name: "show_note_change_request",
            description: "Read the current status of an existing request without creating another request.",
            properties: commonStatusProperties
        ),
        tool(
            name: "cancel_note_change_request",
            description: "Cancel an unresolved request without modifying any Note.",
            properties: commonStatusProperties
        ),
    ] }

    private var commonStatusProperties: [String: Any] { [
        "triptych_id": ["type": "string", "format": "uuid"],
        "coordination_key": ["type": "string"],
        "request_id": ["type": "string", "format": "uuid"],
    ] }

    private func tool(
        name: String,
        description: String,
        properties: [String: Any]
    ) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": [
                "type": "object",
                "additionalProperties": false,
                "properties": properties,
                "required": Array(properties.keys).sorted(),
            ],
        ]
    }
}

private enum AgentMCPError: Error {
    case invalidArguments
    case invalidResponse
    case unknownTool
}
