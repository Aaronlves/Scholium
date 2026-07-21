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
    private let lifecyclePolicy: ScholiumLifecyclePolicy
    private let finalSaver: @MainActor (WindowSessionSnapshot) async throws -> Void
    private var saveTask: Task<Void, Never>?
    private(set) var isFinalizing = false

    init(
        lifecyclePolicy: ScholiumLifecyclePolicy,
        finalSaver: @escaping @MainActor (WindowSessionSnapshot) async throws -> Void
    ) {
        self.lifecyclePolicy = lifecyclePolicy
        self.finalSaver = finalSaver
    }

    func schedule(
        snapshot: WindowSessionSnapshot,
        save: @escaping @MainActor (WindowSessionSnapshot) async throws -> Void,
        completion: @escaping @MainActor (Result<Void, Error>) -> Void
    ) {
        guard !isFinalizing else { return }
        saveTask?.cancel()
        saveTask = Task {
            do {
                try await save(snapshot)
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
        do {
            try await withScholiumLifecycleDeadline(
                phase: .presentationSnapshot,
                timeout: lifecyclePolicy.presentationSnapshot
            ) { [finalSaver] in
                _ = await pending?.result
                try await finalSaver(snapshot)
            }
            guard attemptIsCurrent() else { return .superseded }
            return .saved
        } catch {
            guard attemptIsCurrent() else { return .superseded }
            return .failed(error.localizedDescription)
        }
    }
}
