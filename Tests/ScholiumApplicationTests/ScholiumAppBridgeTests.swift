import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Scholium App bridge", .serialized)
struct ScholiumAppBridgeTests {
    @Test("A committed Note write stays uncertain when its bridge confirmation is unavailable", arguments: BridgeConfirmationFailure.allCases)
    func committedWriteLosesConfirmation(_ scenario: BridgeConfirmationFailure) async throws {
        let root = try makeRoot("lost-confirmation-\(scenario.rawValue)")
        defer { try? FileManager.default.removeItem(at: root) }
        let analyses = root.appendingPathComponent("Analyses")
        let topics = root.appendingPathComponent("Topics")
        let works = root.appendingPathComponent("Works")
        for directory in [analyses, topics, works] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let noteURL = topics.appendingPathComponent("Note.md")
        try Data("# Before\n".utf8).write(to: noteURL)
        let committedBytes = Data("# After\nExact committed source.\n".utf8)
        let runtime = WorkspaceRuntime(
            configuration: .live(
                .init(
                    applicationSupportURL: root.appendingPathComponent("Support"),
                    workspaceRegistryStorageURL: root.appendingPathComponent("Registry"))))
        defer { Task { await runtime.shutdown() } }
        let handle = try await runtime.configureTriptych(
            paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
            portableContainerURL: root, triptychName: "Lost Confirmation Fixture")
        let snapshot = try await handle.refresh()
        let note = try #require(snapshot.vaults.flatMap(\.documents).first { $0.id.relativePath == "Note.md" })
        let noteID = try #require(note.stableIdentity.resolvedID)
        let agent = handle.agentCollaboration
        let gate = BridgeOperationGate()
        let bridgeRoot = root.appendingPathComponent("Bridge")
        let server = try ScholiumAppBridgeServer(
            applicationSupportURL: bridgeRoot, operationTimeout: scenario == .deadline ? 1 : 5
        ) { request in
            _ = try await agent.updateNote(
                noteID: noteID, expectedFingerprint: note.fingerprint,
                update: .source(String(decoding: committedBytes, as: UTF8.self)))
            await gate.enterAndWait()
            switch scenario {
            case .eof, .deadline:
                return try Self.success(for: request)
            case .mismatchedRequest:
                return try ScholiumMCPBridgeResponse(requestID: UUID(), result: .object(["status": .string("ok")]))
            case .missingOutcome, .bothOutcomes, .unsupportedVersion:
                // Fault injection at the existing handler boundary: the current
                // synthesized decoder accepts a response with no outcome.
                var fields: [String: MCPJSONValue] = [
                    "schemaVersion": .integer(ScholiumMCPBridgeResponse.currentSchemaVersion),
                    "requestID": .string(request.mcpRequest.requestID.uuidString),
                ]
                if scenario == .bothOutcomes {
                    fields["result"] = .object(["status": .string("ok")])
                    fields["error"] = try JSONDecoder().decode(
                        MCPJSONValue.self,
                        from: JSONEncoder().encode(
                            ScholiumMCPFailure(
                                code: .staleRevision, message: "An invalid simultaneous refusal.", recovery: "Read the Note.")))
                } else if scenario == .unsupportedVersion {
                    fields["schemaVersion"] = .integer(ScholiumMCPBridgeResponse.currentSchemaVersion + 1)
                    fields["result"] = .object(["status": .string("ok")])
                }
                return try JSONDecoder().decode(ScholiumMCPBridgeResponse.self, from: JSONEncoder().encode(MCPJSONValue.object(fields)))
            }
        }
        defer { server.stop() }
        let bridge = try MCPBridgeOperations(applicationSupportURL: bridgeRoot)
        let mcp = ScholiumMCPServer(bridge: bridge)
        let call = Task { try await Self.callTool(.updateNote, server: mcp) }
        let releaseDeadline = Task {
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            await gate.release()
            await gate.expireEntryWait()
        }
        await gate.waitForEntry()
        let entered = await gate.didEnter()
        if scenario == .eof { server.stop() }
        if scenario != .deadline { await gate.release() }
        let response: MCPJSONValue
        do {
            response = try await call.value
        } catch {
            await gate.release()
            releaseDeadline.cancel()
            await releaseDeadline.value
            _ = await server.stopAndWait(timeout: 1)
            await runtime.shutdown()
            throw error
        }
        await gate.release()
        releaseDeadline.cancel()
        await releaseDeadline.value
        #expect(await server.stopAndWait(timeout: 1))
        let changes = try await agent.agentChanges()
        await runtime.shutdown()

        #expect(entered, "The real Note mutation must commit before the confirmation fault.")
        #expect(try Data(contentsOf: noteURL) == committedBytes)
        #expect(changes.count == 1 && changes.first?.state == .confirmed)
        #expect(changes.first?.afterFingerprint == DocumentFingerprint(data: committedBytes))
        let result = try #require(response.objectValue?["result"]?.objectValue)
        #expect(result["isError"] == .bool(true))
        let failure = try #require(result["structuredContent"]?.objectValue)
        #expect(failure["code"] == .string(ScholiumMCPFailureCode.operationUncertain.rawValue))
        #expect(failure["recovery"]?.stringValue?.contains("Do not retry automatically") == true)
    }

    @Test("A valid domain refusal and a missing pre-dispatch bridge keep their definite failure meaning")
    func definiteBridgeFailuresRemainDefinite() async throws {
        let root = try makeRoot("definite-failures")
        defer { try? FileManager.default.removeItem(at: root) }
        let server = try ScholiumAppBridgeServer(applicationSupportURL: root) { request in
            try ScholiumMCPBridgeResponse(
                requestID: request.mcpRequest.requestID,
                error: .init(code: .staleRevision, message: "The Note changed.", recovery: "Read the current Note."))
        }
        defer { server.stop() }
        let bridge = try MCPBridgeOperations(applicationSupportURL: root)
        let response = try await Self.callTool(.updateNote, server: ScholiumMCPServer(bridge: bridge))
        #expect(response.objectValue?["result"]?.objectValue?["structuredContent"]?.objectValue?["code"] == .string("stale_revision"))
        #expect(await server.stopAndWait(timeout: 1))
        let missing = try MCPBridgeOperations(applicationSupportURL: root.appendingPathComponent("Missing"))
        let unavailable = try await Self.callTool(.updateNote, server: ScholiumMCPServer(bridge: missing))
        #expect(unavailable.objectValue?["result"]?.objectValue?["structuredContent"]?.objectValue?["code"] == .string("app_unavailable"))
    }

    private static func callTool(_ tool: ScholiumMCPToolName, server: ScholiumMCPServer) async throws -> MCPJSONValue {
        let request: MCPJSONValue = .object([
            "jsonrpc": .string("2.0"), "id": .integer(1), "method": .string("tools/call"),
            "params": .object(["name": .string(tool.rawValue), "arguments": .object([:])]),
        ])
        let response = try #require(await server.handle(requestData: JSONEncoder().encode(request)))
        return try JSONDecoder().decode(MCPJSONValue.self, from: response)
    }

    @Test("An authenticated request waiting for input does not block another connection")
    func concurrentRequests() async throws {
        let root = try makeRoot("concurrent")
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = BridgeOperationGate()
        let server = try ScholiumAppBridgeServer(applicationSupportURL: root, timeout: 5, operationTimeout: 25) { request in
            if request.mcpRequest.tool == .updateNote { await gate.enterAndWait() }
            return try Self.success(for: request)
        }
        defer { server.stop() }
        let first = Task { try await Self.send(.updateNote, root: root, timeout: 30) }
        await gate.waitForEntry()
        var second: ScholiumAppBridgeResponse?
        var secondError: Error?
        do { second = try await Self.send(.search, root: root, timeout: 10) } catch { secondError = error }
        await gate.release()
        _ = try await first.value
        #expect(secondError == nil, "Second connection failed: \(String(describing: secondError))")
        #expect(second?.mcpResponse?.result?.objectValue?["status"] == .string("ok"))
        #expect(await server.stopAndWait(timeout: 1))
    }

    @Test("Shutdown reports its deadline even when an admitted operation must finish later")
    func boundedDrain() async throws {
        let root = try makeRoot("bounded-drain")
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = BridgeOperationGate()
        let server = try ScholiumAppBridgeServer(applicationSupportURL: root, timeout: 1, operationTimeout: 3) { request in
            await gate.enterAndWait()
            return try Self.success(for: request)
        }
        let first = Task { try? await Self.send(.updateNote, root: root) }
        await gate.waitForEntry()
        // Bound the regression itself if a broken drain ignores its deadline.
        let releaseDeadline = Task {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            await gate.release()
        }
        let drained = await server.stopAndWait(timeout: 0.1)
        #expect(!drained)
        await gate.release()
        releaseDeadline.cancel()
        await releaseDeadline.value
        _ = await first.value
        #expect(await server.stopAndWait(timeout: 1))
    }

    private static func send(_ tool: ScholiumMCPToolName, root: URL, timeout: TimeInterval = 2)
        async throws -> ScholiumAppBridgeResponse
    {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let client = try ScholiumAppBridgeClient(applicationSupportURL: root, timeout: timeout)
                    continuation.resume(returning: try client.send(.init(mcpRequest: .init(tool: tool))))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    @Test("A bounded current-state operation may outlast transport IO timeout")
    func boundedSlowOperationCompletes() async throws {
        let root = try makeRoot("slow-operation")
        defer { try? FileManager.default.removeItem(at: root) }

        let server = try ScholiumAppBridgeServer(applicationSupportURL: root) { request in
            try await Task.sleep(for: .seconds(5.25))
            return try ScholiumMCPBridgeResponse(
                requestID: request.mcpRequest.requestID,
                result: .object([
                    "schema_version": .integer(2),
                    "status": .string("ok"),
                ])
            )
        }
        defer { server.stop() }

        let client = try ScholiumAppBridgeClient(applicationSupportURL: root)
        let response = try client.send(
            ScholiumAppBridgeRequest(
                mcpRequest: ScholiumMCPBridgeRequest(tool: .search)
            ))

        #expect(response.mcpResponse?.result?.objectValue?["status"] == .string("ok"))
    }

    @Test("A stopped bridge can immediately bind the same private endpoint")
    func immediateRestartRebinds() async throws {
        let root = try makeRoot("immediate-restart")
        defer { try? FileManager.default.removeItem(at: root) }

        let first = try ScholiumAppBridgeServer(applicationSupportURL: root) {
            try Self.success(for: $0)
        }
        let firstClient = try ScholiumAppBridgeClient(applicationSupportURL: root)
        _ = try firstClient.send(
            ScholiumAppBridgeRequest(
                mcpRequest: ScholiumMCPBridgeRequest(tool: .workspaceStatus)
            ))
        #expect(await first.stopAndWait(timeout: 1))

        let second = try ScholiumAppBridgeServer(applicationSupportURL: root) {
            try Self.success(for: $0)
        }
        defer { second.stop() }
        let secondClient = try ScholiumAppBridgeClient(applicationSupportURL: root)
        let response = try secondClient.send(
            ScholiumAppBridgeRequest(
                mcpRequest: ScholiumMCPBridgeRequest(tool: .workspaceStatus)
            ))

        #expect(response.mcpResponse?.result?.objectValue?["status"] == .string("ok"))
    }

    private static func success(
        for request: ScholiumAppBridgeRequest
    ) throws -> ScholiumMCPBridgeResponse {
        try ScholiumMCPBridgeResponse(
            requestID: request.mcpRequest.requestID,
            result: .object([
                "schema_version": .integer(2),
                "status": .string("ok"),
            ])
        )
    }

    private func makeRoot(_ name: String) throws -> URL {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root =
            repositoryRoot
            .appendingPathComponent(".build/app-bridge-tests", isDirectory: true)
            .appendingPathComponent("\(name)-\(UUID().uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: root.path
        )
        return root
    }
}

/// Models a transaction that must finish despite cancellation; entry is synchronized.
private actor BridgeOperationGate {
    private var entered = false
    private var entryExpired = false
    private var open = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var operationWaiter: CheckedContinuation<Void, Never>?
    func waitForEntry() async {
        if entered || entryExpired { return }
        await withCheckedContinuation { entryWaiter = $0 }
    }
    func enterAndWait() async {
        entered = true
        entryWaiter?.resume()
        entryWaiter = nil
        if open { return }
        await withCheckedContinuation { operationWaiter = $0 }
    }
    func release() {
        open = true
        operationWaiter?.resume()
        operationWaiter = nil
    }
    func didEnter() -> Bool { entered }
    func expireEntryWait() {
        entryExpired = true
        entryWaiter?.resume()
        entryWaiter = nil
    }
}

enum BridgeConfirmationFailure: String, CaseIterable, Sendable {
    case eof, deadline, mismatchedRequest, missingOutcome, bothOutcomes, unsupportedVersion
}
