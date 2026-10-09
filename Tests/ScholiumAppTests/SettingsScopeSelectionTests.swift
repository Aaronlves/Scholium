import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Settings scope selection", .timeLimit(.minutes(1)))
@MainActor
struct SettingsScopeSelectionTests {
    @Test("A page refresh follows an in-flight Triptych selection and ignores its stale failure")
    func refreshDuringSelectionKeepsRequestedScope() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let original = snapshot(firstID, revision: "first")
        let selected = snapshot(secondID, revision: "second")
        let loader = ControlledSettingsSnapshotLoader()
        defer { loader.cancelPending() }
        var requests = loader.requests.makeAsyncIterator()
        let model = WorkspaceSettingsModel(snapshot: original, loadSnapshot: loader.load)

        let activation = Task { await model.activateTriptych(id: secondID) }
        let activationRequest = try #require(await requests.next())
        #expect(activationRequest.triptychID == secondID)
        #expect(model.selectedTriptychID == secondID)
        #expect(model.snapshot == original)

        let refresh = Task { await model.refresh() }
        let refreshRequest = try #require(await requests.next())
        #expect(refreshRequest.triptychID == secondID)
        loader.finish(refreshRequest, with: .success(selected))
        #expect(await refresh.value)
        loader.finish(activationRequest, with: .failure(ScopeLoadFailure("stale failure")))
        await activation.value

        #expect(model.selectedTriptychID == secondID)
        #expect(model.snapshot == selected)
        #expect(model.errorMessage == nil)
        #expect(!model.isRefreshing)
    }

    @Test("A Triptych selection supersedes a refresh of the previously confirmed scope")
    func selectionSupersedesOlderRefresh() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let original = snapshot(firstID, revision: "first")
        let selected = snapshot(secondID, revision: "second")
        let loader = ControlledSettingsSnapshotLoader()
        defer { loader.cancelPending() }
        var requests = loader.requests.makeAsyncIterator()
        let model = WorkspaceSettingsModel(snapshot: original, loadSnapshot: loader.load)

        let refresh = Task { await model.refresh() }
        let refreshRequest = try #require(await requests.next())
        #expect(refreshRequest.triptychID == firstID)
        let activation = Task { await model.activateTriptych(id: secondID) }
        let activationRequest = try #require(await requests.next())
        #expect(activationRequest.triptychID == secondID)
        loader.finish(activationRequest, with: .success(selected))
        await activation.value
        loader.finish(refreshRequest, with: .success(original))

        #expect(await refresh.value == false)
        #expect(model.selectedTriptychID == secondID)
        #expect(model.snapshot == selected)
        #expect(model.errorMessage == nil)
        #expect(!model.isRefreshing)
    }

    @Test("Consecutive selections and their page refreshes publish only the latest scope")
    func consecutiveSelectionsKeepLatestScope() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let loader = ControlledSettingsSnapshotLoader()
        defer { loader.cancelPending() }
        var requests = loader.requests.makeAsyncIterator()
        let model = WorkspaceSettingsModel(
            snapshot: snapshot(firstID, revision: "first"), loadSnapshot: loader.load)

        let secondActivation = Task { await model.activateTriptych(id: secondID) }
        let secondRequest = try #require(await requests.next())
        let thirdActivation = Task { await model.activateTriptych(id: thirdID) }
        let thirdRequest = try #require(await requests.next())
        let refresh = Task { await model.refresh() }
        let refreshRequest = try #require(await requests.next())
        #expect(secondRequest.triptychID == secondID)
        #expect(thirdRequest.triptychID == thirdID)
        #expect(refreshRequest.triptychID == thirdID)
        let confirmed = snapshot(thirdID, revision: "latest third")
        loader.finish(refreshRequest, with: .success(confirmed))
        #expect(await refresh.value)
        loader.finish(secondRequest, with: .success(snapshot(secondID, revision: "second")))
        await secondActivation.value
        loader.finish(thirdRequest, with: .failure(ScopeLoadFailure("older third failed")))
        await thirdActivation.value

        #expect(model.selectedTriptychID == thirdID)
        #expect(model.snapshot == confirmed)
        #expect(model.errorMessage == nil)
        #expect(!model.isRefreshing)
    }

    @Test("A failed selection preserves the confirmed snapshot and retries the requested target")
    func failedSelectionRetainsSnapshotAndRetryScope() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let original = snapshot(firstID, revision: "confirmed first")
        let loader = ControlledSettingsSnapshotLoader()
        defer { loader.cancelPending() }
        var requests = loader.requests.makeAsyncIterator()
        let model = WorkspaceSettingsModel(snapshot: original, loadSnapshot: loader.load)

        let activation = Task { await model.activateTriptych(id: secondID) }
        let activationRequest = try #require(await requests.next())
        loader.finish(activationRequest, with: .failure(ScopeLoadFailure("second unavailable")))
        await activation.value
        #expect(model.selectedTriptychID == secondID)
        #expect(model.snapshot == original)
        #expect(model.errorMessage == "second unavailable")
        #expect(!model.isRefreshing)

        let refresh = Task { await model.refresh() }
        let refreshRequest = try #require(await requests.next())
        #expect(refreshRequest.triptychID == secondID)
        let confirmed = snapshot(secondID, revision: "confirmed second")
        loader.finish(refreshRequest, with: .success(confirmed))
        #expect(await refresh.value)
        #expect(model.snapshot == confirmed)
        #expect(model.errorMessage == nil)
    }

    @Test("Initial restoration adopts the scope returned by the common snapshot loader")
    func initialRestorationAdoptsResolvedScope() async throws {
        let resolvedID = UUID()
        let loader = ControlledSettingsSnapshotLoader()
        defer { loader.cancelPending() }
        var requests = loader.requests.makeAsyncIterator()
        let model = WorkspaceSettingsModel(loadSnapshot: loader.load)

        let restoration = Task { await model.restorePreferredWorkspaceIfNeeded() }
        let request = try #require(await requests.next())
        #expect(request.triptychID == nil)
        let confirmed = snapshot(resolvedID, revision: "initial")
        loader.finish(request, with: .success(confirmed))
        await restoration.value

        #expect(model.selectedTriptychID == resolvedID)
        #expect(model.snapshot == confirmed)
    }

    @Test("A live activation hint never relabels another Triptych's confirmed settings")
    func activationHintPreservesConfirmedSnapshotOnFailure() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let original = snapshot(firstID, revision: "confirmed first")
        let loader = ControlledSettingsSnapshotLoader()
        defer { loader.cancelPending() }
        var requests = loader.requests.makeAsyncIterator()
        let model = WorkspaceSettingsModel(snapshot: original, loadSnapshot: loader.load)

        let restoration = Task {
            await model.restorePreferredWorkspaceIfNeeded(activeTriptychID: secondID)
        }
        let request = try #require(await requests.next())
        #expect(request.triptychID == secondID)
        #expect(model.selectedTriptychID == secondID)
        #expect(model.snapshot == original)
        loader.finish(request, with: .failure(ScopeLoadFailure("registry unavailable")))
        await restoration.value

        #expect(model.selectedTriptychID == secondID)
        #expect(model.snapshot == original)
        #expect(model.errorMessage == "registry unavailable")
        #expect(!model.isRefreshing)
    }

    private func snapshot(_ id: UUID, revision: String) -> WorkspaceSettingsSnapshot {
        WorkspaceSettingsSnapshot(
            activeTriptychID: id,
            settingsRevision: SettingsRevision(fingerprint: DocumentFingerprint(content: revision)))
    }
}

private struct ScopeLoadFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Each test controls completion at the same loader used by production refresh,
/// activation and restoration; no alternate activation implementation is injected.
@MainActor
private final class ControlledSettingsSnapshotLoader {
    struct Request: Sendable {
        let index: Int
        let triptychID: UUID?
    }

    let requests: AsyncStream<Request>
    private let requestContinuation: AsyncStream<Request>.Continuation
    private var pending: [CheckedContinuation<WorkspaceSettingsSnapshot, any Error>?] = []

    init() {
        (requests, requestContinuation) = AsyncStream.makeStream(of: Request.self)
    }

    func load(_ triptychID: UUID?) async throws -> WorkspaceSettingsSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            let request = Request(index: pending.count, triptychID: triptychID)
            pending.append(continuation)
            requestContinuation.yield(request)
        }
    }

    func finish(_ request: Request, with result: Result<WorkspaceSettingsSnapshot, any Error>) {
        let continuation = pending[request.index]
        pending[request.index] = nil
        continuation?.resume(with: result)
    }

    func cancelPending() {
        for index in pending.indices {
            let continuation = pending[index]
            pending[index] = nil
            continuation?.resume(throwing: CancellationError())
        }
        requestContinuation.finish()
    }
}
