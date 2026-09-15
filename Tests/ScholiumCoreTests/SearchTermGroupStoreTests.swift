import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Term group persistence")
struct SearchTermGroupStoreTests {
    @Test("Edits compare their original group, preserve other groups and refuse unreadable data")
    func persistenceAndConflicts() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(
            ".build/term-groups-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SearchTermGroupStore(workspaceStorageURL: root)
        #expect(try await store.load().isEmpty)
        let first = SearchTermGroup(name: "Reasons", terms: ["理由", "reason"])
        let second = SearchTermGroup(name: "Emotion", terms: ["情绪", "emotion"])
        _ = try await store.save(first, replacing: nil)
        _ = try await store.save(second, replacing: nil)
        let revised = SearchTermGroup(id: first.id, name: first.name, terms: ["实践理由", "practical reason"])
        #expect(try await store.save(revised, replacing: first) == [revised, second])
        await #expect(throws: SearchTermGroupError.changed) { try await store.save(first, replacing: first) }
        #expect(try await SearchTermGroupStore(workspaceStorageURL: root).load() == [revised, second])
        #expect(try await store.delete(second) == [revised])
        let path = root.appendingPathComponent("search-term-groups.json")
        let corrupt = Data("{unknown version and unfinished data".utf8)
        try corrupt.write(to: path)
        await #expect(throws: SearchTermGroupError.unreadable) { try await store.save(first, replacing: nil) }
        #expect(try Data(contentsOf: path) == corrupt)
    }
}
