import Foundation
import ScholiumContracts
import ScholiumCore
import Testing

@testable import ScholiumApplication

#if DEBUG
    @Suite("Deferred workspace derived-state maintenance")
    struct WorkspaceDeferredMaintenanceTests {
        @Test("Listing and source-ready opening defer maintenance until complete opening", .timeLimit(.minutes(1)))
        func listingAndOpeningDeferral() async throws {
            try await withFixture { fixture, runtime, passes, lifetime in
                let retired = try makeRetiredIndex(fixture)
                #expect(try await runtime.availableWorkspaces().map(\.id) == [fixture.assignment.id])
                #expect(try await runtime.defaultWorkspace().id == fixture.assignment.id)
                #expect(await runtime.derivedMaintenancePhaseForTesting == nil)
                #expect(await runtime.derivedMaintenancePassCountForTesting == 0)
                #expect(FileManager.default.fileExists(atPath: retired.path))

                let handle = try await runtime.openWorkspace(id: fixture.assignment.id, openingVault: .paperAnalysis)
                let opening = MaintenanceOpeningGate()
                await lifetime.releaseOnCleanup { await opening.release() }
                await handle.setProgressiveActivationReconciliationBarrierForTesting { await opening.wait() }
                #expect(try await handle.snapshot().phase == .opening)
                try await requireState {
                    let waiting = await runtime.derivedMaintenancePhaseForTesting == "waiting"
                    let subscribers = await handle.events.subscriberCount
                    return waiting && subscribers == 1
                }
                #expect(await runtime.derivedMaintenancePassCountForTesting == 0)
                await handle.openingPresentationDidComplete()
                try await requireState { await opening.arrived }
                #expect(await runtime.derivedMaintenancePassCountForTesting == 0)
                await opening.release()
                try await requireState { await passes.started.contains(1) }
                #expect(try await handle.snapshot().phase == .complete)
                try await requireState { await handle.events.subscriberCount == 0 }
                #expect(FileManager.default.fileExists(atPath: retired.path))
                await passes.release(1)
                try await requireState { await runtime.derivedMaintenancePhaseForTesting == nil }
                #expect(await runtime.latestDerivedStateMaintenanceSummary?.removedFiles ?? 0 > 0)
                #expect(!FileManager.default.fileExists(atPath: retired.path))
            }
        }

        @Test("Forced cleanup cancels the opening wait and runs one fresh pass", .timeLimit(.minutes(1)))
        func forceReplacesWaitingTask() async throws {
            try await withFixture { fixture, runtime, passes, lifetime in
                let handle = try await runtime.openWorkspace(id: fixture.assignment.id, openingVault: .paperAnalysis)
                try await requireState { await runtime.derivedMaintenancePhaseForTesting == "waiting" }
                let forced = Task { try await runtime.performStorageAction(.cleanRetiredDerivedState) }
                await lifetime.track(forced)
                try await requireState { await passes.started.contains(1) }
                #expect(await runtime.derivedMaintenanceWaitingCancellationCountForTesting == 1)
                #expect(await runtime.derivedMaintenancePassCountForTesting == 1)
                try await requireState { await handle.events.subscriberCount == 0 }
                await passes.release(1)
                #expect(try await forced.value.action == .cleanRetiredDerivedState)
                #expect(await runtime.derivedMaintenancePhaseForTesting == nil)
                #expect(await runtime.derivedMaintenancePassCountForTesting == 1)
            }
        }

        @Test("Forced cleanup joins a running automatic pass before performing a fresh pass", .timeLimit(.minutes(1)))
        func forceJoinsRunningThenRefreshes() async throws {
            try await withFixture { fixture, runtime, passes, lifetime in
                _ = try await runtime.openWorkspace(id: fixture.assignment.id)
                try await requireState { await passes.started.contains(1) }
                let forced = Task { try await runtime.performStorageAction(.cleanRetiredDerivedState) }
                await lifetime.track(forced)
                try await requireState { await runtime.derivedMaintenanceJoinCountForTesting == 1 }
                #expect(await runtime.derivedMaintenancePassCountForTesting == 1)
                #expect(await passes.cancelled.isEmpty)
                await passes.release(1)
                try await requireState { await passes.started.contains(2) }
                #expect(await runtime.derivedMaintenancePassCountForTesting == 2)
                #expect(await passes.cancelled.isEmpty)
                await passes.release(2)
                #expect(try await forced.value.action == .cleanRetiredDerivedState)
                #expect(await runtime.derivedMaintenancePhaseForTesting == nil)
            }
        }

        enum ShutdownStage: CaseIterable, Equatable, Sendable { case waiting, running }

        @Test("Shutdown drains deferred work before its final forced maintenance", .timeLimit(.minutes(1)), arguments: ShutdownStage.allCases)
        func shutdownDrain(stage: ShutdownStage) async throws {
            try await withFixture { fixture, runtime, passes, lifetime in
                let handle = try await runtime.openWorkspace(
                    id: fixture.assignment.id, openingVault: stage == .waiting ? .paperAnalysis : nil)
                if stage == .waiting {
                    try await requireState { await runtime.derivedMaintenancePhaseForTesting == "waiting" }
                } else {
                    try await requireState { await passes.started.contains(1) }
                }
                let shutdown = Task { await runtime.shutdown() }
                await lifetime.track(shutdown)
                let finalPass = stage == .waiting ? 1 : 2
                try await requireState { await passes.started.contains(finalPass) }
                if stage == .waiting {
                    #expect(await runtime.derivedMaintenanceWaitingCancellationCountForTesting == 1)
                } else {
                    #expect(await passes.cancelled == [1])
                }
                try await requireState { await handle.events.subscriberCount == 0 }
                await passes.release(finalPass)
                await shutdown.value
                #expect(await runtime.derivedMaintenancePassCountForTesting == finalPass)
                #expect(await runtime.derivedMaintenancePhaseForTesting == nil)
                await runtime.shutdown()
                #expect(await runtime.derivedMaintenancePassCountForTesting == finalPass)
            }
        }

        @Test("Forced maintenance preserves unreadable membership and propagates its failure", .timeLimit(.minutes(1)))
        func failedRegistryNeverAuthorizesDeletion() async throws {
            try await withFixture { fixture, runtime, passes, _ in
                let retired = try makeRetiredIndex(fixture)
                let originalRetired = try Data(contentsOf: retired)
                let registry = fixture.registryStorageURL.appendingPathComponent("workspace-registration-v3.json")
                let original = try Data(contentsOf: registry)
                defer { try? original.write(to: registry, options: .atomic) }
                try Data("{unreadable membership".utf8).write(to: registry, options: .atomic)
                await passes.releaseAll()
                await #expect(throws: WorkspaceRegistryError.self) {
                    _ = try await runtime.performStorageAction(.cleanRetiredDerivedState)
                }
                #expect(await runtime.derivedMaintenancePassCountForTesting == 1)
                #expect(await runtime.latestDerivedStateMaintenanceSummary?.failedDirectories == 1)
                #expect(try Data(contentsOf: retired) == originalRetired)
                #expect(try Data(contentsOf: registry) == Data("{unreadable membership".utf8))
            }
        }

        private func makeRetiredIndex(_ fixture: ApplicationFixture) throws -> URL {
            let directory = fixture.applicationSupportURL
                .appendingPathComponent("Triptychs/\(UUID().uuidString.lowercased())/indexes", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent("search-v9.sqlite")
            try Data("test-owned retired generated state".utf8).write(to: target)
            return target
        }

        private func withFixture(
            _ body: (ApplicationFixture, WorkspaceRuntime, MaintenancePassProbe, MaintenanceTestLifetime) async throws -> Void
        ) async throws {
            let fixture = try await ApplicationFixture.make(registerLiveAccess: true)
            let runtime = WorkspaceRuntime(configuration: .live(.init(
                applicationSupportURL: fixture.applicationSupportURL,
                workspaceRegistryStorageURL: fixture.registryStorageURL)))
            let passes = MaintenancePassProbe()
            let lifetime = MaintenanceTestLifetime()
            await runtime.setDerivedMaintenanceBarrierForTesting { await passes.wait($0) }
            do { try await body(fixture, runtime, passes, lifetime) } catch {
                await lifetime.cleanup(runtime: runtime, passes: passes)
                fixture.remove()
                throw error
            }
            await lifetime.cleanup(runtime: runtime, passes: passes)
            fixture.remove()
        }

        private func requireState(_ predicate: @Sendable () async throws -> Bool) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(5))
            while clock.now < deadline {
                if try await predicate() { return }
                try await Task.sleep(for: .milliseconds(2))
            }
            Issue.record("The controlled deferred-maintenance state was not reached.")
            throw MaintenanceTestError.timedOut
        }
    }

    private enum MaintenanceTestError: Error { case timedOut }

    private actor MaintenancePassProbe {
        private(set) var started: Set<Int> = []
        private(set) var cancelled: Set<Int> = []
        private var released: Set<Int> = []
        private var releaseEverything = false
        private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]

        func wait(_ pass: Int) async {
            started.insert(pass)
            await withTaskCancellationHandler {
                if released.contains(pass) || releaseEverything { return }
                await withCheckedContinuation { waiters[pass] = $0 }
            } onCancel: {
                Task { await self.cancel(pass) }
            }
        }

        private func cancel(_ pass: Int) {
            cancelled.insert(pass)
            release(pass)
        }

        func release(_ pass: Int) {
            released.insert(pass)
            waiters.removeValue(forKey: pass)?.resume()
        }

        func releaseAll() {
            releaseEverything = true
            let pending = Array(waiters.values)
            waiters.removeAll()
            pending.forEach { $0.resume() }
        }
    }

    private actor MaintenanceOpeningGate {
        private(set) var arrived = false
        private var released = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            arrived = true
            await withTaskCancellationHandler {
                if released { return }
                await withCheckedContinuation { waiters.append($0) }
            } onCancel: {
                Task { await self.release() }
            }
        }

        func release() {
            released = true
            let pending = waiters
            waiters.removeAll()
            pending.forEach { $0.resume() }
        }
    }

    private actor MaintenanceTestLifetime {
        private var releases: [@Sendable () async -> Void] = []
        private var cancellations: [@Sendable () -> Void] = []
        private var joins: [@Sendable () async -> Void] = []

        func releaseOnCleanup(_ release: @escaping @Sendable () async -> Void) { releases.append(release) }

        func track<Success: Sendable, Failure: Error>(_ task: Task<Success, Failure>) {
            cancellations.append { task.cancel() }
            joins.append { _ = await task.result }
        }

        func cleanup(runtime: WorkspaceRuntime, passes: MaintenancePassProbe) async {
            cancellations.forEach { $0() }
            for release in releases { await release() }
            await passes.releaseAll()
            await runtime.shutdown()
            for join in joins { await join() }
        }
    }
#endif
