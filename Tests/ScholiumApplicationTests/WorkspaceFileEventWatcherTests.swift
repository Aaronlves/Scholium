import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Workspace file-event watcher")
struct WorkspaceFileEventWatcherTests {
    @Test("Portable citation observation includes metadata without widening vault source observation")
    func citationControlScope() {
        #expect(WorkspaceFileEventScope.citationControl.includes("identities.json"))
        #expect(WorkspaceFileEventScope.citationControl.includes("citations/v1/note.json"))
        #expect(!WorkspaceFileEventScope.citationControl.includes("settings.json"))
        #expect(!WorkspaceFileEventScope.citationControl.includes("attachments/v2/item.json"))
        #expect(!WorkspaceFileEventScope.markdown.includes("citations/v1/note.json"))
        #expect(WorkspaceFileEventScope.markdown.includes("Note.md"))
    }

    @Test("A dropped raw callback becomes one complete reconciliation request")
    func rawCallbackDropRequiresReconciliation() async throws {
        let pair = WorkspaceWatchEventBuffer.makeStream()
        WorkspaceWatchEventBuffer.yield(
            VaultWatchEvent(
                added: [],
                modified: ["First.md"],
                deleted: [],
                sequence: 41,
                requiresFullRescan: false,
                rootChanged: true
            ), to: pair.continuation)
        WorkspaceWatchEventBuffer.yield(
            VaultWatchEvent(
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

    @Test("Repeated subscriber overflow preserves an earlier root discontinuity")
    func repeatedOverflowPreservesRootChange() async throws {
        let pair = WorkspaceWatchEventBuffer.makeStream()
        WorkspaceWatchEventBuffer.yield(
            VaultWatchEvent(
                added: [],
                modified: [],
                deleted: [],
                sequence: 10,
                requiresFullRescan: true,
                rootChanged: true
            ), to: pair.continuation)

        for sequence in 11...150 {
            WorkspaceWatchEventBuffer.yield(
                VaultWatchEvent(
                    added: ["Note-\(sequence).md"],
                    modified: [],
                    deleted: [],
                    sequence: UInt64(sequence),
                    requiresFullRescan: false,
                    rootChanged: false
                ), to: pair.continuation)
        }

        var iterator = pair.stream.makeAsyncIterator()
        let event = try #require(await iterator.next())
        #expect(event.requiresFullRescan)
        #expect(event.rootChanged)
        #expect(event.sequence == 150)
        #expect(event.added.isEmpty)
        #expect(event.modified.isEmpty)
        #expect(event.deleted.isEmpty)
    }
}
