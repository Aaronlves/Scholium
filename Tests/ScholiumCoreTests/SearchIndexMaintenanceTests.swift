import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Explicit Search index maintenance")
struct SearchIndexMaintenanceTests {
    enum PendingPublication: CaseIterable, Sendable, Equatable { case unchanged, changed, rebuild }
    @Test("Explicit rebuild hydrates every unchanged source and bypasses stored projections")
    func rebuildDerivesEverySource() async throws {
        let fixture = try MaintenanceFixture()
        defer { fixture.remove() }
        try await fixture.withIndex { index in
            let cache = SourceProjectionCache(applicationSupportURL: fixture.support, vaultID: fixture.vault.id, role: fixture.vault.role)
            let first = try await fixture.publish(index, generation: 1, caches: [fixture.vault.id: cache])
            let expectedHits = try await fixture.hits(index)
            #expect(expectedHits.sorted() == ["A.md", "B.md"])
            let loads = MaintenanceLoads(fixture.documents)
            let rebuilt = try await index.synchronizeManifest(
                fixture.manifest, sourceProjectionCaches: [fixture.vault.id: cache], workspaceGeneration: 2, mode: .rebuild,
                loadChanged: { try await loads.load($0) }, validateManifest: {})
            #expect(rebuilt.disposition == .rebuilt)
            #expect(rebuilt.generation.sequence > first.generation.sequence)
            #expect(rebuilt.generation.sourceManifestHash == first.generation.sourceManifestHash)
            #expect(Set(await loads.paths) == Set(fixture.documents.map(\.relativePath)))
            #expect(await index.lastSynchronizationTimings?.projectedDocuments == fixture.documents.count)
            #expect(await index.lastSynchronizationTimings?.restoredSearchProjections == 0)
            let rebuiltHits = try await fixture.hits(index)
            #expect(rebuiltHits == expectedHits)
        }
        try fixture.expectSourcesUnchanged()
    }

    @Test("Clear reclaims owned rows, pauses refresh and preserves monotonic freshness across rebuild and reopen")
    func clearDefersRebuild() async throws {
        let fixture = try MaintenanceFixture(large: true)
        defer { fixture.remove() }
        let expectedHits = try await fixture.withIndex { index in
            let first = try await fixture.publish(index, generation: 1)
            let initialHits = try await fixture.hits(index)
            #expect(initialHits.sorted() == ["A.md", "B.md"])
            let beforeBytes = fixture.indexByteCount()
            let cleared = try await index.clear()
            #expect(cleared.removedDocuments == fixture.documents.count)
            #expect(cleared.reclamation == .completed)
            #expect(fixture.indexByteCount() < beforeBytes)
            #expect(try await index.generation() == nil)
            #expect(try await index.hasDeferredRebuild)
            #expect(await index.availability() == .unavailable)
            #expect(try await fixture.hits(index).isEmpty)
            try fixture.expectEmptyOwnedTables()
            try await fixture.withIndex { peer in
                #expect(try await peer.hasDeferredRebuild)
                #expect(try await peer.generation() == nil)
                await #expect {
                    try await fixture.publish(peer, generation: 2)
                } throws: { error in
                    guard case SearchIndexError.awaitingRebuild = error else { return false }
                    return true
                }
                #expect(try await index.hasDeferredRebuild)
                try fixture.expectEmptyOwnedTables()
            }
            await #expect {
                try await fixture.publish(index, generation: 2)
            } throws: { error in
                guard case SearchIndexError.awaitingRebuild = error else { return false }
                return true
            }
            let rebuilt = try await fixture.publish(index, generation: 2, mode: .rebuild)
            #expect(rebuilt.disposition == .rebuilt)
            #expect(rebuilt.generation.sequence > first.generation.sequence)
            #expect(rebuilt.generation != first.generation)
            #expect(try await !index.hasDeferredRebuild)
            let rebuiltHits = try await fixture.hits(index)
            #expect(rebuiltHits == initialHits)
            _ = try await index.clear()
            return initialHits
        }
        // Reconstructing an owner is neutral. Only explicit rebuilding may
        // replace the persisted clear marker, including after every peer exits.
        try await fixture.withIndex { reopened in
            #expect(try await reopened.hasDeferredRebuild)
            await #expect {
                try await fixture.publish(reopened, generation: 3)
            } throws: { error in
                guard case SearchIndexError.awaitingRebuild = error else { return false }
                return true
            }
            try fixture.expectEmptyOwnedTables()
            let built = try await fixture.publish(reopened, generation: 3, mode: .rebuild)
            #expect(built.disposition == .rebuilt)
            let reopenedHits = try await fixture.hits(reopened)
            #expect(reopenedHits == expectedHits)
        }
        try fixture.expectSourcesUnchanged()
    }

    #if DEBUG
        @Test("Cancelled rebuild retains the prior complete or explicitly cleared state", arguments: [false, true])
        func cancelledRebuildPreservesPriorState(cleared: Bool) async throws {
            let fixture = try MaintenanceFixture()
            defer { fixture.remove() }
            try await fixture.withIndex { index in
                let first = try await fixture.publish(index, generation: 1)
                let expectedHits = try await fixture.hits(index)
                #expect(expectedHits.sorted() == ["A.md", "B.md"])
                if cleared { _ = try await index.clear() }
                let gate = MaintenanceGate()
                let rebuilding = Task {
                    try await index.synchronizeManifest(
                        fixture.manifest, workspaceGeneration: 2, mode: .rebuild,
                        loadChanged: { try fixture.load($0) }, validateManifest: { await gate.hold() })
                }
                defer {
                    rebuilding.cancel()
                    Task { await gate.release() }
                }
                await gate.waitUntilEntered()
                #expect(try await index.generation() == (cleared ? nil : first.generation))
                rebuilding.cancel()
                await gate.release()
                await #expect(throws: CancellationError.self) { try await rebuilding.value }
                #expect(try await index.generation() == (cleared ? nil : first.generation))
                #expect(try await index.hasDeferredRebuild == cleared)
                if cleared {
                    try fixture.expectEmptyOwnedTables()
                } else {
                    let retainedHits = try await fixture.hits(index)
                    #expect(retainedHits == expectedHits)
                }
                let rebuilt = try await fixture.publish(index, generation: 3, mode: .rebuild)
                #expect(rebuilt.disposition == .rebuilt)
                #expect(try await !index.hasDeferredRebuild)
            }
        }

        @Test("Clear cancellation or rejection before commit rolls back the complete generation", arguments: [false, true])
        func clearBeforeCommitRollsBack(cancel: Bool) async throws {
            let fixture = try MaintenanceFixture()
            defer { fixture.remove() }
            try await fixture.withIndex { index in
                let first = try await fixture.publish(index, generation: 1)
                let expectedHits = try await fixture.hits(index)
                #expect(expectedHits.sorted() == ["A.md", "B.md"])
                let gate = MaintenanceGate()
                await index.setClearObserverForTesting { phase in
                    if case .beforeCommit = phase {
                        await gate.hold()
                        if !cancel { throw MaintenanceFailure.rejected }
                    }
                }
                let clearing = Task { try await index.clear() }
                defer {
                    clearing.cancel()
                    Task { await gate.release() }
                }
                await gate.waitUntilEntered()
                let reader = try SearchSQLiteDatabase(path: fixture.database.path, readOnly: true)
                defer { reader.close() }
                #expect(try reader.scalarText("SELECT count(*) FROM search_documents;") == "2")
                if cancel { clearing.cancel() }
                await gate.release()
                if cancel {
                    await #expect(throws: CancellationError.self) { try await clearing.value }
                } else {
                    await #expect(throws: MaintenanceFailure.self) { try await clearing.value }
                }
                #expect(try await index.generation() == first.generation)
                #expect(try await !index.hasDeferredRebuild)
                let retainedHits = try await fixture.hits(index)
                #expect(retainedHits == expectedHits)
            }
            try fixture.expectSourcesUnchanged()
        }

        @Test("Post-commit cancellation or compaction failure reports committed deletion truthfully", arguments: [false, true])
        func clearAfterCommitIsNotRollback(cancel: Bool) async throws {
            let fixture = try MaintenanceFixture()
            defer { fixture.remove() }
            try await fixture.withIndex { index in
                _ = try await fixture.publish(index, generation: 1)
                let gate = MaintenanceGate()
                await index.setClearObserverForTesting { phase in
                    if case .afterCommit = phase {
                        await gate.hold()
                        if !cancel { throw MaintenanceFailure.rejected }
                    }
                }
                let clearing = Task { try await index.clear() }
                defer {
                    clearing.cancel()
                    Task { await gate.release() }
                }
                await gate.waitUntilEntered()
                try fixture.expectEmptyOwnedTables()
                if cancel { clearing.cancel() }
                await gate.release()
                let result = try await clearing.value
                #expect(result.removedDocuments == 2)
                #expect(result.reclamation == (cancel ? .deferred : .failed))
                #expect(try await index.hasDeferredRebuild)
                #expect(try await index.generation() == nil)
            }
        }

        @Test(
            "An older peer queued before clear cannot refill either publication path or undo clear with an older rebuild",
            arguments: PendingPublication.allCases)
        func olderPeerCannotRefill(_ pending: PendingPublication) async throws {
            let fixture = try MaintenanceFixture()
            defer { fixture.remove() }
            try await fixture.withIndex { first in
                _ = try await fixture.publish(first, generation: 1)
                try await fixture.withIndex { peer in
                    let gate = MaintenanceGate()
                    await peer.setSynchronizationBeforeTransactionForTesting { await gate.hold() }
                    let documents = pending == .changed ? fixture.documents + [fixture.document(path: "C.md", text: "new needle")] : fixture.documents
                    let loads = MaintenanceLoads(documents)
                    let publication = Task {
                        try await peer.synchronizeManifest(
                            documents.map(SearchIndexManifestEntry.init(document:)), workspaceGeneration: 2,
                            mode: pending == .rebuild ? .rebuild : .incremental,
                            loadChanged: { try await loads.load($0) }, validateManifest: {})
                    }
                    defer {
                        publication.cancel()
                        Task { await gate.release() }
                    }
                    await gate.waitUntilEntered()
                    _ = try await first.clear()
                    #expect(try await peer.hasDeferredRebuild)
                    await gate.release()
                    await #expect {
                        try await publication.value
                    } throws: { error in
                        guard case SearchIndexError.awaitingRebuild = error else { return false }
                        return true
                    }
                    try fixture.expectEmptyOwnedTables()
                    #expect(try await peer.generation() == nil)
                    #expect(await loads.paths.isEmpty)
                }
            }
        }

        @Test("Clear drains the existing transaction before acquiring the sole writer")
        func clearDrainsSynchronization() async throws {
            let fixture = try MaintenanceFixture()
            defer { fixture.remove() }
            try await fixture.withIndex { index in
                _ = try await fixture.publish(index, generation: 1)
                let gate = MaintenanceGate()
                let rebuilding = Task {
                    try await index.synchronizeManifest(
                        fixture.manifest, workspaceGeneration: 2, mode: .rebuild,
                        loadChanged: { try fixture.load($0) }, validateManifest: { await gate.hold() })
                }
                defer {
                    rebuilding.cancel()
                    Task { await gate.release() }
                }
                await gate.waitUntilEntered()
                let clearing = Task { try await index.clear() }
                defer { clearing.cancel() }
                await gate.waitUntilCancelled()
                await gate.release()
                await #expect(throws: CancellationError.self) { try await rebuilding.value }
                #expect(try await clearing.value.removedDocuments == 2)
                #expect(try await index.hasDeferredRebuild)
                try fixture.expectEmptyOwnedTables()
            }
        }

        @Test("Shutdown retains its lifetime lease until the clear transaction has drained")
        func shutdownJoinsClear() async throws {
            let fixture = try MaintenanceFixture()
            defer { fixture.remove() }
            let index = try fixture.index()
            _ = try await fixture.publish(index, generation: 1)
            let gate = MaintenanceGate()
            await index.setClearObserverForTesting { phase in
                if case .beforeCommit = phase { await gate.hold() }
            }
            let clearing = Task { try await index.clear() }
            defer {
                clearing.cancel()
                Task {
                    await gate.release()
                    await index.shutdown()
                }
            }
            await gate.waitUntilEntered()
            let shutdown = Task { await index.shutdown() }
            await gate.waitUntilCancelled()
            #expect(throws: DerivedStateStorageError.inUse) {
                try DerivedStateStorage.searchMaintenanceLease(
                    storage: DerivedStateStorage.searchStorage(applicationSupportURL: fixture.support, triptychID: fixture.triptychID))
            }
            await gate.release()
            await shutdown.value
            await #expect(throws: CancellationError.self) { try await clearing.value }
            let maintenance = try DerivedStateStorage.searchMaintenanceLease(
                storage: DerivedStateStorage.searchStorage(applicationSupportURL: fixture.support, triptychID: fixture.triptychID))
            withExtendedLifetime(maintenance) {}
            await #expect(throws: SearchIndexError.self) { try await index.generation() }
        }
    #endif

    @Test("A live owner refuses explicit maintenance if policy becomes future or unrecognized", arguments: [false, true], [false, true])
    func maintenancePreservesUnsupportedPolicy(future: Bool, rebuild: Bool) async throws {
        let fixture = try MaintenanceFixture()
        defer { fixture.remove() }
        try await fixture.withIndex { index in
            _ = try await fixture.publish(index, generation: 1)
            let external = try SearchSQLiteDatabase(path: fixture.database.path)
            try external.execute(future ? "UPDATE search_index_state SET schema_version = schema_version + 1;" : "DROP TABLE search_index_state;")
            external.close()
            let before = try Data(contentsOf: fixture.database)
            let wal = URL(fileURLWithPath: fixture.database.path + "-wal")
            let beforeWAL = try Data(contentsOf: wal)
            await #expect(throws: future ? DerivedStateStorageError.futurePolicy : .unrecognizedPolicy) {
                if rebuild {
                    _ = try await fixture.publish(index, generation: 2, mode: .rebuild)
                } else {
                    _ = try await index.clear()
                }
            }
            #expect(try Data(contentsOf: fixture.database) == before)
            #expect(try Data(contentsOf: wal) == beforeWAL)
            let reader = try SearchSQLiteDatabase(path: fixture.database.path, readOnly: true)
            defer { reader.close() }
            #expect(try reader.scalarText("SELECT count(*) FROM search_documents;") == "2")
        }
        try fixture.expectSourcesUnchanged()
    }
}

private struct MaintenanceFixture: Sendable {
    let root: URL
    let support: URL
    let triptychID = UUID()
    let vault: RegisteredVault
    let documents: [SearchIndexDocument]
    let originalFiles: [URL: Data]
    var database: URL { TriptychSearchIndex.databaseURL(applicationSupportURL: support, triptychID: triptychID) }
    var manifest: [SearchIndexManifestEntry] { documents.map(SearchIndexManifestEntry.init(document:)) }

    init(large: Bool = false) throws {
        root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/search-maintenance-tests/\(UUID().uuidString)")
        support = root.appendingPathComponent("Support")
        let library = root.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library.appendingPathComponent(".scholium/recovery"), withIntermediateDirectories: true)
        let registeredVault = RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: library.path)
        vault = registeredVault
        let body = large ? String(repeating: "Exact needle source preserves café 中文.\n", count: 2_048) : "Exact needle source.\n"
        let sources = [
            "A.md": "---\naliases: [Alpha]\nstatus: draft\n---\n# Alpha\n\n" + body,
            "B.md": "# Beta\n\nAnother needle source.\n",
            ".scholium/recovery/preserved": "source recovery sentinel\r\n",
        ]
        originalFiles = Dictionary(uniqueKeysWithValues: sources.map { (library.appendingPathComponent($0.key), Data($0.value.utf8)) })
        for (url, bytes) in originalFiles { try bytes.write(to: url) }
        documents = sources.keys.sorted().filter { $0.hasSuffix(".md") }.map { path in
            SearchIndexDocument(
                vaultID: registeredVault.id, vaultName: registeredVault.name, vaultRole: registeredVault.role,
                document: .init(relativePath: path, rawContent: sources[path]!))
        }
    }

    func index() throws -> TriptychSearchIndex { try .init(applicationSupportURL: support, triptychID: triptychID, vaults: [vault]) }

    func withIndex<Value: Sendable>(_ operation: @Sendable (TriptychSearchIndex) async throws -> Value) async throws -> Value {
        let index = try index()
        do {
            let value = try await operation(index)
            await index.shutdown()
            return value
        } catch {
            await index.shutdown()
            throw error
        }
    }

    func document(path: String, text: String) -> SearchIndexDocument {
        .init(vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role, document: .init(relativePath: path, rawContent: text))
    }

    func load(_ entry: SearchIndexManifestEntry) throws -> SearchIndexDocument {
        guard let source = documents.first(where: { $0.relativePath == entry.relativePath }) else { throw MaintenanceFailure.rejected }
        return source
    }

    func publish(
        _ index: TriptychSearchIndex, generation: UInt64, mode: SearchIndexSynchronizationMode = .incremental,
        caches: [UUID: SourceProjectionCache] = [:]
    ) async throws -> TriptychSearchIndexSyncResult {
        try await index.synchronizeManifest(
            manifest, sourceProjectionCaches: caches, workspaceGeneration: generation, mode: mode,
            loadChanged: { try load($0) }, validateManifest: {})
    }

    func hits(_ index: TriptychSearchIndex) async throws -> [String] {
        try await index.testSearch(.init(query: "needle", presentationScope: .triptych, executionScope: .triptych, limit: 20)).noteResults.map(\.relativePath)
    }

    func expectSourcesUnchanged() throws {
        for (url, bytes) in originalFiles { #expect(try Data(contentsOf: url) == bytes) }
    }

    func expectEmptyOwnedTables() throws {
        let reader = try SearchSQLiteDatabase(path: database.path, readOnly: true)
        defer { reader.close() }
        for table in ["search_fts", "search_segments", "search_aliases", "search_properties", "search_documents", "search_vaults"] {
            #expect(try reader.scalarText("SELECT count(*) FROM \(table);") == "0")
        }
    }

    func indexByteCount() -> Int {
        ["", "-wal"].reduce(0) { total, suffix in
            total + ((try? URL(fileURLWithPath: database.path + suffix).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

private enum MaintenanceFailure: Error { case rejected }

private actor MaintenanceLoads {
    let documents: [SearchIndexDocument]
    private(set) var paths: [String] = []
    init(_ documents: [SearchIndexDocument]) { self.documents = documents }
    func load(_ entry: SearchIndexManifestEntry) throws -> SearchIndexDocument {
        guard let source = documents.first(where: { $0.relativePath == entry.relativePath }) else { throw MaintenanceFailure.rejected }
        paths.append(entry.relativePath)
        return source
    }
}

private actor MaintenanceGate {
    private var entered = false
    private var released = false
    private var cancelled = false
    private var entry: CheckedContinuation<Void, Never>?
    private var exit: CheckedContinuation<Void, Never>?
    private var cancellation: CheckedContinuation<Void, Never>?

    func hold() async {
        entered = true
        entry?.resume()
        entry = nil
        guard !released else { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { exit = $0 }
        } onCancel: {
            Task { await self.recordCancellation() }
        }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { entry = $0 }
    }

    func waitUntilCancelled() async {
        if cancelled { return }
        await withCheckedContinuation { cancellation = $0 }
    }

    private func recordCancellation() {
        cancelled = true
        cancellation?.resume()
        cancellation = nil
    }

    func release() {
        released = true
        exit?.resume()
        exit = nil
    }
}
