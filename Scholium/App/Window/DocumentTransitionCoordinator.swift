import Foundation

/// Serializes document-view replacement without becoming another document
/// owner. The newest requested transition wins; preparation always completes
/// before the selected operation can replace the visible target.
@MainActor
final class DocumentTransitionCoordinator {
    private var generation: UInt64 = 0
    private var tail: Task<Void, Never>?

    func enqueue(
        prepare: @escaping @MainActor () async throws -> Void,
        operation: @escaping @MainActor () async throws -> Void,
        didFail: @escaping @MainActor (Error) -> Void,
        didFinish: @escaping @MainActor () -> Void = {}
    ) {
        generation &+= 1
        let requestedGeneration = generation
        let previous = tail
        tail = Task { [weak self] in
            defer { didFinish() }
            _ = await previous?.value
            guard let self, requestedGeneration == generation else { return }
            do {
                try await prepare()
                guard requestedGeneration == generation else { return }
                try await operation()
            } catch is CancellationError {
                return
            } catch {
                didFail(error)
            }
        }
    }

    func invalidate() {
        generation &+= 1
    }

    func waitForIdle() async {
        _ = await tail?.value
    }
}
