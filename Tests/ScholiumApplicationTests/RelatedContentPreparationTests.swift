import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Related-content background preparation")
struct RelatedContentPreparationTests {
    #if DEBUG
        @Test("Same-key callers share preparation; completed reuse never authorizes foreground source", .timeLimit(.minutes(1)))
        func singleFlightAndForegroundFreshness() async throws {
            try await withPreparationFixture { fixture in
                let handle = fixture.handle
                let gate = PreparationGate()
                await handle.setRelatedContentPreparationStartedBarrierForTesting { await gate.holdOnce() }
                let first = await fixture.tasks.start(handle, request: fixture.request())
                try await waitForPreparation { await gate.entries == 1 }
                let joiner = await fixture.tasks.start(
                    handle,
                    request: fixture.request(
                        roles: [.work, .topic, .analysis, .topic], focus: "A different foreground focus"))
                try await waitForPreparation { await handle.relatedContentPreparationFlights.values.first?.waiters.count == 2 }
                await gate.release()
                let produced = try #require(try await first.value)
                let joined = try #require(try await joiner.value)
                #expect(produced.sourceCount > 0 && !produced.reusedCompletedPreparation && !produced.joinedRunningPreparation)
                #expect(joined.sourceCount == 0 && joined.joinedRunningPreparation && !joined.reusedCompletedPreparation)
                #expect(joined.peakBufferedSourceBytes == 0 && joined.peakBufferedSourceCount == 0)
                #expect(await gate.entries == 1)
                #expect(await handle.relatedContentSourceLoadAttemptsForTesting == produced.sourceCount)
                let reused = try #require(try await handle.prepareRelatedContent(fixture.request()))
                #expect(reused.reusedCompletedPreparation && reused.sourceCount == 0 && !reused.joinedRunningPreparation)
                let before = await handle.relatedContentSourceLoadAttemptsForTesting
                let foreground = try await handle.discovery.relatedContent(fixture.request())
                #expect(foreground.passages.map(\.candidate.note.relativePath) == ["Quantum.md"])
                #expect(await handle.relatedContentSourceLoadAttemptsForTesting == before + 1)
                #expect(await handle.lastRelatedContentMeasurement?.sourceCount == 1)

                try Data("New unrelated source bytes.".utf8).write(to: fixture.target)
                let unchangedCohort = try #require(try await handle.prepareRelatedContent(fixture.request()))
                #expect(unchangedCohort.reusedCompletedPreparation && unchangedCohort.sourceCount == 0)
                let stale = try await handle.discovery.relatedContent(fixture.request())
                #expect(stale.omittedSourceCount > 0 && !stale.passages.contains { $0.candidate.note.relativePath == "Quantum.md" })
                #expect(await handle.relatedContentSourceLoadAttemptsForTesting == before + 2)
            }
        }

        @Test("Caller cancellation owns only its waiter, and the last caller cancels the producer", .timeLimit(.minutes(1)), arguments: [0, 1, 2])
        func waiterCancellation(cancelledCaller: Int) async throws {
            try await withPreparationFixture { fixture in
                let handle = fixture.handle
                let gate = PreparationGate()
                await handle.setRelatedContentPreparationStartedBarrierForTesting { await gate.holdOnce() }
                let creator = await fixture.tasks.start(handle, request: fixture.request())
                try await waitForPreparation { await gate.entries == 1 }
                if cancelledCaller == 0 {
                    creator.cancel()
                    await #expect(throws: CancellationError.self) { try await creator.value }
                    try await waitForPreparation { await handle.relatedContentPreparationFlights.isEmpty }
                    #expect(await handle.relatedContentCompletedPreparations.isEmpty)
                    #expect(await gate.exits == 1)
                    let retry = try #require(try await handle.prepareRelatedContent(fixture.request()))
                    #expect(retry.sourceCount > 0 && !retry.reusedCompletedPreparation && !retry.joinedRunningPreparation)
                } else {
                    let joiner = await fixture.tasks.start(handle, request: fixture.request())
                    try await waitForPreparation { await handle.relatedContentPreparationFlights.values.first?.waiters.count == 2 }
                    let cancelled = cancelledCaller == 1 ? joiner : creator
                    let retained = cancelledCaller == 1 ? creator : joiner
                    cancelled.cancel()
                    await #expect(throws: CancellationError.self) { try await cancelled.value }
                    try await waitForPreparation { await handle.relatedContentPreparationFlights.values.first?.waiters.count == 1 }
                    #expect(await handle.relatedContentPreparationFlights.values.first?.task.isCancelled == false)
                    await gate.release()
                    #expect(try await retained.value != nil)
                }
                let reused = try #require(try await handle.prepareRelatedContent(fixture.request()))
                #expect(reused.reusedCompletedPreparation && reused.sourceCount == 0)
            }
        }

        @Test("Seed revision and normalized scope separate keys; completed metadata has two slots", .timeLimit(.minutes(1)))
        func preparationKeysAndBound() async throws {
            try await withPreparationFixture { fixture in
                let handle = fixture.handle
                let initial = try #require(try await handle.prepareRelatedContent(fixture.request()))
                #expect(initial.sourceCount > 0 && !initial.reusedCompletedPreparation)
                let normalized = try #require(
                    try await handle.prepareRelatedContent(fixture.request(roles: [.topic, .work, .analysis, .analysis], focus: "different")))
                #expect(normalized.reusedCompletedPreparation && normalized.sourceCount == 0)
                let revision = try #require(try await handle.prepareRelatedContent(fixture.request(source: fixture.seed + " Extra context.")))
                #expect(revision.sourceCount > 0 && !revision.reusedCompletedPreparation)
                let scope = try #require(try await handle.prepareRelatedContent(fixture.request(roles: [.topic])))
                #expect(scope.sourceCount == 1 && !scope.reusedCompletedPreparation)
                #expect(await handle.relatedContentCompletedPreparations.count == 2)
                let evicted = try #require(try await handle.prepareRelatedContent(fixture.request()))
                #expect(evicted.sourceCount > 0 && !evicted.reusedCompletedPreparation)
                #expect(await handle.relatedContentCompletedPreparations.count == 2)
            }
        }

        @Test("Running preparation admits at most two independent keys", .timeLimit(.minutes(1)))
        func runningBound() async throws {
            try await withPreparationFixture { fixture in
                let gate = PreparationGate(holdEveryEntry: true)
                await fixture.handle.setRelatedContentPreparationStartedBarrierForTesting { await gate.holdOnce() }
                let first = await fixture.tasks.start(fixture.handle, request: fixture.request())
                let second = await fixture.tasks.start(fixture.handle, request: fixture.request(source: fixture.seed + " Second."))
                try await waitForPreparation { await gate.entries == 2 }
                #expect(await fixture.handle.relatedContentPreparationFlights.count == 2)
                #expect(try await fixture.handle.prepareRelatedContent(fixture.request(source: fixture.seed + " Third.")) == nil)
                #expect(await gate.entries == 2)
                await gate.release()
                #expect(try await first.value?.sourceCount ?? 0 > 0)
                #expect(try await second.value?.sourceCount ?? 0 > 0)
                #expect(await fixture.handle.relatedContentCompletedPreparations.count == 2)
            }
        }

        @Test("Changed or failed refresh cannot complete the earlier source cohort", .timeLimit(.minutes(1)), arguments: [false, true])
        func generationInvalidation(failingRefresh: Bool) async throws {
            try await withPreparationFixture { fixture in
                let handle = fixture.handle
                let generation = try await handle.snapshot().discovery.searchGeneration
                let gate = PreparationGate()
                await handle.setRelatedContentPreparationStartedBarrierForTesting { await gate.holdOnce() }
                let pending = await fixture.tasks.start(handle, request: fixture.request())
                try await waitForPreparation { await gate.entries == 1 }
                let added = fixture.analyses.appendingPathComponent("Added.md")
                if failingRefresh {
                    try Data([0xFF, 0xFE, 0xFA]).write(to: added)
                    await #expect(throws: (any Error).self) { try await handle.discovery.refresh() }
                    #expect(await handle.derivedStateRequiresRefresh)
                } else {
                    try Data("Agency freedom background added.".utf8).write(to: added)
                    let refreshed = try await handle.discovery.refresh()
                    #expect(refreshed.discovery.searchGeneration != generation)
                }
                await gate.release()
                await #expect(throws: CancellationError.self) { try await pending.value }
                #expect(await handle.relatedContentCompletedPreparations.isEmpty)
                if failingRefresh {
                    try FileManager.default.removeItem(at: added)
                    _ = try await handle.discovery.refresh()
                }
                let retry = try #require(try await handle.prepareRelatedContent(fixture.request()))
                #expect(retry.sourceCount > 0 && !retry.reusedCompletedPreparation)
                #expect(await handle.relatedContentCompletedPreparations.count == 1)
            }
        }

        @Test("Unreadable or changed source leaves no completed marker and a repaired source retries", .timeLimit(.minutes(1)), arguments: [false, true])
        func sourceReadFailure(validChangedSource: Bool) async throws {
            try await withPreparationFixture { fixture in
                let handle = fixture.handle
                let gate = PreparationGate()
                await handle.setRelatedContentPreparationStartedBarrierForTesting { await gate.holdOnce() }
                let pending = await fixture.tasks.start(handle, request: fixture.request())
                try await waitForPreparation { await gate.entries == 1 }
                let original = try Data(contentsOf: fixture.target)
                try (validChangedSource ? Data("Changed source bytes without index publication.".utf8) : Data([0xFF, 0xFE, 0xFA]))
                    .write(to: fixture.target)
                await gate.release()
                #expect(try await pending.value == nil)
                #expect(await handle.relatedContentCompletedPreparations.isEmpty)
                try original.write(to: fixture.target)
                let repaired = try #require(try await handle.prepareRelatedContent(fixture.request()))
                #expect(repaired.sourceCount > 0 && !repaired.reusedCompletedPreparation)
            }
        }

        @Test("Shutdown cancels and joins owned preparation before returning", .timeLimit(.minutes(1)))
        func preparationShutdown() async throws {
            try await withPreparationFixture { fixture in
                let handle = fixture.handle
                let gate = PreparationGate()
                await handle.setRelatedContentPreparationStartedBarrierForTesting { await gate.holdOnce() }
                let pending = await fixture.tasks.start(handle, request: fixture.request())
                try await waitForPreparation { await gate.entries == 1 }
                await fixture.runtime.shutdown()
                await #expect { _ = try await pending.value } throws: {
                    guard let error = $0 as? ScholiumApplicationError else { return false }
                    if case .workspaceShutDown(let id) = error { return id == handle.id }
                    return false
                }
                #expect(await gate.exits == 1)
                #expect(await handle.relatedContentPreparationFlights.isEmpty)
                #expect(await handle.relatedContentCompletedPreparations.isEmpty)
                await #expect { _ = try await handle.prepareRelatedContent(fixture.request()) } throws: {
                    guard let error = $0 as? ScholiumApplicationError else { return false }
                    if case .workspaceShutDown(let id) = error { return id == handle.id }
                    return false
                }
            }
        }
    #endif

    @Test("Preparation publishes nothing, preserves cold results and never authorizes stale source")
    func exactSourceAndScope() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/two-layer-retrieval/application-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let analyses = root.appendingPathComponent("analyses")
        let topics = root.appendingPathComponent("topics")
        let works = root.appendingPathComponent("works")
        for directory in [analyses, topics, works] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let seed = "Agency freedom background.\n\nquantum measurement"
        let target = topics.appendingPathComponent("Quantum.md")
        try Data(seed.utf8).write(to: works.appendingPathComponent("Draft.md"))
        for number in 0..<25 {
            try Data("Agency freedom background.".utf8).write(to: analyses.appendingPathComponent("Context-\(number).md"))
        }
        try Data("Quantum measurement concerns a different topic.".utf8).write(to: target)
        let support = root.appendingPathComponent("state")
        let live = WorkspaceRuntime(
            configuration: .live(.init(applicationSupportURL: support, workspaceRegistryStorageURL: root.appendingPathComponent("registry"))))
        let configured = try await live.configureTriptych(
            paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
            portableContainerURL: root, triptychName: "Preparation fixture")
        let assignment = configured.assignment
        await live.shutdown()
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(applicationSupportURL: support, assignments: [assignment])))
        let handle = try await runtime.openWorkspace(id: assignment.id)
        do {
            let vault = try #require(assignment.vault(for: .output)?.id)
            let request = RelatedContentRequest(
                seed: .init(
                    noteID: .init(vaultID: vault, relativePath: "Draft.md"), source: seed,
                    focuses: [.init(kind: .selectedPassage, text: "quantum measurement")]))
            let cold = try await handle.discovery.relatedContent(request)
            #expect(cold.passages.map(\.candidate.note.relativePath) == ["Quantum.md"])
            let before = try await handle.snapshot()
            let measurement = await handle.lastRelatedContentMeasurement?.requestID
            try await handle.discovery.prepareRelatedContent(request)
            let after = try await handle.snapshot()
            #expect(after.generatedAt == before.generatedAt)
            #expect(after.discovery.searchGeneration == before.discovery.searchGeneration)
            #expect(after.discovery.catalog.notes == before.discovery.catalog.notes)
            #expect(await handle.lastRelatedContentMeasurement?.requestID == measurement)
            #expect(try await handle.discovery.relatedContent(request) == cold)
            // The Note's broad background must not force unrelated source I/O
            // for a narrow current-line query, even when all 25 Notes are warm.
            #expect(await handle.lastRelatedContentMeasurement?.sourceCount == 1)

            // A source change that has not reached the disposable index must be
            // caught even after preparation has populated every derived cache.
            try Data("New unrelated source bytes.".utf8).write(to: target)
            let staleSource = try await handle.discovery.relatedContent(request)
            #expect(staleSource.omittedSourceCount > 0)
            #expect(!staleSource.passages.contains { $0.candidate.note.relativePath == "Quantum.md" })
            _ = try await handle.discovery.refresh()
            #expect(try await handle.discovery.relatedContent(request).passages.isEmpty)
            await #expect(throws: (any Error).self) {
                try await handle.discovery.prepareRelatedContent(
                    .init(
                        seed: .init(
                            noteID: .init(vaultID: UUID(), relativePath: "Private.md"), source: seed)))
            }
            let cancelled = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                try await handle.discovery.prepareRelatedContent(request)
            }
            await #expect(throws: CancellationError.self) { try await cancelled.value }
        } catch {
            await runtime.shutdown()
            throw error
        }
        await runtime.shutdown()
        await #expect(throws: (any Error).self) {
            try await handle.discovery.prepareRelatedContent(
                .init(
                    seed: .init(
                        noteID: .init(vaultID: UUID(), relativePath: "Departed.md"), source: seed)))
        }
    }
}

#if DEBUG
    private struct PreparationFixture: Sendable {
        let root: URL
        let analyses: URL
        let target: URL
        let seed: String
        let note: VaultQualifiedNoteID
        let runtime: WorkspaceRuntime
        let handle: WorkspaceHandle
        let tasks = PreparationTestTasks()

        func request(
            source: String? = nil, roles: [RelatedContentCandidateRole] = RelatedContentCandidateRole.allCases,
            focus: String = "quantum measurement"
        ) -> RelatedContentRequest {
            .init(seed: .init(noteID: note, source: source ?? seed, focuses: [.init(kind: .selectedPassage, text: focus)]), candidateRoles: roles)
        }

        static func make() async throws -> Self {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(".build/related-preparation-tests/\(UUID().uuidString)", isDirectory: true)
            let analyses = root.appendingPathComponent("analyses")
            let topics = root.appendingPathComponent("topics")
            let works = root.appendingPathComponent("works")
            let seed = "Agency freedom background.\n\nquantum measurement"
            let target = topics.appendingPathComponent("Quantum.md")
            do {
                for directory in [analyses, topics, works] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
                try Data(seed.utf8).write(to: works.appendingPathComponent("Draft.md"))
                for number in 0..<4 {
                    try Data("Agency freedom background.".utf8).write(to: analyses.appendingPathComponent("Context-\(number).md"))
                }
                try Data("Quantum measurement concerns a different topic.".utf8).write(to: target)
                let support = root.appendingPathComponent("state")
                let live = WorkspaceRuntime(
                    configuration: .live(.init(applicationSupportURL: support, workspaceRegistryStorageURL: root.appendingPathComponent("registry"))))
                let assignment: TriptychAssignment
                do {
                    assignment = try await live.configureTriptych(
                        paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
                        portableContainerURL: root, triptychName: "Preparation fixture"
                    ).assignment
                } catch {
                    await live.shutdown()
                    throw error
                }
                await live.shutdown()
                let runtime = WorkspaceRuntime(configuration: .snapshot(.init(applicationSupportURL: support, assignments: [assignment])))
                do {
                    let handle = try await runtime.openWorkspace(id: assignment.id)
                    let vault = try #require(assignment.vault(for: .output)?.id)
                    return .init(
                        root: root, analyses: analyses, target: target, seed: seed,
                        note: .init(vaultID: vault, relativePath: "Draft.md"), runtime: runtime, handle: handle)
                } catch {
                    await runtime.shutdown()
                    throw error
                }
            } catch {
                try? FileManager.default.removeItem(at: root)
                throw error
            }
        }
    }

    private actor PreparationTestTasks {
        private var tasks: [Task<WorkspaceHandle.RelatedContentPreparationMeasurement?, Error>] = []
        func start(_ handle: WorkspaceHandle, request: RelatedContentRequest) -> Task<WorkspaceHandle.RelatedContentPreparationMeasurement?, Error> {
            let task = Task { try await handle.prepareRelatedContent(request) }
            tasks.append(task)
            return task
        }
        func cancelAndJoin() async {
            for task in tasks { task.cancel() }
            for task in tasks { _ = await task.result }
            tasks.removeAll()
        }
    }

    private actor PreparationGate {
        private let releaseSignal = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        private let holdEveryEntry: Bool
        private(set) var entries = 0
        private(set) var exits = 0
        init(holdEveryEntry: Bool = false) { self.holdEveryEntry = holdEveryEntry }
        func holdOnce() async {
            entries += 1
            defer { exits += 1 }
            guard holdEveryEntry || entries == 1 else { return }
            var iterator = releaseSignal.stream.makeAsyncIterator()
            _ = await iterator.next()
        }
        func release() {
            releaseSignal.continuation.yield(())
            releaseSignal.continuation.finish()
        }
    }

    private func withPreparationFixture(_ body: (PreparationFixture) async throws -> Void) async throws {
        let fixture = try await PreparationFixture.make()
        do { try await body(fixture) } catch {
            await fixture.tasks.cancelAndJoin()
            await fixture.runtime.shutdown()
            try? FileManager.default.removeItem(at: fixture.root)
            throw error
        }
        await fixture.tasks.cancelAndJoin()
        await fixture.runtime.shutdown()
        try? FileManager.default.removeItem(at: fixture.root)
    }

    private func waitForPreparation(_ predicate: @escaping @Sendable () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await predicate()) {
            guard ContinuousClock.now < deadline else {
                Issue.record("Preparation did not reach the explicitly observed phase before its deadline")
                throw CancellationError()
            }
            try Task.checkCancellation()
            await Task.yield()
        }
    }
#endif
