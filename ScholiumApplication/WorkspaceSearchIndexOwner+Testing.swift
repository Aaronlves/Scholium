#if DEBUG
    import Foundation
    import ScholiumContracts
    import ScholiumCore

    /// Keeps real index lifetime/identity checks inside Application's module.
    /// Equality compares the underlying Core actor, never a copied identifier.
    struct WorkspaceSearchIndexTestResource: Sendable, Equatable {
        fileprivate let index: TriptychSearchIndex

        init(applicationSupportURL: URL, triptychID: UUID) throws {
            index = try TriptychSearchIndex(
                applicationSupportURL: applicationSupportURL, triptychID: triptychID)
        }

        fileprivate init(_ index: TriptychSearchIndex) { self.index = index }

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.index === rhs.index }

        func generation() async throws -> SearchGenerationID? {
            try await index.generation()
        }

        func shutdown() async { await index.shutdown() }
    }

    /// Exercises the production admission owner without exposing Core to its
    /// boundary tests. This adapter owns no second admission state or tasks.
    struct WorkspaceSearchIndexOwnerTestProbe: Sendable {
        enum AdmissionState: Sendable {
            case pending
            case ready(WorkspaceSearchIndexTestResource)
            case failed(Error)
            case shutDown
        }

        private let owner: WorkspaceSearchIndexOwner

        init(factory: @escaping @Sendable () async throws -> WorkspaceSearchIndexTestResource) {
            owner = WorkspaceSearchIndexOwner(factory: { (try await factory()).index })
        }

        var resolvingWaiterCountForTesting: Int {
            get async { await owner.resolvingWaiterCountForTesting }
        }

        func setResultDeliveryBarrierForTesting(_ barrier: (@Sendable (UUID) async -> Void)?) async {
            await owner.setResultDeliveryBarrierForTesting(barrier)
        }

        func admissionState() async -> AdmissionState {
            switch await owner.admissionState() {
            case .pending: .pending
            case .ready(let index): .ready(WorkspaceSearchIndexTestResource(index))
            case .failed(let error): .failed(error)
            case .shutDown: .shutDown
            }
        }

        func readyIndex() async -> WorkspaceSearchIndexTestResource? {
            let index = await owner.readyIndex()
            return index.map(WorkspaceSearchIndexTestResource.init)
        }

        func retryFailedAdmission() async throws { try await owner.retryFailedAdmission() }

        func resolve() async throws -> WorkspaceSearchIndexTestResource {
            WorkspaceSearchIndexTestResource(try await owner.resolve())
        }

        func beginShutdown() async -> Task<Void, Never> { await owner.beginShutdown() }

        func shutdown() async { await owner.shutdown() }
    }
#endif
