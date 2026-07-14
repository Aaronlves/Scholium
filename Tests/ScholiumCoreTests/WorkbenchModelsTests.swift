import Foundation
import Testing
@testable import ScholiumCore

@Suite("Workbench completion models")
struct WorkbenchModelsTests {
    @Test("Legacy named Canvas state remains readable for path migration only")
    func legacyNamedCanvasPathMigration() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let first = CanvasNode(relativePath: "Claims/A.md", position: .init(x: 10, y: 20))
        let second = CanvasNode(relativePath: "Claims/B.md", position: .init(x: 30, y: 40))
        let edge = CanvasEdge(
            subjectNodeID: first.id,
            objectNodeID: second.id,
            predicate: "pressures"
        )
        let canvas = NamedCanvas(name: "Argument Map", nodes: [first, second], edges: [edge])
        let store = NamedCanvasStore(vaultStorageURL: base)
        let directory = base.appendingPathComponent("canvases", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(canvas).write(
            to: directory.appendingPathComponent(canvas.id.uuidString.lowercased() + ".json"),
            options: .atomic
        )

        let loaded = try await store.list()

        #expect(loaded.count == 1)
        #expect(loaded[0].name == "Argument Map")
        #expect(loaded[0].edges[0].origin == .canvasAnnotation)
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("\(canvas.id.uuidString.lowercased()).json").path
        ))

        let migrated = try await store.moveNotePath(from: "Claims/A.md", to: "Claims/Renamed A.md")
        #expect(migrated.count == 1)
        let reopened = try await store.list()[0]
        #expect(reopened.nodes.contains { $0.id == first.id && $0.relativePath == "Claims/Renamed A.md" })
        #expect(reopened.edges[0].subjectNodeID == first.id)
    }

    @Test("Search workspace state round trips")
    func stateRoundTrip() throws {
        let saved = SavedSearch(
            name: "Open objections",
            state: SearchWorkspaceState(
                query: #"status:open callout:objection"#,
                scope: .selectedRoles,
                selectedRoles: [.topicKnowledge, .dissertationControl]
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
            state: SearchWorkspaceState(query: "status:unsettled", scope: .allWorkspace),
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
                    state: SearchWorkspaceState(query: "test", scope: .allWorkspace)
                ),
            ])
        }
        #expect(try Data(contentsOf: file) == corrupt)
    }
}
