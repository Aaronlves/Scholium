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
    /// Atomically retains one attributed Agent turn and finishes the
    /// Discussion owned by this authenticated Run. The Session authenticates
    /// the Run; it does not become a general-purpose portable-record or
    /// filesystem token.
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
            allowFinalized: true,
        )
        let handle = try await openWorkspace(id: authenticated.triptychID)
        return try await handle.replyToResearchAgentDiscussion(
            credential: credential,
            run: run,
            request: request
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
            allowFinalized: true,
        )
        guard authenticated.triptychID == self.id else {
            throw ResearchAgentSessionError.sessionRejected
        }

        guard let execution = try await researchAgentDiscussionDependencies.localResearchExecutionStore
            .recordIfPresent(id: authenticated.runID),
              execution.triptychID == self.id,
              execution.snapshot.actionSnapshot.actionID == .discuss,
              execution.discussion?.id == authenticated.runID,
              let discussionContract = execution.discussion?.responseContract,
              discussionContract.validationIssues.isEmpty else {
            throw ResearchAgentConnectionError.runUnavailable
        }

        let expected = try ResearchDiscussionFactory.make(
            snapshot: execution.snapshot,
            triptychID: self.id
        )
        guard let active = try await researchAgentDiscussionDependencies
            .portableResearchRecordStore.activeDiscussionIfPresent(
                id: authenticated.runID
            ) else {
            let finished = try await researchAgentDiscussionDependencies
                .portableResearchRecordStore.record(id: authenticated.runID)
            guard ResearchDiscussionFactory.finishedMatches(
                finished,
                expected: expected
            ),
            let existing = finished.statements.first(where: {
                $0.id == request.statementID
            }) else {
                throw ResearchAgentConnectionError.runUnavailable
            }
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
                discussionID: finished.id,
                statementID: request.statementID,
                state: .alreadyRecorded,
                message: "The Agent reply was already recorded and the Discussion already formed its Research Record."
            )
        }
        guard ResearchDiscussionFactory.activeMatches(active, expected: expected) else {
            throw ResearchActionRunContractError.invalidCompletion(
                "The portable Discussion no longer matches its frozen Discuss Action."
            )
        }

        let statement: PortableResearchStatement
        if let existing = active.statements.first(where: {
            $0.id == request.statementID
        }) {
            statement = try PortableResearchStatement(
                id: request.statementID,
                author: .agent,
                kind: .discussionTurn,
                attribution: request.attribution,
                text: request.text,
                createdAt: existing.createdAt
            )
            guard statement == existing else {
                throw PortableResearchDiscussionError.duplicateStatement(
                    request.statementID
                )
            }
        } else {
            statement = try PortableResearchStatement(
                id: request.statementID,
                author: .agent,
                kind: .discussionTurn,
                attribution: request.attribution,
                text: request.text,
                createdAt: max(Date(), active.updatedAt)
            )
        }
        let commit = try await researchActionRunCoordinator
            .finishProtectedDiscussion(
                runID: authenticated.runID,
                appendingAgentStatement: statement,
                host: self
            )
        return try ResearchAgentDiscussionReplyReceipt(
            run: run,
            discussionID: commit.record.id,
            statementID: request.statementID,
            state: commit.replyWasAlreadyRecorded ? .alreadyRecorded : .recorded,
            message: commit.replyWasAlreadyRecorded
                ? "The Agent reply was already recorded and the Discussion already formed its Research Record."
                : "The Agent reply was recorded and the Discussion formed its Research Record."
        )
    }
}
