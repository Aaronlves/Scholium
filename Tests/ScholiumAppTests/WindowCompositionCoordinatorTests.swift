import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Window composition coordinators", .serialized)
@MainActor
struct WindowCompositionCoordinatorTests {
    @Test("The newest document transition wins and preserves preparation ordering")
    func newestTransitionWins() async {
        let coordinator = DocumentTransitionCoordinator()
        var events: [String] = []

        coordinator.enqueue(
            prepare: { events.append("obsolete prepare") },
            operation: { events.append("obsolete operation") },
            didFail: { _ in Issue.record("Obsolete transition failed") }
        )
        coordinator.enqueue(
            prepare: { events.append("prepare") },
            operation: { events.append("operation") },
            didFail: { error in Issue.record("Unexpected transition failure: \(error)") }
        )

        await coordinator.waitForIdle()
        #expect(events == ["prepare", "operation"])
    }

    @Test("A superseding presentation save cancels the older completion")
    func presentationSaveReplacement() async {
        let coordinator = WindowSessionPersistenceCoordinator(
            lifecyclePolicy: ScholiumLifecyclePolicy(),
            finalSaver: { _ in }
        )
        var completedIDs: [UUID] = []
        let first = WindowSessionSnapshot(id: UUID())
        let second = WindowSessionSnapshot(id: UUID())

        coordinator.schedule(
            snapshot: first,
            save: { _ in try await Task.sleep(for: .seconds(1)) },
            completion: { _ in completedIDs.append(first.id) }
        )
        coordinator.schedule(
            snapshot: second,
            save: { _ in },
            completion: { result in
                if case .failure(let error) = result {
                    Issue.record("Unexpected persistence failure: \(error)")
                }
                completedIDs.append(second.id)
            }
        )
        for _ in 0..<10 where completedIDs.isEmpty {
            await Task.yield()
        }

        #expect(completedIDs == [second.id])
    }

    @Test("Final presentation persistence is bounded and does not claim content failure")
    func finalPersistenceDeadline() async {
        var policy = ScholiumLifecyclePolicy()
        policy.presentationSnapshot = .milliseconds(20)
        let coordinator = WindowSessionPersistenceCoordinator(
            lifecyclePolicy: policy,
            finalSaver: { _ in
                try await Task.sleep(for: .seconds(10))
            }
        )

        let result = await coordinator.finalize(
            snapshot: WindowSessionSnapshot(),
            attemptIsCurrent: { true }
        )
        guard case .failed(let message) = result else {
            Issue.record("A hanging presentation save did not return a bounded diagnostic")
            return
        }
        #expect(message.contains("timed out"))
        #expect(!coordinator.isFinalizing)
    }
}
