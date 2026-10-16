import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Chat fixture preference isolation", .serialized)
@MainActor
struct AgentChatFixturePreferenceTests {
    @Test("Omitted owners are fresh for each fixture and caller-provided owners retain identity")
    func defaultsAndExplicitOwners() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/preference-isolation-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = fixtureChatController(triptychID: UUID(), root: root, toolHandler: response)
        let second = fixtureChatController(triptychID: UUID(), root: root, toolHandler: response)
        try #require(await first.waitUntilLoaded())
        try #require(await second.waitUntilLoaded())
        #expect(first.connectionDefaults !== second.connectionDefaults)
        #expect(first.contextAccessPreferences !== second.contextAccessPreferences)
        first.connectionDefaults.set("first", forKey: "fixture.canary")
        first.contextAccessPreferences.chatStateAccess = false
        #expect(second.connectionDefaults.object(forKey: "fixture.canary") == nil)
        #expect(second.contextAccessPreferences.chatStateAccess)

        let supplied = AgentChatFixturePreferenceStore()
        let context = AgentContextAccessPreferences(defaults: supplied.defaults)
        let explicit = fixtureChatController(
            triptychID: UUID(), root: root, methodDefaults: supplied.defaults,
            contextAccessPreferences: context, toolHandler: response)
        try #require(await explicit.waitUntilLoaded())
        #expect(explicit.connectionDefaults === supplied.defaults)
        #expect(explicit.contextAccessPreferences === context)
        await first.disconnect()
        await second.disconnect()
        await explicit.disconnect()
    }

    @Test("A partially supplied fixture never borrows the caller store for its missing owner")
    func partialOwnerInjection() async throws {
        let root = repository.appendingPathComponent(".build/agent-chat-tests/partial-preferences-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let supplied = AgentChatFixturePreferenceStore()
        let onlyDefaults = fixtureChatController(
            triptychID: UUID(), root: root, methodDefaults: supplied.defaults,
            toolHandler: response)
        let context = AgentContextAccessPreferences(defaults: supplied.defaults)
        let onlyContext = fixtureChatController(
            triptychID: UUID(), root: root, contextAccessPreferences: context,
            toolHandler: response)
        try #require(await onlyDefaults.waitUntilLoaded())
        try #require(await onlyContext.waitUntilLoaded())
        #expect(onlyDefaults.connectionDefaults === supplied.defaults)
        #expect(onlyContext.contextAccessPreferences === context)
        #expect(onlyContext.connectionDefaults !== supplied.defaults)
        onlyDefaults.contextAccessPreferences.chatWorkingTextAccess = true
        #expect(supplied.defaults.object(forKey: AgentContextAccessPreferences.chatWorkingTextKey) == nil)
        #expect(!context.chatWorkingTextAccess)
        await onlyDefaults.disconnect()
        await onlyContext.disconnect()
    }

    @Test("Generated suite cleanup removes only its own persistent domain")
    func generatedSuiteCleanup() {
        let survivor = AgentChatFixturePreferenceStore()
        survivor.defaults.set("preserved", forKey: "fixture.canary")
        var retired: AgentChatFixturePreferenceStore? = AgentChatFixturePreferenceStore()
        let suiteName = retired!.suiteName
        let defaults = retired!.defaults
        weak var weakRetired = retired
        defaults.set("retired", forKey: "fixture.canary")
        #expect(defaults.persistentDomain(forName: suiteName)?["fixture.canary"] as? String == "retired")
        retired = nil
        #expect(weakRetired == nil)
        #expect(defaults.persistentDomain(forName: suiteName)?.isEmpty != false)
        #expect(survivor.defaults.string(forKey: "fixture.canary") == "preserved")
    }

    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func response(_ request: ScholiumMCPBridgeRequest) -> ScholiumMCPBridgeResponse {
        try! .init(requestID: request.requestID, result: .object([:]))
    }
}
