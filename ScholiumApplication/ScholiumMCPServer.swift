import Foundation
import ScholiumContracts

/// Local stdio MCP protocol owner. Tool execution is delegated verbatim to
/// the current-user authenticated App bridge; this process never opens a
/// Triptych or reads its filesystem directly.
public actor ScholiumMCPServer {
    public static let protocolVersion = "2025-11-25"
    public static let serverName = "scholium"
    public static let serverVersion = ScholiumProductIdentity.marketingVersion

    private let callBridge:
        @Sendable (ScholiumMCPBridgeRequest) async throws
            -> MCPJSONValue
    private let conversationToken: UUID?

    public init(bridge: MCPBridgeOperations, conversationToken: UUID? = nil) {
        self.conversationToken = conversationToken
        callBridge = { request in
            try await bridge.call(request)
        }
    }

    public init(
        conversationToken: UUID? = nil,
        handler:
            @escaping @Sendable (ScholiumMCPBridgeRequest) async throws
            -> MCPJSONValue
    ) {
        self.conversationToken = conversationToken
        callBridge = handler
    }

    public func handle(requestData: Data) async -> Data? {
        guard requestData.count <= ScholiumMCPContract.maximumEncodedMessageByteCount else {
            return encode(responseError(id: .null, code: -32600, message: "The MCP request exceeds its encoded size limit."))
        }
        let request: RPCRequest
        do {
            request = try JSONDecoder().decode(RPCRequest.self, from: requestData)
        } catch {
            return encode(
                responseError(
                    id: .null,
                    code: -32700,
                    message: "Invalid JSON-RPC payload."
                ))
        }
        guard let id = request.id else { return nil }
        let identityEncoder = JSONEncoder()
        identityEncoder.outputFormatting = [.withoutEscapingSlashes]
        guard let identity = try? identityEncoder.encode(id),
            identity.count <= ScholiumMCPContract.maximumEncodedResponseIdentityByteCount
        else {
            return encode(responseError(id: .null, code: -32600, message: "The MCP response identity exceeds its encoded size limit."))
        }
        guard request.jsonrpc == "2.0", !request.method.isEmpty else {
            return encode(
                responseError(
                    id: id,
                    code: -32600,
                    message: "Invalid JSON-RPC request."
                ))
        }

        switch request.method {
        case "initialize":
            let requested = request.params?.objectValue?["protocolVersion"]?.stringValue
            let selected =
                [Self.protocolVersion, "2024-11-05"].contains(requested)
                ? requested!
                : Self.protocolVersion
            return encode(
                responseResult(
                    id: id,
                    result: .object([
                        "protocolVersion": .string(selected),
                        "capabilities": .object(["tools": .object([:])]),
                        "serverInfo": .object([
                            "name": .string(Self.serverName),
                            "version": .string(Self.serverVersion),
                        ]),
                        "instructions": .string(
                            "Begin with scholium_workspace_status. In the selected Triptych, browse, search, and read Notes and accessible authored attachments as needed without per-read approval; retain exact source and coverage. Markdown source is authoritative; Search, Metadata, and links are retrieval aids. Note mutations require the researcher's instruction and current fingerprints."
                        ),
                    ])))
        case "ping":
            return encode(responseResult(id: id, result: .object([:])))
        case "tools/list":
            return encode(
                responseResult(
                    id: id,
                    result: .object([
                        "tools": .array(Self.toolDefinitions(conversationToken: conversationToken))
                    ])))
        case "tools/call":
            let result = await callTool(params: request.params)
            let response = encodeUnbounded(responseResult(id: id, result: result))
            if let response, response.count <= ScholiumMCPContract.maximumEncodedMessageByteCount { return response }
            let tool = request.params?.objectValue?["name"]?.stringValue.flatMap(ScholiumMCPToolName.init(rawValue:))
            let mayHaveChangedState = tool?.mayMutatePersistentState == true
            let failure = ScholiumMCPFailure(
                code: mayHaveChangedState ? .operationUncertain : .invalidRequest,
                message: "The complete MCP result exceeds its encoded reply limit.",
                recovery: mayHaveChangedState
                    ? "Do not replay the operation. Inspect the current source, retained Agent Changes or runtime settings before another mutation."
                    : "Request a smaller page or source slice and continue using the returned fingerprints.")
            let refusal = encodeUnbounded(responseResult(id: id, result: toolResult(failureValue(failure, for: tool), isError: true)))
            if let refusal, refusal.count <= ScholiumMCPContract.maximumEncodedMessageByteCount { return refusal }
            return encode(responseError(id: .null, code: -32600, message: "The MCP reply identity exceeds its encoded size limit."))
        default:
            return encode(
                responseError(
                    id: id,
                    code: -32601,
                    message: "Unsupported MCP method."
                ))
        }
    }

    private func callTool(params: MCPJSONValue?) async -> MCPJSONValue {
        let requestedTool = params?.objectValue?["name"]?.stringValue.flatMap(ScholiumMCPToolName.init(rawValue:))
        do {
            guard let params = params?.objectValue,
                let tool = requestedTool
            else {
                throw ScholiumMCPFailure(
                    code: .invalidRequest,
                    message: "The requested Scholium MCP tool is unknown.",
                    recovery: "Call tools/list and use one of the published tool names."
                )
            }
            guard !tool.isChatControl || conversationToken != nil else {
                throw ScholiumMCPFailure(
                    code: .invalidRequest,
                    message: "This tool requires an in-app Scholium Chat conversation.",
                    recovery: "Open Scholium Chat and use its connected Scholium tool, or call one of the external research tools."
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
                !thread.isEmpty, !turn.isEmpty, thread.utf8.count <= 256, turn.utf8.count <= 256
            {
                context = .init(threadID: thread, turnID: turn)
            } else {
                context = nil
            }
            let result = try await callBridge(
                ScholiumMCPBridgeRequest(
                    tool: tool,
                    arguments: arguments,
                    conversationToken: conversationToken,
                    runtimeContext: context
                ))
            let response = toolResult(result, isError: false, includesImage: tool == .readAttachment)
            if tool == .observeCurrentState {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                guard try encoder.encode(response).count <= ScholiumMCPContract.maximumChatObservationUTF8ByteCount else {
                    throw ScholiumMCPFailure.chatObservation(.invalidRequest)
                }
            }
            return response
        } catch let failure as ScholiumMCPFailure {
            return toolResult(failureValue(failure, for: requestedTool), isError: true)
        } catch let error as ScholiumAppBridgeError {
            let failure: ScholiumMCPFailure
            switch error {
            case .requestTooLarge:
                failure = ScholiumMCPFailure(
                    code: .invalidRequest,
                    message: "The encoded request exceeds the App bridge limit and was not sent.",
                    recovery: "Reduce the request within the published source and edit limits. No operation was admitted.")
            case .unavailable, .timeout:
                failure = ScholiumMCPFailure(
                    code: .appUnavailable,
                    message: "The Scholium App bridge is unavailable.",
                    recovery: "Launch Scholium, open a Triptych, and call workspace status again."
                )
            case .outcomeUnknown:
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
            return toolResult(failureValue(failure, for: requestedTool), isError: true)
        } catch {
            return toolResult(
                failureValue(
                    ScholiumMCPFailure(
                        code: .internalError,
                        message: "The local Scholium MCP adapter failed.",
                        recovery: "Restart Scholium and begin again with workspace status."
                    ), for: requestedTool), isError: true)
        }
    }

    private func toolResult(_ value: MCPJSONValue, isError: Bool, includesImage: Bool = false) -> MCPJSONValue {
        var textValue = value
        var imageBlock: MCPJSONValue?
        if includesImage, !isError, let image = value.objectValue?["image"]?.objectValue,
            image["mime_type"]?.stringValue == "image/png", let data = image["data"]?.stringValue
        {
            imageBlock = .object(["type": .string("image"), "mimeType": .string("image/png"), "data": .string(data)])
            var object = value.objectValue ?? [:]
            var metadata = image
            metadata["data"] = nil
            object["image"] = .object(metadata)
            textValue = .object(object)
        }
        var content: [MCPJSONValue] = [.object(["type": .string("text"), "text": .string(Self.jsonString(textValue))])]
        if let imageBlock { content.append(imageBlock) }
        return .object(["content": .array(content), "structuredContent": value, "isError": .bool(isError)])
    }

    private func failureValue(_ failure: ScholiumMCPFailure, for tool: ScholiumMCPToolName?) -> MCPJSONValue {
        let failure = tool == .observeCurrentState ? ScholiumMCPFailure.chatObservation(failure.code) : failure
        var value: [String: MCPJSONValue] = [
            "schema_version": .integer(failure.schemaVersion),
            "status": .string(failure.status),
            "code": .string(failure.code.rawValue),
            "message": .string(failure.message),
            "recovery": .string(failure.recovery),
        ]
        if tool != .observeCurrentState { value["recovery_details"] = failure.recoveryDetails?.jsonValue ?? .null }
        return .object(value)
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
        guard let data = encodeUnbounded(response) else { return nil }
        guard data.count <= ScholiumMCPContract.maximumEncodedMessageByteCount else {
            return encodeUnbounded(responseError(id: .null, code: -32600, message: "The MCP reply exceeds its encoded size limit."))
        }
        return data
    }

    private func encodeUnbounded(_ response: RPCResponse) -> Data? {
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

    private static let researchToolDefinitions: [MCPJSONValue] = [
        tool(
            .workspaceStatus,
            description: "Reconcile and report the running App's currently open Triptych state.",
            properties: [
                "triptych_id": stringSchema("Optional open Triptych UUID.")
            ],
            required: [],
            readOnly: true,
            destructive: false,
            idempotent: true
        ),
        tool(
            .browse,
            description:
                "Browse role roots or immediate Library directory/Note children without a search query. Continue with the returned listing fingerprint.",
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
                "query": stringSchema(
                    "Scholium Search contract \(SearchCapabilities.current.contractVersion). "
                        + SearchCapabilities.current.booleanQueryHelp + " "
                        + SearchCapabilities.current.propertyQueryHelp
                        + " Examples: "
                        + (SearchCapabilities.current.capability(for: .note)?.examples.joined(separator: "; ") ?? "")
                ),
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
                "paragraph_limit": integerSchema(minimum: 1, maximum: 50, default: 10),
                "paragraph_offset": integerSchema(minimum: 0, maximum: nil, default: 0),
            ],
            required: ["triptych_id", "query"],
            readOnly: true,
            destructive: false,
            idempotent: true
        ),
        tool(
            .readNote,
            description:
                "Read exact Note prose by stable UUID. Set include_context to also inspect the first 20 attachment pointers derived from this Note source. These pointers are not proof of reading their contents. Continue attachment listings with scholium_list_attachments; read selected material with the corresponding attachment or Zotero tool.",
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
        tool(
            .showNote,
            description:
                "Display an exact current Note or passage in its existing foreground window. External hosts must name a window from workspace_status; Chat uses its original visible window. Never foregrounds a background task.",
            properties: [
                "triptych_id": uuidSchema("Open Triptych UUID."), "window_id": uuidSchema("Live window UUID; required outside in-app Chat."),
                "note_id": uuidSchema("Stable Note UUID."), "expected_fingerprint": fingerprintSchema,
                "start_utf8": integerSchema(minimum: 0, maximum: nil, default: 0), "end_utf8": integerSchema(minimum: 1, maximum: nil, default: 1),
                "expected_text": stringSchema("Exact complete text for the requested source range, at most 64 KiB."),
            ],
            required: ["triptych_id", "note_id", "expected_fingerprint"],
            alternatives: [
                .object(["required": .array(["start_utf8", "end_utf8", "expected_text"].map(MCPJSONValue.string))]),
                .object(["not": .object(["anyOf": .array(["start_utf8", "end_utf8", "expected_text"].map { .object(["required": .array([.string($0)])]) })])]),
            ],
            readOnly: false, destructive: false, idempotent: false),
        tool(
            .listAttachments, description: "List the current Note's document attachments and registered authored images; metadata is not source reading.",
            properties: [
                "triptych_id": uuidSchema("Open Triptych UUID."), "note_id": uuidSchema("Stable Note UUID."),
                "offset": integerSchema(minimum: 0, maximum: nil, default: 0), "limit": integerSchema(minimum: 1, maximum: 100, default: 20),
                "expected_listing_fingerprint": fingerprintSchema,
            ], required: ["triptych_id", "note_id"], readOnly: true, destructive: false, idempotent: true),
        tool(
            .readAttachment,
            description:
                "Read one related current attachment. Text uses exact UTF-8 offsets; PDF reads require one explicit page. Image mode returns a bounded rendered PNG, never OCR.",
            properties: [
                "triptych_id": uuidSchema("Open Triptych UUID."), "note_id": uuidSchema("Stable Note UUID."),
                "attachment_id": uuidSchema("Attachment UUID from list_attachments."), "expected_note_fingerprint": fingerprintSchema,
                "expected_fingerprint": fingerprintSchema, "mode": .object(["type": .string("string"), "enum": .array([.string("text"), .string("image")])]),
                "page": integerSchema(minimum: 1, maximum: nil, default: 1), "start_utf8": integerSchema(minimum: 0, maximum: nil, default: 0),
                "max_utf8": integerSchema(minimum: 1, maximum: 65_536, default: 16_384),
            ],
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
                "content": stringSchema("Complete exact Markdown source, including optional user-authored YAML."),
            ],
            required: ["triptych_id", "role", "relative_path", "content"],
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
                    "items": closedObject(
                        properties: [
                            "start_utf8": .object([
                                "type": .string("integer"), "minimum": .integer(0),
                                "description": .string("Zero-based UTF-8 offset in the complete original source, including BOM and YAML."),
                            ]),
                            "end_utf8": .object([
                                "type": .string("integer"), "minimum": .integer(0),
                                "description": .string("Exclusive UTF-8 offset; equal to start_utf8 for insertion."),
                            ]),
                            "expected_text": stringSchema("Exact original bytes decoded as text; empty for insertion."),
                            "replacement": stringSchema("Exact replacement; empty for deletion. No newline normalization."),
                        ], required: ["start_utf8", "end_utf8", "expected_text", "replacement"]),
                ]),
            ],
            required: [
                "triptych_id", "note_id", "expected_fingerprint", "mode",
            ],
            alternatives: [
                .object([
                    "properties": .object(["mode": .object(["enum": .array([.string("body"), .string("source")])])]),
                    "required": .array([.string("content")]), "not": .object(["required": .array([.string("edits")])]),
                ]),
                .object([
                    "properties": .object(["mode": .object(["const": .string("edits")])]),
                    "required": .array([.string("edits")]), "not": .object(["required": .array([.string("content")])]),
                ]),
            ],
            readOnly: false,
            destructive: true,
            idempotent: false
        ),
        tool(
            .moveNote,
            description:
                "Execute the exact previously previewed same-vault Note move, preserving identity and recording all linked-source effects. A changed plan is rejected.",
            properties: [
                "triptych_id": uuidSchema("Open Triptych UUID."), "note_id": uuidSchema("Stable Note UUID."),
                "expected_fingerprint": fingerprintSchema, "relative_path": stringSchema("Exact destination .md path in the same vault."),
                "expected_plan_fingerprint": fingerprintSchema,
            ],
            required: ["triptych_id", "note_id", "expected_fingerprint", "relative_path", "expected_plan_fingerprint"],
            readOnly: false, destructive: true, idempotent: false),
        tool(
            .previewMove,
            description:
                "Preview a same-role Note rename/move and exact incoming-link effects without changing source. Continue only with the full plan fingerprint.",
            properties: [
                "triptych_id": uuidSchema("Open Triptych UUID."), "note_id": uuidSchema("Stable Note UUID."),
                "expected_fingerprint": fingerprintSchema, "relative_path": stringSchema("Exact destination .md path in the same vault."),
                "offset": integerSchema(minimum: 0, maximum: nil, default: 0), "limit": integerSchema(minimum: 1, maximum: 100, default: 20),
                "expected_plan_fingerprint": fingerprintSchema,
            ], required: ["triptych_id", "note_id", "expected_fingerprint", "relative_path"],
            readOnly: true, destructive: false, idempotent: true),
        tool(
            .listChanges,
            description: "List exact machine-local Agent Change receipts; history is not current source or mutation permission.",
            properties: [
                "triptych_id": uuidSchema("Open Triptych UUID."), "note_id": uuidSchema("Optional stable Note UUID."),
                "offset": integerSchema(minimum: 0, maximum: nil, default: 0), "limit": integerSchema(minimum: 1, maximum: 100, default: 20),
                "expected_listing_fingerprint": fingerprintSchema,
            ], required: ["triptych_id"], readOnly: true, destructive: false, idempotent: true),
        tool(
            .readChange,
            description: "Read one retained change and a paged exact source comparison, with current Undo eligibility. No source is changed.",
            properties: [
                "triptych_id": uuidSchema("Open Triptych UUID."), "change_id": uuidSchema("Exact Agent Change UUID."),
                "note_id": uuidSchema("An affected Note UUID; defaults to the primary Note comparison."),
                "effect_offset": integerSchema(minimum: 0, maximum: nil, default: 0), "effect_limit": integerSchema(minimum: 1, maximum: 100, default: 20),
                "offset": integerSchema(minimum: 0, maximum: nil, default: 0), "limit": integerSchema(minimum: 1, maximum: 1000, default: 200),
            ],
            required: ["triptych_id", "change_id"], readOnly: true, destructive: false, idempotent: true),
        tool(
            .undoChange,
            description:
                "Undo only the explicitly requested eligible source, Metadata or attachment-relationship change while its current values equal the recorded ending. Use the receipt ending fingerprint, not a different Note-source fingerprint. Never automatically undo another task or repeat a completed write.",
            properties: [
                "triptych_id": uuidSchema("Open Triptych UUID."), "note_id": uuidSchema("Stable Note UUID bound to this change."),
                "change_id": uuidSchema("Exact Agent Change UUID."), "expected_fingerprint": fingerprintSchema,
            ],
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
        tool(
            .observeWorkspace,
            description:
                "Observe bounded live app-state metadata for an explicit Triptych. Omit triptych_id for passive Triptych discovery. Supply it to list registered windows, and window_id to inspect open tabs and readiness. In-app workspace calls bind omitted identities to the turn’s already admitted originating window. Native Agent Context Access settings control access. Reads cached owners without saving, refreshing, navigation or provider calls; cached readiness does not prove disk currentness. Continuations require the returned listing hash.",
            properties: [
                "triptych_id": uuidSchema("Explicit open Triptych UUID."), "window_id": uuidSchema("Exact registered window UUID."),
                "offset": integerSchema(minimum: 0, maximum: nil, default: 0), "limit": integerSchema(minimum: 1, maximum: 100, default: 20),
                "expected_listing_fingerprint": fingerprintSchema,
            ], required: [],
            alternatives: [
                .object(["not": forbiddenContextFields(["triptych_id", "window_id"])]),
                .object(["required": .array([.string("triptych_id")])]),
            ], readOnly: true, destructive: false, idempotent: true),
        tool(
            .observeResearchContext,
            description:
                "Observe the exact window's active Note revision and selection coordinates, Library/Search/Related state and paged Kept Passage references. Returns metadata without working text or philosophical judgments. Native state access is required; unavailable or changed state remains explicit. No save, hydration, vault scan or provider call. Use explicit reads for exact content and preserve captured source provenance.",
            properties: [
                "triptych_id": uuidSchema("Explicit open Triptych UUID."), "window_id": uuidSchema("Exact registered window UUID."),
                "offset": integerSchema(minimum: 0, maximum: nil, default: 0), "limit": integerSchema(minimum: 1, maximum: 100, default: 20),
                "expected_listing_fingerprint": fingerprintSchema,
            ], required: ["triptych_id", "window_id"], readOnly: true, destructive: false, idempotent: true),
        tool(
            .readContext,
            description:
                "Read one explicit bounded exact working-text slice from the active Note, its verified selection or a retained Kept Passage. Native working-text permission is independent of state and write permissions. Requires the captured source fingerprint and Note identity; selection also binds original source coordinates. UTF-8 paging is relative to the requested material. Kept text is a historical snapshot; editor text is an unsaved snapshot when applicable. No save, fallback source, navigation or new authority.",
            properties: [
                "triptych_id": uuidSchema("Explicit open Triptych UUID."), "window_id": uuidSchema("Exact registered window UUID."),
                "kind": enumSchema(["active_note", "selection", "kept_passage"]),
                "note_id": uuidSchema("Exact active Note UUID; required for active Note or selection."),
                "expected_fingerprint": fingerprintSchema, "kept_passage_id": boundedStringSchema(maximum: 8_192),
                "expected_start_utf8": nonnegativeIntegerSchema,
                "expected_end_utf8": .object(["type": .string("integer"), "minimum": .integer(1)]),
                "start_utf8": integerSchema(minimum: 0, maximum: nil, default: 0),
                "max_utf8": integerSchema(minimum: 1, maximum: 65_536, default: 16_384),
            ], required: ["triptych_id", "window_id", "kind", "expected_fingerprint"],
            alternatives: [
                .object([
                    "properties": .object(["kind": enumSchema(["active_note"])]), "required": .array([.string("note_id")]),
                    "not": forbiddenContextFields(["kept_passage_id", "expected_start_utf8", "expected_end_utf8"]),
                ]),
                .object([
                    "properties": .object(["kind": enumSchema(["selection"])]),
                    "required": .array([.string("note_id"), .string("expected_start_utf8"), .string("expected_end_utf8")]),
                    "not": forbiddenContextFields(["kept_passage_id"]),
                ]),
                .object([
                    "properties": .object(["kind": enumSchema(["kept_passage"])]), "required": .array([.string("kept_passage_id")]),
                    "not": forbiddenContextFields(["expected_start_utf8", "expected_end_utf8"]),
                ]),
            ], readOnly: true, destructive: false, idempotent: true),
    ]

    private static func toolDefinitions(conversationToken: UUID?) -> [MCPJSONValue] {
        researchToolDefinitions + (conversationToken == nil ? [] : chatControlToolDefinitions)
    }

    private static let chatControlToolDefinitions: [MCPJSONValue] = [
        tool(
            .capabilities,
            description:
                "Inspect the current in-app Agent runtime: available Skills, the Triptych Skills directory, connected MCP tools, and the writable tool-configuration revision. This is an observation, not permission to change research Notes.",
            properties: [:],
            required: [],
            readOnly: true,
            destructive: false,
            idempotent: true
        ),
        tool(
            .configureSkill,
            description:
                "Enable or disable an available Skill at the researcher's request. Triptych Skills are discovered automatically from the workspace skills directory. Use runtime file tools to create or edit a requested Skill there; this control does not rewrite files. The protected Scholium Core Protocol cannot be disabled.",
            properties: [
                "action": enumSchema(["enable", "disable"]),
                "path": stringSchema("Exact SKILL.md path for enable/disable."),
                "name": stringSchema("Optional Skill name used with an exact SKILL.md path."),
            ],
            required: ["action"],
            readOnly: false,
            destructive: false,
            idempotent: true
        ),
        tool(
            .configureTool,
            description:
                "Begin runtime-owned sign-in for an observed MCP connection. Adding, editing, enabling, disabling or removing connections requires the researcher-controlled native Settings surface; a model request cannot authorize executable or access configuration changes.",
            properties: [
                "action": enumSchema(["sign_in"]),
                "name": stringSchema("Exact connection name."),
            ],
            required: ["action"],
            readOnly: false,
            destructive: false,
            idempotent: true
        ),
        tool(
            .configureChat,
            description:
                "Change this conversation's runtime preferences or next-message Skill selection. Changes are stored on the addressed conversation and apply to the next turn. Permission can only be reduced to Ask; Full Access requires the researcher's native idle-conversation control. Changes do not rewrite Notes or retroactively change the active turn.",
            properties: [
                "action": enumSchema(["set_permission", "set_model", "set_effort", "set_web_search", "set_selected_skills"]),
                "permission": enumSchema(["ask"]),
                "model": nullable(stringSchema("Available model identifier; omit or send null to use the runtime default.")),
                "effort": nullable(stringSchema("Reasoning effort supported by the selected model; omit or send null for the default.")),
                "web_search": enumSchema(["runtimeDefault", "disabled", "cached", "live"]),
                "skill_paths": arraySchema(stringSchema("Exact enabled Skill.md path for the next message.")),
            ],
            required: ["action"],
            readOnly: false,
            destructive: false,
            idempotent: true
        ),
        tool(
            .observeCurrentState,
            description:
                "Observe metadata in the exact window, Triptych and conversation bound to this admitted Chat turn. Returns current Note identity, revision and selection coordinates without source text, drafts, queued input, raw errors or external-document paths. No navigation, save, provider request or new authority. Unavailable revision or selection is explicit; departed or revoked context fails without retargeting. Encoded tool results are capped at 16 KiB without truncation.",
            properties: [
                "triptych_id": uuidSchema("Exact admitted Triptych UUID."),
                "window_id": uuidSchema("Original visible window UUID captured for this turn."),
                "conversation_id": uuidSchema("Exact admitted Chat conversation UUID."),
            ],
            required: ["triptych_id", "window_id", "conversation_id"],
            readOnly: true,
            destructive: false,
            idempotent: true
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
        // Some runtime tool renderers project oneOf branches without the parent.
        // Make every branch self-contained while preserving its constraints.
        let completeAlternatives = alternatives.map { alternative -> MCPJSONValue in
            guard var branch = alternative.objectValue else { return alternative }
            var fields = properties
            for (key, value) in branch["properties"]?.objectValue ?? [:] {
                if let base = fields[key]?.objectValue, let refinement = value.objectValue {
                    fields[key] = .object(base.merging(refinement) { _, new in new })
                } else {
                    fields[key] = value
                }
            }
            let extra = branch["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
            branch["type"] = .string("object")
            branch["properties"] = .object(fields)
            branch["required"] = .array(Array(Set(required + extra)).sorted().map(MCPJSONValue.string))
            branch["additionalProperties"] = .bool(false)
            return .object(branch)
        }
        return .object([
            "name": .string(name.rawValue),
            "description": .string(description),
            "inputSchema": .object(
                [
                    "type": .string("object"),
                    "properties": .object(properties),
                    "required": .array(required.map(MCPJSONValue.string)),
                    "additionalProperties": .bool(false),
                ].merging(alternatives.isEmpty ? [:] : ["oneOf": .array(completeAlternatives)]) { _, value in value }),
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

    private static func enumSchema(_ values: [String]) -> MCPJSONValue {
        .object([
            "type": .string("string"),
            "enum": .array(values.map(MCPJSONValue.string)),
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
            "indeterminate_notes": nonnegativeIntegerSchema,
            "has_more": booleanSchema,
            "results": arraySchema(
                closedObject(
                    properties: [
                        "note_id": nullable(uuidSchema("Stable Note UUID.")),
                        "role": roleSchema,
                        "relative_path": simpleSchema("string"),
                        "title": simpleSchema("string"),
                        "fingerprint": fingerprintSchema,
                        "match_reasons": arraySchema(simpleSchema("string")),
                        "rank_reason": simpleSchema("string"),
                        "snippet": simpleSchema("string"),
                        "paragraphs": closedObject(
                            properties: [
                                "total": nonnegativeIntegerSchema, "offset": nonnegativeIntegerSchema, "limit": nonnegativeIntegerSchema,
                                "has_more": booleanSchema, "locators": arraySchema(locatorSchema),
                            ], required: ["total", "offset", "limit", "has_more", "locators"]),
                        "source_locator": nullable(locatorSchema),
                    ],
                    required: [
                        "note_id", "role", "relative_path", "title",
                        "fingerprint", "match_reasons", "rank_reason",
                        "snippet", "paragraphs", "source_locator",
                    ]
                )),
        ],
        required: [
            "freshness", "offset", "limit", "total", "indeterminate_notes", "has_more", "results",
        ]
    )

    private static let moveEffectSchema = closedObject(
        properties: [
            "note_id": uuidSchema("Affected Note UUID."), "role": roleSchema, "source_relative_path": simpleSchema("string"),
            "relative_path": simpleSchema("string"),
            "before_fingerprint": fingerprintSchema, "after_fingerprint": fingerprintSchema, "rewritten_occurrences": nonnegativeIntegerSchema,
        ], required: ["note_id", "role", "source_relative_path", "relative_path", "before_fingerprint", "after_fingerprint", "rewritten_occurrences"])

    private static let changeReceiptSchema = closedObject(
        properties: [
            "change_id": uuidSchema("Agent Change UUID."), "note_id": uuidSchema("Stable Note UUID."), "role": roleSchema,
            "affected_note_count": nonnegativeIntegerSchema,
            "operation": .object([
                "type": .string("string"), "enum": .array(["create", "update", "trash", "move"].map(MCPJSONValue.string)),
            ]),
            "state": .object(["type": .string("string"), "enum": .array(["prepared", "confirmed", "outcome_uncertain", "undone"].map(MCPJSONValue.string))]),
            "original_relative_path": nullable(simpleSchema("string")), "final_relative_path": nullable(simpleSchema("string")),
            "before_fingerprint": nullable(fingerprintSchema), "after_fingerprint": nullable(fingerprintSchema),
            "created_at": simpleSchema("string"), "confirmed_at": nullable(simpleSchema("string")), "undone_at": nullable(simpleSchema("string")),
        ],
        required: [
            "change_id", "note_id", "role", "affected_note_count", "operation", "state", "original_relative_path", "final_relative_path",
            "before_fingerprint", "after_fingerprint", "created_at", "confirmed_at", "undone_at",
        ])

    private static let changeComparisonSchema = closedObject(
        properties: [
            "before_fingerprint": fingerprintSchema, "after_fingerprint": fingerprintSchema,
            "before_has_bom": booleanSchema, "after_has_bom": booleanSchema,
            "offset": nonnegativeIntegerSchema, "limit": nonnegativeIntegerSchema, "total": nonnegativeIntegerSchema, "has_more": booleanSchema,
            "rows": arraySchema(
                closedObject(
                    properties: [
                        "kind": .object(["type": .string("string"), "enum": .array(["unchanged", "removed", "added"].map(MCPJSONValue.string))]),
                        "before_line": nullable(nonnegativeIntegerSchema), "after_line": nullable(nonnegativeIntegerSchema), "text": simpleSchema("string"),
                        "line_ending": .object(["type": .string("string"), "enum": .array(["LF", "CRLF", "None"].map(MCPJSONValue.string))]),
                    ], required: ["kind", "before_line", "after_line", "text", "line_ending"])),
        ], required: ["before_fingerprint", "after_fingerprint", "before_has_bom", "after_has_bom", "offset", "limit", "total", "has_more", "rows"])

    private static func outputSchema(
        for tool: ScholiumMCPToolName
    ) -> MCPJSONValue {
        let successes: [MCPJSONValue] =
            switch tool {
            case .capabilities:
                [
                    successSchema(
                        properties: [
                            "triptych_id": uuidSchema("Current Triptych UUID."),
                            "conversation_id": uuidSchema("Addressed Chat conversation UUID."),
                            "conversation": simpleSchema("object"),
                            "skill_roots": arraySchema(stringSchema("Absolute Skill discovery directory.")),
                            "skills": arraySchema(simpleSchema("object")),
                            "skill_errors": arraySchema(simpleSchema("string")),
                            "connected_tools": arraySchema(simpleSchema("object")),
                            "tool_configuration": simpleSchema("object"),
                        ],
                        required: [
                            "triptych_id", "conversation_id", "conversation", "skill_roots", "skills", "skill_errors", "connected_tools", "tool_configuration",
                        ])
                ]
            case .configureSkill:
                [
                    successSchema(
                        properties: [
                            "action": simpleSchema("string"), "path": nullable(simpleSchema("string")),
                            "effective_enabled": nullable(booleanSchema), "skill_roots": arraySchema(stringSchema("Absolute Skill discovery directory.")),
                        ], required: ["action", "path", "effective_enabled", "skill_roots"])
                ]
            case .configureTool:
                [
                    successSchema(
                        properties: [
                            "action": simpleSchema("string"), "applies_to": simpleSchema("string"),
                            "authorization_url": simpleSchema("string"),
                        ], required: ["action", "applies_to", "authorization_url"])
                ]
            case .configureChat:
                [
                    successSchema(
                        properties: [
                            "action": simpleSchema("string"), "applies_to": simpleSchema("string"), "conversation": simpleSchema("object"),
                        ], required: ["action", "applies_to", "conversation"])
                ]
            case .observeCurrentState:
                [chatObservationSchema]
            case .observeWorkspace:
                [
                    successSchema(
                        properties: [
                            "observed_at": simpleSchema("string"),
                            "triptychs": contextListingSchema(
                                contextObject(["triptych_id": uuidSchema("Open Triptych UUID."), "window_count": nonnegativeIntegerSchema])),
                        ], required: ["observed_at", "triptychs"]),
                    successSchema(
                        properties: [
                            "triptych_id": uuidSchema("Observed Triptych UUID."), "observed_at": simpleSchema("string"),
                            "windows": contextListingSchema(contextWindowSummarySchema),
                        ], required: ["triptych_id", "observed_at", "windows"]),
                    successSchema(
                        properties: [
                            "triptych_id": uuidSchema("Observed Triptych UUID."), "window_id": uuidSchema("Observed window UUID."),
                            "observed_at": simpleSchema("string"), "window": contextWindowSchema,
                            "listing_fingerprint": fingerprintSchema, "tabs": contextPageSchema(contextTabSchema),
                        ], required: ["triptych_id", "window_id", "observed_at", "window", "listing_fingerprint", "tabs"]),
                ]
            case .observeResearchContext:
                [
                    successSchema(
                        properties: [
                            "triptych_id": uuidSchema("Observed Triptych UUID."), "window_id": uuidSchema("Observed window UUID."),
                            "observed_at": simpleSchema("string"), "window": contextWindowSchema, "listing_fingerprint": fingerprintSchema,
                            "document_surface": enumSchema(["none", "triptych_note", "external_document", "unavailable"]),
                            "active_note": nullable(contextActiveNoteSchema), "library": contextLibrarySchema, "search": contextSearchSchema,
                            "related_material": contextRelatedSchema, "kept_passages": contextKeptSchema,
                        ],
                        required: [
                            "triptych_id", "window_id", "observed_at", "window", "listing_fingerprint", "document_surface", "active_note", "library", "search",
                            "related_material", "kept_passages",
                        ])
                ]
            case .readContext:
                [
                    successSchema(
                        properties: [
                            "triptych_id": uuidSchema("Observed Triptych UUID."), "window_id": uuidSchema("Observed window UUID."),
                            "observed_at": simpleSchema("string"),
                            "kind": enumSchema(["active_note", "selection", "kept_passage"]),
                            "origin": enumSchema(["editor_snapshot", "saved_source", "kept_snapshot"]),
                            "note": closedObject(
                                properties: [
                                    "vault_id": uuidSchema("Source vault UUID."), "note_id": nullable(uuidSchema("Source Note UUID.")), "role": roleSchema,
                                    "relative_path": boundedStringSchema(maximum: 4_096),
                                ], required: ["vault_id", "note_id", "role", "relative_path"]),
                            "fingerprint": fingerprintSchema, "text_fingerprint": fingerprintSchema, "source_locator": contextReadLocatorSchema,
                            "kept_passage_id": nullable(boundedStringSchema(maximum: 8_192)), "text": simpleSchema("string"),
                            "coverage": closedObject(
                                properties: [
                                    "basis": enumSchema(["context"]), "total_utf8": nonnegativeIntegerSchema, "start_utf8": nonnegativeIntegerSchema,
                                    "end_utf8": nonnegativeIntegerSchema, "has_more": booleanSchema, "next_start_utf8": nullable(nonnegativeIntegerSchema),
                                ], required: ["basis", "total_utf8", "start_utf8", "end_utf8", "has_more", "next_start_utf8"]),
                        ],
                        required: [
                            "triptych_id", "window_id", "observed_at", "kind", "origin", "note", "fingerprint", "text_fingerprint", "source_locator",
                            "kept_passage_id", "text", "coverage",
                        ])
                ]
            case .workspaceStatus:
                [
                    successSchema(
                        properties: [
                            "current": booleanSchema,
                            "selection_required": booleanSchema,
                            "triptychs": arraySchema(
                                closedObject(
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
                            "windows": arraySchema(
                                closedObject(
                                    properties: ["window_id": uuidSchema("Live window UUID."), "can_display": booleanSchema],
                                    required: ["window_id", "can_display"])),
                            "source_generation": generationSchema(
                                includesCount: true
                            ),
                            "search_generation": generationSchema(
                                includesCount: false
                            ),
                            "graph_generation": generationSchema(
                                includesCount: false
                            ),
                            "vaults": arraySchema(
                                closedObject(
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
                [
                    successSchema(
                        properties: [
                            "triptych_id": uuidSchema("Open Triptych UUID."), "role": nullable(roleSchema),
                            "directory": simpleSchema("string"), "listing_fingerprint": fingerprintSchema,
                            "offset": nonnegativeIntegerSchema, "limit": nonnegativeIntegerSchema,
                            "total": nonnegativeIntegerSchema, "has_more": booleanSchema,
                            "entries": arraySchema(
                                closedObject(
                                    properties: [
                                        "kind": .object(["type": .string("string"), "enum": .array(["role", "directory", "note"].map(MCPJSONValue.string))]),
                                        "role": roleSchema, "relative_path": simpleSchema("string"), "title": simpleSchema("string"),
                                        "note_id": nullable(uuidSchema("Stable Note UUID; null for roles, directories or unresolved Notes.")),
                                        "fingerprint": nullable(fingerprintSchema),
                                    ], required: ["kind", "role", "relative_path", "title", "note_id", "fingerprint"])),
                        ], required: ["triptych_id", "role", "directory", "listing_fingerprint", "offset", "limit", "total", "has_more", "entries"])
                ]
            case .search:
                [
                    successSchema(
                        properties: [
                            "triptych_id": uuidSchema("Open Triptych UUID."),
                            "query": simpleSchema("string"),
                            "notes": noteSearchGroupSchema,
                        ],
                        required: ["triptych_id", "query", "notes"]
                    )
                ]
            case .readNote:
                [
                    successSchema(
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
                    )
                ]
            case .showNote:
                [
                    successSchema(
                        properties: [
                            "triptych_id": uuidSchema("Triptych UUID."), "window_id": uuidSchema("Window UUID."),
                            "note_id": uuidSchema("Note UUID."), "relative_path": simpleSchema("string"), "fingerprint": fingerprintSchema,
                            "activated": booleanSchema, "location_requested": booleanSchema, "line": nullable(nonnegativeIntegerSchema),
                        ],
                        required: ["triptych_id", "window_id", "note_id", "relative_path", "fingerprint", "activated", "location_requested", "line"])
                ]
            case .listAttachments:
                [attachmentListingSchema]
            case .readAttachment:
                [
                    successSchema(
                        properties: [
                            "triptych_id": uuidSchema("Triptych UUID."), "note_id": uuidSchema("Note UUID."),
                            "attachment_id": uuidSchema("Attachment UUID."), "filename": simpleSchema("string"), "note_fingerprint": fingerprintSchema,
                            "fingerprint": fingerprintSchema,
                            "kind": .object([
                                "type": .string("string"), "enum": .array(["utf8_text", "pdf_text", "image", "pdf_page_image"].map(MCPJSONValue.string)),
                            ]),
                            "page": nullable(nonnegativeIntegerSchema), "total_pages": nullable(nonnegativeIntegerSchema),
                            "text": nullable(simpleSchema("string")), "text_available": nullable(booleanSchema),
                            "start_utf8": nonnegativeIntegerSchema, "end_utf8": nonnegativeIntegerSchema, "total_utf8": nonnegativeIntegerSchema,
                            "has_more": booleanSchema,
                            "image": nullable(
                                closedObject(
                                    properties: [
                                        "mime_type": .object(["const": .string("image/png")]), "data": simpleSchema("string"),
                                        "pixel_width": nonnegativeIntegerSchema, "pixel_height": nonnegativeIntegerSchema,
                                    ], required: ["mime_type", "data", "pixel_width", "pixel_height"])),
                        ],
                        required: [
                            "triptych_id", "note_id", "attachment_id", "filename", "note_fingerprint", "fingerprint", "kind", "page", "total_pages", "text",
                            "text_available",
                            "start_utf8", "end_utf8", "total_utf8", "has_more", "image",
                        ])
                ]
            case .listLinks:
                [
                    successSchema(
                        properties: [
                            "triptych_id": uuidSchema("Open Triptych UUID."),
                            "note_id": uuidSchema("Stable Note UUID."),
                            "direction": simpleSchema("string"),
                            "graph_generation": nullable(nonnegativeIntegerSchema),
                            "offset": nonnegativeIntegerSchema,
                            "limit": nonnegativeIntegerSchema,
                            "has_more": booleanSchema,
                            "links": arraySchema(
                                closedObject(
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
                    )
                ]
            case .createNote:
                [
                    successSchema(
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
                    )
                ]
            case .updateNote:
                [
                    successSchema(
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
                    )
                ]
            case .moveNote:
                [
                    successSchema(
                        properties: [
                            "triptych_id": uuidSchema("Open Triptych UUID."), "note_id": uuidSchema("Stable Note UUID."),
                            "change_id": uuidSchema("Agent Change UUID."),
                            "source_relative_path": simpleSchema("string"), "relative_path": simpleSchema("string"), "before_fingerprint": fingerprintSchema,
                            "after_fingerprint": fingerprintSchema,
                            "readback_verified": booleanSchema, "effects": arraySchema(moveEffectSchema),
                            "derived_refresh_warning": nullable(simpleSchema("string")),
                        ],
                        required: [
                            "triptych_id", "note_id", "change_id", "source_relative_path", "relative_path", "before_fingerprint", "after_fingerprint",
                            "readback_verified", "effects", "derived_refresh_warning",
                        ])
                ]
            case .previewMove:
                [
                    successSchema(
                        properties: [
                            "triptych_id": uuidSchema("Open Triptych UUID."), "note_id": uuidSchema("Stable Note UUID."), "role": roleSchema,
                            "source_relative_path": simpleSchema("string"), "relative_path": simpleSchema("string"), "fingerprint": fingerprintSchema,
                            "plan_fingerprint": fingerprintSchema, "can_move": booleanSchema, "offset": nonnegativeIntegerSchema,
                            "limit": nonnegativeIntegerSchema,
                            "total": nonnegativeIntegerSchema, "has_more": booleanSchema,
                            "entries": arraySchema(
                                closedObject(
                                    properties: [
                                        "kind": .object([
                                            "type": .string("string"), "enum": .array(["move", "link_rewrite", "blocked"].map(MCPJSONValue.string)),
                                        ]),
                                        "note_id": nullable(uuidSchema("Affected stable Note UUID.")), "role": roleSchema,
                                        "source_relative_path": simpleSchema("string"),
                                        "relative_path": nullable(simpleSchema("string")), "before_fingerprint": nullable(fingerprintSchema),
                                        "after_fingerprint": nullable(fingerprintSchema),
                                        "rewritten_occurrences": nonnegativeIntegerSchema, "source_locator": nullable(locatorSchema),
                                        "reason": nullable(simpleSchema("string")),
                                    ],
                                    required: [
                                        "kind", "note_id", "role", "source_relative_path", "relative_path", "before_fingerprint", "after_fingerprint",
                                        "rewritten_occurrences", "source_locator", "reason",
                                    ])),
                        ],
                        required: [
                            "triptych_id", "note_id", "role", "source_relative_path", "relative_path", "fingerprint", "plan_fingerprint", "can_move", "offset",
                            "limit", "total", "has_more", "entries",
                        ])
                ]
            case .listChanges:
                [
                    successSchema(
                        properties: [
                            "triptych_id": uuidSchema("Open Triptych UUID."), "note_id": nullable(uuidSchema("Stable Note UUID.")),
                            "listing_fingerprint": fingerprintSchema, "offset": nonnegativeIntegerSchema, "limit": nonnegativeIntegerSchema,
                            "total": nonnegativeIntegerSchema, "has_more": booleanSchema, "changes": arraySchema(changeReceiptSchema),
                        ],
                        required: ["triptych_id", "note_id", "listing_fingerprint", "offset", "limit", "total", "has_more", "changes"])
                ]
            case .readChange:
                [
                    successSchema(
                        properties: [
                            "triptych_id": uuidSchema("Open Triptych UUID."), "change": changeReceiptSchema,
                            "ending_revision_state": nullable(
                                .object(["type": .string("string"), "enum": .array(["current", "earlier_revision", "unavailable"].map(MCPJSONValue.string))])),
                            "can_undo": booleanSchema, "comparison": nullable(changeComparisonSchema),
                            "comparison_note_id": uuidSchema("Selected comparison Note UUID."), "undo_unavailable_reason": nullable(simpleSchema("string")),
                            "effects": closedObject(
                                properties: [
                                    "offset": nonnegativeIntegerSchema, "limit": nonnegativeIntegerSchema, "total": nonnegativeIntegerSchema,
                                    "has_more": booleanSchema, "entries": arraySchema(moveEffectSchema),
                                ], required: ["offset", "limit", "total", "has_more", "entries"]),
                        ],
                        required: [
                            "triptych_id", "change", "ending_revision_state", "can_undo", "comparison", "comparison_note_id", "undo_unavailable_reason",
                            "effects",
                        ])
                ]
            case .undoChange:
                [
                    successSchema(
                        properties: [
                            "triptych_id": uuidSchema("Open Triptych UUID."), "note_id": uuidSchema("Stable Note UUID."),
                            "change_id": uuidSchema("Original Agent Change UUID."), "relative_path": simpleSchema("string"),
                            "source_relative_path": simpleSchema("string"), "effects": arraySchema(moveEffectSchema),
                            "before_fingerprint": fingerprintSchema, "after_fingerprint": fingerprintSchema, "readback_verified": booleanSchema,
                            "undone": booleanSchema,
                        ],
                        required: [
                            "triptych_id", "note_id", "change_id", "relative_path", "before_fingerprint", "after_fingerprint", "readback_verified", "undone",
                            "source_relative_path", "effects",
                        ])
                ]
            case .trashNote:
                [
                    successSchema(
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
                    )
                ]
            }
        return .object([
            "type": .string("object"),
            "oneOf": .array(successes + [tool == .observeCurrentState ? chatObservationFailureSchema : failureSchema]),
        ])
    }

    private static func forbiddenContextFields(_ keys: [String]) -> MCPJSONValue {
        .object(["anyOf": .array(keys.map { .object(["required": .array([.string($0)])]) })])
    }

    private static func contextObject(_ properties: [String: MCPJSONValue]) -> MCPJSONValue {
        closedObject(properties: properties, required: properties.keys.sorted())
    }

    private static func contextPageSchema(_ item: MCPJSONValue) -> MCPJSONValue {
        contextObject([
            "offset": nonnegativeIntegerSchema, "limit": integerSchema(minimum: 1, maximum: 100, default: 20),
            "total": nonnegativeIntegerSchema, "has_more": booleanSchema, "next_offset": nullable(nonnegativeIntegerSchema),
            "items": .object(["type": .string("array"), "maxItems": .integer(100), "items": item]),
        ])
    }

    private static func contextListingSchema(_ item: MCPJSONValue) -> MCPJSONValue {
        var fields = contextPageSchema(item).objectValue!["properties"]!.objectValue!
        fields["listing_fingerprint"] = fingerprintSchema
        return contextObject(fields)
    }

    private static var contextNoteReferenceSchema: MCPJSONValue {
        contextObject([
            "vault_id": uuidSchema("Source vault UUID."), "note_id": nullable(uuidSchema("Stable Note UUID, unavailable when unresolved.")),
            "role": roleSchema, "relative_path": boundedStringSchema(maximum: 4_096),
        ])
    }

    private static var contextActiveNoteSchema: MCPJSONValue {
        var schema = chatObservationSchema.objectValue!["properties"]!.objectValue!["active_note"]!.objectValue!["anyOf"]!.arrayValue![0].objectValue!
        var fields = schema["properties"]!.objectValue!
        for key in ["dirty", "saving", "conflict"] { fields[key] = nullable(booleanSchema) }
        schema["properties"] = .object(fields)
        return .object(schema)
    }

    private static var contextTabSchema: MCPJSONValue {
        var fields = contextNoteReferenceSchema.objectValue!["properties"]!.objectValue!
        let active = contextActiveNoteSchema.objectValue!["properties"]!.objectValue!
        for key in ["mode", "revision", "dirty", "saving", "conflict"] { fields[key] = active[key] }
        return contextObject([
            "tab_id": uuidSchema("Presentation tab UUID."), "selected": booleanSchema,
            "document_surface": enumSchema(["triptych_note", "unavailable"]), "note": nullable(contextObject(fields)),
            "errors": arraySchema(enumSchema(["document_save", "document_conflict"])),
        ])
    }

    private static var contextWindowSummarySchema: MCPJSONValue {
        contextObject([
            "window_id": uuidSchema("Registered window UUID."), "kind": nullable(enumSchema(["main", "document"])),
            "selected_tab_id": nullable(uuidSchema("Selected tab UUID.")), "tab_count": nullable(nonnegativeIntegerSchema),
            "restoring": nullable(booleanSchema), "transferring": nullable(booleanSchema), "closing": nullable(booleanSchema), "available": booleanSchema,
        ])
    }

    private static var contextWindowSchema: MCPJSONValue {
        var fields = contextWindowSummarySchema.objectValue!["properties"]!.objectValue!
        fields.removeValue(forKey: "available")
        fields["kind"] = enumSchema(["main", "document"])
        fields["tab_count"] = nonnegativeIntegerSchema
        for key in ["restoring", "transferring", "closing"] { fields[key] = booleanSchema }
        fields["selected_role"] = roleSchema
        fields["sidebar"] = contextObject(["visible": booleanSchema, "content": enumSchema(["library", "chat"])])
        fields["inspector"] = contextObject(["visible": booleanSchema, "mode": enumSchema(["links", "related"])])
        fields["focus_layout"] = booleanSchema
        fields["software"] = contextObject(["version": nullable(simpleSchema("string")), "build": nullable(simpleSchema("string"))])
        var recovery: [String: MCPJSONValue] = ["snapshot_available": booleanSchema, "identity_recovering": booleanSchema]
        for key in [
            "pending_changes_count", "agent_changes_count", "transaction_recovery_count", "interrupted_save_recovery_count", "attention_count",
            "identity_ambiguity_count", "identity_pending_rebinding_count", "identity_migration_failure_count",
        ] {
            recovery[key] = nullable(nonnegativeIntegerSchema)
        }
        recovery["errors"] = arraySchema(
            enumSchema(["agent_changes", "pending_changes", "transaction_recovery", "interrupted_save_recovery", "note_identity"]))
        fields["recovery"] = contextObject(recovery)
        let generation = nullable(contextObject(["sequence": nonnegativeIntegerSchema, "manifest_sha256": simpleSchema("string")]))
        fields["workspace"] = contextObject([
            "availability": enumSchema(["unavailable", "opening", "complete"]), "phase": enumSchema(["unavailable", "opening", "complete"]),
            "generated_at": nullable(simpleSchema("string")), "refreshing": booleanSchema,
            "derived_state": enumSchema(["unavailable", "opening", "current", "stale", "failed"]),
            "search_generation": generation, "graph_generation": generation,
            "errors": arraySchema(enumSchema(["catalog", "access_recovery", "workspace_recovery"])),
        ])
        fields["errors"] = arraySchema(enumSchema(["window_session", "operation_issue"]))
        return contextObject(fields)
    }

    private static var contextLocatorSchema: MCPJSONValue {
        var fields = ["start_utf16": nonnegativeIntegerSchema, "end_utf16": nonnegativeIntegerSchema]
        for key in ["start_line", "start_column", "end_line", "end_column"] {
            fields[key] = .object(["type": .string("integer"), "minimum": .integer(1)])
        }
        return contextObject(fields)
    }

    private static var contextLibrarySchema: MCPJSONValue {
        contextObject([
            "role": roleSchema, "source_scope": enumSchema(["library"]), "loading": booleanSchema, "has_error": booleanSchema,
            "unavailable_reference_count": nonnegativeIntegerSchema,
            "selection": contextPageSchema(
                contextObject([
                    "kind": enumSchema(["note", "folder_or_unavailable"]), "vault_id": uuidSchema("Selected vault UUID."),
                    "relative_path": boundedStringSchema(maximum: 4_096), "note": nullable(contextNoteReferenceSchema),
                ])),
        ])
    }

    private static var contextSearchSchema: MCPJSONValue {
        contextObject([
            "scope": enumSchema(["triptych", "thisNote", "currentVault"]), "query_present": booleanSchema, "query_text_omitted": enumBooleanTrue,
            "running": booleanSchema, "availability": enumSchema(["unavailable", "building", "current", "limited", "refreshing", "stale", "failed"]),
            "has_error": booleanSchema, "has_more_results": booleanSchema, "unavailable_reference_count": nonnegativeIntegerSchema,
            "indeterminate_document_count": nonnegativeIntegerSchema,
            "results": contextPageSchema(
                contextObject([
                    "result_id": simpleSchema("string"), "selected": booleanSchema, "note": contextNoteReferenceSchema,
                    "fingerprint": fingerprintSchema, "source_locator": nullable(contextLocatorSchema),
                ])),
        ])
    }

    private static var contextRelatedSchema: MCPJSONValue {
        contextObject([
            "loading": booleanSchema, "did_search": booleanSchema, "has_error": booleanSchema, "needs_refresh": booleanSchema,
            "context_changed": booleanSchema, "omitted_count": nonnegativeIntegerSchema, "seed_text_omitted": enumBooleanTrue,
            "unavailable_reference_count": nonnegativeIntegerSchema,
            "passages": contextPageSchema(
                contextObject([
                    "passage_id": simpleSchema("string"), "note": contextNoteReferenceSchema, "fingerprint": fingerprintSchema,
                    "source_locator": contextLocatorSchema,
                ])),
        ])
    }

    private static var contextKeptSchema: MCPJSONValue {
        contextObject([
            "has_error": booleanSchema, "unavailable_reference_count": nonnegativeIntegerSchema,
            "passages": contextPageSchema(
                contextObject([
                    "kept_passage_id": boundedStringSchema(maximum: 8_192), "note": contextNoteReferenceSchema, "fingerprint": fingerprintSchema,
                    "source_locator": contextLocatorSchema, "action_locator": contextLocatorSchema, "origin": enumSchema(["kept_snapshot"]),
                ])),
        ])
    }

    private static var contextReadLocatorSchema: MCPJSONValue {
        let ranges = contextActiveNoteSchema.objectValue!["properties"]!.objectValue!["selection"]!.objectValue!["oneOf"]!.arrayValue!
        return .object([
            "oneOf": .array([
                contextLocatorSchema, ranges[1],
                contextObject(["state": enumSchema(["whole_note"]), "start_utf8": nonnegativeIntegerSchema, "end_utf8": nonnegativeIntegerSchema]),
            ])
        ])
    }

    private static var enumBooleanTrue: MCPJSONValue { .object(["type": .string("boolean"), "const": .bool(true)]) }

    private static var noteContextSchema: MCPJSONValue {
        closedObject(properties: ["attachments": attachmentListingSchema], required: ["attachments"])
    }

    private static var chatObservationSchema: MCPJSONValue {
        let availableRevision = closedObject(
            properties: ["origin": enumSchema(["saved_source", "editor_snapshot"]), "fingerprint": fingerprintSchema],
            required: ["origin", "fingerprint"])
        let unavailableRevision = closedObject(
            properties: [
                "origin": enumSchema(["unavailable"]),
                "reason": enumSchema(["loading", "composing", "source_snapshot_unavailable"]),
            ], required: ["origin", "reason"])
        let noSelection = closedObject(properties: ["state": enumSchema(["none"])], required: ["state"])
        let unavailableSelection = closedObject(
            properties: [
                "state": enumSchema(["unavailable"]),
                "reason": enumSchema(["loading", "composing", "multiple_selections", "stale_renderer", "source_mapping_unavailable"]),
            ], required: ["state", "reason"])
        let positiveInteger: MCPJSONValue = .object(["type": .string("integer"), "minimum": .integer(1)])
        let selectedRange = closedObject(
            properties: [
                "state": enumSchema(["range"]), "start_utf8": nonnegativeIntegerSchema,
                "end_utf8": positiveInteger, "byte_count": positiveInteger,
                "start_line": positiveInteger, "end_line": positiveInteger,
            ], required: ["state", "start_utf8", "end_utf8", "byte_count", "start_line", "end_line"])
        var note =
            closedObject(
                properties: [
                    "vault_id": uuidSchema("Active Note vault UUID."), "note_id": uuidSchema("Active Note UUID."),
                    "role": roleSchema, "relative_path": boundedStringSchema(maximum: 4_096),
                    "mode": enumSchema(["review", "edit", "source"]),
                    "revision": .object(["oneOf": .array([availableRevision, unavailableRevision])]),
                    "dirty": booleanSchema, "saving": booleanSchema, "conflict": booleanSchema,
                    "selection": .object(["oneOf": .array([noSelection, selectedRange, unavailableSelection])]),
                ], required: ["vault_id", "note_id", "role", "relative_path", "mode", "revision", "dirty", "saving", "conflict", "selection"]
            ).objectValue ?? [:]
        note["allOf"] = .array([
            .object([
                "if": .object([
                    "properties": .object([
                        "selection": .object(["properties": .object(["state": enumSchema(["range"])])])
                    ])
                ]),
                "then": .object(["properties": .object(["revision": availableRevision])]),
            ])
        ])
        let activeNote = MCPJSONValue.object(note)
        let errors: MCPJSONValue = .object([
            "type": .string("array"), "uniqueItems": .bool(true), "maxItems": .integer(9),
            "items": enumSchema([
                "connection", "history_load", "history_save", "material_cleanup", "history_refresh",
                "execution", "queued_input", "document_save", "document_conflict",
            ]),
        ])
        let chat = closedObject(
            properties: [
                "thread_id": boundedStringSchema(maximum: 512), "turn_id": boundedStringSchema(maximum: 512),
                "state": .object(["type": .string("string"), "const": .string("working")]), "pending_delivery": booleanSchema,
                "queued_message_count": nonnegativeIntegerSchema, "approval_count": nonnegativeIntegerSchema,
                "question_count": nonnegativeIntegerSchema, "errors": errors,
            ], required: ["thread_id", "turn_id", "state", "pending_delivery", "queued_message_count", "approval_count", "question_count", "errors"])
        var result =
            successSchema(
                properties: [
                    "triptych_id": uuidSchema("Admitted Triptych UUID."), "window_id": uuidSchema("Originating window UUID."),
                    "conversation_id": uuidSchema("Admitted conversation UUID."),
                    "observed_at": .object(["type": .string("string"), "format": .string("date-time")]),
                    "document_surface": enumSchema(["none", "triptych_note", "external_document", "unavailable"]),
                    "active_note": nullable(activeNote), "chat": chat,
                ], required: ["triptych_id", "window_id", "conversation_id", "observed_at", "document_surface", "active_note", "chat"]
            ).objectValue ?? [:]
        result["allOf"] = .array([
            .object([
                "if": .object(["properties": .object(["document_surface": enumSchema(["triptych_note"])])]),
                "then": .object(["properties": .object(["active_note": activeNote])]),
                "else": .object(["properties": .object(["active_note": simpleSchema("null")])]),
            ])
        ])
        return .object(result)
    }

    private static var chatObservationFailureSchema: MCPJSONValue {
        closedObject(
            properties: [
                "schema_version": .object(["type": .string("integer"), "const": .integer(ScholiumMCPContract.currentToolSchemaVersion)]),
                "status": .object(["type": .string("string"), "const": .string("failed")]),
                "code": enumSchema(["app_unavailable", "workspace_not_ready", "stale_revision", "invalid_request", "permission_denied", "internal_error"]),
                "message": boundedStringSchema(maximum: 1_024), "recovery": boundedStringSchema(maximum: 1_024),
            ], required: ["schema_version", "status", "code", "message", "recovery"])
    }

    private static func boundedStringSchema(maximum: Int) -> MCPJSONValue {
        .object(["type": .string("string"), "minLength": .integer(1), "maxLength": .integer(maximum)])
    }

    private static var attachmentListingSchema: MCPJSONValue {
        successSchema(
            properties: [
                "triptych_id": uuidSchema("Triptych UUID."), "note_id": uuidSchema("Note UUID."),
                "note_fingerprint": fingerprintSchema, "listing_fingerprint": fingerprintSchema,
                "offset": nonnegativeIntegerSchema, "total": nonnegativeIntegerSchema, "has_more": booleanSchema,
                "attachments": arraySchema(
                    closedObject(
                        properties: [
                            "attachment_id": uuidSchema("Attachment UUID."),
                            "filename": simpleSchema("string"),
                            "relationship": .object(["type": .string("string"), "enum": .array([.string("document"), .string("authoredImage")])]),
                            "available": booleanSchema,
                        ], required: ["attachment_id", "filename", "relationship", "available"])),
            ],
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

    private static let recoveryDetailsSchema = closedObject(
        properties: [
            "recovery_id": uuidSchema("Existing recovery record UUID."), "total": nonnegativeIntegerSchema, "has_more": booleanSchema,
            "files": arraySchema(
                closedObject(
                    properties: [
                        "vault_id": nullable(uuidSchema("Affected vault UUID.")), "path": simpleSchema("string"),
                        "alternate_path": nullable(simpleSchema("string")), "role": simpleSchema("string"), "before_fingerprint": nullable(fingerprintSchema),
                        "intended_fingerprint": nullable(fingerprintSchema), "observed_fingerprint": nullable(fingerprintSchema),
                        "state": simpleSchema("string"), "detail": simpleSchema("string"),
                    ],
                    required: [
                        "vault_id", "path", "alternate_path", "role", "before_fingerprint", "intended_fingerprint", "observed_fingerprint", "state", "detail",
                    ])),
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
            ])
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
            "manifest_sha256": simpleSchema("string")
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
