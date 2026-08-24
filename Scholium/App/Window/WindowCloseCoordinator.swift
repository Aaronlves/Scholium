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
    typealias ContentFlusher = @MainActor () async throws -> Void
    typealias PresentationSnapshot = @MainActor () -> WindowSessionSnapshot?
    typealias PersistenceFailureHandler = @MainActor (String?) -> Void
    typealias Finalizer = @MainActor () -> Void

    private let lifecyclePolicy: ScholiumLifecyclePolicy
    private let persistenceCoordinator: WindowSessionPersistenceCoordinator
    private let flushContent: ContentFlusher
    private let presentationSnapshot: PresentationSnapshot
    private let recordPersistenceFailure: PersistenceFailureHandler
    private let finalizeDependencies: Finalizer
    private var closeAttemptSequence: UInt64 = 0
    private var currentCloseAttemptID = LifecycleAttemptID(rawValue: 0)
    private var activePreparation: (
        attempt: LifecycleAttemptID,
        task: Task<WindowClosePreparationOutcome, Error>
    )?
    private(set) var isFinalized = false

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
        return try await task.value
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
            try await self.flushContent()
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

    func finalize() {
        guard !isFinalized else { return }
        isFinalized = true
        activePreparation?.task.cancel()
        activePreparation = nil
        persistenceCoordinator.close()
        finalizeDependencies()
    }
}
