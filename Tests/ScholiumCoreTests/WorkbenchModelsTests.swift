import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Workbench completion models")
struct WorkbenchModelsTests {
    @Test("Saved Search persists only its current Search definition")
    func stateRoundTrip() throws {
        let saved = SavedSearch(
            name: "Open objections",
            definition: SearchDefinition(
                query: #"callout:state -has:broken-link"#,
                presentationScope: .triptych
            )
        )
        let encoded = try JSONEncoder().encode(saved)
        let decoded = try JSONDecoder().decode(SavedSearch.self, from: encoded)

        #expect(decoded == saved)
        #expect(decoded.definition.contractVersion == SearchContract.currentVersion)
    }

    @Test("Saved searches persist in workspace storage")
    func savedSearchPersistence() async throws {
        let base = testDirectory("saved-search-persistence")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = SavedSearchStore(workspaceStorageURL: base)
        let expected = SavedSearch(
            name: "Unsettled control records",
            definition: SearchDefinition(query: "has:broken-link", presentationScope: .triptych),
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let olderButFirst = SavedSearch(
            name: "Researcher-ordered first",
            definition: SearchDefinition(query: "callout:state", presentationScope: .currentVault),
            createdAt: Date(timeIntervalSince1970: 1)
        )

        try await store.save([olderButFirst, expected])
        let loaded = try await store.load()

        #expect(loaded.map(\.id) == [olderButFirst.id, expected.id])
        #expect(loaded[1].name == expected.name)
        #expect(loaded[1].definition == expected.definition)
    }

    @Test("A corrupt Saved Searches file remains untouched and blocks replacement")
    func corruptSavedSearchesFailClosed() async throws {
        let base = testDirectory("saved-search-corruption")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let file = base.appendingPathComponent("saved-searches.json")
        let corrupt = Data("{broken saved searches".utf8)
        try corrupt.write(to: file)
        let store = SavedSearchStore(workspaceStorageURL: base)

        await #expect(throws: SavedSearchStoreError.self) {
            _ = try await store.load()
        }
        await #expect(throws: SavedSearchStoreError.self) {
            try await store.save([
                SavedSearch(
                    name: "Must not replace",
                    definition: SearchDefinition(query: "test", presentationScope: .triptych)
                ),
            ])
        }
        #expect(try Data(contentsOf: file) == corrupt)
    }

    @Test("Unreadable Saved Searches are archived exactly before reset")
    func corruptSavedSearchesCanBePreserved() async throws {
        let base = testDirectory("saved-search-recovery")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let file = base.appendingPathComponent("saved-searches.json")
        let corrupt = Data([0x00, 0xff, 0x7b, 0x0a])
        try corrupt.write(to: file)
        let store = SavedSearchStore(workspaceStorageURL: base)
        await #expect(throws: SavedSearchStoreError.self) { _ = try await store.load() }

        let preserved = try #require(try await store.preserveUnreadableAndReset())

        #expect(try Data(contentsOf: preserved) == corrupt)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try await store.load().isEmpty)
        let replacement = SavedSearch(
            name: "Current",
            definition: SearchDefinition(query: "current", presentationScope: .triptych)
        )
        try await store.save([replacement])
        let reloaded = try await store.load()
        #expect(reloaded.map(\.id) == [replacement.id])
        #expect(reloaded.map(\.name) == [replacement.name])
        #expect(reloaded.map(\.definition) == [replacement.definition])
        #expect(try await store.preserveUnreadableAndReset() == nil)
    }

    private func testDirectory(_ name: String) -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }
}
