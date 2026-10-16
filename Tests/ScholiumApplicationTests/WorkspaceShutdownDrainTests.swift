import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

#if DEBUG
    @Suite("Shared shutdown completion")
    struct WorkspaceShutdownDrainTests {
        @Test("Cancelling Library activation preserves the shared source opening and its cleared index", .timeLimit(.minutes(1)))
        func cancelledActivationDoesNotResumeClearedIndex() async throws {
            let fixture = try await makeFixture()
            defer { fixture.remove() }
            let runtime = WorkspaceRuntime(
                configuration: .snapshot(.init(applicationSupportURL: fixture.support, assignments: [fixture.assignment])))
            let barrier = ShutdownDrainBarrier()
            var activation: Task<WorkspaceHandle, any Error>?
            var borrowing: Task<WorkspaceHandle, any Error>?
            try await withTaskCancellationHandler {
                do {
                    _ = try await runtime.performStorageAction(.clearIndex, triptychID: fixture.assignment.id)
                    #expect(await runtime.openingFactoryCountForTesting == 0)
                    await runtime.setOpeningLookupBarrierForTesting { _ in await barrier.hold() }
                    let opening = Task { try await runtime.openWorkspace(id: fixture.assignment.id) }
                    activation = opening
                    try await waitUntil { await barrier.didArrive }
                    let neutral = Task { try await runtime.workspace(id: fixture.assignment.id) }
                    borrowing = neutral
                    try await waitUntil { await runtime.openingJoinCountForTesting == 1 }
                    opening.cancel()
                    await barrier.release()
                    await #expect(throws: CancellationError.self) { _ = try await opening.value }
                    let handle = try await neutral.value
                    #expect(!(await barrier.wasCancelled))
                    #expect(try await handle.snapshot().discovery.searchGeneration == nil)
                    #expect(try await handle.services.searchIndex.hasDeferredRebuild)
                    #expect(await handle.indexRebuildTask == nil)
                    #expect(await runtime.openingFactoryCountForTesting == 1)
                    let activated = try await runtime.openWorkspace(id: fixture.assignment.id)
                    #expect(activated === handle)
                    #expect(try await activated.snapshot().discovery.searchGeneration != nil)
                    #expect(try await !activated.services.searchIndex.hasDeferredRebuild)
                    #expect(await runtime.openingFactoryCountForTesting == 1)
                    #expect(try Data(contentsOf: fixture.sourceURL) == fixture.sourceBytes)
                    await runtime.shutdown()
                } catch {
                    activation?.cancel()
                    await barrier.release()
                    _ = await activation?.result
                    _ = await borrowing?.result
                    await runtime.shutdown()
                    throw error
                }
            } onCancel: {
                Task { await barrier.release() }
            }
        }

        @Test("Runtime cancels an opening before joining Clear's shared opening wait", .timeLimit(.minutes(1)))
        func clearWaitingForOpeningDoesNotBlockShutdown() async throws {
            let fixture = try await makeFixture()
            defer { fixture.remove() }
            let runtime = WorkspaceRuntime(
                configuration: .snapshot(.init(applicationSupportURL: fixture.support, assignments: [fixture.assignment])))
            let barrier = ShutdownDrainBarrier()
            let completions = ShutdownCompletions()
            var opening: Task<WorkspaceHandle, any Error>?
            var clear: Task<ScholiumStorageOperationResult, any Error>?
            var drains: [Task<Void, Never>] = []
            try await withTaskCancellationHandler {
                do {
                    await runtime.setOpeningLookupBarrierForTesting { _ in await barrier.hold() }
                    let opener = Task { try await runtime.openWorkspace(id: fixture.assignment.id) }
                    opening = opener
                    try await waitUntil { await barrier.didArrive }
                    let clearing = Task { try await runtime.performStorageAction(.clearIndex, triptychID: fixture.assignment.id) }
                    clear = clearing
                    try await waitUntil { await runtime.storageOpeningJoinCountForTesting == 1 }
                    drains.append(
                        Task {
                            await runtime.shutdown()
                            await completions.finished("first")
                        })
                    try await waitUntil { await barrier.wasCancelled }
                    drains.append(
                        Task {
                            await runtime.shutdown()
                            await completions.finished("second")
                        })
                    try await waitUntil { await runtime.shutdownJoinCountForTesting == 1 }
                    #expect(await completions.names.isEmpty)
                    #expect(await runtime.openingFactoryCountForTesting == 0)
                    await barrier.release()
                    await #expect(throws: CancellationError.self) { _ = try await opener.value }
                    await #expect(throws: CancellationError.self) { _ = try await clearing.value }
                    for drain in drains { await drain.value }
                    #expect(await completions.names == ["first", "second"])
                    #expect(await runtime.pooledVaultRuntimeCount == 0)
                    #expect(try Data(contentsOf: fixture.sourceURL) == fixture.sourceBytes)
                } catch {
                    await barrier.release()
                    await runtime.shutdown()
                    _ = await opening?.result
                    _ = await clear?.result
                    for drain in drains { await drain.value }
                    throw error
                }
            } onCancel: {
                Task { await barrier.release() }
            }
        }

        @Test("Runtime starts Handle shutdown before joining Rebuild's independent owner", .timeLimit(.minutes(1)))
        func rebuildWaitingForHandleDoesNotBlockShutdown() async throws {
            let fixture = try await makeFixture()
            defer { fixture.remove() }
            let runtime = WorkspaceRuntime(
                configuration: .snapshot(.init(applicationSupportURL: fixture.support, assignments: [fixture.assignment])))
            let barrier = ShutdownDrainBarrier()
            let completions = ShutdownCompletions()
            var rebuild: Task<ScholiumStorageOperationResult, any Error>?
            var drains: [Task<Void, Never>] = []
            try await withTaskCancellationHandler {
                do {
                    let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
                    await handle.setCapturedSearchManifestBarrierForTesting { await barrier.hold() }
                    let rebuilding = Task { try await runtime.performStorageAction(.rebuildIndex, triptychID: fixture.assignment.id) }
                    rebuild = rebuilding
                    try await waitUntil { await barrier.didArrive }
                    drains.append(
                        Task {
                            await runtime.shutdown()
                            await completions.finished("first")
                        })
                    try await waitUntil { await barrier.wasCancelled }
                    #expect(await handle.isShutDown)
                    drains.append(
                        Task {
                            await runtime.shutdown()
                            await completions.finished("second")
                        })
                    try await waitUntil { await runtime.shutdownJoinCountForTesting == 1 }
                    #expect(await completions.names.isEmpty)
                    await barrier.release()
                    await #expect(throws: CancellationError.self) { _ = try await rebuilding.value }
                    for drain in drains { await drain.value }
                    #expect(await completions.names == ["first", "second"])
                    #expect(await runtime.pooledVaultRuntimeCount == 0)
                    #expect(try Data(contentsOf: fixture.sourceURL) == fixture.sourceBytes)
                } catch {
                    await barrier.release()
                    await runtime.shutdown()
                    _ = await rebuild?.result
                    for drain in drains { await drain.value }
                    throw error
                }
            } onCancel: {
                Task { await barrier.release() }
            }
        }

        @Test("Runtime and Handle shutdown callers join the same source refresh drain", .timeLimit(.minutes(1)))
        func runtimeAndHandleJoinDrain() async throws {
            let fixture = try await makeFixture()
            defer { fixture.remove() }
            let runtime = WorkspaceRuntime(
                configuration: .snapshot(.init(applicationSupportURL: fixture.support, assignments: [fixture.assignment])))
            let maintenance = fixture.maintenanceRuntime()
            let barrier = ShutdownDrainBarrier()
            let completions = ShutdownCompletions()
            var drains: [Task<Void, Never>] = []
            try await withTaskCancellationHandler {
                do {
                    let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
                    let snapshot = try await handle.snapshot()
                    let source = try #require(snapshot.vaults.flatMap(\.documents).first { $0.id.relativePath == "Note.md" })
                    let stableID = try #require(source.stableIdentity.resolvedID)
                    await handle.setCommittedMutationRefreshBarrierForTesting { await barrier.hold() }
                    let replacement = "\u{FEFF}# Replacement\r\n\r\nExact e\u{301} 中文 😀 without final newline"
                    _ = try await handle.documents.commit(
                        .init(documentID: source.id, stableNoteID: stableID, revision: source.fingerprint),
                        changeSet: .source(replacement))
                    try await waitUntil { await barrier.didArrive }
                    let retired = fixture.support.appendingPathComponent(
                        "Triptychs/\(fixture.assignment.id.uuidString.lowercased())/indexes/search-v9.sqlite")
                    let retiredBytes = Data("retired generated index".utf8)
                    try retiredBytes.write(to: retired)
                    let first = Task {
                        await runtime.shutdown()
                        await completions.finished("runtime-first")
                    }
                    drains.append(first)
                    try await waitUntil { await handle.isShutDown }
                    drains.append(
                        Task {
                            await runtime.shutdown()
                            await completions.finished("runtime-second")
                        })
                    drains.append(
                        Task {
                            await handle.shutdown()
                            await completions.finished("handle-second")
                        })
                    try await waitUntil {
                        let runtimeJoins = await runtime.shutdownJoinCountForTesting
                        let handleJoins = await handle.shutdownJoinCountForTesting
                        return runtimeJoins == 1 && handleJoins == 1
                    }
                    #expect(await completions.names.isEmpty)
                    _ = try await maintenance.performStorageAction(.cleanRetiredDerivedState)
                    #expect(await maintenance.latestDerivedStateMaintenanceSummary?.busyDirectories ?? 0 > 0)
                    #expect(try Data(contentsOf: retired) == retiredBytes)
                    await barrier.release()
                    for drain in drains { await drain.value }
                    #expect(await completions.names == ["runtime-first", "runtime-second", "handle-second"])
                    await maintenance.shutdown()
                    #expect(!FileManager.default.fileExists(atPath: retired.path))
                    #expect(try Data(contentsOf: fixture.sourceURL) == Data(replacement.utf8))
                } catch {
                    await barrier.release()
                    for drain in drains { await drain.value }
                    await runtime.shutdown()
                    await maintenance.shutdown()
                    throw error
                }
            } onCancel: {
                Task { await barrier.release() }
            }
        }

        @Test("Pool and pooled Library shutdown callers wait until the cache lease releases", .timeLimit(.minutes(1)))
        func poolAndLibraryJoinDrain() async throws {
            let fixture = try await makeFixture()
            defer { fixture.remove() }
            let pool = WorkspaceVaultPool(applicationSupportURL: fixture.support, mode: .snapshot)
            let maintenance = fixture.maintenanceRuntime()
            let barrier = ShutdownDrainBarrier()
            let completions = ShutdownCompletions()
            var drains: [Task<Void, Never>] = []
            try await withTaskCancellationHandler {
                do {
                    let vault = try #require(fixture.assignment.vault(for: .paperAnalysis))
                    let pooled = try await pool.vault(for: vault)
                    await pooled.setShutdownBarrierForTesting { await barrier.hold() }
                    let directory = fixture.support.appendingPathComponent("Vaults/\(vault.id.uuidString)/source-projections-v1")
                    let records = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    let record = try #require(records.first { $0.lastPathComponent.hasSuffix(".projection.plist") })
                    let retired = directory.appendingPathComponent(String(repeating: "0", count: 64) + ".projection.json")
                    let retiredBytes = try Data(contentsOf: record)
                    try retiredBytes.write(to: retired)
                    drains.append(
                        Task {
                            await pool.shutdown()
                            await completions.finished("pool-first")
                        })
                    try await waitUntil { await barrier.didArrive }
                    drains.append(
                        Task {
                            await pool.shutdown()
                            await completions.finished("pool-second")
                        })
                    drains.append(
                        Task {
                            await pooled.shutdown()
                            await completions.finished("library-second")
                        })
                    try await waitUntil {
                        let poolJoins = await pool.shutdownJoinCountForTesting
                        let libraryJoins = await pooled.shutdownJoinCountForTesting
                        return poolJoins == 1 && libraryJoins == 1
                    }
                    #expect(await completions.names.isEmpty)
                    _ = try await maintenance.performStorageAction(.cleanRetiredDerivedState)
                    #expect(await maintenance.latestDerivedStateMaintenanceSummary?.busyDirectories ?? 0 > 0)
                    #expect(try Data(contentsOf: retired) == retiredBytes)
                    await barrier.release()
                    for drain in drains { await drain.value }
                    #expect(await completions.names == ["pool-first", "pool-second", "library-second"])
                    await maintenance.shutdown()
                    #expect(!FileManager.default.fileExists(atPath: retired.path))
                    #expect(try Data(contentsOf: fixture.sourceURL) == fixture.sourceBytes)
                } catch {
                    await barrier.release()
                    for drain in drains { await drain.value }
                    await pool.shutdown()
                    await maintenance.shutdown()
                    throw error
                }
            } onCancel: {
                Task { await barrier.release() }
            }
        }

        @Test(
            "One registered opening owns lookup, same-ID joins and shutdown admission",
            .timeLimit(.minutes(1)), arguments: [false, true])
        func lookupAndFactoryShareOpeningOwnership(shutdownDuringLookup: Bool) async throws {
            let fixture = try await makeFixture(withSecondWorkspace: true)
            defer { fixture.remove() }
            let second = try #require(fixture.secondAssignment)
            let generated =
                [fixture.support.appendingPathComponent("Triptychs/\(second.id.uuidString.lowercased())/indexes")]
                + second.vaults.values.map {
                    fixture.support.appendingPathComponent("Vaults/\($0.id.uuidString)/source-projections-v1")
                }
            for path in generated where FileManager.default.fileExists(atPath: path.path) {
                try FileManager.default.removeItem(at: path)
            }
            let runtime = WorkspaceRuntime(
                configuration: .snapshot(.init(applicationSupportURL: fixture.support, assignments: [fixture.assignment, second])))
            let lookupBarrier = ShutdownDrainBarrier()
            let sourceDrainBarrier = ShutdownDrainBarrier()
            let completions = ShutdownCompletions()
            var openers: [Task<WorkspaceHandle, any Error>] = []
            var drains: [Task<Void, Never>] = []
            try await withTaskCancellationHandler {
                do {
                    let active = try await runtime.openWorkspace(id: fixture.assignment.id)
                    let factories = await runtime.openingFactoryCountForTesting
                    let lookups = await runtime.openingLookupCountForTesting
                    if shutdownDuringLookup {
                        let snapshot = try await active.snapshot()
                        let source = try #require(snapshot.vaults.flatMap(\.documents).first { $0.id.relativePath == "Note.md" })
                        let stableID = try #require(source.stableIdentity.resolvedID)
                        await active.setCommittedMutationRefreshBarrierForTesting { await sourceDrainBarrier.hold() }
                        _ = try await active.documents.commit(
                            .init(documentID: source.id, stableNoteID: stableID, revision: source.fingerprint),
                            changeSet: .source("# Committed before shutdown\n"))
                        try await waitUntil { await sourceDrainBarrier.didArrive }
                    }
                    await runtime.setOpeningLookupBarrierForTesting { id in
                        if id == second.id { await lookupBarrier.hold() }
                    }
                    let first = Task { try await runtime.openWorkspace(id: second.id) }
                    openers.append(first)
                    try await waitUntil { await lookupBarrier.didArrive }
                    let joined = Task { try await runtime.openWorkspace(id: second.id) }
                    openers.append(joined)
                    try await waitUntil { await runtime.openingJoinCountForTesting == 1 }
                    #expect(await runtime.openingLookupCountForTesting == lookups + 1)
                    #expect(await runtime.openingFactoryCountForTesting == factories)
                    #expect(await runtime.pooledVaultRuntimeCount == 3)
                    for path in generated { #expect(!FileManager.default.fileExists(atPath: path.path)) }

                    if shutdownDuringLookup {
                        drains.append(
                            Task {
                                await runtime.shutdown()
                                await completions.finished("first")
                            })
                        try await waitUntil { await lookupBarrier.wasCancelled }
                        drains.append(
                            Task {
                                await runtime.shutdown()
                                await completions.finished("second")
                            })
                        try await waitUntil { await runtime.shutdownJoinCountForTesting == 1 }
                        #expect(await completions.names.isEmpty)
                        try await waitUntil { await active.isShutDown }
                        try await waitUntil { await sourceDrainBarrier.wasCancelled }
                        await lookupBarrier.release()
                        await #expect(throws: CancellationError.self) { _ = try await first.value }
                        await #expect(throws: CancellationError.self) { _ = try await joined.value }
                        try await waitUntil { await active.isShutDown }
                        #expect(await completions.names.isEmpty)
                        #expect(await runtime.openingFactoryCountForTesting == factories)
                        for path in generated { #expect(!FileManager.default.fileExists(atPath: path.path)) }
                        await sourceDrainBarrier.release()
                        for drain in drains { await drain.value }
                        #expect(await completions.names == ["first", "second"])
                        #expect(await runtime.pooledVaultRuntimeCount == 0)
                        #expect(try Data(contentsOf: fixture.sourceURL) == Data("# Committed before shutdown\n".utf8))
                    } else {
                        await lookupBarrier.release()
                        let firstHandle = try await first.value
                        let joinedHandle = try await joined.value
                        #expect(firstHandle === joinedHandle)
                        #expect(await runtime.openingLookupCountForTesting == lookups + 1)
                        #expect(await runtime.openingFactoryCountForTesting == factories + 1)
                        await runtime.shutdown()
                    }
                    let secondVault = try #require(second.vault(for: .paperAnalysis))
                    let secondSource = URL(fileURLWithPath: secondVault.canonicalPath).appendingPathComponent("Note.md")
                    #expect(try Data(contentsOf: secondSource) == fixture.sourceBytes)
                } catch {
                    await lookupBarrier.release()
                    await sourceDrainBarrier.release()
                    await runtime.shutdown()
                    for opener in openers { _ = await opener.result }
                    for drain in drains { await drain.value }
                    throw error
                }
            } onCancel: {
                Task {
                    await lookupBarrier.release()
                    await sourceDrainBarrier.release()
                }
            }
        }

        private func waitUntil(_ predicate: @Sendable () async -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while ContinuousClock.now < deadline {
                try Task.checkCancellation()
                if await predicate() { return }
                await Task.yield()
            }
            throw ShutdownFixtureError.barrierNotReached
        }

        private func makeFixture(withSecondWorkspace: Bool = false) async throws -> ShutdownFixture {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(".build/shutdown-drain/\(UUID().uuidString)", isDirectory: true)
            let analyses = root.appendingPathComponent("Analyses", isDirectory: true)
            let topics = root.appendingPathComponent("Topics", isDirectory: true)
            let works = root.appendingPathComponent("Works", isDirectory: true)
            let support = root.appendingPathComponent("Application Support", isDirectory: true)
            let registry = root.appendingPathComponent("Registry", isDirectory: true)
            let sourceURL = analyses.appendingPathComponent("Note.md")
            let sourceBytes = Data("\u{FEFF}# Original\r\n\r\nExact e\u{301} 中文 😀 without final newline".utf8)
            let runtime = WorkspaceRuntime(
                configuration: .live(.init(applicationSupportURL: support, workspaceRegistryStorageURL: registry)))
            do {
                for directory in [analyses, topics, works, support] {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                }
                try sourceBytes.write(to: sourceURL)
                let handle = try await runtime.configureTriptych(
                    paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
                    portableContainerURL: root, triptychName: "Shutdown drain fixture")
                _ = try await handle.refresh()
                let assignment = handle.assignment
                var secondAssignment: TriptychAssignment?
                if withSecondWorkspace {
                    let container = root.appendingPathComponent("Second Triptych", isDirectory: true)
                    let secondAnalyses = container.appendingPathComponent("Analyses", isDirectory: true)
                    let secondTopics = container.appendingPathComponent("Topics", isDirectory: true)
                    let secondWorks = container.appendingPathComponent("Works", isDirectory: true)
                    for directory in [secondAnalyses, secondTopics, secondWorks] {
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    }
                    try sourceBytes.write(to: secondAnalyses.appendingPathComponent("Note.md"))
                    let second = try await runtime.configureTriptych(
                        paperAnalysisURL: secondAnalyses, topicKnowledgeURL: secondTopics, outputURL: secondWorks,
                        portableContainerURL: container, triptychName: "Second shutdown fixture")
                    _ = try await second.refresh()
                    secondAssignment = second.assignment
                }
                await runtime.shutdown()
                return ShutdownFixture(
                    root: root, support: support, registry: registry, sourceURL: sourceURL,
                    sourceBytes: sourceBytes, assignment: assignment, secondAssignment: secondAssignment)
            } catch {
                await runtime.shutdown()
                try? FileManager.default.removeItem(at: root)
                throw error
            }
        }
    }

    private enum ShutdownFixtureError: Error { case barrierNotReached }

    private struct ShutdownFixture {
        let root: URL
        let support: URL
        let registry: URL
        let sourceURL: URL
        let sourceBytes: Data
        let assignment: TriptychAssignment
        let secondAssignment: TriptychAssignment?

        func maintenanceRuntime() -> WorkspaceRuntime {
            WorkspaceRuntime(configuration: .live(.init(applicationSupportURL: support, workspaceRegistryStorageURL: registry)))
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    private actor ShutdownCompletions {
        private(set) var names: Set<String> = []
        func finished(_ name: String) { names.insert(name) }
    }

    private actor ShutdownDrainBarrier {
        private(set) var didArrive = false
        private(set) var wasCancelled = false
        private var isReleased = false
        private var continuation: CheckedContinuation<Void, Never>?

        // Cancellation of the drained task must not stand in for completion of
        // admitted work. Test cancellation releases this barrier from its owner.
        func hold() async {
            didArrive = true
            guard !isReleased else { return }
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation = $0 }
            } onCancel: {
                Task { await self.observeCancellation() }
            }
        }

        private func observeCancellation() { wasCancelled = true }

        func release() {
            isReleased = true
            continuation?.resume()
            continuation = nil
        }
    }
#endif
