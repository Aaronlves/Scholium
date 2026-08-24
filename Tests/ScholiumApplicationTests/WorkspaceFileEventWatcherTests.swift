import ScholiumContracts
import Testing
@testable import ScholiumApplication

@Suite("Workspace file-event watcher")
struct WorkspaceFileEventWatcherTests {
    @Test("A dropped raw callback becomes one complete reconciliation request")
    func rawCallbackDropRequiresReconciliation() async throws {
        let pair = WorkspaceWatchEventBuffer.makeStream()
        WorkspaceWatchEventBuffer.yield(VaultWatchEvent(
            added: [],
            modified: ["First.md"],
            deleted: [],
            sequence: 41,
            requiresFullRescan: false,
            rootChanged: true
        ), to: pair.continuation)
        WorkspaceWatchEventBuffer.yield(VaultWatchEvent(
            added: ["Second.md"],
            modified: [],
            deleted: [],
            sequence: 42,
            requiresFullRescan: false,
            rootChanged: false
        ), to: pair.continuation)

        var iterator = pair.stream.makeAsyncIterator()
        let event = try #require(await iterator.next())
        #expect(event.requiresFullRescan)
        #expect(event.rootChanged)
        #expect(event.sequence == 42)
        #expect(event.added.isEmpty)
        #expect(event.modified.isEmpty)
        #expect(event.deleted.isEmpty)
    }
}
