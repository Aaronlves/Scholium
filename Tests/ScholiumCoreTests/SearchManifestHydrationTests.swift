import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Compact Search manifest publication")
struct SearchManifestHydrationTests {
    @Test(
        "Final publication admission leaves last-good queries reentrant and rolls back on rejection or cancellation",
        .timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func finalPublicationAdmissionOwnsCommit(changesSource: Bool, cancelsAdmission: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL, triptychID: fixture.triptychID, vaults: [fixture.vault])
        let source = FixtureSources(vault: fixture.vault, documents: ["A.md": "oldneedle"])
        let previous = try await index.synchronizeManifest(
            await source.manifest(), workspaceGeneration: 1,
            loadChanged: { try await source.load($0) }, validateManifest: {})
        if changesSource { await source.replace("A.md", with: "newneedle") }
        let manifest = await source.manifest()
        let gate = ManifestValidationGate()
        let publication = Task {
            try await index.synchronizeManifest(
                manifest, workspaceGeneration: 2,
                loadChanged: { try await source.load($0) },
                validateManifest: {
                    // Application acquires its final source-publication lease
                    // here. An older immutable preparation must remain private
                    // while that admission suspends or rejects its source epoch.
                    await gate.hold()
                    if !cancelsAdmission { throw ProbeValidationFailure.rejected }
                })
        }
        await gate.waitUntilEntered()
        defer {
            publication.cancel()
            Task { await gate.release() }
        }
        #expect(try await index.generation() == previous.generation)
        // These calls must complete while publication admission is suspended:
        // a source-operation holder can still query the last committed reader.
        #expect(
            try await index.testSearch(
                SearchRequest(query: "oldneedle", presentationScope: .triptych, executionScope: .triptych, limit: 20)
            ).noteResults.map(\.relativePath) == ["A.md"])
        #expect(
            try await index.testSearch(
                SearchRequest(query: "newneedle", presentationScope: .triptych, executionScope: .triptych, limit: 20)
            ).noteResults.isEmpty)
        let storage = try SearchSQLiteDatabase(path: fixture.databaseURL.path)
        #expect(try storage.scalarText("SELECT workspace_generation FROM search_index_state WHERE singleton = 1;") == "1")
        if cancelsAdmission { publication.cancel() }
        await gate.release()
        if cancelsAdmission {
            await #expect(throws: CancellationError.self) { try await publication.value }
        } else {
            await #expect(throws: ProbeValidationFailure.self) { try await publication.value }
        }
        #expect(try await index.generation() == previous.generation)
        #expect(try storage.scalarText("SELECT workspace_generation FROM search_index_state WHERE singleton = 1;") == "1")
        let recovered = try await index.synchronizeManifest(
            manifest, workspaceGeneration: 3,
            loadChanged: { try await source.load($0) }, validateManifest: {})
        #expect(recovered.disposition == (changesSource ? .incrementallyUpdated : .unchanged))
        #expect(try storage.scalarText("SELECT workspace_generation FROM search_index_state WHERE singleton = 1;") == "3")
        #expect(
            try await index.testSearch(
                SearchRequest(
                    query: changesSource ? "newneedle" : "oldneedle",
                    presentationScope: .triptych, executionScope: .triptych, limit: 20)
            ).noteResults.map(\.relativePath) == ["A.md"])
    }

    @Test("Changed source preparation overlaps while one ordered complete generation is published", .timeLimit(.minutes(1)))
    func concurrentPreparationHasOnePublication() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL, triptychID: fixture.triptychID, vaults: [fixture.vault])
        let source = FixtureSources(
            vault: fixture.vault,
            documents: ["A.md": "# Alpha\n\nCafé 自由 needle.", "B.md": "# Beta\n\nCafe\u{301} 😀 needle."])
        let admission = ConcurrentSourceAdmission()
        let manifest = await source.manifest()
        let published = try await index.synchronizeManifest(
            manifest, workspaceGeneration: 1,
            loadChanged: { entry in
                // A serial loader cannot complete: both independently authorized
                // reads must enter before either source is released.
                try await admission.enter()
                return try await source.load(entry)
            }, validateManifest: {})
        #expect(published.generation.sequence == 1)
        #expect(try await index.workspaceGeneration() == 1)
        #expect(await admission.arrivals == 2)
        let hits = try await index.testSearch(
            SearchRequest(query: "needle", presentationScope: .triptych, executionScope: .triptych, limit: 20))
        #expect(hits.noteResults.map(\.relativePath) == ["A.md", "B.md"])
        #expect(hits.noteResults.allSatisfy { $0.sourceRange != nil })
        let storage = try SearchSQLiteDatabase(path: fixture.databaseURL.path)
        var paths: [String] = []
        try storage.query("SELECT relative_path FROM search_documents ORDER BY id;") { paths.append($0.text(at: 0)!) }
        #expect(paths == ["A.md", "B.md"])
    }

    @Test("A rejected concurrent source cancels its sibling and preserves the last complete index", .timeLimit(.minutes(1)))
    func failedPreparationDrainsChildrenAndRollsBack() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL, triptychID: fixture.triptychID, vaults: [fixture.vault])
        let source = FixtureSources(vault: fixture.vault, documents: ["A.md": "oldneedle"])
        let previous = try await index.synchronizeManifest(
            await source.manifest(), workspaceGeneration: 1,
            loadChanged: { try await source.load($0) }, validateManifest: {})
        await source.replace("A.md", with: "newneedle")
        await source.replace("B.md", with: "newneedle")
        let admission = ConcurrentSourceAdmission()
        await #expect(throws: SearchIndexError.self) {
            _ = try await index.synchronizeManifest(
                await source.manifest(), workspaceGeneration: 2,
                loadChanged: { entry in
                    try await admission.enter()
                    if entry.relativePath == "B.md" {
                        return SearchIndexDocument(
                            vaultID: fixture.vault.id, vaultName: fixture.vault.name, vaultRole: fixture.vault.role,
                            document: NoteDocument(relativePath: "B.md", rawContent: "foreign revision"))
                    }
                    try await Task.sleep(for: .seconds(60))
                    return try await source.load(entry)
                }, validateManifest: {})
        }
        #expect(await admission.arrivals == 2)
        #expect(try await index.generation() == previous.generation)
        let storage = try SearchSQLiteDatabase(path: fixture.databaseURL.path)
        var persistedGeneration: Int?
        try storage.query("SELECT workspace_generation FROM search_index_state WHERE singleton = 1;") {
            persistedGeneration = $0.int(at: 0)
        }
        #expect(persistedGeneration == 1)
        #expect(
            try await index.testSearch(
                SearchRequest(query: "oldneedle", presentationScope: .triptych, executionScope: .triptych, limit: 20)
            ).noteResults.map(\.relativePath) == ["A.md"])
        let recovered = try await index.synchronizeManifest(
            await source.manifest(), workspaceGeneration: 3,
            loadChanged: { try await source.load($0) }, validateManifest: {})
        #expect(recovered.generation.sequence == 2)
        #expect(
            try await index.testSearch(
                SearchRequest(query: "newneedle", presentationScope: .triptych, executionScope: .triptych, limit: 20)
            ).noteResults.map(\.relativePath) == ["A.md", "B.md"])
    }

    @Test("Cancelling a later waiter does not cancel the older changed-row writer")
    func joinedWaiterDoesNotOwnWriterCancellation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL, triptychID: fixture.triptychID,
            vaults: [fixture.vault])
        let source = FixtureSources(vault: fixture.vault, documents: ["A.md": "# Alpha\n\noldneedle."])
        _ = try await index.synchronizeManifest(
            await source.manifest(), workspaceGeneration: 1,
            loadChanged: { try await source.load($0) }, validateManifest: {})
        await source.replace("A.md", with: "# Alpha\n\nnewneedle.")
        let revised = await source.manifest()
        let writerGate = ManifestValidationGate()
        let owner = Task {
            try await index.synchronizeManifest(
                revised, workspaceGeneration: 2,
                loadChanged: { entry in
                    await writerGate.hold()
                    return try await source.load(entry)
                }, validateManifest: {})
        }
        await writerGate.waitUntilEntered()
        let waiterGate = ManifestValidationGate()
        await index.setJoinedSynchronizationWaitForTesting { await waiterGate.hold() }
        let waiter = Task {
            try await index.synchronizeManifest(
                revised, workspaceGeneration: 3,
                loadChanged: { try await source.load($0) }, validateManifest: {})
        }
        await waiterGate.waitUntilEntered()
        waiter.cancel()
        await waiterGate.release()
        await writerGate.release()
        #expect(try await owner.value.disposition == .incrementallyUpdated)
        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(
            try await index.testSearch(
                SearchRequest(
                    query: "newneedle", presentationScope: .triptych,
                    executionScope: .triptych, limit: 20)
            ).noteResults.map(\.relativePath) == ["A.md"])
        await index.setJoinedSynchronizationWaitForTesting(nil)
    }

    @Test("A suspended changed-row read leaves last-good queries visible and rolls back on validation failure")
    func changedRowRollbackAndRecovery() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL, triptychID: fixture.triptychID,
            vaults: [fixture.vault])
        let source = FixtureSources(vault: fixture.vault, documents: ["A.md": "# Alpha\n\noldneedle."])
        let firstManifest = await source.manifest()
        let first = try await index.synchronizeManifest(
            firstManifest, workspaceGeneration: 1,
            loadChanged: { try await source.load($0) }, validateManifest: {})
        await source.replace("A.md", with: "# Alpha\n\nnewneedle.")
        let changedManifest = await source.manifest()
        let gate = ManifestValidationGate()
        let pending = Task {
            try await index.synchronizeManifest(
                changedManifest, workspaceGeneration: 2,
                loadChanged: { entry in
                    await gate.hold()
                    return try await source.load(entry)
                },
                validateManifest: { throw ProbeValidationFailure.rejected })
        }
        await gate.waitUntilEntered()
        #expect(try await index.generation() == first.generation)
        #expect(
            try await index.testSearch(
                SearchRequest(
                    query: "oldneedle", presentationScope: .triptych,
                    executionScope: .triptych, limit: 20)
            ).noteResults.map(\.relativePath) == ["A.md"])
        #expect(
            try await index.testSearch(
                SearchRequest(
                    query: "newneedle", presentationScope: .triptych,
                    executionScope: .triptych, limit: 20)
            ).noteResults.isEmpty)
        await gate.release()
        await #expect(throws: ProbeValidationFailure.self) { try await pending.value }
        #expect(try await index.generation() == first.generation)
        #expect(
            try await index.testSearch(
                SearchRequest(
                    query: "oldneedle", presentationScope: .triptych,
                    executionScope: .triptych, limit: 20)
            ).noteResults.map(\.relativePath) == ["A.md"])
        let recovered = try await index.synchronizeManifest(
            changedManifest, workspaceGeneration: 3,
            loadChanged: { try await source.load($0) }, validateManifest: {})
        #expect(recovered.disposition == .incrementallyUpdated)
        #expect(
            try await index.testSearch(
                SearchRequest(
                    query: "newneedle", presentationScope: .triptych,
                    executionScope: .triptych, limit: 20)
            ).noteResults.map(\.relativePath) == ["A.md"])
    }

    @Test("Cold, unchanged, and one-edit generations load two, zero, and one source rows")
    func changedRowsOnly() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL, triptychID: fixture.triptychID,
            vaults: [fixture.vault])
        let source = FixtureSources(
            vault: fixture.vault,
            documents: [
                "A.md": "# Alpha\n\nNeedle one.",
                "B.md": "# Beta\n\nNeedle two.",
            ])
        let first = await source.manifest()
        let cold = try await index.synchronizeManifest(
            first, workspaceGeneration: 1,
            loadChanged: { try await source.load($0) }, validateManifest: {})
        #expect(cold.disposition == .rebuilt)
        #expect(await source.loadedPaths.sorted() == ["A.md", "B.md"])
        await source.clearLoads()

        let unchanged = try await index.synchronizeManifest(
            first, workspaceGeneration: 2,
            loadChanged: { try await source.load($0) }, validateManifest: {})
        #expect(unchanged.disposition == .unchanged)
        #expect(await source.loadedPaths.isEmpty)

        await source.replace("B.md", with: "# Beta\n\nChanged needle.")
        let revised = await source.manifest()
        let changed = try await index.synchronizeManifest(
            revised, workspaceGeneration: 3,
            loadChanged: { try await source.load($0) }, validateManifest: {})
        #expect(changed.disposition == .incrementallyUpdated)
        #expect(await source.loadedPaths == ["B.md"])
        #expect(await index.lastSynchronizationTimings?.changedCount == 1)
    }

    @Test("An unchanged publication holds the sole writer while manifest validation suspends")
    func unchangedWriterRemainsSerialized() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try TriptychSearchIndex(
            databaseURL: fixture.databaseURL, triptychID: fixture.triptychID,
            vaults: [fixture.vault])
        let source = FixtureSources(vault: fixture.vault, documents: ["A.md": "# Alpha\n"])
        let manifest = await source.manifest()
        _ = try await index.synchronizeManifest(
            manifest, workspaceGeneration: 1,
            loadChanged: { try await source.load($0) }, validateManifest: {})
        let gate = ManifestValidationGate()
        let first = Task {
            try await index.synchronizeManifest(
                manifest, workspaceGeneration: 2,
                loadChanged: { try await source.load($0) },
                validateManifest: { await gate.hold() })
        }
        await gate.waitUntilEntered()
        let queued = ManifestValidationGate()
        await index.setSynchronizationQueuedForTesting { generation in
            if generation == 3 { await queued.hold() }
        }
        let second = Task {
            try await index.synchronizeManifest(
                manifest, workspaceGeneration: 3,
                loadChanged: { try await source.load($0) }, validateManifest: {})
        }
        await queued.waitUntilEntered()
        await gate.release()
        await queued.release()
        #expect(try await first.value.disposition == .unchanged)
        #expect(try await second.value.disposition == .unchanged)
        #expect(try await index.workspaceGeneration() == 3)
        await index.setSynchronizationQueuedForTesting(nil)
    }
}

/// Cancellation-aware rendezvous; a failed or timed-out publication cannot
/// strand the task-group drain in a noncancellable test continuation.
private actor ConcurrentSourceAdmission {
    private(set) var arrivals = 0
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]

    func enter() async throws {
        try Task.checkCancellation()
        arrivals += 1
        if arrivals == 2 {
            let pending = waiters.values
            waiters.removeAll()
            for continuation in pending { continuation.resume() }
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) } else { waiters[id] = continuation }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func cancel(_ id: UUID) { waiters.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
}

private enum ProbeValidationFailure: Error { case rejected }

private struct Fixture {
    let root: URL
    let databaseURL: URL
    let triptychID = UUID()
    let vault: RegisteredVault

    init() throws {
        root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/search-manifest-tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        databaseURL = root.appendingPathComponent("search.sqlite")
        vault = RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: root.path)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

private actor FixtureSources {
    let vault: RegisteredVault
    var documents: [String: String]
    private(set) var loadedPaths: [String] = []

    init(vault: RegisteredVault, documents: [String: String]) {
        self.vault = vault
        self.documents = documents
    }

    func manifest() -> [SearchIndexManifestEntry] {
        documents.keys.sorted().compactMap { path in
            guard let source = documents[path] else { return nil }
            return SearchIndexManifestEntry(
                vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role,
                relativePath: path, stableNoteID: nil,
                fingerprint: DocumentFingerprint(content: source), hasBrokenLink: false)
        }
    }

    func load(_ entry: SearchIndexManifestEntry) throws -> SearchIndexDocument {
        guard let source = documents[entry.relativePath] else {
            throw SearchIndexError.invalidDocuments("missing fixture source")
        }
        loadedPaths.append(entry.relativePath)
        return SearchIndexDocument(
            vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role,
            document: NoteDocument(relativePath: entry.relativePath, rawContent: source))
    }

    func replace(_ path: String, with source: String) { documents[path] = source }
    func clearLoads() { loadedPaths = [] }
}

private actor ManifestValidationGate {
    private var entered = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func hold() async {
        entered = true
        arrival?.resume()
        arrival = nil
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
