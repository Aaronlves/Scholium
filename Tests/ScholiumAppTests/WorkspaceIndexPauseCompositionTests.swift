import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp
@testable import ScholiumApplication

@Suite("Paused index App composition", .serialized)
@MainActor
struct WorkspaceIndexPauseCompositionTests {
    @Test(
        "Settings, recovery, MCP and Chat borrow a paused index without activating a Library",
        .timeLimit(.minutes(2)), arguments: [false, true])
    func metadataPreservesIndexPause(reopenStore: Bool) async throws {
        let fixture = try await MCPAppBridgeRequestRouterTests.Fixture.make()
        await fixture.runtime.shutdown()
        let support = fixture.root.appendingPathComponent("ApplicationSupport", isDirectory: true)
        var currentStore: WorkspaceStore?
        do {
            let initial = try WorkspaceStore(applicationSupportURL: support)
            currentStore = initial
            let original = try await initial.applicationRuntime.workspace(id: fixture.assignment.id)
            #expect(try await original.snapshot().discovery.searchGeneration != nil)
            _ = try await initial.applicationRuntime.performStorageAction(.clearIndex, triptychID: fixture.assignment.id)
            #expect(try await original.snapshot().discovery.searchGeneration == nil)
            if reopenStore {
                await initial.shutdownApplicationRuntime()
                currentStore = try WorkspaceStore(applicationSupportURL: support)
            }
            let store = try #require(currentStore)
            var handle = try await store.applicationRuntime.workspace(id: fixture.assignment.id)
            #expect(try await handle.snapshot().discovery.searchGeneration == nil)
            let settings = try await store.settingsSnapshot(preferredTriptychID: fixture.assignment.id)
            #expect(settings.activeTriptychID == fixture.assignment.id)
            let capabilities = store.settingsCapabilities().workspace
            _ = try await capabilities.loadSettingsRecovery(fixture.assignment.id)
            let triptychRoot = fixture.topicsURL.deletingLastPathComponent()
            let configured = try await capabilities.configureWorkspace(
                triptychRoot.appendingPathComponent("Analyses"), fixture.topicsURL,
                triptychRoot.appendingPathComponent("Works"), triptychRoot,
                fixture.assignment.id, fixture.assignment.triptych.name)
            #expect(configured.activeTriptychID == fixture.assignment.id)
            handle = try await store.applicationRuntime.workspace(id: fixture.assignment.id)
            #expect(store.latestWorkspaceActivation == nil)
            #expect(store.workspaceSnapshots.isEmpty && store.workspaceEvents.isEmpty && store.workspaceActivations.isEmpty)
            #expect(try await handle.snapshot().discovery.searchGeneration == nil)
            let router = MCPAppBridgeRequestRouter(
                runtime: store.applicationRuntime, flushEditors: { _ in }, openTriptychs: { [fixture.assignment] })
            let response = await router.handle(
                .init(tool: .workspaceStatus, arguments: ["triptych_id": .string(fixture.assignment.id.uuidString)]))
            #expect(response.error?.code == .workspaceNotReady)
            #expect(response.error?.recovery.contains("Settings > Storage > Rebuild Index") == true)
            #expect(response.result == nil)
            let chat = store.chatRegistry.controller(for: fixture.assignment.id)
            let directory = try await chat.workspaceDirectory()
            #expect(directory.standardizedFileURL.path == triptychRoot.appendingPathComponent(".scholium", isDirectory: true).standardizedFileURL.path)
            #expect(chat.runtime == nil)
            #expect(try await handle.snapshot().discovery.searchGeneration == nil)
            #expect(try await handle.services.searchIndex.hasDeferredRebuild)
            #expect(store.latestWorkspaceActivation == nil && store.workspaceSnapshots.isEmpty)

            // Only this presentation entry explicitly enters a Library. Its
            // live source-ready return need not await the owned rebuild.
            let activated = try await store.workspaceCapabilities(id: fixture.assignment.id)
            #expect(activated.runtimeIdentity == handle.runtimeIdentity)
            #expect(store.latestWorkspaceActivation?.runtimeIdentity == handle.runtimeIdentity)
            try await waitUntil {
                try await handle.snapshot().discovery.searchGeneration != nil
            }
            #expect(!(try await handle.services.searchIndex.hasDeferredRebuild))
            let resumed = try await handle.snapshot()
            #expect(resumed.discovery.catalog.graph?.sourceManifestHash == resumed.discovery.searchGeneration?.sourceManifestHash)
            await store.shutdownApplicationRuntime()
            currentStore = nil
            await fixture.dispose()
        } catch {
            if let currentStore { await currentStore.shutdownApplicationRuntime() }
            await fixture.dispose()
            throw error
        }
    }

    private func waitUntil(_ predicate: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if try await predicate() { return }
            await Task.yield()
        }
        throw IndexPauseCompositionTestError.readinessTimeout
    }
}

private enum IndexPauseCompositionTestError: Error { case readinessTimeout }
