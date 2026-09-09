import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApplication
@testable import ScholiumApp

@Suite("Zotero Chat configuration", .serialized) @MainActor
struct AgentChatZoteroConfigurationTests {
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Zotero configuration fixture did not reach its expected state")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("The read-only preset persists in runtime configuration and keeps local API status separate")
    func persistentReadPreset() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-chat-tests/zotero-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let calls = ZoteroStatusFixture()
        let operations = ZoteroOperations(requestLoader: { request in await calls.load(request) })
        let executable = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        let triptych = UUID()
        func make() async throws -> AgentChatController {
            let controller = AgentChatController(triptychID: triptych, root: root, zotero: operations) { request in
                try! .init(requestID: request.requestID, result: .object([:]))
            }
            try await wait { controller.isLoaded }
            controller.connect(executable: executable, home: controller.runtimeHome, cli: executable)
            try await wait { controller.capabilities.canConfigureTools }
            return controller
        }
        let first = try await make()
        let caps = first.capabilities
        let preset = try #require(caps.zoteroToolEdit(executable: first.zoteroToolExecutable))
        #expect(preset.connection.name == "scholium-zotero" && preset.connection.kind == .local)
        #expect(preset.connection.arguments == ["zotero", "mcp", "serve", "--read-only"])
        #expect(caps.zoteroLibraryInfo == nil)
        #expect(await calls.count == 0)
        #expect(await caps.saveTool(preset))
        try await wait { caps.canConfigureTools }
        #expect(caps.zoteroConnection?.enabled == true)
        #expect(caps.tools.first { $0.name == "scholium-zotero" }?.connectionStatus == "notStarted")
        caps.checkZotero(); try await wait { !caps.isCheckingZotero }
        #expect(caps.zoteroLibraryInfo?.status == .apiDisabled && caps.zoteroConnection?.enabled == true)
        await calls.setStatus(200)
        caps.checkZotero(); try await wait { !caps.isCheckingZotero }
        #expect(caps.zoteroLibraryInfo?.status == .available)
        #expect(await calls.count == 2)
        var disabled = try #require(caps.zoteroToolEdit(executable: first.zoteroToolExecutable))
        disabled.connection.enabled = false
        #expect(await caps.saveTool(disabled)); try await wait { caps.canConfigureTools }
        await first.disconnect()
        let second = try await make()
        #expect(second.capabilities.zoteroConnection?.enabled == false)
        #expect(second.capabilities.zoteroConnection?.arguments == preset.connection.arguments)
        #expect(second.capabilities.zoteroLibraryInfo == nil)
        let retained = try #require(second.capabilities.zoteroToolEdit(executable: second.zoteroToolExecutable))
        second.editDraft("hold"); second.send()
        try await wait { second.state == .working && second.selected?.pendingMessageID == nil }
        #expect(second.capabilities.zoteroToolEdit(executable: second.zoteroToolExecutable) == nil)
        #expect(!(await second.capabilities.saveTool(retained)))
        #expect(second.capabilities.zoteroConnection?.enabled == false)
        second.stop(); try await wait { second.state == .ready && !second.isBusy }
        #expect(await second.capabilities.saveTool(retained, removing: true))
        try await wait { second.capabilities.canConfigureTools }
        var custom = try #require(second.capabilities.editTool())
        custom.connection = .init(name: "scholium-zotero", address: "https://example.invalid/custom", enabled: false)
        #expect(await second.capabilities.saveTool(custom)); try await wait { second.capabilities.canConfigureTools }
        let existing = try #require(second.capabilities.zoteroToolEdit(executable: second.zoteroToolExecutable))
        #expect(existing.connection.address == custom.connection.address && existing.connection.kind == .remote)
        await second.disconnect()
    }
}

private actor ZoteroStatusFixture {
    private var status = 403
    private(set) var count = 0
    func setStatus(_ value: Int) { status = value }
    func load(_ request: URLRequest) -> (Data, URLResponse) {
        count += 1
        #expect(request.httpMethod == "GET" && request.url?.host == "127.0.0.1" && request.url?.path == "/api/users/0/items")
        return (Data("[]".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!)
    }
}
