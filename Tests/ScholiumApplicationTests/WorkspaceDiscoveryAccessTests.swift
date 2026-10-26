import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

#if DEBUG
    @Suite("Derived discovery source-access admission")
    struct WorkspaceDiscoveryAccessTests {
        @Test(
            "Root invalidation revokes prepared discovery results and subsequent reads",
            .timeLimit(.minutes(1)),
            arguments: DiscoveryRead.allCases)
        func invalidatedRootRejectsDelivery(_ read: DiscoveryRead) async throws {
            try await withFixture { runtime, handle, fixture in
                // A real successful neighbor prevents universal rejection from
                // satisfying the revocation assertions.
                #expect(try await read.perform(handle, note: fixture.analysisNoteID))
                let original = try await handle.snapshot()
                let barrier = DiscoveryDeliveryBarrier()
                await handle.setDiscoveryResultDeliveryBarrierForTesting { await barrier.holdOnce() }
                let pending = Task { try await read.perform(handle, note: fixture.analysisNoteID) }
                try await withTaskCancellationHandler {
                    do {
                        try #require(await barrier.waitUntilArrived())
                        try await runtime.deliverPooledVaultEventForTesting(
                            .reconciliationRequired(sequence: 90, rootChanged: true),
                            vaultID: fixture.analysisNoteID.vaultID)
                        try await waitUntilRootIsInvalid(handle, vaultID: fixture.analysisNoteID.vaultID)
                        await barrier.release()
                        await #expect {
                            _ = try await pending.value
                        } throws: { Self.isAccessUnavailable($0, path: fixture.analysesURL.path) }
                        await handle.setDiscoveryResultDeliveryBarrierForTesting(nil)
                        await #expect {
                            _ = try await read.perform(handle, note: fixture.analysisNoteID)
                        } throws: { Self.isAccessUnavailable($0, path: fixture.analysesURL.path) }
                        // Recovery may still inspect the last complete snapshot;
                        // retaining it grants no new derived-content read.
                        let retained = try await handle.snapshot()
                        #expect(retained.discovery.catalog.notes == original.discovery.catalog.notes)
                        #expect(retained.discovery.searchGeneration == original.discovery.searchGeneration)
                    } catch {
                        pending.cancel()
                        await barrier.release()
                        _ = await pending.result
                        await handle.setDiscoveryResultDeliveryBarrierForTesting(nil)
                        throw error
                    }
                } onCancel: {
                    pending.cancel()
                    Task { await barrier.release() }
                }
            }
        }

        @Test("A completed cached Search cannot deliver after activation shutdown", .timeLimit(.minutes(1)))
        func shutdownRejectsDelivery() async throws {
            try await withFixture { _, handle, fixture in
                let barrier = DiscoveryDeliveryBarrier()
                await handle.setDiscoveryResultDeliveryBarrierForTesting { await barrier.holdOnce() }
                let pending = Task { try await DiscoveryRead.search.perform(handle, note: fixture.analysisNoteID) }
                try await withTaskCancellationHandler {
                    do {
                        try #require(await barrier.waitUntilArrived())
                        await handle.shutdown()
                        await barrier.release()
                        await #expect {
                            _ = try await pending.value
                        } throws: {
                            guard let error = $0 as? ScholiumApplicationError else { return false }
                            if case .workspaceShutDown(let id) = error { return id == fixture.assignment.id }
                            return false
                        }
                    } catch {
                        pending.cancel()
                        await barrier.release()
                        _ = await pending.result
                        throw error
                    }
                } onCancel: {
                    pending.cancel()
                    Task { await barrier.release() }
                }
            }
        }

        private func withFixture(
            _ body: (WorkspaceRuntime, WorkspaceHandle, ApplicationFixture) async throws -> Void
        ) async throws {
            let fixture = try await ApplicationFixture.make()
            defer { fixture.remove() }
            try Data("# Agency\n\nFreedom enables action and agency.\n\n[[Freedom]]\n".utf8)
                .write(to: fixture.analysesURL.appendingPathComponent(fixture.analysisNoteID.relativePath))
            let runtime = WorkspaceRuntime(
                configuration: .live(
                    .init(
                        applicationSupportURL: fixture.applicationSupportURL,
                        workspaceRegistryStorageURL: fixture.registryStorageURL)))
            do {
                let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
                await handle.awaitOpeningCompletionForTesting()
                _ = try await handle.discovery.refresh()
                try await waitUntilDiscoveryIsIdle(handle)
                try await body(runtime, handle, fixture)
            } catch {
                await runtime.shutdown()
                throw error
            }
            await runtime.shutdown()
        }

        private func waitUntilDiscoveryIsIdle(_ handle: WorkspaceHandle) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(30))
            while clock.now < deadline {
                try Task.checkCancellation()
                let eventsAreEmpty = await handle.pendingLiveEvents.isEmpty
                let liveRefreshIsIdle = await handle.liveIndexRefreshTask == nil
                let sourceRefreshIsIdle = await handle.sourceCommitRefreshTask == nil
                if eventsAreEmpty && liveRefreshIsIdle && sourceRefreshIsIdle { return }
                await Task.yield()
            }
            throw DiscoveryAccessTestError.discoveryReadinessTimedOut
        }

        private func waitUntilRootIsInvalid(_ handle: WorkspaceHandle, vaultID: UUID) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(30))
            while clock.now < deadline {
                try Task.checkCancellation()
                if await handle.unavailableRootVaultIDs.contains(vaultID) { return }
                await Task.yield()
            }
            throw DiscoveryAccessTestError.rootInvalidationTimedOut
        }

        private static func isAccessUnavailable(_ error: any Error, path: String) -> Bool {
            guard let error = error as? WorkspaceRegistryError else { return false }
            if case .vaultAccessUnavailable(let unavailable) = error { return unavailable == path }
            return false
        }
    }

    private enum DiscoveryAccessTestError: Error { case discoveryReadinessTimedOut, rootInvalidationTimedOut }

    enum DiscoveryRead: CaseIterable, Sendable {
        case search, completion, writing, related, preparation, links, diagnostics

        func perform(_ handle: WorkspaceHandle, note: VaultQualifiedNoteID) async throws -> Bool {
            let related = RelatedContentRequest(
                seed: .init(
                    noteID: note, source: "# Agency\n\nFreedom enables action and agency.\n\n[[Freedom]]\n",
                    focuses: [.init(kind: .selectedPassage, text: "agency")]))
            switch self {
            case .search:
                let response = try await handle.discovery.search(
                    .init(
                        query: "freedom", presentationScope: .triptych, executionScope: .triptych, limit: 20))
                guard case .current = response.availability else { return false }
                return !response.results.isEmpty
            case .completion:
                let response = try await handle.discovery.searchCompletions(
                    .init(
                        lookup: .init(partial: "fre"), presentationScope: .triptych, executionScope: .triptych))
                guard case .current = response.availability else { return false }
                return !response.terms.isEmpty
            case .writing:
                return try await !handle.discovery.writingCompletions(matching: "Fre").isEmpty
            case .related:
                return try await !handle.discovery.relatedContent(related).passages.isEmpty
            case .preparation:
                return try await handle.prepareRelatedContent(related) != nil
            case .links:
                return try await !handle.discovery.links(for: note, direction: .outgoing).isEmpty
            case .diagnostics:
                return try await handle.discovery.linkDiagnostics().isEmpty
            }
        }
    }

    private actor DiscoveryDeliveryBarrier {
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
#endif
