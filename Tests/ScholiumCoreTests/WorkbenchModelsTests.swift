import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Workbench completion models")
struct WorkbenchModelsTests {
    @Test("Saved Search persists only its v4 definition")
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
    }

    @Test("Saved searches persist in workspace storage")
    func savedSearchPersistence() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
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
                    definition: SearchDefinition(query: "test", presentationScope: .triptych)
                ),
            ])
        }
        #expect(try Data(contentsOf: file) == corrupt)
    }

    @Test("Legacy Saved Search drops transient state and preserves removed fields for editing")
    func legacySavedSearchMigration() throws {
        let id = UUID()
        let legacy = """
        {
          "id": "\(id.uuidString)",
          "name": "Legacy role query",
          "createdAt": 0,
          "state": {
            "query": "role:analyses autonomy",
            "scope": "triptych",
            "selectedRoles": ["source_corpus"],
            "selectedResultID": "transient-result"
          }
        }
        """
        let decoded = try JSONDecoder().decode(SavedSearch.self, from: Data(legacy.utf8))
        #expect(decoded.definition.query == "role:analyses autonomy")
        #expect(decoded.definition.presentationScope == .triptych)
        #expect(decoded.needsEditingDiagnostic?.code == .removedField)

        let encoded = try JSONEncoder().encode(decoded)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["definition"] != nil)
        #expect(object["state"] == nil)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("transient-result"))
    }
}
