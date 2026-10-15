import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

#if DEBUG
    @Suite("External edits during workspace opening")
    struct WorkspaceOpeningExternalEditTests {
        enum Completion: String, CaseIterable, Sendable {
            case recoverBufferedEdit
            case shutDownWhileCaptured
        }

        @Test(
            "A captured opening rejects replaced source and either recovers its buffered edit or shuts down cleanly",
            .timeLimit(.minutes(2)), arguments: Completion.allCases)
        func externalEditAfterManifestCapture(completion: Completion) async throws {
            let fixture = try await ApplicationFixture.make(registerLiveAccess: true)
            defer { fixture.remove() }
            let sourceURL = fixture.analysesURL.appendingPathComponent(fixture.analysisNoteID.relativePath)
            let sourceA = "# Agency\n\nopeningoldneedle belongs to the captured source.\n"
            let sourceB = "# Agency\n\nopeningnewneedle belongs to the external replacement.\n"
            try Data(sourceA.utf8).write(to: sourceURL, options: .atomic)
            let runtime = WorkspaceRuntime(
                configuration: .live(
                    .init(
                        applicationSupportURL: fixture.applicationSupportURL,
                        workspaceRegistryStorageURL: fixture.registryStorageURL)))
            let handle: WorkspaceHandle
            do {
                handle = try await runtime.openWorkspace(id: fixture.assignment.id, openingVault: .paperAnalysis)
            } catch {
                await runtime.shutdown()
                throw error
            }
            let barrier = OpeningExternalEditBarrier()
            let stream = await handle.events.events()
            let publications = Task {
                var complete: [WorkspaceSnapshot] = []
                for await event in stream where event.snapshot.phase.isComplete {
                    complete.append(event.snapshot)
                }
                return complete
            }
            let lifecycle = OpeningExternalEditLifecycle(
                runtime: runtime, handle: handle, barrier: barrier, publications: publications)
            try await withTaskCancellationHandler {
                do {
                    await handle.setCapturedSearchManifestBarrierForTesting { await barrier.holdOnce() }
                    await handle.openingPresentationDidComplete()
                    try #require(await barrier.waitUntilArrived())
                    let opening = try await handle.snapshot()
                    #expect(opening.phase == .opening)
                    #expect(opening.vaults.map(\.slot) == WorkspaceVaultSlot.allCases)
                    #expect(opening.sourceInventoryRevision > 0)
                    #expect(opening.discovery.searchGeneration == nil)
                    #expect(opening.discovery.catalog.graph == nil)
                    #expect(opening.document(id: fixture.analysisNoteID)?.fingerprint == DocumentFingerprint(content: sourceA))
                    let retainedSearchGeneration = try await handle.services.searchIndex.generation()

                    // The complete builder has captured A. This write bypasses
                    // Scholium's source lease, as a real external editor does.
                    try Data(sourceB.utf8).write(to: sourceURL, options: .atomic)
                    let eventSequence: UInt64 = 42
                    try await runtime.deliverPooledVaultEventForTesting(
                        .init(
                            added: [], modified: [fixture.analysisNoteID.relativePath], deleted: [],
                            sequence: eventSequence, requiresFullRescan: false, rootChanged: false),
                        vaultID: fixture.analysisNoteID.vaultID)
                    try await waitUntil("the external invalidation is buffered before row validation") {
                        await handle.pendingLiveEvents[fixture.analysisNoteID.vaultID]?.events
                            .contains(where: { $0.sequence == eventSequence }) == true
                    }
                    #expect(try await handle.snapshot().phase == .opening)
                    #expect(try await handle.services.searchIndex.generation() == retainedSearchGeneration)
                    if completion == .shutDownWhileCaptured {
                        // Shutdown must cancel the still-held builder itself.
                        // Releasing first would let a complete publication race
                        // ahead of departure and would not test cancellation.
                        await runtime.shutdown()
                        await lifecycle.cleanup()
                        #expect(await publications.value.isEmpty)
                        #expect(await handle.ownedBackgroundTaskCount == 0)
                        #expect(!(await handle.sourceOperationGate.refreshCycleIsActive))
                        #expect(!(await handle.sourceOperationGate.sourceMutationIsActive))
                        #expect(await handle.sourceOperationGate.waitingCount == 0)
                        #expect(try Data(contentsOf: sourceURL) == Data(sourceB.utf8))
                        return
                    }
                    await barrier.release()
                    await handle.awaitOpeningCompletionForTesting()

                    // No explicit refresh: the buffered native invalidation
                    // must recover the rejected first complete generation.
                    try await waitUntil("opening converges after its captured source is replaced") {
                        try await handle.snapshot().phase.isComplete
                    }
                    let complete = try await handle.snapshot()
                    #expect(complete.vaults.count == 3)
                    #expect(complete.vaults.flatMap(\.documents).count == 3)
                    #expect(complete.document(id: fixture.analysisNoteID)?.fingerprint == DocumentFingerprint(content: sourceB))
                    let searchGeneration = try #require(complete.discovery.searchGeneration)
                    let graph = try #require(complete.discovery.catalog.graph)
                    #expect(graph.sourceManifestHash == searchGeneration.sourceManifestHash)
                    let newResults = try await handle.discovery.search(
                        SearchRequest(
                            query: "openingnewneedle", presentationScope: .triptych,
                            executionScope: .triptych, limit: 20))
                    #expect(
                        newResults.results.compactMap { result -> VaultQualifiedNoteID? in
                            guard case .note(let note) = result else { return nil }
                            return note.noteReference
                        } == [fixture.analysisNoteID])
                    let oldResults = try await handle.discovery.search(
                        SearchRequest(
                            query: "openingoldneedle", presentationScope: .triptych,
                            executionScope: .triptych, limit: 20))
                    #expect(oldResults.results.isEmpty)
                    #expect(try Data(contentsOf: sourceURL) == Data(sourceB.utf8))

                    await lifecycle.cleanup()
                    let observed = await publications.value
                    #expect(!observed.isEmpty)
                    for snapshot in observed {
                        #expect(snapshot.vaults.count == 3)
                        #expect(snapshot.document(id: fixture.analysisNoteID)?.fingerprint == DocumentFingerprint(content: sourceB))
                    }
                    #expect(await handle.ownedBackgroundTaskCount == 0)
                    #expect(!(await handle.sourceOperationGate.refreshCycleIsActive))
                    #expect(!(await handle.sourceOperationGate.sourceMutationIsActive))
                    #expect(await handle.sourceOperationGate.waitingCount == 0)
                } catch {
                    await lifecycle.cleanup()
                    throw error
                }
            } onCancel: {
                Task { await lifecycle.cleanup() }
            }
        }

        @Test("Every prepared Library is usable before Search finishes without acknowledging newly observed Notes", .timeLimit(.minutes(2)))
        func sourceLibrariesPublishBeforeCompleteIndex() async throws {
            let fixture = try await ApplicationFixture.make(registerLiveAccess: true)
            defer { fixture.remove() }
            let topicsVaultID = try #require(fixture.assignment.vault(for: .topicKnowledge)?.id)
            let firstSeenID = VaultQualifiedNoteID(vaultID: topicsVaultID, relativePath: "First Seen.md")
            let firstSeenSource = Data("\u{FEFF}# First Seen\r\n\r\nfirstseenlibraryneedle belongs to existing source.".utf8)
            try firstSeenSource.write(to: fixture.topicsURL.appendingPathComponent(firstSeenID.relativePath))
            let runtime = WorkspaceRuntime(
                configuration: .live(
                    .init(
                        applicationSupportURL: fixture.applicationSupportURL,
                        workspaceRegistryStorageURL: fixture.registryStorageURL)))
            let handle: WorkspaceHandle
            do {
                handle = try await runtime.openWorkspace(id: fixture.assignment.id, openingVault: .paperAnalysis)
            } catch {
                await runtime.shutdown()
                throw error
            }
            let barrier = OpeningExternalEditBarrier()
            let events = await handle.events.events()
            let publications = Task {
                var snapshots: [WorkspaceSnapshot] = []
                for await event in events { snapshots.append(event.snapshot) }
                return snapshots
            }
            let lifecycle = OpeningExternalEditLifecycle(
                runtime: runtime, handle: handle, barrier: barrier, publications: publications)
            try await withTaskCancellationHandler {
                do {
                    let first = try await handle.snapshot()
                    #expect(first.phase == .opening)
                    #expect(first.vaults.map(\.slot) == [.paperAnalysis])
                    let newlyObservedID = VaultQualifiedNoteID(
                        vaultID: fixture.analysisNoteID.vaultID, relativePath: "Observed New.md")
                    let newlyObservedSource = Data("# Observed New\n\nobservednewlibraryneedle is new in an observed Library.\n".utf8)
                    try newlyObservedSource.write(
                        to: fixture.analysesURL.appendingPathComponent(newlyObservedID.relativePath))
                    await handle.setCapturedSearchManifestBarrierForTesting { await barrier.holdOnce() }
                    await handle.openingPresentationDidComplete()
                    try #require(await barrier.waitUntilArrived())

                    let ready = try await handle.snapshot()
                    #expect(ready.phase == .opening)
                    #expect(ready.vaults.map(\.slot) == WorkspaceVaultSlot.allCases)
                    #expect(ready.vaults.flatMap(\.documents).count == 5)
                    #expect(ready.sourceInventoryRevision > first.sourceInventoryRevision)
                    #expect(ready.discovery.catalog.notes.count == 5)
                    #expect(ready.discovery.catalog.graph == nil)
                    #expect(ready.discovery.searchGeneration == nil)
                    #expect(!(await handle.sourceOperationGate.refreshCycleIsActive))
                    for vault in ready.vaults {
                        for note in vault.documents {
                            let loaded = try await handle.documents.load(note.id)
                            #expect(loaded.fingerprint == note.fingerprint)
                            #expect(note.stableIdentity.resolvedID != nil)
                        }
                    }
                    let existing = try #require(ready.document(id: firstSeenID))
                    let observed = try #require(ready.document(id: newlyObservedID))
                    let store = try #require(await handle.services.documentReviewStore)
                    let existingID = try #require(existing.stableIdentity.resolvedID)
                    let observedID = try #require(observed.stableIdentity.resolvedID)
                    let existingBaseline = try #require(try await store.baseline(noteID: existingID, vaultID: topicsVaultID))
                    let observedBaseline = try #require(
                        try await store.baseline(noteID: observedID, vaultID: newlyObservedID.vaultID))
                    #expect(existingBaseline.state == .known)
                    #expect(existingBaseline.fingerprint == DocumentFingerprint(data: firstSeenSource))
                    #expect(observedBaseline.state == .newDocument)
                    #expect(observedBaseline.fingerprint == nil)

                    let limited = try await handle.discovery.search(
                        SearchRequest(
                            query: "agency", presentationScope: .currentVault,
                            executionScope: .currentVault(topicsVaultID), limit: 20))
                    guard case .limited = limited.availability else {
                        throw OpeningExternalEditError.readinessTimeout("Prepared This Vault Search must remain Limited")
                    }
                    #expect(!limited.results.isEmpty)
                    #expect(limited.diagnostics.isEmpty)
                    do {
                        _ = try await handle.discovery.search(
                            SearchRequest(
                                query: "agency", presentationScope: .triptych,
                                executionScope: .triptych, limit: 20))
                        Issue.record("Prepared source libraries were incorrectly promoted to complete Search.")
                    } catch let error as ScholiumApplicationError {
                        guard case .workspaceStillLoading = error else { throw error }
                    }

                    await barrier.release()
                    await handle.awaitOpeningCompletionForTesting()
                    let complete = try await handle.snapshot()
                    #expect(complete.phase.isComplete)
                    #expect(complete.sourceInventoryRevision > ready.sourceInventoryRevision)
                    #expect(complete.discovery.catalog.graph?.sourceManifestHash == complete.discovery.searchGeneration?.sourceManifestHash)
                    #expect(try await store.baseline(noteID: existingID, vaultID: topicsVaultID)?.id == existingBaseline.id)
                    #expect(try await store.baseline(noteID: observedID, vaultID: newlyObservedID.vaultID)?.state == .newDocument)
                    let results = try await handle.discovery.search(
                        SearchRequest(
                            query: "firstseenlibraryneedle", presentationScope: .triptych,
                            executionScope: .triptych, limit: 20))
                    #expect(results.results.count == 1)
                    #expect(
                        try Data(contentsOf: fixture.topicsURL.appendingPathComponent(firstSeenID.relativePath)) == firstSeenSource)
                    #expect(
                        try Data(contentsOf: fixture.analysesURL.appendingPathComponent(newlyObservedID.relativePath)) == newlyObservedSource)
                    await lifecycle.cleanup()
                    let observedPublications = await publications.value
                    #expect(observedPublications.contains { !$0.phase.isComplete && $0.vaults.count == 3 })
                    #expect(
                        zip(observedPublications, observedPublications.dropFirst()).allSatisfy { pair in
                            pair.0.sourceInventoryRevision <= pair.1.sourceInventoryRevision
                        })
                    #expect(await handle.ownedBackgroundTaskCount == 0)
                    #expect(!(await handle.sourceOperationGate.refreshCycleIsActive))
                } catch {
                    await lifecycle.cleanup()
                    throw error
                }
            } onCancel: {
                Task { await lifecycle.cleanup() }
            }
        }

        @Test("Shutdown after final Review initialization cannot publish the captured complete snapshot", .timeLimit(.minutes(2)))
        func shutdownDuringReviewedSnapshotPublication() async throws {
            let fixtureRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent(".build/application-test-fixtures/review-publication-\(UUID().uuidString)", isDirectory: true)
            let fixture = try await ApplicationFixture.make(registerLiveAccess: true, rootURL: fixtureRoot)
            defer { fixture.remove() }
            let roots = [fixture.analysesURL, fixture.topicsURL, fixture.worksURL]
            let sourceURLs = [
                fixture.analysesURL.appendingPathComponent("Agency.md"),
                fixture.topicsURL.appendingPathComponent("Freedom.md"),
                fixture.worksURL.appendingPathComponent("Chapter.md"),
            ]
            let originalSources = try sourceURLs.map { try Data(contentsOf: $0) }
            let originalRootIdentities = try roots.map(rootIdentity)
            let runtime = WorkspaceRuntime(
                configuration: .live(
                    .init(
                        applicationSupportURL: fixture.applicationSupportURL,
                        workspaceRegistryStorageURL: fixture.registryStorageURL)))
            let handle: WorkspaceHandle
            do {
                handle = try await runtime.openWorkspace(id: fixture.assignment.id, openingVault: .paperAnalysis)
            } catch {
                await runtime.shutdown()
                throw error
            }
            let barrier = OpeningExternalEditBarrier()
            let events = await handle.events.events()
            let publications = Task {
                var snapshots: [WorkspaceSnapshot] = []
                for await event in events { snapshots.append(event.snapshot) }
                return snapshots
            }
            let lifecycle = OpeningExternalEditLifecycle(
                runtime: runtime, handle: handle, barrier: barrier, publications: publications)
            try await withTaskCancellationHandler {
                do {
                    await handle.setReviewedSnapshotPublicationBarrierForTesting { await barrier.holdOnce() }
                    await handle.openingPresentationDidComplete()
                    try #require(await barrier.waitUntilArrived())
                    let opening = try await handle.snapshot()
                    #expect(opening.phase == .opening)
                    #expect(opening.vaults.count == 3)
                    #expect(opening.discovery.searchGeneration == nil)
                    #expect(await handle.sourceOperationGate.refreshCycleIsActive)
                    let reviews = try #require(await handle.services.documentReviewStore)
                    for note in opening.vaults.flatMap(\.documents) {
                        let noteID = try #require(note.stableIdentity.resolvedID)
                        #expect(try await reviews.baseline(noteID: noteID, vaultID: note.id.vaultID) != nil)
                    }

                    // Do not release the barrier first: shutdown must cancel
                    // the actual refresh worker while its final result waits.
                    await runtime.shutdown()
                    try await waitUntil("the cancelled final publication releases its source lease") {
                        !(await handle.sourceOperationGate.refreshCycleIsActive)
                    }
                    // Check the owner as well as its stream: a late assignment
                    // is invalid even if stream teardown hides the publication.
                    #expect(await handle.currentSnapshot.phase == .opening)
                    #expect(await publications.value.allSatisfy { !$0.phase.isComplete })
                    #expect(await handle.ownedBackgroundTaskCount == 0)
                    #expect(!(await handle.sourceOperationGate.sourceMutationIsActive))
                    #expect(await handle.sourceOperationGate.waitingCount == 0)
                    #expect(try sourceURLs.map { try Data(contentsOf: $0) } == originalSources)
                    #expect(try roots.map(rootIdentity) == originalRootIdentities)
                    await lifecycle.cleanup()
                } catch {
                    await lifecycle.cleanup()
                    throw error
                }
            } onCancel: {
                Task { await lifecycle.cleanup() }
            }
        }

        private func rootIdentity(_ url: URL) throws -> String {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let device = try #require(attributes[.systemNumber] as? NSNumber)
            let inode = try #require(attributes[.systemFileNumber] as? NSNumber)
            return "\(device):\(inode)"
        }

        private func waitUntil(
            _ description: String,
            predicate: @Sendable () async throws -> Bool
        ) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(10))
            while clock.now < deadline {
                try Task.checkCancellation()
                if try await predicate() { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            throw OpeningExternalEditError.readinessTimeout(description)
        }
    }

    private enum OpeningExternalEditError: Error {
        case readinessTimeout(String)
    }

    private actor OpeningExternalEditBarrier {
        private let arrival = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        private let releaseSignal = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        private var entered = false

        func holdOnce() async {
            guard !entered else { return }
            entered = true
            arrival.continuation.yield(())
            arrival.continuation.finish()
            var iterator = releaseSignal.stream.makeAsyncIterator()
            _ = await iterator.next()
        }

        func waitUntilArrived() async -> Bool {
            let stream = arrival.stream
            return await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    var iterator = stream.makeAsyncIterator()
                    return await iterator.next() != nil
                }
                group.addTask {
                    do { try await Task.sleep(for: .seconds(10)) } catch { return false }
                    return false
                }
                let arrived = await group.next() ?? false
                group.cancelAll()
                return arrived
            }
        }

        func release() {
            releaseSignal.continuation.yield(())
            releaseSignal.continuation.finish()
            arrival.continuation.finish()
        }
    }

    private actor OpeningExternalEditLifecycle {
        private let runtime: WorkspaceRuntime
        private let handle: WorkspaceHandle
        private let barrier: OpeningExternalEditBarrier
        private let publications: Task<[WorkspaceSnapshot], Never>
        private var cleanupTask: Task<Void, Never>?

        init(
            runtime: WorkspaceRuntime, handle: WorkspaceHandle, barrier: OpeningExternalEditBarrier,
            publications: Task<[WorkspaceSnapshot], Never>
        ) {
            self.runtime = runtime
            self.handle = handle
            self.barrier = barrier
            self.publications = publications
        }

        func cleanup() async {
            if let cleanupTask {
                await cleanupTask.value
                return
            }
            let task = Task {
                await barrier.release()
                await handle.setCapturedSearchManifestBarrierForTesting(nil)
                await handle.setReviewedSnapshotPublicationBarrierForTesting(nil)
                await runtime.shutdown()
                let clock = ContinuousClock()
                let deadline = clock.now.advanced(by: .seconds(10))
                while await handle.sourceOperationGate.refreshCycleIsActive {
                    guard clock.now < deadline else {
                        Issue.record("Opening cleanup did not drain the cancelled refresh source lease.")
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(20))
                }
                _ = await publications.value
            }
            cleanupTask = task
            await task.value
        }
    }
#endif
