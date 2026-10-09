import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Live refresh admission races")
struct WorkspaceLiveRefreshRaceTests {
    enum ExternalChange: String, CaseIterable, Sendable {
        case none, source, folder, identity, fileMetadata
    }

    @Test(
        "A delayed live preflight skips an already published commit and retains later content, folder, identity, and metadata changes",
        arguments: ExternalChange.allCases)
    func publishedCommitOvertakesLivePreflight(externalChange: ExternalChange) async throws {
        try await withWorkspace { runtime, handle, id, sourceURL in
            let original = try await handle.documents.load(id)
            let target = try await capturedSaveTarget(handle, id, revision: original.fingerprint)
            let barrier = LiveInventoryPreflightBarrier()
            await handle.setLiveInventoryPreflightBarrierForTesting { await barrier.holdOnce() }
            do {
                try await runtime.deliverPooledVaultEventForTesting(.reconciliationRequired(sequence: 100), vaultID: id.vaultID)
                await barrier.waitUntilArrived()
                let liveTask = try #require(await handle.liveIndexRefreshTask?.task)
                let committedText = "# Committed\r\n\r\nExact source B. 😀\r\n"
                let save = try await handle.documents.save(target, changeSet: .source(committedText))
                let committed = try await handle.snapshot()
                #expect(committed.phase.isComplete)
                #expect(committed.document(id: id)?.fingerprint == save.committedValue.document.fingerprint)
                let evidence = WorkspaceDerivedRefreshEvidence(snapshot: committed)
                let catalog = try #require(await handle.services.sourceCatalogs[id.vaultID])
                let sourceGeneration = try await catalog.snapshot(refreshFolders: false).generation
                let externalText = "# External\n\nA later external source C.\n"
                let committedNote = try #require(committed.document(id: id))
                let committedGraph = try #require(committed.discovery.catalog.graph)
                let laterIdentity = UUID()
                switch externalChange {
                case .none:
                    break
                case .source:
                    try Data(externalText.utf8).write(to: sourceURL)
                    try await runtime.deliverPooledVaultEventForTesting(
                        .init(added: [], modified: [id.relativePath], deleted: [], sequence: 101, requiresFullRescan: false, rootChanged: false),
                        vaultID: id.vaultID)
                case .folder:
                    try FileManager.default.createDirectory(
                        at: sourceURL.deletingLastPathComponent().appendingPathComponent("Later folder"), withIntermediateDirectories: true)
                    try await runtime.deliverPooledVaultEventForTesting(.reconciliationRequired(sequence: 101), vaultID: id.vaultID)
                case .identity:
                    let noteID = try #require(committedNote.stableIdentity.resolvedID)
                    _ = try await handle.services.controlStore.purgeIdentity(id: noteID, vaultID: id.vaultID, relativePath: id.relativePath)
                    _ = try await handle.services.controlStore.identity(
                        forVaultID: id.vaultID, relativePath: id.relativePath, fingerprint: committedNote.fingerprint, preferredID: laterIdentity)
                    try await runtime.deliverPooledVaultEventForTesting(.reconciliationRequired(sequence: 101), vaultID: id.vaultID)
                case .fileMetadata:
                    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: sourceURL.path)
                    try await runtime.deliverPooledVaultEventForTesting(
                        .init(added: [], modified: [id.relativePath], deleted: [], sequence: 101, requiresFullRescan: false, rootChanged: false),
                        vaultID: id.vaultID)
                }
                await barrier.release()
                await liveTask.value
                let final = try await handle.snapshot()
                #expect(final.phase.isComplete)
                let finalGraph = try #require(final.discovery.catalog.graph)
                switch externalChange {
                case .source:
                    #expect(final.document(id: id)?.fingerprint == DocumentFingerprint(content: externalText))
                    #expect(finalGraph.generation > committedGraph.generation)
                    #expect(final.discovery.searchGeneration != committed.discovery.searchGeneration)
                    #expect(try Data(contentsOf: sourceURL) == Data(externalText.utf8))
                case .folder:
                    #expect(final.vault(id: id.vaultID)?.folders.contains(where: { $0.rawValue == "Later folder" }) == true)
                    #expect(finalGraph.generation > committedGraph.generation)
                    #expect(final.document(id: id)?.fingerprint == committedNote.fingerprint)
                case .identity:
                    #expect(final.document(id: id)?.stableIdentity.resolvedID == laterIdentity)
                    #expect(finalGraph.generation > committedGraph.generation)
                    #expect(final.document(id: id)?.fingerprint == committedNote.fingerprint)
                case .fileMetadata:
                    #expect(final.document(id: id)?.fileMetadata != committedNote.fileMetadata)
                    #expect(finalGraph.generation > committedGraph.generation)
                    #expect(final.document(id: id)?.fingerprint == committedNote.fingerprint)
                case .none:
                    #expect(WorkspaceDerivedRefreshEvidence(snapshot: final) == evidence)
                    #expect(try await catalog.snapshot(refreshFolders: false).generation == sourceGeneration)
                    #expect(try Data(contentsOf: sourceURL) == Data(committedText.utf8))
                }
                await handle.setLiveInventoryPreflightBarrierForTesting(nil)
            } catch {
                await barrier.release()
                await handle.setLiveInventoryPreflightBarrierForTesting(nil)
                throw error
            }
        }
    }

    @Test("A queued live-only refresh revalidates its complete inputs under the source lease")
    func queuedLiveRefreshRevalidatesPublishedInputs() async throws {
        try await withWorkspace { _, handle, id, _ in
            let original = try await handle.documents.load(id)
            let target = try await capturedSaveTarget(handle, id, revision: original.fingerprint)
            _ = try await handle.documents.save(target, changeSet: .source("# Queued\n\nPublished source.\n"))
            let committed = try await handle.snapshot()
            #expect(committed.phase.isComplete)
            let evidence = WorkspaceDerivedRefreshEvidence(snapshot: committed)
            let nextGraphGeneration = await handle.nextGraphGeneration
            let retained = try await handle.refresh(publication: .liveInventory)
            #expect(WorkspaceDerivedRefreshEvidence(snapshot: retained) == evidence)
            #expect(await handle.nextGraphGeneration == nextGraphGeneration)
            let explicit = try await handle.refresh()
            let retainedGraph = try #require(retained.discovery.catalog.graph)
            let explicitGraph = try #require(explicit.discovery.catalog.graph)
            #expect(explicitGraph.generation > retainedGraph.generation)
        }
    }

    private func withWorkspace(_ body: (WorkspaceRuntime, WorkspaceHandle, VaultQualifiedNoteID, URL) async throws -> Void) async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/live-refresh-race/\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let analyses = root.appendingPathComponent("Analyses")
        let topics = root.appendingPathComponent("Topics")
        let works = root.appendingPathComponent("Works")
        for folder in [analyses, topics, works] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let sourceURL = analyses.appendingPathComponent("Source.md")
        try Data("# Original\n\nExact source A.\n".utf8).write(to: sourceURL)
        try Data("# Topic\n".utf8).write(to: topics.appendingPathComponent("Topic.md"))
        try Data("# Work\n".utf8).write(to: works.appendingPathComponent("Work.md"))
        let runtime = WorkspaceRuntime(configuration: .live(.init(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))))
        do {
            let handle = try await runtime.configureTriptych(
                paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works, portableContainerURL: root, triptychName: "Live refresh race")
            let vault = try #require(handle.assignment.vault(for: .paperAnalysis))
            try await body(runtime, handle, .init(vaultID: vault.id, relativePath: "Source.md"), sourceURL)
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
    }
}

private actor LiveInventoryPreflightBarrier {
    private var arrived = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var held: CheckedContinuation<Void, Never>?

    func holdOnce() async {
        guard !arrived else { return }
        arrived = true
        arrival?.resume()
        arrival = nil
        await withCheckedContinuation { held = $0 }
    }

    func waitUntilArrived() async {
        if arrived { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func release() {
        held?.resume()
        held = nil
    }
}
