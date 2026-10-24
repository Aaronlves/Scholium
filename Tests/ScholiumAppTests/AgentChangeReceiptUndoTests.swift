import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Agent Change receipt Undo", .serialized)
@MainActor
struct AgentChangeReceiptUndoTests {
    @Test("A committed Undo remains a completion when its receipt refresh fails", arguments: [AgentChangeOperation.update, .move])
    func committedUndoSurvivesReceiptReadFailure(operation: AgentChangeOperation) async throws {
        let change = fixtureChange(operation: operation)
        let session = AgentChangeReceiptSession(changeID: change.id)
        await session.reload { _ in review(change) }
        var restores = 0
        await session.undoChange(
            change,
            undo: { _ in
                restores += 1
                return result(change)
            }, loadReview: { _ in throw ReceiptFailure() })
        #expect(restores == 1)
        #expect(session.undoResult == result(change))
        #expect(session.errorMessage == nil && session.actionErrorMessage == nil)
        #expect(session.refreshWarning != nil && session.review == nil)
        #expect(!session.canUndo && !session.isUndoing && !session.isLoading)
    }

    @Test("A completed Undo cannot be repeated while a stale confirmed receipt remains readable", arguments: [AgentChangeOperation.update, .move])
    func committedUndoRejectsStaleRepeat(operation: AgentChangeOperation) async throws {
        let change = fixtureChange(operation: operation)
        let session = AgentChangeReceiptSession(changeID: change.id)
        await session.reload { _ in review(change) }
        var restores = 0
        let undo: AgentChangeReceiptSession.Undo = { _ in
            restores += 1
            return result(change)
        }
        await session.undoChange(change, undo: undo, loadReview: { _ in review(change) })
        #expect(session.undoResult == result(change))
        #expect(session.review == nil && session.refreshWarning != nil && !session.canUndo)
        await session.undoChange(change, undo: undo, loadReview: { _ in review(change) })
        #expect(restores == 1)
    }

    enum RefreshOutcome: CaseIterable { case success, failure, cancellation }
    @Test("History refresh cannot change committed Undo and retry refresh never repeats source", arguments: RefreshOutcome.allCases)
    func postCommitHistoryRefresh(outcome: RefreshOutcome) async throws {
        let change = fixtureChange()
        let ended = undone(change)
        let session = AgentChangeReceiptSession(changeID: change.id)
        await session.reload { _ in review(change) }
        var restores = 0
        var refreshes = 0
        let refresh: AgentChangeReceiptSession.Refresh = {
            refreshes += 1
            guard refreshes == 1 else { return }
            switch outcome {
            case .success: return
            case .failure: throw ReceiptFailure()
            case .cancellation: throw CancellationError()
            }
        }
        await session.undoChange(
            change,
            undo: { _ in
                restores += 1
                return result(change)
            }, loadReview: { _ in review(ended) }, refreshAfterUndo: refresh)
        #expect(session.undoResult == result(change))
        #expect(session.review?.change == ended && !session.canUndo)
        #expect((session.refreshWarning != nil) == (outcome != .success))
        #expect(session.errorMessage == nil && session.actionErrorMessage == nil)
        await session.reload(using: { _ in review(ended) }, refreshAfterUndo: refresh)
        #expect(restores == 1 && refreshes == 2)
        #expect(session.refreshWarning == nil && session.review?.change == ended)
    }

    @Test("A failed mutation remains a failure and does not run secondary refresh")
    func failedMutationDoesNotClaimCompletion() async throws {
        let change = fixtureChange()
        let session = AgentChangeReceiptSession(changeID: change.id)
        await session.reload { _ in review(change) }
        var refreshes = 0
        await session.undoChange(
            change, undo: { _ in throw ReceiptFailure() },
            loadReview: { _ in
                Issue.record("A failed Undo must not reload as completion")
                return review(change)
            }, refreshAfterUndo: { refreshes += 1 })
        #expect(session.undoResult == nil && session.refreshWarning == nil)
        #expect(session.actionErrorMessage != nil && session.review?.change == change)
        #expect(refreshes == 0 && !session.isUndoing)
        await session.undoChange(change, undo: { _ in result(change) }, loadReview: { _ in review(undone(change)) })
        #expect(session.undoResult == result(change) && session.actionErrorMessage == nil)
    }

    @Test("Cancellation before mutation preserves eligibility without executing or claiming a change")
    func cancellationBeforeMutation() async throws {
        let change = fixtureChange()
        let session = AgentChangeReceiptSession(changeID: change.id)
        await session.reload { _ in review(change) }
        var restores = 0
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            await session.undoChange(
                change,
                undo: { _ in
                    restores += 1
                    return result(change)
                }, loadReview: { _ in review(change) })
        }
        await task.value
        #expect(restores == 0 && session.undoResult == nil && session.canUndo)
        #expect(session.actionErrorMessage == nil && !session.isUndoing)
    }

    @Test("Cancellation after authoritative success retains completion and offers only display refresh")
    func cancellationAfterMutation() async throws {
        let change = fixtureChange()
        let session = AgentChangeReceiptSession(changeID: change.id)
        await session.reload { _ in review(change) }
        let task = Task { @MainActor in
            await session.undoChange(
                change,
                undo: { _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return result(change)
                }, loadReview: { _ in review(undone(change)) })
        }
        await task.value
        #expect(session.undoResult == result(change) && !session.canUndo)
        #expect(session.review == nil && session.refreshWarning != nil)
        #expect(session.errorMessage == nil && session.actionErrorMessage == nil && !session.isLoading)
        await session.reload { _ in review(undone(change)) }
        #expect(session.refreshWarning == nil && session.review?.change.state == .undone)
    }

    @Test("Closing during source work suppresses late presentation without canceling its admitted result")
    func closeDuringMutation() async throws {
        let change = fixtureChange()
        let session = AgentChangeReceiptSession(changeID: change.id)
        let gate = Gate<AgentChangeUndoResult>()
        await session.reload { _ in review(change) }
        var refreshes = 0
        let task = Task { @MainActor in
            await session.undoChange(
                change, undo: { _ in try await gate.read() },
                loadReview: { _ in
                    Issue.record("Closed receipt must not read after source completion")
                    return review(undone(change))
                }, refreshAfterUndo: { refreshes += 1 })
        }
        defer { gate.release(.success(result(change))) }
        try await wait { gate.isPending }
        session.close()
        gate.release(.success(result(change)))
        await task.value
        #expect(refreshes == 0 && session.undoResult == nil && !session.canUndo)
        #expect(!session.isLoading && !session.isUndoing && session.refreshWarning == nil)
    }

    @Test("Closing during secondary refresh cannot publish a late error", arguments: [false, true])
    func closeDuringRefresh(fails: Bool) async throws {
        let change = fixtureChange()
        let session = AgentChangeReceiptSession(changeID: change.id)
        let gate = Gate<Void>()
        await session.reload { _ in review(change) }
        let task = Task { @MainActor in
            await session.undoChange(
                change, undo: { _ in result(change) },
                loadReview: { _ in
                    Issue.record("Closed receipt must not reload")
                    return review(undone(change))
                }, refreshAfterUndo: { try await gate.read() })
        }
        defer { gate.release(.success(())) }
        try await wait { gate.isPending }
        #expect(session.undoResult == result(change))
        session.close()
        gate.release(fails ? .failure(ReceiptFailure()) : .success(()))
        await task.value
        #expect(session.refreshWarning == nil && session.errorMessage == nil)
        #expect(!session.isLoading && !session.isUndoing && !session.canUndo)
    }

    @Test("Superseded receipt reads cannot replace a newer projection or publish a late error", arguments: [false, true])
    func supersededReceiptRead(fails: Bool) async throws {
        let change = fixtureChange()
        let session = AgentChangeReceiptSession(changeID: change.id)
        let gate = Gate<AgentChangeReview>()
        let first = Task { @MainActor in await session.reload { _ in try await gate.read() } }
        defer { gate.release(.success(review(change))) }
        try await wait { gate.isPending }
        let current = AgentChangeReview(change: change, comparison: nil, currentCreatedSource: "New projection", endingRevisionState: .current)
        await session.reload { _ in current }
        gate.release(fails ? .failure(ReceiptFailure()) : .success(review(change)))
        await first.value
        #expect(session.review?.currentCreatedSource == "New projection")
        #expect(session.errorMessage == nil && !session.isLoading)
    }

    enum MismatchedResult: CaseIterable { case change, note, fingerprint }
    @Test("A mismatched Undo response cannot prove completion or enable replay", arguments: MismatchedResult.allCases)
    func mismatchedResultIsNotReplayed(mismatch: MismatchedResult) async throws {
        let change = fixtureChange()
        let session = AgentChangeReceiptSession(changeID: change.id)
        await session.reload { _ in review(change) }
        var restores = 0
        let undo: AgentChangeReceiptSession.Undo = { _ in
            restores += 1
            return .init(
                changeID: mismatch == .change ? UUID() : change.id,
                noteID: mismatch == .note ? UUID() : change.noteID,
                restoredFingerprint: mismatch == .fingerprint ? .init(content: "Other") : change.beforeFingerprint!)
        }
        await session.undoChange(change, undo: undo, loadReview: { _ in review(change) })
        #expect(session.undoResult == nil && session.actionErrorMessage != nil && !session.canUndo)
        await session.reload { _ in review(change) }
        await session.undoChange(change, undo: undo, loadReview: { _ in review(change) })
        #expect(restores == 1 && !session.canUndo)
    }

    private func fixtureChange(operation: AgentChangeOperation = .update) -> AgentChange {
        .init(
            id: UUID(), triptychID: UUID(), operation: operation, noteID: UUID(), role: .topicKnowledge,
            originalRelativePath: "Synthetic.md", finalRelativePath: operation == .move ? "Moved/Synthetic.md" : "Synthetic.md",
            beforeFingerprint: DocumentFingerprint(content: "Before"), afterFingerprint: DocumentFingerprint(content: "After"),
            state: .confirmed, createdAt: Date(), confirmedAt: Date(), undoneAt: nil)
    }

    private func review(_ change: AgentChange) -> AgentChangeReview {
        .init(change: change, comparison: nil, currentCreatedSource: nil, endingRevisionState: .current)
    }

    private func result(_ change: AgentChange) -> AgentChangeUndoResult {
        .init(changeID: change.id, noteID: change.noteID, restoredFingerprint: change.beforeFingerprint!)
    }

    private func undone(_ change: AgentChange) -> AgentChange {
        .init(
            id: change.id, triptychID: change.triptychID, operation: change.operation, noteID: change.noteID, role: change.role,
            originalRelativePath: change.originalRelativePath, finalRelativePath: change.finalRelativePath,
            beforeFingerprint: change.beforeFingerprint, afterFingerprint: change.afterFingerprint,
            state: .undone, createdAt: change.createdAt, confirmedAt: change.confirmedAt, undoneAt: Date())
    }

    private func wait(_ ready: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !ready(), ContinuousClock.now < deadline { await Task.yield() }
        try #require(ready(), "The controlled receipt operation did not reach its suspension boundary")
    }
}

private struct ReceiptFailure: Error, LocalizedError {
    var errorDescription: String? { "Synthetic receipt refresh failed." }
}

@MainActor
private final class Gate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, any Error>?
    var isPending: Bool { continuation != nil }
    func read() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func release(_ result: Result<Value, any Error>) {
        let pending = continuation
        continuation = nil
        pending?.resume(with: result)
    }
}
