import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Scholium App bridge", .serialized)
struct ScholiumAppBridgeTests {
    @Test("An authenticated request waiting for input does not block another connection")
    func concurrentRequests() async throws {
        let root = try makeRoot("concurrent")
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = BridgeOperationGate()
        let server = try ScholiumAppBridgeServer(applicationSupportURL: root, timeout: 1, operationTimeout: 3) { request in
            if request.mcpRequest.tool == .updateNote { await gate.enterAndWait() }
            return try Self.success(for: request)
        }
        defer { server.stop() }
        let first = Task { try await Self.send(.updateNote, root: root) }
        await gate.waitForEntry()
        var second: ScholiumAppBridgeResponse?
        do { second = try await Self.send(.search, root: root, timeout: 0.5) } catch {}
        await gate.release()
        _ = try await first.value
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
    private var open = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var operationWaiter: CheckedContinuation<Void, Never>?
    func waitForEntry() async {
        if entered { return }
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
}
