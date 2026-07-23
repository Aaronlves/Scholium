import Foundation
import ScholiumContracts

enum WindowSessionFinalPersistenceResult: Equatable {
    case saved
    case failed(String)
    case superseded
}

/// Owns debounced-save task replacement and bounded final persistence. It
/// persists presentation only and therefore cannot authorize window closure.
@MainActor
final class WindowSessionPersistenceCoordinator {
    typealias Saver = @MainActor (
        WindowSessionSnapshot,
        LifecycleAttemptID
    ) async throws -> Void

    private let lifecyclePolicy: ScholiumLifecyclePolicy
    private let finalSaver: Saver
    private var saveTask: Task<Void, Never>?
    private static var processWriteSequence: UInt64 = 0
    private(set) var isFinalizing = false

    init(
        lifecyclePolicy: ScholiumLifecyclePolicy,
        finalSaver: @escaping Saver
    ) {
        self.lifecyclePolicy = lifecyclePolicy
        self.finalSaver = finalSaver
    }

    func schedule(
        snapshot: WindowSessionSnapshot,
        save: @escaping Saver,
        completion: @escaping @MainActor (Result<Void, Error>) -> Void
    ) {
        guard !isFinalizing else { return }
        guard let attempt = nextWriteAttempt() else {
            completion(.failure(ScholiumWindowLifecycleError.failed(
                "Window persistence attempt IDs were exhausted."
            )))
            return
        }
        saveTask?.cancel()
        saveTask = Task {
            do {
                try await save(snapshot, attempt)
                guard !Task.isCancelled else { return }
                completion(.success(()))
            } catch {
                guard !Task.isCancelled else { return }
                completion(.failure(error))
            }
        }
    }

    func finalize(
        snapshot: WindowSessionSnapshot,
        attemptIsCurrent: @escaping @MainActor () -> Bool
    ) async -> WindowSessionFinalPersistenceResult {
        isFinalizing = true
        defer { isFinalizing = false }
        let pending = saveTask
        saveTask = nil
        pending?.cancel()
        guard let writeAttempt = nextWriteAttempt() else {
            return .failed("Window persistence attempt IDs were exhausted.")
        }
        do {
            try await withScholiumLifecycleDeadline(
                phase: .presentationSnapshot,
                timeout: lifecyclePolicy.presentationSnapshot
            ) { [finalSaver] in
                _ = await pending?.result
                try await finalSaver(snapshot, writeAttempt)
            }
            guard attemptIsCurrent() else { return .superseded }
            return .saved
        } catch {
            guard attemptIsCurrent() else { return .superseded }
            return .failed(error.localizedDescription)
        }
    }

    private func nextWriteAttempt() -> LifecycleAttemptID? {
        guard Self.processWriteSequence < UInt64.max else { return nil }
        Self.processWriteSequence += 1
        return LifecycleAttemptID(rawValue: Self.processWriteSequence)
    }
}
