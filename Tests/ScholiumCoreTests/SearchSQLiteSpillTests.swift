import Foundation
import Testing

@testable import ScholiumCore

@Suite("Search SQLite dirty-page spill")
struct SearchSQLiteSpillTests {
    @Test("Large WAL writes respect the cache budget without publishing partial or rolled-back bytes", .timeLimit(.minutes(1)))
    func boundedCachePreservesPublication() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/search-sqlite-spill-tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("index.sqlite").path
        let writer = try SearchSQLiteDatabase(path: path)
        defer { writer.close() }
        try writer.execute("PRAGMA journal_mode=WAL;")
        #expect(try writer.scalarText("PRAGMA journal_mode;") == "wal")
        // Only this fixture shrinks the budget; production keeps SQLite's cache size.
        try writer.execute("PRAGMA cache_size=-1024;")
        try writer.execute("CREATE TABLE snapshots(id INTEGER PRIMARY KEY, content BLOB NOT NULL);")
        let previous = Data("previous complete snapshot\0\u{FEFF}自由\r\n".utf8)
        try writer.transaction {
            try writer.execute("INSERT INTO snapshots(id, content) VALUES(1, ?);", bindings: [.blob(previous)])
        }
        let reader = try SearchSQLiteDatabase(path: path, readOnly: true)
        defer { reader.close() }
        let replacement = Data(repeating: 0xA5, count: 9 * 1_024 * 1_024)
        var maximumObservedCacheBytes = 0

        func replaceUncommitted() throws {
            try writer.execute("UPDATE snapshots SET content = ? WHERE id = 1;", bindings: [.blob(replacement)])
            let cacheBytes = writer.cacheUsedBytes
            #expect(cacheBytes > 0)
            maximumObservedCacheBytes = max(maximumObservedCacheBytes, cacheBytes)
            // Dirty pages may reach the WAL, but another connection still sees
            // only the last complete commit before this transaction ends.
            #expect(try content(in: reader) == previous)
        }

        #expect(throws: RollbackProbe.requested) {
            try writer.transaction {
                try replaceUncommitted()
                throw RollbackProbe.requested
            }
        }
        #expect(try content(in: writer) == previous)
        #expect(try content(in: reader) == previous)

        try writer.transaction { try replaceUncommitted() }
        #expect(maximumObservedCacheBytes <= 2 * 1_024 * 1_024)
        #expect(try content(in: reader) == replacement)
        writer.close()
        reader.close()

        let reopened = try SearchSQLiteDatabase(path: path, readOnly: true)
        defer { reopened.close() }
        #expect(try content(in: reopened) == replacement)
    }

    private func content(in database: SearchSQLiteDatabase) throws -> Data {
        var value: Data?
        try database.query("SELECT content FROM snapshots WHERE id = 1;") { value = $0.data(at: 0) }
        return try #require(value)
    }

    private enum RollbackProbe: Error, Equatable { case requested }
}
