import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Workspace storage management", .serialized)
struct WorkspaceStorageManagementTests {
    @Test("Clear stays paused through refresh; cached reopening and explicit rebuild restore complete fresh generations")
    func clearAndRebuildLifecycle() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(
            configuration: .snapshot(
                .init(
                    applicationSupportURL: fixture.applicationSupportURL, assignments: [fixture.assignment])))
        do {
            let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
            let before = try await handle.snapshot()
            let source = fixture.analysesURL.appendingPathComponent("Agency.md")
            let original = try Data(contentsOf: source)
            let portable = fixture.rootURL.appendingPathComponent(".scholium/identities.json")
            let portableBytes = try Data(contentsOf: portable)
            let runtimeDirectory = fixture.applicationSupportURL.appendingPathComponent("Chat/Codex")
            try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
            let runtimeFile = runtimeDirectory.appendingPathComponent("runtime-owned.bin")
            let runtimeBytes = Data(repeating: 0x5A, count: 17_293)
            try runtimeBytes.write(to: runtimeFile)
            let initial = try await runtime.storageInventory()
            #expect(initial.usages.first { $0.category == .sourceProjectionCache }?.fileCount ?? 0 > 0)
            let cache = try await runtime.performStorageAction(.clearProjectionCache)
            #expect(cache.cleanup.removedFiles > 0)
            let afterCache = try await runtime.storageInventory()
            #expect(afterCache.usages.first { $0.category == .sourceProjectionCache }?.byteCount == 0)

            let cleared = try await runtime.performStorageAction(.clearIndex, triptychID: fixture.assignment.id)
            #expect(cleared.warnings.isEmpty)
            #expect(try await handle.snapshot().discovery.searchGeneration == nil)
            let refreshed = try await handle.refresh()
            #expect(refreshed.discovery.searchGeneration == nil)
            #expect(refreshed.discovery.catalog.graph?.generation != nil)
            let reopened = try await runtime.openWorkspace(id: fixture.assignment.id)
            #expect(reopened.runtimeIdentity == handle.runtimeIdentity)
            let resumed = try await reopened.snapshot()
            #expect(resumed.discovery.searchGeneration != nil)
            #expect(resumed.discovery.searchGeneration != before.discovery.searchGeneration)
            let count = resumed.vaults.reduce(0) { $0 + $1.documents.count }
            #expect(await handle.latestRefreshMeasurement.parsedDocuments == count)
            #expect(await handle.latestRefreshMeasurement.projectedDocuments == count)
            #expect(await handle.latestRefreshMeasurement.restoredCatalogProjections == 0)
            #expect(await handle.latestRefreshMeasurement.restoredSearchProjections == 0)
            _ = try await runtime.performStorageAction(.rebuildIndex, triptychID: fixture.assignment.id)
            #expect(await handle.latestRefreshMeasurement.parsedDocuments == count)
            #expect(try Data(contentsOf: source) == original)
            #expect(try Data(contentsOf: portable) == portableBytes)
            #expect(try Data(contentsOf: runtimeFile) == runtimeBytes)
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
    }

    @Test("Clearing an inactive index does not open or read unavailable source folders")
    func inactiveClearNeedsNoVaultAccess() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let moved = fixture.rootURL.appendingPathComponent("Analyses unavailable")
        try FileManager.default.moveItem(at: fixture.analysesURL, to: moved)
        let runtime = WorkspaceRuntime(
            configuration: .snapshot(
                .init(
                    applicationSupportURL: fixture.applicationSupportURL, assignments: [fixture.assignment])))
        do {
            let result = try await runtime.performStorageAction(.clearIndex, triptychID: fixture.assignment.id)
            #expect(result.action == .clearIndex)
            #expect(await runtime.openingFactoryCountForTesting == 0)
            #expect(FileManager.default.fileExists(atPath: moved.appendingPathComponent("Agency.md").path))
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
    }
}
