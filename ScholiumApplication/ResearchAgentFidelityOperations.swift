import Foundation
import ScholiumContracts
import ScholiumCore

extension WorkspaceRuntime {
    public func prepareResearchAgentFidelity(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator
    ) async throws -> ResearchAgentFidelityPreparationReceipt {
        guard let sessions = researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false,
            allowFinalized: true
        )
        let handle = try await openWorkspace(id: authenticated.triptychID)
        return try await handle.prepareResearchAgentFidelity(
            credential: credential,
            run: run
        )
    }
}

extension ResearchOperations {
    public func prepareAgentFidelity(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator
    ) async throws -> ResearchAgentFidelityPreparationReceipt {
        let handle = try await reference.requireHandle()
        return try await handle.prepareResearchAgentFidelity(
            credential: credential,
            run: run
        )
    }
}

extension WorkspaceHandle {
    func prepareResearchAgentFidelity(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator
    ) async throws -> ResearchAgentFidelityPreparationReceipt {
        try requireActive()
        guard let sessions = services.researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false,
            allowFinalized: true
        )
        guard authenticated.triptychID == id else {
            throw ResearchAgentSessionError.sessionRejected
        }
        let parent = try await services.localResearchExecutionStore.record(
            id: authenticated.runID
        )
        guard parent.triptychID == id,
              [.develop, .revise].contains(parent.snapshot.request.function),
              parent.resultPayload != nil,
              let parentCompletion = parent.completion else {
            throw ResearchAgentConnectionError.runUnavailable
        }

        if [.complete, .unverified].contains(parentCompletion.state) {
            guard let childRunID = parentCompletion.childRunIDs?.only,
                  let childCompletion = try await services.localResearchExecutionStore
                    .record(id: childRunID).completion,
                  [.complete, .unverified].contains(childCompletion.state) else {
                throw ResearchAgentConnectionError.runUnavailable
            }
            return try terminalFidelityPreparationReceipt(
                childState: actionRunState(childCompletion.state),
                parentCompletion: parentCompletion
            )
        }
        guard parentCompletion.state == .awaitingFidelity else {
            throw ResearchAgentConnectionError.runUnavailable
        }

        let automatic = try await researchFunctionCoordinator
            .prepareAutomaticFidelity(
                parentRunID: authenticated.runID,
                host: self
            )
        if [.complete, .unverified].contains(automatic.state) {
            let advanced = try await researchFunctionCoordinator.advanceFidelityParent(
                parentRunID: authenticated.runID,
                childRunID: automatic.effectiveFidelityRunID,
                host: self
            )
            return try terminalFidelityPreparationReceipt(
                childState: actionRunState(automatic.state),
                parentCompletion: advanced
            )
        }
        guard automatic.state == .prepared,
              case .automatic(let recordedParentID)? =
                automatic.preparation.snapshot.resolvedFidelityInvocation,
              recordedParentID == authenticated.runID,
              automatic.preparation.snapshot.request.function == .fidelity else {
            throw ResearchAgentConnectionError.runUnavailable
        }

        let childRunID = automatic.preparation.runID
        let locator = try await sessions.attachRun(
            runID: childRunID,
            triptychID: authenticated.triptychID,
            canWrite: false,
            to: credential,
            authorizedBy: run
        )
        return try ResearchAgentFidelityPreparationReceipt(
            childRun: locator,
            childState: .prepared,
            parentState: .awaitingFidelity,
            parentRecordFormed: false,
            message: "The exact final-revision Fidelity child is attached read-only to this authenticated Session. Load its context and submit that child Result; Scholium will link it back to the parent automatically."
        )
    }

    private func terminalFidelityPreparationReceipt(
        childState: ResearchActionRunState,
        parentCompletion: ResearchFunctionCompletion
    ) throws -> ResearchAgentFidelityPreparationReceipt {
        let parentState: ResearchAgentResultFinalizationState = switch parentCompletion.state {
        case .complete: .finalized
        case .unverified: .unverified
        case .awaitingFidelity: .awaitingFidelity
        case .prepared, .stale, .cancelled:
            throw ResearchAgentConnectionError.runUnavailable
        }
        return try ResearchAgentFidelityPreparationReceipt(
            childRun: nil,
            childState: childState,
            parentState: parentState,
            parentRecordFormed: true,
            message: parentState == .unverified
                ? "Existing exact-revision Fidelity evidence formed the parent Research Record with an explicit unverified outcome."
                : "Existing exact-revision Fidelity evidence finalized the parent Research Record."
        )
    }

    private func actionRunState(
        _ state: ResearchFunctionRunState
    ) -> ResearchActionRunState {
        switch state {
        case .prepared: .prepared
        case .awaitingFidelity: .awaitingFidelity
        case .complete: .complete
        case .unverified: .unverified
        case .stale: .stale
        case .cancelled: .cancelled
        }
    }
}

private extension Array {
    var only: Element? { count == 1 ? self[0] : nil }
}
