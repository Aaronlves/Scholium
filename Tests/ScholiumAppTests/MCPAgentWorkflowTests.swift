import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp
@testable import ScholiumApplication

extension MCPAppBridgeRequestRouterTests {
    @Test("Agent discovery, paged reading, exact editing, verification and Undo use the authenticated bridge")
    func authenticatedAgentEditWorkflow() async throws {
        let repeated = "Repeat 原文 e\u{301} 📝 [citation](zotero://select/library/items/ABCD1234).\r\n"
        let prefix = "\u{feff}---\r\ntitle: 'Exact' # retain\r\nunknown: |\r\n  Keep this value.\r\n---\r\n# Analysis\r\n\r\n"
        let source = prefix + repeated + repeated
        try await withAgentWorkflowFixture(source: source) { fixture in
            try await withAgentWorkflowBridge(fixture) { handler in
                let (_, discovery) = try await agentWorkflowRPC(handler, method: "tools/list", params: [:])
                let tools = try #require(discovery["tools"]?.arrayValue)
                #expect(tools.count == 19)
                let readTool = try #require(tools.first { $0.objectValue?["name"] == .string("scholium_read_note") }?.objectValue)
                #expect(readTool["inputSchema"]?.objectValue?["properties"]?.objectValue?["expected_fingerprint"] != nil)
                let status = try await agentWorkflowCall(handler, tool: .workspaceStatus, arguments: [:])
                let scope: [String: MCPJSONValue] = ["triptych_id": try #require(status["triptych_id"])]
                let browse = try await agentWorkflowCall(handler, tool: .browse, arguments: scope.merging(["role": .string("analyses")]) { _, new in new })
                let entry = try #require(browse["entries"]?.arrayValue?.first?.objectValue)
                let noteScope = scope.merging(["note_id": try #require(entry["note_id"])]) { _, new in new }
                var readArgs = noteScope.merging([
                    "line_count": .integer(8), "expected_fingerprint": try #require(entry["fingerprint"]),
                ]) { _, new in new }
                let first = try await agentWorkflowCall(handler, tool: .readNote, arguments: readArgs)
                readArgs["start_line"] = first["next_line"]
                let second = try await agentWorkflowCall(handler, tool: .readNote, arguments: readArgs)
                #expect(first["source"] == .string(prefix + repeated))
                #expect(second["source"] == .string(repeated) && second["complete"] == .bool(true))
                let replacement = repeated.replacingOccurrences(of: "Repeat", with: "Revised")
                let edit: MCPJSONValue = .object([
                    "start_utf8": try #require(second["start_utf8"]), "end_utf8": try #require(second["end_utf8"]),
                    "expected_text": .string(repeated), "replacement": .string(replacement),
                ])
                var update = noteScope.merging([
                    "expected_fingerprint": try #require(second["fingerprint"]), "mode": .string("edits"), "edits": .array([edit]),
                ]) { _, new in new }
                let invalid = update.merging(["edits": .array([edit, .object([
                    "start_utf8": .integer(1), "end_utf8": .integer(2), "expected_text": .string(""), "replacement": .string("bad"),
                ])])]) { _, new in new }
                #expect(try await agentWorkflowCall(handler, tool: .updateNote, arguments: invalid, failed: true)["code"] == .string("invalid_request"))
                let changed = try await agentWorkflowCall(handler, tool: .updateNote, arguments: update)
                let expectedSource = prefix + repeated + replacement
                let saved = try await agentWorkflowCall(handler, tool: .readNote, arguments: noteScope.merging([
                    "expected_fingerprint": try #require(changed["after_fingerprint"]),
                ]) { _, new in new })
                #expect(saved["source"] == .string(expectedSource))
                #expect(saved["fingerprint"] == changed["after_fingerprint"])
                #expect(try await agentWorkflowCall(handler, tool: .updateNote, arguments: update, failed: true)["code"] == .string("stale_revision"))
                update["expected_fingerprint"] = saved["fingerprint"]
                update["mode"] = .string("source")
                update["edits"] = nil
                update["content"] = .string(expectedSource)
                #expect(try await agentWorkflowCall(handler, tool: .updateNote, arguments: update, failed: true)["code"] == .string("no_changes"))
                let changes = try await agentWorkflowCall(handler, tool: .listChanges, arguments: noteScope)
                #expect(changes["total"] == .integer(1))
                let undo = noteScope.merging([
                    "change_id": try #require(changed["change_id"]), "expected_fingerprint": try #require(saved["fingerprint"]),
                ]) { _, new in new }
                _ = try await agentWorkflowCall(handler, tool: .undoChange, arguments: undo)
                let restored = try await agentWorkflowCall(handler, tool: .readNote, arguments: noteScope)
                #expect(restored["source"] == .string(source) && restored["fingerprint"] == first["fingerprint"])
                let file = fixture.topicsURL.deletingLastPathComponent().appendingPathComponent("Analyses/Alpha.md")
                #expect(try Data(contentsOf: file) == Data(source.utf8))
            }
        }
    }

    @Test("A dense long-line link page fits the MCP reply while preserving complete authored occurrences")
    func boundedLinkContextWorkflow() async throws {
        let padding = String(repeating: "字e\u{301}📝", count: 48)
        let annotations = (0..<100).map { $0 == 0 ? String(repeating: "原文", count: 150) : "Reason \($0)." }
        let source = "# Alpha\r\n\r\n" + annotations.map { padding + "[[Topic]]{{" + $0 + "}} " }.joined() + "\r\n"
        try await withAgentWorkflowFixture(source: source) { fixture in
            let router = MCPAppBridgeRequestRouter(
                runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
            let args: [String: MCPJSONValue] = [
                "triptych_id": .string(fixture.assignment.id.uuidString), "note_id": .string(fixture.analysisNoteID.uuidString), "direction": .string("outgoing"),
            ]
            let raw = try result(await router.handle(.init(tool: .listLinks, arguments: args)))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let structured = MCPJSONValue.object(raw)
            let wire: MCPJSONValue = .object([
                "jsonrpc": .string("2.0"), "id": .integer(1), "result": .object([
                    "content": .array([.object(["type": .string("text"), "text": .string(String(decoding: try encoder.encode(structured), as: UTF8.self))])]),
                    "structuredContent": structured, "isError": .bool(false),
                ]),
            ])
            print("MCP_LINK_PAYLOAD source_utf8=\(source.utf8.count) occurrences=100 structured_utf8=\(try encoder.encode(structured).count) wire_utf8=\(try encoder.encode(wire).count)")
            try await withAgentWorkflowBridge(fixture) { handler in
                let page = try await agentWorkflowCall(handler, tool: .listLinks, arguments: args)
                let links = try #require(page["links"]?.arrayValue)
                #expect(links.count == 100 && page["has_more"] == .bool(false))
                for (index, link) in links.enumerated() {
                    let row = try #require(link.objectValue)
                    let context = try #require(row["local_context"]?.stringValue)
                    #expect(context.utf8.count <= 512 && !context.contains("\u{fffd}"))
                    #expect(row["local_context_truncated"] == .bool(true))
                    #expect(row["link_markup"] == .string("[[Topic]]"))
                    #expect(row["annotation_text"] == .string(annotations[index]))
                    #expect(row["occurrence_markup"] == .string("[[Topic]]{{" + annotations[index] + "}}"))
                    #expect(row["source_fingerprint"]?.objectValue?["sha256"] == .string(fixture.analysisFingerprint.sha256))
                    #expect(row["source_fingerprint"]?.objectValue?["byte_count"] == .integer(source.utf8.count))
                }
                #expect(try encoder.encode(wire).count < ScholiumMCPContract.maximumEncodedMessageByteCount)
            }
        }
    }

    @Test("Revision-bound Note reads refuse stale discovery and continuation before returning source")
    func revisionBoundNoteReads() async throws {
        let source = "\u{feff}---\r\ntitle: 'Exact' # retain\r\n---\r\n原文 e\u{301} 📝\r\nSecond page.\r\n"
        try await withAgentWorkflowFixture(source: source) { fixture in
            let router = MCPAppBridgeRequestRouter(
                runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
            let scope: [String: MCPJSONValue] = [
                "triptych_id": .string(fixture.assignment.id.uuidString), "note_id": .string(fixture.analysisNoteID.uuidString),
            ]
            let first = try result(await router.handle(.init(tool: .readNote, arguments: scope.merging(["line_count": .integer(4)]) { _, new in new })))
            let fingerprint = try #require(first["fingerprint"])
            var continuation = scope.merging([
                "start_line": try #require(first["next_line"]), "expected_fingerprint": fingerprint,
            ]) { _, new in new }
            let same = await router.handle(.init(tool: .readNote, arguments: continuation))
            #expect(same.error == nil)
            #expect(same.result?.objectValue?["source"] == .string("Second page.\r\n"))

            let file = fixture.topicsURL.deletingLastPathComponent().appendingPathComponent("Analyses/Alpha.md")
            let changed = source.replacingOccurrences(of: "Second page.", with: "Concurrent revision.")
            try Data(changed.utf8).write(to: file)
            let stale = await router.handle(.init(tool: .readNote, arguments: continuation))
            #expect(stale.error?.code == .staleRevision)
            #expect(stale.result == nil)
            continuation["expected_fingerprint"] = nil
            let fresh = try result(await router.handle(.init(tool: .readNote, arguments: continuation)))
            #expect(fresh["source"] == .string("Concurrent revision.\r\n"))
            continuation["expected_fingerprint"] = fresh["fingerprint"]
            #expect(try result(await router.handle(.init(tool: .readNote, arguments: continuation))) == fresh)
            #expect(try Data(contentsOf: file) == Data(changed.utf8))
            let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
            #expect(try await handle.agentCollaboration.agentChanges().isEmpty)
        }
    }

    @Test("Malformed read fingerprints fail before workspace reconciliation")
    func malformedReadFingerprints() async throws {
        var reconciliations = 0
        let runtime = WorkspaceRuntime(configuration: .live(.init(applicationSupportURL: URL(fileURLWithPath: "/nonexistent"))))
        let router = MCPAppBridgeRequestRouter(
            runtime: runtime, flushEditors: { _ in reconciliations += 1 }, openTriptychs: { [] })
        for value: MCPJSONValue in [
            .null, .string("sha256"), .object(["sha256": .string(String(repeating: "A", count: 64)), "byte_count": .integer(1)]),
            .object(["sha256": .string(String(repeating: "a", count: 64)), "byte_count": .integer(-1)]),
            .object(["sha256": .string(String(repeating: "a", count: 64)), "byte_count": .integer(1), "extra": .bool(true)]),
        ] {
            let response = await router.handle(.init(tool: .readNote, arguments: [
                "triptych_id": .string(UUID().uuidString), "note_id": .string(UUID().uuidString), "expected_fingerprint": value,
            ]))
            #expect(response.error?.code == .invalidRequest)
            #expect(response.result == nil)
        }
        #expect(reconciliations == 0)
        await runtime.shutdown()
    }

    private func withAgentWorkflowFixture(
        source: String, _ body: @MainActor (Fixture) async throws -> Void
    ) async throws {
        let fixture = try await Fixture.make(exactAnalysis: source)
        do {
            try await body(fixture)
        } catch {
            await fixture.runtime.shutdown()
            try FileManager.default.trashItem(at: fixture.root, resultingItemURL: nil)
            throw error
        }
        await fixture.runtime.shutdown()
        try FileManager.default.trashItem(at: fixture.root, resultingItemURL: nil)
    }

    private func withAgentWorkflowBridge(
        _ fixture: Fixture, _ body: @MainActor (AgentMCPService.Handler) async throws -> Void
    ) async throws {
        let router = MCPAppBridgeRequestRouter(
            runtime: fixture.runtime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
        let bridgeRoot = fixture.root.appendingPathComponent("Bridge")
        let server = try ScholiumAppBridgeServer(applicationSupportURL: bridgeRoot) { request in await router.handle(request) }
        do {
            let handler = try AgentMCPService.helperHandler(
                arguments: ["mcp", "serve"], environment: ["SCHOLIUM_APP_BRIDGE_CONTAINER": bridgeRoot.path])
            try await body(handler)
        } catch {
            _ = await server.stopAndWait(timeout: 2)
            throw error
        }
        #expect(await server.stopAndWait(timeout: 2))
    }

    private func agentWorkflowRPC(
        _ handler: AgentMCPService.Handler, method: String, params: [String: MCPJSONValue]
    ) async throws -> (Data, [String: MCPJSONValue]) {
        let request: MCPJSONValue = .object([
            "jsonrpc": .string("2.0"), "id": .integer(1), "method": .string(method), "params": .object(params),
        ])
        let response = try #require(await handler(JSONEncoder().encode(request)))
        let result = try #require(try JSONDecoder().decode(MCPJSONValue.self, from: response).objectValue?["result"]?.objectValue)
        return (response, result)
    }

    private func agentWorkflowCall(
        _ handler: AgentMCPService.Handler, tool: ScholiumMCPToolName, arguments: [String: MCPJSONValue], failed: Bool = false
    ) async throws -> [String: MCPJSONValue] {
        let (_, result) = try await agentWorkflowRPC(handler, method: "tools/call", params: ["name": .string(tool.rawValue), "arguments": .object(arguments)])
        #expect(result["isError"] == .bool(failed))
        return try #require(result["structuredContent"]?.objectValue)
    }
}
