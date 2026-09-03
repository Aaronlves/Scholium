import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApplication

@Suite("Scholium App bridge", .serialized)
struct ScholiumAppBridgeTests {
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
        let response = try client.send(ScholiumAppBridgeRequest(
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
        _ = try firstClient.send(ScholiumAppBridgeRequest(
            mcpRequest: ScholiumMCPBridgeRequest(tool: .workspaceStatus)
        ))
        #expect(await first.stopAndWait(timeout: 1))

        let second = try ScholiumAppBridgeServer(applicationSupportURL: root) {
            try Self.success(for: $0)
        }
        defer { second.stop() }
        let secondClient = try ScholiumAppBridgeClient(applicationSupportURL: root)
        let response = try secondClient.send(ScholiumAppBridgeRequest(
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
        let root = repositoryRoot
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
