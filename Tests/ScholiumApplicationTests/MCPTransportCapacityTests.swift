import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("MCP encoded transport capacity", .serialized)
struct MCPTransportCapacityTests {
    @Test("A maximum exact edit and its escaped source reply traverse the authenticated bridge")
    func escapedMaximumSourceRoundTrip() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = String(repeating: "\u{0001}", count: ScholiumMCPContract.maximumDocumentUTF8ByteCount)
        let after = String(repeating: "\u{0002}", count: ScholiumMCPContract.maximumDocumentUTF8ByteCount)
        let edit = AgentSourceEdit(startUTF8: 0, endUTF8: before.utf8.count, expectedText: before, replacement: after)
        #expect(try AgentSourceEdit.applying([edit], to: Data(before.utf8)) == after)
        let arguments: [String: MCPJSONValue] = [
            "triptych_id": .string(UUID().uuidString), "note_id": .string(UUID().uuidString),
            "expected_fingerprint": .object([
                "sha256": .string(DocumentFingerprint(content: before).sha256), "byte_count": .integer(before.utf8.count),
            ]),
            "mode": .string("edits"),
            "edits": .array([
                .object([
                    "start_utf8": .integer(0), "end_utf8": .integer(before.utf8.count),
                    "expected_text": .string(before), "replacement": .string(after),
                ])
            ]),
        ]
        let server = try ScholiumAppBridgeServer(applicationSupportURL: root) { request in
            #expect(request.mcpRequest.arguments == arguments)
            return try .init(
                requestID: request.mcpRequest.requestID,
                result: .object([
                    "schema_version": .integer(ScholiumMCPContract.currentToolSchemaVersion), "status": .string("ok"), "source": .string(after),
                ]))
        }
        defer { server.stop() }
        let bridge = try MCPBridgeOperations(applicationSupportURL: root)
        let mcp = ScholiumMCPServer(bridge: bridge)
        let response = try #require(await mcp.handle(requestData: rpc(.updateNote, arguments: arguments)))
        #expect(response.count <= ScholiumMCPContract.maximumEncodedMessageByteCount)
        let value = try JSONDecoder().decode(MCPJSONValue.self, from: response)
        let result = try #require(value.objectValue?["result"]?.objectValue)
        #expect(result["isError"] == .bool(false))
        #expect(result["structuredContent"]?.objectValue?["source"] == .string(after))
        #expect(await server.stopAndWait(timeout: 1))
    }

    @Test("Oversized requests are refused before any bridge admission")
    func oversizedRequestHasNoEffects() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let noteURL = root.appendingPathComponent("Source.md")
        let before = Data("Exact preserved source.\n".utf8)
        try before.write(to: noteURL)
        let recorder = TransportAdmissionRecorder()
        let server = try ScholiumAppBridgeServer(applicationSupportURL: root) { request in
            await recorder.record()
            try Data("Prohibited mutation".utf8).write(to: noteURL)
            return try .init(requestID: request.mcpRequest.requestID, result: .object([:]))
        }
        defer { server.stop() }
        let request = ScholiumAppBridgeRequest(
            mcpRequest: .init(
                tool: .updateNote, arguments: ["content": .string(String(repeating: "x", count: ScholiumMCPContract.maximumEncodedMessageByteCount))]))
        let client = try ScholiumAppBridgeClient(applicationSupportURL: root)
        #expect(throws: ScholiumAppBridgeError.requestTooLarge) { try client.send(request) }
        #expect(await recorder.count == 0)
        #expect(try Data(contentsOf: noteURL) == before)
        let mcp = ScholiumMCPServer { _ in throw ScholiumAppBridgeError.requestTooLarge }
        let response = try #require(await mcp.handle(requestData: rpc(.updateNote)))
        let value = try JSONDecoder().decode(MCPJSONValue.self, from: response)
        #expect(value.objectValue?["result"]?.objectValue?["structuredContent"]?.objectValue?["code"] == .string("invalid_request"))
        #expect(await server.stopAndWait(timeout: 1))
    }

    @Test("An oversized bridge reply preserves definite reads and committed mutation evidence", arguments: [ScholiumMCPToolName.readNote, .updateNote])
    func oversizedBridgeReply(tool: ScholiumMCPToolName) async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let analyses = root.appendingPathComponent("Analyses")
        let topics = root.appendingPathComponent("Topics")
        let works = root.appendingPathComponent("Works")
        for directory in [analyses, topics, works] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let noteURL = topics.appendingPathComponent("Source.md")
        let before = Data("# Before\n".utf8)
        let after = Data("# After\n".utf8)
        try before.write(to: noteURL)
        let runtime = WorkspaceRuntime(
            configuration: .live(
                .init(
                    applicationSupportURL: root.appendingPathComponent("Support"), workspaceRegistryStorageURL: root.appendingPathComponent("Registry"))))
        let handle = try await runtime.configureTriptych(
            paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works, portableContainerURL: root, triptychName: "Encoded reply fixture")
        let snapshot = try await handle.refresh()
        let note = try #require(snapshot.vaults.flatMap(\.documents).first { $0.id.relativePath == "Source.md" })
        let noteID = try #require(note.stableIdentity.resolvedID)
        let agent = handle.agentCollaboration
        let server = try ScholiumAppBridgeServer(applicationSupportURL: root.appendingPathComponent("Bridge")) { request in
            if tool == .updateNote {
                _ = try await agent.updateNote(noteID: noteID, expectedFingerprint: note.fingerprint, update: .source(String(decoding: after, as: UTF8.self)))
            }
            return try .init(
                requestID: request.mcpRequest.requestID,
                result: .object([
                    "schema_version": .integer(ScholiumMCPContract.currentToolSchemaVersion), "status": .string("ok"),
                    "oversized_result": .string(String(repeating: "x", count: ScholiumMCPContract.maximumEncodedMessageByteCount)),
                ]))
        }
        defer { server.stop() }
        let mcp = ScholiumMCPServer(bridge: try MCPBridgeOperations(applicationSupportURL: root.appendingPathComponent("Bridge")))
        let raw = try #require(await mcp.handle(requestData: rpc(tool)))
        let response = try JSONDecoder().decode(MCPJSONValue.self, from: raw)
        #expect(
            response.objectValue?["result"]?.objectValue?["structuredContent"]?.objectValue?["code"]
                == .string(
                    tool == .updateNote ? "operation_uncertain" : "invalid_request"))
        #expect(try Data(contentsOf: noteURL) == (tool == .updateNote ? after : before))
        let changes = try await agent.agentChanges()
        #expect(changes.count == (tool == .updateNote ? 1 : 0))
        if tool == .updateNote { #expect(changes.first?.state == .confirmed && changes.first?.afterFingerprint == DocumentFingerprint(data: after)) }
        #expect(await server.stopAndWait(timeout: 1))
        await runtime.shutdown()
    }

    @Test("Complete MCP reply budgeting includes text and structured copies")
    func duplicatedReplyBudget() async throws {
        let row: MCPJSONValue = .object(["local_context": .string(String(repeating: "x", count: ScholiumMCPContract.maximumDocumentUTF8ByteCount))])
        let server = ScholiumMCPServer { _ in
            .object([
                "schema_version": .integer(ScholiumMCPContract.currentToolSchemaVersion), "status": .string("ok"),
                "links": .array(Array(repeating: row, count: 10)),
            ])
        }
        let raw = try #require(await server.handle(requestData: rpc(.listLinks)))
        #expect(raw.count <= ScholiumMCPContract.maximumEncodedMessageByteCount)
        let response = try JSONDecoder().decode(MCPJSONValue.self, from: raw)
        #expect(response.objectValue?["result"]?.objectValue?["structuredContent"]?.objectValue?["code"] == .string("invalid_request"))
    }

    @Test("Oversized response identities are refused before mutation admission", arguments: ["tools/list", "tools/call"])
    func oversizedIdentityHasNoEffects(method: String) async throws {
        let recorder = TransportAdmissionRecorder()
        let server = ScholiumMCPServer { _ in
            await recorder.record()
            return .object(["status": .string("ok")])
        }
        let request: MCPJSONValue = .object([
            "jsonrpc": .string("2.0"),
            "id": .string(String(repeating: "x", count: ScholiumMCPContract.maximumEncodedResponseIdentityByteCount)),
            "method": .string(method),
            "params": .object(["name": .string(ScholiumMCPToolName.updateNote.rawValue), "arguments": .object([:])]),
        ])
        let raw = try #require(await server.handle(requestData: JSONEncoder().encode(request)))
        #expect(raw.count <= ScholiumMCPContract.maximumEncodedMessageByteCount)
        let response = try JSONDecoder().decode(MCPJSONValue.self, from: raw)
        #expect(response.objectValue?["id"] == .null)
        #expect(response.objectValue?["error"]?.objectValue?["code"] == .integer(-32600))
        #expect(await recorder.count == 0)
    }

    @Test("An identity at the wire budget remains usable, including unescaped slashes", arguments: ["x", "/"])
    func admittedIdentityBoundary(character: String) async throws {
        let id = String(repeating: character, count: ScholiumMCPContract.maximumEncodedResponseIdentityByteCount - 2)
        let recorder = TransportAdmissionRecorder()
        let server = ScholiumMCPServer { _ in
            await recorder.record()
            return .object(["status": .string("ok")])
        }
        let request: MCPJSONValue = .object([
            "jsonrpc": .string("2.0"), "id": .string(id), "method": .string("tools/call"),
            "params": .object(["name": .string(ScholiumMCPToolName.readNote.rawValue), "arguments": .object([:])]),
        ])
        let raw = try #require(await server.handle(requestData: JSONEncoder().encode(request)))
        let response = try JSONDecoder().decode(MCPJSONValue.self, from: raw)
        #expect(response.objectValue?["id"] == .string(id))
        #expect(response.objectValue?["result"]?.objectValue?["isError"] == .bool(false))
        #expect(await recorder.count == 1)
    }

    private func rpc(_ tool: ScholiumMCPToolName, arguments: [String: MCPJSONValue] = [:]) throws -> Data {
        try JSONEncoder().encode(
            MCPJSONValue.object([
                "jsonrpc": .string("2.0"), "id": .integer(1), "method": .string("tools/call"),
                "params": .object(["name": .string(tool.rawValue), "arguments": .object(arguments)]),
            ]))
    }

    private func makeRoot() throws -> URL {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/mcp-transport-tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return root
    }
}

private actor TransportAdmissionRecorder {
    private(set) var count = 0
    func record() { count += 1 }
}
