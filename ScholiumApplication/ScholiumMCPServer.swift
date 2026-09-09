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
                    recovery: "Call tools/list and use one of the published tool names."
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
            let metadata = params["_meta"]?.objectValue?["x-codex-turn-metadata"]?.objectValue
            let context: ScholiumMCPRuntimeContext?
            if let thread = metadata?["thread_id"]?.stringValue,
               let turn = metadata?["turn_id"]?.stringValue,
               !thread.isEmpty, !turn.isEmpty, thread.utf8.count <= 256, turn.utf8.count <= 256 {
                context = .init(threadID: thread, turnID: turn)
            } else {
                context = nil
            }
            let result = try await callBridge(ScholiumMCPBridgeRequest(
                tool: tool,
                arguments: arguments,
                runtimeContext: context
            ))
            return toolResult(result, isError: false, includesImage: tool == .readAttachment)
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

    private func toolResult(_ value: MCPJSONValue, isError: Bool, includesImage: Bool = false) -> MCPJSONValue {
        var textValue = value
        var imageBlock: MCPJSONValue?
        if includesImage, !isError, let image = value.objectValue?["image"]?.objectValue,
           image["mime_type"]?.stringValue == "image/png", let data = image["data"]?.stringValue {
            imageBlock = .object(["type": .string("image"), "mimeType": .string("image/png"), "data": .string(data)])
            var object = value.objectValue ?? [:]; var metadata = image; metadata["data"] = nil
            object["image"] = .object(metadata); textValue = .object(object)
        }
        var content: [MCPJSONValue] = [.object(["type": .string("text"), "text": .string(Self.jsonString(textValue))])]
        if let imageBlock { content.append(imageBlock) }
        return .object(["content": .array(content), "structuredContent": value, "isError": .bool(isError)])
    }

    private func failureValue(_ failure: ScholiumMCPFailure) -> MCPJSONValue {
        .object([
            "schema_version": .integer(failure.schemaVersion),
            "status": .string(failure.status),
            "code": .string(failure.code.rawValue),
            "message": .string(failure.message),
            "recovery": .string(failure.recovery),
            "recovery_details": failure.recoveryDetails?.jsonValue ?? .null,
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
            .browse,
            description: "Browse role roots or immediate Library directory/Note children without a search query. Continue with the returned listing fingerprint.",
            properties: [
                "triptych_id": uuidSchema("Open Triptych UUID."), "role": roleSchema,
                "directory": stringSchema("Exact vault-relative directory; empty means role root. Requires role."),
                "limit": integerSchema(minimum: 1, maximum: 100, default: 20),
                "offset": integerSchema(minimum: 0, maximum: nil, default: 0),
                "expected_listing_fingerprint": fingerprintSchema,
            ],
            required: ["triptych_id"], readOnly: true, destructive: false, idempotent: true
        ),
        tool(
            .search,
            description: "Search current Notes in the authorized Triptych.",
            properties: [
                "triptych_id": uuidSchema("Open Triptych UUID."),
                "query": stringSchema("Canonical Scholium Search query."),
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
                "limit": integerSchema(minimum: 1, maximum: 100, default: 20),
                "offset": integerSchema(minimum: 0, maximum: nil, default: 0),
            ],
            required: ["triptych_id", "query"],
            readOnly: true,
            destructive: false,
            idempotent: true
        ),
        tool(
            .readNote,
            description: "Read exact Note prose by stable UUID. Set include_context to also inspect saved Metadata, its exact Zotero item binding and the first 20 related attachment pointers. These local records are not fresh Zotero data or proof of reading a paper. Continue attachment listings with scholium_list_attachments; read selected material with the corresponding attachment or Zotero tool.",
            properties: [
                "triptych_id": uuidSchema("Open Triptych UUID."),
                "note_id": uuidSchema("Stable Note UUID."),
                "start_line": integerSchema(minimum: 1, maximum: nil, default: 1),
                "line_count": integerSchema(minimum: 1, maximum: 1_000, default: 200),
                "include_context": .object(["type": .string("boolean"), "default": .bool(false)]),
            ],
            required: ["triptych_id", "note_id"],
            readOnly: true,
            destructive: false,
            idempotent: true
        ),
        tool(.showNote, description: "Display an exact current Note or passage in its existing foreground window. External hosts must name a window from workspace_status; Chat uses its original visible window. Never foregrounds a background task.",
            properties: ["triptych_id": uuidSchema("Open Triptych UUID."), "window_id": uuidSchema("Live window UUID; required outside in-app Chat."),
                "note_id": uuidSchema("Stable Note UUID."), "expected_fingerprint": fingerprintSchema,
                "start_utf8": integerSchema(minimum: 0, maximum: nil, default: 0), "end_utf8": integerSchema(minimum: 1, maximum: nil, default: 1),
                "expected_text": stringSchema("Exact complete text for the requested source range, at most 64 KiB.")],
            required: ["triptych_id", "note_id", "expected_fingerprint"],
            alternatives: [.object(["required": .array(["start_utf8", "end_utf8", "expected_text"].map(MCPJSONValue.string))]),
                .object(["not": .object(["anyOf": .array(["start_utf8", "end_utf8", "expected_text"].map { .object(["required": .array([.string($0)])]) })])])],
            readOnly: false, destructive: false, idempotent: false),
        tool(.listAttachments, description: "List the current Note's document attachments and registered authored images; metadata is not source reading.",
            properties: ["triptych_id": uuidSchema("Open Triptych UUID."), "note_id": uuidSchema("Stable Note UUID."),
                "offset": integerSchema(minimum: 0, maximum: nil, default: 0), "limit": integerSchema(minimum: 1, maximum: 100, default: 20),
                "expected_listing_fingerprint": fingerprintSchema], required: ["triptych_id", "note_id"], readOnly: true, destructive: false, idempotent: true),
        tool(.readAttachment, description: "Read one related current attachment. Text uses exact UTF-8 offsets; PDF reads require one explicit page. Image mode returns a bounded rendered PNG, never OCR.",
            properties: ["triptych_id": uuidSchema("Open Triptych UUID."), "note_id": uuidSchema("Stable Note UUID."),
                "attachment_id": uuidSchema("Attachment UUID from list_attachments."), "expected_note_fingerprint": fingerprintSchema,
                "expected_fingerprint": fingerprintSchema, "mode": .object(["type": .string("string"), "enum": .array([.string("text"), .string("image")])]),
                "page": integerSchema(minimum: 1, maximum: nil, default: 1), "start_utf8": integerSchema(minimum: 0, maximum: nil, default: 0),
                "max_utf8": integerSchema(minimum: 1, maximum: 65_536, default: 16_384)],
            required: ["triptych_id", "note_id", "attachment_id", "expected_note_fingerprint", "mode"], readOnly: true, destructive: false, idempotent: true),
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
            description: "Revision-check one Note: replace body/source or apply exact UTF-8 range edits.",
            properties: [
                "triptych_id": uuidSchema("Open Triptych UUID."),
                "note_id": uuidSchema("Stable Note UUID."),
                "expected_fingerprint": fingerprintSchema,
                "mode": .object([
                    "type": .string("string"),
                    "enum": .array([.string("body"), .string("source"), .string("edits")]),
                ]),
                "content": stringSchema("Replacement body or complete source; omit for edits."),
                "edits": .object([
                    "type": .string("array"), "minItems": .integer(1), "maxItems": .integer(AgentSourceEdit.maximumCount),
                    "items": closedObject(properties: [
                        "start_utf8": .object(["type": .string("integer"), "minimum": .integer(0),
                            "description": .string("Zero-based UTF-8 offset in the complete original source, including BOM and YAML.")]),
                        "end_utf8": .object(["type": .string("integer"), "minimum": .integer(0),
                            "description": .string("Exclusive UTF-8 offset; equal to start_utf8 for insertion.")]),
                        "expected_text": stringSchema("Exact original bytes decoded as text; empty for insertion."),
                        "replacement": stringSchema("Exact replacement; empty for deletion. No newline normalization."),
                    ], required: ["start_utf8", "end_utf8", "expected_text", "replacement"]),
                ]),
            ],
            required: [
                "triptych_id", "note_id", "expected_fingerprint", "mode",
            ],
            alternatives: [
                .object(["properties": .object(["mode": .object(["enum": .array([.string("body"), .string("source")])])]),
                         "required": .array([.string("content")]), "not": .object(["required": .array([.string("edits")])])]),
                .object(["properties": .object(["mode": .object(["const": .string("edits")])]),
                         "required": .array([.string("edits")]), "not": .object(["required": .array([.string("content")])])]),
            ],
            readOnly: false,
            destructive: true,
            idempotent: false
        ),
        tool(.updateMetadata,
            description: "Set or remove selected managed Metadata fields on one Note. Preserve every unmentioned value and all authored text. Read include_context first; supply its Metadata fingerprint, or explicit null for absence. An authorized write returns a reviewable, undoable record change; its ending fingerprint describes Metadata, not Markdown.",
            properties: ["triptych_id": uuidSchema("Open Triptych UUID."), "note_id": uuidSchema("Stable Note UUID."),
                "expected_fingerprint": fingerprintSchema, "expected_metadata_fingerprint": nullable(fingerprintSchema),
                "set": .object(["type": .string("object"), "maxProperties": .integer(128), "additionalProperties": .bool(true)]),
                "remove": .object(["type": .string("array"), "items": simpleSchema("string"), "maxItems": .integer(128), "uniqueItems": .bool(true)])],
            required: ["triptych_id", "note_id", "expected_fingerprint", "expected_metadata_fingerprint"], readOnly: false, destructive: true, idempotent: false),
        tool(.updateAttachment,
            description: "Add, replace or remove a Note's document attachment relationship. Removal preserves files. For add/replace, choose a registered document attachment in this Triptych and supply its listing and file fingerprints from prior reads. Same-vault files are shared; cross-vault or referenced originals are copied from bounded verified bytes. No arbitrary path, URL, original-file overwrite or Markdown image removal is accepted. Returns a reviewable, undoable relationship change; fingerprints describe the relationship record.",
            properties: ["triptych_id": uuidSchema("Open Triptych UUID."), "note_id": uuidSchema("Target Note UUID."),
                "expected_fingerprint": fingerprintSchema, "expected_listing_fingerprint": fingerprintSchema,
                "action": .object(["type": .string("string"), "enum": .array(["add", "replace", "remove"].map(MCPJSONValue.string))]),
                "attachment_id": uuidSchema("New UUID for add; the existing relationship UUID for replace/remove."),
                "source": closedObject(properties: ["note_id": uuidSchema("Source Note UUID."), "attachment_id": uuidSchema("Source document attachment UUID."),
                    "expected_listing_fingerprint": fingerprintSchema, "expected_fingerprint": fingerprintSchema],
                    required: ["note_id", "attachment_id", "expected_listing_fingerprint", "expected_fingerprint"])],
            required: ["triptych_id", "note_id", "expected_fingerprint", "expected_listing_fingerprint", "action", "attachment_id"],
            readOnly: false, destructive: true, idempotent: false),
        tool(.moveNote,
            description: "Execute the exact previously previewed same-vault Note move, preserving identity and recording all linked-source effects. A changed plan is rejected.",
            properties: ["triptych_id": uuidSchema("Open Triptych UUID."), "note_id": uuidSchema("Stable Note UUID."),
                "expected_fingerprint": fingerprintSchema, "relative_path": stringSchema("Exact destination .md path in the same vault."),
                "expected_plan_fingerprint": fingerprintSchema],
            required: ["triptych_id", "note_id", "expected_fingerprint", "relative_path", "expected_plan_fingerprint"],
            readOnly: false, destructive: true, idempotent: false),
        tool(.previewMove,
            description: "Preview a same-role Note rename/move and exact incoming-link effects without changing source. Continue only with the full plan fingerprint.",
            properties: ["triptych_id": uuidSchema("Open Triptych UUID."), "note_id": uuidSchema("Stable Note UUID."),
                "expected_fingerprint": fingerprintSchema, "relative_path": stringSchema("Exact destination .md path in the same vault."),
                "offset": integerSchema(minimum: 0, maximum: nil, default: 0), "limit": integerSchema(minimum: 1, maximum: 100, default: 20),
                "expected_plan_fingerprint": fingerprintSchema], required: ["triptych_id", "note_id", "expected_fingerprint", "relative_path"],
            readOnly: true, destructive: false, idempotent: true),
        tool(.listChanges,
            description: "List exact machine-local Agent Change receipts; history is not current source or mutation permission.",
            properties: ["triptych_id": uuidSchema("Open Triptych UUID."), "note_id": uuidSchema("Optional stable Note UUID."),
                "offset": integerSchema(minimum: 0, maximum: nil, default: 0), "limit": integerSchema(minimum: 1, maximum: 100, default: 20),
                "expected_listing_fingerprint": fingerprintSchema], required: ["triptych_id"], readOnly: true, destructive: false, idempotent: true),
        tool(.readChange,
            description: "Read one retained change and a paged exact source comparison, with current Undo eligibility. No source is changed.",
            properties: ["triptych_id": uuidSchema("Open Triptych UUID."), "change_id": uuidSchema("Exact Agent Change UUID."),
                "note_id": uuidSchema("An affected Note UUID; defaults to the primary Note comparison."),
                "effect_offset": integerSchema(minimum: 0, maximum: nil, default: 0), "effect_limit": integerSchema(minimum: 1, maximum: 100, default: 20),
                "offset": integerSchema(minimum: 0, maximum: nil, default: 0), "limit": integerSchema(minimum: 1, maximum: 1000, default: 200)],
            required: ["triptych_id", "change_id"], readOnly: true, destructive: false, idempotent: true),
        tool(.undoChange,
            description: "Undo only the explicitly requested eligible source, Metadata or attachment-relationship change while its current values equal the recorded ending. Use the receipt ending fingerprint, not a different Note-source fingerprint. Never automatically undo another task or repeat a completed write.",
            properties: ["triptych_id": uuidSchema("Open Triptych UUID."), "note_id": uuidSchema("Stable Note UUID bound to this change."),
                "change_id": uuidSchema("Exact Agent Change UUID."), "expected_fingerprint": fingerprintSchema],
            required: ["triptych_id", "note_id", "change_id", "expected_fingerprint"], readOnly: false, destructive: true, idempotent: false),
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
    ]

    private static func tool(
        _ name: ScholiumMCPToolName,
        description: String,
        properties: [String: MCPJSONValue],
        required: [String],
        alternatives: [MCPJSONValue] = [],
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
            ].merging(alternatives.isEmpty ? [:] : ["oneOf": .array(alternatives)]) { _, value in value }),
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

    private static let moveEffectSchema = closedObject(properties: [
        "note_id": uuidSchema("Affected Note UUID."), "role": roleSchema, "source_relative_path": simpleSchema("string"), "relative_path": simpleSchema("string"),
        "before_fingerprint": fingerprintSchema, "after_fingerprint": fingerprintSchema, "rewritten_occurrences": nonnegativeIntegerSchema,
    ], required: ["note_id", "role", "source_relative_path", "relative_path", "before_fingerprint", "after_fingerprint", "rewritten_occurrences"])

    private static let changeReceiptSchema = closedObject(properties: [
        "change_id": uuidSchema("Agent Change UUID."), "note_id": uuidSchema("Stable Note UUID."), "role": roleSchema,
        "affected_note_count": nonnegativeIntegerSchema,
        "operation": .object(["type": .string("string"), "enum": .array(["create", "update", "trash", "move", "metadata", "attachment"].map(MCPJSONValue.string))]),
        "state": .object(["type": .string("string"), "enum": .array(["prepared", "confirmed", "outcome_uncertain", "undone"].map(MCPJSONValue.string))]),
        "original_relative_path": nullable(simpleSchema("string")), "final_relative_path": nullable(simpleSchema("string")),
        "before_fingerprint": nullable(fingerprintSchema), "after_fingerprint": nullable(fingerprintSchema),
        "created_at": simpleSchema("string"), "confirmed_at": nullable(simpleSchema("string")), "undone_at": nullable(simpleSchema("string")),
    ], required: ["change_id", "note_id", "role", "affected_note_count", "operation", "state", "original_relative_path", "final_relative_path",
                  "before_fingerprint", "after_fingerprint", "created_at", "confirmed_at", "undone_at"])

    private static let changeComparisonSchema = closedObject(properties: [
        "before_fingerprint": fingerprintSchema, "after_fingerprint": fingerprintSchema,
        "before_has_bom": booleanSchema, "after_has_bom": booleanSchema,
        "offset": nonnegativeIntegerSchema, "limit": nonnegativeIntegerSchema, "total": nonnegativeIntegerSchema, "has_more": booleanSchema,
        "rows": arraySchema(closedObject(properties: [
            "kind": .object(["type": .string("string"), "enum": .array(["unchanged", "removed", "added"].map(MCPJSONValue.string))]),
            "before_line": nullable(nonnegativeIntegerSchema), "after_line": nullable(nonnegativeIntegerSchema), "text": simpleSchema("string"),
            "line_ending": .object(["type": .string("string"), "enum": .array(["LF", "CRLF", "None"].map(MCPJSONValue.string))]),
        ], required: ["kind", "before_line", "after_line", "text", "line_ending"])),
    ], required: ["before_fingerprint", "after_fingerprint", "before_has_bom", "after_has_bom", "offset", "limit", "total", "has_more", "rows"])

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
                        "windows": arraySchema(closedObject(properties: ["window_id": uuidSchema("Live window UUID."), "can_display": booleanSchema], required: ["window_id", "can_display"])),
                        "source_generation": generationSchema(
                            includesCount: true
                        ),
                        "search_generation": generationSchema(
                            includesCount: false
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
                        "graph_generation", "vaults", "windows",
                    ]
                ),
            ]
        case .browse:
            [successSchema(properties: [
                "triptych_id": uuidSchema("Open Triptych UUID."), "role": nullable(roleSchema),
                "directory": simpleSchema("string"), "listing_fingerprint": fingerprintSchema,
                "offset": nonnegativeIntegerSchema, "limit": nonnegativeIntegerSchema,
                "total": nonnegativeIntegerSchema, "has_more": booleanSchema,
                "entries": arraySchema(closedObject(properties: [
                    "kind": .object(["type": .string("string"), "enum": .array(["role", "directory", "note"].map(MCPJSONValue.string))]),
                    "role": roleSchema, "relative_path": simpleSchema("string"), "title": simpleSchema("string"),
                    "note_id": nullable(uuidSchema("Stable Note UUID; null for roles, directories or unresolved Notes.")),
                    "fingerprint": nullable(fingerprintSchema),
                ], required: ["kind", "role", "relative_path", "title", "note_id", "fingerprint"])),
            ], required: ["triptych_id", "role", "directory", "listing_fingerprint", "offset", "limit", "total", "has_more", "entries"])]
        case .search:
            [successSchema(
                properties: [
                    "triptych_id": uuidSchema("Open Triptych UUID."),
                    "query": simpleSchema("string"),
                    "notes": noteSearchGroupSchema,
                                    ],
                required: ["triptych_id", "query", "notes"]
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
                    "start_utf8": nonnegativeIntegerSchema,
                    "end_utf8": nonnegativeIntegerSchema,
                    "source": simpleSchema("string"),
                    "complete": booleanSchema,
                    "next_line": nullable(nonnegativeIntegerSchema),
                    "context": nullable(noteContextSchema),
                ],
                required: [
                    "triptych_id", "note_id", "role", "relative_path",
                    "fingerprint", "start_line", "line_count", "start_utf8", "end_utf8", "source",
                    "complete", "next_line", "context",
                ]
            )]
        case .showNote:
            [successSchema(properties: ["triptych_id": uuidSchema("Triptych UUID."), "window_id": uuidSchema("Window UUID."),
                "note_id": uuidSchema("Note UUID."), "relative_path": simpleSchema("string"), "fingerprint": fingerprintSchema,
                "activated": booleanSchema, "location_requested": booleanSchema, "line": nullable(nonnegativeIntegerSchema)],
                required: ["triptych_id", "window_id", "note_id", "relative_path", "fingerprint", "activated", "location_requested", "line"])]
        case .listAttachments:
            [attachmentListingSchema]
        case .readAttachment:
            [successSchema(properties: ["triptych_id": uuidSchema("Triptych UUID."), "note_id": uuidSchema("Note UUID."),
                "attachment_id": uuidSchema("Attachment UUID."), "filename": simpleSchema("string"), "note_fingerprint": fingerprintSchema,
                "fingerprint": fingerprintSchema, "kind": .object(["type": .string("string"), "enum": .array(["utf8_text", "pdf_text", "image", "pdf_page_image"].map(MCPJSONValue.string))]),
                "page": nullable(nonnegativeIntegerSchema), "total_pages": nullable(nonnegativeIntegerSchema), "text": nullable(simpleSchema("string")), "text_available": nullable(booleanSchema),
                "start_utf8": nonnegativeIntegerSchema, "end_utf8": nonnegativeIntegerSchema, "total_utf8": nonnegativeIntegerSchema, "has_more": booleanSchema,
                "image": nullable(closedObject(properties: ["mime_type": .object(["const": .string("image/png")]), "data": simpleSchema("string"),
                    "pixel_width": nonnegativeIntegerSchema, "pixel_height": nonnegativeIntegerSchema], required: ["mime_type", "data", "pixel_width", "pixel_height"]))],
                required: ["triptych_id", "note_id", "attachment_id", "filename", "note_fingerprint", "fingerprint", "kind", "page", "total_pages", "text", "text_available",
                    "start_utf8", "end_utf8", "total_utf8", "has_more", "image"])]
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
        case .updateNote, .updateMetadata, .updateAttachment:
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
        case .moveNote:
            [successSchema(properties: ["triptych_id": uuidSchema("Open Triptych UUID."), "note_id": uuidSchema("Stable Note UUID."), "change_id": uuidSchema("Agent Change UUID."),
                "source_relative_path": simpleSchema("string"), "relative_path": simpleSchema("string"), "before_fingerprint": fingerprintSchema, "after_fingerprint": fingerprintSchema,
                "readback_verified": booleanSchema, "effects": arraySchema(moveEffectSchema), "derived_refresh_warning": nullable(simpleSchema("string"))],
                required: ["triptych_id", "note_id", "change_id", "source_relative_path", "relative_path", "before_fingerprint", "after_fingerprint", "readback_verified", "effects", "derived_refresh_warning"])]
        case .previewMove:
            [successSchema(properties: ["triptych_id": uuidSchema("Open Triptych UUID."), "note_id": uuidSchema("Stable Note UUID."), "role": roleSchema,
                "source_relative_path": simpleSchema("string"), "relative_path": simpleSchema("string"), "fingerprint": fingerprintSchema,
                "plan_fingerprint": fingerprintSchema, "can_move": booleanSchema, "offset": nonnegativeIntegerSchema, "limit": nonnegativeIntegerSchema,
                "total": nonnegativeIntegerSchema, "has_more": booleanSchema,
                "entries": arraySchema(closedObject(properties: [
                    "kind": .object(["type": .string("string"), "enum": .array(["move", "link_rewrite", "blocked"].map(MCPJSONValue.string))]),
                    "note_id": nullable(uuidSchema("Affected stable Note UUID.")), "role": roleSchema, "source_relative_path": simpleSchema("string"),
                    "relative_path": nullable(simpleSchema("string")), "before_fingerprint": nullable(fingerprintSchema), "after_fingerprint": nullable(fingerprintSchema),
                    "rewritten_occurrences": nonnegativeIntegerSchema, "source_locator": nullable(locatorSchema), "reason": nullable(simpleSchema("string")),
                ], required: ["kind", "note_id", "role", "source_relative_path", "relative_path", "before_fingerprint", "after_fingerprint", "rewritten_occurrences", "source_locator", "reason"])),
            ], required: ["triptych_id", "note_id", "role", "source_relative_path", "relative_path", "fingerprint", "plan_fingerprint", "can_move", "offset", "limit", "total", "has_more", "entries"])]
        case .listChanges:
            [successSchema(properties: ["triptych_id": uuidSchema("Open Triptych UUID."), "note_id": nullable(uuidSchema("Stable Note UUID.")),
                "listing_fingerprint": fingerprintSchema, "offset": nonnegativeIntegerSchema, "limit": nonnegativeIntegerSchema,
                "total": nonnegativeIntegerSchema, "has_more": booleanSchema, "changes": arraySchema(changeReceiptSchema)],
                required: ["triptych_id", "note_id", "listing_fingerprint", "offset", "limit", "total", "has_more", "changes"])]
        case .readChange:
            [successSchema(properties: ["triptych_id": uuidSchema("Open Triptych UUID."), "change": changeReceiptSchema,
                "ending_revision_state": nullable(.object(["type": .string("string"), "enum": .array(["current", "earlier_revision", "unavailable"].map(MCPJSONValue.string))])),
                "can_undo": booleanSchema, "comparison": nullable(changeComparisonSchema),
                "comparison_note_id": uuidSchema("Selected comparison Note UUID."), "undo_unavailable_reason": nullable(simpleSchema("string")),
                "effects": closedObject(properties: ["offset": nonnegativeIntegerSchema, "limit": nonnegativeIntegerSchema, "total": nonnegativeIntegerSchema,
                    "has_more": booleanSchema, "entries": arraySchema(moveEffectSchema)], required: ["offset", "limit", "total", "has_more", "entries"])],
                required: ["triptych_id", "change", "ending_revision_state", "can_undo", "comparison", "comparison_note_id", "undo_unavailable_reason", "effects"])]
        case .undoChange:
            [successSchema(properties: ["triptych_id": uuidSchema("Open Triptych UUID."), "note_id": uuidSchema("Stable Note UUID."),
                "change_id": uuidSchema("Original Agent Change UUID."), "relative_path": simpleSchema("string"),
                "source_relative_path": simpleSchema("string"), "effects": arraySchema(moveEffectSchema),
                "before_fingerprint": fingerprintSchema, "after_fingerprint": fingerprintSchema, "readback_verified": booleanSchema, "undone": booleanSchema],
                required: ["triptych_id", "note_id", "change_id", "relative_path", "before_fingerprint", "after_fingerprint", "readback_verified", "undone", "source_relative_path", "effects"])]
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
        }
        return .object([
            "oneOf": .array(successes + [failureSchema]),
        ])
    }

    private static var noteContextSchema: MCPJSONValue {
        closedObject(properties: [
            "metadata": nullable(closedObject(properties: [
                "fingerprint": fingerprintSchema,
                "fields": .object(["type": .string("object"), "additionalProperties": .bool(true)]),
            ], required: ["fingerprint", "fields"])),
            "zotero_binding": nullable(closedObject(properties: [
                "library": .object(["oneOf": .array([
                    closedObject(properties: ["kind": .object(["const": .string("user")])], required: ["kind"]),
                    closedObject(properties: ["kind": .object(["const": .string("group")]),
                        "group_id": .object(["type": .string("integer"), "minimum": .integer(1)])], required: ["kind", "group_id"]),
                ])]),
                "item_key": simpleSchema("string"), "reference": simpleSchema("string"),
            ], required: ["library", "item_key", "reference"])),
            "zotero_bindings_fingerprint": nullable(fingerprintSchema),
            "attachments": attachmentListingSchema,
        ], required: ["metadata", "zotero_binding", "zotero_bindings_fingerprint", "attachments"])
    }

    private static var attachmentListingSchema: MCPJSONValue {
        successSchema(properties: ["triptych_id": uuidSchema("Triptych UUID."), "note_id": uuidSchema("Note UUID."),
                "note_fingerprint": fingerprintSchema, "listing_fingerprint": fingerprintSchema,
                "offset": nonnegativeIntegerSchema, "total": nonnegativeIntegerSchema, "has_more": booleanSchema,
                "attachments": arraySchema(closedObject(properties: ["attachment_id": uuidSchema("Attachment UUID."),
                    "filename": simpleSchema("string"), "relationship": .object(["type": .string("string"), "enum": .array([.string("document"), .string("authoredImage")])]),
                    "available": booleanSchema], required: ["attachment_id", "filename", "relationship", "available"]))],
                required: ["triptych_id", "note_id", "note_fingerprint", "listing_fingerprint", "offset", "total", "has_more", "attachments"])
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

    private static let recoveryDetailsSchema = closedObject(properties: [
        "recovery_id": uuidSchema("Existing recovery record UUID."), "total": nonnegativeIntegerSchema, "has_more": booleanSchema,
        "files": arraySchema(closedObject(properties: ["vault_id": nullable(uuidSchema("Affected vault UUID.")), "path": simpleSchema("string"),
            "alternate_path": nullable(simpleSchema("string")), "role": simpleSchema("string"), "before_fingerprint": nullable(fingerprintSchema),
            "intended_fingerprint": nullable(fingerprintSchema), "observed_fingerprint": nullable(fingerprintSchema), "state": simpleSchema("string"), "detail": simpleSchema("string")],
            required: ["vault_id", "path", "alternate_path", "role", "before_fingerprint", "intended_fingerprint", "observed_fingerprint", "state", "detail"])),
    ], required: ["recovery_id", "total", "has_more", "files"])

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
            "recovery_details": nullable(recoveryDetailsSchema),
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
