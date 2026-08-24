import Foundation
import ScholiumContracts

enum WindowSessionFinalPersistenceResult: Equatable {
    case saved
    case failed(String)
    case superseded
}

/// Client-owned persistence port for one window's recoverable presentation
/// snapshot. The concrete macOS adapter remains in the composition root.
@MainActor
protocol WindowSessionPersistenceStore: AnyObject {
    func windowSession(id: UUID) async throws -> WindowSessionSnapshot?
    func saveWindowSession(
        _ snapshot: WindowSessionSnapshot,
        attempt: LifecycleAttemptID
    ) async throws
}

extension WorkspaceStore: WindowSessionPersistenceStore {}

/// Owns presentation restore, debounced-save task replacement, and bounded
/// final persistence. It persists presentation only and therefore cannot
/// authorize window closure.
@MainActor
final class WindowSessionPersistenceCoordinator {
    typealias Saver = @MainActor (
        WindowSessionSnapshot,
        LifecycleAttemptID
    ) async throws -> Void

    private let lifecyclePolicy: ScholiumLifecyclePolicy
    private let store: any WindowSessionPersistenceStore
    private let finalSaver: Saver?
    private var saveTask: Task<Void, Never>?
    private static var processWriteSequence: UInt64 = 0
    private var activeFinalizationCount = 0
    private(set) var isClosed = false

    var isFinalizing: Bool { activeFinalizationCount > 0 }

    init(
        store: any WindowSessionPersistenceStore,
        lifecyclePolicy: ScholiumLifecyclePolicy,
        finalSaver: Saver? = nil
    ) {
        self.store = store
        self.lifecyclePolicy = lifecyclePolicy
        self.finalSaver = finalSaver
    }

    func load(id: UUID) async throws -> WindowSessionSnapshot? {
        try await store.windowSession(id: id)
    }

    func schedule(
        snapshot: WindowSessionSnapshot,
        completion: @escaping @MainActor (Result<Void, Error>) -> Void
    ) {
        guard !isFinalizing, !isClosed else { return }
        guard let attempt = nextWriteAttempt() else {
            completion(.failure(ScholiumWindowLifecycleError.failed(
                "Window persistence attempt IDs were exhausted."
            )))
            return
        }
        saveTask?.cancel()
        saveTask = Task { [store] in
            do {
                try await store.saveWindowSession(snapshot, attempt: attempt)
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
        guard !isClosed else { return .superseded }
        activeFinalizationCount += 1
        defer { activeFinalizationCount -= 1 }
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
            ) { [store, finalSaver] in
                _ = await pending?.result
                if let finalSaver {
                    try await finalSaver(snapshot, writeAttempt)
                } else {
                    try await store.saveWindowSession(
                        snapshot,
                        attempt: writeAttempt
                    )
                }
            }
            guard attemptIsCurrent() else { return .superseded }
            return .saved
        } catch {
            guard attemptIsCurrent() else { return .superseded }
            return .failed(error.localizedDescription)
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        saveTask?.cancel()
        saveTask = nil
    }

    private func nextWriteAttempt() -> LifecycleAttemptID? {
        guard Self.processWriteSequence < UInt64.max else { return nil }
        Self.processWriteSequence += 1
        return LifecycleAttemptID(rawValue: Self.processWriteSequence)
    }
}
