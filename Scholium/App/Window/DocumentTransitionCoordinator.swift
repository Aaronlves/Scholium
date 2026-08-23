import Foundation

/// Serializes document-view replacement without becoming another document
/// owner. The newest requested transition wins; preparation always completes
/// before the selected operation can replace the visible target.
@MainActor
final class DocumentTransitionCoordinator {
    typealias Currency = @MainActor () -> Bool
    private var generation: UInt64 = 0
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var tailID: UUID?
    private var tail: Task<Void, Never>?

    func enqueue(
        prepare: @escaping @MainActor () async throws -> Void,
        operation: @escaping @MainActor () async throws -> Void,
        didFail: @escaping @MainActor (Error) -> Void,
        didSucceed: @escaping @MainActor () -> Void = {},
        didFinish: @escaping @MainActor () -> Void = {}
    ) {
        enqueueCurrencyAware(
            prepare: prepare,
            operation: { _ in try await operation() },
            didFail: didFail,
            didSucceed: didSucceed,
            didFinish: didFinish
        )
    }

    func enqueueCurrencyAware(
        prepare: @escaping @MainActor () async throws -> Void,
        operation: @escaping @MainActor (Currency) async throws -> Void,
        didFail: @escaping @MainActor (Error) -> Void,
        didSucceed: @escaping @MainActor () -> Void = {},
        didFinish: @escaping @MainActor () -> Void = {}
    ) {
        generation &+= 1
        let requestedGeneration = generation
        let previous = tail
        let taskID = UUID()
        let task = Task { [weak self] in
            defer {
                didFinish()
                self?.taskDidFinish(taskID)
            }
            do {
                _ = await previous?.value
                try Task.checkCancellation()
                guard let self, requestedGeneration == generation else { return }
                try await prepare()
                try Task.checkCancellation()
                guard requestedGeneration == generation else { return }
                let isCurrent: Currency = { [weak self] in
                    self?.generation == requestedGeneration
                }
                try await operation(isCurrent)
                try Task.checkCancellation()
                guard requestedGeneration == generation else { return }
                didSucceed()
            } catch is CancellationError {
                return
            } catch {
                didFail(error)
            }
        }
        tasks[taskID] = task
        tailID = taskID
        tail = task
    }

    func cancelAll() {
        generation &+= 1
        tasks.values.forEach { $0.cancel() }
    }

    func waitForIdle() async {
        while !tasks.isEmpty {
            let outstanding = Array(tasks.values)
            for task in outstanding {
                _ = await task.value
            }
        }
    }

    private func taskDidFinish(_ taskID: UUID) {
        tasks[taskID] = nil
        guard tailID == taskID else { return }
        tailID = nil
        tail = nil
    }
}
