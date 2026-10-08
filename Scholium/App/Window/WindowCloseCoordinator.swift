import Foundation
import ScholiumContracts

struct WindowClosePreparationOutcome: Sendable {
    let presentationWarning: String?
}

/// Owns one native window's close-attempt sequencing and irreversible
/// teardown. Content must be safe before recoverable presentation is saved;
/// dependency shutdown happens only after AppKit commits the close.
@MainActor
final class WindowCloseCoordinator {
    /// Install the acquired input suspension before awaiting any persistence.
    /// The coordinator releases only this attempt's resumption on cancellation.
    typealias ContentFlusher = @MainActor (_ retainSuspension: @escaping @MainActor (@escaping Finalizer) throws -> Void) async throws -> Void
    typealias PresentationSnapshot = @MainActor () -> WindowSessionSnapshot?
    typealias PersistenceFailureHandler = @MainActor (String?) -> Void
    typealias Finalizer = @MainActor () -> Void

    private let lifecyclePolicy: ScholiumLifecyclePolicy
    private let persistenceCoordinator: WindowSessionPersistenceCoordinator
    private let flushContent: ContentFlusher
    private let presentationSnapshot: PresentationSnapshot
    private let recordPersistenceFailure: PersistenceFailureHandler
    private let finalizeDependencies: Finalizer
    private(set) var closeAttemptSequence: UInt64 = 0
    private var currentCloseAttemptID = LifecycleAttemptID(rawValue: 0)
    private var preparedOutcome: WindowClosePreparationOutcome?
    private var resumePreparedContent: Finalizer?
    private var activePreparation:
        (
            attempt: LifecycleAttemptID,
            task: Task<WindowClosePreparationOutcome, Error>
        )?
    private(set) var isFinalized = false
    var isPrepared: Bool { preparedOutcome != nil && !isFinalized }
    var isPreparingOrFinalized: Bool {
        activePreparation != nil || preparedOutcome != nil || isFinalized
    }

    init(
        lifecyclePolicy: ScholiumLifecyclePolicy,
        persistenceCoordinator: WindowSessionPersistenceCoordinator,
        flushContent: @escaping ContentFlusher,
        presentationSnapshot: @escaping PresentationSnapshot,
        recordPersistenceFailure: @escaping PersistenceFailureHandler,
        finalizeDependencies: @escaping Finalizer
    ) {
        self.lifecyclePolicy = lifecyclePolicy
        self.persistenceCoordinator = persistenceCoordinator
        self.flushContent = flushContent
        self.presentationSnapshot = presentationSnapshot
        self.recordPersistenceFailure = recordPersistenceFailure
        self.finalizeDependencies = finalizeDependencies
    }

    func prepare() async throws -> WindowClosePreparationOutcome {
        guard !isFinalized else {
            return WindowClosePreparationOutcome(presentationWarning: nil)
        }
        if let preparedOutcome { return preparedOutcome }
        if let activePreparation {
            return try await activePreparation.task.value
        }
        guard closeAttemptSequence < UInt64.max else {
            throw ScholiumWindowLifecycleError.failed(
                "Window lifecycle attempt IDs were exhausted."
            )
        }
        closeAttemptSequence += 1
        let attempt = LifecycleAttemptID(rawValue: closeAttemptSequence)
        currentCloseAttemptID = attempt
        let task = Task { @MainActor [weak self] in
            guard let self else {
                throw ScholiumWindowLifecycleError.unregisteredBeforeReady
            }
            return try await self.performPreparation(attempt: attempt)
        }
        activePreparation = (attempt, task)
        defer {
            if activePreparation?.attempt == attempt {
                activePreparation = nil
            }
        }
        do {
            let outcome = try await task.value
            guard currentCloseAttemptID == attempt, !isFinalized else {
                throw ScholiumWindowLifecycleError.cancelled
            }
            preparedOutcome = outcome
            return outcome
        } catch {
            if currentCloseAttemptID == attempt { cancelPreparation() }
            throw error
        }
    }

    private func performPreparation(
        attempt: LifecycleAttemptID
    ) async throws -> WindowClosePreparationOutcome {
        try await withScholiumLifecycleDeadline(
            phase: .contentFlush,
            timeout: lifecyclePolicy.contentFlush
        ) { [weak self] in
            guard let self, !self.isFinalized else {
                throw ScholiumWindowLifecycleError.unregisteredBeforeReady
            }
            try await self.flushContent { resume in
                guard attempt == self.currentCloseAttemptID, !self.isFinalized,
                    !Task.isCancelled
                else {
                    resume()
                    throw ScholiumWindowLifecycleError.cancelled
                }
                self.resumePreparedContent = resume
            }
        }
        guard attempt == currentCloseAttemptID, !isFinalized else {
            throw ScholiumWindowLifecycleError.cancelled
        }

        guard let snapshot = presentationSnapshot() else {
            return WindowClosePreparationOutcome(presentationWarning: nil)
        }
        let result = await persistenceCoordinator.finalize(
            snapshot: snapshot,
            attemptIsCurrent: { [weak self] in
                guard let self else { return false }
                return !self.isFinalized
                    && self.currentCloseAttemptID == attempt
            }
        )
        guard attempt == currentCloseAttemptID, !isFinalized else {
            throw ScholiumWindowLifecycleError.cancelled
        }

        switch result {
        case .saved:
            recordPersistenceFailure(nil)
            return WindowClosePreparationOutcome(presentationWarning: nil)
        case .failed(let message):
            recordPersistenceFailure(message)
            return WindowClosePreparationOutcome(presentationWarning: message)
        case .superseded:
            throw ScholiumWindowLifecycleError.cancelled
        }
    }

    /// A refused native close or cancelled application termination restores
    /// only the input suspension acquired by this attempt. Late completion
    /// cannot prepare a window after cancellation or release a newer attempt.
    func cancelPreparation() {
        guard !isFinalized else { return }
        currentCloseAttemptID = LifecycleAttemptID(rawValue: 0)
        activePreparation?.task.cancel()
        activePreparation = nil
        preparedOutcome = nil
        let resume = resumePreparedContent
        resumePreparedContent = nil
        resume?()
    }

    func finalize() {
        guard !isFinalized else { return }
        isFinalized = true
        activePreparation?.task.cancel()
        activePreparation = nil
        preparedOutcome = nil
        resumePreparedContent = nil
        persistenceCoordinator.close()
        finalizeDependencies()
    }
}
