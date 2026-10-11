import Foundation
import ScholiumContracts
import Testing

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

        try await store.save([olderButFirst, expected], replacing: [])
        let loaded = try await store.load()

        #expect(loaded.map(\.id) == [olderButFirst.id, expected.id])
        #expect(loaded[1].name == expected.name)
        #expect(loaded[1].definition == expected.definition)
    }

    @Test("Changed Saved Search definitions and order reject stale replacement with current state")
    func savedSearchCollectionComparisonRejectsStaleState() async throws {
        let first = SavedSearch(
            name: "First", definition: .init(query: "first", presentationScope: .triptych),
            createdAt: Date(timeIntervalSince1970: 10))
        let second = SavedSearch(
            name: "Second", definition: .init(query: "second", presentationScope: .currentVault),
            createdAt: Date(timeIntervalSince1970: 20))
        var renamed = first
        renamed.name = "Renamed first"
        var revised = first
        revised.definition = .init(query: "title:revised", presentationScope: .currentVault)

        for current in [[renamed, second], [second, first], [revised, second]] {
            let base = testDirectory("saved-search-collection-comparison")
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: base) }
            let store = SavedSearchStore(workspaceStorageURL: base)
            try await store.save([first, second], replacing: [])
            let stale = try await store.load()
            try await store.save(current, replacing: stale)
            let file = base.appendingPathComponent("saved-searches.json")
            let committedBytes = try Data(contentsOf: file)

            do {
                try await store.save([second], replacing: stale)
                Issue.record("A stale collection replacement must be refused")
            } catch let error as SavedSearchStoreError {
                guard case .changed(let authoritative) = error else { throw error }
                #expect(authoritative == current)
            }
            #expect(try Data(contentsOf: file) == committedBytes)
            #expect(try await store.load() == current)
        }
    }

    @Test("Saved Search comparison uses ISO8601 persisted precision for subsequent edits")
    func savedSearchComparisonUsesPersistedDatePrecision() async throws {
        let base = testDirectory("saved-search-date-precision")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = SavedSearchStore(workspaceStorageURL: base)
        let saved = SavedSearch(
            name: "Fractional date", definition: .init(query: "first", presentationScope: .triptych),
            createdAt: Date(timeIntervalSince1970: 10.125))
        try await store.save([saved], replacing: [])
        #expect(try await store.load().first?.createdAt == Date(timeIntervalSince1970: 10))
        var renamed = saved
        renamed.name = "Renamed with original precision"
        try await store.save([renamed], replacing: [saved])
        let persisted = try await store.load()
        #expect(persisted.map(\.id) == [saved.id])
        #expect(persisted.first?.name == renamed.name)
        #expect(persisted.first?.definition == saved.definition)
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
            try await store.save(
                [
                    SavedSearch(
                        name: "Must not replace",
                        definition: SearchDefinition(query: "test", presentationScope: .triptych)
                    )
                ], replacing: [])
        }
        #expect(try Data(contentsOf: file) == corrupt)
    }

    @Test("Unsupported Saved Search formats remain untouched and block replacement")
    func unsupportedSavedSearchFormat() async throws {
        let base = testDirectory("saved-search-unsupported-format")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let file = base.appendingPathComponent("saved-searches.json")
        let saved = SavedSearch(
            name: "Unsupported format",
            definition: SearchDefinition(query: "emotion OR reason", presentationScope: .triptych)
        )
        var document = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode([saved])) as? [[String: Any]]
        )
        var definition = try #require(document[0]["definition"] as? [String: Any])
        definition["contractVersion"] = -1
        document[0]["definition"] = definition
        let bytes = try JSONSerialization.data(withJSONObject: document)
        try bytes.write(to: file)
        let store = SavedSearchStore(workspaceStorageURL: base)
        await #expect(throws: SavedSearchStoreError.self) { _ = try await store.load() }
        await #expect(throws: SavedSearchStoreError.self) { try await store.save([saved], replacing: []) }
        #expect(try Data(contentsOf: file) == bytes)
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
        try await store.save([replacement], replacing: [])
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
