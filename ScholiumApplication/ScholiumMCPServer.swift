import Foundation
import ScholiumContracts

/// Local stdio MCP protocol owner. Tool execution is delegated verbatim to
/// the current-user authenticated App bridge; this process never opens a
/// Triptych or reads its filesystem directly.
public actor ScholiumMCPServer {
    public static let protocolVersion = "2025-11-25"
    public static let serverName = "scholium"
    public static let serverVersion = ScholiumProductIdentity.marketingVersion

    private let callBridge: @Sendable (ScholiumMCPBridgeRequest) async throws
        -> MCPJSONValue

    public init(bridge: MCPBridgeOperations) {
        callBridge = { request in
            try await bridge.call(request)
        }
    }

    public init(
        handler: @escaping @Sendable (ScholiumMCPBridgeRequest) async throws
            -> MCPJSONValue
    ) {
        callBridge = handler
    }

    public func handle(requestData: Data) async -> Data? {
        let request: RPCRequest
        do {
            request = try JSONDecoder().decode(RPCRequest.self, from: requestData)
        } catch {
            return encode(responseError(
                id: .null,
                code: -32700,
                message: "Invalid JSON-RPC payload."
            ))
        }
        guard let id = request.id else { return nil }
        guard request.jsonrpc == "2.0", !request.method.isEmpty else {
            return encode(responseError(
                id: id,
                code: -32600,
                message: "Invalid JSON-RPC request."
            ))
        }

        switch request.method {
        case "initialize":
            let requested = request.params?.objectValue?["protocolVersion"]?.stringValue
            let selected = [Self.protocolVersion, "2024-11-05"].contains(requested)
                ? requested!
                : Self.protocolVersion
            return encode(responseResult(id: id, result: .object([
                "protocolVersion": .string(selected),
                "capabilities": .object(["tools": .object([:])]),
                "serverInfo": .object([
                    "name": .string(Self.serverName),
                    "version": .string(Self.serverVersion),
                ]),
                "instructions": .string(
                    "Begin with scholium_workspace_status. Markdown source is authoritative. Search, Metadata, and links are retrieval aids. Mutations require current fingerprints. Tool availability is not permission; act only on the researcher's explicit instruction."
                ),
            ])))
        case "ping":
            return encode(responseResult(id: id, result: .object([:])))
        case "tools/list":
            return encode(responseResult(id: id, result: .object([
                "tools": .array(Self.toolDefinitions),
            ])))
        case "tools/call":
            return encode(responseResult(
                id: id,
                result: await callTool(params: request.params)
            ))
        default:
            return encode(responseError(
                id: id,
                code: -32601,
                message: "Unsupported MCP method."
            ))
        }
    }

    private func callTool(params: MCPJSONValue?) async -> MCPJSONValue {
        do {
            guard let params = params?.objectValue,
                  let rawName = params["name"]?.stringValue,
                  let tool = ScholiumMCPToolName(rawValue: rawName) else {
                throw ScholiumMCPFailure(
                    code: .invalidRequest,
                    message: "The requested Scholium MCP tool is unknown.",
                    recovery: "Call tools/list and use one of the ten published tool names."
                )
            }
            let arguments: [String: MCPJSONValue]
            if let value = params["arguments"] {
                guard let object = value.objectValue else {
                    throw ScholiumMCPFailure(
                        code: .invalidRequest,
                        message: "Tool arguments must be one JSON object.",
                        recovery: "Send the object defined by the selected tool schema."
                    )
                }
                arguments = object
            } else {
                arguments = [:]
            }
            let result = try await callBridge(ScholiumMCPBridgeRequest(
                tool: tool,
                arguments: arguments
            ))
            return toolResult(result, isError: false)
        } catch let failure as ScholiumMCPFailure {
            return toolResult(failureValue(failure), isError: true)
        } catch let error as ScholiumAppBridgeError {
            let failure: ScholiumMCPFailure
            switch error {
            case .unavailable:
                failure = ScholiumMCPFailure(
                    code: .appUnavailable,
                    message: "The Scholium App bridge is unavailable.",
                    recovery: "Launch Scholium, open a Triptych, and call workspace status again."
                )
            case .outcomeUnknown, .timeout:
                failure = ScholiumMCPFailure(
                    code: .operationUncertain,
                    message: "The App bridge could not determine the operation outcome.",
                    recovery: "Do not retry automatically. Recheck workspace status and the target identity, path, and fingerprint."
                )
            default:
                failure = ScholiumMCPFailure(
                    code: .internalError,
                    message: "The local Scholium App bridge failed.",
                    recovery: "Restart Scholium and begin again with workspace status."
                )
            }
            return toolResult(failureValue(failure), isError: true)
        } catch {
            return toolResult(failureValue(ScholiumMCPFailure(
                code: .internalError,
                message: "The local Scholium MCP adapter failed.",
                recovery: "Restart Scholium and begin again with workspace status."
            )), isError: true)
        }
    }

    private func toolResult(_ value: MCPJSONValue, isError: Bool) -> MCPJSONValue {
        .object([
            "content": .array([.object([
                "type": .string("text"),
                "text": .string(Self.jsonString(value)),
            ])]),
            "structuredContent": value,
            "isError": .bool(isError),
        ])
    }

    private func failureValue(_ failure: ScholiumMCPFailure) -> MCPJSONValue {
        .object([
            "schema_version": .integer(failure.schemaVersion),
            "status": .string(failure.status),
            "code": .string(failure.code.rawValue),
            "message": .string(failure.message),
            "recovery": .string(failure.recovery),
        ])
    }

    private func responseResult(id: MCPJSONValue, result: MCPJSONValue)
        -> RPCResponse
    {
        RPCResponse(jsonrpc: "2.0", id: id, result: result, error: nil)
    }

    private func responseError(
        id: MCPJSONValue,
        code: Int,
        message: String
    ) -> RPCResponse {
        RPCResponse(
            jsonrpc: "2.0",
            id: id,
            result: nil,
            error: RPCError(code: code, message: message)
        )
    }

    private func encode(_ response: RPCResponse) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(response)
    }

    private static func jsonString(_ value: MCPJSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? String(decoding: encoder.encode(value), as: UTF8.self)) ?? "{}"
    }

    private struct RPCRequest: Codable {
        let jsonrpc: String
        let id: MCPJSONValue?
        let method: String
        let params: MCPJSONValue?
    }

    private struct RPCResponse: Codable {
        let jsonrpc: String
        let id: MCPJSONValue
        let result: MCPJSONValue?
        let error: RPCError?
    }

    private struct RPCError: Codable {
        let code: Int
        let message: String
    }

    private static let toolDefinitions: [MCPJSONValue] = [
        tool(
            .workspaceStatus,
            description: "Reconcile and report the running App's currently open Triptych state.",
            properties: [
                "triptych_id": stringSchema("Optional open Triptych UUID."),
            ],
            required: [],
            readOnly: true,
            destructive: false,
            idempotent: true
        ),
        tool(
            .search,
            description: "Search current Notes and Research Records through Scholium's provider-separated Search.",
            properties: [
                "triptych_id": uuidSchema("Open Triptych UUID."),
                "query": stringSchema("Canonical Scholium Search query."),
                "providers": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("string"),
                        "enum": .array([.string("note"), .string("record")]),
                    ]),
                    "uniqueItems": .bool(true),
                    "minItems": .integer(1),
                    "maxItems": .integer(2),
                ]),
                "roles": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("string"),
                        "enum": .array(["analyses", "topics", "works"].map(MCPJSONValue.string)),
                    ]),
                    "uniqueItems": .bool(true),
                    "minItems": .integer(1),
                    "maxItems": .integer(3),
                ]),
                "note_limit": integerSchema(minimum: 1, maximum: 100, default: 20),
                "note_offset": integerSchema(minimum: 0, maximum: nil, default: 0),
                "record_limit": integerSchema(minimum: 1, maximum: 100, default: 20),
                "record_offset": integerSchema(minimum: 0, maximum: nil, default: 0),
            ],
            required: ["triptych_id", "query"],
            readOnly: true,
            destructive: false,
            idempotent: true
        ),
        tool(
            .readNote,
            description: "Read an exact current Markdown source slice by stable Note UUID.",
            properties: [
                "triptych_id": uuidSchema("Open Triptych UUID."),
                "note_id": uuidSchema("Stable Note UUID."),
                "start_line": integerSchema(minimum: 1, maximum: nil, default: 1),
                "line_count": integerSchema(minimum: 1, maximum: 1_000, default: 200),
            ],
            required: ["triptych_id", "note_id"],
            readOnly: true,
            destructive: false,
            idempotent: true
        ),
        tool(
            .readRecord,
            description: "Read one strict attributed Research Record with bounded step pagination.",
            properties: [
                "triptych_id": uuidSchema("Open Triptych UUID."),
                "record_id": uuidSchema("Research Record UUID."),
                "step_offset": integerSchema(minimum: 0, maximum: nil, default: 0),
                "step_limit": integerSchema(minimum: 1, maximum: 100, default: 20),
            ],
            required: ["triptych_id", "record_id"],
            readOnly: true,
            destructive: false,
            idempotent: true
        ),
        tool(
            .listLinks,
            description: "List authored incoming or outgoing link occurrences with source-owned annotations and exact locators.",
            properties: [
                "triptych_id": uuidSchema("Open Triptych UUID."),
                "note_id": uuidSchema("Stable Note UUID."),
                "direction": .object([
                    "type": .string("string"),
                    "enum": .array([.string("incoming"), .string("outgoing")]),
                ]),
                "limit": integerSchema(minimum: 1, maximum: 100, default: 100),
                "offset": integerSchema(minimum: 0, maximum: nil, default: 0),
            ],
            required: ["triptych_id", "note_id", "direction"],
            readOnly: true,
            destructive: false,
            idempotent: true
        ),
        tool(
            .createNote,
            description: "Create one exact Markdown Note inside one selected role vault.",
            properties: [
                "triptych_id": uuidSchema("Open Triptych UUID."),
                "role": roleSchema,
                "relative_path": stringSchema("Exact vault-relative .md path."),
                "body": stringSchema("Exact Markdown body without frontmatter."),
                "summary": stringSchema("Optional authored YAML summary."),
                "keywords": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "uniqueItems": .bool(true),
                ]),
            ],
            required: ["triptych_id", "role", "relative_path", "body"],
            readOnly: false,
            destructive: false,
            idempotent: false
        ),
        tool(
            .updateNote,
            description: "Revision-check and update one Note body or complete source.",
            properties: [
                "triptych_id": uuidSchema("Open Triptych UUID."),
                "note_id": uuidSchema("Stable Note UUID."),
                "expected_fingerprint": fingerprintSchema,
                "mode": .object([
                    "type": .string("string"),
                    "enum": .array([.string("body"), .string("source")]),
                ]),
                "content": stringSchema("Replacement body or complete source."),
            ],
            required: [
                "triptych_id", "note_id", "expected_fingerprint", "mode", "content",
            ],
            readOnly: false,
            destructive: true,
            idempotent: false
        ),
        tool(
            .trashNote,
            description: "Move one exact current Note to macOS system Trash.",
            properties: [
                "triptych_id": uuidSchema("Open Triptych UUID."),
                "note_id": uuidSchema("Stable Note UUID."),
                "expected_fingerprint": fingerprintSchema,
            ],
            required: ["triptych_id", "note_id", "expected_fingerprint"],
            readOnly: false,
            destructive: true,
            idempotent: false
        ),
        tool(
            .recordProgress,
            description: "Create a continuing inquiry Record or append one attributed substantive step.",
            properties: [
                "triptych_id": uuidSchema("Open Triptych UUID."),
                "target": recordProgressTargetSchema,
                "agent_label": stringSchema("External Agent display label."),
                "body_markdown": stringSchema("Complete substantive step Markdown."),
                "revises_step_ids": uuidArraySchema,
                "note_references": noteReferenceArraySchema,
            ],
            required: ["triptych_id", "target", "agent_label", "body_markdown"],
            readOnly: false,
            destructive: false,
            idempotent: false
        ),
        tool(
            .correctRecordStep,
            description: "Append one attributed clerical correction without rewriting Record history.",
            properties: [
                "triptych_id": uuidSchema("Open Triptych UUID."),
                "record_id": uuidSchema("Research Record UUID."),
                "step_id": uuidSchema("Step UUID."),
                "expected_fingerprint": fingerprintSchema,
                "agent_label": stringSchema("External Agent display label."),
                "body_markdown": stringSchema("Complete corrected step Markdown."),
                "revises_step_ids": uuidArraySchema,
                "note_references": noteReferenceArraySchema,
            ],
            required: [
                "triptych_id", "record_id", "step_id", "expected_fingerprint",
                "agent_label", "body_markdown",
            ],
            readOnly: false,
            destructive: false,
            idempotent: false
        ),
    ]

    private static func tool(
        _ name: ScholiumMCPToolName,
        description: String,
        properties: [String: MCPJSONValue],
        required: [String],
        readOnly: Bool,
        destructive: Bool,
        idempotent: Bool
    ) -> MCPJSONValue {
        .object([
            "name": .string(name.rawValue),
            "description": .string(description),
            "inputSchema": .object([
                "type": .string("object"),
                "properties": .object(properties),
                "required": .array(required.map(MCPJSONValue.string)),
                "additionalProperties": .bool(false),
            ]),
            "outputSchema": outputSchema(for: name),
            "annotations": .object([
                "readOnlyHint": .bool(readOnly),
                "destructiveHint": .bool(destructive),
                "idempotentHint": .bool(idempotent),
                "openWorldHint": .bool(false),
            ]),
        ])
    }

    private static func stringSchema(_ description: String) -> MCPJSONValue {
        .object([
            "type": .string("string"),
            "description": .string(description),
        ])
    }

    private static func uuidSchema(_ description: String) -> MCPJSONValue {
        .object([
            "type": .string("string"),
            "format": .string("uuid"),
            "description": .string(description),
        ])
    }

    private static func integerSchema(
        minimum: Int,
        maximum: Int?,
        default defaultValue: Int
    ) -> MCPJSONValue {
        var value: [String: MCPJSONValue] = [
            "type": .string("integer"),
            "minimum": .integer(minimum),
            "default": .integer(defaultValue),
        ]
        if let maximum { value["maximum"] = .integer(maximum) }
        return .object(value)
    }

    private static let roleSchema: MCPJSONValue = .object([
        "type": .string("string"),
        "enum": .array(["analyses", "topics", "works"].map(MCPJSONValue.string)),
    ])

    private static let fingerprintSchema: MCPJSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "sha256": .object([
                "type": .string("string"),
                "pattern": .string("^[0-9a-f]{64}$"),
            ]),
            "byte_count": .object([
                "type": .string("integer"),
                "minimum": .integer(0),
            ]),
        ]),
        "required": .array([.string("sha256"), .string("byte_count")]),
        "additionalProperties": .bool(false),
    ])

    private static let uuidArraySchema: MCPJSONValue = .object([
        "type": .string("array"),
        "items": uuidSchema("UUID."),
        "uniqueItems": .bool(true),
    ])

    private static let noteReferenceSchema = closedObject(
        properties: [
            "note_id": uuidSchema("Stable Note UUID."),
            "relation": .object([
                "type": .string("string"),
                "enum": .array([.string("basis"), .string("modified")]),
            ]),
            "revision": fingerprintSchema,
        ],
        required: ["note_id", "relation", "revision"]
    )

    private static let noteReferenceArraySchema = arraySchema(noteReferenceSchema)

    private static let recordProgressTargetSchema: MCPJSONValue = .object([
        "oneOf": .array([
            closedObject(
                properties: [
                    "kind": .object([
                        "type": .string("string"),
                        "const": .string("new"),
                    ]),
                    "question": simpleSchema("string"),
                ],
                required: ["kind", "question"]
            ),
            closedObject(
                properties: [
                    "kind": .object([
                        "type": .string("string"),
                        "const": .string("existing"),
                    ]),
                    "record_id": uuidSchema("Research Record UUID."),
                    "expected_fingerprint": fingerprintSchema,
                    "replacement_question": nullable(simpleSchema("string")),
                ],
                required: [
                    "kind", "record_id", "expected_fingerprint",
                ]
            ),
        ]),
    ])

    private static let noteSearchGroupSchema = closedObject(
        properties: [
            "freshness": simpleSchema("string"),
            "offset": nonnegativeIntegerSchema,
            "limit": nonnegativeIntegerSchema,
            "total": nullable(nonnegativeIntegerSchema),
            "has_more": booleanSchema,
            "results": arraySchema(closedObject(
                properties: [
                    "note_id": nullable(uuidSchema("Stable Note UUID.")),
                    "role": roleSchema,
                    "relative_path": simpleSchema("string"),
                    "title": simpleSchema("string"),
                    "fingerprint": fingerprintSchema,
                    "match_reason": simpleSchema("string"),
                    "rank_reason": simpleSchema("string"),
                    "snippet": simpleSchema("string"),
                    "source_locator": nullable(locatorSchema),
                ],
                required: [
                    "note_id", "role", "relative_path", "title",
                    "fingerprint", "match_reason", "rank_reason",
                    "snippet", "source_locator",
                ]
            )),
        ],
        required: [
            "freshness", "offset", "limit", "total", "has_more", "results",
        ]
    )

    private static let recordSearchGroupSchema = closedObject(
        properties: [
            "generation": closedObject(
                properties: [
                    "sequence": nonnegativeIntegerSchema,
                    "manifest_sha256": simpleSchema("string"),
                    "record_count": nonnegativeIntegerSchema,
                ],
                required: ["sequence", "manifest_sha256", "record_count"]
            ),
            "offset": nonnegativeIntegerSchema,
            "limit": nonnegativeIntegerSchema,
            "total": nonnegativeIntegerSchema,
            "has_more": booleanSchema,
            "isolated_issue_count": nonnegativeIntegerSchema,
            "results": arraySchema(closedObject(
                properties: [
                    "record_id": uuidSchema("Research Record UUID."),
                    "question": simpleSchema("string"),
                    "last_substantive_at": simpleSchema("string"),
                    "fingerprint": fingerprintSchema,
                    "matched_field": simpleSchema("string"),
                    "matched_step_id": nullable(uuidSchema("Matched step UUID.")),
                    "rank_reason": simpleSchema("string"),
                    "snippet": simpleSchema("string"),
                ],
                required: [
                    "record_id", "question", "last_substantive_at",
                    "fingerprint", "matched_field", "matched_step_id",
                    "rank_reason", "snippet",
                ]
            )),
        ],
        required: [
            "generation", "offset", "limit", "total", "has_more",
            "isolated_issue_count", "results",
        ]
    )

    private static let recordStepSchema = closedObject(
        properties: [
            "step_id": uuidSchema("Step UUID."),
            "recorded_at": simpleSchema("string"),
            "submitted_by": simpleSchema("string"),
            "original_body_markdown": simpleSchema("string"),
            "body_markdown": simpleSchema("string"),
            "revises_step_ids": uuidArraySchema,
            "note_references": noteReferenceArraySchema,
            "corrections": arraySchema(closedObject(
                properties: [
                    "correction_id": uuidSchema("Correction UUID."),
                    "corrected_at": simpleSchema("string"),
                    "submitted_by": simpleSchema("string"),
                    "body_markdown": simpleSchema("string"),
                    "revises_step_ids": uuidArraySchema,
                    "note_references": noteReferenceArraySchema,
                ],
                required: [
                    "correction_id", "corrected_at", "submitted_by",
                    "body_markdown", "revises_step_ids", "note_references",
                ]
            )),
        ],
        required: [
            "step_id", "recorded_at", "submitted_by",
            "original_body_markdown", "body_markdown", "revises_step_ids",
            "note_references", "corrections",
        ]
    )

    private static func outputSchema(
        for tool: ScholiumMCPToolName
    ) -> MCPJSONValue {
        let successes: [MCPJSONValue] = switch tool {
        case .workspaceStatus:
            [
                successSchema(
                    properties: [
                        "current": booleanSchema,
                        "selection_required": booleanSchema,
                        "triptychs": arraySchema(closedObject(
                            properties: [
                                "triptych_id": uuidSchema("Open Triptych UUID."),
                                "name": simpleSchema("string"),
                            ],
                            required: ["triptych_id", "name"]
                        )),
                    ],
                    required: ["current", "selection_required", "triptychs"]
                ),
                successSchema(
                    properties: [
                        "current": booleanSchema,
                        "selection_required": booleanSchema,
                        "triptych_id": uuidSchema("Open Triptych UUID."),
                        "name": simpleSchema("string"),
                        "source_generation": generationSchema(
                            includesCount: true
                        ),
                        "search_generation": generationSchema(
                            includesCount: false
                        ),
                        "record_search_generation": closedObject(
                            properties: [
                                "sequence": nonnegativeIntegerSchema,
                                "manifest_sha256": simpleSchema("string"),
                                "record_count": nonnegativeIntegerSchema,
                            ],
                            required: [
                                "sequence", "manifest_sha256", "record_count",
                            ]
                        ),
                        "graph_generation": generationSchema(
                            includesCount: false
                        ),
                        "vaults": arraySchema(closedObject(
                            properties: [
                                "role": roleSchema,
                                "vault_id": uuidSchema("Vault UUID."),
                                "note_count": nonnegativeIntegerSchema,
                            ],
                            required: ["role", "vault_id", "note_count"]
                        )),
                    ],
                    required: [
                        "current", "selection_required", "triptych_id", "name",
                        "source_generation", "search_generation",
                        "record_search_generation", "graph_generation", "vaults",
                    ]
                ),
            ]
        case .search:
            [successSchema(
                properties: [
                    "triptych_id": uuidSchema("Open Triptych UUID."),
                    "query": simpleSchema("string"),
                    "notes": nullable(noteSearchGroupSchema),
                    "records": nullable(recordSearchGroupSchema),
                ],
                required: ["triptych_id", "query", "notes", "records"]
            )]
        case .readNote:
            [successSchema(
                properties: [
                    "triptych_id": uuidSchema("Open Triptych UUID."),
                    "note_id": uuidSchema("Stable Note UUID."),
                    "role": roleSchema,
                    "relative_path": simpleSchema("string"),
                    "fingerprint": fingerprintSchema,
                    "start_line": nonnegativeIntegerSchema,
                    "line_count": nonnegativeIntegerSchema,
                    "source": simpleSchema("string"),
                    "complete": booleanSchema,
                    "next_line": nullable(nonnegativeIntegerSchema),
                ],
                required: [
                    "triptych_id", "note_id", "role", "relative_path",
                    "fingerprint", "start_line", "line_count", "source",
                    "complete", "next_line",
                ]
            )]
        case .readRecord:
            [successSchema(
                properties: [
                    "triptych_id": uuidSchema("Open Triptych UUID."),
                    "record_id": uuidSchema("Research Record UUID."),
                    "question": simpleSchema("string"),
                    "fingerprint": fingerprintSchema,
                    "step_offset": nonnegativeIntegerSchema,
                    "step_limit": nonnegativeIntegerSchema,
                    "total_steps": nonnegativeIntegerSchema,
                    "has_more": booleanSchema,
                    "steps": arraySchema(recordStepSchema),
                ],
                required: [
                    "triptych_id", "record_id", "question", "fingerprint",
                    "step_offset", "step_limit", "total_steps", "has_more",
                    "steps",
                ]
            )]
        case .listLinks:
            [successSchema(
                properties: [
                    "triptych_id": uuidSchema("Open Triptych UUID."),
                    "note_id": uuidSchema("Stable Note UUID."),
                    "direction": simpleSchema("string"),
                    "graph_generation": nullable(nonnegativeIntegerSchema),
                    "offset": nonnegativeIntegerSchema,
                    "limit": nonnegativeIntegerSchema,
                    "has_more": booleanSchema,
                    "links": arraySchema(closedObject(
                        properties: [
                            "occurrence_direction": .object([
                                "type": .string("string"),
                                "enum": .array([.string("outgoing")]),
                            ]),
                            "source_note_id": nullable(uuidSchema("Stable Note UUID.")),
                            "destination_note_id": nullable(uuidSchema("Stable Note UUID.")),
                            "source_role": .object([
                                "type": .string("string"),
                                "enum": .array([
                                    .string("analyses"), .string("topics"),
                                    .string("works"), .string("unsupported"),
                                ]),
                            ]),
                            "source_relative_path": simpleSchema("string"),
                            "destination_role": nullable(roleSchema),
                            "destination_relative_path": nullable(simpleSchema("string")),
                            "occurrence_markup": simpleSchema("string"),
                            "link_markup": simpleSchema("string"),
                            "annotation_markup": nullable(simpleSchema("string")),
                            "annotation_text": nullable(simpleSchema("string")),
                            "authored_target": simpleSchema("string"),
                            "local_context": simpleSchema("string"),
                            "source_fingerprint": fingerprintSchema,
                            "source_locator": locatorSchema,
                            "link_locator": locatorSchema,
                            "annotation_locator": nullable(locatorSchema),
                        ],
                        required: [
                            "occurrence_direction",
                            "source_note_id", "destination_note_id",
                            "source_role", "source_relative_path",
                            "destination_role", "destination_relative_path",
                            "occurrence_markup", "link_markup",
                            "annotation_markup", "annotation_text",
                            "authored_target", "local_context",
                            "source_fingerprint", "source_locator",
                            "link_locator", "annotation_locator",
                        ]
                    )),
                ],
                required: [
                    "triptych_id", "note_id", "direction", "graph_generation",
                    "offset", "limit", "has_more", "links",
                ]
            )]
        case .createNote:
            [successSchema(
                properties: [
                    "triptych_id": uuidSchema("Open Triptych UUID."),
                    "change_id": uuidSchema("Agent Change UUID."),
                    "note_id": uuidSchema("Stable Note UUID."),
                    "role": roleSchema,
                    "relative_path": simpleSchema("string"),
                    "fingerprint": fingerprintSchema,
                ],
                required: [
                    "triptych_id", "change_id", "note_id", "role",
                    "relative_path", "fingerprint",
                ]
            )]
        case .updateNote:
            [successSchema(
                properties: [
                    "triptych_id": uuidSchema("Open Triptych UUID."),
                    "change_id": uuidSchema("Agent Change UUID."),
                    "note_id": uuidSchema("Stable Note UUID."),
                    "relative_path": simpleSchema("string"),
                    "before_fingerprint": fingerprintSchema,
                    "after_fingerprint": fingerprintSchema,
                    "readback_verified": booleanSchema,
                ],
                required: [
                    "triptych_id", "change_id", "note_id", "relative_path",
                    "before_fingerprint", "after_fingerprint",
                    "readback_verified",
                ]
            )]
        case .trashNote:
            [successSchema(
                properties: [
                    "triptych_id": uuidSchema("Open Triptych UUID."),
                    "change_id": uuidSchema("Agent Change UUID."),
                    "note_id": uuidSchema("Stable Note UUID."),
                    "original_location": closedObject(
                        properties: [
                            "role": roleSchema,
                            "relative_path": simpleSchema("string"),
                        ],
                        required: ["role", "relative_path"]
                    ),
                    "moved_to_system_trash": booleanSchema,
                ],
                required: [
                    "triptych_id", "change_id", "note_id",
                    "original_location", "moved_to_system_trash",
                ]
            )]
        case .recordProgress:
            [successSchema(
                properties: [
                    "triptych_id": uuidSchema("Open Triptych UUID."),
                    "branch": simpleSchema("string"),
                    "record_id": uuidSchema("Research Record UUID."),
                    "step_id": uuidSchema("Stored step UUID."),
                    "question": simpleSchema("string"),
                    "fingerprint": fingerprintSchema,
                ],
                required: [
                    "triptych_id", "branch", "record_id", "step_id",
                    "question", "fingerprint",
                ]
            )]
        case .correctRecordStep:
            [successSchema(
                properties: [
                    "triptych_id": uuidSchema("Open Triptych UUID."),
                    "record_id": uuidSchema("Research Record UUID."),
                    "step_id": uuidSchema("Corrected step UUID."),
                    "correction_id": uuidSchema("Appended correction UUID."),
                    "corrected_at": simpleSchema("string"),
                    "body_markdown": simpleSchema("string"),
                    "fingerprint": fingerprintSchema,
                ],
                required: [
                    "triptych_id", "record_id", "step_id", "correction_id",
                    "corrected_at", "body_markdown", "fingerprint",
                ]
            )]
        }
        return .object([
            "oneOf": .array(successes + [failureSchema]),
        ])
    }

    private static func successSchema(
        properties: [String: MCPJSONValue],
        required: [String]
    ) -> MCPJSONValue {
        closedObject(
            properties: properties.merging([
                "schema_version": .object([
                    "type": .string("integer"),
                    "const": .integer(ScholiumMCPContract.currentToolSchemaVersion),
                ]),
                "status": .object([
                    "type": .string("string"),
                    "const": .string("ok"),
                ]),
            ]) { current, _ in current },
            required: ["schema_version", "status"] + required
        )
    }

    private static let failureSchema = closedObject(
        properties: [
            "schema_version": .object([
                "type": .string("integer"),
                "const": .integer(ScholiumMCPContract.currentToolSchemaVersion),
            ]),
            "status": .object([
                "type": .string("string"),
                "const": .string("failed"),
            ]),
            "code": .object([
                "type": .string("string"),
                "enum": .array(
                    ScholiumMCPFailureCode.allCases.map {
                        .string($0.rawValue)
                    }
                ),
            ]),
            "message": simpleSchema("string"),
            "recovery": simpleSchema("string"),
        ],
        required: [
            "schema_version", "status", "code", "message", "recovery",
        ]
    )

    private static func closedObject(
        properties: [String: MCPJSONValue],
        required: [String]
    ) -> MCPJSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map(MCPJSONValue.string)),
            "additionalProperties": .bool(false),
        ])
    }

    private static func arraySchema(_ item: MCPJSONValue) -> MCPJSONValue {
        .object([
            "type": .string("array"),
            "items": item,
        ])
    }

    private static func nullable(_ schema: MCPJSONValue) -> MCPJSONValue {
        .object([
            "anyOf": .array([
                schema,
                .object(["type": .string("null")]),
            ]),
        ])
    }

    private static func simpleSchema(_ type: String) -> MCPJSONValue {
        .object(["type": .string(type)])
    }

    private static let booleanSchema = simpleSchema("boolean")

    private static let nonnegativeIntegerSchema: MCPJSONValue = .object([
        "type": .string("integer"),
        "minimum": .integer(0),
    ])

    private static let locatorSchema = closedObject(
        properties: [
            "line": nonnegativeIntegerSchema,
            "column": nonnegativeIntegerSchema,
            "end_line": nonnegativeIntegerSchema,
            "end_column": nonnegativeIntegerSchema,
        ],
        required: ["line", "column", "end_line", "end_column"]
    )

    private static func generationSchema(
        includesCount: Bool
    ) -> MCPJSONValue {
        var properties: [String: MCPJSONValue] = [
            "manifest_sha256": simpleSchema("string"),
        ]
        var required = ["manifest_sha256"]
        if includesCount {
            properties["note_count"] = nonnegativeIntegerSchema
            required.append("note_count")
        } else {
            properties["sequence"] = nonnegativeIntegerSchema
            required.append("sequence")
        }
        return closedObject(properties: properties, required: required)
    }
}
