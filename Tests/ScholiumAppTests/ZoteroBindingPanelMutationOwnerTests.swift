import Testing
@testable import ScholiumApp

@Suite("Zotero binding panel mutation owner")
@MainActor
struct ZoteroBindingPanelMutationOwnerTests {
    @Test("Window teardown cancels a blocked commit without retry or late state")
    func cancellationDoesNotRecover() async {
        let owner = ZoteroBindingPanelMutationOwner()
        var didStart = false
        var didFinishOperation = false
        var failureCount = 0
        var recoveryCount = 0

        owner.perform(
            operation: {
                didStart = true
                do {
                    try await Task.sleep(for: .seconds(30))
                    didFinishOperation = true
                } catch is CancellationError {
                    throw CancellationError()
                }
            },
            didFail: { _ in failureCount += 1 },
            recover: { recoveryCount += 1 }
        )
        for _ in 0..<100 where !didStart { await Task.yield() }
        #expect(owner.isSaving)

        owner.cancelAll()
        await owner.waitForIdle()

        #expect(!owner.isSaving)
        #expect(!didFinishOperation)
        #expect(failureCount == 0)
        #expect(recoveryCount == 0)
    }
}
