import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Compact Search manifest publication")
struct SearchManifestHydrationTests {
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
        #expect(await source.loadedPaths == ["A.md", "B.md"])
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
