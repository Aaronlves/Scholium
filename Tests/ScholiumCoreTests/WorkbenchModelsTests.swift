import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Workbench completion models")
struct WorkbenchModelsTests {
    @Test("Search workspace state round trips")
    func stateRoundTrip() throws {
        let saved = SavedSearch(
            name: "Open objections",
            state: SearchWorkspaceState(
                query: #"status:open callout:objection"#,
                scope: .triptych,
                selectedRoles: [.topicKnowledge, .draftProject]
            )
        )
        let encoded = try JSONEncoder().encode(saved)
        let decoded = try JSONDecoder().decode(SavedSearch.self, from: encoded)

        #expect(decoded == saved)
    }

    @Test("Saved searches persist in workspace storage")
    func savedSearchPersistence() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = SavedSearchStore(workspaceStorageURL: base)
        let expected = SavedSearch(
            name: "Unsettled control records",
            state: SearchWorkspaceState(query: "status:unsettled", scope: .triptych),
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let olderButFirst = SavedSearch(
            name: "Researcher-ordered first",
            state: SearchWorkspaceState(query: "callout:objection", scope: .currentVault),
            createdAt: Date(timeIntervalSince1970: 1)
        )

        try await store.save([olderButFirst, expected])
        let loaded = try await store.load()

        #expect(loaded.map(\.id) == [olderButFirst.id, expected.id])
        #expect(loaded[1].name == expected.name)
        #expect(loaded[1].state == expected.state)
    }

    @Test("A corrupt Saved Searches file remains untouched and blocks replacement")
    func corruptSavedSearchesFailClosed() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
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
                    state: SearchWorkspaceState(query: "test", scope: .triptych)
                ),
            ])
        }
        #expect(try Data(contentsOf: file) == corrupt)
    }
}
