import Foundation
import ScholiumContracts
import ScholiumCore

/// Owns one lazy, fully validated Core index for a Workspace activation.
/// Source-only readiness never starts or waits for generated-state admission.
actor WorkspaceSearchIndexOwner {
    enum AdmissionState: Sendable {
        case pending
        case ready(TriptychSearchIndex)
        case failed(Error)
        case shutDown
    }

    private let factory: @Sendable () async throws -> TriptychSearchIndex
    private var opened: TriptychSearchIndex?
    private var opening: (id: UUID, task: Task<TriptychSearchIndex, Error>)?
    private var failure: Error?
    private var shutdownTask: Task<Void, Never>?
    private var isShutDown = false

    #if DEBUG
        private(set) var resolvingWaiterCountForTesting = 0
        private var resultDeliveryBarrierForTesting: (@Sendable (UUID) async -> Void)?

        func setResultDeliveryBarrierForTesting(_ barrier: (@Sendable (UUID) async -> Void)?) {
            resultDeliveryBarrierForTesting = barrier
        }
    #endif

    init(applicationSupportURL: URL, triptychID: UUID, vaults: [RegisteredVault]) {
        factory = {
            try await TriptychSearchIndex.openRecovering(
                applicationSupportURL: applicationSupportURL,
                triptychID: triptychID, vaults: vaults
            ).index
        }
    }

    init(factory: @escaping @Sendable () async throws -> TriptychSearchIndex) {
        self.factory = factory
    }

    func admissionState() -> AdmissionState {
        if isShutDown { return .shutDown }
        if let opened { return .ready(opened) }
        if let failure { return .failed(failure) }
        return .pending
    }

    func readyIndex() -> TriptychSearchIndex? {
        isShutDown ? nil : opened
    }

    /// Only an explicit recovery request may retry a failed factory. Pending
    /// and successful admission retain the same shared task or Core identity.
    func retryFailedAdmission() throws {
        guard !isShutDown else { throw ScholiumApplicationError.runtimeShutDown }
        try Task.checkCancellation()
        failure = nil
    }

    func resolve() async throws -> TriptychSearchIndex {
        guard !isShutDown else { throw ScholiumApplicationError.runtimeShutDown }
        try Task.checkCancellation()
        if let opened { return opened }
        if let failure { throw failure }
        let admitted: (id: UUID, task: Task<TriptychSearchIndex, Error>)
        if let opening {
            admitted = opening
        } else {
            let factory = factory
            admitted = (UUID(), Task.detached(priority: .utility) { try await factory() })
            opening = admitted
        }
        #if DEBUG
            resolvingWaiterCountForTesting += 1
            defer { resolvingWaiterCountForTesting -= 1 }
        #endif
        let result = await admitted.task.result
        #if DEBUG
            if let resultDeliveryBarrierForTesting {
                await resultDeliveryBarrierForTesting(admitted.id)
            }
        #endif
        // Shutdown captures the task before retiring it, including a successful
        // factory result whose delivery to this waiter was delayed.
        guard !isShutDown else { throw ScholiumApplicationError.runtimeShutDown }
        switch result {
        case .success(let index):
            if opening?.id == admitted.id {
                opened = index
                opening = nil
            }
            // Cancelling a waiter must not cancel or poison shared admission.
            try Task.checkCancellation()
            return index
        case .failure(let error):
            if opening?.id == admitted.id {
                failure = error
                opening = nil
            }
            throw error
        }
    }

    /// Cancels admission before returning a retained drain task. Handle shutdown
    /// starts this before joining refresh producers that may await resolve().
    func beginShutdown() -> Task<Void, Never> {
        if let shutdownTask { return shutdownTask }
        isShutDown = true
        let admitted = opening?.task
        let current = opened
        opening = nil
        opened = nil
        failure = nil
        admitted?.cancel()
        let task = Task {
            if let admitted, case .success(let index) = await admitted.result {
                await index.shutdown()
            }
            if let current { await current.shutdown() }
        }
        shutdownTask = task
        return task
    }

    func shutdown() async {
        await beginShutdown().value
    }
}
