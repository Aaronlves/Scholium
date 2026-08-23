import Foundation
import ScholiumContracts
import ScholiumCore

struct WorkspaceResearchAgentDiscussionDependencies: Sendable {
    let researchAgentSessions: ResearchAgentSessionAuthority?
    let localResearchExecutionStore: LocalResearchExecutionStore
    let portableResearchRecordStore: PortableResearchRecordStore
}

extension WorkspaceServices {
    var researchAgentDiscussionDependencies:
        WorkspaceResearchAgentDiscussionDependencies {
        WorkspaceResearchAgentDiscussionDependencies(
            researchAgentSessions: researchAgentSessions,
            localResearchExecutionStore: localResearchExecutionStore,
            portableResearchRecordStore: portableResearchRecordStore
        )
    }
}

extension WorkspaceRuntime {
    /// Appends one attributed Agent turn to the active Discussion owned by
    /// this authenticated Run. The Session authenticates the Run; it does
    /// not become a general-purpose portable-record or filesystem token.
    public func replyToResearchAgentDiscussion(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        request: ResearchAgentDiscussionReplyRequest
    ) async throws -> ResearchAgentDiscussionReplyReceipt {
        guard let sessions = researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false
        )
        let handle = try await openWorkspace(id: authenticated.triptychID)
        return try await handle.replyToResearchAgentDiscussion(
            credential: credential,
            run: run,
            request: request
        )
    }

    /// Finishes the current authenticated Discuss Run after at least one
    /// durable Agent turn and forms its canonical portable Record.
    public func finishResearchAgentDiscussion(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator
    ) async throws -> ResearchAgentDiscussionFinishReceipt {
        guard let sessions = researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false
        )
        let handle = try await openWorkspace(id: authenticated.triptychID)
        return try await handle.finishResearchAgentDiscussion(
            credential: credential,
            run: run
        )
    }
}

extension WorkspaceHandle {
    func replyToResearchAgentDiscussion(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        request: ResearchAgentDiscussionReplyRequest
    ) async throws -> ResearchAgentDiscussionReplyReceipt {
        try requireActive()
        guard let sessions = researchAgentDiscussionDependencies.researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false
        )
        guard authenticated.triptychID == self.id else {
            throw ResearchAgentSessionError.sessionRejected
        }

        guard let execution = try await researchAgentDiscussionDependencies.localResearchExecutionStore
            .recordIfPresent(id: authenticated.runID),
              execution.triptychID == self.id,
              execution.completion == nil,
              let action = execution.snapshot.actionSnapshot,
              action.actionID == .discuss,
              execution.discussion?.id == authenticated.runID,
              let discussionContract = execution.discussion?.responseContract,
              discussionContract.validationIssues.isEmpty else {
            throw ResearchAgentConnectionError.runUnavailable
        }

        let expected = try ResearchDiscussionFactory.make(
            snapshot: execution.snapshot,
            triptychID: self.id
        )
        let active: PortableResearchDiscussion
        do {
            active = try await researchAgentDiscussionDependencies.portableResearchRecordStore
                .activeDiscussion(id: authenticated.runID)
        } catch ResearchRecordStoreV1Error.discussionNotFound {
            throw ResearchAgentConnectionError.runUnavailable
        }
        guard ResearchDiscussionFactory.activeMatches(active, expected: expected) else {
            throw ResearchFunctionContractError.invalidCompletion(
                "The portable Discussion no longer matches its frozen Discuss Action."
            )
        }

        if let existing = active.statements.first(where: {
            $0.id == request.statementID
        }) {
            let expectedExisting = try PortableResearchStatement(
                id: request.statementID,
                author: .agent,
                kind: .discussionTurn,
                attribution: request.attribution,
                text: request.text,
                createdAt: existing.createdAt
            )
            guard existing == expectedExisting else {
                throw PortableResearchDiscussionError.duplicateStatement(
                    request.statementID
                )
            }
            return try ResearchAgentDiscussionReplyReceipt(
                run: run,
                discussionID: active.id,
                statementID: request.statementID,
                state: .alreadyRecorded,
                message: "The Agent Discussion reply was already recorded."
            )
        }

        let statement = try PortableResearchStatement(
            id: request.statementID,
            author: .agent,
            kind: .discussionTurn,
            attribution: request.attribution,
            text: request.text,
            createdAt: max(Date(), active.updatedAt)
        )
        let stored = try await appendAgentDiscussionStatement(
            statement,
            to: active
        )
        return try ResearchAgentDiscussionReplyReceipt(
            run: run,
            discussionID: stored.id,
            statementID: request.statementID,
            state: .recorded,
            message: "The Agent Discussion reply was recorded."
        )
    }

    func finishResearchAgentDiscussion(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator
    ) async throws -> ResearchAgentDiscussionFinishReceipt {
        try requireActive()
        guard let sessions = researchAgentDiscussionDependencies.researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false
        )
        guard authenticated.triptychID == self.id else {
            throw ResearchAgentSessionError.sessionRejected
        }
        guard let execution = try await researchAgentDiscussionDependencies
            .localResearchExecutionStore.recordIfPresent(id: authenticated.runID),
              execution.triptychID == self.id,
              execution.completion == nil,
              let action = execution.snapshot.actionSnapshot,
              action.actionID == .discuss,
              execution.discussion?.id == authenticated.runID else {
            throw ResearchAgentConnectionError.runUnavailable
        }

        let expected = try ResearchDiscussionFactory.make(
            snapshot: execution.snapshot,
            triptychID: self.id
        )
        let active: PortableResearchDiscussion
        do {
            active = try await researchAgentDiscussionDependencies
                .portableResearchRecordStore.activeDiscussion(id: authenticated.runID)
        } catch ResearchRecordStoreV1Error.discussionNotFound {
            throw ResearchAgentConnectionError.runUnavailable
        }
        guard ResearchDiscussionFactory.activeMatches(active, expected: expected),
              active.statements.contains(where: {
                  $0.author == .agent
                      && $0.createdAt >= execution.snapshot.preparedAt
                      && !$0.attribution.isEmpty
                      && !$0.text.isEmpty
              }) else {
            throw ResearchFunctionContractError.invalidCompletion(
                "Record at least one durable attributed Agent turn before finishing Discuss."
            )
        }

        _ = try await researchFunctionCoordinator.finishProtectedDiscussion(
            runID: authenticated.runID,
            host: self
        )
        return try ResearchAgentDiscussionFinishReceipt(
            run: run,
            discussionID: active.id,
            message: "The Discussion finished and formed one portable Research Record."
        )
    }
}
