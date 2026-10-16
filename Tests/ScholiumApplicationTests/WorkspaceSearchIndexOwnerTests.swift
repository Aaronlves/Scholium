import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

#if DEBUG
    @Suite("Workspace Search admission ownership")
    struct WorkspaceSearchIndexOwnerTests {
        @Test("Readiness is lazy and two resolving callers share one complete factory", .timeLimit(.minutes(1)))
        func sharedAdmission() async throws {
            try await withContext { context in
                let index = try await context.makeIndex()
                let factory = AdmissionFactoryProbe(outcomes: [.success(index)])
                await context.releaseOnCleanup { await factory.releaseAll() }
                let owner = await context.makeOwner { try await factory.run() }
                guard case .pending = await owner.admissionState() else { throw AdmissionTestError.unexpectedState }
                #expect(await owner.readyIndex() == nil)
                #expect(await factory.callCount == 0)

                let first = Task { try await owner.resolve() }
                let second = Task { try await owner.resolve() }
                await context.track(first)
                await context.track(second)
                try await requireState { await owner.resolvingWaiterCountForTesting == 2 }
                #expect(await factory.callCount == 1)
                #expect(await owner.readyIndex() == nil)
                await factory.release(0)
                #expect(try await first.value == index)
                #expect(try await second.value == index)
                #expect(await owner.readyIndex() == index)
                guard case .ready(let admitted) = await owner.admissionState() else { throw AdmissionTestError.unexpectedState }
                #expect(admitted == index)
                try await owner.retryFailedAdmission()
                #expect(try await owner.resolve() == index)
                #expect(await factory.callCount == 1)
            }
        }

        @Test("Cancelling one waiter preserves the shared factory and surviving index", .timeLimit(.minutes(1)))
        func cancelledWaiter() async throws {
            try await withContext { context in
                let index = try await context.makeIndex()
                let factory = AdmissionFactoryProbe(outcomes: [.success(index)])
                await context.releaseOnCleanup { await factory.releaseAll() }
                let owner = await context.makeOwner { try await factory.run() }
                let cancelled = Task { try await owner.resolve() }
                let survivor = Task { try await owner.resolve() }
                await context.track(cancelled)
                await context.track(survivor)
                try await requireState { await owner.resolvingWaiterCountForTesting == 2 }
                cancelled.cancel()
                await factory.release(0)
                await #expect(throws: CancellationError.self) { _ = try await cancelled.value }
                #expect(try await survivor.value == index)
                #expect(await owner.readyIndex() == index)
                #expect(await factory.cancelledCalls.isEmpty)
                #expect(await factory.callCount == 1)
            }
        }

        @Test("Shutdown before resolution never starts admission and remains idempotent", .timeLimit(.minutes(1)))
        func idleShutdown() async throws {
            try await withContext { context in
                let index = try await context.makeIndex()
                let factory = AdmissionFactoryProbe(outcomes: [.success(index)])
                await factory.release(0)
                let owner = await context.makeOwner { try await factory.run() }
                let first = await owner.beginShutdown()
                let second = await owner.beginShutdown()
                await first.value
                await second.value
                await owner.shutdown()
                guard case .shutDown = await owner.admissionState() else { throw AdmissionTestError.unexpectedState }
                #expect(await owner.readyIndex() == nil)
                #expect(await factory.callCount == 0)
                await #expect(throws: ScholiumApplicationError.self) { _ = try await owner.resolve() }
                await #expect(throws: ScholiumApplicationError.self) { try await owner.retryFailedAdmission() }
                // The uncalled factory's dependency was never transferred to the owner.
                #expect(try await index.generation() == nil)
            }
        }

        @Test("Shutdown cancels and joins an admitted cooperative factory", .timeLimit(.minutes(1)))
        func shutdownDuringAdmission() async throws {
            try await withContext { context in
                let index = try await context.makeIndex()
                let factory = AdmissionFactoryProbe(outcomes: [.success(index)])
                await context.releaseOnCleanup { await factory.releaseAll() }
                let owner = await context.makeOwner { try await factory.run() }
                let resolving = Task { try await owner.resolve() }
                await context.track(resolving)
                try await requireState { await factory.callCount == 1 }
                let shutdown = await owner.beginShutdown()
                guard case .shutDown = await owner.admissionState() else { throw AdmissionTestError.unexpectedState }
                await shutdown.value
                await #expect(throws: ScholiumApplicationError.self) { _ = try await resolving.value }
                #expect(await factory.cancelledCalls == [0])
                #expect(await owner.readyIndex() == nil)
            }
        }

        @Test("Shutdown retains and closes a late successful factory that ignores cancellation", .timeLimit(.minutes(1)))
        func shutdownClosesLateSuccess() async throws {
            try await withContext { context in
                let index = try await context.makeIndex()
                let factory = AdmissionFactoryProbe(outcomes: [.success(index)], honorsCancellation: false)
                await context.releaseOnCleanup { await factory.releaseAll() }
                let owner = await context.makeOwner { try await factory.run() }
                let resolving = Task { try await owner.resolve() }
                await context.track(resolving)
                try await requireState { await factory.callCount == 1 }
                let shutdown = await owner.beginShutdown()
                let completion = AdmissionCompletionProbe()
                let observer = Task {
                    await shutdown.value
                    await completion.finish()
                }
                await context.track(observer)
                try await requireState { await factory.cancelledCalls == [0] }
                #expect(!(await completion.finished))
                await factory.release(0)
                await shutdown.value
                await observer.value
                await #expect(throws: ScholiumApplicationError.self) { _ = try await resolving.value }
                await #expect(throws: SearchIndexError.self) { _ = try await index.generation() }
                #expect(await owner.readyIndex() == nil)
            }
        }

        @Test("Shutdown owns a successful result while its resolver is suspended before delivery", .timeLimit(.minutes(1)))
        func shutdownDuringResultDelivery() async throws {
            try await withContext { context in
                let index = try await context.makeIndex()
                let factory = AdmissionFactoryProbe(outcomes: [.success(index)])
                let delivery = AdmissionResultDeliveryGate(passFirst: false)
                await context.releaseOnCleanup {
                    await factory.releaseAll()
                    await delivery.releaseAll()
                }
                let owner = await context.makeOwner { try await factory.run() }
                await owner.setResultDeliveryBarrierForTesting { await delivery.arrive($0) }
                let resolving = Task { try await owner.resolve() }
                await context.track(resolving)
                try await requireState { await factory.callCount == 1 }
                await factory.release(0)
                try await requireState { await delivery.heldCount == 1 }
                #expect(await owner.readyIndex() == nil)
                let shutdown = await owner.beginShutdown()
                await shutdown.value
                await #expect(throws: SearchIndexError.self) { _ = try await index.generation() }
                await delivery.releaseAll()
                await #expect(throws: ScholiumApplicationError.self) { _ = try await resolving.value }
            }
        }

        @Test("Explicit retry is required and a stale failed waiter cannot poison its successful successor", .timeLimit(.minutes(1)))
        func explicitRetryAndStaleFailure() async throws {
            try await withContext { context in
                let index = try await context.makeIndex()
                let factory = AdmissionFactoryProbe(outcomes: [.failure(.injected), .success(index)])
                let delivery = AdmissionResultDeliveryGate(passFirst: true)
                await context.releaseOnCleanup {
                    await factory.releaseAll()
                    await delivery.releaseAll()
                }
                let owner = await context.makeOwner { try await factory.run() }
                await owner.setResultDeliveryBarrierForTesting { await delivery.arrive($0) }
                let first = Task { try await owner.resolve() }
                let stale = Task { try await owner.resolve() }
                await context.track(first)
                await context.track(stale)
                try await requireState { await owner.resolvingWaiterCountForTesting == 2 }
                await factory.release(0)
                try await requireState {
                    guard case .failed = await owner.admissionState() else { return false }
                    return await delivery.heldCount == 1
                }
                guard case .failed(let error) = await owner.admissionState() else { throw AdmissionTestError.unexpectedState }
                #expect(error as? AdmissionTestError == .injected)
                await #expect(throws: AdmissionTestError.injected) { _ = try await owner.resolve() }
                #expect(await factory.callCount == 1)
                try await owner.retryFailedAdmission()
                await owner.setResultDeliveryBarrierForTesting(nil)
                guard case .pending = await owner.admissionState() else { throw AdmissionTestError.unexpectedState }
                let retry = Task { try await owner.resolve() }
                await context.track(retry)
                try await requireState { await factory.callCount == 2 }
                await factory.release(1)
                #expect(try await retry.value == index)
                await delivery.releaseAll()
                await #expect(throws: AdmissionTestError.injected) { _ = try await first.value }
                await #expect(throws: AdmissionTestError.injected) { _ = try await stale.value }
                #expect(await owner.readyIndex() == index)
                #expect(try await owner.resolve() == index)
                #expect(await factory.callCount == 2)
            }
        }

        private func withContext(_ body: (AdmissionTestContext) async throws -> Void) async throws {
            let context = try AdmissionTestContext()
            do { try await body(context) } catch {
                await context.cleanup()
                throw error
            }
            await context.cleanup()
        }

        private func requireState(_ predicate: @Sendable () async -> Bool) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(5))
            while clock.now < deadline {
                if await predicate() { return }
                try await Task.sleep(for: .milliseconds(2))
            }
            Issue.record("The controlled Search admission state was not reached.")
            throw AdmissionTestError.timedOut
        }
    }

    private enum AdmissionTestError: Error, Equatable { case injected, timedOut, unexpectedState }

    private actor AdmissionCompletionProbe {
        private(set) var finished = false
        func finish() { finished = true }
    }

    private actor AdmissionFactoryProbe {
        let outcomes: [Result<WorkspaceSearchIndexTestResource, AdmissionTestError>]
        let honorsCancellation: Bool
        private(set) var callCount = 0
        private(set) var cancelledCalls: Set<Int> = []
        private var released: Set<Int> = []
        private var releaseEverything = false
        private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]

        init(outcomes: [Result<WorkspaceSearchIndexTestResource, AdmissionTestError>], honorsCancellation: Bool = true) {
            self.outcomes = outcomes
            self.honorsCancellation = honorsCancellation
        }

        func run() async throws -> WorkspaceSearchIndexTestResource {
            let call = callCount
            callCount += 1
            await withTaskCancellationHandler {
                await waitForRelease(call)
            } onCancel: {
                Task { await self.cancelled(call) }
            }
            if honorsCancellation { try Task.checkCancellation() }
            guard outcomes.indices.contains(call) else { throw AdmissionTestError.unexpectedState }
            return try outcomes[call].get()
        }

        private func waitForRelease(_ call: Int) async {
            if released.contains(call) || releaseEverything { return }
            await withCheckedContinuation { waiters[call] = $0 }
        }

        private func cancelled(_ call: Int) {
            cancelledCalls.insert(call)
            if honorsCancellation { release(call) }
        }

        func release(_ call: Int) {
            released.insert(call)
            waiters.removeValue(forKey: call)?.resume()
        }

        func releaseAll() {
            releaseEverything = true
            let pending = Array(waiters.values)
            waiters.removeAll()
            pending.forEach { $0.resume() }
        }
    }

    private actor AdmissionResultDeliveryGate {
        let passFirst: Bool
        private var arrivals = 0
        private var released = false
        private var held: [CheckedContinuation<Void, Never>] = []
        var heldCount: Int { held.count }

        init(passFirst: Bool) { self.passFirst = passFirst }

        func arrive(_ attempt: UUID) async {
            arrivals += 1
            if released || (passFirst && arrivals == 1) { return }
            await withCheckedContinuation { held.append($0) }
        }

        func releaseAll() {
            released = true
            let pending = held
            held.removeAll()
            pending.forEach { $0.resume() }
        }
    }

    private actor AdmissionTestContext {
        let root: URL
        private var indexes: [WorkspaceSearchIndexTestResource] = []
        private var owners: [WorkspaceSearchIndexOwnerTestProbe] = []
        private var releases: [@Sendable () async -> Void] = []
        private var drains: [@Sendable () async -> Void] = []

        init() throws {
            root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent(".build/workspace-search-owner-tests/\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func makeIndex() throws -> WorkspaceSearchIndexTestResource {
            let index = try WorkspaceSearchIndexTestResource(applicationSupportURL: root, triptychID: UUID())
            indexes.append(index)
            return index
        }

        func makeOwner(_ factory: @escaping @Sendable () async throws -> WorkspaceSearchIndexTestResource) -> WorkspaceSearchIndexOwnerTestProbe {
            let owner = WorkspaceSearchIndexOwnerTestProbe(factory: factory)
            owners.append(owner)
            return owner
        }

        func releaseOnCleanup(_ release: @escaping @Sendable () async -> Void) { releases.append(release) }

        func track<Success: Sendable, Failure: Error>(_ task: Task<Success, Failure>) {
            drains.append {
                task.cancel()
                _ = await task.result
            }
        }

        func cleanup() async {
            for release in releases { await release() }
            var shutdowns: [Task<Void, Never>] = []
            for owner in owners { shutdowns.append(await owner.beginShutdown()) }
            for drain in drains { await drain() }
            for shutdown in shutdowns { await shutdown.value }
            for index in indexes { await index.shutdown() }
            try? FileManager.default.removeItem(at: root)
        }
    }
#endif
