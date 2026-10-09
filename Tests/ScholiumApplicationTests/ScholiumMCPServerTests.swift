import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Scholium stdio MCP")
struct ScholiumMCPServerTests {
    @Test("Context tools expose closed nested state schemas and exact kind-bound inputs")
    func contextContractsAreDiscoverable() async throws {
        let server = ScholiumMCPServer { _ in .object([:]) }
        let listed = try await rpc(server, id: 1, method: "tools/list", params: [:])
        let tools = try #require(object(listed["result"])["tools"] as? [[String: Any]])
        func checkClosed(_ value: Any) {
            if let schema = value as? [String: Any] {
                if schema["type"] as? String == "object" {
                    #expect(schema["properties"] != nil || schema["oneOf"] != nil)
                    if let fields = schema["properties"] as? [String: Any] {
                        #expect(schema["additionalProperties"] as? Bool == false)
                        #expect(Set(schema["required"] as? [String] ?? []) == Set(fields.keys.filter { $0 != "recovery_details" }))
                    }
                }
                for child in schema.values { checkClosed(child) }
            } else if let array = value as? [Any] {
                array.forEach(checkClosed)
            }
        }
        for name in ["scholium_observe_workspace", "scholium_observe_research_context", "scholium_read_context"] {
            let tool = try #require(tools.first { $0["name"] as? String == name })
            checkClosed(try object(tool["outputSchema"]))
            let annotations = try object(tool["annotations"])
            #expect(annotations["readOnlyHint"] as? Bool == true)
            #expect(annotations["destructiveHint"] as? Bool == false)
        }
        let read = try #require(tools.first { $0["name"] as? String == "scholium_read_context" })
        let input = try object(read["inputSchema"])
        let properties = try object(input["properties"])
        #expect(try object(properties["expected_start_utf8"])["default"] == nil)
        #expect(try object(properties["expected_end_utf8"])["default"] == nil)
        let alternatives = try #require(input["oneOf"] as? [[String: Any]])
        #expect(alternatives.count == 3 && alternatives.allSatisfy { $0["not"] != nil })
        let workspace = try #require(tools.first { $0["name"] as? String == "scholium_observe_workspace" })
        #expect(try object(workspace["inputSchema"])["required"] as? [String] == [])
    }
    @Test("Search tool advertises the shared generic YAML query contract")
    func searchPropertyCapability() async throws {
        let server = ScholiumMCPServer { _ in .object([:]) }
        let listed = try await rpc(server, id: 1, method: "tools/list", params: [:])
        let tools = try #require(object(listed["result"])["tools"] as? [[String: Any]])
        let search = try #require(tools.first { $0["name"] as? String == "scholium_search" })
        let schema = try object(search["inputSchema"])
        let query = try object(object(schema["properties"])["query"])
        let description = try #require(query["description"] as? String)
        #expect(description.contains(SearchCapabilities.current.propertyQueryHelp))
        #expect(description.contains(SearchCapabilities.current.booleanQueryHelp))
        for example in SearchCapabilities.current.capability(for: .note)?.examples ?? [] {
            #expect(description.contains(example))
            #expect(SearchQueryParser.parse(example).isValid)
        }
    }

    @Test("Attachment images reach MCP as native image content while text describes their scope")
    func attachmentImageDelivery() async throws {
        let image: MCPJSONValue = .object(["mime_type": .string("image/png"), "data": .string("cG5n"), "pixel_width": .integer(1), "pixel_height": .integer(1)])
        let server = ScholiumMCPServer { _ in .object(["kind": .string("pdf_page_image"), "page": .integer(2), "image": image]) }
        let response = try await rpc(server, id: 1, method: "tools/call", params: ["name": "scholium_read_attachment", "arguments": [:]])
        let result = try object(response["result"])
        let content = try #require(result["content"] as? [[String: Any]])
        #expect(content.count == 2 && content[1]["type"] as? String == "image" && content[1]["mimeType"] as? String == "image/png")
        #expect(content[1]["data"] as? String == "cG5n")
        #expect(content[0]["text"] as? String != nil && (content[0]["text"] as? String)?.contains("cG5n") == false)
        #expect(try object(object(result["structuredContent"])["image"])["data"] as? String == "cG5n")
    }

    @Test("Partial move recovery returns bounded per-file outcomes without claiming successful mutation")
    func moveRecoveryIsStructured() async throws {
        let before = DocumentFingerprint(content: "Before")
        let intended = DocumentFingerprint(content: "After")
        let record = TriptychMutationRecoveryRecord(
            triptychID: UUID(), operation: .noteMove, failure: "Synthetic rollback interruption",
            files: (0..<101).map { index in
                .init(
                    vaultID: UUID(), path: "Note\(index).md", alternatePath: index == 0 ? "Moved.md" : nil,
                    role: index == 0 ? .movedNote : .incomingLinkRewrite, beforeRevision: before, intendedRevision: intended,
                    observedRevision: index == 0 ? intended : before, state: index == 0 ? .intendedBytesRemain : .restored, detail: "Synthetic readback")
            })
        let failure = ScholiumMCPFailure(
            code: .operationUncertain, message: record.failure,
            recovery: "Inspect the retained Recovery record before another mutation.", recoveryDetails: .init(record: record))
        let transported = try JSONDecoder().decode(ScholiumMCPFailure.self, from: JSONEncoder().encode(failure))
        let server = ScholiumMCPServer { _ in throw transported }
        let response = try await rpc(server, id: 1, method: "tools/call", params: ["name": "scholium_move_note", "arguments": [:]])
        let result = try object(response["result"])
        #expect(result["isError"] as? Bool == true)
        let structured = try object(result["structuredContent"])
        #expect(structured["code"] as? String == "operation_uncertain" && structured["readback_verified"] == nil)
        let recovery = try object(structured["recovery_details"])
        #expect(recovery["recovery_id"] as? String == record.id.uuidString.lowercased())
        #expect(recovery["total"] as? Int == 101 && recovery["has_more"] as? Bool == true)
        let files = try #require(recovery["files"] as? [[String: Any]])
        #expect(files.count == 100 && files[0]["state"] as? String == "intendedBytesRemain")
        #expect(files[1]["state"] as? String == "restored")
        #expect(try object(files[0]["observed_fingerprint"])["sha256"] as? String == intended.sha256)
        #expect(try object(files[1]["observed_fingerprint"])["sha256"] as? String == before.sha256)
    }

    @Test("Initialization and discovery publish exactly the fixed local tool surface")
    func discoveryIsDataFreeAndClosed() async throws {
        let recorder = MCPRequestRecorder()
        let server = ScholiumMCPServer { request in
            await recorder.record(request)
            return .object(["schema_version": .integer(ScholiumMCPContract.currentToolSchemaVersion), "status": .string("ok")])
        }

        let initialized = try await rpc(
            server,
            id: 1,
            method: "initialize",
            params: ["protocolVersion": "2025-11-25"]
        )
        let result = try object(initialized["result"])
        #expect(result["protocolVersion"] as? String == "2025-11-25")
        #expect(try object(result["serverInfo"])["name"] as? String == "scholium")
        #expect((result["instructions"] as? String)?.contains("workspace_status") == true)

        let listed = try await rpc(server, id: 2, method: "tools/list", params: [:])
        let listResult = try object(listed["result"])
        let tools = try #require(listResult["tools"] as? [[String: Any]])
        let externalTools = ScholiumMCPToolName.allCases.filter { !$0.isChatControl }
        #expect(tools.compactMap { $0["name"] as? String } == externalTools.map(\.rawValue))
        #expect(tools.count == externalTools.count)
        let read = try #require(tools.first { $0["name"] as? String == "scholium_read_note" })
        let readProperties = try object(object(read["inputSchema"])["properties"])
        #expect(try object(readProperties["include_context"])["default"] as? Bool == false)
        let readVariants = try #require(object(read["outputSchema"])["oneOf"] as? [[String: Any]])
        #expect(try object(readVariants[0]["properties"])["context"] != nil)
        for tool in tools {
            let schema = try object(tool["inputSchema"])
            #expect(schema["additionalProperties"] as? Bool == false)
            let outputSchema = try object(tool["outputSchema"])
            #expect(outputSchema["type"] as? String == "object")
            let variants = try #require(
                outputSchema["oneOf"] as? [[String: Any]]
            )
            #expect(!variants.isEmpty)
            #expect(
                variants.allSatisfy {
                    $0["additionalProperties"] as? Bool == false
                })
            let annotations = try object(tool["annotations"])
            #expect(annotations["openWorldHint"] as? Bool == false)
        }
        let update = try #require(tools.first { $0["name"] as? String == "scholium_update_note" })
        let input = try object(update["inputSchema"])
        let alternatives = try #require(input["oneOf"] as? [[String: Any]])
        #expect(alternatives.count == 2)
        for branch in alternatives {
            let fields = try object(branch["properties"])
            #expect(fields["content"] != nil && fields["expected_fingerprint"] != nil)
            let required = Set(try #require(branch["required"] as? [String]))
            #expect(required.isSuperset(of: ["triptych_id", "note_id", "expected_fingerprint", "mode"]))
            #expect(required.contains("content") || required.contains("edits"))
        }
        let properties = try object(input["properties"])
        let edits = try object(properties["edits"])
        #expect(edits["maxItems"] as? Int == 100)
        let edit = try object(edits["items"])
        #expect(edit["additionalProperties"] as? Bool == false)
        #expect(Set(try #require(edit["required"] as? [String])) == Set(["start_utf8", "end_utf8", "expected_text", "replacement"]))
        let show = try #require(tools.first { $0["name"] as? String == "scholium_show_note" })
        #expect(try object(show["inputSchema"])["oneOf"] as? [[String: Any]] != nil)
        #expect(try object(show["annotations"])["readOnlyHint"] as? Bool == false)
        #expect(try object(show["annotations"])["idempotentHint"] as? Bool == false)
        #expect(await recorder.requests().isEmpty)
    }

    @Test("In-app Chat publishes capability controls and binds every call to its conversation token")
    func chatCapabilitySurface() async throws {
        let recorder = MCPRequestRecorder()
        let token = UUID()
        let server = ScholiumMCPServer(conversationToken: token) { request in
            await recorder.record(request)
            return .object(["schema_version": .integer(ScholiumMCPContract.currentToolSchemaVersion), "status": .string("ok")])
        }
        let listed = try await rpc(server, id: 1, method: "tools/list", params: [:])
        let tools = try #require(try object(listed["result"])["tools"] as? [[String: Any]])
        let names = tools.compactMap { $0["name"] as? String }
        #expect(names == ScholiumMCPToolName.allCases.map(\.rawValue))
        for tool in tools {
            #expect(try object(tool["outputSchema"])["type"] as? String == "object")
        }
        #expect(
            Array(names.suffix(5)) == [
                ScholiumMCPToolName.capabilities.rawValue,
                ScholiumMCPToolName.configureSkill.rawValue,
                ScholiumMCPToolName.configureTool.rawValue,
                ScholiumMCPToolName.configureChat.rawValue,
                ScholiumMCPToolName.observeCurrentState.rawValue,
            ])
        for tool in tools.suffix(5) {
            let schema = try object(tool["inputSchema"])
            #expect(schema["additionalProperties"] as? Bool == false)
            #expect(try object(tool["outputSchema"])["oneOf"] as? [[String: Any]] != nil)
        }
        let toolControl = try #require(tools.first { $0["name"] as? String == ScholiumMCPToolName.configureTool.rawValue })
        let toolProperties = try object(try object(toolControl["inputSchema"])["properties"])
        #expect(try object(toolProperties["action"])["enum"] as? [String] == ["sign_in"])
        #expect(toolProperties["address"] == nil && toolProperties["args"] == nil && toolProperties["env_vars"] == nil)
        let toolOutputs = try #require(try object(toolControl["outputSchema"])["oneOf"] as? [[String: Any]])
        let toolSuccessProperties = try object(try #require(toolOutputs.first)["properties"])
        #expect(toolSuccessProperties["configuration"] == nil)
        #expect(try object(toolSuccessProperties["authorization_url"])["type"] as? String == "string")
        let chatControl = try #require(tools.first { $0["name"] as? String == ScholiumMCPToolName.configureChat.rawValue })
        let chatProperties = try object(try object(chatControl["inputSchema"])["properties"])
        #expect(try object(chatProperties["permission"])["enum"] as? [String] == ["ask"])
        _ = try await rpc(
            server, id: 2, method: "tools/call",
            params: [
                "name": ScholiumMCPToolName.capabilities.rawValue,
                "arguments": [:],
            ])
        let requests = await recorder.requests()
        #expect(requests.last?.conversationToken == token && requests.last?.tool == .capabilities)
    }

    @Test("Current-state observation publishes only bound metadata and closed safe failures")
    func chatObservationSchema() async throws {
        let server = ScholiumMCPServer(conversationToken: UUID()) { _ in .null }
        let listed = try await rpc(server, id: 1, method: "tools/list", params: [:])
        let tools = try #require(object(listed["result"])["tools"] as? [[String: Any]])
        let tool = try #require(tools.first { $0["name"] as? String == ScholiumMCPToolName.observeCurrentState.rawValue })
        let input = try object(tool["inputSchema"])
        let bindings: Set<String> = ["triptych_id", "window_id", "conversation_id"]
        #expect(Set(try object(input["properties"]).keys) == bindings)
        #expect(Set(try #require(input["required"] as? [String])) == bindings)
        #expect(input["additionalProperties"] as? Bool == false)
        for field in try object(input["properties"]).values {
            #expect(try object(field)["format"] as? String == "uuid")
        }
        let variants = try #require(object(tool["outputSchema"])["oneOf"] as? [[String: Any]])
        let success = try #require(variants.first)
        let fields = try object(success["properties"])
        #expect(Set(fields.keys) == bindings.union(["schema_version", "status", "observed_at", "document_surface", "active_note", "chat"]))
        #expect(try object(fields["observed_at"])["format"] as? String == "date-time")
        let chat = try object(fields["chat"])
        #expect(chat["additionalProperties"] as? Bool == false)
        let chatFields = try object(chat["properties"])
        #expect(
            Set(chatFields.keys) == ["thread_id", "turn_id", "state", "pending_delivery", "queued_message_count", "approval_count", "question_count", "errors"])
        #expect(try object(chatFields["state"])["const"] as? String == "working")
        #expect(try object(chatFields["errors"])["uniqueItems"] as? Bool == true)
        let activeVariants = try #require(object(fields["active_note"])["anyOf"] as? [[String: Any]])
        let note = try #require(activeVariants.first)
        #expect(note["additionalProperties"] as? Bool == false)
        let noteFields = try object(note["properties"])
        #expect(Set(noteFields.keys) == ["vault_id", "note_id", "role", "relative_path", "mode", "revision", "dirty", "saving", "conflict", "selection"])
        #expect(try object(noteFields["relative_path"])["maxLength"] as? Int == 4_096)
        let rangeRule = try #require((note["allOf"] as? [[String: Any]])?.first)
        let revision = try object(object(object(rangeRule["then"])["properties"])["revision"])
        #expect(Set(try #require(revision["required"] as? [String])) == ["origin", "fingerprint"])
        let failure = try #require(variants.last)
        #expect(failure["additionalProperties"] as? Bool == false)
        let failureFields = try object(failure["properties"])
        #expect(Set(failureFields.keys) == ["schema_version", "status", "code", "message", "recovery"])
        #expect(try object(failureFields["message"])["maxLength"] as? Int == 1_024)
        let annotations = try object(tool["annotations"])
        #expect(annotations["readOnlyHint"] as? Bool == true && annotations["destructiveHint"] as? Bool == false)
        #expect(AgentChatActivity.Kind.forTool(.observeCurrentState) == .tool)
    }

    @Test("External hosts cannot call the observation tool or reach its App owner")
    func externalObservationRejected() async throws {
        let recorder = MCPRequestRecorder()
        let server = ScholiumMCPServer { request in
            await recorder.record(request)
            return .null
        }
        let response = try await rpc(
            server, id: 1, method: "tools/call",
            params: [
                "name": ScholiumMCPToolName.observeCurrentState.rawValue,
                "arguments": ["triptych_id": UUID().uuidString, "window_id": UUID().uuidString, "conversation_id": UUID().uuidString],
            ])
        let result = try object(response["result"])
        let failure = try object(result["structuredContent"])
        #expect(result["isError"] as? Bool == true && failure["code"] as? String == "invalid_request")
        #expect(Set(failure.keys) == ["schema_version", "status", "code", "message", "recovery"])
        #expect(await recorder.requests().isEmpty)
    }

    @Test("Observation calls retain conversation and runtime scope through the helper")
    func observationBinding() async throws {
        let recorder = MCPRequestRecorder()
        let token = UUID()
        let triptych = UUID().uuidString
        let window = UUID().uuidString
        let conversation = UUID().uuidString
        let server = ScholiumMCPServer(conversationToken: token) { request in
            await recorder.record(request)
            return .object([
                "schema_version": .integer(ScholiumMCPContract.currentToolSchemaVersion), "status": .string("ok"),
                "triptych_id": .string(triptych), "window_id": .string(window), "conversation_id": .string(conversation),
                "observed_at": .string("2026-10-08T12:00:00Z"), "document_surface": .string("none"), "active_note": .null,
                "chat": .object([
                    "thread_id": .string("thread"), "turn_id": .string("turn"), "state": .string("working"),
                    "pending_delivery": .bool(false), "queued_message_count": .integer(0), "approval_count": .integer(0),
                    "question_count": .integer(0), "errors": .array([]),
                ]),
            ])
        }
        let response = try await rpc(
            server, id: 1, method: "tools/call",
            params: [
                "name": ScholiumMCPToolName.observeCurrentState.rawValue,
                "arguments": ["triptych_id": triptych, "window_id": window, "conversation_id": conversation],
                "_meta": ["x-codex-turn-metadata": ["thread_id": "thread", "turn_id": "turn"]],
            ])
        let result = try object(response["result"])
        #expect(result["isError"] as? Bool == false)
        let request = try #require(await recorder.requests().first)
        #expect(request.conversationToken == token && request.tool == .observeCurrentState)
        #expect(request.runtimeContext == .init(threadID: "thread", turnID: "turn"))
        #expect(request.arguments == ["triptych_id": .string(triptych), "window_id": .string(window), "conversation_id": .string(conversation)])
        let content = try #require(result["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        #expect(
            try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .withoutEscapingSlashes]).count
                <= ScholiumMCPContract.maximumChatObservationUTF8ByteCount)
        #expect(try object(JSONSerialization.jsonObject(with: Data(text.utf8)))["window_id"] as? String == window)
    }

    @Test("Observation caps the encoded MCP result after text duplication and Unicode escaping")
    func observationEncodedResultBound() async throws {
        let relativePath = String(repeating: "a\"📝/", count: 1_000) + "note.md"
        #expect(relativePath.unicodeScalars.count <= 4_096)
        let triptych = UUID().uuidString
        let window = UUID().uuidString
        let conversation = UUID().uuidString
        let metadata: MCPJSONValue = .object([
            "schema_version": .integer(ScholiumMCPContract.currentToolSchemaVersion), "status": .string("ok"),
            "triptych_id": .string(triptych), "window_id": .string(window), "conversation_id": .string(conversation),
            "observed_at": .string("2026-10-08T12:00:00Z"), "document_surface": .string("triptych_note"),
            "active_note": .object([
                "vault_id": .string(UUID().uuidString), "note_id": .string(UUID().uuidString),
                "role": .string("works"), "relative_path": .string(relativePath), "mode": .string("review"),
                "revision": .object([
                    "origin": .string("saved_source"),
                    "fingerprint": .object(["sha256": .string(String(repeating: "a", count: 64)), "byte_count": .integer(1)]),
                ]),
                "dirty": .bool(false), "saving": .bool(false), "conflict": .bool(false),
                "selection": .object(["state": .string("none")]),
            ]),
            "chat": .object([
                "thread_id": .string("thread"), "turn_id": .string("turn"), "state": .string("working"),
                "pending_delivery": .bool(false), "queued_message_count": .integer(0), "approval_count": .integer(0),
                "question_count": .integer(0), "errors": .array([]),
            ]),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let raw = try encoder.encode(metadata)
        #expect(raw.count <= ScholiumMCPContract.maximumChatObservationUTF8ByteCount)
        let unboundedResult: MCPJSONValue = .object([
            "content": .array([.object(["type": .string("text"), "text": .string(String(decoding: raw, as: UTF8.self))])]),
            "structuredContent": metadata, "isError": .bool(false),
        ])
        #expect(try encoder.encode(unboundedResult).count > ScholiumMCPContract.maximumChatObservationUTF8ByteCount)
        let server = ScholiumMCPServer(conversationToken: UUID()) { _ in metadata }
        let response = try await rpc(
            server, id: 1, method: "tools/call",
            params: [
                "name": ScholiumMCPToolName.observeCurrentState.rawValue,
                "arguments": ["triptych_id": triptych, "window_id": window, "conversation_id": conversation],
            ])
        let result = try object(response["result"])
        #expect(result["isError"] as? Bool == true)
        #expect(try object(result["structuredContent"])["code"] as? String == "invalid_request")
        let encoded = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .withoutEscapingSlashes])
        #expect(encoded.count <= ScholiumMCPContract.maximumChatObservationUTF8ByteCount)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("📝"))
    }

    @Test("Observation failures discard raw diagnostics and oversized results", arguments: [false, true])
    func observationFailureContainment(oversized: Bool) async throws {
        let marker = "private-diagnostic-marker"
        let server = ScholiumMCPServer(conversationToken: UUID()) { _ in
            if oversized { return .object(["oversized": .string(String(repeating: marker, count: 1_000))]) }
            throw ScholiumMCPFailure(code: .operationUncertain, message: marker, recovery: marker)
        }
        let response = try await rpc(
            server, id: 1, method: "tools/call",
            params: [
                "name": ScholiumMCPToolName.observeCurrentState.rawValue,
                "arguments": ["triptych_id": UUID().uuidString, "window_id": UUID().uuidString, "conversation_id": UUID().uuidString],
            ])
        let result = try object(response["result"])
        #expect(result["isError"] as? Bool == true)
        let failure = try object(result["structuredContent"])
        #expect(failure["code"] as? String == (oversized ? "invalid_request" : "internal_error"))
        #expect(Set(failure.keys) == ["schema_version", "status", "code", "message", "recovery"])
        #expect(!String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self).contains(marker))
    }

    @Test("Tool calls carry only the named tool and argument object to the App bridge")
    func toolCallDelegatesToAppBridge() async throws {
        let recorder = MCPRequestRecorder()
        let server = ScholiumMCPServer { request in
            await recorder.record(request)
            return .object([
                "schema_version": .integer(ScholiumMCPContract.currentToolSchemaVersion),
                "status": .string("ok"),
                "current": .bool(false),
            ])
        }
        let response = try await rpc(
            server,
            id: 1,
            method: "tools/call",
            params: [
                "name": ScholiumMCPToolName.workspaceStatus.rawValue,
                "arguments": [:],
            ]
        )
        let result = try object(response["result"])
        #expect(result["isError"] as? Bool == false)
        let structured = try object(result["structuredContent"])
        #expect(structured["status"] as? String == "ok")
        let requests = await recorder.requests()
        #expect(requests.count == 1)
        #expect(requests[0].tool == .workspaceStatus)
        #expect(requests[0].arguments.isEmpty)
    }

    @Test("Runtime turn metadata stays separate from tool arguments across the bridge")
    func runtimeContextIsTransportMetadata() async throws {
        let recorder = MCPRequestRecorder()
        let server = ScholiumMCPServer { request in
            await recorder.record(request)
            return .object(["status": .string("ok")])
        }
        _ = try await rpc(
            server, id: 1, method: "tools/call",
            params: [
                "name": ScholiumMCPToolName.workspaceStatus.rawValue,
                "arguments": [:],
                "_meta": ["x-codex-turn-metadata": ["thread_id": "thread-1", "turn_id": "turn-1"]],
            ])
        _ = try await rpc(
            server, id: 2, method: "tools/call",
            params: [
                "name": ScholiumMCPToolName.workspaceStatus.rawValue,
                "arguments": [:],
                "_meta": ["x-codex-turn-metadata": ["thread_id": "thread-1", "turn_id": ""]],
            ])
        let requests = await recorder.requests()
        #expect(requests[0].runtimeContext == .init(threadID: "thread-1", turnID: "turn-1"))
        #expect(requests.allSatisfy { $0.arguments.isEmpty && $0.conversationToken == nil })
        #expect(requests[1].runtimeContext == nil)
        let decoded = try JSONDecoder().decode(ScholiumMCPBridgeRequest.self, from: JSONEncoder().encode(requests[0]))
        #expect(decoded == requests[0] && decoded.schemaVersion == 3)
    }

    @Test("Expected App failures remain structured MCP tool failures")
    func domainFailureIsStructured() async throws {
        let server = ScholiumMCPServer { _ in
            throw ScholiumMCPFailure(
                code: .workspaceNotReady,
                message: "No open Triptych.",
                recovery: "Open one Triptych."
            )
        }
        let response = try await rpc(
            server,
            id: 1,
            method: "tools/call",
            params: [
                "name": ScholiumMCPToolName.workspaceStatus.rawValue,
                "arguments": [:],
            ]
        )
        let result = try object(response["result"])
        #expect(result["isError"] as? Bool == true)
        let structured = try object(result["structuredContent"])
        #expect(structured["schema_version"] as? Int == ScholiumMCPContract.currentToolSchemaVersion)
        #expect(structured["status"] as? String == "failed")
        #expect(structured["code"] as? String == "workspace_not_ready")
        #expect(structured["recovery"] as? String == "Open one Triptych.")
    }

    private func rpc(
        _ server: ScholiumMCPServer,
        id: Int,
        method: String,
        params: [String: Any]
    ) async throws -> [String: Any] {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ]
        let data = try JSONSerialization.data(withJSONObject: request)
        let responseData = try #require(await server.handle(requestData: data))
        return try #require(
            JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        )
    }

    private func object(_ value: Any?) throws -> [String: Any] {
        try #require(value as? [String: Any])
    }
}

private actor MCPRequestRecorder {
    private var values: [ScholiumMCPBridgeRequest] = []

    func record(_ request: ScholiumMCPBridgeRequest) {
        values.append(request)
    }

    func requests() -> [ScholiumMCPBridgeRequest] { values }
}
