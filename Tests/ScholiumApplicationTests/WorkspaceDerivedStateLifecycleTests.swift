import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Runtime derived-state retention")
struct WorkspaceDerivedStateLifecycleTests {
    @Test("Startup retires old indexes; unregistering reclaims only the inactive owner's derived records")
    func registeredLifecycle() async throws {
        let root = Self.fixtureRoot()
        let fixture = try await ApplicationFixture.make(rootURL: root)
        defer { fixture.remove() }
        let indexDirectory = fixture.applicationSupportURL.appendingPathComponent(
            "Triptychs/\(fixture.assignment.id.uuidString.lowercased())/indexes")
        let database = indexDirectory.appendingPathComponent("search-v10.sqlite")
        let originalDatabase = try Data(contentsOf: database)
        let retired = indexDirectory.appendingPathComponent("search-v9.sqlite")
        let future = indexDirectory.appendingPathComponent("search-v11.sqlite")
        let unrelated = indexDirectory.appendingPathComponent("Research.txt")
        let sentinel = Data("unknown owner bytes".utf8)
        try Data("known retired generated index".utf8).write(to: retired)
        try sentinel.write(to: future)
        try sentinel.write(to: unrelated)
        let sourceURL = fixture.analysesURL.appendingPathComponent("Agency.md")
        let source = try Data(contentsOf: sourceURL)
        let manifestURL = root.appendingPathComponent(".scholium/manifest.json")
        let manifest = try Data(contentsOf: manifestURL)
        let runtime = Self.runtime(fixture)
        do {
            #expect(try await runtime.availableWorkspaces().map(\.id) == [fixture.assignment.id])
            #expect(!FileManager.default.fileExists(atPath: retired.path))
            #expect(try Data(contentsOf: database) == originalDatabase)
            let maintenance = try #require(await runtime.latestDerivedStateMaintenanceSummary)
            #expect(maintenance.removedFiles == 1)
            let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
            _ = try await handle.refresh()
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
        #expect(FileManager.default.fileExists(atPath: database.path))
        let cacheDirectories = fixture.assignment.vaults.values.map { vault in
            fixture.applicationSupportURL.appendingPathComponent("Vaults/\(vault.id.uuidString)/source-projections-v1")
        }
        #expect(
            try cacheDirectories.allSatisfy { directory in
                try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasSuffix(".catalog.plist") }
            })
        let removal = Self.runtime(fixture)
        do {
            try await removal.removeLocalTriptychRegistration(id: fixture.assignment.id)
            #expect(try await removal.availableWorkspaces().isEmpty)
            #expect(!FileManager.default.fileExists(atPath: database.path))
            for directory in cacheDirectories {
                let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                #expect(names.allSatisfy { !$0.hasSuffix(".plist") && !$0.hasSuffix(".json") })
                #expect(names.contains(".derived-state.lock"))
            }
            await removal.shutdown()
        } catch {
            await removal.shutdown()
            throw error
        }
        #expect(try Data(contentsOf: future) == sentinel)
        #expect(try Data(contentsOf: unrelated) == sentinel)
        #expect(try Data(contentsOf: sourceURL) == source)
        #expect(try Data(contentsOf: manifestURL) == manifest)
    }

    @Test("An unreadable registration is never interpreted as an empty retention set")
    func invalidRegistryPreservesDerivedState() async throws {
        let fixture = try await ApplicationFixture.make(rootURL: Self.fixtureRoot())
        defer { fixture.remove() }
        let database = fixture.applicationSupportURL.appendingPathComponent(
            "Triptychs/\(fixture.assignment.id.uuidString.lowercased())/indexes/search-v10.sqlite")
        let bytes = try Data(contentsOf: database)
        try Data("invalid registration bytes".utf8).write(
            to: fixture.registryStorageURL.appendingPathComponent("workspace-registration-v3.json"))
        let runtime = Self.runtime(fixture)
        await #expect(throws: (any Error).self) { try await runtime.availableWorkspaces() }
        #expect(try Data(contentsOf: database) == bytes)
        let summary = try #require(await runtime.latestDerivedStateMaintenanceSummary)
        #expect(summary.failedDirectories == 1)
        #expect(summary.removedFiles == 0)
        await runtime.shutdown()
        #expect(try Data(contentsOf: database) == bytes)
    }

    @Test("An unavailable projection-cache directory does not block fresh source browsing")
    func unavailableCacheKeepsSourceAvailable() async throws {
        let fixture = try await ApplicationFixture.make(rootURL: Self.fixtureRoot())
        defer { fixture.remove() }
        let cache = fixture.applicationSupportURL.appendingPathComponent(
            "Vaults/\(fixture.analysisNoteID.vaultID.uuidString)/source-projections-v1")
        let outside = fixture.rootURL.appendingPathComponent("Unrelated directory")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let sentinelURL = outside.appendingPathComponent("sentinel.txt")
        let sentinel = Data("must not enter or mutate this directory".utf8)
        try sentinel.write(to: sentinelURL)
        try FileManager.default.removeItem(at: cache)
        try FileManager.default.createSymbolicLink(at: cache, withDestinationURL: outside)
        let sourceURL = fixture.analysesURL.appendingPathComponent("Agency.md")
        let original = try Data(contentsOf: sourceURL)
        let runtime = WorkspaceRuntime(
            configuration: .snapshot(
                .init(
                    applicationSupportURL: fixture.applicationSupportURL,
                    assignments: [fixture.assignment])))
        do {
            let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
            let snapshot = try await handle.snapshot()
            let summary = try #require(snapshot.document(id: fixture.analysisNoteID))
            #expect(summary.fingerprint == NoteDocument(relativePath: "Agency.md", rawContent: String(decoding: original, as: UTF8.self)).fingerprint)
            #expect(await handle.latestRefreshMeasurement.parsedDocuments >= 1)
            #expect(try Data(contentsOf: sourceURL) == original)
            #expect(try Data(contentsOf: sentinelURL) == sentinel)
            #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path) == ["sentinel.txt"])
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
    }

    private static func runtime(_ fixture: ApplicationFixture) -> WorkspaceRuntime {
        WorkspaceRuntime(
            configuration: .live(
                .init(
                    applicationSupportURL: fixture.applicationSupportURL,
                    workspaceRegistryStorageURL: fixture.registryStorageURL)))
    }

    private static func fixtureRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/runtime-derived-state/\(UUID().uuidString)", isDirectory: true)
    }
}
