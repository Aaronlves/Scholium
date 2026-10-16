import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

#if DEBUG
    @Suite("Storage maintenance source publication")
    struct WorkspaceStoragePublicationTests {
        enum Boundary: Sendable, CaseIterable, Equatable { case captured, publication }

        @Test(
            "A deferred Search recaptures new source and retains final authority through Graph publication",
            .timeLimit(.minutes(2)), arguments: Boundary.allCases)
        func deferredSearchPublication(_ boundary: Boundary) async throws {
            let fixture = try await makeFixture()
            defer { fixture.remove() }
            let runtime = WorkspaceRuntime(
                configuration: .snapshot(.init(applicationSupportURL: fixture.applicationSupportURL, assignments: [fixture.assignment])))
            let barrier = StoragePublicationBarrier()
            do {
                let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
                let original = try await handle.documents.load(fixture.analysisNoteID)
                let target = try await capturedSaveTarget(handle, fixture.analysisNoteID, revision: original.fingerprint)
                _ = try await handle.clearSearchIndex()
                #expect(try await handle.services.searchIndex.hasDeferredRebuild)
                switch boundary {
                case .captured:
                    await handle.setCapturedSearchManifestBarrierForTesting { await barrier.holdOnce() }
                case .publication:
                    await handle.setReviewedSnapshotPublicationBarrierForTesting { await barrier.holdOnce() }
                }
                let refresh = Task { try await handle.discovery.refresh() }
                do {
                    try await withTaskCancellationHandler {
                        try #require(await barrier.waitUntilArrived())
                        let completion = StoragePublicationCompletion()
                        let source = "\u{FEFF}# Latest source\r\n\r\nExact e\u{301} 中文 😀 without final newline"
                        let save = Task {
                            let committed = try await handle.documents.commit(target, changeSet: .source(source))
                            await completion.finish()
                            return committed
                        }
                        do {
                            try await waitUntil {
                                let finished = await completion.isComplete
                                let waiting = await handle.sourceOperationGate.waitingCount
                                return finished || waiting > 0
                            }
                            let finished = await completion.isComplete
                            #expect(finished == (boundary == .captured))
                            #expect(await handle.sourceOperationGate.refreshCycleIsActive == (boundary == .publication))
                            await barrier.release()
                            let captured = try await refresh.value
                            let committed = try await save.value
                            #expect(captured.phase.isComplete)
                            #expect(captured.discovery.searchGeneration == nil)
                            #expect(captured.discovery.catalog.graph != nil)
                            #expect(
                                captured.document(id: fixture.analysisNoteID)?.fingerprint
                                    == (boundary == .captured ? committed.document.fingerprint : original.fingerprint))
                            try await waitUntil {
                                let snapshot = try? await handle.snapshot()
                                let pending = await handle.sourceCommitRefreshTask != nil
                                return !pending && snapshot?.document(id: fixture.analysisNoteID)?.fingerprint == committed.document.fingerprint
                            }
                            let complete = try await handle.snapshot()
                            #expect(complete.discovery.searchGeneration == nil)
                            #expect(complete.discovery.catalog.graph != nil)
                            #expect(try Data(contentsOf: fixture.analysesURL.appendingPathComponent(fixture.analysisNoteID.relativePath)) == Data(source.utf8))
                            #expect(!(await handle.sourceOperationGate.refreshCycleIsActive))
                            #expect(await handle.sourceOperationGate.waitingCount == 0)
                        } catch {
                            save.cancel()
                            await barrier.release()
                            _ = await save.result
                            throw error
                        }
                    } onCancel: {
                        refresh.cancel()
                        Task { await barrier.release() }
                    }
                } catch {
                    refresh.cancel()
                    await barrier.release()
                    _ = await refresh.result
                    throw error
                }
                await runtime.shutdown()
            } catch {
                await barrier.release()
                await runtime.shutdown()
                throw error
            }
        }

        enum RebuildBoundary: Sendable, CaseIterable, Equatable { case candidate, cohort }

        @Test(
            "Opening rebuild retries preserve fresh parsing after candidate or installed-cohort supersession",
            .timeLimit(.minutes(2)), arguments: RebuildBoundary.allCases)
        func openingRebuildRemainsFresh(_ boundary: RebuildBoundary) async throws {
            let fixture = try await makeFixture()
            defer { fixture.remove() }
            let companion = fixture.analysesURL.appendingPathComponent("Unchanged.md")
            let companionBytes = Data("# Unchanged companion\n\n[[Agency]]\n".utf8)
            try companionBytes.write(to: companion)
            let pool = WorkspaceVaultPool(applicationSupportURL: fixture.applicationSupportURL, mode: .snapshot)
            let barrier = StoragePublicationBarrier()
            do {
                // Live presentation with snapshot access exercises progressive
                // readiness without independent native Vault watcher events.
                let handle = try await WorkspaceHandle.open(
                    assignment: fixture.assignment, mode: .live,
                    applicationSupportURL: fixture.applicationSupportURL,
                    windowSessionStore: .init(applicationSupportURL: fixture.applicationSupportURL),
                    vaultPool: pool, zotero: ZoteroOperations(applicationSupportURL: fixture.applicationSupportURL),
                    access: .snapshot, openingVault: .paperAnalysis)
                do {
                    #expect(try await handle.snapshot().phase == .opening)
                    let selected = boundary == .candidate ? WorkspaceVaultSlot.paperAnalysis : .output
                    let blockedVaultID = try #require(fixture.assignment.vault(for: selected)?.id)
                    await handle.setPreparedSourceCatalogBarrierForTesting { vaultID in
                        if vaultID == blockedVaultID { await barrier.holdOnce() }
                    }
                    let rebuild = Task { try await handle.rebuildSearchIndex() }
                    do {
                        try await withTaskCancellationHandler {
                            try #require(await barrier.waitUntilArrived())
                            #expect(!(await handle.sourceOperationGate.refreshCycleIsActive))
                            let source = "\u{FEFF}# Rebuilt source\r\n\r\nFresh e\u{301} 中文 😀 without final newline"
                            try Data(source.utf8).write(
                                to: fixture.analysesURL.appendingPathComponent(fixture.analysisNoteID.relativePath), options: .atomic)
                            await barrier.release()
                            let snapshot = try await rebuild.value
                            #expect(snapshot.phase.isComplete)
                            #expect(snapshot.document(id: fixture.analysisNoteID)?.fingerprint == DocumentFingerprint(content: source))
                            #expect(snapshot.discovery.catalog.graph?.sourceManifestHash == snapshot.discovery.searchGeneration?.sourceManifestHash)
                            let catalog = try #require(await handle.services.sourceCatalogs[fixture.analysisNoteID.vaultID])
                            let rebuilt = try await catalog.snapshot()
                            #expect(rebuilt.measurement.parsedDocuments == 2)
                            #expect(rebuilt.measurement.readFiles == 2)
                            #expect(rebuilt.measurement.restoredCatalogProjections == 0)
                            #expect(try Data(contentsOf: companion) == companionBytes)
                            #expect(!(await handle.sourceOperationGate.refreshCycleIsActive))
                            #expect(await handle.sourceOperationGate.waitingCount == 0)
                        } onCancel: {
                            rebuild.cancel()
                            Task { await barrier.release() }
                        }
                    } catch {
                        rebuild.cancel()
                        await barrier.release()
                        _ = await rebuild.result
                        throw error
                    }
                    await handle.shutdown()
                } catch {
                    await barrier.release()
                    await handle.shutdown()
                    throw error
                }
                await pool.shutdown()
            } catch {
                await barrier.release()
                await pool.shutdown()
                throw error
            }
        }

        private func makeFixture() async throws -> ApplicationFixture {
            let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            return try await ApplicationFixture.make(rootURL: repository.appendingPathComponent(".build/storage-publication-tests/\(UUID().uuidString)"))
        }

        private func waitUntil(_ predicate: @Sendable () async -> Bool) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(30))
            while clock.now < deadline {
                try Task.checkCancellation()
                if await predicate() { return }
                await Task.yield()
            }
            throw StoragePublicationTestError.readinessTimeout
        }
    }

    private enum StoragePublicationTestError: Error { case readinessTimeout }

    private actor StoragePublicationCompletion {
        private(set) var isComplete = false
        func finish() { isComplete = true }
    }

    private actor StoragePublicationBarrier {
        private let arrival = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        private let signal = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        private var didArrive = false

        func holdOnce() async {
            guard !didArrive else { return }
            didArrive = true
            arrival.continuation.yield(())
            arrival.continuation.finish()
            var iterator = signal.stream.makeAsyncIterator()
            _ = await iterator.next()
        }

        func waitUntilArrived() async -> Bool {
            var iterator = arrival.stream.makeAsyncIterator()
            return await iterator.next() != nil
        }

        func release() {
            signal.continuation.yield(())
            signal.continuation.finish()
            arrival.continuation.finish()
        }
    }
#endif
