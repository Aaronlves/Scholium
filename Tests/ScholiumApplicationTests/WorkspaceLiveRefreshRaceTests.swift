import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Live refresh admission races")
struct WorkspaceLiveRefreshRaceTests {
    enum ExternalChange: String, CaseIterable, Sendable {
        case none, source, folder, identity, fileMetadata
    }

    #if DEBUG
        // This deterministic barrier is compiled only into the Debug runtime.
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
                    let sourceGeneration = try await catalog.snapshot().generation
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
                        #expect(try await catalog.snapshot().generation == sourceGeneration)
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

        @Test(
            "An editor-style source-only save and its own watcher hints publish one current derived generation",
            .timeLimit(.minutes(1)))
        func sourceOnlyTypingCommitCoalescesOwnWatcherHints() async throws {
            try await withWorkspace { runtime, handle, id, sourceURL in
                _ = try await handle.refresh()
                if let task = await handle.liveIndexRefreshTask?.task { await task.value }
                let stream = await handle.events.events()
                var iterator = stream.makeAsyncIterator()
                let initial = try #require(await iterator.next())
                try #require(initial.snapshot.phase.isComplete)
                let initialGraphGeneration = await handle.nextGraphGeneration
                let original = try await handle.documents.load(id)
                let target = try await capturedSaveTarget(handle, id, revision: original.fingerprint)
                let liveBarrier = LiveInventoryPreflightBarrier()
                let commitBarrier = LiveInventoryPreflightBarrier()
                await handle.setLiveInventoryPreflightBarrierForTesting { await liveBarrier.holdOnce() }
                await handle.setCommittedMutationRefreshBarrierForTesting { await commitBarrier.holdOnce() }
                do {
                    try await withTaskCancellationHandler {
                        // Hold a harmless preflight while the editor commits durable bytes.
                        try await runtime.deliverPooledVaultEventForTesting(.reconciliationRequired(sequence: 100), vaultID: id.vaultID)
                        await liveBarrier.waitUntilArrived()
                        try Task.checkCancellation()
                        let liveTask = try #require(await handle.liveIndexRefreshTask?.task)
                        let typedSource = original.rawContent + "x"
                        let saved = try await handle.documents.commit(target, changeSet: .source(typedSource))
                        await commitBarrier.waitUntilArrived()
                        try Task.checkCancellation()
                        let committedTask = try #require(await handle.sourceCommitRefreshTask)
                        #expect(saved.document.fingerprint == DocumentFingerprint(content: typedSource))
                        #expect(try Data(contentsOf: sourceURL) == Data(typedSource.utf8))
                        // This is the synthetic counterpart of the committed file's own event.
                        try await runtime.deliverPooledVaultEventForTesting(
                            .init(added: [], modified: [id.relativePath], deleted: [], sequence: 101, requiresFullRescan: false, rootChanged: false),
                            vaultID: id.vaultID)
                        await handle.setCommittedMutationRefreshBarrierForTesting(nil)
                        await commitBarrier.release()
                        await committedTask.value
                        let published = try #require(await iterator.next())
                        let kind: String
                        switch published {
                        case .sourceCommitted: kind = "sourceCommitted"
                        case .derivedStateChanged: kind = "derivedStateChanged"
                        case .inventoryChanged: kind = "inventoryChanged"
                        default: kind = "other"
                        }
                        let status: String
                        let reason: String
                        switch published.derivedRefreshStatus {
                        case .current:
                            status = "current"
                            reason = ""
                        case .opening:
                            status = "opening"
                            reason = ""
                        case .stale(let issue):
                            status = "stale"
                            reason = issue.reason
                        case .failed(let issue):
                            status = "failed"
                            reason = issue.reason
                        }
                        let committed = try await handle.snapshot()
                        let committedGraphGeneration = await handle.nextGraphGeneration
                        let receipt: [String: Any] = [
                            "event": kind, "status": status, "reason": reason,
                            "initial_generation": initial.generation, "published_generation": published.generation,
                            "initial_next_graph": initialGraphGeneration, "committed_next_graph": committedGraphGeneration,
                            "durable_fingerprint": saved.document.fingerprint.sha256,
                            "derived_fingerprint": committed.document(id: id)?.fingerprint.sha256 ?? "missing",
                        ]
                        print(
                            "SOURCE_ONLY_WATCHER_RECEIPT "
                                + String(decoding: try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]), as: UTF8.self))
                        #expect(kind == "sourceCommitted" && status == "current", "Ordinary source-only typing must not publish a derived failure: \(reason)")
                        #expect(published.generation == initial.generation + 1)
                        #expect(committedGraphGeneration == initialGraphGeneration + 1)
                        #expect(committed.document(id: id)?.fingerprint == saved.document.fingerprint)
                        let evidence = WorkspaceDerivedRefreshEvidence(snapshot: committed)
                        await liveBarrier.release()
                        await liveTask.value
                        let final = try await handle.snapshot()
                        #expect(WorkspaceDerivedRefreshEvidence(snapshot: final) == evidence)
                        #expect(await handle.events.publishedGeneration == published.generation)
                        #expect(await handle.nextGraphGeneration == committedGraphGeneration)
                        #expect(try Data(contentsOf: sourceURL) == Data(typedSource.utf8))
                        print(
                            "SOURCE_ONLY_WATCHER_SETTLED generation=\(await handle.events.publishedGeneration) next_graph=\(await handle.nextGraphGeneration) fingerprint=\(final.document(id: id)?.fingerprint.sha256 ?? "missing")"
                        )
                    } onCancel: {
                        Task {
                            await liveBarrier.cancel()
                            await commitBarrier.cancel()
                        }
                    }
                    await handle.setLiveInventoryPreflightBarrierForTesting(nil)
                    await handle.setCommittedMutationRefreshBarrierForTesting(nil)
                } catch {
                    await liveBarrier.cancel()
                    await commitBarrier.cancel()
                    await handle.setLiveInventoryPreflightBarrierForTesting(nil)
                    await handle.setCommittedMutationRefreshBarrierForTesting(nil)
                    throw error
                }
            }
        }

        enum SourceRecaptureOrigin: CaseIterable, Sendable { case externalWriter, appCommit }

        @Test(
            "Readers never observe an index failure while a proven source cohort is being recaptured", .timeLimit(.minutes(1)),
            arguments: SourceRecaptureOrigin.allCases)
        func concurrentReadersDuringSourceRecapture(origin: SourceRecaptureOrigin) async throws {
            try await withWorkspace { runtime, handle, id, sourceURL in
                _ = try await handle.refresh()
                if let live = await handle.liveIndexRefreshTask?.task { await live.value }
                let initial = try await handle.snapshot()
                let generation = try #require(initial.discovery.searchGeneration)
                let evidence = WorkspaceDerivedRefreshEvidence(snapshot: initial)
                let original = try await handle.documents.load(id)
                let target = try await capturedSaveTarget(handle, id, revision: original.fingerprint)
                let commitBarrier = LiveInventoryPreflightBarrier()
                if origin == .appCommit {
                    await handle.setCommittedMutationRefreshBarrierForTesting { await commitBarrier.holdOnce() }
                }
                let first = LiveInventoryPreflightBarrier()
                let recapture = LiveInventoryPreflightBarrier()
                let ordinal = SourceRecaptureOrdinal()
                await handle.setCapturedSearchManifestBarrierForTesting {
                    switch await ordinal.next() {
                    case 1: await first.holdOnce()
                    case 2: await recapture.holdOnce()
                    default: break
                    }
                }
                let refreshing = Task { try await handle.refresh() }
                try await withTaskCancellationHandler {
                    do {
                        await first.waitUntilArrived()
                        try Task.checkCancellation()
                        let changed = Data("# Current external source\n\nFresh exact source bytes.\n".utf8)
                        if origin == .appCommit {
                            _ = try await handle.documents.commit(target, changeSet: .source(String(decoding: changed, as: UTF8.self)))
                            await commitBarrier.waitUntilArrived()
                            try Task.checkCancellation()
                        } else {
                            try changed.write(to: sourceURL)
                        }
                        await first.release()
                        await recapture.waitUntilArrived()
                        try Task.checkCancellation()
                        let index = try await handle.services.searchIndex
                        let availability = await index.availability()
                        #expect(availability == .current(generation))
                        let request = RelatedContentRequest(seed: .init(noteID: id, source: "Unsaved current writing about exact source."))
                        let related = try await handle.relatedContent(request)
                        #expect(related.availability == .current(generation))
                        #expect(related.state != .unavailable)
                        // A stale response may honestly await the new App
                        // generation; it must not carry an index failure.
                        #expect(WorkspaceDerivedRefreshEvidence(snapshot: try await handle.snapshot()) == evidence)
                        print(
                            "CONCURRENT_COHORT_READER origin=\(origin) index=\(availability) related_state=\(related.state) related_availability=\(related.availability)"
                        )
                        await recapture.release()
                        let final = try await refreshing.value
                        #expect(final.document(id: id)?.fingerprint == DocumentFingerprint(content: String(decoding: changed, as: UTF8.self)))
                        #expect(final.discovery.searchGeneration != generation)
                        #expect(try Data(contentsOf: sourceURL) == changed)
                        await handle.setCapturedSearchManifestBarrierForTesting(nil)
                        await handle.setCommittedMutationRefreshBarrierForTesting(nil)
                        await commitBarrier.release()
                        if let committed = await handle.sourceCommitRefreshTask { await committed.value }
                        #expect(try Data(contentsOf: sourceURL) == changed)
                    } catch {
                        await first.cancel()
                        await recapture.cancel()
                        await commitBarrier.cancel()
                        await handle.setCommittedMutationRefreshBarrierForTesting(nil)
                        refreshing.cancel()
                        await handle.setCapturedSearchManifestBarrierForTesting(nil)
                        await runtime.shutdown()
                        _ = await refreshing.result
                        throw error
                    }
                } onCancel: {
                    refreshing.cancel()
                    Task {
                        await first.cancel()
                        await recapture.cancel()
                        await commitBarrier.cancel()
                    }
                }
            }
        }

        enum CapturedExternalSourceChange: String, CaseIterable, Sendable {
            case bodyAppend, identicalAtomicReplacement, deletion
        }

        enum CapturedSourceBoundary: String, CaseIterable, Sendable {
            case finalValidation, changedRow
        }

        @Test(
            "An external descriptor change after source capture is recaptured without a derived failure",
            .timeLimit(.minutes(1)), arguments: CapturedSourceBoundary.allCases, CapturedExternalSourceChange.allCases)
        func externalSourceSupersedesCapturedManifest(boundary: CapturedSourceBoundary, change: CapturedExternalSourceChange) async throws {
            try await withWorkspace { runtime, handle, id, sourceURL in
                _ = try await handle.refresh()
                if let live = await handle.liveIndexRefreshTask?.task { await live.value }
                let initial = try await handle.snapshot()
                try #require(initial.phase.isComplete)
                let lastGood = WorkspaceDerivedRefreshEvidence(snapshot: initial)
                let initialGeneration = await handle.events.publishedGeneration
                let stableID = try #require(initial.document(id: id)?.stableIdentity.resolvedID)
                let repository = try await handle.repository(vaultID: id.vaultID)
                let authorityToken = await handle.sourceAuthorityToken
                let stream = await handle.events.events()
                let publications = Task { () -> [WorkspaceEvent] in
                    var recorded: [WorkspaceEvent] = []
                    for await event in stream { recorded.append(event) }
                    return recorded
                }
                let barrier = LiveInventoryPreflightBarrier()
                await handle.setCapturedSearchManifestBarrierForTesting { await barrier.holdOnce() }
                if boundary == .changedRow {
                    // Index A remains current while the captured source becomes
                    // B, requiring row hydration during this refresh.
                    try Data("# Before capture\n\nChanged source B.\n".utf8).write(to: sourceURL)
                }
                let refreshing = Task { try await handle.refresh() }
                try await withTaskCancellationHandler {
                    do {
                        await barrier.waitUntilArrived()
                        try Task.checkCancellation()
                        let blocked = try await handle.snapshot()
                        #expect(WorkspaceDerivedRefreshEvidence(snapshot: blocked) == lastGood)
                        let original = try await repository.loadVersioned(relativePath: id.relativePath)
                        let originalBytes = try Data(contentsOf: sourceURL)
                        var expectedBytes: Data? = originalBytes
                        switch change {
                        case .bodyAppend:
                            let addition = Data("\nExternally appended exact source. 中文 😀\n".utf8)
                            let file = try FileHandle(forWritingTo: sourceURL)
                            defer { try? file.close() }
                            try file.seekToEnd()
                            try file.write(contentsOf: addition)
                            expectedBytes?.append(addition)
                        case .identicalAtomicReplacement:
                            try originalBytes.write(to: sourceURL, options: .atomic)
                        case .deletion:
                            try FileManager.default.removeItem(at: sourceURL)
                            expectedBytes = nil
                        }
                        let replacement = change == .deletion ? nil : try await repository.loadVersioned(relativePath: id.relativePath)
                        if let replacement {
                            #expect(replacement.version != original.version)
                            if change == .identicalAtomicReplacement {
                                #expect(replacement.document.fingerprint == original.document.fingerprint)
                                #expect(replacement.version.inode != original.version.inode)
                            } else {
                                #expect(replacement.document.fingerprint != original.document.fingerprint)
                            }
                        }
                        // External writers do not acquire the App mutation lease.
                        #expect(await handle.sourceAuthorityToken == authorityToken)
                        let stillBlocked = try await handle.snapshot()
                        #expect(WorkspaceDerivedRefreshEvidence(snapshot: stillBlocked) == lastGood)
                        #expect((try? Data(contentsOf: sourceURL)) == expectedBytes)
                        await barrier.release()
                        let outcome = await refreshing.result
                        let succeeded: Bool
                        switch outcome {
                        case .success(let refreshed):
                            succeeded = true
                            #expect(refreshed.phase.isComplete)
                            #expect(refreshed.document(id: id)?.fingerprint == replacement?.document.fingerprint)
                        case .failure(let error):
                            succeeded = false
                            Issue.record("A known superseded source cohort became a failed refresh: \(error)")
                        }
                        await handle.setCapturedSearchManifestBarrierForTesting(nil)
                        let final = try await handle.snapshot()
                        #expect(final.phase.isComplete)
                        #expect(final.document(id: id)?.fingerprint == replacement?.document.fingerprint)
                        #expect(final.document(id: id)?.stableIdentity.resolvedID == (change == .deletion ? nil : stableID))
                        #expect(final.discovery.catalog.graph?.sourceManifestHash == final.discovery.searchGeneration?.sourceManifestHash)
                        let catalog = try #require(await handle.services.sourceCatalogs[id.vaultID])
                        if let replacement {
                            #expect(
                                await catalog.sourceVersion(relativePath: id.relativePath, fingerprint: replacement.document.fingerprint) == replacement.version
                            )
                        } else {
                            let inventory = try? await catalog.sourceInventory()
                            #expect(inventory != nil)
                            #expect(inventory?[id.relativePath] == nil)
                        }
                        #expect((try? Data(contentsOf: sourceURL)) == expectedBytes)
                        // Join watcher/event completion rather than assuming a
                        // sleep proves that no later warning was published.
                        await runtime.shutdown()
                        let events = await publications.value
                        let later = events.filter { $0.generation > initialGeneration }
                        let failures = later.filter { event in
                            switch event.derivedRefreshStatus {
                            case .failed, .stale: true
                            case .opening, .current: false
                            }
                        }
                        #expect(failures.count == 0)
                        #expect(later.count == 1)
                        #expect(later.last?.snapshot.document(id: id)?.fingerprint == replacement?.document.fingerprint)
                        print(
                            "EXTERNAL_COHORT_RECEIPT boundary=\(boundary.rawValue) case=\(change.rawValue) refresh_succeeded=\(succeeded) publications=\(later.count) failed_or_stale=\(failures.count) authority_token_unchanged=\(await handle.sourceAuthorityToken == authorityToken)"
                        )
                    } catch {
                        await barrier.cancel()
                        refreshing.cancel()
                        await handle.setCapturedSearchManifestBarrierForTesting(nil)
                        await runtime.shutdown()
                        _ = await refreshing.result
                        _ = await publications.value
                        throw error
                    }
                } onCancel: {
                    refreshing.cancel()
                    Task { await barrier.cancel() }
                }
            }
        }

        enum CapturedGenuineFailure: String, CaseIterable, Sendable {
            case invalidUTF8, closedSearchIndex
        }

        @Test(
            "A genuine source decoding or Search backend failure is not a successful recapture",
            .timeLimit(.minutes(1)), arguments: CapturedGenuineFailure.allCases)
        func genuineFailureRemainsVisible(failure: CapturedGenuineFailure) async throws {
            try await withWorkspace { runtime, handle, _, sourceURL in
                _ = try await handle.refresh()
                if let live = await handle.liveIndexRefreshTask?.task { await live.value }
                let lastGood = WorkspaceDerivedRefreshEvidence(snapshot: try await handle.snapshot())
                let originalBytes = try Data(contentsOf: sourceURL)
                let barrier = LiveInventoryPreflightBarrier()
                await handle.setCapturedSearchManifestBarrierForTesting { await barrier.holdOnce() }
                let stream = await handle.events.events()
                let publications = Task { () -> [WorkspaceEvent] in
                    var recorded: [WorkspaceEvent] = []
                    for await event in stream { recorded.append(event) }
                    return recorded
                }
                let refreshing = Task { try await handle.refresh() }
                try await withTaskCancellationHandler {
                    do {
                        await barrier.waitUntilArrived()
                        try Task.checkCancellation()
                        let expectedBytes: Data
                        switch failure {
                        case .invalidUTF8:
                            expectedBytes = Data([0xFF, 0xFE, 0xFF])
                            try expectedBytes.write(to: sourceURL)
                        case .closedSearchIndex:
                            expectedBytes = originalBytes
                            let index = try await handle.services.searchIndex
                            await index.shutdown()
                        }
                        await barrier.release()
                        let outcome = await refreshing.result
                        switch outcome {
                        case .success:
                            Issue.record("A genuine source/backend failure was treated as a current refresh")
                        case .failure(let error):
                            switch failure {
                            case .invalidUTF8:
                                #expect((error as? CocoaError)?.code == .fileReadInapplicableStringEncoding)
                            case .closedSearchIndex:
                                if case .sqlite = error as? SearchIndexError {
                                } else {
                                    Issue.record("The real Search backend failure lost its typed outcome: \(error)")
                                }
                            }
                        }
                        await handle.setCapturedSearchManifestBarrierForTesting(nil)
                        #expect(WorkspaceDerivedRefreshEvidence(snapshot: try await handle.snapshot()) == lastGood)
                        #expect(try Data(contentsOf: sourceURL) == expectedBytes)
                        await runtime.shutdown()
                        let events = await publications.value
                        let failed = events.filter { if case .failed = $0.derivedRefreshStatus { true } else { false } }
                        #expect(failed.count == 1)
                        print("GENUINE_COHORT_FAILURE case=\(failure.rawValue) failed_events=\(failed.count) last_good_preserved=true")
                    } catch {
                        await barrier.cancel()
                        refreshing.cancel()
                        await handle.setCapturedSearchManifestBarrierForTesting(nil)
                        await runtime.shutdown()
                        _ = await refreshing.result
                        _ = await publications.value
                        throw error
                    }
                } onCancel: {
                    refreshing.cancel()
                    Task { await barrier.cancel() }
                }
            }
        }

    #endif

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

    func cancel() {
        arrived = true
        arrival?.resume()
        arrival = nil
        release()
    }
}

private actor SourceRecaptureOrdinal {
    private var value = 0
    func next() -> Int {
        value += 1
        return value
    }
}
