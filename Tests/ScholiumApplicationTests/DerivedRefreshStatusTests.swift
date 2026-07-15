import ScholiumContracts
import Foundation
import Testing
@testable import ScholiumApplication

@Suite("Derived refresh status")
struct DerivedRefreshStatusTests {
    @Test("Live rebuild failure is typed and a successful retry clears it")
    func liveFailureThenCurrent() async throws {
        let fixture = try await ApplicationFixture.make(registerLiveAccess: true)
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL,
            refreshInterval: .milliseconds(20)
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let stream = await handle.events.events()
        var iterator = stream.makeAsyncIterator()
        _ = try #require(await iterator.next())
        let topicVaultID = try #require(
            fixture.assignment.vault(for: .topicKnowledge)?.id
        )

        let invalidURL = fixture.topicsURL.appendingPathComponent("Invalid UTF-8.md")
        try Data([0xFF, 0xFE, 0xFD]).write(to: invalidURL, options: .atomic)
        for _ in 0..<120 where await handle.events.publishedGeneration < 1 {
            try await Task.sleep(for: .milliseconds(25))
        }
        guard await handle.events.publishedGeneration >= 1 else {
            Issue.record("The native watcher did not report the failed rebuild.")
            await runtime.shutdown()
            return
        }
        let failed = try #require(await iterator.next())
        guard case .derivedStateChanged(let event) = failed,
              case .failed(let issue) = event.status else {
            Issue.record("A live rebuild failure was published as current state.")
            await runtime.shutdown()
            return
        }
        #expect(issue.affectedVaultIDs == [topicVaultID])
        #expect(!issue.reason.isEmpty)

        try FileManager.default.removeItem(at: invalidURL)
        _ = try await handle.discovery.refresh()
        let current = try #require(await iterator.next())
        guard case .current(let evidence) = current.derivedRefreshStatus else {
            Issue.record("The successful live retry did not clear failed state.")
            await runtime.shutdown()
            return
        }
        #expect(evidence == WorkspaceDerivedRefreshEvidence(snapshot: current.snapshot))
        await runtime.shutdown()
    }

    @Test("A failed rebuild retains evidence and a later success clears it")
    func failedRebuildThenCurrent() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let stream = await handle.events.events()
        var iterator = stream.makeAsyncIterator()
        let initial = try #require(await iterator.next())

        let invalidURL = fixture.topicsURL.appendingPathComponent("Invalid UTF-8.md")
        try Data([0xFF, 0xFE, 0xFD]).write(to: invalidURL)
        do {
            _ = try await handle.discovery.refresh()
            Issue.record("An invalid source unexpectedly produced a current projection.")
        } catch {
            // Expected: source bytes remain authoritative and the prior
            // complete projection remains readable.
        }

        let failed = try #require(await iterator.next())
        #expect(failed.generation == initial.generation + 1)
        guard case .derivedStateChanged(let event) = failed,
              case .failed(let issue) = event.status else {
            Issue.record("A failed rebuild was not published as failed derived state.")
            await runtime.shutdown()
            return
        }
        #expect(!issue.reason.isEmpty)
        #expect(issue.lastKnownGood == WorkspaceDerivedRefreshEvidence(snapshot: initial.snapshot))
        #expect(event.snapshot.generatedAt == initial.snapshot.generatedAt)
        #expect(event.discovery.indexGenerations == initial.snapshot.discovery.indexGenerations)

        try FileManager.default.removeItem(at: invalidURL)
        let refreshed = try await handle.discovery.refresh()
        let current = try #require(await iterator.next())
        #expect(current.generation == failed.generation + 1)
        guard case .derivedStateChanged(let event) = current,
              case .current(let evidence) = event.status else {
            Issue.record("A successful retry did not clear the failed derived status.")
            await runtime.shutdown()
            return
        }
        #expect(evidence == WorkspaceDerivedRefreshEvidence(snapshot: refreshed))
        #expect(event.snapshot.generatedAt == refreshed.generatedAt)
        await runtime.shutdown()
    }

    @Test("A committed source mutation publishes stale state and must not be retried")
    func committedMutationIsNotRetried() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let original = try await handle.documents.load(fixture.analysisNoteID)
        let stream = await handle.events.events()
        var iterator = stream.makeAsyncIterator()
        let initial = try #require(await iterator.next())

        let invalidURL = fixture.topicsURL.appendingPathComponent("Invalid UTF-8.md")
        try Data([0xFF, 0xFE, 0xFD]).write(to: invalidURL)
        let applicationError: ScholiumApplicationError
        do {
            _ = try await handle.documents.save(
                fixture.analysisNoteID,
                changeSet: .body("Committed exactly once.\n"),
                expectedRevision: original.fingerprint
            )
            Issue.record("The committed save unexpectedly refreshed its projection.")
            await runtime.shutdown()
            return
        } catch let error as ScholiumApplicationError {
            applicationError = error
        }

        guard case .committedButRefreshFailed(let committedRevision, _) = applicationError else {
            Issue.record("The post-commit refresh failure lost its committed outcome.")
            await runtime.shutdown()
            return
        }
        #expect(applicationError.durableMutationWasCommitted)
        #expect(applicationError.mustNotRetryMutation)
        #expect(applicationError.committedDocumentRevision == committedRevision)
        #expect(applicationError.refreshFailureReason?.isEmpty == false)

        let stale = try #require(await iterator.next())
        #expect(stale.generation == initial.generation + 1)
        guard case .derivedStateChanged(let event) = stale,
              case .stale(let issue) = event.status else {
            Issue.record("A committed mutation with a failed refresh was not marked stale.")
            await runtime.shutdown()
            return
        }
        #expect(issue.affectedVaultIDs == [fixture.analysisNoteID.vaultID])
        #expect(issue.lastKnownGood == WorkspaceDerivedRefreshEvidence(snapshot: initial.snapshot))
        #expect(event.snapshot.document(id: fixture.analysisNoteID)?.fingerprint == original.fingerprint)

        // Read the authority directly through DocumentOperations. The new
        // revision is durable even though the last complete projection is old;
        // a caller must refresh, never replay the save.
        let committed = try await handle.documents.load(fixture.analysisNoteID)
        #expect(committed.fingerprint == committedRevision)
        #expect(committed.rawContent.contains("Committed exactly once."))

        try FileManager.default.removeItem(at: invalidURL)
        let recovered = try await handle.discovery.refresh()
        let recoveryEvent = try #require(await iterator.next())
        #expect(recoveryEvent.generation == stale.generation + 1)
        guard case .current(let evidence) = recoveryEvent.derivedRefreshStatus else {
            Issue.record("A successful refresh did not clear stale derived state.")
            await runtime.shutdown()
            return
        }
        #expect(evidence == WorkspaceDerivedRefreshEvidence(snapshot: recovered))
        #expect(recoveryEvent.snapshot.document(id: fixture.analysisNoteID)?.fingerprint == committedRevision)
        await runtime.shutdown()
    }
}
