import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

#if DEBUG
    @Suite("Source commits during derived preparation")
    struct WorkspaceSourceDerivedLifetimeTests {
        @Test(
            "An immediate Undo save commits while an older derived generation is preparing",
            .timeLimit(.minutes(2)))
        func sourceCommitOvertakesDerivedPreparation() async throws {
            let fixture = try await makeFixture()
            defer { fixture.remove() }
            let sourceURL = fixture.analysesURL.appendingPathComponent(
                fixture.analysisNoteID.relativePath)
            let original = "\u{FEFF}# Original\r\n\r\nExact source e\u{301} 😀 中文 without final newline"
            let replacement = original.replacingOccurrences(of: "Original", with: "Replacement")
            try Data(original.utf8).write(to: sourceURL)
            let runtime = WorkspaceRuntime(
                configuration: .snapshot(
                    .init(
                        applicationSupportURL: fixture.applicationSupportURL, assignments: [fixture.assignment])
                ))
            let handle: WorkspaceHandle
            do {
                handle = try await runtime.openWorkspace(id: fixture.assignment.id)
            } catch {
                await runtime.shutdown()
                throw error
            }
            let barrier = SourceDerivedPreparationBarrier()
            let lifecycle = SourceDerivedTestLifecycle(runtime: runtime, handle: handle, barrier: barrier)
            let stream = await handle.events.events()
            let publications = Task {
                var snapshots: [WorkspaceSnapshot] = []
                for await event in stream where event.snapshot.phase.isComplete {
                    snapshots.append(event.snapshot)
                }
                return snapshots
            }
            try await withTaskCancellationHandler {
                do {
                    let initial = try await handle.snapshot()
                    let initialIndex = try await handle.services.searchIndex.generation()
                    let target = try await capturedSaveTarget(
                        handle, fixture.analysisNoteID, revision: DocumentFingerprint(content: original))
                    await handle.setCapturedSearchManifestBarrierForTesting { await barrier.holdOnce() }
                    let first = try await handle.documents.commit(target, changeSet: .source(replacement))
                    try #require(await barrier.waitUntilArrived())
                    let refresh = try #require(await handle.sourceCommitRefreshTask)
                    let result = SourceDerivedSaveResult()
                    let undo = Task {
                        do {
                            let saved = try await handle.documents.commit(
                                NoteMutationTarget(
                                    documentID: target.documentID, stableNoteID: target.stableNoteID,
                                    revision: first.document.fingerprint),
                                changeSet: .source(original))
                            await result.completed()
                            return saved
                        } catch {
                            await result.completed()
                            throw error
                        }
                    }
                    await lifecycle.track(undo)
                    try await waitUntil("the second save either commits or reaches the source gate") {
                        let complete = await result.isComplete
                        let waiting = await handle.sourceOperationGate.waitingCount
                        return complete || waiting > 0
                    }
                    // No timing threshold: a held immutable generation must
                    // not retain write authority or block this real save.
                    let committedWhilePreparing = await result.isComplete
                    #expect(committedWhilePreparing)
                    #expect(!(await handle.sourceOperationGate.refreshCycleIsActive))
                    if committedWhilePreparing {
                        #expect(try Data(contentsOf: sourceURL) == Data(original.utf8))
                        #expect(try await handle.services.searchIndex.generation() == initialIndex)
                        #expect(
                            try await handle.snapshot().discovery.searchGeneration
                                == initial.discovery.searchGeneration)
                    }
                    await barrier.release()
                    let saved = try await undo.value
                    #expect(saved.document.sourceBytes == Data(original.utf8))
                    await refresh.value
                    try await waitUntil(
                        "the owned source-commit queue finishes its latest complete generation"
                    ) {
                        let pending = await handle.sourceCommitRefreshTask != nil
                        let refreshing = await handle.sourceOperationGate.refreshCycleIsActive
                        return !pending && !refreshing
                    }
                    let complete = try await handle.snapshot()
                    #expect(complete.phase.isComplete)
                    #expect(
                        complete.document(id: target.documentID)?.fingerprint == saved.document.fingerprint)
                    #expect(
                        complete.document(id: target.documentID)?.stableIdentity.resolvedID
                            == target.stableNoteID)
                    #expect(
                        complete.discovery.catalog.graph?.sourceManifestHash
                            == complete.discovery.searchGeneration?.sourceManifestHash)
                    #expect(try Data(contentsOf: sourceURL) == Data(original.utf8))
                    await lifecycle.cleanup()
                    let snapshots = await publications.value
                    #expect(!snapshots.isEmpty)
                    if committedWhilePreparing {
                        for snapshot in snapshots {
                            #expect(
                                snapshot.document(id: target.documentID)?.fingerprint == saved.document.fingerprint)
                        }
                    }
                    try await waitUntil("shutdown drains the last refresh publication lease") {
                        !(await handle.sourceOperationGate.refreshCycleIsActive)
                    }
                    #expect(await handle.sourceOperationGate.waitingCount == 0)
                    #expect(!(await handle.sourceOperationGate.sourceMutationIsActive))
                    #expect(!(await handle.sourceOperationGate.refreshCycleIsActive))
                } catch {
                    await lifecycle.cleanup()
                    _ = await publications.value
                    throw error
                }
            } onCancel: {
                Task { await lifecycle.cleanup() }
            }
        }

        @Test(
            "Final source authority spans the committed index and matching Application publication",
            .timeLimit(.minutes(2)))
        func finalPublicationRetainsSourceAuthority() async throws {
            let fixture = try await makeFixture()
            defer { fixture.remove() }
            let runtime = WorkspaceRuntime(
                configuration: .snapshot(
                    .init(
                        applicationSupportURL: fixture.applicationSupportURL, assignments: [fixture.assignment])
                ))
            let handle: WorkspaceHandle
            do {
                handle = try await runtime.openWorkspace(id: fixture.assignment.id)
            } catch {
                await runtime.shutdown()
                throw error
            }
            let barrier = SourceDerivedPreparationBarrier()
            let lifecycle = SourceDerivedTestLifecycle(runtime: runtime, handle: handle, barrier: barrier)
            try await withTaskCancellationHandler {
                do {
                    let original = try await handle.documents.load(fixture.analysisNoteID)
                    let initialIndex = try await handle.services.searchIndex.generation()
                    let target = try await capturedSaveTarget(
                        handle, fixture.analysisNoteID, revision: original.fingerprint)
                    let sourceURL = fixture.analysesURL.appendingPathComponent(target.relativePath)
                    let replacement = original.rawContent + "\nA durable replacement before Undo.\n"
                    await handle.setReviewedSnapshotPublicationBarrierForTesting { await barrier.holdOnce() }
                    let first = try await handle.documents.commit(target, changeSet: .source(replacement))
                    try #require(await barrier.waitUntilArrived())
                    #expect(try await handle.services.searchIndex.generation() != initialIndex)
                    #expect(
                        try await handle.snapshot().document(id: target.documentID)?.fingerprint
                            == original.fingerprint)
                    #expect(await handle.sourceOperationGate.refreshCycleIsActive)
                    let result = SourceDerivedSaveResult()
                    let undo = Task {
                        let saved = try await handle.documents.commit(
                            NoteMutationTarget(
                                documentID: target.documentID, stableNoteID: target.stableNoteID,
                                revision: first.document.fingerprint),
                            changeSet: .source(original.rawContent))
                        await result.completed()
                        return saved
                    }
                    await lifecycle.track(undo)
                    try await waitUntil("the new save is queued behind final publication authority") {
                        await handle.sourceOperationGate.waitingCount == 1
                    }
                    #expect(!(await result.isComplete))
                    #expect(try Data(contentsOf: sourceURL) == first.document.sourceBytes)
                    await barrier.release()
                    let saved = try await undo.value
                    #expect(saved.document.sourceBytes == original.sourceBytes)
                    try await waitUntil("the new source revision publishes coherently after final admission") {
                        let pending = await handle.sourceCommitRefreshTask != nil
                        let snapshot = try? await handle.snapshot()
                        return !pending
                            && snapshot?.document(id: target.documentID)?.fingerprint
                                == saved.document.fingerprint
                    }
                    let complete = try await handle.snapshot()
                    #expect(
                        complete.discovery.catalog.graph?.sourceManifestHash
                            == complete.discovery.searchGeneration?.sourceManifestHash)
                    #expect(try Data(contentsOf: sourceURL) == original.sourceBytes)
                    await lifecycle.cleanup()
                    try await waitUntil("final publication cleanup releases its exact lease") {
                        !(await handle.sourceOperationGate.refreshCycleIsActive)
                    }
                    #expect(await handle.sourceOperationGate.waitingCount == 0)
                } catch {
                    await lifecycle.cleanup()
                    throw error
                }
            } onCancel: {
                Task { await lifecycle.cleanup() }
            }
        }

        @Test(
            "A coherent save transparently recaptures source superseded before row hydration",
            .timeLimit(.minutes(2)))
        func coherentSaveRecapturesSupersededHydration() async throws {
            let fixture = try await makeFixture()
            defer { fixture.remove() }
            let runtime = WorkspaceRuntime(
                configuration: .snapshot(
                    .init(
                        applicationSupportURL: fixture.applicationSupportURL, assignments: [fixture.assignment])
                ))
            let handle: WorkspaceHandle
            do {
                handle = try await runtime.openWorkspace(id: fixture.assignment.id)
            } catch {
                await runtime.shutdown()
                throw error
            }
            let barrier = SourceDerivedPreparationBarrier()
            let lifecycle = SourceDerivedTestLifecycle(runtime: runtime, handle: handle, barrier: barrier)
            try await withTaskCancellationHandler {
                do {
                    let original = try await handle.documents.load(fixture.analysisNoteID)
                    let target = try await capturedSaveTarget(
                        handle, fixture.analysisNoteID, revision: original.fingerprint)
                    let replacement = original.rawContent + "\nThe first coherent save's captured row.\n"
                    await handle.setCapturedSearchManifestBarrierForTesting { await barrier.holdOnce() }
                    let coherent = Task {
                        try await handle.documents.save(target, changeSet: .source(replacement))
                    }
                    await lifecycle.track(coherent)
                    try #require(await barrier.waitUntilArrived())
                    let restored = try await handle.documents.commit(
                        NoteMutationTarget(
                            documentID: target.documentID, stableNoteID: target.stableNoteID,
                            revision: DocumentFingerprint(content: replacement)),
                        changeSet: .source(original.rawContent))
                    #expect(restored.document.sourceBytes == original.sourceBytes)
                    await barrier.release()
                    let outcome = try await coherent.value
                    #expect(outcome.committedValue.document.sourceBytes == Data(replacement.utf8))
                    #expect(outcome.derivedRefreshWarning == nil)
                    #expect(outcome.identityRecoveryWarning == nil)
                    let complete = try await handle.snapshot()
                    #expect(complete.phase.isComplete)
                    #expect(
                        complete.document(id: target.documentID)?.fingerprint == restored.document.fingerprint)
                    #expect(
                        complete.discovery.catalog.graph?.sourceManifestHash
                            == complete.discovery.searchGeneration?.sourceManifestHash)
                    let sourceURL = fixture.analysesURL.appendingPathComponent(target.relativePath)
                    #expect(try Data(contentsOf: sourceURL) == original.sourceBytes)
                    await lifecycle.cleanup()
                    try await waitUntil("the recaptured coherent cycle releases its final lease") {
                        !(await handle.sourceOperationGate.refreshCycleIsActive)
                    }
                } catch {
                    await lifecycle.cleanup()
                    throw error
                }
            } onCancel: {
                Task { await lifecycle.cleanup() }
            }
        }

        @Test(
            "An identity-only resolution invalidates an older captured complete generation",
            .timeLimit(.minutes(2)))
        func identityResolutionSupersedesCapturedIdentity() async throws {
            let fixture = try await makeFixture()
            defer { fixture.remove() }
            let originalURL = fixture.analysesURL.appendingPathComponent(
                fixture.analysisNoteID.relativePath)
            let source = try Data(contentsOf: originalURL)
            let twinURL = fixture.analysesURL.appendingPathComponent("Identity twin.md")
            try source.write(to: twinURL)
            let runtime = WorkspaceRuntime(
                configuration: .snapshot(
                    .init(
                        applicationSupportURL: fixture.applicationSupportURL, assignments: [fixture.assignment])
                ))
            let handle: WorkspaceHandle
            do {
                handle = try await runtime.openWorkspace(id: fixture.assignment.id)
            } catch {
                await runtime.shutdown()
                throw error
            }
            let barrier = SourceDerivedPreparationBarrier()
            let lifecycle = SourceDerivedTestLifecycle(runtime: runtime, handle: handle, barrier: barrier)
            try await withTaskCancellationHandler {
                do {
                    let movedURL = fixture.analysesURL.appendingPathComponent("Identity moved.md")
                    let movedTwinURL = fixture.analysesURL.appendingPathComponent("Identity moved twin.md")
                    try FileManager.default.moveItem(at: originalURL, to: movedURL)
                    try FileManager.default.moveItem(at: twinURL, to: movedTwinURL)
                    let ambiguous = try await handle.discovery.refresh()
                    let vault = try #require(ambiguous.vault(id: fixture.analysisNoteID.vaultID))
                    let ambiguity = try #require(vault.identityRecovery.ambiguities.first)
                    #expect(ambiguity.candidates.count == 2)
                    let documentID = VaultQualifiedNoteID(
                        vaultID: ambiguity.vaultID, relativePath: ambiguity.relativePath)
                    #expect(ambiguous.document(id: documentID)?.stableIdentity.resolvedID == nil)
                    await handle.setCapturedSearchManifestBarrierForTesting { await barrier.holdOnce() }
                    let refresh = Task { try await handle.discovery.refresh() }
                    await lifecycle.track(refresh)
                    try #require(await barrier.waitUntilArrived())
                    let resolution = Task {
                        try await handle.documents.resolveIdentity(ambiguity, candidateID: nil)
                    }
                    await lifecycle.track(resolution)
                    try await waitUntil(
                        "the identity choice commits before the old derived capture is released"
                    ) {
                        (try? await handle.services.controlStore.identityRecord(
                            vaultID: ambiguity.vaultID, relativePath: ambiguity.relativePath)) != nil
                    }
                    #expect(try Data(contentsOf: movedURL) == source)
                    #expect(try Data(contentsOf: movedTwinURL) == source)
                    await barrier.release()
                    let capturedResult = try await refresh.value
                    let resolved = try await resolution.value
                    #expect(resolved.derivedRefreshWarning == nil)
                    #expect(
                        capturedResult.document(id: documentID)?.stableIdentity.resolvedID
                            == resolved.committedValue.id)
                    #expect(
                        capturedResult.discovery.catalog.graph?.sourceManifestHash
                            == capturedResult.discovery.searchGeneration?.sourceManifestHash)
                    let complete = try await handle.snapshot()
                    #expect(
                        complete.document(id: documentID)?.stableIdentity.resolvedID
                            == resolved.committedValue.id)
                    #expect(try Data(contentsOf: movedURL) == source)
                    #expect(try Data(contentsOf: movedTwinURL) == source)
                    await lifecycle.cleanup()
                    try await waitUntil("identity resolution releases its capture and publication authority") {
                        !(await handle.sourceOperationGate.refreshCycleIsActive)
                    }
                } catch {
                    await lifecycle.cleanup()
                    throw error
                }
            } onCancel: {
                Task { await lifecycle.cleanup() }
            }
        }

        @Test(
            "A selected Library save overtakes catalog preparation and reaches the fresh final cohort",
            arguments: [WorkspaceVaultSlot.paperAnalysis, .topicKnowledge])
        func sourceSaveOvertakesCatalogPreparation(blockedSlot: WorkspaceVaultSlot) async throws {
            let fixture = try await makeFixture()
            defer { fixture.remove() }
            let runtime = WorkspaceRuntime(
                configuration: .snapshot(
                    .init(applicationSupportURL: fixture.applicationSupportURL, assignments: [fixture.assignment])))
            let handle: WorkspaceHandle
            do {
                handle = try await runtime.openWorkspace(id: fixture.assignment.id)
            } catch {
                await runtime.shutdown()
                throw error
            }
            let barrier = SourceDerivedPreparationBarrier()
            let lifecycle = SourceDerivedTestLifecycle(runtime: runtime, handle: handle, barrier: barrier)
            try await withTaskCancellationHandler {
                do {
                    let original = try await handle.documents.load(fixture.analysisNoteID)
                    let target = try await capturedSaveTarget(handle, fixture.analysisNoteID, revision: original.fingerprint)
                    let blockedVaultID = try #require(fixture.assignment.vault(for: blockedSlot)?.id)
                    await handle.setPreparedSourceCatalogBarrierForTesting { vaultID in
                        if vaultID == blockedVaultID { await barrier.holdOnce() }
                    }
                    let refresh = Task { try await handle.discovery.refresh() }
                    await lifecycle.track(refresh)
                    try #require(await barrier.waitUntilArrived())
                    let result = SourceDerivedSaveResult()
                    let source = "\u{FEFF}# Latest catalog source\r\n\r\nExact e\u{301} 😀 中文 without final newline"
                    let save = Task {
                        let committed = try await handle.documents.commit(target, changeSet: .source(source))
                        await result.completed()
                        return committed
                    }
                    await lifecycle.track(save)
                    try await waitUntil("the selected Library save finishes or reaches the source gate") {
                        let finished = await result.isComplete
                        let waiting = await handle.sourceOperationGate.waitingCount
                        return finished || waiting > 0
                    }
                    #expect(await result.isComplete)
                    #expect(!(await handle.sourceOperationGate.refreshCycleIsActive))
                    if await result.isComplete {
                        #expect(try Data(contentsOf: fixture.analysesURL.appendingPathComponent(fixture.analysisNoteID.relativePath)) == Data(source.utf8))
                    }
                    // Snapshot mode has no watcher. The accepted cohort must
                    // detect this source change itself, including when an
                    // earlier Library was already installed before the hold.
                    await barrier.release()
                    let committed = try await save.value
                    let complete = try await refresh.value
                    #expect(complete.phase.isComplete)
                    #expect(complete.document(id: fixture.analysisNoteID)?.fingerprint == committed.document.fingerprint)
                    #expect(try await handle.documents.load(fixture.analysisNoteID).sourceBytes == Data(source.utf8))
                    await lifecycle.cleanup()
                } catch {
                    await lifecycle.cleanup()
                    throw error
                }
            } onCancel: {
                Task { await lifecycle.cleanup() }
            }
        }

        private func makeFixture() async throws -> ApplicationFixture {
            let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            return try await ApplicationFixture.make(
                rootURL: repository.appendingPathComponent(
                    ".build/source-derived-lifetime-tests/\(UUID().uuidString)"))
        }

        private func waitUntil(_ description: String, predicate: @Sendable () async -> Bool)
            async throws
        {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(30))
            while clock.now < deadline {
                try Task.checkCancellation()
                if await predicate() { return }
                await Task.yield()
            }
            throw SourceDerivedTestError.readinessTimeout(description)
        }
    }

    private enum SourceDerivedTestError: Error { case readinessTimeout(String) }

    private actor SourceDerivedSaveResult {
        private(set) var isComplete = false
        func completed() { isComplete = true }
    }

    private actor SourceDerivedPreparationBarrier {
        private let arrival = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        private let releaseSignal = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        private var didArrive = false

        func holdOnce() async {
            guard !didArrive else { return }
            didArrive = true
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

    private actor SourceDerivedTestLifecycle {
        private let runtime: WorkspaceRuntime
        private let handle: WorkspaceHandle
        private let barrier: SourceDerivedPreparationBarrier
        private var cancellations: [@Sendable () -> Void] = []
        private var drains: [@Sendable () async -> Void] = []
        private var cleanupTask: Task<Void, Never>?

        init(
            runtime: WorkspaceRuntime, handle: WorkspaceHandle, barrier: SourceDerivedPreparationBarrier
        ) {
            self.runtime = runtime
            self.handle = handle
            self.barrier = barrier
        }

        func track<Success: Sendable, Failure: Error>(_ task: Task<Success, Failure>) async {
            if cleanupTask != nil {
                task.cancel()
                _ = await task.result
                return
            }
            cancellations.append { task.cancel() }
            drains.append { _ = await task.result }
        }

        func cleanup() async {
            if let cleanupTask {
                await cleanupTask.value
                return
            }
            for cancel in cancellations { cancel() }
            let drains = drains
            let task = Task {
                await barrier.release()
                await handle.setPreparedSourceCatalogBarrierForTesting(nil)
                await handle.setCapturedSearchManifestBarrierForTesting(nil)
                await handle.setReviewedSnapshotPublicationBarrierForTesting(nil)
                await runtime.shutdown()
                for drain in drains { await drain() }
            }
            cleanupTask = task
            await task.value
        }
    }
#endif
