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
                    #expect(opening.phase == .opening(availableVault: .paperAnalysis))
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
                    #expect(try await handle.snapshot().phase == .opening(availableVault: .paperAnalysis))
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
            var iterator = arrival.stream.makeAsyncIterator()
            return await iterator.next() != nil
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
                await runtime.shutdown()
                _ = await publications.value
            }
            cleanupTask = task
            await task.value
        }
    }
#endif
