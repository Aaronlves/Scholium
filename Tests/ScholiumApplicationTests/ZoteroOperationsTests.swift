import ScholiumContracts
import Foundation
import Testing
@testable import ScholiumApplication

@Suite("Runtime-owned Zotero operations")
struct ZoteroOperationsTests {
    @Test("Snapshot runtime owns one delivery-neutral Zotero capability")
    func runtimeOwnershipAndTransportReports() async throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let first = runtime.zotero
        let second = runtime.zotero

        #expect(first === second)
        #expect(first.descriptor == .supportedLocal)

        let environment = ["PATH": ""]
        let report = first.report(environment: environment)
        #expect(report.descriptorID == first.descriptor.identifier)
        #expect(report.state == .notConfigured)
        #expect(!report.liveHandshakePerformed)
        #expect(report.commandPath == nil)

        let probed = await first.probe(environment: environment, timeout: 0.01)
        #expect(probed == report)
        await runtime.shutdown()
    }

    @Test("Application request handling preserves the MCP delivery contract")
    func requestHandling() async throws {
        let fixture = try Fixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let operations = runtime.zotero
        let request = Data(
            #"{"jsonrpc":"2.0","id":7,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#.utf8
        )
        let response = try #require(await operations.handle(requestData: request))
        let object = try #require(
            JSONSerialization.jsonObject(with: response) as? [String: Any]
        )
        #expect(object["jsonrpc"] as? String == "2.0")
        #expect(object["id"] as? Int == 7)
        let result = try #require(object["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2024-11-05")
        let server = try #require(result["serverInfo"] as? [String: Any])
        #expect(server["name"] as? String == "scholium-zotero")
        #expect(server["version"] as? String == "0.1.0")

        let notification = Data(
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8
        )
        #expect(await operations.handle(requestData: notification) == nil)
        await runtime.shutdown()
    }
}

private struct Fixture {
    let rootURL: URL
    let supportURL: URL
    let registryURL: URL

    static func make() throws -> Self {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Scholium-ZoteroOperations-\(UUID().uuidString)",
            isDirectory: true
        )
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        let registry = root.appendingPathComponent("Registry", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return Self(rootURL: root, supportURL: support, registryURL: registry)
    }

    func runtime() -> WorkspaceRuntime {
        WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: supportURL,
            workspaceRegistryStorageURL: registryURL,
            assignments: []
        )))
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
